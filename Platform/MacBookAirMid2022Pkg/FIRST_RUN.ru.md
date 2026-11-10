# Первый запуск Windows 11 ARM64 на MacBook Air 13" M2 (J413, T8112)

> **Эта цепочка ни разу не запускалась на железе. Ни нами, ни, насколько нам известно, кем-либо ещё.**
> Всё ниже получено чтением кода и сборкой. Каждый шаг помечен:
> - без пометки — команда или факт взяты из кода или документации репозиториев (ссылка `файл:строка`);
> - «**выведено из кода, не проверено**» — вывод из кода; на железе не выполнялся;
> - «**по документации Microsoft, здесь не проверено**» — синтаксис стандартной утилиты Windows; на этой цепочке не проверялся;
> - «**неизвестно**» — проверить нечем; указано, что ответило бы на вопрос.
>
> Цель первого запуска — не рабочая Windows, а логи: до какого этапа дошло и где встало.

Цепочка: iBoot → m1n1 (ставит установщик Asahi) → по USB со второго ПК: гипервизор `m1n1_windows` → гостевой
m1n1 (первая стадия) → прошивка Project Mu (`.fd`) → Windows Boot Manager → winload → ядро Windows с внешнего USB-диска.

Обозначения источников:

| Ключ | Что это |
|---|---|
| `M` | `/home/claude/ntasp/m1n1_windows`, ветка `vgic-state-machine`, коммит `1110872` |
| `U` | `/home/claude/ntasp/apple_silicon_platforms_mu`, ветка `m2-air-j413-scaffold`, коммит `ada1bf6` |
| `D` | `/home/claude/ntasp/apple_silicon_nt_drivers`, ветка `dchid-driver`, коммит `7ddd3be` |
| `R-boot` | `/tmp/claude-0/-home-claude/a0c2d3af-ccae-55e0-bf62-dfe45a26d2a9/scratchpad/research_bootpath.md` |
| `R-win` | `/tmp/claude-0/-home-claude/a0c2d3af-ccae-55e0-bf62-dfe45a26d2a9/scratchpad/research_windows_reqs.md` |
| `R-hw` | `/tmp/claude-0/-home-claude/a0c2d3af-ccae-55e0-bf62-dfe45a26d2a9/scratchpad/research_hw_t8112.md` |

Пути внутри `U` указаны от корня `U`; `Pkg/` означает `Platform/MacBookAirMid2022Pkg/`.

---

## 0. Статус и риски

1. **Резервная копия всего, что есть на Air.** Установщик Asahi меняет разметку внутреннего диска (`Pkg/INSTALL.ru.md:12`, `:50-52`).
2. **Внешний USB-C SSD будет полностью стёрт** на шаге 5.
3. **Что обратимо.** Установку Asahi/m1n1 можно удалить без переустановки macOS: инструкция Asahi
   «Deleting an install» (ссылка в `Pkg/INSTALL.ru.md:55`, удалять только через `diskutil`). Больше мы ничего
   не обещаем: гарантий, что железо не пострадает, у нас нет.
4. **Что известно про внутренний диск.** В прошивке драйвер NVMe закомментирован (`Pkg/MacBookAirMid2022.fdf:155-158`),
   у Windows драйвера для Apple ANS нет (`Pkg/WINDOWS_BOOT_MAP.ru.md:58-59`). Поэтому прошивка и Windows внутренний диск,
   скорее всего, не видят. Это **выведено из кода, не проверено**.
5. **Чего мы не знаем.** Гипервизор отдаёт гостю все MMIO-диапазоны `/arm-io` как настоящее железо
   (`M/proxyclient/m1n1/hv/__init__.py:1757-1760`). Гостевой m1n1 и прошивка сами пишут в регистры питания, USB и PHY.
   Чем это грозит на M2, **неизвестно**.
6. Если Mac завис намертво: долгое нажатие кнопки питания выключает его. Сброс и выключение из гостя перезагружают
   всю машину (`R-boot:83`).

---

## 1. Что понадобится

**Железо**
- MacBook Air 13" M2 (J413), заряженный.
- Второй ПК с Linux или macOS и кабель USB-C для связи с Air.
- Внешний USB-C SSD (пустой или ненужный).
- USB-клавиатура и USB-хаб: клавиатура и SSD будут вместе в одном порту Air.
  Работу клавиатуры через хаб в прошивке никто не проверял.
- Телефон с камерой: снимать экран Air на каждом этапе.

**Порты Air (важно).** Какой из двух левых портов физически является `usb0`, **неизвестно**.
- Метки в дереве устройств Asahi есть только у PD-контроллеров: `typec0` = «USB-C Left-back», `typec1` = «USB-C Left-front»
  (`R-hw:60, :64`, источник `a_j413.dts:84-90`). Что `typec0` обслуживает именно `usb-drd0`, не доказано.
- Надёжная проверка одна: строка `Initializing hypervisor over iodev USB0` в выводе `run_guest.py`
  (`M/proxyclient/m1n1/hv/__init__.py:1739`). См. шаги 3.4 и 6.
