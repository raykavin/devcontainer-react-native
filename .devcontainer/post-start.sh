#!/bin/sh
# Runs on every container start (and once from post-create.sh).
#
# Named volumes take the owner of their mount point in the image. That breaks
# when the mount point does not exist in the image (mobile/node_modules) or when
# VS Code changes the vscode UID to match the host user. Fix only what is wrong,
# so a healthy start costs a few `stat` calls instead of a recursive chown.

for dir in \
  /opt/android-sdk \
  /home/vscode/.android \
  /home/vscode/.claude \
  /home/vscode/.expo \
  /home/vscode/.gradle \
  /home/vscode/.local/share/pnpm/store \
  /home/vscode/.npm \
  /workspaces/mobile/node_modules; do
  [ -d "$dir" ] || continue
  if [ "$(stat -c %U "$dir")" != "vscode" ]; then
    echo "> Fixing ownership of $dir"
    sudo chown -R vscode:vscode "$dir"
  fi
done
