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

print_banner() {
    echo -e "${GREEN}"
    echo "  ██╗  ██╗ █████╗ ███████╗    ██╗  ██╗██╗██╗   ██╗██╗   ██╗███╗   ██╗"
    echo "  ██║ ██╔╝██╔══██╗██╔════╝    ╚██╗██╔╝██║╚██╗ ██╔╝██║   ██║████╗  ██║"
    echo "  █████╔╝ ╚█████╔╝███████╗     ╚███╔╝ ██║ ╚████╔╝ ██║   ██║██╔██╗ ██║"
    echo "  ██╔═██╗ ██╔══██╗╚════██║     ██╔██╗ ██║  ╚██╔╝  ██║   ██║██║╚██╗██║"
    echo "  ██║  ██╗╚█████╔╝███████║    ██╔╝ ██╗██║   ██║   ╚██████╔╝██║ ╚████║"
    echo "  ╚═╝  ╚═╝ ╚════╝ ╚══════╝    ╚═╝  ╚═╝╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═══╝"
    echo -e "${NC}"
}

# ==================== 配置变量 ====================
K8S_VERSION="1.21.0"
DOCKER_VERSION="20.10.12-0ubuntu4"
K8S_APT_MIRROR="https://repo.huaweicloud.com/kubernetes/apt"
REGISTRY_MIRROR="https://adw6g9fr.mirror.aliyuncs.com"
IMAGE_REGISTRY="harbor.nosugar.tech"
CALICO_VERSION="3.18.1"

LOG_DIR="/var/log/k8s-install"
LOG_FILE="${LOG_DIR}/install-xiyun-$(date '+%Y%m%d-%H%M%S').log"

declare -A IMAGES=(
    ["${IMAGE_REGISTRY}/library/node-exporter:v1.3.1"]="prom/node-exporter:v1.3.1"
    ["${IMAGE_REGISTRY}/kubesphere/kube-rbac-proxy:v0.11.0"]="kubesphere/kube-rbac-proxy:v0.11.0"
    ["${IMAGE_REGISTRY}/library/cni:v${CALICO_VERSION}"]="calico/cni:v${CALICO_VERSION}"
    ["${IMAGE_REGISTRY}/library/pod2daemon-flexvol:v${CALICO_VERSION}"]="calico/pod2daemon-flexvol:v${CALICO_VERSION}"
    ["${IMAGE_REGISTRY}/library/node:v${CALICO_VERSION}"]="calico/node:v${CALICO_VERSION}"
)

MARKER_DIR="/var/lib/k8s-install"
MARKER_FILE="${MARKER_DIR}/installed-xiyun"

# ==================== 工具函数 ====================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限执行"
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "无法识别操作系统（缺少 /etc/os-release）"
        exit 1
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]] && [[ "${ID:-}" != "debian" ]]; then
        log_error "此脚本仅支持 Ubuntu/Debian，当前系统: ${PRETTY_NAME:-unknown}"
        exit 1
    fi
    log_info "系统: ${PRETTY_NAME:-unknown}"
}

is_installed() {
    [[ -f "${MARKER_FILE}" ]]
}

mark_installed() {
    mkdir -p "${MARKER_DIR}"
    cat > "${MARKER_FILE}" <<EOF
# Kubernetes 节点安装标记（希云环境）
# 安装时间: $(date '+%Y-%m-%d %H:%M:%S')
# K8S_VERSION: ${K8S_VERSION}
# DOCKER_VERSION: ${DOCKER_VERSION}
# 日志文件: ${LOG_FILE}
EOF
}

# ==================== 步骤 1: 基础依赖 ====================
install_base() {
    log_step "步骤 1/6: 安装基础依赖..."

    log_info "更新软件包列表..."
    if apt update -y 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "软件包列表更新完成"
    else
        log_error "apt update 失败，查看日志: ${LOG_FILE}"
        exit 1
    fi

    log_info "安装基础工具..."
    local packages=(
        curl wget ca-certificates
        apt-transport-https software-properties-common
        nfs-common open-iscsi
        qemu-guest-agent
        ipset ipvsadm conntrack
        chrony telnet net-tools
    )
    if apt install -y "${packages[@]}" 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "基础工具安装完成"
    else
        log_error "基础工具安装失败，查看日志: ${LOG_FILE}"
        exit 1
    fi

    print_separator
}

