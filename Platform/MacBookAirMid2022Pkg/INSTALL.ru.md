# Установка и сборка: MacBook Air 13" M2 (J413)

> **Статус.** Пакет собирается, но на железе не запускался. NTASP сам пишет, что Windows на Apple Silicon пока
> не устанавливается: загрузчик доходит до передачи управления ядру и зависает; нет драйверов клавиатуры, трекпада,
> Wi-Fi/Bluetooth, GPU, внутреннего NVMe. Этот гайд доводит вас до отладочной загрузки прошивки, а не до рабочей Windows.
> Значения, не проверенные на реальном Air, перечислены в [`T8112_BRINGUP_TODO.md`](T8112_BRINGUP_TODO.md).

## 0. Что понадобится

- MacBook Air M2 13" (J413) и **второй компьютер** с Linux или macOS для m1n1 (связь по USB-C).
- **Внешний USB-C накопитель**, пустой: прошивка грузится с USB-C, внутренний NVMe в NTASP для M2 пока не работает.
- Резервная копия данных на Air: установщик Asahi меняет разметку внутреннего диска.
- На машине сборки: Linux (проверено на Ubuntu), `git`, `python3`, `acpica-tools`, `uuid-dev`,
  `gcc-aarch64-linux-gnu`, `lld`, `llvm`, `clang`.

## 1. Получить исходники

```
git clone https://github.com/Tsifrokayf/apple_silicon_platforms_mu
cd apple_silicon_platforms_mu
git checkout m2-air-j413-scaffold
git remote add upstream https://github.com/NT-for-ASi/apple_silicon_platforms_mu   # чтобы подтягивать обновления
```

Ветка `m2-air-j413-scaffold` содержит пакеты `Platform/MacBookAirMid2022Pkg` и `Silicon/Apple/T811XFamilyPkg`.
Они созданы копированием M1-пакетов (J313, T810X), поэтому многие значения нужно сверить с вашим Air.

## 2. Собрать прошивку

```
python3 -m venv venv && . venv/bin/activate
pip install -r pip-requirements.txt "setuptools<81"
# Если pip не ставит pygount (нет поддержки вашей версии Python), установите остальные пакеты из файла без него:
# он для сборки не нужен.

export CLANGPDB_BIN=/usr/lib/llvm-18/bin/ CLANGPDB_AARCH64_PREFIX=aarch64-linux-gnu-
stuart_setup  -c Platform/MacBookAirMid2022Pkg/PlatformBuild.py TOOL_CHAIN_TAG=CLANGPDB
stuart_update -c Platform/MacBookAirMid2022Pkg/PlatformBuild.py TOOL_CHAIN_TAG=CLANGPDB
stuart_build  -c Platform/MacBookAirMid2022Pkg/PlatformBuild.py TOOL_CHAIN_TAG=CLANGPDB
```

Результат: `Build/MacBookAirMid2022-AARCH64/DEBUG_CLANGPDB/FV/J413MACBOOKAIRMID2022_EFI.fd`
(около 31 МБ, сырой бинарник). Для релизной сборки добавьте `TARGET=RELEASE`.

Если `stuart_update` не может скачать `mu_nasm`, `edk2-acpica-iasl` или `mu-uncrustify-release` (NuGet недоступен),
см. раздел 5 в `T8112_BRINGUP_TODO.md`: для сборки под AArch64 они не нужны.

## 3. Подготовить Air

1. Сделайте резервную копию и обновите macOS.
2. Запустите установщик Asahi в macOS: `curl https://alx.sh | sh`. Если предложен вариант «только UEFI/m1n1»
   (минимальный раздел), выбирайте его. Установщик уменьшит раздел macOS и создаст раздел с m1n1.
3. Эта часть остаётся на **внутреннем** диске: iBoot загружает m1n1 только оттуда.

Как всё это потом удалить без переустановки macOS: [Deleting an install](https://asahilinux.org/docs/sw/deleting-an-install)
(удалять только командами `diskutil`, не через графический Disk Utility).

## 4. Подключение

- Второй компьютер подключается к порту, который прошивка считает `usb0` (его драйвер DART пропускает: он нужен для m1n1).
  Какой из двух портов Air это, надо проверить по ADT.
- Внешний накопитель подключается ко второму порту.

## 5. Снять ADT и сверить значения

Запустите m1n1 на Air, затем на втором компьютере, из каталога `proxyclient` репозитория `m1n1_windows`:

```
python3 -m m1n1.adt -r adt.bin > adt.txt
```

Сверьте `adt.txt` с таблицей в `T8112_BRINGUP_TODO.md` (прерывания и MPIDR ядер, адреса vGIC, карта MMIO,
число DWC3/DART, адрес FD) и поправьте пакеты. Это обязательный шаг: без него прошивка, скорее всего, не стартует.

## 6. Запуск прошивки (не проверено)

Прошивка рассчитана на vGIC из гипервизора `m1n1_windows` (`AIC_BUILD=FALSE`). В `proxyclient/tools/run_guest.py`
есть режим сырого образа (`-r`, точка входа задаётся `-E`). Но готовой документированной команды запуска `.fd`
для M2 нет, а адреса в пакете (FD `0x830000000`, boot args `0x840000000`, ADT `0x840004000`) взяты от M1 и должны
совпадать с тем, куда гипервизор кладёт образ. Не запускайте это вслепую: сверьте адреса по разделу 5 и по `hv_vgic.c`.

## 7. Обновление

```
git fetch upstream
git rebase upstream/main      # или git merge upstream/main
git push --force-with-lease origin m2-air-j413-scaffold    # только после rebase
```

## 8. Откат

Удаление раздела Asahi и возврат места macOS: см. ссылку в разделе 3. Данные и macOS это не затрагивает.
