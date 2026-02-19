#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-install}"   # install | boot | status | stop

VM_DIR="/var/lib/vm"
ISO_DIR="/var/lib/iso"
DISK="${VM_DIR}/vm.qcow2"
ISO="${ISO_DIR}/ubuntu.iso"

# Your requested specs
RAM_MB=65536           # 64GB
VCPUS=16
DISK_SIZE="80G"

# VNC (localhost only)
VNC_ADDR="127.0.0.1:1" # => TCP 5901

# CPU name string (display/brand string)
CPU_BRAND='AMD Ryzen 9 7950X 16-Core Processor'

PIDFILE="/run/qemu-vm.pid"
LOGFILE="/var/log/qemu-vm.log"

need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run as root (or use sudo)." >&2
    exit 1
  fi
}

check_kvm() {
  if [[ ! -e /dev/kvm ]]; then
    echo "ERROR: /dev/kvm not found. KVM acceleration is not available on this host." >&2
    exit 1
  fi
}

ensure_paths() {
  mkdir -p "$VM_DIR" "$ISO_DIR"
}

ensure_disk() {
  if [[ ! -f "$DISK" ]]; then
    echo "Creating disk: $DISK ($DISK_SIZE)"
    qemu-img create -f qcow2 "$DISK" "$DISK_SIZE"
  fi
}

ensure_iso() {
  if [[ ! -f "$ISO" ]]; then
    echo "Ubuntu ISO not found at $ISO"
    echo "Downloading Ubuntu 22.04.5 Server ISO..."
    wget -O "$ISO" "https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso"
  fi
}

start_vm_install() {
  echo "Starting VM in INSTALL mode (boots ISO) ..."
  echo "VNC: tunnel with  ssh -L 5901:127.0.0.1:5901 root@<server-ip>  then connect VNC to 127.0.0.1:5901"

  # -daemonize runs in background
  qemu-system-x86_64 -enable-kvm \
    -machine q35 \
    -m "$RAM_MB" \
    -smp "$VCPUS" \
    -cpu host \
    -global "cpu.model-id=${CPU_BRAND}" \
    -drive "file=${DISK},if=virtio,format=qcow2" \
    -cdrom "$ISO" \
    -boot order=d \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -vnc "$VNC_ADDR" \
    -display none \
    -daemonize \
    -pidfile "$PIDFILE" \
    -D "$LOGFILE"

  echo "Started. PID: $(cat "$PIDFILE")"
  echo "Log: $LOGFILE"
}

start_vm_boot() {
  echo "Starting VM in BOOT mode (boots from disk) ..."
  echo "VNC: tunnel with  ssh -L 5901:127.0.0.1:5901 root@<server-ip>  then connect VNC to 127.0.0.1:5901"

  qemu-system-x86_64 -enable-kvm \
    -machine q35 \
    -m "$RAM_MB" \
    -smp "$VCPUS" \
    -cpu host \
    -global "cpu.model-id=${CPU_BRAND}" \
    -drive "file=${DISK},if=virtio,format=qcow2" \
    -boot order=c \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -vnc "$VNC_ADDR" \
    -display none \
    -daemonize \
    -pidfile "$PIDFILE" \
    -D "$LOGFILE"

  echo "Started. PID: $(cat "$PIDFILE")"
  echo "Log: $LOGFILE"
}

status_vm() {
  if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "VM running. PID: $(cat "$PIDFILE")"
    ss -tlnp | grep 5901 || true
  else
    echo "VM not running."
  fi
}

stop_vm() {
  if [[ -f "$PIDFILE" ]]; then
    PID="$(cat "$PIDFILE")"
    if kill -0 "$PID" 2>/dev/null; then
      echo "Stopping VM PID $PID ..."
      kill "$PID"
      sleep 2
      kill -0 "$PID" 2>/dev/null && kill -9 "$PID" || true
      echo "Stopped."
    else
      echo "PID file exists but process not running."
    fi
    rm -f "$PIDFILE"
  else
    echo "No PID file, VM not running."
  fi
}

main() {
  need_root
  check_kvm
  ensure_paths

  case "$MODE" in
    install)
      ensure_disk
      ensure_iso
      start_vm_install
      ;;
    boot)
      ensure_disk
      start_vm_boot
      ;;
    status)
      status_vm
      ;;
    stop)
      stop_vm
      ;;
    *)
      echo "Usage: $0 {install|boot|status|stop}"
      exit 1
      ;;
  esac
}

main
