/**
 * Module Name:
 *     DSDT.asl
 *
 * Abstract:
 *     Differentiated System Description Table for the MacBook Air (M2, 2022, 13-inch, J413).
 *
 *     Minimal on purpose: processors and the two USB host controllers. Everything else on the
 *     board has no Windows driver yet and is left undescribed.
 *
 *     NOT VERIFIED ON HARDWARE. MMIO bases come from the Asahi Linux device tree (t8112.dtsi).
 *     The interrupt numbers are the virtual INTIDs that the m1n1_windows vGIC assigns to the
 *     AIC lines (vgic_remap_t8112 in src/hv_vgic.c): AIC 1031 -> 960, AIC 1112 -> 962.
 *     Keep the two in sync.
 *
 * License:
 *     SPDX-License-Identifier: BSD-2-Clause-Patent OR MIT
 **/

DefinitionBlock("DSDT.aml", "DSDT", 0x02, "Apple ", "J413    ", 0x8112) {
    Scope(\_SB) {
        // _UID values match the AcpiProcessorUid fields of the MADT GICC entries.
        Device(CPU0) { Name(_HID, "ACPI0007") Name(_UID, 0) }
        Device(CPU1) { Name(_HID, "ACPI0007") Name(_UID, 1) }
        Device(CPU2) { Name(_HID, "ACPI0007") Name(_UID, 2) }
        Device(CPU3) { Name(_HID, "ACPI0007") Name(_UID, 3) }
        Device(CPU4) { Name(_HID, "ACPI0007") Name(_UID, 4) }
        Device(CPU5) { Name(_HID, "ACPI0007") Name(_UID, 5) }
        Device(CPU6) { Name(_HID, "ACPI0007") Name(_UID, 6) }
        Device(CPU7) { Name(_HID, "ACPI0007") Name(_UID, 7) }

        //
        // USB host controllers. Each is a Synopsys DWC3 whose xHCI register block starts at the
        // DWC3 base. The firmware must leave the controller in host mode with its PHY set up and
        // its DARTs in bypass or identity-mapped: Windows has no driver for either.
        // _CCA is 1 because the generic xHCI driver is told DMA is cache-coherent.
        //
        Device(USB0) {
            Name(_HID, "PNP0D10")
            Name(_UID, 0)
            Name(_CCA, 1)
            Name(_CRS, ResourceTemplate() {
                QWordMemory(ResourceConsumer, PosDecode, MinFixed, MaxFixed, NonCacheable, ReadWrite,
                    0x0, 0x382280000, 0x382287FFF, 0x0, 0x8000)
                Interrupt(ResourceConsumer, Level, ActiveHigh, Exclusive) { 960 }
            })
        }
        Device(USB1) {
            Name(_HID, "PNP0D10")
            Name(_UID, 1)
            Name(_CCA, 1)
            Name(_CRS, ResourceTemplate() {
                QWordMemory(ResourceConsumer, PosDecode, MinFixed, MaxFixed, NonCacheable, ReadWrite,
                    0x0, 0x502280000, 0x502287FFF, 0x0, 0x8000)
                Interrupt(ResourceConsumer, Level, ActiveHigh, Exclusive) { 962 }
            })
        }
    }
}
