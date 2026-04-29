# Makefile for Ghostty (Zig 0.16.0 Compatibility Fork)
# This provides convenient commands for building, testing, and deploying Ghostty

# Default target
.PHONY: default
default: build

# Variables
ZIG := zig
BUILD_DIR := zig-out
BIN_DIR := $(BUILD_DIR)/bin
LIB_DIR := $(BUILD_DIR)/lib
SHARE_DIR := $(BUILD_DIR)/share
EXE_NAME := ghostty
EXE_PATH := $(BIN_DIR)/$(EXE_NAME)

# Build options
BUILD_FLAGS := -Demit-macos-app=false
DEBUG_FLAGS := $(BUILD_FLAGS) -Doptimize=Debug
RELEASE_FLAGS := $(BUILD_FLAGS) -Doptimize=ReleaseFast
SAFE_FLAGS := $(BUILD_FLAGS) -Doptimize=ReleaseSafe

# Feature flags
MINIMAL_FLAGS := $(BUILD_FLAGS) -Dsentry=false -Di18n=false -Dsimd=false
PERFORMANCE_FLAGS := $(BUILD_FLAGS) -Doptimize=ReleaseFast -Dsimd=true

# macOS-specific flags to avoid SDK issues
MACOS_FLAGS := $(BUILD_FLAGS) -Dsentry=false -Di18n=false -Dsimd=false
SKIP_DEPS_FLAGS := $(BUILD_FLAGS) -Dsentry=false -Di18n=false -Dsimd=false -Drenderer=opengl -Dfont-backend=freetype

