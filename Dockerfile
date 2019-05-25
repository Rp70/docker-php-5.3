FROM debian:jessie
MAINTAINER https://github.com/helderco/

# persistent / runtime deps
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      librecode0 \
      libmysqlclient-dev \
      libsqlite3-0 \
      libxml2 \
    && apt-get clean \
    && rm -r /var/lib/apt/lists/*

# phpize deps
RUN apt-get update && apt-get install -y --no-install-recommends \
      autoconf \
      file \
      g++ \
      gcc \
      libc-dev \
      make \
      pkg-config \
      re2c \
    && apt-get clean \
    && rm -r /var/lib/apt/lists/*

ENV PHP_INI_DIR /usr/local/etc/php
RUN mkdir -p $PHP_INI_DIR/conf.d

ENV GPG_KEYS 0B96609E270F565C13292B24C13C70B87267B52D 0A95E9A026542D53835E3F3A7DEC4E69FC9C83D7 0E604491
RUN set -xe \
  && for key in $GPG_KEYS; do \
    gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
  done

# compile openssl, otherwise --with-openssl won't work
RUN OPENSSL_VERSION="1.0.2k" \
      && cd /tmp \
      && mkdir openssl \
      && curl -sL "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz" -o openssl.tar.gz \
      && curl -sL "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz.asc" -o openssl.tar.gz.asc \
      && gpg --verify openssl.tar.gz.asc \
      && tar -xzf openssl.tar.gz -C openssl --strip-components=1 \
      && cd /tmp/openssl \
      && ./config && make && make install \
      && rm -rf /tmp/*

ENV PHP_VERSION 5.3.29

# php 5.3 needs older autoconf
# --enable-mysqlnd is included below because it's harder to compile after the fact the extensions are (since it's a plugin for several extensions, not an extension in itself)
RUN buildDeps=" \
                autoconf2.13 \
                libcurl4-openssl-dev \
                libreadline6-dev \
                librecode-dev \
                libsqlite3-dev \
                libssl-dev \
                libxml2-dev \
                xz-utils \
                \
                ssmtp bsd-mailx \
                sudo \
                procps \
                git \
                libfreetype6-dev libjpeg62-turbo-dev libpng-dev libwebp-dev libxpm-dev libmcrypt-dev imagemagick libmagickwand-dev \
                libkrb5-dev libc-client2007e-dev krb5-multidev libpam0g-dev libssl-dev \
                libpspell-dev librecode-dev libtidy-dev libxslt1-dev libgmp-dev libmemcached-dev zip unzip zlib1g-dev \
      " \
      && set -x \
      && apt-get update && apt-get install -y $buildDeps --no-install-recommends && rm -rf /var/lib/apt/lists/* \
      && curl -SL "http://php.net/get/php-$PHP_VERSION.tar.xz/from/this/mirror" -o php.tar.xz \
      && curl -SL "http://php.net/get/php-$PHP_VERSION.tar.xz.asc/from/this/mirror" -o php.tar.xz.asc \
      && gpg --verify php.tar.xz.asc \
      && mkdir -p /usr/src/php \
      && tar -xof php.tar.xz -C /usr/src/php --strip-components=1 \
      && rm php.tar.xz* \
      && cd /usr/src/php \
      && ls -lah \
      \
      && cd ext \
      && curl -SL http://pecl.php.net/get/APC -o APC-current.tar.gz \
      && tar -xzf APC-current.tar.gz \
      && rm -rf APC-current.tar.gz \
      && mv APC* apc \
      \
      && curl -SL http://pecl.php.net/get/memcache -o memcache-current.tar.gz \
      && tar -xzf memcache-current.tar.gz \
      && rm -rf memcache-current.tar.gz \
      && mv memcache* memcache \
      \
      && curl -SL http://pecl.php.net/get/imagick -o imagick-current.tar.gz \
      && tar -xzf imagick-current.tar.gz \
      && rm -rf imagick-current.tar.gz \
      && mv imagick* imagick \
      \
      && cd .. \
      && rm -rf configure autom4te.cache \
      && chmod +x ./buildconf \
      && ./buildconf --force \
      && ./configure \
            --with-config-file-path="$PHP_INI_DIR" \
            --with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
            --enable-fpm \
            --with-fpm-user=www-data \
            --with-fpm-group=www-data \
            --disable-cgi \
            --enable-mysqlnd \
            --with-mysql \
            --with-curl \
            --with-openssl=/usr/local/ssl \
            --with-readline \
            --with-recode \
            --with-zlib \
            # Additional options
            \
            --enable-bcmath \
            --with-gd \
            --enable-mbstring \
            --enable-pcntl \
            --enable-soap \
            --enable-sockets \
            --enable-sqlite-utf8 \
            --with-jpeg-dir \
            --with-png-dir \
            --with-zlib-dir \
            --with-gettext \
            --with-mcrypt \
            --with-mysql \
            --with-mysqli \
            --with-pdo-mysql \
            --with-pdo-sqlite \
            --with-pear \
            --enable-memcache \
            --enable-apc \
            --disable-phar \
      && make -j"$(nproc)" \
      && make install \
      && { find /usr/local/bin /usr/local/sbin -type f -executable -exec strip --strip-all '{}' + || true; } \
      && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false -o APT::AutoRemove::SuggestsImportant=false $buildDeps \
      && make clean

COPY docker-php-* /usr/local/bin/

WORKDIR /var/www/html

RUN set -ex \
  && cd /usr/local/etc \
  && if [ -d php-fpm.d ]; then \
    # for some reason, upstream's php-fpm.conf.default has "include=NONE/etc/php-fpm.d/*.conf"
    sed 's!=NONE/!=!g' php-fpm.conf.default | tee php-fpm.conf > /dev/null; \
    cp php-fpm.d/www.conf.default php-fpm.d/www.conf; \
  else \
    # PHP 5.x don't use "include=" by default, so we'll create our own simple config that mimics PHP 7+ for consistency
    mkdir php-fpm.d; \
    cp php-fpm.conf.default php-fpm.d/www.conf; \
    { \
      echo '[global]'; \
      echo 'include=etc/php-fpm.d/*.conf'; \
    } | tee php-fpm.conf; \
  fi \
  && { \
    echo '[global]'; \
    echo 'error_log = /proc/self/fd/2'; \
    echo; \
    echo '[www]'; \
    echo '; if we send this to /proc/self/fd/1, it never appears'; \
    echo 'access.log = /proc/self/fd/2'; \
    echo; \
    echo '; Ensure worker stdout and stderr are sent to the main error log.'; \
    echo 'catch_workers_output = yes'; \
  } | tee php-fpm.d/docker.conf \
  && { \
    echo '[global]'; \
    echo 'daemonize = no'; \
    echo; \
    echo '[www]'; \
    echo 'listen = 9000'; \
  } | tee php-fpm.d/zz-docker.conf \
	# sendmail setup with SSMTP for mail().
	&& echo "FromLineOverride=YES" >> /etc/ssmtp/ssmtp.conf \
	&& echo 'sendmail_path = "/usr/sbin/ssmtp -t"' > /usr/local/etc/php/conf.d/mail.ini


# fix some weird corruption in this file
RUN sed -i -e "" /usr/local/etc/php-fpm.d/www.conf

EXPOSE 9000
CMD ["php-fpm"]
