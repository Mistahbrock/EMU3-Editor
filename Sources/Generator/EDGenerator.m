#import "EDGenerator.h"

@implementation EDGeneratedSample
@end

@implementation EDGeneratorRegistry
+ (NSURL *)defaultAddOnFolder {
    NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [[base URLByAppendingPathComponent:@"EMU3 Editor" isDirectory:YES] URLByAppendingPathComponent:@"Add Ons" isDirectory:YES];
}
+ (NSURL *)addOnFolder {   // Settings ▸ Add Ons can point it elsewhere
    NSString *custom = [NSUserDefaults.standardUserDefaults stringForKey:@"AddOnFolder"];
    if (custom.length) return [NSURL fileURLWithPath:custom isDirectory:YES];
    NSString *disk = [NSUserDefaults.standardUserDefaults stringForKey:@"FixedFolderDisk"];   // Settings ▸ Disk images: Add Ons live in a subfolder of it
    return disk.length ? [[NSURL fileURLWithPath:disk isDirectory:YES] URLByAppendingPathComponent:@"Add Ons" isDirectory:YES] : [self defaultAddOnFolder];
}
static NSArray *classesNamed(NSArray<NSString *> *names) {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *n in names) { Class c = NSClassFromString(n); if (c && [c conformsToProtocol:@protocol(EDGeneratorPlugin)]) [a addObject:c]; }
    return a;
}
+ (NSArray<Class<EDGeneratorPlugin>> *)builtInGenerators { return classesNamed(@[@"EDSimpleTonesGenerator"]); }
+ (NSArray<Class<EDGeneratorPlugin>> *)addOns {
    static NSArray *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *a = [classesNamed(@[@"EDOrganGenerator", @"EDFractalGenerator"]) mutableCopy];   // shipped as Add Ons for now
        NSArray<NSURL *> *items = [NSFileManager.defaultManager contentsOfDirectoryAtURL:[self addOnFolder] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
        for (NSURL *u in [items sortedArrayUsingComparator:^NSComparisonResult(NSURL *x, NSURL *y) { return [x.lastPathComponent compare:y.lastPathComponent]; }]) {
            if (![u.pathExtension isEqualToString:@"addon"]) continue;
            NSBundle *b = [NSBundle bundleWithURL:u];
            if (!b || ![b load]) { NSLog(@"Add On %@ could not be loaded", u.lastPathComponent); continue; }
            Class c = b.principalClass;
            if (c && [c conformsToProtocol:@protocol(EDGeneratorPlugin)]) [a addObject:c]; else NSLog(@"Add On %@ has no EDGeneratorPlugin principal class", u.lastPathComponent);
        }
        list = a;
    });
    return list;
}
+ (NSArray<Class<EDGeneratorPlugin>> *)generators { return [[self builtInGenerators] arrayByAddingObjectsFromArray:[self addOns]]; }
@end
