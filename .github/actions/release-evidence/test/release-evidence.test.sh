#!/usr/bin/env bash
# Tests create-evidence.sh and verify-evidence.sh with a throwaway signing key.
set -uo pipefail

action_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tools="${RELEASE_EVIDENCE_TOOLS:-$work/tools}"
failures=0

bash "$action_dir/install-tools.sh" "$tools" || { echo "tool installation failed"; exit 1; }
export SYFT="$tools/syft" COSIGN="$tools/cosign"

expect() { # description, expected exit (0 or 1), command...
  local description="$1" expected="$2"
  shift 2
  "$@" > "$work/out.log" 2>&1
  local status=$?
  if { [ "$expected" -eq 0 ] && [ "$status" -eq 0 ]; } || { [ "$expected" -ne 0 ] && [ "$status" -ne 0 ]; }; then
    echo "ok   $description"
  else
    echo "FAIL $description (exit $status)"
    sed 's/^/     /' "$work/out.log"
    failures=$((failures + 1))
  fi
}
output_contains() { grep -q -- "$1" "$work/out.log"; }

# A release like the products publish: an application archive, an installer, and a manifest.
mkdir -p "$work/app" "$work/release"
cat > "$work/app/App.deps.json" <<'EOF'
{
  "runtimeTarget": { "name": ".NETCoreApp,Version=v10.0/win-x64" },
  "targets": { ".NETCoreApp,Version=v10.0/win-x64": {
    "App/1.2.3": { "dependencies": { "Newtonsoft.Json": "13.0.3" }, "runtime": { "App.dll": {} } },
    "Newtonsoft.Json/13.0.3": { "runtime": { "lib/net6.0/Newtonsoft.Json.dll": {} } } } },
  "libraries": {
    "App/1.2.3": { "type": "project", "serviceable": false, "sha512": "" },
    "Newtonsoft.Json/13.0.3": { "type": "package", "serviceable": true, "sha512": "sha512-HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ==", "path": "newtonsoft.json/13.0.3", "hashPath": "newtonsoft.json.13.0.3.nupkg.sha512" } }
}
EOF
touch "$work/app/App.dll" "$work/app/Newtonsoft.Json.dll"
(cd "$work/app" && zip -q -r "$work/release/App-1.2.3.zip" .)
head -c 4096 /dev/urandom > "$work/release/App-1.2.3.msi"
echo '{"version":"1.2.3"}' > "$work/release/app-update.json"

(cd "$work" && COSIGN_PASSWORD=test-password "$COSIGN" generate-key-pair --output-key-prefix release > /dev/null 2>&1)
(cd "$work" && COSIGN_PASSWORD=other "$COSIGN" generate-key-pair --output-key-prefix other > /dev/null 2>&1)

export GITHUB_REPOSITORY=Solsem-Consulting/example GITHUB_SHA=0123456789abcdef0123456789abcdef01234567
export GITHUB_REF=refs/tags/v1.2.3 GITHUB_WORKFLOW_REF=Solsem-Consulting/example/.github/workflows/publish.yml@refs/tags/v1.2.3
export GITHUB_RUN_ID=42 GITHUB_RUN_ATTEMPT=1 GITHUB_EVENT_NAME=push
export RELEASE_DIR="$work/release" PRODUCT=App VERSION=1.2.3 TAG=v1.2.3 CANDIDATE_DIGEST=abc
signing_key=$(cat "$work/release.key")
public_key=$(cat "$work/release.pub")
other_public_key=$(cat "$work/other.pub")

create() { # evidence dir, signing key, password, public key, [sbom archive glob]
  EVIDENCE_DIR="$1" RELEASE_SIGNING_KEY="$2" RELEASE_SIGNING_PASSWORD="$3" PUBLIC_KEY="$4" \
    SBOM_ARCHIVES="${5:-*.zip}" bash "$action_dir/create-evidence.sh"
}
verify() { # evidence dir, public key, expected commit, expected workflow ref, [release dir]
  EVIDENCE_DIR="$1" PUBLIC_KEY="$2" EXPECTED_REPOSITORY=Solsem-Consulting/example EXPECTED_COMMIT="$3" \
    EXPECTED_WORKFLOW_REF="$4" RELEASE_DIR="${5-$work/release}" bash "$action_dir/verify-evidence.sh"
}

expect "creates and verifies evidence" 0 create "$work/evidence" "$signing_key" test-password "$public_key"
for file in SHA256SUMS App-1.2.3.cdx.json App-1.2.3.provenance.sigstore.json VERIFY.md; do
  expect "writes $file" 0 test -s "$work/evidence/$file"
done
expect "SBOM lists the NuGet dependency" 0 grep -q 'pkg:nuget/Newtonsoft.Json@13.0.3' "$work/evidence/App-1.2.3.cdx.json"
expect "SHA256SUMS covers release files and SBOM" 0 bash -c "cd '$work/release' && sha256sum --check --ignore-missing --quiet '$work/evidence/SHA256SUMS' && [ \$(wc -l < '$work/evidence/SHA256SUMS') -eq 4 ]"
expect "VERIFY.md names the commit" 0 grep -q "$GITHUB_SHA" "$work/evidence/VERIFY.md"
expect "no signing key material in evidence" 0 bash -c "! grep -rq 'ENCRYPTED SIGSTORE PRIVATE KEY' '$work/evidence'"

wf="$GITHUB_WORKFLOW_REF"
expect "audit verification with release files" 0 verify "$work/evidence" "$public_key" "$GITHUB_SHA" "$wf"
expect "verification without release files checks the SBOM" 0 verify "$work/evidence" "$public_key" "$GITHUB_SHA" "$wf" ""
expect "rejects another signing key" 1 verify "$work/evidence" "$other_public_key" "$GITHUB_SHA" "$wf"
output_contains "could not verify" || { echo "FAIL wrong-key message"; failures=$((failures + 1)); }
expect "rejects another commit" 1 verify "$work/evidence" "$public_key" "ffffffffffffffffffffffffffffffffffffffff" "$wf"
expect "rejects another signing workflow" 1 verify "$work/evidence" "$public_key" "$GITHUB_SHA" "Solsem-Consulting/example/.github/workflows/other.yml@refs/heads/main"

cp -r "$work/release" "$work/tampered"
echo tampered >> "$work/tampered/App-1.2.3.msi"
expect "rejects a changed release file" 1 verify "$work/evidence" "$public_key" "$GITHUB_SHA" "$wf" "$work/tampered"
output_contains "does not match SHA256SUMS" || { echo "FAIL tampered-file message"; failures=$((failures + 1)); }

cp -r "$work/evidence" "$work/evidence-edited"
echo "0000000000000000000000000000000000000000000000000000000000000000  extra.bin" >> "$work/evidence-edited/SHA256SUMS"
expect "rejects an edited SHA256SUMS" 1 verify "$work/evidence-edited" "$public_key" "$GITHUB_SHA" "$wf"

expect "refuses to sign without the signing secrets" 1 create "$work/evidence-unset" "" "" "$public_key"
output_contains "Release signing is not configured" || { echo "FAIL missing-secrets message"; failures=$((failures + 1)); }
expect "refuses a wrong key password" 1 create "$work/evidence-password" "$signing_key" wrong-password "$public_key"
expect "requires an application archive for the SBOM" 1 create "$work/evidence-noarchive" "$signing_key" test-password "$public_key" '*.tar'
output_contains "No release archive matches" || { echo "FAIL missing-archive message"; failures=$((failures + 1)); }

if [ "$failures" -ne 0 ]; then
  echo "$failures release evidence check(s) failed."
  exit 1
fi
echo "Release evidence checks passed."
