#!/bin/bash

# =====================================
#  SSH PORT CHANGER
#  Developer: Eiro.tf
# =====================================

CONFIG_FILE="/etc/ssh/sshd_config"

RED="\e[31m"
GREEN="\e[32m"
CYAN="\e[36m"
YELLOW="\e[33m"
RESET="\e[0m"

clear_screen() { clear; }

header() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════╗"
    echo "║        SSH PORT CHANGER           ║"
    echo "║        Developer: Eiro.tf         ║"
    echo "╚══════════════════════════════════╝"
    echo -e "${RESET}"
}

pause() { read -rp "Press Enter to continue..."; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Please run as root${RESET}"
        exit 1
    fi
}

get_current_port() {
    PORT=$(grep -E "^Port " "$CONFIG_FILE" | awk '{print $2}')
    [[ -z "$PORT" ]] && PORT="22"
    echo "$PORT"
}

enable_ufw_port() {
    ufw allow "$1/tcp" >/dev/null
    echo -e "${GREEN}✔ UFW: Enabled port $1${RESET}"
}

disable_ufw_port() {
    ufw delete allow "$1/tcp" >/dev/null 2>&1
    echo -e "${YELLOW}✖ UFW: Disabled old port $1${RESET}"
}

show_current_port() {
    clear_screen
    header
    echo -e "${GREEN}🔍 Current SSH Port: ${YELLOW}$(get_current_port)${RESET}"
    pause
}

change_ssh_port() {
    clear_screen
    header

    OLD_PORT=$(get_current_port)

    read -rp "Enter new SSH port: " NEW_PORT

    if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || [[ "$NEW_PORT" -lt 1 || "$NEW_PORT" -gt 65535 ]]; then
        echo -e "${RED}❌ Invalid port number${RESET}"
        pause
        return
    fi

    if [[ "$NEW_PORT" == "$OLD_PORT" ]]; then
        echo -e "${YELLOW}⚠ New port is same as current port${RESET}"
        pause
        return
    fi

    cp "$CONFIG_FILE" "$CONFIG_FILE.bak"

    if grep -q "^Port " "$CONFIG_FILE"; then
        sed -i "s/^Port .*/Port $NEW_PORT/" "$CONFIG_FILE"
    else
        echo "Port $NEW_PORT" >> "$CONFIG_FILE"
    fi

    echo -e "${GREEN}✔ SSH config updated${RESET}"

    if command -v ufw >/dev/null 2>&1; then
        enable_ufw_port "$NEW_PORT"
        disable_ufw_port "$OLD_PORT"
        ufw reload >/dev/null
        echo -e "${GREEN}✔ UFW rules updated${RESET}"
    else
        echo -e "${YELLOW}⚠ UFW not detected. Firewall not modified${RESET}"
    fi

    systemctl restart ssh 2>/dev/null || systemctl restart sshd

    echo -e "${GREEN}🔁 SSH restarted successfully${RESET}"
    echo -e "${YELLOW}⚠ Do NOT close this session until you test the new port${RESET}"
    pause
}

menu() {
    while true; do
        clear_screen
        header
        echo -e "${CYAN}1️⃣  Change SSH Port"
        echo "2️⃣  See Current SSH Port"
        echo "0️⃣  Exit${RESET}"
        echo
        read -rp "Select an option: " choice

        case $choice in
            1) change_ssh_port ;;
            2) show_current_port ;;
            0)
                echo -e "${GREEN}👋 Exiting... Powered by Eiro.tf${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Invalid option${RESET}"
                sleep 1
                ;;
        esac
    done
}

check_root
menu
