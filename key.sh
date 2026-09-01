#!/usr/bin/env bash
#=============================================================
# SSH Key & Security Installer
# Supporting: Alpine Linux (OpenRC), Debian/Ubuntu/CentOS/RHEL (systemd)
#=============================================================

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
PURPLE="\033[35m"
CYAN="\033[36m"
BOLD="\033[1m"
RESET="\033[0m"

INFO="${GREEN}[INFO]${RESET}"
WARN="${YELLOW}[WARN]${RESET}"
ERROR="${RED}[ERROR]${RESET}"

[ "$EUID" -ne 0 ] && SUDO="sudo" || SUDO=""

# ---------------------------------------------------------------
# 环境与服务检测
# ---------------------------------------------------------------
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$NAME
        OS_VER=$VERSION_ID
    else
        OS_NAME=$(uname -s)
        OS_VER=$(uname -r)
    fi
}

restart_sshd() {
    echo -e "${INFO} 正在检测 SSH 配置文件语法..."
    if command -v sshd &>/dev/null; then
        if ! $SUDO sshd -t; then
            echo -e "${ERROR} SSH 配置文件测试失败！检测到语法错误，已取消重启以防止断连锁死！"
            return 1
        fi
    fi

    echo -e "${INFO} 正在重启 SSH 服务..."
    if command -v rc-service &>/dev/null; then
        $SUDO rc-service sshd restart
    elif command -v systemctl &>/dev/null; then
        if systemctl list-unit-files 2>/dev/null | grep -q "ssh.socket"; then
            echo -e "${INFO} 检测到 systemd ssh.socket，正在强制关闭并屏蔽 (mask)..."
            $SUDO systemctl stop ssh.socket &>/dev/null
            $SUDO systemctl disable ssh.socket &>/dev/null
            $SUDO systemctl mask ssh.socket &>/dev/null
        fi
        $SUDO systemctl daemon-reload &>/dev/null
        $SUDO systemctl enable ssh &>/dev/null || $SUDO systemctl enable sshd &>/dev/null
        $SUDO systemctl restart ssh || $SUDO systemctl restart sshd
    elif command -v service &>/dev/null; then
        $SUDO service sshd restart || $SUDO service ssh restart
    else
        $SUDO /etc/init.d/sshd restart
    fi

    if [ $? -eq 0 ]; then
        echo -e "${INFO} ${GREEN}SSH 服务重启成功！${RESET}"
        return 0
    else
        echo -e "${ERROR} SSH 服务重启失败，请检查配置文件！"
        return 1
    fi
}

check_dependencies() {
    local deps=("curl" "ssh-keygen" "gawk" "awk")
    for dep in "${deps[@]}"; do
        if [ "$dep" == "awk" ] || [ "$dep" == "gawk" ]; then
            command -v awk &>/dev/null && continue
        fi
        if ! command -v "$dep" &>/dev/null; then
            echo -e "${WARN} 检测到未安装 $dep，尝试自动安装..."
            if command -v apk &>/dev/null; then
                $SUDO apk add --no-cache openssh-client curl gawk
            elif command -v apt-get &>/dev/null; then
                $SUDO apt-get update && $SUDO apt-get install -y curl openssh-client gawk
            elif command -v yum &>/dev/null; then
                $SUDO yum install -y curl openssh-clients gawk
            fi
        fi
    done
}

# ---------------------------------------------------------------
# SSH 配置解析与修改
# ---------------------------------------------------------------
get_sshd_config_val() {
    local key="$1"
    local default_val="$2"
    local file="/etc/ssh/sshd_config"
    if [ -f "$file" ]; then
        local val
        val=$(grep -iE "^\s*${key}\s+" "$file" | tail -n 1 | awk '{print $2}')
        if [ -n "$val" ]; then
            echo "$val"
            return
        fi
    fi
    echo "$default_val"
}

set_sshd_config() {
    local param="$1"
    local value="$2"
    local file="/etc/ssh/sshd_config"

    if [ -d "/etc/ssh/sshd_config.d" ]; then
        for conf in /etc/ssh/sshd_config.d/*.conf; do
            if [ -f "$conf" ]; then
                $SUDO sed -i -E "s/^\s*#?\s*(${param})\b.*/# \1 (disabled by key.sh)/i" "$conf"
            fi
        done
    fi

    if grep -qiE "^\s*#?\s*${param}\b" "$file"; then
        $SUDO sed -i -E "s/^\s*#?\s*(${param})\b.*/${param} ${value}/i" "$file"
    else
        echo "${param} ${value}" | $SUDO tee -a "$file" > /dev/null
    fi
}

