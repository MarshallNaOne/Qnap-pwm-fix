# Complete reconstruction: QNAP TS-230 fan PWM cap

This document is the English counterpart of the detailed Russian documentation.
It is written so that a person unfamiliar with QNAP internals can understand
what was wrong, why each test was run, which ideas failed, and how to reproduce
or undo the result safely.

## 1. Initial problem

The stock 80 mm chassis fan of a QNAP TS-230 was replaced with an **ARCTIC P8
Slim PWM PST 80 mm**, rated up to 3000 RPM. The old fan's exact label and rated
RPM were not recorded. What matters is that the replacement has a different
operating range while QTS continues to use the model profile designed for the
stock configuration.

QTS was set to fixed 100% and `/etc/config/uLinux.conf` agreed:

```ini
FAN action = Fixed
FAN speed = 100
```

Nevertheless, the GUI reported only about 2200 RPM. The goal was to determine
whether this came from the fan, power, PWM frequency, QFan settings, a kernel
driver, or a QNAP-specific limit. A secondary goal was to retain native QTS fan
control rather than bypass it with a permanent raw PWM value.

## 2. Safety principles used during the investigation

1. Read before writing.
2. Change one variable at a time.
3. Prefer documented configuration and vendor HAL over raw registers.
4. Keep a rollback path before every persistent modification.
5. Treat GUI labels, policy values, physical duty cycle, and RPM as distinct.
6. Do not assume an interface is active merely because it exists in sysfs.

This is why no direct write was made to Realtek PWM sysfs or memory-mapped SoC
registers.

## 3. Baseline data

The system reported:

```text
Linux msk-nas03 4.2.8 ... aarch64 GNU/Linux
```

QFan configuration:

```ini
[GLOBAL]
qfan_enable = TRUE
stop_pwm = 0
low_pwm = 60
mid_pwm = 150
high_pwm = 255

[SMART MODE]
formula = 2
low_sys_temp = 40
high_sys_temp = 54
high_cpu_temp = 75
high_hdd_temp = 55
```

This ruled out the obvious theory that `qfan.conf` had a low high-speed value:
`high_pwm` was already 255.

Useful read-only baseline commands:

```sh
uname -a
uname -m
getcfg System Model -f /etc/config/uLinux.conf
grep -iE 'fan|pwm' /etc/config/uLinux.conf
cat /etc/config/qfan.conf
readlink -f /etc/model.conf
grep -n -A6 '^\[System FAN\]' /etc/model.conf
```

## 4. Why normal Linux fan controls were not useful

`/sys/class/hwmon/hwmon0/name` was `rtk_thermal`. There were no `fan*_input`
or `pwm*` controls. This meant the normal Linux hwmon recipe was not applicable.

The Device Tree contained:

```text
/sys/firmware/devicetree/base/rtk_fan@9801BC00
compatible = Realtek,rtd129x-fan
status = disabled
```

Its binary `pwms` property was:

```text
00 00 00 4c 00 00 00 01 00 00 93 f6
```

Decoded as three big-endian cells:

```text
phandle: 0x4c
channel: 1
period:  0x93f6 = 37878 ns ≈ 26.4 kHz
```

The frequency is reasonable for a four-wire PWM fan, so an incompatible PWM
frequency became less likely. More importantly, the fan node was disabled.

The Realtek controller exposed both:

```text
/sys/devices/platform/980070d0.pwm
/sys/class/pwm/pwmchip0
```

Observed channels:

| Channel | enable | duty | output frequency | clock divisors |
| --- | ---: | ---: | ---: | --- |
| PWM0 | 1 | 50% | 12 Hz | 255 / 12 |
| PWM1 | 0 | 100% | 26367 Hz | 255 / 1 |
| PWM2 | 0 | 100% | 26367 Hz | 255 / 1 |
| PWM3 | 1 | 50% | 12 Hz | 255 / 12 |

These values did not change when QTS was switched from 100% to 50%. Therefore
this visible sysfs controller was not the active system-fan control path. Direct
writes there would have been unjustified and potentially dangerous because the
channels could serve unrelated hardware.

## 5. QNAP HAL investigation

Although `hal_app --help` did not advertise useful fan commands, strings in the
binary included hidden `se_sys_get/set_fan` and PWM operations.

Enumeration showed the main enclosure:

```text
enc_id=0 enc_sys_id=root model=TS-230 fan_no=1
```

The likely read calls were tested:

```sh
hal_app --se_sys_get_fan enc_sys_id=root,obj_index=0
hal_app --se_sys_get_fan_pwm enc_sys_id=root,obj_index=0
```

