#!/bin/bash
# Unified Backup + Security System

set -euo pipefail

backup_folder="/home/ace/Desktop/SYSAD_PROJ/Backup_Folder"
source_data="/home/ace/Desktop/SYSAD_PROJ/source_data"
password="secret123"   # replace with your chosen password
today=$(date +%Y-%m-%d)
target="$backup_folder/$today"

# --- Backup at startup ---
mkdir -p "$target"
cp -r "$source_data"/* "$target"
echo "[$(date)] Backup completed to $target"

# --- Secure access function ---
secure_access() {
    read -sp "Enter password: " input
    echo
    if [[ "$input" == "$password" ]]; then
        echo "Access granted. Listing contents:"
        ls -l "$backup_folder"
    else
        echo "Access denied."
        exit 1
    fi
}

# Alias for convenience
alias cd_backup='secure_access'
