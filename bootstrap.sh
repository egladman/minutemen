#!/bin/bash

################################################################################
#                                                                              #
#                                  minutemen                                   #
#                           Written By: Eli Gladman                            #
#                                                                              #
#                                                                              #
#                                   EXAMPLE                                    #
#                               ./bootstrap.sh                                 #
#                                                                              #
#                   https://github.com/egladman/minutemen                      #
#                                                                              #
################################################################################

# The following can be optionally passed in as environment variables
# - MC_USER_PASSWORD_HASH

# MC_* denotes Minecraft or Master Chief 
MC_SERVER_UUID="$(uuidgen)" # Each server instance has its own value
MC_PARENT_DIR="/opt/minecraft"
MC_SERVER_INSTANCES_DIR="${MC_PARENT_DIR}/instances"
MC_BIN_DIR="${MC_PARENT_DIR}/bin"
MC_BIN_DIR_OCTAL=774
MC_LOG_DIR="${MC_PARENT_DIR}/log"
MC_LOG_INSTANCE_DIR="${MC_LOG_DIR}/${MC_SERVER_UUID}"
MC_DOWNLOADS_CACHE_DIR="${MC_PARENT_DIR}/.downloads"
MC_MODS_CACHE_DIR="${MC_PARENT_DIR}/.mods"
MC_INSTALL_DIR="${MC_SERVER_INSTANCES_DIR}/${MC_SERVER_UUID}"
MC_MAX_HEAP_SIZE="896M" # This variable gets redefined later on. Not some random number i pulled out of a hat: 1024-128=896
MC_USER="minecraft" # For the love of god don't be an asshat and change to "root"

MC_SERVER_MAX_CONCURRENT_INSTANCES=16 # Realistically I never see myself running more than 4 instances simultaneously...
MC_SERVER_PORT_RANGE_START=25565 # Default minecraft port
MC_SERVER_PORT_RANGE_END=$(( ${MC_SERVER_PORT_RANGE_START} + ${MC_SERVER_MAX_CONCURRENT_INSTANCES} ))

MC_EXECUTABLE_START="start"
MC_EXECUTABLE_START_PATH="${MC_PARENT_DIR}/${MC_BIN_DIR}/${MC_EXECUTABLE_START}"
MC_EXECUTABLE_COMMAND="tell" # At first this was "command", but i felt it might get confusing having an executable in ./bin named "command"
MC_EXECUTABLE_COMMAND_PATH="${MC_PARENT_DIR}/${MC_BIN_DIR}/${MC_EXECUTABLE_COMMAND}"

MC_SYSTEMD_SERVICE_NAME="minutemen"
MC_SYSTEMD_SERVICE_PATH="/etc/systemd/system/${MC_SYSTEMD_SERVICE_NAME}.service"

MC_SERVER_INSTANCE_PIPE="${MC_SYSTEMD_SERVICE_NAME}.fifo"
MC_SERVER_INSTANCE_PIPE_PATH="${MC_SERVER_INSTANCES_DIR}/${MC_SERVER_UUID}/${MC_SERVER_INSTANCE_PIPE}"

# M_* denotes Minecraft Mod
M_FORGE_DOWNLOAD_URL="https://files.minecraftforge.net/maven/net/minecraftforge/forge/1.14.3-27.0.25/forge-1.14.3-27.0.25-installer.jar"
M_FORGE_DOWNLOAD_SHA1SUM="7b96f250e52584086591e14472b96ec2648a1c9c"
M_FORGE_INSTALLER_JAR="$(basename ${M_FORGE_DOWNLOAD_URL})"
M_FORGE_INSTALLER_JAR_PATH="${MC_INSTALL_DIR}/${M_FORGE_INSTALLER_JAR}"

# SYS_* denotes System
SYS_TOTAL_MEMORY_KB="$(grep MemTotal /proc/meminfo | awk '{print $2}')"
SYS_TOTAL_MEMORY_MB="$(( $SYS_TOTAL_MEMORY_KB / 1024 ))"
SYS_RESERVED_MEMORY_MB=128 

# MU_ * denotes Mutex
MU_JAVA_CHECK_PASSED=1
MU_USER_CHECK_PASSED=1
MU_FORGE_DOWNLOAD_CACHED=1

