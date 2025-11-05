#!/bin/bash

INSTALLATION_DIR="/opt/blitz"
NAME_PATH="$INSTALLATION_DIR/B.L.I.T.Z/system_data/name.txt"

if [ -z $NAME_PATH ]; then
    echo "UNDEFINED BEHAVIOR: No name.txt file found in ~/Documents/B.L.I.T.Z/system_data/"
    exit 1
fi

NAME=$(cat $NAME_PATH)

if [ "$NAME" != "blitz-pi-random-name-1234" ]; then
    exit 0
fi

function get_name() {
    read -p "Enter a name for the Blitz Pi: " NEW_NAME
    if [[ "$NEW_NAME" == *" "* ]]; then
        echo "Name cannot contain spaces, try again"
        get_name
    fi
    echo "$NEW_NAME"
}

NAME=$(get_name)
echo "$NAME" > $NAME_PATH
reboot