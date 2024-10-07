#!/bin/bash

set -eux

DIRECTORY_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

CRON_FILE_PATH=/etc/cron.d/restart-pods
CRON_LOGS_FILE_PATH=/state/cron.logs

apt-get update --yes > /dev/null
apt-get install cron --yes > /dev/null

touch "$CRON_FILE_PATH" "$CRON_LOGS_FILE_PATH"

cat <<EOF >> "$CRON_FILE_PATH"
0 */6 * * * $(whoami) export ROLE="$ROLE" && $(which bash) $DIRECTORY_PATH/restart-pods.sh > "$CRON_LOGS_FILE_PATH" 2>&1

EOF

cron -L 15
