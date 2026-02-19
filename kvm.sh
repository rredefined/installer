#!/bin/bash
set -euo pipefail

# =============================
# Enhanced Multi-VM Manager (Pure QEMU Version)
# =============================

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

check_image_lock() {
    local img_file=$1
    local vm_name=$2

    if lsof "$img_file" 2>/dev/null | grep -q qemu-system; then
        print_status "WARN" "🔒 Image file $img_file is already in use by another QEMU process"
        local pid
        pid=$(lsof "$img_file" 2>/dev/null | grep qemu-system | awk '{print $2}' | head -1 || true)
        if [[ -n "${pid:-}" ]]; then
            print_status "INFO" "🔍 Process ID using the image: $pid"

            if ps -p "$pid" -o cmd= | grep -q "$vm_name"; then
                print_status "INFO" "🤔 This appears to be the same VM already running"
                read -r -p "$(print_status "INPUT" "🔄 Kill existing process and restart? (y/N): ")" kill_choice
                if [[ "$kill_choice" =~ ^[Yy]$ ]]; then
                    kill "$pid" || true
                    sleep 2
                    if kill -0 "$pid" 2>/dev/null; then
                        kill -9 "$pid" || true
                        print_status "WARN" "⚠️  Forcefully terminated process $pid"
                    fi
                    return 0
                else
                    return 1
                fi
            else
                print_status "ERROR" "🚫 Another QEMU instance is using this image"
                return 1
            fi
        fi
        return 1
    fi

    local lock_file="${img_file}.lock"
    if [[ -f "$lock_file" ]]; then
        print_status "WARN" "🔒 Lock file found: $lock_file"

        if [[ $(find "$lock_file" -mmin +5 2>/dev/null) ]]; then
            print_status "WARN" "⏰ Lock file appears stale (older than 5 minutes)"
            read -r -p "$(print_status "INPUT" "🗑️  Remove stale lock file? (y/N): ")" remove_lock
            if [[ "$remove_lock" =~ ^[Yy]$ ]]; then
                rm -f "$lock_file"
                print_status "SUCCESS" "✅ Removed stale lock file"
                return 0
            else
                return 1
            fi
        fi
        return 1
    fi
    return 0
}

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
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "lsof" "openssl")
    local missing_deps=()

    for dep in "${deps[@]}"; do
        command -v "$dep" &>/dev/null || missing_deps+=("$dep")
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "🔧 Missing dependencies: ${missing_deps[*]}"
        print_status "INFO" "💡 On Ubuntu/Debian, try: sudo apt install qemu-system cloud-image-utils wget lsof openssl"
        exit 1
    fi
}

cleanup() {
    rm -f user-data meta-data 2>/dev/null || true
}

get_vm_list() {
    find "$VM_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort
}

load_vm_config() {
    local vm_name=$1
    local config_file="$VM_DIR/$vm_name.conf"

    if [[ -f "$config_file" ]]; then
        unset VM_NAME OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD
        unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED
        source "$config_file"
        return 0
    else
        print_status "ERROR" "📂 Configuration for VM '$vm_name' not found"
        return 1
    fi
}

save_vm_config() {
    local config_file="$VM_DIR/$VM_NAME.conf"

    cat > "$config_file" <<EOF
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
CREATED="$CREATED"
EOF

    print_status "SUCCESS" "💾 Configuration saved to $config_file"
}

setup_vm_image() {
    print_status "INFO" "📥 Downloading and preparing image..."
    mkdir -p "$VM_DIR"

    if [[ -f "$IMG_FILE" ]]; then
        print_status "INFO" "✅ Image file already exists. Skipping download."
    else
        print_status "INFO" "🌐 Downloading image from $IMG_URL..."
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
}

is_vm_running() {
    local vm_name=$1
    pgrep -f "qemu-system.*$vm_name" >/dev/null && return 0
    if load_vm_config "$vm_name" 2>/dev/null; then
        pgrep -f "qemu-system.*$IMG_FILE" >/dev/null && return 0
    fi
    return 1
}