# CLR_* denotes Color
CLR_RED="\033[0;31m"
CLR_GREEN="\033[32m"
CLR_YELLOW="\033[33m"
CLR_CYAN="\033[36m"
CLR_NONE="\033[0m"

# FL_ * denotes Flag
FL_VERBOSE=1
FL_DISABLE_SYSTEMD_START=1

# Variables that are dynamically set later
M_FORGE_DOWNLOAD_ACTUAL_SHA1SUM=""
M_FORGE_UNIVERSAL_JAR_PATH=""
MC_SERVER_PORT_SELECTED=""

# Helpers
_log() {
    echo -e ${0##*/}: "${@}" 1>&2
}

_debug() {
    if [ "${FL_VERBOSE}" -eq 0 ]; then
        _log "${CLR_CYAN}DEBUG:${CLR_NONE} ${@}"
    fi
}

_warn() {
    _log "${CLR_YELLOW}WARNING:${CLR_NONE} ${@}"
}

_success() {
    _log "${CLR_GREEN}SUCCESS:${CLR_NONE} ${@}"
}

_die() {
    _log "${CLR_RED}FATAL:${CLR_NONE} ${@}"
    exit 1
}

_init_dir() {
    # I'm making a lot assumptions:
    # - All files in MC_PARENT_DIR should have the same owner:group
    # - The first argument passed in is the parent directory of all subsequent directories passed in

    # TODO: Add safety check to validate directory hierarchy

    local TARGET_USER="${1}"

    local ARG
    IFS=' ' read -r -a ARG <<< "${2}"
    local TARGET_DIR="${ARG[0]}"

    _debug "Checking for directory: ${TARGET_DIR}"
    if [ ! -d "${TARGET_DIR}" ]; then
        mkdir -p "${ARG[@]}" || _die "Failed to create ${ARG[@]}"
        if [ -n "${ARG[1]}" ]; then # Be ashamed for writing such a shitty block of code
            chown -R "${TARGET_USER}":"${TARGET_USER}" "${MC_PARENT_DIR}" || {
	        _die "Failed to perform chown on the following dir(s): ${MC_PARENT_DIR}"
	    }
	fi
    else
        _log "Directory: ${TARGET_DIR} already exists. Proceeding with install..."
    fi
}

_run() {
    # Run commands as unprivileged user
    local CMD="${@}"
    su - "${MC_USER}" -c "${CMD}" 
}

_if_installed() {
    # Check if a bin is present
    local PROGRAM="${1}"
    command -v "${PROGRAM}" >/dev/null 2>&1
}

_usage() {
cat << EOF
${0##*/} [-h] [-v] [-s] -- minutemen -- Build/Provision Minecraft Servers with ForgeMods Support in under 60 seconds
where:
    -h  show this help text
    -v  verbose
    -s  disable systemd start/enable
EOF
}

while getopts ':h :v :s' option; do
    case "${option}" in
        h|\?) _usage
           exit 0
           ;;
        v) FL_VERBOSE=0
           ;;
	s) FL_DISABLE_SYSTEMD_START=0
	   ;;
        :) printf "missing argument for -%s\n" "${OPTARG}"
           _usage
           exit 1
           ;;
    esac
done
shift $((OPTIND - 1))

# Where the magic happens

umask 003 #ug=rwx,o=r

_if_installed systemctl || _die "systemd not found. No other init systems are currently supported." # Sanity check

if [ -d "${MC_SYSTEMD_SERVICE_PATH}" ]; then
    _debug "Attempting to stop ${MC_SYSTEMD_SERVICE_NAME}.service"
    systemctl daemon-reload || _warn "Failed to run \"systemctl daemon-reload\""
    systemctl stop "${MC_SYSTEMD_SERVICE_NAME}" || _log "${MC_SYSTEMD_SERVICE_NAME}.service not running..."
fi

if [ -f "${MC_DOWNLOADS_CACHE_DIR}/${M_FORGE_INSTALLER_JAR}" ]; then
    _debug "Cached ${M_FORGE_INSTALLER_JAR} found."
    MU_FORGE_DOWNLOAD_CACHED=0
fi

