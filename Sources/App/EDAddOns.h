// EDAddOns — Add Ons are separate apps kept in one folder; the Tools menu lists them and opens them.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface EDAddOns : NSObject
@property (class, nonatomic, readonly) NSURL *folder;     // ~/Library/Application Support/EMU3 Editor/Add Ons (Add On installers put their app here)
+ (NSArray<NSURL *> *)appsInFolder:(NSURL *)folder;       // the .app bundles in it, sorted by name; empty when the folder is missing
+ (NSString *)titleFor:(NSURL *)app;                      // menu title: the file name without .app
+ (NSArray<NSArray<NSURL *> *> *)menuGroups:(NSArray<NSURL *> *)apps;   // menu sections: Emu_Imager (comes with the editor), then the others in the given order; no empty sections
+ (NSArray<NSURL *> *)removableApps:(NSArray<NSURL *> *)apps;           // what Settings may remove: all but Emu_Imager
@end
NS_ASSUME_NONNULL_END
