#!/bin/sh

VERSION=$(cat /app/version)

# Check/create config file
cp -Raf /app/htdocs /var/www/ 2>&1 | grep -v "preserve ownership"
if [ -f /app/conf/conf.php ];then
	chown www-data:www-data /app/conf/conf.php
	chmod 660 /app/conf/conf.php
	ln -sf /app/conf/conf.php /var/www/htdocs/conf.php
else
	ln -sf /var/documents/conf/conf.php /var/www/htdocs/conf/conf.php
	if [ ! -e /var/documents/conf/conf.php ];then
		mkdir -p /var/documents/conf
		cat >/var/documents/conf/conf.php <<ENDFILE
<?php
// Config file for Dolibarr ${VERSION} ($(date +%Y-%m-%dT%H:%M:%S%:z))
// ###################
// # Main parameters #
// ###################
\$dolibarr_main_url_root='${DOLI_URL_ROOT:-"http://'.\$_SERVER['HTTP_HOST'].'/"}';
\$dolibarr_main_document_root='/var/www/htdocs';
\$dolibarr_main_url_root_alt='/custom';
\$dolibarr_main_document_root_alt='/var/www/htdocs/custom';
\$dolibarr_main_data_root='/var/documents';
\$dolibarr_main_db_host='${DOLI_DB_HOST:="mariadb"}';
\$dolibarr_main_db_port='${DOLI_DB_PORT}';
\$dolibarr_main_db_name='${DOLI_DB_NAME}';
\$dolibarr_main_db_prefix='${DOLI_DB_PREFIX}';
\$dolibarr_main_db_user='${DOLI_DB_USER}';
\$dolibarr_main_db_pass='${DOLI_DB_PASSWORD:="dolibarr"}';
\$dolibarr_main_db_type='${DOLI_DB_TYPE}';
\$dolibarr_main_db_character_set='${DOLI_DB_CHARACTER_SET}';
\$dolibarr_main_db_collation='${DOLI_DB_COLLATION}';
// ##################
// # Login          #
// ##################
\$dolibarr_main_authentication='${DOLI_AUTH}';
\$dolibarr_main_auth_ldap_host='${DOLI_LDAP_HOST}';
\$dolibarr_main_auth_ldap_port='${DOLI_LDAP_PORT}';
\$dolibarr_main_auth_ldap_version='${DOLI_LDAP_VERSION}';
\$dolibarr_main_auth_ldap_servertype='${DOLI_LDAP_SERVERTYPE}';
\$dolibarr_main_auth_ldap_login_attribute='${DOLI_LDAP_LOGIN_ATTRIBUTE}';
\$dolibarr_main_auth_ldap_dn='${DOLI_LDAP_DN}';
\$dolibarr_main_auth_ldap_filter ='${DOLI_LDAP_FILTER}';
\$dolibarr_main_auth_ldap_admin_login='${DOLI_LDAP_ADMIN_LOGIN}';
\$dolibarr_main_auth_ldap_admin_pass='${DOLI_LDAP_ADMIN_PASS}';
\$dolibarr_main_auth_ldap_debug='${DOLI_LDAP_DEBUG}';
// ##################
// # Security       #
// ##################
\$dolibarr_main_prod='${DOLI_PROD:="0"}';
\$dolibarr_main_force_https='${DOLI_HTTPS}';
\$dolibarr_main_restrict_os_commands='mysqldump, mysql, pg_dump, pgrestore';
\$dolibarr_nocsrfcheck='${DOLI_NO_CSRF_CHECK:="0"}';
\$dolibarr_main_cookie_cryptkey='$(openssl rand -hex 32)';
\$dolibarr_mailing_limit_sendbyweb='0';
define('MAIN_ANTIVIRUS_COMMAND', '/usr/bin/clamdscan');
define('MAIN_ANTIVIRUS_PARAM', '--fdpass');

