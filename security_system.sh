#!/bin/bash
#Security System

set -euo pipefail

#Forcing Root Access
if [ "$EUID" -ne 0 ]; then
    echo "This must be run as root"
    exit 1
fi

#Variables
psswrd_file="/etc/project_auth"
mt_file="/etc/project_auth_meta"
max=7

umask 077

#Creating Initial Password for the System 
ini_password() {
    if [ ! -f "$psswrd_file" ]; then
        echo "Warning!: No system password yet. Please create one."
        read -s -p "Enter your new password: " newpass
        echo 

# Password
        specials=$(echo "$newpass" | grep -o '[^a-zA-Z0-9]' | wc -l)
        if ! [[ -n "$newpass" && ${#newpass} -ge 6 && "$newpass" =~ [A-Z] && "$newpass" =~ [0-9] && $specials -eq 1 ]]; then
            echo "Password must be at least 6 characters, include one uppercase letter, one number, and exactly one special character."
            exit 1
        fi
                openssl passwd -6 "$newpass" > "$psswrd_file"
                date +%s > "$mt_file"
                chmod 600 "$psswrd_file" "$mt_file"
                unset newpass specials
                echo "System Password Successfully Assigned."
    fi      
}

#Password Aging or Expiration
psswrd_expiration() {
    if [ -f "$mt_file" ]; then
        last_change=$(cat "$mt_file")
        since=$(( ( $(date +%s) - last_change ) / 86400 ))
        if [ $since -ge $max ]; then 
            echo "WARNING: The System is Insecure, Files and Data may be Compromised"
            renew_psswrd
        fi
    fi
}

#User Authentication
authenticate() {
    max_attempts=3
    attempt=0

    while [ $attempt -lt $max_attempts ]; do 
        echo -n "Enter the System Password: "
        read -s input
        echo

    if [[ -z "$input" ]]; then
            echo "Password cannot be empty."
            continue
    fi
       
    stored_hash=$(cat "$psswrd_file")

    salt=$(echo "$stored_hash" | cut -d '$' -f3)
    input_hash=$(openssl passwd -6 -salt "$salt" "$input")

     if [ "$input_hash" = "$stored_hash" ]; then
            echo "Access Granted."
            unset input input_hash   
            psswrd_expiration
            return
        else
            echo "Incorrect password."
            attempt=$((attempt + 1))   
        fi
    done

    echo "Too many failed attempts. Access denied."   
    exit 1
}

#Password Renewal
renew_psswrd() {
    echo "Renew the system Password: "
    read -s -p "Enter the New Password: " newpass 
    echo

    specials=$(echo "$newpass" | grep -o '[^a-zA-Z0-9]' | wc -l)
    if ! [[ -n "$newpass" && ${#newpass} -ge 6 && "$newpass" =~ [A-Z] && "$newpass" =~ [0-9] && $specials -eq 1 ]]; then
        echo "Password must be at least 6 characters, include one uppercase letter, one number, and exactly one special character."
        return
    fi
    
    openssl passwd -6 "$newpass" > "$psswrd_file" 
    date +%s > "$mt_file"
    chmod 600 "$psswrd_file" "$mt_file"
    unset newpass specials
    echo "Password Successfully Renewed."
}
