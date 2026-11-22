# NODE_VERSION, JAVA_VERSION and TZ are injected by docker-compose.yml
ARG NODE_VERSION=24
ARG JAVA_VERSION=17

# Node.js and the JDK come from their official prebuilt images on Docker Hub and
# are copied into the dev image below (no nvm, no sdkman). The binaries are
# glibc builds and run unchanged on Debian trixie.
FROM node:${NODE_VERSION}-trixie-slim AS node

FROM eclipse-temurin:${JAVA_VERSION}-jdk-noble AS jdk

FROM mcr.microsoft.com/devcontainers/base:2-trixie AS development

ARG TZ=America/Belem

# Android command-line tools (sdkmanager, avdmanager). Build number and checksum
# come from https://dl.google.com/android/repository/repository2-3.xml
# (package "cmdline-tools;latest"). The rest of the SDK (platform-tools,
# platforms, build-tools, NDK, CMake) is installed by post-create.sh into the
# android_sdk volume, so it survives container rebuilds.
ARG ANDROID_CMDLINE_TOOLS_BUILD=16111833
ARG ANDROID_CMDLINE_TOOLS_SHA256=0877a1d048fe4a24efe2eff536ca4223f7adeb58648bb81909d33c446918cfa8

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=${TZ}
ENV JAVA_HOME=/opt/java/openjdk
ENV ANDROID_HOME=/opt/android-sdk
# Global npm packages (eas-cli, pnpm, @expo/ngrok) go to a user-writable prefix,
# so `npm install -g` works without sudo
ENV NPM_CONFIG_PREFIX=/home/vscode/.npm-global
ENV PATH=/home/vscode/.npm-global/bin:${JAVA_HOME}/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/emulator:${PATH}

# The yarn apt repository shipped with some devcontainer images has a broken signature on trixie
RUN rm -f /etc/apt/sources.list.d/yarn.list \
    && apt-get update && apt-get install -y --no-install-recommends \
    fish \
    jq \
    unzip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Node.js
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules

# npm, npx and corepack are Node scripts; recreate the symlinks the node image uses.
# corepack is no longer bundled from Node 25 on, so it is linked only when present.
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && if [ -f /usr/local/lib/node_modules/corepack/dist/corepack.js ]; then \
    ln -sf /usr/local/lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack; \
    fi \
    && rm -rf /usr/local/share/nvm \
    && node --version && npm --version

# JDK (React Native's Android toolchain expects JDK 17)
COPY --from=jdk /opt/java/openjdk /opt/java/openjdk
RUN java -version

# Android SDK command-line tools + accepted licenses
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools \
    && curl -fsSL -o /tmp/cmdline-tools.zip \
    "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_BUILD}_latest.zip" \
    && echo "${ANDROID_CMDLINE_TOOLS_SHA256}  /tmp/cmdline-tools.zip" | sha256sum -c - \
    && unzip -q /tmp/cmdline-tools.zip -d ${ANDROID_HOME}/cmdline-tools \
    && mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest \
    && rm /tmp/cmdline-tools.zip \
    && yes | sdkmanager --licenses > /dev/null \
    && sdkmanager --version

# Debian's /etc/profile resets PATH for login shells; restore the toolchain paths there
RUN printf '%s\n' \
    'export JAVA_HOME=/opt/java/openjdk' \
    'export ANDROID_HOME=/opt/android-sdk' \
    'export NPM_CONFIG_PREFIX=/home/vscode/.npm-global' \
    'export PATH="/home/vscode/.npm-global/bin:$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"' \
    > /etc/profile.d/android-dev.sh

RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime \
    && echo ${TZ} > /etc/timezone

# Mount points of the named volumes. Creating them here, owned by vscode, makes
# Docker initialize each new volume with that ownership instead of root.
RUN mkdir -p \
    /home/vscode/.android \
    /home/vscode/.claude \
    /home/vscode/.config/fish/conf.d \
    /home/vscode/.expo \
    /home/vscode/.gradle \
    /home/vscode/.local/share/pnpm/store \
    /home/vscode/.npm \
    /home/vscode/.npm-global \
    && chown -R vscode:vscode /home/vscode ${ANDROID_HOME}

# fish becomes the default shell in post-create.sh, after the image is built.
# Changing it here breaks tools that run `su vscode -c "..."` with a POSIX script.

USER vscode

CMD ["fish"]
