# Sourced by create-evidence.sh and verify-evidence.sh so they run the same on Linux,
# Windows (Git Bash), and macOS (bash 3.2).

# macOS has shasum instead of sha256sum. Git Bash prints "<hash> *<file>" (binary mode);
# normalize_sums turns that into the "<hash>  <file>" form that SHA256SUMS uses.
if command -v sha256sum > /dev/null 2>&1; then
  sha256_cmd=(sha256sum)
else
  sha256_cmd=(shasum -a 256)
fi
normalize_sums() {
  sed 's/^\([0-9a-f]\{64\}\) \*/\1  /'
}
sha256() {
  "${sha256_cmd[@]}" "$@" | normalize_sums
}

# Paths inside the scripts are POSIX paths; native Windows tools (syft.exe, cosign.exe)
# get Windows paths. Without cygpath (Linux, macOS) both return the path unchanged.
posix_path() {
  if command -v cygpath > /dev/null 2>&1; then
    cygpath -u "$1"
  else
    printf '%s\n' "$1"
  fi
}
native_path() {
  if command -v cygpath > /dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s\n' "$1"
  fi
}
