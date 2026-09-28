#!/usr/bin/env bash
# Verifies release evidence: the cosign-signed SLSA provenance, its claims about the
# source repository, commit, and signer workflow, and the SHA-256 of every file.
#
# Environment:
#   EVIDENCE_DIR          directory with SHA256SUMS, *.cdx.json, and *.provenance.sigstore.json
#   RELEASE_DIR           optional directory with the published release files
#   PUBLIC_KEY            cosign public key (PEM)
#   EXPECTED_REPOSITORY   owner/name the release must come from
#   EXPECTED_COMMIT       commit SHA the release must be built from
#   EXPECTED_WORKFLOW_REF optional owner/name/path@ref of the workflow that must have signed it
#   COSIGN                path to cosign (default: cosign on PATH)
set -euo pipefail

cosign="${COSIGN:-cosign}"
evidence_dir="${EVIDENCE_DIR:?EVIDENCE_DIR is required}"
release_dir="${RELEASE_DIR:-}"
server_url="${GITHUB_SERVER_URL:-https://github.com}"

fail() {
  echo "::error title=Release evidence verification failed::$1"
  exit 1
}

[ -n "${PUBLIC_KEY:-}" ] || fail "PUBLIC_KEY is empty; set the RELEASE_SIGNING_PUBLIC_KEY variable."
if [ -z "${EXPECTED_REPOSITORY:-}" ] || [ -z "${EXPECTED_COMMIT:-}" ]; then
  fail "EXPECTED_REPOSITORY and EXPECTED_COMMIT are required."
fi
[ -f "$evidence_dir/SHA256SUMS" ] || fail "SHA256SUMS not found in $evidence_dir."
mapfile -t bundles < <(find "$evidence_dir" -maxdepth 1 -type f -name '*.provenance.sigstore.json')
[ "${#bundles[@]}" -eq 1 ] || fail "Expected exactly one *.provenance.sigstore.json in $evidence_dir, found ${#bundles[@]}."
bundle="${bundles[0]}"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
printf '%s\n' "$PUBLIC_KEY" > "$work_dir/cosign.pub"

"$cosign" verify-blob-attestation \
  --key "$work_dir/cosign.pub" \
  --type slsaprovenance1 \
  --bundle "$bundle" \
  --insecure-ignore-tlog=true \
  "$evidence_dir/SHA256SUMS" > /dev/null 2>"$work_dir/cosign.log" ||
  fail "cosign could not verify $(basename "$bundle") for SHA256SUMS with the release signing key: $(grep -v '^WARNING' "$work_dir/cosign.log" | tail -1)"

# The bundle's signature is verified above; its payload is the signed in-toto statement.
jq -r '.dsseEnvelope.payload' "$bundle" | base64 --decode > "$work_dir/statement.json"
expected_source="git+${server_url}/${EXPECTED_REPOSITORY}"
jq -e \
  --arg source "$expected_source" \
  --arg commit "$EXPECTED_COMMIT" \
  '.predicateType == "https://slsa.dev/provenance/v1"
   and (.predicate.buildDefinition.resolvedDependencies[0].uri | startswith($source + "@"))
   and .predicate.buildDefinition.resolvedDependencies[0].digest.gitCommit == $commit' \
  "$work_dir/statement.json" > /dev/null ||
  fail "The signed provenance does not name ${EXPECTED_REPOSITORY} at commit ${EXPECTED_COMMIT}."
if [ -n "${EXPECTED_WORKFLOW_REF:-}" ]; then
  jq -e --arg builder "${server_url}/${EXPECTED_WORKFLOW_REF}" '.predicate.runDetails.builder.id == $builder' \
    "$work_dir/statement.json" > /dev/null ||
    fail "The signed provenance was not produced by ${EXPECTED_WORKFLOW_REF}."
fi

checked=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  expected_hash="${line%%  *}"
  name="${line#*  }"
  if [ -f "$evidence_dir/$name" ]; then
    file="$evidence_dir/$name"
  elif [ -n "$release_dir" ] && [ -f "$release_dir/$name" ]; then
    file="$release_dir/$name"
  elif [ -n "$release_dir" ]; then
    fail "$name is listed in SHA256SUMS but missing from the release files."
  else
    continue
  fi
  actual_hash=$(sha256sum "$file" | awk '{ print $1 }')
  [ "$actual_hash" = "$expected_hash" ] || fail "$name does not match SHA256SUMS (expected $expected_hash, found $actual_hash)."
  checked=$((checked + 1))
done < "$evidence_dir/SHA256SUMS"

echo "Verified signed provenance for ${EXPECTED_REPOSITORY}@${EXPECTED_COMMIT} and ${checked} file hash(es)."
