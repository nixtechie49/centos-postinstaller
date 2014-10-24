#!/bin/sh
#
# CentOS 6 epic Cleaner and Installer
# By kjohnson@aerisnetwork.com
# 
# v2.34 2014-04-04

######## Global variables ########

URL="http://build.aerisnetwork.com"
BUILDLOG="/tmp/build.log"

### IP ###

if [ -f /etc/sysconfig/network-scripts/ifcfg-venet0 ];
	then
    	IP=`/sbin/ifconfig venet0:0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}'`
elif [ -f /etc/sysconfig/network-scripts/ifcfg-eth0 ];
	then
    	IP=`/sbin/ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}'`
else
		IP="127.0.0.1"
fi

# Simple next/go function
function enter ()
 {
  echo ""
  read -sn 1 -p "All done! Press any key to continue..."
 }

################################################################################################
################################### Option 1 cPanel Startup ####################################

function cpanel {

### cpanel installation ###

pushd /root
wget -N http://layer1.cpanel.net/latest 3>&1 4>&2 >>$BUILDLOG 2>&1
echo "Installing cPanel.. this will take about 20 minutes.."
sh latest 3>&1 4>&2 >>$BUILDLOG 2>&1
chmod 777 /var/run/screen
echo "cPanel has been installed."

### alias ###

echo "
alias apachetop=\"/opt/scripts/apache-top.py -u http://127.0.0.1/whm-server-status\"
alias apachelogs=\"tail -f /usr/local/apache/logs/error_log\"
alias eximlogs=\"tail -f /var/log/exim_mainlog\"
alias htop=\"htop -C\"
" >> /etc/profile
echo "Custom alias have been installed."

### basic mysql config ###

mv /etc/my.cnf /etc/my.cnf.origin
touch /var/log/mysqld-slow.log
chown mysql:root /var/log/mysqld-slow.log
chmod 664 /var/log/mysqld-slow.log
echo "[mysqld]
innodb_file_per_table = 1
default-storage-engine = MyISAM
log-error = /var/log/mysqld.log
bind-address = 127.0.0.1

query-cache-type = 1
query-cache-size = 32M
query_cache_limit = 4M
table_cache = 1024  ### replace table_open_cache= if MySQL 5.6
open_files_limit = 2048
max_connections = 75
thread_cache_size = 2
tmp_table_size = 32M
max_heap_table_size = 32M
key_buffer_size = 32M
innodb_buffer_pool_size = 32M
join_buffer_size = 256k
sort_buffer_size = 256k
read_buffer_size = 256k
read_rnd_buffer_size = 256k
max_allowed_packet = 64M

slow_query_log = 1
slow_query_log_file = /var/log/mysqld-slow.log
long_query_time = 15
" > /etc/my.cnf
echo "MySQL has been optimized."

### other stuff ###

wget -O /opt/scripts/apache-top.py $URL/scripts/apache-top.py 3>&1 4>&2 >>$BUILDLOG 2>&1
chmod +x /opt/scripts/apache-top.py
echo "Downloading useful scripts..."
touch /var/cpanel/optimizefsdisable
echo "Disabling cPanel optimizefs script while noatime activated."
rm -f /root/latest /root/installer.lock /root/php.ini.new /root/php.ini.orig

echo -e "\n*****************************************************************\n"
echo -e "cPanel is now installed. You can browse the following link"
echo -e "http://$IP:/whm"
echo -e "Please check /etc/my.cnf before doing /scripts/restartsrv_mysql ; tail -f /var/log/mysqld.log"
echo -e "\n*****************************************************************\n"

}


################################################################################################
############################### Option 3 LAMP with Nginx Startup ###############################

