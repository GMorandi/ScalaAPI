#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

fail() {
    echo "pair manifest generation failed: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

if (( $# > 1 )); then
    echo "Usage: scripts/generate-pair-manifest.sh [output.json]" >&2
    exit 2
fi

for command_name in git jq sha256sum find sort awk basename; do
    require_command "$command_name"
done

invocation_dir="$PWD"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_path="${1:-pair-manifest.json}"
if [[ "$output_path" != /* ]]; then
    output_path="$invocation_dir/$output_path"
fi

"$repo_root/scripts/validate-pair.sh"

temp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$temp_dir"
}
trap cleanup EXIT

contract_rows="$temp_dir/contracts.ndjson"
migration_rows="$temp_dir/migrations.ndjson"
migration_digest_input="$temp_dir/migration-digests.txt"
: > "$contract_rows"
: > "$migration_rows"
: > "$migration_digest_input"

while read -r digest contract_file; do
    contract_file="${contract_file#\*}"
    jq -cn \
        --arg path "$contract_file" \
        --arg sha256 "$digest" \
        '{path: $path, sha256: $sha256}' >> "$contract_rows"
done < "$repo_root/platform/contracts/capnp/SHA256SUMS"

add_migration() {
    local logical_path="$1"
    local source_path="$2"
    local source_relative_path="$3"
    local digest

    [[ -s "$source_path" ]] || fail "migration is missing or empty: $source_path"
    digest="$(sha256sum "$source_path" | awk '{print $1}')"
    jq -cn \
        --arg path "$logical_path" \
        --arg source "$source_relative_path" \
        --arg sha256 "$digest" \
        '{path: $path, source: $source, sha256: $sha256}' >> "$migration_rows"
    printf '%s  %s\n' "$digest" "$logical_path" >> "$migration_digest_input"
}

add_migration \
    "000-orleans.sql" \
    "$repo_root/platform/deploy/orleans-postgres-schema.sql" \
    "platform/deploy/orleans-postgres-schema.sql"

while IFS= read -r migration_path; do
    add_migration \
        "$(basename "$migration_path")" \
        "$migration_path" \
        "platform/deploy/migrations/$(basename "$migration_path")"
done < <(
    find "$repo_root/platform/deploy/migrations" \
        -maxdepth 1 -type f -name '*.sql' -print |
        sort
)

contract_array="$temp_dir/contracts.json"
migration_array="$temp_dir/migrations.json"
jq -s '.' "$contract_rows" > "$contract_array"
jq -s '.' "$migration_rows" > "$migration_array"

superproject_sha="$(git -C "$repo_root" rev-parse HEAD)"
platform_sha="$(git -C "$repo_root/platform" rev-parse HEAD)"
gateway_sha="$(git -C "$repo_root/gateway" rev-parse HEAD)"
superproject_url="$(git -C "$repo_root" remote get-url origin 2>/dev/null || printf '%s' unknown)"
platform_url="$(git -C "$repo_root" config --file .gitmodules --get submodule.platform.url)"
gateway_url="$(git -C "$repo_root" config --file .gitmodules --get submodule.gateway.url)"
contract_digest="$(
    sha256sum "$repo_root/platform/contracts/capnp/SHA256SUMS" |
        awk '{print $1}'
)"
migration_digest="$(sha256sum "$migration_digest_input" | awk '{print $1}')"
migration_count="$(jq 'length' "$migration_array")"
latest_migration="$(jq -r '.[-1].path' "$migration_array")"

mkdir -p "$(dirname "$output_path")"
temporary_output="$temp_dir/pair-manifest.json"
jq -n \
    --arg superproject_url "$superproject_url" \
    --arg superproject_sha "$superproject_sha" \
    --arg platform_url "$platform_url" \
    --arg platform_sha "$platform_sha" \
    --arg gateway_url "$gateway_url" \
    --arg gateway_sha "$gateway_sha" \
    --arg contract_digest "$contract_digest" \
    --slurpfile contract_files "$contract_array" \
    --arg migration_digest "$migration_digest" \
    --arg latest_migration "$latest_migration" \
    --argjson migration_count "$migration_count" \
    --slurpfile migrations "$migration_array" \
    '{
        manifest_version: 1,
        superproject: {
            repository: $superproject_url,
            commit: $superproject_sha
        },
        components: {
            platform: {
                repository: $platform_url,
                gitlink: "platform",
                commit: $platform_sha
            },
            gateway: {
                repository: $gateway_url,
                gitlink: "gateway",
                commit: $gateway_sha
            }
        },
        contract: {
            algorithm: "sha256",
            digest: $contract_digest,
            canonical_path: "platform/contracts/capnp",
            vendored_path: "gateway/proto",
            files: $contract_files[0]
        },
        migrations: {
            algorithm: "sha256",
            digest: $migration_digest,
            latest: $latest_migration,
            count: $migration_count,
            files: $migrations[0]
        }
    }' > "$temporary_output"

mv "$temporary_output" "$output_path"
echo "wrote pair manifest: $output_path"
