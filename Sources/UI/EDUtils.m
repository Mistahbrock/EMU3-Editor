#import "EDUtils.h"
#import "EDTheme.h"
#import "EDSamplerRemote.h"
#import <AVFoundation/AVFoundation.h>

// Each screen is an LCD panel like the ones on the sampler. Assign Key keeps a profile (the sampler stores its keys in flash and cannot be read);
// Tones is a real reference-tone generator on the Mac's output; Channel Volume needs live data the sampler only shows on its own display.

// one MIDI channel's multimode volume: a vertical bar you can drag
@interface EDChanBar : NSView
@property (nonatomic) NSInteger channel, value, pan;   // value 0...127, pan -64...63
@property (nonatomic) BOOL live;                    // data from the sampler present
@property (nonatomic, copy) void (^onChange)(NSInteger channel, NSInteger value);
@property (nonatomic, copy) void (^onPan)(NSInteger channel, NSInteger pan);
@property (nonatomic, copy) void (^onSelect)(NSInteger channel);
@property (nonatomic) BOOL selected;
@end
@implementation EDChanBar {
    BOOL _dragPan;
}
- (BOOL)isFlipped { return NO; }
- (void)setValue:(NSInteger)v { _value = MAX(0, MIN(127, v)); self.needsDisplay = YES; }
- (void)setPan:(NSInteger)p { _pan = MAX(-64, MIN(63, p)); self.needsDisplay = YES; }
- (void)setLive:(BOOL)l { _live = l; self.needsDisplay = YES; }
- (void)setSelected:(BOOL)s { _selected = s; self.needsDisplay = YES; }
// like the sampler's screen, top to bottom: the channel number, the pan cross, the volume bar
- (NSRect)numRect { return NSMakeRect(0, self.bounds.size.height - 18, self.bounds.size.width, 18); }
- (NSRect)panRect { return NSMakeRect(0.5, self.bounds.size.height - 18 - 4 - 16, self.bounds.size.width - 1, 16); }
- (NSRect)barRect { return NSMakeRect(0.5, 2.5, self.bounds.size.width - 1, self.bounds.size.height - 18 - 4 - 16 - 6 - 2); }
- (void)drawRect:(NSRect)dirty {
    NSRect r = [self barRect], pr = [self panRect], nr = [self numRect]; NSColor *ink = EDTheme.lcdInk;
    NSDictionary *at = @{NSFontAttributeName: [EDTheme lcdFont:12], NSForegroundColorAttributeName: ink};
    NSString *n = [NSString stringWithFormat:@"%ld", (long)_channel];
    if (_selected) { [ink setFill]; NSRectFill(nr); at = @{NSFontAttributeName: [EDTheme lcdFont:12], NSForegroundColorAttributeName: EDTheme.lcdBackground}; }
    NSSize ns = [n sizeWithAttributes:at]; [n drawAtPoint:NSMakePoint(NSMidX(nr) - ns.width / 2, NSMinY(nr) + 2) withAttributes:at];
    [ink setStroke]; NSBezierPath *nb = [NSBezierPath bezierPathWithRect:NSInsetRect(nr, 0.5, 0.5)]; nb.lineWidth = 1; [nb stroke];
    NSBezierPath *f = [NSBezierPath bezierPathWithRect:r]; f.lineWidth = 1; [f stroke];
    if (!_live) return;
    CGFloat h = round((r.size.height - 4) * _value / 127.0);
    [[ink colorWithAlphaComponent:0.85] setFill]; NSRectFill(NSMakeRect(r.origin.x + 3, r.origin.y + 2, r.size.width - 6, h));
    // pan: the strip's axis with a cross where the sound sits (the sampler's "+" shape); the centre is marked
    CGFloat inner = pr.size.width - 4, cx = pr.origin.x + 2 + inner / 2, px = pr.origin.x + 2 + inner * (_pan + 64) / 127.0, my = NSMidY(pr);
    [[ink colorWithAlphaComponent:0.35] setFill]; NSRectFill(NSMakeRect(pr.origin.x + 2, my - 0.5, inner, 1)); NSRectFill(NSMakeRect(cx - 0.5, my - 5, 1, 10));
    [ink setFill]; NSRectFill(NSMakeRect(px - 5, my - 1, 10, 2)); NSRectFill(NSMakeRect(px - 1, my - 6, 2, 12));
}
- (void)setFromEvent:(NSEvent *)e {
    if (!_live) return; NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    if (_dragPan) {
        NSRect pr = [self panRect]; NSInteger v = (NSInteger)lround((p.x - pr.origin.x - 2) / (pr.size.width - 4) * 127.0) - 64; v = MAX(-64, MIN(63, v));
        if (labs(v) <= 2) v = 0;     // a little magnet at the centre
        if (v != _pan) { self.pan = v; if (_onPan) _onPan(_channel, v); }
        return;
    }
    NSRect r = [self barRect];
    NSInteger v = (NSInteger)lround((p.y - r.origin.y - 2) / (r.size.height - 4) * 127.0); v = MAX(0, MIN(127, v));
    if (v != _value) { self.value = v; if (_onChange) _onChange(_channel, v); }
}
- (void)mouseDown:(NSEvent *)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    [self.window makeFirstResponder:nil]; if (_onSelect) _onSelect(_channel);   // a click leaves any text box, so the arrow keys work
    _dragPan = p.y >= NSMinY([self panRect]) - 2 && p.y < NSMinY([self numRect]);   // the strip under the number is pan; double-click puts it back to the centre
    if (_dragPan && e.clickCount >= 2 && _live) { self.pan = 0; if (_onPan) _onPan(_channel, 0); return; }
    [self setFromEvent:e];
}
- (void)mouseDragged:(NSEvent *)e { [self setFromEvent:e]; }
@end

