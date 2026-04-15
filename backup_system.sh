#!/bin/bash
 
# -e if any commands fails, the script terminate. 
# -u hard error when a variable is referenced to a wrong/typo variable. 
# -o pipefail if any of the pipe A or B the the script will fail. 
set -euo pipefail
 
base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
main_backup="$base_dir/backups"
watch_dir="$base_dir/monitored_files"
log_file="$main_backup/backuplog.txt"
zip_archive="$main_backup/.deleted_archive"
 
#init the PID of monitoring (inotify) when started.
monitoring_PID=""
backup_monitor_PID=""
 
#msmtp is the tool here
NOTIFY_EMAIL="qamrtadalan@tip.edu.ph"
 
#set the permission of any new files or directories. 
umask 077
 
format_report() {
    local function_name="$1"
    local error_detail="$2"
    local timestamp="$3"
    local extra_info="$4"
 
    echo "Backup System Report"
    echo "=============================="
    echo "Time     : $timestamp"
    echo "Function : $function_name"
    echo "Detail   : $error_detail"
    echo "Host     : $(hostname)"
 
    if [ -n "$extra_info" ]; then
        echo "------------------------------"
        echo "$extra_info"
    fi
 
    echo "=============================="
}
 
send_notification() {
    local function_name="$1"
    local error_detail="$2"
    local extra_info="${3:-}"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
 
    local body
    body=$(format_report "$function_name" "$error_detail" "$timestamp" "$extra_info")
 
    echo "$body" | msmtp -a gmail "$NOTIFY_EMAIL" 2>/dev/null
    echo "NOTIFICATION sent to $NOTIFY_EMAIL --- $function_name: $error_detail"
    echo "$timestamp, NOTIFICATION, EMAIL_SENT, $function_name --- $error_detail" >> "$log_file"
 
    echo "SYSTEM TERMINATED due to: $function_name"
    exit 1
}
 
