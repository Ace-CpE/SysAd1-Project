#!/bin/bash
 
base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
main_backup="$base_dir/backups"
watch_dir="$base_dir/monitored_files"
log_file="$main_backup/backuplog.txt"
zip_archive="$main_backup/.deleted_archive"
 
monitoring_PID=""
BACKUP_SYSTEM_OK=true
 
umask 077
 
validate_backup_system() {
    local errors=()
 
    if ! bash -n "${BASH_SOURCE[0]}" 2>/dev/null; then
        errors+=("Syntax error detected in BackupSystem.sh")
    fi
 
    [[ -z "$base_dir" ]]     && errors+=("Critical variable 'base_dir' is unset or empty")
    [[ -z "$main_backup" ]]  && errors+=("Critical variable 'main_backup' is unset or empty")
    [[ -z "$watch_dir" ]]    && errors+=("Critical variable 'watch_dir' is unset or empty")
    [[ -z "$log_file" ]]     && errors+=("Critical variable 'log_file' is unset or empty")
    [[ -z "$zip_archive" ]]  && errors+=("Critical variable 'zip_archive' is unset or empty")
 
    for fn in backup_dirs backup_created backup_deleted backup_recovered auto_cleanup start_inotify stop_monitoring; do
        if ! declare -f "$fn" > /dev/null 2>&1; then
            errors+=("Critical function '$fn' is missing or failed to load")
        fi
    done
 
    if [ ${#errors[@]} -gt 0 ]; then
        echo "ERROR: BackupSystem validation failed:"
        for err in "${errors[@]}"; do
            echo "  - $err"
        done
        BACKUP_SYSTEM_OK=false
        return 1
    fi
 
    BACKUP_SYSTEM_OK=true
    return 0
}
 
# Guard: called at the top of each backup function before proceeding
_require_system_ok() {
    if [ "$BACKUP_SYSTEM_OK" != true ]; then
        echo "ERROR: BackupSystem is in a failed state. Operation aborted."
        return 1
    fi
    return 0
}
 
# ─────────────────────────────────────────────
# CORE FUNCTIONS
# ─────────────────────────────────────────────
 
backup_dirs() {
    _require_system_ok || return 1
 
    mkdir -p "$main_backup"
    mkdir -p "$zip_archive"
    mkdir -p "$watch_dir"
    chmod 700 "$main_backup" "$zip_archive"
    chmod 775 "$watch_dir"
 
    current_user=$(logname 2>/dev/null || echo $USER)
    chown "$current_user:$current_user" "$watch_dir"
 
    today=$(date +"%m-%d-%Y")
    today_folder="$main_backup/BackupFolder($today)"
    mkdir -p "$today_folder"
 
    echo "Today's backup folder ready: BackupFolder($today)"
}
 
get_today_folder() {
    today=$(date +"%m-%d-%Y")
    echo "$main_backup/BackupFolder($today)"
}
 
log_activity() {
    local category="$1"
    local action="$2"
    local detail="$3"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "$timestamp, $category, $action, $detail" >> "$log_file"
}
 
backup_created() {
    _require_system_ok || return 1
 
    local source="$1"
    local filename
    filename=$(basename "$source")
    local destination_folder
    destination_folder=$(get_today_folder)
    local destination="$destination_folder/(CREATED)_$filename"
 
    if [ ! -f "$source" ]; then
        echo "ERROR file not found: $source"
        log_activity "ERROR" "BACKUP_ABORTED" "File not found: $filename"
        return 1
    fi
 
    if ! cp "$source" "$destination"; then
        echo "ERROR: Failed to copy '$filename' to backup. Operation terminated."
        log_activity "ERROR" "BACKUP_ABORTED" "Copy failed for: $filename"
        return 1
    fi
 
    echo "BACKUP created: (CREATED)_$filename"
    log_activity "BACKUP" "CREATED" "$filename -> $(basename "$destination_folder")"
}
 
backup_deleted() {
    _require_system_ok || return 1
 
    local source="$1"
    local filename
    filename=$(basename "$source")
    local destination_folder
    destination_folder=$(get_today_folder)
    local destination="$destination_folder/(DELETED)_$filename"
    local delete_date
    delete_date=$(date +%s)
    local zip_name="$zip_archive/DELETED_${filename}_deleted_${delete_date}.zip"
 
    if [ ! -f "$source" ]; then
        echo "ERROR file not found: $source"
        log_activity "ERROR" "BACKUP_ABORTED" "File not found for deletion backup: $filename"
        return 1
    fi
 
    if ! cp "$source" "$destination"; then
        echo "ERROR: Failed to copy '$filename' for deletion backup. Operation terminated."
        log_activity "ERROR" "BACKUP_ABORTED" "Copy failed (delete) for: $filename"
        return 1
    fi
 
    if ! zip -j "$zip_name" "$source" > /dev/null 2>&1; then
        echo "ERROR: Failed to ZIP archive '$filename'. Operation terminated."
        log_activity "ERROR" "BACKUP_ABORTED" "ZIP failed for: $filename"
        return 1
    fi
 
    echo "BACKUP deleted file backed up: (DELETED)_$filename"
    echo "ZIP compressed archive saved for long term retention"
 
    echo "${destination}|${delete_date}" >> "$main_backup/.expiry_registry"
    log_activity "BACKUP" "DELETED" "$filename -> $(basename "$destination_folder") + ZIP archive saved"
}
 
backup_recovered() {
    _require_system_ok || return 1
 
    local filename="$1"
    local recover_into="$2"
 
    local found
    found=$(find "$main_backup" -name "(DELETED)_$filename" | sort | tail -1)
 
    if [ -z "$found" ]; then
        echo "ERROR No deleted backup found for: $filename"
        echo "Check the ZIP archive at: $zip_archive"
        log_activity "ERROR" "BACKUP_ABORTED" "No backup found for recovery: $filename"
        return 1
    fi
 
    local destination_folder
    destination_folder=$(get_today_folder)
    local recovered_copy="$destination_folder/(RECOVERED)_$filename"
 
    if ! cp "$found" "$recover_into/$filename" || ! cp "$found" "$recovered_copy"; then
        echo "ERROR: Recovery copy failed for '$filename'. Operation terminated."
        log_activity "ERROR" "BACKUP_ABORTED" "Recovery copy failed: $filename"
        return 1
    fi
 
    if [ -f "$main_backup/.expiry_registry" ]; then
        sed -i "\|$found|d" "$main_backup/.expiry_registry"
    fi
 
    echo "BACKUP File recovered: $filename -> $recover_into"
    log_activity "BACKUP" "RECOVERED" "$filename recovered to $recover_into"
}
 
auto_cleanup() {
    _require_system_ok || return 1
 
    echo "CLEANUP checking for expired deleted files."
 
    if [ ! -f "$main_backup/.expiry_registry" ]; then
        echo "CLEANUP No expiry registry found."
        return 0
    fi
 
    local now
    now=$(date +%s)
    local thirty_days=$(( 30 * 86400 ))
    local cleaned=0
    local temp_registry
    temp_registry=$(mktemp)
 
    while IFS='|' read -r filepath delete_timestamp; do
        [ -z "$filepath" ] && continue
        local age=$(( now - delete_timestamp ))
 
        if [ "$age" -ge "$thirty_days" ]; then
            if [ -f "$filepath" ]; then
                local fname
                fname=$(basename "$filepath")
                rm -f "$filepath"
                echo "CLEANUP Expired and removed: $fname"
                log_activity "CLEANUP" "EXPIRED_DELETED" "$fname removed after 30 days"
                cleaned=$(( cleaned + 1 ))
            fi
        else
            echo "${filepath}|${delete_timestamp}" >> "$temp_registry"
        fi
    done < "$main_backup/.expiry_registry"
 
    mv "$temp_registry" "$main_backup/.expiry_registry"
    echo "CLEANUP Process finished. Removed $cleaned expired files."
}
 
daily_folder() {
    _require_system_ok || return 1
 
    local today_folder
    today_folder=$(get_today_folder)
    if [ ! -d "$today_folder" ]; then
        mkdir -p "$today_folder"
        chmod 700 "$today_folder"
        echo "New daily folder created: $(basename "$today_folder")"
        log_activity "SYSTEM" "DAILY_FOLDER_CREATED" "$(basename "$today_folder")"
    fi
}
 
check_inotify() {
    if ! command -v inotifywait &> /dev/null; then
        echo "WARNING inotify is not yet installed."
        echo "Run: sudo apt install inotify-tools"
        return 1
    fi
    return 0
}
 
start_inotify() {
    _require_system_ok || return 1
    if ! check_inotify; then return 1; fi
    backup_dirs
    export main_backup log_file zip_archive watch_dir
 
    inotifywait -mr -e create -e delete --format "%e %w%f" "$watch_dir" 2>/dev/null | \
    while read -r event filepath; do
        if [[ "$filepath" == "$main_backup"* ]]; then continue; fi
        filename=$(basename "$filepath")
        if [[ "$filename" == .* ]]; then continue; fi
 
        timestamp=$(date "+%Y-%m-%d %H:%M:%S")
        destination_folder=$(get_today_folder)
        mkdir -p "$destination_folder"
 
        case "$event" in
            CREATE)
                sleep 0.5
                if [ -f "$filepath" ]; then
                    if ! cp "$filepath" "$destination_folder/(CREATED)_$filename" 2>/dev/null; then
                        echo "[$timestamp] ERROR AUTO-MONITORING FAILED (CREATE) $filename" >> "$log_file"
                    else
                        echo "[$timestamp] AUTO-MONITORING CREATED $filename" >> "$log_file"
                        echo "MONITORING Auto-backed up new file: $filename"
                    fi
                fi
                ;;
 
            DELETE)
                found_copy=$(find "$main_backup" -name "(CREATED)_$filename" | sort | tail -1)
                if [ -n "$found_copy" ]; then
                    delete_date=$(date +%s)
                    destination_deleted="$destination_folder/(DELETED)_$filename"
                    zip_name="$zip_archive/DELETED_${filename}_deleted_${delete_date}.zip"
                    if ! cp "$found_copy" "$destination_deleted" 2>/dev/null || \
                       ! zip -j "$zip_name" "$found_copy" > /dev/null 2>&1; then
                        echo "[$timestamp] ERROR AUTO-MONITORING FAILED (DELETE) $filename" >> "$log_file"
                    else
                        echo "${destination_deleted}|${delete_date}" >> "$main_backup/.expiry_registry"
                        echo "[$timestamp] AUTO-MONITORING DELETED $filename" >> "$log_file"
                        echo "MONITORING Auto-backed up deleted file: $filename"
                    fi
                else
                    echo "[$timestamp] AUTO-MONITORING DELETED $filename (No backup found)" >> "$log_file"
                fi
                ;;
        esac
    done &
 
    monitoring_PID=$!
    echo "Auto-monitoring started (PID is $monitoring_PID)"
    log_activity "SYSTEM" "MONITORING_STARTED" "PID $monitoring_PID"
}
 
stop_monitoring() {
    pkill inotifywait || echo "No active monitor found."
}
 
validate_backup_system
