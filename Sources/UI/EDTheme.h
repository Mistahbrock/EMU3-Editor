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
/// The sampler's Master > Setup > Contrast (-8 ... +7). 0 = the stock look; lower fades the ink into the screen, higher makes the screen paler.
+ (NSInteger)lcdContrast;
/// Sets the contrast and recolours every green screen in all open windows.
+ (void)setLcdContrast:(NSInteger)c;
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
/// Lays a click-through glass reflection over a green LCD view. Call it after the view's other subviews are added.
+ (void)addGlareTo:(NSView *)host;
/// Wraps a scroll view holding an LCD list in a view that adds that black frame (rounded, click-through). Use the returned view in the layout.
+ (NSView *)framedLCD:(NSScrollView *)s;
/// The same frame with a row of keys inside it, under the list.
+ (NSView *)framedLCD:(NSView *)s footer:(NSView *)footer;
+ (void)styleLCDMenu:(NSMenu *)m;
/// Same look for the dropdown list of a popup button (call after its items are added).
+ (void)styleLCDPopup:(NSPopUpButton *)p;
+ (void)styleWindow:(NSWindow *)w;
/// Sampler-style modal dialogs (green LCD box, "?" or "!" glyph, soft buttons). Returns YES for OK.
+ (BOOL)confirm:(NSString *)message okTitle:(NSString *)ok cancelTitle:(NSString *)cancel;
/// A soft-key style button for the LCD: outlined, filled with ink while its state is On.
+ (NSButton *)lcdButton:(NSString *)title target:(nullable id)target action:(nullable SEL)action;
/// A green LCD-coloured key for the dark window (filled green, black outline).
+ (void)styleLCDField:(NSTextField *)t;                      // ink on a slightly darker green, no bezel
+ (NSTextField *)lcdLabel:(NSString *)s size:(CGFloat)pt;
+ (NSView *)lcdScreenAround:(NSView *)content;                // green framed screen around a stack of controls
+ (NSButton *)lcdKey:(NSString *)title target:(nullable id)target action:(nullable SEL)action;
/// Returns the index of the pressed button (the last one is the default); -1 for Esc.
+ (NSInteger)choose:(NSString *)message buttons:(NSArray<NSString *> *)titles;
+ (void)notice:(NSString *)message;
@end

/// The sampler's vertical page label (hatched strip with stacked letters), e.g. D I S K.
@interface EDLCDSideTab : NSView
- (instancetype)initWithTitle:(NSString *)title;
@end

NS_ASSUME_NONNULL_END

/// A popup button that also answers the mouse wheel / trackpad scroll like the sampler's data wheel:
/// scroll up = next entry, scroll down = previous entry, and the popup's action fires for each step.
@interface EDWheelPopUp : NSPopUpButton
@end
