BUILD_DIR ?= build
BUILD_TYPE ?= Release
PREFIX ?= $(HOME)/.local
GENERATOR ?= Ninja

CMAKE ?= cmake
CLANG_TIDY ?= clang-tidy
CLAZY ?= clazy-standalone
QMLLINT ?= qmllint

LINT_SOURCES := $(wildcard src/*.cpp tests/*.cpp)
LINT_CHECKS ?= -*,clang-analyzer-*,bugprone-*,performance-*,misc-*

# Container runs: the same image locally and in CI (container/Dockerfile).
# The checkout is bind-mounted at /src and commands run as the caller's uid,
# so build output stays owned by the caller. Each run gets a private 0700
# XDG_RUNTIME_DIR on tmpfs, which Qt and Sway require. DOCKER_BUILD_DIR keeps
# the container's CMake cache apart from a native build/.
DOCKER ?= docker
DOCKER_TARGET ?= build
DOCKER_IMAGE ?= omasnap-dev:$(DOCKER_TARGET)
DOCKER_BUILD_FLAGS ?=
DOCKER_BUILD_DIR ?= build-docker
DOCKER_RUN = $(DOCKER) run --rm --init --user "$$(id -u):$$(id -g)" \
	--tmpfs "/tmp/runtime:mode=0700,uid=$$(id -u),gid=$$(id -g)" \
	--env XDG_RUNTIME_DIR=/tmp/runtime \
	--volume "$(CURDIR):/src" --workdir /src

.PHONY: all configure build clean install check smoke lint qt-lint \
	docker-image docker-check docker-run docker-shell

all: build

configure:
	$(CMAKE) -S . -B $(BUILD_DIR) -G $(GENERATOR) \
		-DCMAKE_BUILD_TYPE=$(BUILD_TYPE) \
		-DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
		-DCMAKE_INSTALL_PREFIX=$(PREFIX)

build: configure
	$(CMAKE) --build $(BUILD_DIR) --parallel

smoke: build
	QT_QPA_PLATFORM=offscreen $(BUILD_DIR)/omasnap-smoke

lint: build
	@set -eu; \
	if command -v "$(CLANG_TIDY)" >/dev/null 2>&1; then \
		commands_dir=$$(mktemp -d); \
		trap 'rm -rf "$$commands_dir"' EXIT; \
		cp "$(BUILD_DIR)/compile_commands.json" \
			"$$commands_dir/compile_commands.json"; \
		sed -i 's/ -mno-direct-extern-access//g' \
			"$$commands_dir/compile_commands.json"; \
		printf '%s\n' $(LINT_SOURCES) | xargs -r -P "$$(nproc)" -n 1 \
			"$(CLANG_TIDY)" -p "$$commands_dir" \
			-checks="$(LINT_CHECKS)" -header-filter='.*'; \
	else \
		echo "make check: clang-tidy unavailable; skipping"; \
	fi

qt-lint: build
	@set -eu; \
	if command -v "$(CLAZY)" >/dev/null 2>&1; then \
		for source in $(LINT_SOURCES); do \
			"$(CLAZY)" -p "$(BUILD_DIR)" "$$source"; \
		done; \
	else \
		echo "make check: clazy unavailable; skipping Qt-specific clazy pass"; \
	fi; \
	if command -v "$(QMLLINT)" >/dev/null 2>&1 && test -d qml; then \
		"$(QMLLINT)" qml; \
	else \
		echo "make check: no QML sources or qmllint unavailable; skipping"; \
	fi

check: smoke lint qt-lint

clean:
	@if test -d "$(BUILD_DIR)"; then \
		$(CMAKE) --build "$(BUILD_DIR)" --target clean; \
	fi

install: build
	$(CMAKE) --install $(BUILD_DIR)

docker-image:
	$(DOCKER) build $(DOCKER_BUILD_FLAGS) --target $(DOCKER_TARGET) \
		--tag $(DOCKER_IMAGE) container

docker-check: docker-image
	$(DOCKER_RUN) $(DOCKER_IMAGE) make check BUILD_DIR=$(DOCKER_BUILD_DIR)

# Run one command in the image: make docker-run CMD='bash -n install-arch'
docker-run: docker-image
	$(DOCKER_RUN) $(DOCKER_IMAGE) $(CMD)

docker-shell: docker-image
	$(DOCKER_RUN) --interactive --tty $(DOCKER_IMAGE) bash
