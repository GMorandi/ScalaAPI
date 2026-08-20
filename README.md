# ScalaAPI

**English** | [简体中文](README.zh-CN.md)

ScalaAPI is a production-grade LLM API platform: a high-performance C++ edge
gateway in front of a .NET business/money authority, with financial-style
settlement guarantees — request leases, balance holds, exactly-once usage
accounting, and an immutable ledger — on a greenfield schema.

ScalaAPI 是一个生产级 LLM API 平台:C++ 高性能边缘网关 + .NET 业务/资金权威,
具备金融级结算保证——请求租约、余额冻结、精确一次用量记账、不可变账本——基于
绿地带 schema 构建。(English continues below.)

> Status: active development, not yet release-certified.

## What is in this repository

This superproject is the **release and compatibility authority**. It pins
exactly one commit of each component; that immutable pair is the only supported
way to run ScalaAPI.

| Component | Role |
| --- | --- |
| [`platform/`](https://github.com/GMorandi/ScalaAPI-Platform) | .NET 10 authority: accounts, credentials, routing, quotas, leases, settlement, billing, admin/user web, ops workers |
| [`gateway/`](https://github.com/GMorandi/ScalaAPI-GateWay) | C++20/Photon edge: OpenAI/Anthropic/Gemini/xAI protocols, SSE, realtime WebSocket, media, upstream failover |

```
            ┌─────────────┐   Cap'n Proto IPC (Unix socket)
 clients ──▶│   Gateway   │◀──────────────────────────┐
            │  C++/Photon │   leases · holds · usage  │
            └──────┬──────┘   aborts · blobs          │
                   │ upstream HTTPS            ┌──────┴──────┐
                   ▼                           │ Platform xN │
            ┌─────────────┐            ┌──────▶│  .NET silo  │
            │  Providers  │            │       └──────┬──────┘
            │ (OpenAI etc)│            │              ▼
            └─────────────┘            │       PostgreSQL (authority)
                                       │       Garnet (projection)
                                       └────── MinIO (media/backup)
```

ScalaAPI is a greenfield product. The Sub2API repository is research input only;
there is no Sub2API migration path, schema/data compatibility, API emulation or
dual-run contract.

## Quick start (development stack)

```bash
git clone --recurse-submodules https://github.com/GMorandi/ScalaAPI.git
cd ScalaAPI
```

The full topology (PostgreSQL 17, Garnet, MinIO, provider mock, two platform
silos, two gateways, admin/user web) is defined in
`platform/deploy/stack/docker-compose.yml`. Required environment variables
(secrets and ports) follow `platform/deploy/stack/smoke.sh`; the minimum set:

```bash
cat > dev.env <<'EOF'
POSTGRES_DB=platform
POSTGRES_USER=platform
POSTGRES_PASSWORD=dev-postgres-password
JWT_KEY=dev-jwt-0123456789012345678901234567890123
ADMIN_USERNAME=admin@scalaapi.test
ADMIN_PASSWORD=dev-admin-password
SECURITY_MASTER_KEY=MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=
INTERNAL_RECONCILIATION_TOKEN=dev-reconciliation-token
INTERNAL_CACHE_REBUILD_TOKEN=dev-cache-rebuild-token
GARNET_PASSWORD=dev-garnet-password
OBJECT_STORAGE_ACCESS_KEY=devplatform
OBJECT_STORAGE_SECRET_KEY=dev-object-storage-secret
OBJECT_STORAGE_BUCKET=scalaapi-dev-media
OBJECT_STORAGE_PUBLIC_ENDPOINT=http://127.0.0.1:9000
PROVIDER_CREDENTIALS_ALLOW_INSECURE=true
EOF
docker compose -p scalaapi-dev --env-file dev.env \
  -f platform/deploy/stack/docker-compose.yml up -d --build
```

Admin console `http://localhost:3000` · User portal `http://localhost:3001` ·
Gateway `http://localhost:8080`. The provider mock serves all four upstream
protocols, so no real API keys are needed. For the complete, repo-owned gate
(including partition, soak, and TLS scenarios) run `platform/deploy/stack/smoke.sh`.

## Supported version pairs

A superproject commit pins exactly one `platform` commit and one `gateway`
commit. That immutable pair is the only supported way to combine the two
components; component branches, similarly named component tags, and arbitrary
checked-out commits are not compatibility promises.

A superproject tag is the release version for the complete pair. Release tags
are created only here and are applied unchanged to every published image. The
release workflow never publishes `latest`.

### Check out and validate a pair

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

### Upgrade the supported pair

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
