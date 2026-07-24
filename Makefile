.PHONY: stack builder test clean

BUILDER_NAME=bref-builder
BUILD_IMAGE=bref-buildpack/build
RUN_IMAGE=bref-buildpack/run

# Build the CNB-compatible stack images (build + run)
stack:
	docker build -f stack/build.Dockerfile -t $(BUILD_IMAGE) .
	docker build -f stack/run.Dockerfile -t $(RUN_IMAGE) .

# Create the builder from our buildpack
builder: stack
	pack builder create $(BUILDER_NAME) \
		--config builder.toml \
		--pull-policy if-not-present

# Test the buildpack against a sample PHP app
test: builder
	@echo "=== Testing buildpack against Bref demo app ==="
	pack build test-bref-lambda \
		--builder $(BUILDER_NAME) \
		--path $(TEST_APP_PATH) \
		--pull-policy if-not-present \
		--trust-builder \
		--env BP_PHP_VERSION=84 \
		--env BP_BREF_RUNTIME=fpm \
		--verbose
	@echo ""
	@echo "=== Build successful! Inspecting image... ==="
	docker inspect test-bref-lambda --format '{{.Config.Cmd}}'

# Clean up test artifacts
clean:
	docker rmi test-bref-lambda 2>/dev/null || true
	docker rmi $(BUILD_IMAGE) 2>/dev/null || true
	docker rmi $(RUN_IMAGE) 2>/dev/null || true
	pack builder remove $(BUILDER_NAME) 2>/dev/null || true
