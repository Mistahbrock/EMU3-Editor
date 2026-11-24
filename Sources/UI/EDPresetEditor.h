// EDPresetEditor — preset list, voice/sample tree and parameter table. GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>
#import "EDBank.h"

NS_ASSUME_NONNULL_BEGIN
@interface EDPresetEditor : NSView <NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate, NSMenuDelegate, NSSplitViewDelegate>
@property (nonatomic, strong, nullable) EDBank *bank;
@property (nonatomic, readonly) NSView *lcdView;   // the LCD page view (for aligning outside notes)
@property (nonatomic, copy, nullable) void (^edited)(void);     // called after every change
@property (nonatomic, copy, nullable) void (^selectionChanged)(void);
@property (nonatomic, strong, nullable) NSMenu *presetMenu;                 // right-click menu of the preset list; the clicked row is selected first
@property (nonatomic, copy, nullable) void (^presetCountChanged)(void);   // a preset was added, deleted or restored
@property (nonatomic, readonly) NSInteger selectedIndex;     // row of the selected preset, -1 when none
- (void)selectIndex:(NSInteger)i;
/// The sampler's Enter / Exit keys for the Presets page: Enter goes one level in (preset list → preset → voice → zone), Exit one level out.
/// YES when the key was used; NO means the caller should do what Exit/Enter normally does (go back a page).
- (BOOL)handleEnter;
- (BOOL)handleExit;
- (void)reload;
- (void)deletePresetFromMenu:(id)s;
- (void)removePresetObject:(EDPreset *)p;   // undoable
/// Deletes several presets as one undo step.
- (void)removePresets:(NSArray<EDPreset *> *)ps;
/// Opens the "Fit presets to memory" window: sizes, duplicate finder, and removal until the presets fit `limitK` kilobytes.
- (void)presentFitToMemoryLimitK:(double)limitK;
- (void)newPreset:(nullable id)sender;   // adds an empty preset to the open bank (Preset Manage > New)
/// Plays `key` on the selected preset until -endAudition (the Space-bar audition on the Presets page). NO when there is no preset to play.
- (BOOL)auditionKey:(int)key;
- (void)endAudition;
@end
NS_ASSUME_NONNULL_END
