#!/usr/bin/env bash
set -euo pipefail

export LANG=en_US.UTF-8

if [[ "${M_UI_INSTALL_TEST_MODE:-0}" == "1" ]]; then
    INSTALL_ROOT="${INSTALL_ROOT:-/etc/mui}"
    BINARY_PATH="${BINARY_PATH:-${INSTALL_ROOT}/m-ui}"
    ENV_FILE="${ENV_FILE:-${INSTALL_ROOT}/m-ui.env}"
    SERVICE_NAME="${SERVICE_NAME:-m-ui}"
    SERVICE_FILE="${SERVICE_FILE:-/etc/systemd/system/${SERVICE_NAME}.service}"
else
    INSTALL_ROOT="/etc/mui"
    BINARY_PATH="${INSTALL_ROOT}/m-ui"
    ENV_FILE="${INSTALL_ROOT}/m-ui.env"
    SERVICE_NAME="m-ui"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
fi
RELEASE_REPO="${RELEASE_REPO:-mack-a/m-ui-preview}"
RELEASE_BASE_URL="${RELEASE_BASE_URL:-https://github.com/${RELEASE_REPO}/releases}"
GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com/repos/${RELEASE_REPO}}"
AUTHOR_NAME="${AUTHOR_NAME:-mack-a}"
PORT_MIN="${PORT_MIN:-20000}"
PORT_MAX="${PORT_MAX:-60000}"
INSTALL_TMP_DIR=""

echoContent() {
    local color="${1:-}"
    local message="${2:-}"
    local code=""

    case "${color}" in
    "red")
        code="31"
        ;;
    "skyBlue")
        code="1;36"
        ;;
    "green")
        code="32"
        ;;
    "white")
        code="37"
        ;;
    "yellow")
        code="33"
        ;;
    esac

    if [[ -n "${code}" ]]; then
        printf "\033[%sm%b \033[0m\n" "${code}" "${message}"
    else
        printf "%b\n" "${message}"
    fi
}

is_installed() {
    [[ -f "${BINARY_PATH}" ]]
}

has_service_file() {
    [[ -f "${SERVICE_FILE}" ]]
}

service_is_running() {
    command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "${SERVICE_NAME}"
}

read_listen_addr() {
    if [[ -f "${ENV_FILE}" ]]; then
        grep -E '^M_UI_ADDR=' "${ENV_FILE}" | tail -1 | cut -d= -f2- || true
    fi
}

read_listen_port() {
    local listen_addr
    listen_addr="$(read_listen_addr)"
    if [[ "${listen_addr}" == *:* ]]; then
        echo "${listen_addr##*:}"
    fi
}

read_installed_version() {
    if [[ -f "${INSTALL_ROOT}/.release-version" ]]; then
        head -1 "${INSTALL_ROOT}/.release-version"
    fi
}

detect_server_ip() {
    local ip_value
    if [[ "${M_UI_INSTALL_TEST_MODE:-0}" == "1" && -n "${M_UI_INSTALL_SERVER_IP:-}" ]]; then
        echo "${M_UI_INSTALL_SERVER_IP}"
        return
    fi

    if command -v curl >/dev/null 2>&1; then
        ip_value="$(curl -fsS --max-time 3 https://api.ipify.org 2>/dev/null || true)"
        if [[ -n "${ip_value}" ]]; then
            echo "${ip_value}"
            return
        fi
        ip_value="$(curl -fsS --max-time 3 https://ifconfig.me/ip 2>/dev/null || true)"
        if [[ -n "${ip_value}" ]]; then
            echo "${ip_value}"
            return
        fi
    fi

    if command -v hostname >/dev/null 2>&1; then
        ip_value="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
        if [[ -n "${ip_value}" ]]; then
            echo "${ip_value}"
            return
        fi
    fi

    if command -v ip >/dev/null 2>&1; then
        ip_value="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}' || true)"
        if [[ -n "${ip_value}" ]]; then
            echo "${ip_value}"
            return
        fi
    fi

    echo "127.0.0.1"
}

service_status_label() {
    if ! is_installed; then
        echo "未安装"
    elif service_is_running; then
        echo "运行中"
    elif has_service_file; then
        echo "已安装，未启动"
    else
        echo "已安装，服务配置缺失"
    fi
}

