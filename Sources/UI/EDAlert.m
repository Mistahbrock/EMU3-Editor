#import "EDAlert.h"
#import "EDTheme.h"

// Esc = Cancel when the dialog has one, or the only button; a title-bar close works as before.
@interface EDAlertPanel : NSPanel
@property (weak) NSArray<NSButton *> *escButtons;
@end
@implementation EDAlertPanel
- (void)cancelOperation:(id)s {
    NSButton *pick = nil; for (NSButton *b in _escButtons) if ([b.title isEqualToString:@"Cancel"]) pick = b;
    if (!pick && _escButtons.count == 1) pick = _escButtons.firstObject;
    if (pick) [pick performClick:nil];
}
@end

@implementation EDAlert { NSMutableArray<NSString *> *_buttons; NSPanel *_panel; BOOL _answered; }
- (instancetype)init { if ((self = [super init])) { _buttons = [NSMutableArray array]; _messageText = @""; _informativeText = @""; } return self; }
- (void)addButtonWithTitle:(NSString *)title { [_buttons addObject:title]; }
- (void)pressed:(NSButton *)b { _answered = YES; [NSApp stopModalWithCode:NSAlertFirstButtonReturn + b.tag]; [_panel close]; }
- (NSModalResponse)runModal {
    if (!_buttons.count) [_buttons addObject:@"OK"];
    NSImageView *iv = [NSImageView imageViewWithImage:[NSImage imageNamed:NSImageNameApplicationIcon]];
    [iv.widthAnchor constraintEqualToConstant:64].active = YES; [iv.heightAnchor constraintEqualToConstant:64].active = YES;
    NSTextField *title = [NSTextField wrappingLabelWithString:_messageText]; title.font = [NSFont boldSystemFontOfSize:15]; title.alignment = NSTextAlignmentCenter;
    NSMutableArray *views = [NSMutableArray arrayWithObjects:iv, title, nil];
    CGFloat w = MAX(420, _accessoryView.frame.size.width);
    title.preferredMaxLayoutWidth = w; [title.widthAnchor constraintLessThanOrEqualToConstant:w].active = YES;
    if (_informativeText.length) {
        NSTextField *info = [NSTextField wrappingLabelWithString:_informativeText]; info.font = [NSFont systemFontOfSize:11]; info.textColor = EDTheme.labelWhite; info.alignment = NSTextAlignmentCenter;
        info.preferredMaxLayoutWidth = w; [info.widthAnchor constraintLessThanOrEqualToConstant:w].active = YES; [views addObject:info];
    }
    if (_accessoryView) { _accessoryView.translatesAutoresizingMaskIntoConstraints = NO; [_accessoryView.widthAnchor constraintEqualToConstant:_accessoryView.frame.size.width].active = YES; [_accessoryView.heightAnchor constraintEqualToConstant:_accessoryView.frame.size.height].active = YES; [views addObject:_accessoryView]; }
    NSMutableArray *bs = [NSMutableArray array];
    for (NSUInteger i = _buttons.count; i-- > 0;) {   // right to left: default button on the right
        NSButton *b = [NSButton buttonWithTitle:_buttons[i] target:self action:@selector(pressed:)]; b.tag = (NSInteger)i; b.bezelStyle = NSBezelStyleRegularSquare;
        if (i == 0) b.keyEquivalent = @"\r"; else if ([_buttons[i] isEqualToString:@"Cancel"]) b.keyEquivalent = @"\033";
        [bs addObject:b];
    }
    NSStackView *row = [NSStackView stackViewWithViews:bs]; row.spacing = 10; [views addObject:row];
    NSStackView *st = [NSStackView stackViewWithViews:views];
    st.orientation = NSUserInterfaceLayoutOrientationVertical; st.alignment = NSLayoutAttributeCenterX; st.spacing = 14;
    [st setCustomSpacing:24 afterView:views[views.count - 2]]; st.edgeInsets = NSEdgeInsetsMake(28, 44, 26, 44);
    _panel = [[EDAlertPanel alloc] initWithContentRect:NSMakeRect(0, 0, 380, 200) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    _panel.title = @"EMU3 Editor"; _panel.releasedWhenClosed = NO; _panel.contentView = st;
    [_panel setContentSize:st.fittingSize]; [_panel center]; ((EDAlertPanel *)_panel).escButtons = bs;
    if (_initialFirstResponder) _panel.initialFirstResponder = _initialFirstResponder;
    __block id tok = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification object:_panel queue:nil usingBlock:^(NSNotification *n) {
        [NSNotificationCenter.defaultCenter removeObserver:tok]; if (!self->_answered && NSApp.modalWindow == self->_panel) [NSApp stopModalWithCode:NSModalResponseCancel + 10000]; }];
    [_panel makeKeyAndOrderFront:nil];
    NSModalResponse r = [NSApp runModalForWindow:_panel];
    // window closed with the title-bar button = last button (Cancel) / the only one
    if (r == NSModalResponseCancel + 10000) r = NSAlertFirstButtonReturn + (NSInteger)_buttons.count - 1;
    return r;
}
@end
