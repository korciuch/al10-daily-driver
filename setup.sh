#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || exec sudo -E "$0" "$@"

IPU6_REPO="https://github.com/korciuch/al10-intel-ipu6.git"
IPU6_DIR="/opt/al10-intel-ipu6"

clone_ipu6() {
  if [[ ! -d "$IPU6_DIR" ]]; then
    git clone --recurse-submodules "$IPU6_REPO" "$IPU6_DIR"
  elif [[ ! -f "$IPU6_DIR/ipu6-drivers/dkms.conf" ]]; then
    git -C "$IPU6_DIR" submodule update --init --recursive
  fi
}

# Build checklist — devtools only on bare metal (requires GNOME Keyring)
if ! systemd-detect-virt -q; then
  CHECKLIST=(
    "camera"      "Intel IPU6 camera (Meteor Lake / XPS 16)"  OFF
    "audio"       "Intel SOF audio  (Meteor Lake / XPS 16)"   OFF
    "codecs"      "Multimedia codecs + VLC (RPM Fusion)"      OFF
    "obs"         "OBS Studio (RPM Fusion)"                   OFF
    "chrome"      "Google Chrome"                             OFF
    "openscreen"  "OpenScreen (screen sharing AppImage)"      OFF
    "devtools"    "Dev tools (GPG key, SSH key, Claude Code)" OFF
  )
  HEIGHT=26 ITEMS=7
else
  CHECKLIST=(
    "camera"     "Intel IPU6 camera (Meteor Lake / XPS 16)"  OFF
    "audio"      "Intel SOF audio  (Meteor Lake / XPS 16)"   OFF
    "codecs"     "Multimedia codecs + VLC (RPM Fusion)"       OFF
    "obs"        "OBS Studio (RPM Fusion)"                    OFF
    "chrome"     "Google Chrome"                              OFF
    "openscreen" "OpenScreen (screen sharing AppImage)"       OFF
  )
  HEIGHT=24 ITEMS=6
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
              gstreamer1-plugins-ugly-free gstreamer1-plugin-libav vlc ;;
    obs)
      dnf install -y libcamera-v4l2 flatpak
      flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
      flatpak install -y flathub com.obsproject.Studio
      flatpak override --user --device=all com.obsproject.Studio
      ;;

    chrome)
      dnf install -y \
        https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm ;;

    openscreen)
      curl -L -o /opt/Openscreen.AppImage \
        https://github.com/siddharthvaddem/openscreen/releases/download/v1.2.0/Openscreen-Linux-latest.AppImage
      chmod +x /opt/Openscreen.AppImage
      cat > /usr/local/share/applications/openscreen.desktop <<'DESKTOP'
[Desktop Entry]
Name=OpenScreen
Exec=/opt/Openscreen.AppImage --no-sandbox
Icon=video-display
Type=Application
Categories=Network;
DESKTOP
      update-desktop-database /usr/local/share/applications 2>/dev/null || true
      ;;

    devtools)
      ADMIN_USER="${SUDO_USER:-admin}"
      ADMIN_HOME=$(getent passwd "${ADMIN_USER}" | cut -d: -f6)
      ADMIN_UID=$(id -u "${ADMIN_USER}")
      export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${ADMIN_UID}/bus"

      as_admin() {
        sudo -u "${ADMIN_USER}" --preserve-env=DBUS_SESSION_BUS_ADDRESS,DISPLAY "$@"
      }

      # ── GitHub auth ────────────────────────────────────────────────────────
      echo "==> Checking GitHub authentication..."
      REQUIRED_SCOPES="user read:user user:email write:gpg_key"
      NEEDS_LOGIN=false
      NEEDS_SCOPE=false

      if ! as_admin gh auth status &>/dev/null; then
        NEEDS_LOGIN=true
      else
        AUTH_STATUS=$(as_admin gh auth status 2>&1)
        for scope in $REQUIRED_SCOPES; do
          if ! echo "$AUTH_STATUS" | grep -q "$scope"; then
            NEEDS_SCOPE=true; break
          fi
        done
      fi

      if $NEEDS_LOGIN; then
        as_admin gh auth login \
          --hostname github.com --git-protocol ssh --web \
          --scopes "user,read:user,user:email,write:gpg_key"
      elif $NEEDS_SCOPE; then
        as_admin gh auth refresh \
          --hostname github.com \
          --scopes "user,read:user,user:email,write:gpg_key"
      else
        echo "  ok Already authenticated with GitHub"
      fi

      GH_USER=$(as_admin gh api user --jq '.login')
      GH_EMAIL=$(as_admin gh api user/emails --jq '[.[] | select(.primary==true)] | .[0].email')
      GH_NAME=$(as_admin gh api user --jq '.name // .login')
      echo "  ok $GH_USER ($GH_NAME <$GH_EMAIL>)"

      # ── GPG key ────────────────────────────────────────────────────────────
      echo "==> Checking for existing GPG key for $GH_EMAIL..."
      GPG_FP=$(as_admin gpg --list-secret-keys --with-colons "$GH_EMAIL" 2>/dev/null \
        | awk -F: '/^fpr/{print $10; exit}') || true

      if [[ -n "$GPG_FP" ]]; then
        echo "  warn GPG key already exists ($GPG_FP) -- skipping generation"
      else
        echo "==> Generating 4096-bit RSA GPG key..."
        GPG_BATCH=$(mktemp)
        cat > "$GPG_BATCH" <<EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: ${GH_NAME}
