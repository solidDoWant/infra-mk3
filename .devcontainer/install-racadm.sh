#!/bin/bash

VERSION="${1}"
OS_RELEASE='jammy'  # 'noble' is not supported yet

KEYRING_PATH='/usr/share/keyrings/linux.dell.com.sources-keyring.asc'
KEYRING_URL=' https://linux.dell.com/repo/pgp_pubkeys/0x1285491434D8786F.asc'
REPO_URL="http://linux.dell.com/repo/community/openmanage/${VERSION}/${OS_RELEASE}"

sudo curl -fsSL -o "${KEYRING_PATH}" "${KEYRING_URL}"

echo "deb [signed-by=${KEYRING_PATH}] ${REPO_URL} ${OS_RELEASE} main" \
    | sudo tee -a /etc/apt/sources.list.d/linux.dell.com.sources.list

sudo apt install -y srvadmin-hapi || sudo dpkg --configure -a
sudo apt install -y srvadmin-idracadm8 || sudo dpkg --configure -a
