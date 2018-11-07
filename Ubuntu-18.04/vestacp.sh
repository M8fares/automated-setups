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


# Generate password for the Vesta Control Panel admin user
VESTA_PASS=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32) || true

# Install Vesta Control Panel
function install_vestacp(){
  apt-add-repository universe

  curl -O http://vestacp.com/pub/vst-install.sh
  bash vst-install.sh --nginx yes --phpfpm yes --apache no --named yes --remi no \
    --vsftpd yes --proftpd no --iptables yes --fail2ban yes --quota no \
    --exim yes --dovecot yes --spamassassin yes --clamav yes --softaculous no \
    --mysql yes --postgresql no --hostname "$(hostname -I | cut -f1 -d' ')" \
    --email admin@example.com --password "${VESTA_PASS}" <<CMD_EOF
y
CMD_EOF
}

# Add a message to login motd, with credentials script created
function setup_motd(){
  local MOTD_FILE='/etc/update-motd.d/99-credentials'
  cat >"${MOTD_FILE}" <<CMD_EOF
#!/bin/bash
echo 'Vesta Control Panel Login Credentials'
echo 'You can login at https://$(hostname -I | cut -f1 -d" "):8083/'
echo 'Use username/password: admin/${VESTA_PASS}'
CMD_EOF
  chmod +x "${MOTD_FILE}"
}

# Install cURL
apt-get install -y curl


install_vestacp;
setup_motd;
