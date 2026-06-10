#!/usr/bin/env bash
export DISPLAY=:0
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/0/bus

DISTRO_DIR="/default-distros"

# Hard stop if the core flat-file database didn't copy over
if [ ! -d "$DISTRO_DIR" ]; then
    yad --error --title="Fatal Error" --width=400 \
        --text="The local distribution registry matrix (/default-distros) is missing.\nCannot proceed with installation."
    exit 1
fi

# 1. PARSE THE DECOUPLED DATA DIRECTORIES
YAD_ARGS=()
FIRST_ROW=true
while IFS= read -r d; do
    INI_FILE="$d/variants.ini"
    [ ! -f "$INI_FILE" ] && continue

    LOGO="preferences-desktop-theme"
    if [ -f "$d/logo.png" ]; then LOGO="$d/logo.png"; fi

    current_section=""
    current_name=""
    current_url=""
    current_desc=""

    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^\[(.*)\]$ ]]; then
            if [ -n "$current_name" ] && [ -n "$current_url" ]; then
                YAD_ARGS+=("$FIRST_ROW" "$LOGO" "$current_name" "$current_url" "$current_desc")
                FIRST_ROW=false
            fi
            current_section="${BASH_REMATCH[1]}"
            current_name=""
            current_url=""
            current_desc="No description provided."
        elif [[ "$line" =~ ^name=(.*)$ ]]; then
            current_name="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^url=(.*)$ ]]; then
            current_url="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^description=(.*)$ ]]; then
            current_desc="${BASH_REMATCH[1]}"
        fi
    done < "$INI_FILE"

    if [ -n "$current_name" ] && [ -n "$current_url" ]; then
        YAD_ARGS+=("$FIRST_ROW" "$LOGO" "$current_name" "$current_url" "$current_desc")
        FIRST_ROW=false
    fi
done < <(find "$DISTRO_DIR" -mindepth 1 -maxdepth 1 -type d)


# 2. INTERACTIVE LOOP WITH STRICT VALIDATION
while true; do
    # Render the primary menu list
    CHOSEN_ROW=$(yad --list \
      --title="Universal Blue Evergreen Deployer" \
      --width=750 --height=500 --center --fixed \
      --text="Select your target hardware container deployment layout:" \
      --radiolist \
      --column="Select" --column="Icon:IMG" --column="Variant" --column="OCI Target Endpoint" --column="Description:hide" \
      "${YAD_ARGS[@]}" \
      --dclick-action="none" \
      --button="Deploy Profile:0" --button="Custom Repo String:2" --button="Cancel:1")

    ACTION_STATUS=$?

    # Handle explicit installation cancellation
    if [ "$ACTION_STATUS" -eq 1 ] || [ -z "$CHOSEN_ROW" ]; then
        yad --warning --title="Aborted" --text="Installation cancelled by user. Rebooting..." --width=300
        exit 1
    fi

    # Branch routing based on user input type
    if [ "$ACTION_STATUS" -eq 2 ]; then
        FINAL_URL=$(yad --entry \
          --title="Custom OCI Deployment" \
          --text="Enter or paste any valid bootc/ublue container address:" \
          --entry-text="docker://ghcr.io/")
    else
        FINAL_URL=$(echo "$CHOSEN_ROW" | awk -F '|' '{print $4}')
    fi

    # Clean up formatting: Ensure the string has the single 'docker://' scheme prefix expected by podman/skopeo
    FINAL_URL=$(echo "$FINAL_URL" | sed -E 's|^(docker://)?|docker://|')

    # Remove the prefix temporarily to run a lightweight network look-up check via skopeo or podman
    RAW_REGISTRY_PATH=${FINAL_URL#docker://}

    # Display a non-blocking progress spinner while verifying the remote image layers over the network
    yad --title="Validating Target" --text="Verifying connection to remote OCI image:\n$RAW_REGISTRY_PATH" --progress --pulsate --auto-close &
    SPINNER_PID=$!

    # Execute a remote manifest inspection check to ensure the repository path actually exists and is accessible
    podman manifest inspect "docker://$RAW_REGISTRY_PATH" > /dev/null 2>&1
    VALIDATION_RESULT=$?

    # Kill the background progress spinner window
    kill $SPINNER_PID 2>/dev/null

    # 3. EVALUATE THE VALIDATION TRUTH STATE
    if [ "$VALIDATION_RESULT" -eq 0 ]; then
        # The container was resolved successfully. Write the file and exit the loop.
        echo "bootc --image=${FINAL_URL}" > /tmp/bootc-target.ks
        break
    else
        # Error Handled: Do not fall back to another image. Pop up an error and retry.
        yad --error \
          --title="Deployment Error" \
          --width=450 \
          --text="<b>Could not resolve target image:</b>\n<i>$RAW_REGISTRY_PATH</i>\n\nPlease check your network connection, verify that the image name is spelled correctly, and make sure the repository is public."
    fi
done