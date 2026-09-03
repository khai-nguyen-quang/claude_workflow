# HIL (`vision_hil`) — General Knowledge

Orientation reference for reviewing hardware-in-the-loop CI work. Durable background only — no
MR-specific detail. OTA domain background lives in `summary_ota.md`.

**Primary sources:** `docs/ota-ci-strategy.md` (design), `ci/vision_hil_runner.md` (operator
runbook), `.gitlab/ci/vision-hil.yml` (job definition), `tools/verify/` (the orchestrator),
`system/testing/mocks/ota_server.py` (mock server).

---

## 1. Why it exists

The Docker test suite proves the `updated` daemon's state machine and HTTP error handling, but
**never triggers a real reboot, never flips a real A/B slot, and never talks HTTPS over WiFi**.
`vision_hil` closes that gap: a persistent GitLab runner with a real RK3588 board attached, running
an `ota-e2e` job against production binaries on every MR.

It is explicitly designed as **shared foundation** for all future hardware e2e jobs
(`streaming-e2e`, `dms-e2e`), not as OTA-specific plumbing.

---

## 2. Topology — three parties

```
GitLab CI
  └── ota-e2e job   (tags: [vision_hil], stage: e2e, needs: build-cross-compile)
        │  dispatched to the persistent runner host
        ▼
  vision_hil runner host  (Ubuntu, static IP 10.101.0.2, SHELL executor)
        ├── verify_rk3588.py --ci      ← orchestrator, scenario iterator
        └── mock OTA server            ← HTTPS subprocess, ephemeral port (bind :0)
        │
        ├── ADB over USB   ── CONTROL PLANE ──▶  RK3588 device
        │      every Params write, process start/stop, state poll, reboot signal
        │
        └── HTTPS over WiFi ── DATA PLANE ──◀    device fetches the OTA artifact
```

Two hard rules follow from this split:

- **ADB is the only control channel.** Nothing reaches the device except through an ADB session.
- **The runner is the HTTPS server, the device is the client.** WiFi carries bytes only.

### Runner constraints worth knowing

| Constraint | Why |
|---|---|
| **Shell executor**, not Docker | The job runs `adb` against a USB-attached device; a Docker executor would isolate it from the device |
| Static IP `10.101.0.2` | It is the mock server's bind address *and* the TLS SAN. DHCP drift ⇒ every job fails on TLS handshake |
| Runner tag `vision_hil`, never `vision` | `vision` is the x86 Docker fleet tag; adding it would route Docker jobs to a host with no Docker daemon |
| GitLab Runner ≥ 13.5 | Older runners leave `CI_JOB_STATUS` empty in `after_script`, silently skipping retention cleanup |
| System Python has `cryptography` + `PyYAML` | CI jobs do **not** activate `/opt/vision_hil/venv`; that venv is bench/dev only. Pins in `tools/scripts/vision_hil_requirements.txt`, matched to the CI Docker image |
| `git-lfs` installed | The default `before_script` runs `git lfs pull` |
| Device WiFi provisioned once, persistently | The job **never** re-provisions WiFi (`ctk-wifi` / `/userdata`, from `tvi-system-artifacts`) |
| Slot-1 invariant | `readlink /opt/openpilot` must be `/openpilot_1` — `tools/verify` is hardcoded to slot 1 |

### CI variables (project scope)

| Variable | Value | Notes |
|---|---|---|
| `VISION_HIL_RUNNER_IP` | `10.101.0.2` | Must be an IP **literal** — a DNS name breaks device-side SAN validation |
| `VISION_HIL_DEVICE_SERIAL` | ADB serial | From `adb devices`; selects among multiple attached boards |
| `OTA_E2E_SCENARIOS` | comma-separated list | Defined in `.gitlab/ci/vision-hil.yml`, **order-provided** |
| `HIL_ONLY` | `"false"` default | See §7 |
| `MAX_VERSION` | version string | Soft-fail drift monitor; warns when the device's baseline version climbs too high |