- Второй ПК должен стоять в порту `usb0`. По этому порту работает связь с гипервизором, поэтому прошивка его не трогает
  (`U/Silicon/Apple/AppleSiliconPkg/Drivers/AppleDartIoMmuDxe/AppleDartIoMmuDxe.c:507-511`). В DSDT его тоже нет:
  там описан только второй контроллер, DWC3 по адресу `0x502280000` (`Pkg/AcpiTables/DSDT.asl:39-52`).
- SSD и хаб с клавиатурой — в другой порт. Прошивка поднимает на нём только USB2 (`Pkg/WINDOWS_BOOT_MAP.ru.md:30`).

**ПО на втором ПК**
- `git`, `python3`, библиотеки `construct` и `pyserial` (`M/requirements.txt`).
- Сборка m1n1: на Linux `gcc-aarch64-linux-gnu` (`M/README.md:5`), на macOS `brew install llvm lld` (`M/README.md:21-24`);
  Rust с целью `aarch64-unknown-none-softfloat` (`M/README.md:6-10`).
- Сборка прошивки: Linux; пакеты перечислены в `Pkg/INSTALL.ru.md:13-14`.
- Linux: правило udev `M/udev/80-m1n1.rules`. Оно создаёт `/dev/m1n1` (связь с m1n1) и `/dev/m1n1-sec`
  (второй последовательный порт). На macOS это `/dev/cu.usbmodemP_01` и `/dev/cu.usbmodemP_03`
  (`M/proxyclient/m1n1/proxy.py:135-138`, `M/proxyclient/tools/picocom-sec.sh:3-4`).
- **Машина с Windows (можно виртуальная, с пробросом USB-диска)** для `diskpart`, `DISM`, `bcdboot`, `bcdedit`, `reg`.
  Без Windows шаг 5 целиком не сделать (см. 5.6).
- Дерево устройств `t8112-j413.dtb`. Гостевому m1n1 нужен DTB, без него он не загрузит `.fd` (см. 2.4).

**Образ Windows.** Только официальный образ Microsoft Windows 11 ARM64 (ISO или VHDX). Ссылок не даём: мы их не проверяли.
Ниже описан путь через ISO (файл `sources\install.wim` или `sources\install.esd`).

---

## 2. Сборка

### 2.1 Прошивка (`.fd`)

Команды из `Pkg/INSTALL.ru.md:18-43`:

```
git clone https://github.com/Tsifrokayf/apple_silicon_platforms_mu
cd apple_silicon_platforms_mu
git checkout m2-air-j413-scaffold
python3 -m venv venv && . venv/bin/activate
pip install -r pip-requirements.txt "setuptools<81"
export CLANGPDB_BIN=/usr/lib/llvm-18/bin/ CLANGPDB_AARCH64_PREFIX=aarch64-linux-gnu-
stuart_setup  -c Platform/MacBookAirMid2022Pkg/PlatformBuild.py TOOL_CHAIN_TAG=CLANGPDB
stuart_update -c Platform/MacBookAirMid2022Pkg/PlatformBuild.py TOOL_CHAIN_TAG=CLANGPDB
stuart_build  -c Platform/MacBookAirMid2022Pkg/PlatformBuild.py TOOL_CHAIN_TAG=CLANGPDB
```

- Результат: `Build/MacBookAirMid2022-AARCH64/DEBUG_CLANGPDB/FV/J413MACBOOKAIRMID2022_EFI.fd`.
- Для первого запуска нужна **DEBUG-сборка**: она печатает лог, а на `ASSERT` останавливается с сообщением
  (`U/Silicon/Apple/AppleSiliconPkg/AppleSiliconPkg.dsc.inc:78-79`).
- Убедитесь, что `git log -1` показывает `ada1bf6` или новее. В этом коммите появились резервирование памяти, identity-карта
  DART и DSDT без порта связи.

### 2.2 Гипервизор `m1n1_windows`

```
git clone https://github.com/Tsifrokayf/m1n1_windows
cd m1n1_windows
git checkout vgic-state-machine
git submodule update --init                      # README клонирует с --recursive (M/README.md:13)
rustup target add aarch64-unknown-none-softfloat
make -j"$(nproc)" USE_CLANG=0                    # Linux: gcc aarch64-linux-gnu- (M/Makefile:27-46)
# macOS: просто make (там USE_CLANG=1 по умолчанию, M/Makefile:3-4)
pip install -r requirements.txt
```

- Результат: `build/m1n1.bin`.
- vGIC включается в `M/config.h:32` (`ENABLE_VGIC_MODULE`), отдельный флаг не нужен.
- `USE_CLANG=0` на Linux совпадает со значением по умолчанию: `USE_CLANG=1` ставится только на Darwin.
- Коммит должен быть `1110872` или новее (PSCI `CPU_ON`, виртуальный PL011, исправления vGIC).

Проверка, что proxyclient вообще запускается. Раньше он падал с `IndentationError`, `R-boot:33-34`; исправлено в `821dc44`:

```
cd proxyclient
python3 -c "import m1n1.hv; print('ok')"
```

### 2.3 Драйверы (для первого запуска не нужны)

