#!/bin/bash
set -e

function if_success() {
    local RETURN_STATUS=$1
    local ERROR_MSG=$2
    if [ ${RETURN_STATUS} -ne 0 ]; then
        echo -e "\\033[\[\\033[1;31m  ${ERROR_MSG}  \\033[0;39m]\r"
        exit 1
    fi
}

function msg() {
    local MSG=$1
    echo -e "\\033[\[\\033[1;32m  ${MSG}  \\033[0;39m]\r"
    return 0
}

function config() {
    local -r MYFLY_ZSH='eval $(mcfly init zsh)'
    local -r JUMP_ZSH="source /usr/share/autojump/autojump.zsh"
    local -r ALIAS_BAT="alias cat='batcat -p'"
    local -r ALIAS_TLDR="alias help='tldr'"
    local -r ALIAS_PROCS="alias ps='procs --use-config large'"
    local -r THEME_BAT="export BAT_THEME='1337'"
    local -r FZF_OPTS="export FZF_DEFAULT_OPTS=\"--height=90% --layout=reverse --info=right --border  --margin=1 --padding=1  --preview='batcat --color=always --style=numbers {}' --preview-window=border\""
    
    if [ ! -d ~/.oh-my-zsh ]; then
        ZSH=
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/kinghu88/zsh/refs/heads/main/install.sh)"
        if_success $? "安装Oh My Zsh失败"
    fi
    msg "将进行~/.zshrc配置..."
    TEMP_ZSHRC=$(mktemp) && cp -rf ~/.zshrc  "${TEMP_ZSHRC}"
    # 追加或更新配置（仅当它们不存在时）
    grep -qF  "${MYFLY_ZSH}" "${TEMP_ZSHRC}" || echo "${MYFLY_ZSH}" >> "${TEMP_ZSHRC}"
    grep -qF  "${JUMP_ZSH}" "${TEMP_ZSHRC}" || echo "${JUMP_ZSH}" >> "${TEMP_ZSHRC}"
    grep -qF  "${ALIAS_BAT}" "${TEMP_ZSHRC}" || echo "${ALIAS_BAT}" >> "${TEMP_ZSHRC}"
    grep -qF  "${ALIAS_TLDR}"  "${TEMP_ZSHRC}" || echo "${ALIAS_TLDR}" >> "${TEMP_ZSHRC}"
    grep -qF  "${ALIAS_PROCS}"  "${TEMP_ZSHRC}" || echo "${ALIAS_PROCS}" >> "${TEMP_ZSHRC}"
    grep -qF  "${THEME_BAT}"  "${TEMP_ZSHRC}" || echo "${THEME_BAT}" >> "${TEMP_ZSHRC}"
    grep -qF  "${FZF_OPTS}"  "${TEMP_ZSHRC}" || echo "${FZF_OPTS}" >> "${TEMP_ZSHRC}"
    # 如果.zshrc的内容发生了变化，则替换它
    if ! cmp -s ~/.zshrc "${TEMP_ZSHRC}"; then
        mv "${TEMP_ZSHRC}" ~/.zshrc
        zsh && source ~/.zshrc
    fi
}

function ensure_command_installed() {
    local CMD_NAME="$1"
    local INSTALL_CMD="$2"
    if ! command -v "${CMD_NAME}" &> /dev/null; then
        msg "安装 ${CMD_NAME}"
        eval "${INSTALL_CMD}"  # 直接执行命令，假设它是安全的
        if_success $? "${CMD_NAME} 安装失败"
    else
        msg "${CMD_NAME} 已安装"
    fi
}

function handle_ubuntu_init() {
    local -r MCFLY_URL="https://raw.githubusercontent.com/cantino/mcfly/master/ci/install.sh"
    local -r FZF_URL="https://github.com/junegunn/fzf/releases/download/0.42.0/fzf-0.42.0-linux_amd64.tar.gz"
    local -r PROCS_URL="https://github.com/dalance/procs/releases/download/v0.14.0/procs-v0.14.0-x86_64-linux.zip"
    local FZF_EXEC='curl -LSfs "${FZF_URL}" | $SUDO tar -xzf - -C /usr/local/bin/'
    local MCFLY_EXEC='curl -LSfs "${MCFLY_URL}" | $SUDO sh -s -- --git cantino/mcfly'
    local PROCS_EXEC='wget -q -O /tmp/procs.zip "${PROCS_URL}" && $SUDO unzip -o /tmp/procs.zip -d /usr/local/bin/'
    local TLDR_EXEC='pip3 install tldr'
    SUDO=sudo
    if [ $(id -u) -eq 0 ]; then
        SUDO=
    fi
    msg "配置时区..."
    $SUDO timedatectl set-timezone Asia/Shanghai
    if_success $? "设置时区失败"
    
    msg "更新系统软件包..."
    $SUDO apt update #&& $SUDO apt upgrade -y
    if_success $? "系统更新失败"
    
    msg "安装常用工具..."
    $SUDO apt install -y zsh bat autojump ripgrep build-essential unzip python3-pip
    if_success $? "工具安装失败"
    ensure_command_installed mcfly "${MCFLY_EXEC}"
    ensure_command_installed fzf "${FZF_EXEC}"
    ensure_command_installed procs "{$PROCS_EXEC}"
    ensure_command_installed tldr "${TLDR_EXEC}"
    config
    msg "系统初始化完成！"
}

function handle_centos() {
    msg "执行针对 CentOS/RHEL 系统的操作"
}

function handle_unknown() {
    msg "未知的操作系统，无法执行特定操作"
}

function main() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        msg "${NAME} ${VERSION}"
        case "${NAME}" in
            "Ubuntu" | "Debian GNU/Linux")
                handle_ubuntu_init
            ;;
            "CentOS Linux" | "Red Hat Enterprise Linux")
                handle_centos
            ;;
            *)
                handle_unknown
            ;;
        esac
        elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        msg "${DISTRIB_ID} ${DISTRIB_RELEASE}"
        case "${DISTRIB_ID}" in
            "Ubuntu" | "Debian")
                handle_ubuntu_init
            ;;
            *)
                handle_unknown
            ;;
        esac
        elif [ -f /etc/debian_version ]; then
        msg "$(cat /etc/debian_version)"
        handle_ubuntu_init
        elif [ -f /etc/redhat-release ]; then
        cat /etc/redhat-release
        handle_centos
    else
        msg "未知的操作系统"
        handle_unknown
    fi
}

main