init_ssh_dir() {
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    touch "${HOME}/.ssh/authorized_keys"
    chmod 600 "${HOME}/.ssh/authorized_keys"
}

append_key_with_meta() {
    local pub_content="$1"
    local source_tag="$2"
    local auth_file="${HOME}/.ssh/authorized_keys"
    local ts
    ts=$(date "+%Y-%m-%d %H:%M:%S")

    init_ssh_dir

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        line=$(echo "$line" | sed -e 's/[[:space:]]*$//')
        
        local core_key
        core_key=$(echo "$line" | awk '{print $1, $2}')

        if [ -z "$core_key" ]; then
            continue
        fi

        if grep -qF "$core_key" "$auth_file" 2>/dev/null; then
            echo -e "${WARN} 该公钥已经存在于 authorized_keys 中，已跳过重复追加。"
            continue
        fi

        echo "${core_key} [${ts}|${source_tag}]" >> "$auth_file"
        echo -e "${INFO} ${GREEN}已成功追加公钥 (${source_tag})${RESET}"
    done <<< "$pub_content"

    chmod 600 "$auth_file"
}

# ---------------------------------------------------------------
# 状态 UI 面板
# ---------------------------------------------------------------
show_status() {
    detect_os
    
    local port
    port=$(get_sshd_config_val "Port" "22")
    
    local pwd_auth
    pwd_auth=$(get_sshd_config_val "PasswordAuthentication" "yes")
    
    local pubkey_auth
    pubkey_auth=$(get_sshd_config_val "PubkeyAuthentication" "yes")

    local key_count=0
    if [ -f "${HOME}/.ssh/authorized_keys" ]; then
        key_count=$(awk '!/^[[:space:]]*($|#)/{c++} END{print c+0}' "${HOME}/.ssh/authorized_keys")
    fi

    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${BOLD}${PURPLE}                     SSH 密钥安全配置工具${RESET}"
    echo -e "${CYAN}============================================================${RESET}"
    echo -e " 系统架构 : ${GREEN}${OS_NAME} ${OS_VER}${RESET}"
    echo -e " SSH 端口 : ${CYAN}${port}${RESET}"
    
    if [[ "${pwd_auth,,}" == "no" ]]; then
        echo -e " 密码登录 : ${GREEN}已禁用 (PasswordAuthentication no)${RESET}"
    else
        echo -e " 密码登录 : ${RED}已开启 (推荐配置密钥后禁用)${RESET}"
    fi

    if [[ "${pubkey_auth,,}" == "yes" ]]; then
        if [ "$key_count" -gt 0 ]; then
            echo -e " 密钥登录 : ${GREEN}已启用 (PubkeyAuthentication yes)${RESET}"
        else
            echo -e " 密钥登录 : ${YELLOW}已开启 (但未配置公钥，无法通过密钥登录)${RESET}"
        fi
    else
        echo -e " 密钥登录 : ${RED}已禁用${RESET}"
    fi

    echo -e " 已存公钥 : ${YELLOW}${key_count} 条记录${RESET} (${HOME}/.ssh/authorized_keys)"
    echo -e "${CYAN}============================================================${RESET}"
}

