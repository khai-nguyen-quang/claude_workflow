# Firmware & software versions — how they are managed and used in OTA

Orientation reference for reviewing version-related work (written for MR!253 / issue #246).
Sections 1–6 are durable background; section 7 is the MR!253 delta.

**Primary sources:** `docs/OTA.md` (§ anti-rollback, § rollback), `system/updated/verifier.cc`,
`system/updated/ota_interfaces.h`, `system/updated/post_reboot_health_check.cc`,
`ci/scripts/package.sh`, `.gitlab-ci.yml`, `system/version.py`, `tools/scripts/provision_device.py`.
Companion doc: `summary_ota.md`.

---

## 1. Two independent version tracks

Everything about versions in this repo starts here. There are **two tracks**, produced by two
different pipelines, stored in two different files, and compared separately:

| Track | Means | Produced by | File on device | Const in code |
|---|---|---|---|---|
| **firmware** | Yocto OS image (kernel, rootfs, A/B slots) | `tvi-linux` pipeline | `/etc/version` | `ota_version_paths::kFirmwareVersionPath` |
| **software** | openpilot package (binaries, models, params) | this repo's CI | `/opt/openpilot/version` (through the active-slot symlink) | `ota_version_paths::kSoftwareVersionPath` |

`ota_version_paths::path_for(ota_type)` in `system/updated/ota_interfaces.h` maps the string
`"firmware"`/`"software"` to the path. At runtime the software path always goes through
`openpilot_slots::software_version_path()`, which honours `OTA_TEST_SYMLINK` so non-root Docker
tests can redirect the read — never use the raw constant at a call site.

`IVersionReader::current(path)` (`FileVersionReader`) is the single read seam; it returns a trimmed
string, **empty on any failure** (fail-closed, no exception).

### Not the same thing: `/etc/os-release`

`/etc/os-release` is Yocto build metadata, not a release identifier:
- `VERSION_ID` → read by `HARDWARE.get_os_version()` (`system/hardware/rk3588/hardware.py`).
- `BUILD_INFO` → a build **date**, and the producing side has removed the key. This is what the
  preflight used to print, and is exactly the gap #246 closes.

---

## 2. Version format and where the string comes from

Format: **`v{MAJOR}.{MINOR}.{CI_PIPELINE_IID}`**, e.g. `v1.0.216`. Both pipelines follow the scheme
independently, so a firmware `v1.0.216` and a software `v1.0.216` are unrelated numbers.

Software side, in this repo:
- `VERSION` (repo root) holds `1.0` — the MAJOR.MINOR half.
- `.gitlab-ci.yml`: `VERSION_TAG="v$(cat VERSION).${CI_PIPELINE_IID}"`.
- `ci/scripts/package.sh --version "$VERSION_TAG"` writes it to the package root as plain text:
  `printf '%s\n' "$PACKAGE_VERSION" > "${OUTPUT_PATH}/version"` — that file *becomes*
  `/opt/openpilot/<slot>/version` on device. A local build with no `--version` gets `dev-<sha>`.
- `tools/scripts/make_ota_artifact.py --version` must match `v<N>.<N>.<N>`; the value is signed
  into the trigger as `expected_version`.

Firmware side: written into `/etc/version` by the Yocto image build (`tvi-linux`; the producing
half of #246 is tvi-linux !25). Host-side, the release the provisioning flow *expects* comes from
`CROSS_BUILDER_VERSION` in `.ci-support-version.yml` (the cross-builder image is built against the
same OS image that ships), or from a `vision-system-<version>.img[.gz]` filename with `--firmware`.

> `common/version.h` is a separate, upstream-openpilot thing: `COMMA_VERSION "0.9.4"`, sliced out as
> *text* by `system/version.py::get_version()`. It is not a release version and has nothing to do
> with OTA. (It historically also carried a `CT_VERSION` placeholder — see §7.)

---

## 3. How `updated` uses versions

### 3.1 Trigger fields (`Trigger` in `system/updated/ota_state.h`)

Per-component: `ota_type` (`"software"`/`"firmware"`), `op_type` (`"update"`/`"rollback"`),
`expected_version`, and four cross-track bounds: `min|max_firmware_version`,
`min|max_software_version`. `expected_version` is covered by the Ed25519 signature (it is part of
the signed message, alongside the domain tag, digest, size and type byte), so it cannot be swapped
without invalidating the signature.

### 3.2 Version grammar — `parse_version()` in `verifier.cc`

Leading `v`, then exactly three `.`-separated components, each parsed as `uint64` via
`std::from_chars`. Minimum length 6 (`v0.0.0`). Anything else → `nullopt`. Leading zeros are
accepted (`v1.0.09` parses). Comparison is component-wise (`Version::operator<`).

### 3.3 Anti-rollback (`check_anti_rollback`) — verify step 4 of 5

Steps are: size → hash → signature → **anti-rollback** → compatibility.

1. `expected_version` too long or unparseable → `versionRejected`.
2. Running version read from the **same track** as the component
   (`software_version_path()` or `/etc/version`).
3. Running string **empty** → `versionRejected` (a genuine error, not "assume oldest").
4. Running string present but unparseable (e.g. `dev-<sha>` local builds) → treated as **v0.0.0**,
   so any semver release is a forward update.
5. Accept only if `op_type=="update" && running < expected`, or `op_type=="rollback" && expected < running`.
   Equal versions are always rejected — reinstalling the same version is not allowed.

### 3.4 Cross-track compatibility (`check_compatibility`) — verify step 5

- `ota_type=="software"` → check `min/max_firmware_version` against **`/etc/version`**.
- `ota_type=="firmware"` → check `min/max_software_version` against **`/opt/openpilot/version`**,
  *unless* the trigger-level mode is `full_firmware` (both tracks move together, so the bound is
  skipped).
- Both bounds empty → check skipped entirely. A bound present but the running version unparseable
  or missing → `compatibilityRejected` (stricter than anti-rollback's v0.0.0 fallback — worth
  remembering, the two steps treat an unparseable running version *differently*).

### 3.5 Post-reboot health check (`post_reboot_health_check.cc`)

After the reboot, with `boot_id` confirmed changed:
- `rebootPending`: read the running version from the track's path; success iff it equals
  `expected_version` (or equals `previous_version` on the revert paths). A mismatch is classified
  into `rollback_cause`: `firmware_auto_revert` (firmware version ≠ expected → the Rockchip
  bootloader auto-reverted the A/B slot) vs `software_version_mismatch` (software ≠ expected while
  firmware matches). Both dispatch the Openpilot Reverter; only the latter also writes `DoReboot`.
- `revertPending`: success iff running version **≠** `revert_from_version` (proving the slot/symlink
  actually flipped); equal ⇒ `revertFailed`.

So the version file is the *only* evidence `updated` has that an update actually took effect —
which is why an empty or mis-formatted `/etc/version` is a real availability risk, not cosmetics.

---

## 4. Version reporting outside OTA

- `selfdrive/manager/manager.py` (startup): `params.put("Version", get_version())` and
  `params.put("SWVer1", get_ct_version())`.
- `selfdrive/athena/athenad2.py` reads the `SWVer1` param and puts it in the welcome message to the
  CTK board / backend. `SWVer1` is also a CT protocol param key (`common/keys.cc`).
- So **`get_ct_version()` is what the backend sees as the device's openpilot version** — it is a
  reporting path, but it is the fleet-visible one, and it survives reboots as a param.

---

## 5. Host-side tooling that touches versions

| Tool | Uses version for |
|---|---|
| `tools/scripts/provision_device.py` | resolves the firmware to download (`CROSS_BUILDER_VERSION`) or the `--firmware` basename; after `--flash`, reads back `/etc/version` and compares |
| `tools/verify/runner.py` (`collect_device_versions`) | preflight banner: firmware OS, firmware release, openpilot version |
| `tools/scripts/ota_trigger.py` / `make_ota_artifact.py` | build & sign a trigger carrying `expected_version` + bounds |
| `tools/scripts/prepare_ota_scenarios.sh` | auto-detects the device version to build packages that pass anti-rollback |
| `tools/verify/scenarios/ota_downgrade_fail.py` | asserts `versionRejected` for a version ≤ current |

---

## 6. Review checklist for version-touching changes

1. Which **track** does the change read/write? Does it use `path_for()` /
   `software_version_path()` rather than a hard-coded path (test-symlink support)?
2. Does any new parser agree with `verifier.cc::parse_version()`? Divergence is only acceptable in
   the **narrower** direction (reject what C++ accepts), never wider.
3. What happens on empty / unparseable / unreadable? The three sites disagree on purpose
   (anti-rollback: empty=reject, unparseable=v0.0.0; compatibility: both reject; host tooling:
   warn-and-continue). A change should state which policy it follows and why.
4. Comparison semantics: byte equality (post-reboot check, flash-time check) vs component ordering
   (anti-rollback). `v1.0.09` vs `v1.0.9` is a *mismatch* byte-wise but *equal* component-wise.
5. Does the change alter what the backend sees (`SWVer1`) or only what a human sees (a log line)?

---

## 7. What MR!253 (issue #246, consuming half) changes

Branch `feature/246-device-firmware-version`, single commit
`6490190d3 Report firmware release version from /etc/version`. Producing half is tvi-linux !25.

1. **New shared reader** `tools/verify/lib/firmware_version.py`: four states —
   `SEMVER` / `UNPARSEABLE` / `ABSENT` / `UNREACHABLE`; one device command
   (`cat /etc/version 2>/dev/null`), one classifier mirroring `parse_version()` (with a deliberate
   narrower divergence: components > 20 digits rejected), one renderer producing a single escaped,
   64-char-capped line (`(unknown)`, `(error)`, `<value> (unparseable)`).
   `read_release_version()` catches bare `Exception` and never raises; `render_release_line()`
   *does* raise `AssertionError` on an unknown state, and each caller decides how to handle that.
2. **Preflight** (`tools/verify/runner.py`, `reporters/console.py`): `firmware_build`
   (`BUILD_INFO` from `/etc/os-release` — a build date, key now removed upstream) is replaced by
   `firmware_release` read from `/etc/version`. Console now indexes the key directly and raises
   `TypeError` if it is not a `str`.
3. **Flash-time check** (`provision_device.py`): after `--flash` + `wait-for-device`, read
   `/etc/version` and compare against the expected release. Exits 1 **only** when both sides are
   valid semver and differ; every other outcome warns and continues (so a pre-rollout image or a
   transport failure cannot strand a board before `--push`). Also adds an
   `OPENPILOT_UPGRADE_TOOL` test seam and logs which upgrade_tool binary is used.
4. **`get_ct_version()` rewritten** (`system/version.py`): was slicing the `CT_VERSION`
   `@@@###2000.99###@@@` placeholder out of `common/version.h` text (a string CI/CD was meant to
   patch into the final binary); now reads `/opt/openpilot/version` (module constant
   `SOFTWARE_VERSION_PATH`, overridable for tests) and falls back to `get_version()` when the file
   is absent/empty/unreadable. **This changes what the backend sees in `SWVer1`** — the highest-blast-radius
   part of the MR.
5. **`common/version.h`**: the dead `CT_VERSION` / `get_cartrack_version()` C++ symbols are deleted;
   only `COMMA_VERSION` remains, with a long comment about the text-slicing invariant.
6. **`get_os_version()` fix** (rk3588): `startswith("VERSION_ID")` → `startswith("VERSION_ID=")`,
   so `VERSION_ID_CODENAME=` cannot match first.
7. **Tests/infra**: new `test_firmware_version_unit.py` (414 lines) and
   `test_get_ct_version_unit.py`; `system/hardware/rk3588/tests/test_rk3588_hardware.py` renamed to
   `*_unit.py` (it matched no collected pytest pattern and had **never run**) and registered in
   `ci/test_selection/paths.py` with a new `hardware` group + triggers for `common/version.h` and
   `system/version.py`; two `ruff.toml` per-file ignores.

Things worth probing in review: the `SWVer1` semantic change (§4 — fleet-visible, and the fallback
to `COMMA_VERSION "0.9.4"` off-device), the classifier's agreement with `parse_version()` (§6.2),
byte-vs-component equality in `compare_release()` (§6.4), the bare `except Exception` containment,
and whether the `assert expected_release is not None` on the auto-download path is acceptable given
`python -O` strips it.
