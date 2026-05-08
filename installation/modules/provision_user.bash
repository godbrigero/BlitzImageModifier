#!/bin/bash
set -euo pipefail

BLITZ_USER="${BLITZ_USER:-ubuntu}"
BLITZ_PASSWORD="${BLITZ_PASSWORD:-ubuntu}"
BLITZ_UID="${BLITZ_UID:-1000}"
BLITZ_GID="${BLITZ_GID:-1000}"

if [[ -z "$BLITZ_USER" || -z "$BLITZ_PASSWORD" || -z "$BLITZ_UID" || -z "$BLITZ_GID" ]]; then
    echo "BLITZ_USER, BLITZ_PASSWORD, BLITZ_UID, and BLITZ_GID must be set." >&2
    exit 1
fi

if ! [[ "$BLITZ_UID" =~ ^[0-9]+$ && "$BLITZ_GID" =~ ^[0-9]+$ ]]; then
    echo "BLITZ_UID and BLITZ_GID must be numeric." >&2
    exit 1
fi

if ! [[ "$BLITZ_USER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
    echo "BLITZ_USER must be a valid Linux username." >&2
    exit 1
fi

if [[ "$BLITZ_PASSWORD" == *$'\n'* || "$BLITZ_PASSWORD" == *:* ]]; then
    echo "BLITZ_PASSWORD cannot contain newlines or colons." >&2
    exit 1
fi

function passwd_name_for_uid() {
    awk -F: -v uid="$1" '$3 == uid { print $1; exit }' /etc/passwd
}

function group_name_for_gid() {
    awk -F: -v gid="$1" '$3 == gid { print $1; exit }' /etc/group
}

if getent passwd "$BLITZ_USER" >/dev/null; then
    EXISTING_UID="$(id -u "$BLITZ_USER")"
    EXISTING_GID="$(id -g "$BLITZ_USER")"
    if [[ "$EXISTING_UID" != "$BLITZ_UID" || "$EXISTING_GID" != "$BLITZ_GID" ]]; then
        echo "User $BLITZ_USER already exists with UID:GID $EXISTING_UID:$EXISTING_GID, expected $BLITZ_UID:$BLITZ_GID." >&2
        exit 1
    fi
else
    EXISTING_UID_USER="$(passwd_name_for_uid "$BLITZ_UID")"
    if [[ -n "$EXISTING_UID_USER" ]]; then
        EXISTING_USER_GID="$(id -g "$EXISTING_UID_USER")"
        if [[ "$EXISTING_USER_GID" != "$BLITZ_GID" ]]; then
            EXISTING_GID_GROUP="$(group_name_for_gid "$BLITZ_GID")"
            if [[ -z "$EXISTING_GID_GROUP" ]]; then
                groupadd --gid "$BLITZ_GID" "$BLITZ_USER"
            fi
            usermod --gid "$BLITZ_GID" "$EXISTING_UID_USER"
        fi

        if getent group "$BLITZ_USER" >/dev/null; then
            EXISTING_GROUP_GID="$(getent group "$BLITZ_USER" | cut -d: -f3)"
            if [[ "$EXISTING_GROUP_GID" != "$BLITZ_GID" ]]; then
                echo "Group $BLITZ_USER already exists with GID $EXISTING_GROUP_GID, expected $BLITZ_GID." >&2
                exit 1
            fi
        else
            EXISTING_GID_GROUP="$(group_name_for_gid "$BLITZ_GID")"
            if [[ -n "$EXISTING_GID_GROUP" ]]; then
                groupmod --new-name "$BLITZ_USER" "$EXISTING_GID_GROUP"
            else
                groupadd --gid "$BLITZ_GID" "$BLITZ_USER"
            fi
        fi

        TARGET_HOME="/home/$BLITZ_USER"
        EXISTING_HOME="$(getent passwd "$EXISTING_UID_USER" | cut -d: -f6)"
        HOME_ARGS=(--home "$TARGET_HOME")
        if [[ "$EXISTING_HOME" != "$TARGET_HOME" && -d "$EXISTING_HOME" && ! -e "$TARGET_HOME" ]]; then
            HOME_ARGS+=(--move-home)
        fi

        usermod \
            --login "$BLITZ_USER" \
            "${HOME_ARGS[@]}" \
            --shell /bin/bash \
            "$EXISTING_UID_USER"
    else
        if getent group "$BLITZ_USER" >/dev/null; then
            EXISTING_GROUP_GID="$(getent group "$BLITZ_USER" | cut -d: -f3)"
            if [[ "$EXISTING_GROUP_GID" != "$BLITZ_GID" ]]; then
                echo "Group $BLITZ_USER already exists with GID $EXISTING_GROUP_GID, expected $BLITZ_GID." >&2
                exit 1
            fi
        elif EXISTING_GID_GROUP="$(group_name_for_gid "$BLITZ_GID")"; [[ -n "$EXISTING_GID_GROUP" ]]; then
            echo "GID $BLITZ_GID is already used by $EXISTING_GID_GROUP." >&2
            exit 1
        else
            groupadd --gid "$BLITZ_GID" "$BLITZ_USER"
        fi

        useradd \
            --uid "$BLITZ_UID" \
            --gid "$BLITZ_GID" \
            --create-home \
            --shell /bin/bash \
            "$BLITZ_USER"
    fi
fi

echo "$BLITZ_USER:$BLITZ_PASSWORD" | chpasswd

PRIMARY_GROUP="$(id -gn "$BLITZ_USER")"
mkdir -p "/home/$BLITZ_USER"
chown "$BLITZ_USER:$PRIMARY_GROUP" "/home/$BLITZ_USER"
chmod 755 "/home/$BLITZ_USER"

if ! getent group sudo >/dev/null; then
    groupadd --system sudo
fi

for GROUP in sudo adm dialout video plugdev input gpio i2c spi; do
    if getent group "$GROUP" >/dev/null; then
        usermod -aG "$GROUP" "$BLITZ_USER"
    fi
done

echo "Provisioned image user $BLITZ_USER ($BLITZ_UID:$BLITZ_GID)."
