#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"

IPU6_REPO="https://github.com/korciuch/al10-intel-ipu6.git"
IPU6_DIR="/opt/al10-intel-ipu6"

clone_ipu6() {
  [[ -d "$IPU6_DIR" ]] && return
  git clone --recurse-submodules "$IPU6_REPO" "$IPU6_DIR"
}

CHOICES=$(whiptail --title "al10-daily-driver Setup" \
  --checklist "Select modules to install (SPACE to toggle, ENTER to confirm):" 20 60 3 \
  "camera" "Intel IPU6 camera (Meteor Lake / XPS 16)"  OFF \
  "audio"  "Intel SOF audio  (Meteor Lake / XPS 16)"  OFF \
  "codecs" "Multimedia codecs (RPM Fusion)"            OFF \
  3>&1 1>&2 2>&3) || exit 0

for choice in $CHOICES; do
  choice="${choice//\"/}"
  case "$choice" in
    camera) clone_ipu6; bash "$IPU6_DIR/setup.sh" ;;
    audio)  clone_ipu6; bash "$IPU6_DIR/audio/setup.sh" ;;
    codecs) dnf install -y ffmpeg gstreamer1-plugins-bad-free \
              gstreamer1-plugins-ugly-free gstreamer1-plugin-libav ;;
  esac
done

echo "==> Done. Reboot to apply all changes."