# Test flags
TEST_FLAGS := --test-filter
PERFORMANCE_TEST_FLAGS := -Doptimize=ReleaseFast

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
PURPLE := \033[0;35m
CYAN := \033[0;36m
NC := \033[0m # No Color

# Help target
.PHONY: help
help:
	@echo "$(CYAN)Ghostty (Zig 0.16.0 Fork) Makefile$(NC)"
	@echo ""
	@echo "$(YELLOW)Build Commands:$(NC)"
	@echo "  make build          - Build Ghostty with default settings"
	@echo "  make debug          - Build Ghostty with debug symbols"
	@echo "  make release        - Build Ghostty optimized for performance"
	@echo "  make safe           - Build Ghostty with safety optimizations"
	@echo "  make minimal        - Build Ghostty with minimal features"
	@echo "  make performance    - Build Ghostty with performance optimizations"
	@echo "  make macos-safe     - Build Ghostty without macOS SDK dependencies"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make rebuild        - Clean and rebuild"
	@echo ""
	@echo "$(YELLOW)Run Commands:$(NC)"
	@echo "  make run            - Build and run Ghostty"
	@echo "  make run-debug      - Build and run Ghostty with debug output"
	@echo "  make run-minimal    - Build and run minimal Ghostty"
	@echo ""
	@echo "$(YELLOW)Test Commands:$(NC)"
	@echo "  make test           - Run all tests"
	@echo "  make test-compat    - Run Zig 0.16.0 compatibility tests"
	@echo "  make test-terminal  - Run terminal compatibility tests"
	@echo "  make test-perf      - Run performance regression tests"
	@echo "  make test-all       - Run all test suites"
	@echo "  make test-verbose   - Run tests with verbose output"
	@echo ""
	@echo "$(YELLOW)Library Commands:$(NC)"
	@echo "  make lib-vt         - Build libghostty-vt library"
	@echo "  make lib-wasm       - Build WebAssembly library"
	@echo ""
	@echo "$(YELLOW)Deploy Commands:$(NC)"
	@echo "  make install        - Install Ghostty to system"
	@echo "  make install-local  - Install Ghostty to user directory"
	@echo "  make uninstall      - Uninstall Ghostty from system"
	@echo "  make dist           - Create distribution tarball"
	@echo "  make deploy          - Deploy to GitHub (requires setup)"
	@echo ""
	@echo "$(YELLOW)Development Commands:$(NC)"
	@echo "  make fmt             - Format all Zig code"
	@echo "  make lint            - Run linting checks"
	@echo "  make docs            - Generate documentation"
	@echo "  make bench           - Run benchmarks"
	@echo "  make fuzz            - Run fuzzing tests"
	@echo ""
	@echo "$(YELLOW)Utility Commands:$(NC)"
	@echo "  make version        - Show Ghostty version"
	@echo "  make info            - Show build information"
	@echo "  make check           - Check build environment"
	@echo "  make update          - Update dependencies"

# Build commands
.PHONY: build
build:
	@echo "$(GREEN)Building Ghostty (Zig 0.16.0 compatibility)...$(NC)"
	$(ZIG) build $(SKIP_DEPS_FLAGS)
	@echo "$(GREEN)Build complete!$(NC)"
	@echo "$(BLUE)Executable: $(EXE_PATH)$(NC)"

.PHONY: debug
debug:
	@echo "$(GREEN)Building Ghostty (debug)...$(NC)"
	$(ZIG) build $(DEBUG_FLAGS)
	@echo "$(GREEN)Debug build complete!$(NC)"

.PHONY: release
release:
	@echo "$(GREEN)Building Ghostty (release)...$(NC)"
	$(ZIG) build $(RELEASE_FLAGS)
	@echo "$(GREEN)Release build complete!$(NC)"
	@echo "$(BLUE)Executable: $(EXE_PATH)$(NC)"

.PHONY: safe
safe:
	@echo "$(GREEN)Building Ghostty (safe release)...$(NC)"
	$(ZIG) build $(SAFE_FLAGS)
	@echo "$(GREEN)Safe release build complete!$(NC)"

.PHONY: minimal
minimal:
	@echo "$(GREEN)Building Ghostty (minimal features)...$(NC)"
	$(ZIG) build $(SKIP_DEPS_FLAGS)
	@echo "$(GREEN)Minimal build complete!$(NC)"

.PHONY: performance
performance:
	@echo "$(GREEN)Building Ghostty (performance optimized)...$(NC)"
	$(ZIG) build $(PERFORMANCE_FLAGS)
	@echo "$(GREEN)Performance build complete!$(NC)"

.PHONY: macos-safe
macos-safe:
	@echo "$(GREEN)Building Ghostty (macOS SDK-safe)...$(NC)"
	$(ZIG) build $(SKIP_DEPS_FLAGS) -Dtarget=native
	@echo "$(GREEN)macOS-safe build complete!$(NC)"
	@echo "$(BLUE)Executable: $(EXE_PATH)$(NC)"

.PHONY: clean
clean:
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	rm -rf $(BUILD_DIR)
	rm -rf .zig-cache
	rm -rf zig-out
	@echo "$(GREEN)Clean complete!$(NC)"

.PHONY: rebuild
rebuild: clean build

# Run commands
.PHONY: run
run: build
	@echo "$(GREEN)Running Ghostty...$(NC)"
	$(EXE_PATH)

.PHONY: run-debug
run-debug: debug
	@echo "$(GREEN)Running Ghostty (debug mode)...$(NC)"
	$(EXE_PATH) --debug

.PHONY: run-minimal
run-minimal: minimal
	@echo "$(GREEN)Running Ghostty (minimal)...$(NC)"
	$(EXE_PATH)

# Test commands
.PHONY: test
test:
	@echo "$(GREEN)Running all tests...$(NC)"
	$(ZIG) build test

.PHONY: test-compat
test-compat:
	@echo "$(GREEN)Running Zig 0.16.0 compatibility tests...$(NC)"
	$(ZIG) build test $(TEST_FLAGS)=build_system_compatibility
	$(ZIG) build test $(TEST_FLAGS)=terminal_compatibility
	$(ZIG) build test $(TEST_FLAGS)=performance_regression

.PHONY: test-terminal
test-terminal:
	@echo "$(GREEN)Running terminal compatibility tests...$(NC)"
	$(ZIG) build test $(TEST_FLAGS)=terminal_compatibility

.PHONY: test-perf
test-perf:
	@echo "$(GREEN)Running performance regression tests...$(NC)"
	$(ZIG) build test $(PERFORMANCE_TEST_FLAGS) $(TEST_FILTER)=performance_regression

.PHONY: test-all
test-all:
	@echo "$(GREEN)Running all test suites...$(NC)"
	$(MAKE) test-compat
	$(MAKE) test-terminal
	$(MAKE) test-perf
	@echo "$(GREEN)All tests complete!$(NC)"

.PHONY: test-verbose
test-verbose:
	@echo "$(GREEN)Running tests with verbose output...$(NC)"
	$(ZIG) build test -freference-trace

# Library commands
.PHONY: lib-vt
lib-vt:
	@echo "$(GREEN)Building libghostty-vt...$(NC)"
	$(ZIG) build -Demit-lib-vt

.PHONY: lib-wasm
lib-wasm:
	@echo "$(GREEN)Building WebAssembly library...$(NC)"
	$(ZIG) build -Demit-lib-vt -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall

# Deploy commands
.PHONY: install
install: build
	@echo "$(GREEN)Installing Ghostty to system...$(NC)"
	sudo $(ZIG) build install $(BUILD_FLAGS) --prefix /usr/local
	@echo "$(GREEN)Installation complete!$(NC)"

.PHONY: install-local
install-local: build
	@echo "$(GREEN)Installing Ghostty to user directory...$(NC)"
	$(ZIG) build install $(BUILD_FLAGS) --prefix $(HOME)/.local
	@echo "$(GREEN)Local installation complete!$(NC)"

.PHONY: uninstall
uninstall:
	@echo "$(YELLOW)Uninstalling Ghostty from system...$(NC)"
	sudo rm -f /usr/local/bin/ghostty
	sudo rm -rf /usr/local/share/ghostty
	sudo rm -rf /usr/local/lib/libghostty*
	@echo "$(GREEN)Uninstall complete!$(NC)"

.PHONY: dist
dist:
	@echo "$(GREEN)Creating distribution tarball...$(NC)"
	$(ZIG) build dist
	@echo "$(GREEN)Distribution complete!$(NC)"
	@echo "$(BLUE)Check zig-out/dist/ for tarball$(NC)"

.PHONY: deploy
deploy: test-all dist
	@echo "$(GREEN)Deploying to GitHub...$(NC)"
	@if command -v gh >/dev/null 2>&1; then \
		gh release create v$$(($(ZIG) build --help 2>/dev/null | grep -o 'version [0-9.]*' | head -1 | cut -d' ' -f2 || echo "1.0.0")) \
			zig-out/dist/ghostty-*.tar.* \
			--title "Ghostty Zig 0.16.0 Fork v$$(git describe --tags --abbrev=0 2>/dev/null || echo "1.0.0")" \
			--notes "Zig 0.16.0 compatible Ghostty fork with comprehensive API updates and test coverage."; \
		echo "$(GREEN)Deploy complete!$(NC)"; \
	else \
		echo "$(RED)Error: gh CLI not found. Install GitHub CLI first.$(NC)"; \
		exit 1; \
	fi

# Development commands
.PHONY: fmt
fmt:
	@echo "$(GREEN)Formatting Zig code...$(NC)"
	$(ZIG) fmt .
	@echo "$(GREEN)Formatting complete!$(NC)"

.PHONY: lint
lint:
	@echo "$(GREEN)Running linting checks...$(NC)"
	@if command -v ziglint >/dev/null 2>&1; then \
		ziglint .; \
	else \
		echo "$(YELLOW)ziglint not found, skipping lint checks$(NC)"; \
	fi

.PHONY: docs
docs:
	@echo "$(GREEN)Generating documentation...$(NC)"
	$(ZIG) build -Demit-docs
	@echo "$(GREEN)Documentation generated!$(NC)"
	@echo "$(BLUE)Check zig-out/docs/ for generated docs$(NC)"

.PHONY: bench
bench:
	@echo "$(GREEN)Running benchmarks...$(NC)"
	$(ZIG) build -Demit-bench
	$(ZIG-out)/bin/ghostty-bench
	@echo "$(GREEN)Benchmarks complete!$(NC)"

.PHONY: fuzz
fuzz:
	@echo "$(GREEN)Running fuzzing tests...$(NC)"
	$(ZIG) build test-fuzz
	@echo "$(GREEN)Fuzzing complete!$(NC)"

# Utility commands
.PHONY: version
version:
	@echo "$(CYAN)Ghostty Zig 0.16.0 Fork$(NC)"
	@if [ -f build.zig.zon ]; then \
		echo "$(BLUE)Version: $$(grep -o '"version":"[^"]*"' build.zig.zon | cut -d'"' -f4)$(NC)"; \
	else \
		echo "$(YELLOW)Version information not available$(NC)"; \
	fi
	@echo "$(BLUE)Zig version: $$(zig version)$(NC)"

.PHONY: info
info:
	@echo "$(CYAN)Ghostty Build Information$(NC)"
	@echo "$(BLUE)Build directory: $(BUILD_DIR)$(NC)"
	@echo "$(BLUE)Executable path: $(EXE_PATH)$(NC)"
	@echo "$(BLUE)Library directory: $(LIB_DIR)$(NC)"
	@echo "$(BLUE)Share directory: $(SHARE_DIR)$(NC)"
	@echo "$(BLUE)Zig version: $$(zig version)$(NC)"
	@echo "$(BLUE)Target: $$(zig target)$(NC)"
	@echo "$(BLUE)Build flags: $(BUILD_FLAGS)$(NC)"

.PHONY: check
check:
	@echo "$(GREEN)Checking build environment...$(NC)"
	@echo "$(BLUE)Zig version: $$(zig version)$(NC)"
	@echo "$(BLUE)Target: $$(zig target)$(NC)"
	@if [ -d .git ]; then \
		echo "$(BLUE)Git branch: $$(git branch --show-current)$(NC)"; \
		echo "$(BLUE)Git commit: $$(git rev-parse --short HEAD)$(NC)"; \
	fi
	@if [ -f build.zig.zon ]; then \
		echo "$(BLUE)Minimum Zig version: $$(grep -o '"minimum_zig_version":"[^"]*"' build.zig.zon | cut -d'"' -f4)$(NC)"; \
	fi
	@echo "$(GREEN)Environment check complete!$(NC)"

.PHONY: update
update:
	@echo "$(GREEN)Updating dependencies...$(NC)"
	$(ZIG) fetch --save
	@echo "$(GREEN)Dependencies updated!$(NC)"

# Special targets for development workflow
.PHONY: dev
dev: test-compat run
	@echo "$(GREEN)Development workflow complete!$(NC)"

.PHONY: ci
ci: fmt test-all
	@echo "$(GREEN)CI workflow complete!$(NC)"

.PHONY: release-complete
release-complete: clean test-all dist deploy
	@echo "$(GREEN)Release workflow complete!$(NC)"

# Convenience targets
.PHONY: b r d t c i l
b: build
r: run
d: debug
t: test
c: clean
i: install
l: lint

# Check if required tools are available
.PHONY: check-tools
check-tools:
	@echo "$(GREEN)Checking required tools...$(NC)"
	@if ! command -v $(ZIG) >/dev/null 2>&1; then \
		echo "$(RED)Error: Zig not found. Please install Zig 0.16.0 or later.$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Zig found: $$(zig version)$(NC)"
	@if command -v git >/dev/null 2>&1; then \
		echo "$(GREEN)Git found: $$(git --version)$(NC)"; \
	else \
		echo "$(YELLOW)Warning: Git not found$(NC)"; \
	fi

# Include check-tools as a prerequisite for most targets
build debug release safe minimal performance: check-tools
run run-debug run-minimal: check-tools
test test-compat test-terminal test-perf test-all: check-tools
lib-vt lib-wasm: check-tools
install install-local: check-tools

# Default goal
.DEFAULT_GOAL := build