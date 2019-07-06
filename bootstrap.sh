#!/bin/bash

MINECRAFT_DOWNLOAD_URL="https://launcher.mojang.com/v1/objects/d0d0fe2b1dc6ab4c65554cb734270872b72dadd6/server.jar" # Latest download link as of 7/06/2019
MINECRAFT_VERSION="1.14.3"

MINECRAFT_INSTALL_DIR="/opt/minecraft"
MINECRAFT_MIN_HEAP_SIZE="512M"
MINECRAFT_MAX_HEAP_SIZE="896M"
MINECRAFT_USER="minecraft" # For the love of god don't be an asshat and change to "root"
MINECRAFT_JAR_PATH="${MINECRAFT_INSTALL_DIR}/server.${MINECRAFT_VERSION}.jar"
MINECRAFT_EXECUTABLE_PATH="${MINECRAFT_INSTALL_DIR}/run.sh"
MINECRAFT_SYSTEMD_SERVICE_NAME="minecraft-server"
MINECRAFT_SYSTEMD_SERVICE_PATH="/etc/systemd/system/${MINECRAFT_SYSTEMD_SERVICE_NAME}.service"

RED="\033[0;31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
NC="\033[0m" #No color

_log() {
    echo -e ${0##*/}: "${@}" 1>&2
}

_die() {
    _log "${RED}FATAL:${NC} ${@}"
    exit 1
}

command -v systemctl >/dev/null 2>&1 || _die "systemd not found. No other init systems are currently supported." # Sanity check

# Disabling passwords is traditonally frowned upon, however since the server's sole purpose is running minecraft we can relax on security.
_log "Creating user: ${MINECRAFT_USER}"
command -v apt-get >/dev/null 2>&1 && adduser --disabled-password --gecos "" "${MINECRAFT_USER}"

if [ ! -d "${MINECRAFT_INSTALL_DIR}" ]; then
    _log "Creating ${MINECRAFT_INSTALL_DIR}"
    mkdir -m 700 "${MINECRAFT_INSTALL_DIR}" || _die "Failed to create ${MINECRAFT_INSTALL_DIR} and set permissions"
    chown "${MINECRAFT_USER}":"${MINECRAFT_USER}" "${MINECRAFT_INSTALL_DIR}"
else
    _log "${MINECRAFT_INSTALL_DIR} already exists. Proceeding with install."
fi

_log "Downloading minecraft jar..."
wget "${MINECRAFT_DOWNLOAD_URL}" -O "${MINECRAFT_JAR_PATH}" || _die "Failed to fetch ${MINECRAFT_DOWNLOAD_URL}"

# Install Ubuntu dependencies
apt_dependencies=(
    "openjdk-11-jdk"
)
command -v apt-get >/dev/null 2>&1 && sudo apt-get update -y && sudo apt-get install -y "${apt_dependencies[@]}"

cat << EOF > "${MINECRAFT_EXECUTABLE_PATH}"
#!/bin/bash
java -Xms${MINECRAFT_MIN_HEAP_SIZE} -Xmx${MINECRAFT_MAX_HEAP_SIZE} -jar ${MINECRAFT_JAR_PATH}
EOF

chown -R "${MINECRAFT_USER}":"${MINECRAFT_USER}" "${MINECRAFT_INSTALL_DIR}"
chmod +x "${MINECRAFT_EXECUTABLE_PATH}" || _die "Failed to perform chmod on ${MINECRAFT_EXECUTABLE_PATH}"

su - "${MINECRAFT_USER}" -c "cd ${MINECRAFT_INSTALL_DIR}; /bin/bash ${MINECRAFT_EXECUTABLE_PATH}" && {
    # When executed for the first time, the process will exit. We need to accept the EULA
    _log "Accepting end user license agreement"
    sed -i -e 's/false/true/' "${MINECRAFT_INSTALL_DIR}/eula.txt" || _die "Failed to modify ${MINECRAFT_INSTALL_DIR}/eula.txt"
}

cat << EOF > "${MINECRAFT_SYSTEMD_SERVICE_PATH}" || _die "Failed to create systemd service"
[Unit]
Description=minecraft server
After=network.target

[Service]
Type=simple
User=${MINECRAFT_USER}
ExecStart=/usr/bin/bash ${MINECRAFT_EXECUTABLE_PATH}
Restart=on-failure

[Install]
WantedBy=multi-user.target

EOF

_log "Starting ${MINECRAFT_SYSTEMD_SERVICE_NAME}"
systemctl start "${MINECRAFT_SYSTEMD_SERVICE_PATH}" || _die "Failed to start ${MINECRAFT_SYSTEMD_SERVICE_NAME} with systemd"
systemctl enable "${MINECRAFT_SYSTEMD_SERVICE_PATH}" || _die "Failed to permanently enable ${MINECRAFT_SYSTEMD_SERVICE_NAME} with systemd"