# ==================== 步骤 2: 系统配置 ====================
configure_system() {
    log_step "步骤 2/6: 配置系统参数..."

    # 关闭 swap
    if swapon --show 2>/dev/null | grep -q .; then
        log_info "关闭 swap 分区..."
        swapoff -a
        if grep -qE '^[^#].*swap' /etc/fstab 2>/dev/null; then
            cp /etc/fstab /etc/fstab.bak."$(date '+%Y%m%d%H%M%S')"
            sed -i '/swap/s/^/#/' /etc/fstab
            log_info "已注释 /etc/fstab 中的 swap 行"
        fi
        log_success "swap 已关闭"
    else
        log_warning "swap 已关闭，跳过"
    fi

    # 加载内核模块
    local need_modprobe=false
    for mod in overlay br_netfilter ip_vs ip_vs_sh ip_vs_wrr ip_vs_rr; do
        if ! lsmod | grep -q "${mod}"; then
            need_modprobe=true
            break
        fi
    done

    if $need_modprobe; then
        log_info "加载内核模块..."
        cat <<EOF | tee /etc/modules-load.d/k8s.conf > /dev/null
overlay
br_netfilter
ip_vs
ip_vs_sh
ip_vs_wrr
ip_vs_rr
EOF
        modprobe overlay
        modprobe br_netfilter
        modprobe ip_vs
        modprobe ip_vs_sh
        modprobe ip_vs_wrr
        modprobe ip_vs_rr
        log_success "内核模块加载完成"
    else
        log_warning "内核模块已加载，跳过"
    fi

    # 配置内核参数
    log_info "配置内核参数..."
    cat <<EOF | tee /etc/sysctl.d/k8s.conf > /dev/null
# k8s-xiyun - DO NOT REMOVE

# === K8s / Calico 必需 ===
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1

# === Calico iptables 模式 ===
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0

# === 文件句柄与 inotify ===
fs.file-max = 2097152
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 8192

# === 监听队列 ===
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 16384

# === socket 缓冲 ===
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# === TIME-WAIT 复用 ===
net.ipv4.tcp_tw_reuse = 1

# === IPv6 ===
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv6.conf.all.forwarding = 1
EOF
    if sysctl --system >> "${LOG_FILE}" 2>&1; then
        log_success "内核参数配置完成"
    else
        log_error "sysctl --system 执行失败，查看日志: ${LOG_FILE}"
        exit 1
    fi

    print_separator
}

# ==================== 步骤 3: 安装 Docker ====================
install_docker() {
    log_step "步骤 3/6: 安装 Docker ${DOCKER_VERSION}..."

    if command -v docker &>/dev/null; then
        local installed_ver
        installed_ver=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
        if [[ "${installed_ver}" == "$(echo "${DOCKER_VERSION}" | grep -oP '^\d+\.\d+\.\d+')" ]]; then
            log_warning "Docker 已安装 (${installed_ver})，跳过"
        else
            log_warning "Docker 已安装但版本不匹配 (已安装: ${installed_ver}, 需要: ${DOCKER_VERSION})"
        fi
        docker --version
        print_separator
        return
    fi

    # 先写 daemon.json，避免 apt install 自动启动时因缺少配置而失败
    log_info "配置 Docker daemon..."
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "registry-mirrors": ["${REGISTRY_MIRROR}"],
  "storage-driver": "overlay2"
}
EOF

    log_info "安装 docker.io..."
    if apt install -y "docker.io=${DOCKER_VERSION}" 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Docker 安装成功"
    else
        log_error "Docker 安装失败，查看日志: ${LOG_FILE}"
        exit 1
    fi

    # 重载并确保 Docker 正常启动
    systemctl daemon-reload
    if ! systemctl restart docker 2>&1 | tee -a "${LOG_FILE}"; then
        log_warning "Docker 首次启动失败，尝试修复..."
        # 等待一下再重试
        sleep 2
        if ! systemctl restart docker 2>&1 | tee -a "${LOG_FILE}"; then
            log_error "Docker 启动失败，查看日志: ${LOG_FILE}"
            log_error "手动排查: journalctl -xeu docker"
            exit 1
        fi
    fi
    systemctl enable docker >> "${LOG_FILE}" 2>&1
    apt-mark hold docker.io >> "${LOG_FILE}" 2>&1

    if docker --version &>/dev/null; then
        log_success "Docker 服务已启动"
    else
        log_error "Docker 启动失败，查看日志: ${LOG_FILE}"
        exit 1
    fi

    print_separator
}

