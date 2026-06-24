//
//  MachOUtils.h
//  Feather
//
//  Created by samara on 12.06.2025.
//

@import Darwin;
@import Foundation;
@import MachO;

NSString *LCPatchMachOFixupARM64eSlice(const char *path);
NSString *LCPatchMachOForSDK26(const char *path);

/// Read-only: returns a JSON string describing every LC_LOAD_DYLIB /
/// LC_LOAD_WEAK_DYLIB / LC_REEXPORT_DYLIB / LC_LAZY_LOAD_DYLIB entry
/// in the Mach-O at `path`. For fat binaries, returns the union across
/// all slices (deduped by path).
///
/// JSON shape:
///   {
///     "dylibs": [
///       { "path": "@rpath/Foo.framework/Foo",
///         "type": "LC_LOAD_DYLIB",
///         "loadIndex": 0,
///         "currentVersion": "1.0.0",
///         "compatVersion": "1.0.0",
///         "weak": false }
///     ]
///   }
///
/// Returns nil on error (not a Mach-O, unreadable, etc.).
NSString *MachOReadLinkedDylibs(const char *path);

