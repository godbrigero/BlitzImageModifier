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
export BLITZ_USER
export BLITZ_PASSWORD
export BLITZ_UID
export BLITZ_GID

build-all:
	COMPILE_ALL=true docker-compose up --build

build-for:
	COMPILE_ALL=false FOR_X=$(ARGS) docker-compose up --build

# Swallow the device goal so "make build-for jetsonnano" does not fail on "jetsonnano".
ifneq ($(_device),)
$(_device):
	@:
endif
