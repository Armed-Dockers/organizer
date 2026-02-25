#!/bin/sh
set -eu

LOCK_FILE="/tmp/organize.lock"

# Only do permission fix if running as root
if [ "$(id -u)" = "0" ]; then
    echo "Fixing permissions..."

    mkdir -p /organize

    chown -R "$PUID:$PGID" /organize

    # Drop privileges and restart script as target user
    exec su-exec "$PUID:$PGID" "$0" "$@"
fi

rotate_logs() {
    MAX_MB=${LOG_MAX_SIZE_MB:-10}
    BACKUPS=${LOG_BACKUPS:-3}

    # File must exist
    [ -f "$LOG_FILE" ] || return 0

    # Get file size in MB (portable)
    FILESIZE=$(wc -c < "$LOG_FILE")
    MAX_BYTES=$((MAX_MB * 1024 * 1024))

    if [ "$FILESIZE" -lt "$MAX_BYTES" ]; then
        return 0
    fi

    echo "[$(date)] Rotating logs..." >> "$LOG_FILE"

    # Rotate old logs
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

    # Move current log to .1
    mv "$LOG_FILE" "$LOG_FILE.1"

    # Create fresh log
    touch "$LOG_FILE"
}

log() {
    rotate_logs
    echo "[$(date)] $1" | tee -a "$LOG_FILE"
}

cleanup() {
    log "Shutting down..."
    exit 0
}

trap cleanup INT TERM

# ---- Validate required env vars ----

if [ -z "${WATCH_DIRS:-}" ]; then
    echo "WATCH_DIRS is not set"
    exit 1
fi

if [ -z "${ORGANIZE_CONFIG:-}" ]; then
    echo "ORGANIZE_CONFIG is not set"
    exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")" || true
touch "$LOG_FILE" || true

# ---- Convert comma-separated dirs into array ----

DIRS=$(echo "$WATCH_DIRS" | tr ',' ' ')

# ---- Run organize safely ----

run_organize() {
    log "Running organize..."

    flock "$LOCK_FILE" -c "
        /usr/local/bin/organize run \"$ORGANIZE_CONFIG\" >> \"$LOG_FILE\" 2>&1
    "

    log "Organize run finished."
}

# ---- Watcher with smart debounce ----

watcher() {
    while true; do
        # Wait for first filesystem event in any watched dir
        inotifywait -r -e create -e moved_to -e close_write "$DIRS" >/dev/null 2>&1

        log "Filesystem event detected. Waiting for quiet window ($DEBOUNCE_SECONDS seconds)..."

        # Reset timer if more events occur
        while inotifywait -r -e create -e moved_to -e close_write \
            --timeout "$DEBOUNCE_SECONDS" "$DIRS" >/dev/null 2>&1
        do
            log "More filesystem events detected. Resetting quiet timer..."
        done

        log "Quiet period reached. Executing organize."
        run_organize
    done
}

# ---- Startup ----

log "Starting organize service"
log "Watching directories: $WATCH_DIRS"
log "Quiet window: $DEBOUNCE_SECONDS seconds"

# Optional: initial run on startup
run_organize

# Start watcher loop
watcher
