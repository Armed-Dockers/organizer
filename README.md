# organizer

Organize files automatically using both:

- inotify-triggered runs (live filesystem events)
- cron-scheduled runs (fixed schedule)

## Environment variables

### Required

- `PUID`: user id used inside container
- `PGID`: group id used inside container
- `WATCH_DIRS`: comma-separated directories to watch with inotify
- `ORGANIZE_CONFIG`: config file used for inotify-triggered runs
- `SCHEDULED_ORGANIZE_CONFIG`: config file used for cron-triggered runs
- `CRON_SCHEDULE`: cron expression for scheduled runs (example: `0 * * * *`)
- `LOG_FILE`: common log file for organize runs

### Optional

- `DEBOUNCE_SECONDS` (default: `15`): quiet window before inotify run starts
- `LOCK_FILE` (default: `/tmp/organize.lock`): lock file preventing concurrent runs
- `LOG_MAX_SIZE_MB` (default: `10`): log rotation size threshold
- `LOG_BACKUPS` (default: `3`): number of rotated log backups
- `CRON_DIR` (default: `/tmp/crontabs`): directory used by `crond` for schedule files
- `CRON_FILE` (default: `$CRON_DIR/appuser`): cron schedule file path
- `CRON_LOG_FILE` (default: `/tmp/cron.log`): cron daemon log path
