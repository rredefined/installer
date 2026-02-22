#!/bin/bash
set -euo pipefail

# =========================================================
# Enhanced Multi-VM Manager (QEMU + KVM)
# CPU Spoof: AMD Ryzen 9 7950X (exact string)
#
# Features:
#  - Create / Start / Stop / Info / Edit / Delete
#  - Disk resize
#  - Performance view
#  - Fix issues (locks, seed recreate, kill stuck)
#  - Cloud-image OSes via cloud-init
#  - Proxmox VE ISO install mode (manual installer)
#
# KVM upgrades:
#  - accel=kvm, -cpu host
#  - Ryzen model string spoof via -global cpu.model-id=...
#  - virtio-net + vhost-net acceleration (when possible)
#  - optional TAP/bridge networking (faster than user NAT)
# =========================================================

# -----------------------------
# Paths
# -----------------------------
VM_DIR="${VM_DIR:-$HOME/vms}"
ISO_DIR="${ISO_DIR:-$VM_DIR/iso}"
mkdir -p "$VM_DIR" "$ISO_DIR"

# -----------------------------
# Header UI
# -----------------------------
display_header() {
    clear
    cat << "EOF"
██████╗ ███████╗███╗   ██╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗████████╗███████╗
██╔══██╗██╔════╝████╗  ██║██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝╚══██╔══╝██╔════╝
██████╔╝█████╗  ██╔██╗ ██║██║  ██║█████╗  ██████╔╝██████╔╝ ╚████╔╝    ██║   █████╗
██╔══██╗██╔══╝  ██║╚██╗██║██║  ██║██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝     ██║   ██╔══╝
██║  ██║███████╗██║ ╚████║██████╔╝███████╗██║  ██║██████╔╝   ██║      ██║   ███████╗
╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═════╝    ╚═╝      ╚═╝   ╚══════╝
EOF
    echo
}

print_status() {
    local type=$1
    local message=$2
    case $type in
        "INFO") echo -e "\033[1;34m📋 [INFO]\033[0m $message" ;;
        "WARN") echo -e "\033[1;33m⚠️  [WARN]\033[0m $message" ;;
        "ERROR") echo -e "\033[1;31m❌ [ERROR]\033[0m $message" ;;
        "SUCCESS") echo -e "\033[1;32m✅ [SUCCESS]\033[0m $message" ;;
        "INPUT") echo -e "\033[1;36m🎯 [INPUT]\033[0m $message" ;;
        *) echo "[$type] $message" ;;
    esac
}

# -----------------------------
# Helpers
# -----------------------------
cleanup() { rm -f user-data meta-data 2>/dev/null || true; }
trap cleanup EXIT

validate_input() {
    local type=$1
    local value=$2
    case $type in
        "number") [[ "$value" =~ ^[0-9]+$ ]] || { print_status "ERROR" "❌ Must be a number"; return 1; } ;;
        "size") [[ "$value" =~ ^[0-9]+[GgMm]$ ]] || { print_status "ERROR" "❌ Must be size like 50G or 512M"; return 1; } ;;
        "port")
            if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 23 ] || [ "$value" -gt 65535 ]; then
                print_status "ERROR" "❌ Must be valid port (23-65535)"; return 1
            fi ;;
        "name") [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]] || { print_status "ERROR" "❌ Only letters/numbers/_/-"; return 1; } ;;
        "username") [[ "$value" =~ ^[a-z_][a-z0-9_-]*$ ]] || { print_status "ERROR" "❌ Bad username"; return 1; } ;;
    esac
    return 0
}

