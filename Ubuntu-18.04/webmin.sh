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


# Install Webmin
function install_webmin(){

  # Universe is required for php-fpm
  apt-add-repository universe

  echo "deb http://download.webmin.com/download/repository sarge contrib" > /etc/apt/sources.list.d/webmin.list
  wget -qO - http://www.webmin.com/jcameron-key.asc | apt-key add -
  apt-get -y update
  apt-get -y install webmin
}

# Add a message to login motd, with credentials script created
function setup_motd(){
  local MOTD_FILE='/etc/update-motd.d/99-credentials'
  cat >"${MOTD_FILE}" <<CMD_EOF
#!/bin/bash
echo 'Webmin install complete.'
echo 'You can now login to https://$(hostname -I | cut -f1 -d" "):10000/'
echo 'as root with your root password, or as any user '
echo 'who can use sudo to run commands as root.'
CMD_EOF
  chmod +x "${MOTD_FILE}"
}


install_webmin;
setup_motd;