_debug "Checking for user: ${MC_USER}"
id -u "${MC_USER}" >/dev/null 2>&1 && _debug "User: ${MC_USER} found." || {
    _debug "User: ${MC_USER} not found. Creating..."

    ADDUSER_PASSWORD_PARAM=""

    # Check if we need to set a password for MC_USER
    if [ -n "${MC_USER_PASSWORD_HASH}" ]; then
	_debug "Setting password for ${MC_USER}"
        ADDUSER_PASSWORD_PARAM="--password ${MC_USER_PASSWORD_HASH}"
    fi

    _if_installed dnf && adduser "${ADDUSER_PASSWORD_PARAM}" "${MC_USER}" >/dev/null 2>&1 && {
        MU_USER_CHECK_PASSED=0
    }

    if [ -z "${ADDUSER_PASSWORD_PARAM}" ]; then
        ADDUSER_PASSWORD_PARAM="--disabled-password"
        _if_installed apt-get && adduser "${ADDUSER_PASSWORD_PARAM}" --gecos "" "${MC_USER}" >/dev/null 2>&1 && {
            MU_USER_CHECK_PASSED=0
        }
    fi

    wait && MC_USER_PASSWORD_HASH=""; ADDUSER_PASSWORD_PARAM="" # Clear password variables just in case...

    if [[ $MU_USER_CHECK_PASSED -ne 0 ]]; then
        _die "Failed to run \"adduser ${MC_USER}\". Does the user already exist?"
    fi
}

_init_dir "${MC_USER}" "${MC_PARENT_DIR}"
_init_dir "${MC_USER}" "${MC_INSTALL_DIR} ${MC_BIN_DIR} ${MC_LOG_INSTANCE_DIR} ${MC_DOWNLOADS_CACHE_DIR} ${MC_MODS_CACHE_DIR}"

if [[ ${MU_FORGE_DOWNLOAD_CACHED} -eq 0 ]]; then
    _debug "Copying ${MC_DOWNLOADS_CACHE_DIR}/${M_FORGE_INSTALLER_JAR} to ${MC_INSTALL_DIR}/"
    cp "${MC_DOWNLOADS_CACHE_DIR}/${M_FORGE_INSTALLER_JAR}" "${MC_INSTALL_DIR}/" || {
        _die "Failed to copy ${MC_DOWNLOADS_CACHE_DIR}/${M_FORGE_INSTALLER_JAR} to ${MC_INSTALL_DIR}/"
    }
else
    _debug "Downloading ${M_FORGE_INSTALLER_JAR}"
    wget "${M_FORGE_DOWNLOAD_URL}" -P "${MC_INSTALL_DIR}" || _die "Failed to fetch ${M_FORGE_DOWNLOAD_URL}"
    chown "${MC_USER}":"${MC_USER}" "${MC_INSTALL_DIR}"/"${M_FORGE_INSTALLER_JAR}" || {
        _die "Failed to perform chown on ${MC_INSTALL_DIR}/${M_FORGE_INSTALLER_JAR}"
    }
fi

# Validate file download integrity
M_FORGE_DOWNLOAD_ACTUAL_SHA1SUM="$(sha1sum ${M_FORGE_INSTALLER_JAR_PATH} | cut -d' ' -f1)"
if [ "${M_FORGE_DOWNLOAD_ACTUAL_SHA1SUM}" != "${M_FORGE_DOWNLOAD_SHA1SUM}" ]; then
    _debug "M_FORGE_DOWNLOAD_ACTUAL_SHA1SUM: ${M_FORGE_DOWNLOAD_ACTUAL_SHA1SUM}"
    _debug "M_FORGE_DOWNLOAD_SHA1SUM: ${M_FORGE_DOWNLOAD_SHA1SUM}"
    _die "sha1sum doesn't match for ${M_FORGE_INSTALLER_JAR_PATH}"
fi

# Install Ubuntu dependencies
apt_dependencies=(
    "openjdk-8-jdk" # Must be the first index!! openjdk-11-jdk works fine with vanilla Minecraft, but not with Forge
)
_if_installed apt-get && apt-get update -y && apt-get install -y "${apt_dependencies[@]}"

# Install Fedora dependencies
dnf_dependencies=(
    "java-1.8.0-openjdk" # Must be the first index!!
)
_if_installed dnf && dnf update -y && dnf install -y "${dnf_dependencies[@]}"

# Rebinding /usr/bin/java could negatively impact other aspects of the os stack i'm NOT going to automate it.
_if_installed dnf && update-alternatives --list | grep "^java.*${dnf_dependencies[0]}" && {
    MU_JAVA_CHECK_PASSED=0
    _debug "${dnf_dependencies[0]} is the default. Proceeding..."
}

