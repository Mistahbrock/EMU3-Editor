// EDHomeList — the "Open" list on the Master tab: banks on the mounted sampler disk, then recently opened files.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@interface EDHomeList : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate>
@property (nonatomic, readonly) NSTableView *table;
@property (nonatomic, copy, nullable) void (^onOpen)(NSURL *url);
@property (nonatomic, copy, nullable) void (^onConvert)(NSURL *url);   // right-click ▸ Convert (only offered for Emulator 3X / ESI-32 banks)
/// Rescans `diskFolder` (nil when no sampler disk is mounted) and the recent files.
- (void)reloadWithSamplerDisk:(nullable NSURL *)diskFolder;
+ (void)noteRecent:(NSURL *)url;
@end
NS_ASSUME_NONNULL_END