check_dependencies() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "lsof" "openssl" "ss" "pgrep" "pkill")
    local missing=()
    for dep in "${deps[@]}"; do command -v "$dep" &>/dev/null || missing+=("$dep"); done

    if [ ${#missing[@]} -ne 0 ]; then
        print_status "ERROR" "🔧 Missing: ${missing[*]}"
        print_status "INFO"  "💡 Ubuntu/Debian: apt update && apt install -y qemu-system-x86 qemu-utils cloud-image-utils wget lsof openssl iproute2 procps"
        exit 1
    fi

    # KVM check (warning only)
    if [[ ! -e /dev/kvm ]]; then
        print_status "WARN" "⚠️ /dev/kvm not found. KVM won't work. Enable virtualization in BIOS + install kvm."
        print_status "INFO" "💡 Install: apt install -y qemu-kvm && usermod -aG kvm \$USER"
    fi
}

get_vm_list() { find "$VM_DIR" -maxdepth 1 -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort; }

check_image_lock() {
    local img_file=$1
    local vm_name=$2
    [[ -z "${img_file:-}" || ! -f "$img_file" ]] && return 0

    if lsof "$img_file" 2>/dev/null | grep -q qemu-system; then
        print_status "WARN" "🔒 Image in use: $img_file"
        local pid
        pid=$(lsof "$img_file" 2>/dev/null | grep qemu-system | awk '{print $2}' | head -1 || true)
        [[ -n "${pid:-}" ]] && print_status "INFO" "PID: $pid"
        return 1
    fi

    local lock_file="${img_file}.lock"
    if [[ -f "$lock_file" ]]; then
        print_status "WARN" "🔒 Lock file: $lock_file"
        return 1
    fi
    return 0
}

# -----------------------------
# Config load/save
# -----------------------------
load_vm_config() {
    local vm_name=$1
    local cfg="$VM_DIR/$vm_name.conf"
    [[ -f "$cfg" ]] || { print_status "ERROR" "📂 Config not found: $vm_name"; return 1; }

    unset VM_NAME OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD
    unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED
    unset ISO_FILE INSTALLED NET_MODE BRIDGE_IFACE

    # shellcheck source=/dev/null
    source "$cfg"

    ISO_FILE="${ISO_FILE:-}"
    INSTALLED="${INSTALLED:-false}"
    GUI_MODE="${GUI_MODE:-false}"
    PORT_FORWARDS="${PORT_FORWARDS:-}"

    # networking mode:
    #   user = NAT (default, easiest)
    #   tap  = bridge/tap (faster) needs host setup
    NET_MODE="${NET_MODE:-user}"
    BRIDGE_IFACE="${BRIDGE_IFACE:-br0}"
    return 0
}

save_vm_config() {
    local cfg="$VM_DIR/$VM_NAME.conf"
    ISO_FILE="${ISO_FILE:-}"
    INSTALLED="${INSTALLED:-false}"
    NET_MODE="${NET_MODE:-user}"
    BRIDGE_IFACE="${BRIDGE_IFACE:-br0}"

    cat > "$cfg" <<EOF
VM_NAME="$VM_NAME"
OS_TYPE="$OS_TYPE"
CODENAME="$CODENAME"
IMG_URL="$IMG_URL"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
DISK_SIZE="$DISK_SIZE"
MEMORY="$MEMORY"
CPUS="$CPUS"
SSH_PORT="$SSH_PORT"
GUI_MODE="$GUI_MODE"
PORT_FORWARDS="$PORT_FORWARDS"
NET_MODE="$NET_MODE"
BRIDGE_IFACE="$BRIDGE_IFACE"
IMG_FILE="$IMG_FILE"
SEED_FILE="$SEED_FILE"
ISO_FILE="$ISO_FILE"
INSTALLED="$INSTALLED"
CREATED="$CREATED"
EOF
    print_status "SUCCESS" "💾 Saved: $cfg"
}

# -----------------------------
# OS Options
# -----------------------------
declare -A OS_OPTIONS=(
    ["Ubuntu 22.04"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Ubuntu 24.04"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Debian 11"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
    ["Debian 12"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Debian 13"]="debian|trixie|https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-generic-amd64-daily.qcow2|debian13|debian|debian"
    ["Fedora 40"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
    ["CentOS Stream 9"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos"
    ["AlmaLinux 9"]="almalinux|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma"
    ["Rocky Linux 9"]="rockylinux|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky"
    ["Proxmox VE (Installer ISO)"]="proxmox|ve|https://enterprise.proxmox.com/iso/proxmox-ve_8.3-1.iso|proxmox|root|changeme"
)

# -----------------------------
# Create VM
# -----------------------------
create_new_vm() {
    print_status "INFO" "🆕 Creating a new VM"
    print_status "INFO" "🌍 Select an OS:"

    local os_options=()
    local i=1
    for os in "${!OS_OPTIONS[@]}"; do
        echo "  $i) $os"
        os_options[$i]="$os"
        ((i++))
    done

    local choice
    while true; do
        read -r -p "$(print_status "INPUT" "🎯 Choice (1-${#OS_OPTIONS[@]}): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#OS_OPTIONS[@]} ]; then
            local os="${os_options[$choice]}"
            IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD <<< "${OS_OPTIONS[$os]}"
            break
        fi
        print_status "ERROR" "❌ Invalid selection"
    done

    while true; do
        read -r -p "$(print_status "INPUT" "🏷️ VM name (default: $DEFAULT_HOSTNAME): ")" VM_NAME
        VM_NAME="${VM_NAME:-$DEFAULT_HOSTNAME}"
        if validate_input "name" "$VM_NAME"; then
            [[ -f "$VM_DIR/$VM_NAME.conf" ]] && { print_status "ERROR" "⚠️ VM exists"; continue; }
            break
        fi
    done

    read -r -p "$(print_status "INPUT" "🏠 Hostname (default: $VM_NAME): ")" HOSTNAME
    HOSTNAME="${HOSTNAME:-$VM_NAME}"

    while true; do
        read -r -p "$(print_status "INPUT" "👤 Username (default: $DEFAULT_USERNAME): ")" USERNAME
        USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
        validate_input "username" "$USERNAME" && break
    done

    while true; do
        read -r -s -p "$(print_status "INPUT" "🔑 Password (default: $DEFAULT_PASSWORD): ")" PASSWORD
        PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
        echo
        [[ -n "$PASSWORD" ]] && break
        print_status "ERROR" "❌ Password cannot be empty"
    done

    while true; do
        read -r -p "$(print_status "INPUT" "💾 Disk size (default: 20G): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-20G}"
        validate_input "size" "$DISK_SIZE" && break
    done

    while true; do
        read -r -p "$(print_status "INPUT" "🧠 Memory MB (default: 2048): ")" MEMORY
        MEMORY="${MEMORY:-2048}"
        validate_input "number" "$MEMORY" && break
    done

    while true; do
        read -r -p "$(print_status "INPUT" "⚡ CPUs (default: 2): ")" CPUS
        CPUS="${CPUS:-2}"
        validate_input "number" "$CPUS" && break
    done

    while true; do
        read -r -p "$(print_status "INPUT" "🔌 SSH Port (default: 2222): ")" SSH_PORT
        SSH_PORT="${SSH_PORT:-2222}"
        if validate_input "port" "$SSH_PORT"; then
            if ss -tln 2>/dev/null | grep -q ":$SSH_PORT "; then
                print_status "ERROR" "🚫 Port $SSH_PORT is in use"
            else
                break
            fi
        fi
    done

    read -r -p "$(print_status "INPUT" "🖥️ Enable GUI? (y/n, default: n): ")" gui_input
    gui_input="${gui_input:-n}"
    [[ "$gui_input" =~ ^[Yy]$ ]] && GUI_MODE=true || GUI_MODE=false

    read -r -p "$(print_status "INPUT" "🌐 Additional port forwards (e.g., 8080:80, Enter none): ")" PORT_FORWARDS

    # Networking mode choice (optional)
    read -r -p "$(print_status "INPUT" "🌐 Network mode: user (NAT) or tap (bridge)? [user]: ")" NET_MODE
    NET_MODE="${NET_MODE:-user}"
    if [[ "$NET_MODE" != "user" && "$NET_MODE" != "tap" ]]; then
        print_status "WARN" "Unknown NET_MODE. Using user."
        NET_MODE="user"
    fi
    if [[ "$NET_MODE" == "tap" ]]; then
        read -r -p "$(print_status "INPUT" "🔧 Bridge interface name (default: br0): ")" BRIDGE_IFACE
        BRIDGE_IFACE="${BRIDGE_IFACE:-br0}"
    else
        BRIDGE_IFACE="br0"
    fi

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    ISO_FILE=""
    INSTALLED="false"
    CREATED="$(date)"

    setup_vm_image
    save_vm_config
}

# -----------------------------
# Setup VM Image
# -----------------------------
setup_vm_image() {
    print_status "INFO" "📥 Preparing VM files..."

    if [[ "$OS_TYPE" == "proxmox" ]]; then
        ISO_FILE="$ISO_DIR/${VM_NAME}.iso"
        if [[ ! -f "$ISO_FILE" ]]; then
            print_status "INFO" "🌐 Downloading Proxmox ISO..."
            wget --progress=bar:force "$IMG_URL" -O "$ISO_FILE.tmp"
            mv "$ISO_FILE.tmp" "$ISO_FILE"
        fi

        [[ -f "$IMG_FILE" ]] || { print_status "INFO" "💾 Creating disk $DISK_SIZE"; qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"; }
        SEED_FILE=""
        print_status "SUCCESS" "🎉 Proxmox installer prepared."
        return 0
    fi

    if [[ ! -f "$IMG_FILE" ]]; then
        print_status "INFO" "🌐 Downloading image..."
        wget --progress=bar:force "$IMG_URL" -O "$IMG_FILE.tmp"
        mv "$IMG_FILE.tmp" "$IMG_FILE"
    else
        print_status "INFO" "✅ Image exists. Skipping download."
    fi

    qemu-img resize "$IMG_FILE" "$DISK_SIZE" 2>/dev/null || true

    cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    password: $(openssl passwd -6 "$PASSWORD" | tr -d '\n')
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
EOF

    cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
EOF

    cloud-localds "$SEED_FILE" user-data meta-data
    print_status "SUCCESS" "🎉 VM '$VM_NAME' prepared."
    print_status "INFO" "🔌 SSH (NAT): ssh -p $SSH_PORT $USERNAME@localhost"
}

# -----------------------------
# Running state
# -----------------------------
is_vm_running() {
    local vm_name=$1
    pgrep -f "qemu-system.*$vm_name" >/dev/null && return 0
    if load_vm_config "$vm_name" 2>/dev/null; then
        [[ -n "${IMG_FILE:-}" ]] && pgrep -f "qemu-system.*$IMG_FILE" >/dev/null && return 0
    fi
    return 1
}

# -----------------------------
# TAP helpers (optional)
# -----------------------------
ensure_tap() {
    local tap="tap-${VM_NAME}"
    if ip link show "$tap" &>/dev/null; then
        return 0
    fi

    print_status "INFO" "🔧 Creating TAP interface: $tap (bridge: $BRIDGE_IFACE)"
    sudo ip tuntap add dev "$tap" mode tap user "$(id -un)"
    sudo ip link set "$tap" up
    sudo ip link set "$tap" master "$BRIDGE_IFACE"
}

# -----------------------------
# Start/Stop
# -----------------------------
start_vm() {
    local vm_name=$1
    load_vm_config "$vm_name" || return 1

    if [[ -n "${IMG_FILE:-}" && -f "$IMG_FILE" ]]; then
        check_image_lock "$IMG_FILE" "$vm_name" || { print_status "ERROR" "🔒 Image locked/in use"; return 1; }
    fi

    if is_vm_running "$vm_name"; then
        print_status "WARN" "⚠️ VM already running"
        return 1
    fi

    if [[ "$OS_TYPE" == "proxmox" ]]; then
        ISO_FILE="${ISO_FILE:-$ISO_DIR/${VM_NAME}.iso}"
        [[ -f "$IMG_FILE" ]] || { print_status "ERROR" "❌ Disk not found: $IMG_FILE"; return 1; }
        [[ -f "$ISO_FILE" ]] || { print_status "ERROR" "❌ ISO not found: $ISO_FILE"; return 1; }
    else
        [[ -f "$IMG_FILE" ]] || { print_status "ERROR" "❌ Image not found: $IMG_FILE"; return 1; }
        [[ -f "${SEED_FILE:-}" ]] || { print_status "WARN" "⚠️ Seed missing, recreating..."; setup_vm_image; }
    fi

    print_status "INFO" "🚀 Starting VM: $vm_name"
    print_status "INFO" "⚡ Mode: KVM (fast) | CPU spoof: AMD Ryzen 9 7950X"
    print_status "INFO" "🔌 SSH: ssh -p $SSH_PORT $USERNAME@localhost (user-mode NAT)"

    # KVM + Ryzen spoof (works well on QEMU 6.2+)
    # -cpu host gives near-native performance
    # model-id sets the CPU brand string visible in guest
    local qemu_cmd=(
        qemu-system-x86_64
        -name "$VM_NAME"
        -enable-kvm
        -machine "q35,accel=kvm"
        -m "$MEMORY"
        -smp "$CPUS"
        -cpu host
        -global "cpu.model-id=AMD Ryzen 9 7950X 16-Core Processor"
        -drive "file=$IMG_FILE,format=qcow2,if=virtio,cache=none,aio=native"
        -device virtio-balloon-pci
        -object rng-random,filename=/dev/urandom,id=rng0
        -device virtio-rng-pci,rng=rng0
        -rtc base=utc,clock=host
    )

    # Boot media logic
    if [[ "$OS_TYPE" != "proxmox" && -n "${SEED_FILE:-}" ]]; then
        qemu_cmd+=(-drive "file=$SEED_FILE,format=raw,if=virtio")
        qemu_cmd+=(-boot order=c)
    fi

    if [[ "$OS_TYPE" == "proxmox" ]]; then
        if [[ "${INSTALLED:-false}" == "true" ]]; then
            qemu_cmd+=(-boot order=c)
        else
            qemu_cmd+=(-cdrom "$ISO_FILE" -boot order=d,c)
        fi
    fi

    # Networking
    # user-mode NAT: easiest, decent performance
    # tap/bridge: best performance, requires host bridge setup
    if [[ "${NET_MODE:-user}" == "tap" ]]; then
        ensure_tap
        local tap="tap-${VM_NAME}"
        qemu_cmd+=(
            -netdev "tap,id=n0,ifname=${tap},script=no,downscript=no,vhost=on"
            -device "virtio-net-pci,netdev=n0"
        )
        print_status "INFO" "🌐 NET_MODE=tap (bridge) via ${BRIDGE_IFACE}, interface: ${tap}"
        print_status "INFO" "🟢 Guest will get LAN IP (not localhost forward)."
    else
        # NAT with vhost-net not applicable; still ok.
        qemu_cmd+=(
            -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22"
            -device "virtio-net-pci,netdev=n0"
        )
        # Extra forwards (NAT mode only)
        if [[ -n "${PORT_FORWARDS:-}" ]]; then
            IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
            for forward in "${forwards[@]}"; do
                IFS=':' read -r host_port guest_port <<< "$forward"
                [[ -n "${host_port:-}" && -n "${guest_port:-}" ]] || continue
                qemu_cmd[${#qemu_cmd[@]}-2]="${qemu_cmd[${#qemu_cmd[@]}-2]},hostfwd=tcp::${host_port}-:${guest_port}"
            done
        fi
    fi

    # Display mode
    if [[ "$OS_TYPE" == "proxmox" ]]; then
        qemu_cmd+=(-vga virtio -display gtk)
    else
        if [[ "$GUI_MODE" == "true" ]]; then
            qemu_cmd+=(-vga virtio -display gtk,gl=on)
        else
            qemu_cmd+=(-nographic -serial mon:stdio)
            print_status "INFO" "📟 Console exit: Ctrl+A then X"
        fi
    fi

    "${qemu_cmd[@]}"
}

stop_vm() {
    local vm_name=$1
    load_vm_config "$vm_name" || return 1

    if is_vm_running "$vm_name"; then
        print_status "INFO" "🛑 Stopping VM: $vm_name"
        pkill -f "qemu-system.*-name $VM_NAME" 2>/dev/null || true
        pkill -f "qemu-system.*$IMG_FILE" 2>/dev/null || true
        sleep 2
        pkill -9 -f "qemu-system.*$IMG_FILE" 2>/dev/null || true
        rm -f "${IMG_FILE}.lock" 2>/dev/null || true
        print_status "SUCCESS" "✅ VM stopped"
    else
        print_status "INFO" "💤 VM not running"
    fi
}

# -----------------------------
# Info / Delete
# -----------------------------
show_vm_info() {
    local vm_name=$1
    load_vm_config "$vm_name" || return 1

    echo
    print_status "INFO" "📊 VM Information: $vm_name"
    echo "--------------------------------------------"
    echo "🌍 OS_TYPE:        $OS_TYPE"
    echo "🏷️  Hostname:      $HOSTNAME"
    echo "👤 Username:      $USERNAME"
    echo "🔌 SSH Port:      $SSH_PORT"
    echo "🧠 Memory:        ${MEMORY} MB"
    echo "⚡ CPUs:          $CPUS"
    echo "💾 Disk:          $DISK_SIZE"
    echo "🖥️  GUI Mode:     $GUI_MODE"
    echo "🌐 NET_MODE:      ${NET_MODE:-user}"
    echo "🌉 Bridge:        ${BRIDGE_IFACE:-br0}"
    echo "🌐 Port Forwards: ${PORT_FORWARDS:-None}"
    echo "💿 Disk Image:    $IMG_FILE"
    echo "🌱 Seed ISO:      ${SEED_FILE:-None}"
    echo "📀 ISO File:      ${ISO_FILE:-None}"
    echo "✅ Installed:     ${INSTALLED:-false}"
    echo "📅 Created:       $CREATED"
    echo "🚀 Status:        $([[ $(is_vm_running "$vm_name"; echo $?) -eq 0 ]] && echo Running || echo Stopped)"
    echo "--------------------------------------------"
    echo
    read -r -p "$(print_status "INPUT" "⏎ Press Enter to continue...")"
}

delete_vm() {
    local vm_name=$1
    print_status "WARN" "⚠️ Delete VM '$vm_name' (disk + config)!"
    read -r -p "$(print_status "INPUT" "🗑️ Sure? (y/N): ")" ans
    [[ "$ans" =~ ^[Yy]$ ]] || { print_status "INFO" "Cancelled"; return 0; }

    load_vm_config "$vm_name" || return 1
    is_vm_running "$vm_name" && stop_vm "$vm_name"

    rm -f "$VM_DIR/$vm_name.conf" 2>/dev/null || true
    [[ -n "${IMG_FILE:-}" ]] && rm -f "$IMG_FILE" "${IMG_FILE}.lock" 2>/dev/null || true
    [[ -n "${SEED_FILE:-}" ]] && rm -f "$SEED_FILE" 2>/dev/null || true
    [[ -n "${ISO_FILE:-}" ]] && rm -f "$ISO_FILE" 2>/dev/null || true

    # remove tap if created
    if ip link show "tap-${VM_NAME}" &>/dev/null; then
        sudo ip link set "tap-${VM_NAME}" down || true
        sudo ip tuntap del dev "tap-${VM_NAME}" mode tap || true
    fi

    print_status "SUCCESS" "✅ Deleted VM '$vm_name'"
}

# -----------------------------
# Edit VM
# -----------------------------
edit_vm_config() {
    local vm_name=$1
    load_vm_config "$vm_name" || return 1

    while true; do
        display_header
        print_status "INFO" "✏️ Editing VM: $vm_name"
        echo "  1) 🏷️ Hostname"
        echo "  2) 👤 Username"
        echo "  3) 🔑 Password"
        echo "  4) 🔌 SSH Port"
        echo "  5) 🖥️ GUI Mode"
        echo "  6) 🌐 Port Forwards (NAT only)"
        echo "  7) 🧠 Memory (RAM)"
        echo "  8) ⚡ CPU Count"
        echo "  9) 💾 Disk Size (config only)"
        echo " 10) 🌐 NET_MODE (user/tap)"
        echo " 11) 🌉 Bridge iface (tap mode)"
        if [[ "$OS_TYPE" == "proxmox" ]]; then
            echo " 12) ✅ Toggle INSTALLED (Proxmox)"
        fi
        echo "  0) ↩️ Back"
        echo

        read -r -p "$(print_status "INPUT" "🎯 Choice: ")" c
        case $c in
            1) read -r -p "$(print_status "INPUT" "Hostname (current: $HOSTNAME): ")" v; v="${v:-$HOSTNAME}"; validate_input "name" "$v" && HOSTNAME="$v" ;;
            2) read -r -p "$(print_status "INPUT" "Username (current: $USERNAME): ")" v; v="${v:-$USERNAME}"; validate_input "username" "$v" && USERNAME="$v" ;;
            3) read -r -s -p "$(print_status "INPUT" "New password: ")" v; echo; [[ -n "${v:-}" ]] && PASSWORD="$v" ;;
            4)
                read -r -p "$(print_status "INPUT" "SSH port (current: $SSH_PORT): ")" v
                v="${v:-$SSH_PORT}"
                if validate_input "port" "$v"; then
                    if [[ "$v" != "$SSH_PORT" ]] && ss -tln 2>/dev/null | grep -q ":$v "; then
                        print_status "ERROR" "🚫 Port $v is in use"
                    else
                        SSH_PORT="$v"
                    fi
                fi ;;
            5) read -r -p "$(print_status "INPUT" "GUI? y/n (current: $GUI_MODE): ")" v; [[ "${v:-}" =~ ^[Yy]$ ]] && GUI_MODE=true; [[ "${v:-}" =~ ^[Nn]$ ]] && GUI_MODE=false ;;
            6) read -r -p "$(print_status "INPUT" "Port forwards (current: ${PORT_FORWARDS:-None}): ")" v; PORT_FORWARDS="${v:-$PORT_FORWARDS}" ;;
            7) read -r -p "$(print_status "INPUT" "Memory MB (current: $MEMORY): ")" v; v="${v:-$MEMORY}"; validate_input "number" "$v" && MEMORY="$v" ;;
            8) read -r -p "$(print_status "INPUT" "CPU count (current: $CPUS): ")" v; v="${v:-$CPUS}"; validate_input "number" "$v" && CPUS="$v" ;;
            9) read -r -p "$(print_status "INPUT" "Disk size (current: $DISK_SIZE): ")" v; v="${v:-$DISK_SIZE}"; validate_input "size" "$v" && DISK_SIZE="$v" ;;
            10)
                read -r -p "$(print_status "INPUT" "NET_MODE user/tap (current: ${NET_MODE:-user}): ")" v
                v="${v:-$NET_MODE}"
                if [[ "$v" == "user" || "$v" == "tap" ]]; then NET_MODE="$v"; else print_status "ERROR" "Use user or tap"; fi ;;
            11)
                read -r -p "$(print_status "INPUT" "Bridge iface (current: ${BRIDGE_IFACE:-br0}): ")" v
                BRIDGE_IFACE="${v:-$BRIDGE_IFACE}" ;;
            12)
                if [[ "$OS_TYPE" == "proxmox" ]]; then
                    [[ "${INSTALLED:-false}" == "true" ]] && INSTALLED="false" || INSTALLED="true"
                    print_status "SUCCESS" "INSTALLED=$INSTALLED"
                fi ;;
            0) break ;;
            *) print_status "ERROR" "❌ Invalid option" ;;
        esac

        if [[ "$OS_TYPE" != "proxmox" && ( "$c" == "1" || "$c" == "2" || "$c" == "3" ) ]]; then
            print_status "INFO" "🔄 Rebuilding cloud-init seed..."
            setup_vm_image
        fi

        save_vm_config
        read -r -p "$(print_status "INPUT" "⏎ Enter...")"
    done
}

