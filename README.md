# React Native Devcontainer Template

[![React Native Devcontainer](https://img.shields.io/badge/React%20Native%20Devcontainer-blue?style=flat&logo=react)](https://github.com/raykavin/devcontainer-react-native)

Single-container React Native template (Expo or bare React Native CLI) optimized for AI coding agents, interactive setup and persistent caches.

## Purpose

Provide one consistent environment where an AI agent (or you) can install, lint, type-check, test and build the Android app from the same shell: no Android Studio, no JDK or SDK setup per machine.

## What's inside

| Tool                        | Version / source                                                                                                                                                                 |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Base image                  | `mcr.microsoft.com/devcontainers/base:2-trixie` (Debian 13)                                                                                                                      |
| Node.js                     | 24 (or 22 / 26), copied from the official `node` image (no nvm)                                                                                                                  |
| JDK                         | Temurin 17 (or 21), copied from the official `eclipse-temurin` image                                                                                                             |
| Android SDK                 | cmdline-tools in the image (`sdkmanager`, `avdmanager` and the new `android` CLI); platform-tools, platform 37, build-tools 37, NDK 27, CMake installed into a persistent volume |
| Gradle                      | Project wrapper (`android/gradlew`), cache in a persistent volume                                                                                                                |
| Expo CLI / React Native CLI | Per project (`npx expo`, `npx react-native`)                                                                                                                                     |
| EAS CLI                     | `eas-cli` (cloud builds for Android and iOS, local Android builds)                                                                                                               |
| @expo/ngrok                 | For `expo start --tunnel` (Expo projects)                                                                                                                                        |
| npm / pnpm                  | npm by default; pnpm configured with `node-linker=hoisted`                                                                                                                       |
| Shell                       | fish                                                                                                                                                                             |

## Project Layout

```
.devcontainer/   Development container: compose, Dockerfile, post-create, post-start, fish config
mobile/          React Native app (created on the first start if it has no package.json)
.vscode/         Launchers: dev server, run on Android, attach to Hermes
Makefile         Task entry point
AGENTS.md        Instructions for AI coding agents
init.sh          Interactive configurator
```

## How to Use

### 1. Clone

```sh
git clone https://github.com/raykavin/devcontainer-react-native.git my-app
cd my-app
```

### 2. Configure

```sh
./init.sh
```

Asks each option with a sensible default (press Enter to accept):

```
Project name [my-app]:
Framework (expo/bare) [expo]:
Expo template (default/blank-typescript/tabs/blank/bare-minimum) [default]:
Application ID (Android package / iOS bundle ID) [com.example.myapp]:
Node.js version (24/22/26) [24]:
JDK version (React Native targets 17) (17/21) [17]:
Package manager (npm/pnpm) [npm]:
Timezone [America/Belem]:
ADB mode (host/container) [host]:
Dev server host [localhost]:
Git user.name / user.email / origin URL / initial branch
```

At the end it offers to delete itself and open VS Code directly inside the dev container, so the build starts without the "Reopen in Container" click. Answer `n` to keep the script; it is idempotent and can be re-run at any time (then use "Dev Containers: Rebuild Container").

All values live in `.devcontainer/devcontainer.json` (`containerEnv`) and `.devcontainer/docker-compose.yml` (build args), so editing by hand also works.

### 3. Start the host ADB server (ADB mode `host`)

The container has no emulator; it talks to the ADB server of your machine, where the emulator (Android Studio / `emulator`) and USB devices live. Start it listening on all interfaces so the container can reach it:

```sh
adb kill-server
adb -a nodaemon server start      # keep this terminal open
```

> `-a` exposes the ADB server to your network. Use it on trusted networks only, or block port 5037 in the host firewall for anything other than the Docker bridge.

### 4. First start

`post-create.sh` runs automatically and:

1. Initializes (or validates) the Git repository and configures `user.name` / `user.email` / `origin`
2. Installs the Android SDK packages from `ANDROID_SDK_PACKAGES` into the `android_sdk` volume and accepts the licenses
3. Checks the ADB connection and lists the devices
4. Installs `eas-cli` (and `pnpm`, `@expo/ngrok` when needed)
5. If `mobile/package.json` does not exist, scaffolds the app with `create-expo-app` (template `EXPO_TEMPLATE`) or `@react-native-community/cli init`, and sets the Android package / iOS bundle ID to `APP_ID`
6. Installs the app dependencies and runs the initial lint
7. Sets fish as the default shell

The first start installs about 2.5 GB of Android SDK/NDK plus the app dependencies (a few minutes on a fast connection). Rebuilds reuse the volumes. The first Gradle build downloads Gradle and the Android dependencies into the `gradle_cache` volume.

### Reuse in an existing project

Copy `.devcontainer/`, `.vscode/`, `Makefile` and `AGENTS.md` into a project that keeps the app in `mobile/`. The post-create script skips every step whose result already exists (`.git`, `mobile/package.json`, installed SDK packages).

## Running the app on a device

| Scenario                                    | Setup                                                                                        | Command                               |
| ------------------------------------------- | -------------------------------------------------------------------------------------------- | ------------------------------------- |
| Emulator on the host                        | ADB mode `host`, emulator running on the host                                                | `make android`                        |
| Phone on USB                                | ADB mode `host` (any OS), or mode `container` + USB passthrough (Linux)                      | `make android`                        |
| Phone on Wi-Fi, ADB debugging (Android 11+) | ADB mode `container`: `make adb-pair DEVICE=ip:port`, then `make adb-connect DEVICE=ip:port` | `make android`                        |
| Phone with Expo Go, same Wi-Fi              | Dev server host = your LAN IP (`init.sh`), port 8081 allowed in the host firewall            | `make start`, scan the QR code        |
| Phone with Expo Go, any network             | Nothing                                                                                      | `make start-tunnel`, scan the QR code |

How the device reaches Metro: port 8081 is published on the host. ADB-connected devices use `localhost:8081`, mapped by `adb reverse` (Expo and the React Native CLI run it automatically; `make adb-reverse` does it by hand, also for the API port). Expo Go over Wi-Fi uses the host's LAN IP, which is why `REACT_NATIVE_PACKAGER_HOSTNAME` must be set to it in that case.

Calling a backend from the app: `localhost` on the phone is the phone itself. With `make adb-reverse` the device's `localhost:8080` points to the host's port 8080, so `EXPO_PUBLIC_API_BASE_URL=http://localhost:8080` works for ADB-connected devices. For Expo Go over Wi-Fi use `http://<host LAN IP>:8080`.

### iOS

iOS builds need macOS and Xcode, so they cannot run in a Linux container. You can still:

- run the app on an iPhone with **Expo Go** (`make start` / `make start-tunnel`) while it only uses modules included in Expo Go;
- build it in the cloud with **EAS Build**: `make eas-build-ios` (Apple Developer account required).

## Builds

|                     | Command                  | Output                                             |
| ------------------- | ------------------------ | -------------------------------------------------- |
| Debug APK           | `make apk-debug`         | `mobile/android/app/build/outputs/apk/debug/`      |
| Release APK         | `make apk`               | `mobile/android/app/build/outputs/apk/release/`    |
| Play Store bundle   | `make aab`               | `mobile/android/app/build/outputs/bundle/release/` |
| EAS cloud (Android) | `make eas-build-android` | Expo dashboard                                     |
| EAS cloud (iOS)     | `make eas-build-ios`     | Expo dashboard                                     |
| EAS local (Android) | `make eas-build-local`   | `mobile/`                                          |

Expo projects generate `android/` on demand (`npx expo prebuild`); the Makefile does it before local builds. Local builds compile native code for every ABI; pass `GRADLE_ARGS=-PreactNativeArchitectures=arm64-v8a` (or `x86_64` for emulators) for a much faster build. `make android` already builds only the ABI of the connected device. The release builds of both templates are signed with the debug keystore until you configure your own signing key. EAS commands need `eas login` once (the session persists in the `expo_state` volume) and `eas build:configure` to create `eas.json`.

## Makefile Targets

```
make start              # Metro / Expo dev server (:8081)
make start-clear        # Dev server with an empty bundler cache
make start-tunnel       # Expo dev server through a tunnel
make android            # Build the debug app and run it on the device/emulator (SERIAL=...)
make prebuild           # Expo: generate android/ (PREBUILD_ARGS=--clean)
make devices            # ADB devices
make adb-reverse        # Forward device ports 8081 and API_PORT to the dev machine
make adb-pair           # Wi-Fi pairing (DEVICE=ip:port)
make adb-connect        # Wi-Fi connection (DEVICE=ip:port)
make logcat             # React Native logs from the device
make lint               # Lint script
make test               # Test script
make typecheck          # tsc --noEmit
make doctor             # expo-doctor / react-native doctor
make apk-debug          # Debug APK (Gradle, inside the container)
make apk                # Release APK
make aab                # Release Android App Bundle
make install-apk        # Install the release APK
make clean              # Clear bundler caches and Gradle outputs
make eas-build-android  # EAS cloud build, Android (EAS_PROFILE=development)
make eas-build-ios      # EAS cloud build, iOS
make eas-build-local    # EAS build of Android inside the container
```

## Configuration Reference

`containerEnv` in `.devcontainer/devcontainer.json`:

| Variable                         | Purpose                                                                                    |
| -------------------------------- | ------------------------------------------------------------------------------------------ |
| `PROJECT_NAME`                   | npm package / app name used when scaffolding                                               |
| `APP_FRAMEWORK`                  | `expo` or `bare` (selects the scaffolder and the Makefile commands)                        |
| `EXPO_TEMPLATE`                  | `create-expo-app` template: `default`, `blank-typescript`, `tabs`, `blank`, `bare-minimum` |
| `APP_ID`                         | Android `applicationId` / iOS bundle identifier                                            |
| `PKG_MANAGER`                    | `npm` or `pnpm`                                                                            |
| `ANDROID_SDK_PACKAGES`           | `sdkmanager` packages installed on create (Gradle downloads any other version it needs)    |
| `ADB_SERVER_SOCKET`              | `tcp:host.docker.internal:5037` (host ADB) or `tcp:localhost:5037` (ADB in the container)  |
| `REACT_NATIVE_PACKAGER_HOSTNAME` | Host announced by the dev server: `localhost` (ADB devices) or the host LAN IP (Expo Go)   |
| `EXPO_PUBLIC_API_BASE_URL`       | Example public variable inlined into the Expo bundle                                       |
| `GIT_*`                          | Git identity, remote and initial branch                                                    |

## Persistent Caches

Named volumes survive container rebuilds:

```
android_sdk   →  /opt/android-sdk        (SDK, NDK, CMake, licenses)
gradle_cache  →  ~/.gradle               (Gradle distributions and dependencies)
android_user  →  ~/.android              (ADB keys: devices stay authorized)
node_modules  →  /workspaces/mobile/node_modules
npm_cache     →  ~/.npm
pnpm_store    →  ~/.local/share/pnpm/store
expo_state    →  ~/.expo                 (Expo / EAS login)
claude_code   →  ~/.claude               (Claude Code credentials, settings, history — if installed manually)
```

## Troubleshooting

- **`make devices` is empty (ADB mode `host`)**: the host server must run with `-a` (step 3). On Linux, check that the firewall allows the Docker bridge to reach port 5037.
- **Apple Silicon**: the Android SDK only ships linux/x86_64 binaries, so the container runs as `linux/amd64` under Rosetta. Enable "Use Rosetta for x86_64/amd64 emulation" in Docker Desktop.
- **Gradle runs out of memory**: React Native builds need 6–8 GB of RAM available to Docker (Docker Desktop → Resources).
- **Expo Go cannot connect over Wi-Fi**: the host LAN IP changed (re-run `init.sh` or edit `REACT_NATIVE_PACKAGER_HOSTNAME`), or the host firewall blocks port 8081. `make start-tunnel` works around both.
- **React Native DevTools (`j` in the dev server)** cannot open a browser inside the container: open `http://localhost:8081/json/list` on the host and use the `devtoolsFrontendUrl` in Chrome or Edge, or use the "Attach to Hermes" launcher in VS Code.
- **Missing SDK/NDK version**: Gradle installs it on demand into the `android_sdk` volume; to pre-install, add it to `ANDROID_SDK_PACKAGES` or run `sdkmanager "ndk;<version>"`.

## AI Agents

- `AGENTS.md` at the root documents every command and convention; Claude Code and similar tools read it automatically. Expo projects also get, from `create-expo-app`, their own `mobile/AGENTS.md` and a `mobile/.claude/settings.json` that enables Expo's official Claude Code plugin.
- The Claude Code CLI is **not** installed automatically; install it manually inside the container if you use it (`npm install -g @anthropic-ai/claude-code`). Its state persists across rebuilds via the `claude_code` volume.

## Notes

- This is a personal template, meant to evolve over time
- Default shell inside the container is fish
- The container joins the `devnet` Docker network, the same one used by [devcontainer-go-react](https://github.com/raykavin/devcontainer-go-react), so it can reach that backend container by name

---

Built to make mobile development with AI agents easier.
