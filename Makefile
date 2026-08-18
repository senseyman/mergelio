# ============================================================
# Mergelio — Flutter Desktop (Windows / macOS / Linux)
# Usage: make help
# ============================================================

FLUTTER ?= flutter
DART    ?= dart

# Current host OS (build targets are host-bound for Flutter desktop)
UNAME_S := $(shell uname -s 2>/dev/null || echo Windows)

.DEFAULT_GOAL := help

# ------------------------------------------------------------
# Meta
# ------------------------------------------------------------
.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.PHONY: doctor
doctor: ## Flutter environment diagnostics
	$(FLUTTER) doctor -v

# ------------------------------------------------------------
# Dependencies & codegen
# ------------------------------------------------------------
.PHONY: deps
deps: ## Fetch pub dependencies
	$(FLUTTER) pub get

.PHONY: upgrade
upgrade: ## Upgrade pub dependencies
	$(FLUTTER) pub upgrade

.PHONY: gen
gen: ## Run code generation (freezed / json / drift)
	$(DART) run build_runner build --delete-conflicting-outputs

.PHONY: gen-watch
gen-watch: ## Code generation in watch mode
	$(DART) run build_runner watch --delete-conflicting-outputs

# ------------------------------------------------------------
# Quality: format / lint / analyze
# ------------------------------------------------------------
.PHONY: format
format: ## Format Dart sources in place
	$(DART) format lib test

.PHONY: format-check
format-check: ## Verify formatting (CI: fails on diff)
	$(DART) format --output=none --set-exit-if-changed lib test

.PHONY: analyze
analyze: ## Static analysis (flutter analyze)
	$(FLUTTER) analyze

.PHONY: lint
lint: format-check analyze ## Full lint pass (format check + analyze)

.PHONY: fix
fix: ## Apply automated dart fixes, then format
	$(DART) fix --apply
	$(DART) format lib test

# ------------------------------------------------------------
# Tests
# ------------------------------------------------------------
.PHONY: test
test: ## Run unit & widget tests
	$(FLUTTER) test

.PHONY: coverage
coverage: ## Tests with coverage (lcov at coverage/lcov.info)
	$(FLUTTER) test --coverage
	@echo "coverage report: coverage/lcov.info"

# ------------------------------------------------------------
# Run (debug)
# ------------------------------------------------------------
.PHONY: run
run: ## Run debug build on the host desktop platform
ifeq ($(UNAME_S),Darwin)
	$(FLUTTER) run -d macos
else ifeq ($(UNAME_S),Linux)
	$(FLUTTER) run -d linux
else
	$(FLUTTER) run -d windows
endif

# ------------------------------------------------------------
# Builds (host-bound: each desktop target builds on its own OS)
# ------------------------------------------------------------
.PHONY: build
build: ## Release build for the host platform
ifeq ($(UNAME_S),Darwin)
	$(MAKE) build-macos
else ifeq ($(UNAME_S),Linux)
	$(MAKE) build-linux
else
	$(MAKE) build-windows
endif

.PHONY: build-macos
build-macos: ## Release build: macOS (.app + zip in dist/)
	./scripts/build-macos.sh

.PHONY: build-macos-debug
build-macos-debug: ## Debug build: macOS
ifeq ($(UNAME_S),Darwin)
	$(FLUTTER) build macos --debug
else
	@echo "error: macOS builds require a macOS host" && exit 1
endif

.PHONY: build-linux
build-linux: ## Release build: Linux (bundle + tar.gz in dist/)
	./scripts/build-linux.sh

.PHONY: build-windows
build-windows: ## Release build: Windows (exe + zip in dist/)
	powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build-windows.ps1

# ------------------------------------------------------------
# Aggregate pipelines
# ------------------------------------------------------------
.PHONY: check
check: lint test ## CI gate: lint + tests

.PHONY: ci
ci: deps gen check ## Full CI pipeline: deps -> codegen -> lint -> tests

.PHONY: all
all: ci build ## Everything: CI pipeline + host release build

# ------------------------------------------------------------
# Housekeeping
# ------------------------------------------------------------
.PHONY: clean
clean: ## Remove build artifacts
	$(FLUTTER) clean

.PHONY: distclean
distclean: clean ## clean + remove generated code & pub cache artifacts
	find lib -name '*.g.dart' -delete
	find lib -name '*.freezed.dart' -delete
	rm -rf .dart_tool coverage