`AppleDockChannelHid` (клавиатура и трекпад) привязывается к ACPI-устройству `APPL0D01`
(`D/AppleDockChannelHid/README.md:24`, `:79-83`). В текущем DSDT такого устройства нет: там только процессоры и `USB1`
(`Pkg/AcpiTables/DSDT.asl:21-53`). Поэтому на первом запуске драйвер не загрузится, даже если его поставить.
Если нужно собрать заранее (`D/AppleDockChannelHid/README.md:95-101`, `D/build/README.md:32-38`, `:69-73`):

```
export WDK_ROOT=$HOME/wdkx      # распакованные NuGet-пакеты WDK и SDK, см. D/build/README.md
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
    -keyout test.key -out test.crt -subj "/CN=NTASP Test Signing" \
    -addext extendedKeyUsage=codeSigning
SIGN_CERT=test.crt SIGN_KEY=test.key build/build.sh   # -> build/out/arm64/AppleDockChannelHid.sys
```

### 2.4 DTB для гостевого m1n1

- Гостевой m1n1 ищет DTB с `compatible = "apple," + target-type` в нижнем регистре
  (`M/src/payload.c:295-301`, `:112-117`). Без DTB он пишет
  `ERROR: Kernel found but no devicetree for ... available.` (`M/src/payload.c:351-352`).
- Нужный файл — `t8112-j413.dtb` из ядра Asahi Linux (`R-boot:26`).
- В наших репозиториях DTB нет, и его сборку мы не проверяли. Обычный для ядра путь — в дереве исходников ядра Asahi выполнить
  `make ARCH=arm64 defconfig` и `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dtbs`; файл появится в
  `arch/arm64/boot/dts/apple/t8112-j413.dtb`. Это **не проверено**.
- Подходит ли DTB, видно по строке `Found a devicetree for apple,j413` (`M/src/payload.c:115`).

### 2.5 Сборка полезной нагрузки для гостя

**Выведено из кода, не проверено** (`R-boot:24-31`). Формат «m1n1 + DTB + сжатое ядро» описан в `M/README.md:66-80`.
Прошивка начинается с заголовка образа ядра Linux arm64 (`Pkg/MacBookAirMid2022.fdf:57-69`), поэтому m1n1 загружает её
как ядро.

```
cd m1n1_windows
gzip -c /путь/к/J413MACBOOKAIRMID2022_EFI.fd > fd.gz
cat build/m1n1.bin /путь/к/t8112-j413.dtb fd.gz > m1n1-uefi.bin
```

Запускать `.fd` напрямую (`run_guest.py -r fd`) нельзя: прошивка ждёт DTB в `x0` и boot args в `x4`
(`M/src/kboot.c:2984-2989`), а гипервизор передаёт только `x0..x3` (`R-boot:30-31`).

---

## 3. Подготовка Air

1. Сделайте резервную копию и обновите macOS (`Pkg/INSTALL.ru.md:50`).
2. В macOS выполните `curl https://alx.sh | sh`. Если предложен вариант «только UEFI/m1n1», выберите его
   (`Pkg/INSTALL.ru.md:51-53`). m1n1 остаётся на внутреннем диске: iBoot грузит его только оттуда.
3. **Режим прокси.**
   - По коду m1n1 переходит в режим прокси (`Running proxy...`), когда не находит полезной нагрузки
     (`M/src/main.c:127-138`).
   - Как перевести в этот режим m1n1, поставленный установщиком Asahi, в наших репозиториях **не описано**.
     Смотрите руководство m1n1 на сайте Asahi, на него ссылается `M/README.md:52`.
   - Решит вопрос любой рабочий способ: признак успеха — пункт 4.
4. Подключите второй ПК к Air. На втором ПК должен появиться `/dev/m1n1` (macOS: `/dev/cu.usbmodemP_01`). Проверьте связь:

   ```
   cd m1n1_windows/proxyclient
   python3 tools/shell.py          # печатает "m1n1 base: 0x..." (M/proxyclient/m1n1/setup.py:30)
   >>> p.iodev_whoami()            # ожидается IODEV.USB0; если USB1 — переткните кабель в другой порт
   ```

   Вызов `p.iodev_whoami()` в оболочке **выведен из кода, не проверен**: тот же вызов делает гипервизор
   (`M/proxyclient/m1n1/hv/__init__.py:1728`).

---

## 4. Снять ADT и заполнить чек-лист

Команда из `Pkg/T8112_BRINGUP_TODO.md:12-15`, Air в режиме прокси:

```
cd m1n1_windows/proxyclient
python3 -m m1n1.adt -r adt.bin > adt.txt
```

`adt.txt` может содержать серийный номер и MAC-адреса машины. Решите сами, публиковать ли его.

Сверьте и запишите (значения справа — наши ожидания из дерева устройств Asahi, а не из вашей машины):

