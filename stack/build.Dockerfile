ARG BREF_IMAGE=bref/arm-build-php-84:3
FROM ${BREF_IMAGE}

# CNB requires specific labels and environment variables
LABEL io.buildpacks.stack.id="io.bref.lambda"
ENV CNB_USER_ID=1000
ENV CNB_GROUP_ID=1000
ENV CNB_STACK_ID="io.bref.lambda"

# Detect architecture for downloading correct binaries
RUN ARCH=$(uname -m) && \
    case "${ARCH}" in \
        aarch64) JQ_ARCH="arm64"; CRANE_ARCH="arm64" ;; \
        x86_64)  JQ_ARCH="amd64"; CRANE_ARCH="x86_64" ;; \
        *)       echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
    esac && \
    # Install jq (static binary - package managers segfault in this image)
    curl -sL "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-${JQ_ARCH}" -o /usr/local/bin/jq && \
    chmod +x /usr/local/bin/jq && \
    # Install crane (go-containerregistry) for extracting extension images without Docker
    CRANE_VERSION="v0.20.2" && \
    curl -sL "https://github.com/google/go-containerregistry/releases/download/${CRANE_VERSION}/go-containerregistry_Linux_${CRANE_ARCH}.tar.gz" | \
    tar -xzf - -C /usr/local/bin crane && \
    chmod +x /usr/local/bin/crane

# Install composer
COPY --from=composer:2.8 /usr/bin/composer /usr/local/bin/composer

# Create CNB user (uid 1000)
RUN echo 'cnb:x:1000:1000::/home/cnb:/bin/bash' >> /etc/passwd && \
    echo 'cnb:x:1000:' >> /etc/group && \
    mkdir -p /home/cnb && \
    chown 1000:1000 /home/cnb
