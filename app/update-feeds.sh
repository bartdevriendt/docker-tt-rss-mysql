#!/bin/bash -e
#
# TT-RSS Feed Update script
#

TTRSS_FEED_UPDATE_CHECK=${TTRSS_FEED_UPDATE_CHECK:-900}
sudo -Eu app ${TTRSS_PHP_EXECUTABLE} /var/www/tt-rss/update_daemon2.php --interval=${TTRSS_FEED_UPDATE_CHECK}
exit 0