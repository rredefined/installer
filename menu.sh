#!/bin/bash
set -euo pipefail

KVM_URL="https://raw.githubusercontent.com/rredefined/installer/main/kvm.sh"
VM_URL="https://raw.githubusercontent.com/rredefined/installer/main/vm.sh"

header() {
  clear
  cat <<'EOF'
===============================
   VM Manager Launcher Menu
===============================
EOF
}

run_script() {
  local url="$1"
  # Use bash directly, fail fast if download fails
  bash <(curl -fsSL "$url")
}

while true; do
  header
  echo "1) 🚀 KVM VM Manager"
  echo "2) 🐢 Non-KVM VM Manager"
  echo "0) ❌ Exit"
  echo

  read -r -p "Enter choice: " choice

  case "${choice:-}" in
    1)
      echo "Starting KVM VM Manager..."
      run_script "$KVM_URL"
      ;;
    2)
      echo "Starting Non-KVM VM Manager..."
      run_script "$VM_URL"
      ;;
    0)
      echo "Bye!"
      exit 0
      ;;
    *)
      echo "Invalid option. Try again."
      sleep 1
      ;;
  esac

  echo
  read -r -p "Press Enter to return to menu..."
done
