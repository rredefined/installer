bash <<'EOF'
set -e

MOTD_FILE="/etc/profile.d/renderbyte-motd.sh"

echo "[+] Installing RenderByte MOTD to: $MOTD_FILE"

cat > "$MOTD_FILE" <<'MOTD'
#!/bin/bash
# -------- RenderByte MOTD (Colored + Animated + Stats + ISP + VPS Type) --------
[[ $- != *i* ]] && return

# Colors (RenderByte vibe)
C_RESET="\e[0m"
C_BOLD="\e[1m"
C_DIM="\e[2m"

C_BLUE="\e[38;5;39m"
C_CYAN="\e[38;5;51m"
C_WHITE="\e[97m"
C_GRAY="\e[38;5;245m"
C_GREEN="\e[38;5;82m"
C_YELLOW="\e[38;5;226m"
C_RED="\e[38;5;196m"

spinner() {
  local msg="$1"
  local spin='-\|/'
  echo -ne "${C_CYAN}${msg}${C_RESET} "
  for i in {1..10}; do
    echo -ne "${C_CYAN}${msg}${C_RESET} ${C_BLUE}${spin:i%4:1}${C_RESET}\r"
    sleep 0.06
  done
  echo -ne "${C_CYAN}${msg}${C_RESET} ${C_GREEN}done${C_RESET}\n"
}

clear
spinner "Initializing RenderByte Environment"
spinner "Fetching system statistics"

# OS
OS=$(lsb_release -ds 2>/dev/null || awk -F= '/^PRETTY_NAME=/{gsub(/"/,"",$2);print $2}' /etc/os-release)

# CPU + cores
CPU=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')
CORES=$(nproc)

# RAM / Disk
RAM_USED=$(free -h | awk '/Mem:/ {print $3}')
RAM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')

# IP/Host/Uptime
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
HOST=$(hostname)
UPTIME=$(uptime -p 2>/dev/null)

# CPU usage %
read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
prev_idle=$((idle + iowait))
prev_total=$((user + nice + system + idle + iowait + irq + softirq + steal))
sleep 0.2
read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
idle_now=$((idle + iowait))
total_now=$((user + nice + system + idle + iowait + irq + softirq + steal))
diff_idle=$((idle_now - prev_idle))
diff_total=$((total_now - prev_total))
CPU_PCT=$(( (1000 * (diff_total - diff_idle) / diff_total + 5) / 10 ))
LOAD=$(cat /proc/loadavg 2>/dev/null | awk '{print $1" "$2" "$3}')

# Network usage since boot
IFACE=$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')
if [[ -z "$IFACE" ]]; then
  IFACE=$(ls /sys/class/net 2>/dev/null | grep -E '^(eth|ens|enp|venet)' | head -n1)
fi

RX_B=0
TX_B=0
if [[ -n "$IFACE" && -r "/sys/class/net/$IFACE/statistics/rx_bytes" ]]; then
  RX_B=$(cat "/sys/class/net/$IFACE/statistics/rx_bytes")
  TX_B=$(cat "/sys/class/net/$IFACE/statistics/tx_bytes")
fi

human_bytes() {
  local b=$1
  awk -v b="$b" 'BEGIN{
    split("B KB MB GB TB PB",u," ");
    i=1;
    while (b>=1024 && i<6){b/=1024;i++}
    printf "%.2f %s", b, u[i]
  }'
}
RX_H=$(human_bytes "$RX_B")
TX_H=$(human_bytes "$TX_B")

# CPU color
CPU_CLR="$C_GREEN"
if (( CPU_PCT >= 60 )); then CPU_CLR="$C_YELLOW"; fi
if (( CPU_PCT >= 85 )); then CPU_CLR="$C_RED"; fi

# ---- VPS TYPE (VM / container detection) ----
VIRT_RAW="unknown"
if command -v systemd-detect-virt >/dev/null 2>&1; then
  VIRT_RAW=$(systemd-detect-virt 2>/dev/null)
fi

DMI_VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
DMI_PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null)

