#!/bin/bash
set -e

echo "🚀 Applying final RenderByte SSH MOTD fix..."

### 1. Remove Ubuntu login banner (Welcome to Ubuntu)
echo "" > /etc/issue
echo "" > /etc/issue.net

sed -i 's/^#\?Banner.*/Banner none/' /etc/ssh/sshd_config || true

### 2. Disable pam_motd (this is the BIG one)
sed -i 's/^session\s\+optional\s\+pam_motd.so/#&/' /etc/pam.d/sshd
sed -i 's/^session\s\+optional\s\+pam_motd.so/#&/' /etc/pam.d/login

### 3. Kill Ubuntu dynamic MOTD files
rm -f /etc/motd
rm -f /run/motd*
rm -f /var/lib/update-notifier/motd*

### 4. Disable motd-news (updates / esm spam)
systemctl disable motd-news.service motd-news.timer >/dev/null 2>&1 || true
systemctl stop motd-news.service motd-news.timer >/dev/null 2>&1 || true

### 5. Disable ALL default update-motd scripts
if [ -d /etc/update-motd.d ]; then
  chmod -x /etc/update-motd.d/* || true
fi

### 6. Install RenderByte MOTD (ONLY one enabled)
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

echo " OS        : $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"
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

### 7. Restart SSH
systemctl restart ssh

echo "✅ DONE: Ubuntu banners removed"
echo "✅ DONE: Only RenderByte MOTD will show"
echo "🔁 IMPORTANT: Logout completely and SSH again"