stop_vm() {
    local vm_name=$1
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            print_status "INFO" "🛑 Stopping VM: $vm_name"
            pkill -f "qemu-system.*$IMG_FILE" || true
            sleep 2
            if is_vm_running "$vm_name"; then
                print_status "WARN" "⚠️  Forcing termination..."
                pkill -9 -f "qemu-system.*$IMG_FILE" || true
                sleep 1
            fi
            rm -f "${IMG_FILE}.lock" 2>/dev/null || true
            print_status "SUCCESS" "✅ VM $vm_name stopped"
        else
            print_status "INFO" "💤 VM $vm_name is not running"
        fi
    fi
}

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

    while true; do
        read -r -p "$(print_status "INPUT" "🎯 Enter your choice (1-${#OS_OPTIONS[@]}): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#OS_OPTIONS[@]} ]; then
            local os="${os_options[$choice]}"
            IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD <<< "${OS_OPTIONS[$os]}"
            break
        else
            print_status "ERROR" "❌ Invalid selection. Try again."
        fi
    done

    while true; do
        read -r -p "$(print_status "INPUT" "🏷️  Enter VM name (default: $DEFAULT_HOSTNAME): ")" VM_NAME
        VM_NAME="${VM_NAME:-$DEFAULT_HOSTNAME}"
        if validate_input "name" "$VM_NAME"; then
            [[ -f "$VM_DIR/$VM_NAME.conf" ]] && { print_status "ERROR" "⚠️  VM '$VM_NAME' already exists"; } || break
        fi
    done

    read -r -p "$(print_status "INPUT" "🏠 Enter hostname (default: $VM_NAME): ")" HOSTNAME
    HOSTNAME="${HOSTNAME:-$VM_NAME}"

    read -r -p "$(print_status "INPUT" "👤 Enter username (default: $DEFAULT_USERNAME): ")" USERNAME
    USERNAME="${USERNAME:-$DEFAULT_USERNAME}"

    read -r -s -p "$(print_status "INPUT" "🔑 Enter password (default: $DEFAULT_PASSWORD): ")" PASSWORD
    PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
    echo

    read -r -p "$(print_status "INPUT" "💾 Disk size (default: 20G): ")" DISK_SIZE
    DISK_SIZE="${DISK_SIZE:-20G}"

    read -r -p "$(print_status "INPUT" "🧠 Memory in MB (default: 2048): ")" MEMORY
    MEMORY="${MEMORY:-2048}"

    read -r -p "$(print_status "INPUT" "⚡ Number of CPUs (default: 2): ")" CPUS
    CPUS="${CPUS:-2}"

    read -r -p "$(print_status "INPUT" "🔌 SSH Port (default: 2222): ")" SSH_PORT
    SSH_PORT="${SSH_PORT:-2222}"

    read -r -p "$(print_status "INPUT" "🖥️  Enable GUI mode? (y/n, default: n): ")" gui_input
    GUI_MODE=false
    gui_input="${gui_input:-n}"
    [[ "$gui_input" =~ ^[Yy]$ ]] && GUI_MODE=true

    read -r -p "$(print_status "INPUT" "🌐 Additional port forwards (e.g., 8080:80, press Enter for none): ")" PORT_FORWARDS

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date)"

    setup_vm_image
    save_vm_config
}

start_vm() {
    local vm_name=$1

    if load_vm_config "$vm_name"; then
        if ! check_image_lock "$IMG_FILE" "$vm_name"; then
            print_status "ERROR" "🔒 Cannot start VM: Image locked/in use"
            return 1
        fi

        if is_vm_running "$vm_name"; then
            print_status "WARN" "⚠️  VM '$vm_name' already running"
            return 1
        fi

        print_status "INFO" "🚀 Starting VM: $vm_name"
        print_status "INFO" "🐌 Running in pure software emulation mode (no KVM)"

        local qemu_cmd=(
            qemu-system-x86_64
            -m "$MEMORY"
            -smp "$CPUS"

            # ✅ CPU SPOOF HERE (Ryzen 9 7950X)
            -cpu "Dhyana,vendor=AuthenticAMD,model_id=AMD Ryzen 9 7950X 16-Core Processor"
            -smbios type=4,processor-version="AMD Ryzen 9 7950X 16-Core Processor"

            -machine type=pc,accel=tcg
            -drive "file=$IMG_FILE,format=qcow2,if=virtio"
            -drive "file=$SEED_FILE,format=raw,if=virtio"
            -boot order=c
            -device virtio-net-pci,netdev=n0
            -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22"
        )

        if [[ -n "${PORT_FORWARDS:-}" ]]; then
            IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
            for forward in "${forwards[@]}"; do
                IFS=':' read -r host_port guest_port <<< "$forward"
                qemu_cmd+=(-netdev "user,id=pf${host_port},hostfwd=tcp::${host_port}-:${guest_port}")
                qemu_cmd+=(-device "virtio-net-pci,netdev=pf${host_port}")
            done
        fi

        if [[ "$GUI_MODE" == true ]]; then
            qemu_cmd+=(-vga virtio -display gtk,gl=on)
        else
            qemu_cmd+=(-nographic -serial mon:stdio)
        fi

        qemu_cmd+=(
            -device virtio-balloon-pci
            -object rng-random,filename=/dev/urandom,id=rng0
            -device virtio-rng-pci,rng=rng0
            -no-hpet
            -rtc base=utc,clock=host
        )

        "${qemu_cmd[@]}"
    fi
}

main_menu() {
    while true; do
        display_header
        local vms=($(get_vm_list))
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
        fi
        echo "  0) 👋 Exit"
        echo

        read -r -p "$(print_status "INPUT" "🎯 Enter your choice: ")" choice

        case $choice in
            1) create_new_vm ;;
            2)
                if [ $vm_count -gt 0 ]; then
                    read -r -p "$(print_status "INPUT" "🚀 Enter VM number to start: ")" vm_num
                    start_vm "${vms[$((vm_num-1))]}"
                fi
                ;;
            3)
                if [ $vm_count -gt 0 ]; then
                    read -r -p "$(print_status "INPUT" "🛑 Enter VM number to stop: ")" vm_num
                    stop_vm "${vms[$((vm_num-1))]}"
                fi
                ;;
            0) print_status "INFO" "👋 Goodbye!"; exit 0 ;;
            *) print_status "ERROR" "❌ Invalid option" ;;
        esac

        read -r -p "$(print_status "INPUT" "⏎ Press Enter to continue...")"
    done
}

trap cleanup EXIT
check_dependencies

VM_DIR="${VM_DIR:-$HOME/vms}"
mkdir -p "$VM_DIR"

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
)

main_menu
