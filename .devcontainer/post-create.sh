#!/bin/sh
set -e

log() { echo "> $*"; }
info() { echo "  $*"; }
warn() { echo "  [!] $*"; }

WORKSPACE="/workspaces"
MOBILE_DIR="$WORKSPACE/mobile"

PROJECT_NAME="${PROJECT_NAME:-my-app}"
APP_FRAMEWORK="${APP_FRAMEWORK:-expo}"
EXPO_TEMPLATE="${EXPO_TEMPLATE:-default}"
APP_ID="${APP_ID:-com.example.myapp}"
PKG_MANAGER="${PKG_MANAGER:-npm}"
ANDROID_SDK_PACKAGES="${ANDROID_SDK_PACKAGES:-platform-tools}"

# --- Git ----------------------------------------------------------------------
log "Configuring Git"
cd "$WORKSPACE"

if [ ! -d ".git" ]; then
  info "Initializing repository (branch: $GIT_INIT_DEFAULT_BRANCH)"
  git init --initial-branch="$GIT_INIT_DEFAULT_BRANCH"
else
  info "Repository already exists, skipping init"
fi

git config --global --add safe.directory "$WORKSPACE"
git config --global user.name  "$GIT_CONFIG_DEV_USERNAME"
git config --global user.email "$GIT_CONFIG_DEV_EMAIL"

if git remote | grep -q "^origin$"; then
  CURRENT_URL="$(git remote get-url origin)"
  if [ "$CURRENT_URL" != "$GIT_REPO_ADDRESS" ]; then
    info "Updating origin URL"
    git remote set-url origin "$GIT_REPO_ADDRESS"
  else
    info "Origin already configured correctly"
  fi
else
  info "Adding origin remote"
  git remote add origin "$GIT_REPO_ADDRESS"
fi

if git show-ref --verify --quiet "refs/heads/$GIT_INIT_DEFAULT_BRANCH"; then
  git branch --set-upstream-to="origin/$GIT_INIT_DEFAULT_BRANCH" "$GIT_INIT_DEFAULT_BRANCH" 2>/dev/null || true
fi

# --- Volumes and shell ----------------------------------------------------------
log "Checking cache volume ownership"
sh "$WORKSPACE/.devcontainer/post-start.sh"

log "Linking fish configuration"
mkdir -p "$HOME/.config/fish/conf.d"
ln -sf "$WORKSPACE/.devcontainer/config.fish" "$HOME/.config/fish/conf.d/devcontainer.fish"

# --- Android SDK ----------------------------------------------------------------
# The SDK lives in the android_sdk volume: packages installed here (and the ones
# Gradle downloads on demand, e.g. another NDK version) survive rebuilds.
log "Installing Android SDK packages"
info "$ANDROID_SDK_PACKAGES"

yes | sdkmanager --licenses > /dev/null 2>&1 || true

SDK_LOG="$(mktemp)"
# Word splitting is intended: one sdkmanager package per word
# shellcheck disable=SC2086
if ! yes | sdkmanager $ANDROID_SDK_PACKAGES > "$SDK_LOG" 2>&1; then
  tail -n 30 "$SDK_LOG"
  echo "[✘] sdkmanager failed (full log: $SDK_LOG)"
  exit 1
fi
rm -f "$SDK_LOG"

log "Checking ADB server ($ADB_SERVER_SOCKET)"
# Output goes to /dev/null so a locally started ADB daemon does not hold this
# script's stdout open
if timeout 15 adb devices > /dev/null 2>&1; then
  adb devices -l | tail -n +2 | sed '/^$/d; s/^/  /'
else
  case "$ADB_SERVER_SOCKET" in
    *host.docker.internal*)
      warn "Host ADB server not reachable. On the HOST run:"
      warn "  adb kill-server && adb -a nodaemon server start"
      ;;
    *)
      warn "Local ADB server did not start; run 'adb devices' to see the error"
      ;;
  esac
fi

# --- Node global CLIs -----------------------------------------------------------
# NPM_CONFIG_PREFIX points to ~/.npm-global (see Dockerfile), so no sudo is needed
log "Installing global Node CLIs"

if [ "$PKG_MANAGER" = "pnpm" ]; then
  if ! command -v pnpm > /dev/null 2>&1; then
    info "pnpm"
    npm install -g pnpm --silent
  fi
  # Without an explicit store-dir pnpm creates a store on the project's
  # filesystem (the bind-mounted workspace) instead of the pnpm_store volume
  pnpm config set store-dir /home/vscode/.local/share/pnpm/store --global
fi

info "eas-cli"
npm install -g eas-cli --silent

if [ "$APP_FRAMEWORK" = "expo" ]; then
  info "@expo/ngrok (used by 'expo start --tunnel')"
  npm install -g @expo/ngrok@^4.1.0 --silent
fi

# --- Mobile app -----------------------------------------------------------------
if [ -f "$MOBILE_DIR/package.json" ]; then
  log "mobile/package.json found, skipping app scaffolding"
