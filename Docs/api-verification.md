# Сверка API по заголовкам SDK

**Проверено:** 12.08.2026 · macOS 26.5 (25F84) · Xcode 26.5 · SDK MacOSX 26.5 · arm64

Версии в ТЗ 1.1 были собраны из WWDC-сессий, форумов и выдачи — страницы документации Apple
отдаются через JavaScript и не читались автоматически. Здесь зафиксирован результат сверки по
`API_AVAILABLE` в заголовках установленного SDK. Заголовок — первоисточник, эта таблица имеет
приоритет над любыми утверждениями в ТЗ.

Закрывает issue #1.

## Подтверждённые версии

| Символ | В SDK | В ТЗ 1.1 | |
|---|---|---|---|
| `VZEFIBootLoader` | macOS 13.0 | 13 | совпадает |
| `VZEFIVariableStore` | macOS 13.0 | 13 | совпадает |
| `VZVirtioGraphicsDeviceConfiguration` | macOS 13.0 | 13 | совпадает |
| `VZLinuxRosettaDirectoryShare` | macOS 13.0 | 13 | совпадает |
| `VZSpiceAgentPortAttachment` | macOS 13.0 | 13 | совпадает |
| `saveMachineStateTo` / `restoreMachineStateFrom` | macOS 14.0, `__arm64__` | 14 | совпадает |
| `VZNVMExpressControllerDeviceConfiguration` | macOS 14.0 | — | не упоминалось |
| `VZXHCIControllerConfiguration`, `VZUSBDeviceConfiguration` | macOS 15.0 | 15 | совпадает |
| `VZVmnetNetworkDeviceAttachment` | macOS 26.0 | 26 | совпадает |
| `vmnet_network_configuration_add_port_forwarding_rule` | macOS 26.0 | 26 | совпадает |
| `VZMacOSRestoreImage` | macOS 12.0 | 12 | совпадает |
| `VZVirtioSoundDeviceConfiguration` | macOS 12.0 | 12 | совпадает |
| `VZUSBKeyboardConfiguration` | macOS 12.0 | 12 | совпадает |
| `VZUSBScreenCoordinatePointingDeviceConfiguration` | macOS 12.0 | 12 | совпадает |

## Расхождения

**`VZVirtioFileSystemDeviceConfiguration` — macOS 12.0, а не 13.0.** Общие папки через virtiofs
доступны на релиз раньше, чем считалось. На минимальную версию не влияет, но в ревью ТЗ было
названо неверно.

**ASIF не является символом Virtualization.framework.** В `VZDiskImageStorageDeviceAttachment.h`
нет ни одного упоминания формата: attachment просто открывает файл. ASIF — формат образа,
создаваемый средствами системы, а не API виртуализации. Практическая проверка:

```sh
diskutil image create blank --format ASIF --size 8G --fs none Disk.asif
```

Образ на 8 ГБ занимает **4 МБ** на диске. Ключ `--fs none` обязателен: по умолчанию внутрь
создаётся том APFS, что для диска Linux-гостя не нужно. Формат доступен в `diskutil` на macOS 26;
`DiskImageKit` со слоёными образами приходит только в macOS 27.

## Ответы на два вопроса, влиявших на объём этапа 2

### Работает ли сохранение состояния для macOS-гостей?

**Заголовки не различают типы гостей.** Ограничение сформулировано иначе: пригодность
конфигурации проверяется в рантайме через `validateSaveRestoreSupportWithError:` (macOS 14.0), и
документация прямо говорит «не все параметры конфигурации могут быть безопасно сохранены и
восстановлены». То есть вопрос не «Linux или macOS», а «какие устройства в конфигурации».

Отсюда следуют требования, которых в ТЗ не было:

- **Сохранять можно только приостановленную машину.** Не запущенную — сначала `pause`, потом
  `save`. Иначе `VZErrorInvalidVirtualMachineState`.
- **Только Apple Silicon** — API объявлен внутри `#if defined(__arm64__)`.
- **Файл состояния зашифрован ключом, привязанным к хосту.** Перенести снапшот на другой Mac
  невозможно в принципе. Это подтверждает `BND-04` (снапшот не входит в экспорт) — но теперь
  причина твёрдая, а не соображение удобства.
- **Обновление системы может сделать файл нечитаемым.** По документации восстановление может
  отказать после обновления хоста, и в этом случае машину следует запускать холодным стартом.
  Значит `LC-06` обязан деградировать до обычного запуска, а не показывать ошибку.
- Перед предложением сохранить состояние интерфейс должен спросить у конфигурации
  `validateSaveRestoreSupport`, иначе пользователю обещается функция, которая упадёт при вызове.

