#!/bin/bash

# MC_* denotes Minecraft or Master Chief 
MC_DOWNLOAD_URL="https://launcher.mojang.com/v1/objects/d0d0fe2b1dc6ab4c65554cb734270872b72dadd6/server.jar" # Latest download link as of 7/06/2019
MC_DOWNLOAD_SHA256SUM="942256f0bfec40f2331b1b0c55d7a683b86ee40e51fa500a2aa76cf1f1041b38"
MC_VERSION="1.14.3"

MC_INSTALL_DIR="/opt/minecraft"
MC_MAX_HEAP_SIZE="896M" # Not some random number i pulled out of a hat: 1024-128
MC_USER="minecraft" # For the love of god don't be an asshat and change to "root"
MC_JAR_PATH="${MC_INSTALL_DIR}/server.${MC_VERSION}.jar"
MC_EXECUTABLE_PATH="${MC_INSTALL_DIR}/start.sh"
MC_SYSTEMD_SERVICE_NAME="minecraftd"
MC_SYSTEMD_SERVICE_PATH="/etc/systemd/system/${MC_SYSTEMD_SERVICE_NAME}.service"

# M_* denotes Minecraft Mod
M_FORGE_DOWNLOAD_URL="https://files.minecraftforge.net/maven/net/minecraftforge/forge/1.12.2-14.23.5.2837/forge-1.12.2-14.23.5.2837-installer.jar"
M_FORGE_DOWNLOAD_SHA1="e4fd5f2ade6f4d6d3e18971fa18d8aade6ba1358"

MC_DOWNLOAD_ACTUAL_SHA256SUM=""
M_FORGE_DOWNLOAD_ACTUAL_SHA1=""
M_FORGE_INSTALLER_JAR_PATH=""
M_FORGE_UNIVERSAL_JAR_PATH=""
SYS_TOTAL_MEMORY_KB=""
SYS_TOTAL_MEMORY_MB=""

# CLR_* denotes Color
CLR_RED="\033[0;31m"
CLR_GREEN="\033[32m"
CLR_YELLOW="\033[33m"
CLR_CYAN="\033[36m"
CLR_NONE="\033[0m"

