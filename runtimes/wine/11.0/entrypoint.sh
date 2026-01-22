#!/bin/bash
set -e

cd /home/container

# Information output
echo "Running on Debian $(cat /etc/debian_version)"
echo "Current timezone: $(cat /etc/timezone)"
wine --version

# Make internal Docker IP address available to processes.
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# Set an ammount of colums for wine to not wrap
stty columns 250 || true

## just in case someone removed the defaults.
if [ "${STEAM_USER}" == "" ]; then
    echo -e "steam user is not set.\n"
    echo -e "Using anonymous user.\n"
    STEAM_USER=anonymous
    STEAM_PASS=""
    STEAM_AUTH=""
else
    echo -e "user set to ${STEAM_USER}"
fi

## if auto_update is not set or to 1 update
if [ -z ${AUTO_UPDATE} ] || [ "${AUTO_UPDATE}" == "1" ]; then
    # Update Source Server
    if [ ! -z ${SRCDS_APPID} ]; then
        ./steamcmd/steamcmd.sh +force_install_dir /home/container +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} $( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) +app_update 1007 +app_update ${SRCDS_APPID} $( [[ -z ${SRCDS_BETAID} ]] || printf %s "-beta ${SRCDS_BETAID}" ) $( [[ -z ${SRCDS_BETAPASS} ]] || printf %s "-betapassword ${SRCDS_BETAPASS}" ) $( [[ -z ${HLDS_GAME} ]] || printf %s "+app_set_config 90 mod ${HLDS_GAME}" ) $( [[ -z ${VALIDATE} ]] || printf %s "validate" ) +quit
    else
        echo -e "No appid set. Starting Server"
    fi
else
    echo -e "Not updating game server as auto update was set to 0. Starting Server"
fi

if [[ $XVFB == 1 ]]; then
    Xvfb :0 -screen 0 ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}x${DISPLAY_DEPTH} &
fi

# Install necessary to run packages
echo "First launch will throw some errors. Ignore them"

mkdir -p $WINEPREFIX

# Check if wine-gecko required and install it if so
if [[ $WINETRICKS_RUN =~ gecko ]]; then
    echo "Installing Gecko"
    WINETRICKS_RUN=${WINETRICKS_RUN/gecko}

    if [ ! -f "$WINEPREFIX/gecko_x86.msi" ]; then
        wget -q -O $WINEPREFIX/gecko_x86.msi http://dl.winehq.org/wine/wine-gecko/2.47.4/wine_gecko-2.47.4-x86.msi
    fi

    if [ ! -f "$WINEPREFIX/gecko_x86_64.msi" ]; then
        wget -q -O $WINEPREFIX/gecko_x86_64.msi http://dl.winehq.org/wine/wine-gecko/2.47.4/wine_gecko-2.47.4-x86_64.msi
    fi

    wine msiexec /i $WINEPREFIX/gecko_x86.msi /qn /quiet /norestart /log $WINEPREFIX/gecko_x86_install.log
    wine msiexec /i $WINEPREFIX/gecko_x86_64.msi /qn /quiet /norestart /log $WINEPREFIX/gecko_x86_64_install.log
fi

