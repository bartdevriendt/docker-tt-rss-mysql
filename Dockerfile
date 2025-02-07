#Dockerfile.
FROM ubuntu:jammy

ARG DEBIAN_FRONTEND="noninteractive"

ENV SCRIPT_ROOT=/opt/tt-rss

VOLUME /var/www/html
VOLUME ${SCRIPT_ROOT}/config.d

RUN apt update && apt install software-properties-common -y
RUN add-apt-repository ppa:ondrej/php
RUN apt update
# Install software
RUN apt-get -qq update -y && apt-get -qq upgrade -y && apt-get -qq install git curl sudo -y
RUN apt-get -qq install nginx-core -y
RUN apt-get -qq install php8.2 php8.2-fpm php8.2-common php8.2-apcu \
    php8.2-gd php8.2-pgsql php8.2-pdo-mysql php8.2-xml php8.2-opcache \
    php8.2-mbstring php8.2-intl php8.2-xml php8.2-curl php8.2-tokenizer \
    php-json php8.2-zip -y
RUN apt-get -qq install mysql-client rsync tzdata -y
RUN apt-get -qq install supervisor -y
RUN rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*
RUN sed -i -e 's/;\(clear_env\) = .*/\1 = no/i' \
		-e 's/^\(user\|group\) = .*/\1 = app/i' \
		-e 's/;\(php_admin_value\[error_log\]\) = .*/\1 = \/tmp\/error.log/' \
		-e 's/;\(php_admin_flag\[log_errors\]\) = .*/\1 = on/' \
        /etc/php/8.2/fpm/pool.d/www.conf
RUN mkdir -p ${SCRIPT_ROOT}/config.d /etc/nginx/global /var/www/tt-rss

# Configure Image
COPY app/config.docker.php ${SCRIPT_ROOT}
COPY app/update-feeds.sh ${SCRIPT_ROOT}
RUN chmod 755 ${SCRIPT_ROOT}/update-feeds.sh

COPY config/README.md ${SCRIPT_ROOT}/config.d
COPY config/php.conf /etc/nginx/global
COPY config/restrictions.conf /etc/nginx/global
COPY config/nginx.conf /etc/nginx/sites-enabled/default
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# forward request and error logs to docker log collector
RUN ln -sf /dev/stdout /var/log/nginx/access.log \
	&& ln -sf /dev/stderr /var/log/nginx/error.log \
	&& ln -sf /dev/stderr /var/log/php8.2-fpm.log

# HTTP
EXPOSE 80/tcp

# these are applied on every startup, if set
ENV ADMIN_USER_PASS=""
# see classes/UserHelper.php ACCESS_LEVEL_*
# setting this to -2 would effectively disable built-in admin user
# unless single user mode is enabled
ENV ADMIN_USER_ACCESS_LEVEL=""

# these are applied unless user already exists
ENV AUTO_CREATE_USER=""
ENV AUTO_CREATE_USER_PASS=""
ENV AUTO_CREATE_USER_ACCESS_LEVEL="0"

# don't try to update local plugins on startup (except for nginx_xaccel)
ENV TTRSS_NO_STARTUP_PLUGIN_UPDATES=""

ENV TTRSS_DB_TYPE="mysql"
ENV TTRSS_DB_HOST="mysql"
ENV TTRSS_DB_PORT="3306"

ENV TTRSS_MYSQL_CHARSET="UTF8"
ENV TTRSS_PHP_EXECUTABLE="/usr/bin/php"
ENV TTRSS_PLUGINS="auth_internal, note, nginx_xaccel"

ENV TTRSS_FEED_UPDATE_CHECK=900

ENV OWNER_UID=1000
ENV OWNER_GID=1000

ENV PHP_WORKER_MAX_CHILDREN=5
ENV PHP_WORKER_MEMORY_LIMIT=256M

ENV SIMPLE_UPDATE_MODE=false
ENV SINGLE_USER_MODE=false

COPY app/startup.sh /startup.sh
RUN chmod 755 /startup.sh

CMD ["/startup.sh"]

LABEL maintainer="me@alandoyle.com"
