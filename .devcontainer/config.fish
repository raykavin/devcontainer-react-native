# Linked to ~/.config/fish/conf.d/devcontainer.fish by post-create.sh

# Enable auto-cd
set -g fish_auto_cd 1

# Toolchain paths (also set by the image; repeated for shells started outside VS Code)
set -gx JAVA_HOME /opt/java/openjdk
set -gx ANDROID_HOME /opt/android-sdk
fish_add_path -g /home/vscode/.npm-global/bin $JAVA_HOME/bin $ANDROID_HOME/cmdline-tools/latest/bin $ANDROID_HOME/platform-tools $ANDROID_HOME/emulator

# Prompt (only when tide is installed: fisher install IlanCosman/tide@v6)
if status --is-interactive; and functions -q tide
    tide configure --auto
end

# Directory shortcuts
alias ..="cd .."
alias ...="cd ../.."
alias c="clear"
alias m="cd /workspaces/mobile"

# Git
alias gst="git status"
alias gaa="git add ."
alias gc="git commit -m"
alias gp="git push"
alias gl="git log --oneline --graph --decorate"

# React Native / Expo
alias ex="npx expo"
alias rn="npx react-native"
alias exs="make -C /workspaces start"
alias exa="make -C /workspaces android"

# Android
alias adbd="adb devices -l"
alias adbr="adb reverse tcp:8081 tcp:8081"
alias logcat="adb logcat '*:S' ReactNative:V ReactNativeJS:V"
alias gw="./gradlew"
