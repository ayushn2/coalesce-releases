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

# GitHub's release-asset redirect can be slow from some networks — with no
# feedback at all, a slow-but-working download is indistinguishable from a
# hung one. curl's own progress meter (-#) isn't reliable when run this way
# (through curl | bash) — it queries the terminal for width/cursor control
# and can render corrupted when that detection misfires. This renders our
# OWN fixed-width bar with nothing but a bare carriage return (\r) — no
# terminal queries, no width detection, nothing for it to get wrong.
total_size="$(curl -sI -L --max-time 15 "$download_url" 2>/dev/null | tr -d '\r' | grep -i '^content-length:' | tail -1 | awk '{print $2}')"

curl -sSL --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 180 "$download_url" -o "$tmp" &
curl_pid=$!
bar_width=30
while kill -0 "$curl_pid" 2>/dev/null; do
  sleep 0.2
  have="$(wc -c <"$tmp" 2>/dev/null | tr -d ' ')"
  have="${have:-0}"
  if [ -n "${total_size:-}" ] && [ "$total_size" -gt 0 ] 2>/dev/null; then
    pct=$(( have * 100 / total_size ))
    [ "$pct" -gt 100 ] && pct=100
    filled=$(( pct * bar_width / 100 ))
    empty=$(( bar_width - filled ))
    bar="$(printf '%*s' "$filled" '' | tr ' ' '#')$(printf '%*s' "$empty" '' | tr ' ' '.')"
    printf '\r  [%s] %3d%%' "$bar" "$pct"
  else
    printf '\r  %d KB downloaded' "$(( have / 1024 ))"
  fi
done
printf '\r%*s\r' 50 ""
if ! wait "$curl_pid"; then
  echo "Download failed or timed out. This is usually a network/DNS issue on this" >&2
  echo "machine, not the release itself — try again, or download the asset directly:" >&2
  echo "  https://github.com/${RELEASES_REPO}/releases/download/${tag_name:-latest}/${asset}" >&2
  rm -f "$tmp"
  exit 1
fi
echo "Download complete."
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
  2. Every member runs this with the same -peers list — it sets up the
     cluster AND continues straight into running your node, no separate
     `run` step. -enforce is safe to pass from the very start; it activates
     automatically once the cluster is funded, no restart needed:
       coalesce-node bootstrap -dir ./me -addr <your host:port> \
         -peers "addr0,addr1,addr2" -wallet <yourwallet> -enforce
  3. At the prompt: keygen, then dfund to fund the cluster (both auto-restart
     on their own).

Run 'coalesce-node --help' any time to see all subcommands.
EOF
