#!/bin/sh
# ============================================================================
# Interactive devcontainer configurator (React Native)
#
# Run this BEFORE opening the folder in VS Code. It asks a few questions and
# rewrites the values inside .devcontainer/devcontainer.json and
# .devcontainer/docker-compose.yml. Safe to re-run at any time.
#
# Usage:  ./init.sh
# ============================================================================
set -e

DEVCONTAINER_JSON=".devcontainer/devcontainer.json"
COMPOSE_FILE=".devcontainer/docker-compose.yml"

[ -f "$DEVCONTAINER_JSON" ] || { echo "Run this script from the repository root."; exit 1; }

# --- helpers ----------------------------------------------------------------
ask() {
  # ask "Question" "default"
  printf "%s [%s]: " "$1" "$2" >&2
  read -r answer
  [ -z "$answer" ] && answer="$2"
  echo "$answer"
}

ask_choice() {
  # ask_choice "Question" "opt1 opt2 ..." "default"
  while true; do
    v=$(ask "$1 ($(echo "$2" | tr ' ' '/'))" "$3")
    for opt in $2; do
      [ "$v" = "$opt" ] && echo "$v" && return
    done
    echo "  Invalid option: $v" >&2
  done
}

ask_match() {
  # ask_match "Question" "default" "extended regex" "hint shown on invalid input"
  while true; do
    v=$(ask "$1" "$2")
    if echo "$v" | grep -Eq "$3"; then echo "$v"; return; fi
    echo "  Invalid value: $v ($4)" >&2
  done
}

# In-place sed that works with both GNU sed (Linux) and BSD sed (macOS)
sed_inplace() {
  file="$1"; shift
  sed -i.bak "$@" "$file" && rm -f "$file.bak"
}

json_set() {
  # json_set KEY VALUE  -> rewrites "KEY": "..." inside devcontainer.json
  sed_inplace "$DEVCONTAINER_JSON" -e "s|\"$1\": \"[^\"]*\"|\"$1\": \"$2\"|"
}

# --- current values as defaults ----------------------------------------------
cur() { grep -o "\"$1\": \"[^\"]*\"" "$DEVCONTAINER_JSON" | head -1 | sed 's/.*: "\(.*\)"/\1/'; }
cur_arg() { grep -o "$1: \"[^\"]*\"" "$COMPOSE_FILE" | head -1 | sed 's/.*"\(.*\)"/\1/'; }

detect_lan_ip() {
  if command -v ip > /dev/null 2>&1; then
    ip route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}'
  elif command -v ipconfig > /dev/null 2>&1; then
    ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true
  fi
}

case "$(cur ADB_SERVER_SOCKET)" in
  *host.docker.internal*) CUR_ADB_MODE="host" ;;
  *) CUR_ADB_MODE="container" ;;
esac
if grep -q "^    privileged: true" "$COMPOSE_FILE"; then CUR_USB="y"; else CUR_USB="n"; fi

echo "=== React Native devcontainer setup ==="
echo ""

PROJECT_NAME=$(ask_match "Project name" "$(cur PROJECT_NAME)" '^[a-z][a-z0-9-]*$' "lowercase letters, digits and '-', starting with a letter")
APP_FRAMEWORK=$(ask_choice "Framework" "expo bare" "$(cur APP_FRAMEWORK)")
EXPO_TEMPLATE=$(cur EXPO_TEMPLATE)
if [ "$APP_FRAMEWORK" = "expo" ]; then
  EXPO_TEMPLATE=$(ask_choice "Expo template" "default blank-typescript tabs blank bare-minimum" "$EXPO_TEMPLATE")
fi
APP_ID=$(ask_match "Application ID (Android package / iOS bundle ID)" "$(cur APP_ID)" \
  '^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$' "reverse domain, e.g. com.company.app")
NODE_VERSION=$(ask_choice "Node.js version" "24 22 26" "$(cur_arg NODE_VERSION)")
JAVA_VERSION=$(ask_choice "JDK version (React Native targets 17)" "17 21" "$(cur_arg JAVA_VERSION)")
PKG_MANAGER=$(ask_choice "Package manager" "npm pnpm" "$(cur PKG_MANAGER)")
TIMEZONE=$(ask "Timezone" "$(cur TZ)")

echo ""
echo "ADB server:"
echo "  host      - the container uses the ADB server running on your machine (emulator and USB devices"
echo "              stay on the host). Start it with: adb kill-server && adb -a nodaemon server start"
echo "  container - the container runs its own ADB server (Wi-Fi debugging, or USB passthrough on Linux)"
ADB_MODE=$(ask_choice "ADB mode" "host container" "$CUR_ADB_MODE")
USB_PASSTHROUGH="n"
if [ "$ADB_MODE" = "container" ]; then
  USB_PASSTHROUGH=$(ask_choice "Pass host USB devices into the container? (Linux hosts only, runs privileged)" "y n" "$CUR_USB")
fi

echo ""
LAN_IP=$(detect_lan_ip)
echo "Dev server host announced to devices (QR code / deep links):"
echo "  localhost - emulator and ADB-connected devices (ports forwarded by 'adb reverse')"
echo "  LAN IP    - phones on the same Wi-Fi using Expo Go${LAN_IP:+ (detected: $LAN_IP)}"
PACKAGER_HOSTNAME=$(ask "Dev server host" "$(cur REACT_NATIVE_PACKAGER_HOSTNAME)")

