# alandoyle/tt-rss-mysql

![Tiny Tiny RSS](https://community.tt-rss.org/uploads/default/optimized/1X/18a2e96275d1fffb21cce225d30a87be4544db60_2_180x180.png)

A simple Tiny Tiny RSS image which only supports MySQL with integrated feed updates.

+ Support MySQL server.
+ Built in Feed updating.
+ Built-in TT-RSS updating.

----
## IMPORTANT NOTES

This Docker image has several assumptions/prerequisites which need to be  fulfilled, ignoring them *will* bring failure.

1. This Docker Image is for MySQL _ONLY_.
1. This image is for domains or sub-domains with **/tt-rss/** in the URL. e.g. **http://reader.mydomain.tld**
1. MySQL needs to be installed in a separate Docker container.
1. MySQL needs to be configured and setup **BEFORE** this image is deployed (explained below).
1. If a previous MySQL instance is used and and old TT-RSS instance was using PHP 7.x then a "Data Fix" will need to be applied to the database as this image used PHP 8.2 and generates JSON differently. Failure to "Data Fix" the database could result in duplicate posts appearing in TT-RSS (explained below)

## MySQL Setup

This image _requires_ a database and database user be set up **PRIOR** to bringing up the image.

A new database and user can be created using the _mysql_ command.

e.g. If you're running the MySQL container from the Docker Compose example below you will need to run the following commands to create the database and user.

```bash
docker exec -it <MYSQL_CONTAINER> /bin/bash
```
Once inside the container run the following command to access MySQL.
```bash
mysql -u root -p
```
You will be prompted for the MYSQL_ROOT_PASSWORD (see Docker Compose example)
Once in _mysql_ run the following SQL commands to set up the database and user (see Docker Compose example to match up the values).
```sql
CREATE DATABASE <TTRSS_DB_NAME>;
CREATE USER '<TTRSS_DB_USER>' IDENTIFIED BY '<TTRSS_DB_PASS>';
GRANT ALL ON <TTRSS_DB_NAME>.* TO '<TTRSS_DB_USER>';
FLUSH PRIVILEGES;
\q
```

Now the `tt-rss-mysql` image can be started.

## PHP 7 -> PHP 8 "Data Fix"

**NOTE:** If this is a fresh install of Tiny Tiny RSS then ignore this section.

PHP 7 stores the unique GUID used by each article in the following format:
```
{"ver":2,"uid":"2","hash":"SHA1:2b10b494802dc70e9d9d7676cdef0cf0f9969b78"}
```

PHP 8 stores the unique GUID used by each article in the following format:
```
{"ver":2,"uid":2,"hash":"SHA1:2b10b494802dc70e9d9d7676cdef0cf0f9969b78"}
```

Notice that the "uid" value is quoted with PHP 7 but not PHP 8.

### The fix
To fix a previous MySQL database populated by PHP 7 the following SQL commands need to be used via the _mysql_ commandline tool.
```sql
USE <TTRSS-DATABASE>;

UPDATE ttrss_entries
SET guid = replace(replace(guid,'"uid":"', '"uid":'),'", "hash":', ',"hash":')
WHERE guid LIKE '%"uid":"%"%';
```
----

## Docker 

Available on [DockerHub](https://hub.docker.com/r/alandoyle/tt-rss-mysql)
```bash
docker pull alandoyle/tt-rss-mysql
```

## Usage

```bash
docker run --name=tt-rss-mysql \
  -d --init \
  -v <MY_CONF_PATH>:/opt/tt-rss/config.d\
  -v <MY_WEB_PATH>:/var/www/tt-rss\
  -p 8000:80/tcp \
  alandoyle/tt-rss-mysql:latest
```

Docker compose example:

```yaml
version: "3"

services:
  mysql:
    image: mysql:8.0
    container_name: mysql
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: SecureSecretPassword
    volumes:
      - ./mysql/data:/var/lib/mysql
  tt-rss-mysql:
   image: alandoyle/tt-rss-mysql:latest
   container_name: tt-rss-mysql
   restart: unless-stopped
   init: true
   ports:
     - "8000:80/tcp"
    volumes:
      - ./tt-rss/web:/var/www/tt-rss
      - ./tt-rss/config:/opt/tt-rss/config.d
    environment:
      TTRSS_SELF_URL_PATH: https://reader.mydomain.tld
      TTRSS_DB_HOST: mysql
      TTRSS_DB_USER: ttrss_user
      TTRSS_DB_NAME: ttrss_database
      TTRSS_DB_PASS: ttrss_password
      TTRSS_DB_PORT: 3306
      TTRSS_FEED_UPDATE_CHECK: 600
```

### Ports

| Port     | Description           |
|----------|-----------------------|
| `80/tcp` | HTTP                  |

### Volumes

| Path    | Description                           |
|---------|---------------------------------------|
| `/var/www/tt-rss` | path for tt-rss web files |
| `/opt/tt-rss/config.d` | path for tt-rss configuration files          |
