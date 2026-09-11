#!/usr/bin/env bash
#=============================================================
# SSH Security Installer (key.sh)
# Multi-distro: Debian/Ubuntu, RHEL/CentOS/Fedora/Rocky/Alma,
#               Alpine, Arch/Manjaro, openSUSE
#=============================================================


RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"
BLUE="\033[34m"; PURPLE="\033[35m"; CYAN="\033[36m"
GRAY="\033[90m"; BOLD="\033[1m"; RESET="\033[0m"

INFO="${GREEN}[INFO]${RESET}"; WARN="${YELLOW}[WARN]${RESET}"; ERROR="${RED}[ERROR]${RESET}"

JAIL_CONF="/etc/fail2ban/jail.local"
LOG_FILE="/var/log/fail2ban.log"
TARGET_JAIL="sshd"

[ "$EUID" -ne 0 ] && SUDO="sudo" || SUDO=""

PKG_MGR=""; INIT_SYS=""; SSH_LOG=""; OS_NAME=""; OS_ID=""; OS_VER=""; OS_SHORT=""

# ============ 命令行帮助 ============
case "${1:-}" in
    -h|--help)
        cat <<HELP
SSH Security Installer

用法:
  $0 [选项]

交互模式:
  直接运行 $0 进入交互式菜单

命令行模式:
  -g <用户名>    从 GitHub 拉取公钥
  -u <URL>       从自定义 URL 拉取公钥
  -f <文件>      从本地文件导入公钥
  -p <端口>      修改 SSH 端口
  -d             禁用密码登录
  -o             覆盖模式（清空已存公钥）

其他:
  -h, --help     显示帮助
HELP
        exit 0 ;;
esac

# ============ 能力检测 ============
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="${NAME:-Unknown}"; OS_ID="${ID:-unknown}"; OS_VER="${VERSION_ID:-}"
    else
        OS_NAME=$(uname -s); OS_VER=$(uname -r); OS_ID="unknown"
    fi
    case "$OS_ID" in
        debian) OS_SHORT="Debian" ;;
        ubuntu) OS_SHORT="Ubuntu" ;;
        linuxmint) OS_SHORT="Linux Mint" ;;
        kali) OS_SHORT="Kali" ;;
        rhel) OS_SHORT="RHEL" ;;
        centos) OS_SHORT="CentOS" ;;
        fedora) OS_SHORT="Fedora" ;;
        rocky) OS_SHORT="Rocky" ;;
        almalinux) OS_SHORT="AlmaLinux" ;;
        ol) OS_SHORT="Oracle Linux" ;;
        amzn) OS_SHORT="Amazon Linux" ;;
        alpine) OS_SHORT="Alpine" ;;
        arch) OS_SHORT="Arch" ;;
        manjaro) OS_SHORT="Manjaro" ;;
        endeavouros) OS_SHORT="EndeavourOS" ;;
        opensuse*) OS_SHORT="openSUSE" ;;
        sles) OS_SHORT="SLES" ;;
        *)
            local first="${OS_ID:0:1}"
            OS_SHORT="$(echo "$first" | tr '[:lower:]' '[:upper:]')${OS_ID:1}"
            ;;
    esac
}

detect_pkg_mgr() {
    for pm in apt dnf yum zypper pacman apk; do
        command -v "$pm" &>/dev/null && { PKG_MGR="$pm"; return; }
    done
    PKG_MGR="unknown"
}

detect_init() {
    if [ -d /run/systemd/system ]; then INIT_SYS="systemd"
    elif [ -d /run/openrc ]; then INIT_SYS="openrc"
    elif [ -x /sbin/init ]; then INIT_SYS="sysvinit"
    else INIT_SYS="unknown"; fi
}

detect_ssh_log() {
    case "$OS_ID" in
        debian|ubuntu|linuxmint|kali) SSH_LOG="/var/log/auth.log" ;;
        rhel|centos|fedora|rocky|almalinux|ol|amzn) SSH_LOG="/var/log/secure" ;;
        alpine) SSH_LOG="/var/log/messages" ;;
        arch|manjaro|endeavouros) SSH_LOG="/var/log/auth.log" ;;
        opensuse*|sles) SSH_LOG="/var/log/messages" ;;
        *) SSH_LOG="/var/log/auth.log" ;;
    esac
}

# ============ 服务管理抽象 ============
svc_start()  { case "$INIT_SYS" in systemd) $SUDO systemctl start "$1" 2>/dev/null;; openrc) $SUDO rc-service "$1" start 2>/dev/null;; sysvinit) $SUDO service "$1" start 2>/dev/null;; esac; }
svc_stop()   { case "$INIT_SYS" in systemd) $SUDO systemctl stop "$1" 2>/dev/null;; openrc) $SUDO rc-service "$1" stop 2>/dev/null;; sysvinit) $SUDO service "$1" stop 2>/dev/null;; esac; }
svc_restart(){ case "$INIT_SYS" in systemd) $SUDO systemctl restart "$1" 2>/dev/null;; openrc) $SUDO rc-service "$1" restart 2>/dev/null;; sysvinit) $SUDO service "$1" restart 2>/dev/null;; esac; }
svc_enable() { case "$INIT_SYS" in systemd) $SUDO systemctl enable "$1" 2>/dev/null;; openrc) $SUDO rc-update add "$1" default 2>/dev/null;; sysvinit) $SUDO update-rc.d "$1" defaults 2>/dev/null || chkconfig "$1" on 2>/dev/null;; esac; }
svc_disable(){ case "$INIT_SYS" in systemd) $SUDO systemctl disable "$1" 2>/dev/null;; openrc) $SUDO rc-update del "$1" default 2>/dev/null;; sysvinit) $SUDO update-rc.d -f "$1" remove 2>/dev/null || chkconfig "$1" off 2>/dev/null;; esac; }

