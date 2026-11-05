IMAGE ?= mikrotik-xray-gateway
TAG ?= test
PLATFORM ?= linux/arm64
XRAY_VERSION ?= 26.10.31
DIST ?= dist

.PHONY: help image test lint save clean

help:
	@echo "make image   - build for $(PLATFORM) (needs buildx + qemu for cross builds)"
	@echo "make test    - build native image and run tests/unit"
	@echo "make lint    - shellcheck + RouterOS lint"
	@echo "make save    - export $(DIST)/$(IMAGE)-$(XRAY_VERSION).tar for side-loading"
	@echo "make clean   - remove $(DIST)"

image:
	docker buildx build --platform $(PLATFORM) --build-arg XRAY_VERSION=$(XRAY_VERSION) \
		-t $(IMAGE):$(TAG) docker/ --load

test:
	docker buildx build --build-arg XRAY_VERSION=$(XRAY_VERSION) -t $(IMAGE):test docker/ --load
	docker run --rm -v "$(CURDIR)/tests:/w/tests:ro" --entrypoint sh $(IMAGE):test /w/tests/run.sh

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck docker/entrypoint.sh docker/lib/*.sh tests/run.sh tests/lib/*.sh tests/unit/*.t.sh; \
	else echo "shellcheck not installed, skipped"; fi
	@if [ -f tests/lint-rsc.sh ]; then sh tests/lint-rsc.sh router; else echo "no RouterOS lint yet"; fi

save: image
	mkdir -p $(DIST)
	docker save $(IMAGE):$(TAG) -o $(DIST)/$(IMAGE)-$(XRAY_VERSION).tar
	@ls -lh $(DIST)/$(IMAGE)-$(XRAY_VERSION).tar

clean:
	rm -rf $(DIST)
