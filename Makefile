# ClawdKit Makefile
# Usage: make <target> [INSTANCE=<agent_name>]
# Default instance name: clawdkit

INSTANCE ?= clawdkit

REPO_ROOT  := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
SCRIPTS    := $(REPO_ROOT)daemon/scripts
CLAWDKIT   := $(SCRIPTS)/clawdkit.sh

.PHONY: start stop restart status health install uninstall

# ---------------------------------------------------------------------------
# Lifecycle targets — delegate to clawdkit.sh
# ---------------------------------------------------------------------------

start:
	@$(CLAWDKIT) --instance $(INSTANCE) start

stop:
	@$(CLAWDKIT) --instance $(INSTANCE) stop

restart:
	@$(CLAWDKIT) --instance $(INSTANCE) restart

status:
	@$(CLAWDKIT) --instance $(INSTANCE) status

health:
	@$(CLAWDKIT) --instance $(INSTANCE) health

# ---------------------------------------------------------------------------
# Scheduler install/uninstall — delegate to clawdkit.sh
# ---------------------------------------------------------------------------

install:
	@$(CLAWDKIT) --instance $(INSTANCE) install

uninstall:
	@$(CLAWDKIT) --instance $(INSTANCE) uninstall
