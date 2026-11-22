// EDFrontPanel — the app's home window: a scalable, drawn E64-style front panel whose LCD shows the open bank and whose
// buttons, soft keys, data wheel, keypad and floppy slot drive the editor windows. GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>

@class EDMainWindowController;

NS_ASSUME_NONNULL_BEGIN

@interface EDFrontPanelController : NSWindowController <NSWindowDelegate>
- (instancetype)initWithEditor:(EDMainWindowController *)editor;
- (void)showPanel;
@end

NS_ASSUME_NONNULL_END