# ============ 包管理抽象 ============
pkg_install() {
    case "$PKG_MGR" in
        apt) $SUDO apt-get update -qq && $SUDO apt-get install -y "$@" ;;
        dnf) $SUDO dnf install -y "$@" ;;
        yum) $SUDO yum install -y "$@" ;;
        zypper) $SUDO zypper --non-interactive install "$@" ;;
        pacman) $SUDO pacman -Sy --noconfirm "$@" ;;
        apk) $SUDO apk add --no-cache "$@" ;;
        *) echo -e "${ERROR} 未知包管理器"; return 1 ;;
    esac
}
pkg_remove() {
    case "$PKG_MGR" in
        apt) $SUDO apt-get remove --purge -y "$@"; $SUDO apt-get autoremove -y ;;
        dnf) $SUDO dnf remove -y "$@" ;;
        yum) $SUDO yum remove -y "$@" ;;
        zypper) $SUDO zypper --non-interactive remove "$@" ;;
        pacman) $SUDO pacman -R --noconfirm "$@" ;;
        apk) $SUDO apk del "$@" ;;
        *) return 1 ;;
    esac
}

# ============ SSH 配置管理 ============
get_sshd_config_val() {
    local key="$1" default_val="$2" file="/etc/ssh/sshd_config"
    local val=""

    # 1. 主文件
    if [ -f "$file" ]; then
        val=$(grep -iE "^[[:space:]]*${key}[[:space:]=]+" "$file" | tail -n 1 | \
              sed -E 's/^[[:space:]]*[^[:space:]=]+[[:space:]=]+//' | awk '{print $1}')
    fi

    # 2. sshd_config.d 目录（主文件未设置时读取）
    if [ -z "$val" ] && [ -d "/etc/ssh/sshd_config.d" ]; then
        for conf in /etc/ssh/sshd_config.d/*.conf; do
            [ -f "$conf" ] || continue
            val=$(grep -iE "^[[:space:]]*${key}[[:space:]=]+" "$conf" | tail -n 1 | \
                  sed -E 's/^[[:space:]]*[^[:space:]=]+[[:space:]=]+//' | awk '{print $1}')
            [ -n "$val" ] && break
        done
    fi

    [ -n "$val" ] && { echo "$val"; return; }
    echo "$default_val"
}

set_sshd_config() {
    local param="$1" value="$2" file="/etc/ssh/sshd_config"
    if [ -d "/etc/ssh/sshd_config.d" ]; then
        for conf in /etc/ssh/sshd_config.d/*.conf; do
            [ -f "$conf" ] && $SUDO sed -i -E "s/^[[:space:]]*#?[[:space:]]*(${param})[[:space:]=].*/# \1 (disabled by key.sh)/" "$conf"
        done
    fi
    $SUDO sed -i -E "/^[[:space:]]*#?[[:space:]]*(${param})[[:space:]=]/d" "$file"
    echo "${param} ${value}" | $SUDO tee -a "$file" > /dev/null
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
    local restart_ok=1
    if [ "$INIT_SYS" = "systemd" ]; then
        if systemctl list-unit-files 2>/dev/null | grep -q "ssh.socket"; then
            echo -e "${INFO} 检测到 systemd ssh.socket，正在强制关闭并屏蔽 (mask)..."
            $SUDO systemctl stop ssh.socket &>/dev/null
            $SUDO systemctl disable ssh.socket &>/dev/null
            $SUDO systemctl mask ssh.socket &>/dev/null
        fi
        $SUDO systemctl daemon-reload &>/dev/null
        local ssh_unit=""
        if systemctl list-unit-files 2>/dev/null | grep -q "^ssh.service"; then
            ssh_unit="ssh"
        elif systemctl list-unit-files 2>/dev/null | grep -q "^sshd.service"; then
            ssh_unit="sshd"
        fi
        if [ -n "$ssh_unit" ]; then
            svc_enable "$ssh_unit"
            svc_restart "$ssh_unit" && restart_ok=0
        else
            echo -e "${ERROR} 未找到 ssh.service 或 sshd.service！"
        fi
    elif [ "$INIT_SYS" = "openrc" ]; then
        svc_restart sshd && restart_ok=0
    else
        svc_restart sshd 2>/dev/null && restart_ok=0
        if [ "$restart_ok" -ne 0 ]; then
            svc_restart ssh 2>/dev/null && restart_ok=0
        fi
    fi

    if [ "$restart_ok" -eq 0 ]; then
        echo -e "${INFO} ${GREEN}SSH 服务重启成功！${RESET}"
        return 0
    else
        echo -e "${ERROR} SSH 服务重启失败，请检查配置文件！"
        return 1
    fi
}

