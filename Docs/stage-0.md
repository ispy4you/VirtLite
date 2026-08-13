# Этап 0 — запуск гостя локально

Что нужно, чтобы собрать проект и загрузить Linux-гостя на своей машине. Проверено 13.08.2026 на
macOS 26.5, Xcode 26.5, Apple Silicon.

## Подпись и entitlement

Запуск гостя требует `com.apple.security.virtualization`. Entitlement появляется **из подписи**,
а не из бандла — это уточнение важное, потому что определяет, что можно запускать, а что нет:

| Способ | Работает | Почему |
|---|---|---|
| `swift run` | нет | Запускает свежесобранный неподписанный бинарник, entitlement взять неоткуда |
| Подписанный исполняемый файл | **да** | `Scripts/build-boot.sh` — именно так работает headless-инструмент |
| Подписанный `.app` | **да** | `Scripts/build-app.sh` — бандл нужен, чтобы это было приложением, а не чтобы работал entitlement |

Подпись ad-hoc (`codesign --sign -`) достаточна локально. Apple Developer ID нужен для
распространения — нотаризация и Gatekeeper, это задача `OSS-02` и `OSS-03`, к локальной разработке
отношения не имеет.

Для debug-сборок добавляется `get-task-allow`, иначе отладчик не подключится: подпись бандла
затирает ту, что SwiftPM ставит на исполняемый файл, и вместе с ней теряется отладочный
entitlement.

## Загрузка Linux-гостя без интерфейса

```sh
Scripts/build-boot.sh

.build/arm64-apple-macosx/debug/virtlite-boot \
    --iso ~/Downloads/ubuntu-24.04.4-live-server-arm64.iso \
    --bundle ~/VMs/Ubuntu.virtlite \
    --cpus 4 --memory-gb 4 --disk-gb 32
```

Консоль гостя идёт в терминал. Установщик Ubuntu на serial-консоли стартует в basic mode —
это нормально, он сам предлагает переключиться в rich mode.

Без `--iso` машина грузится с собственного диска: так проверяется, что после установки система
поднимается сама, без образа (`INS-01`).

## Автоматическая установка

Установщик Ubuntu на serial-консоли просит подтверждение перед тем, как стирать диск, и
пропустить его можно только параметром `autoinstall` в командной строке ядра — а его при
EFI-загрузке немодифицированного `.iso` задать негде. Ответ приходится отправлять в консоль.

```sh
# cloud-init seed: том обязан называться CIDATA, иначе NoCloud его не найдёт
mkdir seed && touch seed/meta-data
cat > seed/user-data <<'EOF'
#cloud-config
autoinstall:
  version: 1
  interactive-sections: []
  identity:
    hostname: virtlite-test
    username: virtlite
    password: "<хеш из openssl passwd -6>"
  storage:
    layout:
      name: direct
  shutdown: poweroff
EOF
hdiutil makehybrid -o seed.iso -iso -joliet -default-volume-name CIDATA seed

# stdin через FIFO: подтверждение нужно отправить в тот момент, когда установщик его спросит,
# а не заранее — отправленное раньше просто теряется
mkfifo vm-stdin
sleep 3600 > vm-stdin &
virtlite-boot --iso ubuntu.iso --seed seed.iso --bundle Test.virtlite < vm-stdin > install.log &

# когда в логе появится «Continue with autoinstall?»
printf 'yes\n' > vm-stdin
```

`shutdown: poweroff` в конце установки выключает гостя, и инструмент завершается сам.

## Что подтвердилось

Загрузка Ubuntu 24.04.4 Server arm64 с `.iso` до первого экрана установщика:

```
Ubuntu 24.04.4 LTS ubuntu-server hvc0

  As the installer is running on a serial console, it has started in basic
  mode, using only the ASCII character set and black and white colours.

  [ Continue in rich mode  > ]
  [ Continue in basic mode > ]
  [ View SSH instructions    ]
```

Полная установка Ubuntu 24.04.4 и загрузка установленной системы **без образа**:

```
Ubuntu 24.04.4 LTS virtlite-test hvc0
virtlite-test login:
```

Имя хоста `virtlite-test` из конфигурации автоустановки — значит загрузилась установленная
система, а не live-образ. Это критерий приёмки `INS-01`, и именно на нём чаще всего ломается
первая реализация: если образ не отсоединить, машина бесконечно грузит установщик.

Сеть проверена изнутри гостя:

```
inet 192.168.64.4/24 metric 100 brd 192.168.64.255 scope global dynamic enp0s1
HTTP:200 in 0.417085s
```

Адрес по DHCP, DNS резолвится, HTTPS до archive.ubuntu.com отвечает — `NET-01` работает без
какой-либо настройки в госте.

Диск после установки: **5.2 ГБ** при заявленных 24 ГБ — разреженность ASIF сохраняется и после
того, как гость записал систему.

Проверено по ходу:

- **EFI-загрузка с `.iso`** через `VZEFIBootLoader`, образ подключён как USB mass storage —
  именно там прошивка ищет загрузочный носитель.
- **NVRAM** создаётся при первом запуске и живёт в бандле (131 КБ). Без него установленная
  система потеряет загрузочные записи.
- **ASIF-диск** — 4 МБ на диске при заявленных 32 ГБ. Создаётся через `diskutil` с `--fs none`:
  по умолчанию внутрь кладётся том APFS, которому на диске Linux-гостя делать нечего.
- **Serial-консоль** через `VZVirtioConsoleDeviceSerialPortConfiguration` — читается, TUI
  установщика рисуется корректно.
- **Валидация конфигурации** проходит через пределы, полученные от фреймворка (`HW-01`).

## Чего этот этап не проверял

- Графика и ввод: headless-инструмент их отключает намеренно. Это задача этапа 1 (`HW-05`,
  `HW-06`).
- Проброс портов через vmnet: entitlement проверен (см. [api-verification.md](api-verification.md)),
  но сам проброс в работе не проверялся — это `NET-02`, этап 2.
- Пауза, снапшоты, общие папки — этап 2.
