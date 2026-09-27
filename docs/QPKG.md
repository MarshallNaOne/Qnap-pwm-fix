# QPKG: устройство, сборка, установка и обслуживание

## Как работает пакет

QTS генерирует `/etc/model.conf` при загрузке. Service script ждёт появления
файла, разрешает симлинк, проверяет ожидаемый профиль и секцию `[System FAN]`.
Он допускает только два значения:

* `178` — заменяет на `255`;
* `255` — считает патч уже применённым.

Любое другое значение приводит к отказу без изменений. Затем скрипт просит HAL
перечитать текущую политику вентилятора:

```sh
/sbin/hal_event --se_set_fan_force_speed fan_level=7
sleep 3
/sbin/hal_event --se_clear_fan_force_speed
```

Принудительный уровень временный; итоговый режим снова контролируется QTS.

## Сборка с нуля на NAS

Официальная страница QNAP рекомендует QDK 2.3.11 для QTS 4.4.1 и новее:

* <https://www.qnap.com/en/how-to/tutorial/article/qpkg-development-guidelines>
* <https://github.com/qnap-dev/QDK/releases/tag/v2.3.11>

Установите и включите QDK через App Center. Проверка:

```sh
getcfg QDK Install_Path -f /etc/config/qpkg.conf
ls -l /usr/bin/qbuild
qbuild --version
```

Скопируйте каталог `qpkg` из этого репозитория на NAS и выполните:

```sh
cd /share/CACHEDEV1_DATA
mkdir -p qpkg-build
cp -R /путь/к/qnap-pwm/qpkg qpkg-build/QNAP-PWM
cd qpkg-build/QNAP-PWM
chmod 755 shared/QNAP-PWM.sh
qbuild --strict --verbose
```

Generic build выбран намеренно: payload — только POSIX shell, поэтому пустые
архитектурные каталоги не нужны. Готовый файл появится в `build/`.

Альтернативная сборка в Linux-контейнере без установки QDK на NAS:

```sh
sh scripts/build-qpkg-docker.sh
```

Скрипт использует Ubuntu 22.04, получает QDK из официального репозитория
`qnap-dev/QDK` с фиксированным тегом `v2.3.11` и складывает результат в
`qpkg/build/`. Для установки всё равно используйте QTS App Center.

Проверка без установки:

```sh
rm -rf /tmp/qnap-pwm-extract
mkdir /tmp/qnap-pwm-extract
qbuild --extract build/QNAP-PWM_1.0.0.qpkg /tmp/qnap-pwm-extract
cat /tmp/qnap-pwm-extract/qpkg.cfg
tar -tzvf /tmp/qnap-pwm-extract/data.tar.gz
sh -n shared/QNAP-PWM.sh
md5sum build/QNAP-PWM_1.0.0.qpkg
```

## Установка

Предпочтительный путь для unsigned-пакета:

```text
App Center → Install Manually → QNAP-PWM_1.0.0.qpkg
```

Подтвердите предупреждение об отсутствии цифровой подписи только после сверки
SHA-256. На исследованной версии попытки `qpkg_cli -m` останавливались на
code-signing pre-check до install queue, поэтому CLI не является надёжным
способом первоначальной установки этого unsigned QPKG.

## Проверка после установки

```sh
sudo /sbin/qpkg_cli --status QNAP-PWM --output 2
sudo grep -n -A25 '^\[QNAP-PWM\]' /mnt/HDA_ROOT/.config/qpkg.conf
sudo ls -la /share/CACHEDEV1_DATA/.qpkg/QNAP-PWM
sudo cat /mnt/HDA_ROOT/.config/qnap-pwm.log
grep -n -A6 '^\[System FAN\]' /etc/model.conf
pidof hal_daemon
```

Проверка скорости: в QTS применить 50 %, подождать около 10 секунд, затем
применить 100 % и подождать 20–30 секунд. Ожидаемое наблюдение для указанного
ARCTIC — около 2970 RPM.

## Холодный старт

Для чистого теста можно предварительно сохранить старый лог и очистить текущий:

```sh
sudo cp -p /mnt/HDA_ROOT/.config/qnap-pwm.log \
  /mnt/HDA_ROOT/.config/qnap-pwm.log.before-reboot
sudo sh -c ': > /mnt/HDA_ROOT/.config/qnap-pwm.log'
sudo reboot
```

После загрузки, не меняя настройки вентилятора в GUI, выполните команды из
раздела проверки. Особенно ценна последовательность в логе:

```text
Current MAX_PWM=178
MAX_PWM changed: 178 -> 255
Triggering HAL fan configuration reload
PWM patch successfully applied
```

Она доказывает весь boot-механизм, а не только сохранение старой правки.

## Управление пакетом

```sh
sudo /sbin/qpkg_service start QNAP-PWM
sudo /sbin/qpkg_service stop QNAP-PWM
sudo /sbin/qpkg_service restart QNAP-PWM
sudo /sbin/qpkg_cli --status QNAP-PWM --output 2
```

`stop` намеренно ничего не откатывает: резкое уменьшение доступного диапазона
во время работы не требуется. После удаления пакета текущий системный файл
может остаться со значением 255 до reboot; при следующей генерации QTS вернёт
штатный профиль.

## Ручной откат без reboot

Если ранее создана исходная копия:

```sh
sudo cp -p /etc/model_Q04Z0_Q0500_10_10.conf.bak \
  /etc/model_Q04Z0_Q0500_10_10.conf
```

Либо используйте диагностический helper:

```sh
sudo sh scripts/qnap-ts230-fan-cap.sh --rollback
```

После отката примените 50 % → 100 % в QTS.

## После обновления QTS

Проверьте:

* цель `/etc/model.conf`;
* наличие `[System FAN]`, `FAN_UNIT = MCU` и ожидаемого исходного лимита;
* статус QPKG;
* свежий журнал;
* RPM и температуры.

Не расширяйте проверки скрипта под новое оборудование вслепую. Сначала
повторите read-only диагностику: модель, профиль, HAL и фактическую реакцию QTS.
