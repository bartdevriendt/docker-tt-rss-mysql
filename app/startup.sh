#!/bin/sh -e
#
# Based in part on the original TT-RSS Docker startup.sh
#

while ! mysqladmin ping -h $TTRSS_DB_HOST -u $TTRSS_DB_USER -p$TTRSS_DB_PASS; do
	echo waiting until $TTRSS_DB_HOST is ready...
	sleep 3
done

DST_DIR=/var/www/tt-rss
SRC_REPO=https://git.tt-rss.org/fox/tt-rss.git

# Create the 'app' user
if ! id app >/dev/null 2>&1; then
	addgroup --gid $OWNER_GID app
	useradd -d /var/www/tt-rss -g app -u $OWNER_UID app
   usermod -aG www-data,app app
fi

if [ ! -d $DST_DIR/.git ]; then
	mkdir -p $DST_DIR
	chown $OWNER_UID:$OWNER_GID $DST_DIR

	echo cloning tt-rss source from $SRC_REPO to $DST_DIR...
	sudo -u app git clone --depth 1 $SRC_REPO $DST_DIR || echo error: failed to clone master repository.
else
	echo updating tt-rss source in $DST_DIR from $SRC_REPO...

	chown -R $OWNER_UID:$OWNER_GID $DST_DIR
	cd $DST_DIR && \
		sudo -u app git config core.filemode false && \
		sudo -u app git config pull.rebase false && \
		sudo -u app git pull origin master || echo error: unable to update master repository.
fi

update-ca-certificates || true

if [ ! -e $DST_DIR/index.php ]; then
	echo "error: tt-rss index.php missing (git clone failed?), unable to continue."
	exit 1
fi

if [ ! -d $DST_DIR/plugins.local/nginx_xaccel ]; then
	echo cloning plugins.local/nginx_xaccel...
	sudo -u app git clone https://git.tt-rss.org/fox/ttrss-nginx-xaccel.git \
		$DST_DIR/plugins.local/nginx_xaccel ||  echo warning: failed to clone nginx_xaccel.
else
	if [ -z "$TTRSS_NO_STARTUP_PLUGIN_UPDATES" ]; then
		echo updating all local plugins...

		find $DST_DIR/plugins.local/ -maxdepth 1 -mindepth 1 -type d | while read PLUGIN; do
			if [ -d $PLUGIN/.git ]; then
				echo updating $PLUGIN...

				cd $PLUGIN && \
					sudo -u app git config core.filemode false && \
					sudo -u app git config pull.rebase false && \
					sudo -u app git pull origin master || echo warning: attempt to update plugin $PLUGIN failed.
			fi
		done
	else
		echo updating plugins.local/nginx_xaccel...

		cd $DST_DIR/plugins.local/nginx_xaccel && \
			sudo -u app git config core.filemode false && \
			sudo -u app git config pull.rebase false && \
			sudo -u app git pull origin master || echo warning: attempt to update plugin nginx_xaccel failed.
	fi
fi

cp ${SCRIPT_ROOT}/config.docker.php $DST_DIR/config.php
chmod 644 $DST_DIR/config.php

for d in cache lock feed-icons; do
	chmod 777 $DST_DIR/$d
	find $DST_DIR/$d -type f -exec chmod 666 {} \;
done

# Configure PHP
echo "Setting PHP memory_limit to ${PHP_WORKER_MEMORY_LIMIT}"
sed -i.bak "s/^\(memory_limit\) = \(.*\)/\1 = ${PHP_WORKER_MEMORY_LIMIT}/" \
	/etc/php/8.2/fpm/php.ini

echo "Setting PHP pm.max_children to ${PHP_WORKER_MAX_CHILDREN}"
sed -i.bak "s/^\(pm.max_children\) = \(.*\)/\1 = ${PHP_WORKER_MAX_CHILDREN}/" \
	/etc/php/8.2/fpm/pool.d/www.conf


echo "Using php executable ${TTRSS_PHP_EXECUTABLE}"

# Update schema if necessary
sudo -Eu app ${TTRSS_PHP_EXECUTABLE} $DST_DIR/update.php --update-schema=force-yes

if [ ! -z "$ADMIN_USER_PASS" ]; then
	sudo -Eu app ${TTRSS_PHP_EXECUTABLE} $DST_DIR/update.php --user-set-password "admin:$ADMIN_USER_PASS"
else
	if sudo -Eu app ${TTRSS_PHP_EXECUTABLE} $DST_DIR/update.php --user-check-password "admin:password"; then
		RANDOM_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16 ; echo '')

		echo "*****************************************************************************"
		echo "* Setting initial built-in admin user password to '$RANDOM_PASS'        *"
		echo "* If you want to set it manually, use ADMIN_USER_PASS environment variable. *"
		echo "*****************************************************************************"

		sudo -Eu app ${TTRSS_PHP_EXECUTABLE} $DST_DIR/update.php --user-set-password "admin:$RANDOM_PASS"
	fi
fi

if [ ! -z "$ADMIN_USER_ACCESS_LEVEL" ]; then
	sudo -Eu app ${TTRSS_PHP_EXECUTABLE} $DST_DIR/update.php --user-set-access-level "admin:$ADMIN_USER_ACCESS_LEVEL"
fi

if [ ! -z "$AUTO_CREATE_USER" ]; then
	sudo -Eu app /bin/sh -c "php $DST_DIR/update.php --user-exists $AUTO_CREATE_USER ||
		${TTRSS_PHP_EXECUTABLE} $DST_DIR/update.php --force-yes --user-add \"$AUTO_CREATE_USER:$AUTO_CREATE_USER_PASS:$AUTO_CREATE_USER_ACCESS_LEVEL\""
fi

rm -f /tmp/error.log && mkfifo /tmp/error.log && chown app:app /tmp/error.log

(tail -q -f /tmp/error.log >> /proc/1/fd/2) &

unset ADMIN_USER_PASS
unset AUTO_CREATE_USER_PASS

# cleanup any old lockfiles
rm -vf -- /var/www/tt-rss/lock/*.lock

touch $DST_DIR/.app_is_ready

# Run it all :)
echo "Starting daemons for $TTRSS_SELF_URL_PATH"
/usr/bin/supervisord -n -c /etc/supervisor/conf.d/supervisord.conf