_if_installed apt-get && update-alternatives --list | grep "^java.*${apt_dependencies[0]}" && {
    MU_JAVA_CHECK_PASSED=0
    _debug "${apt_dependencies[0]} is the default. Proceeding..."
}
wait # On update-alternatives child processes to complete...

if [[ $MU_JAVA_CHECK_PASSED -ne 0 ]]; then
    _die "openjdk 8 is NOT the default java. Run \"update-alternatives -show java\" for more info."
fi

M_FORGE_INSTALLER_LOG="${MC_LOG_INSTANCE_DIR}/${M_FORGE_INSTALLER_JAR}.out"
_debug "Logging ${M_FORGE_INSTALLER_JAR} installation to ${M_FORGE_INSTALLER_LOG}"

_run "cd ${MC_INSTALL_DIR}; java -jar ${M_FORGE_INSTALLER_JAR_PATH} --installServer | tee ${M_FORGE_INSTALLER_LOG}" && {
    chown "${MC_USER}":"${MC_USER}" "${MC_INSTALL_DIR}"/* || {
        _die "Failed to perform chown on ${MC_INSTALL_DIR}/*"
    }

    if [[ ${MU_FORGE_DOWNLOAD_CACHED} -eq 1 ]]; then
        _debug "Archiving ${M_FORGE_INSTALLER_JAR_PATH} to ${MC_DOWNLOADS_CACHE_DIR}/"
        mv "${M_FORGE_INSTALLER_JAR_PATH}" "${MC_DOWNLOADS_CACHE_DIR}/" || {
	    _warn "Failed to move ${M_FORGE_INSTALLER_JAR_PATH} to ${MC_DOWNLOADS_CACHE_DIR}/"
	}
    else
        rm "${M_FORGE_INSTALLER_JAR_PATH}" || _warn "Failed to delete ${M_FORGE_INSTALLER_JAR_PATH}"
    fi
} || {
    _die "Failed to execute ${M_FORGE_INSTALLER_JAR_PATH}"
}

_success "${M_FORGE_INSTALLER_JAR} returned code 0. Proceeding..."

# the "cd" ensures we get just the basename 
M_FORGE_UNIVERSAL_JAR_PATH="$(cd ${MC_INSTALL_DIR}; ls ${MC_INSTALL_DIR}/forge-*.jar | grep -v ${M_FORGE_INSTALLER_JAR})"
M_FORGE_UNIVERSAL_JAR="$(basename ${M_FORGE_UNIVERSAL_JAR_PATH})"

MC_MAX_HEAP_SIZE="$(( $SYS_TOTAL_MEMORY_MB - $SYS_RESERVED_MEMORY_MB ))M" # Leave 128MB memory for the system to run properly

read -r -d '' MC_EXECUTABLE_COMMAND_CONTENTS << EOF
#!/bin/bash
# ${MC_EXECUTABLE_COMMAND_PATH} Generated by ${MC_SYSTEMD_SERVICE_NAME}

MC_SERVER_UUID="\${1}"
MC_COMMAND="\${@:2}"

if [ -z "\${MC_SERVER_UUID}" ]; then
    echo "MC_SERVER_UUID argument required." && exit 1
fi

if [ -z "\${MC_COMMAND}" ]; then
    echo "second argument required." && exit 1
fi

MC_SERVER_INSTANCE_PIPE_PATH="${MC_SERVER_INSTANCES_DIR}/\${MC_SERVER_UUID}/${MC_SERVER_INSTANCE_PIPE}"
echo "\${MC_COMMAND}" > "\${MC_SERVER_INSTANCE_PIPE_PATH}"

EOF

read -r -d '' MC_EXECUTABLE_START_CONTENTS << EOF
#!/bin/bash
# ${MC_EXECUTABLE_START_PATH} Generated by ${MC_SYSTEMD_SERVICE_NAME}

if [ -z "\${1}" ]; then
    echo "MC_SERVER_UUID argument required." && exit 1
fi
MC_SERVER_UUID="\${1}"
MC_SERVER_INSTANCE_PIPE_PATH="${MC_SERVER_INSTANCES_DIR}/\${MC_SERVER_UUID}/${MC_SERVER_INSTANCE_PIPE}"

function _is_uuid() {
    local TARGET_UUID="\${1}"

    if [[ "\${TARGET_UUID}" =~ ^\{?[A-F0-9a-f]{8}-[A-F0-9a-f]{4}-[A-F0-9a-f]{4}-[A-F0-9a-f]{4}-[A-F0-9a-f]{12}\}?$ ]]; then
        echo 0 # found uuid
    else
        echo 1
    fi
}

function _mkpipe() {
    mkfifo "\${1}" -m 777 || {
        echo "Unable to create named pipe: \${1}"
        exit 1
    }
}

function _flushpipe() {
    dd if="\${1}" iflag=nonblock of=/dev/null
}

MC_USER_UID=$(id -u "${MC_USER}")
MC_SERVER_RUNNING_INSTANCES=() # Declare empty array. We'll push to this later...
MC_SERVER_AVAILABLE_INSTANCES="${MC_SERVER_INSTANCES_DIR}/*"

PS_STDOUT=\$(mktemp --suffix -${MC_SYSTEMD_SERVICE_NAME})
ps -eo pid,uid,cmd | tr -s ' ' | grep -v grep | grep "\${MC_USER_UID}.*" > "\${PS_STDOUT}" || {
    echo "Failed to write to \${PS_STDOUT}"
    exit 1
}

while IFS= read -r PS_STDOUT_LINE; do
    IFS=', ' read -r -a PS_STDOUT_LINE_ARR <<< "\${PS_STDOUT_LINE}"
    for j in "\${PS_STDOUT_LINE_ARR[@]}"; do
	if [[ \$(_is_uuid \$j) -eq 0 ]]; then
            MC_SERVER_RUNNING_INSTANCES+=("\${j}")
        fi
    done
done < "\${PS_STDOUT}"

# It's generally frowned upon to parse the output of ls.
# Since we create/maintain the contents of the directory I'm able to safely make the follow assumption(s):
#   - Every path printed is a directory
#   - None of the paths contain spaces

LS_OUTPUT_ARR=("\$(ls ${MC_SERVER_INSTANCES_DIR})")

# Iterate through all running instances.
# If the instance dir structure no longer exists kill the process.
for i in "\${MC_SERVER_RUNNING_INSTANCES[@]}"; do
    # Check to see if the LS_OUTPUT_ARR contains 'i'
    # This is by no means a robust check, however we can get away with it
    # since we're dealing exclusively with unique identifiers i.e. MC_SERVER_UUID
    if [[ ! "\${LS_OUTPUT_ARR[*]}" =~ "\${i}" ]]; then
        echo "Killing stale processes for instance: \${i}"
        ps -eo pid,uid,cmd | tr -s ' ' | grep -v grep | grep "\${MC_USER_UID}.*\${i}" | cut -d' ' -f1 | xargs kill -9 || {

            # break down of the ugly one liner above ^^
            # [ps -ea         ] Print process info with ONLY the specified columns for ALL users
            # [tr -s ' '      ] Replace sequential spaces with a single space
            # [grep -v grep   ] Invert match. (We don't want to see any grep processes show up in our results)

            echo "Failed to kill stale processes for \${i}"
        }
    fi
done

if [ ! -p "\${MC_SERVER_INSTANCE_PIPE_PATH}" ]; then
    _mkpipe "\${MC_SERVER_INSTANCE_PIPE_PATH}"
else # Pipe exists...
    _flushpipe "\${MC_SERVER_INSTANCE_PIPE_PATH}"
fi

MC_WORKING_DIR="${MC_SERVER_INSTANCES_DIR}/\${MC_SERVER_UUID}/"

pushd "\${MC_WORKING_DIR}" > /dev/null
tail -f "\${MC_SERVER_INSTANCE_PIPE_PATH}" | java -Xmx${MC_MAX_HEAP_SIZE} -jar ${MC_SERVER_INSTANCES_DIR}/\${MC_SERVER_UUID}/${M_FORGE_UNIVERSAL_JAR}
popd > /dev/null
 
EOF

# We want these files updated each time the script gets run
_debug "Updating files in ${MC_BIN_DIR}"
echo "${MC_EXECUTABLE_START_CONTENTS}" > "${MC_EXECUTABLE_START_PATH}" || _die "Failed to create ${MC_EXECUTABLE_SEND_PATH}"
echo "${MC_EXECUTABLE_COMMAND_CONTENTS}" > "${MC_EXECUTABLE_COMMAND_PATH}" || _die "Failed to create ${MC_EXECUTABLE_COMMAND_PATH}"
chown -R "${MC_USER}":"${MC_USER}" "${MC_BIN_DIR}" || _die "Failed to perform chown on ${MC_BIN_DIR}"
chmod "${MC_BIN_DIR_OCTAL}" -R "${MC_BIN_DIR}" || _die "Failed to perform chmod on ${MC_BIN_DIR}"

_run "cd ${MC_INSTALL_DIR}; /bin/bash ${MC_EXECUTABLE_PATH}" && {
    # When executed for the first time, the process will exit. We need to accept the EULA
    _debug "Accepting end user license agreement"
    sed -i -e 's/false/true/' "${MC_INSTALL_DIR}/eula.txt" || _die "Failed to modify \"${MC_INSTALL_DIR}/eula.txt\". ${M_FORGE_UNIVERSAL_JAR} failed most likely."
} || _die "Failed to execute ${MC_EXECUTABLE_PATH} for the first time."

# Install mods if present...
for mod in "${MC_MODS_CACHE_DIR}"/*.jar; do
    test -f "$mod" && {
	_debug "Installing mod ${mod} to ${MC_INSTALL_DIR}/mods/${mod}"
        cp "${mod}" "${MC_INSTALL_DIR}/mods/"
    }
done

# What port should we run the instance on?
_debug "Determining port..."
for port in {${MC_SERVER_PORT_RANGE_START}..${MC_SERVER_PORT_RANGE_END}}; do 
    if [ lsof -Pi :"${port}" -sTCP:LISTEN -t >/dev/null ]; then
       _debug "Port: ${port} is already in use. Skipping..."
       continue
    else
       _debug "Port: ${port} not in use. Selecting..."
       MC_SERVER_PORT_SELECTED="${p}"
       break
    fi
done

_debug "Validating port selection..."
if [ -z "${MC_SERVER_PORT_SELECTED}" ]; then
    # I'm making a broad assumption that only minecraft is using the above port range
    _die "JFC you have ${MC_SERVER_MAX_CONCURRENT_INSTANCES} instances running. No ports available..."
fi

_debug "Updating port in ${MC_INSTALL_DIR}/server.properties"
sed -i "/^\(server-port=\).*/s//\$MC_SERVER_PORT_SELECTED/" "${MC_INSTALL_DIR}/server.properties" || {
    _die "Failed to modify \"${MC_INSTALL_DIR}/server.properties"
}

