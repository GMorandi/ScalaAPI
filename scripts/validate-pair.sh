#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

usage() {
    cat <<'EOF'
Usage: scripts/validate-pair.sh [--allow-superproject-dirty]

Validate the Platform/Gateway gitlinks and their shared Cap'n Proto contract.
The optional flag is intended only while a reviewed gitlink update is staged;
component worktrees and gitlink identities are still required to be clean and
exact.
EOF
}

fail() {
    echo "pair validation failed: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

allow_superproject_dirty=0
while (( $# > 0 )); do
    case "$1" in
        --allow-superproject-dirty)
            allow_superproject_dirty=1
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
    shift
done

for command_name in git sha256sum cmp awk sort find diff uniq wc; do
    require_command "$command_name"
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

[[ -f .gitmodules ]] || fail "missing .gitmodules"

mapfile -t configured_paths < <(
    git config --file .gitmodules --get-regexp '^submodule\..*\.path$' |
        awk '{print $2}' |
        sort
)
expected_paths=(gateway platform)
if [[ "${configured_paths[*]}" != "${expected_paths[*]}" ]]; then
    fail "expected exactly the platform and gateway submodules"
fi

if (( allow_superproject_dirty == 0 )); then
    superproject_status="$(
        git status --porcelain=v1 --untracked-files=all --ignore-submodules=dirty
    )"
    if [[ -n "$superproject_status" ]]; then
        printf '%s\n' "$superproject_status" >&2
        fail "superproject worktree or index is not clean"
    fi
fi

validate_gitlink() {
    local path="$1"
    local stage_record mode expected_sha actual_sha component_status

    [[ -d "$path" ]] || fail "submodule is not initialized: $path"
    git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
        fail "submodule is not a Git worktree: $path"

    stage_record="$(git ls-files --stage -- "$path")"
    [[ -n "$stage_record" ]] || fail "missing gitlink in index: $path"
    [[ "$(printf '%s\n' "$stage_record" | wc -l)" -eq 1 ]] ||
        fail "ambiguous index entries for gitlink: $path"

    mode="$(awk '{print $1}' <<<"$stage_record")"
    expected_sha="$(awk '{print $2}' <<<"$stage_record")"
    [[ "$mode" == "160000" ]] || fail "$path is not recorded as a gitlink"

    actual_sha="$(git -C "$path" rev-parse HEAD)"
    [[ "$actual_sha" == "$expected_sha" ]] ||
        fail "$path HEAD $actual_sha does not match gitlink $expected_sha"

    component_status="$(git -C "$path" status --porcelain=v1 --untracked-files=all)"
    if [[ -n "$component_status" ]]; then
        printf '%s\n' "$component_status" >&2
        fail "$path worktree or index is not clean"
    fi
}

validate_gitlink platform
validate_gitlink gateway

while IFS= read -r status_line; do
    [[ -z "$status_line" ]] && continue
    [[ "${status_line:0:1}" == " " ]] ||
        fail "recursive submodule status is not clean: $status_line"
done < <(git submodule status --recursive)

canonical_dir="$repo_root/platform/contracts/capnp"
vendored_dir="$repo_root/gateway/proto"
manifest_name="SHA256SUMS"

validate_contract_manifest() {
    local label="$1"
    local directory="$2"
    local listed_file actual_file duplicates_file

    [[ -d "$directory" ]] || fail "$label contract directory is missing: $directory"
    [[ -f "$directory/$manifest_name" ]] ||
        fail "$label contract checksum manifest is missing"

    listed_file="$(mktemp)"
    actual_file="$(mktemp)"
    duplicates_file="$(mktemp)"

    awk '
        NF != 2 || length($1) != 64 || $1 ~ /[^0-9a-f]/ { exit 1 }
        {
            name = $2
            sub(/^\*/, "", name)
            if (name !~ /^[A-Za-z0-9._-]+[.]capnp$/) { exit 1 }
            print name
        }
    ' "$directory/$manifest_name" | sort > "$listed_file" || {
        rm -f "$listed_file" "$actual_file" "$duplicates_file"
        fail "$label checksum manifest is malformed or contains unsafe paths"
    }

    sort "$listed_file" | uniq -d > "$duplicates_file"
    if [[ -s "$duplicates_file" ]]; then
        cat "$duplicates_file" >&2
        rm -f "$listed_file" "$actual_file" "$duplicates_file"
        fail "$label checksum manifest contains duplicate entries"
    fi

    find "$directory" -maxdepth 1 -type f -name '*.capnp' -printf '%f\n' |
        sort > "$actual_file"
    if ! diff -u "$listed_file" "$actual_file"; then
        rm -f "$listed_file" "$actual_file" "$duplicates_file"
        fail "$label checksum manifest does not cover exactly its Cap'n Proto files"
    fi

    rm -f "$listed_file" "$actual_file" "$duplicates_file"
    (cd "$directory" && sha256sum --check --strict "$manifest_name") ||
        fail "$label contract checksum verification failed"
}

validate_contract_manifest "Platform canonical" "$canonical_dir"
validate_contract_manifest "Gateway vendored" "$vendored_dir"

cmp "$canonical_dir/$manifest_name" "$vendored_dir/$manifest_name" ||
    fail "Platform and Gateway checksum manifests differ"

while read -r _ contract_file; do
    contract_file="${contract_file#\*}"
    cmp "$canonical_dir/$contract_file" "$vendored_dir/$contract_file" ||
        fail "contract differs between Platform and Gateway: $contract_file"
done < "$canonical_dir/$manifest_name"

contract_digest="$(sha256sum "$canonical_dir/$manifest_name" | awk '{print $1}')"
echo "pair validation passed"
echo "  superproject: $(git rev-parse HEAD)"
echo "  platform:     $(git -C platform rev-parse HEAD)"
echo "  gateway:      $(git -C gateway rev-parse HEAD)"
echo "  contract:     sha256:$contract_digest"
