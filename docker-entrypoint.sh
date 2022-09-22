#!/bin/bash
CRON_SCHEDULE=${CRON_SCHEDULE:-"18 1 * * *"}
log info "Initialising with schedule: $CRON_SCHEDULE"
echo "$CRON_SCHEDULE cd /backup && ./backup.sh" | crontab -
crond -f