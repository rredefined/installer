#!/bin/bash
set -euo pipefail

# =========================================================
# Enhanced Multi-VM Manager (Pure QEMU / TCG - No KVM)
# CPU Spoof: AMD Ryzen 9 7950X (exact string)
# QEMU 6.2 compatible (NO -smbios processor-version)
#
# Features:
#  - Create / Start / Stop / Info / Edit / Delete
#  - Disk resize
#  - Performance view
#  - Fix issues (locks, seed recreate, kill stuck)
#  - Cloud-image OSes via cloud-init
#  - Proxmox VE ISO install mode (manual installer)
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
cleanup() {
    rm -f user-data meta-data 2>/dev/null || true
}
trap cleanup EXIT

validate_input() {
    local type=$1
    local value=$2

    case $type in
        "number")
            [[ "$value" =~ ^[0-9]+$ ]] || { print_status "ERROR" "❌ Must be a number"; return 1; }
            ;;
        "size")
            [[ "$value" =~ ^[0-9]+[GgMm]$ ]] || { print_status "ERROR" "❌ Must be a size with unit (e.g., 100G, 512M)"; return 1; }
            ;;
        "port")
            if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 23 ] || [ "$value" -gt 65535 ]; then
                print_status "ERROR" "❌ Must be a valid port number (23-65535)"
                return 1
            fi
            ;;
        "name")
            [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]] || { print_status "ERROR" "❌ VM name can only contain letters, numbers, hyphens, and underscores"; return 1; }
            ;;
        "username")
            [[ "$value" =~ ^[a-z_][a-z0-9_-]*$ ]] || { print_status "ERROR" "❌ Username must start with a letter or underscore, and contain only letters, numbers, hyphens, and underscores"; return 1; }
            ;;
    esac
    return 0
}

