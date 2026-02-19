bash <<'EOF'
set -e

MOTD_FILE="/etc/profile.d/renderbyte-motd.sh"

cat > "$MOTD_FILE" <<'MOTD'
#!/bin/bash
[[ $- != *i* ]] && return

# -------- RenderByte MOTD (Banner Fix) --------

C_RESET="\e[0m"
C_BOLD="\e[1m"

C_BLUE="\e[38;5;39m"
C_CYAN="\e[38;5;51m"
C_WHITE="\e[97m"
C_GRAY="\e[38;5;245m"
C_GREEN="\e[38;5;82m"
C_YELLOW="\e[38;5;226m"
C_RED="\e[38;5;196m"

clear

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

# CPU usage
read -r cpu user nice system idle iowait irq softirq steal _ < /proc/stat
prev_idle=$((idle + iowait))
prev_total=$((user + nice + system + idle + iowait + irq + softirq + steal))
sleep 0.2
read -r cpu user nice system idle iowait irq softirq steal _ < /proc/stat
idle_now=$((idle + iowait))
total_now=$((user + nice + system + idle + iowait + irq + softirq + steal))
diff_idle=$((idle_now - prev_idle))
diff_total=$((total_now - prev_total))
CPU_PCT=$(( (1000 * (diff_total - diff_idle) / diff_total + 5) / 10 ))
LOAD=$(awk '{print $1" "$2" "$3}' /proc/loadavg)

CPU_CLR="$C_GREEN"
if (( CPU_PCT >= 60 )); then CPU_CLR="$C_YELLOW"; fi
if (( CPU_PCT >= 85 )); then CPU_CLR="$C_RED"; fi

# Network
IFACE=$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')
if [[ -z "$IFACE" ]]; then
  IFACE=$(ls /sys/class/net 2>/dev/null | grep -E '^(eth|ens|enp|venet)' | head -n1)
fi
RX_B=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
TX_B=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null || echo 0)

human_bytes() {
  awk -v b="$1" 'BEGIN{
    split("B KB MB GB TB PB",u," ");
    i=1; while (b>=1024 && i<6){b/=1024;i++}
    printf "%.2f %s", b, u[i]
  }'
}
RX_H=$(human_bytes "$RX_B")
TX_H=$(human_bytes "$TX_B")

# VPS Type
VIRT_RAW=$(systemd-detect-virt 2>/dev/null || echo "unknown")
case "$VIRT_RAW" in
  docker) VPS_TYPE="Docker Container" ;;
  lxc) VPS_TYPE="LXC Container" ;;
  qemu|kvm) VPS_TYPE="KVM / Proxmox VM" ;;
  vmware) VPS_TYPE="VMware VM" ;;
  xen) VPS_TYPE="Xen VM" ;;
  none) VPS_TYPE="Bare Metal / Dedicated" ;;
  *) VPS_TYPE="$VIRT_RAW" ;;
esac