show_status() {
    local status listen_addr version server_ip
    status="$(service_status_label)"
    listen_addr="$(read_listen_addr)"
    version="$(read_installed_version)"
    server_ip="$(detect_server_ip)"

    echoContent skyBlue "\n========================================"
    echoContent skyBlue "m-ui 管理脚本"
    echoContent yellow "作者: ${AUTHOR_NAME}"
    echoContent skyBlue "========================================"
    echoContent yellow "服务状态: ${status}"

    if is_installed; then
        echoContent yellow "安装目录: ${INSTALL_ROOT}"
        if [[ -n "${listen_addr}" ]]; then
            echoContent yellow "监听地址: http://${server_ip}:${listen_addr##*:}"
        fi
        if [[ -n "${version}" ]]; then
            echoContent yellow "安装版本: ${version}"
        fi
    fi
    echoContent skyBlue "----------------------------------------"
}

pause_after_action() {
    echo
    read -r -p "按回车键返回菜单..."
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echoContent red "请使用 root 用户执行，或使用 sudo 运行本脚本"
        exit 1
    fi
}

require_command() {
    local command_name="$1"
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echoContent red "缺少必要命令: ${command_name}"
        exit 1
    fi
}

require_linux_systemd() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        echoContent red "本脚本仅支持 Linux 系统"
        exit 1
    fi
    require_command systemctl
    if [[ ! -d /run/systemd/system ]]; then
        echoContent red "本脚本仅支持 systemd 系统"
        exit 1
    fi
}

detect_asset_arch() {
    local machine
    machine="$(uname -m)"
    case "${machine}" in
    x86_64 | amd64)
        echo "amd64"
        ;;
    aarch64 | arm64 | armv7l | armv6l)
        echoContent red "检测到 ARM 架构 ${machine}，当前版本暂不支持 ARM 安装" >&2
        exit 1
        ;;
    *)
        echoContent red "无法识别或暂不支持的 CPU 架构: ${machine}" >&2
        exit 1
        ;;
    esac
}

require_install_commands() {
    require_command curl
    require_command tar
    require_command chmod
    require_command ss
    require_command grep
    require_command cut
    require_command head
    require_command mktemp
    require_command awk
    require_command seq
    require_command install
}

run_preflight_checks() {
    require_root
    require_linux_systemd
    require_install_commands
}

resolve_version() {
    if [[ -n "${VERSION:-}" ]]; then
        echo "${VERSION}"
        return
    fi

    local response
    if ! response="$(curl -fsSL "${GITHUB_API_URL}/releases/latest")"; then
        echoContent red "GitHub API 请求失败: ${GITHUB_API_URL}/releases/latest" >&2
        exit 1
    fi
    printf "%s\n" "${response}" | grep -E '"tag_name":' | head -1 | cut -d'"' -f4
}

download_release_package() {
    local version="$1"
    local arch="$2"
    local target_dir="$3"
    local asset_name="m-ui_linux_${arch}.tar.gz"
    local url="${RELEASE_BASE_URL}/download/${version}/${asset_name}"
    local package_path="${target_dir}/${asset_name}"

    echoContent skyBlue "下载 m-ui ${version}: ${asset_name}" >&2
    if ! curl -fL --connect-timeout 15 --retry 3 -o "${package_path}" "${url}"; then
        echoContent red "下载失败: ${url}" >&2
        exit 1
    fi
    echo "${package_path}"
}

extract_release_binary() {
    local package_path="$1"
    local target_dir="$2"
    if ! tar -xzf "${package_path}" -C "${target_dir}" m-ui; then
        echoContent red "解压失败: ${package_path}"
        exit 1
    fi
    chmod +x "${target_dir}/m-ui"
}

port_is_available() {
    local port="$1"
    ! ss -ltn | awk '{print $4}' | grep -Eq "[:.]${port}$"
}

random_port_candidate() {
    shuf -i "${PORT_MIN}-${PORT_MAX}" -n 1 2>/dev/null || echo $((PORT_MIN + (((RANDOM << 1) ^ RANDOM) % (PORT_MAX - PORT_MIN + 1))))
}

generate_random_port() {
    local port
    local _
    for _ in $(seq 1 30); do
        port="$(random_port_candidate)"
        if port_is_available "${port}"; then
            echo "${port}"
            return
        fi
    done
    echoContent red "无法生成可用随机端口"
    exit 1
}

create_runtime_dirs() {
    mkdir -p "${INSTALL_ROOT}/data" "${INSTALL_ROOT}/config" "${INSTALL_ROOT}/logs" "${INSTALL_ROOT}/core" "${INSTALL_ROOT}/backups"
}

