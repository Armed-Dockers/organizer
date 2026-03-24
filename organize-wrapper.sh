#!/bin/sh
set -eu

LOCK_FILE="${LOCK_FILE:-/tmp/organize.lock}"

# -------------------------
# Log Rotation
# -------------------------

rotate_logs() {
    MAX_MB=${LOG_MAX_SIZE_MB:-10}
    BACKUPS=${LOG_BACKUPS:-3}

    [ -f "$LOG_FILE" ] || return 0

    FILESIZE=$(wc -c < "$LOG_FILE")
    MAX_BYTES=$((MAX_MB * 1024 * 1024))

    [ "$FILESIZE" -lt "$MAX_BYTES" ] && return 0

    echo "[$(date)] Rotating logs..." >> "$LOG_FILE"

    i=$BACKUPS
    while [ $i -gt 0 ]; do
        if [ -f "$LOG_FILE.$i" ]; then
            if [ $i -eq $BACKUPS ]; then
                rm -f "$LOG_FILE.$i"
            else
                mv "$LOG_FILE.$i" "$LOG_FILE.$((i+1))"
            fi
        fi
        i=$((i-1))
    done

    mv "$LOG_FILE" "$LOG_FILE.1"
    touch "$LOG_FILE"
}

log() {
    rotate_logs
    echo "[$(date)] $1" | tee -a "$LOG_FILE"
}

# -------------------------
# Validate Environment
# -------------------------

[ -z "${WATCH_DIRS:-}" ] && { echo "WATCH_DIRS not set"; exit 1; }
[ -z "${ORGANIZE_CONFIG:-}" ] && { echo "ORGANIZE_CONFIG not set"; exit 1; }
[ -z "${SCHEDULED_ORGANIZE_CONFIG:-}" ] && { echo "SCHEDULED_ORGANIZE_CONFIG not set"; exit 1; }
[ -z "${LOG_FILE:-}" ] && { echo "LOG_FILE not set"; exit 1; }
[ -z "${CRON_SCHEDULE:-}" ] && { echo "CRON_SCHEDULE not set"; exit 1; }

CRON_DIR=${CRON_DIR:-/tmp/crontabs}
CRON_FILE=${CRON_FILE:-$CRON_DIR/appuser}
CRON_LOG_FILE=${CRON_LOG_FILE:-/tmp/cron.log}

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

# -------------------------
# Convert comma-separated dirs
# -------------------------

DIRS=$(echo "$WATCH_DIRS" | tr ',' ' ')

# -------------------------
# Run organize safely
# -------------------------

run_organize_inotify() {
    log "Running organize (inotify config)..."
    flock "$LOCK_FILE" -c "organize run \"$ORGANIZE_CONFIG\" >> \"$LOG_FILE\" 2>&1"
    log "Organize run finished (inotify config)."
}

run_organize_scheduled() {
    log "Running organize (scheduled config)..."
    flock "$LOCK_FILE" -c "organize run \"$SCHEDULED_ORGANIZE_CONFIG\" >> \"$LOG_FILE\" 2>&1"
    log "Organize run finished (scheduled config)."
}

# -------------------------
# Cron setup for scheduled runs
# -------------------------

setup_cron() {
    mkdir -p "$CRON_DIR"

    cat > "$CRON_FILE" <<CRON
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$CRON_SCHEDULE flock "$LOCK_FILE" -c 'organize run "$SCHEDULED_ORGANIZE_CONFIG" >> "$LOG_FILE" 2>&1'
CRON

    chmod 600 "$CRON_FILE"

    : > "$CRON_LOG_FILE"

    log "Cron configured: $CRON_SCHEDULE"
    log "Cron config path: $CRON_FILE"
    log "Cron log file: $CRON_LOG_FILE"

    crond -c "$CRON_DIR" -f -l 8 -L "$CRON_LOG_FILE" &
    CRON_PID=$!
    log "Cron daemon started (PID $CRON_PID)."
}

# -------------------------
# Smart Debounce Watcher
# -------------------------

watcher() {
    while true; do
        inotifywait -r -e create -e moved_to -e close_write $DIRS >/dev/null 2>&1

        log "Filesystem event detected. Waiting for quiet window (${DEBOUNCE_SECONDS:-15}s)..."

        while inotifywait -r -e create -e moved_to -e close_write \
            --timeout "${DEBOUNCE_SECONDS:-15}" $DIRS >/dev/null 2>&1
        do
            log "More events detected. Resetting timer..."
        done

        log "Quiet period reached."
        run_organize_inotify
    done
}

log "Starting organize service"
log "Watching: $WATCH_DIRS"
log "Inotify config: $ORGANIZE_CONFIG"
log "Scheduled config: $SCHEDULED_ORGANIZE_CONFIG"
log "Quiet window: ${DEBOUNCE_SECONDS:-15}s"

setup_cron
run_organize_inotify
watcher