function lamp {

WWWPASS=`cat /dev/urandom | tr -cd 'a-f0-9' | head -c 8`
SQLPASS=`cat /dev/urandom | tr -cd 'a-f0-9' | head -c 8`
MONITPASS=`cat /dev/urandom | tr -cd 'a-f0-9' | head -c 8`
MUNINPASS=`cat /dev/urandom | tr -cd 'a-f0-9' | head -c 8`
PMA=`cat /dev/urandom | tr -cd 'a-f0-9' | head -c 8`
MariaDB=false

### Domain configuration ###

echo -e "\n*****************************************************************"
echo -e "Apache / Nginx Webkit preparation"
echo -e "What is the main domain? Will be used to install Web/PMA/Munin/Monit/Staging\n"
read -p "Enter the domain : " -e DOMAIN
echo -e "\nChoose PHP version: builtin|53|54|55"
echo -e "Built-in (default) will also use built-in MySQL. Others use latest PHP with latest MySQL 5.6 OR MariaDB 10\n"
read -p "Enter PHP version: " -e PHPVERSION

if [ "$PHPVERSION" == "53" ] || [ "$PHPVERSION" == "54" ] || [ "$PHPVERSION" == "55" ]; then
	echo -e "\nThis PHP version allows MariaDB support."
	read -p "Do you want to switch MySQL 5.6 for MariaDB 10? (N/y): " -e MariaDB_INPUT
	if [ "$MariaDB_INPUT" == "y" ] || [ "$MariaDB_INPUT" == "Y" ]; then
		MariaDB=true
	fi
fi

echo -e "\nProceeding with $DOMAIN with PHP $PHPVERSION...\n"

echo -e "\n*****************************************************************"
echo -e "Basic setup for $DOMAIN.."
echo -e "*****************************************************************\n"

mkdir -p /home/www/$DOMAIN
mkdir /home/www/$DOMAIN/public_html
mkdir /home/www/$DOMAIN/subdomains
mkdir /home/www/$DOMAIN/subdomains/staging
mkdir /home/www/$DOMAIN/subdomains/monit
ln -s /var/www/html/munin /home/www/$DOMAIN/subdomains/munin
echo -e "Directories for $DOMAIN and services are created."


echo -e "\n*****************************************************************"
echo -e "Installing packages.."
echo -e "*****************************************************************\n"

## Notes: No ionCube module in PHP 5.5 repo as of 2014/03/28

yum install -y db4-utils httpd httpd-devel monit munin munin-node vsftpd 3>&1 4>&2 >>$BUILDLOG 2>&1
echo -e "Default packages installed."

if [ $PHPVERSION == "53" ];
	then
		yum install -y $URL/repos/ius-release-1.0-11.ius.centos6.noarch.rpm 3>&1 4>&2 >>$BUILDLOG 2>&1
		echo -e "IUScommunity repo installed."
		yum install -y yum-plugin-replace 3>&1 4>&2 >>$BUILDLOG 2>&1
		yum install -y php53u php53u-cli php53u-common php53u-devel php53u-enchant php53u-gd php53u-imap php53u-ioncube-loader php53u-mbstring php53u-mcrypt php53u-mysql php53u-pdo php53u-pear php53u-pecl-memcache php53u-soap php53u-tidy php53u-xml php53u-xmlrpc 3>&1 4>&2 >>$BUILDLOG 2>&1
		echo -e "Latest PHP 5.3 has been installed."
		if [[ "$MariaDB" == true ]]; then
			echo "[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.0/centos6-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1" > /etc/yum.repos.d/MariaDB.repo
			echo -e "MariaDB repo installed."
			yum install -y MariaDB-server MariaDB-client 3>&1 4>&2 >>$BUILDLOG 2>&1
			echo -e "Latest MariaDB 10 has been installed."
		else
			yum install -y mysql 3>&1 4>&2 >>$BUILDLOG 2>&1
	    	yum replace -y mysql --replace-with mysql56u 3>&1 4>&2 >>$BUILDLOG 2>&1
	    	yum install -y mysql56u-server 3>&1 4>&2 >>$BUILDLOG 2>&1
	    	echo -e "Latest MySQL 5.6 have been installed."
		fi   	
elif [ $PHPVERSION == "54" ];
	then
		yum install -y $URL/repos/ius-release-1.0-11.ius.centos6.noarch.rpm 3>&1 4>&2 >>$BUILDLOG 2>&1
		echo -e "IUScommunity repo installed."
		yum install -y yum-plugin-replace 3>&1 4>&2 >>$BUILDLOG 2>&1
		yum install -y php54 php54-cli php54-common php54-devel php54-enchant php54-gd php54-imap php54-ioncube-loader php54-mbstring php54-mcrypt php54-mysql php54-pdo php54-pear php54-pecl-memcache php54-soap php54-tidy php54-xml php54-xmlrpc 3>&1 4>&2 >>$BUILDLOG 2>&1
		echo -e "Latest PHP 5.4 has been installed."
		if [[ "$MariaDB" == true ]]; then
			echo "[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.0/centos6-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1" > /etc/yum.repos.d/MariaDB.repo
			echo -e "MariaDB repo installed."
			yum install -y -q MariaDB-server MariaDB-client 3>&1 4>&2 >>$BUILDLOG 2>&1
			echo -e "Latest MariaDB 10 has been installed."
		else
			yum install -y mysql 3>&1 4>&2 >>$BUILDLOG 2>&1
	    	yum replace -y mysql --replace-with mysql56u 3>&1 4>&2 >>$BUILDLOG 2>&1
	    	yum install -y mysql56u-server 3>&1 4>&2 >>$BUILDLOG 2>&1
	    	echo -e "Latest MySQL 5.6 have been installed."
		fi 
elif [ $PHPVERSION == "55" ];
	then
		yum install -y $URL/repos/ius-release-1.0-11.ius.centos6.noarch.rpm 3>&1 4>&2 >>$BUILDLOG 2>&1
		echo -e "IUScommunity repo installed."
		yum install -y yum-plugin-replace 3>&1 4>&2 >>$BUILDLOG 2>&1
		yum install -y php55u php55u-cli php55u-common php55u-devel php55u-enchant php55u-gd php55u-imap php55u-ioncube-loader php55u-mbstring php55u-mcrypt php55u-mysql php55u-pdo php55u-pear php55u-pecl-memcache php55u-soap php55u-tidy php55u-xml php55u-xmlrpc 3>&1 4>&2 >>$BUILDLOG 2>&1
	    echo -e "Latest PHP 5.5 has been installed. Keep in mind that PHP 5.5 doesn't support ionCube yet."
		if [[ "$MariaDB" == true ]]; then
			echo "[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.0/centos6-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1" > /etc/yum.repos.d/MariaDB.repo
			echo -e "MariaDB repo installed."
			yum install -y MariaDB-server MariaDB-client 3>&1 4>&2 >>$BUILDLOG 2>&1
			echo -e "Latest MariaDB 10 have been installed."
		else
			yum install -y mysql 3>&1 4>&2 >>$BUILDLOG 2>&1
	    	yum replace -y mysql --replace-with mysql56u 3>&1 4>&2 >>$BUILDLOG 2>&1
	    	yum install -y mysql56u-server 3>&1 4>&2 >>$BUILDLOG 2>&1
	    	echo -e "Latest MySQL 5.6 has been installed."
		fi 
	    
else
		yum install -y mysql mysql-server php php-cli php-common php-devel php-enchant php-gd php-imap php-ioncube-loader php-mbstring php-mcrypt php-mysql php-pdo php-pear php-pecl-memcache php-soap php-tidy php-xml php-xmlrpc 3>&1 4>&2 >>$BUILDLOG 2>&1
		echo -e "Built-in PHP and MySQL installed."
fi


echo -e "\n*****************************************************************"
echo -e "Adding Web user, set password and permissions.."
echo -e "*****************************************************************\n"

adduser www 3>&1 4>&2 >>$BUILDLOG 2>&1
echo $WWWPASS | passwd www --stdin
chown -R www:www /home/www
chmod 755 /home/www
echo -e "User www added with password $WWWPASS."

echo -e "\n*****************************************************************"
echo -e "Optimizing services configurations.."
echo -e "*****************************************************************\n"


### Apache ###
mv /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf.origin
wget -O /etc/httpd/conf/httpd.conf $URL/config/httpd22-centos6.conf 3>&1 4>&2 >>$BUILDLOG 2>&1
sed -i "s/replaceme/$DOMAIN/g" /etc/httpd/conf/httpd.conf
echo -e "Apache configured on port 80 for $DOMAIN."


### MySQL ###
if [[ "$MariaDB" == true ]]; then
	/etc/init.d/mysql start 3>&1 4>&2 >>$BUILDLOG 2>&1
	echo "Giving 3s to start MariaDB..."
else
	/etc/init.d/mysqld start 3>&1 4>&2 >>$BUILDLOG 2>&1
	echo "Giving 3s to start MySQL..."
fi
sleep 3
/usr/bin/mysqladmin -u root password $SQLPASS 3>&1 4>&2 >>$BUILDLOG 2>&1
echo "Setting root password for SQL."
/usr/bin/mysqladmin -u root -p$SQLPASS -f drop test 3>&1 4>&2 >>$BUILDLOG 2>&1
echo "Dropping database test."
echo "
[client]
user=root
password=$SQLPASS
">/root/.my.cnf
cp /root/.my.cnf /home/www/.my.cnf
chown www:www /home/www/.my.cnf
echo -e "SQL server configured with root password $SQLPASS."


### Monit ###
echo "Monit monitoring" > /var/www/html/monit.html
echo "Default" > /var/www/html/index.html
echo "<?php echo 'Current PHP version: ' . phpversion(); ?>" > /home/www/$DOMAIN/public_html/index.php
sed -i "s/use\ address\ localhost/\#use\ address\ localhost/g" /etc/monitrc
sed -i "s/allow\ monit\:monit/allow\ monit\:$MONITPASS/g" /etc/monitrc
echo -e "Monit configured for Apache and MySQL. Listening on port 2812."


### PMA ###
wget -O /home/www/$DOMAIN/subdomains/phpmyadmin.tar.gz $URL/files/phpmyadmin.tar.gz 3>&1 4>&2 >>$BUILDLOG 2>&1
tar -zxf /home/www/$DOMAIN/subdomains/phpmyadmin.tar.gz -C /home/www/$DOMAIN/subdomains 3>&1 4>&2 >>$BUILDLOG 2>&1
rm -f /home/www/$DOMAIN/subdomains/phpmyadmin.tar.gz
mv /home/www/$DOMAIN/subdomains/phpMyAdmin* /home/www/$DOMAIN/subdomains/pma
echo "<?php
\$cfg['blowfish_secret'] = '$PMA';
 
\$i=0;
\$i++;
\$cfg['Servers'][\$i]['auth_type']     = 'cookie';
?>" > /home/www/$DOMAIN/subdomains/pma/config.inc.php
rm -rf /home/www/$DOMAIN/subdomains/pma/setup
echo -e "PhpMyAdmin installed with root $SQLPASS. Make sure to keep it updated."


### Munin ###
sed -i "s/\[localhost\]/\[$DOMAIN\]/g" /etc/munin/munin.conf
pushd /etc/munin/plugins 3>&1 4>&2 >>$BUILDLOG 2>&1
find /etc/munin/plugins -exec unlink {} \; >/dev/null 2>&1
ln -s /usr/share/munin/plugins/cpu /etc/munin/plugins/cpu
ln -s /usr/share/munin/plugins/df /etc/munin/plugins/df
ln -s /usr/share/munin/plugins/load /etc/munin/plugins/load
ln -s /usr/share/munin/plugins/memory /etc/munin/plugins/memory
ln -s /usr/share/munin/plugins/apache_accesses /etc/munin/plugins/apache_accesses
ln -s /usr/share/munin/plugins/apache_volume /etc/munin/plugins/apache_volume
ln -s /usr/share/munin/plugins/nginx_status /etc/munin/plugins/nginx_status
ln -s /usr/share/munin/plugins/nginx_request /etc/munin/plugins/nginx_request
ln -s /usr/share/munin/plugins/mysql_queries /etc/munin/plugins/mysql_queries
ln -s /usr/share/munin/plugins/mysql_threads /etc/munin/plugins/mysql_threads
ln -s /usr/share/munin/plugins/mysql_slowqueries /etc/munin/plugins/mysql_slowqueries
echo "
[apache_*]
env.url   http://127.0.0.1:%d/server-status?auto
env.ports 80
 
[mysql*]
user root
group wheel
env.mysqladmin /usr/bin/mysqladmin
env.mysqlopts --defaults-extra-file=/root/.my.cnf
" >> /etc/munin/plugin-conf.d/munin-node
pushd /root 3>&1 4>&2 >>$BUILDLOG 2>&1
htpasswd -b -c /var/www/html/munin/.htpasswd munin $MUNINPASS
echo -e "Munin configured with password $MUNINPASS."

### VsFTPd ###
sed -i "s/anonymous_enable=YES/anonymous_enable=NO/g" /etc/vsftpd/vsftpd.conf 
sed -i "s/\#chroot_local_user=YES/chroot_local_user=YES/g" /etc/vsftpd/vsftpd.conf 
sed -i "s/pam_service_name=vsftpd/\#pam_service_name=vsftpd/g" /etc/vsftpd/vsftpd.conf
echo "pam_service_name=vsftpd-virtual
virtual_use_local_privs=YES
hide_ids=YES
user_config_dir=/etc/vsftpd/vusers
guest_enable=YES
" >> /etc/vsftpd/vsftpd.conf
echo "auth required pam_userdb.so db=/etc/vsftpd/virtual-users
account required pam_userdb.so db=/etc/vsftpd/virtual-users
session required pam_loginuid.so
" >> /etc/pam.d/vsftpd-virtual
echo "www" > /etc/vsftpd/vuserslist
echo "$WWWPASS" >> /etc/vsftpd/vuserslist
db_load -T -t hash -f /etc/vsftpd/vuserslist /etc/vsftpd/virtual-users.db
mkdir /etc/vsftpd/vusers/
echo "local_root=/home/www
dirlist_enable=YES
download_enable=YES
write_enable=YES
guest_username=www
" >> /etc/vsftpd/vusers/www
echo "FTP server configured for user www with password $WWWPASS."


### Nginx ###

## TODO: switch to Nginx with Apache or Nginx with FPM


### Final and Startups ###
chown www:www /var/lib/php/session
chown -R www:www /home/www
echo "chown www:www /var/lib/php/session" >> /etc/rc.local
chkconfig --level 2345 mysqld on >/dev/null 2>&1
chkconfig --level 2345 mysql on >/dev/null 2>&1
chkconfig --level 2345 monit on
chkconfig --level 2345 munin-node on
chkconfig --level 2345 vsftpd on
echo "Final configurations done."
echo "Starting Apache, Monit, Munin, VsFTPd..."
service httpd start 3>&1 4>&2 >>$BUILDLOG 2>&1
service monit start 3>&1 4>&2 >>$BUILDLOG 2>&1
service munin-node start 3>&1 4>&2 >>$BUILDLOG 2>&1
service vsftpd start 3>&1 4>&2 >>$BUILDLOG 2>&1
echo "Everything started."

echo -e "\n*****************************************************************"
echo -e "Webkit installed!\n"
echo -e "Please copy all those information carefully:\n"
echo -e "SSH: root / replace"
echo -e "Apache: www / $WWWPASS"
echo -e "FTP: www / $WWWPASS"
echo -e "MySQL: root / $SQLPASS"
echo -e "Web: http://www.$DOMAIN"
echo -e "Pma: http://pma.$DOMAIN / root / $SQLPASS"
echo -e "Monit: http://monit.$DOMAIN / monit / $MONITPASS"
echo -e "Munin: http://munin.$DOMAIN / munin / $MUNINPASS"
echo -e "\nVersions:\n"
httpd -v
php -v
mysql -V
echo -e "\n*****************************************************************\n"

}


