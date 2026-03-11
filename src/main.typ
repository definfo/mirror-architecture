#import "@preview/touying:0.6.1": *
#import "lib.typ": *

#show: sjtu-theme.with(config-info(
  title: [An overview of SJTUG mirror infrastructure],
  author: [SJTUG],
  date: datetime.today(),
  institution: [Shanghai Jiao Tong University],
))

#show raw.where(lang: "log"): it => {
  set text(size: 12pt)
  raw(lang: "bash", it.text)
}

#title-slide()

#outline-slide()

= Current Status

== Physical Resources

- Storage:
  - Local Storage @ Zhiyuan: 12.73 TiB, *93%* used
  - iSCSI @ Siyuan: 54.35 TiB, 56% used
  - jCloud S3: Bad performance to list-object #emoji.cat.angry
    - Consider pre-caching S3 uploads in `mirror-intel` to mitigate this issue.

== Software Stack

- Main repo
  - #githublink("https://github.com/sjtug/mirror-docker-unified", text: "mirror-docker-unified"):
    service orchestration via docker-compose;
    configuration management;
    templated codegen for Caddyfile, S3 routing, etc.

- Sync tools
  - #githublink("https://github.com/sjtug/mirror-clone", text: "mirror-clone"): general-purpose fetcher
  - #githublink("https://github.com/sjtug/mirror-intel", text: "mirror-intel"): reverse proxy backend with smart cache
  - #githublink("https://github.com/sjtug/rsync-sjtug", text: "rsync-sjtug"): rsync pulling to S3 bucket and HTTP serving from S3 bucket
  and helper scripts under `mirror-docker-unified:lug/worker-scripts`
  - #githublink("https://github.com/sjtug/lug", text: "lug"): service backend, lightweight task scheduler for sync orchestration

---

= Sync tools

#align(center)[
  #text(size: 24pt, weight: "bold")[mirror-clone]
  #v(4pt)
  #text(size: 14pt)[All-in-One High-Performance Repository Mirroring]
]
#grid(
  columns: (1fr, 1fr),
  gutter: 12pt,

  [
    == Purpose & Functionality
    Synchronizes package repositories from upstream to mirror targets.
    Supports: PyPI, Rustup, crates.io, Homebrew, Dart/Pub, PyTorch, Flutter, GitHub Releases, Gradle

    == Core Abstractions
    - SnapshotStorage: Captures file list
    - SourceStorage: Retrieves content from upstream
    - TargetStorage: Delivers to destination
    - SimpleDiffTransfer: Orchestrates sync
  ],

  [
    == Synchronization Strategy
    Simple Diff Transfer: Compares filename lists, transfers only missing objects.

    Source ──snapshot()──▶ File List A ──┐
    ├── Diff ──▶ Transfer Missing
    Target ──snapshot()──▶ File List B ──┘

    - Concurrent processing (default 128 buffered)
    - 60-second timeout
    - Trait-based polymorphism for extensibility
  ],
)

#align(center)[
  #text(size: 24pt, weight: "bold")[mirror-intel]
  #v(4pt)
  #text(size: 14pt)[Intelligent Caching Proxy / Redirector]
]
#grid(
  columns: (1fr, 1fr),
  gutter: 12pt,

  [
    == Lazy Caching Strategy
    Cache Hit: Object in S3 → redirect to S3 (permanent)
    Cache Miss: Redirect to upstream → background download to S3

    Serves popular content from fast S3, avoids storage bloat.

    == Concurrency Control
    - Bounded channel (16384 tasks)
    - Semaphore downloads (256 concurrent)
    - Deduplication via HashSet
  ],

  [
    == Architecture Flow
    Client ──Request──▶ mirror-intel
    │
    ┌───────────┼───────────┐
    ▼           ▼           ▼
    Cache Hit    Queue      Check S3
    (S3 Redirect)  Task          │
    │           │           │
    │      Download ──▶ Upload to S3
    │        Worker
    └───────────┐
    ▼
    Client ←── fast redirect
  ],
)

#align(center)[
  #text(size: 24pt, weight: "bold")[rsync-sjtug]
  #v(4pt)
  #text(size: 14pt)[High-Performance Rsync-to-S3 with Atomic Updates]
]
#grid(
  columns: (1fr, 1fr),
  gutter: 12pt,

  [
    == Key Features
    - Atomic updates (users never see partial repos)
    - Delta transfer (only changed blocks)
    - Garbage collection of old versions
    - Content-addressed storage (Blake2b-160)

    == Components
    - rsync-core: Shared types, PostgreSQL, S3
    - rsync-fetcher: Rsync receiver protocol
    - rsync-gateway: HTTP server with 2-level cache
    - rsync-gc: Garbage collection
  ],

  [
    == Revision States
    Live: Production-ready, served
    Partial: Currently syncing
    Stale: Marked for GC

    == Delta Transfer Pipeline
    Download Basis ──▶ Generate Requests ──▶ Receive Deltas ──▶ Upload to S3
    │
    PostgreSQL (metadata) ◀┘
  ],
)

`mirror-docker-unified` is the main repo for our mirror infrastructure:

```log
.
apache              caddy                       caddy-gen                 clash
common              config.siyuan.yaml          config.zhiyuan.yaml       data
devshell.toml       docker-compose.ci.yml       docker-compose.local.yml  docker-compose.siyuan.yml
docker-compose.yml  docker-compose.zhiyuan.yml  docs                      flake.lock
flake.nix           flakes                      frontend                  gateway-gen
git-backend         integration-test            LICENSE                   lug
Makefile            mirror-intel                postgresql.siyuan.conf    postgresql.zhiyuan.conf
README.md           rsync-gateway               rsyncd                    scripts
secrets
```

