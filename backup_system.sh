#!/bin/bash

# Variables
main_backup="/home/ace/Desktop/SYSAD_PROJ/Backup_Folder"
today=$(date +%Y-%m-%d)
targetdr="$main_backup/$today"
source_data="/home/ace/Desktop/SYSAD_PROJ/source_data"

# Ensure folders exist
mkdir -p "$targetdr"
mkdir -p "$source_data"

# Track created files
for file in "$source_data"/*; do
    fname=$(basename "$file")
    cp "$file" "$targetdr/(CREATED)_$fname"
done

# Track deleted files (If a file is missing in source but present in yesterday’s backup)
yesterday=$(date -d "yesterday" +%Y-%m-%d)
yesterdaydr="$main_backup/$yesterday"

if [ -d "$yesterdaydr" ]; then
    for oldfile in "$yesterdaydr"/*; do
        fname=$(basename "$oldfile")
        # If file no longer exists in source_data, mark as deleted
        if [ ! -f "$source_data/${fname#*(CREATED)_}" ]; then
            expiration=$(date -d "+30 days" +%Y-%m-%d)
            cp "$oldfile" "$targetdr/(DELETED $expiration)_${fname#*(CREATED)_}"
        fi
    done
fi

# Compress the folder
tar -czf "$main_backup/${today}.tar.gz" -C "$main_backup" "$today"

# Log the backup
echo "$(date '+%Y-%m-%d %H:%M:%S') Backup completed for $today" >> "$main_backup/backup.log"

# CRemoving of all the deleted files that is older than 30 days
find "$main_backup" -type f -name "(DELETED*_" | while read f; do
    exp_date=$(echo "$f" | sed -n 's/.*(DELETED \([0-9-]\+\)).*/\1/p')
    if [ "$(date -d "$exp_date" +%s)" -lt "$(date +%s)" ]; then
        rm -f "$f"
        echo "$(date '+%Y-%m-%d %H:%M:%S') Deleted file $f permanently removed" >> "$main_backup/backup.log"
    fi
done