################################################################################################
############################### Option 6 FreePBX Startup #######################################

function freepbx {

echo -e "\n*****************************************************************"
echo -e "FreePBX preparation starting"
echo -e "*****************************************************************\n"

read -p "Which Panel admin password do you want ? : " -e PANEL_PASS
read -p "Which MySQL root password do you want ? : " -e MYSQL_PASS
ARI=`cat /dev/urandom | tr -cd 'a-f0-9' | head -c 8`

sed -i "s/enabled=1/enabled=0/g" /etc/yum.repos.d/epel.repo >/dev/null 2>&1
yum clean all -q
echo -e "\nEPEL repo disabled because it has an old asterisk version. Yum cleaned."

wget --quiet -N -O /opt/src/freepbx-2.11.0.25.tgz http://mirror.freepbx.org/freepbx-2.11.0.25.tgz
pushd /opt/src >/dev/null 2>&1
tar -zxf freepbx*.tgz
rm -f freepbx*.tgz
echo "FreePBX 2.11 downloaded and uncompressed."

yum install -q -y httpd httpd-devel php php-devel php-process php-common php-pear php-pear-DB php-mysql php-xml php-xmlrpc php-mbstring php-pdo php-cli php-mysql php-gd php-xml php-imap mysql mysql-server libxml2-devel sqlite-devel openssl-devel perl curl sox bison audiofile-devel ncurses-devel dnsmasq >/dev/null 2>&1
service mysqld restart >/dev/null 2>&1
sleep 2
echo "FreePBX dependencies such as Apache/PHP/MySQL are installed."

yum install -y -q http://packages.asterisk.org/centos/6/current/x86_64/RPMS/asterisknow-version-3.0.1-2_centos6.noarch.rpm
echo "Asterisk 11 repo installed."

/usr/bin/mysqladmin -u root password $MYSQL_PASS
/usr/bin/mysqladmin -u root -p$MYSQL_PASS create asterisk
/usr/bin/mysqladmin -u root -p$MYSQL_PASS create asteriskcdrdb
echo "MySQl root set to $MYSQL_PASS. Asterisk DBs are created. (asterisk and asteriskcdrdb)"


echo -e "\n*****************************************************************"
echo -e "Web server and Asterisk installation starting"
echo -e "\n*****************************************************************"


yum install -y -q asterisk asterisk-configs asterisk-addons asterisk-ogg asterisk-addons-mysql asterisk-voicemail asterisk-sounds-moh-opsound-wav asterisk-sounds-moh-opsound-ulaw asterisk-sounds-moh-opsound-g722 asterisk-sounds-core-en-ulaw asterisk-sounds-core-en-g722 asterisk-sounds-core-fr-ulaw asterisk-sounds-core-fr-g722 asterisk-sounds-core-fr-gsm asterisk-sounds-extra-en-ulaw asterisk-sounds-extra-en-gsm php-pear-DB --enablerepo=asterisk-11
echo "Asterisk 11 packages have been installed."

touch /var/log/asterisk/freepbx.log
chown asterisk:root /var/log/asterisk/freepbx.log
chmod 664 /var/log/asterisk/freepbx.log
sed -i "s/TTY=9/#TTY=9/g" /usr/sbin/safe_asterisk
sed -i "s/post_max_size\ =\ 8M/post_max_size\ =\ 64M/g" /etc/php.ini
sed -i "s/upload_max_filesize\ =\ 2M/upload_max_filesize\ =\ 64M/g" /etc/php.ini
sed -i "s/User apache/User asterisk/" /etc/httpd/conf/httpd.conf
sed -i "s/Group apache/Group asterisk/" /etc/httpd/conf/httpd.conf
sed -i "s/AllowOverride None/AllowOverride All/" /etc/httpd/conf/httpd.conf
chgrp asterisk /var/lib/php/session
htpasswd -b -c /var/www/.panel_htpasswd admin $PANEL_PASS
echo "
<Location />
AuthType Basic
AuthName \"FreePBX - ACCESS DENIED\"
AuthUserFile /var/www/.panel_htpasswd
<Limit GET POST>
    require valid-user
</Limit>
</Location>
" >> /etc/httpd/conf/httpd.conf
service httpd restart >/dev/null 2>&1
pushd /opt/src/freepbx* >/dev/null 2>&1
echo "Few changes done to Apache/PHP and safe_asterisk binary."

mysql -u root -p$MYSQL_PASS asterisk < SQL/newinstall.sql
mysql -u root -p$MYSQL_PASS asteriskcdrdb < SQL/cdr_mysql_table.sql
mysql -u root -p$MYSQL_PASS -e "GRANT ALL PRIVILEGES ON asteriskcdrdb.* TO asteriskuser@localhost IDENTIFIED BY '$MYSQL_PASS';"
mysql -u root -p$MYSQL_PASS -e "GRANT ALL PRIVILEGES ON asterisk.* TO asteriskuser@localhost IDENTIFIED BY '$MYSQL_PASS';"
mysql -u root -p$MYSQL_PASS -e "flush privileges;"
echo -e "FreePBX SQL tables installed.\n\n"

chown -R asterisk:root /var/lib/asterisk
chmod 775 /var/lib/asterisk
chown -R asterisk:asterisk /var/www/html
echo -e "Starting Asterisk, you can ignore errors.\n\n"
/usr/sbin/safe_asterisk & >/dev/null 2>&1
sleep 2
echo -e "\nAsterisk started."
echo -e "\n*****************************************************************"
echo -e "FreePBX installation starting"
echo -e "*****************************************************************"
echo -e "You will need to enter those information : "
echo -e "USERNAME to connect to the 'asterisk' database: asteriskuser"
echo -e "PASSWORD to connect to the 'asterisk' database: $MYSQL_PASS"
echo -e "HOSTNAME of the 'asterisk' database: localhost"
echo -e "USERNAME to connect to the Asterisk Manager interface: admin"
echo -e "PASSWORD to connect to the Asterisk Manager interface: $PANEL_PASS"
echo -e "PATH to use for your AMP web root: /var/www/html"
echo -e "IP : $IP"
echo -e "*****************************************************************\n"
./install_amp
amportal chown >/dev/null 2>&1
sed -i "s/ari_password/$ARI/g" /etc/amportal.conf
mysql -u root -p$MYSQL_PASS asterisk -e "UPDATE freepbx_settings SET value='$PANEL_PASS' WHERE keyword='AMPMGRPASS';"
echo "FreePBX installed."

/usr/local/sbin/amportal stop >/dev/null 2>&1
sleep 2
/usr/local/sbin/amportal start >/dev/null 2>&1
echo "Asterisk restarted."

chkconfig mysqld on
chkconfig httpd on
echo '/usr/local/sbin/amportal restart'>> /etc/rc.local
echo "sed -i \"s/TTY=9/#TTY=9/g\" /usr/sbin/safe_asterisk" >> /etc/rc.local
echo "chown asterisk /var/lib/php/session" >> /etc/rc.local
chkconfig --level 123456 asterisk off
mv /etc/asterisk/confbridge.conf /etc/asterisk/confbridge.conf.origin
mv /etc/asterisk/cel.conf /etc/asterisk/cel.conf.origin
mv /etc/asterisk/cel_odbc.conf /etc/asterisk/cel_odbc.conf.origin
mv /etc/asterisk/logger.conf /etc/asterisk/logger.conf.origin
mv /etc/asterisk/features.conf /etc/asterisk/features.conf.origin
mv /etc/asterisk/sip_notify.conf /etc/asterisk/sip_notify.conf.origin
mv /etc/asterisk/sip.conf /etc/asterisk/sip.conf.origin
mv /etc/asterisk/iax.conf /etc/asterisk/iax.conf.origin
mv /etc/asterisk/extensions.conf /etc/asterisk/extensions.conf.origin
mv /etc/asterisk/ccss.conf /etc/asterisk/ccss.conf.origin
mv /etc/asterisk/chan_dahdi.conf /etc/asterisk/chan_dahdi.conf.origin
mv /etc/asterisk/udptl.conf /etc/asterisk/udptl.conf.origin
mv /etc/asterisk/http.conf /etc/asterisk/http.conf.origin
/var/lib/asterisk/bin/retrieve_conf >/dev/null 2>&1
mkdir /var/www/html/admin/modules/_cache
chown asterisk:asterisk /var/www/html/admin/modules/_cache
echo "Last asterisk/freepbx configurations done."
/usr/local/sbin/amportal restart >/dev/null 2>&1
echo "Asterisk started."


echo -e "\n*****************************************************************"
echo -e "FreePBX & Asterisk installation done!"
echo -e "*****************************************************************\n"
asterisk -V
echo -e "\nYou should now open your browser at : http://$IP/"
echo -e "Asterisk Manager interface username : admin"
echo -e "Asterisk Manager interface password : $PANEL_PASS"
echo -e "\n*****************************************************************\n"

}