# -----------------------------
# Resize disk
# -----------------------------
resize_vm_disk() {
    local vm_name=$1
    load_vm_config "$vm_name" || return 1
    is_vm_running "$vm_name" && { print_status "ERROR" "❌ Stop VM first"; return 1; }

    print_status "INFO" "💾 Current: $DISK_SIZE"
    read -r -p "$(print_status "INPUT" "New disk size (e.g., 50G): ")" new_size
    validate_input "size" "$new_size" || return 1
    qemu-img resize "$IMG_FILE" "$new_size"
    DISK_SIZE="$new_size"
    save_vm_config
    print_status "SUCCESS" "✅ Disk resized: $new_size"
}

# -----------------------------
# Performance
# -----------------------------
show_vm_performance() {
    local vm_name=$1
    load_vm_config "$vm_name" || return 1
    if ! is_vm_running "$vm_name"; then
        print_status "INFO" "💤 VM not running"
        read -r -p "$(print_status "INPUT" "⏎ Enter...")"
        return 0
    fi

    local pid=""
    pid=$(pgrep -f "qemu-system.*$IMG_FILE" | head -n1 || true)

    print_status "INFO" "📊 Performance: $vm_name"
    echo "--------------------------------------------"
    echo "PID: ${pid:-unknown}"
    [[ -n "${pid:-}" ]] && ps -p "$pid" -o pid,%cpu,%mem,rss,vsz,cmd --no-headers || true
    echo
    free -h || true
    echo
    [[ -f "$IMG_FILE" ]] && du -h "$IMG_FILE" 2>/dev/null || true
    echo "--------------------------------------------"
    read -r -p "$(print_status "INPUT" "⏎ Enter...")"
}

