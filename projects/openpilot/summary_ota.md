# OTA — General Knowledge (openpilot / Vision Board)

Orientation reference for reviewing OTA work. Durable background only — no MR-specific detail.

**Primary sources:** `docs/OTA.md`, `system/updated/README.md`, `ota-daemon-design.md` (referenced by
`docs/OTA.md`, not in this repo), `selfdrive/manager/process_config.py`.

---

## 1. What OTA means here

The **Vision Board (RK3588)** downloads and applies its own updates directly from the OTA backend
over **HTTPS via its USB-attached modem** — "Direct Mode". It does not receive image bytes through
the CTK board; CTK only forwards the *command*.

End-to-end chain:

```
Backend (mSwitch + OTA storage)
    │  1. OTA command over CT protocol (destination name, version, size, checksum)
    ▼
CTG3 device / CTK board
    │  2. Vision B2B 0x4200 → OTA request
    ▼
Vision Board (RK3588) ── 3. HTTPS GET ──▶ OTA server (HTTPS endpoint)
    │  4-5. streamed download, chunked to storage (resumable)
    │  6. verify: SHA256 + Ed25519 signature + version anti-rollback
    │  7. apply + reboot if required
    │  8. Vision B2B 0x1201 → result
    ▼
CTK board → 9. completion report to backend
```

**openpilot owns steps 3–8 only.** Everything else is Backend / CTG3 team territory.

---

## 2. `updated` — the daemon

`system/updated/` builds `updated`, a C++ `NativeProcess` registered in
`selfdrive/manager/process_config.py`. Manager autostarts it **after** the B2B service.

> The CTK-facing B2B service in this repo (`athenad2.py` / `updated2.py`) is a **POC kept for
> documentation only** — not started by manager, carries an `OUTDATED` header. A C++ MVP replaces
> it later. "The B2B service" in docs means that future replacement.

### Interfaces

| Direction | Channel |
|---|---|
| Inbound trigger | `priv_OTA_Request` Params key (written by B2B service) |
| Outbound status | `otaStatus` ZMQ stream — Cap'n Proto `OTAStatus` wrapping `OTAStatusEvent` (`cereal/custom.capnp`), registered in `cereal/services.py` as `"otaStatus": (False, 0.)`, `log.capnp` arm `otaStatus @156` |
| Durable progress | `priv_OTA_State` Params key |

Internally: main thread polls Params every **200 ms**, spawns a worker thread for the actual
download/verify/apply; the worker calls the Applier scripts via `execve` (blackbox pattern).

### Params channels — sole-writer discipline

Four persistent OTA keys plus one shared system key. **No key has two writers** — that is what
removes the need for cross-process locks.

| Key | Writer | Reader | Purpose |
|---|---|---|---|
| `priv_OTA_Request` | B2B service | `updated` | Per-operation command: trigger / cancel / rollback, plus `last_forwarded_for` delivery sentinel |
| `priv_OTA_Ack` | B2B service | `updated` | Reboot-flush confirmation — plain `correlation_id` string; separate key so the two-phase reboot handshake never forces a read-modify-write on the request blob |
| `priv_OTA_State` | `updated` | B2B service, `updated` at startup | Durable progress record; survives restart and reboot |
| `priv_OTA_Endpoint` | provisioning tool (install time) | `updated` (read-only) | HTTPS base URL, host allowlist, CA bundle path, TLS settings |
| `DoReboot` | `updated` worker | `manager.py` | Manager performs the actual kernel reboot |

All four OTA keys carry `DONT_LOG` so URLs and correlation IDs never reach rlogs.

**Params-as-command-channel is deliberate**: `priv_OTA_Request` and `priv_OTA_State` are PERSISTENT,
so a crash between trigger-accept and worker-spawn is safe — the startup dispatch table re-enters
the correct phase from persisted data. Same pattern as `DoReboot`.

**`priv_OTA_Endpoint` is also the respawn gate**: manager only spawns `updated` while that key
exists. Any teardown that wants `updated` to stay dead must delete the endpoint key **first**.

---

## 3. State machine

`docs/OTA.md §State Machine`. Live phases only; terminal outcomes live in
`priv_OTA_State.last_completed.outcome` (`succeeded` | `failed` | `canceled` | `reverted`).
`phase=idle` means nothing is in progress.

