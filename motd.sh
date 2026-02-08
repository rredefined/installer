#!/bin/bash
set -e

echo "🚀 Installing RenderByte universal login banner..."

#######################################
# 1. Disable Ubuntu/Debian MOTD safely #
#######################################
if [ -d /etc/update-motd.d ]; then
  chmod -x /etc/update-motd.d/* 2>/dev/null || true
fi

systemctl disable motd-news.service motd-news.timer 2>/dev/null || true
systemctl stop motd-news.service motd-news.timer 2>/dev/null || true

rm -f /etc/motd /run/motd* /var/lib/update-notifier/motd* 2>/dev/null || true

###################################
# 2. Remove distro login banners  #
###################################
echo "" > /etc/issue 2>/dev/null || true
echo "" > /etc/issue.net 2>/dev/null || true

###################################
# 3. Create UNIVERSAL login banner#
###################################
cat > /etc/profile.d/renderbyte.sh << 'EOF'
#!/bin/bash

# Prevent duplicate output (sudo, su, tmux, etc.)
[ -n "$RENDERBYTE_SHOWN" ] && return
export RENDERBYTE_SHOWN=1

clear
echo -e "\e[36m"
cat << "BANNER"
██████╗ ███████╗███╗   ██╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗████████╗███████╗
██╔══██╗██╔════╝████╗  ██║██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝╚══██╔══╝██╔════╝
██████╔╝█████╗  ██╔██╗ ██║██║  ██║█████╗  ██████╔╝██████╔╝ ╚████╔╝    ██║   █████╗  
██╔══██╗██╔══╝  ██║╚██╗██║██║  ██║██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝     ██║   ██╔══╝  
██║  ██║███████╗██║ ╚████║██████╔╝███████╗██║  ██║██████╔╝   ██║      ██║   ███████╗
╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═════╝    ╚═╝      ╚═╝   ╚══════╝
BANNER
echo -e "\e[0m"

OS_NAME=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
CPU=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d ':' -f2 | xargs)
CORES=$(nproc 2>/dev/null)
RAM=$(free -h 2>/dev/null | awk '/Mem:/ {print $3 " / " $2}')
DISK=$(df -h / 2>/dev/null | awk 'NR==2 {print $3 " / " $2}')
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
HOST=$(hostname)
UP=$(uptime -p 2>/dev/null)

echo " OS        : ${OS_NAME:-Unknown}"
echo " Processor : ${CPU:-Unknown}"
echo " Cores     : ${CORES:-N/A}"
echo " RAM       : ${RAM:-N/A}"
echo " Disk      : ${DISK:-N/A}"
echo " IPv4      : ${IP:-N/A}"
echo " Hostname  : ${HOST}"
echo " Uptime    : ${UP:-N/A}"
echo
echo " Welcome to RenderByte VPS Hosting 🚀"
echo " Website  : https://www.renderbyte.site"
echo " Discord  : https://discord.gg/renderbyte"
echo " Support  : Open a ticket via Discord"
echo
EOF

chmod +x /etc/profile.d/renderbyte.sh

###################################
# 4. Done                          #
###################################
echo "✅ RenderByte universal banner installed"
echo "🔁 Logout completely and SSH again"
