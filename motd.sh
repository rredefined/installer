#!/bin/bash
set -e

echo "🚀 Setting up RenderByte SSH MOTD..."

# Disable ALL default Ubuntu MOTD scripts
if [ -d /etc/update-motd.d ]; then
  chmod -x /etc/update-motd.d/* || true
fi

# Create RenderByte MOTD
cat > /etc/update-motd.d/00-renderbyte << 'EOF'
#!/bin/bash

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

echo " OS        : $(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"
echo " Processor : $(grep -m1 'model name' /proc/cpuinfo | cut -d ':' -f2 | xargs)"
echo " Cores     : $(nproc)"
echo " RAM       : $(free -h | awk '/Mem:/ {print $3 \" / \" $2}')"
echo " Disk      : $(df -h / | awk 'NR==2 {print $3 \" / \" $2}')"
echo " IPv4      : $(hostname -I | awk '{print $1}')"
echo " Hostname  : $(hostname)"
echo " Uptime    : $(uptime -p)"
echo
echo " Welcome to RenderByte VPS Hosting 🚀"
echo " Website  : https://www.renderbyte.site"
echo " Discord  : https://discord.gg/renderbyte"
echo " Support  : Open a ticket via Discord"
echo
EOF

chmod +x /etc/update-motd.d/00-renderbyte

# Disable Ubuntu MOTD via PAM (extra safety)
sed -i 's/^session\s\+optional\s\+pam_motd.so/#&/' /etc/pam.d/sshd
echo "session optional pam_motd.so motd=/run/motd.dynamic" >> /etc/pam.d/sshd

echo "✅ Ubuntu MOTD removed"
echo "✅ RenderByte MOTD installed"
echo "🔁 Logout & SSH again to see the clean login screen"