@interface EDUtils ()
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, weak) NSWindow *parent;
@end

@implementation EDUtils {
    AVAudioEngine *_engine; AVAudioSourceNode *_source; BOOL _playing;
    double _freq, _phase, _amp; NSInteger _wave;
    NSButton *_playBtn, *_doneBtn; NSLayoutConstraint *_doneCenterX;
    NSTextField *_presetField, *_yField, *_pField; void (^_presetSet)(NSInteger); NSArray *_chanBars; NSInteger (^_selChannel)(void); id _keyMonitor;
}
static EDUtils *sCurrent;   // keeps the open sheet alive

+ (void)presentTitle:(NSString *)title in:(NSWindow *)w build:(void (^)(EDUtils *u, NSView *screen))build {
    EDUtils *u = [EDUtils new]; sCurrent = u; u.parent = w; u->_freq = 1000; u->_amp = 0.1;
    NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 780, 430) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    [EDTheme styleWindow:p]; u.panel = p;
    NSView *content = p.contentView;
    NSView *screen = [NSView new]; screen.wantsLayer = YES; screen.layer.backgroundColor = EDTheme.lcdBackground.CGColor; screen.layer.cornerRadius = 0;
    screen.layer.borderWidth = EDTheme.lcdFrameWidth; screen.layer.borderColor = NSColor.blackColor.CGColor; screen.translatesAutoresizingMaskIntoConstraints = NO; [content addSubview:screen];
    NSTextField *t = [NSTextField labelWithString:title]; t.font = [EDTheme lcdFont:26]; t.textColor = EDTheme.lcdInk; t.translatesAutoresizingMaskIntoConstraints = NO; [screen addSubview:t];
    NSButton *close = [EDTheme lcdKey:@"Done" target:u action:@selector(done:)]; close.keyEquivalent = @"\r"; close.toolTip = @"Close this panel."; close.translatesAutoresizingMaskIntoConstraints = NO; [screen addSubview:close];
    [NSLayoutConstraint activateConstraints:@[
        [screen.topAnchor constraintEqualToAnchor:content.topAnchor constant:20], [screen.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [screen.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20], [screen.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20],
        [t.topAnchor constraintEqualToAnchor:screen.topAnchor constant:14], [t.centerXAnchor constraintEqualToAnchor:screen.centerXAnchor],
        [(u->_doneCenterX = [close.centerXAnchor constraintEqualToAnchor:screen.centerXAnchor]) self], [close.widthAnchor constraintEqualToConstant:110], [close.heightAnchor constraintEqualToConstant:30], [close.bottomAnchor constraintEqualToAnchor:screen.bottomAnchor constant:-16]]];
    u->_doneBtn = close;
    build(u, screen);
    [EDTheme addGlareTo:screen];        // the same glass reflection as the other LCD panels
    [w beginSheet:p completionHandler:^(NSModalResponse r) { [u removeKeyMonitor]; [u stopTone]; sCurrent = nil; }];
    [p makeFirstResponder:nil];        // no text box active at the start, so the keys reach the panel
}
- (void)removeKeyMonitor { if (_keyMonitor) { [NSEvent removeMonitor:_keyMonitor]; _keyMonitor = nil; } }
- (void)done:(id)s { [self removeKeyMonitor]; [self stopTone]; [self.parent endSheet:self.panel]; }

