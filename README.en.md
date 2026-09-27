# QNAP TS-230: removing the built-in system-fan PWM cap

**Language:** [Русский](README.md) · English

This repository preserves the complete investigation of a system-fan speed
limit on a QNAP TS-230 and provides a reproducible QPKG named `QNAP-PWM`.

## Why this project exists

The original 80 mm chassis fan in a QNAP TS-230 was replaced with an
**ARCTIC P8 Slim PWM PST 80 mm**, a four-wire PWM fan rated for up to 3000 RPM.
The exact model number and rated speed printed on the removed QNAP fan were not
recorded during the original session, so this project deliberately does not
invent them.

After the replacement, QTS was set to a fixed **100%** fan speed but reported
only about **2200 RPM**. The reason was not a defective ARCTIC fan. QTS kept
using the TS-230 model profile intended for the stock hardware. That profile
capped the final MCU command at `MAX_PWM = 178` on a 0…255 scale.

```text
178 / 255 = 69.8%
```

After changing the cap to 255 and reapplying 50% then 100% in the QTS GUI, the
fan reached **2970 RPM**. The purpose is not to force 3000 RPM continuously.
It is to make the full range of the replacement fan available while retaining
QTS Smart Fan, temperature policy, tachometer monitoring, and fail-safes.

## Proven result

Before:

```text
QTS fixed speed: 100%
model MAX_PWM:   178/255
observed speed:  about 2200 RPM
```

After:

```text
QTS fixed speed: 100%
model MAX_PWM:   255/255
observed speed:  2970 RPM
```

PWM duty and RPM do not have to be perfectly linear, but `2200/3000` is close
enough to `178/255` to support the diagnosis. The 2970 RPM result after the
single model-profile change confirms it experimentally.

## Tested system

| Item | Observed value |
| --- | --- |
| NAS | QNAP TS-230 |
| QTS internal model | `TS-XA28A` |
| Kernel and architecture | Linux 4.2.8, `aarch64` |
| Replacement fan | ARCTIC P8 Slim PWM PST 80 mm, up to 3000 RPM |
| Model profile | `/etc/model_Q04Z0_Q0500_10_10.conf` |
| `/etc/model.conf` | symlink to that model profile |
| Fan transport | `FAN_UNIT = MCU`, `FAN_1 = I1:C0` |
| Original cap | `MAX_PWM = 178` |
| Modified cap | `MAX_PWM = 255` |

Do not blindly apply this change to another model. Run diagnostics first and
require the same profile, fan transport, and original values.

## Where to start

The complete English reconstruction is in
[`docs/en/COMPLETE_GUIDE.md`](docs/en/COMPLETE_GUIDE.md). It contains:

- the original problem and desired outcome;
- all important observations and commands;
- the investigation chronology, including failed approaches;
- the manual diagnostic, apply, verification, and rollback procedure;
- the QTS/HAL/MCU architecture explanation;
- QPKG design, local build, installation, and boot verification;
- troubleshooting and known unknowns.

The original Russian documentation is intentionally split into smaller files:

- [`docs/START_HERE.md`](docs/START_HERE.md)
- [`docs/PROBLEM.md`](docs/PROBLEM.md)
- [`docs/INVESTIGATION.md`](docs/INVESTIGATION.md)
- [`docs/TIMELINE.md`](docs/TIMELINE.md)
- [`docs/MANUAL_METHOD.md`](docs/MANUAL_METHOD.md)
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`docs/QPKG.md`](docs/QPKG.md)
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)

Raw outputs saved from the SSH session are in
[`logs/session-evidence.txt`](logs/session-evidence.txt). Secrets are excluded.

## Safe diagnostic helper

The helper is read-only unless an explicit apply or rollback option is given:

```sh
sh scripts/qnap-ts230-fan-cap.sh
```

One-time apply after reviewing its output:

```sh
sudo sh scripts/qnap-ts230-fan-cap.sh --apply-255
```

Rollback:

```sh
sudo sh scripts/qnap-ts230-fan-cap.sh --restore-178
```

The helper validates the platform, resolved profile path, `[System FAN]`
section, MCU assignment, and expected values. It creates a backup before a
change and never writes directly to PWM sysfs or SoC registers.

## QPKG

The ready-to-install package and checksums are under [`release/`](release/).
Install it using QTS App Center → **Install Manually**. QTS will warn that this
locally built package is unsigned. Verify its SHA-256 before accepting it.

The package service runs at boot because `/etc/model.conf` is recreated by QTS.
It waits for the profile, validates every invariant, changes only the expected
`MAX_PWM`, asks the normal HAL path to reapply fan control, clears that override,
and logs the result in:

```text
/mnt/HDA_ROOT/.config/qnap-pwm.log
```

The source is in [`qpkg/`](qpkg/). See the complete guide for installation,
removal, build, and boot-test details.

## GitHub Actions

`.github/workflows/build-qpkg.yml` performs shell syntax checks and builds the
QPKG with QDK 2.3.11 on every push and pull request. The resulting `.qpkg` and
checksum files are uploaded as a workflow artifact.

Pushing a version tag such as `v1.0.0` additionally creates a GitHub Release
and attaches the QPKG plus SHA-256 and MD5 checksum files.

## Important limitations

- The result was confirmed on the listed TS-230 configuration only.
- `/etc/model.conf` persistence after reboot is not assumed; that is why the
  QPKG reapplies the validated change during startup.
- A real cold-boot test of the currently committed rebuilt QPKG and behavior
  after a future QTS update still have to be verified on the NAS.
- A QTS update can replace the profile or change its semantics. Recheck the log,
  fan speed, and temperatures after every update.
- The stock fan's exact label was not captured in the original session.

## License

MIT. This is an unofficial system modification and is not affiliated with or
supported by QNAP or ARCTIC.
