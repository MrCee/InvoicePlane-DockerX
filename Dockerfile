# -------------------------------
# Stage 0: Base Setup
# -------------------------------
ARG PHP_VERSION=8.4
FROM php:${PHP_VERSION}-fpm-alpine AS base

# Declare additional build arguments.
ARG IP_VERSION
ARG IP_SOURCE
ARG IP_LANGUAGE
ARG PUID
ARG PGID
ARG PHPIZE_DEPS="autoconf dpkg-dev dpkg file g++ gcc libc-dev make pkgconf re2c"

# Set environment variables for subsequent commands.
ENV PHP_VERSION=${PHP_VERSION} \
    IP_VERSION=${IP_VERSION} \
    IP_SOURCE=${IP_SOURCE} \
    IP_LANGUAGE=${IP_LANGUAGE} \
    PUID=${PUID} \
    PGID=${PGID}

# Standard OCI metadata labels.
LABEL org.opencontainers.image.authors="MrCee" \
      org.opencontainers.image.url="https://github.com/MrCee/InvoicePlane-DockerX" \
      org.opencontainers.image.title="InvoicePlane-DockerX" \
      org.opencontainers.image.description="InvoicePlane DockerX offers a fully dockerized multi-platform up-to-date version of InvoicePlane, complete with persistent mount points, the latest PHP, MariaDB, and a simple one-click setup."

# Debug: Show the base stage PATH.
RUN echo "Base stage PATH: $PATH"

# Install runtime dependencies.
RUN apk add --no-cache \
      git \
      openssh-client \
      patch \
      nginx \
      curl \
      unzip \
      mariadb-client \
      libpng-dev \
      libjpeg-turbo-dev \
      freetype-dev \
      oniguruma-dev \
      libxml2-dev \
      icu-dev \
      shadow

# Install build dependencies.
RUN apk add --no-cache --virtual .BUILD-DEPS linux-headers ${PHPIZE_DEPS}

# Install Composer.
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer && \
    chmod +x /usr/local/bin/composer

# Debug: Verify Composer is installed.
RUN ls -la /usr/local/bin/composer

# ---------------------------------------------------------
# Configure and install PHP extensions
# ---------------------------------------------------------
# Install additional libraries for PHP extensions.
RUN apk add --no-cache freetype-dev libjpeg-turbo-dev libpng-dev

# --- Build GD Extension ---
# Configure GD extension with explicit paths.
RUN docker-php-ext-configure gd --with-freetype=/usr/include/freetype2 --with-jpeg=/usr/include
# Build GD using reduced parallelism (-j1) to mitigate compiler issues.
RUN docker-php-ext-install -j1 gd

# --- Build MBSTRING Extension separately ---
RUN docker-php-ext-install -j1 mbstring

# --- Build MySQLi Extension separately ---
RUN docker-php-ext-install -j1 mysqli

# --- Build Other Extensions in parallel ---
RUN docker-php-ext-install -j$(nproc) xml dom intl bcmath session && \
    docker-php-ext-enable gd bcmath

# Clean up build dependencies and caches; create necessary directories.
RUN apk del .BUILD-DEPS && \
    rm -rf /var/cache/apk/* && \
    mkdir -p /run/nginx

# ---------------------------------------------------------
# Copy configuration and patch files.
# ---------------------------------------------------------
COPY setup /tmp/setup
COPY patches /tmp/patches
RUN chmod -R 775 /tmp/setup /tmp/patches

# Configure PHP and Nginx using the setup files.
# This step copies configuration files and then ensures that GD is enabled in php.ini.
RUN PHP_VERSION_CLEAN=$(echo "$PHP_VERSION" | cut -d. -f1-2 | tr -d '.') && \
    mkdir -p /etc/php${PHP_VERSION_CLEAN} /etc/php${PHP_VERSION_CLEAN}-fpm.d && \
    cp /tmp/setup/php.ini /etc/php${PHP_VERSION_CLEAN}/php.ini && \
    cp /tmp/setup/php-fpm.conf /etc/php${PHP_VERSION_CLEAN}-fpm.d/www.conf && \
    cp /tmp/setup/nginx.conf /etc/nginx/http.d/default.conf && \
    mkdir -p /config && \
    cp /tmp/setup/start.sh /config/start.sh && \
    cp /tmp/setup/wait-for-db.sh /config/wait-for-db.sh && \
    grep -q "extension=gd.so" /etc/php${PHP_VERSION_CLEAN}/php.ini || \
    echo "extension=gd.so" >> /etc/php${PHP_VERSION_CLEAN}/php.ini

# Download InvoicePlane and ensure variables are set correctly.
RUN echo "IP_SOURCE=${IP_SOURCE}" && echo "IP_VERSION=${IP_VERSION}" && \
    curl -L -o /tmp/${IP_VERSION}.zip ${IP_SOURCE}/${IP_VERSION}/${IP_VERSION}.zip && \
    cd /tmp && unzip /tmp/${IP_VERSION}.zip && \
    mkdir -p /var/www/html_default && \
    cp -r /tmp/ip/* /var/www/html_default/ && \
    mkdir -p /var/www/html && \
    cp -r /tmp/ip/* /var/www/html/ && \
    rm /tmp/${IP_VERSION}.zip

# Apply all patch files found in /tmp/patches.
RUN for patch in /tmp/patches/*.patch; do \
      echo "Applying patch: $patch"; \
      patch -p1 -d /var/www/html < "$patch" || exit 1; \
    done

# -------------------------------
# Stage 1: Composer Dependencies
# -------------------------------
FROM base AS composer-builder

# Debug: Show PATH in composer-builder stage.
RUN echo "Composer-builder PATH: $PATH"

# Set working directory to where InvoicePlane is located.
WORKDIR /var/www/html

# Copy Composer files.
COPY composer.json composer.lock ./

# Ensure Composer is available and install dependencies,
# then regenerate the optimized autoloader.
RUN composer --version && \
    sed -i "s/\"php\": \"[^\"]*\"/\"php\": \"${PHP_VERSION}\"/" composer.json && \
    export COMPOSER_PROCESS_TIMEOUT=300 && \
    composer install --no-dev --optimize-autoloader && \
    composer dump-autoload -o

# -------------------------------
# Stage 2: Final Image
# -------------------------------
FROM base

# Set working directory to the InvoicePlane application folder.
WORKDIR /var/www/html

# Bring in vendor directory and updated Composer files.
COPY --from=composer-builder /var/www/html/vendor ./vendor
COPY --from=composer-builder /var/www/html/composer.json ./composer.json
COPY --from=composer-builder /var/www/html/composer.lock ./composer.lock

# Expose port 80.
EXPOSE 80

# Set the entrypoint to your start script.
ENTRYPOINT ["/config/start.sh"]

# Define a healthcheck.
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD curl -f http://127.0.0.1/index.php || exit 1

