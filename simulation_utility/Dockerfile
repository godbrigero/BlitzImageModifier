FROM ubuntu:24.04

ENV container=docker
ENV DEBIAN_FRONTEND=noninteractive
ENV BLITZ_USER=ubuntu
ENV BLITZ_PASSWORD=ubuntu
ENV BLITZ_UID=1000
ENV BLITZ_GID=1000

STOPSIGNAL SIGRTMIN+3

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        iproute2 \
        iputils-ping \
        sudo \
        systemd \
        systemd-sysv \
        dbus \
    && rm -rf /var/lib/apt/lists/*

RUN printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    'command="${1:-}"' \
    'shift || true' \
    'case "$command" in' \
    '  daemon-reload|start|restart|stop|status)' \
    '    exit 0' \
    '    ;;' \
    '  is-system-running)' \
    '    exit 1' \
    '    ;;' \
    '  enable)' \
    '    mkdir -p /etc/systemd/system/multi-user.target.wants' \
    '    for unit in "$@"; do' \
    '      case "$unit" in --*) continue ;; esac' \
    '      case "$unit" in *.service) service_unit="$unit" ;; *) service_unit="${unit}.service" ;; esac' \
    '      source_path=""' \
    '      for unit_dir in /etc/systemd/system /lib/systemd/system /usr/lib/systemd/system; do' \
    '        if [ -f "$unit_dir/$service_unit" ]; then' \
    '          source_path="$unit_dir/$service_unit"' \
    '          break' \
    '        fi' \
    '      done' \
    '      if [ -n "$source_path" ]; then' \
    '        ln -sf "$source_path" "/etc/systemd/system/multi-user.target.wants/$service_unit"' \
    '      else' \
    '        echo "systemctl shim: service file not found for $service_unit" >&2' \
    '      fi' \
    '    done' \
    '    exit 0' \
    '    ;;' \
    '  *)' \
    '    echo "systemctl shim: no-op for $command $*" >&2' \
    '    exit 0' \
    '    ;;' \
    'esac' \
    > /usr/local/sbin/systemctl \
    && chmod +x /usr/local/sbin/systemctl \
    && printf '%s\n' '#!/bin/sh' 'exit 101' > /usr/sbin/policy-rc.d \
    && chmod +x /usr/sbin/policy-rc.d

WORKDIR /workspace

COPY installation /workspace/installation
COPY simulation_utility/entrypoint.bash /usr/local/bin/blitz-sim-entrypoint.bash

RUN chmod +x /usr/local/bin/blitz-sim-entrypoint.bash \
    && cd /workspace/installation/modules \
    && bash ./provision_user.bash \
    && bash ./installation_common.bash \
    && bash ./installation_blitz.bash \
    && bash ./installation_autobahn.bash \
    && bash ./finalize_permissions.bash \
    && mkdir -p /etc/systemd/system/multi-user.target.wants \
    && for unit in blitz-startup.service autobahn.service ssh.service avahi-daemon.service; do \
        found=""; \
        for unit_dir in /etc/systemd/system /lib/systemd/system /usr/lib/systemd/system; do \
            if [ -f "$unit_dir/$unit" ]; then \
                ln -sf "$unit_dir/$unit" "/etc/systemd/system/multi-user.target.wants/$unit"; \
                found=1; \
                break; \
            fi; \
        done; \
        if [ -z "$found" ]; then \
            echo "warning: could not enable missing systemd unit $unit" >&2; \
        fi; \
    done \
    && rm -f /usr/local/sbin/systemctl /usr/sbin/policy-rc.d \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

VOLUME ["/sys/fs/cgroup"]

ENTRYPOINT ["/usr/local/bin/blitz-sim-entrypoint.bash"]