static NSTextField *lcdText(NSString *s, CGFloat size) { NSTextField *t = [NSTextField labelWithString:s]; t.font = [EDTheme lcdFont:size]; t.textColor = EDTheme.lcdInk; return t; }
static NSPopUpButton *lcdPopup(NSArray<NSString *> *items, NSString *sel) {
    NSPopUpButton *pop = [[EDWheelPopUp alloc] initWithFrame:NSZeroRect pullsDown:NO]; pop.bordered = NO; pop.font = [EDTheme lcdFont:17]; pop.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];   // dark arrows on the green
    NSDictionary *attr = @{NSFontAttributeName: [EDTheme lcdFont:17], NSForegroundColorAttributeName: EDTheme.lcdInk};
    for (NSString *o in items) { NSMenuItem *mi = [pop.menu addItemWithTitle:o action:nil keyEquivalent:@""]; mi.attributedTitle = [[NSAttributedString alloc] initWithString:o attributes:attr]; }
    [EDTheme styleLCDPopup:pop]; if (sel) [pop selectItemWithTitle:sel];
    pop.toolTip = @"Click to choose, or scroll over it to step through the values."; [pop.widthAnchor constraintGreaterThanOrEqualToConstant:170].active = YES; return pop;
}
static void place(NSView *screen, NSView *v, CGFloat top) {
    v.translatesAutoresizingMaskIntoConstraints = NO; [screen addSubview:v];
    [NSLayoutConstraint activateConstraints:@[[v.topAnchor constraintEqualToAnchor:screen.topAnchor constant:top], [v.leadingAnchor constraintEqualToAnchor:screen.leadingAnchor constant:40]]];
}

// MARK: Assign Key

