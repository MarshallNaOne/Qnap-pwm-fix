# Полностью ручной способ

Этот раздел объясняет, как повторить исследование без готового QPKG. Он нужен
для диагностики новой системы, аварийного восстановления и проверки гипотезы.

## 1. Подключение

Включите SSH в QTS и подключитесь пользователем с правом `sudo`:

```sh
ssh admin@IP_АДРЕС_NAS
```

Команды чтения обычно не требуют root. Изменения системных файлов требуют
`sudo`.

## 2. Зафиксируйте исходное состояние

```sh
date
uname -a
uname -m
hostname
getcfg System Model -f /etc/config/uLinux.conf
getcfg System Version -f /etc/config/uLinux.conf
getcfg System "Build Number" -f /etc/config/uLinux.conf
```

Сохраните результат. Название на корпусе и внутреннее имя QTS могут
различаться: исследованный TS-230 сообщал `TS-XA28A`.

## 3. Найдите активный профиль модели

```sh
ls -l /etc/model.conf
readlink /etc/model.conf
readlink -f /etc/model.conf
```

В исследовании:

```text
/etc/model.conf -> /etc/model_Q04Z0_Q0500_10_10.conf
```

Всегда изменяйте только фактическую цель активного симлинка, предварительно
проверив её. Не копируйте имя профиля на другую модель.

## 4. Прочитайте секцию системного вентилятора

```sh
grep -n -A8 '^\[System FAN\]' /etc/model.conf
```

Ожидаемый блок:

```ini
[System FAN]
FAN_UNIT = MCU
FAN_1 = I1:C0
MIN_PWM = 51
MAX_PWM = 178
HEAT_SOURCE = SYS, DISK
```

Зачем проверять каждое поле:

* `FAN_UNIT=MCU` подтверждает ожидаемый backend;
* `FAN_1=I1:C0` подтверждает аппаратное назначение;
* `MAX_PWM=178` подтверждает найденный ограничитель;
* `HEAT_SOURCE` показывает, что QTS продолжает учитывать систему и диски.

## 5. Проверьте политику QFan

```sh
cat /etc/config/qfan.conf
grep -n -A20 -B5 -E 'qfan_enable|stop_pwm|low_pwm|mid_pwm|high_pwm|SMART' \
  /etc/config/qfan.conf
```

В исследовании `high_pwm=255`. Если у вас `high_pwm` меньше, существует ещё
один верхний предел, и изменение только model.conf может не дать тот же эффект.

## 6. Создайте резервную копию

Для текущей сессии:

```sh
real_conf=$(readlink -f /etc/model.conf)
sudo cp -p "$real_conf" "$real_conf.bak"
ls -l "$real_conf" "$real_conf.bak"
```

Учтите: `/etc` может пересоздаваться при загрузке. Для долгосрочного хранения
скопируйте backup на data volume:

```sh
sudo mkdir -p /share/CACHEDEV1_DATA/qnap-pwm-backup
sudo cp -p "$real_conf" /share/CACHEDEV1_DATA/qnap-pwm-backup/
```

## 7. Измените только ожидаемую строку

На подтверждённом профиле:

```sh
sudo sed -i 's/^MAX_PWM = 178$/MAX_PWM = 255/' "$real_conf"
```

Почему используется точная замена:

* не затрагиваются другие секции;
* повторный запуск не меняет 255;
* неожиданное исходное значение не подменяется молча.

Проверка:

```sh
grep -n -A8 '^\[System FAN\]' /etc/model.conf
```

Если осталось 178, команда ничего не нашла. Не используйте более широкий
`sed`, пока не выясните различие формата.

## 8. Примените изменение через GUI

Первый подтверждённый способ:

1. В QTS выбрать 50 %.
2. Нажать Apply.
3. Подождать примерно 10 секунд.
4. Выбрать 100 %.
5. Нажать Apply.
6. Подождать 20–30 секунд.
7. Записать RPM и температуры.

В исследовании скорость изменилась с ~2200 до 2970 RPM.

## 9. Примените изменение без GUI

Штатный HAL-триггер:

```sh
sudo /sbin/hal_event --se_set_fan_force_speed fan_level=7
sleep 3
sudo /sbin/hal_event --se_clear_fan_force_speed
```

Что происходит:

1. QTS временно переводит вентилятор во внутренний forced level 7.
2. Обороты могут измениться или колебаться.
3. Через три секунды override снимается.
4. HAL возвращается в ранее выбранный режим QTS.
5. При возврате HAL перечитывает новый `MAX_PWM`.

В исходном тесте уровни 7, 8 и 10 давали около 2800 RPM, а после `clear`
режим Fixed 100 % дал 2970 RPM. Это доказало, что `fan_level` — внутренний
уровень, а не процент и не непосредственный PWM.

Если первая команда прошла, а вторая нет, немедленно повторите clear:

```sh
sudo /sbin/hal_event --se_clear_fan_force_speed
```

## 10. Контрольный A/B-тест

Этот тест окончательно связывает результат с `MAX_PWM`.

Вернуть 178:

```sh
sudo sed -i 's/^MAX_PWM = 255$/MAX_PWM = 178/' "$real_conf"
sudo /sbin/hal_event --se_set_fan_force_speed fan_level=7
sleep 3
sudo /sbin/hal_event --se_clear_fan_force_speed
```

Ожидается возврат примерно к 2100–2200 RPM.

Снова применить 255:

```sh
sudo sed -i 's/^MAX_PWM = 178$/MAX_PWM = 255/' "$real_conf"
sudo /sbin/hal_event --se_set_fan_force_speed fan_level=7
sleep 3
sudo /sbin/hal_event --se_clear_fan_force_speed
```

Ожидается возврат примерно к 2970 RPM.

## 11. Откат

Из backup рядом с профилем:

```sh
sudo cp -p "$real_conf.bak" "$real_conf"
```

Или точной обратной заменой:

```sh
sudo sed -i 's/^MAX_PWM = 255$/MAX_PWM = 178/' "$real_conf"
```

Затем выполните GUI-переключение или HAL force/clear.

## 12. Автоматизированный helper

Диагностика:

```sh
sh scripts/qnap-ts230-fan-cap.sh
```

Применение:

```sh
sudo sh scripts/qnap-ts230-fan-cap.sh --apply-255
```

Откат:

```sh
sudo sh scripts/qnap-ts230-fan-cap.sh --rollback
```

Helper намеренно не выполняет HAL force/clear автоматически: пользователь
может сначала проверить файл и выбрать применение через GUI. Постоянный QPKG,
напротив, делает HAL reload, потому что предназначен для запуска без оператора.

## 13. Что записывать в журнал исследования

Для воспроизводимости сохраните:

* модель с корпуса и внутреннее имя QTS;
* полную версию QTS и ядра;
* цель `/etc/model.conf`;
* секцию `[System FAN]` до и после;
* relevant-поля `qfan.conf`;
* режим QTS;
* RPM и температуры до изменения;
* RPM и температуры после изменения;
* точное время каждого шага;
* результат после reboot.