---

## 3. Concurrency model — the part that matters most for review

- `resource_group: hil-device-vision_hil` on the `.vision-hil-e2e` template makes GitLab
  **serialise** every hardware job. That single line is what today prevents concurrent ADB access,
  concurrent port binds, and concurrent Params writes. It is hardcoded for the single-device MVP;
  per-serial interpolation (`hil-device-$VISION_HIL_DEVICE_SERIAL`) is deferred because GitLab's
  variable interpolation in `resource_group` varies by release.
- `interruptible: false` on the template (overriding the pipeline-wide `default: interruptible:
  true`): a new push must not kill a job mid-scenario, because a kill leaves device state the next
  job inherits. `publish-arm64` has the same override.
- `retry: { max: 1, when: runner_system_failure }` — infrastructure blips retry once; **scenario
  failures never retry**.
- `allow_failure: true` — still a **soft gate** while the hardware stabilises. A failing `ota-e2e`
  shows in the pipeline and its JUnit report but does not block the MR. Flip to `false` once the
  device/USB link stops dropping.

> Because serialisation is the only thing making single-instance assumptions safe, any code that
> assumes "only one harness runs at a time" is *latently* wrong. That is exactly the class of issue
> #478 addresses.

---

## 4. Job anatomy

### Template `.vision-hil-e2e`

Leading dot ⇒ GitLab never runs it directly. It pins `stage: e2e`, `tags: [vision_hil]`,
`resource_group`, `retry`, `interruptible: false`, `allow_failure`, and
`artifacts: {when: always, expire_in: 7 days, reports: {junit: "*-e2e-results.xml"}}`.

**It deliberately defines no `script:` / `before_script:` / `after_script:`.** GitLab `extends:`
shallow-merges array-typed keys, so a template-level cleanup step would be *silently replaced* by
any extending job that declares its own. Keeping them out forces each job to own its full lifecycle.