# ISP
ISP=$(curl -m 1.5 -s https://ipinfo.io/org 2>/dev/null)
[[ -z "$ISP" ]] && ISP="N/A"

# ✅ FULL banner printed via heredoc (most reliable)
cat <<'BANNER'
██████╗ ███████╗███╗   ██╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗████████╗███████╗
██╔══██╗██╔════╝████╗  ██║██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝╚══██╔══╝██╔════╝
██████╔╝█████╗  ██╔██╗ ██║██║  ██║█████╗  ██████╔╝██████╔╝ ╚████╔╝    ██║   █████╗  
██╔══██╗██╔══╝  ██║╚██╗██║██║  ██║██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝     ██║   ██╔══╝  
██║  ██║███████╗██║ ╚████║██████╔╝███████╗██║  ██║██████╔╝   ██║      ██║   ███████╗
╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═════╝    ╚═╝      ╚═╝   ╚══════╝
BANNER

# Colorize banner (apply blue/cyan quickly)
# (prints banner again colored, then clears the plain one by moving up 6 lines)
# If your terminal doesn't support cursor movement, it will just show colored one below (still fine).
if command -v tput >/dev/null 2>&1; then
  tput cuu 6 2>/dev/null || true
fi
echo -e "${C_BLUE}██████╗ ${C_CYAN}███████╗${C_BLUE}███╗   ██╗${C_CYAN}██████╗ ${C_BLUE}███████╗${C_CYAN}██████╗ ${C_BLUE}██████╗ ${C_CYAN}██╗   ██╗${C_BLUE}████████╗${C_CYAN}███████╗${C_RESET}"
echo -e "${C_BLUE}██╔══██╗${C_CYAN}██╔════╝${C_BLUE}████╗  ██║${C_CYAN}██╔══██╗${C_BLUE}██╔════╝${C_CYAN}██╔══██╗${C_BLUE}██╔══██╗${C_CYAN}╚██╗ ██╔╝${C_BLUE}╚══██╔══╝${C_CYAN}██╔════╝${C_RESET}"
echo -e "${C_BLUE}██████╔╝${C_CYAN}█████╗  ${C_BLUE}██╔██╗ ██║${C_CYAN}██║  ██║${C_BLUE}█████╗  ${C_CYAN}██████╔╝${C_BLUE}██████╔╝${C_CYAN} ╚████╔╝ ${C_BLUE}   ██║   ${C_CYAN}█████╗  ${C_RESET}"
echo -e "${C_BLUE}██╔══██╗${C_CYAN}██╔══╝  ${C_BLUE}██║╚██╗██║${C_CYAN}██║  ██║${C_BLUE}██╔══╝  ${C_CYAN}██╔══██╗${C_BLUE}██╔══██╗${C_CYAN}  ╚██╔╝  ${C_BLUE}   ██║   ${C_CYAN}██╔══╝  ${C_RESET}"
echo -e "${C_BLUE}██║  ██║${C_CYAN}███████╗${C_BLUE}██║ ╚████║${C_CYAN}██████╔╝${C_BLUE}███████╗${C_CYAN}██║  ██║${C_BLUE}██████╔╝${C_CYAN}   ██║   ${C_BLUE}   ██║   ${C_CYAN}███████╗${C_RESET}"
echo -e "${C_BLUE}╚═╝  ╚═╝${C_CYAN}╚══════╝${C_BLUE}╚═╝  ╚═══╝${C_CYAN}╚═════╝ ${C_BLUE}╚══════╝${C_CYAN}╚═╝  ╚═╝${C_BLUE}╚═════╝ ${C_CYAN}   ╚═╝   ${C_BLUE}   ╚═╝   ${C_CYAN}╚══════╝${C_RESET}"
echo ""

echo -e "${C_WHITE} OS        ${C_GRAY}: ${C_RESET}${OS}"
echo -e "${C_WHITE} Processor ${C_GRAY}: ${C_RESET}${CPU}"
echo -e "${C_WHITE} Cores     ${C_GRAY}: ${C_RESET}${CORES}"
echo -e "${C_WHITE} RAM       ${C_GRAY}: ${C_RESET}${RAM_USED} / ${RAM_TOTAL}"
echo -e "${C_WHITE} Disk      ${C_GRAY}: ${C_RESET}${DISK_USED} / ${DISK_TOTAL}"
echo -e "${C_WHITE} IPv4      ${C_GRAY}: ${C_RESET}${IP:-N/A}"
echo -e "${C_WHITE} Hostname  ${C_GRAY}: ${C_RESET}${HOST}"
echo -e "${C_WHITE} Uptime    ${C_GRAY}: ${C_RESET}${UPTIME}"
echo -e "${C_WHITE} ISP       ${C_GRAY}: ${C_RESET}${ISP}"
echo -e "${C_WHITE} VPS Type  ${C_GRAY}: ${C_RESET}${VPS_TYPE}"
echo ""

echo -e "${C_BOLD}${C_CYAN} Live Stats${C_RESET}"
echo -e "${C_WHITE} CPU Usage ${C_GRAY}: ${CPU_CLR}${CPU_PCT}%${C_RESET} ${C_GRAY}(Load: ${LOAD})${C_RESET}"
echo -e "${C_WHITE} Network   ${C_GRAY}: ${C_RESET}${IFACE:-N/A}  RX:${RX_H}  TX:${TX_H}"
echo ""

echo -e "${C_BOLD}${C_BLUE}🛡 DDoS Protection:${C_RESET} ${C_GREEN}ENABLED${C_RESET}"
echo ""
echo -e "${C_BOLD}${C_CYAN} Welcome to RenderByte VPS Hosting 🚀${C_RESET}"
echo -e "${C_WHITE} Website  ${C_GRAY}: ${C_RESET}${C_CYAN}https://www.renderbyte.site${C_RESET}"
echo -e "${C_WHITE} Discord  ${C_GRAY}: ${C_RESET}${C_CYAN}https://discord.gg/renderbyte${C_RESET}"
echo ""
MOTD

chmod +x "$MOTD_FILE"

# Ensure UNIX line endings (just in case)
sed -i 's/\r$//' "$MOTD_FILE" || true

# Disable default MOTD
rm -f /etc/motd
touch /etc/motd
chmod -x /etc/update-motd.d/* 2>/dev/null || true

echo "✔ RenderByte MOTD banner fixed."
echo "Test:"
bash "$MOTD_FILE" || true
EOF