check_dependencies() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "lsof" "openssl" "ss" "pgrep" "pkill")
    local missing=()
    for dep in "${deps[@]}"; do
        command -v "$dep" &>/dev/null || missing+=("$dep")
    done
    if [ ${#missing[@]} -ne 0 ]; then
        print_status "ERROR" "🔧 Missing dependencies: ${missing[*]}"
        print_status "INFO"  "💡 Ubuntu/Debian: apt update && apt install -y qemu-system-x86 cloud-image-utils wget lsof openssl iproute2 procps"
        exit 1
    fi
}

get_vm_list() {
    find "$VM_DIR" -maxdepth 1 -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort
}

check_image_lock() {
    local img_file=$1
    local vm_name=$2

    if [[ -z "${img_file:-}" || ! -f "$img_file" ]]; then
        return 0
    fi

    if lsof "$img_file" 2>/dev/null | grep -q qemu-system; then
        print_status "WARN" "🔒 Image file $img_file is already in use"
        local pid
        pid=$(lsof "$img_file" 2>/dev/null | grep qemu-system | awk '{print $2}' | head -1 || true)
        if [[ -n "${pid:-}" ]]; then
            print_status "INFO" "🔍 PID using image: $pid"
            if ps -p "$pid" -o cmd= | grep -q "$vm_name"; then
                read -r -p "$(print_status "INPUT" "🔄 Kill existing process and restart? (y/N): ")" kill_choice
                if [[ "$kill_choice" =~ ^[Yy]$ ]]; then
                    kill "$pid" || true
                    sleep 2
                    if kill -0 "$pid" 2>/dev/null; then
                        kill -9 "$pid" || true
                        print_status "WARN" "⚠️ Force killed $pid"
                    fi
                    return 0
                fi
                return 1
            fi
        fi
        return 1
    fi

    local lock_file="${img_file}.lock"
    if [[ -f "$lock_file" ]]; then
        print_status "WARN" "🔒 Lock file found: $lock_file"
        if [[ $(find "$lock_file" -mmin +5 2>/dev/null) ]]; then
            read -r -p "$(print_status "INPUT" "🗑️ Remove stale lock file? (y/N): ")" remove_lock
            if [[ "$remove_lock" =~ ^[Yy]$ ]]; then
                rm -f "$lock_file"
                print_status "SUCCESS" "✅ Removed stale lock file"
                return 0
            fi
        fi
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
    if [[ ! -f "$cfg" ]]; then
        print_status "ERROR" "📂 Config not found for '$vm_name'"
        return 1
    fi

    unset VM_NAME OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD
    unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED
    unset ISO_FILE INSTALLED

    # shellcheck source=/dev/null
    source "$cfg"

    # Defaults for new fields if old config
    ISO_FILE="${ISO_FILE:-}"
    INSTALLED="${INSTALLED:-false}"
    GUI_MODE="${GUI_MODE:-false}"
    PORT_FORWARDS="${PORT_FORWARDS:-}"

    return 0
}

save_vm_config() {
    local cfg="$VM_DIR/$VM_NAME.conf"

    ISO_FILE="${ISO_FILE:-}"
    INSTALLED="${INSTALLED:-false}"

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
    # Proxmox is installer ISO (manual install)
    ["Proxmox VE (Installer ISO)"]="proxmox|ve|https://enterprise.proxmox.com/iso/proxmox-ve_8.3-1.iso|proxmox|root|changeme"
)

# -----------------------------
# Create VM
# -----------------------------
create_new_vm() {
    print_status "INFO" "🆕 Creating a new VM"
    print_status "INFO" "🌍 Select an OS to set up:"

    local os_options=()
    local i=1
    for os in "${!OS_OPTIONS[@]}"; do
        echo "  $i) $os"
        os_options[$i]="$os"
        ((i++))
    done

    local choice
    while true; do
        read -r -p "$(print_status "INPUT" "🎯 Enter your choice (1-${#OS_OPTIONS[@]}): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#OS_OPTIONS[@]} ]; then
            local os="${os_options[$choice]}"
            IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD <<< "${OS_OPTIONS[$os]}"
            break
        fi
        print_status "ERROR" "❌ Invalid selection"
    done

    while true; do
        read -r -p "$(print_status "INPUT" "🏷️ Enter VM name (default: $DEFAULT_HOSTNAME): ")" VM_NAME
        VM_NAME="${VM_NAME:-$DEFAULT_HOSTNAME}"
        if validate_input "name" "$VM_NAME"; then
            [[ -f "$VM_DIR/$VM_NAME.conf" ]] && { print_status "ERROR" "⚠️ VM '$VM_NAME' already exists"; continue; }
            break
        fi
    done

    while true; do
        read -r -p "$(print_status "INPUT" "🏠 Hostname (default: $VM_NAME): ")" HOSTNAME
        HOSTNAME="${HOSTNAME:-$VM_NAME}"
        validate_input "name" "$HOSTNAME" && break
    done

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
                print_status "ERROR" "🚫 Port $SSH_PORT is already in use"
            else
                break
            fi
        fi
    done

    while true; do
        read -r -p "$(print_status "INPUT" "🖥️ Enable GUI mode? (y/n, default: n): ")" gui_input
        gui_input="${gui_input:-n}"
        if [[ "$gui_input" =~ ^[Yy]$ ]]; then
            GUI_MODE=true
            break
        elif [[ "$gui_input" =~ ^[Nn]$ ]]; then
            GUI_MODE=false
            break
        else
            print_status "ERROR" "❌ Please answer y or n"
        fi
    done

    read -r -p "$(print_status "INPUT" "🌐 Additional port forwards (e.g., 8080:80, Enter for none): ")" PORT_FORWARDS

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

    # Proxmox ISO installer mode
    if [[ "$OS_TYPE" == "proxmox" ]]; then
        ISO_FILE="$ISO_DIR/${VM_NAME}.iso"

        if [[ ! -f "$ISO_FILE" ]]; then
            print_status "INFO" "🌐 Downloading Proxmox ISO..."
            wget --progress=bar:force "$IMG_URL" -O "$ISO_FILE.tmp"
            mv "$ISO_FILE.tmp" "$ISO_FILE"
        else
            print_status "INFO" "✅ Proxmox ISO already exists: $ISO_FILE"
        fi

        if [[ ! -f "$IMG_FILE" ]]; then
            print_status "INFO" "💾 Creating disk image $IMG_FILE ($DISK_SIZE)..."
            qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"
        fi

        SEED_FILE=""
        print_status "SUCCESS" "🎉 Proxmox installer prepared (manual install)."
        print_status "INFO" "📝 After install, set INSTALLED=true in $VM_DIR/$VM_NAME.conf"
        return 0
    fi

    # Cloud image mode
    if [[ -f "$IMG_FILE" ]]; then
        print_status "INFO" "✅ Image file exists. Skipping download."
    else
        print_status "INFO" "🌐 Downloading image..."
        wget --progress=bar:force "$IMG_URL" -O "$IMG_FILE.tmp"
        mv "$IMG_FILE.tmp" "$IMG_FILE"
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

    print_status "SUCCESS" "🎉 VM '$VM_NAME' created successfully."
    print_status "INFO" "🔌 SSH: ssh -p $SSH_PORT $USERNAME@localhost"
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
# Start/Stop
# -----------------------------
start_vm() {
    local vm_name=$1
    load_vm_config "$vm_name" || return 1

    # Lock check only if disk exists
    if [[ -n "${IMG_FILE:-}" && -f "$IMG_FILE" ]]; then
        if ! check_image_lock "$IMG_FILE" "$vm_name"; then
            print_status "ERROR" "🔒 Cannot start: image locked"
            read -r -p "$(print_status "INPUT" "💀 Force kill processes using this image? (y/N): ")" fk
            if [[ "$fk" =~ ^[Yy]$ ]]; then
                pkill -f "qemu-system.*$IMG_FILE" || true
                sleep 2
                pkill -9 -f "qemu-system.*$IMG_FILE" 2>/dev/null || true
                rm -f "${IMG_FILE}.lock" 2>/dev/null || true
            else
                return 1
            fi
        fi
    fi

    if is_vm_running "$vm_name"; then
        print_status "WARN" "⚠️ VM '$vm_name' already running"
        return 1
    fi

    # Ensure files exist
    if [[ "$OS_TYPE" == "proxmox" ]]; then
        ISO_FILE="${ISO_FILE:-$ISO_DIR/${VM_NAME}.iso}"
        [[ -f "$IMG_FILE" ]] || { print_status "ERROR" "❌ Disk not found: $IMG_FILE"; return 1; }
        [[ -f "$ISO_FILE" ]] || { print_status "ERROR" "❌ ISO not found: $ISO_FILE"; return 1; }
    else
        [[ -f "$IMG_FILE" ]] || { print_status "ERROR" "❌ Image not found: $IMG_FILE"; return 1; }
        [[ -f "$SEED_FILE" ]] || { print_status "WARN" "⚠️ Seed missing, recreating..."; setup_vm_image; }
    fi

    print_status "INFO" "🚀 Starting VM: $vm_name"
    print_status "INFO" "🐌 Mode: software emulation (TCG) | CPU spoof: AMD Ryzen 9 7950X"
    print_status "INFO" "🔌 SSH: ssh -p $SSH_PORT $USERNAME@localhost"

    # Base command
    local qemu_cmd=(
        qemu-system-x86_64
        -m "$MEMORY"
        -smp "$CPUS"
        -cpu "qemu64,vendor=AuthenticAMD,model_id=AMD Ryzen 9 7950X"
        -machine type=pc,accel=tcg
        -drive "file=$IMG_FILE,format=qcow2,if=virtio"
    )

    # Cloud-init seed (only for cloud images)
    if [[ "$OS_TYPE" != "proxmox" && -n "${SEED_FILE:-}" ]]; then
        qemu_cmd+=(-drive "file=$SEED_FILE,format=raw,if=virtio")
        qemu_cmd+=(-boot order=c)
    fi

    # Proxmox ISO boot handling
    if [[ "$OS_TYPE" == "proxmox" ]]; then
        if [[ "${INSTALLED:-false}" == "true" ]]; then
            qemu_cmd+=(-boot order=c)
            print_status "INFO" "💿 Booting Proxmox from disk (INSTALLED=true)"
        else
            qemu_cmd+=(-cdrom "$ISO_FILE" -boot order=d,c)
            print_status "INFO" "📀 Booting Proxmox installer ISO (INSTALLED=false)"
            print_status "INFO" "✅ After install: set INSTALLED=\"true\" in $VM_DIR/$VM_NAME.conf"
        fi
    fi

    # Networking: primary NIC with SSH forward
    qemu_cmd+=(
        -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22"
        -device "virtio-net-pci,netdev=n0"
    )

    # Additional port forwards
    if [[ -n "${PORT_FORWARDS:-}" ]]; then
        IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
        for forward in "${forwards[@]}"; do
            IFS=':' read -r host_port guest_port <<< "$forward"
            [[ -n "${host_port:-}" && -n "${guest_port:-}" ]] || continue
            qemu_cmd+=(-netdev "user,id=pf${host_port},hostfwd=tcp::${host_port}-:${guest_port}")
            qemu_cmd+=(-device "virtio-net-pci,netdev=pf${host_port}")
        done
    fi

    # Display mode
    if [[ "$OS_TYPE" == "proxmox" ]]; then
        # Proxmox installer is easiest with GUI
        qemu_cmd+=(-vga virtio -display gtk)
        print_status "INFO" "🖥️ Proxmox uses GUI (GTK)"
    else
        if [[ "$GUI_MODE" == "true" ]]; then
            qemu_cmd+=(-vga virtio -display gtk,gl=on)
            print_status "INFO" "🖥️ GUI mode enabled"
        else
            qemu_cmd+=(-nographic -serial mon:stdio)
            print_status "INFO" "📟 Console mode | Exit: Ctrl+A then X"
        fi
    fi

    # Extras
    qemu_cmd+=(
        -device virtio-balloon-pci
        -object rng-random,filename=/dev/urandom,id=rng0
        -device virtio-rng-pci,rng=rng0
        -no-hpet
        -rtc base=utc,clock=host
    )

    "${qemu_cmd[@]}"
}

stop_vm() {
    local vm_name=$1
    load_vm_config "$vm_name" || return 1

    if is_vm_running "$vm_name"; then
        print_status "INFO" "🛑 Stopping VM: $vm_name"
        if [[ -n "${IMG_FILE:-}" ]]; then
            pkill -f "qemu-system.*$IMG_FILE" || true
            sleep 2
            pgrep -f "qemu-system.*$IMG_FILE" >/dev/null && pkill -9 -f "qemu-system.*$IMG_FILE" || true
            rm -f "${IMG_FILE}.lock" 2>/dev/null || true
        else
            pkill -f "qemu-system.*$vm_name" || true
        fi
        print_status "SUCCESS" "✅ VM stopped"
    else
        print_status "INFO" "💤 VM is not running"
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
    print_status "WARN" "⚠️ This will permanently delete VM '$vm_name' (disk + config)!"
    read -r -p "$(print_status "INPUT" "🗑️ Are you sure? (y/N): ")" ans
    [[ "$ans" =~ ^[Yy]$ ]] || { print_status "INFO" "Cancelled"; return 0; }

    load_vm_config "$vm_name" || return 1

    if is_vm_running "$vm_name"; then
        print_status "WARN" "VM running, stopping first..."
        stop_vm "$vm_name"
    fi

    rm -f "$VM_DIR/$vm_name.conf" 2>/dev/null || true
    [[ -n "${IMG_FILE:-}" ]] && rm -f "$IMG_FILE" "${IMG_FILE}.lock" 2>/dev/null || true
    [[ -n "${SEED_FILE:-}" ]] && rm -f "$SEED_FILE" 2>/dev/null || true
    [[ -n "${ISO_FILE:-}" ]] && rm -f "$ISO_FILE" 2>/dev/null || true

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
        echo "  6) 🌐 Port Forwards"
        echo "  7) 🧠 Memory (RAM)"
        echo "  8) ⚡ CPU Count"
        echo "  9) 💾 Disk Size (config only)"
        if [[ "$OS_TYPE" == "proxmox" ]]; then
            echo " 10) ✅ Toggle INSTALLED (Proxmox)"
        fi
        echo "  0) ↩️ Back"
        echo

        read -r -p "$(print_status "INPUT" "🎯 Choice: ")" c
        case $c in
            1)
                read -r -p "$(print_status "INPUT" "New hostname (current: $HOSTNAME): ")" v
                v="${v:-$HOSTNAME}"
                validate_input "name" "$v" && HOSTNAME="$v"
                ;;
            2)
                read -r -p "$(print_status "INPUT" "New username (current: $USERNAME): ")" v
                v="${v:-$USERNAME}"
                validate_input "username" "$v" && USERNAME="$v"
                ;;
            3)
                read -r -s -p "$(print_status "INPUT" "New password: ")" v
                echo
                [[ -n "${v:-}" ]] && PASSWORD="$v"
                ;;
            4)
                read -r -p "$(print_status "INPUT" "New SSH port (current: $SSH_PORT): ")" v
                v="${v:-$SSH_PORT}"
                if validate_input "port" "$v"; then
                    if [[ "$v" != "$SSH_PORT" ]] && ss -tln 2>/dev/null | grep -q ":$v "; then
                        print_status "ERROR" "🚫 Port $v is in use"
                    else
                        SSH_PORT="$v"
                    fi
                fi
                ;;
            5)
                read -r -p "$(print_status "INPUT" "Enable GUI? (y/n, current: $GUI_MODE): ")" v
                if [[ "${v:-}" =~ ^[Yy]$ ]]; then GUI_MODE=true; fi
                if [[ "${v:-}" =~ ^[Nn]$ ]]; then GUI_MODE=false; fi
                ;;
            6)
                read -r -p "$(print_status "INPUT" "Port forwards (current: ${PORT_FORWARDS:-None}): ")" v
                PORT_FORWARDS="${v:-$PORT_FORWARDS}"
                ;;
            7)
                read -r -p "$(print_status "INPUT" "Memory MB (current: $MEMORY): ")" v
                v="${v:-$MEMORY}"
                validate_input "number" "$v" && MEMORY="$v"
                ;;
            8)
                read -r -p "$(print_status "INPUT" "CPU count (current: $CPUS): ")" v
                v="${v:-$CPUS}"
                validate_input "number" "$v" && CPUS="$v"
                ;;
            9)
                read -r -p "$(print_status "INPUT" "Disk size (current: $DISK_SIZE): ")" v
                v="${v:-$DISK_SIZE}"
                validate_input "size" "$v" && DISK_SIZE="$v"
                ;;
            10)
                if [[ "$OS_TYPE" == "proxmox" ]]; then
                    if [[ "${INSTALLED:-false}" == "true" ]]; then
                        INSTALLED="false"
                    else
                        INSTALLED="true"
                    fi
                    print_status "SUCCESS" "✅ INSTALLED is now: $INSTALLED"
                fi
                ;;
            0) break ;;
            *) print_status "ERROR" "❌ Invalid option" ;;
        esac

        # If cloud image identity changed, rebuild seed (not for proxmox)
        if [[ "$OS_TYPE" != "proxmox" && ( "$c" == "1" || "$c" == "2" || "$c" == "3" ) ]]; then
            print_status "INFO" "🔄 Rebuilding cloud-init seed..."
            setup_vm_image
        fi

        save_vm_config
        read -r -p "$(print_status "INPUT" "⏎ Press Enter to continue...")"
    done
}

