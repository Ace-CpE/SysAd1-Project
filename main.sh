#!/bin/bash
# MAIN SYSTEM CONTROLLER

set -euo pipefail

# ─────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────
ADMIN_EMAIL="admin@example.com"

BACKUP_SCRIPT="/root/backup_system.sh"
SECURITY_SCRIPT="/root/security_system.sh"
RECOVERY_SCRIPT="/root/recovery_system.sh"

LOG_FILE="/root/main_system.log"

# ─────────────────────────────────────────────
# EMAIL NOTIFICATION FUNCTION
# ─────────────────────────────────────────────
send_alert() {
    local subject="$1"
    local message="$2"

    echo "$message" | mail -s "$subject" "$ADMIN_EMAIL"
}

# ─────────────────────────────────────────────
# START BACKUP SYSTEM (AUTO RUN)
# ─────────────────────────────────────────────
start_backup() {
    echo "[INFO] Starting Backup System..." >> "$LOG_FILE"

    if ! bash "$BACKUP_SCRIPT" & then
        send_alert "BACKUP SYSTEM FAILURE" \
        "Backup system failed to start or crashed."
    fi
}

# ─────────────────────────────────────────────
# CHECK PASSWORD EXPIRATION
# ─────────────────────────────────────────────
check_security_status() {
    META_FILE="/etc/project_auth_meta"
    MAX_DAYS=7

    if [ -f "$META_FILE" ]; then
        last_change=$(cat "$META_FILE")
        days=$(( ( $(date +%s) - last_change ) / 86400 ))

        if [ "$days" -ge "$MAX_DAYS" ]; then
            send_alert "SECURITY ALERT: PASSWORD EXPIRED" \
            "System password has expired. Immediate action required."
        fi
    fi
}

# ─────────────────────────────────────────────
# RECOVERY ACCESS (WITH SECURITY)
# ─────────────────────────────────────────────
access_recovery() {
    echo "======================================="
    echo "  SECURE ACCESS TO BACKUP RECOVERY"
    echo "======================================="

    # Run security check BEFORE allowing recovery
    if bash "$SECURITY_SCRIPT"; then
        bash "$RECOVERY_SCRIPT"
    else
        echo "Access denied."
    fi
}

# ─────────────────────────────────────────────
# MAIN MENU
# ─────────────────────────────────────────────
main_menu() {
    while true; do
        echo
        echo "========== MAIN SYSTEM =========="
        echo "[1] Start Backup System (Auto)"
        echo "[2] Access Recovery System"
        echo "[3] Check Security Status"
        echo "[0] Exit"
        echo "================================"
        read -rp "Choose option: " choice

        case "$choice" in
            1)
                start_backup
                ;;
            2)
                access_recovery
                ;;
            3)
                check_security_status
                echo "Security check complete."
                ;;
            0)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo "Invalid option."
                ;;
        esac
    done
}

# ─────────────────────────────────────────────
# AUTO START (WHEN VM RUNS)
# ─────────────────────────────────────────────

# Automatically start backup in background
start_backup

# Periodically check security (every 1 hour)
(
    while true; do
        check_security_status
        sleep 3600
    done
) &

# Run menu
main_menu