ENDFILE
	fi
	chown www-data:www-data /var/documents/conf/conf.php
	chmod 660 /var/documents/conf/conf.php

fi
chown -R www-data:www-data /var/documents/


versionCheck() {
	[ "$(printf '%s\n' "$@" | sort -t '.' -n -k1,1 -k2,2 -k3,3 | head -n 1)" == "$2" ]
}
getBaseVers() {
	echo "$1"|awk -F. '{print $1"."$2".0"}'
}

wwwRun() {
	if [ "$(id -u)" = 0 ]; then
		su - www-data -c "cd $(pwd);$*"
	else
		$*
	fi
}

mysqlRunE() {
	mysql -u "${DOLI_DB_USER}" "-p${DOLI_DB_PASSWORD:="dolibarr"}" -h "${DOLI_DB_HOST:="mariadb"}" -P "${DOLI_DB_PORT}" "$@" > /dev/null 2>&1
}
mysqlRun() {
	mysqlRunE "$DOLI_DB_NAME" "$@"
}
pgsqlRun() {
	PGPASSWORD="${DOLI_DB_PASSWORD:="dolibarr"}" psql -h "${DOLI_DB_HOST:="postgres"}" -p "${DOLI_DB_PORT}" -U "${DOLI_DB_USER}" -w "$@" > /dev/null 2>&1
}
dbRun() {
	local r=1
	if [[ ${DOLI_DB_TYPE} == "mysqli" ]];then
		mysqlRun -e "$@"
		r=$?
	elif [[ ${DOLI_DB_TYPE} == "pgsql" ]];then
		pgsqlRun -c "$@"
		r=$?
	fi
	return $r
}

installEnd() {
	touch /var/documents/install.lock
	chown www-data:www-data /var/documents/install.lock
	chmod 400 /var/documents/install.lock
	cat /app/version>/var/documents/install.version
}
upgrade() {
	echo "Upgrading...."
	if versionCheck "$VERSION" "$current"; then
		if [ -f /var/documents/install.lock ]; then
			rm /var/documents/install.lock
		fi
		upg="$(getBaseVers "$current") $(getBaseVers "$VERSION")"
		cd /var/www/htdocs/install
		wwwRun php upgrade.php $upg
		wwwRun php upgrade2.php $upg
		wwwRun php step5.php $upg
		cd -
		installEnd
	fi
}


r=1
c=0
if [[ ${DOLI_DB_TYPE} == "mysqli" ]];then
	while [ $r -ne 0 ]; do
		mysqlRunE -e "status"
		r=$?
		if [ $r -ne 0 ]; then
			echo "Waiting that mySQL database is up... ($c)"
			sleep 2
			c=$(($c + 1))
		fi
	done
elif [[ ${DOLI_DB_TYPE} == "pgsql" ]];then
	while [ $r -ne 0 ]; do
		pgsqlRun -c 'select * from pg_settings where 0=1;'
		r=$?
		if [ $r -ne 0 ]; then
			echo "Waiting that postgreSQL database is up...($c)"
			sleep 2
			c=$(($c + 1))
		fi
	done
fi
echo "Database ready to connect..."
current="0.0.0"
if [ -f /var/documents/install.version ]; then
	# Upgrade database
	current="$(cat /var/documents/install.version)"
	upgrade
else
	dbRun "SELECT * FROM llx_const"
	if [ $? -ne 0 ]; then
			cat > /var/www/htdocs/install/install.forced.php <<EOF
