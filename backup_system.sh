#!/bin/bash

# Variables
backupdr="/home/ace/Desktop/SYSAD_PROJ/backups"
today=$(date +%Y-%m-%d)
targetdr="$backupdr/$today"

# Create daily folder
mkdir -p "$targetdr"
mkdir -p /home/ace/Desktop/SYSAD_PROJ/source_data
echo "test file" > /home/ace/Desktop/SYSAD_PROJ/source_data/test.txt


# Copy files (example: from /shared/data)
cp -r /home/ace/Desktop/SYSAD_PROJ/source_data/* "$targetdr/"

# Compress the folder
tar -czf "$backupdr/${today}.tar.gz" -C "$backupdr" "$today"

# Log the backup
echo "$(date '+%Y-%m-%d %H:%M:%S') Backup completed for $today" >> "$backupdr/backup.log"
