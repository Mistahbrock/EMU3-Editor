// EDDiskIcons — the Disk page's drive icons (hard disk, CD, floppy) drawn like the sampler's Disk screen.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, EDDiskKind) { EDDiskHard, EDDiskCD, EDDiskFloppy };
@interface EDDiskItem : NSObject
@property (nonatomic) EDDiskKind kind;
@property (nonatomic, copy) NSString *title, *subtitle;
@property (nonatomic, strong, nullable) NSURL *url;
@property (nonatomic) BOOL sampler;        // the disk the sampler sees (Disk Manager's served volume)
@end

@interface EDDiskIcons : NSView
@property (nonatomic, copy) NSArray<EDDiskItem *> *items;
@property (nonatomic, copy, nullable) void (^onOpen)(EDDiskItem *item);
@end
NS_ASSUME_NONNULL_END
