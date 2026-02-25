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

log() {
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

IFS=',' read -ra DIRS <<EOF
$WATCH_DIRS
EOF

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
        inotifywait -r -e create -e moved_to -e close_write "${DIRS[@]}" >/dev/null 2>&1

        log "Filesystem event detected. Waiting for quiet window ($DEBOUNCE_SECONDS seconds)..."

        # Reset timer if more events occur
        while inotifywait -r -e create -e moved_to -e close_write \
            --timeout "$DEBOUNCE_SECONDS" "${DIRS[@]}" >/dev/null 2>&1
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
