#!/bin/sh
# Build the pinned shurectl fork (the `shurectl` submodule) and install it to
# ~/.local/bin/shurectl, where Mv7.qml looks first. Run again after pulling a
# new pin. Builds outside the plugin directory so ~/.config/omarchy/plugins
# doesn't carry cargo's target/.
#
# Usage: ./install.sh
set -eu

cd "$(dirname "$0")"

git submodule update --init shurectl

target="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-shurectl/target"
CARGO_TARGET_DIR="$target" cargo build --release --locked --manifest-path shurectl/Cargo.toml
install -Dm755 "$target/release/shurectl" "$HOME/.local/bin/shurectl"
echo "Installed $("$HOME/.local/bin/shurectl" --version) to ~/.local/bin/shurectl"

# Without the udev rule only root can open the mic's HID device.
if [ ! -e /etc/udev/rules.d/62-shure.rules ]; then
  echo "Installing the udev rule (needs sudo)"
  sudo install -m644 shurectl/62-shure.rules /etc/udev/rules.d/62-shure.rules
  sudo udevadm control --reload-rules
  sudo udevadm trigger
  echo "Replug the mic if it's connected"
fi
