#!/bin/bash
#Security System

#Variables
psswrd_file="/etc/project_auth"
mt_file="/meta/project_auth_meta"
max=7

#Creating Initial Password for the System 
ini_password() {
    if [ ! -f "$psswrd_file" ]; then
        echo "No system password yet. Please create one."
        read -s -p "Enter your new password: " newpass
        echo 

        openssl passwd -6 "newpass" > "psswrd_file"

        date +%s "mt_file"
        echo "System Password Successfully Assigned."
    fi
}

#Password Aging or Expiration
psswrd_expiration() {
    if [ -f "mt_file" ]; then
        last_change=$(cat "$mt_file")
        since=$(( ( $(date +%s) - last_change ) / 86400 ))
        if [ $since -ge $max ]; then 
            echo "WARNING: The System is Insecure, Files and Data may be Compromised"
        fi
    fi
}

#User Authentication
authenthicate() {
    echo -n "Enter the System Password: "
    read -s input
    echo
    stored_hash=$(cat "psswrd_file")
    input_hash=$(openssl passwd -6 -stdin <<< "$input")

    if [ "$input_hash" = "$stored_hash" ]; then
        echo "Access Granted."
        psswrd_expiration
    else
        echo "Access Denied"
        exit 1
    fi
}

#Password Renewal
renew_psswrd() {
    echo "Renew the system Password: "
    read -s -p "Enter the New Password: " newpass 
    echo
    openssl  password -6 "$newpass" > "psswrd_file" 
    date +%s > "mt_file"
    echo "Password Successfully Renewed."
}