VPS_TYPE="Unknown"
case "$VIRT_RAW" in
  docker) VPS_TYPE="Docker Container" ;;
  lxc) VPS_TYPE="LXC Container" ;;
  openvz) VPS_TYPE="OpenVZ Container" ;;
  podman) VPS_TYPE="Podman Container" ;;
  qemu|kvm)
    if echo "$DMI_VENDOR $DMI_PRODUCT" | grep -qiE 'proxmox|pve'; then
      VPS_TYPE="Proxmox VM (KVM)"
    else
      VPS_TYPE="KVM/QEMU VM"
    fi
    ;;
  vmware) VPS_TYPE="VMware VM" ;;
  microsoft) VPS_TYPE="Hyper-V VM" ;;
  xen) VPS_TYPE="Xen VM" ;;
  oracle) VPS_TYPE="VirtualBox VM" ;;
  none)
    if grep -qa docker /proc/1/cgroup 2>/dev/null; then
      VPS_TYPE="Docker Container"
    elif grep -qa lxc /proc/1/cgroup 2>/dev/null; then
      VPS_TYPE="LXC Container"
    else
      VPS_TYPE="Bare Metal / Dedicated"
    fi
    ;;
  *)
    if grep -qa docker /proc/1/cgroup 2>/dev/null; then
      VPS_TYPE="Docker Container"
    elif grep -qa lxc /proc/1/cgroup 2>/dev/null; then
      VPS_TYPE="LXC Container"
    else
      VPS_TYPE="$(echo "$VIRT_RAW" | tr '[:lower:]' '[:upper:]')"
    fi
    ;;
esac

