#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

usage() {
    cat <<'EOF'
Usage: scripts/generate-release-evidence.sh \
  --version vX.Y.Z --pair-manifest pair.json \
  --images-dir image-metadata --gates-json gates.json \
  --output release-evidence.json
EOF
}

fail() {
    echo "release evidence generation failed: $*" >&2
    exit 1
}

version=""
pair_manifest=""
images_dir=""
gates_json=""
output_path=""
while (( $# > 0 )); do
    case "$1" in
        --version|--pair-manifest|--images-dir|--gates-json|--output)
            (( $# >= 2 )) || fail "missing value for $1"
            case "$1" in
                --version) version="$2" ;;
                --pair-manifest) pair_manifest="$2" ;;
                --images-dir) images_dir="$2" ;;
                --gates-json) gates_json="$2" ;;
                --output) output_path="$2" ;;
            esac
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            fail "unknown argument: $1"
            ;;
    esac
done

[[ -n "$version" && -n "$pair_manifest" && -n "$images_dir" && -n "$gates_json" && -n "$output_path" ]] || {
    usage >&2
    exit 2
}
[[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] ||
    fail "version is not a supported SemVer release: $version"
[[ -f "$pair_manifest" ]] || fail "pair manifest not found: $pair_manifest"
[[ -d "$images_dir" ]] || fail "image metadata directory not found: $images_dir"
[[ -f "$gates_json" ]] || fail "gate results not found: $gates_json"
command -v jq >/dev/null 2>&1 || fail "required command not found: jq"
command -v sha256sum >/dev/null 2>&1 || fail "required command not found: sha256sum"

jq -e '
    .status == "passed" and
    (.run_id | test("^[0-9]+$")) and
    (.run_attempt | test("^[0-9]+$")) and
    (.gates | type == "array" and length > 0) and
    (all(.gates[]; .conclusion == "success"))
' "$gates_json" >/dev/null ||
    fail "gate results do not demonstrate a fully green paired CI: $gates_json"

jq -e '
    .manifest_version == 1 and
    (.superproject.commit | test("^[0-9a-f]{40}$")) and
    (.components.platform.commit | test("^[0-9a-f]{40}$")) and
    (.components.gateway.commit | test("^[0-9a-f]{40}$")) and
    (.contract.digest | test("^[0-9a-f]{64}$")) and
    (.migrations.digest | test("^[0-9a-f]{64}$"))
' "$pair_manifest" >/dev/null || fail "pair manifest has an invalid schema"

mapfile -t image_files < <(find "$images_dir" -maxdepth 1 -type f -name '*.json' -print | sort)
(( ${#image_files[@]} == 5 )) ||
    fail "expected metadata for exactly five images, found ${#image_files[@]}"

expected_repositories_file="$(mktemp)"
actual_repositories_file="$(mktemp)"
images_array_file="$(mktemp)"
cleanup() {
    rm -f "$expected_repositories_file" "$actual_repositories_file" "$images_array_file"
}
trap cleanup EXIT

cat > "$expected_repositories_file" <<'EOF'
ghcr.io/gmorandi/scalaapi-admin-api
ghcr.io/gmorandi/scalaapi-gateway
ghcr.io/gmorandi/scalaapi-migrator
ghcr.io/gmorandi/scalaapi-platform
ghcr.io/gmorandi/scalaapi-provider-mock
EOF

superproject_sha="$(jq -r '.superproject.commit' "$pair_manifest")"
contract_digest="$(jq -r '.contract.digest' "$pair_manifest")"
migration_digest="$(jq -r '.migrations.digest' "$pair_manifest")"

for image_file in "${image_files[@]}"; do
    jq -e \
        --arg version "$version" \
        --arg superproject_sha "$superproject_sha" \
        --arg contract_digest "$contract_digest" \
        --arg migration_digest "$migration_digest" '
        (.repository | type == "string") and
        (.tag == $version) and
        (.reference == (.repository + ":" + $version)) and
        (.digest | test("^sha256:[0-9a-f]{64}$")) and
        (.component == "platform" or .component == "gateway") and
        (.component_commit | test("^[0-9a-f]{40}$")) and
        (.superproject_commit == $superproject_sha) and
        (.contract_digest == $contract_digest) and
        (.migration_digest == $migration_digest)
    ' "$image_file" >/dev/null || fail "invalid image metadata: $image_file"

    component="$(jq -r '.component' "$image_file")"
    component_commit="$(jq -r '.component_commit' "$image_file")"
    expected_component_commit="$(jq -r ".components.${component}.commit" "$pair_manifest")"
    [[ "$component_commit" == "$expected_component_commit" ]] ||
        fail "component commit mismatch in $image_file"
done

jq -r '.repository' "${image_files[@]}" | sort > "$actual_repositories_file"
if ! diff -u "$expected_repositories_file" "$actual_repositories_file"; then
    fail "image metadata does not contain the required release image set"
fi

jq -s 'sort_by(.repository)' "${image_files[@]}" > "$images_array_file"
pair_manifest_digest="$(sha256sum "$pair_manifest" | awk '{print $1}')"
mkdir -p "$(dirname "$output_path")"

jq -n \
    --arg version "$version" \
    --arg pair_manifest_digest "$pair_manifest_digest" \
    --arg workflow_repository "${GITHUB_REPOSITORY:-unknown}" \
    --arg workflow_run_id "${GITHUB_RUN_ID:-unknown}" \
    --arg workflow_run_attempt "${GITHUB_RUN_ATTEMPT:-unknown}" \
    --slurpfile pair "$pair_manifest" \
    --slurpfile gates "$gates_json" \
    --slurpfile images "$images_array_file" '
    {
        evidence_version: 1,
        release: {
            tag: $version,
            superproject_sha: $pair[0].superproject.commit,
            platform_sha: $pair[0].components.platform.commit,
            gateway_sha: $pair[0].components.gateway.commit
        },
        pair_manifest_digest: $pair_manifest_digest,
        contract: $pair[0].contract,
        migration_manifest: $pair[0].migrations,
        verification: {
            status: $gates[0].status,
            run_id: $gates[0].run_id,
            run_attempt: $gates[0].run_attempt,
            gates: $gates[0].gates,
            skipped: []
        },
        images: $images[0],
        workflow: {
            repository: $workflow_repository,
            run_id: $workflow_run_id,
            run_attempt: $workflow_run_attempt
        }
    }' > "$output_path"

echo "wrote release evidence: $output_path"
