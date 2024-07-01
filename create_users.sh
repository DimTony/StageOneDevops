#!/bin/bash

# Path to log file
LOG_FILE="/var/log/user_management.log"
# Path to store passwords
PASSWORD_FILE="/var/secure/user_passwords.txt"

# Function to log actions
log_action() {
    echo "$(date "+%Y-%m-%d %H:%M:%S") - $1" >> $LOG_FILE
}

# Ensure secure directory exists
if [ ! -d /var/secure ]; then

    mkdir -p /var/secure
    chmod 700 /var/secure
fi

# Function to generate a random password
generate_password() {
    tr -dc A-Za-z0-9 </dev/urandom | head -c 12
}

# Clear existing password file and set permissions
> $PASSWORD_FILE
chmod 600 $PASSWORD_FILE

# Check if the argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <file-with-usernames-and-groups>"
    exit 1
fi

# Check if the script is run with root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or use sudo."
    exit 1
fi



# Read the file line by line
while IFS=";" read -r username groups || [[ -n "$username" ]]; do
    # Remove whitespace
    username=$(echo "$username" | xargs)
    groups=$(echo "$groups" | xargs)

    # Skip empty lines and invalid entries
    if [ -z "$username" ]; then
        continue
    fi

    # Check if user already exists
    if id "$username" &>/dev/null; then
        log_action "User $username already exists. Skipping."
        continue
    fi

    # Create user and personal group
    useradd -m -s /bin/bash "$username"
    if [ $? -ne 0 ]; then
        log_action "Failed to create user $username."
        continue
    fi
    log_action "Created user $username and their home directory."

    # Set ownership of the home directory
    chown "$username":"$username" "/home/$username"
    log_action "Set ownership for /home/$username."

    # Generate a random password
    password=$(generate_password)
    echo "$username:$password" | chpasswd
    if [ $? -ne 0 ]; then
        log_action "Failed to set password for $username."
        continue
    fi
    log_action "Set password for $username."

    # Store the password securely
    echo "$username,$password" >> $PASSWORD_FILE

    # Add user to specified groups
    if [ -n "$groups" ]; then
        IFS="," read -ra group_array <<< "$groups"
        for group in "${group_array[@]}"; do
            group=$(echo "$group" | xargs)  # Remove any whitespace
            if [ -n "$group" ]; then
                if ! getent group "$group" >/dev/null; then
                    groupadd "$group"
                    log_action "Created group $group."
                fi
                usermod -aG "$group" "$username"
                log_action "Added $username to group $group."
            fi
        done
    fi

done < "$1"

echo "User creation process completed. Check $LOG_FILE for details."