# ============ 依赖安装 ============
check_dependencies() {
    local pkgs=()
    for dep in curl ssh-keygen awk; do
        command -v "$dep" &>/dev/null && continue
        case "$dep" in
            curl) pkgs+=("curl") ;;
            ssh-keygen) case "$PKG_MGR" in apt) pkgs+=("openssh-client");; dnf|yum) pkgs+=("openssh-clients");; apk) pkgs+=("openssh-client");; pacman) pkgs+=("openssh");; zypper) pkgs+=("openssh");; esac ;;
            awk) command -v gawk &>/dev/null && continue; pkgs+=("gawk") ;;
        esac
    done
    [ ${#pkgs[@]} -gt 0 ] && { echo -e "${WARN} 正在安装依赖: ${pkgs[*]}"; pkg_install "${pkgs[@]}"; }
}

init_ssh_dir() {
    mkdir -p "${HOME}/.ssh"; chmod 700 "${HOME}/.ssh"
    touch "${HOME}/.ssh/authorized_keys"; chmod 600 "${HOME}/.ssh/authorized_keys"
}

append_key_with_meta() {
    local pub_content="$1" source_tag="$2" auth_file="${HOME}/.ssh/authorized_keys"
    local ts; ts=$(date "+%Y-%m-%d %H:%M:%S")
    init_ssh_dir
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        line=$(echo "$line" | sed -e 's/[[:space:]]*$//')
        local core_key; core_key=$(echo "$line" | awk '{print $1, $2}')
        [ -z "$core_key" ] && continue
        if grep -qF "$core_key" "$auth_file" 2>/dev/null; then
            echo -e "${WARN} 该公钥已经存在于 authorized_keys 中，已跳过重复追加。"
            continue
        fi
        echo "${core_key} [${ts}|${source_tag}]" >> "$auth_file"
        echo -e "${INFO} ${GREEN}已成功追加公钥 (${source_tag})${RESET}"
    done <<< "$pub_content"
    chmod 600 "$auth_file"
}

# 统计 authorized_keys 中有效公钥数量
count_authorized_keys() {
    local auth_file="${HOME}/.ssh/authorized_keys"
    if [ -f "$auth_file" ]; then
        awk '!/^[[:space:]]*(#|$)/{c++} END{print c+0}' "$auth_file"
    else
        echo "0"
    fi
}

# ============ Fail2Ban ============
get_f2b_conf() {
    local key=$1
    [ -f "$JAIL_CONF" ] && sed -n "/^\[${TARGET_JAIL}\]/,/^\[/p" "$JAIL_CONF" | \
        grep "^${key}[[:space:]]*=" | tail -n 1 | awk -F'=' '{print $2}' | tr -d ' '
}

set_f2b_conf() {
    local key=$1 val=$2
    [ ! -f "$JAIL_CONF" ] && { touch "$JAIL_CONF"; echo "[$TARGET_JAIL]" > "$JAIL_CONF"; }
    if sed -n "/^\[${TARGET_JAIL}\]/,/^\[/p" "$JAIL_CONF" | grep -q "^${key}[[:space:]]*="; then
        sed -i "/^\[${TARGET_JAIL}\]/,/^\[/ s/^${key}[[:space:]]*=.*/${key} = ${val}/" "$JAIL_CONF"
    else
        sed -i "/^\[${TARGET_JAIL}\]/a ${key} = ${val}" "$JAIL_CONF"
    fi
}

restart_f2b() {
    echo -e "${INFO} 正在重载 Fail2Ban 配置..."
    svc_restart fail2ban
    for i in {1..5}; do
        if fail2ban-client ping >/dev/null 2>&1; then
            echo -e "${INFO} ${GREEN}成功！配置已生效。${RESET}"; return 0
        fi; sleep 1
    done
    echo -e "${ERROR} Fail2Ban 重启超时或失败。"
    echo -e "${YELLOW}请手动运行 'journalctl -u fail2ban -n 50' 排查错误。${RESET}"
}

get_fail2ban_status() {
    if command -v fail2ban-client >/dev/null 2>&1 && fail2ban-client ping >/dev/null 2>&1; then
        local count
        count=$(fail2ban-client status "$TARGET_JAIL" 2>/dev/null | grep -i "Currently banned" | awk '{print $NF}')
        echo -e "${GREEN}防护中 (已封禁${count:-0} IP)${RESET}"
    elif command -v fail2ban-client >/dev/null 2>&1; then
        echo -e "${YELLOW}已安装 / 已停止${RESET}"
    else
        echo -e "${YELLOW}未安装${RESET}"
    fi
}

fmt_f2b_unit() {
    local val=$1 type=$2
    if [[ "$val" =~ ^[0-9]+$ ]]; then
        [ "$type" == "time" ] && echo "${val}秒" || { [ "$type" == "factor" ] && echo "${val}倍" || echo "$val"; }
    else echo "$val"; fi
}

validate_time() { [[ "$1" =~ ^[0-9]+[smhdw]?$ ]]; }
validate_int() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; }

generate_default_jail_conf() {
    local backend="auto"
    [ "$INIT_SYS" = "systemd" ] && backend="systemd"
    local ssh_filter="sshd"
    [ "$OS_ID" = "alpine" ] && ssh_filter="alpine-sshd"
    local banaction="iptables-multiport"
    if ! command -v iptables &>/dev/null && command -v nft &>/dev/null; then
        banaction="nftables-multiport"
    fi
    cat <<EOF2
[DEFAULT]
backend = ${backend}

[${TARGET_JAIL}]
enabled = true
port = ssh
filter = ${ssh_filter}
logpath = ${SSH_LOG}
maxretry = 5
bantime = 600
findtime = 3600
bantime.increment = true
bantime.factor = 2
bantime.maxtime = 7d
banaction = ${banaction}
ignoreip = 127.0.0.1/8
EOF2
}

