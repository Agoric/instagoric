#!/bin/bash

apt-get install logrotate --yes

cat <<'EOF' >> /etc/logrotate.d/slogs
    /state/slogfile_$BOOT_TIME.json {
        create 644 root root
        compress
        copytruncate
        dateext
        dateformat slogfile_$BOOT_TIME_%Y%m%d%H%M%S
        hourly
        rotate 0
        size 1
        postrotate
            ls -al /state
        endscript
    }
EOF

cat /etc/logrotate.d/slogs
which logrotate

(crontab -l | grep --quiet "/state/slogfile_$BOOT_TIME.json") || \
 (crontab -l 2>/dev/null; echo "0 */6 * * * $(which logrotate) /etc/logrotate.d/slogs") | crontab -