+ (void)showAssignKeysIn:(NSWindow *)w {
    NSArray *screens = @[@"Memory", @"Bank", @"Sample Manage", @"Sample Edit", @"Preset Manage", @"Preset Edit", @"MIDI Mode", @"MIDI Controllers 1", @"MIDI Controllers 2",
                         @"MIDI Preferences 1", @"MIDI Preferences 2", @"Tones", @"Channel Volume", @"Sequencer"];
    NSArray *names = @[@"Key 1", @"Key 2", @"Key 3", @"Shift + Key 1", @"Shift + Key 2", @"Shift + Key 3"];
    NSDictionary *def = @{@"Key 1": @"Sample Manage", @"Key 2": @"Preset Manage", @"Key 3": @"Memory", @"Shift + Key 1": @"MIDI Mode", @"Shift + Key 2": @"Tones", @"Shift + Key 3": @"Channel Volume"};
    NSMutableDictionary *saved = [([NSUserDefaults.standardUserDefaults dictionaryForKey:@"SamplerAssignKeys"] ?: @{}) mutableCopy];
    [self presentTitle:@"Assignable Keys" in:w build:^(EDUtils *u, NSView *screen) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSString *n in names) {
            NSPopUpButton *p = lcdPopup(screens, saved[n] ?: def[n]); p.identifier = n; p.target = u; p.action = @selector(assignChanged:);
            NSStackView *r = [NSStackView stackViewWithViews:@[lcdText(n, 17), p]]; r.spacing = 16; [(NSTextField *)r.views[0] setPreferredMaxLayoutWidth:200];
            [r.views[0].widthAnchor constraintEqualToConstant:210].active = YES; [rows addObject:r];
        }
        NSStackView *col = [NSStackView stackViewWithViews:rows]; col.orientation = NSUserInterfaceLayoutOrientationVertical; col.alignment = NSLayoutAttributeLeading; col.spacing = 10;
        place(screen, col, 70);
        NSTextField *note = [NSTextField ed_wrappingLabelWithString:@"The sampler stores its assignable keys in its own memory and cannot be read from here. Set them to match, or use this as a reference sheet."];
        note.font = [NSFont systemFontOfSize:11]; note.textColor = EDTheme.lcdInk; note.translatesAutoresizingMaskIntoConstraints = NO; [screen addSubview:note];
        [NSLayoutConstraint activateConstraints:@[[note.leadingAnchor constraintEqualToAnchor:screen.leadingAnchor constant:40], [note.trailingAnchor constraintEqualToAnchor:screen.trailingAnchor constant:-40], [note.bottomAnchor constraintEqualToAnchor:screen.bottomAnchor constant:-58]]];
    }];
}
- (void)assignChanged:(NSPopUpButton *)p {
    NSMutableDictionary *d = [([NSUserDefaults.standardUserDefaults dictionaryForKey:@"SamplerAssignKeys"] ?: @{}) mutableCopy];
    d[p.identifier] = p.titleOfSelectedItem; [NSUserDefaults.standardUserDefaults setObject:d forKey:@"SamplerAssignKeys"];
}

// MARK: Channel Volume