_debug "Creating ${MC_SYSTEMD_SERVICE_PATH}"
cat << EOF > "${MC_SYSTEMD_SERVICE_PATH}" || _die "Failed to create systemd service"
[Unit]
Description=minecraft server: %i
After=network.target

[Service]
Type=simple
User=${MC_USER}
Group=${MC_USER}
WorkingDirectory=${MC_SERVER_INSTANCES_DIR}/%i
ExecStart=/bin/bash ${MC_SERVER_INSTANCES_DIR}/%i/${MC_EXECUTABLE_START}
Restart=on-failure
RestartSec=60s

[Install]
WantedBy=multi-user.target

EOF

if [ "${FL_DISABLE_SYSTEMD_START}" -eq 0 ]; then
    _log "Configuring systemd to automatically start ${MC_SYSTEMD_SERVICE_NAME}.service on boot"
    systemctl enable "${MC_SYSTEMD_SERVICE_NAME}@${MC_SERVER_UUID}" || {
        _die "Failed to permanently enable ${MC_SYSTEMD_SERVICE_NAME}@${MC_SERVER_UUID} with systemd"
    }

    _log "Starting ${MC_SYSTEMD_SERVICE_NAME}.service. This can take awhile... Go grab some popcorn."
    systemctl start "${MC_SYSTEMD_SERVICE_NAME}@${MC_SERVER_UUID}" || {
        _die "Failed to start ${MC_SYSTEMD_SERVICE_NAME}@${MC_SERVER_UUID} with systemd"
    }

    ip_addresses="$(hostname -I)"
    _success "Server is now running. Go crazy ${ip_addresses}"
else
    _log "To start server run: ${MC_EXECUTABLE_START_PATH} ${MC_SERVER_UUID}" 
    _debug "Skipping systemd start/enable"
fi
 
