#!/bin/bash
set -euo pipefail

COMMAND="${1:-status}"

SIM_IMAGE="${SIM_IMAGE:-blitz-sim:latest}"
SIM_NETWORK="${SIM_NETWORK:-blitz-sim}"
SIM_CONTAINER_PREFIX="${SIM_CONTAINER_PREFIX:-blitz-sim}"
SIM_AUTOBAHN_HOST_PORT_BASE="${SIM_AUTOBAHN_HOST_PORT_BASE:-${SIM_AUTOBANH_HOST_PORT_BASE:-18080}}"
SIM_WATCHDOG_HOST_PORT_BASE="${SIM_WATCHDOG_HOST_PORT_BASE:-15000}"
SIM_SSH_HOST_PORT_BASE="${SIM_SSH_HOST_PORT_BASE:-2220}"
SIM_HOST_IP_PREFIX="${SIM_HOST_IP_PREFIX:-127.42.0}"
SIM_NAMES="${SIM_NAMES:-}"
PYTHON="${PYTHON:-python3}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM_MDNS_BRIDGE="${SIM_MDNS_BRIDGE:-$SCRIPT_DIR/mdns_bridge.py}"
N="${N:-1}"
SIM_STATUS_INTERVAL_SECONDS="${SIM_STATUS_INTERVAL_SECONDS:-3}"

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
    local containers

    containers="$(docker ps -aq --filter label=blitz.simulation=true)"

    if [ -n "$containers" ]; then
        printf '%s\n' "$containers" | xargs docker rm -f >/dev/null
    fi
}

function host_ip_for_index() {
    local index="$1"

    printf '%s.%s\n' "$SIM_HOST_IP_PREFIX" "$index"
}

function is_darwin() {
    [ "$(uname -s)" = "Darwin" ]
}

function ensure_loopback_alias() {
    local host_ip="$1"

    if ! is_darwin; then
        return
    fi

    if ifconfig lo0 | grep -q "inet $host_ip "; then
        return
    fi

    sudo ifconfig lo0 alias "$host_ip" up
}

function remove_loopback_alias() {
    local host_ip="$1"

    if ! is_darwin; then
        return
    fi

    case "$host_ip" in
        "$SIM_HOST_IP_PREFIX".*) ;;
        *) return ;;
    esac

    if ifconfig lo0 | grep -q "inet $host_ip "; then
        sudo ifconfig lo0 -alias "$host_ip" >/dev/null 2>&1 || true
    fi
}

function container_host_ip() {
    local name="$1"

    docker inspect \
        --format '{{ index .Config.Labels "blitz.simulation.host-ip" }}' \
        "$name" 2>/dev/null
}

function current_sim_host_ips() {
    local container
    local host_ip

    docker ps -aq --filter label=blitz.simulation=true | while IFS= read -r container; do
        [ -z "$container" ] && continue
        host_ip="$(container_host_ip "$container")"
        [ -n "$host_ip" ] && printf '%s\n' "$host_ip"
    done
}