### Что именно даёт vmnet в macOS 26?

Богаче, чем предполагалось. На уровне конфигурации сети (все — macOS 26.0):

| Функция | Что даёт |
|---|---|
| `vmnet_network_configuration_add_port_forwarding_rule` | Проброс портов — `NET-02` |
| `vmnet_network_configuration_add_dhcp_reservation` | Фиксированный IP для гостя по MAC |
| `vmnet_network_configuration_set_ipv4_subnet` / `set_ipv6_prefix` | Своя подсеть |
| `vmnet_network_configuration_disable_nat44` / `disable_nat66` | Изолированная сеть — `NET-03` |
| `vmnet_network_configuration_disable_dhcp` / `disable_dns_proxy` | Тонкая настройка |
| `vmnet_network_configuration_set_external_interface` | Привязка к конкретному интерфейсу хоста |
| `vmnet_network_configuration_set_mtu` | MTU |
| `vmnet_network_copy_serialization` | Передача сети между процессами через XPC |

Порядок работы: сеть создаётся и настраивается через `vmnet.framework`, затем
`vmnet_network_ref` передаётся в `VZVmnetNetworkDeviceAttachment`. Правила проброса задаются
**до** создания сети, на объекте конфигурации — не на интерфейсе запущенной VM.

Отдельно: сеть может использовать только тот процесс, который её создал. Обмен сетями между
приложениями заблокирован намеренно.

## Entitlement для vmnet — проверено, риска нет

**Результат: `vmnet` довольствуется `com.apple.security.virtualization`.** Ограниченный
`com.apple.vm.networking`, которым закрыт bridged networking, не нужен. Проброс портов
(`NET-02`) и изолированные сети (`NET-03`) доступны без всякого согласования с Apple.

Проверено эмпирически — `Tools/vmnet-probe.c`, ad-hoc подпись, три прогона одного бинарника:

| Подпись | `vmnet_network_create` |
|---|---|
| Без подписи | `VMNET_MEM_FAILURE` |
| Подписан, entitlements нет | `VMNET_MEM_FAILURE` |
| Подписан, `com.apple.security.virtualization` | **`VMNET_SUCCESS`** |

Правило проброса портов (`vmnet_network_configuration_add_port_forwarding_rule`) принимается на
объекте конфигурации в любом случае — отказ приходит позже, при создании сети.

Отдельно стоит запомнить: при нехватке прав возвращается **`VMNET_MEM_FAILURE`**, а не
`VMNET_INVALID_ACCESS`. Код возврата говорит о нехватке памяти, хотя проблема в подписи —
разработчик, наткнувшийся на это, будет искать не там. Сообщение об ошибке в приложении должно
называть настоящую причину.

Порядок аргументов в правиле — `(protocol, family, internal_port, external_port, address)`, то
есть сначала порт гостя, потом порт хоста, и адрес гостя обязателен. Перепутать местами легко.

<details>
<summary>Исходная формулировка риска (до проверки)</summary>

Заголовок `VZVmnetNetworkDeviceAttachment.h` говорит прямо:

> The vmnet framework requires an entitlement to create or configure a network.

Какой именно — ни `VZVmnetNetworkDeviceAttachment.h`, ни `vmnet.h` не называют; в `vmnet.h` нет
ни одного упоминания entitlement, есть только код возврата `VMNET_INVALID_ACCESS` (permission
denied). Исторически vmnet в host/shared-режиме требовал либо root, либо
`com.apple.vm.networking` — того самого ограниченного разрешения, которым закрыт bridged
networking.

**Почему это важно.** В ревью ТЗ проброс портов был назван решением, доступным «без всяких
restricted entitlements», и половина обоснования минимальной версии macOS 26.0 держалась на
vmnet-топологиях. Если vmnet потребует `com.apple.vm.networking`, то:

- `NET-02` и `NET-03` уезжают за то же разрешение, что и bridged, и перестают быть
  дифференциатором;
- обоснование планки macOS 26.0 сокращается до одного ASIF — всё ещё достаточного (компактность
  образов — заявленная цель продукта), но одного;
- формулировка ограничения bridged в разделе 7 становится неточной: «вместо него — проброс
  портов» перестаёт быть честным ответом.

Заголовками это не решается. Нужен эмпирический тест: попытаться создать vmnet-сеть из
приложения, подписанного Developer ID и имеющего только `com.apple.security.virtualization`.
Вынесено в отдельную задачу, блокирует объём `NET-02` и `NET-03`.

`VZNATNetworkDeviceAttachment` (`NET-01`) этим риском не затронут — это отдельный путь, которым
VZ пользуется сам, и на нём MVP не завязан.

</details>
