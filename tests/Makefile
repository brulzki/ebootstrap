# Copyright (c) 2020 Bruce Schultz <brulzki@gmail.com>
# Distributed under the terms of the GNU General Public License v2

# default shell /bin/sh does not work for ebootstrap
#RUNTEST ?= $(SHELL)
RUNTEST ?= /bin/bash

EXCLUDES = test-lib.sh
TESTS = $(filter-out $(EXCLUDES),$(wildcard test-*.sh))

all: test

test: $(TESTS)

$(TESTS):
	@echo "*** $@"
	@$(RUNTEST) $@

.PHONY: all test $(TESTS)