| # | Что в `adt.txt` | Ожидаем | С чем должно совпасть |
|---|---|---|---|
| 1 | `/` → `target-type` | `J413` | DTB `apple,j413` (`M/src/payload.c:295-301`) |
| 2 | `/arm-io/usb-drd1` → `interrupts` | `1112` | таблица `vgic_remap_t8112`: `1112 → 962` (`M/src/hv_vgic.c:1271-1277`); DSDT `Interrupt { 962 }` (`Pkg/AcpiTables/DSDT.asl:50`) |
| 3 | `/arm-io/dart-usb1` → `interrupts` | `1116` | `1116 → 963` (`M/src/hv_vgic.c:1275`) |
| 4 | `/arm-io/usb-drd0`, `/arm-io/dart-usb0` → `interrupts` | `1031`, `1035` | `1031 → 960`, `1035 → 961` (`M/src/hv_vgic.c:1272-1273`) |
| 5 | `/arm-io/usb-drd1` → `reg` (после трансляции `ranges`) | `0x502280000` | DSDT `QWordMemory` (`Pkg/AcpiTables/DSDT.asl:48-49`) |
| 6 | `/arm-io/dart-usb1` → `reg` | `0x502f00000`, `0x502f80000` | `R-hw:65` |
| 7 | `/cpus/cpu0..7` → `reg`, `cpu-id`, `cluster-id` | кластер 0 = 4 E-ядра, кластер 1 = 4 P-ядра; в DT это MPIDR `0x0..0x3` и `0x10100..0x10103` (`R-hw:100-103`) | MADT `GET_MPIDR(0,0,0,n)` и `GET_MPIDR(0,1,1,n)` (`U/Silicon/Apple/T811XFamilyPkg/AcpiTables/MADT_Static.aslc:87-110`). В ADT `reg` закодирован как `(die<<11)\|(cluster<<8)\|cpu` (`M/proxyclient/m1n1/hv/__init__.py:1968-1969`), а не как MPIDR |
| 8 | наличие `dart-usb0`, `dart-usb1` | оба есть | `PcdAppleNumDwc3Controllers 2`, `PcdAppleNumDwc3Darts 4` (`Pkg/MacBookAirMid2022.dsc:47-48`) |
| 9 | `/arm-io/uart0` → `reg`, `interrupts` | `0x235200000` | `Pkg/T8112_BRINGUP_TODO.md:34-35`; на этот UART гипервизор вешает vUART (`M/proxyclient/m1n1/hv/__init__.py:1829-1836`) |

Если не совпали строки 2–5, **не запускайте**: Windows не увидит USB-контроллер. Пришлите `adt.txt` разработчику.
Переносить таблицу remap на числа из вашей ADT нужно в коде (`M/src/hv_vgic.c:1271-1277` и `Pkg/AcpiTables/DSDT.asl:50`
одновременно).

**RAM и boot args.** В `python3 tools/shell.py` (**выведено из кода, не проверено**; поля из `M/proxyclient/m1n1/tgtypes.py:10-12`):

```
>>> hex(u.ba.phys_base), hex(u.ba.mem_size)
```

- Прошивка копирует boot args и ADT по фиксированным адресам `0x840000000` и `0x840004000`, ADT до `0x400000` байт
  (`U/Silicon/Apple/T811XFamilyPkg/T811XFamilyPkg.dsc.inc:21-25`).
- Если этот диапазон не лежит в свободной RAM выше загрузчика и прошивки, прошивка теперь **останавливается
  с сообщением**, а не портит память (`U/Silicon/Apple/AppleSiliconPkg/PrePi/AdtParser.c:36-55`,
  `U/Silicon/Apple/T811XFamilyPkg/Library/MemoryInitPeiLib/MemoryInitPeiLib.c:326-330`). Запишите оба числа.
- Обратите внимание: в гостя попадают не эти значения, а boot args, которые гипервизор строит в `load_raw`
  (`M/proxyclient/m1n1/hv/__init__.py:2069`). Сравнить их можно только в логе запуска.

**Бит bypass в DART (PARAMS2, бит 0).** От него зависит, пойдёт ли прошивка по пути bypass или построит identity-карту
(`U/Silicon/Apple/AppleSiliconPkg/Drivers/AppleDartIoMmuDxe/AppleDartIoMmuDxe.c:572`, `:587-591`).
Чтение из оболочки прокси **выведено из кода, не проверено**:

```
>>> p.pmgr_adt_power_enable("/arm-io/dart-usb1")
>>> d = u.adt["/arm-io/dart-usb1"]
>>> for i in range(len(d.reg)):
...     base, size = d.get_reg(i)
...     print(hex(base), hex(p.read32(base + 0x4)))
```

- Используемые функции: `pmgr_adt_power_enable` (`M/proxyclient/m1n1/proxy.py:1091`), `get_reg` (`M/proxyclient/m1n1/adt.py:724-729`),
  `read32` (`M/proxyclient/m1n1/proxy.py:869`). PARAMS2 лежит по смещению `0x04`, бит 0 = `BYPASS_SUPPORT` (`R-hw:129`).
  Значение на T8112 **неизвестно** (`R-hw:158`).
- Риск: чтение из блока без питания может повесить Air. Тогда помогает принудительная перезагрузка; к поломке это не ведёт.
  Если `pmgr_adt_power_enable` вернул ошибку, не читайте.

