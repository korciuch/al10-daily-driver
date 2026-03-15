#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || exec sudo -E "$0" "$@"

IPU6_REPO="https://github.com/korciuch/al10-intel-ipu6.git"
IPU6_DIR="/opt/al10-intel-ipu6"

clone_ipu6() {
  [[ -d "$IPU6_DIR" ]] && return
  git clone --recurse-submodules "$IPU6_REPO" "$IPU6_DIR"
}

# Build checklist — devtools only on bare metal (requires GNOME Keyring)
if ! systemd-detect-virt -q; then
  CHECKLIST=(
    "camera"   "Intel IPU6 camera (Meteor Lake / XPS 16)"  OFF
    "audio"    "Intel SOF audio  (Meteor Lake / XPS 16)"   OFF
    "codecs"   "Multimedia codecs (RPM Fusion)"             OFF
    "devtools" "Dev tools (GPG key, SSH key, Claude Code)"  OFF
  )
  HEIGHT=22 ITEMS=4
else
  CHECKLIST=(
    "camera" "Intel IPU6 camera (Meteor Lake / XPS 16)"  OFF
    "audio"  "Intel SOF audio  (Meteor Lake / XPS 16)"   OFF
    "codecs" "Multimedia codecs (RPM Fusion)"             OFF
  )
  HEIGHT=20 ITEMS=3
fi

CHOICES=$(whiptail --title "al10-daily-driver Setup" \
  --checklist "Select modules to install (SPACE to toggle, ENTER to confirm):" \
  "$HEIGHT" 60 "$ITEMS" "${CHECKLIST[@]}" \
  3>&1 1>&2 2>&3) || exit 0

for choice in $CHOICES; do
  choice="${choice//\"/}"
  case "$choice" in
    camera) clone_ipu6; bash "$IPU6_DIR/setup.sh" ;;
    audio)  clone_ipu6; bash "$IPU6_DIR/audio/setup.sh" ;;
    codecs) dnf install -y ffmpeg gstreamer1-plugins-bad-free \
              gstreamer1-plugins-ugly-free gstreamer1-plugin-libav ;;
    devtools)
      ADMIN_HOME=$(getent passwd admin | cut -d: -f6)
      ADMIN_UID=$(id -u admin)
      export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${ADMIN_UID}/bus"

      # Prompt for key details
      GPG_NAME=$(whiptail --inputbox "Full name for GPG key:" 8 60 \
        3>&1 1>&2 2>&3) || exit 0
      GPG_EMAIL=$(whiptail --inputbox "Email for GPG/SSH keys:" 8 60 \
        3>&1 1>&2 2>&3) || exit 0
      GPG_EXPIRE=$(whiptail --inputbox "GPG key expiry (e.g. 2y, 1y, 0 = none):" 8 60 "2y" \
        3>&1 1>&2 2>&3) || exit 0

      # GPG key
      GPG_PASS=$(openssl rand -base64 32)
      sudo -u admin gpg --batch --gen-key <<EOF
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: ${GPG_NAME}
Name-Email: ${GPG_EMAIL}
Expire-Date: ${GPG_EXPIRE}
Passphrase: ${GPG_PASS}
EOF
      sudo -u admin --preserve-env=DBUS_SESSION_BUS_ADDRESS \
        bash -c "echo -n '${GPG_PASS}' | secret-tool store \
          --label='GPG Key Passphrase' service gpg account admin"

      # SSH key
      SSH_PASS=$(openssl rand -base64 32)
      mkdir -p "${ADMIN_HOME}/.ssh"
      chmod 700 "${ADMIN_HOME}/.ssh"
      sudo -u admin ssh-keygen -t ed25519 -C "${GPG_EMAIL}" \
        -f "${ADMIN_HOME}/.ssh/id_ed25519" -N "${SSH_PASS}"
      sudo -u admin --preserve-env=DBUS_SESSION_BUS_ADDRESS \
        bash -c "echo -n '${SSH_PASS}' | secret-tool store \
          --label='SSH Key Passphrase' service ssh account admin"

      # Configure gpg-agent to use pinentry-gnome3
      mkdir -p "${ADMIN_HOME}/.gnupg"
      echo "pinentry-program /usr/bin/pinentry-gnome3" \
        > "${ADMIN_HOME}/.gnupg/gpg-agent.conf"
      chown -R admin:admin "${ADMIN_HOME}/.gnupg"

      # Claude Code
      sudo -u admin bash -c "curl -fsSL https://claude.ai/install.sh | bash"
      ;;
  esac
done

echo "==> Done. Reboot to apply all changes."
