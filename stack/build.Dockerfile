FROM bref/arm-build-php-84:3

# CNB requires specific labels and environment variables
LABEL io.buildpacks.stack.id="io.bref.lambda"
ENV CNB_USER_ID=1000
ENV CNB_GROUP_ID=1000
ENV CNB_STACK_ID="io.bref.lambda"

# Install jq (static binary - package managers segfault in this image)
RUN curl -sL https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-arm64 -o /usr/local/bin/jq && \
    chmod +x /usr/local/bin/jq

# Install composer
COPY --from=composer:2.8 /usr/bin/composer /usr/local/bin/composer

# Create CNB user (uid 1000)
RUN echo 'cnb:x:1000:1000::/home/cnb:/bin/bash' >> /etc/passwd && \
    echo 'cnb:x:1000:' >> /etc/group && \
    mkdir -p /home/cnb && \
    chown 1000:1000 /home/cnb
