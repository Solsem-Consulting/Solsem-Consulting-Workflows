#!/usr/bin/env bash
# Installs the pinned, checksum-verified Syft and cosign binaries into $1 (Linux x64).
set -euo pipefail

tools_dir="$1"
syft_version="1.52.0"
syft_sha256="caeedb81fb0491615f1ebd1761e4145d41ee86dd2cc7bf80669f9f5ad9d6133d"
cosign_version="3.1.3"
cosign_sha256="4629c757b7618056f8ddd7e2625ae9fdd94c0372a65049520bc7d9df9efc7f71"

mkdir -p "$tools_dir"
download() {
  curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error --retry 3 --output "$1" "$2"
}

if [ ! -x "$tools_dir/syft" ]; then
  archive="$tools_dir/syft_${syft_version}_linux_amd64.tar.gz"
  download "$archive" "https://github.com/anchore/syft/releases/download/v${syft_version}/syft_${syft_version}_linux_amd64.tar.gz"
  echo "${syft_sha256}  ${archive}" | sha256sum --check --strict --quiet
  tar -xzf "$archive" -C "$tools_dir" syft
  rm -f "$archive"
fi

if [ ! -x "$tools_dir/cosign" ]; then
  download "$tools_dir/cosign" "https://github.com/sigstore/cosign/releases/download/v${cosign_version}/cosign-linux-amd64"
  echo "${cosign_sha256}  $tools_dir/cosign" | sha256sum --check --strict --quiet
  chmod +x "$tools_dir/cosign"
fi