backup_dirs() {
    mkdir -p "$main_backup" || send_notification "backup_dirs" "Failed to create main backup directory"
    mkdir -p "$zip_archive" || send_notification "backup_dirs" "Failed to create zip archive directory"
    mkdir -p "$watch_dir"
    chmod 700 "$main_backup" "$zip_archive"
 
    today=$(date +"%m-%d-%Y")
    today_folder="$main_backup/BackupFolder($today)"
    mkdir -p "$today_folder" || send_notification "backup_dirs" "Failed to create today's folder"
 
    echo "Backup environment initialized at: $base_dir"
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
  
backup_recovered() {
    local filename="$1"
    local recover_into="$2"
 
    local found
    found=$(find "$main_backup" -name "(DELETED)_$filename" | sort | tail -1)
 
    if [ -z "$found" ]; then
        send_notification "backup_recovered" "No deleted backup found for: $filename"
    fi
 
    local destination_folder
    destination_folder=$(get_today_folder)
    local recovered_copy="$destination_folder/(RECOVERED)_$filename"
 
    cp "$found" "$recover_into/$filename" || send_notification "backup_recovered" "Failed to restore $filename to $recover_into"
    cp "$found" "$recovered_copy" || send_notification "backup_recovered" "Failed to save recovered copy of $filename"
 
    if [ -f "$main_backup/.expiry_registry" ]; then
        sed -i "\|$found|d" "$main_backup/.expiry_registry"
    fi
 
    echo "BACKUP File recovered: $filename -> $recover_into"
    log_activity "BACKUP" "RECOVERED" "$filename recovered to $recover_into"
}
 
auto_cleanup() {
    echo "CLEANUP checking for expired deleted files..."
 
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
                rm -f "$filepath" || send_notification "auto_cleanup" "Failed to remove expired file: $fname"
                echo "CLEANUP Expired and removed: $fname"
                log_activity "CLEANUP" "EXPIRED_DELETED" "$fname removed after 30 days (kept in ZIP archive)"
                cleaned=$(( cleaned + 1 ))
            fi
        else
            echo "${filepath}|${delete_timestamp}" >> "$temp_registry"
        fi
    done < "$main_backup/.expiry_registry"
 
    mv "$temp_registry" "$main_backup/.expiry_registry" || send_notification "auto_cleanup" "Failed to update expiry registry"
    echo "CLEANUP Process finished. Removed $cleaned expired files."
}
 
daily_folder() {
    local today_folder
    today_folder=$(get_today_folder)
    if [ ! -d "$today_folder" ]; then
        mkdir -p "$today_folder" || send_notification "daily_folder" "Failed to create daily folder: $today_folder"
        chmod 700 "$today_folder"
        echo "New daily folder created: $(basename "$today_folder")"
        log_activity "SYSTEM" "DAILY_FOLDER_CREATED" "$(basename "$today_folder")"
    fi
}
 
check_inotify() {
    if ! command -v inotifywait &> /dev/null; then
        send_notification "check_inotify" "inotifywait is not installed --- run: sudo apt install inotify-tools"
    fi
    return 0
}
 
start_inotify() {
    check_inotify
    backup_dirs
    export main_backup log_file zip_archive watch_dir NOTIFY_EMAIL
 
    inotifywait -mr -e create -e delete --format "%e %w%f" "$watch_dir" 2>/dev/null | \
    while read -r event filepath; do
        if [[ "$filepath" == "$main_backup"* ]]; then continue; fi
 
        filename=$(basename "$filepath")
        if [[ "$filename" == .* ]]; then continue; fi
 
        timestamp=$(date "+%Y-%m-%d %H:%M:%S")
        today=$(date +"%m-%d-%Y")
        destination_folder="$main_backup/BackupFolder($today)"
        mkdir -p "$destination_folder"
 
        case "$event" in
            CREATE)
                sleep 0.5
                if [ -f "$filepath" ]; then
                    cp "$filepath" "$destination_folder/(CREATED)_$filename" 2>/dev/null || \
                        send_notification "start_inotify CREATE" "Failed to backup $filename"
                    echo "[$timestamp] AUTO-MONITORING CREATED $filename" >> "$log_file"
                    echo "MONITORING Auto-backed up new file: $filename"
                    check_duplicates "$watch_dir" "Watch Directory"
                fi
                ;;
 
            DELETE)
                found_copy=$(find "$main_backup" -name "(CREATED)_$filename" | sort | tail -1)
                if [ -n "$found_copy" ]; then
                    delete_date=$(date +%s)
                    destination_deleted="$destination_folder/(DELETED)_$filename"
                    zip_name="$zip_archive/DELETED_${filename}_deleted_${delete_date}.zip"
 
                    cp "$found_copy" "$destination_deleted" 2>/dev/null || \
                        send_notification "start_inotify DELETE" "Failed to copy deleted file $filename"
                    zip -j "$zip_name" "$found_copy" > /dev/null 2>&1 || \
                        send_notification "start_inotify ZIP" "Failed to ZIP $filename"
                    echo "${destination_deleted}|${delete_date}" >> "$main_backup/.expiry_registry"
                    echo "[$timestamp] AUTO-MONITORING DELETED $filename" >> "$log_file"
                    echo "MONITORING Auto-backed up deleted file: $filename"
                else
                    echo "[$timestamp] AUTO-MONITORING DELETED $filename (No backup found)" >> "$log_file"
                    echo "MONITORING Detected deletion: $filename (no prior backup found)"
                fi
                ;;
        esac
    done &
 
    monitoring_PID=$!
    echo "Auto-monitoring started (PID is $monitoring_PID)"
    log_activity "SYSTEM" "MONITORING_STARTED" "PID $monitoring_PID"
}
 
stop_monitoring() {
    pkill inotifywait 2>/dev/null || echo "No active monitor found."
    monitoring_PID=""
    log_activity "SYSTEM" "MONITORING_STOPPED" "inotifywait stopped"
}
 
