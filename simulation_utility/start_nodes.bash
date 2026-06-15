#!/bin/bash
set -euo pipefail

COMMAND="${1:-status}"

SIM_IMAGE="${SIM_IMAGE:-blitz-sim:latest}"
SIM_NETWORK="${SIM_NETWORK:-blitz-sim}"
SIM_CONTAINER_PREFIX="${SIM_CONTAINER_PREFIX:-blitz-sim}"
SIM_AUTOBAHN_HOST_PORT_BASE="${SIM_AUTOBAHN_HOST_PORT_BASE:-${SIM_AUTOBANH_HOST_PORT_BASE:-18080}}"
SIM_WATCHDOG_HOST_PORT_BASE="${SIM_WATCHDOG_HOST_PORT_BASE:-15000}"
SIM_SSH_HOST_PORT_BASE="${SIM_SSH_HOST_PORT_BASE:-2220}"
SIM_NAMES="${SIM_NAMES:-}"
N="${N:-1}"

HOSTS_BEGIN="# BEGIN BlitzImageModifier simulation"
HOSTS_END="# END BlitzImageModifier simulation"

function require_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "docker is required for the simulation utility." >&2
        exit 1
    fi
}

function require_positive_integer() {
    local name="$1"
    local value="$2"
    if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
        echo "$name must be a positive integer; got '$value'." >&2
        exit 1
    fi
}

function require_valid_sim_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Simulator names can only contain letters, numbers, underscores, or hyphens; got '$name'." >&2
        exit 1
    fi
}

function sim_names() {
    local name

    if [ -n "$SIM_NAMES" ]; then
        for name in $(printf '%s\n' "$SIM_NAMES" | tr ',' ' '); do
            require_valid_sim_name "$name"
            printf '%s\n' "$name"
        done
        return
    fi

    require_positive_integer N "$N"
    for index in $(seq 1 "$N"); do
        printf '%s-%s\n' "$SIM_CONTAINER_PREFIX" "$index"
    done
}

function ensure_network() {
    if ! docker network inspect "$SIM_NETWORK" >/dev/null 2>&1; then
        docker network create "$SIM_NETWORK" >/dev/null
    fi
}

function remove_container_if_present() {
    local name="$1"
    if docker container inspect "$name" >/dev/null 2>&1; then
        docker rm -f "$name" >/dev/null
    fi
}

function remove_all_sim_containers() {
    local containers=()
    local container

    while IFS= read -r container; do
        [ -n "$container" ] && containers+=("$container")
    done < <(docker ps -aq --filter label=blitz.simulation=true)

    if [ "${#containers[@]}" -gt 0 ]; then
        docker rm -f "${containers[@]}" >/dev/null
    fi
}

function container_ip() {
    local name="$1"

    docker inspect \
        --format "{{range .NetworkSettings.Networks}}{{if eq .NetworkID \"$(docker network inspect "$SIM_NETWORK" --format '{{.Id}}')\"}}{{.IPAddress}}{{end}}{{end}}" \
        "$name"
}

function sync_container_hosts() {
    local names=("$@")
    local host_lines=()
    local name
    local ip
    local target

    for name in "${names[@]}"; do
        ip="$(container_ip "$name")"
        if [ -z "$ip" ]; then
            echo "warning: could not find Docker network IP for $name" >&2
            continue
        fi
        host_lines+=("$ip $name.local $name")
    done

    if [ "${#host_lines[@]}" -eq 0 ]; then
        return
    fi

    for target in "${names[@]}"; do
        printf '%s\n' "${host_lines[@]}" | docker exec -i "$target" /bin/bash -c '
            set -euo pipefail
            begin="$1"
            end="$2"
            tmp_file="$(mktemp)"
            awk \
                -v begin="$begin" \
                -v end="$end" \
                "$0 == begin { skip = 1; next } $0 == end { skip = 0; next } !skip { print }" \
                /etc/hosts > "$tmp_file"
            printf "%s\n" "$begin" >> "$tmp_file"
            cat >> "$tmp_file"
            printf "%s\n" "$end" >> "$tmp_file"
            cat "$tmp_file" > /etc/hosts
            rm -f "$tmp_file"
        ' _ "$HOSTS_BEGIN" "$HOSTS_END"
    done
}

