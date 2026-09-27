# Полный журнал расследования

## 1. Исходная проблема

На QNAP TS-230 штатный вентилятор был заменён на **ARCTIC P8 Slim PWM PST,
80 mm, до 3000 RPM**. При ручной установке 100 % в QTS интерфейс показывал
примерно 2200 RPM. Целью было найти реальный ограничитель, не отключая
терморегулирование, аварийный контроль и интерфейс QTS.

Исходное окружение:

```text
QTS / Linux 4.2.8
architecture: aarch64
QTS model identifier: TS-XA28A
host: msk-nas03
```

## 2. Проверка пользовательской политики QFan

В `/etc/config/qfan.conf` обнаружено:

```ini
qfan_enable=TRUE
stop_pwm=0
low_pwm=60
mid_pwm=150
high_pwm=255

[SMART MODE]
formula=2
low_sys_temp=40
high_sys_temp=54
high_cpu_temp=75
high_hdd_temp=55
```

`high_pwm=255` означал, что пользовательская политика уже разрешает полный
8-битный диапазон. В `/etc/config/uLinux.conf` одновременно наблюдалось:

```ini
FAN action=Fixed
FAN speed=100
```

Следовательно, проблема находилась ниже GUI/qfan policy.

## 3. hwmon и Device Tree

`hwmon0` оказался `rtk_thermal`. Стандартных Linux hwmon-файлов `fan*` и
`pwm*` для системного вентилятора не было.

В Device Tree найден узел:

```text
/sys/firmware/devicetree/base/rtk_fan@9801BC00
compatible: Realtek,rtd129x-fan
status: disabled
```

Свойство `pwms`:

```text
00 00 00 4c 00 00 00 01 00 00 93 f6
```

Декодирование трёх big-endian ячеек:

* phandle: `0x4c`;
* канал: `1`;
* период: `0x93f6 = 37878 ns`, около 26.4 kHz.

Наличие узла ещё не означает, что драйвер активен: `status=disabled` оказался
важным признаком.

## 4. Проверка Realtek PWM sysfs

Найдены:

```text
/sys/devices/platform/980070d0.pwm
/sys/class/pwm/pwmchip0
```

Интерфейс содержит `enable0..3`, `dutyRate0..3`, `out_freq0..3`,
`clkoutDiv0..3`, `clksrcDiv0..3`. Снимок состояния:

| Канал | enable | dutyRate | out_freq | clkoutDiv | clksrcDiv |
| --- | ---: | ---: | ---: | ---: | ---: |
| PWM0 | 1 | 50 % | 12 Hz | 255 | 12 |
| PWM1 | 0 | 100 % | 26367 Hz | 255 | 1 |
| PWM2 | 0 | 100 % | 26367 Hz | 255 | 1 |
| PWM3 | 1 | 50 % | 12 Hz | 255 | 12 |

При переключении QTS 100 % → 50 % значения не менялись. Поэтому этот sysfs
не является подтверждённым активным путём системного вентилятора. Записи в
эти файлы намеренно не выполнялись: каналы могут обслуживать другую периферию.

## 5. Исследование HAL

В строках `hal_app` найдены скрытые команды семейства `se_sys_get/set_fan` и
`se_sys_get/set_fan_pwm`. Перечисление enclosure:

```text
enc_id=0
enc_sys_id=root
fan_no=1
```

Попытки чтения:

```sh
hal_app --se_sys_get_fan enc_sys_id=root,obj_index=0
hal_app --se_sys_get_fan_pwm enc_sys_id=root,obj_index=0
```

вернули `ret=-2` и нулевые RPM/PWM. Значит этот enclosure API на TS-230 не
реализован или требует иной внутренний объект.

В `/lib/libuLinux_hal.so` найдены строки/символы:

```text
HM_Set_Fan_Speed_By_PWM
i2c_sys_set_root_fan_pwm
se_sys_get_fan_pwm_min_max
/etc/model.conf
```

