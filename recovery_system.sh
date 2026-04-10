#!/bin/bash
# Recovery System
# Allows authorized users to browse and recover deleted files from the backup
# Integrates with the Auto Backup System (backup_system.sh)

set -euo pipefail

# ─────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────
MAIN_BACKUP="/root/MainBackupFolder"
LOG_FILE="$MAIN_BACKUP/backup_system.log"

# ─────────────────────────────────────────────
# UTILITIES
# ─────────────────────────────────────────────
print_header() {
    clear
    echo "============================================"
    echo "         BACKUP RECOVERY SYSTEM             "
    echo "============================================"
    echo
}

pause() {
    echo
    read -rp "Press Enter to continue..."
}

# ─────────────────────────────────────────────
# STEP 1: Browse Daily Folders by Date
# ─────────────────────────────────────────────
pick_daily_folder() {
    print_header
    echo "Available Backup Dates:"
    echo "--------------------------------------------"

    # Collect all daily folders
    mapfile -t folders < <(find "$MAIN_BACKUP" -maxdepth 1 -type d -name "BackupFolder(*)" | sort)

    if [ ${#folders[@]} -eq 0 ]; then
        echo "No backup folders found."
        exit 0
    fi

    local i=1
    for folder in "${folders[@]}"; do
        local label
        label=$(basename "$folder")
        echo "  [$i] $label"
        (( i++ ))
    done

    echo
    echo "  [0] Exit"
    echo
    read -rp "Select a date [0-$((i-1))]: " choice

    if [[ "$choice" == "0" ]]; then
        echo "Exiting recovery system."
        exit 0
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#folders[@]} ]; then
        echo "Invalid selection."
        pause
        pick_daily_folder
        return
    fi

    SELECTED_FOLDER="${folders[$((choice-1))]}"
}

# ─────────────────────────────────────────────
# STEP 2: Browse Deleted Files in Selected Folder
# ─────────────────────────────────────────────
pick_deleted_file() {
    print_header
    local folder_label
    folder_label=$(basename "$SELECTED_FOLDER")
    echo "Deleted Files in: $folder_label"
    echo "--------------------------------------------"

    # Collect only DELETED files (exclude .meta files)
    mapfile -t deleted_files < <(find "$SELECTED_FOLDER" -maxdepth 1 -type f -name "(DELETED)_*" ! -name "*.meta" | sort)

    if [ ${#deleted_files[@]} -eq 0 ]; then
        echo "No deleted files found in this backup date."
        pause
        pick_daily_folder
        return
    fi

    local i=1
    for file in "${deleted_files[@]}"; do
        local label
        label=$(basename "$file")

        # Try to get original path from .meta file
        local meta="${file}.meta"
        local original_path="(original path unknown)"
        if [ -f "$meta" ]; then
            original_path=$(grep '^original_path=' "$meta" | cut -d'=' -f2-)
        fi

        echo "  [$i] $label"
        echo "       Original: $original_path"
        echo
        (( i++ ))
    done

    echo "  [b] Go back to date selection"
    echo "  [0] Exit"
    echo
    read -rp "Select a file to recover [0-$((i-1))]: " choice

    if [[ "$choice" == "0" ]]; then
        echo "Exiting recovery system."
        exit 0
    fi

    if [[ "$choice" == "b" || "$choice" == "B" ]]; then
        pick_daily_folder
        pick_deleted_file
        return
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#deleted_files[@]} ]; then
        echo "Invalid selection."
        pause
        pick_deleted_file
        return
    fi

    SELECTED_FILE="${deleted_files[$((choice-1))]}"
}

# ─────────────────────────────────────────────
# STEP 3: Recover the Selected File
# ─────────────────────────────────────────────
recover_file() {
    print_header
    local filename
    filename=$(basename "$SELECTED_FILE")
    local meta="${SELECTED_FILE}.meta"

    echo "File to Recover: $filename"
    echo "--------------------------------------------"

    # Read original path from .meta
    if [ ! -f "$meta" ]; then
        echo "Error: No metadata found for this file. Cannot determine original path."
        pause
        return
    fi

    local original_path
    original_path=$(grep '^original_path=' "$meta" | cut -d'=' -f2-)

    if [ -z "$original_path" ]; then
        echo "Error: Original path is missing from metadata."
        pause
        return
    fi

    echo "Original Path : $original_path"
    echo

    # Confirm before restoring
    read -rp "Restore this file to its original path? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Recovery cancelled."
        pause
        return
    fi

    # Ensure destination directory exists
    local dest_dir
    dest_dir=$(dirname "$original_path")
    if [ ! -d "$dest_dir" ]; then
        echo "Warning: Original directory '$dest_dir' no longer exists."
        read -rp "Create the directory and restore anyway? (y/n): " create_dir
        if [[ "$create_dir" == "y" || "$create_dir" == "Y" ]]; then
            mkdir -p "$dest_dir"
        else
            echo "Recovery cancelled."
            pause
            return
        fi
    fi

    # Warn if a file already exists at the destination
    if [ -e "$original_path" ]; then
        echo "Warning: A file already exists at '$original_path'."
        read -rp "Overwrite it? (y/n): " overwrite
        if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
            echo "Recovery cancelled."
            pause
            return
        fi
    fi

    # Perform the restore
    cp --preserve=all "$SELECTED_FILE" "$original_path"

    # Log the recovery
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] RECOVERED: $filename → $original_path" >> "$LOG_FILE"

    # Label a RECOVERED copy in today's daily backup folder
    local today
    today=$(date '+%-m/%-d/%Y')
    local daily_dir="$MAIN_BACKUP/BackupFolder($today)"
    mkdir -p "$daily_dir"
    chmod 700 "$daily_dir"

    local base_name="${filename#(DELETED)_}"
    base_name=$(echo "$base_name" | sed 's/_[0-9]\{6\}$//')
    local recovered_dest="$daily_dir/(RECOVERED)_${base_name}"

    if [ -e "$recovered_dest" ]; then
        local ts
        ts=$(date '+%H%M%S')
        recovered_dest="$daily_dir/(RECOVERED)_${base_name}_${ts}"
    fi

    cp --preserve=all "$SELECTED_FILE" "$recovered_dest"

    echo
    echo "============================================"
    echo "  File successfully recovered!"
    echo "  Restored to: $original_path"
    echo "  Recovery logged in today's backup folder."
    echo "============================================"
    pause
}

# ─────────────────────────────────────────────
# MAIN MENU
# ─────────────────────────────────────────────
main_menu() {
    while true; do
        print_header
        echo "  [1] Recover a Deleted File"
        echo "  [0] Exit"
        echo
        read -rp "Select an option: " opt

        case "$opt" in
            1)
                pick_daily_folder
                pick_deleted_file
                recover_file
                ;;
            0)
                echo "Exiting recovery system."
                exit 0
                ;;
            *)
                echo "Invalid option."
                pause
                ;;
        esac
    done
}

# ─────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────

# Must run as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
fi

# Check that Main Backup Folder exists
if [ ! -d "$MAIN_BACKUP" ]; then
    echo "Error: Main Backup Folder not found at $MAIN_BACKUP."
    echo "Please run the backup system first."
    exit 1
fi

main_menu