check_f2b_install() {
    hash -r 2>/dev/null
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        echo -e "${WARN} 未检测到 Fail2Ban 服务。"
        read -rp "是否立即安装 Fail2Ban？(y/N): " install_confirm
        [[ ! "$install_confirm" =~ ^[Yy]$ ]] && { echo -e "${WARN} 已取消安装。"; return 1; }

        echo -e "${INFO} 正在安装 Fail2Ban 及相关依赖..."
        local f2b_pkgs=()
        case "$PKG_MGR" in
            apt) f2b_pkgs=("fail2ban" "python3-systemd" "rsyslog");;
            dnf|yum) f2b_pkgs=("fail2ban" "rsyslog");;
            zypper) f2b_pkgs=("fail2ban" "rsyslog");;
            pacman) f2b_pkgs=("fail2ban");;
            apk) f2b_pkgs=("fail2ban");;
        esac
        pkg_install "${f2b_pkgs[@]}"
        [ ! -f "$SSH_LOG" ] && { $SUDO touch "$SSH_LOG"; svc_enable rsyslog 2>/dev/null; svc_start rsyslog 2>/dev/null; }
        [ ! -f "$JAIL_CONF" ] && generate_default_jail_conf > "$JAIL_CONF"
        [ "$INIT_SYS" = "systemd" ] && $SUDO systemctl unmask fail2ban &>/dev/null || true
        svc_enable fail2ban; svc_start fail2ban
        echo -e "${INFO} ${GREEN}Fail2Ban 安装并启动完成！${RESET}"; sleep 1; return 0
    fi

    if [ ! -f "$JAIL_CONF" ]; then
        generate_default_jail_conf > "$JAIL_CONF"
    else
        if ! grep -q "^\[DEFAULT\]" "$JAIL_CONF"; then
            local be="auto"; [ "$INIT_SYS" = "systemd" ] && be="systemd"
            sed -i "1i [DEFAULT]\nbackend = ${be}" "$JAIL_CONF"
        fi
        if ! grep -q "^\[${TARGET_JAIL}\]" "$JAIL_CONF"; then
            generate_default_jail_conf | grep -A99 "^\[${TARGET_JAIL}\]" >> "$JAIL_CONF"
        else
            local defaults=(
                "enabled=true" "port=ssh" "filter=sshd" "maxretry=5"
                "bantime=600" "findtime=3600"
                "bantime.increment=true" "bantime.factor=2" "bantime.maxtime=7d"
            )
            for item in "${defaults[@]}"; do
                local k="${item%%=*}" v="${item#*=}"
                sed -n "/^\[${TARGET_JAIL}\]/,/^\[/p" "$JAIL_CONF" | grep -q "^${k}[[:space:]]*=" || set_f2b_conf "$k" "$v"
            done
        fi
    fi
    return 0
}

uninstall_f2b() {
    echo -e "\n${RED}${BOLD}警告：即将卸载 Fail2Ban 及其配置！${RESET}"
    read -rp "确认卸载吗？(y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo -e "${INFO} 已取消卸载。"; read -rp "按回车键继续..."; return; }
    svc_stop fail2ban; svc_disable fail2ban
    pkg_remove fail2ban
    read -rp "是否同时删除配置目录 /etc/fail2ban ？(y/N): " del_conf
    [[ "$del_conf" =~ ^[Yy]$ ]] && { $SUDO rm -rf /etc/fail2ban; echo -e "${INFO} 已删除 /etc/fail2ban"; }
    echo -e "${INFO} ${GREEN}Fail2Ban 卸载完成。${RESET}"; read -rp "按回车键继续..."
}

change_f2b_param() {
    local name=$1 key=$2 type=$3
    local current; current=$(get_f2b_conf "$key")
    echo -e "\n${INFO} 正在修改: ${CYAN}${name}${RESET}"
    echo -e "当前值: ${GREEN}$(fmt_f2b_unit "$current" "$type")${RESET}"
    [ "$type" == "time" ] && echo -e "${GRAY}(支持后缀: s=秒, m=分, h=小时, d=天)${RESET}"
    while true; do
        read -rp "请输入新值 (留空取消): " new_val
        [ -z "$new_val" ] && return
        if [ "$type" == "time" ] && validate_time "$new_val"; then break; fi
        if [ "$type" == "int" ] && validate_int "$new_val"; then break; fi
        if [ "$type" == "factor" ] && validate_int "$new_val"; then break; fi
        echo -e "${ERROR} 格式错误，请重试。"
    done
    set_f2b_conf "$key" "$new_val"; restart_f2b
}

toggle_f2b_service() {
    echo -e "\n${CYAN}------------------- 服务开关 -------------------${RESET}"
    if fail2ban-client ping >/dev/null 2>&1; then
        read -rp "是否停止并禁用 Fail2Ban? (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] && { svc_stop fail2ban; svc_disable fail2ban; echo -e "${WARN} 服务已停止。${RESET}"; }
    else
        read -rp "是否启用并启动 Fail2Ban? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            svc_enable fail2ban; svc_start fail2ban
            for i in {1..5}; do
                if fail2ban-client ping >/dev/null 2>&1; then echo -e "${INFO} ${GREEN}服务已成功启动。${RESET}"; read -rp "按回车键继续..."; return; fi; sleep 1
            done
            echo -e "${ERROR} 启动失败或超时。"
        fi
    fi
    read -rp "按回车键继续..."
}

unban_f2b_ip() {
    echo -e "\n${CYAN}------------------ 手动解封 IP ------------------${RESET}"
    local banned_list
    banned_list=$(fail2ban-client status "$TARGET_JAIL" 2>/dev/null | grep "Banned IP list" | awk -F':' '{print $2}' | sed 's/^[ \t]*//')
    [ -z "$banned_list" ] && banned_list="无"
    echo -e "当前被封禁列表: ${YELLOW}${banned_list}${RESET}"
    read -rp "输入要解封的 IP (留空取消): " target_ip; [ -z "$target_ip" ] && return
    $SUDO fail2ban-client set "$TARGET_JAIL" unbanip "$target_ip"
    [ $? -eq 0 ] && echo -e "${INFO} ${GREEN}解封成功: $target_ip${RESET}" || echo -e "${ERROR} 操作失败。"
    read -rp "按回车键继续..."
}

add_f2b_whitelist() {
    echo -e "\n${CYAN}------------------ 白名单管理 ------------------${RESET}"
    local current_list; current_list=$(get_f2b_conf "ignoreip")
    echo -e "当前白名单: ${YELLOW}${current_list:-继承全局或无}${RESET}"
    local current_ip; current_ip=$(echo "$SSH_CLIENT" | awk '{print $1}')
    read -rp "输入要放行的 IP (回车默认当前连接 IP: ${current_ip:-无}): " input_ip
    [ -z "$input_ip" ] && input_ip="$current_ip"
    [ -z "$input_ip" ] && echo -e "${ERROR} 无法获取 IP。" && return
    if echo "$current_list" | grep -Fq "$input_ip"; then
        echo -e "${WARN} 该 IP 已在白名单中。"
    else
        if [ -z "$current_list" ]; then set_f2b_conf "ignoreip" "$input_ip"
        else set_f2b_conf "ignoreip" "$current_list $input_ip"; fi
        restart_f2b
    fi
    read -rp "按回车键继续..."
}

