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

# Update YUM
function yum_update(){
  yum update -y
}


# Install EPEL Repo
function epel_release(){
  yum install -y epel-release
}


# Install and Enable Remi's RPM repository
function enable_remi_repo(){
  yum install -y yum-utils
  yum install -y http://rpms.remirepo.net/enterprise/remi-release-7.rpm
}

# Install cPanel
function install_cpanel(){
  yum install -y wget perl bzip2 rdate yum-plugin-fastestmirror

  # cPanel does not support NetworkManager enabled systems
  systemctl stop NetworkManager
  systemctl disable NetworkManager

  # Set a dummy domain
  hostname cpanel.example.com

  # Download and run cPanel installer
  curl -o /tmp/latest -L https://securedownloads.cpanel.net/latest
  sh /tmp/latest
  rm -f /tmp/latest
}

# Add a message to login motd, with credentials script created
function setup_motd(){
  local MOTD_FILE='/etc/update-motd.d/99-credentials'
  cat >"${MOTD_FILE}" <<CMD_EOF
#!/bin/bash
echo 'cPanel install complete.'
echo 'You can login with your root password to WHM at'
echo 'https://$(hostname -I | cut -f1 -d" "):2087/'
CMD_EOF
  chmod +x "${MOTD_FILE}"
}


yum_update;
epel_release;
enable_remi_repo;
install_cpanel;
setup_motd;
