// Add Ons: only app bundles in the folder are listed, by name; a missing folder gives an empty list.
#import <Foundation/Foundation.h>
#import "EDAddOns.h"
static int fails = 0;
#define CHECK(c, m) do { if (!(c)) { printf("FAIL: %s\n", m); fails++; } else printf("ok:   %s\n", m); } while (0)
int main(void) { @autoreleasepool {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *dir = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    CHECK([EDAddOns appsInFolder:dir].count == 0, "missing folder");
    for (NSString *n in @[@"Zed.app", @"Emu_Imager.app", @".hidden.app", @"notes.txt", @"Folder"])
        [fm createDirectoryAtURL:[dir URLByAppendingPathComponent:n] withIntermediateDirectories:YES attributes:nil error:nil];
    NSArray<NSURL *> *a = [EDAddOns appsInFolder:dir];
    CHECK(a.count == 2 && [[EDAddOns titleFor:a[0]] isEqualToString:@"Emu_Imager"] && [[EDAddOns titleFor:a[1]] isEqualToString:@"Zed"], "apps only, sorted");
    CHECK([EDAddOns.folder.path hasSuffix:@"/Library/Application Support/EMU3 Editor/Add Ons"], "folder location");
    // menu sections, as titles: "Emu_Imager | Alpha,Zed"
    NSString *(^menu)(NSArray<NSString *> *) = ^(NSArray<NSString *> *names) {
        NSMutableArray *urls = [NSMutableArray array], *sections = [NSMutableArray array];
        for (NSString *n in names) [urls addObject:[dir URLByAppendingPathComponent:n]];
        for (NSArray<NSURL *> *g in [EDAddOns menuGroups:urls]) {
            NSMutableArray *t = [NSMutableArray array]; for (NSURL *u in g) [t addObject:[EDAddOns titleFor:u]];
            [sections addObject:[t componentsJoinedByString:@","]];
        }
        return [sections componentsJoinedByString:@" | "];
    };
    CHECK([menu(@[@"Alpha.app", @"Emu_Imager.app", @"Zed.app"]) isEqualToString:@"Emu_Imager | Alpha,Zed"], "Imager first, others below a separator");
    CHECK([menu(@[@"Emu_Imager.app"]) isEqualToString:@"Emu_Imager"], "Imager alone, no separator");
    CHECK([menu(@[@"Alpha.app", @"Zed.app"]) isEqualToString:@"Alpha,Zed"], "no Imager, no separator");
    CHECK([EDAddOns menuGroups:@[]].count == 0, "nothing installed");
    NSURL *imager = [dir URLByAppendingPathComponent:@"Emu_Imager.app"], *other = [dir URLByAppendingPathComponent:@"Alpha.app"];
    CHECK(([[EDAddOns removableApps:@[other, imager]] isEqualToArray:@[other]]), "removing keeps the Imager");
    CHECK([EDAddOns removableApps:@[imager]].count == 0, "nothing to remove with the Imager alone");
    [fm removeItemAtURL:dir error:nil];
    printf(fails ? "%d FAILED\n" : "all ok\n", fails); return fails ? 1 : 0;
} }