echo ""
GIT_USERNAME=$(ask "Git user.name"                     "$(cur GIT_CONFIG_DEV_USERNAME)")
GIT_EMAIL=$(ask    "Git user.email"                    "$(cur GIT_CONFIG_DEV_EMAIL)")
GIT_REPO=$(ask     "Git remote (origin) URL"           "$(cur GIT_REPO_ADDRESS)")
GIT_BRANCH=$(ask   "Initial branch name"               "$(cur GIT_INIT_DEFAULT_BRANCH)")

if [ "$ADB_MODE" = "host" ]; then
  ADB_SERVER_SOCKET="tcp:host.docker.internal:5037"
else
  ADB_SERVER_SOCKET="tcp:localhost:5037"
fi

# --- devcontainer.json --------------------------------------------------------
echo ""
echo "> Updating $DEVCONTAINER_JSON"
sed_inplace "$DEVCONTAINER_JSON" -e "s|\"name\": \"[^\"]*\"|\"name\": \"$PROJECT_NAME DevContainer (React Native)\"|"
json_set PROJECT_NAME                   "$PROJECT_NAME"
json_set APP_FRAMEWORK                  "$APP_FRAMEWORK"
json_set EXPO_TEMPLATE                  "$EXPO_TEMPLATE"
json_set APP_ID                         "$APP_ID"
json_set PKG_MANAGER                    "$PKG_MANAGER"
json_set TZ                             "$TIMEZONE"
json_set ADB_SERVER_SOCKET              "$ADB_SERVER_SOCKET"
json_set REACT_NATIVE_PACKAGER_HOSTNAME "$PACKAGER_HOSTNAME"
json_set GIT_CONFIG_DEV_USERNAME        "$GIT_USERNAME"
json_set GIT_CONFIG_DEV_EMAIL           "$GIT_EMAIL"
json_set GIT_REPO_ADDRESS               "$GIT_REPO"
json_set GIT_INIT_DEFAULT_BRANCH        "$GIT_BRANCH"

# --- docker-compose.yml -------------------------------------------------------
echo "> Updating $COMPOSE_FILE"
sed_inplace "$COMPOSE_FILE" \
  -e "s|container_name: .*|container_name: ${PROJECT_NAME}_mobile_dev|" \
  -e "s|NODE_VERSION: \"[^\"]*\"|NODE_VERSION: \"$NODE_VERSION\"|" \
  -e "s|JAVA_VERSION: \"[^\"]*\"|JAVA_VERSION: \"$JAVA_VERSION\"|" \
  -e "s|TZ: \"[^\"]*\"|TZ: \"$TIMEZONE\"|"

if [ "$USB_PASSTHROUGH" = "y" ]; then
  sed_inplace "$COMPOSE_FILE" \
    -e "s|^      # - /dev/bus/usb:/dev/bus/usb|      - /dev/bus/usb:/dev/bus/usb|" \
    -e "s|^    # privileged: true|    privileged: true|"
else
  sed_inplace "$COMPOSE_FILE" \
    -e "s|^      - /dev/bus/usb:/dev/bus/usb|      # - /dev/bus/usb:/dev/bus/usb|" \
    -e "s|^    privileged: true|    # privileged: true|"
fi

echo ""
echo "> Done. Summary:"
echo "    Project:      $PROJECT_NAME ($APP_ID)"
if [ "$APP_FRAMEWORK" = "expo" ]; then
  echo "    Framework:    Expo (template: $EXPO_TEMPLATE)"
else
  echo "    Framework:    React Native CLI (bare)"
fi
echo "    Node:         $NODE_VERSION ($PKG_MANAGER)"
echo "    JDK:          $JAVA_VERSION"
echo "    Timezone:     $TIMEZONE"
echo "    ADB:          $ADB_MODE ($ADB_SERVER_SOCKET)$( [ "$USB_PASSTHROUGH" = "y" ] && echo ", USB passthrough" )"
echo "    Dev server:   $PACKAGER_HOSTNAME:8081"
echo "    Git:          $GIT_USERNAME <$GIT_EMAIL> -> $GIT_REPO ($GIT_BRANCH)"
echo ""
if [ "$ADB_MODE" = "host" ]; then
  echo "Before opening the container, start the host ADB server listening on all interfaces:"
  echo "    adb kill-server && adb -a nodaemon server start"
  echo ""
fi

# --- open in VS Code + self-delete -------------------------------------------
OPEN_NOW=$(ask_choice "Delete init.sh and open VS Code in the dev container now?" "y n" "y")

if [ "$OPEN_NOW" = "y" ]; then
  # Encode the absolute folder path as lowercase hex, as required by the
  # vscode-remote://dev-container+<hex> URI scheme
  FOLDER="$(pwd)"
  HEX=$(printf '%s' "$FOLDER" | od -A n -t x1 | tr -d ' \n')

  rm -- "$0"
  echo "> init.sh removed"

  if command -v code > /dev/null 2>&1; then
    echo "> Opening VS Code directly in the dev container (build starts automatically)"
    exec code --folder-uri "vscode-remote://dev-container+${HEX}/workspaces"
  else
    echo "'code' CLI not found. Open the folder manually and choose 'Reopen in Container'."
  fi
else
  echo "Open the folder in VS Code and choose 'Reopen in Container'."
  echo "If the container was already built, run 'Dev Containers: Rebuild Container'."
fi
