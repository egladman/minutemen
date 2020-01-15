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

umask 003 #ug=rwx,o=r

# MC_* denotes Minecraft or Master Chief
MC_SERVER_UUID="$(cat /proc/sys/kernel/random/uuid)" # Each server instance has its own value
MC_PARENT_DIR="/opt/minecraft"
MC_SERVER_INSTANCES_DIR="${MC_PARENT_DIR}/instances"
MC_BIN_DIR="${MC_PARENT_DIR}/bin"
MC_BIN_DIR_OCTAL=774
MC_LOG_DIR="${MC_PARENT_DIR}/log"
MC_LOG_INSTANCE_DIR="${MC_LOG_DIR}/${MC_SERVER_UUID}"
MC_BACKUP_DIR="${MC_PARENT_DIR}/backups"
MC_DOWNLOADS_CACHE_DIR="${MC_PARENT_DIR}/.cache"
MC_FORGE_MODS_CACHE_DIR="${MC_PARENT_DIR}/.forgemods"
MC_INSTALL_DIR="${MC_SERVER_INSTANCES_DIR}/${MC_SERVER_UUID}"
MC_MAX_HEAP_SIZE="896M" # This variable gets redefined later on. Not some random number i pulled out of a hat: 1024-128=896
MC_USER="mminecraft" # Stands for "Minutemen Minecraft". For the love of god don't be an asshat and change to "root"

MC_SERVER_MAX_CONCURRENT_INSTANCES=16 # Realistically I never see myself running more than 4 instances simultaneously...
MC_SERVER_PORT_RANGE_START=25565 # Default minecraft port
MC_SERVER_PORT_RANGE_END=$(( ${MC_SERVER_PORT_RANGE_START} + ${MC_SERVER_MAX_CONCURRENT_INSTANCES} ))

MC_EXECUTABLE_START="start"
MC_EXECUTABLE_START_PATH="${MC_BIN_DIR}/${MC_EXECUTABLE_START}"
MC_EXECUTABLE_STOP="stop"
MC_EXECUTABLE_STOP_PATH="${MC_BIN_DIR}/${MC_EXECUTABLE_STOP}"
MC_EXECUTABLE_COMMAND="cmd"
MC_EXECUTABLE_COMMAND_PATH="${MC_BIN_DIR}/${MC_EXECUTABLE_COMMAND}"
MC_EXECUTABLE_BACKUP="backup"
MC_EXECUTABLE_BACKUP_PATH="${MC_BIN_DIR}/${MC_EXECUTABLE_BACKUP}"
MC_EXECUTABLE_BACKUPRESTORE="backup-restore"
MC_EXECUTABLE_BACKUPRESTORE_PATH="${MC_BIN_DIR}/${MC_EXECUTABLE_BACKUPRESTORE}"
MC_EXECUTABLE_SAVE="save"
MC_EXECUTABLE_SAVE_PATH="${MC_BIN_DIR}/${MC_EXECUTABLE_SAVE}"

MC_SYSTEMD_SERVICE_NAME="minutemen"
MC_SYSTEMD_SERVICE_PATH="/etc/systemd/system/${MC_SYSTEMD_SERVICE_NAME}@.service"

MC_SERVER_INSTANCE_PIPE="${MC_SYSTEMD_SERVICE_NAME}.fifo"
MC_SERVER_INSTANCE_PIPE_PATH="${MC_SERVER_INSTANCES_DIR}/${MC_SERVER_UUID}/${MC_SERVER_INSTANCE_PIPE}"

# MM_* denotes MinuteMen
MM_MANIFEST_JSON_PATH="${MC_DOWNLOADS_CACHE_DIR}/manifest.json"
MM_MANIFEST_JSON_URL="https://raw.githubusercontent.com/egladman/minutemen/master/manifest.json"
MM_MANIFEST_JSON_SHA256SUM="76b168f3ebefbcd2ee3f1636bd0dc271ec28a406fb47c5328a14277b1639e42b"

# M_* denotes Minecraft Mod
M_FORGE_DOWNLOAD_URL=""
M_FORGE_DOWNLOAD_SHA256SUM=""
M_FORGE_VERSION=""
M_FORGE_INSTALLER_JAR=""
M_FORGE_INSTALLER_JAR_PATH=""
M_FORGE_DOWNLOAD_ACTUAL_SHA256SUM=""
M_FORGE_UNIVERSAL_JAR_PATH=""

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
FL_LOCAL_INSTALL=1 # Simple no frills way to determine if curl was piped to bash (even though i don't condone this...)

