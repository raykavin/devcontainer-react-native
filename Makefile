PROJECT_NAME  ?= my-app
APP_FRAMEWORK ?= expo
PKG_MANAGER   ?= npm
MOBILE_DIR    ?= mobile
API_PORT      ?= 8080
EAS_PROFILE   ?= development
# Target a single device when several are connected: make android SERIAL=emulator-5554
SERIAL        ?=
# Device address for Wi-Fi debugging: make adb-connect DEVICE=192.168.0.10:5555
DEVICE        ?=
# Extra Gradle arguments for local builds, e.g. a single ABI for faster builds:
# make apk-debug GRADLE_ARGS=-PreactNativeArchitectures=arm64-v8a
GRADLE_ARGS   ?=

ADB         := adb $(if $(SERIAL),-s $(SERIAL))
ANDROID_DIR := $(MOBILE_DIR)/android

# Runs a package.json script only when it is defined (failures still propagate)
define run_script
	@cd $(MOBILE_DIR) && if node -e 'process.exit(require("./package.json").scripts?.["$(1)"] ? 0 : 1)'; then \
		$(PKG_MANAGER) run $(1); \
	else \
		echo "No '$(1)' script defined in $(MOBILE_DIR)/package.json"; \
	fi
endef

.PHONY: help
help:
	@echo "Development ($(APP_FRAMEWORK), $(PKG_MANAGER))"
	@echo "  start              Start Metro / Expo dev server (:8081)"
	@echo "  start-clear        Start the dev server with an empty bundler cache"
	@echo "  start-tunnel       Expo dev server through a tunnel (phone outside the LAN)"
	@echo "  android            Build the debug app and run it on the device/emulator"
	@echo "  prebuild           Expo only: generate android/ (PREBUILD_ARGS=--clean to regenerate)"
	@echo ""
	@echo "Devices (ADB)"
	@echo "  devices            List devices seen by the ADB server"
	@echo "  adb-reverse        Forward device ports 8081 and API_PORT ($(API_PORT)) to the dev machine"
	@echo "  adb-pair           Pair over Wi-Fi (Android 11+): DEVICE=ip:pairing-port"
	@echo "  adb-connect        Connect over Wi-Fi: DEVICE=ip:port"
	@echo "  logcat             React Native logs from the device"
	@echo ""
	@echo "Quality"
	@echo "  lint               Run the lint script"
	@echo "  test               Run the test script"
	@echo "  typecheck          Type-check with tsc --noEmit"
	@echo "  doctor             expo-doctor / react-native doctor"
	@echo ""
	@echo "Local Android builds (Gradle, inside the container)"
	@echo "  apk-debug          Debug APK"
	@echo "  apk                Release APK"
	@echo "  aab                Release Android App Bundle (Play Store)"
	@echo "  install-apk        Install the release APK on the device"
	@echo "  clean              Clear bundler caches and Gradle build outputs"
	@echo ""
	@echo "EAS (Expo Application Services)"
	@echo "  eas-build-android  Cloud build for Android (EAS_PROFILE=$(EAS_PROFILE))"
	@echo "  eas-build-ios      Cloud build for iOS (no Mac needed)"
	@echo "  eas-build-local    Android EAS build running inside this container"

# --- Development ----------------------------------------------------------------

.PHONY: start
start:
ifeq ($(APP_FRAMEWORK),expo)
	@cd $(MOBILE_DIR) && npx expo start
else
	@cd $(MOBILE_DIR) && npx react-native start
endif

.PHONY: start-clear
start-clear:
ifeq ($(APP_FRAMEWORK),expo)
	@cd $(MOBILE_DIR) && npx expo start --clear
else
	@cd $(MOBILE_DIR) && npx react-native start --reset-cache
endif

.PHONY: start-tunnel
start-tunnel:
ifeq ($(APP_FRAMEWORK),expo)
	@cd $(MOBILE_DIR) && npx expo start --tunnel
else
	@echo "Tunnel mode is an Expo feature. For bare React Native use 'make adb-reverse' or Wi-Fi ADB."
	@exit 1
endif

# Expo starts the dev server in the same terminal. The React Native CLI would try
# to open Metro in a new terminal window, which does not exist in the container,
# so for bare projects run 'make start' in another terminal first.
.PHONY: android
android:
ifeq ($(APP_FRAMEWORK),expo)
	@cd $(MOBILE_DIR) && npx expo run:android $(if $(SERIAL),--device $(SERIAL))
else
	@cd $(MOBILE_DIR) && npx react-native run-android --no-packager $(if $(SERIAL),--device $(SERIAL))
