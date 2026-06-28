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
    echo "  ███╗   ██╗ ██████╗ ███████╗██╗   ██╗ ██████╗  █████╗ ██████╗ "
    echo "  ████╗  ██║██╔═══██╗██╔════╝██║   ██║██╔════╝ ██╔══██╗██╔══██╗"
    echo "  ██╔██╗ ██║██║   ██║███████╗██║   ██║██║  ███╗███████║██████╔╝"
    echo "  ██║╚██╗██║██║   ██║╚════██║██║   ██║██║   ██║██╔══██║██╔══██╗"
    echo "  ██║ ╚████║╚██████╔╝███████║╚██████╔╝╚██████╔╝██║  ██║██║  ██║"
    echo "  ╚═╝  ╚═══╝ ╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝"
    echo -e "${NC}"
}

# ==================== 配置变量 ====================
K8S_VERSION="1.21.11"
DOCKER_VERSION="20.10.17"
DOCKER_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/docker-ce"
K8S_APT_MIRROR="https://mirrors.aliyun.com/kubernetes/apt"
REGISTRY_MIRROR="https://docker.mirrors.ustc.edu.cn"
ALIYUN_REGISTRY="swr.cn-north-4.myhuaweicloud.com/ddn-k8s"

LOG_DIR="/var/log/k8s-install"
LOG_FILE=""

MARKER_DIR="/var/lib/k8s-install"
MARKER_FILE="${MARKER_DIR}/installed"

# 安装用的镜像映射（源 -> 目标）
declare -A INSTALL_IMAGES=(
    ["${ALIYUN_REGISTRY}/docker.io/prom/node-exporter:v1.3.1"]="docker.io/prom/node-exporter:v1.3.1"
    ["${ALIYUN_REGISTRY}/docker.io/kubesphere/kube-rbac-proxy:v0.11.0"]="docker.io/kubesphere/kube-rbac-proxy:v0.11.0"
    ["${ALIYUN_REGISTRY}/docker.io/calico/node:v3.22.2"]="docker.io/calico/node:v3.22.2"
    ["${ALIYUN_REGISTRY}/docker.io/calico/cni:v3.22.2"]="docker.io/calico/cni:v3.22.2"
    ["${ALIYUN_REGISTRY}/docker.io/calico/pod2daemon-flexvol:v3.22.2"]="docker.io/calico/pod2daemon-flexvol:v3.22.2"
)

# 卸载用的镜像列表（目标名）
UNINSTALL_IMAGES=(
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

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "无法识别操作系统（缺少 /etc/os-release）"
        exit 1
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
        log_error "此脚本仅支持 Ubuntu，当前系统: ${PRETTY_NAME:-unknown}"
        exit 1
    fi
    if [[ "${VERSION_ID:-}" != "22.04" ]]; then
        log_error "此脚本仅支持 Ubuntu 22.04，当前版本: ${VERSION_ID:-unknown} (${VERSION_CODENAME:-})"
        exit 1
    fi
}

is_installed() {
    [[ -f "${MARKER_FILE}" ]]
}

mark_installed() {
    mkdir -p "${MARKER_DIR}"
    cat > "${MARKER_FILE}" <<EOF
# Kubernetes 节点安装标记
# 安装时间: $(date '+%Y-%m-%d %H:%M:%S')
# K8S_VERSION: ${K8S_VERSION}
# DOCKER_VERSION: ${DOCKER_VERSION}
# 日志文件: ${LOG_FILE}
EOF
}