MC_SERVER_PORT_SELECTED="" # dynamically set later on...

MC_MAX_HEAP_SIZE="$(( $SYS_TOTAL_MEMORY_MB - $SYS_RESERVED_MEMORY_MB ))M" # This can be overwritten with a CLI param

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

_validate_semver() {
    local SEMANTIC_VERSION="${1}"
    if [[ ! "${SEMANTIC_VERSION}" =~ ^[0-9]+(\.[0-9]+){2,3}$ ]]; then
        _die "\"${SEMANTIC_VERSION}\" isn't a valid semantic version."
    fi
}

_compare_checksum() {
    local TARGET_FILE="${1}"
    local CHECKSUM_ACTUAL="$(sha256sum ${TARGET_FILE} | cut -d' ' -f1)"
    local CHECKSUM_DESIRED="${2}"

    if [ "${CHECKSUM_ACTUAL}" != "${CHECKSUM_DESIRED}" ]; then
        _debug "CURRENT CHECKSUM: ${CHECKSUM_ACTUAL}"
        _debug "DESIRED CHECKSUM: ${CHECKSUM_DESIRED}"
        _die "Checksum doesn't match for file: ${TARGET_FILE}"
    fi
}

_if_installed() {
    # Check if a bin is present
    local PROGRAM="${1}"
    command -v "${PROGRAM}" >/dev/null 2>&1
}

_usage() {
cat << EOF
${0##*/} [-h] [-v] [-s] [-m integer] -- minutemen -- Build/Provision Minecraft Servers with ForgeMods Support in under 60 seconds
where:
    -h  show this help text
    -v  verbose
    -s  disable systemd start/enable
    -m  override jvm max heap size (default: ${MC_MAX_HEAP_SIZE})
    -e  specify forgemod version
EOF
}

while getopts ':h :v :s e: m:' option; do
    case "${option}" in
        h|\?) _usage
           exit 0
           ;;
        v) FL_VERBOSE=0
           ;;
        s) FL_DISABLE_SYSTEMD_START=0
           ;;
        m) MC_MAX_HEAP_SIZE="${OPTARG}"
           ;;
        e) M_FORGE_VERSION="${OPTARG}"
           ;;
        :) printf "missing argument for -%s\n" "${OPTARG}"
           _usage
           exit 1
           ;;
    esac
done
shift $((OPTIND - 1))

_if_installed systemctl || _die "systemd not found. No other init systems are currently supported." # Sanity check

if [ -n "${M_FORGE_VERSION}" ]; then
    _validate_semver "${M_FORGE_VERSION}"
else
    _die "-e parameter is missing. You must specify the forgemod version."
fi

if [ -f "./$(basename ${MM_MANIFEST_JSON_PATH})"]; then
    _debug "Found ${MC_MANIFEST_JSON} in working directory. Detected local install."
    FL_LOCAL_INSTALL=0
fi

if [ -f "${MC_DOWNLOADS_CACHE_DIR}/${M_FORGE_INSTALLER_JAR}" ]; then
    _debug "Cached ${M_FORGE_INSTALLER_JAR} found."
    MU_FORGE_DOWNLOAD_CACHED=0
fi

_debug "Checking for user: ${MC_USER}"
id -u "${MC_USER}" >/dev/null 2>&1 && _debug "User: ${MC_USER} found." || {
    _debug "User: ${MC_USER} not found. Creating..."

    #TODO: Check if adduser behaves the same on ubuntu so i can reuse the same code...
    ADDUSER_PASSWORD_PARAM="--system"
    _if_installed dnf && adduser ${ADDUSER_PASSWORD_PARAM} ${MC_USER} >/dev/null 2>&1 && {
        passwd -d "${MC_USER}" || _die "Failed to remove password requirements for user: ${MC_USER}"
        MU_USER_CHECK_PASSED=0
    }

    ADDUSER_PASSWORD_PARAM="--system --disabled-password"
    _if_installed apt-get && adduser "${ADDUSER_PASSWORD_PARAM}" --gecos "" "${MC_USER}" >/dev/null 2>&1 && {
        MU_USER_CHECK_PASSED=0
    }

    # Check if we need to set a password for MC_USER
    if [ -n "${MC_USER_PASSWORD_HASH}" ]; then
        _debug "Setting password for ${MC_USER}"
        usermod -p "${MC_USER_PASSWORD_HASH}" "${MC_USER}" >/dev/null 2>&1 || {
            _die "Failed to set password for ${MC_USER}"
	  }
    fi

    wait && MC_USER_PASSWORD_HASH=""; ADDUSER_PASSWORD_PARAM="" # Clear password variables just in case...

    if [[ $MU_USER_CHECK_PASSED -ne 0 ]]; then
        _die "Failed to run \"adduser ${MC_USER}\". Does the user already exist?"
    fi
}

