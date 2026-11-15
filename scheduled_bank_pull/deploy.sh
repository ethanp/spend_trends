#!/bin/bash
# Ship the scheduled bank pull to the home server: spend_trends and its path
# packages into ~/Flutter (the compose build context), the two env files the
# run mounts, and the daily timer. Run infra/deploy.sh first so compose has the
# spend-trends-bank-pull service.
#
# Usage (from anywhere): Flutter/spend_trends/scheduled_bank_pull/deploy.sh [--run]
#   --run  also pull now and follow the log

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLUTTER_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INFRA_ROOT="$(cd "$FLUTTER_ROOT/../infra" && pwd)"
# shellcheck source=../../../infra/lib/remote-host.sh
source "$INFRA_ROOT/lib/remote-host.sh"

REMOTE_FLUTTER_ROOT="/home/ethan/Flutter"
UNIT_NAME="spend-trends-bank-pull"

for package_name in ethan_utils ethan_ui ethan_sync spend_trends; do
  echo "Syncing $package_name"
  rsync -az --delete --mkpath \
    --exclude='.git' \
    --exclude='build' \
    --exclude='.dart_tool' \
    --exclude='.real_data' \
    --exclude='ios' \
    --exclude='macos' \
    --exclude='screenshots' \
    "$FLUTTER_ROOT/$package_name/" \
    "$REMOTE_HOST:$REMOTE_FLUTTER_ROOT/$package_name/"
done
ssh "$REMOTE_HOST" "chmod 600 $REMOTE_FLUTTER_ROOT/spend_trends/.env $REMOTE_FLUTTER_ROOT/ethan_sync/home_server.env"

echo "Installing $UNIT_NAME.timer"
ssh "$REMOTE_HOST" "mkdir -p ~/.config/systemd/user"
rsync -az "$SCRIPT_DIR/systemd/" "$REMOTE_HOST:.config/systemd/user/"
ssh "$REMOTE_HOST" "systemctl --user daemon-reload \
  && systemctl --user enable --now $UNIT_NAME.timer > /dev/null \
  && systemctl --user list-timers $UNIT_NAME.timer --no-legend"

if [ "${1:-}" = "--run" ]; then
  ssh "$REMOTE_HOST" "cd ~/infra && docker compose --profile jobs run --rm --build $UNIT_NAME"
fi
