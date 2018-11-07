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

# Add a message to login motd, with credentials script created
function setup_motd(){
  local MOTD_FILE=/etc/update-motd.d/99-credentials
  cat >"${MOTD_FILE}" <<CMD_EOF
#!/bin/bash
echo "### Information for your server ###"
echo "MySQL root password: ${MYSQL_PASS}"
echo "### (To remove this message delete ${MOTD_FILE}) ###"
CMD_EOF
  chmod +x "${MOTD_FILE}"
}


install_mysql;
configure_mysql;
setup_motd;
