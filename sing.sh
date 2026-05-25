#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="${CONFIG_DIR}/config.json"
SERVICE_NAME="sing-box"
CLIENT_CONFIG_FILE="${CONFIG_DIR}/client.txt"
OFFLINE_PACK="/root/sing-box.tar.gz"
BIN_TMP_DIR="/tmp/sing-box-offline"

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}请使用 root 权限执行此脚本！${RESET}"
        exit 1
    fi
}

check_offline_pkg() {
    if [ ! -f "${OFFLINE_PACK}" ]; then
        echo -e "${RED}离线包不存在！请将 sing-box.tar.gz 放置到 /root 目录下${RESET}"
        exit 1
    fi
}

is_sing_box_installed() {
    command -v sing-box &> /dev/null
}

is_sing_box_running() {
    systemctl is-active --quiet "${SERVICE_NAME}"
}

check_ss_command() {
    if ! command -v ss &> /dev/null; then
        apt-get update && apt-get install -y iproute2 || yum install -y iproute || dnf install -y iproute || pacman -Sy --noconfirm iproute2 || zypper install -y iproute2 || {
            echo -e "${RED}无法安装 iproute2${RESET}"
            exit 1
        }
    fi
}

generate_unused_port() {
    while true; do
        port=$(shuf -i 1025-65535 -n 1)
        if ! ss -tuln | grep -q ":$port "; then
            echo $port
            return
        fi
    done
}

offline_install_bin() {
    rm -rf "${BIN_TMP_DIR}"
    mkdir -p "${BIN_TMP_DIR}"
    tar -zxf "${OFFLINE_PACK}" -C "${BIN_TMP_DIR}" || { echo -e "${RED}解压失败${RESET}"; exit 1; }
    SING_BIN=$(find "${BIN_TMP_DIR}" -name "sing-box" -type f)
    [ -z "${SING_BIN}" ] && { echo -e "${RED}未找到二进制文件${RESET}"; exit 1; }
    cp -f "${SING_BIN}" /usr/local/bin/
    chmod +x /usr/local/bin/sing-box
    command -v sing-box &> /dev/null || { echo -e "${RED}部署失败${RESET}"; exit 1; }
    rm -rf "${BIN_TMP_DIR}"
}

