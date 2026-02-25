#!/bin/sh
set -eu

LOCK_FILE="/tmp/organize.lock"

log() {
    echo "[$(date)] $1" | tee -a "$LOG_FILE"
}

cleanup() {
    log "Shutting down..."
    exit 0
}

trap cleanup INT TERM

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

log "Starting organize service"
log "Watching: $DOWNLOADS"
log "Quiet window: $DEBOUNCE_SECONDS seconds"

run_organize() {
    log "Running organize..."
    flock "$LOCK_FILE" -c "
        organize run \"$ORGANIZE_CONFIG\" >> \"$LOG_FILE\" 2>&1
    "
    log "Organize run finished"
}

# Optional initial run
run_organize

while true
do
    inotifywait -r -e create -e moved_to -e close_write "$DOWNLOADS" >/dev/null 2>&1

    log "Event detected. Waiting for quiet period..."

    while inotifywait -r -e create -e moved_to -e close_write \
        --timeout "$DEBOUNCE_SECONDS" "$DOWNLOADS" >/dev/null 2>&1
    do
        log "New event detected. Resetting timer..."
    done

    log "Quiet period reached. Executing organize."
    run_organize
done