check_duplicates() {
    local scan_dir="$1"
    local location_label="$2"
    local duplicates_found=0
 
    echo "DUPLICATE CHECK scanning: $location_label"
 
    declare -A checksum_map
 
    while IFS= read -r -d '' filepath; do
        local filename
        filename=$(basename "$filepath")
 
        if [[ "$filename" == .* ]]; then continue; fi
 
        local checksum
        checksum=$(md5sum "$filepath" 2>/dev/null | cut -d' ' -f1)
 
        if [ -z "$checksum" ]; then continue; fi
 
        if [ -n "${checksum_map[$checksum]:-}" ]; then
            local original="${checksum_map[$checksum]}"
            local timestamp
            timestamp=$(date "+%Y-%m-%d %H:%M:%S")
 
            echo "DUPLICATE FOUND in $location_label:"
            echo "  Original : $original"
            echo "  Duplicate: $filepath"
 
            log_activity "DUPLICATE" "DETECTED" "Duplicate of $(basename "$original") found at $filepath"
 
            duplicates_found=$(( duplicates_found + 1 ))
        else
            checksum_map[$checksum]="$filepath"
        fi
 
    done < <(find "$scan_dir" -type f -print0 2>/dev/null)
 
    unset checksum_map
 
    if [ "$duplicates_found" -eq 0 ]; then
        echo "DUPLICATE CHECK No duplicates found in $location_label. All good!"
    else
        echo "DUPLICATE CHECK Found $duplicates_found duplicate(s) in $location_label. Notification sent."
    fi
}
 
check_all_duplicates() {
    check_duplicates "$watch_dir" "Watch Directory"
    check_duplicates "$main_backup" "Backup Folder"
}
 
start_backup_monitor() {
    check_inotify
 
    export main_backup log_file NOTIFY_EMAIL
 
    inotifywait -mr -e modify -e delete -e move \
        --format "%e %w%f" "$main_backup" 2>/dev/null | \
    while read -r event filepath; do
 
        filename=$(basename "$filepath")
        timestamp=$(date "+%Y-%m-%d %H:%M:%S")
 
        if [[ "$filename" == .* ]]; then continue; fi
        if [[ "$filename" == "backuplog.txt" ]]; then continue; fi
        if [[ "$filename" == "alerts.log" ]]; then continue; fi
 
        extra_info="Event     : $event
File      : $filepath"
 
        case "$event" in
            DELETE|MOVED_FROM)
                echo "[$timestamp] TAMPER DETECTED: $event on $filepath" >> "$log_file"
                echo "BACKUP MONITOR: Deletion/move detected in backup folder: $filename"
                send_notification "backup_monitor" \
                    "Backup file was DELETED or MOVED: $filename" \
                    "$extra_info"
                ;;
            MODIFY)
                echo "[$timestamp] TAMPER DETECTED: $event on $filepath" >> "$log_file"
                echo "BACKUP MONITOR: Modification detected in backup folder: $filename"
                send_notification "backup_monitor" \
                    "Backup file was MODIFIED: $filename" \
                    "$extra_info"
                ;;
        esac
    done &
 
    backup_monitor_PID=$!
    echo "Backup folder monitor started (PID is $backup_monitor_PID)"
    echo "Monitoring recursively: $main_backup"
    log_activity "SYSTEM" "BACKUP_MONITOR_STARTED" "PID $backup_monitor_PID"
}
 
stop_backup_monitor() {
    if [ -n "${backup_monitor_PID:-}" ] && kill -0 "$backup_monitor_PID" 2>/dev/null; then
        kill "$backup_monitor_PID" 2>/dev/null
        echo "Backup folder monitor stopped (PID is $backup_monitor_PID)"
        log_activity "SYSTEM" "BACKUP_MONITOR_STOPPED" "PID $backup_monitor_PID stopped"
        backup_monitor_PID=""
    else
        echo "No active backup monitor found."
    fi
}