```
idle → downloadQueued → downloadInProgress → verifying → applying → rebootPending → idle
                              ↑ retry (backoff)          ↘ applyDeferred (unreachable in this fork)
idle → reverting → revertPending → idle          (CTK rollback command)
```

Failure edges all return to `idle` with an `error_code`:

| From | error_code | Meaning |
|---|---|---|
| `downloadInProgress` | `maxRetriesExceeded` | Retries exhausted (see `OtaMaxRetries`) |
| `verifying` | `hashFailed` | SHA256 mismatch |
| `verifying` | `signatureFailed` | Ed25519 signature invalid |
| `verifying` | `versionRejected` | Anti-rollback: version ≤ running version |
| `verifying` | `compatibilityRejected` | min/max version bounds violated |
| `applying` | `flashFailed` / `flashTimeout` / `flashInterrupted` | Applier non-zero / timeout / crash-during-apply |
| `rebootPending` | `rollbackDetected` | Post-reboot version mismatch |
| `rebootPending` | `rebootNotHonored` | Manager restarted the daemon without a kernel reboot |
| `reverting` | `revertFailed` | Reverter non-zero / timeout |

**Fork note:** this fork has no self-drive, so `IsOffroad` is permanently true — the
`applyDeferred` branch is unreachable but preserved to avoid diverging from upstream.
Cancel is **rejected** in `reverting` / `revertPending` (daemon publishes `cancelRejected`).

The four failure codes that matter most for CI (`hashFailed`, `signatureFailed`, `versionRejected`,
`maxRetriesExceeded`) all resolve **before `applying`** — so they never flash, never reboot, and
never flip a slot. That is why they are the safe scenarios to run on real hardware repeatedly.

---

## 4. Storage layout — five areas

| Area | Path | Role |
|---|---|---|
| Yocto A | Rockchip A/B rootfs slot A | Firmware (kernel + OS) |
| Yocto B | Rockchip A/B rootfs slot B | Firmware (kernel + OS) |
| Openpilot_1 | `/openpilot_1/` | openpilot binary + app configs, slot 1 |
| Openpilot_2 | `/openpilot_2/` | openpilot binary + app configs, slot 2 |
| Persistent OTA state | `/data/params` (`priv_OTA_State`) | Control-plane state, survives every slot switch |

- `/opt/openpilot/` is a **symlink** to the active openpilot slot.
- App configs live *inside* the slot tree, so rolling back a slot rolls back its configs too.
- Two **independent** slot schemes: Rockchip A/B for firmware, 1/2 for openpilot.
- `/data/params` is outside both, which is what lets `PostRebootHealthCheck` read the expected
  version regardless of which slot booted.

Version sources for anti-rollback differ per track: `/opt/openpilot/version` for `software`
components, `/etc/version` (Yocto build) for `firmware` components.

---

## 5. Three update modes

### Software-only OTA
Download → verify → `tar -x` into the **free** openpilot slot (active slot keeps running) → switch
the `/opt/openpilot` symlink → `DoReboot` → `PostRebootHealthCheck`.
On mismatch: `rollback_cause = "software_version_mismatch"` → Openpilot Reverter → reboot.

### Yocto-only OTA
Download → verify → flash the **free** Yocto slot → Rockchip A/B switch → reboot → health check.
openpilot untouched. If the new slot fails to boot, the **Rockchip bootloader auto-reverts** before
the daemon is even reached. Optional `min/max_software_version` bounds checked against
`/opt/openpilot/version`.

> BSP dependency: the auto-revert guarantee depends on bootloader max-boot-attempt / timeout
> configuration. A *degraded but booting* slot will not trigger auto-revert.

### Full firmware OTA (SM-orchestrated)
One CTK trigger, two installs, then an **ordered two-step commit**:
1. openpilot symlink switch (`--commit`) → `apply_step = openpilot_committed`
2. Yocto A/B switch → `apply_step = yocto_committed`

Both steps run inside the single `applying` FSM phase — the FSM gains **no new top-level phases**.
Progress is tracked by the sub-step field `priv_OTA_State.apply_step`
(`installing` | `openpilot_committed` | `yocto_committed`), which the startup dispatch reads to pick
the crash-recovery rule. Cross-track compatibility via `min/max_firmware_version` vs `/etc/version`.