view_f2b_logs() {
    clear
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${BOLD}${PURPLE}                 Fail2Ban 审计日志 (最近 20 条)${RESET}"
    echo -e "${CYAN}============================================================${RESET}"
    if [ ! -f "$LOG_FILE" ]; then
        echo -e "${WARN} 日志文件不存在: $LOG_FILE"
    else
        local out
        out=$(grep -E "(Ban|Unban)" "$LOG_FILE" 2>/dev/null | tail -n 20)
        if [ -z "$out" ]; then
            echo -e "${WARN} 暂无封禁/解封记录${RESET}"
        else
            echo "$out" | awk '{
                gsub(/Unban/, "\033[32m&\033[0m");
                gsub(/Ban/, "\033[31m&\033[0m");
                print
            }'
        fi
    fi
    echo -e "${CYAN}============================================================${RESET}"
    read -rp "按回车键返回..."
}

menu_f2b_exponential() {
    while true; do
        clear
        local inc fac max
        inc=$(get_f2b_conf "bantime.increment")
        fac=$(get_f2b_conf "bantime.factor")
        max=$(get_f2b_conf "bantime.maxtime")
        local S_INC; [ "$inc" == "true" ] && S_INC="${GREEN}启用${RESET}" || S_INC="${YELLOW}禁用${RESET}"
        echo -e "${CYAN}============================================================${RESET}"
        echo -e "${BOLD}${PURPLE}            高级: 指数封禁设置 (针对 sshd)${RESET}"
        echo -e "${CYAN}============================================================${RESET}"
        echo -e " 说明: 对重复犯错的恶意 IP，封禁时间按设定系数成倍递增"
        echo -e "${CYAN}------------------------------------------------------------${RESET}"
        echo -e "  ${GREEN}1.${RESET} 递增模式开关   [${S_INC}]"
        echo -e "  ${GREEN}2.${RESET} 增长系数       [${YELLOW}${fac:-未设置}${RESET}]$(fmt_f2b_unit "$fac" "factor")"
        echo -e "  ${GREEN}3.${RESET} 封禁上限       [${YELLOW}${max:-未设置}${RESET}]$(fmt_f2b_unit "$max" "time")"
        echo -e "${CYAN}------------------------------------------------------------${RESET}"
        echo -e "  ${GREEN}0.${RESET} 返回上级"
        echo -e "${CYAN}============================================================${RESET}"
        read -rp "请选择 [0-3]: " sc
        case "$sc" in
            1) [ "$inc" == "true" ] && ns="false" || ns="true"; set_f2b_conf "bantime.increment" "$ns"; restart_f2b ;;
            2) change_f2b_param "增长系数 (倍数)" "bantime.factor" "factor" ;;
            3) change_f2b_param "封禁上限 (时间)" "bantime.maxtime" "time" ;;
            0) return ;;
            *) echo -e "${ERROR} 无效选项！"; sleep 1 ;;
        esac
    done
}

manage_fail2ban_menu() {
    if ! check_f2b_install; then read -rp "按回车键返回主菜单..."; return; fi
    while true; do
        clear
        VAL_MAX=$(get_f2b_conf "maxretry"); VAL_BAN=$(get_f2b_conf "bantime"); VAL_FIND=$(get_f2b_conf "findtime")
        echo -e "${CYAN}============================================================${RESET}"
        echo -e "${BOLD}${PURPLE}                     Fail2Ban 防护管理${RESET}"
        echo -e "${CYAN}============================================================${RESET}"
        echo -e "  服务状态: $(get_fail2ban_status)"
        echo -e "${CYAN}------------------------------------------------------------${RESET}"
        echo -e "  ${GREEN}1.${RESET} 最大重试次数     [${YELLOW}${VAL_MAX:-默认}${RESET}]"
        echo -e "  ${GREEN}2.${RESET} 初始封禁时长     [${YELLOW}${VAL_BAN:-默认}${RESET}]$(fmt_f2b_unit "$VAL_BAN" "time")"
        echo -e "  ${GREEN}3.${RESET} 监测时间窗口     [${YELLOW}${VAL_FIND:-默认}${RESET}]$(fmt_f2b_unit "$VAL_FIND" "time")"
        echo -e "${CYAN}------------------------------------------------------------${RESET}"
        echo -e "  ${GREEN}4.${RESET} 手动解封 IP"
        echo -e "  ${GREEN}5.${RESET} 添加 IP 白名单"
        echo -e "  ${GREEN}6.${RESET} 查看封禁日志 (最近20条)"
        echo -e "  ${GREEN}7.${RESET} 指数递增封禁设置 ->"
        echo -e "${CYAN}------------------------------------------------------------${RESET}"
        echo -e "  ${GREEN}8.${RESET} 启用 / 停止 服务"
        echo -e "  ${GREEN}9.${RESET} 卸载 Fail2Ban"
        echo -e "  ${GREEN}0.${RESET} 返回主菜单"
        echo -e "${CYAN}============================================================${RESET}"
        read -rp "请选择 [0-9]: " choice
        case "$choice" in
            1) change_f2b_param "最大重试次数" "maxretry" "int" ;;
            2) change_f2b_param "初始封禁时长" "bantime" "time" ;;
            3) change_f2b_param "监测时间窗口" "findtime" "time" ;;
            4) unban_f2b_ip ;;
            5) add_f2b_whitelist ;;
            6) view_f2b_logs ;;
            7) menu_f2b_exponential ;;
            8) toggle_f2b_service ;;
            9) uninstall_f2b ;;
            0) return ;;
            *) echo -e "${ERROR} 无效选项！"; sleep 1 ;;
        esac
    done
}