# ==================== 步骤 4: 安装 Kubernetes ====================
install_kubernetes() {
    log_step "步骤 4/6: 安装 Kubernetes ${K8S_VERSION}..."

    if command -v kubectl &>/dev/null; then
        local installed_ver
        installed_ver=$(kubectl version --client --short 2>/dev/null | grep -oP 'v\K[\d.]+' || echo "unknown")
        if [[ "${installed_ver}" == "${K8S_VERSION}" ]]; then
            log_warning "Kubernetes ${K8S_VERSION} 已安装，跳过"
        else
            log_warning "Kubernetes 已安装但版本不匹配 (已安装: ${installed_ver}, 需要: ${K8S_VERSION})"
        fi
        kubectl version --client --short 2>/dev/null || echo "已安装"
        print_separator
        return
    fi

    log_info "添加 Kubernetes APT 源（华为云镜像）..."
    local keyring_dir="/etc/apt/keyrings"
    mkdir -p "${keyring_dir}"

    if ! curl -fsSL "${K8S_APT_MIRROR}/doc/apt-key.gpg" | gpg --dearmor --batch --yes -o "${keyring_dir}/kubernetes-huawei.gpg" 2>>"${LOG_FILE}"; then
        log_error "Kubernetes GPG key 下载失败"
        exit 1
    fi

    cat <<EOF > /etc/apt/sources.list.d/kubernetes.list
deb [signed-by=${keyring_dir}/kubernetes-huawei.gpg] ${K8S_APT_MIRROR}/ kubernetes-xenial main
EOF

    log_info "更新软件包列表..."
    if apt update -y 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "软件包列表更新完成"
    else
        log_error "apt update 失败，查看日志: ${LOG_FILE}"
        exit 1
    fi

    log_info "安装 kubelet、kubeadm、kubectl..."
    if apt install -y \
        "kubelet=${K8S_VERSION}-00" \
        "kubeadm=${K8S_VERSION}-00" \
        "kubectl=${K8S_VERSION}-00" 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Kubernetes 组件安装成功"
    else
        log_error "Kubernetes 组件安装失败，查看日志: ${LOG_FILE}"
        exit 1
    fi

    log_info "锁定版本防止自动更新..."
    apt-mark hold kubelet kubeadm kubectl >> "${LOG_FILE}" 2>&1

    systemctl enable kubelet >> "${LOG_FILE}" 2>&1
    log_success "kubelet 已设置为开机自启（待 kubeadm init/join 后自动启动）"

    print_separator
}

# ==================== 步骤 5: 预拉取镜像 ====================
pull_images() {
    log_step "步骤 5/6: 从镜像仓库拉取并打标签..."

    local total=${#IMAGES[@]}
    local current=0
    local skipped=0

    for src_image in "${!IMAGES[@]}"; do
        current=$((current + 1))
        target_image="${IMAGES[$src_image]}"

        if docker image inspect "${target_image}" &>/dev/null; then
            log_warning "[${current}/${total}] 镜像已存在，跳过: ${target_image}"
            skipped=$((skipped + 1))
            continue
        fi

        echo -e "\n${YELLOW}▶ 进度: ${current}/${total}${NC}"
        log_info "拉取: ${src_image}"

        if docker pull "${src_image}" >> "${LOG_FILE}" 2>&1; then
            log_success "拉取成功: ${src_image}"

            log_info "重新打标签为: ${target_image}"
            if docker tag "${src_image}" "${target_image}" 2>>"${LOG_FILE}"; then
                log_success "标签完成: ${target_image}"
            else
                log_error "打标签失败: ${target_image}，查看日志: ${LOG_FILE}"
                exit 1
            fi
        else
            log_error "拉取失败: ${src_image}，查看日志: ${LOG_FILE}"
            exit 1
        fi
    done

    if [[ $skipped -gt 0 ]]; then
        log_warning "跳过 ${skipped} 个已存在的镜像"
    fi
    log_success "所有镜像处理完成"
    print_separator
}

# ==================== 步骤 6: 验证 ====================
verify_installation() {
    log_step "步骤 6/6: 验证安装..."

    local all_ok=true

    echo ""
    echo -e "${WHITE}已安装组件版本:${NC}"

    if docker --version 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Docker"
    else
        echo -e "  ${RED}✗${NC} Docker"
        all_ok=false
    fi

    if kubeadm version 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} kubeadm"
    else
        echo -e "  ${RED}✗${NC} kubeadm"
        all_ok=false
    fi

    if kubectl version --client 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} kubectl"
    else
        echo -e "  ${RED}✗${NC} kubectl"
        all_ok=false
    fi

    if kubelet --version 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} kubelet"
    else
        echo -e "  ${RED}✗${NC} kubelet"
        all_ok=false
    fi

    echo ""

    if $all_ok; then
        log_success "所有组件验证通过"
    else
        log_warning "部分组件验证失败，请检查日志: ${LOG_FILE}"
    fi

    print_separator
}