################################################################################################
################################## OS Cleanup Startup ##########################################

function cleanup {

sshkey="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDWfE1zygFZ8tbnG2yGcgc1LFGoSkFWVvB+TGIr6l5R+z/j7CBFQlvo9Wn5ziNBIUy7esXJN0qy2i+p5ZN1v1WBLi0GQZ8ZjqyM7f58wQlxlS7UEEVITwtGNv8B33M+Akg5kRBQgmNswsshukUHLQH8xhdJKBq76DFMXrlOYgXeAF/CBWBf/o5PqdDC9Qi/BqP5tCtsPGDIX9rj3qwzksoAI98gEhGhNYU4Tu7duC/Ie6rhseQIBHdH3xky7og8TOPNWRzSy5/9v5MNYmC+AjYXXPko8mnlMOheDNYerf6S/nz0r8J0EBD5KQEWQcURUoHeHD2+NSgRScTxVW7DxsKT karl@kjmac.aerisnetwork.net-DO-NOT-REMOVE"
SERVICES="iscsid iscsi smartd kudzu messagebus mcstrans cpuspeed NetworkManager NetworkManagerDispatcher acpid anacron apmd atd auditd autofs avahi-daemon bluetooth cups dhcdbd diskdump firstboot gpm haldaemon hidd ip6tables iptables irda isdn mdmonitor named netdump netfs netplugd nfs nfslock nscd ntpd pcmcia portmap portreserve psacct pcscd rdisc readahead_early readahead_later restorecond rhnsd rpcgssd rpcidmapd rpcsvcgssd saslauthd xfs xinetd winbind ypbind yum yum-updatesd"
RPMS="systemtap systemtap-runtime eject words alsa-lib python-ldap nfs-utils-lib mkbootdisk sos krb5-workstation pam_krb5 talk cyrus-sasl-plain doxygen gpm dhcdbd NetworkManager yum-updatesd libX11 GConf2 at-spi bluez-gnome bluez-utils cairo cups dogtail frysk gail glib-java gnome-keyring gnome-mount gnome-python2 gnome-python2-bonobo gnome-python2-gconf gnome-python2-gnomevfs gnome-vfs2 gtk2 libXTrap libXaw libXcursor libXevie libXext libXfixes libXfontcache libXft libXi libXinerama libXmu libXpm libXrandr libXrender libXt libXres libXtst libXxf86misc libXxf86vm libbonoboui libgcj libglade2 libgnome libgnomecanvas libgnomeui libnotify libwnck mesa-libGL notification-daemon pango paps pycairo pygtk2 pyspi redhat-lsb startup-notification xorg-x11-server-utils xorg-x11-xauth xorg-x11-xinit libXfont libXau libXdmcp xorg-x11-server-Xvfb ORBit2 firstboot-tui libbonobo pyorbit rhpl desktop-file-utils htmlview pinfo redhat-menus esound ppp wpa_supplicant rp-pppoe ypbind yp-tools oprofile pcmciautils oddjob-libs oddjob gnome-mime-data bluez-libs audiofile aspell aspell-en cpuspeed system-config-securitylevel-tui apmd dhcpv6-client portmap nfs-utils pcsc-lite ccid coolkey ifd-egate pcsc-lite-libs psacct nscd nss_ldap avahi avahi-glib ibmasm rdist conman xinetd samba* php*"

echo -e "\n*****************************************************************"
echo -e "Configuring OS (SELinux, timezone)"
echo -e "*****************************************************************\n"

rm -f /etc/localtime >/dev/null 2>&1
unlink /etc/localtime >/dev/null 2>&1
ln -s /usr/share/zoneinfo/America/Montreal /etc/localtime >/dev/null 2>&1
echo "Timezone set to Montreal."
sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config >/dev/null 2>&1
echo "SELinux disabled. Need to reboot."


echo -e "\n*****************************************************************"
echo -e "Disabling services and stopping default services.."
echo -e "*****************************************************************\n"

for service in $SERVICES; do
/sbin/chkconfig --level 2345 $service off >/dev/null 2>&1
done

/etc/init.d/auditd stop 3>&1 4>&2 >>$BUILDLOG 2>&1
/etc/init.d/httpd stop 3>&1 4>&2 >>$BUILDLOG 2>&1
/etc/init.d/xinetd stop 3>&1 4>&2 >>$BUILDLOG 2>&1
/etc/init.d/saslauthd stop 3>&1 4>&2 >>$BUILDLOG 2>&1
/etc/init.d/iptables stop 3>&1 4>&2 >>$BUILDLOG 2>&1
/etc/init.d/sendmail stop 3>&1 4>&2 >>$BUILDLOG 2>&1
echo "All unused services have been stopped and removed from boot."

echo -e "\n*****************************************************************"
echo -e "Removing useless rpms.."
echo -e "*****************************************************************\n"

yum clean all 3>&1 4>&2 >>$BUILDLOG 2>&1
yum remove -y $RPMS 3>&1 4>&2 >>$BUILDLOG 2>&1
yum remove -y *.i386 3>&1 4>&2 >>$BUILDLOG 2>&1
rm -f /root/anaconda-ks.cfg  /root/install.log  /root/install.log.syslog 3>&1 4>&2 >>$BUILDLOG 2>&1
echo "Yum cleared. Unused packages and all i386 packages have been removed."

echo -e "\n*****************************************************************"
echo -e "Updating packages.."
echo -e "*****************************************************************\n"

yum -y update 3>&1 4>&2 >>$BUILDLOG 2>&1
echo "All installed packages have been updated."

echo -e "\n*****************************************************************"
echo -e "Installing EPEL and Aeris repos.."
echo -e "*****************************************************************\n"

yum install -y $URL/repos/epel-release-6-5.noarch.rpm 3>&1 4>&2 >>$BUILDLOG 2>&1
yum install -y $URL/repos/aeris-release-1.0-1.el6.noarch.rpm 3>&1 4>&2 >>$BUILDLOG 2>&1
sed -i '/enabled\=1/a exclude\=nginx*,monit*' /etc/yum.repos.d/epel.repo 
echo "EPEL and Aeris repos installed for usefull packages."
echo "Disabling nginx and monit from EPEL for better version in Aeris."

echo -e "\n*****************************************************************"
echo -e "Installing usefull packages and directories.."
echo -e "*****************************************************************\n"

yum install -y bc bind-utils gcc gcc-c++ file git htop iftop iotop hdparm make mtr mutt nc nethogs openssh-clients pbzip2 perl pigz postfix pv rsync screen strace sysbench 3>&1 4>&2 >>$BUILDLOG 2>&1
yum remove -y sendmail 3>&1 4>&2 >>$BUILDLOG 2>&1
/etc/init.d/postfix start 3>&1 4>&2 >>$BUILDLOG 2>&1
chkconfig postfix on
echo "All packages have been installed. Sendmail switched for postfix."
chmod 775 /var/run/screen
mkdir -p /opt/scripts
mkdir -p /opt/src
echo "Directory /opt/scripts and /opt/src created."

echo -e "\n*****************************************************************"
echo -e "Installing public keys and SSH port 2222.."
echo -e "*****************************************************************\n"

mkdir /root/.ssh
echo $sshkey > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
sed -i "s/\#Port\ 22/Port\ 2222/g" /etc/ssh/sshd_config
/etc/init.d/auditd stop >/dev/null 2>&1
restorecon /root/.ssh/authorized_keys
/etc/init.d/sshd restart >/dev/null 2>&1
echo "SSH keys installed, port 2222 activated, auditd stopped to make SSH key works."

echo -e "\n*****************************************************************"
echo -e "Benchmarking.."
echo -e "*****************************************************************\n"

echo -e "Benchmarking / partition with dd.."
DD=`dd bs=1M count=512 \if=/dev/zero of=/root/benchtestfile conv=fdatasync|& awk '/copied/ {print $8 " "  $9}'`
rm -f /root/benchtestfile
echo -e "Writing speed on / partition is: $DD\n"

echo -e "Benchmarking CPU with 400 request at 20000 max prime.."
syscpu=`sysbench --test=cpu --cpu-max-prime=20000 --max-requests=400 run|grep approx| awk '{print $4}'`
echo -e "Average CPU time per-request : $syscpu\n"

echo -e "Benchmarking network with 10mbps file on Cachefly.."
echo -e "Speed is \c"
echo "scale=2; `curl --silent -w "%{speed_download}" -o /dev/null "http://cachefly.cachefly.net/10mb.test"` / 131072" | bc | xargs -I {} echo {}Mb\/s


echo -e "\n*****************************************************************"
echo -e "Detecting virtualization and IP.."
echo -e "*****************************************************************\n"

### Virtualization ###

yum install -y virt-what 3>&1 4>&2 >>$BUILDLOG 2>&1

VIRT=`virt-what |head -n1`

if [ "$VIRT" == "xen" ];
	then
    	echo -e "We seem to be on a Xen domU. Checking IP..\n"
elif [ "$VIRT" == "openvz" ];
	then
    	echo -e "We seem to be on an OpenVZ container. Checking IP..\n"
elif [ "$VIRT" == "kvm" ];
	then
	    echo -e "We seem to be on KVM. Checking IP..\n"
elif [ "$VIRT" == "vmware" ];
	then
	    echo -e "We seem to be on VMware. Checking IP..\n"
else
		echo -e "No virtualization detected, we seem to be on a dedicated server. Checking IP..\n"
		VIRT="node"
fi

read -p "Script has detected that we are running $VIRT on IP address $IP. Is that correct? (Y/n) " -e VIRT_INPUT

case "$VIRT_INPUT" in
        n)
		read -p "Enter the right virtualization (openvz|xen|kvm|vmware|node):" -e VIRT;
		read -p "Enter the right IP:" -e IP;
		;;
		*)
        ;;
