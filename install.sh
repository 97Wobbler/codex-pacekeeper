#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexPacekeeper"
REPO="97Wobbler/codex-pacekeeper"
VERSION="${CODEX_PACEKEEPER_VERSION:-latest}"
INSTALL_DIR="${CODEX_PACEKEEPER_INSTALL_DIR:-$HOME/Applications}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ "$VERSION" == "latest" ]]; then
  DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/$APP_NAME.app.zip"
else
  DOWNLOAD_URL="https://github.com/$REPO/releases/download/$VERSION/$APP_NAME.app.zip"
fi

mkdir -p "$INSTALL_DIR"

echo "Downloading $APP_NAME from $DOWNLOAD_URL"
curl -fL "$DOWNLOAD_URL" -o "$TMP_DIR/$APP_NAME.app.zip"

echo "Installing to $INSTALL_DIR/$APP_NAME.app"
unzip -q "$TMP_DIR/$APP_NAME.app.zip" -d "$TMP_DIR"

if [[ ! -d "$TMP_DIR/$APP_NAME.app" ]]; then
  echo "Downloaded archive did not contain $APP_NAME.app" >&2
  exit 1
fi

rm -rf "$INSTALL_DIR/$APP_NAME.app"
mv "$TMP_DIR/$APP_NAME.app" "$INSTALL_DIR/"

open "$INSTALL_DIR/$APP_NAME.app"
echo "Installed $APP_NAME"