---

## 5. Подготовка диска Windows (на втором ПК)

**Ограничения.**
- Программа установки Windows не ставит систему на USB-диск. Образ разворачивается вручную, без запуска Setup (`R-win:60`).
- Все команды этого раздела — для Windows (`cmd.exe` от администратора). Их синтаксис взят **по документации Microsoft,
  здесь не проверен**.
- Буквы ниже: `S:` — ESP, `W:` — раздел Windows, `D:` — смонтированный ISO.

### 5.1 Разметка (Windows, `diskpart`)

```
diskpart
list disk
select disk N                 <- номер ВНЕШНЕГО SSD; ошибка здесь сотрёт другой диск
clean
convert gpt
create partition efi size=260
format quick fs=fat32 label=System
assign letter=S
create partition msr size=16
create partition primary
format quick fs=ntfs label=Windows
assign letter=W
exit
```

### 5.2 Развернуть образ (Windows, `DISM`)

```
dism /Get-ImageInfo /ImageFile:D:\sources\install.wim
dism /Apply-Image /ImageFile:D:\sources\install.wim /Index:<номер редакции> /ApplyDir:W:\
```

Если в ISO лежит `install.esd`, подставьте его вместо `install.wim`.

### 5.3 Загрузочные файлы и BCD (Windows)

```
bcdboot W:\Windows /s S: /f UEFI
```

- Работает ли `bcdboot` с x64-машины для ARM64-образа (берёт ли он ARM64-файлы из `W:\Windows\Boot\EFI`), **неизвестно**.
- Проверьте, что есть `S:\EFI\Boot\bootaa64.efi`. Если файла нет, скопируйте туда `S:\EFI\Microsoft\Boot\bootmgfw.efi`
  под этим именем.
- Зачем это нужно: UEFI-переменные в прошивке не сохраняются (`PcdEmuVariableNvModeEnable|TRUE`,
  `U/Silicon/Apple/AppleSiliconPkg/AppleSiliconPkg.dsc.inc:91`). Поэтому записи `Boot####`, созданной `bcdboot`, на Air не будет,
  и найти Windows можно только по стандартному пути `\EFI\Boot\bootaa64.efi`. Это **выведено из кода, не проверено**.

Настройки BCD для отладки (**по документации Microsoft, здесь не проверено**):

```
set BCD=S:\EFI\Microsoft\Boot\BCD
bcdedit /store %BCD% /set {default} testsigning on
bcdedit /store %BCD% /set {default} debug on
bcdedit /store %BCD% /dbgsettings serial debugport:1 baudrate:115200
bcdedit /store %BCD% /set {default} numproc 1
bcdedit /store %BCD% /set {default} bootlog yes
bcdedit /store %BCD% /enum all > S:\bcd-enum.txt
```

- `testsigning on` нужен только для своих тестово подписанных драйверов. Работает он лишь при выключенном Secure Boot
  (`R-win:102`). Ключи Secure Boot в прошивке не сохраняются (см. `AppleSiliconPkg.dsc.inc:91`), поэтому Secure Boot,
  вероятно, выключен. Это **выведено из кода, не проверено**.
- Отладочный порт описан в DBG2: тип PL011 (подтип `0x3`), адрес `0xF20000000` (`Pkg/AcpiTables/DBG2.aslc:88-100`).
  Там работает виртуальный PL011 гипервизора (`M/src/hv_vgic.c:1582-1588`, `M/src/hv_vuart.c:144-153`). Скорость он
  игнорирует: регистры делителя только запоминаются (`M/src/hv_vuart.c:207-212`).
  Соответствует ли `debugport:1` записи DBG2, **неизвестно**; запись одна, поэтому выбрано `1`.
- `numproc 1` вместе с `-C 0` на шаге 6 ограничивает систему одним ядром. Как Windows ведёт себя при отказе `CPU_ON`
  для остальных ядер MADT, **неизвестно** (подробнее в разделе 7).
- `bootlog yes` пишет `W:\Windows\ntbtlog.txt`, если ядро дойдёт до загрузки драйверов. После попытки файл можно прочитать
  на втором ПК.
- В PowerShell фигурные скобки нужно брать в кавычки (`'{default}'`); проще работать в `cmd.exe`.

### 5.4 BootDriverFlags (загрузка с USB)

Без этого значения USB-драйверы не грузятся как загрузочные (`R-win:61-62`). Значение `0x14`, ключ
`HKLM\SYSTEM\HardwareConfig\{uuid}\BootDriverFlags`. Под `{uuid}` понимается UUID системы из SMBIOS. В прошивке он
постоянный: `c08ac5fb-2a54-4369-8c51-af7d060a93cc` (`U/Silicon/Apple/AppleSiliconPkg/Drivers/SmbiosInfoDxe/SmbiosInfoDxe.c:145-168`).
Две вещи **неизвестны**:
- совпадёт ли имя ключа, которое создаст Windows, с этой строкой;
- достаточно ли этого ключа в свежем образе.