Это связало управление вентилятором с HAL, I²C/MCU и профилем модели.

## 6. Найден реальный ограничитель

`/etc/model.conf` оказался симлинком:

```text
/etc/model.conf -> /etc/model_Q04Z0_Q0500_10_10.conf
```

Секция профиля:

```ini
[System FAN]
FAN_UNIT = MCU
FAN_1 = I1:C0
MIN_PWM = 51
MAX_PWM = 178
HEAT_SOURCE = SYS, DISK
```

Числа согласуются с симптомом:

```text
178 / 255 = 69.8 %
2200 / 3000 ≈ 73.3 %
```

То есть GUI 100 % означал 100 % разрешённого профилем диапазона, верхняя
граница которого была около 70 % физического PWM.

## 7. Контрольный эксперимент

Создана резервная копия и заменена одна точная строка:

```sh
sudo cp -p /etc/model_Q04Z0_Q0500_10_10.conf \
  /etc/model_Q04Z0_Q0500_10_10.conf.bak
sudo sed -i 's/^MAX_PWM = 178$/MAX_PWM = 255/' \
  /etc/model_Q04Z0_Q0500_10_10.conf
```

Проверка:

```sh
grep -n -A5 '^\[System FAN\]' /etc/model.conf
```

После переключения в QTS 50 % → 100 % и ожидания 20–30 секунд GUI показал
**2970 RPM**. Гипотеза была подтверждена без прямого доступа к PWM-регистрам.

## 8. Первая попытка persistence: ручная регистрация

Рабочий service script был положен в:

```text
/share/CACHEDEV1_DATA/.qpkg/QNAP-PWM/QNAP-PWM.sh
```

а в `/mnt/HDA_ROOT/.config/qpkg.conf` вручную появилась секция `QNAP-PWM`.
Ручной вызов работал:

```sh
sudo /sbin/qpkg_service start QNAP-PWM
```

После reboot выяснилось, что это не полноценный установленный QPKG:

```ini
[QNAP-PWM]
Name = QNAP-PWM
Display_Name = QNAP PWM Unlock
Version = 1.0.0
Author = adminit
Shell = /share/CACHEDEV1_DATA/.qpkg/QNAP-PWM/QNAP-PWM.sh
Install_Path = /share/CACHEDEV1_DATA/.qpkg/QNAP-PWM
RC_Number = 150
Enable = FALSE
Status = complete
Incomplete_Conf = 1
```

Статус:

```json
{"name":"QNAP-PWM","status_code":700,"status_value":"disabled","enabled":"false"}
```

`qpkgd` писал `Can not found qpkg QNAP-PWM`. При этом ручной
`qpkg_service start` снова менял 178 → 255, доказывая, что payload исправен,
а проблема только в регистрации/автозапуске.

## 9. Сборка настоящего QPKG

Установлен официальный QDK 2.3.11. Он создал:

```text
/usr/bin/qbuild -> /share/CACHEDEV1_DATA/.qpkg/QDK/bin/qbuild
```

Рабочее окружение создавалось не внутри каталога QDK, где обычному
пользователю не хватало прав, а на data volume:

```sh
cd /share/CACHEDEV1_DATA
sudo mkdir -p qpkg-build
sudo chown adminit:administrators qpkg-build
cd qpkg-build
qbuild --create-env QNAP-PWM
cd QNAP-PWM
```

`uname -m` вернул `aarch64`; QDK называет архитектурный target `arm_64`.
Но пакет содержит только POSIX shell и был собран generic: пустые
архитектурные каталоги удалили, payload оставили в `shared/`.

```sh
rm -rf arm-x19 arm-x31 arm-x41 arm_64 x86 x86_64 x86_ce53xx
qbuild --strict --verbose
```

Результат исходной сборки:

```text
build/QNAP-PWM_1.0.0.qpkg       25K
build/QNAP-PWM_1.0.0.qpkg.md5    60 bytes
Adding QPKG checksum: 1090392554
```

`qbuild --query info/dump` у этой версии дал пустые метаданные, однако
`qbuild --extract` подтвердил корректную структуру:

```text
data.tar.gz
qpkg.cfg
package_routines
qinstall.sh
built_info
```

В `data.tar.gz` находился исполняемый `QNAP-PWM.sh`, а `qinstall.sh` был
стандартным установщиком QDK 2.3.11 и читал `. qpkg.cfg`.

## 10. Установка и code signing

Старую ручную секцию удалили только после backup `qpkg.conf`. Первая попытка:

```sh
sudo /sbin/qpkg_cli -m \
  /share/CACHEDEV1_DATA/qpkg-build/QNAP-PWM/build/QNAP-PWM_1.0.0.qpkg
```

распознала internal name, но пакет не установила. Debug `/var/log/log.qpkg`
показал точную причину:

```text
qpkgd_code_signing_check ... QNAP-PWM_1.0.0.qpkg -2:-2
```

Пакет даже не попадал в install queue. Опция CLI `-A/--ignore_cert` требовала
аргумент, но варианты `-A 1` и `-A xyz` не обходили предварительную проверку.
Внутри `qpkgd` также найдены `QDevelop`, `developer_mode_license` и
`Ignore_Cert`; лицензируемый developer mode не стали обходить.

Рабочим штатным способом оказался:

```text
App Center → Install Manually
```

GUI показал предупреждение об отсутствии цифровой подписи и позволил явно
подтвердить установку локального пакета.

## 11. Подтверждённый результат QPKG

После установки через App Center:

```json
{"name":"QNAP-PWM","status_code":600,"status_value":"enabled",
 "op_code":1,"st_code":0,"enabled":"true"}
```

Регистрация:

```ini
[QNAP-PWM]
Status = complete
Name = QNAP-PWM
Build = 20260927
Display_Name = QNAP PWM Unlock
Version = 1.0.0
Author = adminit
QPKG_File = QNAP-PWM.qpkg
Date = 2026-09-27
Shell = /share/CACHEDEV1_DATA/.qpkg/QNAP-PWM/QNAP-PWM.sh
Volume_Select = 1
Install_Path = /share/CACHEDEV1_DATA/.qpkg/QNAP-PWM
RC_Number = 150
FW_Ver_Min = 5.2.0
FW_Ver_Max = 5.9.9
Enable = TRUE
Opt_Xml = 0
```

`Incomplete_Conf = 1` отсутствовал. Каталог содержал service script,
`.list` и `.uninstall.sh`. QTS сам запустил сервис при установке.

Фактический журнал:

```text
2026-09-27 21:11:45 [QNAP-PWM] Starting PWM patch
2026-09-27 21:11:45 [QNAP-PWM] Model config: /etc/model_Q04Z0_Q0500_10_10.conf
2026-09-27 21:11:45 [QNAP-PWM] Current MAX_PWM=255
2026-09-27 21:11:45 [QNAP-PWM] MAX_PWM already set to 255
2026-09-27 21:11:45 [QNAP-PWM] Triggering HAL fan configuration reload
2026-09-27 21:11:48 [QNAP-PWM] PWM patch successfully applied
```

## 12. Что ещё требуется проверить

На момент фиксации истории отсутствовал подтверждённый лог первого холодного
старта после установки настоящего QPKG. Идеальный reboot-тест должен показать:

1. QTS восстановил модельный конфиг с `MAX_PWM=178`.
2. QPKG автоматически стартовал.
3. В логе появились `Current MAX_PWM=178` и `changed: 178 -> 255`.
4. `/etc/model.conf` содержит 255.
5. При штатных 100 % QTS показывает около 2970 RPM.

Это важно отличать от уже подтверждённого запуска при установке и ручного
`qpkg_service start`.
