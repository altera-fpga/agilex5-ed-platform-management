#!/bin/sh
# deploy-dashboard - install updated dashboard files onto a running BMC.
#
# Copies the static dashboard assets from a source directory into the bmcweb
# web root, backing up the current version first, then restarts bmcweb so any
# newly added files get routes. Intended for on-board use during development.
set -eu

WEBROOT="/usr/share/www/dashboard"
BACKUP_ROOT="/var/lib/dashboard-backups"
ASSETS="index.html dashboard.css dashboard.js chart.umd.min.js"
SRC="."

usage() {
    cat <<EOF
Usage: deploy-dashboard [SRC_DIR]

Install dashboard files from SRC_DIR (default: current directory) into
${WEBROOT} and restart bmcweb.

Files handled: ${ASSETS}
Only files present in SRC_DIR are copied; missing ones are left untouched.

The current web root is backed up to ${BACKUP_ROOT}/<timestamp>/ first.

Options:
  -h, --help   Show this help and exit
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    -*) echo "deploy-dashboard: unknown option '$1'" >&2; usage >&2; exit 2 ;;
    "") : ;;
    *) SRC="$1" ;;
esac

if [ ! -d "$SRC" ]; then
    echo "deploy-dashboard: source directory not found: $SRC" >&2
    exit 1
fi

# Make sure we actually have something to deploy.
found=""
for f in $ASSETS; do
    [ -f "$SRC/$f" ] && found="yes"
done
if [ -z "$found" ]; then
    echo "deploy-dashboard: none of ($ASSETS) found in $SRC" >&2
    exit 1
fi

# The rootfs is normally read-only; remount read-write for the update.
if ! mount -o remount,rw / 2>/dev/null; then
    echo "deploy-dashboard: warning: could not remount / read-write" >&2
fi

mkdir -p "$WEBROOT"

# Back up the current web root.
stamp="$(date +%Y%m%d-%H%M%S)"
backup="$BACKUP_ROOT/$stamp"
mkdir -p "$backup"
for f in $ASSETS; do
    [ -f "$WEBROOT/$f" ] && cp -p "$WEBROOT/$f" "$backup/" || true
done
echo "deploy-dashboard: backed up current dashboard to $backup"

# Install the new files (cp + chmod; BusyBox may lack `install`).
for f in $ASSETS; do
    if [ -f "$SRC/$f" ]; then
        cp "$SRC/$f" "$WEBROOT/$f"
        chmod 0644 "$WEBROOT/$f"
        echo "deploy-dashboard: installed $f"
    fi
done

sync

# Restart bmcweb so any newly added files are registered as routes.
if command -v systemctl >/dev/null 2>&1; then
    systemctl restart bmcweb || \
        echo "deploy-dashboard: warning: failed to restart bmcweb" >&2
fi

echo "deploy-dashboard: done. Browse https://<bmc>/dashboard"