```
reg load HKLM\OFFSYS W:\Windows\System32\config\SYSTEM
reg add "HKLM\OFFSYS\HardwareConfig\{c08ac5fb-2a54-4369-8c51-af7d060a93cc}" /v BootDriverFlags /t REG_DWORD /d 0x14 /f
reg unload HKLM\OFFSYS
```

(Синтаксис `reg` — **по документации Microsoft, здесь не проверено**.)

### 5.5 Драйвер (на первом запуске пропустить)

Причина — в 2.3: в DSDT нет `APPL0D01`. На будущее путь из `D/AppleDockChannelHid/README.md:111-116`:
`DISM /Add-Driver /ForceUnsigned` для офлайн-образа. Каталога `.cat` нет, и этот путь никто не пробовал:

```
dism /Image:W:\ /Add-Driver /Driver:<путь>\AppleDockChannelHid.inf /ForceUnsigned
```

### 5.6 Если Windows нет совсем

- Развернуть `install.wim` на NTFS-раздел из Linux может `wimlib-imagex apply` (`R-win:60`). Загрузится ли развёрнутая
  так ARM64-система, **не проверено**. Сами мы утилиту здесь не запускали.
- Для BCD и правки куста реестра из Linux упоминаются `hivex` и `chntpw` (`R-win:61`, `:102`). Проверенных команд у нас нет.
- Значит, шаги 5.3–5.4 без Windows сейчас **не сделать**. Вопрос решила бы проверенная процедура записи BCD через hivex
  или готовый шаблон BCD.

---

## 6. Первый запуск (одно ядро)

Подключение:
- второй ПК — в порт `usb0`;
- SSD с Windows и хаб с USB-клавиатурой — в другой порт;
- Air в режиме прокси (шаг 3).

Заведите каталог для логов, например `~/air-run1`.

**Терминал 1 — запись второго последовательного порта.**
- Через этот порт идут вывод гостевого m1n1, лог прошивки (vUART на UART0, `M/src/hv_vuart.c:307-313`) и данные
  отладчика ядра (виртуальный PL011). Канал у всех один (`M/src/hv_vuart.c:146-149`, `M/src/usb.c:234-238`).
- Порт исчезает при каждой перезагрузке m1n1, поэтому запись идёт в цикле (Linux; на macOS `stty -f`
  и `/dev/cu.usbmodemP_03`).
- Это обычный shell, но с этим портом мы его **не проверяли**:

```
while true; do
  if [ -e /dev/m1n1-sec ]; then stty -F /dev/m1n1-sec raw -echo; cat /dev/m1n1-sec >> ~/air-run1/sec.log; fi
  sleep 1
done
```

**Терминал 2:** `tail -f ~/air-run1/sec.log`. Для интерактивного просмотра есть `M/proxyclient/tools/picocom-sec.sh`,
но он ничего не пишет в файл.

**Терминал 3 — запуск.** **Выведено из кода, не проверено** (`R-boot:24-31`; ключи из `M/proxyclient/tools/run_guest.py:20-24`,
`:61-71`, `:92-93`; `M/proxyclient/tools/chainload.py:12-13`):

```
cd m1n1_windows/proxyclient
python3 tools/chainload.py -r ../build/m1n1.bin
# дождаться, пока /dev/m1n1 появится снова (теперь на Air работает m1n1_windows)
python3 tools/run_guest.py -r -C 0 -l ~/air-run1/hv.log ../m1n1-uefi.bin
```

- `-r` — сырой образ с точкой входа `0x800` по умолчанию, как у `m1n1.bin`.
- `-C 0` — оставить в ADT гостя только `cpu0`.
- `-l` — писать в файл строки `TTY>` и трассировку. Обычный `print` скрипта в файл не попадает (`M/proxyclient/m1n1/hv/__init__.py:1722-1724`),
  поэтому вывод терминала 3 тоже сохраните (scrollback).
- `Ctrl+C` в терминале 3 останавливает гостя и открывает оболочку гипервизора (`M/proxyclient/m1n1/hv/__init__.py:2318`, `:1335-1351`).
  В ней `ctx` печатает контекст, `bt()` — стек, `cont()` продолжает работу (`:1447`, `:1625`, `:1631`).

Что ожидать по этапам. Строки взяты из кода; дошла ли до них хоть одна попытка, **неизвестно**.

