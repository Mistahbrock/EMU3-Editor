// EDAlert — the editor's dialog box, styled like the About window: titled dark panel, app icon, bold heading, text, optional
// accessory view and buttons. Same shape as NSAlert for what the editor uses (first button = Return, "Cancel" = Esc).
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@interface EDAlert : NSObject
@property (copy) NSString *messageText;
@property (copy) NSString *informativeText;
@property (nullable, strong) NSView *accessoryView;
@property (nullable, weak) NSView *initialFirstResponder;
@property NSAlertStyle alertStyle;    // kept for call-site compatibility
- (void)addButtonWithTitle:(NSString *)title;
/// Returns NSAlertFirstButtonReturn + the index of the pressed button.
- (NSModalResponse)runModal;
@end
NS_ASSUME_NONNULL_END
