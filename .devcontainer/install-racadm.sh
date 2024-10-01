#!/bin/bash

VERSION="11010"
OS_RELEASE='jammy'  # 'noble' is not supported yet

KEYRING_PATH='/usr/share/keyrings/linux.dell.com.sources-keyring.asc'
KEYRING_URL=' https://linux.dell.com/repo/pgp_pubkeys/0x1285491434D8786F.asc'
REPO_URL="http://linux.dell.com/repo/community/openmanage/${VERSION}/${OS_RELEASE}"
SOURCES_FILE="/etc/apt/sources.list.d/linux.dell.com.sources.list"

sudo curl -fsSL -o "${KEYRING_PATH}" "${KEYRING_URL}"

echo "deb [signed-by=${KEYRING_PATH}] ${REPO_URL} ${OS_RELEASE} main" \
    | sudo tee -a "${SOURCES_FILE}"

sudo apt install -y srvadmin-hapi || sudo dpkg --configure -a
sudo apt install -y srvadmin-idracadm8 || sudo dpkg --configure -a

# Something later in the build process is dumping the keyfiles so the source
# must be removed, or later apt invocations will fail
sudo rm -vf "${SOURCES_FILE}"
