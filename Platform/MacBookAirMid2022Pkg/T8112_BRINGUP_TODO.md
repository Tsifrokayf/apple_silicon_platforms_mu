# MacBook Air (M2, 2022, 13-inch, J413) - bring-up checklist

This package and `Silicon/Apple/T811XFamilyPkg` were scaffolded by copying the M1 packages
(`MacBookAirMid2020Pkg`, `T810XFamilyPkg`) and renaming them. **Nothing here has been booted on hardware.**
Every value listed below is an M1 value carried over (or an assumption) and must be checked against the
ADT of the real machine before it is trusted.

## 0. Get the ADT of your machine

With m1n1 running on the Air and the proxy cable connected to the second PC:

```
cd m1n1_windows/proxyclient
python3 -m m1n1.adt -r adt.bin > adt.txt
```

`adt.txt` is the reference for every row below (`/arm-io/...` nodes, `cpus`, `chosen`, `device-tree`).

## 1. Values to verify

| # | Where | Carried over from M1 | Verify against |
|---|-------|----------------------|----------------|
| 1 | `T811XFamilyPkg/AcpiTables/MADT_Static.aslc` | per-core `PmuIrq` 50/54/58/62/34/38, MPIDR layout `(0,0,0,n)` E-cores / `(0,1,1,n)` P-cores | ADT `/cpus/cpuN` (`reg`, `cpu-id`, `cluster-id`), PMU IRQs |
| 2 | `MADT_Static.aslc` + `T811XFamilyPkg.dsc.inc` | vGIC distributor `0xF00000000`, redistributors `0xF10000000`, ITS `0xF20000000` | must match `DIST_BASE_36_BIT`/`REDIST_BASE_36_BIT` in `m1n1_windows/src/hv_vgic.c`; only valid if T8112 is a 36-bit-PA platform (not checked) |
| 3 | `T811XFamilyPkg.dsc.inc` | `PcdAppleSartVersion|2`, `PcdBootArgsPointer 0x840000000`, `PcdAdtPointer 0x840004000`, `PcdSecPhaseStackBase 0x900000000`, 8 cores / 2 clusters | SART version for T8112 is unchecked; the pointers must match where the hypervisor places boot args/ADT |
| 4 | `T811XFamilyPkg.dsc.inc` | PCIe windows (`0xc0000000`, `0x400000000`, ECAM `0x690000000`, DMA offset) | ADT `/arm-io/apcie*`; PCIe is not in the Air FDF yet, so low priority |
| 5 | `T811XFamilyPkg/Include/Library/T811XFamilyVirtualMemoryMapDefines.h` | all MMIO ranges | ADT `/arm-io` `ranges`; wrong ranges mean faults in early memory init |
| 6 | `MacBookAirMid2022Pkg/AcpiTables/DSDT.asl` | UART interrupt `1097`, 2 clusters x 4 CPUs | ADT `/arm-io/uart0` interrupts |
| 7 | `MacBookAirMid2022.dsc` | **assumed** `PcdAppleNumDwc3Controllers|2`, `PcdAppleNumDwc3Darts|4` | ADT nodes `dart-usb0`, `dart-usb1`, ... |
| 8 | `MacBookAirMid2022.fdf` | FD base `0x830000000` (M1 Air layout); `Resources/RegulatoryLogos.png` is the M1 Air image | where the hypervisor loads the firmware; replace the logo |
| 9 | `MacBookAirFamilyPkg/MacBookAirFamily.dsc.inc` | framebuffer defaults 2560x1600 | the iBoot framebuffer is used at runtime (`PcdFrameBuffer*` are patched from the FDT); the 13" M2 Air panel should be 2560x1664 |
| 10 | `MacBookAirMid2022.dsc` | SMBIOS model `Mac14,2`; CPU id `T8112` | model identifier from ADT `/` (`model`, `target-type`) |

Values already confirmed from `m1n1_windows`: `EARLY_UART_BASE` for `T8112` is `0x235200000`
(same as T8103), so `PcdAppleUartBase` and `DBG2.aslc` need no change.

## 2. Interrupt controller

* `AIC_BUILD = FALSE`: the firmware expects a vGIC provided by the `m1n1_windows` hypervisor.
* The vGIC interrupt state machine was rewritten (`hv_vgic_core.c`, branch `vgic-state-machine` of the
  `m1n1_windows` fork) and has a host test. Remaining work is listed in `WINDOWS_BOOT_MAP.ru.md`.
* The AIC version used by T8112 (v1 vs v2) is not confirmed. m1n1 detects it from the ADT `compatible`.
  The native AIC DXE driver says AICv2 is finished and AICv1 is in progress.

## 3. USB-C boot path

* The firmware boots from USB-C storage through `AppleUsbTypeCBringupDxe` + `AppleDartIoMmuDxe`.
* `AppleDartIoMmuDxe` deliberately skips DART indices 0, 1, 4 and 5 ("DFU port"), so the first USB-C
  controller (`usb0`) is left alone for the m1n1 proxy. Plug the **second PC** into that port and the
  **boot drive** into the other one. Which physical port is `usb0` on the Air must be checked.
* There is no `SoC id` switch in these two drivers; the DART flavour comes from the ADT `compatible`
  (`dart,t8110` or the T8020 default). `AppleSiliconPciPlatformDxe` only knows T602x and is not in the FDF.

## 4. Not supported by this package (see NTASP feature table for T8112)

Internal keyboard/trackpad (dockchannel), Wi-Fi/Bluetooth (PCIe + DART), internal NVMe, GPU, SMC/battery.

## 5. Building

Build check (sandbox, Ubuntu, clang 18, `TOOL_CHAIN_TAG=CLANGPDB`): `stuart_setup`, `stuart_build` finish with
`Success` and produce `Build/MacBookAirMid2022-AARCH64/DEBUG_CLANGPDB/FV/J413MACBOOKAIRMID2022_EFI.fd` (~31 MB).
This only proves the package compiles and links. It says nothing about whether it boots.

```
export CLANGPDB_BIN=/usr/lib/llvm-18/bin/ CLANGPDB_AARCH64_PREFIX=aarch64-linux-gnu-
stuart_setup -c Platform/MacBookAirMid2022Pkg/PlatformBuild.py TOOL_CHAIN_TAG=CLANGPDB
stuart_update -c Platform/MacBookAirMid2022Pkg/PlatformBuild.py TOOL_CHAIN_TAG=CLANGPDB
stuart_build  -c Platform/MacBookAirMid2022Pkg/PlatformBuild.py TOOL_CHAIN_TAG=CLANGPDB
```

Needs `acpica-tools` (iasl), `uuid-dev`, `gcc-aarch64-linux-gnu`, `lld`, `llvm`, and `setuptools<81` in the venv
(edk2toolext still imports `pkg_resources`).

In the sandbox the NuGet feeds were unreachable, so `stuart_update` failed for `mu_nasm`, `edk2-acpica-iasl` and
`mu-uncrustify-release`. None of them is used for an AArch64 firmware build (nasm is x86, uncrustify is a style
check, iasl comes from apt), so I created empty `*_extdep` state folders to get past the dependency check.
On a normal machine with network access `stuart_update` should fetch them properly and the stubs are not needed.
