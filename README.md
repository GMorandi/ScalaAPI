# ScalaAPI supported version pairs

This repository is the release and compatibility authority for ScalaAPI. A
superproject commit pins exactly one `platform` commit and one `gateway` commit.
That immutable pair is the only supported way to combine the two components;
component branches, similarly named component tags, and arbitrary checked-out
commits are not compatibility promises.

A superproject tag is the release version for the complete pair. Release tags
are created only here and are applied unchanged to every published image. The
release workflow never publishes `latest`.

## Current audited state

Audit date: 2026-08-14.

At audit time, superproject commit `032721b` pinned and validated this supported
pair (documentation-only commits do not change the gitlinks):

| Component | Pinned commit |
| --- | --- |
| Platform | `e73a5d806000722e3b3abe7ee25c7075b4007687` |
| Gateway | `777278ea8b38491a19f585b3c026f28da7726c0f` |

`scripts/validate-pair.sh` and pair-manifest generation pass for these pins. The
canonical and vendored Cap'n Proto files are byte-identical, and the manifest
contains 66 migration records (the Orleans schema plus 65 product migrations).

The independently audited component branch heads, Platform `30d82d0` and Gateway
`98c62fd`, are newer than this supported pair. They are implementation candidates,
not a compatibility promise, until both gitlinks are advanced in one reviewed
superproject commit and the complete paired CI passes. A dirty component worktree
is never an eligible pin.

ScalaAPI is a greenfield product. The Sub2API repository is research input only;
this version authority does not provide a Sub2API migration path, schema/data
compatibility, API emulation or dual-run contract.

## Check out and validate a pair

```bash
git clone --recurse-submodules https://github.com/GMorandi/ScalaAPI.git
cd ScalaAPI
scripts/validate-pair.sh
scripts/generate-pair-manifest.sh /tmp/scalaapi-pair-manifest.json
```

`validate-pair.sh` rejects an unclean superproject, uninitialized or displaced
gitlinks, dirty component worktrees, invalid component `SHA256SUMS`, and any
difference between Platform's canonical Cap'n Proto schemas and Gateway's
vendored copies. `generate-pair-manifest.sh` runs the same validation before it
writes JSON; it does not record test results or claim that skipped work passed.

Any validation failure is a release blocker. It must not be converted into a
warning or bypassed in CI.

Local prerequisites are Bash, Git, GNU `sha256sum`, `cmp`, and `jq`. The GitHub
Actions workflows install the build-specific .NET, Node, C++, CMake, and
PostgreSQL dependencies.

## Upgrade the supported pair

1. Commit and push the compatible changes in the Platform and Gateway component
   repositories. Do not use uncommitted component worktrees as candidate pins.
2. Fetch each component and detach it at the exact reviewed commit:

   ```bash
   git -C platform fetch origin
   git -C platform checkout --detach <platform-commit>
   git -C gateway fetch origin
   git -C gateway checkout --detach <gateway-commit>
   ```

3. Stage both gitlinks, then validate the candidate pair. The local-only flag
   permits the deliberately staged superproject update; component worktrees and
   gitlink identities remain strict.

   ```bash
   git add platform gateway
   scripts/validate-pair.sh --allow-superproject-dirty
   ```

4. Commit the two pins together and open a pull request. The paired CI builds and
   tests Gateway, runs Platform against an empty PostgreSQL 17 database twice,
   runs all Platform tests and benchmark smoke checks, typechecks, builds, and
   runs the Playwright e2e suites of both web applications, builds and
   vulnerability-scans all five release images, and drives one billable chat
   request through a full docker compose stack (Gateway, Platform, admin API,
   Provider mock) with settlement assertions and the live User Web spec. A
   machine-readable pair manifest is uploaded only after all jobs pass.
5. After the paired commit is merged, create a SemVer tag on that superproject
   commit and push it:

   ```bash
   git tag -a v1.2.3 -m "ScalaAPI v1.2.3"
   git push origin v1.2.3
   ```

The tag workflow reuses the complete paired CI before registry login or image
push. It refuses to publish a tag that already exists in the registry, builds
all five images without pushing first, and pushes them only after every build
succeeded. It publishes Gateway plus the four Platform runtime images under the
exact superproject tag, then emits release evidence containing all three
commits, the contract digest, the complete migration manifest, the per-gate CI
conclusions of the producing run, and registry-reported image digests.