_init_dir "${MC_USER}" "${MC_PARENT_DIR}"
_init_dir "${MC_USER}" "${MC_INSTALL_DIR} ${MC_BIN_DIR} ${MC_LOG_INSTANCE_DIR} ${MC_DOWNLOADS_CACHE_DIR} ${MC_FORGE_MODS_CACHE_DIR}"

if [[ ${FL_LOCAL_INSTALL} -eq 1 ]]; then # Fetch manifest.json and validate file integrity
    _debug "Fetching ${MM_MANIFEST_JSON_URL}"
    wget -N "${MM_MANIFEST_JSON_URL}" -P "${MC_DOWNLOADS_CACHE_DIR}" || _die "Failed to fetch ${MM_MANIFEST_JSON_URL}"

    MM_MANIFEST_JSON_PATH="${MC_DOWNLOADS_CACHE_DIR}/$(basename ${MM_MANIFEST_JSON_PATH})"
    _compare_checksum "${MM_MANIFEST_JSON_PATH}" "${MM_MANIFEST_JSON_SHA256SUM}"
fi

# Install Ubuntu dependencies
apt_dependencies=(
    "openjdk-8-jdk" # Must be the first index!! openjdk-11-jdk works fine with vanilla Minecraft, but not with Forge
    "jq"
)
_if_installed apt-get && apt-get update -y && apt-get install -y "${apt_dependencies[@]}"

# Install Fedora dependencies
dnf_dependencies=(
    "java-1.8.0-openjdk" # Must be the first index!!
    "jq"
)
_if_installed dnf && dnf update -y && dnf install -y "${dnf_dependencies[@]}"

M_FORGE_DOWNLOAD_URL=$(jq --raw-output --arg _semver "${M_FORGE_VERSION}" '.["java-edition"][].custom.forge[] | select(.version == $_semver) | .url' "${MM_MANIFEST_JSON_PATH}")
M_FORGE_DOWNLOAD_SHA256SUM=$(jq --raw-output --arg _semver "${M_FORGE_VERSION}" '.["java-edition"][].custom.forge[] | select(.version == $_semver) | .sha256' "${MM_MANIFEST_JSON_PATH}")
M_FORGE_INSTALLER_JAR="$(basename ${M_FORGE_DOWNLOAD_URL})"
M_FORGE_INSTALLER_JAR_PATH="${MC_INSTALL_DIR}/${M_FORGE_INSTALLER_JAR}"

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

_compare_checksum "${M_FORGE_INSTALLER_JAR_PATH}" "${M_FORGE_DOWNLOAD_SHA256SUM}"

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

read -r -d '' MC_EXECUTABLE_STOP_CONTENTS << EOF
#!/bin/bash
# ${MC_EXECUTABLE_STOP_PATH} Generated by ${MC_SYSTEMD_SERVICE_NAME}

MC_SERVER_UUID="\${1}"

if [ -z "\${MC_SERVER_UUID}" ]; then
    echo "MC_SERVER_UUID argument required." && exit 1
fi

if [ -n "\${2}" ]; then
    echo "More than one argument provided. I don't know what to do..." && exit 1
fi

${MC_EXECUTABLE_COMMAND_PATH} "\${MC_SERVER_UUID}" say Stopping instance: "\${MC_SERVER_UUID}" in 15 seconds...
sleep 15s
${MC_EXECUTABLE_COMMAND_PATH} "\${MC_SERVER_UUID}" stop

EOF

read -r -d '' MC_EXECUTABLE_BACKUP_CONTENTS << EOF
#!/bin/bash
# ${MC_EXECUTABLE_BACKUP_PATH} Generated by ${MC_SYSTEMD_SERVICE_NAME}

MC_SERVER_UUID="\${1}"

if [ -z "\${MC_SERVER_UUID}" ]; then
    echo "MC_SERVER_UUID argument required." && exit 1
fi

