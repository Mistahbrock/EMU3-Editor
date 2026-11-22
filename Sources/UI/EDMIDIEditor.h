// EDMIDIEditor — the MIDI tab: the MIDI A–D fields of every preset in one table. GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>
#import "EDBank.h"

NS_ASSUME_NONNULL_BEGIN
@interface EDMIDIEditor : NSView <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong, nullable) EDBank *bank;
@property (nonatomic, copy, nullable) void (^edited)(void);     // called after every change
@property (nonatomic, copy, nullable) void (^action)(NSString *name);   // "erasePresets", "saveAs"
@property (nonatomic, copy, nullable) NSString *bankTitle;
- (void)reload;
/// "MIDI", "Setup" or "Bank": which of the sampler's Master menus the soft keys show.
- (void)setMenu:(NSString *)menu;
@end
NS_ASSUME_NONNULL_END