# -----------------------------
# Fix issues
# -----------------------------
fix_vm_issues() {
    local vm_name=$1
    load_vm_config "$vm_name" || return 1

    display_header
    print_status "INFO" "🔧 Fix VM: $vm_name"
    echo "  1) 🔓 Remove lock files"
    echo "  2) 🗑️ Recreate seed image (cloud images)"
    echo "  3) 💾 Rewrite config file"
    echo "  4) 💀 Kill stuck QEMU processes"
    echo "  0) ↩️ Back"
    echo

    read -r -p "$(print_status "INPUT" "🎯 Choice: ")" c
    case $c in
        1) rm -f "${IMG_FILE}.lock" "${IMG_FILE}"*.lock 2>/dev/null || true; print_status "SUCCESS" "✅ Locks removed" ;;
        2)
            if [[ "$OS_TYPE" == "proxmox" ]]; then
                print_status "WARN" "Proxmox doesn't use cloud-init seed."
            else
                rm -f "$SEED_FILE" 2>/dev/null || true
                setup_vm_image
                print_status "SUCCESS" "✅ Seed recreated"
            fi ;;
        3) save_vm_config; print_status "SUCCESS" "✅ Config rewritten" ;;
        4) pkill -f "qemu-system.*$IMG_FILE" 2>/dev/null || true; sleep 1; pkill -9 -f "qemu-system.*$IMG_FILE" 2>/dev/null || true; print_status "SUCCESS" "✅ Killed stuck" ;;
        0) return 0 ;;
        *) print_status "ERROR" "❌ Invalid option" ;;
    esac
    read -r -p "$(print_status "INPUT" "⏎ Enter...")"
}