install_sing_box() {
    check_offline_pkg
    offline_install_bin
    check_ss_command

    # 仅保留兼容的协议端口
    anytls_port=$(generate_unused_port)
    shadowsocks_port=$(generate_unused_port)
    hysteria2_port=$(generate_unused_port)
    trojan_port=$(generate_unused_port)
    tuic_port=$(generate_unused_port)
    http_port=$(generate_unused_port)
    socks_port=$(generate_unused_port)
    naive_port=$(generate_unused_port)

    # 生成密钥
    ss_password=$(sing-box generate rand 16 --base64)
    password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
    trojan_password=$(sing-box generate rand 16 --base64)
    tuic_password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
    tuic_uuid=$(sing-box generate uuid)
    naive_username=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
    naive_password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
    http_username=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
    http_password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
    socks_username=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
    socks_password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
    uuid=$(sing-box generate uuid)
    reality_output=$(sing-box generate reality-keypair)
    private_key=$(echo "${reality_output}" | grep -oP 'PrivateKey:\s*\K.*')
    public_key=$(echo "${reality_output}" | grep -oP 'PublicKey:\s*\K.*')

    mkdir -p "${CONFIG_DIR}"
    openssl ecparam -genkey -name prime256v1 -out "${CONFIG_DIR}/key.pem" || exit 1
    openssl req -new -x509 -days 3650 -key "${CONFIG_DIR}/key.pem" -out "${CONFIG_DIR}/cert.pem" -subj "/CN=bing.com" || exit 1

    host_ip=$(curl -s -m3 https://api.ipify.org || hostname -I | awk '{print $1}')
    [ -z "${host_ip}" ] && host_ip="127.0.0.1"
    ip_country="Server"

    # 配置文件（已移除所有报错协议）
    cat > "${CONFIG_FILE}" << EOF
{
    "log": {"level": "info", "timestamp": true},
    "inbounds": [
        {
            "type": "anytls",
            "tag": "anytls-in",
            "listen": "::",
            "listen_port": ${anytls_port},
            "users": [{"password": "${public_key}"}],
            "tls": {"enabled": true, "certificate_path": "${CONFIG_DIR}/cert.pem", "key_path": "${CONFIG_DIR}/key.pem"}
        },
        {
            "type": "shadowsocks",
            "tag": "shadowsocks-in",
            "listen": "::",
            "listen_port": ${shadowsocks_port},
            "method": "2022-blake3-aes-128-gcm",
            "password": "${ss_password}",
            "multiplex": {"enabled": true}
        },
        {
            "type": "hysteria2",
            "tag": "hysteria2-in",
            "listen": "::",
            "listen_port": ${hysteria2_port},
            "users": [{"password": "${password}"}],
            "masquerade": "https://bing.com",
            "tls": {"enabled": true, "alpn": ["h3"], "certificate_path": "${CONFIG_DIR}/cert.pem", "key_path": "${CONFIG_DIR}/key.pem"}
        },
        {
            "type": "trojan",
            "tag": "trojan-in",
            "listen": "::",
            "listen_port": ${trojan_port},
            "users": [{"password": "${trojan_password}"}],
            "tls": {"enabled": true, "certificate_path": "${CONFIG_DIR}/cert.pem", "key_path": "${CONFIG_DIR}/key.pem"}
        },
        {
            "type": "tuic",
            "tag": "tuic-in",
            "listen": "::",
            "listen_port": ${tuic_port},
            "users": [{"uuid": "${tuic_uuid}", "password": "${tuic_password}"}],
            "congestion_control": "cubic",
            "tls": {"enabled": true, "certificate_path": "${CONFIG_DIR}/cert.pem", "key_path": "${CONFIG_DIR}/key.pem"}
        },
        {
            "type": "http",
            "tag": "http-in",
            "listen": "::",
            "listen_port": ${http_port},
            "users": [{"username": "${http_username}", "password": "${http_password}"}],
            "tls": {"enabled": true, "certificate_path": "${CONFIG_DIR}/cert.pem", "key_path": "${CONFIG_DIR}/key.pem"}
        },
        {
            "type": "socks",
            "tag": "socks-in",
            "listen": "::",
            "listen_port": ${socks_port},
            "users": [{"username": "${socks_username}", "password": "${socks_password}"}]
        },
        {
            "type": "naive",
            "tag": "naive-in",
            "listen": "::",
            "listen_port": ${naive_port},
            "users": [{"username": "${naive_username}", "password": "${naive_password}"}],
            "tls": {"enabled": true, "certificate_path": "${CONFIG_DIR}/cert.pem", "key_path": "${CONFIG_DIR}/key.pem"}
        }
    ],
    "outbounds": [{"type": "direct", "tag": "direct"}]
}
EOF

    cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Sing-Box Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/sing-box run -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}"
    systemctl start "${SERVICE_NAME}"

    if ! is_sing_box_running; then
        echo -e "${RED}服务启动失败！执行 'journalctl -u sing-box' 查看日志${RESET}"
        exit 1
    fi

    {
cat << EOF
- name: ${ip_country}
  type: anytls
  server: ${host_ip}
  port: ${anytls_port}
  password: ${public_key}
  tls: true
  servername: www.bing.com
  skip-cert-verify: true

- name: ${ip_country}
  type: ss
  server: ${host_ip}
  port: ${shadowsocks_port}
  cipher: 2022-blake3-aes-128-gcm
  password: ${ss_password}
  udp: true

- name: ${ip_country}
  type: hysteria2
  server: ${host_ip}
  port: ${hysteria2_port}
  password: ${password}
  alpn:
    - h3
  sni: www.bing.com
  skip-cert-verify: true
  fast-open: true
  udp: true

- name: ${ip_country}
  type: trojan
  server: ${host_ip}
  port: ${trojan_port}
  password: ${trojan_password}
  tls: true
  servername: www.bing.com
  skip-cert-verify: true
  udp: true

- name: ${ip_country}
  type: tuic
  server: ${host_ip}
  port: ${tuic_port}
  uuid: ${tuic_uuid}
  password: ${tuic_password}
  tls: true
  servername: www.bing.com
  skip-cert-verify: true
  congestion-control: cubic
  udp: true

- name: ${ip_country}
  type: http
  server: ${host_ip}
  port: ${http_port}
  username: ${http_username}
  password: ${http_password}
  tls: true
  servername: www.bing.com
  skip-cert-verify: true

- name: ${ip_country}
  type: socks5
  server: ${host_ip}
  port: ${socks_port}
  username: ${socks_username}
  password: ${socks_password}
  udp: true

- name: ${ip_country}
  type: naive
  server: ${host_ip}
  port: ${naive_port}
  username: ${naive_username}
  password: ${naive_password}
  tls: true
  servername: www.bing.com
  skip-cert-verify: true
EOF
echo "hy2://${password}@${host_ip}:${hysteria2_port}?insecure=1&sni=www.bing.com#${ip_country}"
echo "trojan://${trojan_password}@${host_ip}:${trojan_port}?security=tls&sni=www.bing.com&allowInsecure=1#${ip_country}"
echo "tuic://${tuic_uuid}:${tuic_password}@${host_ip}:${tuic_port}?congestion_control=cubic&tls=1&sni=www.bing.com&insecure=1#${ip_country}"
echo "anytls://${public_key}@${host_ip}:${anytls_port}?security=tls&sni=www.bing.com&allowInsecure=1&type=tcp#${ip_country}"
    } > "${CLIENT_CONFIG_FILE}"

    echo -e "${GREEN}Sing-Box 安装完成，服务已启动！${RESET}"
    cat "${CLIENT_CONFIG_FILE}"
}

