## Current State
Complete
- Memory Management (paging, buddy allocator, slub allocator, virtual allocator, page fault handlers)
- Process Management (signals, timers, synchronization primitives, exceptions)

Future (in order of priority)
- Virtual file system
- Basic I/O devices like mouse, keyboard, display, speakers, and maybe microphone and camera
- User mode gnu software port (gcc, binutils, etc), mlibc port
- Storage devices like AHCI (SATA), USB Attached AHCI (UAS), NVMe, and USB Bulk Only Transport (BOT)
- EEVDF Scheduler
- File system implementations like FAT, exFAT, ext3

## Standards
Famex rests upon a number of different standards, all of which are listed below

- POSIX.1-2024 (EEE Std 1003.1™-2024 and The Open Group Standard Base Specifications, Issue 8) (https://pubs.opengroup.org/onlinepubs/9799919799/)


- ELF-64 Object File Format (Version 1.5, Draft 2)
- UEFI Spec (Release 2.11) (https://uefi.org/sites/default/files/resources/UEFI_Spec_Final_2.11.pdf)
- ACPI Spec (Release 6.6) (https://uefi.org/sites/default/files/resources/ACPI_Spec_6.6.pdf)


- IA-PC HPET Spec (https://www.intel.com/content/dam/www/public/us/en/documents/technical-specifications/software-developers-hpet-spec-1-0a.pdf)
- MC146818A CMOS Real Time Clock (RTC) with RAM
- Intel 64 and IA-32 SDM (https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html)
- AMD64 APM (https://docs.amd.com/v/u/en-US/40332-PUB_4.08)
- AMD64 System V ABI (https://gitlab.com/x86-psABIs/x86-64-ABI)

## Libraries
Famex relies on these software libraries.

- Linux data structures implementations: Maple Tree, RBTree, XArray
- X86-CPUID-DB (https://gitlab.com/x86-cpuid.org/x86-cpuid-db)
- Limine Bootloader (https://github.com/limine-bootloader/limine)
- ACPI Component Architecture (https://github.com/acpica/acpica)

# AI Usage
- AI was not used for code generation.
- No AI output was copied verbatim.
- AI chatbots were used to explain concepts and generate some build scripts. 
- AI chatbots were used as code logic checkers, an additional check above the linter.
