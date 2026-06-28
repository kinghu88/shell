#!/bin/bash
set -euo pipefail

# ==================== 颜色定义 ====================
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' PURPLE='' CYAN='' WHITE='' NC=''
fi

log_info()    { echo -e "${BLUE}[INFO]${NC}    $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE:-/dev/null}"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE:-/dev/null}"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE:-/dev/null}"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE:-/dev/null}" >&2; }
log_step()    { echo -e "${PURPLE}▶${NC} ${CYAN}$*${NC}" | tee -a "${LOG_FILE:-/dev/null}"; }
log_debug()   { [[ "${DEBUG:-false}" == "true" ]] && echo -e "${WHITE}[DEBUG]${NC}   $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE:-/dev/null}"; }

print_separator() {
    echo -e "${WHITE}========================================${NC}" | tee -a "${LOG_FILE:-/dev/null}"
}

# ==================== 配置变量 ====================
K8S_VERSION="1.21.11"
DOCKER_VERSION="20.10.17"
MARKER_DIR="/var/lib/k8s-install"
MARKER_FILE="${MARKER_DIR}/installed"

LOG_DIR="/var/log/k8s-install"
LOG_FILE="${LOG_DIR}/uninstall-$(date '+%Y%m%d-%H%M%S').log"

IMAGES=(
    "docker.io/prom/node-exporter:v1.3.1"
    "docker.io/kubesphere/kube-rbac-proxy:v0.11.0"
    "docker.io/calico/node:v3.22.2"
    "docker.io/calico/cni:v3.22.2"
    "docker.io/calico/pod2daemon-flexvol:v3.22.2"
)

# ==================== 工具函数 ====================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限执行"
        exit 1
    fi
}

is_installed() {
    [[ -f "${MARKER_FILE}" ]]
}

# 执行命令并记录日志
run_cmd() {
    local desc="$1"
    shift
    log_debug "执行: $*"
    if "$@" >> "${LOG_FILE}" 2>&1; then
        return 0
    else
        local rc=$?
        log_warning "${desc} (退出码: ${rc})"
        return $rc
    fi
}

# ==================== 卸载步骤 ====================
stop_services() {
    log_step "步骤 1/6: 停止服务..."

    local svc
    for svc in kubelet docker containerd; do
        if systemctl is-active --quiet "${svc}" 2>/dev/null; then
            if systemctl disable --now "${svc}" >> "${LOG_FILE}" 2>&1; then
                log_info "${svc} 已停止"
            else
                log_warning "${svc} 停止失败"
            fi
        else
            log_info "${svc} 未运行"
        fi
    done

    log_success "服务已停止"
    print_separator
}

reset_kubeadm() {
    log_step "步骤 2/6: kubeadm reset..."

    if ! command -v kubeadm >/dev/null 2>&1; then
        log_warning "kubeadm 未安装，跳过"
        print_separator
        return 0
    fi

    if [[ ! -f /etc/kubernetes/kubelet.conf ]] && [[ ! -f /etc/kubernetes/admin.conf ]]; then
        log_info "节点未加入集群（无 /etc/kubernetes/{kubelet,admin}.conf），跳过"
        print_separator
        return 0
    fi

    log_info "执行 kubeadm reset --force..."
    if kubeadm reset --force >> "${LOG_FILE}" 2>&1; then
        log_success "kubeadm reset 完成"
    else
        log_warning "kubeadm reset 失败，查看日志: ${LOG_FILE}，继续后续清理"
    fi
    print_separator
}

remove_packages() {
    log_step "步骤 3/6: 卸载软件包..."

    log_info "取消版本锁定..."
    apt-mark unhold kubelet kubeadm kubectl docker-ce >> "${LOG_FILE}" 2>&1 || true

    log_info "卸载 Kubernetes 组件..."
    if apt-get purge -y kubelet kubeadm kubectl >> "${LOG_FILE}" 2>&1; then
        log_success "Kubernetes 组件已卸载"
    else
        log_warning "Kubernetes 组件卸载失败（可能未安装）"
    fi

    log_info "卸载 Docker 组件..."
    if apt-get purge -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin >> "${LOG_FILE}" 2>&1; then
        log_success "Docker 组件已卸载"
    else
        log_warning "Docker 组件卸载失败（可能未安装）"
    fi

    log_info "清理无用依赖..."
    apt-get autoremove -y >> "${LOG_FILE}" 2>&1 || true

    log_success "软件包已卸载"
    print_separator
}

