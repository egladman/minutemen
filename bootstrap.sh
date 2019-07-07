#!/bin/bash

# MC_* denotes Minecraft or Master Chief 
MC_INSTALL_DIR="/opt/minecraft"
MC_MAX_HEAP_SIZE="896M" # Not some random number i pulled out of a hat: 1024-128
MC_USER="minecraft" # For the love of god don't be an asshat and change to "root"
MC_EXECUTABLE_PATH="${MC_INSTALL_DIR}/start.sh"
MC_SYSTEMD_SERVICE_NAME="minecraftd"
MC_SYSTEMD_SERVICE_PATH="/etc/systemd/system/${MC_SYSTEMD_SERVICE_NAME}.service"

# M_* denotes Minecraft Mod
M_FORGE_DOWNLOAD_URL="https://files.minecraftforge.net/maven/net/minecraftforge/forge/1.14.3-27.0.25/forge-1.14.3-27.0.25-installer.jar"
M_FORGE_DOWNLOAD_SHA1SUM="7b96f250e52584086591e14472b96ec2648a1c9c"
M_FORGE_INSTALLER_JAR="$(basename ${M_FORGE_DOWNLOAD_URL})"
M_FORGE_INSTALLER_JAR_PATH="${MC_INSTALL_DIR}/${M_FORGE_INSTALLER_JAR}"

# SYS_* denotes System
SYS_JAVA_PATH="/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java"

# CLR_* denotes Color
CLR_RED="\033[0;31m"
CLR_GREEN="\033[32m"
CLR_YELLOW="\033[33m"
CLR_CYAN="\033[36m"
CLR_NONE="\033[0m"

# Variables that are dynamically created later
M_FORGE_DOWNLOAD_ACTUAL_SHA1SUM=""
M_FORGE_UNIVERSAL_JAR_PATH=""
M_FORGE_UNIVERSAL_JAR=""
SYS_TOTAL_MEMORY_KB=""
SYS_TOTAL_MEMORY_MB=""

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

_log "Downloading forge..."
wget "${M_FORGE_DOWNLOAD_URL}" -P "${MC_INSTALL_DIR}" || _die "Failed to fetch ${M_FORGE_DOWNLOAD_URL}"

# Validate file download integrity
M_FORGE_DOWNLOAD_ACTUAL_SHA1SUM="$(sha1sum ${M_FORGE_INSTALLER_JAR_PATH} | cut -d' ' -f1)"
if [ "${M_FORGE_DOWNLOAD_ACTUAL_SHA1SUM}" != "${M_FORGE_DOWNLOAD_SHA1SUM}" ]; then
    _debug "M_FORGE_DOWNLOAD_ACTUAL_SHA1SUM: ${M_FORGE_DOWNLOAD_ACTUAL_SHA1SUM}"
    _debug "M_FORGE_DOWNLOAD_SHA1SUM: ${M_FORGE_DOWNLOAD_SHA1SUM}"
    _die "sha1sum doesn't match for ${M_FORGE_INSTALLER_JAR_PATH}"
fi

# Install Ubuntu dependencies
apt_dependencies=(
    "openjdk-8-jdk" # openjdk-11-jdk works fine with vanilla Minecraft, but not with Forge
)
command -v apt-get >/dev/null 2>&1 && sudo apt-get update -y && sudo apt-get install -y "${apt_dependencies[@]}"

#Configure /usr/bin/java to point to openjdk-8 instead of openjdk-11
update-alternatives --set java "${SYS_JAVA_PATH}" || _die "Failed to default java to openjdk-8"

SYS_TOTAL_MEMORY_KB="$(grep MemTotal /proc/meminfo | awk '{print $2}')"
SYS_TOTAL_MEMORY_MB="$(( $SYS_TOTAL_MEMORY_KB / 1024 ))"
MC_MAX_HEAP_SIZE="$(( $SYS_TOTAL_MEMORY_MB - 128 ))M" # Leave 128MB memory for the system to run properly

chown -R "${MC_USER}":"${MC_USER}" "${MC_INSTALL_DIR}"

su - "${MC_USER}" -c "cd ${MC_INSTALL_DIR}; java -jar ${M_FORGE_INSTALLER_JAR_PATH} --installServer" || {
    _die "Failed to execute ${M_FORGE_INSTALLER_JAR_PATH}"
}
_success "${M_FORGE_INSTALLER_JAR completed!}"

# the "cd" ensures we get just the basename 
M_FORGE_UNIVERSAL_JAR="$(cd ${MC_INSTALL_DIR}; ls ${MC_INSTALL_DIR}/forge-*.jar | grep -v ${M_FORGE_INSTALLER_JAR})" #We will run into issues if multiple versions of forge are present
M_FORGE_UNIVERSAL_JAR_PATH="${MC_INSTALL_DIR}/${M_FORGE_UNIVERSAL_JAR}"

# Create the wrapper script that systemd invokes
_debug "Creating ${MC_EXECUTABLE_PATH}"
cat << EOF > "${MC_EXECUTABLE_PATH}"
#!/bin/bash
java -Xmx${MC_MAX_HEAP_SIZE} -jar ${M_FORGE_UNIVERSAL_JAR_PATH}
EOF

chmod +x "${MC_EXECUTABLE_PATH}" || _die "Failed to perform chmod on ${MC_EXECUTABLE_PATH}"

su - "${MC_USER}" -c "cd ${MC_INSTALL_DIR}; /bin/bash ${MC_EXECUTABLE_PATH}" && {
    # When executed for the first time, the process will exit. We need to accept the EULA
    _log "Accepting end user license agreement"
    sed -i -e 's/false/true/' "${MC_INSTALL_DIR}/eula.txt" || _die "Failed to modify ${MC_INSTALL_DIR}/eula.txt"
}

_debug "Creating ${MC_SYSTEMD_SERVICE_PATH}"
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
_success "Server is now running. Go crazy ${ip_addresses}"
 
