#!/bin/sh
set -eu

LOCK_FILE="/tmp/organize.lock"

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
[ -z "${LOG_FILE:-}" ] && { echo "LOG_FILE not set"; exit 1; }

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

# -------------------------
# Convert comma-separated dirs
# -------------------------

DIRS=$(echo "$WATCH_DIRS" | tr ',' ' ')

# -------------------------
# Run organize safely
# -------------------------

run_organize() {
    log "Running organize..."
    flock "$LOCK_FILE" -c "organize run \"$ORGANIZE_CONFIG\" >> \"$LOG_FILE\" 2>&1"
    log "Organize run finished."
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
        run_organize
    done
}

log "Starting organize service"
log "Watching: $WATCH_DIRS"
log "Quiet window: ${DEBOUNCE_SECONDS:-15}s"

run_organize
watcher
