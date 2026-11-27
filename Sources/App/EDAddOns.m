#import "EDAddOns.h"

@implementation EDAddOns
+ (NSURL *)folder {
    NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [[base URLByAppendingPathComponent:@"EMU3 Editor" isDirectory:YES] URLByAppendingPathComponent:@"Add Ons" isDirectory:YES];
}
+ (NSArray<NSURL *> *)appsInFolder:(NSURL *)folder {
    NSArray<NSURL *> *items = [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    NSPredicate *isApp = [NSPredicate predicateWithBlock:^BOOL(NSURL *u, NSDictionary *b) { return [u.pathExtension caseInsensitiveCompare:@"app"] == NSOrderedSame; }];
    return [[items ?: @[] filteredArrayUsingPredicate:isApp] sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) { return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent]; }];
}
+ (NSString *)titleFor:(NSURL *)app { return app.lastPathComponent.stringByDeletingPathExtension; }
+ (BOOL)isImager:(NSURL *)app { return [[self titleFor:app] isEqualToString:@"Emu_Imager"]; }
+ (NSArray<NSURL *> *)removableApps:(NSArray<NSURL *> *)apps {
    return [apps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *u, NSDictionary *b) { return ![self isImager:u]; }]];
}
+ (NSArray<NSArray<NSURL *> *> *)menuGroups:(NSArray<NSURL *> *)apps {
    NSMutableArray<NSURL *> *imager = [NSMutableArray array], *others = [NSMutableArray array];
    for (NSURL *u in apps) [([self isImager:u] ? imager : others) addObject:u];
    NSMutableArray<NSArray<NSURL *> *> *groups = [NSMutableArray array];
    if (imager.count) [groups addObject:imager];
    if (others.count) [groups addObject:others];
    return groups;
}
@end