| Этап | Где смотреть | Признак |
|---|---|---|
| Гипервизор | терминал 3 | `Initializing hypervisor over iodev USB0` (`hv/__init__.py:1739`). **Если `USB1` — остановитесь** (Ctrl+C, выход) и переткните кабель: иначе DSDT отдаст Windows порт связи. Далее `Disabled cpu1..7` (`run_guest.py:69`), `Removing ADT node /arm-io/usb-drd0` и др. (`hv/__init__.py:1996-2021`), `Jumping to entrypoint at 0x...` (`:2367`) |
| Гостевой m1n1 | `sec.log` | баннер m1n1, `Devicetree compatible value: apple,j413`, `Found a devicetree for apple,j413` (`payload.c:301`, `:115`), `Preparing to boot kernel at ... with fdt at ...` (`kboot.c:2982`), `Vectoring to next stage...` (`main.c:207`) |
| Прошивка, ранний этап | `sec.log` | `If you can see this message, UART works`, `FD Base Address`, `Current ADT Pointer` (`U/.../PrePi/PrePi.c:150-153`) |
| Прошивка, память | `sec.log` | `MemoryInitPeiLib: reserving boot_args/ADT copy ...`, `reserving loader memory ...` (`MemoryInitPeiLib.c:326`, `:308`). Строка с `Halting`/`halting` означает остановку: см. раздел 7 |
| Прошивка, DXE | `sec.log` | `Locating device specific ACPI tables` (`AcpiPlatform.c:508`); `USB DART... supports bypass mode` или строка про identity-карту (`AppleDartIoMmuDxe.c:572`, `:587`); `DWC3_... base address` (`AppleUsbTypeCBringupDxe.c:229`) |
| vGIC/PSCI | терминал 3, `hv.log` | множество строк `HV vGIC DEBUG ...`: логирование включено (`M/src/hv_vgic.c:85`); `PSCI SMC DEBUG: handling PSCI request 0x...` (`M/src/hv_exc.c:967`). Это медленно, но это не зависание |
| Boot Manager | экран Air (фото) | меню прошивки или сразу запуск `bootaa64.efi`. Найдёт ли прошивка диск сама, **неизвестно**. Если открылась UEFI Shell (она есть в FDF, `Pkg/MacBookAirMid2022.fdf:230`), введите `fs0:`, затем `\EFI\Boot\bootaa64.efi` (**не проверено**) |
| winload | экран Air (фото) | что именно покажет экран, **неизвестно**. Цвета или шаг строки могут быть неправильными: прошивка всегда сообщает формат BGRR8888 (`R-boot:75`) |
| Ядро | `sec.log` | после передачи управления ядру в `sec.log` должны появиться **двоичные** данные KD с виртуального PL011. Если байты пошли, ядро как минимум запустило отладчик. Расшифровать их может только WinDbg |

**WinDbg.** WinDbg работает только под Windows. Ему нужен COM-порт, за которым стоит `/dev/m1n1-sec` второго ПК.
Проверенного способа это сделать нет: возможно, Windows-VM с пробросом последовательного порта хоста. Кроме того,
прошивка и KD делят один канал, так что порт одновременно держит только одна программа. Для первого запуска хватит сырого `sec.log`.

**Второй запуск (только после первого).** Уберите `-C 0` и `numproc 1`.

---

## 7. Если встало

Таблица построена по списку кандидатов из `R-boot:114-136`. Что с тех пор исправлено, сверено по текущему коду.