---

## 6. Appliers and Reverters (execve blackboxes)

Everything that mutates slots is a **shell script invoked via `execve`** (never a shell), with an
exit-code contract. `updated` never restarts manager and never reboots directly.

| Script | Location | Interface |
|---|---|---|
| `openpilot_applier.sh` | `<slot_root>/selfdrive/manager/scripts/` | `--install` (tar into free slot), `--commit $target_slot` (`ln -sfn`) |
| `revert_openpilot.sh` | same dir | `revert_openpilot.sh <previous_slot_path>` — stateless, reads no Params |
| Yocto applier | `/usr/bin/updateEngine` (BSP) | `--update --partition=0x3C00` to apply; `--misc=other` to revert; `--misc=now` to confirm (init-layer duty, currently unimplemented) |

Invocation goes through the active symlink:
`$(readlink -f /opt/openpilot)/selfdrive/manager/scripts/<script>`. After a rollback the old slot
carries its own copy of both scripts, so both stay callable either way.

**Reverter exit contract:** `0` = symlink now points at the target; non-zero = symlink state is
**unknown** — the caller must not assume either slot. SM timeout is ≤ 10 s (metadata-only op).
On failure the SM does **not** retry and does **not** reboot; it leaves the symlink alone and lets
the next-boot layer observe the inconsistency.

C++ wrapper: `OpenpilotReverter` implements `IReverter::revert(previous_slot, cancel_token,
sigterm_token, stderr_tail)` over an `ISubprocessRunner`; fails closed if either slot is outside
`{/openpilot_1, /openpilot_2}` or the target already equals the active slot.

### Two defense layers for rollback

1. **SM path** — `PostRebootHealthCheck` in `updated` detects a version mismatch, writes
   `rollback_cause` durably, calls the Reverter, then writes `DoReboot`.
2. **Init-layer path** — `S90openpilot` detects `managerd` failing to start within ≤ 30 s, calls the
   same Reverter, then hard-reboots via `/sbin/reboot` (manager is dead, `DoReboot` unavailable).
   It reboots **regardless** of the Reverter's exit code.
   Testability seam: `OTA_INIT_REVERT_DRY_RUN=1` logs the intended action and exits without acting.

---

## 7. Trust model

- Packages are tarballs with a SHA256 and an **Ed25519 signature**; the device holds a **trust set**
  of public keys at `<slot>/system/updated/keys/ota_pub.key`.
- Verification accepts a signature from **any** key in the trust set — this is what makes test-key
  provisioning *additive* rather than a replacement.
- Version strings are `v<N>.<N>.<N>` (regex `^v\d+\.\d+\.\d+$`), enforced in
  `tools/scripts/make_ota_artifact.py` and `tools/verify/lib/ota.py`.
- Anti-rollback rejects any version ≤ the currently running one → `versionRejected`.

---

## 8. Vocabulary cheat-sheet

| Term | Meaning |
|---|---|
| SM | State Machine — the `updated` daemon's FSM (used interchangeably with "the daemon" in docs) |
| Slot | One of the two openpilot trees (`/openpilot_1`, `/openpilot_2`) or one Rockchip A/B firmware slot |
| Applier / Reverter | The execve'd shell scripts that commit / undo a slot switch |
| Track | `software` (openpilot) vs `firmware` (Yocto) — different version sources, different appliers |
| `apply_step` | Sub-step field inside `priv_OTA_State` tracking multi-step commit progress |
| B2B 0x4200 / 0x1201 | CTK→Vision OTA command / Vision→CTK status message |
| CTK | The CTG3 board that talks to the backend; the Vision Board's upstream peer |

---

## 9. Related docs

- `docs/OTA.md` — the authoritative design document (this file is a digest of it)
- `docs/ota-ci-strategy.md` — how OTA is validated in CI; see also `summary_hil.md`
- `system/updated/README.md` — Params schemas, thread model, source layout, build commands
- `tools/verify/scenarios/ota*.py` — the on-device scenario implementations
- `docs/provisioning.md` — flashing and deploying to a device