Both returned `ret=-2` and zero RPM/PWM. Those zeroes were not real sensor
values: this enclosure API was not implemented or not appropriate for this
platform.

Further inspection of `/lib/libuLinux_hal.so` found:

```text
HM_Set_Fan_Speed_By_PWM
i2c_sys_set_root_fan_pwm
se_sys_get_fan_pwm_min_max
/etc/model.conf
```

This established that QNAP's HAL had its own MCU/I²C path and read per-model
limits from `/etc/model.conf`.

## 6. Root cause

`/etc/model.conf` was a symlink to:

```text
/etc/model_Q04Z0_Q0500_10_10.conf
```

The decisive section was:

```ini
[System FAN]
FAN_UNIT = MCU
FAN_1 = I1:C0
MIN_PWM = 51
MAX_PWM = 178
HEAT_SOURCE = SYS, DISK
```

The final QNAP hardware path was therefore MCU-based, not the visible Realtek
PWM sysfs path. The profile capped the maximum command at 178 out of 255:

```text
178 / 255 = 69.8%
2200 / 3000 = 73.3%
```

The numbers were close enough to form a strong hypothesis. The controlled
change below confirmed it.

## 7. Manual proof and result

First preserve the profile:

```sh
sudo cp -p /etc/model_Q04Z0_Q0500_10_10.conf \
  /etc/model_Q04Z0_Q0500_10_10.conf.bak
```

Then replace only the exact expected line:

```sh
sudo sed -i 's/^MAX_PWM = 178$/MAX_PWM = 255/' \
  /etc/model_Q04Z0_Q0500_10_10.conf
```

Verify:

```sh
grep -n -A6 '^\[System FAN\]' /etc/model.conf
```

In QTS, set 50%, apply, wait about 10 seconds; then set 100%, apply, and wait
20–30 seconds. This caused QTS/HAL to read and apply the new limit. The GUI
reported **2970 RPM**, effectively the rated 3000 RPM maximum.

Lines such as `[System FAN]` or `MAX_PWM = 255` are configuration content, not
shell commands. Accidentally pasting them at a shell prompt only produced
`command not found`; it did not alter the NAS.

## 8. Manual rollback

If the backup exists:

```sh
sudo cp -p /etc/model_Q04Z0_Q0500_10_10.conf.bak \
  /etc/model_Q04Z0_Q0500_10_10.conf
```

Or restore the exact expected value:

```sh
sudo sed -i 's/^MAX_PWM = 255$/MAX_PWM = 178/' \
  /etc/model_Q04Z0_Q0500_10_10.conf
```

Reapply 50% then 100% in QTS and verify the section again. If the profile path
or current value differs, stop instead of adapting the command blindly.

## 9. Architecture after the investigation

```text
QTS GUI / Smart Fan policy
           |
           v
uLinux.conf and qfan.conf policy values
           |
           v
QNAP HAL reads /etc/model.conf
           |
           v
model clamp: MIN_PWM=51, MAX_PWM=178 (changed to 255)
           |
           v
I²C / MCU route identified as FAN_1=I1:C0
           |
           v
ARCTIC PWM input and tachometer -> RPM displayed by QTS
```

The fix changes only the clamp. It does not replace QTS policy or hold a fixed
duty cycle.

## 10. Why persistence needs a QPKG

QTS recreates `/etc` model data at boot. In a reboot test, both the modified
profile and a backup stored beside it disappeared and the original profile was
restored. Therefore `/etc/*.bak` is not a persistent backup location.

`QNAP-PWM` is a small QPKG service. At startup it:

1. waits until `/etc/model.conf` is available;
2. resolves and validates the exact expected profile;
3. verifies `FAN_UNIT = MCU`, `FAN_1 = I1:C0`, `MIN_PWM = 51`, and an allowed
   `MAX_PWM` value;
4. creates a persistent backup in its QPKG data area;
5. changes only an exact `MAX_PWM = 178` to `MAX_PWM = 255`;
6. uses a temporary native HAL force/clear cycle to make QTS reapply control;
7. clears the override so QTS remains in charge;
8. logs every decision.

Repeated execution is safe: 255 is treated as already applied. Unexpected
models, profiles, duplicated settings, or values cause a refusal rather than a
best-effort edit.

## 11. Installing and verifying the QPKG

Download `release/QNAP-PWM_1.0.0.qpkg`, verify its SHA-256 against
`release/SHA256SUMS`, and use QTS App Center → Install Manually. The package is
locally built and unsigned, so the signature warning is expected.

