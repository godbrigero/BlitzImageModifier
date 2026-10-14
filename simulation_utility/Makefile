BLITZ_REF ?= HEAD
BLITZ_GIT_URL ?= https://github.com/PinewoodRobotics/B.L.I.T.Z.git
SIM_IMAGE ?= blitz-sim:latest
SIM_NETWORK ?= blitz-sim
SIM_CONTAINER_PREFIX ?= blitz-sim
SIM_HOST_IP_PREFIX ?= 127.42.0
SIM_NAMES ?=
N ?= 1
NAME ?= blitz-sim-1
SERVICE ?= blitz-startup
LINES ?= 200
FOLLOW ?= 0

SIM_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
SIM_BUILD_SCRIPT := $(SIM_DIR)build_image.bash
SIM_NODES_SCRIPT := $(SIM_DIR)start_nodes.bash

.PHONY: sim-build sim-up sim-down sim-status sim-logs sim-shell sim-hosts sim-hosts-remove sim-clean-hosts

sim-build:
	BLITZ_REF="$(BLITZ_REF)" BLITZ_GIT_URL="$(BLITZ_GIT_URL)" SIM_IMAGE="$(SIM_IMAGE)" bash "$(SIM_BUILD_SCRIPT)"

sim-up:
	SIM_IMAGE="$(SIM_IMAGE)" \
	SIM_NETWORK="$(SIM_NETWORK)" \
	SIM_CONTAINER_PREFIX="$(SIM_CONTAINER_PREFIX)" \
	SIM_HOST_IP_PREFIX="$(SIM_HOST_IP_PREFIX)" \
	SIM_NAMES="$(SIM_NAMES)" \
	N="$(N)" \
	bash "$(SIM_NODES_SCRIPT)" up

sim-down:
	SIM_NETWORK="$(SIM_NETWORK)" bash "$(SIM_NODES_SCRIPT)" down

sim-status:
	bash "$(SIM_NODES_SCRIPT)" status

sim-logs:
	docker exec $(if $(filter 1,$(FOLLOW)),-it) "$(NAME)" journalctl -u "$(SERVICE)" -n "$(LINES)" --no-pager $(if $(filter 1,$(FOLLOW)),--follow)

sim-shell:
	docker exec -it "$(NAME)" /bin/bash

sim-hosts:
	bash "$(SIM_NODES_SCRIPT)" hosts

sim-hosts-remove:
	bash "$(SIM_NODES_SCRIPT)" hosts-remove

sim-clean-hosts: sim-hosts-remove
