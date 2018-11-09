#!/bin/bash

# ==============================================================================
# The MIT License (MIT)
#
# Copyright (c) 2017-2018 NorseStack LTD (United Kingdom)
# Email: contact@norsestack.com
# GitHub: https://github.com/norsestack
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ==============================================================================

set -Eeuo pipefail


# Update and Upgrade APT
apt-get -y update
apt-get -y upgrade


# Generate MySQL password for 'root'@'localhost'
MYSQL_PASS=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32) || true

MG_DB='magento'
MG_USER='magentouser'
MG_PASS=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32) || true

MG_ADMIN='magentoadmin'
MG_ADMIN_PASS=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32) || true

function lemp(){
  # Add 'Universe' repository for libmcrypt4
  apt-get -y install software-properties-common
  add-apt-repository -y universe
  # Needed for php7.0 (magento dependency)
  add-apt-repository -y ppa:ondrej/php
  apt update -y

  debconf-set-selections <<< "mysql-server mysql-server/root_password password ${MYSQL_PASS}"
  debconf-set-selections <<< "mysql-server mysql-server/root_password_again password ${MYSQL_PASS}"

  DEBIAN_FRONTEND=noninteractive apt-get -y install nginx mysql-server mysql-client php7.0-fpm php7.0-mysql

  # Enable passwordless mysql command execution
  cat >/root/.my.cnf <<CMD_EOF
[mysql]
user=root
password=${MYSQL_PASS}
CMD_EOF

  PHP_VER=$(php -v | head -1 | cut -f2 -d' ' | cut -f1,2 -d.)
  cat >/etc/nginx/conf.d/fpm.conf <<CMD_EOF
upstream php-handler {
  server unix:///run/php/php${PHP_VER}-fpm.sock;
}
CMD_EOF

  # Uncomment PHP section
  pushd /etc/nginx/sites-available
  sed -i.save '/location ~ \\\.php\$ {/,/#}/ s/#//' default
  sed -i.save '/location ~ \\\.php\$ {/,/#}/ {/fastcgi_pass 127/d}' default
  sed -i.save '/location ~ \\\.php\$ {/,/#}/ s/fastcgi_pass unix.*/fastcgi_pass fastcgi_backend;/' default
  rm -f default.save
  popd

  # Increase limits for PHP
  cat >"/etc/php/${PHP_VER}/fpm/conf.d/99-limits.conf" <<EOF
upload_max_filesize = 2048M
post_max_size = 32M
memory_limit = 256M
EOF

  systemctl reload nginx
}

function install_magento(){
  # php7.0-mcrypt
  apt-get -y install php7.0-common php7.0-gd php7.0-curl php7.0-intl php7.0-xsl \
    php7.0-mbstring php7.0-zip php7.0-iconv php7.0-mcrypt php7.0-bcmath \
    php7.0-soap unzip

  mysql -u root <<CMD_EOF
CREATE DATABASE ${MG_DB};
GRANT ALL PRIVILEGES ON ${MG_DB}.* TO '${MG_USER}'@'localhost' IDENTIFIED BY '${MG_PASS}';
CMD_EOF

  # Download app
  curl -L https://github.com/magento/magento2/archive/2.2.zip >/tmp/2.2.zip
  pushd /var/www/
  unzip /tmp/2.2.zip
  mv magento2-* magento
  rm -f /tmp/2.2.zip
  popd

  useradd magento
  usermod -g www-data magento

  # Setup file access
  pushd /var/www/magento
  find var vendor pub/static pub/media app/etc -type f -exec chmod g+w {} \;
  find var vendor pub/static pub/media app/etc -type d -exec chmod g+ws {} \;
  chown -R magento:www-data .
  chmod u+x bin/magento
  popd

  # Setup web server conf
  cat >/etc/nginx/sites-available/magento <<CMD_EOF
server {
     listen 80;
     server_name $(hostname -I | cut -f1 -d' ');
     set \$MAGE_ROOT /var/www/magento;
     include /var/www/magento/nginx.conf.sample;
}
CMD_EOF

  rm -f /etc/nginx/sites-enabled/default
  ln -s /etc/nginx/sites-available/magento /etc/nginx/sites-enabled/magento
  systemctl restart nginx

  # Note: distro composer requires distro PHP
  curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/bin --filename=composer

  # Install deps and magento
  pushd /var/www/magento
  composer install -v
  chown -R magento:www-data .

  pushd /var/www/magento/bin
  sudo -u magento ./magento setup:install --admin-firstname="John" --admin-lastname="Doe" \
    --admin-email="your@email.com" \
    --admin-user="${MG_ADMIN}" --admin-password="${MG_ADMIN_PASS}" \
    --db-name="${MG_DB}" --db-host="localhost" --db-user="${MG_USER}" \
    --db-password="${MG_PASS}"
  MG_ADMIN_URI=$(./magento info:adminuri | grep 'URI:' | cut -f2 -d/)
  popd
  popd

  # Setup cron jobs
  cat >/etc/cron.d/magento <<CMD_EOF
  * * * * * magento /usr/bin/php /var/www/magento/bin/magento cron:run | grep -v "Ran jobs by schedule" >> /var/www/magento/var/log/magento.cron.log
  * * * * * magento /usr/bin/php /var/www/magento/update/cron.php >> /var/www/magento/var/log/update.cron.log
  * * * * * magento /usr/bin/php /var/www/magento/bin/magento setup:cron:run >> /var/www/magento/var/log/setup.cron.log
CMD_EOF

  # Improve security
  pushd /var/www/magento
  sed -i.save "s/'x-frame-options'.*/'x-frame-options' => 'DENY',/" app/etc/env.php
  find app/etc -type f -exec chmod g-w {} \;
  find app/etc -type d -exec chmod g-ws {} \;
  popd
}


