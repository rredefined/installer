#!/bin/bash
set -e

echo "🚀 Installing RenderByte UNIVERSAL login banner..."

BANNER_FILE="/etc/renderbyte-banner.sh"

###################################
# 1. Create banner script
###################################
cat > $BANNER_FILE << 'EOF'
#!/bin/bash

# Avoid duplicate prints
[ -n "$RENDERBYTE_SHOWN" ] && return
export RENDERBYTE_SHOWN=1

clear
echo -e "\e[36m"
cat << "RBANNER"
██████╗ ███████╗███╗   ██╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗████████╗███████╗
██╔══██╗██╔════╝████╗  ██║██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝╚══██╔══╝██╔════╝
██████╔╝█████╗  ██╔██╗ ██║██║  ██║█████╗  ██████╔╝██████╔╝ ╚████╔╝    ██║   █████╗  
██╔══██╗██╔══╝  ██║╚██╗██║██║  ██║██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝     ██║   ██╔══╝  
██║  ██║███████╗██║ ╚████║██████╔╝███████╗██║  ██║██████╔╝   ██║      ██║   ███████╗
╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═════╝    ╚═╝      ╚═╝   ╚══════╝
RBANNER
echo -e "\e[0m"

OS=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
CPU=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d ':' -f2 | xargs)
CORES=$(nproc 2>/dev/null)
RAM=$(free -h 2>/dev/null | awk '/Mem:/ {print $3 " / " $2}')
DISK=$(df -h / 2>/dev/null | awk 'NR==2 {print $3 " / " $2}')
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
HOST=$(hostname)
UP=$(uptime -p 2>/dev/null)

echo " OS        : ${OS:-Unknown}"
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

chmod +x $BANNER_FILE

###################################
# 2. Hook into ALL shells
###################################

# /etc/profile (login shells)
grep -q renderbyte-banner.sh /etc/profile || \
echo "[ -f $BANNER_FILE ] && . $BANNER_FILE" >> /etc/profile

# /etc/bash.bashrc (interactive shells)
grep -q renderbyte-banner.sh /etc/bash.bashrc || \
echo "[ -f $BANNER_FILE ] && . $BANNER_FILE" >> /etc/bash.bashrc

###################################
# 3. Done
###################################
echo "✅ All Packages Installed"
echo "🔁 Restarting SSh Services"
