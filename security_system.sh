#!/bin/bash
# Security System: Password Authorization & Aging (Regex Version)

# Forced Root Access
if [ "$EUID" -ne 0 ]; then
    echo "Error: Authorization system must be run with sudo/root."
    exit 1
fi

# System-wide paths for credentials
pwd_f="/etc/project_auth"
mt_f="/etc/project_auth_meta"

NOTIFY_EMAIL="qamrtadalan@tip.edu.ph"
NOTIFY_EMAIL="nikkandoy9@gmail.com"

# --- PRODUCTION: 7 days = 604800 seconds ---
#EXPIRY_SECONDS=604800
EXPIRY_SECONDS=300

send_expiry_email() {
    local seconds_since="$1"

    # Convert elapsed time (in seconds) to days
    #local days_since=$((seconds_since / 86400))
    local minutes_since=$((seconds_since / 60))

    # Get current timestamp for logging/reporting
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    local body="Backup System Report
==============================
Time     : $timestamp
Function : password_expiry
Status   : EXPIRED
Detail   : Admin password expired (${minutes_since} day(s) old - 7 day policy)
Host     : $(hostname)
User     : $(whoami)
=============================="

#Detail   : Admin password expired (${days_since} day(s) old - 7 day policy)#

    # Send email (with basic error handling)
    if echo "$body" | msmtp -a gmail "$NOTIFY_EMAIL" 2>/dev/null; then
        echo "NOTIFICATION sent to $NOTIFY_EMAIL --- password expired"
    else
        echo "WARNING: Failed to send email notification"
    fi
}

# Initial Setting of Password for the System
if [ ! -f "$pwd_f" ]; then
    echo "--- SYSTEM INITIALIZATION: Set Admin Password ---"

    while true; do
        read -s -p "Create New Admin Password: " p
        echo

        # Regex password policy:
        # At least 8 chars, 1 uppercase, 1 lowercase, 1 number, 1 special char
        if [[ "$p" =~ ^(?=.*[A-Z])(?=.*[a-z])(?=.*[0-9])(?=.*[^A-Za-z0-9]).{8,}$ ]]; then
            break
        else
            echo "Invalid password. Must contain at least:"
            echo "- 8 characters"
            echo "- 1 uppercase letter"
            echo "- 1 lowercase letter"
            echo "- 1 number"
            echo "- 1 special character"
        fi
    done

    openssl passwd -6 "$p" > "$pwd_f"
    date +%s > "$mt_f"
    chmod 600 "$pwd_f" "$mt_f"

    echo "Password secured in $pwd_f"
fi

# Read stored hash
stored_hash=$(cat "$pwd_f")

# Verify stored hash format using regex
if [[ ! "$stored_hash" =~ ^\$6\$[^$]+\$.*$ ]]; then
    echo "Error: Stored password hash format is invalid."
    exit 1
fi

# Extract salt from SHA-512 hash using regex
if [[ "$stored_hash" =~ ^\$6\$([^$]+)\$ ]]; then
    salt="${BASH_REMATCH[1]}"
else
    echo "Error: Could not extract salt from password hash."
    exit 1
fi

# 3-Attempt Login Policy
for i in {1..3}; do
    read -s -p "Enter Admin Password: " in
    echo

    generated_hash=$(openssl passwd -6 -salt "$salt" "$in")

    if [[ "$generated_hash" == "$stored_hash" ]]; then

        # Password Expiration Logic (10 minutes demo)
        mins=$(( ($(date +%s) - $(cat "$mt_f")) / 60 ))

        if [ "$mins" -ge 10 ]; then
            echo "Warning: Password Expired. The System is Insecure, Files may be Compromised"

            confirmed=false

            for j in {1..3}; do
                read -s -p "Re-enter Expired Password to Confirm: " confirm
                echo

                confirm_hash=$(openssl passwd -6 -salt "$salt" "$confirm")

                if [[ "$confirm_hash" == "$stored_hash" ]]; then
                    confirmed=true
                    break
                fi

                echo "Incorrect. $((3-j)) confirmation attempts remaining."
            done

            if [ "$confirmed" = false ]; then
                echo "Confirmation failed. Password renewal failed."
                exit 1
            fi

            while true; do
                read -s -p "Enter New Password: " n
                echo

                if [[ "$n" =~ ^(?=.*[A-Z])(?=.*[a-z])(?=.*[0-9])(?=.*[^A-Za-z0-9]).{8,}$ ]]; then
                    break
                else
                    echo "New password does not meet the required format."
                fi
            done

            openssl passwd -6 "$n" > "$pwd_f"
            date +%s > "$mt_f"

            echo "Password successfully renewed."
        fi

        echo "Access Granted."
        exit 0
    fi

    echo "Access Denied. $((3-i)) attempts remaining."
done

echo "Access Terminated."
exit 1
