#!/bin/bash

set -o errexit -o nounset -o xtrace

apt-get update --yes
apt-get install cron logrotate --yes

CRON_FILE_PATH=/etc/cron.d/logs_rotation
LOGROTATE_CONFIG_FILE_PATH=/etc/logrotate.d/logs

cat <<EOF >> "$LOGROTATE_CONFIG_FILE_PATH"
/state/slogfile_$BOOT_TIME.json /state/app.log /state/server.log {
    create 644 root root
    compress
    copytruncate
    dateext
    dateformat _%Y%m%d%H%M%S
    extension .json
    hourly
    rotate 1
    size 1
    postrotate
        /bin/bash -c "ls -al /state >> /state/temp.log"
    endscript
}
EOF

touch "$CRON_FILE_PATH"
cat <<EOF >> "$CRON_FILE_PATH"
0 */1 * * * $(whoami) $(which logrotate) $LOGROTATE_CONFIG_FILE_PATH

EOF

cron -f -L 15
