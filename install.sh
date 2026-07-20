#!/usr/bin/env bash
# Installs the coalesce-node binary from the public releases repo.
# Usage: curl -sSL https://raw.githubusercontent.com/<you>/coalesce-releases/main/install.sh | bash
set -euo pipefail

RELEASES_REPO="${COALESCE_RELEASES_REPO:-ayushn2/coalesce-releases}"
BIN_NAME="coalesce-node"
INSTALL_DIR="${COALESCE_INSTALL_DIR:-/usr/local/bin}"

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"

case "$arch" in
  x86_64|amd64) arch="amd64" ;;
  arm64|aarch64) arch="arm64" ;;
  *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
esac

case "$os" in
  darwin|linux) ;;
  *) echo "Unsupported OS: $os (Windows users: download the .exe asset manually from https://github.com/${RELEASES_REPO}/releases)" >&2; exit 1 ;;
esac

asset="${BIN_NAME}-${os}-${arch}"
api_url="https://api.github.com/repos/${RELEASES_REPO}/releases/latest"

echo "Fetching latest release info from ${RELEASES_REPO}..."
download_url="$(curl -sSL "$api_url" | grep "browser_download_url.*${asset}\"" | cut -d '"' -f 4)"

if [ -z "$download_url" ]; then
  echo "Could not find asset '${asset}' in the latest release of ${RELEASES_REPO}." >&2
  exit 1
fi

tmp="$(mktemp)"
echo "Downloading ${download_url}..."
curl -sSL "$download_url" -o "$tmp"
chmod +x "$tmp"

if [ -w "$INSTALL_DIR" ]; then
  mv "$tmp" "${INSTALL_DIR}/${BIN_NAME}"
else
  echo "Elevated permission needed to write to ${INSTALL_DIR}"
  sudo mv "$tmp" "${INSTALL_DIR}/${BIN_NAME}"
fi

echo "Installed ${BIN_NAME} to ${INSTALL_DIR}/${BIN_NAME}"
"${INSTALL_DIR}/${BIN_NAME}" 2>/dev/null || true
echo
echo "Run '${BIN_NAME}' with no arguments to see subcommands (init, fund, close, run)."
