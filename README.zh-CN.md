# ScalaAPI

[English](README.md) | **简体中文**

ScalaAPI 是一个生产级 LLM API 平台:C++ 高性能边缘网关 + .NET 业务/资金权威,
具备金融级结算保证——请求租约、余额冻结、精确一次用量记账、不可变账本——基于
绿地带 schema 构建。

> 状态:积极开发中,尚未通过发布认证。

## 本仓库是什么

本超项目是 ScalaAPI 的**发布与兼容性权威**。每个超项目提交精确 pin 各组件的一个
commit;这个不可变配对是运行 ScalaAPI 的唯一受支持方式。

| 组件 | 职责 |
| --- | --- |
| [`platform/`](https://github.com/GMorandi/ScalaAPI-Platform) | .NET 10 权威:账号、凭证、路由、配额、租约、结算、计费、管理/用户 Web、运维工作者 |
| [`gateway/`](https://github.com/GMorandi/ScalaAPI-GateWay) | C++20/Photon 边缘:OpenAI/Anthropic/Gemini/xAI 协议、SSE、实时 WebSocket、媒体、上游故障转移 |

```
            ┌─────────────┐   Cap'n Proto IPC(Unix 套接字)
 clients ──▶│   Gateway   │◀──────────────────────────┐
            │  C++/Photon │   租约 · 冻结 · 用量       │
            └──────┬──────┘   中止 · blob 上传        │
                   │ 上游 HTTPS              ┌───────┴──────┐
                   ▼                         │  Platform xN │
            ┌─────────────┐          ┌─────▶ │  .NET silo   │
            │  Providers  │          │       └───────┬──────┘
            │(OpenAI 等)  │          │               ▼
            └─────────────┘          │        PostgreSQL(权威)
                                     │        Garnet(投影)
                                     └─────── MinIO(媒体/备份)
```

ScalaAPI 是绿地带产品。Sub2API 仓库仅作研究输入;不提供 Sub2API 迁移路径、
schema/数据兼容、API 仿真或双运行契约。

## 快速开始(开发栈)

```bash
git clone --recurse-submodules https://github.com/GMorandi/ScalaAPI.git
cd ScalaAPI
```

完整拓扑(PostgreSQL 17、Garnet、MinIO、provider mock、两个平台 silo、两个网关、
管理/用户 Web)定义在 `platform/deploy/stack/docker-compose.yml`。所需环境变量
(密钥与端口)参照 `platform/deploy/stack/smoke.sh`,最小集合:

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

管理控制台 `http://localhost:3000` · 用户门户 `http://localhost:3001` ·
网关 `http://localhost:8080`。provider mock 支持全部四种上游协议,无需真实
API Key。完整仓库门禁(含分区、浸泡、TLS 场景)请运行
`platform/deploy/stack/smoke.sh`。

## 受支持的版本配对

超项目提交精确 pin 一个 `platform` commit 和一个 `gateway` commit。该不可变
配对是组合两个组件的唯一受支持方式;组件分支、同名组件标签、任意检出的 commit
均不构成兼容性承诺。

超项目标签即完整配对的发布版本。发布标签只在此处创建,并原样应用到每个已发布
镜像。发布工作流永不发布 `latest`。

### 检出并校验配对

```bash
git clone --recurse-submodules https://github.com/GMorandi/ScalaAPI.git
cd ScalaAPI
scripts/validate-pair.sh
scripts/generate-pair-manifest.sh /tmp/scalaapi-pair-manifest.json
```

`validate-pair.sh` 会拒绝:不干净的超项目、未初始化或错位的 gitlink、脏的组件
工作树、无效的组件 `SHA256SUMS`,以及 Platform 权威 Cap'n Proto schema 与
Gateway vendored 副本之间的任何差异。`generate-pair-manifest.sh` 在写 JSON 前
执行相同校验;它不记录测试结果,也不宣称被跳过的工作通过。

任何校验失败都是发布阻断项,不得降级为警告或在 CI 中绕过。

本地前置:Bash、Git、GNU `sha256sum`、`cmp`、`jq`。GitHub Actions 工作流会
安装构建所需的 .NET、Node、C++、CMake 与 PostgreSQL 依赖。

### 升级受支持配对

1. 在 Platform 与 Gateway 组件仓库提交并推送兼容变更。不得用未提交的组件工作树
   作为候选 pin。
2. 拉取各组件并 detach 到精确的已评审 commit:

   ```bash
   git -C platform fetch origin
   git -C platform checkout --detach <platform-commit>
   git -C gateway fetch origin
   git -C gateway checkout --detach <gateway-commit>
   ```

3. 暂存两个 gitlink,然后校验候选配对。local-only 标志仅允许刻意暂存的超项目
   更新;组件工作树与 gitlink 一致性检查保持严格:

   ```bash
   git add platform gateway
   scripts/validate-pair.sh --allow-superproject-dirty
   ```

4. 将两个 pin 合并为一个提交并开 PR。配对 CI 会:构建并测试 Gateway;对空
   PostgreSQL 17 数据库跑两遍 Platform;跑全部 Platform 测试与基准冒烟;对两个
   Web 应用做 typecheck、构建与 Playwright e2e;构建并漏洞扫描全部五个发布镜像;
   并在完整 docker compose 栈(网关、平台、管理 API、provider mock)中驱动一次
   可计费聊天请求,附带结算断言与真实 User Web 规格。全部通过后才上传机器可读
   的配对 manifest。
5. 配对提交合并后,在该超项目 commit 上创建 SemVer 标签并推送:

   ```bash
   git tag -a v1.2.3 -m "ScalaAPI v1.2.3"
   git push origin v1.2.3
   ```

标签工作流在 registry 登录或镜像推送前复用完整配对 CI;拒绝发布 registry 中
已存在的标签;先构建全部五个镜像、全部成功后才推送;以精确的超项目标签发布
Gateway 与四个 Platform 运行时镜像,随后输出包含三个 commit、契约摘要、完整
迁移清单、产出运行的逐门禁 CI 结论与 registry 报告的镜像摘要的发布证据。
