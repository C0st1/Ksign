//
//  MachOUtils.m
//  Feather
//
//  Created by samara on 12.06.2025.
//

#import "MachOUtils.h"

#define SDK_VERSION_26_0_0 0x1A0000

/// https://github.com/LiveContainer/LiveContainer/commit/3a029b6bb36c11cc05784a8840d41c7e46af1540
/// this is licensed under Apache-2.0, bundled when compiled.
NSString *LCPatchMachOFixupARM64eSlice(const char *path) {
        int fd = open(path, O_RDWR, 0600);
        if(fd < 0) {
                return [NSString stringWithFormat:@"Failed to open %s: %s", path, strerror(errno)];
        }
        struct stat s = {0};
        fstat(fd, &s);
        void *map = mmap(NULL, s.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        if(map == MAP_FAILED) {
                close(fd);
                return [NSString stringWithFormat:@"Failed to map %s: %s", path, strerror(errno)];
        }
        
        uint32_t magic = *(uint32_t *)map;
        if(magic == FAT_CIGAM) {
                // Find arm64e slice without CPU_SUBTYPE_LIB64
                struct fat_header *header = (struct fat_header *)map;
                struct fat_arch *arch = (struct fat_arch *)(map + sizeof(struct fat_header));
                for(int i = 0; i < OSSwapInt32(header->nfat_arch); i++) {
                        if(OSSwapInt32(arch->cputype) == CPU_TYPE_ARM64 && OSSwapInt32(arch->cpusubtype) == CPU_SUBTYPE_ARM64E) {
                                struct mach_header_64 *header = (struct mach_header_64 *)(map + OSSwapInt32(arch->offset));
                                header->cpusubtype |= CPU_SUBTYPE_LIB64;
                                arch->cpusubtype = htonl(header->cpusubtype);
                                break;
                        }
                        arch = (struct fat_arch *)((void *)arch + sizeof(struct fat_arch));
                }
        }
        
        msync(map, s.st_size, MS_SYNC);
        munmap(map, s.st_size);
        close(fd);
        return nil;
}

static NSString *PatchMachOAtOffset(void *mapped, size_t fileSize, off_t offset, uint32_t index) {
        uint8_t *base = (uint8_t *)mapped + offset;
        
        if ((size_t)(offset + sizeof(struct mach_header_64)) > fileSize) {
                return [NSString stringWithFormat:@"Slice %u: Invalid offset or truncated header", index];
        }
        
        struct mach_header_64 *header = (struct mach_header_64 *)base;
        if (header->magic != MH_MAGIC_64) {
                return [NSString stringWithFormat:@"Slice %u: Unsupported or non-64-bit Mach-O", index];
        }
        
        struct load_command *cmd = (struct load_command *)(base + sizeof(struct mach_header_64));
        
        for (uint32_t i = 0; i < header->ncmds; i++) {
                uint8_t *cmdEnd = (uint8_t *)cmd + sizeof(struct load_command);
                if ((size_t)(cmdEnd - (uint8_t *)mapped) > fileSize) {
                        return [NSString stringWithFormat:@"Slice %u: Load command exceeds file size", index];
                }
                
                if (cmd->cmd == LC_BUILD_VERSION) {
                        struct build_version_command *bvc = (struct build_version_command *)cmd;
                        bvc->sdk = SDK_VERSION_26_0_0;
                        return [NSString stringWithFormat:@"Slice %u: Patched LC_BUILD_VERSION to SDK 26.0", index];
                }
                
                cmd = (struct load_command *)((uint8_t *)cmd + cmd->cmdsize);
        }
        
        return [NSString stringWithFormat:@"Slice %u: LC_BUILD_VERSION not found", index];
}

NSString *LCPatchMachOForSDK26(const char *path) {
        int fd = open(path, O_RDWR, 0600);
        if(fd < 0) {
                return [NSString stringWithFormat:@"Failed to open %s: %s", path, strerror(errno)];
        }
        struct stat s = {0};
        fstat(fd, &s);
        void *map = mmap(NULL, s.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        if(map == MAP_FAILED) {
                close(fd);
                return [NSString stringWithFormat:@"Failed to map %s: %s", path, strerror(errno)];
        }
        
        NSMutableString *result = [NSMutableString string];
        uint32_t magic = *(uint32_t *)map;
        
        if (magic == FAT_MAGIC || magic == FAT_CIGAM) {
                struct fat_header *fat = (struct fat_header *)map;
                uint32_t nfat = OSSwapBigToHostInt32(fat->nfat_arch);
                struct fat_arch *archs = (struct fat_arch *)((uint8_t *)map + sizeof(struct fat_header));
                
                for (uint32_t i = 0; i < nfat; i++) {
                        uint32_t offset = OSSwapBigToHostInt32(archs[i].offset);
                        NSString *sliceResult = PatchMachOAtOffset(map, s.st_size, offset, i);
                        [result appendFormat:@"%@\n", sliceResult];
                }
        } else if (magic == MH_MAGIC_64) {
                NSString *mainResult = PatchMachOAtOffset(map, s.st_size, 0, 0);
                [result appendFormat:@"%@\n", mainResult];
        } else {
                munmap(map, s.st_size);
                close(fd);
                return [NSString stringWithFormat:@"Unsupported binary format %s: %s", path, strerror(errno)];
        }
        
        munmap(map, s.st_size);
        close(fd);
        return result;
}

// MARK: - Read-Only: Linked Dylibs (for Feature 1: Tweak Load Order Controller)

/// Format a packed version (32-bit: major<<16 | minor<<8 | patch) as "X.Y.Z".
static NSString *MachOFormatVersion(uint32_t ver) {
    return [NSString stringWithFormat:@"%u.%u.%u",
            (ver >> 16) & 0xFFFF,
            (ver >> 8) & 0xFF,
            ver & 0xFF];
}

/// Walk load commands of a single 64-bit Mach-O slice and append dylib entries
/// to the `dylibs` array. Dedupes by path (first occurrence wins).
static void ReadLinkedDylibsFromSlice(void *mapped, size_t fileSize, off_t offset,
                                       NSMutableArray *dylibs, NSMutableSet *seenPaths) {
    uint8_t *base = (uint8_t *)mapped + offset;

    if ((size_t)(offset + sizeof(struct mach_header_64)) > fileSize) {
        return;
    }

    struct mach_header_64 *header = (struct mach_header_64 *)base;
    if (header->magic != MH_MAGIC_64) {
        return;
    }

    struct load_command *cmd = (struct load_command *)(base + sizeof(struct mach_header_64));

    for (uint32_t i = 0; i < header->ncmds; i++) {
        uint8_t *cmdEnd = (uint8_t *)cmd + sizeof(struct load_command);
        if ((size_t)(cmdEnd - (uint8_t *)mapped) > fileSize) {
            return;
        }

        NSString *typeName = nil;
        BOOL weak = NO;

        switch (cmd->cmd) {
            case LC_LOAD_DYLIB:
                typeName = @"LC_LOAD_DYLIB";
                weak = NO;
                break;
            case LC_LOAD_WEAK_DYLIB:
                typeName = @"LC_LOAD_WEAK_DYLIB";
                weak = YES;
                break;
            case LC_REEXPORT_DYLIB:
                typeName = @"LC_REEXPORT_DYLIB";
                weak = NO;
                break;
            case LC_LAZY_LOAD_DYLIB:
                typeName = @"LC_LAZY_LOAD_DYLIB";
                weak = NO;
                break;
            default:
                // Not a dylib load command — skip
                cmd = (struct load_command *)((uint8_t *)cmd + cmd->cmdsize);
                continue;
        }

        // dylib_command layout: { load_command lc; union lc_str name; uint32_t currentVersion; uint32_t compatVersion; }
        struct dylib_command *dc = (struct dylib_command *)cmd;
        // name.offset is the offset from the start of the dylib_command to the path string
        uint32_t nameOffset = dc->dylib.name.offset;
        uint8_t *namePtr = (uint8_t *)cmd + nameOffset;

        // Bounds check: ensure the name string doesn't exceed the command + file
        if ((size_t)(namePtr - (uint8_t *)mapped) >= fileSize) {
            cmd = (struct load_command *)((uint8_t *)cmd + cmd->cmdsize);
            continue;
        }

        // Read the C string (null-terminated) — strnlen to bound it
        size_t maxLen = fileSize - (size_t)(namePtr - (uint8_t *)mapped);
        size_t pathLen = strnlen((const char *)namePtr, maxLen);
        NSString *path = [[NSString alloc] initWithBytes:namePtr length:pathLen encoding:NSUTF8StringEncoding];

        // Dedupe by path (first occurrence wins across slices)
        if (path && ![seenPaths containsObject:path]) {
            [seenPaths addObject:path];

            NSDictionary *entry = @{
                @"path": path,
                @"type": typeName,
                @"loadIndex": @(dylibs.count),
                @"currentVersion": MachOFormatVersion(dc->dylib.current_version),
                @"compatVersion": MachOFormatVersion(dc->dylib.compatibility_version),
                @"weak": @(weak)
            };
            [dylibs addObject:entry];
        }

        cmd = (struct load_command *)((uint8_t *)cmd + cmd->cmdsize);
    }
}

NSString *MachOReadLinkedDylibs(const char *path) {
    int fd = open(path, O_RDONLY, 0);
    if (fd < 0) {
        return nil;
    }

    struct stat s = {0};
    if (fstat(fd, &s) != 0 || s.st_size == 0) {
        close(fd);
        return nil;
    }

    void *map = mmap(NULL, s.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (map == MAP_FAILED) {
        close(fd);
        return nil;
    }

    NSMutableArray *dylibs = [NSMutableArray array];
    NSMutableSet *seenPaths = [NSMutableSet set];

    uint32_t magic = *(uint32_t *)map;

    if (magic == FAT_MAGIC || magic == FAT_CIGAM) {
        // Fat binary — walk all slices
        struct fat_header *fat = (struct fat_header *)map;
        uint32_t nfat = OSSwapBigToHostInt32(fat->nfat_arch);
        struct fat_arch *archs = (struct fat_arch *)((uint8_t *)map + sizeof(struct fat_header));

        for (uint32_t i = 0; i < nfat; i++) {
            uint32_t offset = OSSwapBigToHostInt32(archs[i].offset);
            ReadLinkedDylibsFromSlice(map, s.st_size, offset, dylibs, seenPaths);
        }
    } else if (magic == MH_MAGIC_64) {
        // Thin 64-bit Mach-O
        ReadLinkedDylibsFromSlice(map, s.st_size, 0, dylibs, seenPaths);
    } else {
        // Not a supported Mach-O
        munmap(map, s.st_size);
        close(fd);
        return nil;
    }

    munmap(map, s.st_size);
    close(fd);

    // Build JSON
    NSDictionary *result = @{@"dylibs": dylibs};
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:nil];
    if (!jsonData) {
        return nil;
    }
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

