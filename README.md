# Bref PHP Lambda Buildpack

A [Cloud Native Buildpack](https://buildpacks.io/) that builds PHP applications into AWS Lambda container images using [Bref v3](https://bref.sh/).

**Replace your multi-stage Dockerfile with a single command:**

```bash
make lambda TEST_APP_PATH=./my-php-app LAMBDA_IMAGE=my-lambda
```

## What It Does

This buildpack automates what you'd typically hand-craft in a Dockerfile:

1. **Detects** your PHP/Bref app (via `composer.json` + `bref/bref` dependency)
2. **Installs PHP extensions** from the [bref-extra](https://github.com/brefphp/extra-php-extensions) ecosystem
3. **Runs `composer install`** with production optimizations (cached)
4. **Configures OPcache/JIT** for Lambda cold start performance
5. **Warms Symfony cache** (if Symfony detected)
6. **Produces a Lambda-ready container image** based on `bref/arm-php-{version}:3`

## Quick Start

### 1. Install Prerequisites

```bash
brew install buildpacks/tap/pack
# Docker must be running
```

### 2. Build & Deploy

```bash
cd bref-buildpack/

# One-shot: build + flatten + push to ECR
make lambda \
  TEST_APP_PATH=~/my-symfony-app \
  LAMBDA_IMAGE=my-app \
  BP_BREF_RUNTIME=fpm \
  BP_BREF_EXTENSIONS=redis,gd \
  BP_OPCACHE_JIT=true

make push \
  LAMBDA_IMAGE=my-app \
  ECR_REPO=123456789.dkr.ecr.eu-west-1.amazonaws.com/my-app \
  AWS_PROFILE=myprofile \
  AWS_REGION=eu-west-1
```

### 3. Create/Update Lambda

```bash
# Create a new Lambda function
aws lambda create-function \
  --function-name my-app \
  --package-type Image \
  --code ImageUri=123456789.dkr.ecr.eu-west-1.amazonaws.com/my-app:latest \
  --role arn:aws:iam::123456789:role/my-lambda-role \
  --architectures arm64 \
  --memory-size 1024 \
  --timeout 28 \
  --environment "Variables={BREF_RUNTIME=fpm,APP_ENV=prod}"

# Or update an existing one
aws lambda update-function-code \
  --function-name my-app \
  --image-uri 123456789.dkr.ecr.eu-west-1.amazonaws.com/my-app:latest
```

## Configuration

All configuration is via build-time environment variables (prefix `BP_`):

| Variable | Default | Description |
|----------|---------|-------------|
| `BP_PHP_VERSION` | `84` | PHP version: `82`, `83`, `84` |
| `BP_BREF_RUNTIME` | `function` | Bref runtime: `function`, `fpm`, `console` |
| `BP_HANDLER` | `public/index.php` | Lambda handler entrypoint |
| `BP_BREF_EXTENSIONS` | *(empty)* | Comma-separated extensions (e.g., `redis,gd,imagick`) |
| `BP_COMPOSER_FLAGS` | `--no-dev --classmap-authoritative --no-scripts` | Composer install flags |
| `BP_OPCACHE_ENABLE` | `true` | Enable OPcache optimization |
| `BP_OPCACHE_JIT` | `false` | Enable JIT (PHP 8.1+) |
| `BP_SYMFONY_WARMUP` | `auto` | Symfony cache warmup: `auto`, `true`, `false` |
| `BP_VENDOR_SHRINK` | `true` | Run `shrink-vendor` composer script if available |
| `BP_BREF_ARCH` | `arm` | Architecture: `arm` (Graviton) or empty (x86_64) |

### Using project.toml (recommended for apps)

Create a `project.toml` in your app root instead of passing `--env` flags:

```toml
[_]
schema-version = "0.2"

[io.buildpacks.build.env]
  BP_PHP_VERSION = "84"
  BP_BREF_RUNTIME = "fpm"
  BP_BREF_EXTENSIONS = "redis,gd"
  BP_OPCACHE_JIT = "true"
  BP_HANDLER = "public/index.php"
```

See `samples/project.toml` for a complete example.

## Available Extensions

All 40+ extensions from [bref/extra-php-extensions](https://github.com/brefphp/extra-php-extensions) are supported:

`amqp`, `blackfire`, `calendar`, `cassandra`, `decimal`, `ds`, `excimer`, `gd`, `gnupg`, `gmp`, `grpc`, `h3`, `igbinary`, `imagick`, `imap`, `ldap`, `mailparse`, `maxminddb`, `memcache`, `memcached`, `mongodb`, `msgpack`, `newrelic`, `odbc-snowflake`, `openswoole`, `opentelemetry`, `oci8`, `pcov`, `pgsql`, `rdkafka`, `redis`, `redis-igbinary`, `relay`, `scoutapm`, `scrypt`, `snmp`, `spx`, `ssh2`, `swoole`, `sqlsrv`, `tidy`, `uuid`, `xdebug`, `xlswriter`, `xmlrpc`, `yaml`

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make stack` | Build CNB-compatible base images from Bref |
| `make builder` | Create the `pack` builder (includes stack) |
| `make build` | Build an app image using the buildpack |
| `make lambda` | Build + flatten for Lambda (single command) |
| `make push` | Tag and push to ECR |
| `make test` | Build + verify image content |
| `make clean` | Remove generated images |

## Architecture

```
bref-buildpack/
├── buildpack.toml              # Buildpack descriptor (API 0.10)
├── builder.toml                # Builder config (build + run images)
├── package.toml                # For distributing as OCI image
├── Makefile                    # Build/test/deploy workflow
├── bin/
│   ├── detect*                 # Detects composer.json + bref/bref
│   └── build*                  # Extensions, composer, opcache, symfony, /var/task
├── stack/
│   ├── build.Dockerfile        # CNB-labeled build image (bref/arm-build-php-84:3)
│   └── run.Dockerfile          # CNB-labeled run image (bref/arm-php-84:3)
├── extensions/
│   └── bref-php-version/       # Image extension for PHP version switching
│       ├── extension.toml
│       └── bin/
│           ├── detect*
│           └── generate*
├── samples/
│   └── project.toml            # Example config for app developers
└── README.md
```

### How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                        make lambda                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. pack build (using CNB lifecycle)                         │
│     Build Image: bref/arm-build-php-84:3                    │
│     ┌──────────┐   ┌─────────┐   ┌─────────┐              │
│     │extensions│ → │composer │ → │symfony  │               │
│     │  (cached)│   │ (cached)│   │ warmup  │               │
│     └──────────┘   └─────────┘   └─────────┘              │
│                                                              │
│  2. Flatten for Lambda                                       │
│     - Copy /workspace → /var/task                           │
│     - ENTRYPOINT = /lambda-entrypoint.sh                    │
│     - CMD = public/index.php                                │
│     - Build without OCI attestations                         │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Result: Lambda-native container image                       │
│  Run Image: bref/arm-php-84:3 (PHP 8.4, Lambda bootstrap)  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Build Layers (Cached Between Builds)

| Layer | Cached | Contents |
|-------|--------|----------|
| `extensions` | ✓ | PHP extension `.so` files + ini configs |
| `opcache` | ✓ | OPcache/JIT configuration |
| `vendor` | ✓ | Composer dependencies (invalidated on `composer.lock` change) |
| `symfony-cache` | ✗ | Compiled DI container + cached routes |
| `app` | ✗ | Application source code |
| `env` | ✗ | BREF_RUNTIME environment variable |

## Comparison: Dockerfile vs Buildpack

### Before (Dockerfile — 100+ lines)

```dockerfile
FROM bref/arm-build-php-84:3 AS ext-gd
RUN dnf -y install libwebp-devel libpng-devel ...
WORKDIR ${PHP_BUILD_DIR}/ext/gd
RUN phpize && ./configure ... && make && make install
# ... repeat for each extension ...

FROM composer:2.8 AS vendors
COPY composer.* ./
RUN composer install --no-dev --classmap-authoritative ...

FROM bref/arm-php-84:3 AS lambda
COPY --from=ext-gd /tmp/gd.so /opt/bref/extensions/
COPY --from=vendors /app/vendor/ /var/task/vendor
COPY . /var/task
RUN php bin/console cache:warmup ...
```

### After (Buildpack)

```toml
# project.toml
[io.buildpacks.build.env]
  BP_BREF_EXTENSIONS = "gd"
  BP_BREF_RUNTIME = "fpm"
```

```bash
make lambda TEST_APP_PATH=. LAMBDA_IMAGE=my-app
```

## Multiple Lambda Functions (Bref v3 Unified Image)

Bref v3 supports a single image with runtime selection via `BREF_RUNTIME`. Build once, deploy to multiple functions:

```bash
# Build once
make lambda TEST_APP_PATH=./my-app LAMBDA_IMAGE=my-app

# Deploy as FPM (API Gateway HTTP)
aws lambda create-function --function-name api \
  --image-uri <ecr>/my-app:latest \
  --environment "Variables={BREF_RUNTIME=fpm}"

# Deploy as Console (CLI commands)
aws lambda create-function --function-name console \
  --image-uri <ecr>/my-app:latest \
  --environment "Variables={BREF_RUNTIME=console}"

# Deploy as Worker (SQS consumer)
aws lambda create-function --function-name worker \
  --image-uri <ecr>/my-app:latest \
  --environment "Variables={BREF_RUNTIME=function}"
```

## Known Constraints

1. **Static assets need CloudFront/S3** — Lambda (via function URL or API Gateway) only serves dynamic PHP responses. CSS/JS/images must be uploaded to S3 and served via CloudFront, same as with a standard Bref Dockerfile deployment.

2. **Flatten step required** — The CNB lifecycle adds metadata layers and a launcher binary that Lambda doesn't support. The `make lambda` target handles this automatically by producing a clean image with the Bref entrypoint.

3. **Extensions via Docker-in-Docker** — Installing bref-extra extensions requires Docker access during build (to pull extension images). If running in a CI environment without Docker, pre-bake extensions into a custom build image instead.

4. **PHP version = builder rebuild** — Changing PHP version requires rebuilding the stack images (they're based on `bref/arm-build-php-XX:3` and `bref/arm-php-XX:3`). The image extension provides a mechanism for this but requires the target images to be pre-built.

## Requirements

- [Pack CLI](https://buildpacks.io/docs/for-platform-operators/how-to/integrate-ci/pack/) v0.32+
- Docker
- A PHP application with `bref/bref` in `composer.json`
- AWS CLI (for deployment)

## License

MIT
