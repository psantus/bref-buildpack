#!/usr/bin/env bash
# =============================================================================
# Extension build recipes for ARM compilation
#
# Each function defines how to compile a PHP extension from source.
# Called by bin/build when crane/docker methods fail (i.e., ARM builds).
#
# Environment available:
#   PHP_BUILD_DIR=/tmp/php (PHP source with ext/ directory)
#   INSTALL_DIR=/opt
#   BUILD_DIR=/tmp/build
#   EXT_DIR=$(php-config --extension-dir)
#
# Each recipe must:
#   1. Install build dependencies (via: LD_LIBRARY_PATH= dnf -y install ...)
#   2. Compile the extension
#   3. Place the .so at /tmp/ext-output/<name>.so
#   4. Place the .ini at /tmp/ext-output/<name>.ini
#   5. Run copy-dependencies.php to /tmp/ext-output/<name>-libs/
# =============================================================================

EXT_OUTPUT="/tmp/ext-output"

# Ensure PHP_BUILD_DIR is set (may not be inherited in CNB context)
: "${PHP_BUILD_DIR:=/tmp/php}"
: "${INSTALL_DIR:=/opt}"
: "${BUILD_DIR:=/tmp/build}"

# --- Helper ---
ext_install_deps() {
    LD_LIBRARY_PATH= dnf -y install "$@" 2>&1 | tail -3
}

ext_compile_bundled() {
    local name="$1"
    shift
    local configure_flags="$@"

    cd "${PHP_BUILD_DIR}/ext/${name}" || { echo "ERROR: ${PHP_BUILD_DIR}/ext/${name} not found"; return 1; }
    phpize
    ./configure ${configure_flags}
    make -j "$(nproc)"
    make install

    local so_path
    so_path="$(php-config --extension-dir)/${name}.so"
    cp "${so_path}" "${EXT_OUTPUT}/${name}.so"
    strip --strip-debug "${EXT_OUTPUT}/${name}.so" 2>/dev/null || true
    echo "extension=${name}.so" > "${EXT_OUTPUT}/${name}.ini"
    php /bref/lib-copy/copy-dependencies.php "${EXT_OUTPUT}/${name}.so" "${EXT_OUTPUT}/${name}-libs/"
}

ext_compile_pecl() {
    local name="$1"
    local version="${2:-}"

    if [[ -n "${version}" ]]; then
        pecl install "${name}-${version}" </dev/null
    else
        pecl install "${name}" </dev/null
    fi

    local so_path
    so_path="$(php-config --extension-dir)/${name}.so"
    cp "${so_path}" "${EXT_OUTPUT}/${name}.so"
    strip --strip-debug "${EXT_OUTPUT}/${name}.so" 2>/dev/null || true
    echo "extension=${name}.so" > "${EXT_OUTPUT}/${name}.ini"
    php /bref/lib-copy/copy-dependencies.php "${EXT_OUTPUT}/${name}.so" "${EXT_OUTPUT}/${name}-libs/"
}

# =============================================================================
# RECIPES
# =============================================================================

recipe_gd() {
    ext_install_deps libwebp-devel libXpm-devel libpng-devel libjpeg-devel freetype-devel

    cd "${PHP_BUILD_DIR}/ext/gd"
    phpize
    ./configure \
        --disable-static \
        --enable-gd-jis-conv \
        --enable-shared \
        --with-freetype \
        --enable-gd \
        --with-jpeg \
        --with-png \
        --with-webp \
        --with-xpm \
        --with-zlib
    make -j "$(nproc)"
    make install

    cp "$(php-config --extension-dir)/gd.so" "${EXT_OUTPUT}/gd.so"
    strip --strip-debug "${EXT_OUTPUT}/gd.so" 2>/dev/null || true
    echo "extension=gd.so" > "${EXT_OUTPUT}/gd.ini"
    php /bref/lib-copy/copy-dependencies.php "${EXT_OUTPUT}/gd.so" "${EXT_OUTPUT}/gd-libs/"
}

recipe_redis() {
    ext_compile_pecl redis
}