# ============ 状态面板 ============
show_status() {
    local port; port=$(get_sshd_config_val "Port" "22")
    local pwd_auth; pwd_auth=$(get_sshd_config_val "PasswordAuthentication" "yes")
    local pubkey_auth; pubkey_auth=$(get_sshd_config_val "PubkeyAuthentication" "yes")
    local f2b_stat; f2b_stat=$(get_fail2ban_status)
    local key_count; key_count=$(count_authorized_keys)

    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${BOLD}${PURPLE}                     SSH 安全配置工具${RESET}"
    echo -e "${CYAN}============================================================${RESET}"
    echo -e " 系统架构 : ${GREEN}${OS_SHORT} ${OS_VER}${RESET}"
    if [[ "${pubkey_auth,,}" == "yes" ]]; then
        if [ "$key_count" -gt 0 ]; then
            echo -e " 密钥登录 : ${GREEN}已启用 (${key_count} 把公钥)${RESET}"
        else
            echo -e " 密钥登录 : ${YELLOW}已启用 (但无公钥，无法密钥登录)${RESET}"
        fi
    else
        echo -e " 密钥登录 : ${YELLOW}已禁用${RESET}"
    fi
    if [[ "${pwd_auth,,}" == "no" ]]; then
        echo -e " 密码登录 : ${GREEN}已禁用 (PasswordAuthentication no)${RESET}"
    else
        echo -e " 密码登录 : ${YELLOW}已启用 (推荐配置密钥后禁用)${RESET}"
    fi
    echo -e " Fail2Ban : ${f2b_stat}"
    echo -e " SSH 端口 : ${CYAN}${port}${RESET}"
    echo -e "${CYAN}============================================================${RESET}"
}

# ============ 密钥生成 ============
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
    if [ ! -f "${key_file}.pub" ]; then
        echo -e "${ERROR} 密钥生成失败！请检查 $HOME/.ssh 是否可写或磁盘空间是否充足。"
        read -rp "按回车键返回..."
        return 1
    fi
    mv "${key_file}.pub" "$pub_file"

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

# ============ 密钥登录开关 ============
toggle_pubkey_login() {
    local current
    current=$(get_sshd_config_val "PubkeyAuthentication" "yes")

    if [[ "${current,,}" == "no" ]]; then
        echo -e "\n当前密钥登录已${GREEN}禁用${RESET}。"
        local key_count; key_count=$(count_authorized_keys)
        if [ "$key_count" -eq 0 ]; then
            echo -e "${YELLOW}[提示] 当前 authorized_keys 中还没有公钥，启用后仍需先添加公钥才能通过密钥登录。${RESET}"
        fi
        read -rp "是否要启用密钥登录？(y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            set_sshd_config "PubkeyAuthentication" "yes"
            restart_sshd
            echo -e "${INFO} ${GREEN}密钥登录已成功启用。${RESET}"
        fi
    else
        echo -e "\n${YELLOW}${BOLD}[警告] 禁用密钥登录后，如果密码登录也已禁用，你将无法登录 VPS！${RESET}"
        if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
            echo -e "${CYAN}${BOLD}[提示] 检测到您正在使用 SSH 远程会话，修改后切勿关闭当前窗口！${RESET}"
        fi

        local pwd_auth
        pwd_auth=$(get_sshd_config_val "PasswordAuthentication" "yes")
        if [[ "${pwd_auth,,}" == "no" ]]; then
            echo -e "${RED} 检测到密码登录已禁用，禁用密钥登录后你将无法登录此 VPS！${RESET}"
            read -rp "确认仍然要禁用密钥登录吗？(y/N): " confirm_risky
            [[ ! "$confirm_risky" =~ ^[Yy]$ ]] && { echo -e "${INFO} 已取消操作。"; read -rp "按回车键继续..."; return; }
        else
            read -rp "确认禁用密钥登录吗？(y/N): " confirm
            [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo -e "${INFO} 已取消操作。"; read -rp "按回车键继续..."; return; }
        fi

        set_sshd_config "PubkeyAuthentication" "no"
        restart_sshd
        echo -e "${INFO} ${GREEN}密钥登录已禁用，现在只能通过密码登录。${RESET}"
    fi
    read -rp "按回车键继续..."
}

