include simulation_utility/Makefile

# First extra target is the device, e.g. "make build-for jetsonnano" -> ARGS=jetsonnano
ifneq ($(filter build-for,$(MAKECMDGOALS)),)
  _device := $(firstword $(filter-out build-for,$(MAKECMDGOALS)))
endif
ifneq ($(_device),)
  ARGS := $(_device)
else
  ARGS ?= pi5
endif

BLITZ_USER ?= ubuntu
BLITZ_PASSWORD ?= ubuntu
BLITZ_UID ?= 1000
BLITZ_GID ?= 1000
ifneq ($(origin BLITZ_SOURCE_DIR),undefined)
export BLITZ_SOURCE_DIR
endif
export BLITZ_REF
export BLITZ_GIT_URL
export BLITZ_USER
export BLITZ_PASSWORD
export BLITZ_UID
export BLITZ_GID
export BLITZ_ROUTER_ENABLED BLITZ_ROUTER_SSID BLITZ_ROUTER_PASSWORD
export BLITZ_ROUTER_WIFI_INTERFACE BLITZ_ROUTER_LAN_INTERFACES BLITZ_ROUTER_ADDRESS
export BLITZ_ROUTER_COUNTRY

build-all:
	COMPILE_ALL=true docker compose run --build --rm blitz_compilation

build-for:
	COMPILE_ALL=false FOR_X=$(ARGS) docker compose run --build --rm blitz_compilation

# Swallow the device goal so "make build-for jetsonnano" does not fail on "jetsonnano".
ifneq ($(_device),)
$(_device):
	@:
endif