# ==================== 安装: 系统初始化 ====================
install_init_system() {
    local sysctl_marker="/etc/sysctl.d/k8s.conf"
    local mod_marker="/etc/modules-load.d/k8s.conf"

    if [[ -f "${sysctl_marker}" ]] && [[ -f "${mod_marker}" ]]; then
        log_warning "系统配置已初始化，跳过"
        print_separator
        return
    fi

    log_step "步骤 1/4: 初始化系统配置..."

    log_info "更新软件包列表..."
    if apt update -y 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "软件包列表更新完成"
    else
        log_error "apt update 失败，查看日志: ${LOG_FILE}"
        exit 1
    fi

    log_info "安装基础工具..."
    if apt install -y curl wget apt-transport-https \
        nfs-common open-iscsi qemu-guest-agent 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "基础工具安装完成"
    else
        log_error "基础工具安装失败，查看日志: ${LOG_FILE}"
        exit 1
    fi

    # 关闭 swap
    if swapon --show 2>/dev/null | grep -q .; then
        log_info "关闭 swap 分区..."
        swapoff -a
        sed -i '/swap/d' /etc/fstab
        log_success "swap 已关闭"
    else
        log_warning "swap 已关闭，跳过"
    fi

    # 加载内核模块
    local need_modprobe=false
    if ! lsmod | grep -q overlay; then need_modprobe=true; fi
    if ! lsmod | grep -q br_netfilter; then need_modprobe=true; fi

    if $need_modprobe; then
        log_info "加载内核模块..."
        cat <<EOF | tee "${mod_marker}" > /dev/null
overlay
br_netfilter
EOF
        modprobe overlay
        modprobe br_netfilter
        log_success "内核模块加载完成"
    else
        log_warning "内核模块已加载，跳过"
    fi

    # 配置内核参数
    log_info "配置内核参数..."
    cat <<EOF | tee "${sysctl_marker}" > /dev/null
# k8s-init - DO NOT REMOVE

# === K8s / Calico 必需 ===
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1

# === Calico iptables 模式建议 ===
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0

# === 文件句柄与 inotify ===
fs.file-max = 2097152
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 8192

# === 监听队列（apiserver 性能）===
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

# === IPv6（如需双栈请删除下面四行） ===
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

# ==================== 安装: Docker ====================
install_docker() {
    log_step "步骤 2/4: 安装 Docker ${DOCKER_VERSION}..."

    if command -v docker &>/dev/null; then
        local installed_ver
        installed_ver=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
        if [[ "${installed_ver}" == "${DOCKER_VERSION}" ]]; then
            log_warning "Docker ${DOCKER_VERSION} 已安装，跳过"
        else
            log_warning "Docker 已安装但版本不匹配 (已安装: ${installed_ver}, 需要: ${DOCKER_VERSION})"
            log_warning "如需重新安装，请先卸载后重试"
        fi
        docker --version
        print_separator
        return
    fi

    log_info "下载并安装 Docker ${DOCKER_VERSION}..."

    local install_urls=(
        "https://ghfast.top/https://raw.githubusercontent.com/docker/docker-install/master/install.sh"
        "https://raw.githubusercontent.com/docker/docker-install/master/install.sh"
    )

    local docker_script="/tmp/docker-install-$$.sh"
    local download_ok=false

    for url in "${install_urls[@]}"; do
        log_info "尝试下载: ${url}"
        if curl -fsSL --connect-timeout 30 --retry 2 -o "${docker_script}" "${url}" 2>>"${LOG_FILE}"; then
            download_ok=true
            log_success "脚本下载成功"
            break
        else
            log_warning "下载失败: ${url}，尝试下一个地址..."
        fi
    done

    if ! $download_ok; then
        log_error "所有下载地址均失败，查看日志: ${LOG_FILE}"
        rm -f "${docker_script}"
        exit 1
    fi

    export DOWNLOAD_URL="$DOCKER_MIRROR"
    log_info "执行 Docker 安装..."
    if sh "${docker_script}" --version "${DOCKER_VERSION}" >> "${LOG_FILE}" 2>&1; then
        log_success "Docker 安装成功"
    else
        log_error "Docker 安装失败，查看日志: ${LOG_FILE}"
        rm -f "${docker_script}"
        exit 1
    fi
    rm -f "${docker_script}"

    log_info "配置 Docker..."
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "registry-mirrors": ["${REGISTRY_MIRROR}"]
}
EOF

    systemctl daemon-reload
    systemctl enable --now docker >> "${LOG_FILE}" 2>&1
    apt-mark hold docker-ce >> "${LOG_FILE}" 2>&1
    log_success "Docker 服务已启动"

    print_separator
}