# ============ 密钥配置菜单 ============
install_key_menu() {
    while true; do
        clear
        init_ssh_dir

        # 动态统计当前公钥数量
        local key_count
        key_count=$(count_authorized_keys)
        local key_count_label
        if [ "$key_count" -gt 0 ]; then
            key_count_label=" (${GREEN}${key_count} 把公钥${RESET})"
        else
            key_count_label=" (${YELLOW}无公钥${RESET})"
        fi

        echo -e "${CYAN}============================================================${RESET}"
        echo -e "${BOLD}${PURPLE}                     SSH 密钥登录管理${RESET}"
        echo -e "${CYAN}============================================================${RESET}"
        echo -e "${BOLD}请选择 SSH 密钥配置方式：${RESET}"
        echo -e "  ${GREEN}1.${RESET} 从 GitHub 获取公钥 (${CYAN}适合：已将公钥上传至 GitHub 的用户${RESET})"
        echo -e "  ${GREEN}2.${RESET} 在 VPS 上全新生成密钥 (${CYAN}适合：本地没有密钥的新手，生成后可传 GitHub${RESET})"
        echo -e "  ${GREEN}3.${RESET} 从自定义 URL 获取公钥 (${CYAN}适合：有公钥直链的用户${RESET})"
        echo -e "  ${GREEN}4.${RESET} 管理已存公钥${key_count_label}"
        echo -e "  ${GREEN}5.${RESET} 密钥登录开关"
        echo -e "  ${GREEN}0.${RESET} 返回主菜单"
        echo -e "${CYAN}============================================================${RESET}"
        read -rp "请输入选项 [0-5]: " key_opt

        local test_hint=""
        local do_restart=0

        case "$key_opt" in
            1)
                echo -e "\n${YELLOW}${BOLD}[使用前提]${RESET}"
                echo -e "需先将本地公钥上传至 GitHub: ${CYAN}https://github.com/settings/keys${RESET}\n"
                read -rp "请输入您的 GitHub 用户名: " gh_user
                if [ -z "$gh_user" ]; then
                    echo -e "${ERROR} 输入不能为空！"
                    read -rp "按回车键继续..."
                    continue
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
                        do_restart=1
                    else
                        read -rp "按回车键继续..."
                        continue
                    fi
                else
                    append_key_with_meta "$pub_key" "GitHub: ${gh_user}"
                    test_hint="请使用该 GitHub 公钥对应的本地私钥，新建终端测试连接。"
                    do_restart=1
                fi
                ;;
            2)
                generate_vps_keypair
                test_hint="请将已保存的私钥导入本地 SSH 客户端，新建终端测试连接。"
                do_restart=1
                ;;
            3)
                read -rp "请输入公钥 URL: " key_url
                if [ -z "$key_url" ]; then
                    echo -e "${ERROR} URL 不能为空！"
                    read -rp "按回车键继续..."
                    continue
                fi
                local pub_key
                pub_key=$(curl -fsSL "$key_url")
                if [ -z "$pub_key" ]; then
                    echo -e "${ERROR} 从 URL 获取公钥失败！"
                    read -rp "按回车键继续..."
                    continue
                fi
                append_key_with_meta "$pub_key" "自定义URL"
                test_hint="请使用该公钥对应的本地私钥，新建终端测试连接。"
                do_restart=1
                ;;
            4)
                manage_keys_menu
                continue
                ;;
            5)
                toggle_pubkey_login
                continue
                ;;
            0) return ;;
            *)
                echo -e "${ERROR} 无效选项！"
                sleep 1
                continue
                ;;
        esac

        if [ "$do_restart" == "1" ]; then
            set_sshd_config "PubkeyAuthentication" "yes"
            restart_sshd
            echo -e "\n${CYAN}------------------------------------------------------------${RESET}"
            echo -e "${YELLOW}${BOLD}[重点测试]${RESET} ${test_hint}"
            echo -e "测试成功后，再返回主菜单【禁用密码登录】！"
            echo -e "${CYAN}------------------------------------------------------------${RESET}"
            read -rp "按回车键返回密钥管理子菜单..."
        fi
    done
}

# ============ 已存公钥管理 ============
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
            read -rp "按回车键返回..."
            return
        fi

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

            printf " ${GREEN}[%2d]${RESET} | ${YELLOW}%19s${RESET} | ${CYAN}%-8s${RESET} | ${PURPLE}%-16s${RESET}\n" "$idx" "$add_time" "$key_type" "$key_tag"
            ((idx++))
        done

        echo -e "${CYAN}============================================================${RESET}"
        echo -e " 输入 ${RED}[序号]${RESET} : 删除指定公钥"
        echo -e " 输入 ${RED}[all]${RESET}  : 清空全部公钥"
        echo -e " 输入 ${GREEN}[0]${RESET}    : 返回上级菜单"
        echo -e "${CYAN}============================================================${RESET}"
        read -rp "请输入操作指令: " key_action

        if [ "$key_action" == "0" ]; then
            return
        elif [ "$key_action" == "all" ]; then
            # 危险检查：密码登录已禁用时清空全部公钥会锁死
            if [[ "$(get_sshd_config_val "PasswordAuthentication" "yes")" == "no" ]]; then
                echo -e "${RED}${BOLD}[危险] 密码登录已禁用，清空全部公钥后你将无法登录此 VPS！${RESET}"
                read -rp "确认仍然要清空吗？(y/N): " risky_all
                [[ ! "$risky_all" =~ ^[Yy]$ ]] && continue
            fi
            read -rp "确认要清空所有公钥吗？(y/N): " confirm_all
            if [[ "$confirm_all" =~ ^[Yy]$ ]]; then
                > "$auth_file"
                echo -e "${INFO} 已清空所有公钥！"
                sleep 1
                continue
            fi
        elif [[ "$key_action" =~ ^[0-9]+$ ]] && [ "$key_action" -ge 1 ] && [ "$key_action" -le "${#key_contents[@]}" ]; then
            local target_idx=$((key_action - 1))
            local target_line_num="${key_lines[$target_idx]}"

            # 危险检查：密码登录已禁用 + 只剩最后一个公钥时删除会锁死
            if [[ "$(get_sshd_config_val "PasswordAuthentication" "yes")" == "no" ]] && [ "${#key_contents[@]}" -eq 1 ]; then
                echo -e "${RED}${BOLD}[危险] 密码登录已禁用，删除最后一个公钥后你将无法登录此 VPS！${RESET}"
                read -rp "确认仍然要删除吗？(y/N): " risky_del
                [[ ! "$risky_del" =~ ^[Yy]$ ]] && continue
            fi

            read -rp "确认删除序号 [${key_action}] 的公钥吗？(y/N): " confirm_del
            if [[ "$confirm_del" =~ ^[Yy]$ ]]; then
                sed -i "${target_line_num}d" "$auth_file"
                chmod 600 "$auth_file"
                echo -e "${INFO} ${GREEN}序号 [${key_action}] 的公钥已成功删除！${RESET}"
                sleep 1
                continue
            fi
        else
            echo -e "${ERROR} 输入无效，请重新输入！"
            sleep 1
            continue
        fi
    done
}