remove_sources() {
    log_step "步骤 4/6: 清理 APT 源与配置..."

    if [[ -f /etc/apt/sources.list.d/kubernetes.list ]]; then
        rm -f /etc/apt/sources.list.d/kubernetes.list
        log_info "已删除 /etc/apt/sources.list.d/kubernetes.list"
    fi

    if [[ -f /etc/apt/sources.list.d/docker.list ]]; then
        rm -f /etc/apt/sources.list.d/docker.list
        log_info "已删除 /etc/apt/sources.list.d/docker.list"
    fi

    # 新版 keyring 路径
    rm -f /etc/apt/keyrings/docker.asc /etc/apt/keyrings/docker.gpg 2>/dev/null || true
    rm -f /etc/apt/keyrings/kubernetes-archive-keyring.gpg 2>/dev/null || true

    if [[ -d /etc/docker ]]; then
        rm -rf /etc/docker
        log_info "已删除 /etc/docker"
    fi

    # 删除源后刷新 APT 缓存
    log_info "刷新 APT 缓存..."
    apt-get update >> "${LOG_FILE}" 2>&1 || true

    log_success "APT 源与配置已清理"
    print_separator
}

restore_system() {
    log_step "步骤 5/6: 恢复系统状态..."

    if [[ -f /etc/sysctl.d/k8s.conf ]]; then
        rm -f /etc/sysctl.d/k8s.conf
        log_info "已删除 /etc/sysctl.d/k8s.conf"
    fi

    if [[ -f /etc/modules-load.d/k8s.conf ]]; then
        rm -f /etc/modules-load.d/k8s.conf
        log_info "已删除 /etc/modules-load.d/k8s.conf"
    fi

    log_info "重新加载 sysctl..."
    sysctl --system >> "${LOG_FILE}" 2>&1 || true

    # 恢复 swap
    if ! swapon --show 2>/dev/null | grep -q .; then
        # 检查 blkid 是否可用
        if ! command -v blkid >/dev/null 2>&1; then
            log_warning "blkid 未安装，无法自动探测 swap 分区"
            log_warning "请手动恢复 swap: swapon -a 或编辑 /etc/fstab"
        else
            local swap_part
            swap_part=$(blkid -t TYPE=swap -o device 2>/dev/null | head -1 || true)
            if [[ -n "${swap_part}" ]]; then
                if ! grep -qE "^${swap_part}[[:space:]].*swap" /etc/fstab 2>/dev/null; then
                    echo "${swap_part} none swap sw 0 0" >> /etc/fstab
                    log_info "已重新写入 /etc/fstab: ${swap_part}"
                fi
                if swapon "${swap_part}" >> "${LOG_FILE}" 2>&1; then
                    log_info "swap 已重新启用: ${swap_part}"
                else
                    log_warning "swap 启用失败: ${swap_part}"
                fi
            else
                log_warning "未检测到 swap 分区，跳过"
            fi
        fi
    else
        log_info "swap 已处于启用状态"
    fi

    log_success "系统状态已恢复"
    print_separator
}

cleanup_marker() {
    log_step "步骤 6/6: 清理安装标记..."

    if [[ -d "${MARKER_DIR}" ]]; then
        rm -rf "${MARKER_DIR}"
        log_info "已删除 ${MARKER_DIR}"
    fi

    log_success "卸载完成"
    print_separator
}

# ==================== 可选：清理运行时数据（--purge）====================
purge_data() {
    log_step "额外步骤: 清理运行时数据（--purge）..."

    # 先清理镜像（此时 Docker 可能还在运行，或已卸载）
    if command -v docker >/dev/null 2>&1 && docker info &>/dev/null 2>&1; then
        log_info "删除安装脚本预拉的镜像..."
        for img in "${IMAGES[@]}"; do
            if docker image inspect "$img" >/dev/null 2>&1; then
                docker rmi -f "$img" >> "${LOG_FILE}" 2>&1 || true
                log_info "  - $img"
            fi
        done

        log_info "清理悬空镜像..."
        docker image prune -f >> "${LOG_FILE}" 2>&1 || true
    else
        log_info "Docker 不可用，跳过镜像清理"
    fi

    local data_dirs=(
        /var/lib/kubelet
        /var/lib/docker
        /var/lib/containerd
        /var/lib/etcd
        /etc/cni/net.d
        /etc/kubernetes
        /var/run/kubernetes
    )
    for d in "${data_dirs[@]}"; do
        if [[ -d "$d" ]]; then
            rm -rf "$d"
            log_info "已删除 $d"
        fi
    done

    if [[ -d /root/.kube ]]; then
        rm -rf /root/.kube
        log_info "已删除 /root/.kube"
    fi

    # 清理 k8s/calico 的 iptables 链（同时清理 ip6tables）
    local ipt_bin
    for ipt_bin in iptables ip6tables; do
        if ! command -v "${ipt_bin}" >/dev/null 2>&1; then
            continue
        fi
        log_info "清理 ${ipt_bin} k8s/calico 链..."
        local removed=0
        for table in filter nat mangle; do
            local chains
            chains=$("${ipt_bin}" -t "$table" -L -n 2>/dev/null \
                | awk '/^Chain/ {print $2}' \
                | grep -E '^(KUBE|CALICO|CNI)' || true)
            for chain in $chains; do
                "${ipt_bin}" -t "$table" -F "$chain" >> "${LOG_FILE}" 2>&1 || true
                "${ipt_bin}" -t "$table" -X "$chain" >> "${LOG_FILE}" 2>&1 || true
                removed=$((removed + 1))
            done
        done
        if [[ $removed -gt 0 ]]; then
            log_info "${ipt_bin}: 已删除 ${removed} 条链"
        fi
    done

    log_success "运行时数据已清理"
    print_separator
}