# ==================== 安装: Kubernetes ====================
install_kubernetes() {
    log_step "步骤 3/4: 安装 Kubernetes ${K8S_VERSION}..."

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

    log_info "添加 Kubernetes APT 源（阿里云镜像）..."
    log_info "v1.21.11 版本几乎国内源已下架..."

    local keyring_dir="/etc/apt/keyrings"
    mkdir -p "${keyring_dir}"

    if ! curl -fsSL "${K8S_APT_MIRROR}/doc/apt-key.gpg" | gpg --dearmor --batch --yes -o "${keyring_dir}/kubernetes-archive-keyring.gpg" 2>>"${LOG_FILE}"; then
        log_error "Kubernetes GPG key 下载失败"
        exit 1
    fi

    cat <<EOF > /etc/apt/sources.list.d/kubernetes.list
deb [signed-by=${keyring_dir}/kubernetes-archive-keyring.gpg] ${K8S_APT_MIRROR}/ kubernetes-xenial main
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
        kubelet="${K8S_VERSION}-00" \
        kubeadm="${K8S_VERSION}-00" \
        kubectl="${K8S_VERSION}-00" >> "${LOG_FILE}" 2>&1; then
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

# ==================== 安装: 预拉取镜像 ====================
install_pull_images() {
    log_step "步骤 4/4: 从阿里云拉取镜像并打标签..."

    local total=${#INSTALL_IMAGES[@]}
    local current=0
    local skipped=0

    for aliyun_image in "${!INSTALL_IMAGES[@]}"; do
        current=$((current + 1))
        target_image="${INSTALL_IMAGES[$aliyun_image]}"

        if docker image inspect "${target_image}" &>/dev/null; then
            log_warning "[${current}/${total}] 镜像已存在，跳过: ${target_image}"
            skipped=$((skipped + 1))
            continue
        fi

        echo -e "\n${YELLOW}▶ 进度: ${current}/${total}${NC}"
        log_info "拉取: ${aliyun_image}"

        if docker pull "${aliyun_image}" >> "${LOG_FILE}" 2>&1; then
            log_success "拉取成功: ${aliyun_image}"
            log_info "重新打标签为: ${target_image}"
            if docker tag "${aliyun_image}" "${target_image}" 2>>"${LOG_FILE}"; then
                log_success "标签完成: ${target_image}"
            else
                log_error "打标签失败: ${target_image}，查看日志: ${LOG_FILE}"
                exit 1
            fi
        else
            log_error "拉取失败: ${aliyun_image}，查看日志: ${LOG_FILE}"
            exit 1
        fi
    done

    if [[ $skipped -gt 0 ]]; then
        log_warning "跳过 ${skipped} 个已存在的镜像"
    fi
    log_success "所有镜像处理完成"
    print_separator
}

# ==================== 卸载: 停止服务 ====================
uninstall_stop_services() {
    log_step "步骤 1/6: 停止服务..."

    local svc
    for svc in kubelet docker containerd; do
        if systemctl is-active --quiet "${svc}" 2>/dev/null; then
            if systemctl disable --now "${svc}" 2>&1 | tee -a "${LOG_FILE}"; then
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

# ==================== 卸载: kubeadm reset ====================
uninstall_reset_kubeadm() {
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
    if kubeadm reset --force 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "kubeadm reset 完成"
    else
        log_warning "kubeadm reset 失败，查看日志: ${LOG_FILE}，继续后续清理"
    fi
    print_separator
}

# ==================== 卸载: 卸载软件包 ====================
uninstall_remove_packages() {
    log_step "步骤 3/6: 卸载软件包..."

    log_info "取消版本锁定..."
    apt-mark unhold kubelet kubeadm kubectl docker-ce >> "${LOG_FILE}" 2>&1 || true

    log_info "卸载 Kubernetes 组件..."
    if apt-get purge -y kubelet kubeadm kubectl 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Kubernetes 组件已卸载"
    else
        log_warning "Kubernetes 组件卸载失败（可能未安装）"
    fi

    log_info "卸载 Docker 组件..."
    if apt-get purge -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Docker 组件已卸载"
    else
        log_warning "Docker 组件卸载失败（可能未安装）"
    fi

    log_info "清理无用依赖..."
    apt-get autoremove -y 2>&1 | tee -a "${LOG_FILE}" || true

    log_success "软件包已卸载"
    print_separator
}

# ==================== 卸载: 清理 APT 源 ====================
uninstall_remove_sources() {
    log_step "步骤 4/6: 清理 APT 源与配置..."

    if [[ -f /etc/apt/sources.list.d/kubernetes.list ]]; then
        rm -f /etc/apt/sources.list.d/kubernetes.list
        log_info "已删除 /etc/apt/sources.list.d/kubernetes.list"
    fi

    if [[ -f /etc/apt/sources.list.d/docker.list ]]; then
        rm -f /etc/apt/sources.list.d/docker.list
        log_info "已删除 /etc/apt/sources.list.d/docker.list"
    fi

    rm -f /etc/apt/keyrings/docker.asc /etc/apt/keyrings/docker.gpg 2>/dev/null || true
    rm -f /etc/apt/keyrings/kubernetes-archive-keyring.gpg 2>/dev/null || true

    if [[ -d /etc/docker ]]; then
        rm -rf /etc/docker
        log_info "已删除 /etc/docker"
    fi

    log_info "刷新 APT 缓存..."
    apt-get update >> "${LOG_FILE}" 2>&1 || true

    log_success "APT 源与配置已清理"
    print_separator
}

# ==================== 卸载: 恢复系统 ====================
uninstall_restore_system() {
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

# ==================== 卸载: 清理标记 ====================
uninstall_cleanup_marker() {
    log_step "步骤 6/6: 清理安装标记..."

    if [[ -d "${MARKER_DIR}" ]]; then
        rm -rf "${MARKER_DIR}"
        log_info "已删除 ${MARKER_DIR}"
    fi

    log_success "卸载完成"
    print_separator
}

# ==================== 卸载: 清理运行时数据（--purge）====================
uninstall_purge_data() {
    log_step "额外步骤: 清理运行时数据（--purge）..."

    if command -v docker >/dev/null 2>&1 && docker info &>/dev/null 2>&1; then
        log_info "删除安装脚本预拉的镜像..."
        for img in "${UNINSTALL_IMAGES[@]}"; do
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

    # 清理 k8s/calico 的 iptables/ip6tables 链
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

# ==================== 帮助信息 ====================
show_help() {
    echo -e "${CYAN}Kubernetes 节点管理脚本 v2（mig环境）${NC}

${YELLOW}用法:${NC}
  $0 <命令> [选项]

${YELLOW}命令:${NC}
  install     安装 Kubernetes 节点
  uninstall   卸载 Kubernetes 节点

${YELLOW}install 选项:${NC}
  -f, --force    强制重新安装（忽略幂等性检查）
  -d, --debug    启用调试模式

${YELLOW}uninstall 选项:${NC}
  -f, --force    跳过确认提示
  -p, --purge    同时清理运行时数据（不可恢复）
  -d, --debug    启用调试模式

${YELLOW}通用选项:${NC}
  -h, --help     显示此帮助信息
  -v, --version  显示脚本版本

${YELLOW}环境说明:${NC}
  Docker 源:  清华镜像 (docker-ce)
  K8s 源:     阿里云镜像
  镜像仓库:   ${ALIYUN_REGISTRY}
  系统要求:   Ubuntu 22.04

${YELLOW}默认版本:${NC}
  Kubernetes: ${K8S_VERSION}
  Docker:     ${DOCKER_VERSION}

${YELLOW}日志:${NC}
  日志保存在: ${LOG_DIR}/

${YELLOW}示例:${NC}
  sudo $0 install                 # 安装
  sudo $0 install --force         # 强制重新安装
  sudo $0 uninstall               # 卸载（保留数据）
  sudo $0 uninstall --purge       # 完全清理（含数据）
  sudo $0 uninstall --force --purge  # 强制完全清理"
}

# ==================== install 入口 ====================
cmd_install() {
    local force=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force) force=true ;;
            -d|--debug) DEBUG=true ;;
            *)
                log_error "未知选项: $1"
                echo "使用 $0 install --help 查看帮助"
                exit 1
                ;;
        esac
        shift
    done

    LOG_FILE="${LOG_DIR}/install-$(date '+%Y%m%d-%H%M%S').log"
    mkdir -p "${LOG_DIR}"
    echo "===== Kubernetes 安装日志 $(date) =====" > "${LOG_FILE}"

    clear
    print_banner

    check_root
    check_os

    if ! $force && is_installed; then
        echo -e "${YELLOW}⚠️  检测到系统已安装 Kubernetes 环境${NC}"
        echo -e "${WHITE}安装信息:${NC}"
        cat "${MARKER_FILE}"
        echo ""
        echo -e "${YELLOW}如需重新安装，请使用: ${WHITE}sudo $0 install --force${NC}"
        echo ""
        exit 0
    fi

    log_info "开始 Kubernetes 集群节点初始化..."
    log_info "系统: Ubuntu 22.04"
    log_info "Kubernetes 版本: ${K8S_VERSION}"
    log_info "Docker 版本: ${DOCKER_VERSION}"
    log_info "日志文件: ${LOG_FILE}"
    print_separator

    install_init_system
    install_docker
    install_kubernetes
    install_pull_images

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

# ==================== uninstall 入口 ====================
cmd_uninstall() {
    local force=false
    local purge=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force) force=true ;;
            -p|--purge) purge=true ;;
            -d|--debug) DEBUG=true ;;
            *)
                log_error "未知选项: $1"
                echo "使用 $0 uninstall --help 查看帮助"
                exit 1
                ;;
        esac
        shift
    done

    LOG_FILE="${LOG_DIR}/uninstall-$(date '+%Y%m%d-%H%M%S').log"
    mkdir -p "${LOG_DIR}"
    echo "===== Kubernetes 卸载日志 $(date) =====" > "${LOG_FILE}"

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

    if $purge; then
        uninstall_purge_data
    fi

    uninstall_stop_services
    uninstall_reset_kubeadm
    uninstall_remove_packages
    uninstall_remove_sources
    uninstall_restore_system
    uninstall_cleanup_marker

    print_separator
    echo -e "${GREEN}✅ 卸载完成!${NC}"
    if ! $purge; then
        echo -e "${YELLOW}提示: 使用 --purge 可清理运行时数据（不可恢复）${NC}"
    fi
    echo -e "${WHITE}日志文件: ${LOG_FILE}${NC}"
    print_separator
}

# ==================== 主入口 ====================
main() {
    DEBUG=false

    if [[ $# -eq 0 ]]; then
        show_help
        exit 1
    fi

    local cmd="$1"
    shift

    case "$cmd" in
        install)
            if $DEBUG; then set -x; export PS4='+ ${BASH_SOURCE:-}:${LINENO}: '; fi
            cmd_install "$@"
            ;;
        uninstall)
            if $DEBUG; then set -x; export PS4='+ ${BASH_SOURCE:-}:${LINENO}: '; fi
            cmd_uninstall "$@"
            ;;
        -h|--help)
            show_help
            ;;
        -v|--version)
            echo "Kubernetes 管理脚本 v2.0（绵阳环境）"
            ;;
        *)
            log_error "未知命令: ${cmd}"
            echo "使用 $0 --help 查看帮助"
            exit 1
            ;;
    esac
}

main "$@"