| Симптом | Вероятная причина | Что снять и прислать |
|---|---|---|
| `python3 -c "import m1n1.hv"` падает | Сломан proxyclient. Прежняя `IndentationError` (`R-boot:33-34`) исправлена: файл разбирается, строки `M/proxyclient/m1n1/hv/__init__.py:2364-2365` в порядке. Новая ошибка — что-то другое | полный traceback, `git log -1` в `M` |
| `Initializing hypervisor over iodev USB1` | второй ПК стоит не в том порту | ничего; переткнуть кабели |
| После `Jumping to entrypoint` в `sec.log` пусто | Гостевой m1n1 не стартовал, или не работает второй ACM-порт | Терминал 3; `Ctrl+C`, затем `ctx`, `bt()`. Есть ли вообще `/dev/m1n1-sec` |
| `ERROR: Kernel found but no devicetree for apple,j413` | DTB не тот или не найден (`M/src/payload.c:352`) | `sec.log`; откуда взят DTB |
| `EarlySetup: cannot place boot_args/ADT copy ... Halting.` | Фиксированная копия boot args/ADT не помещается в RAM или пересекается с загрузчиком (`AdtParser.c:36-55`) | строка целиком (в ней RAM, размер ADT, конец FD); `u.ba.phys_base`, `u.ba.mem_size` из раздела 4 |
| `MemoryInitPeiLib: boot_args/ADT copy ... is not inside free RAM, halting` | то же, на этапе карты памяти (`MemoryInitPeiLib.c:326-330`) | строка; предыдущие 50 строк `sec.log` |
| `Failed to locate device specific tables` и `ASSERT` | GUID ACPI-модулей не совпадают. **Исправлено**: `Pkg/AcpiTables/DeviceAcpiTables.inf:15` = `PcdDeviceAcpiTableStorageFile` (`AppleSiliconPkg.dec:65`), `T811XFamilyPkg/AcpiTables/CPUAcpiTables.inf:15` = `PcdSocAcpiTableStorageFile` (`dec:66`). Если строка всё же есть, собрана старая прошивка | `git log -1` в `U`; путь к `.fd` |
| Любой `ASSERT [...]` в `sec.log` | DEBUG-сборка остановилась на проверке (`AppleSiliconPkg.dsc.inc:78`) | строка ASSERT целиком с файлом и номером строки |
| `Guest exception: ...` и открылась оболочка гипервизора | Ловушка, которую никто не обработал. Варианты: незнакомый системный регистр; доступ к неотображённому адресу (`HV: Unmapped IPA`, `M/src/hv_vm.c:1189`); доступ к нереализованному регистру GICR (`M/src/hv_vgic.c:979-984`) | весь вывод с контекстом; в оболочке `bt()`. Не нажимайте `cont()`, пока не скопировали вывод |
| `USB DART... has no bypass mode and no identity map support, DMA will fault` или `cannot identity map` | DART второго порта не настроен для Windows (`AppleDartIoMmuDxe.c:387-400`, `:591`) | эти строки; значение PARAMS2 из раздела 4 |
| Прошивка не видит SSD (нет пункта загрузки, в Shell нет `fsN:`) | не поднялся хост USB (`AppleUsbTypeCBringupDxe`, только USB2) или порт перепутан | строки `DWC3_...` и `Dwc3XhciCoreInit` из `sec.log`; фото экрана |
| Ошибка Windows Boot Manager на экране | Boot Manager не нашёл или не прочитал файлы (BCD, `winload`) | фото; `S:\bcd-enum.txt` |
| Бесконечный поток `[Redistributor]: 0x14` или `0xc0` | Был кандидат № 3 (WAKER/SYNCR). **Исправлено**: запись WAKER обновляет `ChildrenAsleep` (`M/src/hv_vgic.c:796-803`), SYNCR читается как 0 (`:951-955`). Если поток всё равно есть, причина другая | 200 последних строк `hv.log` |
| Обращения к ITS по адресу `0xF20000000+` или ожидание LPI | Был кандидат № 4. **Исправлено**: `GICD_TYPER.LPIS` сброшен (`M/src/hv_vgic.c:1031-1033`), PLPIS/DirectLPI тоже (`:1093`), ITS в MADT нет (`U/Silicon/Apple/T811XFamilyPkg/AcpiTables/MADT_Static.aslc:116`). Первая страница по этому адресу — PL011 (`hv_vgic.c:1582-1588`) | строки `hv.log` с адресом |
| Последние строки — PSCI, затем тишина | `CPU_ON` переписан (вход в состоянии сброса, `M/src/hv_psci.c:1268-1340`). Неизвестные SMC64 возвращают `NOT_SUPPORTED` (`:1802-1805`), `SMCCC_VERSION` отвечает 1.1 (`:1736-1737`). С `-C 0` ожидаема строка `PSCI DEBUG: CPU%d was never started into the guest` (`:1307-1308`): ядро не запущено, Windows получает `INTERNAL_FAILURE`. Как Windows это переносит, **неизвестно** | последние 300 строк `hv.log`; `Ctrl+C` → `ctx`; был ли `numproc 1` |
| Байтов KD нет, экран застыл после winload | Либо ядро встало до KD, либо KD не заработал. DBG2 раньше ссылался на несуществующее устройство `\_SB.COM0`; теперь в нём стоит «.» (порт без устройства в пространстве имён ACPI), влияло ли это, **неизвестно**. PL011 работает без прерываний (`M/src/hv_vuart.c:150-153`) | `Ctrl+C` → `ctx` (PC гостя) и `bt()`; `hv.log`; фото экрана |
| Синий или зелёный экран с кодом | Bugcheck. Например, `INACCESSIBLE_BOOT_DEVICE` указывает на USB-путь: BootDriverFlags, xHCI в DSDT, DART | фото с кодом и параметрами; `W:\Windows\ntbtlog.txt`, если появился |
| `SError` в оболочке | стадия 2 отображает MMIO как Normal-память, а Windows обращается как к Device (`R-boot:129`) | весь вывод исключения |
| Air перезагрузился сам | гость вызвал PSCI `SYSTEM_RESET`/`SYSTEM_OFF` (`M/src/hv_psci.c:1750-1759`) или `Guest exception not handled, rebooting.` (`M/src/hv_exc.c:102`) | конец `hv.log` и терминала 3 |
| Всё идёт, но очень медленно | каждое обращение к vGIC и каждый SMC печатаются (`M/src/hv_vgic.c:85`, `M/src/hv_exc.c:967`); часть системных регистров обрабатывается в Python (`R-boot:99`) | подождать; прислать `hv.log` |

---

## 8. Что прислать разработчику

1. `git log -1 --oneline` во всех трёх репозиториях; тип сборки прошивки (DEBUG/RELEASE).
2. `adt.bin` и `adt.txt` (с учётом предупреждения о серийном номере), заполненную таблицу из раздела 4, вывод `u.ba.phys_base`,
   `u.ba.mem_size` и значения PARAMS2.
3. `~/air-run1/hv.log` и полный вывод терминала 3.
4. `~/air-run1/sec.log` как есть, без правки: в нём могут быть двоичные данные KD.
5. Фото экрана Air на каждом этапе и в момент остановки.
6. Вывод `dism /Get-ImageInfo` (сборка Windows и номер редакции), `S:\bcd-enum.txt`; `W:\Windows\ntbtlog.txt`, если он появился.
7. Если открывалась оболочка гипервизора — вывод `ctx` и `bt()`.
8. Что делали не по этому тексту: другой порт, другой DTB, другие ключи.