# Check if wine-mono required and install it if so
if [[ $WINETRICKS_RUN =~ mono ]]; then
    echo "Installing mono"
    WINETRICKS_RUN=${WINETRICKS_RUN/mono}
    MONO_VERSION=$(curl -s https://api.github.com/repos/wine-mono/wine-mono/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
    MONO_URL="https://github.com/wine-mono/wine-mono/releases/download/${MONO_VERSION}/wine-mono-${MONO_VERSION#wine-mono-}-x86.msi"

    if [ -z "$MONO_VERSION" ]; then
        echo "Failed to fetch latest Wine Mono version."
    else
        if [ ! -f "$WINEPREFIX/mono.msi" ]; then
            wget -q -O $WINEPREFIX/mono.msi $MONO_URL
        fi

        wine msiexec /i $WINEPREFIX/mono.msi /qn /quiet /norestart /log $WINEPREFIX/mono_install.log
    fi
fi

# List and install other packages
for trick in $WINETRICKS_RUN; do
    echo "Installing $trick"
    winetricks -q $trick
done

# --------------------------------------------------------------------
# Wine 11+ lifecycle handling
#
# Pterodactyl provides STARTUP. We rewrite {{VAR}} into ${VAR}, then run it.
# On Wine 11+, the PID returned by backgrounding `wine ... &` is not reliable
# as "the actual server PID". That can cause Wings to restart-loop.
#
# Optional env vars to keep this runtime generic:
#   WINE_PROCESS_MATCH : pgrep -f match string to find the real server PID
#   LOG_FILE           : path to log file to tail into console
#   PID_WAIT_SECONDS   : how long to wait for WINE_PROCESS_MATCH (default 60)
# --------------------------------------------------------------------

PID_WAIT_SECONDS="${PID_WAIT_SECONDS:-60}"

# Replace Startup Variables
MODIFIED_STARTUP=$(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo ":/home/container$ ${MODIFIED_STARTUP}"

# Start the server in background so we can supervise it
# NOTE: we intentionally do not trust $! on Wine 11+ unless we have no better choice.
eval ${MODIFIED_STARTUP} &
LAUNCH_PID=$!
echo "Launched PID (not trusted on Wine 11+): ${LAUNCH_PID}"

SERVER_PID=""

# If WINE_PROCESS_MATCH is set, use it to find the real server PID.
if [ ! -z "${WINE_PROCESS_MATCH:-}" ]; then
    echo "Waiting for server PID match: ${WINE_PROCESS_MATCH} (timeout ${PID_WAIT_SECONDS}s)"
    for i in $(seq 1 "${PID_WAIT_SECONDS}"); do
        SERVER_PID="$(pgrep -n -f "${WINE_PROCESS_MATCH}" 2>/dev/null || true)"
        if [ ! -z "$SERVER_PID" ]; then
            break
        fi
        sleep 1
    done

    if [ -z "$SERVER_PID" ]; then
        echo "ERROR: Server process not found after ${PID_WAIT_SECONDS}s."
        echo "--- processes (wine/wineserver/server) ---"
        ps -eo pid,args | grep -E 'wine|wineserver' | grep -v grep || true
        exit 1
    fi

    echo "Detected server PID: ${SERVER_PID}"
else
    echo "WINE_PROCESS_MATCH not set; falling back to LAUNCH_PID=${LAUNCH_PID} (may be unreliable on Wine 11+)"
    SERVER_PID="${LAUNCH_PID}"
fi

# If LOG_FILE is set, tail it into the console.
# If not set, we just wait on the PID.
if [ ! -z "${LOG_FILE:-}" ]; then
    # allow simple env var expansion in LOG_FILE
    EXPANDED_LOG_FILE="$(bash -lc "echo \"${LOG_FILE}\"")"
    echo "LOG_FILE set: ${EXPANDED_LOG_FILE}"

    # wait a bit for log file to appear
    for i in $(seq 1 30); do
        [ -f "${EXPANDED_LOG_FILE}" ] && break
        sleep 1
    done

    if [ -f "${EXPANDED_LOG_FILE}" ]; then
        echo "Tailing: ${EXPANDED_LOG_FILE} (will exit when PID ${SERVER_PID} exits)"
        tail -c0 -F "${EXPANDED_LOG_FILE}" --pid="${SERVER_PID}"
        exit 0
    else
        echo "WARN: Log file not found after 30s: ${EXPANDED_LOG_FILE}"
        echo "Continuing without tail."
    fi
fi

# No LOG_FILE (or not found): wait for the server PID to exit
echo "Waiting for server PID ${SERVER_PID} to exit..."
while kill -0 "${SERVER_PID}" 2>/dev/null; do
    sleep 2
done

echo "Server process exited."
exit 0
