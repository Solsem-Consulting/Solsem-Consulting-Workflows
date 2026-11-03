#!/usr/bin/env bash
# Installs the pinned, checksum-verified Syft and cosign binaries into $1 for the
# current runner: Linux x64, Windows x64 (Git Bash), or macOS (Apple Silicon or Intel).
set -euo pipefail

tools_dir="$1"
if command -v cygpath > /dev/null 2>&1; then
  tools_dir=$(cygpath -u "$tools_dir")
fi
syft_version="1.52.0"
cosign_version="3.1.3"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    platform=linux_amd64
    syft_archive="syft_${syft_version}_linux_amd64.tar.gz"
    syft_sha256="caeedb81fb0491615f1ebd1761e4145d41ee86dd2cc7bf80669f9f5ad9d6133d"
    cosign_asset="cosign-linux-amd64"
    cosign_sha256="4629c757b7618056f8ddd7e2625ae9fdd94c0372a65049520bc7d9df9efc7f71"
    exe=""
    ;;
  MINGW64_NT*-x86_64 | MSYS_NT*-x86_64)
    platform=windows_amd64
    syft_archive="syft_${syft_version}_windows_amd64.zip"
    syft_sha256="de787a374cf961c56fd7b206b2e183295abba32d0af3cb44d9aef2357ca9eda2"
    cosign_asset="cosign-windows-amd64.exe"
    cosign_sha256="9fe59be0eca1271873ce019061335eb1ac419b7059202e797828467ddabe33be"
    exe=".exe"
    ;;
  Darwin-arm64)
    platform=darwin_arm64
    syft_archive="syft_${syft_version}_darwin_arm64.tar.gz"
    syft_sha256="014d561b6d13059124155f74a6c5a9a99501f5e209313638dd884f39eb418ee6"
    cosign_asset="cosign-darwin-arm64"
    cosign_sha256="5cf948c2f4dfe59687bdd0b8523709067383e03982cc543475c8a7dc70e92a76"
    exe=""
    ;;
  Darwin-x86_64)
    platform=darwin_amd64
    syft_archive="syft_${syft_version}_darwin_amd64.tar.gz"
    syft_sha256="56975f5d7ffa9846a1eaf64330647841b878097bc7e3730cb9325f93add96917"
    cosign_asset="cosign-darwin-amd64"
    cosign_sha256="2347488e5d5b25336644024dfeca5601b190e91197a71a917bda44744aff106c"
    exe=""
    ;;
  *)
    echo "::error::release-evidence has no pinned tools for $(uname -s) $(uname -m)."
    exit 1
    ;;
esac

# macOS has shasum instead of sha256sum; both print "<hash>  <file>".
if command -v sha256sum > /dev/null 2>&1; then
  sha256_cmd=(sha256sum)
else
  sha256_cmd=(shasum -a 256)
fi

mkdir -p "$tools_dir"
download() {
  curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error --retry 3 --output "$1" "$2"
}
check() { # file, expected sha256
  local actual
  actual=$("${sha256_cmd[@]}" "$1" | awk '{ print $1 }')
  if [ "$actual" != "$2" ]; then
    echo "::error::Checksum mismatch for $(basename "$1") ($platform): expected $2, found $actual."
    exit 1
  fi
}

if [ ! -x "$tools_dir/syft$exe" ]; then
  archive="$tools_dir/$syft_archive"
  download "$archive" "https://github.com/anchore/syft/releases/download/v${syft_version}/${syft_archive}"
  check "$archive" "$syft_sha256"
  case "$syft_archive" in
    *.zip) unzip -q -o "$archive" "syft$exe" -d "$tools_dir" ;;
    *) tar -xzf "$archive" -C "$tools_dir" syft ;;
  esac
  rm -f "$archive"
fi

if [ ! -x "$tools_dir/cosign$exe" ]; then
  download "$tools_dir/cosign$exe" "https://github.com/sigstore/cosign/releases/download/v${cosign_version}/${cosign_asset}"
  check "$tools_dir/cosign$exe" "$cosign_sha256"
  chmod +x "$tools_dir/cosign$exe"
fi
