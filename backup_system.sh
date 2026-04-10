#!/bin/bash
# Auto Backup System
# Monitors the entire filesystem (excluding the backup folder itself)
# Logs created, deleted, and recovered files into organized daily folders

set -euo pipefail

# ─────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────
MAIN_BACKUP="/root/MainBackupFolder"
MONITOR_ROOT="/"
EXCLUDE_PATH="$MAIN_BACKUP"
EXPIRY_DAYS=30
LOG_FILE="$MAIN_BACKUP/backup_system.log"

# ─────────────────────────────────────────────
# INIT: Create Main Backup Folder if not exists
# ─────────────────────────────────────────────
init_backup() {
    if [ ! -d "$MAIN_BACKUP" ]; then
        mkdir -p "$MAIN_BACKUP"
        chmod 700 "$MAIN_BACKUP"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Main Backup Folder created at $MAIN_BACKUP." >> "$LOG_FILE"
    fi
}

# ─────────────────────────────────────────────
# Get today's daily backup folder
# Format: BackupFolder(M/D/YYYY)
# ─────────────────────────────────────────────
get_daily_folder() {
    local today
    today=$(date '+%-m/%-d/%Y')
    local daily_dir="$MAIN_BACKUP/BackupFolder($today)"
    if [ ! -d "$daily_dir" ]; then
        mkdir -p "$daily_dir"
        chmod 700 "$daily_dir"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Daily folder created: BackupFolder($today)" >> "$LOG_FILE"
    fi
    echo "$daily_dir"
}

# ─────────────────────────────────────────────
# Handle CREATED files
# ─────────────────────────────────────────────
handle_create() {
    local filepath="$1"
    local filename
    filename=$(basename "$filepath")
    local daily_dir
    daily_dir=$(get_daily_folder)

    local dest="$daily_dir/(CREATED)_${filename}"

    # Avoid overwriting — append timestamp if duplicate
    if [ -e "$dest" ]; then
        local ts
        ts=$(date '+%H%M%S')
        dest="$daily_dir/(CREATED)_${filename}_${ts}"
    fi

    if [ -f "$filepath" ]; then
        cp --preserve=all "$filepath" "$dest" 2>/dev/null || true
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] CREATED: $filepath → $dest" >> "$LOG_FILE"
    fi
}

# ─────────────────────────────────────────────
# Handle DELETED files
# ─────────────────────────────────────────────
handle_delete() {
    local filepath="$1"
    local filename
    filename=$(basename "$filepath")
    local daily_dir
    daily_dir=$(get_daily_folder)

    local dest="$daily_dir/(DELETED)_${filename}"
    local meta_dest="${dest}.meta"

    # Avoid overwriting — append timestamp if duplicate
    if [ -e "$dest" ]; then
        local ts
        ts=$(date '+%H%M%S')
        dest="$daily_dir/(DELETED)_${filename}_${ts}"
        meta_dest="${dest}.meta"
    fi

    # Search for the last CREATED backup of this file to copy as DELETED record
    local last_created
    last_created=$(find "$MAIN_BACKUP" -name "(CREATED)_${filename}*" -type f 2>/dev/null | sort | tail -n 1)

    if [ -n "$last_created" ]; then
        cp --preserve=all "$last_created" "$dest" 2>/dev/null || true
    else
        # Create a placeholder if no prior backup was found
        echo "File was deleted but no prior backup found." > "$dest"
    fi

    # Save deletion metadata (timestamp) for expiry tracking
    echo "deleted_at=$(date +%s)" > "$meta_dest"
    echo "original_path=$filepath" >> "$meta_dest"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DELETED: $filepath → $dest" >> "$LOG_FILE"
}

