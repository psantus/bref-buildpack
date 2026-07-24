# Bref PHP Lambda Buildpack

A [Cloud Native Buildpack](https://buildpacks.io/) that builds PHP applications into AWS Lambda container images using [Bref v3](https://bref.sh/).

**Replace your multi-stage Dockerfile with a single command:**

```bash
pack build my-lambda-image --builder bref-builder --path ./my-php-app
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

### 1. Install Pack CLI

```bash
brew install buildpacks/tap/pack
```

### 2. Create the Builder

```bash
cd bref-buildpack/
pack builder create bref-builder --config builder.toml
```

### 3. Build Your App

```bash
# Minimal — auto-detects everything
pack build my-lambda \
  --builder bref-builder \
  --path ~/my-symfony-app

# With configuration
pack build my-lambda \
  --builder bref-builder \
  --path ~/my-symfony-app \
  --env BP_PHP_VERSION=84 \
  --env BP_BREF_EXTENSIONS=redis,gd,imagick \
  --env BP_BREF_RUNTIME=fpm \
  --env BP_OPCACHE_JIT=true
```

### 4. Deploy to Lambda

```bash
# Push to ECR
aws ecr get-login-password | docker login --username AWS --password-stdin <account>.dkr.ecr.<region>.amazonaws.com
docker tag my-lambda:latest <account>.dkr.ecr.<region>.amazonaws.com/my-lambda:latest
docker push <account>.dkr.ecr.<region>.amazonaws.com/my-lambda:latest

# Update Lambda function
aws lambda update-function-code \
  --function-name my-function \
  --image-uri <account>.dkr.ecr.<region>.amazonaws.com/my-lambda:latest
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

### Using project.toml (recommended)

Instead of passing `--env` flags every time, create a `project.toml` in your app root:

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

All extensions from [bref/extra-php-extensions](https://github.com/brefphp/extra-php-extensions) are supported:

`amqp`, `blackfire`, `calendar`, `cassandra`, `decimal`, `ds`, `excimer`, `gd`, `gnupg`, `gmp`, `grpc`, `h3`, `igbinary`, `imagick`, `imap`, `ldap`, `mailparse`, `maxminddb`, `memcache`, `memcached`, `mongodb`, `msgpack`, `newrelic`, `odbc-snowflake`, `openswoole`, `opentelemetry`, `oci8`, `pcov`, `pgsql`, `rdkafka`, `redis`, `redis-igbinary`, `relay`, `scoutapm`, `scrypt`, `snmp`, `spx`, `ssh2`, `swoole`, `sqlsrv`, `tidy`, `uuid`, `xdebug`, `xlswriter`, `xmlrpc`, `yaml`

## Architecture

```
bref-buildpack/
├── buildpack.toml              # Buildpack descriptor
├── bin/
│   ├── detect                  # Detection logic (composer.json + bref/bref)
│   └── build                   # Build logic (extensions, composer, opcache, symfony)
├── builder.toml                # Builder definition (build + run images)
├── extensions/
│   └── bref-php-version/       # Image extension for PHP version switching
│       ├── extension.toml
│       └── bin/
│           ├── detect
│           └── generate        # Generates run.Dockerfile
├── samples/
│   └── project.toml            # Example app configuration
└── README.md
```

### How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                     pack build my-lambda                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Build Image: bref/arm-build-php-84:3                       │
│  (has phpize, gcc, make, composer — can compile extensions)  │
│                                                              │
│  ┌─────────┐   ┌──────────┐   ┌─────────┐   ┌───────────┐ │
│  │ detect  │ → │extensions│ → │composer │ → │ symfony   │  │
│  │         │   │  layer   │   │  layer  │   │ warmup    │  │
│  └─────────┘   └──────────┘   └─────────┘   └───────────┘  │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Run Image: bref/arm-php-84:3                               │
│  (Lambda bootstrap + PHP runtime — production minimal)       │
│                                                              │
│  Final image = run image + layers from build                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Layers (Cached)

| Layer | Cached | Launch | Contents |
|-------|--------|--------|----------|
| `extensions` | ✓ | ✓ | PHP extension `.so` files + config |
| `opcache` | ✓ | ✓ | OPcache/JIT ini configuration |
| `vendor` | ✓ | ✓ | Composer dependencies |
| `symfony-cache` | ✗ | ✓ | Compiled DI container + cached routes |
| `app` | ✗ | ✓ | Application source code |

## Comparison: Dockerfile vs Buildpack

### Before (Dockerfile — 100+ lines)

```dockerfile
FROM bref/arm-build-php-84:3 AS ext-gd
RUN dnf -y install libwebp-devel libpng-devel ...
WORKDIR ${PHP_BUILD_DIR}/ext/gd
RUN phpize && ./configure ... && make -j$(nproc) && make install
RUN cp ... /tmp/gd.so
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

### After (Buildpack — zero Dockerfile)

```toml
# project.toml
[io.buildpacks.build.env]
  BP_PHP_VERSION = "84"
  BP_BREF_EXTENSIONS = "gd"
  BP_BREF_RUNTIME = "fpm"
```

```bash
pack build my-lambda --builder bref-builder
```

## Multiple Lambda Functions

Bref v3 supports a single unified image with runtime selection via `BREF_RUNTIME` env var. Build once, deploy to multiple functions:

```bash
# Build once
pack build my-app-lambda --builder bref-builder --env BP_BREF_RUNTIME=function

# Deploy as FPM (API Gateway)
aws lambda update-function-configuration --function-name api \
  --environment "Variables={BREF_RUNTIME=fpm}"

# Deploy as Console
aws lambda update-function-configuration --function-name console \
  --environment "Variables={BREF_RUNTIME=console}"

# Deploy as Worker (SQS consumer)
aws lambda update-function-configuration --function-name worker \
  --environment "Variables={BREF_RUNTIME=function}"
```

## Requirements

- [Pack CLI](https://buildpacks.io/docs/for-platform-operators/how-to/integrate-ci/pack/) v0.32+
- Docker (for building)
- A PHP application with `bref/bref` in `composer.json`

## License

MIT
