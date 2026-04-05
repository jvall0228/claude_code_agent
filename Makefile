# ClawdKit Makefile
# Usage: make <target> [INSTANCE=<agent_name>]
# Default instance name: clawdkit

INSTANCE ?= clawdkit

REPO_ROOT  := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
SCRIPTS    := $(REPO_ROOT)daemon/scripts
CLAWDKIT   := $(SCRIPTS)/clawdkit.sh

OS := $(shell uname -s)

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
# Scheduler install/uninstall (stubs — full impl in Unit 5)
# ---------------------------------------------------------------------------

install:
ifeq ($(OS),Darwin)
	@echo "clawdkit install: launchd support coming in Unit 5."
	@echo "  Instance: $(INSTANCE)"
	@echo "  Platform: Darwin (launchd)"
else
	@echo "clawdkit install: systemd support coming in Unit 5."
	@echo "  Instance: $(INSTANCE)"
	@echo "  Platform: Linux (systemd)"
endif

uninstall:
ifeq ($(OS),Darwin)
	@echo "clawdkit uninstall: launchd support coming in Unit 5."
	@echo "  Instance: $(INSTANCE)"
	@echo "  Platform: Darwin (launchd)"
else
	@echo "clawdkit uninstall: systemd support coming in Unit 5."
	@echo "  Instance: $(INSTANCE)"
	@echo "  Platform: Linux (systemd)"
endif
