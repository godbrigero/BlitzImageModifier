SIM_IMAGE ?= blitz-sim:latest
SIM_NETWORK ?= blitz-sim
SIM_CONTAINER_PREFIX ?= blitz-sim
SIM_AUTOBAHN_HOST_PORT_BASE ?= 18080
SIM_WATCHDOG_HOST_PORT_BASE ?= 15000
SIM_SSH_HOST_PORT_BASE ?= 2220
SIM_NAMES ?=
N ?= 1
NAME ?= blitz-sim-1
SERVICE ?= autobahn
LINES ?= 200

SIM_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
SIM_DOCKERFILE := $(SIM_DIR)Dockerfile
SIM_NODES_SCRIPT := $(SIM_DIR)start_nodes.bash

.PHONY: sim-build sim-up sim-down sim-status sim-logs sim-shell sim-hosts sim-hosts-remove sim-clean-hosts

sim-build:
	docker build -f "$(SIM_DOCKERFILE)" -t "$(SIM_IMAGE)" .

sim-up:
	SIM_IMAGE="$(SIM_IMAGE)" \
	SIM_NETWORK="$(SIM_NETWORK)" \
	SIM_CONTAINER_PREFIX="$(SIM_CONTAINER_PREFIX)" \
	SIM_AUTOBAHN_HOST_PORT_BASE="$(SIM_AUTOBAHN_HOST_PORT_BASE)" \
	SIM_WATCHDOG_HOST_PORT_BASE="$(SIM_WATCHDOG_HOST_PORT_BASE)" \
	SIM_SSH_HOST_PORT_BASE="$(SIM_SSH_HOST_PORT_BASE)" \
	SIM_NAMES="$(SIM_NAMES)" \
	N="$(N)" \
	bash "$(SIM_NODES_SCRIPT)" up

sim-down:
	SIM_NETWORK="$(SIM_NETWORK)" bash "$(SIM_NODES_SCRIPT)" down

sim-status:
	bash "$(SIM_NODES_SCRIPT)" status

sim-logs:
	docker exec "$(NAME)" journalctl -u "$(SERVICE)" -n "$(LINES)" --no-pager

sim-shell:
	docker exec -it "$(NAME)" /bin/bash

sim-hosts:
	bash "$(SIM_NODES_SCRIPT)" hosts

sim-hosts-remove:
	bash "$(SIM_NODES_SCRIPT)" hosts-remove

sim-clean-hosts: sim-hosts-remove
