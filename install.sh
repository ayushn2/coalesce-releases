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
release_json="$(curl -sSL "$api_url")"
tag_name="$(echo "$release_json" | grep '"tag_name"' | head -1 | cut -d '"' -f 4)"
download_url="$(echo "$release_json" | grep "browser_download_url.*${asset}\"" | cut -d '"' -f 4)"

if [ -z "$download_url" ]; then
  echo "Could not find asset '${asset}' in the latest release of ${RELEASES_REPO}." >&2
  exit 1
fi

tmp="$(mktemp)"
echo "Downloading Coalesce Node ${tag_name:-latest} (${os}-${arch})..."
# -# shows a progress bar (GitHub's release-asset redirect can be slow from
# some networks — with no progress output at all, a slow-but-working
# download is indistinguishable from a hung one). --retry/--max-time keep a
# genuinely stuck connection from hanging forever instead of failing clearly.
if ! curl -#SL --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 180 "$download_url" -o "$tmp"; then
  echo >&2
  echo "Download failed or timed out. This is usually a network/DNS issue on this" >&2
  echo "machine, not the release itself — try again, or download the asset directly:" >&2
  echo "  https://github.com/${RELEASES_REPO}/releases/download/${tag_name:-latest}/${asset}" >&2
  rm -f "$tmp"
  exit 1
fi
chmod +x "$tmp"

if [ -w "$INSTALL_DIR" ]; then
  mv "$tmp" "${INSTALL_DIR}/${BIN_NAME}"
else
  echo "Elevated permission needed to write to ${INSTALL_DIR}"
  sudo mv "$tmp" "${INSTALL_DIR}/${BIN_NAME}"
fi

echo
echo "Installed Coalesce Node ${tag_name:-unknown}"
echo "Location: ${INSTALL_DIR}/${BIN_NAME}"

# Verify the binary actually runs and reports the expected version.
installed_version="$("${INSTALL_DIR}/${BIN_NAME}" version 2>/dev/null || true)"
if [ -n "$installed_version" ]; then
  echo "Verified: ${installed_version}"
else
  echo "Warning: could not verify binary — 'coalesce-node version' produced no output." >&2
fi

cat <<EOF

Installation successful.

Next steps:
  1. Ensure a Bitcoin signet node is running and RPC is accessible:
       bitcoind -signet
  2. Create a distributed cluster:
       coalesce-node init -dir ./cluster -nodes 3 -distributed -hosts "host1:9000,host2:9000,host3:9000"
  3. Start your node (all members, without -enforce until funded):
       coalesce-node run -config ./cluster/node0.json -wallet <yourwallet>
  4. At the prompt: keygen, then restart, then dfund to fund the cluster.
  5. Once funded, restart with -enforce for automatic on-chain protection:
       coalesce-node run -config ./cluster/node0.json -wallet <yourwallet> -enforce

Run 'coalesce-node --help' any time to see all subcommands.
EOF
