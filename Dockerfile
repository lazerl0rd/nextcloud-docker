FROM php:7.3-fpm-alpine3.10


ENV NEXTCLOUD_UPDATE=1
ENV NEXTCLOUD_VERSION 17.0.1
VOLUME /var/www/nextcloud


# Install necessary and temporary (with a flag) packages
RUN apk add --no-cache \
		rsync \
		ffmpeg \
		imagemagick \
		samba-client \
		supervisor; \
	apk add --no-cache --virtual .build-deps \
		$PHPIZE_DEPS \
		autoconf \
		freetype-dev \
		icu-dev \
		libevent-dev \
		libjpeg-turbo-dev \
		libmcrypt-dev \
		libpng-dev \
		libmemcached-dev \
		libxml2-dev \
		libzip-dev \
		openldap-dev \
		pcre-dev \
		postgresql-dev \
		imagemagick-dev \
		libwebp-dev \
		gmp-dev \
		imap-dev \
		krb5-dev \
		libressl-dev \
		samba-dev \
		bzip2-dev; \
	apk add --no-cache --virtual .fetch-deps \
		bzip2 \
		gnupg

# Install necessary PHP modules
RUN docker-php-ext-configure gd --with-freetype-dir=/usr --with-png-dir=/usr --with-jpeg-dir=/usr --with-webp-dir=/usr; \
	docker-php-ext-configure ldap; \
	docker-php-ext-install -j "$(nproc)" \
		exif \
		gd \
		intl \
		ldap \
		opcache \
		pcntl \
		pdo_mysql \
		pdo_pgsql \
		zip \
		gmp \
		bz2 \
		imap; \
	pecl install smbclient; \
	pecl install APCu-5.1.18; \
	pecl install memcached-3.1.4; \
	pecl install redis-4.3.0; \
	pecl install imagick-3.4.4; \
	docker-php-ext-enable \
		smbclient \
		apcu \
		memcached \
		redis \
		imagick; \
	runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
		| tr ',' '\n' \
		| sort -u \
		| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
		)"; \
	apk add --virtual .nextcloud-phpext-rundeps $runDeps; \
	apk del .build-deps

# Install Nextcloud into VOLUME
RUN curl -fsSL -o nextcloud.tar.bz2 \
	"https://download.nextcloud.com/server/releases/nextcloud-${NEXTCLOUD_VERSION}.tar.bz2"; \
	curl -fsSL -o nextcloud.tar.bz2.asc \
	"https://download.nextcloud.com/server/releases/nextcloud-${NEXTCLOUD_VERSION}.tar.bz2.asc"; \
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys 28806A878AE423A28372792ED75899B9A724937A; \
	gpg --batch --verify nextcloud.tar.bz2.asc nextcloud.tar.bz2; \
	tar -xjf nextcloud.tar.bz2 -C /usr/src/; \
	gpgconf --kill all; \
	rm -r "$GNUPGHOME" nextcloud.tar.bz2.asc nextcloud.tar.bz2; \
	echo '*/5 * * * * php -f /var/www/nextcloud/cron.php' > /var/spool/cron/crontabs/www-data; \
	apk del .fetch-deps

# Configure PHP
RUN { \
		echo 'opcache.enable=1'; \
		echo 'opcache.huge_code_pages=1'; \
		echo 'opcache.interned_strings_buffer=16'; \
		echo 'opcache.max_accelerated_files=10000'; \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.revalidate_freq=1'; \
		echo 'opcache.save_comments=1'; } > /usr/local/etc/php/conf.d/opcache-recommended.ini; \
	echo 'apc.enable_cli=1' >> /usr/local/etc/php/conf.d/docker-php-ext-apcu.ini; \
	echo 'memory_limit=512M' > /usr/local/etc/php/conf.d/memory-limit.ini; \
	{ \
		echo 'pm.max_children = 60'; \
		echo 'pm.max_spare_servers = 8'; \
		echo 'pm.min_spare_servers = 3'; \
		echo 'pm.start_servers = 6'; } > /usr/local/etc/php-fpm.d/processes.ini

# Manage directories/files
RUN mkdir -p \
		/usr/src/nextcloud/custom_apps \
		/usr/src/nextcloud/data \
		/var/log/supervisord \
		/var/run/supervisord \
		/var/www/data; \
	rm -rf \
		/usr/src/nextcloud/update \
		/var/spool/cron/crontabs/root

# Copy predefined configurations
COPY *.sh supervisord.conf upgrade.exclude /
COPY config/* /usr/src/nextcloud/config/

# Configure ownership
RUN chmod +x /usr/src/nextcloud/occ; \
	chmod -R g=u /var/www; \
	chown -R www-data:root /var/www


ENTRYPOINT ["/entrypoint.sh"]

CMD ["/usr/bin/supervisord", "-c", "/supervisord.conf"]
