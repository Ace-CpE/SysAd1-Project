#!/bin/bash
# Main System: Final Integration
 
# ─────────────────────────────────────────────
# BACKUP SYSTEM HEALTH CHECK BEFORE SOURCING
# ─────────────────────────────────────────────
BACKUP_SCRIPT="./BackupSystem.sh"
 
if [ ! -f "$BACKUP_SCRIPT" ]; then
    echo "=========================================="
    echo "  CRITICAL WARNING: BackupSystem.sh       "
    echo "  NOT FOUND. System cannot start.         "
    echo "=========================================="
    exit 1
fi
 
# Validate syntax of BackupSystem before sourcing
if ! bash -n "$BACKUP_SCRIPT" 2>/tmp/backup_syntax_err; then
    echo "=========================================="
    echo "  CRITICAL WARNING: BackupSystem.sh       "
    echo "  contains SYNTAX ERRORS and is unsafe.   "
    echo "------------------------------------------"
    cat /tmp/backup_syntax_err
    echo "=========================================="
    echo "  System startup ABORTED.                 "
    echo "=========================================="
    exit 1
fi
 
# Source the backup system
source "$BACKUP_SCRIPT"
 
# Check if BackupSystem self-validation passed
if [ "$BACKUP_SYSTEM_OK" != true ]; then
    echo "=========================================="
    echo "  CRITICAL WARNING: BackupSystem failed   "
    echo "  its internal integrity validation.      "
    echo "  Backup operations are DISABLED.         "
    echo "=========================================="
    echo "  System startup ABORTED.                 "
    echo "=========================================="
    exit 1
fi
 
# ─────────────────────────────────────────────
# BACKUP SYSTEM WATCHDOG: monitors PID health
# ─────────────────────────────────────────────
check_backup_alive() {
    if [ "$BACKUP_SYSTEM_OK" != true ]; then
        echo ""
        echo "  !! WARNING: BackupSystem is in a FAILED state. !!"
        echo "  !! Backup operations are currently UNAVAILABLE. !!"
        echo ""
        return 1
    fi
 
    if [ -n "$monitoring_PID" ] && ! kill -0 "$monitoring_PID" 2>/dev/null; then
        echo ""
        echo "  !! WARNING: The BackupSystem monitor has TERMINATED unexpectedly. !!"
        echo "  !! File monitoring is no longer active. Restart recommended.      !!"
        echo ""
        return 1
    fi
 
    return 0
}
 
# ─────────────────────────────────────────────
# INITIAL AUTOMATION
# ─────────────────────────────────────────────
echo "Initializing Project System..."
start_inotify
auto_cleanup
 
while true; do
    echo "------------------------------------------"
    echo "  SYSDAD PROJECT: BACKUP & SECURITY      "
    echo "------------------------------------------"
 
    # Show watchdog status at top of each menu loop
    check_backup_alive
 
    echo "1. Run Manual Cleanup Check"
    echo "2. ACCESS MAIN BACKUP FOLDER (SECURITY)"
    echo "3. View System Logs & Alerts"
    echo "4. Recover a Deleted File"
    echo "5. Stop Monitor & Exit"
    echo "------------------------------------------"
    read -p "Select Option: " opt
 
    case $opt in
        1) auto_cleanup ;;
        2)
            if ! check_backup_alive; then
                echo "Backup access blocked: BackupSystem is not healthy."
            elif ./SecuritySystem.sh; then
                echo "Access Granted."
                ls -R "$main_backup"
            else
                echo "$(date): SECURITY BREACH ATTEMPT" >> "$main_backup/alerts.log"
                echo "ALERT: Admin has been notified of the breach."
            fi ;;
        3)
            echo "--- BACKUP LOGS ---"
            [ -f "$log_file" ] && tail -n 10 "$log_file"
            echo -e "\n--- SECURITY ALERTS ---"
            [ -f "$main_backup/alerts.log" ] && tail -n 5 "$main_backup/alerts.log" ;;
        4)
            if ! check_backup_alive; then
                echo "Recovery blocked: BackupSystem is not healthy."
            else
                read -p "Filename to recover: " fname
                read -p "Recover into which path? " rpath
                backup_recovered "$fname" "$rpath"
            fi ;;
        5)
            stop_monitoring
            exit 0 ;;
    esac
    read -p "Press Enter to continue..."
done
