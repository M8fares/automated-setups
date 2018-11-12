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


function install_docker(){
  apt-get -y install apt-transport-https ca-certificates curl software-properties-common
  curl -sSL https://get.docker.com/ | CHANNEL=stable sh

  # add docket compose
  LATEST_VER=$(curl https://github.com/docker/compose/releases/latest | sed 's/.*\/releases\/tag\/\([0-9\.]\+\).*/\1/')
  curl -L "https://github.com/docker/compose/releases/download/${LATEST_VER}/docker-compose-$(uname -s)-$(uname -m)" >/usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
}

# Add a message to login motd, with credentials script created
function setup_motd(){
  local MOTD_FILE='/etc/update-motd.d/99-credentials'
  cat >"${MOTD_FILE}" <<CMD_EOF
#!/bin/bash
echo '### Information for your server ###'
echo 'Learn more about Docker at https://docs.docker.com/'
echo '### (To remove this message delete ${MOTD_FILE}) ###'
CMD_EOF
  chmod +x "${MOTD_FILE}"
}


install_docker;
setup_motd;
