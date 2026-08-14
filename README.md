# ScalaAPI supported version pairs

This repository is the release and compatibility authority for ScalaAPI. A
superproject commit pins exactly one `platform` commit and one `gateway` commit.
That immutable pair is the only supported way to combine the two components;
component branches, similarly named component tags, and arbitrary checked-out
commits are not compatibility promises.

A superproject tag is the release version for the complete pair. Release tags
are created only here and are applied unchanged to every published image. The
release workflow never publishes `latest`.

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

The current pins are known to contain contract drift, so validation is expected
to fail until a compatible component pair is selected. This is intentional: a
red compatibility gate must not be converted into a warning or bypassed in CI.

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
   runs all Platform tests and benchmark smoke checks, and typechecks/builds both
   web applications. A machine-readable pair manifest is uploaded only after all
   jobs pass.
5. After the paired commit is merged, create a SemVer tag on that superproject
   commit and push it:

   ```bash
   git tag -a v1.2.3 -m "ScalaAPI v1.2.3"
   git push origin v1.2.3
   ```

The tag workflow reuses the complete paired CI before registry login or image
push. It publishes Gateway plus the four Platform runtime images under the exact
superproject tag, then emits release evidence containing all three commits, the
contract digest, the complete migration manifest, and registry-reported image
digests.
