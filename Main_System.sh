#!/bin/bash
# Main System Master Controller - SysAd Project
 
source "$(dirname "$0")/backup_system.sh"
 
echo "Initializing Project System..."
backup_dirs
daily_folder
 
if ! pgrep -x "inotifywait" > /dev/null; then
    start_inotify
fi
 
start_backup_monitor
 
auto_cleanup
 
while true; do
    echo "------------------------------------------"
    echo "   SYSAD PROJECT: BACKUP & SECURITY"
    echo "------------------------------------------"
    echo "  Base Directory  : $base_dir"
    echo "  Monitored Folder: $watch_dir"
    echo "------------------------------------------"
    echo "1. Run Manual Cleanup Check (30-day rule)"
    echo "2. ACCESS MAIN BACKUP FOLDER (SECURITY)"
    echo "3. View System Logs & Alerts"
    echo "4. Recover a Deleted File"
    echo "5. Check for Duplicate Files"
    echo "6. Renew Admin Password"
    echo "7. Stop Monitor & Exit"
    echo "------------------------------------------"
    read -p "Select Option: " opt
 
    case $opt in
        1)
            auto_cleanup
            echo "Cleanup check complete." ;;
        2)
            if bash "$(dirname "$0")/security_system.sh"; then
                echo "Access Granted."
                ls -R "$main_backup"
            else
                echo "$(date): SECURITY BREACH ATTEMPT" >> "$main_backup/alerts.log"
                echo "ALERT: Breach attempt has been logged."
            fi ;;
        3)
            echo "--- BACKUP LOGS ---"
            [ -f "$log_file" ] && tail -n 10 "$log_file" || echo "No logs yet."
            echo ""
            echo "--- SECURITY ALERTS ---"
            [ -f "$main_backup/alerts.log" ] && tail -n 5 "$main_backup/alerts.log" || echo "No alerts." ;;
        4)
            read -p "Filename to recover (e.g., test.txt): " fname
            read -p "Enter recovery path (e.g., ./monitored_files/): " rpath
            backup_recovered "$fname" "$rpath" ;;
        5)
            check_all_duplicates ;;
        6)
            echo "--- Renew Admin Password ---"
            echo "Re-authentication required before renewing password."
            if ! bash "$(dirname "$0")/security_system.sh"; then
                echo "$(date): UNAUTHORIZED PASSWORD RENEWAL ATTEMPT" >> "$main_backup/alerts.log"
                echo "ALERT: Unauthorized renewal attempt has been logged."
                break
            fi
            read -s -p "Enter New Password: " newpass
            echo
            specials=$(echo "$newpass" | grep -o '[^a-zA-Z0-9]' | wc -l)
            if ! [[ -n "$newpass" && ${#newpass} -ge 6 \
                 && "$newpass" =~ [A-Z] \
                 && "$newpass" =~ [0-9] \
                 && $specials -eq 1 ]]; then
                echo "Password must be at least 6 characters, include 1 uppercase letter, 1 number, and exactly 1 special character."
            else
                openssl passwd -6 "$newpass" > /etc/project_auth
                date +%s > /etc/project_auth_meta
                chmod 600 /etc/project_auth /etc/project_auth_meta
                unset newpass specials
                echo "Password successfully renewed."
                log_activity "SECURITY" "PASSWORD_RENEWED" "Admin password was changed"
            fi ;;
        7)
            echo "Stopping monitor..."
            stop_monitoring
            stop_backup_monitor
            exit 0 ;;
        *)
            echo "Invalid option. Please choose 1-7." ;;
    esac
    read -p "Press Enter to continue..."
done