+ (void)showChannelVolumeIn:(NSWindow *)w {
    [self presentTitle:@"Channel Volume" in:w build:^(EDUtils *u, NSView *screen) {
        NSTextField *status = [NSTextField ed_wrappingLabelWithString:@"Reading the sampler…"];
        status.font = [NSFont systemFontOfSize:12]; status.textColor = EDTheme.lcdInk; status.translatesAutoresizingMaskIntoConstraints = NO; [screen addSubview:status];
        [NSLayoutConstraint activateConstraints:@[[status.leadingAnchor constraintEqualToAnchor:screen.leadingAnchor constant:40], [status.trailingAnchor constraintEqualToAnchor:screen.trailingAnchor constant:-40], [status.bottomAnchor constraintEqualToAnchor:screen.bottomAnchor constant:-58]]];
        NSMutableArray<EDChanBar *> *list = [NSMutableArray array]; NSMutableArray<NSNumber *> *presets = [NSMutableArray array];
        NSStackView *bars = [NSStackView new]; bars.spacing = 14; bars.alignment = NSLayoutAttributeBottom;
        // the selected channel: its preset (number and the sampler's name for it)
        NSTextField *chLabel = lcdText(@"Channel 1", 15), *nameLabel = lcdText(@"", 15), *numField = [NSTextField textFieldWithString:@"0"];
        [EDTheme styleLCDField:numField]; numField.font = [EDTheme lcdFont:15]; numField.alignment = NSTextAlignmentCenter; [numField.widthAnchor constraintEqualToConstant:54].active = YES;
        numField.toolTip = @"The preset this MIDI channel plays (0–999; -1 = none). Type a number and press Return, or use − and +.";
        NSButton *minus = [EDTheme lcdKey:@"−" target:nil action:nil], *plus = [EDTheme lcdKey:@"+" target:nil action:nil];
        for (NSButton *k in @[minus, plus]) [k.widthAnchor constraintEqualToConstant:30].active = YES;
        minus.toolTip = @"Previous preset"; plus.toolTip = @"Next preset";
        NSTextField *presetCap = lcdText(@"Preset", 15); [chLabel.widthAnchor constraintEqualToConstant:100].active = YES;
        [nameLabel.widthAnchor constraintGreaterThanOrEqualToConstant:170].active = YES; nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        NSTextField *yField = [NSTextField textFieldWithString:@"127"], *pField = [NSTextField textFieldWithString:@"+0"];
        for (NSTextField *f in @[yField, pField]) { [EDTheme styleLCDField:f]; f.font = [EDTheme lcdFont:15]; f.alignment = NSTextAlignmentCenter; [f.widthAnchor constraintEqualToConstant:52].active = YES; }
        yField.toolTip = @"Volume of the selected channel, 0–127. Type a value and press Return."; pField.toolTip = @"Pan of the selected channel, -64 (left) … +63 (right). Type a value and press Return.";
        u->_yField = yField; u->_pField = pField; yField.target = u; yField.action = @selector(yTyped:); pField.target = u; pField.action = @selector(pTyped:);
        NSStackView *detail = [NSStackView stackViewWithViews:@[chLabel, presetCap, minus, numField, plus, nameLabel, lcdText(@"Y:", 15), yField, lcdText(@"P:", 15), pField]]; detail.spacing = 10; detail.alignment = NSLayoutAttributeCenterY;
        __block NSInteger sel = 0;
        __block void (^showName)(NSInteger) = nil;
        void (^refreshDetail)(void) = ^{
            chLabel.stringValue = [NSString stringWithFormat:@"Channel %ld", (long)sel + 1];
            NSInteger pr = sel < (NSInteger)presets.count ? presets[sel].integerValue : 0;
            numField.stringValue = [NSString stringWithFormat:@"%ld", (long)pr]; showName(pr);
            for (EDChanBar *b in list) b.selected = b.channel == sel + 1;
            EDChanBar *cb = list[sel]; yField.stringValue = [NSString stringWithFormat:@"%ld", (long)cb.value]; pField.stringValue = [NSString stringWithFormat:@"%+ld", (long)cb.pan];
        };
        showName = ^(NSInteger pr) {
            if (pr < 0) { nameLabel.stringValue = @"(no preset)"; return; }
            nameLabel.stringValue = @"…";
            [EDSamplerRemote presetNameForNumber:pr completion:^(NSString *n) { if ([numField.stringValue integerValue] == pr) nameLabel.stringValue = n ?: @"(no answer)"; }];
        };
        void (^setPreset)(NSInteger) = ^(NSInteger pr) {
            pr = MAX(-1, MIN(999, pr)); if (sel < (NSInteger)presets.count) presets[sel] = @(pr);
            numField.stringValue = [NSString stringWithFormat:@"%ld", (long)pr]; showName(pr);
            [EDSamplerRemote setPreset:pr forChannel:sel + 1];
        };
        u->_presetSet = [setPreset copy];
        u->_chanBars = list; u->_selChannel = ^NSInteger { return sel + 1; };
        minus.target = u; minus.action = @selector(presetStep:); minus.tag = -1; plus.target = u; plus.action = @selector(presetStep:); plus.tag = 1;
        numField.target = u; numField.action = @selector(presetTyped:); u->_presetField = numField;
        for (int i = 1; i <= 16; i++) {
            EDChanBar *bar = [EDChanBar new]; bar.channel = i; bar.value = 127; bar.toolTip = [NSString stringWithFormat:@"MIDI channel %d: drag the bar up or down for its multimode volume (0–127); drag the strip under it left or right for pan (double-click = centre). Click to select the channel's preset below.", i];
            [bar.widthAnchor constraintEqualToConstant:30].active = YES; [bar.heightAnchor constraintEqualToConstant:200].active = YES;
            bar.onChange = ^(NSInteger ch, NSInteger v) { [EDSamplerRemote setVolume:v forChannel:ch]; if (ch == sel + 1) yField.stringValue = [NSString stringWithFormat:@"%ld", (long)v]; };
            bar.onPan = ^(NSInteger ch, NSInteger v) { [EDSamplerRemote setPan:v forChannel:ch]; if (ch == sel + 1) pField.stringValue = [NSString stringWithFormat:@"%+ld", (long)v]; };
            bar.onSelect = ^(NSInteger ch) { if (sel != ch - 1) { sel = ch - 1; refreshDetail(); } };
            [bars addArrangedSubview:bar]; [list addObject:bar];
            [presets addObject:@0];
        }
        place(screen, bars, 52);
        detail.translatesAutoresizingMaskIntoConstraints = NO; [screen addSubview:detail];
        [NSLayoutConstraint activateConstraints:@[[detail.topAnchor constraintEqualToAnchor:screen.topAnchor constant:256], [detail.leadingAnchor constraintEqualToAnchor:screen.leadingAnchor constant:40]]];
        list.firstObject.selected = YES;
        // keys, only while this sheet is the key window and no text box is being edited: ⇧▲ ⇧▼ select the channel, ◀ ▶ pan, ▲ ▼ volume
        __weak EDUtils *wu = u;
        u->_keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *e) {
            EDUtils *me = wu; if (!me || e.window != me.panel || [me.panel.firstResponder isKindOfClass:NSText.class]) return e;
            NSUInteger mods = e.modifierFlags & (NSEventModifierFlagShift | NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption);
            BOOL shift = mods == NSEventModifierFlagShift; if (mods && !shift) return e;
            EDChanBar *cb = list[sel];
            switch (e.keyCode) {
                case 123: case 124: {   // left / right: pan (also with ⇧)
                    NSInteger d = e.keyCode == 124 ? 1 : -1;
                    if (!cb.live) return nil; NSInteger v = MAX(-64, MIN(63, cb.pan + d));
                    if (v != cb.pan) { cb.pan = v; pField.stringValue = [NSString stringWithFormat:@"%+ld", (long)v]; [EDSamplerRemote setPan:v forChannel:sel + 1]; }
                    return nil; }
                case 125: case 126: {   // down / up: ⇧ selects the next / previous channel, plain changes the volume
                    if (shift) { NSInteger n = MAX(0, MIN((NSInteger)list.count - 1, sel + (e.keyCode == 125 ? 1 : -1))); if (n != sel) { sel = n; refreshDetail(); } return nil; }
                    if (!cb.live) return nil; NSInteger v = MAX(0, MIN(127, cb.value + (e.keyCode == 126 ? 1 : -1)));
                    if (v != cb.value) { cb.value = v; yField.stringValue = [NSString stringWithFormat:@"%ld", (long)v]; [EDSamplerRemote setVolume:v forChannel:sel + 1]; }
                    return nil; }
            }
            return e; }];
        [EDSamplerRemote readMultimodeWithCompletion:^(NSArray<NSArray<NSNumber *> *> *chans) {
            if (!chans) { status.stringValue = @"No answer from the sampler. Check the MIDI cable and port (Master ▸ MIDI ▸ interface) and that the sampler is on."; return; }
            for (EDChanBar *b in list) { NSInteger i = b.channel - 1; if (i < (NSInteger)chans.count) { b.value = [chans[i][1] integerValue]; b.pan = [chans[i][2] integerValue]; presets[i] = chans[i][0]; b.live = YES; } }
            refreshDetail();
            status.stringValue = @"Volume (bars), pan (strips) and preset of each MIDI channel, read from the sampler. Drag to change them on the sampler; double-click a pan strip for centre.";
        }];
    }];
}
- (void)yTyped:(NSTextField *)f { NSInteger ch = _selChannel ? _selChannel() : 1, v = MAX(0, MIN(127, f.integerValue)); f.stringValue = [NSString stringWithFormat:@"%ld", (long)v]; ((EDChanBar *)_chanBars[ch - 1]).value = v; [EDSamplerRemote setVolume:v forChannel:ch]; [self.panel makeFirstResponder:nil]; }
- (void)pTyped:(NSTextField *)f { NSInteger ch = _selChannel ? _selChannel() : 1, v = MAX(-64, MIN(63, f.integerValue)); f.stringValue = [NSString stringWithFormat:@"%+ld", (long)v]; ((EDChanBar *)_chanBars[ch - 1]).pan = v; [EDSamplerRemote setPan:v forChannel:ch]; [self.panel makeFirstResponder:nil]; }
- (void)presetStep:(NSButton *)b { if (_presetField && _presetSet) _presetSet(_presetField.integerValue + b.tag); }
- (void)presetTyped:(NSTextField *)f { if (_presetSet) _presetSet(f.integerValue); [self.panel makeFirstResponder:nil]; }

