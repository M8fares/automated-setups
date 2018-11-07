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


# Define the Minecraft username
MC_USER='mcrafter'

function install_minecraft(){

  # Install Java Runtime Environment and Screen
  apt-get install -y default-jre-headless screen

  useradd -m "${MC_USER}"

  pushd /home/${MC_USER}
  curl 'https://minecraft.net/en-us/download/server/' >/tmp/page.html

  MC_URL=$(sed -n 's/.*href="\(https:\/\/.*\/server\.jar\)">minecraft_server.[0-9\.]\+.jar<\/a>.*/\1/p' /tmp/page.html)
  MC_VER=$(sed -n 's/.*minecraft_server.\([0-9\.]\+\).jar.*/\1/p' /tmp/page.html | head -1)

  curl -L "${MC_URL}" >"minecraft_server.${MC_VER}.jar"

  MC_CMD=$(sed -n "s/.*\(java .* -jar minecraft_server.${MC_VER}.jar.*\)<\/.*/\1/p" /tmp/page.html)
  if [ -z "${MC_CMD}" ]; then
    MC_CMD="java -Xmx1024M -Xms1024M -jar minecraft_server.${MC_VER}.jar nogui"
  fi

  cat >run.sh <<CMD_EOF
#!/bin/sh
BINDIR=\$(dirname "\$(readlink -fn "\$0")")
cd "\$BINDIR"
${MC_CMD}
CMD_EOF
  chmod +x run.sh
  popd

  rm -f /tmp/page.html
}

# Add a message to login motd, with credentials script created
function setup_motd(){
  local MOTD_FILE='/etc/update-motd.d/99-credentials'
  cat >"${MOTD_FILE}" <<CMD_EOF
#!/bin/bash
echo '### Information for your server ###'
echo 'Your server IP: http://$(hostname -I | cut -f1 -d' ')/'
echo 'To start Minecraft server: screen /home/minecraft/run.sh'
echo '### (To remove this message delete ${MOTD_FILE}) ###'
CMD_EOF
  chmod +x "${MOTD_FILE}"
}


install_minecraft;
setup_motd;