<?php
// Forced install config file for Dolibarr ${VERSION} ($(date +%Y-%m-%dT%H:%M:%S%:z))
/** @var bool Hide PHP informations */
\$force_install_nophpinfo = true;
/** @var int 1 = Lock and hide environment variables, 2 = Lock all set variables */
\$force_install_noedit = 2;
/** @var string Information message */
\$force_install_message = 'Dolibarr installation';
/** @var string Data root absolute path (documents folder) */
\$force_install_main_data_root = '/var/documents';
/** @var bool Force HTTPS */
\$force_install_mainforcehttps = false;
/** @var string Database name */
\$force_install_database = '${DOLI_DB_NAME}';
/** @var string Database driver (mysql|mysqli|pgsql|mssql|sqlite|sqlite3) */
\$force_install_type = '${DOLI_DB_TYPE}';
/** @var string Database server host */
\$force_install_dbserver = '${DOLI_DB_HOST}';
/** @var int Database server port */
\$force_install_port = '${DOLI_DB_PORT}';
/** @var string Database tables prefix */
\$force_install_prefix = '${DOLI_DB_PREFIX}';
/** @var string Database username */
\$force_install_databaselogin = '${DOLI_DB_USER}';
/** @var string Database password */
\$force_install_databasepass = '${DOLI_DB_PASSWORD}';
/** @var bool Force database user creation */
\$force_install_createuser = false;
/** @var bool Force database creation */
\$force_install_createdatabase = !empty('${DOLI_DB_ROOT_LOGIN}');
/** @var string Database root username */
\$force_install_databaserootlogin = '${DOLI_DB_ROOT_LOGIN}';
/** @var string Database root password */
\$force_install_databaserootpass = '${DOLI_DB_ROOT_PASSWORD}';
/** @var string Dolibarr super-administrator username */
\$force_install_dolibarrlogin = '${DOLI_ADMIN_LOGIN}';
/** @var bool Force install locking */
\$force_install_lockinstall = true;
/** @var string Enable module(s) (Comma separated class names list) */
\$force_install_module = '${DOLI_MODULES}';
EOF
		upg="$(getBaseVers "$current") $(getBaseVers "$VERSION")"
		cd /var/www/htdocs/install
		wwwRun php step2.php set
		wwwRun php step5.php $upg '' set "${DOLI_ADMIN_LOGIN}" "$DOLI_ADMIN_PASSWORD" "$DOLI_ADMIN_PASSWORD"
		cd -
		PASS=$(echo -n ${DOLI_ADMIN_PASSWORD:-"admin"} | md5sum | awk '{print $1}')
		dbRun "INSERT INTO llx_user (entity, login, pass_crypted, lastname, admin, statut) VALUES (0, '${DOLI_ADMIN_LOGIN:-"admin"}', '${PASS}', 'SuperAdmin', 1, 1);"

		dbRun "DELETE FROM llx_const WHERE name='MAIN_VERSION_LAST_INSTALL';"
		dbRun "DELETE FROM llx_const WHERE name='MAIN_NOT_INSTALLED';"
		dbRun "DELETE FROM llx_const WHERE name='MAIN_LANG_DEFAULT';"
		dbRun "INSERT INTO llx_const(name,value,type,visible,note,entity) values('MAIN_VERSION_LAST_INSTALL', '${VERSION}', 'chaine', 0, 'Dolibarr version when install', 0);"
		dbRun "INSERT INTO llx_const(name,value,type,visible,note,entity) VALUES ('MAIN_LANG_DEFAULT', 'auto', 'chaine', 0, 'Default language', 1);"

		installEnd
	# TODO mysql upgrade from mysql version
	elif [[ ${DOLI_DB_TYPE} == "pgsql" ]];then
		current=$(pgsqlRun -t -c "select value from llx_const where name='MAIN_VERSION_LAST_INSTALL';")
		upgrade
	else
		echo "${DOLI_DB_TYPE} is not supported by this install script"
	fi
fi

[[ "x${DOLI_REDIS_HOST}" != "x" ]] && { 
    echo 'session.save_handler = redis';
    echo "session.save_path = ${DOLI_REDIS_HOST}";
} >> /usr/local/etc/php/conf.d/docker-php-ext-redis.ini

freshclam --log=/proc/self/fd/1 &

for script in /docker-entrypoint.d/*.sh;do
	ash "${script}"
done

exec "$@"