# ---- ISP / Provider (needs internet) ----
ISP="N/A"
if command -v curl >/dev/null 2>&1; then
  ORG=$(curl -m 1.5 -s https://ipinfo.io/org 2>/dev/null | head -n1)
  if [[ -n "$ORG" ]]; then
    ISP="$ORG"
  fi
fi

# Banner
echo -e "${C_BLUE}██████╗ ${C_CYAN}███████╗${C_BLUE}███╗   ██╗${C_CYAN}██████╗ ${C_BLUE}███████╗${C_CYAN}██████╗ ${C_BLUE}██████╗ ${C_CYAN}██╗   ██╗${C_BLUE}████████╗${C_CYAN}███████╗${C_RESET}"
echo -e "${C_BLUE}██╔══██╗${C_CYAN}██╔════╝${C_BLUE}████╗  ██║${C_CYAN}██╔══██╗${C_BLUE}██╔════╝${C_CYAN}██╔══██╗${C_BLUE}██╔══██╗${C_CYAN}╚██╗ ██╔╝${C_BLUE}╚══██╔══╝${C_CYAN}██╔════╝${C_RESET}"
echo -e "${C_BLUE}██████╔╝${C_CYAN}█████╗  ${C_BLUE}██╔██╗ ██║${C_CYAN}██║  ██║${C_BLUE}█████╗  ${C_CYAN}██████╔╝${C_BLUE}██████╔╝${C_CYAN} ╚████╔╝ ${C_BLUE}   ██║   ${C_CYAN}█████╗  ${C_RESET}"
echo -e "${C_BLUE}██╔══██╗${C_CYAN}██╔══╝  ${C_BLUE}██║╚██╗██║${C_CYAN}██║  ██║${C_BLUE}██╔══╝  ${C_CYAN}██╔══██╗${C_BLUE}██╔══██╗${C_CYAN}  ╚██╔╝  ${C_BLUE}   ██║   ${C_CYAN}██╔══╝  ${C_RESET}"
echo -e "${C_BLUE}██║  ██║${C_CYAN}███████╗${C_BLUE}██║ ╚████║${C_CYAN}██████╔╝${C_BLUE}███████╗${C_CYAN}██║  ██║${C_BLUE}██████╔╝${C_CYAN}   ██║   ${C_BLUE}   ██║   ${C_CYAN}███████╗${C_RESET}"
echo -e "${C_BLUE}╚═╝  ╚═╝${C_CYAN}╚══════╝${C_BLUE}╚═╝  ╚═══╝${C_CYAN}╚═════╝ ${C_BLUE}╚══════╝${C_CYAN}╚═╝  ╚═╝${C_BLUE}╚═════╝ ${C_CYAN}   ╚═╝   ${C_BLUE}   ╚═╝   ${C_CYAN}╚══════╝${C_RESET}"
echo ""

# Info block
echo -e "${C_DIM}${C_WHITE} OS        ${C_GRAY}: ${C_RESET}${C_WHITE}${OS}${C_RESET}"
echo -e "${C_DIM}${C_WHITE} Processor ${C_GRAY}: ${C_RESET}${C_WHITE}${CPU}${C_RESET}"
echo -e "${C_DIM}${C_WHITE} Cores     ${C_GRAY}: ${C_RESET}${C_WHITE}${CORES}${C_RESET}"
echo -e "${C_DIM}${C_WHITE} RAM       ${C_GRAY}: ${C_RESET}${C_WHITE}${RAM_USED} / ${RAM_TOTAL}${C_RESET}"
echo -e "${C_DIM}${C_WHITE} Disk      ${C_GRAY}: ${C_RESET}${C_WHITE}${DISK_USED} / ${DISK_TOTAL}${C_RESET}"
echo -e "${C_DIM}${C_WHITE} IPv4      ${C_GRAY}: ${C_RESET}${C_WHITE}${IP:-N/A}${C_RESET}"
echo -e "${C_DIM}${C_WHITE} Hostname  ${C_GRAY}: ${C_RESET}${C_WHITE}${HOST}${C_RESET}"
echo -e "${C_DIM}${C_WHITE} Uptime    ${C_GRAY}: ${C_RESET}${C_WHITE}${UPTIME}${C_RESET}"
echo -e "${C_DIM}${C_WHITE} ISP       ${C_GRAY}: ${C_RESET}${C_WHITE}${ISP}${C_RESET}"
echo -e "${C_DIM}${C_WHITE} VPS Type  ${C_GRAY}: ${C_RESET}${C_WHITE}${VPS_TYPE}${C_RESET}"
echo ""

# Stats block
echo -e "${C_BOLD}${C_CYAN} Live Stats${C_RESET}"
echo -e "${C_DIM}${C_WHITE} CPU Usage ${C_GRAY}: ${CPU_CLR}${CPU_PCT}%${C_RESET} ${C_GRAY}(Load: ${LOAD})${C_RESET}"
echo -e "${C_DIM}${C_WHITE} Network   ${C_GRAY}: ${C_RESET}${C_WHITE}${IFACE:-N/A}${C_RESET}  ${C_GRAY}RX:${C_RESET} ${C_WHITE}${RX_H}${C_RESET}  ${C_GRAY}TX:${C_RESET} ${C_WHITE}${TX_H}${C_RESET}"
echo ""

# Badge / Footer
echo -e "${C_BOLD}${C_BLUE}🛡 DDoS Protection:${C_RESET} ${C_GREEN}ENABLED${C_RESET} ${C_GRAY}(Enterprise Mitigation)${C_RESET}"
echo ""
echo -e "${C_BOLD}${C_CYAN} Welcome to RenderByte VPS Hosting 🚀${C_RESET}"
echo -e "${C_DIM}${C_WHITE} Website  ${C_GRAY}: ${C_RESET}${C_CYAN}https://www.renderbyte.site${C_RESET}"
echo -e "${C_DIM}${C_WHITE} Discord  ${C_GRAY}: ${C_RESET}${C_CYAN}https://discord.gg/renderbyte${C_RESET}"
echo -e "${C_DIM}${C_WHITE} Support  ${C_GRAY}: ${C_RESET}${C_WHITE}Open a ticket via Discord${C_RESET}"
echo ""
MOTD

chmod +x "$MOTD_FILE"

echo "[+] Disabling default Debian MOTD..."
rm -f /etc/motd
touch /etc/motd

# Disable dynamic MOTD scripts if they exist
if [ -d /etc/update-motd.d ]; then
  chmod -x /etc/update-motd.d/* 2>/dev/null || true
fi

echo "[+] Done! Testing MOTD output now:"
echo "------------------------------------------------------------"
bash "$MOTD_FILE" || true
echo "------------------------------------------------------------"
echo "[✓] Installed. Reconnect SSH to see it automatically."
EOF
