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
  apt-get -y install -y software-properties-common
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
setup_motd;
