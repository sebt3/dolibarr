#ARG PHP_TAG=8.2.0-fpm-alpine3.17
ARG PHP_TAG=7.4-fpm-alpine3.16
FROM docker.io/library/php:${PHP_TAG} as build
# hadolint ignore=DL3018,DL3019,SC2086
RUN apk --update --no-cache --no-progress add curl ca-certificates clamav-clamdscan freshclam imagemagick freetype icu-libs icu-data-full libgomp libzip oniguruma krb5-server-ldap krb5-libs c-client libldap libpng libjpeg-turbo rsync ssmtp shadow mysql-client postgresql-client postgresql-libs pcre-dev \
 && apk --update --no-cache --no-progress add --virtual build-deps ${PHPIZE_DEPS} imagemagick-dev libzip-dev oniguruma-dev krb5-dev openldap-dev autoconf curl-dev freetype-dev build-base  icu-dev libjpeg-turbo-dev libldap libmcrypt-dev libpng-dev libtool libxml2-dev postgresql-dev unzip \
 && docker-php-ext-configure gd --with-freetype --with-jpeg \
 && docker-php-ext-configure pgsql -with-pgsql \
 && pecl install -o -f imagick \
 && docker-php-ext-enable imagick \
 && pecl install -o -f redis \
 && docker-php-ext-enable redis \
 && docker-php-ext-install calendar gd ldap mbstring mysqli intl xml pgsql soap zip opcache \
 && sed -i '/www-data/s#:[^:]*$#:/bin/ash#' /etc/passwd \
 && apk --purge del build-deps \
 && rm -fr /tmp/* /usr/share/php

ARG PHP_TAG=7.4-fpm-alpine3.16
FROM docker.io/library/php:${PHP_TAG} as source
ARG OBLYON_VERSION=10.0
RUN mkdir -p /target/app /target/usr/local/etc/php/
COPY .tags /tmp/
# hadolint ignore=DL4006,SC3037
RUN mkdir -p /target/app && sed 's/,.*//' /tmp/.tags >/target/app/version \
 && curl -sL "https://github.com/aspangaro/oblyon/archive/${OBLYON_VERSION}.tar.gz" | tar xz -C /tmp \
 && curl -sL "https://github.com/Dolibarr/dolibarr/archive/$(cat /target/app/version).tar.gz" | tar xz -C /tmp \
 && mv "/tmp/dolibarr-$(cat /target/app/version)/htdocs" /target/app \
 && mv "/tmp/dolibarr-$(cat /target/app/version)/scripts" /target/app \
 && for i in custom theme;do mv "/tmp/oblyon-${OBLYON_VERSION}/htdocs/$i/oblyon" "/target/app/htdocs/$i/";done \
 && chown -R www-data:root /target/app \
 && chmod -R g=u /target/app \
 && sed -i '/.*\..*\..*/! s#$#.0#' /target/app/version \
 && mkdir /target/docker-entrypoint.d \
 && /bin/echo -e "date.timezone = 'UTC'\nmemory_limit = 256M\nfile_uploads = On\nupload_max_filesize = 20M\npost_max_size = 20M\nmax_execution_time = 300\nsendmail_path = /usr/sbin/sendmail -t -i\nextension = calendar.so\n">/target/usr/local/etc/php/php.ini
COPY entrypoint.sh /target/
RUN chmod 755 /target/entrypoint.sh

FROM build
COPY --from=source /target /
ENV DOLI_DB_TYPE=mysqli	\
    DOLI_DB_HOST=''	\
    DOLI_DB_PORT=3306 \
    DOLI_DB_USER=dolibarr \
    DOLI_DB_PASSWORD=''	\
    DOLI_DB_NAME=dolibarr \
    DOLI_DB_PREFIX=llx_	 \
    DOLI_DB_CHARACTER_SET=utf8 \
    DOLI_DB_COLLATION=utf8_unicode_ci \
    DOLI_ADMIN_LOGIN=admin \
    DOLI_ADMIN_PASSWORD='' \
    DOLI_MODULES='modSociete' \
    DOLI_AUTH=dolibarr \
    DOLI_LDAP_HOST= \
    DOLI_LDAP_PORT=389 \
    DOLI_LDAP_VERSION=3 \
    DOLI_LDAP_SERVERTYPE=openldap \
    DOLI_LDAP_LOGIN_ATTRIBUTE=uid \
    DOLI_LDAP_DN='' \
    DOLI_LDAP_FILTER='' \
    DOLI_LDAP_ADMIN_LOGIN='' \
    DOLI_LDAP_ADMIN_PASS='' \
    DOLI_LDAP_DEBUG=false \
    DOLI_PROD=1 \
    DOLI_NO_CSRF_CHECK=0 \
    DOLI_REDIS_HOST=''

WORKDIR /var/documents
VOLUME /var/www /var/documents /app/conf
USER www-data
ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
