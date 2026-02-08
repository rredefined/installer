#!/bin/bash

set -e

echo "🚀 Installing RenderByte SSH MOTD..."

# Create MOTD script
cat > /etc/update-motd.d/01-renderbyte << 'EOF'
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

echo " OS        : $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2)"
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

# Make executable
chmod +x /etc/update-motd.d/01-renderbyte

# Disable default Ubuntu MOTD noise
for f in 10-help-text 50-motd-news 80-livepatch 95-hwe-eol; do
  [ -f /etc/update-motd.d/$f ] && chmod -x /etc/update-motd.d/$f
done

echo "✅ RenderByte MOTD installed successfully!"
echo "🔁 Re-login via SSH to see the new welcome screen."