Check status and log:

```sh
sudo /sbin/qpkg_cli --status QNAP-PWM --output 2
sudo cat /mnt/HDA_ROOT/.config/qnap-pwm.log
grep -n -A6 '^\[System FAN\]' /etc/model.conf
```

Expected status is enabled, the profile contains 255, and the log contains a
successful patch message. Then test 50% → 100% in QTS and watch RPM and system,
disk, and CPU temperatures.

After a cold reboot, repeat all checks. This exact cold-boot verification of the
currently committed rebuilt package was not captured in the original session,
so it remains an explicit validation step rather than a claimed result.

After every QTS update, confirm the profile path and log before trusting the
patch. Firmware can replace or redesign the model profile.

## 12. Building the QPKG locally

The package was built with official QDK 2.3.11. On a machine with Docker:

```sh
./scripts/build-qpkg-docker.sh
```

The helper starts Ubuntu 22.04, installs build prerequisites, checks out QDK
`v2.3.11`, builds its tools, installs the QDK runtime in the container, and runs:

```sh
qbuild --strict --verbose
```

The output is written to `qpkg/build/`. The committed release file was also
structurally extracted and its packaged service/config compared with source.
It was not installed on a NAS from this current reconstruction session.

## 13. GitHub Actions build and release

The workflow in `.github/workflows/build-qpkg.yml` repeats the QDK build on an
Ubuntu runner. Pushes and pull requests produce a downloadable workflow
artifact. A tag matching `v*`, for example:

```sh
git tag -a v1.0.0 -m 'QNAP-PWM 1.0.0'
git push github v1.0.0
```

also creates a GitHub Release and attaches the `.qpkg`, `SHA256SUMS`, and
`MD5SUMS`. The version inside `qpkg/qpkg.cfg` should match the tag.

## 14. Troubleshooting map

### Script says the model or profile is unsupported

Do not bypass the check. Collect:

```sh
getcfg System Model -f /etc/config/uLinux.conf
readlink -f /etc/model.conf
grep -n -A6 '^\[System FAN\]' /etc/model.conf
```

Another profile can use a different controller, channel, scale, or safety limit.

### The edit succeeded but RPM did not change

Reapply 50% then 100% through QTS, wait, and verify the resolved profile rather
than only the symlink. Check the QPKG log for HAL force/clear errors.

### RPM is still around 2200 after reboot

Confirm that QPKG is enabled, inspect its log, and check whether QTS regenerated
a different profile. Do not write to the Realtek PWM nodes as a workaround.

### Fan becomes too loud

This patch makes 100% physical range available; it does not require using it.
Select Smart Fan or a lower manual percentage. Roll back to 178 if desired.

### QTS update changes the file

Disable the package until the new profile has been reviewed. An unexpected
value is intentionally treated as a safety failure.

### Manual QPKG registration fails with `Incomplete_Conf=1`

Hand-writing a registration entry was unreliable in the investigation. Use
App Center to install the proper QDK-built package so QTS performs registration.

## 15. Confirmed facts and remaining unknowns

Confirmed:

- QTS 100% produced about 2200 RPM before the change;
- `qfan.conf` already had `high_pwm = 255`;
- the normal hwmon fan interface was absent;
- Realtek sysfs values did not follow GUI changes;
- Device Tree marked `rtk_fan` disabled;
- QNAP HAL referenced `/etc/model.conf` and MCU/I²C fan functions;
- the model profile capped PWM at 178;
- changing only 178 to 255 produced 2970 RPM;
- HAL force followed by clear can reapply the policy and return control to QTS;
- a proper QDK-built QPKG was accepted through App Center in the investigation.

Still to verify on the physical NAS:

- the current committed release package across a full cold boot;
- behavior after future QTS updates;
- the exact model and rating of the removed stock fan.

## 16. Files in this repository

```text
README.md                    Russian entry point
README.en.md                 English entry point
docs/*.md                    full Russian documentation
docs/en/COMPLETE_GUIDE.md    complete English reconstruction
logs/session-evidence.txt    sanitized source observations
scripts/qnap-ts230-fan-cap.sh read-only-by-default helper
scripts/build-qpkg-docker.sh reproducible local builder
qpkg/                        QDK package source
release/                     ready package and checksums
```

## 17. Final safety warning

Fan control protects disks and the SoC. Use this only when the exact invariants
match, keep QTS monitoring active, verify RPM and temperatures immediately, and
retain a tested rollback route. This is an unofficial modification.