esac

echo -e "\n*****************************************************************"
echo -e "Last configurations depending on virtualization: $VIRT"
echo -e "*****************************************************************\n"

### Guest Server ###

if [ "$VIRT" == "openvz" ] || [ "$VIRT" == "xen" ] || [ "$VIRT" == "kvm" ] || [ "$VIRT" == "vmware" ]; then
	echo "vm.swappiness = 1" >> /etc/sysctl.conf
	echo "Swappiness done."
	wget -O /opt/scripts/mysqltuner.pl $URL/scripts/mysqltuner.pl 3>&1 4>&2 >>$BUILDLOG 2>&1
	chmod +x /opt/scripts/mysqltuner.pl
	echo "MySQL Tuner script done."
	wget -O /opt/scripts/backup-mysql.sh $URL/scripts/backup-mysql.sh 3>&1 4>&2 >>$BUILDLOG 2>&1
	chmod +x /opt/scripts/backup-mysql.sh
	echo "MySQL Backup script done."
fi

if [ "$VIRT" == "vmware" ]; then

    echo "Need to install vmware tools...."	
	#yum install -y -q http://packages.vmware.com/tools/esx/5.0latest/repos/vmware-tools-repo-RHEL6-8.6.12-1.el6.x86_64.rpm
	#yum install -y -q http://packages.vmware.com/tools/esx/5.1latest/repos/vmware-tools-repo-RHEL6-9.0.10-1.el6.x86_64.rpm
	#yum install -y -q http://packages.vmware.com/tools/esx/5.5latest/repos/vmware-tools-repo-RHEL6-9.4.5-1.el6.x86_64.rpm
	#yum install -y -q vmware-tools-esx-nox

