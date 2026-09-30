#!/usr/bin/env bash
# Creates signed release evidence for the files in RELEASE_DIR:
#   <product>-<version>.cdx.json                 CycloneDX SBOM of the application archives
#   SHA256SUMS                                   SHA-256 of every release file and the SBOM
#   <product>-<version>.provenance.sigstore.json SLSA v1 provenance for SHA256SUMS, signed with cosign
#   VERIFY.md                                    how to verify the release
# The signature uses the release signing key only; nothing is sent to a public
# transparency log or timestamp authority.
#
# Environment:
#   RELEASE_DIR, EVIDENCE_DIR, PRODUCT, VERSION, TAG (optional), SBOM_ARCHIVES (glob, default *.zip),
#   CANDIDATE_DIGEST (optional), PUBLIC_KEY, RELEASE_SIGNING_KEY, RELEASE_SIGNING_PASSWORD,
#   SYFT and COSIGN (paths), and the default GITHUB_* variables.
set -euo pipefail

syft="${SYFT:-syft}"
cosign="${COSIGN:-cosign}"
release_dir="${RELEASE_DIR:?RELEASE_DIR is required}"
evidence_dir="${EVIDENCE_DIR:?EVIDENCE_DIR is required}"
product="${PRODUCT:?PRODUCT is required}"
version="${VERSION:?VERSION is required}"
sbom_archives="${SBOM_ARCHIVES:-*.zip}"
server_url="${GITHUB_SERVER_URL:-https://github.com}"
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

fail() {
  echo "::error title=Release evidence failed::$1"
  exit 1
}

missing=()
[ -n "${RELEASE_SIGNING_KEY:-}" ] || missing+=("secret RELEASE_SIGNING_KEY")
[ -n "${RELEASE_SIGNING_PASSWORD:-}" ] || missing+=("secret RELEASE_SIGNING_PASSWORD")
[ -n "${PUBLIC_KEY:-}" ] || missing+=("variable RELEASE_SIGNING_PUBLIC_KEY")
if [ "${#missing[@]}" -gt 0 ]; then
  fail "Release signing is not configured: missing $(IFS=', '; echo "${missing[*]}"). See 'Signert release-bevis' in the Solsem-Consulting-Workflows README."
fi
[ -d "$release_dir" ] || fail "Release directory not found: $release_dir"
[ -n "$(find "$release_dir" -type f -print -quit)" ] || fail "Release directory is empty: $release_dir"

mkdir -p "$evidence_dir"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
sbom_name="${product}-${version}.cdx.json"
bundle_name="${product}-${version}.provenance.sigstore.json"

# SBOM of the shipped application: the contents of the release archives.
mkdir -p "$work_dir/sbom-source"
archives=0
while IFS= read -r -d '' archive; do
  target="$work_dir/sbom-source/$(basename "$archive")"
  mkdir -p "$target"
  unzip -q "$archive" -d "$target"
  archives=$((archives + 1))
done < <(find "$release_dir" -maxdepth 1 -type f -name "$sbom_archives" -print0 | sort -z)
[ "$archives" -gt 0 ] || fail "No release archive matches '$sbom_archives' in $release_dir; the SBOM needs the shipped application files."
SYFT_CHECK_FOR_APP_UPDATE=false "$syft" scan "dir:$work_dir/sbom-source" \
  --source-name "$product" \
  --source-version "$version" \
  --output "cyclonedx-json=$evidence_dir/$sbom_name" \
  --quiet
components=$(jq '[.components[]? | select(.type == "library")] | length' "$evidence_dir/$sbom_name")
echo "SBOM $sbom_name lists $components library component(s) from $archives archive(s)."

# SHA256SUMS covers every published file and the SBOM.
(
  cd "$release_dir"
  find . -type f -print0 | sort -z | xargs -0 sha256sum | sed 's#  \./#  #'
  (cd "$evidence_dir" && sha256sum "$sbom_name")
) > "$evidence_dir/SHA256SUMS"