function host_ips_from_hosts_block() {
    awk \
        -v begin="$HOSTS_BEGIN" \
        -v end="$HOSTS_END" \
        -v prefix="$SIM_HOST_IP_PREFIX." \
        '$0 == begin { in_block = 1; next } $0 == end { in_block = 0; next } in_block && index($1, prefix) == 1 { print $1 }' \
        /etc/hosts \
        | sort -u
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

function resolved_sim_names() {
    local names=()
    local name

    while IFS= read -r name; do
        [ -n "$name" ] && names+=("$name")
    done < <(sim_names)

    if [ "${#names[@]}" -eq 0 ]; then
        echo "No simulator names resolved." >&2
        exit 1
    fi

    printf '%s\n' "${names[@]}"
}

function start_containers() {
    local names=()
    local name
    local index=1

    while IFS= read -r name; do
        [ -n "$name" ] && names+=("$name")
    done < <(resolved_sim_names)

    require_positive_integer SIM_AUTOBAHN_HOST_PORT_BASE "$SIM_AUTOBAHN_HOST_PORT_BASE"
    require_positive_integer SIM_WATCHDOG_HOST_PORT_BASE "$SIM_WATCHDOG_HOST_PORT_BASE"
    require_positive_integer SIM_SSH_HOST_PORT_BASE "$SIM_SSH_HOST_PORT_BASE"
    ensure_network
    remove_all_sim_containers

    for name in "${names[@]}"; do
        local host_ip
        host_ip="$(host_ip_for_index "$index")"

        remove_container_if_present "$name"
        ensure_loopback_alias "$host_ip"

        docker run -d \
            --name "$name" \
            --hostname "$name" \
            --network "$SIM_NETWORK" \
            --network-alias "$name" \
            --network-alias "$name.local" \
            --label blitz.simulation=true \
            --label "blitz.simulation.host-ip=$host_ip" \
            --privileged \
            --tmpfs /run \
            --tmpfs /run/lock \
            --volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
            -p "${host_ip}:8080:8080" \
            -p "${host_ip}:5000:5000" \
            -p "${host_ip}:22:22" \
            -e "BLITZ_SIM_NAME=$name" \
            "$SIM_IMAGE" >/dev/null

        printf 'started %s: host_ip=%s autobahn=%s:8080 watchdog=%s:5000 ssh=%s:22\n' \
            "$name" "$host_ip" "$host_ip" "$host_ip" "$host_ip" >&2

        index=$((index + 1))
    done

    sync_container_hosts "${names[@]}"

    printf '%s\n' "${names[@]}"
}

function down() {
    local host_ip
    local host_ips

    host_ips="$( (current_sim_host_ips; host_ips_from_hosts_block) | sort -u )"

    remove_all_sim_containers

    if docker network inspect "$SIM_NETWORK" >/dev/null 2>&1; then
        docker network rm "$SIM_NETWORK" >/dev/null 2>&1 || true
    fi

    if hosts_block_exists; then
        hosts_remove
    fi

    while IFS= read -r host_ip; do
        [ -z "$host_ip" ] && continue
        remove_loopback_alias "$host_ip"
    done <<< "$host_ips"
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
    if is_darwin; then
        dscacheutil -flushcache >/dev/null 2>&1 || true
        killall -HUP mDNSResponder >/dev/null 2>&1 || true
    fi
}

function hosts() {
    local names=()
    local name
    local host_ip
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
            host_ip="$(container_host_ip "$name")"
            if [ -z "$host_ip" ]; then
                echo "warning: could not find host IP label for $name" >&2
                continue
            fi
            printf '%s %s.local %s\n' "$host_ip" "$name" "$name"
        done
        printf '%s\n' "$HOSTS_END"
    } >> "$tmp_file"

    sudo cp "$tmp_file" /etc/hosts
    rm -f "$tmp_file"
    flush_host_cache

    printf 'Installed simulator host aliases:\n'
    for name in "${names[@]}"; do
        host_ip="$(container_host_ip "$name")"
        printf '  %s.local -> %s\n' "$name" "${host_ip:-unknown}"
    done
}

function start_mdns_bridge() {
    local log_file="$1"

    if [ ! -f "$SIM_MDNS_BRIDGE" ]; then
        echo "mDNS bridge script not found: $SIM_MDNS_BRIDGE" >&2
        return 1
    fi

    PYTHONUNBUFFERED=1 "$PYTHON" "$SIM_MDNS_BRIDGE" > "$log_file" 2>&1 &
    printf '%s\n' "$!"
}

function start_sudo_keepalive() {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        return
    fi

    sudo -v
    while true; do
        sudo -n -v >/dev/null 2>&1 || exit
        sleep 60
    done &
    sudo_keepalive_pid="$!"
}

function service_status() {
    local name="$1"
    local service="$2"

    docker exec "$name" systemctl is-active "$service" 2>/dev/null || printf 'unknown'
}

function host_port() {
    local name="$1"
    local container_port="$2"

    docker port "$name" "$container_port" 2>/dev/null | sed 's/^[^:]*://' | head -1
}

