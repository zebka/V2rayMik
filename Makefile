IMAGE ?= v2raymik
TAG ?= test
PLATFORM ?= linux/arm64
SING_BOX_VERSION ?= 1.14.4
VERSION ?= $(shell cat VERSION)
DIST ?= dist

.PHONY: help image test lint check-version save clean

help:
	@echo "make image   - build for $(PLATFORM) (needs buildx + qemu for cross builds)"
	@echo "make test    - build native image and run tests/unit"
	@echo "make lint    - shellcheck + RouterOS lint"
	@echo "make check-version - VERSION and CHANGELOG agree"
	@echo "make save    - export $(DIST)/$(IMAGE)-$(SING_BOX_VERSION).tar for side-loading"
	@echo "make clean   - remove $(DIST)"

image:
	docker buildx build --platform $(PLATFORM) --build-arg SING_BOX_VERSION=$(SING_BOX_VERSION) \
		--build-arg VERSION=$(VERSION) -t $(IMAGE):$(TAG) docker/ --load

test:
	docker buildx build --build-arg SING_BOX_VERSION=$(SING_BOX_VERSION) --build-arg VERSION=$(VERSION) \
		-t $(IMAGE):test docker/ --load
	docker run --rm -v "$(CURDIR)/tests:/w/tests:ro" --entrypoint sh $(IMAGE):test /w/tests/run.sh

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck docker/entrypoint.sh docker/lib/*.sh tests/run.sh tests/lib/*.sh tests/unit/*.t.sh; \
	else echo "shellcheck not installed, skipped"; fi
	@if [ -f tests/lint-rsc.sh ]; then sh tests/lint-rsc.sh router; else echo "no RouterOS lint yet"; fi

# One number for the repository, the image and the changelog. CI enforces the
# same thing on every tag, so a container can never be a version the repository
# does not describe.
check-version:
	@v=$$(cat VERSION); \
	case "$$v" in [0-9]*.[0-9]*.[0-9]*) ;; *) echo "VERSION is not x.y.z: $$v" >&2; exit 1 ;; esac; \
	grep -q "^## $$v " CHANGELOG.md || { echo "CHANGELOG.md has no '## $$v' section" >&2; exit 1; }; \
	echo "version $$v ok"

save:
	mkdir -p $(DIST)
	docker buildx build --platform $(PLATFORM) --build-arg SING_BOX_VERSION=$(SING_BOX_VERSION) \
		--build-arg VERSION=$(VERSION) \
		-t $(IMAGE):$(TAG) --output type=docker,dest=$(DIST)/$(IMAGE)-$(SING_BOX_VERSION).tar docker/
	@ls -lh $(DIST)/$(IMAGE)-$(SING_BOX_VERSION).tar

clean:
	rm -rf $(DIST)
