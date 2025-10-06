BASE_DIR="/mnt/c/user_management"
LOG_FILE="$BASE_DIR/user_management.log"
PASSWORD_FILE="$BASE_DIR/user_passwords.csv"
if [[ $EUID -ne 0 ]]; then
    echo " Please run this script as root (use sudo)."
    exit 1
fi

# -------------------------------
# Input File Check
# -------------------------------
if [[ $# -ne 1 ]]; then
    echo "Usage: sudo bash $0 <user_list_file>"
    exit 1
fi

INPUT_FILE="$1"

if [[ ! -f "$INPUT_FILE" ]]; then
    echo " File not found: $INPUT_FILE"
    exit 1
fi

# -------------------------------
# Setup Directories and Permissions
# -------------------------------
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

mkdir -p "$SECURE_DIR"
touch "$PASSWORD_FILE"

chmod 700 "$SECURE_DIR"
chmod 600 "$PASSWORD_FILE"

echo "========== $(date): Starting User Creation ==========" >> "$LOG_FILE"

# -------------------------------
# Main Processing Loop
# -------------------------------
while IFS=";" read -r username groups; do
    # Skip empty lines or comments
    [[ -z "$username" ]] && continue

    username=$(echo "$username" | xargs) # remove extra spaces
    groups=$(echo "$groups" | xargs | tr -d ' ') # remove spaces in group list

    echo "Processing user: $username" | tee -a "$LOG_FILE"

    # Create personal group
    if ! getent group "$username" >/dev/null; then
        groupadd "$username"
        echo "Created group: $username" >> "$LOG_FILE"
    else
        echo "Group $username already exists, skipping." >> "$LOG_FILE"
    fi

    # Create user if not exists
    if ! id "$username" &>/dev/null; then
        useradd -m -g "$username" -s /bin/bash "$username"
        echo "Created user: $username" >> "$LOG_FILE"
    else
        echo "User $username already exists, skipping." >> "$LOG_FILE"
        continue
    fi

    # Add user to additional groups
    if [[ -n "$groups" ]]; then
        IFS="," read -ra ADD_GROUPS <<< "$groups"
        for grp in "${ADD_GROUPS[@]}"; do
            grp=$(echo "$grp" | xargs)
            if ! getent group "$grp" >/dev/null; then
                groupadd "$grp"
                echo "Created group: $grp" >> "$LOG_FILE"
            fi
            usermod -aG "$grp" "$username"
            echo "Added $username to group: $grp" >> "$LOG_FILE"
        done
    fi

    # Set home directory permissions
    chmod 700 "/home/$username"
    chown -R "$username:$username" "/home/$username"

    # Generate random password
    password=$(openssl rand -base64 12)
    echo "$username,$password" >> "$PASSWORD_FILE"
    echo "$username:$password" | chpasswd
    echo "Password set for user: $username" >> "$LOG_FILE"

done < "$INPUT_FILE"

# -------------------------------
# Finish Logging
# -------------------------------
echo "========== $(date): User Creation Completed ==========" >> "$LOG_FILE"

echo " All users created successfully!"
echo " Log File: $LOG_FILE"
echo " Password File: $PASSWORD_FILE (root only access)"