# ==================== 显示帮助信息 ====================
show_help() {
    echo -e "${CYAN}Kubernetes 节点卸载脚本 v2${NC}

${YELLOW}用法:${NC}
  k8s-uninstall.sh [选项]

${YELLOW}选项:${NC}
  -h, --help     显示此帮助信息
  -f, --force    跳过确认提示
  -p, --purge    同时清理运行时数据（不可恢复）
  -d, --debug    启用调试模式（set -x + 详细日志）

${YELLOW}默认行为:${NC}
  • 停止 kubelet / docker / containerd 服务
  • 若节点已加入集群，执行 kubeadm reset --force
  • 卸载 kubelet / kubeadm / kubectl / docker-ce / containerd.io
  • 清理 APT 源与 docker 配置
  • 恢复 swap、删除 sysctl 与 modules-load 配置
  • 删除安装标记文件

${YELLOW}--purge 额外清理:${NC}
  • 删除 /var/lib/kubelet、/var/lib/docker 等数据目录
  • 删除 /etc/kubernetes、/root/.kube 等集群配置
  • 清理 k8s/calico 相关的 iptables/ip6tables 链
  • 删除安装脚本预拉的镜像

${YELLOW}日志:${NC}
  卸载日志保存在: ${LOG_DIR}/

${YELLOW}示例:${NC}
  sudo k8s-uninstall.sh                   # 普通卸载（保留数据）
  sudo k8s-uninstall.sh --force           # 强制卸载（无确认）
  sudo k8s-uninstall.sh --purge           # 完全清理（含数据）
  sudo k8s-uninstall.sh --purge --debug   # 完全清理 + 调试模式"
}

# ==================== 主函数 ====================
main() {
    local force=false
    local purge=false
    DEBUG=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--force)
                force=true
                ;;
            -p|--purge)
                purge=true
                ;;
            -d|--debug)
                DEBUG=true
                ;;
            *)
                log_error "未知选项: $1"
                echo "使用 -h 或 --help 查看帮助"
                exit 1
                ;;
        esac
        shift
    done

    # 初始化日志
    mkdir -p "${LOG_DIR}"
    echo "===== Kubernetes 卸载日志 $(date) =====" > "${LOG_FILE}"

    if $DEBUG; then
        set -x
        export PS4='+ ${BASH_SOURCE:-}:${LINENO}: '
    fi

    check_root

    if ! is_installed; then
        if $force; then
            log_warning "未检测到安装标记（${MARKER_FILE}），将按 --force 继续"
        else
            log_warning "未检测到安装标记（${MARKER_FILE}）"
            echo "如确需清理，请使用 --force"
            exit 0
        fi
    fi

    if ! $force; then
        echo -e "${YELLOW}⚠️  即将卸载 Kubernetes (${K8S_VERSION}) 与 Docker (${DOCKER_VERSION})${NC}"
        if $purge; then
            echo -e "${RED}   --purge 已开启：会同时删除 /var/lib/kubelet、/etc/kubernetes 等所有数据，不可恢复${NC}"
        else
            echo -e "${YELLOW}   提示: 加上 --purge 可同时删除运行时数据${NC}"
        fi
        read -p "$(echo -e "${WHITE}确认继续？[y/N] ${NC}")" -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "已取消"
            exit 0
        fi
    fi

    print_separator
    log_info "开始卸载 Kubernetes 节点..."
    log_info "Kubernetes 版本: ${K8S_VERSION}"
    log_info "Docker 版本: ${DOCKER_VERSION}"
    log_info "日志文件: ${LOG_FILE}"
    print_separator

    # --purge 时先清理镜像（在卸载 Docker 之前），再卸载软件包
    if $purge; then
        purge_data
    fi

    stop_services
    reset_kubeadm
    remove_packages
    remove_sources
    restore_system
    cleanup_marker

    print_separator
    echo -e "${GREEN}✅ 卸载完成!${NC}"
    if ! $purge; then
        echo -e "${YELLOW}提示: 使用 --purge 可清理运行时数据（不可恢复）${NC}"
    fi
    echo -e "${WHITE}日志文件: ${LOG_FILE}${NC}"
    print_separator
}

main "$@"
