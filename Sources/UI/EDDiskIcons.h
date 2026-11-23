// EDDiskIcons — the Disk page's icon browser, drawn like the sampler's Disk / Folder / Bank screens:
// pixel-art icons (hard disk, CD, floppy, folder, bank) with the name under each; the selected one is filled.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, EDDiskKind) { EDDiskHard, EDDiskCD, EDDiskFloppy, EDDiskFolder, EDDiskBank, EDDiskSample };
@interface EDDiskItem : NSObject
@property (nonatomic) EDDiskKind kind;
@property (nonatomic, copy) NSString *title, *subtitle;
@property (nonatomic, strong, nullable) NSURL *url;
@property (nonatomic, strong, nullable) id node;   // the folder / bank this icon stands for
@property (nonatomic, copy, nullable) NSString *tag;   // list view: "S001" in front of the name
@property (nonatomic) BOOL loop;                      // list view: loop marker behind the name
@property (nonatomic) BOOL sampler;        // the disk the sampler sees (Disk Manager's served volume)
@end

@interface EDDiskIcons : NSView
@property (nonatomic, copy) NSArray<EDDiskItem *> *items;
@property (nonatomic) NSInteger selectedIndex;                              // -1 = none
@property (nonatomic, readonly, nullable) EDDiskItem *selectedItem;
@property (nonatomic, copy, nullable) void (^onSelect)(EDDiskItem *item);   // single click / arrow keys
@property (nonatomic, copy, nullable) void (^onOpen)(EDDiskItem *item);     // double-click / Return
@property (nonatomic, copy, nullable) void (^onExit)(void);                 // Escape: back out one level
@property (nonatomic, copy) NSString *emptyText;
/// Union of the icon/row rectangles (view coordinates); NSZeroRect when empty.
- (NSRect)usedRect;
/// Easter egg: makes item `index` jump and flash as if pecked (index -1 stops it).
- (void)setPecked:(NSInteger)index;
/// One rectangle per item (view coordinates).
- (NSArray<NSValue *> *)itemRects;
/// Extra space below the last row, for something drawn over the bottom of the panel (the scroll bar still runs the full height).
@property (nonatomic) CGFloat bottomPad;
@property (nonatomic) BOOL listMode;     // View key: small icon + "S001 name" rows in columns, like the sampler's list view
@end
NS_ASSUME_NONNULL_END