# ---------------------------------------------------------------
# 功能模块
# ---------------------------------------------------------------
generate_vps_keypair() {
    echo -e "\n${INFO} 准备在 VPS 上生成新的 ED25519 密钥..."
    local key_file="${HOME}/.ssh/PrivateKey.pem"
    local pub_file="${HOME}/.ssh/PublicKey.pub"

    if [ -f "$key_file" ] || [ -f "$pub_file" ] || [ -f "${key_file}.pub" ]; then
        echo -e "${WARN} 检测到已有旧同名密钥，即将覆盖清理..."
        rm -f "$key_file" "$pub_file" "${key_file}.pub"
    fi

    # -C "" 保证生成的密钥无后缀标识信息
    ssh-keygen -t ed25519 -C "" -f "$key_file" -N "" -q
    if [ -f "${key_file}.pub" ]; then
        mv "${key_file}.pub" "$pub_file"
    fi

    local pub_content
    pub_content=$(cat "$pub_file")

    append_key_with_meta "$pub_content" "VPS本地生成"

    echo -e "\n${GREEN}====================== 密钥生成成功 ======================${RESET}"
    echo -e " VPS 上的私钥路径 : ${CYAN}${key_file}${RESET}"
    echo -e " VPS 上的公钥路径 : ${CYAN}${pub_file}${RESET}"
    echo -e " 授权目标文件     : 已将公钥写入 ${CYAN}${HOME}/.ssh/authorized_keys${RESET}"
    echo -e "${CYAN}------------------------------------------------------------${RESET}"
    echo -e "${YELLOW}${BOLD}[私钥文本 (PrivateKey.pem)] - 用于登录此 VPS：${RESET}"
    echo -e "${YELLOW}"
    cat "$key_file"
    echo -e "${RESET}"
    echo -e "${CYAN}------------------------------------------------------------${RESET}"
    echo -e "${GREEN}${BOLD}[公钥文本 (PublicKey.pub)] - 用于上传至 GitHub：${RESET}"
    echo -e "${GREEN}${pub_content}${RESET}"
    echo -e "${CYAN}------------------------------------------------------------${RESET}"

    echo -e "${BOLD}${PURPLE}[💡 新手一劳永逸指南]${RESET}"
    echo -e " ${BOLD}一、保存密钥到本地电脑 (二选一)：${RESET}"
    echo -e "   ${GREEN}• 方式 A (推荐·直接下载)：${RESET}打开 SSH 客户端自带的 ${CYAN}SFTP / 文件传输${RESET} 功能 (如 FinalShell、Xshell、WinSCP、Termius 等)，"
    echo -e "     定位到服务器目录：${CYAN}${HOME}/.ssh/${RESET}"
    echo -e "     将 ${CYAN}PrivateKey.pem${RESET} (私钥) 和 ${CYAN}PublicKey.pub${RESET} (公钥) 直接下载保存到本地电脑。"
    echo -e "   ${GREEN}• 方式 B (手动复制)：${RESET}"
    echo -e "     1. 复制上面的【私钥文本】，在本地新建纯文本文件保存为：${CYAN}PrivateKey.pem${RESET}"
    echo -e "     2. 复制上面的【公钥文本】，在本地新建纯文本文件保存为：${CYAN}PublicKey.pub${RESET}"
    echo -e "\n ${BOLD}二、绑定 GitHub 打通长期复用工作流(可选)：${RESET}"
    echo -e "   1. 打开 ${CYAN}https://github.com/settings/keys${RESET} ，点击 \"New SSH key\"；"
    echo -e "   2. 将 ${CYAN}PublicKey.pub${RESET} 里的【公钥文本】粘贴进去并保存；"
    echo -e "   3. ${GREEN}以后在其他 VPS 上运行本脚本，只需选择【选项 1】输入 GitHub 用户名即可快速拉取！${RESET}\n"

    read -rp "确认已保存/下载密钥，是否立即删除 VPS 上的暂存密钥文件？(Y/n): " rm_confirm
    if [[ -z "$rm_confirm" || "$rm_confirm" =~ ^[Yy]$ ]]; then
        rm -f "$key_file" "$pub_file"
        echo -e "${INFO} ${GREEN}已成功删除 VPS 上的暂存密钥文件。${RESET}"
    else
        echo -e "${WARN} 密钥文件仍保留在: ${key_file} 和 ${pub_file} (请务必防范私钥泄露)"
    fi
}