# Hardening PHP for better security
function hardening_php(){
  PHP_VER=$(php -v | head -1 | cut -f2 -d' ' | cut -f1,2 -d.)
  cat >"/etc/php/${PHP_VER}/fpm/conf.d/99-hardening.conf" <<CMD_EOF
# Disable functions globally
disable_functions = _getppid,allow_url_fopen,allow_url_include,chgrp,chmod,chown,curl_exec,curl_multi_exec,diskfreespace,dl,exec,fpaththru,getmypid,getmyuid,highlight_file,ignore_user_abord,ini_set,lchgrp,lchown,leak,link,listen,parse_ini_file,passthru,pcntl_exec,php_uname,phpinfo,popen,posix,posix_ctermid,posix_getcwd,posix_getegid,posix_geteuid,posix_getgid,posix_getgrgid,posix_getgrnam,posix_getgroups,posix_getlogin,posix_getpgid,posix_getpgrp,posix_getpid,posix_getpwnam,posix_getpwuid,posix_getrlimit,posix_getsid,posix_getuid,posix_isatty,posix_kill,posix_mkfifo,posix_setegid,posix_seteuid,posix_setgid,posix_setpgid,posix_setsid,posix_setuid,posix_times,posix_ttyname,posix_uname,proc_close,proc_get_status,proc_nice,proc_open,proc_terminate,putenv,set_time_limit,shell_exec,show_source,source,system,tmpfile,virtual

# Prevent setting of undeletable session ID cookies
session.use_strict_mode = 1

# Allows access to session ID cookie only when protocol is HTTPS
session.cookie_secure = 1
CMD_EOF

  # Limit FPM to .php extension to prevent malicious users to use other extensions to execute php code.
  PHP_CONF="/etc/php/${PHP_VER}/fpm/pool.d/www.conf"
  if grep -m 1 -c 'security.limit_extensions' "${PHP_CONF}" >/dev/null; then
    sed -i.save 's/security.limit_extensions.*/security.limit_extensions = .php/' "${PHP_CONF}"
  else
    echo 'security.limit_extensions = .php' >> "${PHP_CONF}"
  fi

  PHP_CONF="/etc/php/$PHP_VER/fpm/php.ini"

  # Disable PATH_INFO
  if grep -m 1 -c 'cgi.fix_pathinfo' "${PHP_CONF}" >/dev/nulls; then
    sed -i.save 's/cgi.fix_pathinfo.*/cgi.fix_pathinfo = 0/' "${PHP_CONF}"
  else
    echo 'cgi.fix_pathinfo = 0' >> "${PHP_CONF}"
  fi

  # Disable Fopen wrappers
  if grep -m 1 -c 'allow_url_fopen' "${PHP_CONF}" >/dev/null; then
    sed -i.save 's/allow_url_fopen.*/allow_url_fopen = Off/' "${PHP_CONF}"
  else
    echo 'allow_url_fopen = Off' >> "${PHP_CONF}"
  fi

  if grep -m 1 -c 'allow_url_include' "${PHP_CONF}" >/dev/null; then
    sed -i.save 's/allow_url_include.*/allow_url_include = Off/' "${PHP_CONF}"
  else
    echo 'allow_url_include = Off' >> "${PHP_CONF}"
  fi
}


# Add a message to login motd, with credentials script created
function setup_motd(){
  local MOTD_FILE='/etc/update-motd.d/99-credentials'
  cat >"${MOTD_FILE}" <<CMD_EOF
#!/bin/bash
echo '### Information for your server ###'
echo "Your site: http://$(hostname -I | cut -f1 -d' ')/${MG_ADMIN_URI}"
echo 'MySQL root password: ${MYSQL_PASS}'
echo 'Magento db user/pass: ${MG_USER}/${MG_PASS}'
echo 'Magento admin user/pass: ${MG_ADMIN}/${MG_ADMIN_PASS}'
echo "NOTE: Don't forget to update your Magento name/email!"
echo '### (To remove this message delete ${MOTD_FILE}) ###'
CMD_EOF
  chmod +x "${MOTD_FILE}"
}


lemp;
install_magento;
hardening_php;
setup_motd;