fi


### Custom guest virtualization rules ###

if [ "$VIRT" == "xen" ] || [ "$VIRT" == "kvm" ] || [ "$VIRT" == "vmware" ]; then
	echo "/usr/sbin/ntpdate -b ca.pool.ntp.org" >> /etc/rc.local
	echo -e "NTP added."
	echo "/sbin/ethtool --offload eth0 gso off tso off tx off sg off gro off" >> /etc/rc.local
	echo "ehtool opmitization to eth0 added."
	echo -e "\nYou should consider adding the following parameters to grub/fstab: elevator=noop / nohz=off / noatime"

fi


### Node Server ###

if [ "$VIRT" == "node" ]; then
	echo "vm.swappiness = 1" >> /etc/sysctl.conf
	echo -e "Swappiness done."
	echo "Installing few packages for node.."
	yum install -y kpartx lm_sensors ipmitool 3>&1 4>&2 >>$BUILDLOG 2>&1
	yum install -y ebtables 3>&1 4>&2 >>$BUILDLOG 2>&1
	echo "Ebtables installed, need for IP stealing."
	sed -i "s/\Port\ 2222/Port\ 25000/g" /etc/ssh/sshd_config
	/etc/init.d/sshd restart 3>&1 4>&2 >>$BUILDLOG 2>&1
	echo "SSH port switched to 25000."
	echo "/usr/sbin/ntpdate -b ca.pool.ntp.org" >> /etc/rc.local
	echo -e "NTP added."
	echo -e "\nYou should consider adding the following parameters to grub/fstab: elevator=deadline / nohz=off / noatime."
	echo -e "You should also consider adding the drive/raid optmization in rc.local."
	echo -e "If the node has a LSI controller, install MegaCli and add megacli/smartX to /etc/profile."
	echo -e "If the node is a Xen dom0, add ethtool command to /etc/rc.local."