install_key_menu() {
    init_ssh_dir
    echo -e "\n${BOLD}请选择 SSH 密钥配置方式：${RESET}"
    echo -e "  ${GREEN}1.${RESET} 从 GitHub 获取公钥 (${CYAN}适合：已将公钥上传至 GitHub 的用户${RESET})"
    echo -e "  ${GREEN}2.${RESET} 在 VPS 上全新生成密钥 (${CYAN}适合：本地没有密钥的新手，生成后可传 GitHub${RESET})"
    echo -e "  ${GREEN}3.${RESET} 从自定义 URL 获取公钥"
    echo -e "  ${GREEN}0.${RESET} 返回主菜单"
    read -rp "请输入选项 [0-3]: " key_opt

    local test_hint=""

    case "$key_opt" in
        1)
            echo -e "\n${YELLOW}${BOLD}[使用前提]${RESET}"
            echo -e "需先将本地公钥上传至 GitHub: ${CYAN}https://github.com/settings/keys${RESET}\n"
            read -rp "请输入您的 GitHub 用户名: " gh_user
            if [ -z "$gh_user" ]; then
                echo -e "${ERROR} 输入不能为空！"
                read -rp "按回车键返回主菜单..."
                return
            fi
            echo -e "${INFO} 正在从 GitHub 拉取公钥..."
            local pub_key
            pub_key=$(curl -fsSL "https://github.com/${gh_user}.keys")
            if [ -z "$pub_key" ] || [[ "$pub_key" == "Not Found" ]]; then
                echo -e "\n${ERROR} 获取公钥失败！可能是用户名不正确，或该 GitHub 账号未配置公钥。"
                echo -e "${CYAN}------------------------------------------------------------${RESET}"
                read -rp "是否要在 VPS 上全新生成密钥 (选项 2)？(y/N): " switch_opt2
                if [[ "$switch_opt2" =~ ^[Yy]$ ]]; then
                    generate_vps_keypair
                    test_hint="请将已保存的私钥导入本地 SSH 客户端，新建终端测试连接。"
                else
                    read -rp "按回车键返回主菜单..."
                    return
                fi
            else
                append_key_with_meta "$pub_key" "GitHub: ${gh_user}"
                test_hint="请使用该 GitHub 公钥对应的本地私钥，新建终端测试连接。"
            fi
            ;;
        2)
            generate_vps_keypair
            test_hint="请将已保存的私钥导入本地 SSH 客户端，新建终端测试连接。"
            ;;
        3)
            read -rp "请输入公钥 URL: " key_url
            if [ -z "$key_url" ]; then
                echo -e "${ERROR} URL 不能为空！"
                read -rp "按回车键返回主菜单..."
                return
            fi
            local pub_key
            pub_key=$(curl -fsSL "$key_url")
            if [ -z "$pub_key" ]; then
                echo -e "${ERROR} 从 URL 获取公钥失败！"
                read -rp "按回车键返回主菜单..."
                return
            fi
            append_key_with_meta "$pub_key" "自定义URL"
            test_hint="请使用该公钥对应的本地私钥，新建终端测试连接。"
            ;;
        0) return ;;
        *) 
            echo -e "${ERROR} 无效选项！"
            sleep 1
            return 
            ;;
    esac

    set_sshd_config "PubkeyAuthentication" "yes"
    restart_sshd

    echo -e "\n${CYAN}------------------------------------------------------------${RESET}"
    echo -e "${YELLOW}${BOLD}[重点测试]${RESET} ${test_hint}"
    echo -e "测试成功后，再返回主菜单【禁用密码登录】！"
    echo -e "${CYAN}------------------------------------------------------------${RESET}"
    read -rp "按回车键返回主菜单..."
}

