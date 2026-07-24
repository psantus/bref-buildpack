.PHONY: stack builder test lambda push clean

# --- Configuration ---
BUILDER_NAME     ?= bref-builder
BUILD_IMAGE      ?= bref-buildpack/build
RUN_IMAGE        ?= bref-buildpack/run
TEST_APP_PATH    ?= $(error Set TEST_APP_PATH to your PHP app directory)
LAMBDA_IMAGE     ?= my-lambda
ECR_REPO         ?= $(error Set ECR_REPO e.g. 123456789.dkr.ecr.eu-west-1.amazonaws.com/my-repo)
ECR_TAG          ?= latest
AWS_PROFILE      ?= default
AWS_REGION       ?= eu-west-1

# --- Build the CNB-compatible stack images (build + run) ---
stack:
	@echo "=== Building stack images ==="
	docker build -f stack/build.Dockerfile -t $(BUILD_IMAGE) .
	docker build -f stack/run.Dockerfile -t $(RUN_IMAGE) .

# --- Create the builder from our buildpack ---
builder: stack
	@echo "=== Packaging buildpack ==="
	pack buildpack package bref-php-lambda --config package.toml --format image --pull-policy if-not-present
	@echo "=== Creating builder ==="
	pack builder create $(BUILDER_NAME) \
		--config builder.toml \
		--pull-policy if-not-present \
		--force

# --- Build an app image using the buildpack ---
build: builder
	@echo "=== Building app: $(TEST_APP_PATH) ==="
	pack build $(LAMBDA_IMAGE) \
		--builder $(BUILDER_NAME) \
		--path $(TEST_APP_PATH) \
		--pull-policy if-not-present \
		--trust-builder \
		$(if $(BP_PHP_VERSION),--env BP_PHP_VERSION=$(BP_PHP_VERSION)) \
		$(if $(BP_BREF_RUNTIME),--env BP_BREF_RUNTIME=$(BP_BREF_RUNTIME)) \
		$(if $(BP_BREF_EXTENSIONS),--env BP_BREF_EXTENSIONS=$(BP_BREF_EXTENSIONS)) \
		$(if $(BP_OPCACHE_JIT),--env BP_OPCACHE_JIT=$(BP_OPCACHE_JIT)) \
		$(if $(BP_HANDLER),--env BP_HANDLER=$(BP_HANDLER))

# --- Build + flatten for Lambda deployment (single command) ---
# This produces a Lambda-native image without CNB lifecycle overhead
lambda: build
	@echo "=== Flattening image for Lambda ==="
	@echo 'FROM $(LAMBDA_IMAGE)' > /tmp/Dockerfile.lambda-flatten
	@echo 'USER root' >> /tmp/Dockerfile.lambda-flatten
	@echo 'RUN rm -rf /var/task && cp -a /workspace /var/task' >> /tmp/Dockerfile.lambda-flatten
	@echo '# Copy extensions from CNB layer to /opt where Bref expects them (merge, not overwrite)' >> /tmp/Dockerfile.lambda-flatten
	@echo 'RUN if [ -d /layers/bref_php-lambda/extensions/opt ]; then cp -an /layers/bref_php-lambda/extensions/opt/* /opt/ 2>/dev/null; cp -a /layers/bref_php-lambda/extensions/opt/bref/extensions/*.so /opt/bref/extensions/ 2>/dev/null; cp -a /layers/bref_php-lambda/extensions/opt/bref/etc/php/conf.d/*.ini /opt/bref/etc/php/conf.d/ 2>/dev/null; for f in /layers/bref_php-lambda/extensions/opt/lib/*; do [ -f "$$f" ] && cp -n "$$f" /opt/lib/ 2>/dev/null; done; fi' >> /tmp/Dockerfile.lambda-flatten
	@echo '# Copy opcache config from CNB layer' >> /tmp/Dockerfile.lambda-flatten
	@echo 'RUN if [ -d /layers/bref_php-lambda/opcache/opt ]; then cp -a /layers/bref_php-lambda/opcache/opt/bref/etc/php/conf.d/*.ini /opt/bref/etc/php/conf.d/ 2>/dev/null || true; fi' >> /tmp/Dockerfile.lambda-flatten
	@echo 'ENTRYPOINT ["/lambda-entrypoint.sh"]' >> /tmp/Dockerfile.lambda-flatten
	@echo 'CMD ["$(or $(BP_HANDLER),public/index.php)"]' >> /tmp/Dockerfile.lambda-flatten
	@echo 'WORKDIR /var/task' >> /tmp/Dockerfile.lambda-flatten
	DOCKER_BUILDKIT=0 docker build -f /tmp/Dockerfile.lambda-flatten -t $(LAMBDA_IMAGE)-lambda .
	@rm -f /tmp/Dockerfile.lambda-flatten
	@echo ""
	@echo "=== Lambda image ready: $(LAMBDA_IMAGE)-lambda ==="
	@echo "    ENTRYPOINT: /lambda-entrypoint.sh"
	@echo "    CMD:        $(or $(BP_HANDLER),public/index.php)"
	@echo "    WORKDIR:    /var/task"
	@echo ""
	@echo "Deploy with:"
	@echo "  make push ECR_REPO=<account>.dkr.ecr.<region>.amazonaws.com/<repo>"

# --- Push to ECR ---
push:
	@echo "=== Pushing to ECR: $(ECR_REPO):$(ECR_TAG) ==="
	aws ecr get-login-password --region $(AWS_REGION) --profile $(AWS_PROFILE) | \
		docker login --username AWS --password-stdin $(shell echo $(ECR_REPO) | cut -d'/' -f1)
	docker tag $(LAMBDA_IMAGE)-lambda $(ECR_REPO):$(ECR_TAG)
	docker push $(ECR_REPO):$(ECR_TAG)
	@echo ""
	@echo "=== Pushed! Update your Lambda function: ==="
	@echo "  aws lambda update-function-code \\"
	@echo "    --function-name <function-name> \\"
	@echo "    --image-uri $(ECR_REPO):$(ECR_TAG) \\"
	@echo "    --region $(AWS_REGION) --profile $(AWS_PROFILE)"

# --- Test: build + verify image content ---
test: lambda
	@echo "=== Verifying Lambda image ==="
	@docker run --rm --entrypoint bash $(LAMBDA_IMAGE)-lambda -c " \
		echo 'Handler:' && test -f /var/task/$(or $(BP_HANDLER),public/index.php) && echo '  /var/task/$(or $(BP_HANDLER),public/index.php) OK' || echo '  MISSING!'; \
		echo 'Vendor:' && test -f /var/task/vendor/autoload.php && echo '  /var/task/vendor/autoload.php OK' || echo '  MISSING!'; \
		echo 'Entrypoint:' && test -f /lambda-entrypoint.sh && echo '  /lambda-entrypoint.sh OK' || echo '  MISSING!'; \
		echo 'Bootstrap:' && test -f /opt/bref/bootstrap.php && echo '  /opt/bref/bootstrap.php OK' || echo '  MISSING!'; \
		echo 'PHP:' && php --version | head -1; \
		echo 'OPcache config:' && cat /opt/bref/etc/php/conf.d/opcache-buildpack.ini 2>/dev/null | head -3 || echo '  not found'; \
	"

# --- Clean up ---
clean:
	docker rmi $(LAMBDA_IMAGE) $(LAMBDA_IMAGE)-lambda 2>/dev/null || true
	docker rmi $(BUILD_IMAGE) $(RUN_IMAGE) 2>/dev/null || true
	docker rmi bref-php-lambda 2>/dev/null || true
