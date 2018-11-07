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


NC_ADMIN_PASS=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32) || true
NC_PASS=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32) || true
NC_DB='ncloud'
NC_USER='ncuser'

function install_nextcloud(){
  mysql -u root <<CMD_EOF
CREATE DATABASE ${NC_DB};
GRANT ALL PRIVILEGES ON ${NC_DB}.* TO '${NC_USER}'@'localhost' IDENTIFIED BY '${NC_PASS}';
FLUSH PRIVILEGES;
CMD_EOF

  apt-get -y install unzip

  curl https://download.nextcloud.com/server/releases/latest-14.zip >/tmp/latest-14.zip
  unzip /tmp/latest-14.zip -d /var/www/
  rm -f /tmp/latest-14.zip

  mkdir /var/www/nextcloud/data
  chown -R www-data:www-data /var/www/nextcloud

  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/nextcloud-selfsigned.key \
    -out /etc/ssl/certs/nextcloud-selfsigned.crt <<CMD_EOF
AU
Some-State
City

Unit
$(hostname -f)


CMD_EOF

  # Replace nginx root with Nextcloud
  cat >/etc/nginx/sites-available/nextcloud <<CMD_EOF
server {
  listen 80;
  listen [::]:80;
  server_name $(hostname -i | cut -f1 -d' ');
  # enforce https
  return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $(hostname -i | cut -f1 -d' ');

    ssl_certificate /etc/ssl/certs/nextcloud-selfsigned.crt;
    ssl_certificate_key /etc/ssl/private/nextcloud-selfsigned.key;

    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header X-Download-Options noopen;
    add_header X-Permitted-Cross-Domain-Policies none;

    # Path to the root of your installation
    root /var/www/nextcloud/;

    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    # The following 2 rules are only needed for the user_webfinger app.
    # Uncomment it if you're planning to use this app.
    #rewrite ^/.well-known/host-meta /public.php\?service=host-meta last;
    #rewrite ^/.well-known/host-meta.json /public.php\?service=host-meta-json
    # last;

    location = /.well-known/carddav {
      return 301 \$scheme://\$host/remote.php/dav;
    }
    location = /.well-known/caldav {
      return 301 \$scheme://\$host/remote.php/dav;
    }

    # set max upload size
    client_max_body_size 512M;
    fastcgi_buffers 64 4K;

    # Enable gzip but do not remove ETag headers
    gzip on;
    gzip_vary on;
    gzip_comp_level 4;
    gzip_min_length 256;
    gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
    gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;

    location / {
        rewrite ^ /index.php\$uri;
    }

    location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)/ {
        deny all;
    }
    location ~ ^/(?:\\.|autotest|occ|issue|indie|db_|console) {
        deny all;
    }

    location ~ ^/(?:index|remote|public|cron|core/ajax/update|status|ocs/v[12]|updater/.+|ocs-provider/.+)\\.php(?:\$|/) {
        fastcgi_split_path_info ^(.+\\.php)(/.*)\$;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_param HTTPS on;
        #Avoid sending the security headers twice
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_pass php-handler;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
    }

    location ~ ^/(?:updater|ocs-provider)(?:\$|/) {
        try_files \$uri/ =404;
        index index.php;
    }

    # Adding the cache control header for js and css files
    # Make sure it is BELOW the PHP block
    location ~ \\.(?:css|js|woff|svg|gif)\$ {
        try_files \$uri /index.php\$uri\$is_args\$args;
        add_header Cache-Control "public, max-age=15778463";
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header X-Robots-Tag none;
        add_header X-Download-Options noopen;
        add_header X-Permitted-Cross-Domain-Policies none;
        # Optional: Don't log access to assets
        access_log off;
    }

    location ~ \.(?:png|html|ttf|ico|jpg|jpeg)\$ {
        try_files \$uri /index.php\$uri\$is_args\$args;
        # Optional: Don't log access to other assets
        access_log off;
    }
}
CMD_EOF

  ln -s /etc/nginx/sites-available/nextcloud /etc/nginx/sites-enabled/nextcloud
  rm -f /etc/nginx/sites-enabled/default

  systemctl reload nginx

  apt-get install -y php-mysql php-mbstring php-gd php-json php-xml php-zip php-curl php-pear php-intl bzip2

  pushd /var/www/nextcloud
  sudo -u www-data php occ  maintenance:install --database "mysql" --database-name "${NC_DB}" \
    --database-user "${NC_USER}" --database-pass "${NC_PASS}" \
    --admin-user "admin" --admin-pass "${NC_ADMIN_PASS}"

  sed -i.save "/0 => 'localhost',/a\1 => '$(hostname -i | cut -f1 -d' ')'," config/config.php
  popd


}

# Add a message to login motd, with credentials script created
function setup_motd(){
  local MOTD_FILE='/etc/update-motd.d/99-credentials'
  cat >"${MOTD_FILE}" <<CMD_EOF
#!/bin/bash
echo '### Information for your server ###'
echo 'Your site: https://$(hostname -I | cut -f1 -d' ')/'
echo 'NextCloud user/pass: ${NC_USER}/${NC_PASS}'
echo 'NextCloud db: ${NC_DB}'
echo 'NextCloud admin pass: ${NC_ADMIN_PASS}'
echo 'MySQL root password: ${MYSQL_PASS}'
echo '### (To remove this message delete ${MOTD_FILE}) ###'
CMD_EOF
  chmod +x "${MOTD_FILE}"
}


lemp;
hardening_php;
install_nextcloud;
setup_motd;