// MARK: Tones

+ (void)showTonesIn:(NSWindow *)w {
    NSArray *freqs = @[@"50 Hz", @"100 Hz", @"200 Hz", @"261.60 Hz", @"440 Hz", @"444 Hz", @"500 Hz", @"1 kHz", @"2 kHz", @"5 kHz", @"10 kHz", @"15 kHz", @"19 kHz"];
    NSArray *waves = @[@"Sine", @"Triangle", @"Square", @"Sawtooth"];
    NSMutableArray *gains = [NSMutableArray array]; for (int g = -60; g <= 0; g += 6) [gains addObject:[NSString stringWithFormat:@"%d dB", g]];
    [self presentTitle:@"Tones" in:w build:^(EDUtils *u, NSView *screen) {
        NSPopUpButton *f = lcdPopup(freqs, @"1 kHz"), *wv = lcdPopup(waves, @"Sine"), *g = lcdPopup(gains, @"-24 dB");
        f.identifier = @"freq"; wv.identifier = @"wave"; g.identifier = @"gain";
        for (NSPopUpButton *p in @[f, wv, g]) { p.target = u; p.action = @selector(toneChanged:); }
        [u applyFreq:f.titleOfSelectedItem wave:wv.titleOfSelectedItem gain:g.titleOfSelectedItem];
        NSMutableArray *rows = [NSMutableArray array];
        for (NSArray *r in @[@[@"Frequency", f], @[@"Waveform", wv], @[@"Gain", g]]) {
            NSTextField *l = lcdText(r[0], 17); [l.widthAnchor constraintEqualToConstant:210].active = YES;
            NSStackView *row = [NSStackView stackViewWithViews:@[l, r[1]]]; row.spacing = 16; [rows addObject:row];
        }
        NSStackView *col = [NSStackView stackViewWithViews:rows]; col.orientation = NSUserInterfaceLayoutOrientationVertical; col.alignment = NSLayoutAttributeLeading; col.spacing = 12;
        place(screen, col, 80);
        u->_playBtn = [EDTheme lcdKey:@"Play Tone" target:u action:@selector(toggleTone:)]; u->_playBtn.toolTip = @"Play the chosen tone on the sampler until you stop it.";
        u->_doneCenterX.constant = 81;          // Play Tone and Done sit side by side along the bottom, as a pair centred in the panel
        u->_playBtn.translatesAutoresizingMaskIntoConstraints = NO; [screen addSubview:u->_playBtn];
        [NSLayoutConstraint activateConstraints:@[[u->_playBtn.centerXAnchor constraintEqualToAnchor:screen.centerXAnchor constant:-61], [u->_playBtn.bottomAnchor constraintEqualToAnchor:u->_doneBtn.bottomAnchor], [u->_playBtn.widthAnchor constraintEqualToConstant:150], [u->_playBtn.heightAnchor constraintEqualToConstant:30]]];
        NSTextField *note = [NSTextField ed_wrappingLabelWithString:@"Reference tone through this Mac's output, for checking your audio chain. Starts at a low level; raise it with Gain. It stops when you press Done."];
        note.font = [NSFont systemFontOfSize:12]; note.textColor = EDTheme.lcdInk; note.translatesAutoresizingMaskIntoConstraints = NO; [screen addSubview:note];
        [NSLayoutConstraint activateConstraints:@[[note.leadingAnchor constraintEqualToAnchor:screen.leadingAnchor constant:40], [note.trailingAnchor constraintEqualToAnchor:screen.trailingAnchor constant:-40], [note.bottomAnchor constraintEqualToAnchor:screen.bottomAnchor constant:-58]]];
    }];
}
- (void)applyFreq:(NSString *)f wave:(NSString *)wv gain:(NSString *)g {
    double v = f.doubleValue; if ([f containsString:@"kHz"]) v *= 1000; _freq = v;
    _wave = [@[@"Sine", @"Triangle", @"Square", @"Sawtooth"] indexOfObject:wv]; _amp = pow(10.0, g.doubleValue / 20.0);
}
- (void)toneChanged:(NSPopUpButton *)p {
    NSView *screen = p.superview.superview.superview; NSString *f = nil, *wv = nil, *g = nil;
    for (NSView *v in [self allPopups:screen]) { NSPopUpButton *q = (NSPopUpButton *)v; if ([q.identifier isEqual:@"freq"]) f = q.titleOfSelectedItem; if ([q.identifier isEqual:@"wave"]) wv = q.titleOfSelectedItem; if ([q.identifier isEqual:@"gain"]) g = q.titleOfSelectedItem; }
    [self applyFreq:f wave:wv gain:g];
}
- (NSArray *)allPopups:(NSView *)v {
    NSMutableArray *a = [NSMutableArray array]; if ([v isKindOfClass:[NSPopUpButton class]]) [a addObject:v];
    for (NSView *s in v.subviews) [a addObjectsFromArray:[self allPopups:s]]; return a;
}
- (void)setPlayTitle:(NSString *)t {
    _playBtn.title = t;
}
- (void)toggleTone:(id)s { if (_playing) [self stopTone]; else [self startTone]; }
- (void)startTone {
    if (_playing) return;
    _engine = [AVAudioEngine new];
    AVAudioFormat *fmt = [_engine.outputNode outputFormatForBus:0]; double sr = fmt.sampleRate > 0 ? fmt.sampleRate : 44100;
    __unsafe_unretained EDUtils *me = self;
    _source = [[AVAudioSourceNode alloc] initWithRenderBlock:^OSStatus(BOOL *silence, const AudioTimeStamp *ts, AVAudioFrameCount frames, AudioBufferList *out) {
        double inc = me->_freq / sr, amp = me->_amp; NSInteger wave = me->_wave; double ph = me->_phase;
        for (AVAudioFrameCount i = 0; i < frames; i++) {
            double v;
            switch (wave) { case 1: v = 4 * fabs(ph - 0.5) - 1; break; case 2: v = ph < 0.5 ? 1 : -1; break; case 3: v = 2 * ph - 1; break; default: v = sin(2 * M_PI * ph); }
            for (UInt32 b = 0; b < out->mNumberBuffers; b++) ((float *)out->mBuffers[b].mData)[i] = (float)(v * amp);
            ph += inc; if (ph >= 1) ph -= 1;
        }
        me->_phase = ph; return noErr;
    }];
    AVAudioFormat *mono = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sr channels:2];
    [_engine attachNode:_source]; [_engine connect:_source to:_engine.mainMixerNode format:mono];
    NSError *e = nil; if (![_engine startAndReturnError:&e]) { _engine = nil; _source = nil; return; }
    _playing = YES; [self setPlayTitle:@"Stop Tone"];
}
- (void)stopTone {
    if (!_playing) return;
    [_engine stop]; _engine = nil; _source = nil; _playing = NO; [self setPlayTitle:@"Play Tone"];
}
@end