fi

}


################################################################################################
######################################## Notify ################################################

function notify {
	rm -f /root/centos6.sh
	if [ -f /usr/bin/mutt ]; then
		echo -e "A new server has been built. Here's the debug log attached." | mutt -a "$BUILDLOG" -s "New server builded: `hostname`" -- kj@aeris.pro
		echo -e "\nAn email of the build as been sent to kj@aeris.pro. Please mannualy clear history with history -c\n"
		rm -f $BUILDLOG
		rm -f /root/sent
	else
		echo -e "\nMutt is't installed so we cannot send a report email. Please see $BUILDLOG\nPlease mannualy clear history with history -c\n"
	fi
	cat /dev/null > /root/.bash_history
}


################################################################################################
#################################### Script Startup ############################################

echo -e "\n*****************************************************************"
echo -e "CentOS 6 64bits post-installer by kjohnson@aerisnetwork.com"
echo -e "for NEW installation only, hit ctrl-c to cancel."
echo -e "*****************************************************************\n"

INT=3
for i in `seq 1 3`;
do
        sleep 1
        echo -e $INT
        INT=$((INT-1))
done

if [[ `cat /etc/redhat-release | awk '{print$1,$3}' | rev | cut -c 3- | rev` == "CentOS 6" ]] && [[ `uname -p` == "x86_64" ]]; then

	selection=
	until [ "$selection" = "0" ]; do
		echo -e "\n******************** CentOS 6 Builder ********************\n"
		echo -e "Server: `hostname`"
		echo -e "IP: $IP\n"
		echo -e "[1] Clean and optimize the OS"
		echo -e "[2] Proceed with cPanel"
		echo -e "[3] Proceed with LAMP 53/54/55/56"
		echo -e "[4] Proceed with LEMP 53/54/55/56"
		echo -e "[5] Proceed with Zimbra"
		echo -e "[6] Proceed with FreePBX\n"
		echo -e "[0] Quit builder"
		echo -e "\n**********************************************************\n"
	    echo -n "Enter selection: "
	    read selection
	    echo ""
	    case $selection in
			1 ) cleanup;enter ;;
			2 ) cpanel;enter ;;
		    3 ) lamp;enter ;;
			6 ) freepbx;enter ;;
			0 ) notify;exit ;;
		    * ) echo "Please enter 1, 2, 3, 4, 5, 6 or 0"
	    esac
	done

else
	echo -e "\nNot on CentOS 6 64bits, please reinstall -.- \n"
fi