# ─────────────────────────────────────────────
# Handle RECOVERED files (re-created after deletion)
# ─────────────────────────────────────────────
handle_recover() {
    local filepath="$1"
    local filename
    filename=$(basename "$filepath")
    local daily_dir
    daily_dir=$(get_daily_folder)

    # Check if there is a DELETED record for this file
    local deleted_record
    deleted_record=$(find "$MAIN_BACKUP" -name "(DELETED)_${filename}*" -not -name "*.meta" -type f 2>/dev/null | sort | tail -n 1)

    if [ -n "$deleted_record" ]; then
        local dest="$daily_dir/(RECOVERED)_${filename}"

        if [ -e "$dest" ]; then
            local ts
            ts=$(date '+%H%M%S')
            dest="$daily_dir/(RECOVERED)_${filename}_${ts}"
        fi

        cp --preserve=all "$filepath" "$dest" 2>/dev/null || true
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] RECOVERED: $filepath → $dest" >> "$LOG_FILE"
    else
        # No prior deletion record — treat as a regular create
        handle_create "$filepath"
    fi
}

# ─────────────────────────────────────────────
# Expire DELETED files older than 30 days
# Only removes files labeled DELETED with no RECOVERED counterpart
# ─────────────────────────────────────────────
expire_deleted_files() {
    local now
    now=$(date +%s)
    local expiry_seconds=$(( EXPIRY_DAYS * 86400 ))

    find "$MAIN_BACKUP" -name "*.meta" -type f | while read -r meta_file; do
        local deleted_at
        deleted_at=$(grep '^deleted_at=' "$meta_file" | cut -d'=' -f2)

        if [ -z "$deleted_at" ]; then
            continue
        fi

        local age=$(( now - deleted_at ))

        if [ "$age" -ge "$expiry_seconds" ]; then
            local deleted_file="${meta_file%.meta}"
            local filename
            filename=$(basename "$deleted_file")

            # Strip the (DELETED)_ prefix to get the base filename
            local base_name="${filename#(DELETED)_}"
            # Also strip any trailing _HHMMSS timestamp if present
            base_name=$(echo "$base_name" | sed 's/_[0-9]\{6\}$//')

            # Check if a RECOVERED version exists
            local recovered
            recovered=$(find "$MAIN_BACKUP" -name "(RECOVERED)_${base_name}*" -type f 2>/dev/null | head -n 1)

            if [ -z "$recovered" ]; then
                # Safe to expire — no recovered version found
                rm -f "$deleted_file" "$meta_file"
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] EXPIRED (30 days): $deleted_file" >> "$LOG_FILE"
            fi
        fi
    done
}

# ─────────────────────────────────────────────
# Monitor filesystem using inotifywait
# Excludes the Main Backup Folder to avoid loops
# ─────────────────────────────────────────────
start_monitor() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup monitor started. Watching: $MONITOR_ROOT (excluding $EXCLUDE_PATH)" >> "$LOG_FILE"
    echo "Backup system is now running. Monitoring filesystem..."

    # Associative array to track recently deleted files (for recovery detection)
    declare -A recently_deleted

    inotifywait -m -r \
        --exclude "^${EXCLUDE_PATH}" \
        -e create -e delete -e moved_from -e moved_to \
        --format '%e %w%f' \
        "$MONITOR_ROOT" 2>/dev/null | while IFS=' ' read -r event filepath; do

        # Safety net: skip anything inside the backup folder
        if [[ "$filepath" == "${EXCLUDE_PATH}"* ]]; then
            continue
        fi

        # Skip directories — only track files
        if [ -d "$filepath" ]; then
            continue
        fi

        local filename
        filename=$(basename "$filepath")

        case "$event" in
            CREATE|MOVED_TO)
                if [[ -v recently_deleted["$filename"] ]]; then
                    # Was recently deleted → treat as recovery
                    handle_recover "$filepath"
                    unset recently_deleted["$filename"]
                else
                    handle_create "$filepath"
                fi
                ;;
            DELETE|MOVED_FROM)
                recently_deleted["$filename"]=1
                handle_delete "$filepath"
                ;;
        esac

        # Run expiry check on every event (lightweight scan)
        expire_deleted_files

    done
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────

# Must run as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
fi

# Check for inotifywait dependency
if ! command -v inotifywait &>/dev/null; then
    echo "Error: inotifywait is not installed."
    echo "Install it with: apt install inotify-tools"
    exit 1
fi

init_backup
start_monitor