else
  log "Scaffolding a new React Native app in mobile/ ($APP_FRAMEWORK)"

  # mobile/ may have been created by Docker (as root) for the node_modules volume
  sudo mkdir -p "$MOBILE_DIR"
  sudo chown vscode:vscode "$MOBILE_DIR"

  # Scaffold in a temp dir and copy back: the generators refuse non-empty
  # targets, and mobile/node_modules is a mount point that cannot be removed
  SCAFFOLD_ROOT="$(mktemp -d)"
  APP_DIR="$SCAFFOLD_ROOT/$PROJECT_NAME"

  case "$APP_FRAMEWORK" in
    expo)
      info "create-expo-app (template: $EXPO_TEMPLATE)"
      npx --yes create-expo-app@latest "$APP_DIR" --template "$EXPO_TEMPLATE" --no-install --yes
      ;;
    bare)
      # React Native CLI project names must be alphanumeric: my-app -> MyApp
      RN_NAME="$(echo "$PROJECT_NAME" | sed -E 's/(^|[^a-zA-Z0-9]+)([a-zA-Z0-9])/\U\2/g')"
      info "@react-native-community/cli init $RN_NAME (package: $APP_ID)"
      npx --yes @react-native-community/cli@latest init "$RN_NAME" \
        --directory "$APP_DIR" \
        --package-name "$APP_ID" \
        --skip-install \
        --skip-git-init \
        --install-pods false
      ;;
    *)
      echo "[✘] Unknown APP_FRAMEWORK '$APP_FRAMEWORK' (expected: expo or bare)"
      exit 1
      ;;
  esac

  # The repository root already is the Git repository
  rm -rf "$APP_DIR/.git" "$APP_DIR/node_modules"
  cp -a "$APP_DIR/." "$MOBILE_DIR/"
  rm -rf "$SCAFFOLD_ROOT"
  rm -f "$MOBILE_DIR/.gitkeep"

  if [ "$APP_FRAMEWORK" = "expo" ] && [ -f "$MOBILE_DIR/app.json" ]; then
    info "Setting android.package and ios.bundleIdentifier to $APP_ID"
    node -e '
      const fs = require("fs");
      const [file, appId] = process.argv.slice(1);
      const json = JSON.parse(fs.readFileSync(file, "utf8"));
      json.expo.android = { ...json.expo.android, package: appId };
      json.expo.ios = { ...json.expo.ios, bundleIdentifier: appId };
      fs.writeFileSync(file, JSON.stringify(json, null, 2) + "\n");
    ' "$MOBILE_DIR/app.json" "$APP_ID"
  fi

  if [ "$PKG_MANAGER" = "pnpm" ]; then
    info "pnpm: node-linker=hoisted (React Native tooling expects a flat node_modules)"
    echo "node-linker=hoisted" >> "$MOBILE_DIR/.npmrc"
  fi
fi

cd "$MOBILE_DIR"

log "Installing mobile dependencies ($PKG_MANAGER)"
"$PKG_MANAGER" install

log "Verifying installed tools"
info "node      $(node --version)"
info "$PKG_MANAGER $("$PKG_MANAGER" --version)"
info "java      $(java -version 2>&1 | head -n 1)"
info "adb       $(adb version | head -n 1)"
# stderr carries the "sdkmanager is deprecated, use the android CLI" notice
info "sdkmgr    $(sdkmanager --version 2>/dev/null)"
info "eas-cli   $(eas --version 2>/dev/null | head -n 1)"

if node -e 'process.exit(require("./package.json").scripts?.lint ? 0 : 1)'; then
  # CI=1 keeps `expo lint` from prompting
  if [ "$APP_FRAMEWORK" = "expo" ] && ! ls eslint.config.* .eslintrc* > /dev/null 2>&1; then
    # Without an ESLint config, the first `expo lint` only installs and
    # configures ESLint (eslint-config-expo) and then exits with an error
    log "Configuring ESLint (expo lint)"
    CI=1 npx expo lint > /dev/null 2>&1 || true
  fi
  log "Running initial lint"
  CI=1 "$PKG_MANAGER" run lint || true
fi

# Safe to change the login shell now: everything that runs `su vscode -c` already finished
log "Setting fish as default shell for vscode user"
sudo chsh -s /usr/bin/fish vscode || true

cd "$WORKSPACE"
log "Checking out develop branch"
if git show-ref --verify --quiet "refs/heads/develop"; then
  if git rev-parse --abbrev-ref HEAD | grep -q "^develop$"; then
    info "Already on develop branch"
  else
    info "Switching to develop branch"
    git checkout develop
  fi
fi

echo ""
log "Post-create completed successfully"
info "Dev server: make start     (Metro / Expo on :8081)"
info "Android:    make android   (build + install on the connected device or emulator)"
info "Devices:    make devices   (ADB via $ADB_SERVER_SOCKET)"
