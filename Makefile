.SHELLFLAGS := -eu -o pipefail -c
SHELL := /bin/bash

ALLOW_NON_ROOT ?= 0

include make/main.mk
