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

## Из чего состоит исходный проект

```text
qpkg/
├── qpkg.cfg
├── package_routines
├── build.sh
└── shared/
    └── QNAP-PWM.sh
```

### `qpkg.cfg`

Это описание пакета для QDK:

```sh
QPKG_NAME="QNAP-PWM"
QPKG_DISPLAY_NAME="QNAP PWM Unlock"
QPKG_VER="1.0.0"
QPKG_AUTHOR="adminit"
QPKG_LICENSE="MIT"
QPKG_SUMMARY="Unlock full system fan PWM range while retaining native QTS fan control."
```

`QPKG_NAME` — внутреннее стабильное имя. Оно используется в `qpkg.conf`,
`qpkg_cli` и пути установки. `QPKG_DISPLAY_NAME` — подпись в App Center.

```sh
QPKG_RC_NUM="150"
QPKG_SERVICE_PROGRAM="QNAP-PWM.sh"
```

`QPKG_SERVICE_PROGRAM` сообщает QTS, какой файл вызывать с аргументами
`start`, `stop` и `restart`. `RC_NUM` задаёт относительный порядок запуска
среди QPKG; это не RPM и не PWM.

```sh
QTS_MINI_VERSION="5.2.0"
QTS_MAX_VERSION="5.9.9"
QPKG_VOLUME_SELECT="1"
QDK_DATA_DIR_SHARED="shared"
```

Диапазон версии не доказывает совместимость со всеми выпусками — он только
ограничивает установщик. `VOLUME_SELECT=1` разрешает выбор data volume.
`QDK_DATA_DIR_SHARED` указывает на архитектурно-независимый payload.

### `package_routines`

QDK позволяет определить дополнительные install/remove hooks. Проект их не
использует: установка файлов, регистрация и удаление выполняются стандартным
`qinstall.sh`, который генерирует QDK. Чем меньше пользовательской логики в
установщике системного пакета, тем проще его проверить и безопасно удалить.

### `shared/QNAP-PWM.sh`

Это единственный runtime payload. Он написан на POSIX shell, поэтому не требует
компиляции под ARM и не несёт сторонних библиотек.

Ключевые защитные проверки:

```text
/etc/model.conf существует
        ↓
симлинк указывает на ожидаемый профиль
        ↓
есть [System FAN]
        ↓
FAN_UNIT=MCU и FAN_1=I1:C0
        ↓
MAX_PWM равен 178 или 255
        ↓
только после этого разрешено изменение
```

### `build.sh`

Небольшая оболочка над QDK:

```sh
chmod 755 shared/QNAP-PWM.sh
qbuild --strict --verbose
```

`--strict` превращает предупреждения QDK в ошибки. `--verbose` сохраняет
понятный журнал стадий сборки.

## Что QDK создаёт внутри `.qpkg`

QPKG — самораспаковывающийся shell-файл с бинарными архивами и служебным
хвостом. После `qbuild --extract` видны:

```text
qinstall.sh
qpkg.cfg
package_routines
built_info
data.tar.gz
```

* `qinstall.sh` — стандартная логика QDK: выбор volume, проверка версии,
  распаковка, регистрация в QTS, создание `.list` и `.uninstall.sh`.
* `qpkg.cfg` — снимок метаданных сборки.
* `package_routines` — пользовательские hooks, в нашем случае пустые.
* `built_info` — информация о времени/номере сборки.
* `data.tar.gz` — payload с `QNAP-PWM.sh`.

При установке QTS размещает payload примерно так:

```text
/share/CACHEDEV1_DATA/.qpkg/QNAP-PWM/
├── .list
├── .uninstall.sh
└── QNAP-PWM.sh
```

и создаёт секцию `[QNAP-PWM]` в persistent `qpkg.conf`. Именно эта штатная
цепочка отсутствовала у первой ручной регистрации, поэтому QTS позже пометил
её `Incomplete_Conf=1`.

## Как был собран релиз в этом репозитории

Последовательность была такой:

1. Получен официальный исходный QDK с тегом `v2.3.11`.
2. Первая попытка нативной сборки на macOS выявила несовместимость BSD/GNU
   `sed` и `tar`, а также extended attributes macOS.
3. Эти результаты были отброшены и не помещены в release.
4. Запущен чистый контейнер Ubuntu 22.04.
5. В контейнере установлены build tools, `rsync` и `bsdmainutils`.
6. Из исходников QDK собран его `qpkg_encrypt`.
7. `qbuild --strict --verbose` создал generic QPKG.
8. Новый QPKG снова открыт через `qbuild --extract` в Linux.
9. Извлечённые `qpkg.cfg` и `QNAP-PWM.sh` сравнены с Git-исходниками через
   `cmp` — различий нет.
10. Проверен shell-синтаксис.
11. Вычислены SHA-256 и MD5, затем артефакт скопирован в `release/`.

Сборка содержит дату/метаданные QDK, поэтому повторная сборка в другой момент
не обязана быть бит-в-бит идентичной. Воспроизводимы исходники, процедура и
содержимое payload; опубликованный бинарник идентифицируется своим SHA-256.

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
