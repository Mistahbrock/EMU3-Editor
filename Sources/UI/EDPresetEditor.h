// EDPresetEditor — preset list, voice/sample tree and parameter table. GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>
#import "EDBank.h"

NS_ASSUME_NONNULL_BEGIN
@interface EDPresetEditor : NSView <NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate, NSMenuDelegate>
@property (nonatomic, strong, nullable) EDBank *bank;
@property (nonatomic, copy, nullable) void (^edited)(void);     // called after every change
@property (nonatomic, copy, nullable) void (^selectionChanged)(void);
@property (nonatomic, strong, nullable) NSMenu *presetMenu;                 // right-click menu of the preset list; the clicked row is selected first
@property (nonatomic, copy, nullable) void (^presetCountChanged)(void);   // a preset was added, deleted or restored
@property (nonatomic, readonly) NSInteger selectedIndex;     // row of the selected preset, -1 when none
- (void)selectIndex:(NSInteger)i;
- (void)reload;
@end
NS_ASSUME_NONNULL_END
