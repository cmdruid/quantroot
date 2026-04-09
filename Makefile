# Quantroot Makefile
# Canonical command interface for the monorepo.

SHELL := /bin/bash

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

COMPOSE       := docker compose
COMPOSE_FILE  := compose.yml
PROJECT       := quantroot

CORE_SERVICES := bitcoin
# OPT_SERVICES :=

ifeq ($(ALL),1)
  SERVICES := $(CORE_SERVICES) $(OPT_SERVICES)
else
  SERVICES := $(CORE_SERVICES)
endif

ifeq ($(BG),1)
  UP_FLAGS := -d
else
  UP_FLAGS :=
endif

# ---------------------------------------------------------------------------
# Help (default target)
# ---------------------------------------------------------------------------

.DEFAULT_GOAL := help

.PHONY: help
help: ## Print available commands
	@grep -E '^[a-zA-Z_%-]+:.*##' $(MAKEFILE_LIST) \
		| awk -F ':.*## ' '{printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

.PHONY: init
init: ## Initialize submodules and build containers
	git submodule sync --recursive
	git submodule update --init --recursive
	$(COMPOSE) build

.PHONY: start
start: ## Start core services (BG=1 for background, ALL=1 for optional)
	$(COMPOSE) up $(UP_FLAGS) $(SERVICES)

.PHONY: dev
dev: ## Start in development mode with overrides
	$(COMPOSE) -f $(COMPOSE_FILE) -f compose.override.yml up $(UP_FLAGS) $(SERVICES)

.PHONY: stop
stop: ## Stop all services
	$(COMPOSE) down

.PHONY: restart
restart: ## Restart all services
	$(COMPOSE) down
	$(COMPOSE) up $(UP_FLAGS) $(SERVICES)

.PHONY: reset
reset: ## Stop services and remove all runtime data
	$(COMPOSE) down -v --remove-orphans
	./scripts/reset.sh

.PHONY: update
update: ## Refresh service dependencies
	./dev/scripts/update.sh

.PHONY: build
build: ## Rebuild container images
	$(COMPOSE) build --no-cache

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

.PHONY: logs
logs: ## Follow logs for all services
	$(COMPOSE) logs -f

.PHONY: logs-%
logs-%: ## Follow logs for a specific service (e.g., make logs-bitcoin)
	$(COMPOSE) logs -f $*

.PHONY: shell
shell: ## Open an interactive client shell
	./scripts/client.sh

.PHONY: health
health: ## Check service health
	@$(COMPOSE) ps --format "table {{.Name}}\t{{.Status}}"

.PHONY: check
check: ## Run static checks and doc consistency
	./scripts/check-docs.sh
	./scripts/check-setup.sh

# ---------------------------------------------------------------------------
# Testing
# ---------------------------------------------------------------------------

.PHONY: test-smoke
test-smoke: ## Run fast smoke tests
	./test/scripts/test-smoke.sh

.PHONY: test-e2e
test-e2e: ## Run full E2E test suite
	./test/scripts/test-e2e.sh

.PHONY: test-demo
test-demo: ## Run demo environment E2E test (requires: make build-bitcoin && make start BG=1)
	./test/scripts/test-demo.sh

.PHONY: test-check
test-check: ## Verify test workspace integrity
	./test/scripts/check-e2e-workspace.sh

# ---------------------------------------------------------------------------
# Bitcoin build & GUI
# ---------------------------------------------------------------------------

.PHONY: build-bitcoin
build-bitcoin: ## Build Bitcoin Core binaries (including bitcoin-qt) to build/bitcoin/bin/
	docker build \
		--target=export \
		--output=type=local,dest=build/bitcoin \
		-f build/bitcoin/Dockerfile .

.PHONY: qt-regtest
qt-regtest: ## Launch bitcoin-qt (regtest, peers with container node)
	./build/bitcoin/bin/bitcoin-qt -regtest -addnode=127.0.0.1:18444

.PHONY: qt-mainnet
qt-mainnet: ## Launch bitcoin-qt (mainnet, public peers)
	./build/bitcoin/bin/bitcoin-qt

.PHONY: qt-testnet
qt-testnet: ## Launch bitcoin-qt (testnet, public peers)
	./build/bitcoin/bin/bitcoin-qt -testnet

.PHONY: qt-signet
qt-signet: ## Launch bitcoin-qt (signet, public peers)
	./build/bitcoin/bin/bitcoin-qt -signet

.PHONY: shell-bitcoin
shell-bitcoin: ## Open a shell in the bitcoind container
	docker exec -it quantroot-bitcoin /bin/bash

# ---------------------------------------------------------------------------
# Website
# ---------------------------------------------------------------------------

.PHONY: dev-website
dev-website: ## Start the website dev server
	cd services/website && npx astro dev

# ---------------------------------------------------------------------------
# Service-specific targets (pattern rules)
# ---------------------------------------------------------------------------

.PHONY: start-%
start-%: ## Start a specific service (e.g., make start-bitcoin)
	$(COMPOSE) up $(UP_FLAGS) $*

.PHONY: stop-%
stop-%: ## Stop a specific service
	$(COMPOSE) stop $*

.PHONY: restart-%
restart-%: ## Restart a specific service
	$(COMPOSE) restart $*