**Contract for extending jobs:** JUnit filename must match `*-e2e-results.xml`; the extending job
owns its whole lifecycle; declare only `artifacts.paths` in the extending block (which merges
cleanly with the template's `when`/`expire_in`/`reports`); use a disjoint `<job>-*` sidecar prefix.

### Job `ota-e2e` lifecycle

`before_script` — bracketed steps, each with `step <N> begin` / `step <N> end` markers:

1. **runner hygiene** (`--ci-runner-hygiene`) — dependency smoke test (`cryptography`, `PyYAML` in
   system Python), orphan mock-server sweep, CI-variable preflight, device disk hygiene
   (unconditional wipe of `/data/media` and `/data/update` — the 7.9 GB `/userdata` otherwise fills
   with loggerd recordings and Params writes start failing), retry-archive management.
2. **artifact preparation** (`--ci-prepare-payload`) — read the larch64 tarball's version, bump the
   patch component, rewrite, sign, emit the trigger JSON.
3. **mock server launch** — `gen_ota_server_cert.py` binds a self-signed cert to the runner IP, then
   the server starts and publishes its PID/port sidecars.
4. **device staging** — `provision_device.py --clean --push /openpilot_1` deploys the *unsigned*
   larch64 package to the slot the tests expect.
5. **device provisioning** (`--ci-provision`) — see §5.

`script` — `verify_rk3588.py --ci --serial … --artifacts … --report junit:ota-e2e-results.xml`.

`after_script`:

1. **triage capture** (`--ci-teardown-preflight`) — JSON snapshot of device state *before* mutating
   anything, always attempted.
2. **device teardown** (`--ci-teardown`) — best-effort restore, see §5.
3. **mock-server teardown** — signal the server, remove sidecars, drop the baseline pubkey snapshot
   only if triage succeeded.
4. **retention and reset** — drop the intermediate versioned tarball on success, then
   `adb kill-server` so a stale ADB connection cannot leak into the next job.

---

## 5. Device provisioning and teardown

Provisioning is **Python-owned and atomic**: one function,
`tools/verify/lib/ci_provision.py::provision_device`, invoked from bash as a single call, so there
is no window in which the device is half-provisioned.

Order (abort-early — a failure in the checks mutates nothing):

1. `adb wait-for-device` (30 s).
2. **Pre-flight state checks** via `check_device_state` — `slot` (`/opt/openpilot → /openpilot_1`),
   `version` (`^v\d+\.\d+\.\d+$`), `params` (no leftover `priv_OTA_*`), `trust`. Any dirty state
   raises `DeviceStateDirtyError` **before any mutation**.
3. **Baseline pubkey snapshot** — copy the device's `ota_pub.key` to the runner via atomic
   tmp-then-rename. Runs before any drain or canary so the original is captured even if a later step
   fails.
4. **Manager stop + drain `updated`** (30 s, escalating).
5. **Canary TLS probe** — confirm the on-device `updated` was built with `OTA_DEBUG_TLS` acceptance
   by pointing it at a loopback dummy endpoint (`127.0.0.1:65535`, never actually contacted) and
   scanning swaglog for the CA-acceptance signal. Its own teardown removes `priv_OTA_Endpoint`
   first — same ordering as the outer teardown.
6. **Provisioning writes** — push CA bundle; push the test Ed25519 pubkey into
   `<slot>/system/updated/keys/ota_pub.key`; `priv_DEV_MODE=factory1`; `OtaMaxRetries=1` (so a
   connection failure yields `maxRetriesExceeded` immediately rather than after exponential
   backoff); `priv_OTA_Endpoint` pointing at the mock server (IP from `VISION_HIL_RUNNER_IP`, port
   read from the sidecar — the endpoint is not knowable before the server is up).
7. **Manager restart + readiness poll** (`MANAGER_READINESS_TIMEOUT_SECS` = 120 s; the production
   profile on RK3588 needs > 30 s to bring `updated` up).

**Teardown (`--ci-teardown`) is the reverse, and best-effort** — every step wrapped so a single
failure does not skip the rest:

1. **Remove `priv_OTA_Endpoint` FIRST — the respawn kill-switch.** Manager
   (`selfdrive/manager/process_config.py`) respawns `updated` whenever that key exists, so removing
   it first closes the race where `updated` exits naturally between "stop manager" and "drain" and
   manager respawns it.
2. Stop manager. 3. Drain `updated` (SIGKILL on timeout). 4. Restore the baseline pubkey (remount
   rw → cp → remount ro). 5. Remove the test CA. 6. Wipe `OtaMaxRetries`.

Not automated in MVP: **version revert** (a full A/B revert is a manual procedure). The remaining
`priv_OTA_State` / `_Request` / `_Ack` keys are left in place on purpose — the *next* job's params
pre-flight raises `DeviceStateDirtyError` rather than silently masking dirty state.

Manual recovery: `verify_rk3588.py --ci-manual-recover --check <slot|version|params|trust>` inspects
without mutating. `--dry-run` exists on `--ci-provision` / `--ci-teardown` for a runner preflight.

Timeouts: `MANAGER_STOP_TIMEOUT_SECS` 20 s, `MANAGER_POLL_INTERVAL_SECS` 0.5 s,
`CANARY_PROBE_TIMEOUT_SECS` 120 s, `MANAGER_READINESS_TIMEOUT_SECS` 120 s.
`OTA_E2E_DRAIN_TIMEOUT_OVERRIDE` (clamped to [10, 60]) overrides drain timeouts on a bench device.

---

## 6. Scenarios

Registered in `tools/verify/registry.py`, implemented in `tools/verify/scenarios/`. The CI job runs
four **negative** scenarios; the happy path (`ota`, real reboot) is deferred to #390 until WiFi
persistence and A/B revert automation stabilise.

| # | Scenario | Artifact | Terminal state | Reboots |
|:-:|---|---|---|:-:|
| 1 | `ota_hash_fail` | `--corrupt-hash`, version `V0+1` | `phase=idle`, `last_error=hashFailed` | 0 |
| 2 | `ota_sig_fail` | `--corrupt-signature`, version `V0+1` | `signatureFailed` | 0 |
| 3 | `ota_downgrade_fail` | well-formed, version `V0−1` | `versionRejected` | 0 |
| 4 | `ota_connect_fail` | well-formed, `V0+1`; **server stopped after trigger** | `maxRetriesExceeded` | 0 |

**Order is load-bearing.** 1–3 must run while the device is still on `V0` because none of them ever
reach `applying`. 4 must be last because its `_setup` stops the shared mock server.

`OTA_E2E_SCENARIOS` is order-provided. Unknown names make the runner exit non-zero **before any
scenario runs** (typos fail closed), and `_resolve_scenario_selection` in `tools/verify/cli.py`
enforces the single hard invariant: if `ota_connect_fail` is present it must be last. The
version-arithmetic invariants are the operator's responsibility.

Version handling: shape `^v\d+\.\d+\.\d+$` is the single source of truth, duplicated in
`tools/scripts/make_ota_artifact.py` and `tools/verify/lib/ota.py`. The bump is **patch-only,
unbounded, `v`-preserving**: `v1.0.99 → v1.0.100`, `v1.99.99 → v1.99.100`, never `v2.0.0`.

Other registered scenarios (device-only, not in the CI job): `ota`, `ota_ctk_revert`,
`ota_auto_revert`, `production`, `streaming`, `dms_health`, `modeld_thneed`, `adas`,
`preflight_only`.

---

## 7. Trust boundary for test signing

- The test Ed25519 keypair is **committed** under `tools/verify/keys/`, isolated from any production
  build target.
- The public half is pushed to the device at provisioning and removed at teardown — **additive and
  temporary**. It coexists with whatever key the device already carries, so the device returns to
  its pre-job trust state unconditionally.
- This rests on the assumption that the daemon accepts a signature from **any** key in its trust
  set. If that ever changes to "replace", the additive model breaks.
- A leak of the test private key enables signing test artifacts only — production devices carry a
  different, flash-time key. Rotation = regenerate, update the fixture, re-push to HIL devices.

---

## 8. Pipeline plumbing

- **`HIL_ONLY=true`** masks every x86 job so only `fetch-models` + `fetch-thneed` →
  `build-cross-compile` → `ota-e2e` run. Realised by two rule anchors in `.gitlab-ci.yml`:
  `.x86_rules` (build/test/asan/tsan/integration/lint-cpp/lint-python/publish-arm64) and
  `.x86_lint_rules`, each opening with `if: $HIL_ONLY == "true" → when: never`.
  `build-cross-compile` and `ota-e2e` deliberately do **not** reference `.x86_rules`.
  `workflow:rules` admits `$CI_PIPELINE_SOURCE == "web"` so operators can trigger it from
  Build → Pipelines → New pipeline without pushing a branch. It exists to iterate on HIL infra
  cheaply — **not** a substitute for full validation before merge.
- **Job-level retry** of only `ota-e2e` from the GitLab UI reuses `build-cross-compile` artifacts
  (valid 1 day), cutting iteration to ~2–3 min. Corollary: a pipeline queued > 1 day fails on the
  artifact download.
- `ota-e2e` has a `rules: changes:` path filter (`system/updated/**`, `cereal/**`, `common/**`,
  `tools/verify/**`, the OTA tool scripts, `third_party/**`, `VERSION`, …), so it does not run on
  unrelated MRs. CI gate equality, ladder ordering, HIL guards, and needed-producer safety are
  asserted by repository-anchored tests (`ci/test_selection/audit.py`) — **change a gated job and
  you must update the canonical gate + audit evidence in the same changeset**.
- To disable the job during maintenance: replace its `rules` with `when: manual` (plain YAML edit,
  no runner access) and link a tracking issue in the commit.

---

## 9. Diagnostics contract

Three log streams, all declared `when: always` so a failed MR is triageable from the artifact bundle
alone: the orchestrator log, the mock server log, and per-scenario device logs (plus a bounded
job-level device log on any job failure, for pre-scenario triage).

**Every line carries a `[scenario=<name>]` prefix** — this is the primary correlation mechanism,
because runner and device clocks drift and must not be relied on. The convention covers the whole
lifecycle: setup lines are `[scenario=setup]`, teardown lines `[scenario=teardown]`. It is
step-inclusive: `step <N> begin` / `step <N> end` markers window raw subprocess stdout (adb,
`provision_device.py`, the mock server) to a specific step. Stated contract: *every line, every
step, every failure mode*. Pre- and post-scenario failures are the hardest triage case precisely
because their lines would otherwise have no tag.

`MAX_VERSION` drift warnings are surfaced as a labelled JUnit annotation, not just a log line —
a warning that only lives in the console is missed on passing jobs, which is when it matters.

---

## 10. Common failure modes (from the runbook)

| Symptom | Cause | Fix |
|---|---|---|
| `error: device not found` | USB detach mid-job | check cable, `adb wait-for-device`, re-trigger |
| `maxRetriesExceeded` in the *wrong* scenario, or `ota` stalls downloading | WiFi drop | ping the runner from the device; re-provision WiFi + reboot |
| `ota_debug_tls_check=tls_rejected` | CA not pushed, or cert SAN ≠ actual runner IP | confirm `VISION_HIL_RUNNER_IP` = the bound static IP |
| version-format rejection in `--ci-prepare-payload` | package version not `v<N>.<N>.<N>` | fix `VERSION` / `VERSION_TAG` derivation |
| `state-dirty: slot` | A/B stack flipped the active slot | vendor rollback tool, or `./dev.sh provision` to re-flash |
| orphan mock server holding a port | previous job crashed before teardown | `pgrep -af ota_server` and kill |
| `git: 'lfs' is not a git command` | runner missing git-lfs | `apt-get install git-lfs` on the host |
| `runner_ip must be an IPv4/IPv6 literal … got ''` | project CI variable missing | set it at project scope |
| jobs stuck "no runners match tag vision_hil" | runner registration deleted server-side | re-register with a new token, clean `config.toml` |

Known gap: `provision_device.py` leaves the slot mount read-write after `--clean --push`;
`--ci-provision` handles mount state defensively. The `ro` re-mount fix is deferred.

---

## 11. Vocabulary cheat-sheet

| Term | Meaning |
|---|---|
| HIL | Hardware-in-the-loop — CI running against real hardware rather than mocks |
| `vision_hil` | The runner tag, the runner host, and the class of jobs that target it |
| Harness | The runner-side machinery: orchestrator + mock server + sidecar files |
| Sidecar | A small file the harness writes to publish runtime state (pid, port, cert, module name) |
| Orchestrator | `verify_rk3588.py --ci` / `tools/verify/` — iterates scenarios, emits JUnit |
| Canary probe | The loopback TLS check that proves the device build accepts the test CA |
| Respawn kill-switch | Deleting `priv_OTA_Endpoint` first, so manager stops respawning `updated` |
| Drift / `MAX_VERSION` | The device's baseline version climbing over repeated jobs; remediated by re-flashing |
| `V0` | The device's starting version for a job — a placeholder, not a literal |

---

## 12. Related docs

- `docs/ota-ci-strategy.md` — the design document this digests
- `ci/vision_hil_runner.md` — setup, operations, troubleshooting, pre-commit checklist
- `docs/ci.md` — pipeline-wide rules, gate audit, interruptible policy
- `tools/verify/README.md` — orchestrator internals and how to add a scenario
- `summary_ota.md` — the OTA domain this job exercises
