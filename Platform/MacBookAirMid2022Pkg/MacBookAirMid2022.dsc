#MacBook Air (M2, 2022, 13-inch, J413) UEFI DSC file
#some parts borrowed from WOA-Project/SurfaceDuoPkg
#Disclaimer: probably not the best UEFI dev out there
#
#  Copyright (c) 2011-2015, ARM Limited. All rights reserved.
#  Copyright (c) 2014, Linaro Limited. All rights reserved.
#  Copyright (c) 2015 - 2016, Intel Corporation. All rights reserved.
#  Copyright (c) 2018, Bingxing Wang. All rights reserved.
#
#  This program and the accompanying materials
#  are licensed and made available under the terms and conditions of the BSD License
#  which accompanies this distribution.  The full text of the license may be found at
#  http://opensource.org/licenses/bsd-license.php
#
#  THE PROGRAM IS DISTRIBUTED UNDER THE BSD LICENSE ON AN "AS IS" BASIS,
#  WITHOUT WARRANTIES OR REPRESENTATIONS OF ANY KIND, EITHER EXPRESS OR IMPLIED.
#
#

#SPDX-License-Identifier: BSD 2-Clause

[Defines]
  PLATFORM_NAME                  = MacBookAirMid2022
  PLATFORM_GUID                  = d1530866-0f52-4aa8-9d11-e7b23047e69e
  PLATFORM_VERSION               = 1.0
  DSC_SPECIFICATION              = 0x00010005
  OUTPUT_DIRECTORY               = Build/MacBookAirMid2022-$(ARCH)
  SUPPORTED_ARCHITECTURES        = AARCH64
  BUILD_TARGETS                  = DEBUG|RELEASE
  SKUID_IDENTIFIER               = DEFAULT
  FLASH_DEFINITION               = MacBookAirMid2022Pkg/MacBookAirMid2022.fdf
  SECURE_BOOT_ENABLE             = FALSE
  AIC_BUILD                      = FALSE #vGIC (m1n1_windows hypervisor) by default - the native AIC path is still experimental
  USES_MAC_CPU                   = TRUE # a futureproofing switch, changes SoC identifier in SMBIOS
  NETWORK_TLS_ENABLE             = TRUE

[BuildOptions.common]
  GCC:*_*_AARCH64_CC_FLAGS = -DSILICON_PLATFORM=8112
  *_*_*_CC_FLAGS = -D DISABLE_NEW_DEPRECATED_INTERFACES -D HAS_MEMCPY_INTRINSICS

[PcdsFixedAtBuild.common]
  gAppleSiliconPkgTokenSpaceGuid.PcdSmbiosSystemModel|"MacBook Air (M2, 2022)"
  gAppleSiliconPkgTokenSpaceGuid.PcdSmbiosSystemModelNumber|"Mac14,2"
  gAppleSiliconPkgTokenSpaceGuid.PcdSmbiosSystemSku|"MacBook Air (Mac14,2)"
  # TODO(T8112): USB-C controller / DART counts are ASSUMED (2 ports, 2 DARTs per controller, same ratio as
  # the M2 Pro package). Verify against the ADT of the machine.
  gAppleSiliconPkgTokenSpaceGuid.PcdAppleNumDwc3Controllers|2
  gAppleSiliconPkgTokenSpaceGuid.PcdAppleNumDwc3Darts|4
  

[Components.common]

  MacBookAirMid2022Pkg/AcpiTables/DeviceAcpiTables.inf

!include MacBookAirFamilyPkg/MacBookAirFamily.dsc.inc
!include T811XFamilyPkg/T811XFamilyPkg.dsc.inc
!include AppleSiliconPkg/AppleSiliconPkg.dsc.inc
!include AppleSiliconPkg/FrontpageDsc.inc