# Helpers
_log() {
    echo -e ${0##*/}: "${@}" 1>&2
}

_debug() {
    _log "${CLR_CYAN}DEBUG:${CLR_NONE} ${@}"
}

_warn() {
    _log "${CLR_YELLOW}WARNING:${CLR_NONE} ${@}"
}

_success() {
    _log "${CLR_YELLOW}SUCCESS:${CLR_NONE} ${@}"
}

_die() {
    _log "${CLR_RED}FATAL:${CLR_NONE} ${@}"
    exit 1
}

# Where the magic happens
command -v systemctl >/dev/null 2>&1 || _die "systemd not found. No other init systems are currently supported." # Sanity check

if [ -d "${MC_SYSTEMD_SERVICE_PATH}" ]; then
    systemctl daemon-reload
    systemctl stop "${MC_SYSTEMD_SERVICE_NAME}" || _log "${MC_SYSTEMD_SERVICE_NAME}.service not running..."
fi

# Disabling passwords is traditonally frowned upon, however since the server's sole purpose is running minecraft we can relax on security.
_log "Creating user: ${MC_USER}"
command -v apt-get >/dev/null 2>&1 && adduser --disabled-password --gecos "" "${MC_USER}"

if [ ! -d "${MC_INSTALL_DIR}" ]; then
    _log "Creating ${MC_INSTALL_DIR}"
    mkdir -m 700 "${MC_INSTALL_DIR}" || _die "Failed to create ${MC_INSTALL_DIR} and set permissions"
    chown "${MC_USER}":"${MC_USER}" "${MC_INSTALL_DIR}"
else
    _log "${MC_INSTALL_DIR} already exists. Proceeding with install."
fi

_log "Downloading minecraft jar..."
wget "${MC_DOWNLOAD_URL}" -O "${MC_JAR_PATH}" || _die "Failed to fetch ${MC_DOWNLOAD_URL}"

# Validate file download integrity
MC_DOWNLOAD_ACTUAL_SHA256SUM="$(sha256sum ${MC_JAR_PATH} | cut -d' ' -f1)"
if [ "${MC_DOWNLOAD_ACTUAL_SHA256SUM}" != "${MC_DOWNLOAD_SHA256SUM}" ]; then
    _die "sha256sum doesn't match for ${MC_JAR_PATH}"
fi

_log "Downloading forge..."
wget "${M_FORGE_DOWNLOAD_URL}" -P "${MC_INSTALL_DIR}" || _die "Failed to fetch ${M_FORGE_DOWNLOAD_URL}"

# TODO: Validate Forge SHA1

# Install Ubuntu dependencies
apt_dependencies=(
    "openjdk-11-jdk"
    "libsfml-dev"
)
command -v apt-get >/dev/null 2>&1 && sudo apt-get update -y && sudo apt-get install -y "${apt_dependencies[@]}"

SYS_TOTAL_MEMORY_KB="$(grep MemTotal /proc/meminfo | awk '{print $2}')"
SYS_TOTAL_MEMORY_MB="$(( $SYS_TOTAL_MEMORY_KB / 1024 ))"
MC_MAX_HEAP_SIZE="$(( $SYS_TOTAL_MEMORY_MB - 128 ))M" # Leave 128MB memory for the system to run properly

cat << EOF > "${MC_EXECUTABLE_PATH}"
#!/bin/bash
java -Xmx${MC_MAX_HEAP_SIZE} -jar ${MC_JAR_PATH}
EOF

chown -R "${MC_USER}":"${MC_USER}" "${MC_INSTALL_DIR}"
chmod +x "${MC_EXECUTABLE_PATH}" || _die "Failed to perform chmod on ${MC_EXECUTABLE_PATH}"

su - "${MC_USER}" -c "cd ${MC_INSTALL_DIR}; /bin/bash ${MC_EXECUTABLE_PATH}" && {
    # When executed for the first time, the process will exit. We need to accept the EULA
    _log "Accepting end user license agreement"
    sed -i -e 's/false/true/' "${MC_INSTALL_DIR}/eula.txt" || _die "Failed to modify ${MC_INSTALL_DIR}/eula.txt"
}

M_FORGE_INSTALLER_JAR_PATH="$(ls ${MC_INSTALL_DIR}/forge-*installer.jar)"
su - "${MC_USER}" -c "cd ${MC_INSTALL_DIR}; java -jar ${M_FORGE_INSTALLER_JAR_PATH} --installServer" || {
    _die "Failed to execute ${M_FORGE_INSTALLER_JAR_PATH}"
}

M_FORGE_UNIVERSAL_JAR_PATH="$(ls ${MC_INSTALL_DIR}/forge-*universal.jar)"
su - "${MC_USER}" -c "cd ${MC_INSTALL_DIR}; java -jar ${M_FORGE_UNIVERSAL_JAR_PATH}" || {
    _die "Failed to execute ${M_FORGE_UNIVERSAL_JAR_PATH}"
}

cat << EOF > "${MC_SYSTEMD_SERVICE_PATH}" || _die "Failed to create systemd service"
[Unit]
Description=minecraft server
After=network.target

[Service]
Type=simple
User=${MC_USER}
WorkingDirectory=${MC_INSTALL_DIR}
ExecStart=/bin/bash ${MC_EXECUTABLE_PATH}
Restart=on-failure

[Install]
WantedBy=multi-user.target

EOF

_log "Configuring systemd to automatically start ${MC_SYSTEMD_SERVICE_NAME}.service on boot"
systemctl enable "${MC_SYSTEMD_SERVICE_NAME}" || _die "Failed to permanently enable ${MC_SYSTEMD_SERVICE_NAME} with systemd"

_log "Starting ${MC_SYSTEMD_SERVICE_NAME}.service. This can take awhile... Go grab some popcorn."
systemctl start "${MC_SYSTEMD_SERVICE_NAME}" || _die "Failed to start ${MC_SYSTEMD_SERVICE_NAME} with systemd"

ip_addresses="$(hostname -I)"
_log "Server is accessible from the following ip addresses: ${ip_addresses}"
 