write_env_file() {
    local port="$1"
    local public_ip
    public_ip="$(detect_server_ip)"
    cat >"${ENV_FILE}" <<EOF
M_UI_ROOT=${INSTALL_ROOT}
M_UI_ADDR=0.0.0.0:${port}
M_UI_PUBLIC_IP=${public_ip}
EOF
}

write_service_file() {
    mkdir -p "$(dirname "${SERVICE_FILE}")"
    cat >"${SERVICE_FILE}" <<EOF
[Unit]
Description=m-ui admin service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=${ENV_FILE}
WorkingDirectory=${INSTALL_ROOT}
ExecStart=${BINARY_PATH}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
}

write_installed_version() {
    local version="$1"
    echo "${version}" >"${INSTALL_ROOT}/.release-version"
}

print_service_diagnostics() {
    echoContent red "m-ui 服务启动失败，状态如下:"
    systemctl status "${SERVICE_NAME}" --no-pager -l || true
    journalctl -u "${SERVICE_NAME}" --no-pager -n 50 || true
}

cleanup_tmp_dir() {
    if [[ -n "${INSTALL_TMP_DIR}" ]]; then
        rm -rf "${INSTALL_TMP_DIR}"
    fi
}

firewall_port_token() {
    local port="$1"
    if [[ "${port}" == *:* ]]; then
        echo "${port/:/-}"
    else
        echo "${port}"
    fi
}

allow_firewall_port() {
    local port="$1"
    local type="${2:-tcp}"
    local firewall_port ufw_status
    firewall_port="$(firewall_port_token "${port}")"

    if command -v ufw >/dev/null 2>&1; then
        ufw_status="$(ufw status 2>/dev/null || true)"
        if echo "${ufw_status}" | grep -q "Status: active"; then
            if echo "${ufw_status}" | grep -qw "${port}/${type}"; then
                echoContent yellow "防火墙端口已开放: ${port}/${type}"
            else
                ufw allow "${port}/${type}"
                echoContent green "已开放防火墙端口: ${port}/${type}"
            fi
            return
        fi
    fi

    if command -v systemctl >/dev/null 2>&1 &&
        command -v firewall-cmd >/dev/null 2>&1 &&
        systemctl status firewalld 2>/dev/null | grep -q "active (running)"; then
        if firewall-cmd --list-ports --permanent 2>/dev/null | grep -qw "${firewall_port}/${type}"; then
            echoContent yellow "防火墙端口已开放: ${port}/${type}"
        else
            firewall-cmd --zone=public --add-port="${firewall_port}/${type}" --permanent
            firewall-cmd --reload
            echoContent green "已开放防火墙端口: ${port}/${type}"
        fi
        return
    fi

    if command -v systemctl >/dev/null 2>&1 &&
        command -v iptables >/dev/null 2>&1 &&
        command -v netfilter-persistent >/dev/null 2>&1 &&
        systemctl status netfilter-persistent 2>/dev/null | grep -q "active (exited)"; then
        if iptables -L 2>/dev/null | grep -q "${port}/${type}(mack-a)"; then
            echoContent yellow "防火墙端口已开放: ${port}/${type}"
        else
            iptables -I INPUT -p "${type}" --dport "${port}" -m comment --comment "allow ${port}/${type}(mack-a)" -j ACCEPT
            netfilter-persistent save
            echoContent green "已开放防火墙端口: ${port}/${type}"
        fi
        return
    fi

    echoContent yellow "未检测到已启用的系统防火墙，跳过端口开放"
}

confirm_yes_no() {
    local prompt="$1"
    local input
    echoContent red "${prompt}"
    while true; do
        read -r -p "是否继续？[y/n]: " input
        case "${input}" in
        y | Y)
            return 0
            ;;
        n | N)
            return 1
            ;;
        *)
            echoContent yellow "请输入 y 或 n"
            ;;
        esac
    done
}

