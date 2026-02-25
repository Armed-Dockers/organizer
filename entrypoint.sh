#!/bin/sh
set -eu

# -------------------------
# Validate PUID / PGID
# -------------------------

[ -z "${PUID:-}" ] && { echo "PUID not set"; exit 1; }
[ -z "${PGID:-}" ] && { echo "PGID not set"; exit 1; }

# -------------------------
# Create group
# -------------------------

if ! getent group appgroup >/dev/null 2>&1; then
    addgroup -g "$PGID" appgroup
fi

# -------------------------
# Create user
# -------------------------

if ! id appuser >/dev/null 2>&1; then
    adduser -D -u "$PUID" -G appgroup -h /home/appuser appuser
fi

mkdir -p /home/appuser
chown -R "$PUID:$PGID" /home/appuser

export HOME=/home/appuser

# -------------------------
# Fix volume permissions
# -------------------------

mkdir -p /organize
chown -R "$PUID:$PGID" /organize

# -------------------------
# Drop privileges
# -------------------------

exec su-exec "$PUID:$PGID" /usr/local/bin/organize-wrapper.sh