if [ -n "\${2}" ]; then
    echo "More than one argument provided. I don't know what to do..." && exit 1
fi

CURRENT_EPOCH_DATE=\$(date +'%s')

${MC_EXECUTABLE_COMMAND_PATH} "\${MC_SERVER_UUID}" say Backing up instance: "\${MC_SERVER_UUID}".

mkdir -p "${MC_BACKUP_DIR}"/"\${MC_SERVER_UUID}"
tar -zcvf "${MC_BACKUP_DIR}"/"\${MC_SERVER_UUID}"/"\${CURRENT_EPOCH_DATE}".tar.gz "${MC_SERVER_INSTANCES_DIR}"/"\${MC_SERVER_UUID}"/ || {
    echo "Failed to backup instance: \${MC_SERVER_UUID}"
    ${MC_EXECUTABLE_COMMAND_PATH} "\${MC_SERVER_UUID}" say Failed to backup instance: "\${MC_SERVER_UUID}"
    exit 1
}

EOF

read -r -d '' MC_EXECUTABLE_BACKUPRESTORE_CONTENTS << EOF
#!/bin/bash
# ${MC_EXECUTABLE_BACKUP_PATH} Generated by ${MC_SYSTEMD_SERVICE_NAME}

MC_SERVER_UUID="\${1}"
ARCHIVED_EPOCH_DATE="\${2}"

# TODO: Validate second argument is integer

if [ -z "\${MC_SERVER_UUID}" ]; then
    echo "MC_SERVER_UUID argument required." && exit 1
fi

if [ -n "\${3}" ]; then
    echo "More than two arguments provided. I don't know what to do..." && exit 1
fi

${MC_EXECUTABLE_COMMAND_PATH} "\${MC_SERVER_UUID}" say Shutting down instance: "\${MC_SERVER_UUID}" in 15s to restore from backup.
sleep 15s
${MC_EXECUTABLE_STOP_PATH} "\${MC_SERVER_UUID}" || {
    echo "Failed to stop instance: \${MC_SERVER_UUID}"
    exit 1
}

rm -rf "${MC_SERVER_INSTANCES_DIR}"/"\${MC_SERVER_UUID}"/

tar zxvf "${MC_BACKUP_DIR}"/"\${MC_SERVER_UUID}"/"\${ARCHIVED_EPOCH_DATE}".tar.gz -C / || {
    echo "Failed to restore from backup for instance: \${MC_SERVER_UUID}"
    exit 1
}
echo "Successfully restored instance: \${MC_SERVER_UUID} from backup."

EOF

read -r -d '' MC_EXECUTABLE_SAVE_CONTENTS << EOF
#!/bin/bash
# ${MC_EXECUTABLE_BACKUP_PATH} Generated by ${MC_SYSTEMD_SERVICE_NAME}

MC_SERVER_UUID="\${1}"

if [ -z "\${MC_SERVER_UUID}" ]; then
    echo "MC_SERVER_UUID argument required." && exit 1
fi

if [ -n "\${2}" ]; then
    echo "More than one argument provided. I don't know what to do..." && exit 1
fi

${MC_EXECUTABLE_COMMAND_PATH} "\${MC_SERVER_UUID}" say Saving instance: "\${MC_SERVER_UUID}". Server will momentarily become unresponsive.
${MC_EXECUTABLE_COMMAND_PATH} "\${MC_SERVER_UUID}" save-all flush || {
    echo "Failed to backup instance: \${MC_SERVER_UUID}"
    ${MC_EXECUTABLE_COMMAND_PATH} "\${MC_SERVER_UUID}" say Failed to save instance: "\${MC_SERVER_UUID}"
    exit 1
}

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
tail -f "\${MC_SERVER_INSTANCE_PIPE_PATH}" | java -Xmx${MC_MAX_HEAP_SIZE} -Djava.awt.headless=true -jar ${MC_SERVER_INSTANCES_DIR}/\${MC_SERVER_UUID}/${M_FORGE_UNIVERSAL_JAR}
popd > /dev/null

EOF

