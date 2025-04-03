#!/bin/bash

### Automatic Script Updater
#
# Description:
#   This script updates local scripts by downloading newer versions from GitHub.
#   It is intended for personal use only.
#
# Configuration:
#   See 'gitupdate.conf' for details.
#
# Author: flo.alt@it-flows.de
# Version: 0.8

SCRIPTPATH=$(dirname "$(readlink -e "$0")")
CONFIG_FILE="$SCRIPTPATH/gitupdate.conf"

# Check if the configuration file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE not found!"
    exit 1
fi

ALL_UPDATES_SUCCESSFUL=true  # Flag to track if all updates were successful

# Read $OWNER from config file
OWNER="$(grep '^OWNER=' "$CONFIG_FILE" | cut -d'=' -f2)"

# Read the configuration file line by line, skipping OWNER definition
while IFS=";" read -r SCRIPT_FILE SCRIPT_PATH SCRIPT_URL || [[ -n "$SCRIPT_FILE" ]]; do
    
    # Skip empty lines, comments, or OWNER definition
    [[ -z "$SCRIPT_FILE" || "$SCRIPT_FILE" =~ ^# || "$SCRIPT_FILE" =~ ^OWNER= ]] && continue

    FULL_PATH="$SCRIPT_PATH/$SCRIPT_FILE"
    TMP_FILE="$(mktemp)"
    ETAG_FILE="$FULL_PATH.etag"

    # Check if the target file exists
    if [ ! -f "$FULL_PATH" ]; then
        echo "Error: File $FULL_PATH does not exist. Skipping."
        ALL_UPDATES_SUCCESSFUL=false
        continue
    fi

    # Read the old ETag if available
    if [ -f "$ETAG_FILE" ]; then
        ETAG=$(cat "$ETAG_FILE")
    else
        ETAG=""
    fi

    # Download the file only if the ETag has changed
    HTTP_RESPONSE=$(curl -s -H "If-None-Match: $ETAG" -w "%{http_code}" -o "$TMP_FILE" "$SCRIPT_URL")

    if [ "$HTTP_RESPONSE" -eq 200 ]; then
        # Retrieve new ETag
        NEW_ETAG=$(curl -sI "$SCRIPT_URL" | grep -i "etag" | cut -d' ' -f2-)
        if [ -z "$NEW_ETAG" ]; then
            echo "Error: No ETag received from $SCRIPT_URL."
            rm "$TMP_FILE"
            ALL_UPDATES_SUCCESSFUL=false
        fi

        # Move the updated file
        mv "$TMP_FILE" "$FULL_PATH"
        if [ $? -ne 0 ]; then
            echo "Error moving file to $FULL_PATH."
            rm "$TMP_FILE"
            ALL_UPDATES_SUCCESSFUL=false
        fi

        # Save the new ETag
        echo "$NEW_ETAG" > "$ETAG_FILE"
        if [ $? -ne 0 ]; then
            echo "Error writing ETag to $ETAG_FILE."
            rm "$TMP_FILE"
            ALL_UPDATES_SUCCESSFUL=false
        fi

        # Set permissions & ownership
        chmod 754 "$FULL_PATH"
        chown "$OWNER:root" "$FULL_PATH"

        echo "Update applied for $SCRIPT_FILE."
    
    elif [ "$HTTP_RESPONSE" -eq 304 ]; then
        echo "$SCRIPT_FILE is up to date. No update needed."
        rm "$TMP_FILE"
    
    else
        echo "Error fetching $SCRIPT_FILE (HTTP Code: $HTTP_RESPONSE)."
        rm "$TMP_FILE"
        ALL_UPDATES_SUCCESSFUL=false
    fi

done < "$CONFIG_FILE"

# If all updates were successful, create the 'lastupdate-done' file
if [ "$ALL_UPDATES_SUCCESSFUL" = true ]; then
    touch "$SCRIPTPATH/lastupdate-done"
    echo "All updates successful. Monitoring file created."
else
    echo "One or more updates failed. No monitoring file created."
fi