function draw_status_ui() {
    local names=("$@")
    local name
    local container_status
    local watchdog_status
    local autobahn_status
    local watchdog_port
    local autobahn_port
    local ssh_port
    local host_ip
    local running=0
    local total="${#names[@]}"

    if [ -t 1 ]; then
        printf '\033[2J\033[H'
    fi

    printf 'Blitz simulator running (%s nodes). Press Ctrl+C to stop and clean up.\n' "$total"
    printf 'Host aliases and mDNS bridge are active while this process is running.\n\n'
    printf '%-22s %-12s %-12s %-12s %-22s %-22s %-14s\n' \
        'NAME' 'CONTAINER' 'WATCHDOG' 'AUTOBAHN' 'WATCHDOG URL' 'AUTOBAHN URL' 'SSH'

    for name in "${names[@]}"; do
        container_status="$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || printf 'missing')"
        if [ "$container_status" = "running" ]; then
            running=$((running + 1))
        fi

        watchdog_status="$(service_status "$name" blitz-startup)"
        autobahn_status="$(service_status "$name" autobahn)"
        watchdog_port="$(host_port "$name" 5000/tcp)"
        autobahn_port="$(host_port "$name" 8080/tcp)"
        ssh_port="$(host_port "$name" 22/tcp)"
        host_ip="$(container_host_ip "$name")"

        printf '%-22s %-12s %-12s %-12s %-22s %-22s %-14s\n' \
            "$name" \
            "$container_status" \
            "$watchdog_status" \
            "$autobahn_status" \
            "http://$name.local:${watchdog_port:-5000}" \
            "$name.local:${autobahn_port:-8080}" \
            "${name}.local:${ssh_port:-22}"
    done

    printf '\nDocker nodes running: %s/%s\n' "$running" "$total"
}

function supervise() {
    local names=()
    local name
    local mdns_pid=""
    local sudo_keepalive_pid=""
    local mdns_log=""
    local cleanup_started=false

    mdns_log="$(mktemp)"

    function cleanup_supervisor() {
        if [ "$cleanup_started" = true ]; then
            return
        fi
        cleanup_started=true
        trap - INT TERM HUP EXIT

        printf '\nStopping simulator and cleaning host state...\n'

        if [ -n "$mdns_pid" ] && kill -0 "$mdns_pid" >/dev/null 2>&1; then
            kill "$mdns_pid" >/dev/null 2>&1 || true
            wait "$mdns_pid" >/dev/null 2>&1 || true
        fi

        down

        if [ -n "$sudo_keepalive_pid" ] && kill -0 "$sudo_keepalive_pid" >/dev/null 2>&1; then
            kill "$sudo_keepalive_pid" >/dev/null 2>&1 || true
            wait "$sudo_keepalive_pid" >/dev/null 2>&1 || true
        fi

        rm -f "$mdns_log"
        printf 'Simulator stopped.\n'
    }

    trap cleanup_supervisor INT TERM HUP EXIT

    start_sudo_keepalive
    down

    while IFS= read -r name; do
        [ -n "$name" ] && names+=("$name")
    done < <(start_containers)

    hosts
    mdns_pid="$(start_mdns_bridge "$mdns_log")"

    while true; do
        draw_status_ui "${names[@]}"

        if [ -n "$mdns_pid" ] && ! kill -0 "$mdns_pid" >/dev/null 2>&1; then
            printf '\nERROR: mDNS bridge exited unexpectedly. Recent bridge log:\n' >&2
            tail -20 "$mdns_log" >&2 || true
            exit 1
        fi

        sleep "$SIM_STATUS_INTERVAL_SECONDS"
    done
}

function hosts_remove() {
    local tmp_file
    local host_ips
    local host_ip

    if ! hosts_block_exists; then
        echo "No simulator host aliases found in /etc/hosts."
        return
    fi

    host_ips="$(host_ips_from_hosts_block)"

    tmp_file="$(mktemp)"
    write_hosts_without_sim_block > "$tmp_file"
    sudo cp "$tmp_file" /etc/hosts
    rm -f "$tmp_file"
    flush_host_cache

    while IFS= read -r host_ip; do
        [ -z "$host_ip" ] && continue
        remove_loopback_alias "$host_ip"
    done <<< "$host_ips"

    echo "Removed simulator host aliases from /etc/hosts."
}

require_docker

case "$COMMAND" in
    up)
        supervise
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
