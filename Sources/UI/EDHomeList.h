// EDHomeList — the "Open" list on the Master tab: banks on the mounted sampler disk, then recently opened files.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@interface EDHomeList : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, readonly) NSTableView *table;
@property (nonatomic, copy, nullable) void (^onOpen)(NSURL *url);
/// Rescans `diskFolder` (nil when no sampler disk is mounted) and the recent files.
- (void)reloadWithSamplerDisk:(nullable NSURL *)diskFolder;
+ (void)noteRecent:(NSURL *)url;
@end
NS_ASSUME_NONNULL_END