# -----------------------------
# Main Menu
# -----------------------------
main_menu() {
    while true; do
        display_header

        local vms=()
        mapfile -t vms < <(get_vm_list)
        local vm_count=${#vms[@]}

        if [ $vm_count -gt 0 ]; then
            print_status "INFO" "📁 Found $vm_count VM(s):"
            for i in "${!vms[@]}"; do
                local status="💤"
                is_vm_running "${vms[$i]}" && status="🚀"
                printf "  %2d) %s %s\n" $((i+1)) "${vms[$i]}" "$status"
            done
            echo
        fi

        echo "📋 Main Menu:"
        echo "  1) 🆕 Create a new VM"
        if [ $vm_count -gt 0 ]; then
            echo "  2) 🚀 Start a VM"
            echo "  3) 🛑 Stop a VM"
            echo "  4) 📊 Show VM info"
            echo "  5) ✏️  Edit VM configuration"
            echo "  6) 🗑️  Delete a VM"
            echo "  7) 📈 Resize VM disk"
            echo "  8) 📊 Show VM performance"
            echo "  9) 🔧 Fix VM issues"
        fi
        echo "  0) 👋 Exit"
        echo

        read -r -p "$(print_status "INPUT" "🎯 Choice: ")" choice
        case $choice in
            1) create_new_vm ;;
            2)
                [ $vm_count -gt 0 ] || continue
                read -r -p "$(print_status "INPUT" "🚀 VM number: ")" vm_num
                [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ] \
                    && start_vm "${vms[$((vm_num-1))]}" || print_status "ERROR" "❌ Invalid selection"
                ;;
            3)
                [ $vm_count -gt 0 ] || continue
                read -r -p "$(print_status "INPUT" "🛑 VM number: ")" vm_num
                [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ] \
                    && stop_vm "${vms[$((vm_num-1))]}" || print_status "ERROR" "❌ Invalid selection"
                ;;
            4)
                [ $vm_count -gt 0 ] || continue
                read -r -p "$(print_status "INPUT" "📊 VM number: ")" vm_num
                [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ] \
                    && show_vm_info "${vms[$((vm_num-1))]}" || print_status "ERROR" "❌ Invalid selection"
                ;;
            5)
                [ $vm_count -gt 0 ] || continue
                read -r -p "$(print_status "INPUT" "✏️ VM number: ")" vm_num
                [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ] \
                    && edit_vm_config "${vms[$((vm_num-1))]}" || print_status "ERROR" "❌ Invalid selection"
                ;;
            6)
                [ $vm_count -gt 0 ] || continue
                read -r -p "$(print_status "INPUT" "🗑️ VM number: ")" vm_num
                [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ] \
                    && delete_vm "${vms[$((vm_num-1))]}" || print_status "ERROR" "❌ Invalid selection"
                ;;
            7)
                [ $vm_count -gt 0 ] || continue
                read -r -p "$(print_status "INPUT" "📈 VM number: ")" vm_num
                [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ] \
                    && resize_vm_disk "${vms[$((vm_num-1))]}" || print_status "ERROR" "❌ Invalid selection"
                ;;
            8)
                [ $vm_count -gt 0 ] || continue
                read -r -p "$(print_status "INPUT" "📊 VM number: ")" vm_num
                [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ] \
                    && show_vm_performance "${vms[$((vm_num-1))]}" || print_status "ERROR" "❌ Invalid selection"
                ;;
            9)
                [ $vm_count -gt 0 ] || continue
                read -r -p "$(print_status "INPUT" "🔧 VM number: ")" vm_num
                [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ] \
                    && fix_vm_issues "${vms[$((vm_num-1))]}" || print_status "ERROR" "❌ Invalid selection"
                ;;
            0) print_status "INFO" "👋 Bye!"; exit 0 ;;
            *) print_status "ERROR" "❌ Invalid option" ;;
        esac

        read -r -p "$(print_status "INPUT" "⏎ Press Enter...")"
    done
}

# -----------------------------
# Run
# -----------------------------
check_dependencies
main_menu