clear_install_root_except_binary() {
    local entry
    shopt -s dotglob nullglob
    for entry in "${INSTALL_ROOT}"/*; do
        if [[ "${entry}" == "${BINARY_PATH}" ]]; then
            continue
        fi
        rm -rf "${entry}"
    done
    shopt -u dotglob nullglob
}

install_mui() {
    run_preflight_checks
    if is_installed; then
        echoContent yellow "检测到 m-ui 已安装，已跳过安装"
        return
    fi

    local arch version package_path port
    arch="$(detect_asset_arch)"
    version="$(resolve_version)"
    if [[ -z "${version}" ]]; then
        echoContent red "无法获取 Release 版本"
        exit 1
    fi

    INSTALL_TMP_DIR="$(mktemp -d)"
    trap cleanup_tmp_dir EXIT

    package_path="$(download_release_package "${version}" "${arch}" "${INSTALL_TMP_DIR}")"
    extract_release_binary "${package_path}" "${INSTALL_TMP_DIR}"

    mkdir -p "${INSTALL_ROOT}"
    create_runtime_dirs
    install -m 0755 "${INSTALL_TMP_DIR}/m-ui" "${BINARY_PATH}"

    port="$(generate_random_port)"
    write_env_file "${port}"
    write_service_file
    write_installed_version "${version}"

    systemctl daemon-reload
    systemctl enable --now "${SERVICE_NAME}"
    if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
        print_service_diagnostics
        exit 1
    fi

    allow_firewall_port "${port}" "tcp"
    echoContent green "m-ui 安装完成"
    echoContent yellow "访问地址: http://$(detect_server_ip):${port}"
}

restart_mui() {
    require_root
    require_linux_systemd
    if ! is_installed; then
        echoContent red "m-ui 未安装"
        return
    fi
    if ! has_service_file; then
        echoContent red "m-ui 服务配置缺失: ${SERVICE_FILE}"
        return
    fi
    systemctl restart "${SERVICE_NAME}"
    if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
        print_service_diagnostics
        return
    fi
    echoContent green "m-ui 重启完成"
}

stop_mui() {
    require_root
    require_linux_systemd
    if ! is_installed; then
        echoContent red "m-ui 未安装"
        return
    fi
    if ! has_service_file; then
        echoContent red "m-ui 服务配置缺失: ${SERVICE_FILE}"
        return
    fi
    systemctl stop "${SERVICE_NAME}"
    echoContent green "m-ui 已停止"
}

reset_mui() {
    local port
    require_root
    require_linux_systemd
    require_command ss
    if ! is_installed; then
        echoContent red "m-ui 未安装"
        return
    fi
    if ! confirm_yes_no "重置会删除所有 m-ui 数据、配置、日志、core 和备份，仅保留二进制和 systemd 配置。"; then
        echoContent yellow "已取消重置"
        return
    fi

    port="$(read_listen_port)"
    if [[ -z "${port}" ]]; then
        port="$(generate_random_port)"
    fi

    systemctl stop "${SERVICE_NAME}" >/dev/null 2>&1 || true
    clear_install_root_except_binary
    create_runtime_dirs
    write_env_file "${port}"
    if ! has_service_file; then
        write_service_file
    fi
    systemctl daemon-reload
    systemctl restart "${SERVICE_NAME}"
    if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
        print_service_diagnostics
        return
    fi
    allow_firewall_port "${port}" "tcp"
    echoContent green "m-ui 重置完成"
}

uninstall_mui() {
    require_root
    require_linux_systemd
    if ! is_installed; then
        echoContent red "m-ui 未安装"
        return
    fi
    if ! confirm_yes_no "卸载会停止服务并删除 /etc/mui/ 下的所有数据，此操作不可恢复。"; then
        echoContent yellow "已取消卸载"
        return
    fi

    systemctl stop "${SERVICE_NAME}" >/dev/null 2>&1 || true
    systemctl disable "${SERVICE_NAME}" >/dev/null 2>&1 || true
    rm -f "${SERVICE_FILE}"
    rm -rf "${INSTALL_ROOT}"
    systemctl daemon-reload
    echoContent green "m-ui 卸载完成"
}

show_menu() {
    show_status
    if is_installed; then
        echoContent white "1. 重启 m-ui"
        echoContent white "2. 停止 m-ui"
        echoContent white "3. 重置 m-ui"
        echoContent white "4. 卸载 m-ui"
        echoContent white "0. 退出"
        read -r -p "请输入编号选择: " menu
        case "${menu}" in
        1) restart_mui ;;
        2) stop_mui ;;
        3) reset_mui ;;
        4) uninstall_mui ;;
        0) exit 0 ;;
        *) echoContent red "选择错误，请重新选择" ;;
        esac
    else
        echoContent white "1. 安装 m-ui"
        echoContent white "0. 退出"
        read -r -p "请输入编号选择: " menu
        case "${menu}" in
        1) install_mui ;;
        0) exit 0 ;;
        *) echoContent red "选择错误，请重新选择" ;;
        esac
    fi
    pause_after_action
    show_menu
}

main() {
    show_menu
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