# ==================== 帮助信息 ====================
show_help() {
    echo -e "${CYAN}Kubernetes 节点安装脚本 v2（希云环境）${NC}

${YELLOW}用法:${NC}
  k8s-install.sh [选项]

${YELLOW}选项:${NC}
  -h, --help     显示此帮助信息
  -v, --version  显示脚本版本
  -f, --force    强制重新安装（忽略幂等性检查）
  -d, --debug    启用调试模式（set -x + 详细日志）

${YELLOW}功能说明:${NC}
  此脚本用于在 Ubuntu/Debian 上安装 Kubernetes 节点（希云环境），
  包括 docker.io、kubelet、kubeadm、kubectl 的安装和配置。

${YELLOW}环境说明:${NC}
  Docker 源:  Ubuntu 官方仓库 (docker.io)
  K8s 源:     华为云镜像
  镜像仓库:   ${IMAGE_REGISTRY}
  Calico:     v${CALICO_VERSION}

${YELLOW}默认版本:${NC}
  Kubernetes: ${K8S_VERSION}
  Docker:     ${DOCKER_VERSION}

${YELLOW}日志:${NC}
  安装日志保存在: ${LOG_DIR}/

${YELLOW}示例:${NC}
  sudo k8s-install.sh              # 执行安装（幂等）
  sudo k8s-install.sh --force      # 强制执行（重新安装）
  sudo k8s-install.sh --debug      # 调试模式"
}

# ==================== 主函数 ====================
main() {
    local force=false
    DEBUG=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                echo "Kubernetes 安装脚本 v2.0（希云环境）"
                exit 0
                ;;
            -f|--force)
                force=true
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

    mkdir -p "${LOG_DIR}"
    echo "===== Kubernetes 安装日志（希云环境）$(date) =====" > "${LOG_FILE}"

    if $DEBUG; then
        set -x
        export PS4='+ ${BASH_SOURCE:-}:${LINENO}: '
    fi

    clear
    print_banner

    check_root
    check_os

    if ! $force && is_installed; then
        echo -e "${YELLOW}⚠️  检测到系统已安装 Kubernetes 环境${NC}"
        echo -e "${WHITE}安装信息:${NC}"
        cat "${MARKER_FILE}"
        echo ""
        echo -e "${YELLOW}如需重新安装，请使用: ${WHITE}sudo $0 --force${NC}"
        echo ""
        exit 0
    fi

    log_info "开始 Kubernetes 集群节点初始化（希云环境）..."
    log_info "系统: $(. /etc/os-release && echo "${PRETTY_NAME:-unknown}")"
    log_info "Kubernetes 版本: ${K8S_VERSION}"
    log_info "Docker 版本: ${DOCKER_VERSION}"
    log_info "日志文件: ${LOG_FILE}"
    print_separator

    install_base
    configure_system
    install_docker
    install_kubernetes
    pull_images
    verify_installation

    mark_installed

    print_banner
    print_separator
    echo -e "${GREEN}✅ Kubernetes 节点初始化完成!${NC}"
    print_separator
    echo -e "${WHITE}📌 后续操作:${NC}"
    echo -e "  ${CYAN}1.${NC} 初始化集群: ${WHITE}kubeadm init ...${NC}"
    echo -e "  ${CYAN}2.${NC} 查看节点状态: ${WHITE}kubectl get nodes${NC}"
    echo -e "  ${CYAN}3.${NC} 查看已拉取镜像: ${WHITE}docker images${NC}"
    echo -e "  ${CYAN}4.${NC} 查看安装日志: ${WHITE}cat ${LOG_FILE}${NC}"
    print_separator
    echo -e "${GREEN}🎉 祝您使用愉快！${NC}\n"
}

main "$@"