manage_keys_menu() {
    init_ssh_dir
    local auth_file="${HOME}/.ssh/authorized_keys"

    while true; do
        clear
        echo -e "${CYAN}============================================================${RESET}"
        echo -e "${BOLD}${PURPLE}                     SSH 已存公钥管理${RESET}"
        echo -e "${CYAN}============================================================${RESET}"

        local key_lines=()
        local key_contents=()
        local line_num=0

        if [ -f "$auth_file" ]; then
            while IFS= read -r line || [ -n "$line" ]; do
                ((line_num++))
                if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
                    continue
                fi
                key_lines+=("$line_num")
                key_contents+=("$line")
            done < "$auth_file"
        fi

        if [ ${#key_contents[@]} -eq 0 ]; then
            echo -e "\n${WARN} 当前 ${auth_file} 中没有找到任何有效公钥！"
            echo -e "${CYAN}============================================================${RESET}"
            read -rp "按回车键返回主菜单..."
            return
        fi

        # 表头：居中排版与上下对齐
        printf " %-4s | %-19s | %-8s | %-16s\n" "序号" "      添加时间" "公钥类型" "    备注来源"
        echo -e "${CYAN}------------------------------------------------------------${RESET}"

        local idx=1
        for key in "${key_contents[@]}"; do
            local add_time="历史存量/未标记"
            local key_tag="未知/手动导入"

            if [[ "$key" =~ \[([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2})\|([^\]]+)\] ]]; then
                add_time="${BASH_REMATCH[1]}"
                key_tag="${BASH_REMATCH[2]}"
            fi

            local key_type
            key_type=$(echo "$key" | awk '{print $1}')

            # 数据行：竖线与表头严格对齐，文字居中输出
            printf " ${GREEN}[%2d]${RESET} | ${YELLOW}%19s${RESET} | ${CYAN}%-8s${RESET} | ${PURPLE}%-16s${RESET}\n" "$idx" "$add_time" "$key_type" "$key_tag"
            ((idx++))
        done

        echo -e "${CYAN}============================================================${RESET}"
        echo -e " 输入 ${RED}[序号]${RESET} : 删除指定公钥"
        echo -e " 输入 ${RED}[all]${RESET}  : 清空全部公钥"
        echo -e " 输入 ${GREEN}[0]${RESET}    : 返回主菜单"
        echo -e "${CYAN}============================================================${RESET}"
        read -rp "请输入操作指令: " key_action

        if [ "$key_action" == "0" ]; then
            return
        elif [ "$key_action" == "all" ]; then
            read -rp "确认要清空所有公钥吗？(y/N): " confirm_all
            if [[ "$confirm_all" =~ ^[Yy]$ ]]; then
                > "$auth_file"
                echo -e "${INFO} 已清空所有公钥！"
                sleep 1
                return
            fi
        elif [[ "$key_action" =~ ^[0-9]+$ ]] && [ "$key_action" -ge 1 ] && [ "$key_action" -le "${#key_contents[@]}" ]; then
            local target_idx=$((key_action - 1))
            local target_line_num="${key_lines[$target_idx]}"
            
            read -rp "确认删除序号 [${key_action}] 的公钥吗？(y/N): " confirm_del
            if [[ "$confirm_del" =~ ^[Yy]$ ]]; then
                sed -i "${target_line_num}d" "$auth_file"
                chmod 600 "$auth_file"
                echo -e "${INFO} ${GREEN}序号 [${key_action}] 的公钥已成功删除！${RESET}"
                sleep 1
            fi
        else
            echo -e "${ERROR} 输入无效，请重新输入！"
            sleep 1
        fi
    done
}

toggle_password_login() {
    local current
    current=$(get_sshd_config_val "PasswordAuthentication" "yes")

    if [[ "${current,,}" == "no" ]]; then
        echo -e "\n当前密码登录已${GREEN}禁用${RESET}。"
        read -rp "是否要恢复密码登录？(y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            set_sshd_config "PasswordAuthentication" "yes"
            restart_sshd
            echo -e "${INFO} 已重新启用密码登录。"

            read -rp "是否需要为当前用户 ($(whoami)) 设置新密码？(y/N): " pwd_confirm
            if [[ "$pwd_confirm" =~ ^[Yy]$ ]]; then
                passwd "$(whoami)"
            fi
        fi
    else
        echo -e "\n${YELLOW}${BOLD}[警告] 禁用密码登录前，请务必确认密钥登录能够成功！${RESET}"
        if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
            echo -e "${CYAN}${BOLD}[提示] 检测到您正在使用 SSH 远程会话，修改后切勿关闭当前窗口，请先新建终端测试连接！${RESET}"
        fi
        read -rp "确认彻底禁用密码登录吗？(y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            set_sshd_config "PasswordAuthentication" "no"
            set_sshd_config "ChallengeResponseAuthentication" "no"
            set_sshd_config "KbdInteractiveAuthentication" "no"
            restart_sshd
            echo -e "${INFO} ${GREEN}密码登录已成功禁用！现在只能通过密钥登录。${RESET}"
        fi
    fi
    read -rp "按回车键返回主菜单..."
}

change_ssh_port() {
    local current_port
    current_port=$(get_sshd_config_val "Port" "22")
    echo -e "\n当前 SSH 端口为: ${CYAN}${current_port}${RESET}"
    if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
        echo -e "${YELLOW}${BOLD}[提示] 检测到您正在使用 SSH 远程会话，修改端口后请勿关闭当前窗口，请先新建终端验证！${RESET}"
    fi
    read -rp "请输入新的 SSH 端口 (1024-65535): " new_port

    if [[ ! "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        echo -e "${ERROR} 端口格式不正确！"
        read -rp "按回车键返回主菜单..."
        return
    fi

    if command -v getenforce &>/dev/null && [ "$(getenforce)" != "Disabled" ]; then
        echo -e "${INFO} 检测到 SELinux 开启，正在申请放行端口 ${new_port}..."
        if command -v semanage &>/dev/null; then
            $SUDO semanage port -a -t ssh_port_t -p tcp "$new_port" 2>/dev/null || \
            $SUDO semanage port -m -t ssh_port_t -p tcp "$new_port" 2>/dev/null
        else
            echo -e "${WARN} 未安装 semanage，如使用 RHEL/CentOS 系系统，可能需要手动配置 SELinux。"
        fi
    fi

    if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
        echo -e "${INFO} 正在向 ufw 防火墙放行端口 ${new_port}/tcp..."
        $SUDO ufw allow "$new_port"/tcp >/dev/null
    elif command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
        echo -e "${INFO} 正在向 firewalld 防火墙放行端口 ${new_port}/tcp..."
        $SUDO firewall-cmd --permanent --add-port="${new_port}/tcp" >/dev/null
        $SUDO firewall-cmd --reload >/dev/null
    fi

    $SUDO sed -i -E '/^\s*Port\s+/d' /etc/ssh/sshd_config
    set_sshd_config "Port" "$new_port"
    
    if restart_sshd; then
        echo -e "${INFO} ${GREEN}SSH 端口已顺利修改为 ${new_port}${RESET}"
        if command -v ss &>/dev/null; then
            echo -e "${INFO} 系统实际监听服务端口状态："
            ss -tulpn | grep ssh || true
        fi
        echo -e "${WARN} 注意：如使用的是阿里云/腾讯云/AWS等，请务必在【云服务器安全组】中开放 TCP ${new_port} 端口！"
    fi

    read -rp "按回车键返回主菜单..."
}

# ---------------------------------------------------------------
# 主逻辑与 CLI 命令行解析
# ---------------------------------------------------------------
check_dependencies

OVERWRITE=0
while getopts "og:u:f:p:d" OPT; do
    case $OPT in
        o) OVERWRITE=1 ;;
        g) 
            init_ssh_dir
            [ "$OVERWRITE" == "1" ] && > "${HOME}/.ssh/authorized_keys"
            PUB_KEY=$(curl -fsSL "https://github.com/${OPTARG}.keys")
            [ -z "$PUB_KEY" ] && echo -e "${ERROR} 获取 GitHub 公钥失败" && exit 1
            append_key_with_meta "$PUB_KEY" "GitHub: ${OPTARG}"
            set_sshd_config "PubkeyAuthentication" "yes"
            restart_sshd
            exit 0
            ;;
        u)
            init_ssh_dir
            [ "$OVERWRITE" == "1" ] && > "${HOME}/.ssh/authorized_keys"
            PUB_KEY=$(curl -fsSL "${OPTARG}")
            [ -z "$PUB_KEY" ] && echo -e "${ERROR} 从 URL 获取公钥失败" && exit 1
            append_key_with_meta "$PUB_KEY" "自定义URL"
            set_sshd_config "PubkeyAuthentication" "yes"
            restart_sshd
            exit 0
            ;;
        f)
            init_ssh_dir
            [ "$OVERWRITE" == "1" ] && > "${HOME}/.ssh/authorized_keys"
            if [ -f "${OPTARG}" ]; then
                PUB_KEY=$(cat "${OPTARG}")
                append_key_with_meta "$PUB_KEY" "本地文件导入"
                set_sshd_config "PubkeyAuthentication" "yes"
                restart_sshd
            else
                echo -e "${ERROR} 找不到公钥文件 ${OPTARG}" && exit 1
            fi
            exit 0
            ;;
        d)
            set_sshd_config "PasswordAuthentication" "no"
            set_sshd_config "ChallengeResponseAuthentication" "no"
            set_sshd_config "KbdInteractiveAuthentication" "no"
            restart_sshd
            exit 0
            ;;
        p)
            $SUDO sed -i -E '/^\s*Port\s+/d' /etc/ssh/sshd_config
            set_sshd_config "Port" "$OPTARG"
            restart_sshd
            exit 0
            ;;
        *) exit 1 ;;
    esac
done

while true; do
    clear
    show_status
    echo -e " ${GREEN}1.${RESET} 配置/添加 SSH 密钥"
    echo -e " ${GREEN}2.${RESET} 开启/禁用 密码登录"
    echo -e " ${GREEN}3.${RESET} 修改 SSH 端口"
    echo -e " ${GREEN}4.${RESET} 公钥管理"
    echo -e " ${GREEN}0.${RESET} 退出脚本"
    echo -e "${CYAN}============================================================${RESET}"
    read -rp "请输入选项 [0-4]: " choice

    case "$choice" in
        1) install_key_menu ;;
        2) toggle_password_login ;;
        3) change_ssh_port ;;
        4) manage_keys_menu ;;
        0) echo -e "\n感谢使用！"; exit 0 ;;
        *) echo -e "${ERROR} 无效选项，请重新选择！"; sleep 1 ;;
    esac
done