Name-Email: ${GH_EMAIL}
Expire-Date: 2y
%commit
EOF
        as_admin gpg --batch --gen-key "$GPG_BATCH"
        rm -f "$GPG_BATCH"
        GPG_FP=$(as_admin gpg --list-secret-keys --with-colons "$GH_EMAIL" \
          | awk -F: '/^fpr/{print $10; exit}')
        echo "  ok GPG key generated ($GPG_FP)"
      fi

      GPG_KEY_ID=$(as_admin gpg --list-secret-keys --with-colons "$GH_EMAIL" 2>/dev/null \
        | awk -F: '/^sec/{print $5; exit}')
      [[ -n "$GPG_KEY_ID" ]] || { echo "ERROR: failed to extract GPG key ID"; exit 1; }

      if as_admin gh gpg-key list 2>/dev/null | grep -q "$GPG_KEY_ID"; then
        echo "  warn GPG key already on GitHub -- skipping upload"
      else
        as_admin gpg --armor --export "$GPG_FP" \
          | as_admin gh gpg-key add - --title "git-signing-$(hostname)-$(date +%Y%m%d)"
        echo "  ok GPG public key added to GitHub"
      fi

      # Configure pinentry-gnome3
      mkdir -p "${ADMIN_HOME}/.gnupg"
      if ! grep -q "pinentry-program" "${ADMIN_HOME}/.gnupg/gpg-agent.conf" 2>/dev/null; then
        echo "pinentry-program /usr/bin/pinentry-gnome3" \
          >> "${ADMIN_HOME}/.gnupg/gpg-agent.conf"
      fi
      chown -R "${ADMIN_USER}:${ADMIN_USER}" "${ADMIN_HOME}/.gnupg"

      # ── SSH key ────────────────────────────────────────────────────────────
      echo "==> Checking for SSH key..."
      SSH_KEY_PATH="${ADMIN_HOME}/.ssh/id_ed25519_github_${GH_USER}"
      mkdir -p "${ADMIN_HOME}/.ssh"
      chmod 700 "${ADMIN_HOME}/.ssh"
      chown "${ADMIN_USER}:${ADMIN_USER}" "${ADMIN_HOME}/.ssh"

      if [[ -f "$SSH_KEY_PATH" ]]; then
        echo "  warn SSH key already exists at $SSH_KEY_PATH -- skipping generation"
      else
        as_admin ssh-keygen -t ed25519 -C "$GH_EMAIL" -f "$SSH_KEY_PATH" -N ""
        echo "  ok SSH key written to $SSH_KEY_PATH"
      fi

      UPLOAD_OUT=$(as_admin gh ssh-key add "${SSH_KEY_PATH}.pub" \
        --title "git-auth-$(hostname)-$(date +%Y%m%d)" \
        --type authentication 2>&1) && \
        echo "  ok SSH public key added to GitHub" || {
          if echo "$UPLOAD_OUT" | grep -qiE "already|422|validation"; then
            echo "  warn SSH key already on GitHub -- skipping upload"
          else
            echo "ERROR: SSH key upload failed: $UPLOAD_OUT" >&2; exit 1
          fi
        }

      SSH_CONFIG="${ADMIN_HOME}/.ssh/config"
      touch "$SSH_CONFIG"
      chmod 600 "$SSH_CONFIG"
      chown "${ADMIN_USER}:${ADMIN_USER}" "$SSH_CONFIG"
      if ! grep -q "Host github.com" "$SSH_CONFIG" 2>/dev/null; then
        cat >> "$SSH_CONFIG" <<EOF

Host github.com
  HostName github.com
  User git
  IdentityFile ${SSH_KEY_PATH}
  AddKeysToAgent yes
EOF
        echo "  ok SSH config entry added for github.com"
      else
        echo "  warn ~/.ssh/config already has a github.com entry -- not modified"
      fi

      ssh-keyscan github.com >> "${ADMIN_HOME}/.ssh/known_hosts" 2>/dev/null
      chown "${ADMIN_USER}:${ADMIN_USER}" "${ADMIN_HOME}/.ssh/known_hosts"

      # ── Git global config ──────────────────────────────────────────────────
      echo "==> Configuring git globals..."
      as_admin git config --global user.name  "$GH_NAME"
      as_admin git config --global user.email "$GH_EMAIL"
      as_admin git config --global user.signingkey "$GPG_FP"
      as_admin git config --global commit.gpgsign true
      as_admin git config --global tag.gpgsign true
      as_admin git config --global gpg.program gpg
      git -C /opt/al10-daily-driver config \
        remote.origin.url "git@github.com:${GH_USER}/al10-daily-driver.git"
      echo "  ok Git globals updated"

      # ── SSH smoke test ─────────────────────────────────────────────────────
      echo "==> Testing SSH connection to GitHub..."
      SSH_TEST=$(as_admin ssh -T git@github.com \
        -o StrictHostKeyChecking=accept-new 2>&1 || true)
      if echo "$SSH_TEST" | grep -q "successfully authenticated"; then
        echo "  ok SSH auth to GitHub confirmed"
      else
        echo "  warn SSH test output: $SSH_TEST"
      fi

      # ── Claude Code + Zed ─────────────────────────────────────────────────
      as_admin bash -c "curl -fsSL https://claude.ai/install.sh | bash"
      as_admin bash -c "curl -f https://zed.dev/install.sh | sh"

      # ── Summary ───────────────────────────────────────────────────────────
      cat <<SUMMARY

=== devtools setup complete ===
  GPG key ID  : $GPG_KEY_ID  (fingerprint: $GPG_FP)
  SSH key     : $SSH_KEY_PATH
  Git signing : commit.gpgsign=true, tag.gpgsign=true

  Verify a signed commit locally:
    git log --show-signature -1

SUMMARY
      ;;
  esac
done

echo "==> Done. Reboot to apply all changes."