endif

.PHONY: prebuild
prebuild:
ifeq ($(APP_FRAMEWORK),expo)
	@cd $(MOBILE_DIR) && npx expo prebuild --platform android $(PREBUILD_ARGS)
else
	@echo "prebuild is an Expo command; bare projects already have android/"
endif

# Expo projects generate android/ on demand (Continuous Native Generation)
.PHONY: android-project
android-project:
ifeq ($(APP_FRAMEWORK),expo)
	@test -d $(ANDROID_DIR) || (cd $(MOBILE_DIR) && npx expo prebuild --platform android)
else
	@test -d $(ANDROID_DIR) || (echo "$(ANDROID_DIR) not found" && exit 1)
endif

# --- Devices ----------------------------------------------------------------------

.PHONY: devices
devices:
	@$(ADB) devices -l

.PHONY: adb-reverse
adb-reverse:
	@$(ADB) reverse tcp:8081 tcp:8081
	@$(ADB) reverse tcp:$(API_PORT) tcp:$(API_PORT)
	@$(ADB) reverse --list

.PHONY: adb-pair
adb-pair:
	@test -n "$(DEVICE)" || (echo "Usage: make adb-pair DEVICE=ip:pairing-port" && exit 1)
	@adb pair $(DEVICE)

.PHONY: adb-connect
adb-connect:
	@test -n "$(DEVICE)" || (echo "Usage: make adb-connect DEVICE=ip:port" && exit 1)
	@adb connect $(DEVICE)

.PHONY: logcat
logcat:
	@$(ADB) logcat '*:S' ReactNative:V ReactNativeJS:V

# --- Quality ----------------------------------------------------------------------

.PHONY: lint
lint:
	$(call run_script,lint)

.PHONY: test
test:
	$(call run_script,test)

# Expo writes expo-env.d.ts (ignored by Git) on the first `expo start`; create it
# here too, so a fresh clone type-checks without starting the dev server
.PHONY: typecheck
typecheck:
	@cd $(MOBILE_DIR) && if [ ! -f tsconfig.json ]; then echo "No tsconfig.json in $(MOBILE_DIR)"; exit 0; fi; \
	if [ "$(APP_FRAMEWORK)" = "expo" ] && [ ! -f expo-env.d.ts ]; then \
		printf '/// <reference types="expo/types" />\n\n// NOTE: This file should not be edited and should be in your git ignore' > expo-env.d.ts; \
	fi; \
	npx tsc --noEmit

.PHONY: doctor
doctor:
ifeq ($(APP_FRAMEWORK),expo)
	@cd $(MOBILE_DIR) && npx --yes expo-doctor@latest
else
	@cd $(MOBILE_DIR) && npx react-native doctor
endif

# --- Local Android builds -----------------------------------------------------------

.PHONY: apk-debug
apk-debug: android-project
	@cd $(ANDROID_DIR) && ./gradlew assembleDebug $(GRADLE_ARGS)
	@ls -1 $(ANDROID_DIR)/app/build/outputs/apk/debug/*.apk

.PHONY: apk
apk: android-project
	@cd $(ANDROID_DIR) && ./gradlew assembleRelease $(GRADLE_ARGS)
	@ls -1 $(ANDROID_DIR)/app/build/outputs/apk/release/*.apk

.PHONY: aab
aab: android-project
	@cd $(ANDROID_DIR) && ./gradlew bundleRelease $(GRADLE_ARGS)
	@ls -1 $(ANDROID_DIR)/app/build/outputs/bundle/release/*.aab

.PHONY: install-apk
install-apk:
	@$(ADB) install -r $(ANDROID_DIR)/app/build/outputs/apk/release/app-release.apk

.PHONY: clean
clean:
	@rm -rf $(MOBILE_DIR)/.expo /tmp/metro-* /tmp/haste-map-*
	@if [ -x $(ANDROID_DIR)/gradlew ]; then cd $(ANDROID_DIR) && ./gradlew clean; fi

# --- EAS ----------------------------------------------------------------------------

.PHONY: eas-build-android
eas-build-android:
	@cd $(MOBILE_DIR) && eas build --platform android --profile $(EAS_PROFILE)

.PHONY: eas-build-ios
eas-build-ios:
	@cd $(MOBILE_DIR) && eas build --platform ios --profile $(EAS_PROFILE)

.PHONY: eas-build-local
eas-build-local:
	@cd $(MOBILE_DIR) && eas build --platform android --profile $(EAS_PROFILE) --local