function up() {
    local names=()
    local name
    local index=1

    while IFS= read -r name; do
        [ -n "$name" ] && names+=("$name")
    done < <(sim_names)

    if [ "${#names[@]}" -eq 0 ]; then
        echo "No simulator names resolved." >&2
        exit 1
    fi

    require_positive_integer SIM_AUTOBAHN_HOST_PORT_BASE "$SIM_AUTOBAHN_HOST_PORT_BASE"
    require_positive_integer SIM_WATCHDOG_HOST_PORT_BASE "$SIM_WATCHDOG_HOST_PORT_BASE"
    require_positive_integer SIM_SSH_HOST_PORT_BASE "$SIM_SSH_HOST_PORT_BASE"
    ensure_network
    remove_all_sim_containers

    for name in "${names[@]}"; do
        local autobahn_port=$((SIM_AUTOBAHN_HOST_PORT_BASE + index - 1))
        local watchdog_port=$((SIM_WATCHDOG_HOST_PORT_BASE + index - 1))
        local ssh_port=$((SIM_SSH_HOST_PORT_BASE + index - 1))

        remove_container_if_present "$name"

        docker run -d \
            --name "$name" \
            --hostname "$name" \
            --network "$SIM_NETWORK" \
            --network-alias "$name" \
            --network-alias "$name.local" \
            --label blitz.simulation=true \
            --privileged \
            --tmpfs /run \
            --tmpfs /run/lock \
            --volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
            -p "127.0.0.1:${autobahn_port}:8080" \
            -p "127.0.0.1:${watchdog_port}:5000" \
            -p "127.0.0.1:${ssh_port}:22" \
            -e "BLITZ_SIM_NAME=$name" \
            "$SIM_IMAGE" >/dev/null

        printf 'started %s: autobahn=127.0.0.1:%s watchdog=127.0.0.1:%s ssh=127.0.0.1:%s\n' \
            "$name" "$autobahn_port" "$watchdog_port" "$ssh_port"

        index=$((index + 1))
    done

    sync_container_hosts "${names[@]}"

    printf 'optional: run `make sim-hosts` to map simulator .local names to 127.0.0.1 on this host.\n'
}

function down() {
    remove_all_sim_containers

    if docker network inspect "$SIM_NETWORK" >/dev/null 2>&1; then
        docker network rm "$SIM_NETWORK" >/dev/null 2>&1 || true
    fi

    if hosts_block_exists; then
        hosts_remove
    fi
}

function status() {
    docker ps -a \
        --filter label=blitz.simulation=true \
        --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
}

function running_container_names() {
    docker ps \
        --filter label=blitz.simulation=true \
        --format '{{.Names}}' \
        | sort
}

function write_hosts_without_sim_block() {
    awk \
        -v begin="$HOSTS_BEGIN" \
        -v end="$HOSTS_END" \
        '$0 == begin { skip = 1; next } $0 == end { skip = 0; next } !skip { print }' \
        /etc/hosts
}

function hosts_block_exists() {
    grep -qxF "$HOSTS_BEGIN" /etc/hosts && grep -qxF "$HOSTS_END" /etc/hosts
}

function flush_host_cache() {
    if [ "$(uname -s)" = "Darwin" ]; then
        dscacheutil -flushcache >/dev/null 2>&1 || true
        killall -HUP mDNSResponder >/dev/null 2>&1 || true
    fi
}

function hosts() {
    local names=()
    local name
    local tmp_file

    while IFS= read -r name; do
        [ -n "$name" ] && names+=("$name")
    done < <(running_container_names)

    if [ "${#names[@]}" -eq 0 ]; then
        echo "No running simulator containers found." >&2
        exit 1
    fi

    tmp_file="$(mktemp)"
    write_hosts_without_sim_block > "$tmp_file"
    {
        printf '%s\n' "$HOSTS_BEGIN"
        for name in "${names[@]}"; do
            printf '127.0.0.1 %s.local %s\n' "$name" "$name"
        done
        printf '%s\n' "$HOSTS_END"
    } >> "$tmp_file"

    sudo cp "$tmp_file" /etc/hosts
    rm -f "$tmp_file"
    flush_host_cache

    printf 'Installed simulator host aliases:\n'
    for name in "${names[@]}"; do
        printf '  %s.local -> 127.0.0.1\n' "$name"
    done
}

function hosts_remove() {
    local tmp_file

    if ! hosts_block_exists; then
        echo "No simulator host aliases found in /etc/hosts."
        return
    fi

    tmp_file="$(mktemp)"
    write_hosts_without_sim_block > "$tmp_file"
    sudo cp "$tmp_file" /etc/hosts
    rm -f "$tmp_file"
    flush_host_cache

    echo "Removed simulator host aliases from /etc/hosts."
}

require_docker

case "$COMMAND" in
    up)
        up
        ;;
    down)
        down
        ;;
    status)
        status
        ;;
    hosts)
        hosts
        ;;
    hosts-remove)
        hosts_remove
        ;;
    *)
        echo "Usage: $0 {up|down|status|hosts|hosts-remove}" >&2
        exit 1
        ;;
esac
