/*
 * Copyright (c) 2015, Linaro Ltd. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause-Patent
 */

#include <Uefi.h>
#include <Library/BaseLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/PcdLib.h>
#include <Library/DebugAgentLib.h>
#include <Library/DebugLib.h>
#include <Library/AppleDTLib.h>

#define ALIGN_UP(x, a)   (((x) + ((a) - 1)) & ~((a) - 1))

BOOLEAN
EarlySetup (
  IN VOID     *BootArgsAddr,
  OUT UINT64  *SystemMemoryBase,
  OUT UINT64  *SystemMemorySize,
  IN    VOID  *PcdBootArgsDest,
  IN    VOID  *PcdAdtDest
  )
{

  struct boot_args *BootArgs = (struct boot_args *)BootArgsAddr;

  //
  // With a bounded ADT copy the SoC's MemoryInitPeiLib reserves a fixed region for both copies.
  // Check before copying: an oversized ADT would spill past that reservation, and a destination
  // inside the loader's memory (everything from phys_base up to the end of the FD is the loader's
  // image, its heap and the FD itself) or outside RAM would corrupt state that is still live or fault.
  // Returning FALSE is not enough here because the caller ignores it, so halt.
  //
  if (FixedPcdGet32 (PcdAdtMaxSize) != 0) {
    UINT64  CopyBase   = (UINT64)(UINTN)PcdBootArgsDest;
    UINT64  CopyTop    = (UINT64)(UINTN)PcdAdtDest + FixedPcdGet32 (PcdAdtMaxSize);
    UINT64  RamTop     = BootArgs->phys_base + BootArgs->mem_size;
    UINT64  LoaderTop  = PcdGet64 (PcdFdBaseAddress) + FixedPcdGet32 (PcdFdSize);

    if ((sizeof (struct boot_args) > (UINT64)(UINTN)PcdAdtDest - CopyBase) ||
        (BootArgs->devtree_size > FixedPcdGet32 (PcdAdtMaxSize)) ||
        (CopyBase < BootArgs->phys_base) || (CopyTop > RamTop) ||
        (CopyBase < LoaderTop))
    {
      DEBUG ((
        DEBUG_ERROR,
        "EarlySetup: cannot place boot_args/ADT copy at 0x%llx..0x%llx (ADT size 0x%x, max 0x%x; "
        "RAM 0x%llx..0x%llx; loader+FD end 0x%llx). Halting.\n",
        CopyBase, CopyTop, BootArgs->devtree_size, FixedPcdGet32 (PcdAdtMaxSize),
        BootArgs->phys_base, RamTop, LoaderTop
        ));
      CpuDeadLoop ();
    }
  }

  CopyMem(PcdBootArgsDest, BootArgsAddr, sizeof(struct boot_args));
  CopyMem(PcdAdtDest, (VOID*)BootArgs->devtree - BootArgs->virt_base + BootArgs->phys_base, BootArgs->devtree_size);

  if(dt_check(PcdAdtDest, BootArgs->devtree_size, NULL) != 0) {
    DEBUG((EFI_D_INFO | EFI_D_LOAD | EFI_D_ERROR, "no ADT supplied, exiting\n"));
    return FALSE;
  }

  *SystemMemoryBase = BootArgs->phys_base;
  *SystemMemorySize = BootArgs->phys_base + BootArgs->mem_size - BootArgs->phys_base;


  PatchPcdSet64(PcdFrameBufferAddress, BootArgs->video.base);
  PatchPcdSet64(PcdFrameBufferSize, ALIGN_UP(BootArgs->video.stride * BootArgs->video.height, 0x4000)); // for notched/internal displays, the FB size has to be aligned up!

  DEBUG((EFI_D_INFO | EFI_D_LOAD | EFI_D_ERROR, "Framebuffer address loaded to PCDs: 0x%llx (size 0x%llx)\n", PcdGet64(PcdFrameBufferAddress), PcdGet64(PcdFrameBufferSize)));

  return TRUE;
}
