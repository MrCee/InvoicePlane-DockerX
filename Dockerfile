FROM php:8.4-apache-bookworm

ARG IP_VERSION=1.7.1
ARG IP_SOURCE=https://github.com/InvoicePlane/InvoicePlane/releases/download

ENV DEBIAN_FRONTEND=noninteractive \
    APACHE_DOCUMENT_ROOT=/var/www/html \
    IP_VERSION=${IP_VERSION}

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
    libicu-dev \
    libzip-dev \
    libpng-dev \
    libjpeg62-turbo-dev \
    libfreetype6-dev \
    libonig-dev \
    libxml2-dev \
    libxslt1-dev \
    libcurl4-openssl-dev \
    zlib1g-dev \
    default-mysql-client \
  && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
  && docker-php-ext-install -j"$(nproc)" \
    bcmath \
    curl \
    exif \
    gd \
    gettext \
    intl \
    mysqli \
    opcache \
    pdo_mysql \
    xsl \
    zip

RUN a2enmod rewrite headers expires remoteip

RUN VERSION="$(printf "%s" "${IP_VERSION}" | grep -q "^v" && printf "%s" "${IP_VERSION}" || printf "v%s" "${IP_VERSION}")" \
  && echo "Downloading ${IP_SOURCE}/${VERSION}/${VERSION}.zip" \
  && rm -f /tmp/app.zip \
  && for i in 1 2 3; do \
       curl -fSL "${IP_SOURCE}/${VERSION}/${VERSION}.zip" -o /tmp/app.zip && break || \
       { echo "Download attempt ${i} failed, retrying..."; sleep 5; }; \
     done \
  && test -f /tmp/app.zip \
  && rm -rf /tmp/ip-src \
  && mkdir -p /tmp/ip-src \
  && unzip /tmp/app.zip -d /tmp/ip-src \
  && APP_SRC="" \
  && for f in $(find /tmp/ip-src -type f -name ipconfig.php.example); do \
       d="$(dirname "$f")"; \
       if [ -f "$d/index.php" ] && [ -d "$d/application" ] && [ -d "$d/assets" ]; then \
         APP_SRC="$d"; \
         break; \
       fi; \
     done \
  && test -n "${APP_SRC}" \
  && echo "Detected InvoicePlane app root: ${APP_SRC}" \
  && rm -rf /var/www/html/* \
  && cp -a "${APP_SRC}/." /var/www/html/ \
  && rm -rf /tmp/app.zip /tmp/ip-src

RUN if [ -f /var/www/html/htaccess ] && [ ! -f /var/www/html/.htaccess ]; then \
      mv /var/www/html/htaccess /var/www/html/.htaccess; \
    fi

COPY docker/finalize/finalize_install.php /var/www/html/finalize_install.php
COPY docker/finalize/finalize_status.php /var/www/html/finalize_status.php
COPY docker/finalize/custom-complete.php /var/www/html/custom-complete.php

COPY docker/templates/views /opt/invoiceplane-seeds/views

RUN mkdir -p \
    /var/www/html/uploads \
    /var/www/html/uploads/archive \
    /var/www/html/uploads/customer_files \
    /var/www/html/uploads/temp \
    /var/www/html/uploads/temp/mpdf \
    /var/www/html/application/logs \
    /var/www/html/application/config \
    /var/www/html_default \
    /opt/invoiceplane-seeds/views \
  && cp -a /var/www/html/. /var/www/html_default/ \
  && find /opt/invoiceplane-seeds -type d -exec chmod 755 {} \; \
  && find /opt/invoiceplane-seeds -type f -exec chmod 644 {} \; \
  && chown -R www-data:www-data /var/www/html /var/www/html_default

RUN sed -ri 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/000-default.conf \
  && sed -ri 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf

RUN printf '%s\n' \
  'ServerName localhost' \
  '' \
  '<Directory /var/www/html>' \
  '    Options FollowSymLinks' \
  '    AllowOverride All' \
  '    Require all granted' \
  '    DirectoryIndex index.php index.html' \
  '</Directory>' \
  > /etc/apache2/conf-available/invoiceplane.conf \
  && a2enconf invoiceplane

COPY docker/php/custom.ini /usr/local/etc/php/conf.d/zzz-invoiceplane.ini
COPY docker/entrypoint.sh /usr/local/bin/docker-entrypoint-ip.sh
RUN chmod +x /usr/local/bin/docker-entrypoint-ip.sh

COPY docker/compare_seeded_bind_mounts /usr/local/bin/compare_seeded_bind_mounts
RUN chmod +x /usr/local/bin/compare_seeded_bind_mounts

COPY docker/runtime/validate-runtime.sh /usr/local/bin/validate-runtime.sh
RUN chmod +x /usr/local/bin/validate-runtime.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint-ip.sh"]
CMD ["apache2-foreground"]