# SLSA v1 provenance: which repository, commit, and workflow run produced these files.
workflow_ref="${GITHUB_WORKFLOW_REF:?GITHUB_WORKFLOW_REF is required}"
jq -n \
  --arg repository "${server_url}/${GITHUB_REPOSITORY}" \
  --arg ref "$GITHUB_REF" \
  --arg commit "$GITHUB_SHA" \
  --arg workflow_path "${workflow_ref#"${GITHUB_REPOSITORY}"/}" \
  --arg builder "${server_url}/${workflow_ref}" \
  --arg event "${GITHUB_EVENT_NAME:-}" \
  --arg tag "${TAG:-}" \
  --arg version "$version" \
  --arg product "$product" \
  --arg candidate "${CANDIDATE_DIGEST:-}" \
  --arg invocation "${server_url}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/attempts/${GITHUB_RUN_ATTEMPT:-1}" \
  --arg finished "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    buildDefinition: {
      buildType: "https://github.com/Solsem-Consulting/Solsem-Consulting-Workflows/release/v1",
      externalParameters: {
        workflow: { repository: $repository, ref: $ref, path: ($workflow_path | sub("@.*$"; "")) },
        product: $product,
        version: $version,
        tag: $tag
      },
      internalParameters: { eventName: $event, approvedCandidateManifestSha256: $candidate },
      resolvedDependencies: [ { uri: ("git+" + $repository + "@" + $ref), digest: { gitCommit: $commit } } ]
    },
    runDetails: {
      builder: { id: $builder },
      metadata: { invocationId: $invocation, finishedOn: $finished }
    }
  }' > "$work_dir/provenance.json"

COSIGN_PASSWORD="$RELEASE_SIGNING_PASSWORD" "$cosign" attest-blob \
  --key env://RELEASE_SIGNING_KEY \
  --predicate "$work_dir/provenance.json" \
  --type slsaprovenance1 \
  --use-signing-config=false \
  --tlog-upload=false \
  --bundle "$evidence_dir/$bundle_name" \
  --yes \
  "$evidence_dir/SHA256SUMS" > /dev/null 2>"$work_dir/cosign.log" ||
  fail "cosign could not sign the provenance: $(tail -1 "$work_dir/cosign.log")"

printf '%s\n' "$PUBLIC_KEY" > "$work_dir/cosign.pub"
fingerprint=$(openssl pkey -pubin -in "$work_dir/cosign.pub" -outform DER 2>/dev/null | sha256sum | awk '{ print $1 }')
[ -n "$fingerprint" ] || fail "RELEASE_SIGNING_PUBLIC_KEY is not a valid PEM public key."

cat > "$evidence_dir/VERIFY.md" <<EOF
# Verify ${product} ${version}

These files prove which repository, commit, and workflow produced this release:

- \`SHA256SUMS\`: SHA-256 of every published file and of the SBOM.
- \`${sbom_name}\`: CycloneDX SBOM of the application in the release archives.
- \`${bundle_name}\`: SLSA v1 provenance for \`SHA256SUMS\`, signed with the Solsem Consulting release signing key.

The signature is made with a private key only. It is not recorded in a public transparency log, so verification skips the log check.

## 1. Get the trusted public key

Use the release signing public key published by Solsem Consulting and save it as \`cosign.pub\`. Its SHA-256 fingerprint (DER) must be:

\`\`\`
${fingerprint}
\`\`\`

\`\`\`sh
openssl pkey -pubin -in cosign.pub -outform DER | sha256sum
\`\`\`

## 2. Verify the signed provenance (cosign 3.1 or newer)

\`\`\`sh
cosign verify-blob-attestation --key cosign.pub --type slsaprovenance1 \\
  --bundle ${bundle_name} --insecure-ignore-tlog=true SHA256SUMS
\`\`\`

## 3. Check repository, commit, and signing workflow

\`\`\`sh
jq -r '.dsseEnvelope.payload' ${bundle_name} | base64 --decode |
  jq '{source: .predicate.buildDefinition.resolvedDependencies[0], workflow: .predicate.runDetails.builder.id}'
\`\`\`

Expected source: \`git+${server_url}/${GITHUB_REPOSITORY}@${GITHUB_REF}\` at commit \`${GITHUB_SHA}\`.
Expected workflow: \`${server_url}/${workflow_ref}\`.

## 4. Check the downloaded files

\`\`\`sh
sha256sum --check --ignore-missing SHA256SUMS
\`\`\`
EOF

EVIDENCE_DIR="$evidence_dir" RELEASE_DIR="$release_dir" PUBLIC_KEY="$PUBLIC_KEY" \
  EXPECTED_REPOSITORY="$GITHUB_REPOSITORY" EXPECTED_COMMIT="$GITHUB_SHA" EXPECTED_WORKFLOW_REF="$workflow_ref" \
  COSIGN="$cosign" bash "$script_dir/verify-evidence.sh"
