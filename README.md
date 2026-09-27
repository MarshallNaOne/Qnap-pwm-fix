<div align="center">

# QNAP PWM Fix

### Полный диапазон PWM для нового вентилятора QNAP TS-230 без отключения штатного управления QTS

[![Build QPKG](https://github.com/MarshallNaOne/Qnap-pwm-fix/actions/workflows/build-qpkg.yml/badge.svg)](https://github.com/MarshallNaOne/Qnap-pwm-fix/actions/workflows/build-qpkg.yml)
[![GitHub release](https://img.shields.io/github/v/release/MarshallNaOne/Qnap-pwm-fix?display_name=tag&sort=semver)](https://github.com/MarshallNaOne/Qnap-pwm-fix/releases/latest)
[![Release downloads](https://img.shields.io/github/downloads/MarshallNaOne/Qnap-pwm-fix/total)](https://github.com/MarshallNaOne/Qnap-pwm-fix/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![QNAP TS-230](https://img.shields.io/badge/QNAP-TS--230-008a9a)](https://www.qnap.com/)
[![Architecture](https://img.shields.io/badge/architecture-aarch64-informational)](#совместимость-и-риски)
[![QPKG](https://img.shields.io/badge/package-QPKG-orange)](docs/QPKG.md)

**[Скачать последнюю версию](https://github.com/MarshallNaOne/Qnap-pwm-fix/releases/latest)**
· **[Начать здесь](docs/START_HERE.md)**
· **[Ручной способ](docs/MANUAL_METHOD.md)**
· **[Сборка QPKG](docs/QPKG.md)**
· **[English](README.en.md)**

</div>

---

Репозиторий фиксирует полное расследование ограничения системного вентилятора
QNAP TS-230 и воспроизводимое решение в виде QPKG `QNAP-PWM`.

## Зачем это понадобилось

Штатный 80-мм вентилятор QNAP заменили на **ARCTIC P8 Slim PWM PST 80 mm** с
максимальной скоростью до 3000 RPM. Точная маркировка снятого штатного
вентилятора в исходной сессии не была записана, поэтому здесь она не
угадывается. Важно то, что QTS продолжил использовать пределы модельного
профиля, рассчитанные на штатную конфигурацию, хотя рабочий диапазон нового
вентилятора отличается.

После замены штатного вентилятора на **ARCTIC P8 Slim PWM PST 80 mm** (до
3000 RPM) QTS показывал около **2200 RPM** при выбранных 100 %. Причиной
оказался лимит модели `MAX_PWM = 178` для MCU, то есть `178 / 255 = 69.8 %`.
После изменения лимита на 255 и повторного применения режима QTS вентилятор
достиг **2970 RPM**, при этом штатное температурное управление QTS сохранилось.

## Содержимое

* [`docs/START_HERE.md`](docs/START_HERE.md) — первое чтение: что произошло,
  что выбрать и как безопасно повторить результат без знаний устройства QTS.
* [`docs/PROBLEM.md`](docs/PROBLEM.md) — исходная проблема, практический смысл
  исправления и объяснение, почему замена вентилятора обнаружила скрытый предел.
* [`docs/INVESTIGATION.md`](docs/INVESTIGATION.md) — полная хронология,
  наблюдения, команды, выводы и отвергнутые гипотезы.
* [`docs/TIMELINE.md`](docs/TIMELINE.md) — последовательность экспериментов,
  ошибок и решений с объяснением, зачем выполнялся каждый шаг.
* [`docs/MANUAL_METHOD.md`](docs/MANUAL_METHOD.md) — полностью ручной способ
  диагностики, применения и отката без установки QPKG.
* [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — как связаны GUI QTS,
  QFan, HAL, профиль модели, MCU, PWM и обороты.
* [`docs/QPKG.md`](docs/QPKG.md) — как устроен пакет, как собрать, установить,
  проверить, удалить и диагностировать его с нуля.
* [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — симптомы, причины,
  команды проверки и восстановление после типичных ошибок.
* [`logs/session-evidence.txt`](logs/session-evidence.txt) — сохранённые
  технические выводы из исходной SSH-сессии без секретов.
* [`qpkg/`](qpkg/) — исходники QPKG для QDK 2.3.11.
* [`release/`](release/) — готовый установочный QPKG и контрольные суммы.
* [`scripts/qnap-ts230-fan-cap.sh`](scripts/qnap-ts230-fan-cap.sh) — отдельный
  ручной диагностический инструмент; без флага ничего не изменяет.

## Быстрая установка

Скачайте `release/QNAP-PWM_1.0.0.qpkg`, затем в QTS откройте:

```text
App Center → Install Manually / Установить вручную
```

QTS предупредит, что пакет не имеет цифровой подписи. Это ожидаемо для локально
собранного QPKG. Перед подтверждением сверяйте SHA-256 с файлом в `release/`.

После установки:

```sh
sudo /sbin/qpkg_cli --status QNAP-PWM --output 2
sudo cat /mnt/HDA_ROOT/.config/qnap-pwm.log
grep -n -A6 '^\[System FAN\]' /etc/model.conf
```

Ожидается `enabled: true`, `MAX_PWM = 255` и запись `PWM patch successfully
applied`. Полный тест после reboot и поведение после обновления QTS описаны в
[`docs/QPKG.md`](docs/QPKG.md).

## Совместимость и риски

Решение проверялось только на конкретной конфигурации:

| Параметр | Значение |
| --- | --- |
| NAS | QNAP TS-230; внутреннее имя QTS `TS-XA28A` |
| Ядро/архитектура | Linux 4.2.8, `aarch64` |
| Профиль модели | `/etc/model_Q04Z0_Q0500_10_10.conf` |
| Управление вентилятором | `FAN_UNIT = MCU`, `FAN_1 = I1:C0` |
| QTS при сборке | ветка 5.2.x; пакет объявляет 5.2.0–5.9.9 |

Скрипт отказывается менять неожиданный профиль, не пишет в sysfs PWM и не
трогает регистры SoC. Тем не менее это неофициальная модификация системного
конфига. После обновлений QTS проверяйте журнал, температуры и обороты.

## Главный технический вывод

Активный путь управления на TS-230:

```text
QTS fan policy → uLinux HAL → I²C/MCU → FAN_1=I1:C0
                              ↑
             /etc/model.conf: MAX_PWM 178 → 255
```

Realtek PWM sysfs и disabled-узел `rtk_fan` в Device Tree не были активным
путём системного вентилятора. Прямые записи туда не нужны и потенциально
опасны.

Если вы открыли проект впервые, начинайте не с исходников, а с
[`docs/START_HERE.md`](docs/START_HERE.md).