recipe_imagick() {
    ext_install_deps libpng-devel libjpeg-devel lcms2-devel libwebp-devel libtiff-devel ImageMagick-devel

    local version="70087bab33eab913e99ac77d64d04d1a2fd0b7b0"
    local build_dir="${BUILD_DIR}/imagick"
    mkdir -p "${build_dir}"
    cd "${build_dir}"
    curl -Ls -o imagick.tar.gz "https://github.com/Imagick/imagick/archive/${version}.tar.gz"
    tar xzf imagick.tar.gz
    cd "imagick-${version}"
    phpize
    ./configure --with-imagick="${INSTALL_DIR}"
    make -j "$(nproc)"
    make install

    cp "$(php-config --extension-dir)/imagick.so" "${EXT_OUTPUT}/imagick.so"
    strip --strip-debug "${EXT_OUTPUT}/imagick.so" 2>/dev/null || true
    echo "extension=imagick.so" > "${EXT_OUTPUT}/imagick.ini"
    php /bref/lib-copy/copy-dependencies.php "${EXT_OUTPUT}/imagick.so" "${EXT_OUTPUT}/imagick-libs/"
}

recipe_amqp() {
    ext_install_deps cmake

    local build_dir="${BUILD_DIR}/amqp"
    mkdir -p "${build_dir}"

    # Compile rabbitmq-c
    cd "${build_dir}"
    curl -Ls -o rabbitmq-c.tar.gz https://github.com/alanxz/rabbitmq-c/archive/refs/tags/v0.13.0.tar.gz
    tar xzf rabbitmq-c.tar.gz
    cd rabbitmq-c-0.13.0
    cmake -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" .
    cmake --build . --target install

    # Compile php-amqp
    cd "${build_dir}"
    curl -Ls -o php-amqp.tar.gz https://github.com/php-amqp/php-amqp/archive/refs/tags/v2.1.2.tar.gz
    tar xzf php-amqp.tar.gz
    cd php-amqp-2.1.2
    phpize
    ./configure
    make -j "$(nproc)"
    make install

    cp "$(php-config --extension-dir)/amqp.so" "${EXT_OUTPUT}/amqp.so"
    strip --strip-debug "${EXT_OUTPUT}/amqp.so" 2>/dev/null || true
    echo "extension=amqp.so" > "${EXT_OUTPUT}/amqp.ini"
    php /bref/lib-copy/copy-dependencies.php "${EXT_OUTPUT}/amqp.so" "${EXT_OUTPUT}/amqp-libs/"
}

recipe_soap() {
    ext_install_deps libxml2-devel
    ext_compile_bundled soap --enable-soap
}

recipe_ftp() {
    ext_compile_bundled ftp --enable-ftp
}

recipe_gmp() {
    ext_install_deps gmp-devel
    ext_compile_bundled gmp
}

recipe_pgsql() {
    ext_install_deps libpq-devel
    ext_compile_bundled pgsql --with-pgsql="${INSTALL_DIR}"

    # Also build pdo_pgsql
    cd "${PHP_BUILD_DIR}/ext/pdo_pgsql"
    phpize
    ./configure --with-pdo-pgsql="${INSTALL_DIR}"
    make -j "$(nproc)"
    make install
    cp "$(php-config --extension-dir)/pdo_pgsql.so" "${EXT_OUTPUT}/pdo_pgsql.so"
    echo "extension=pdo_pgsql.so" > "${EXT_OUTPUT}/pdo_pgsql.ini"
    php /bref/lib-copy/copy-dependencies.php "${EXT_OUTPUT}/pdo_pgsql.so" "${EXT_OUTPUT}/pdo_pgsql-libs/"
}

recipe_uuid() {
    ext_install_deps libuuid-devel
    ext_compile_pecl uuid
}

recipe_yaml() {
    ext_install_deps libyaml-devel
    ext_compile_pecl yaml
}

recipe_mongodb() {
    ext_compile_pecl mongodb
}

recipe_calendar() {
    ext_compile_bundled calendar --enable-calendar
}

recipe_exif() {
    ext_compile_bundled exif --enable-exif
}