# ============ 密码登录开关 ============
toggle_password_login() {
    local current
    current=$(get_sshd_config_val "PasswordAuthentication" "yes")

    if [[ "${current,,}" == "no" ]]; then
        echo -e "\n当前密码登录已${GREEN}禁用${RESET}。"
        read -rp "是否要启用密码登录？(y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            set_sshd_config "PasswordAuthentication" "yes"
            restart_sshd
            echo -e "${INFO} 已成功启用密码登录。"

            read -rp "是否需要为当前用户 ($(whoami)) 设置新密码？(y/N): " pwd_confirm
            if [[ "$pwd_confirm" =~ ^[Yy]$ ]]; then
                passwd "$(whoami)"
            fi
        fi
    else
        echo -e "\n${YELLOW}${BOLD}[警告] 禁用密码登录前，请务必确认密钥登录能够成功！${RESET}"
        # 危险检查：密钥登录不可用时禁用密码登录会锁死
        local pubkey_auth; pubkey_auth=$(get_sshd_config_val "PubkeyAuthentication" "yes")
        local pubkey_ok=0
        if [[ "${pubkey_auth,,}" == "yes" ]] && grep -qE '^(ssh-|ecdsa-)' "${HOME}/.ssh/authorized_keys" 2>/dev/null; then
            pubkey_ok=1
        fi
        if [ "$pubkey_ok" -eq 0 ]; then
            if [[ "${pubkey_auth,,}" != "yes" ]]; then
                echo -e "${RED}${BOLD}[危险] 密钥登录已禁用，禁用密码登录后你将无法登录此 VPS！${RESET}"
            else
                echo -e "${RED}${BOLD}[危险] authorized_keys 中没有任何公钥，禁用密码登录后你将无法登录此 VPS！${RESET}"
            fi
            read -rp "确认仍然要禁用吗？(y/N): " risky_confirm
            [[ ! "$risky_confirm" =~ ^[Yy]$ ]] && { echo -e "${INFO} 已取消操作。"; read -rp "按回车键继续..."; return; }
        fi
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

# ============ 修改 SSH 端口 ============
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
        echo -e "${INFO} 检测到 SELinux 启用，正在申请放行端口 ${new_port}..."
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

    $SUDO sed -i -E '/^[[:space:]]*Port[[:space:]=]/d' /etc/ssh/sshd_config
    set_sshd_config "Port" "$new_port"

    if restart_sshd; then
        echo -e "${INFO} ${GREEN}SSH 端口已顺利修改为 ${new_port}${RESET}"

        # 同步更新 Fail2Ban 端口
        if [ -f "$JAIL_CONF" ] && grep -q "^\[${TARGET_JAIL}\]" "$JAIL_CONF"; then
            set_f2b_conf "port" "$new_port"
            if command -v fail2ban-client &>/dev/null && fail2ban-client ping >/dev/null 2>&1; then
                echo -e "${INFO} 正在同步更新 Fail2Ban 防护端口..."
                restart_f2b
            fi
        fi

        if command -v ss &>/dev/null; then
            echo -e "${INFO} 系统实际监听服务端口状态："
            ss -tulpn | grep ssh || true
        fi
        echo -e "${WARN} 注意：如使用的是阿里云/腾讯云/AWS等，请务必在【云服务器安全组】中开放 TCP ${new_port} 端口！"
    fi

    read -rp "按回车键返回主菜单..."
}

# ============ 主逻辑 ============
detect_os; detect_pkg_mgr; detect_init; detect_ssh_log
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
            exit 0 ;;
        u)
            init_ssh_dir
            [ "$OVERWRITE" == "1" ] && > "${HOME}/.ssh/authorized_keys"
            PUB_KEY=$(curl -fsSL "${OPTARG}")
            [ -z "$PUB_KEY" ] && echo -e "${ERROR} 从 URL 获取公钥失败" && exit 1
            append_key_with_meta "$PUB_KEY" "自定义URL"
            set_sshd_config "PubkeyAuthentication" "yes"
            restart_sshd
            exit 0 ;;
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
            exit 0 ;;
        d)
            if ! grep -qE '^(ssh-|ecdsa-)' "${HOME}/.ssh/authorized_keys" 2>/dev/null || \
               [[ "$(get_sshd_config_val "PubkeyAuthentication" "yes")" != "yes" ]]; then
                echo -e "${ERROR} 密钥登录不可用（未启用或无公钥），禁用密码登录将导致你无法登录！"
                read -rp "确认仍然执行？(y/N): " confirm
                [[ ! "$confirm" =~ ^[Yy]$ ]] && exit 1
            fi
            set_sshd_config "PasswordAuthentication" "no"
            set_sshd_config "ChallengeResponseAuthentication" "no"
            set_sshd_config "KbdInteractiveAuthentication" "no"
            restart_sshd
            exit 0 ;;
        p)
            $SUDO sed -i -E '/^[[:space:]]*Port[[:space:]=]/d' /etc/ssh/sshd_config
            set_sshd_config "Port" "$OPTARG"
            if restart_sshd; then
                if [ -f "$JAIL_CONF" ] && grep -q "^\[${TARGET_JAIL}\]" "$JAIL_CONF"; then
                    set_f2b_conf "port" "$OPTARG"
                    command -v fail2ban-client &>/dev/null && fail2ban-client ping >/dev/null 2>&1 && restart_f2b
                fi
            fi
            exit 0 ;;
        *) exit 1 ;;
    esac
done

while true; do
    clear
    show_status
    echo -e " ${GREEN}1.${RESET} 密钥登录管理"
    echo -e " ${GREEN}2.${RESET} 密码登录开关"
    echo -e " ${GREEN}3.${RESET} Fail2Ban防护"
    echo -e " ${GREEN}4.${RESET} SSH 端口修改"
    echo -e " ${GREEN}0.${RESET} 退出脚本"
    echo -e "${CYAN}============================================================${RESET}"
    read -rp "请输入选项 [0-4]: " choice

    case "$choice" in
        1) install_key_menu ;;
        2) toggle_password_login ;;
        3) manage_fail2ban_menu ;;
        4) change_ssh_port ;;
        0) echo -e "\n感谢使用！"; exit 0 ;;
        *) echo -e "${ERROR} 无效选项，请重新选择！"; sleep 1 ;;
    esac
done