- `config.{siyuan,zhiyuan}.yaml`: top-level mirror configuration *without mirror-intel*
  - default `Rocket.toml` -> `mirror-intel/Rocket.toml`. Merged into config.yaml in the future?
- `docker-compose.*.yml`: service orchestration

- `caddy-gen` / `gateway-gen`: "codegen" Python scripts
  - From top-level `config.{siyuan,zhiyuan}.yaml`
  - To
    - webserver configuration (`Caddyfile.{siyuan,zhiyuan}`)
    - `rsync-sjtug` configuration (S3 routing): (`rsync-gateway/config.{siyuan,zhiyuan}.toml`)

- `mirror-intel/Rocket.toml`

== Daily Maintenance

- 检查服务状态
  - #strike("清理又双叒叕满了的根分区")
- 观测 mirror-requests issue 列表
  - 文档更新：在 mirror-docker-unified 或 portal 仓库下提交 PR
    重定向至 #iconlink("https://help.mirrors.cernet.edu.cn", text: "MirrorZ Help")

---

- 观测 mirror-requests issue 列表
  - 新增镜像：评估可行后，根据对应同步方式提交 PR
    - 反代+缓存：在 mirror-intel 添加新的上游以及过滤规则，重新部署
    - Rsync：
      - worker-scripts/rsync-fetcher.sh
      - worker-scripts/rsync.sh (rsync-sjtug)
    - Git：
      - worker-scripts/git.sh
      - worker-scripts/github.sh
    - HTTP(S)：worker-scripts/mirror-clone-v2.sh

---

- #strike("以及清理同步工具的陈年issue")
  - #githublink(
      "https://github.com/sjtug/mirror-intel/issues/72",
      text: "mirror-intel#72: Return 404 for non-existent files instead of 403",
    )
  - #githublink(
      "https://github.com/sjtug/mirror-docker-unified/issues/467",
      text: "mirror-docker-unified#467: Support secrets in lug config",
    )

= On-going Projects

== Renewed `lug` backend and top-level config schema

Observability issues are the major bottleneck for the legacy `lug`.

- `lug` is designed to print

  (1) polling logs

  (2) sync script stdout/stderr

  directly to stdout. This results in no direct access to per-repo logs.

---

当前日志示例：

```log
siyuan-lug  | time="2026-03-11T03:09:20Z" level=info msg="Start polling workers" event=poll_start manager=
siyuan-lug  | time="2026-03-11T03:09:20Z" level=info msg="Interval of w git/lean4-packages/batteries (3600 sec) elapsed, send it to pendingQueue" event=trigger_pending manager= target_worker_interval=3600 target_worker_name=git/lean4-packages/batteries
siyuan-lug  | time="2026-03-11T03:09:20Z" level=info msg="Interval of w ros (3600 sec) elapsed, send it to pendingQueue" event=trigger_pending manager= target_worker_interval=3600 target_worker_name=ros
siyuan-lug  | time="2026-03-11T03:09:20Z" level=info msg="Stop polling workers" event=poll_end manager=
siyuan-lug  | time="2026-03-11T03:09:30Z" level=info msg="Start polling workers" event=poll_start manager=
siyuan-lug  | time="2026-03-11T03:09:30Z" level=info msg="Interval of w git/homebrew-services.git (3601 sec) elapsed, send it to pendingQueue" event=trigger_pending manager= target_worker_interval=3601 target_worker_name=git/homebrew-services.git
siyuan-lug  | time="2026-03-11T03:09:30Z" level=info msg="Interval of w git/lean4-packages/lean4-cli (3600 sec) elapsed, send it to pendingQueue" event=trigger_pending manager= target_worker_interval=3600 target_worker_name=git/lean4-packages/lean4-cli
siyuan-lug  | time="2026-03-11T03:09:30Z" level=info msg="Stop polling workers" event=poll_end manager=
siyuan-lug  | time="2026-03-11T03:09:40Z" level=info msg="Start polling workers" event=poll_start manager=
siyuan-lug  | time="2026-03-11T03:09:40Z" level=info msg="Interval of w git/lean4-packages/ProofWidgets4 (3600 sec) elapsed, send it to pendingQueue" event=trigger_pending manager= target_worker_interval=3600 target_worker_name=git/lean4-packages/ProofWidgets4
```

---

What we want:

- Per-repo logging and metrics
- Better interaction and logging format with worker scripts
- Service integration, including Prometheus, Logstash, etc.

== Monitoring

Currently `status.sjtug.org` provides only external status checks via HTTP requests.

It is beneficial to

- Per-repo access pattern & usage statistics
- Real-time traffic analysis

(`uptime-kuma` has a bad reputation on code quality thus we would like to consider alternatives.)

== Infrastructure Cleanup

- `pytorch-wheels` still relies on the legacy version of  `mirror-clone`.
- Migrate from the end-of-life Rust dependency `rusoto-s3` to `aws-sdk-s3`. (Already ported for `mirror-intel` but not deployed online, `mirror-clone` not touched yet.)
  - AWS does not provide any migration guide. #emoji.cat.angry
- Deprecation policy for mirrors that are no longer maintained by upstream.

== End <touying:unoutlined>

#end-slide[
  Thanks for Listening!
]