# We want these files updated each time the script gets run
_debug "Updating files in ${MC_BIN_DIR}"
echo "${MC_EXECUTABLE_START_CONTENTS}" > "${MC_EXECUTABLE_START_PATH}" || _die "Failed to create ${MC_EXECUTABLE_START_PATH}"
echo "${MC_EXECUTABLE_STOP_CONTENTS}" > "${MC_EXECUTABLE_STOP_PATH}" || _die "Failed to create ${MC_EXECUTABLE_STOP_PATH}"
echo "${MC_EXECUTABLE_SAVE_CONTENTS}" > "${MC_EXECUTABLE_SAVE_PATH}" || _die "Failed to create ${MC_EXECUTABLE_SAVE_PATH}"
echo "${MC_EXECUTABLE_COMMAND_CONTENTS}" > "${MC_EXECUTABLE_COMMAND_PATH}" || _die "Failed to create ${MC_EXECUTABLE_COMMAND_PATH}"
echo "${MC_EXECUTABLE_BACKUP_CONTENTS}" > "${MC_EXECUTABLE_BACKUP_PATH}" || _die "Failed to create ${MC_EXECUTABLE_BACKUP_PATH}"
echo "${MC_EXECUTABLE_BACKUPRESTORE_CONTENTS}" > "${MC_EXECUTABLE_BACKUPRESTORE_PATH}" || _die "Failed to create ${MC_EXECUTABLE_BACKUPRESTORE_PATH}"

chown -R "${MC_USER}":"${MC_USER}" "${MC_BIN_DIR}" || _die "Failed to perform chown on ${MC_BIN_DIR}"
chmod "${MC_BIN_DIR_OCTAL}" -R "${MC_BIN_DIR}" || _die "Failed to perform chmod on ${MC_BIN_DIR}"

_debug "Creating ${MC_SYSTEMD_SERVICE_PATH}"
cat << EOF > "${MC_SYSTEMD_SERVICE_PATH}" || _die "Failed to write to ${MC_SYSTEMD_SERVICE_PATH}"
[Unit]
Description=minecraft server: %i
After=network.target

[Service]
Type=simple
User=${MC_USER}
Group=${MC_USER}
WorkingDirectory=${MC_SERVER_INSTANCES_DIR}/%i
ExecStart=/bin/bash ${MC_BIN_DIR}/start %i
ExecStop=/bin/bash ${MC_BIN_DIR}/stop %i
Restart=always
RestartSec=120s

[Install]
WantedBy=multi-user.target

EOF

systemctl start "${MC_SYSTEMD_SERVICE_NAME}@${MC_SERVER_UUID}" && {
    # When executed for the first time, the process will generate eula.txt and exit. We need to accept the EULA
    while [ ! -f "${MC_INSTALL_DIR}/eula.txt" ]
    do
        sleep 2
    done

    # When executed for the first time, the process will exit. We need to accept the EULA
    _debug "Accepting end user license agreement"
    sed -i -e 's/false/true/' "${MC_INSTALL_DIR}/eula.txt" || _die "Failed to modify \"${MC_INSTALL_DIR}/eula.txt\". ${M_FORGE_UNIVERSAL_JAR} failed most likely."
    # Systemd still thinks everything is running as expected, so we have to manually stop it...
    systemctl kill -s SIGKILL "${MC_SYSTEMD_SERVICE_NAME}@${MC_SERVER_UUID}" || _warn "Failed to kill ${MC_SYSTEMD_SERVICE_NAME}@${MC_SERVER_UUID} after first run."
} || _die "Failed to execute ${MC_EXECUTABLE_PATH} via systemd for the first time."

# Install forge mods if present...
for mod in "${MC_FORGE_MODS_CACHE_DIR}"/*.jar; do
    test -f "${mod}" && {
	_debug "Installing mod ${mod} to ${MC_INSTALL_DIR}/mods/${mod}"
        cp "${mod}" "${MC_INSTALL_DIR}/mods/"
    }
done

#TODO: Which is faster? {start..end} or $(seq start end)

# What port should we run the instance on?
_debug "Determining port..."

for port in $(seq ${MC_SERVER_PORT_RANGE_START} ${MC_SERVER_PORT_RANGE_END}); do
   # I've found netcat to be faster than lsof
   nc -vz 127.0.0.1 "${port}" >/dev/null 2>&1
   #lsof -Pi :${port} -sTCP:LISTEN

   if [ $? -eq 0 ]; then
       _debug "Port: ${port} is already in use. Skipping..."
    else
       _debug "Port: ${port} not in use. Selecting..."
       MC_SERVER_PORT_SELECTED="${port}"
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
    _log "To start via systemd (preferred) run: \"systemctl start ${MC_SYSTEMD_SERVICE_NAME}@${MC_SERVER_UUID}\""
    _debug "Skipping systemd start/enable"
fi