# -----------------------------
# Resize disk (qemu-img resize)
# -----------------------------
resize_vm_disk() {
    local vm_name=$1
    load_vm_config "$vm_name" || return 1

    if is_vm_running "$vm_name"; then
        print_status "ERROR" "❌ Stop VM before resizing disk"
        return 1
    fi

    print_status "INFO" "💾 Current disk size setting: $DISK_SIZE"
    read -r -p "$(print_status "INPUT" "📈 New disk size (e.g., 50G): ")" new_size
    validate_input "size" "$new_size" || return 1

    print_status "INFO" "📈 Resizing disk image..."
    qemu-img resize "$IMG_FILE" "$new_size"
    DISK_SIZE="$new_size"
    save_vm_config
    print_status "SUCCESS" "✅ Disk resized to $new_size"
}

# -----------------------------
# Performance
# -----------------------------
show_vm_performance() {
    local vm_name=$1
    load_vm_config "$vm_name" || return 1

    if ! is_vm_running "$vm_name"; then
        print_status "INFO" "💤 VM not running"
        read -r -p "$(print_status "INPUT" "⏎ Press Enter...")"
        return 0
    fi

    local pid=""
    if [[ -n "${IMG_FILE:-}" ]]; then
        pid=$(pgrep -f "qemu-system.*$IMG_FILE" | head -n1 || true)
    else
        pid=$(pgrep -f "qemu-system.*$vm_name" | head -n1 || true)
    fi

    print_status "INFO" "📊 Performance: $vm_name"
    echo "--------------------------------------------"
    echo "PID: ${pid:-unknown}"
    if [[ -n "${pid:-}" ]]; then
        ps -p "$pid" -o pid,%cpu,%mem,rss,vsz,cmd --no-headers || true
    fi
    echo
    free -h || true
    echo
    if [[ -n "${IMG_FILE:-}" && -f "$IMG_FILE" ]]; then
        du -h "$IMG_FILE" 2>/dev/null || true
    fi
    echo "--------------------------------------------"
    read -r -p "$(print_status "INPUT" "⏎ Press Enter...")"
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
        1)
            [[ -n "${IMG_FILE:-}" ]] && rm -f "${IMG_FILE}.lock" "${IMG_FILE}"*.lock 2>/dev/null || true
            print_status "SUCCESS" "✅ Lock files removed"
            ;;
        2)
            if [[ "$OS_TYPE" == "proxmox" ]]; then
                print_status "WARN" "Proxmox doesn’t use cloud-init seed."
            else
                rm -f "$SEED_FILE" 2>/dev/null || true
                setup_vm_image
                print_status "SUCCESS" "✅ Seed recreated"
            fi
            ;;
        3)
            save_vm_config
            print_status "SUCCESS" "✅ Config rewritten"
            ;;
        4)
            if [[ -n "${IMG_FILE:-}" ]]; then
                pkill -f "qemu-system.*$IMG_FILE" 2>/dev/null || true
                sleep 1
                pkill -9 -f "qemu-system.*$IMG_FILE" 2>/dev/null || true
            else
                pkill -f "qemu-system.*$vm_name" 2>/dev/null || true
                sleep 1
                pkill -9 -f "qemu-system.*$vm_name" 2>/dev/null || true
            fi
            print_status "SUCCESS" "✅ Killed stuck processes"
            ;;
        0) return 0 ;;
        *) print_status "ERROR" "❌ Invalid option" ;;
    esac

    read -r -p "$(print_status "INPUT" "⏎ Press Enter...")"
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
            print_status "INFO" "📁 Found $vm_count existing VM(s):"
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

        read -r -p "$(print_status "INPUT" "🎯 Enter your choice: ")" choice

        case $choice in
            1) create_new_vm ;;
            2)
                [ $vm_count -gt 0 ] || continue
                read -r -p "$(print_status "INPUT" "🚀 Enter VM number to start: ")" vm_num
                if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                    start_vm "${vms[$((vm_num-1))]}"
                else
                    print_status "ERROR" "❌ Invalid selection"
                fi
                ;;
            3)
                [ $vm_count -gt 0 ] || continue
                read -r -p "$(print_status "INPUT" "🛑 Enter VM number to stop: ")" vm_num
                if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                    stop_vm "${vms[$((vm_num-1))]}"
                else
                    print_status "ERROR" "❌ Invalid selection"
                fi
                ;;
            4)
                [ $vm_count -gt 0 ] || continue
                read -r -p "$(print_status "INPUT" "📊 Enter VM number: ")" vm_num
                if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                    show_vm_info "${vms[$((vm_num-1))]}"
                else
                    print_status "ERROR" "❌ Invalid selection"
                fi
                ;;
            5)
                [ $vm_count -gt 0 ] || continue
                read -r -p "$(print_status "INPUT" "✏️ Enter VM number: ")" vm_num
                if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                    edit_vm_config "${vms[$((vm_num-1))]}"
                else
                    print_status "ERROR" "❌ Invalid selection"
                fi
                ;;
            6)
                [ $vm_count -gt 0 ] || continue
                read -r -p "$(print_status "INPUT" "🗑️ Enter VM number: ")" vm_num
                if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                    delete_vm "${vms[$((vm_num-1))]}"
                else
                    print_status "ERROR" "❌ Invalid selection"
                fi
                ;;
            7)
                [ $vm_count -gt 0 ] || continue
                read -r -p "$(print_status "INPUT" "📈 Enter VM number: ")" vm_num
                if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                    resize_vm_disk "${vms[$((vm_num-1))]}"
                else
                    print_status "ERROR" "❌ Invalid selection"
                fi
                ;;
            8)
                [ $vm_count -gt 0 ] || continue
                read -r -p "$(print_status "INPUT" "📊 Enter VM number: ")" vm_num
                if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                    show_vm_performance "${vms[$((vm_num-1))]}"
                else
                    print_status "ERROR" "❌ Invalid selection"
                fi
                ;;
            9)
                [ $vm_count -gt 0 ] || continue
                read -r -p "$(print_status "INPUT" "🔧 Enter VM number: ")" vm_num
                if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                    fix_vm_issues "${vms[$((vm_num-1))]}"
                else
                    print_status "ERROR" "❌ Invalid selection"
                fi
                ;;
            0)
                print_status "INFO" "👋 Goodbye!"
                exit 0
                ;;
            *)
                print_status "ERROR" "❌ Invalid option"
                ;;
        esac

        read -r -p "$(print_status "INPUT" "⏎ Press Enter to continue...")"
    done
}

# -----------------------------
# Run
# -----------------------------
check_dependencies
main_menu
