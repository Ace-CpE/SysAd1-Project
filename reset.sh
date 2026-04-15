reset_admin_password_forgot() {
    echo "=== ADMIN PASSWORD RECOVERY MODE ==="
    echo "WARNING: This bypass should only be used if password is forgotten."

    # simple safety check (prevents accidental misuse)
    read -p "Type RECOVER to continue: " confirm

    if [[ "$confirm" != "RECOVER" ]]; then
        echo "Recovery cancelled."
        return 1
    fi

    # optional extra safety (you can remove if not needed)
    echo "Generating recovery lock..."
    recovery_code=$(date +%s | sha256sum | head -c 8)

    echo "Recovery Code: $recovery_code"
    echo "Save this for audit logging."

    read -s -p "Enter NEW admin password: " newpass
    echo
    read -s -p "Confirm NEW admin password: " confirmpass
    echo

    if [[ "$newpass" != "$confirmpass" ]]; then
        echo "ERROR: Passwords do not match."
        return 1
    fi

    specials=$(echo "$newpass" | grep -o '[^a-zA-Z0-9]' | wc -l)

    if ! [[ -n "$newpass" && ${#newpass} -ge 6 \
         && "$newpass" =~ [A-Z] \
         && "$newpass" =~ [0-9] \
         && $specials -eq 1 ]]; then
        echo "Password must be at least 6 chars, include 1 uppercase, 1 number, 1 special char."
        return 1
    fi

    # save hashed password
    openssl passwd -6 "$newpass" > /etc/project_auth
    date +%s > /etc/project_auth_meta
    chmod 600 /etc/project_auth /etc/project_auth_meta

    echo "ADMIN PASSWORD RESET SUCCESSFUL (RECOVERY MODE)"
    log_activity "SECURITY" "PASSWORD_RECOVERY_RESET" "Admin password reset via recovery mode [$recovery_code]"
}
