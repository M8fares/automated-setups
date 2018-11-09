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

# LEMP Stack
function lemp(){
  # Add 'Universe' repository for php-fpm
  apt-get -y install software-properties-common
  apt-add-repository universe

  # Set previously generated password for 'root'@'localhost'
  debconf-set-selections <<< "mysql-server mysql-server/root_password password ${MYSQL_PASS}"
  debconf-set-selections <<< "mysql-server mysql-server/root_password_again password ${MYSQL_PASS}"

  # Install Linux, NGINX, MySQL and PHP (LEMP)
  DEBIAN_FRONTEND=noninteractive apt-get -y install nginx mysql-server mysql-client php-fpm php-mysql

  # Enable passwordless MySQL command execution
  cat >/root/.my.cnf <<CMD_EOF
[mysql]
user=root
password=${MYSQL_PASS}
CMD_EOF

  # Setting up php-fpm socket
  PHP_VER=$(php -v | head -1 | cut -f2 -d' ' | cut -f1,2 -d.)
  cat >/etc/nginx/conf.d/fpm.conf <<CMD_EOF
upstream php-handler {
server unix:///run/php/php${PHP_VER}-fpm.sock;
}
CMD_EOF

  # Uncomment PHP section in NGINX default configuration
  pushd /etc/nginx/sites-available
  sed -i.save '/location ~ \\\.php\$ {/,/#}/ s/#//' default
  sed -i.save '/location ~ \\\.php\$ {/,/#}/ {/fastcgi_pass 127/d}' default
  sed -i.save '/location ~ \\\.php\$ {/,/#}/ s/fastcgi_pass unix.*/fastcgi_pass php-handler;/' default
  rm -f default.save
  popd

  # Increase limits for PHP
  cat >"/etc/php/${PHP_VER}/fpm/conf.d/99-limits.conf" <<EOF
upload_max_filesize = 2048M
post_max_size = 32M
memory_limit = 256M
EOF

  # Reload NGINX and PHP service
  systemctl reload php${PHP_VER}-fpm
  systemctl reload nginx
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


function install_mysql(){

  debconf-set-selections <<< "mysql-server mysql-server/root_password password ${MYSQL_PASS}"
  debconf-set-selections <<< "mysql-server mysql-server/root_password_again password ${MYSQL_PASS}"

  DEBIAN_FRONTEND=noninteractive apt-get -y install mysql-server mysql-client

  systemctl enable mysql
}

function configure_mysql(){
  # Get available memory
  VM_MEM=$(free -m | grep -i mem: | sed 's/[ \t]\+/ /g' | cut -f7 -d' ')

  # 512MB, 1GB, 2GB, 3GB, 4GB, 8GB, 16GB, 32GB, 48GB, 64GB, 96GB, 128GB and 192GB
  keys=(key_buffer_size max_allowed_packet thread_stack thread_cache_size query_cache_limit query_cache_size)
  values=(16M 16M 192K 8 1M 16M)
  if [  "${VM_MEM}"  -lt 512 ]; then     values=(256M   32M   192K 8 8M   32M)
  elif [ "${VM_MEM}" -lt 1024 ]; then    values=(512M   64M   192K 8 16M  64M)
  elif [ "${VM_MEM}" -lt 2048 ]; then    values=(1G     128M  192K 8 32M  128M)
  elif [ "${VM_MEM}" -lt 3072 ]; then    values=(1500M  190M  192K 8 48M  190M)
  elif [ "${VM_MEM}" -lt 4096 ]; then    values=(2G     256M  192K 8 64M  256M)
  elif [ "${VM_MEM}" -lt 8192 ]; then    values=(4G     512M  192K 8 128M 512M)
  elif [ "${VM_MEM}" -lt 16384 ]; then   values=(8G     1G    192K 8 256M 1G)
  elif [ "${VM_MEM}" -lt 32768 ]; then   values=(16G    2G    192K 8 512M 2G)
  elif [ "${VM_MEM}" -lt 49152 ]; then   values=(32G    4G    192K 8 1G   3G)
  elif [ "${VM_MEM}" -lt 65536 ]; then   values=(48G    4G    192K 8 2G   4G)
  elif [ "${VM_MEM}" -lt 98304 ]; then   values=(80G    4G    192K 8 3G   6G)
  elif [ "${VM_MEM}" -lt 131072 ]; then  values=(90G    8G    192K 8 4G   16G)
  elif [ "${VM_MEM}" -lt 196608 ]; then  values=(140G   16G   192K 8 5G   32G)
  fi

  # Update MySQL configuration
  MYCNF=/etc/mysql/mysql.conf.d/mysqld.cnf
  ((KEY_COUNT=${#keys[@]}-1))
  for i in $(seq 0 $KEY_COUNT); do
    sed -i.save "s/^${keys[$i]}.*/${keys[$i]}=${values[$i]}/" ${MYCNF}
  done
  rm -f ${MYCNF}.save
}

# Install phpMyAdmin
function install_phpmyadmin(){
  PHPMYADMIN_URL=$(curl -s https://www.phpmyadmin.net/downloads/ | sed -n 's/.*href="\(https:\/\/files.phpmyadmin.net\/phpMyAdmin\/[0-9\.]\+\/phpMyAdmin-[0-9\.]\+-all-languages.tar.xz\).*/\1/p' | head -1)
  PHPMYADMIN_FILE=$(basename "${PHPMYADMIN_URL}")
  curl -L "${PHPMYADMIN_URL}" >"/tmp/${PHPMYADMIN_FILE}"

  pushd /var/www/html
  tar -xf "/tmp/${PHPMYADMIN_FILE}"
  rm -f "/tmp/${PHPMYADMIN_FILE}"

  PHPMYADMIN_DIR="${PHPMYADMIN_FILE//.tar.gz/}"
  mv "${PHPMYADMIN_DIR}" phpMyAdmin
  chown -R www-data:www-data phpMyAdmin
  popd

  systemctl reload nginx
}

# Add a message to login motd, with credentials script created
function setup_motd(){
  local MOTD_FILE='/etc/update-motd.d/99-credentials'
  cat >"${MOTD_FILE}" <<CMD_EOF
#!/bin/bash
echo '### Information for your server ###'
echo 'Your site: http://$(hostname -I | cut -f1 -d' ')/'
echo 'MySQL root password: ${MYSQL_PASS}'
echo '### (To remove this message delete ${MOTD_FILE}) ###'
CMD_EOF
  chmod +x "${MOTD_FILE}"
}


lemp;
hardening_php;
install_mysql;
configure_mysql;
install_phpmyadmin;
setup_motd;
