#!/bin/bash

# ==========================================================
# Installer Script: XFCE + XRDP + Firefox Setup
# Developer: @Eiro.tf
# ==========================================================

set -e

echo "=============================================="
echo " XFCE + XRDP + Firefox Installer"
echo " Developer: @Eiro.tf"
echo "=============================================="

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run this script as root (sudo ./installer.sh)"
  exit 1
fi

USERNAME=$(logname)
SERVER_IP=$(hostname -I | awk '{print $1}')

echo "👤 Detected user: $USERNAME"
echo "🌐 Server IP: $SERVER_IP"

echo "🔄 Updating system..."
apt update
apt upgrade -y

echo "🌐 Installing Firefox ESR..."
apt install -y firefox-esr

echo "🖥 Installing XFCE Desktop Environment..."
apt install -y xfce4 xfce4-goodies

echo "🔌 Installing XRDP..."
apt install -y xrdp

echo "📝 Configuring XFCE session..."
echo "startxfce4" > /home/$USERNAME/.xsession
chown $USERNAME:$USERNAME /home/$USERNAME/.xsession

echo "🚀 Enabling and restarting XRDP..."
systemctl enable xrdp
systemctl restart xrdp

echo "🌐 Installing latest Firefox..."
apt install -y firefox

echo "🔥 Configuring Firewall (UFW)..."
if command -v ufw >/dev/null 2>&1; then
    ufw allow 3389/tcp
    ufw reload || true
else
    echo "⚠️ UFW not installed, skipping firewall configuration"
fi

echo "=============================================="
echo "✅ Installation completed successfully!"
echo "🖥 Desktop Environment: XFCE"
echo "🔐 RDP Port: 3389"
echo "👉 Now you can access your RDP through:"
echo "   $SERVER_IP:3389"
echo "👨‍💻 Script by @Eiro.tf"
echo "=============================================="