uninstall_sing_box() {
    read -p "$(echo -e "${RED}确定卸载？(Y/n) ${RESET}")" choice
    choice=${choice:-Y}
    if [[ $choice =~ ^[Yy]$ ]]; then
        systemctl stop "${SERVICE_NAME}" 2>/dev/null
        systemctl disable "${SERVICE_NAME}" 2>/dev/null
        rm -f /etc/systemd/system/${SERVICE_NAME}.service
        rm -rf "${CONFIG_DIR}"
        rm -f /usr/local/bin/sing-box
        systemctl daemon-reload
        echo -e "${GREEN}卸载完成${RESET}"
    fi
}

start_sing_box() { systemctl start "${SERVICE_NAME}" && echo -e "${GREEN}服务已启动${RESET}" || echo -e "${RED}启动失败${RESET}"; }
stop_sing_box() { systemctl stop "${SERVICE_NAME}" && echo -e "${GREEN}服务已停止${RESET}" || echo -e "${RED}停止失败${RESET}"; }
restart_sing_box() { systemctl restart "${SERVICE_NAME}" && echo -e "${GREEN}服务已重启${RESET}" || echo -e "${RED}重启失败${RESET}"; }
status_sing_box() { systemctl status "${SERVICE_NAME}"; }
log_sing_box() { journalctl -u sing-box --output cat -f; }
check_sing_box() { [ -f "${CLIENT_CONFIG_FILE}" ] && cat "${CLIENT_CONFIG_FILE}" || echo -e "${YELLOW}配置文件不存在${RESET}"; }

show_menu() {
    clear
    is_sing_box_installed
    sing_box_installed=$?
    is_sing_box_running
    sing_box_running=$?

    echo -e "${GREEN}=== sing-box 离线管理工具 ===${RESET}"
    echo -e "安装状态: $(if [ ${sing_box_installed} -eq 0 ]; then echo -e "${GREEN}已安装${RESET}"; else echo -e "${RED}未安装${RESET}"; fi)"
    echo -e "运行状态: $(if [ ${sing_box_running} -eq 0 ]; then echo -e "${GREEN}已运行${RESET}"; else echo -e "${RED}未运行${RESET}"; fi)"
    echo ""
    echo "1. 离线安装 sing-box 服务"
    echo "2. 卸载 sing-box 服务"
    if [ ${sing_box_installed} -eq 0 ]; then
        if [ ${sing_box_running} -eq 0 ]; then
            echo "3. 停止 sing-box 服务"
        else
            echo "3. 启动 sing-box 服务"
        fi
        echo "4. 重启 sing-box 服务"
        echo "5. 查看 sing-box 状态"
        echo "6. 查看 sing-box 日志"
        echo "7. 查看 sing-box 配置"
    fi
    echo "0. 退出"
    echo -e "${GREEN}=========================${RESET}"
    read -p "请输入选项编号 (0-7): " choice
    echo ""
}

trap 'echo -e "${RED}已取消操作${RESET}"; exit' INT

check_root
while true; do
    show_menu
    case "${choice}" in
    1) [ ${sing_box_installed} -eq 0 ] && echo -e "${YELLOW}已安装！${RESET}" || install_sing_box ;;
    2) [ ${sing_box_installed} -eq 0 ] && uninstall_sing_box || echo -e "${YELLOW}未安装！${RESET}" ;;
    3) if [ ${sing_box_installed} -eq 0 ]; then [ ${sing_box_running} -eq 0 ] && stop_sing_box || start_sing_box; else echo -e "${RED}未安装！${RESET}"; fi ;;
    4) [ ${sing_box_installed} -eq 0 ] && restart_sing_box || echo -e "${RED}未安装！${RESET}" ;;
    5) [ ${sing_box_installed} -eq 0 ] && status_sing_box || echo -e "${RED}未安装！${RESET}" ;;
    6) [ ${sing_box_installed} -eq 0 ] && log_sing_box || echo -e "${RED}未安装！${RESET}" ;;
    7) [ ${sing_box_installed} -eq 0 ] && check_sing_box || echo -e "${RED}未安装！${RESET}" ;;
    0) echo -e "${GREEN}已退出${RESET}"; exit 0 ;;
    *) echo -e "${RED}无效选项${RESET}" ;;
    esac
    read -p "按 Enter 键继续..."
done
