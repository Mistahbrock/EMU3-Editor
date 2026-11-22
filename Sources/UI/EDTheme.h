// EDTheme — the E64 front-panel look shared by the front panel window and the editor windows.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Table for cell-based LCD lists, which draw their own selection: a darker patch of the LCD green.
@interface EDLCDTableView : NSTableView
@end

@interface EDTheme : NSObject
+ (NSColor *)body;          // charcoal panel
+ (NSColor *)bodyDark;
+ (NSColor *)accent;        // the red stripe
+ (NSColor *)lcdBackground; // pale green-blue
+ (NSColor *)lcdInk;        // blue-black
+ (NSColor *)labelWhite;
+ (NSColor *)logoBlue;       // the EMU wordmark
+ (NSFont *)lcdFont:(CGFloat)size;
+ (NSFont *)panelFont:(CGFloat)size;
/// Dark window appearance and body colour for an editor window.
/// LCD look for a list: pale green-blue background, dark ink, thin rules, no striping. Call after the columns exist.
+ (void)styleLCDTable:(NSTableView *)t;
/// The one text style of every LCD list row: semibold system font in the LCD ink.
/// Row view for LCD lists: a selection that is not the active one is drawn as a darker patch of the LCD green.
+ (NSTableRowView *)lcdRowView;
+ (void)styleLCDText:(NSTextField *)f;
+ (NSTextField *)lcdLabel:(NSString *)s;
/// Gives a context menu the LCD look: green rows, ink text, a darker green under the pointer.
/// Thickness of the black frame around every green LCD window.
+ (CGFloat)lcdFrameWidth;
/// Wraps a scroll view holding an LCD list in a view that adds that black frame (rounded, click-through). Use the returned view in the layout.
+ (NSView *)framedLCD:(NSScrollView *)s;
+ (void)styleLCDMenu:(NSMenu *)m;
/// Same look for the dropdown list of a popup button (call after its items are added).
+ (void)styleLCDPopup:(NSPopUpButton *)p;
+ (void)styleWindow:(NSWindow *)w;
/// Sampler-style modal dialogs (green LCD box, "?" or "!" glyph, soft buttons). Returns YES for OK.
+ (BOOL)confirm:(NSString *)message okTitle:(NSString *)ok cancelTitle:(NSString *)cancel;
+ (void)notice:(NSString *)message;
@end

NS_ASSUME_NONNULL_END
