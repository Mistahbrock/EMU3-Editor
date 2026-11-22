#import "EDUtils.h"
#import "EDTheme.h"
#import <AVFoundation/AVFoundation.h>

// Each screen is an LCD panel like the ones on the sampler. Assign Key keeps a profile (the sampler stores its keys in flash and cannot be read);
// Tones is a real reference-tone generator on the Mac's output; Channel Volume needs live data the sampler only shows on its own display.

@interface EDUtils ()
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, weak) NSWindow *parent;
@end

@implementation EDUtils {
    AVAudioEngine *_engine; AVAudioSourceNode *_source; BOOL _playing;
    double _freq, _phase, _amp; NSInteger _wave;
    NSButton *_playBtn;
}
static EDUtils *sCurrent;   // keeps the open sheet alive

+ (void)presentTitle:(NSString *)title in:(NSWindow *)w build:(void (^)(EDUtils *u, NSView *screen))build {
    EDUtils *u = [EDUtils new]; sCurrent = u; u.parent = w; u->_freq = 1000; u->_amp = 0.1;
    NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 780, 430) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    [EDTheme styleWindow:p]; u.panel = p;
    NSView *content = p.contentView;
    NSView *screen = [NSView new]; screen.wantsLayer = YES; screen.layer.backgroundColor = EDTheme.lcdBackground.CGColor; screen.layer.cornerRadius = 6;
    screen.layer.borderWidth = 6; screen.layer.borderColor = NSColor.blackColor.CGColor; screen.translatesAutoresizingMaskIntoConstraints = NO; [content addSubview:screen];
    NSTextField *t = [NSTextField labelWithString:title]; t.font = [EDTheme lcdFont:26]; t.textColor = EDTheme.lcdInk; t.translatesAutoresizingMaskIntoConstraints = NO; [screen addSubview:t];
    NSButton *close = [NSButton buttonWithTitle:@"Done" target:u action:@selector(done:)]; close.keyEquivalent = @"\r"; close.translatesAutoresizingMaskIntoConstraints = NO; [content addSubview:close];
    [NSLayoutConstraint activateConstraints:@[
        [screen.topAnchor constraintEqualToAnchor:content.topAnchor constant:20], [screen.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [screen.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20], [screen.bottomAnchor constraintEqualToAnchor:close.topAnchor constant:-16],
        [t.topAnchor constraintEqualToAnchor:screen.topAnchor constant:14], [t.centerXAnchor constraintEqualToAnchor:screen.centerXAnchor],
        [close.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20], [close.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16]]];
    build(u, screen);
    [w beginSheet:p completionHandler:^(NSModalResponse r) { [u stopTone]; sCurrent = nil; }];
}
- (void)done:(id)s { [self stopTone]; [self.parent endSheet:self.panel]; }

static NSTextField *lcdText(NSString *s, CGFloat size) { NSTextField *t = [NSTextField labelWithString:s]; t.font = [EDTheme lcdFont:size]; t.textColor = EDTheme.lcdInk; return t; }
static NSPopUpButton *lcdPopup(NSArray<NSString *> *items, NSString *sel) {
    NSPopUpButton *pop = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; pop.bordered = NO; pop.font = [EDTheme lcdFont:17]; pop.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];   // dark arrows on the green
    NSDictionary *attr = @{NSFontAttributeName: [EDTheme lcdFont:17], NSForegroundColorAttributeName: EDTheme.lcdInk};
    for (NSString *o in items) { NSMenuItem *mi = [pop.menu addItemWithTitle:o action:nil keyEquivalent:@""]; mi.attributedTitle = [[NSAttributedString alloc] initWithString:o attributes:attr]; }
    if (sel) [pop selectItemWithTitle:sel];
    [pop.widthAnchor constraintGreaterThanOrEqualToConstant:170].active = YES; return pop;
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
        NSTextField *note = [NSTextField wrappingLabelWithString:@"The sampler stores its assignable keys in its own memory and cannot be read from here. Set them to match, or use this as a reference sheet."];
        note.font = [NSFont systemFontOfSize:11]; note.textColor = EDTheme.lcdInk; note.translatesAutoresizingMaskIntoConstraints = NO; [screen addSubview:note];
        [NSLayoutConstraint activateConstraints:@[[note.leadingAnchor constraintEqualToAnchor:screen.leadingAnchor constant:40], [note.trailingAnchor constraintEqualToAnchor:screen.trailingAnchor constant:-40], [note.bottomAnchor constraintEqualToAnchor:screen.bottomAnchor constant:-14]]];
    }];
}
- (void)assignChanged:(NSPopUpButton *)p {
    NSMutableDictionary *d = [([NSUserDefaults.standardUserDefaults dictionaryForKey:@"SamplerAssignKeys"] ?: @{}) mutableCopy];
    d[p.identifier] = p.titleOfSelectedItem; [NSUserDefaults.standardUserDefaults setObject:d forKey:@"SamplerAssignKeys"];
}

// MARK: Channel Volume

+ (void)showChannelVolumeIn:(NSWindow *)w {
    [self presentTitle:@"Channel Volume" in:w build:^(EDUtils *u, NSView *screen) {
        NSStackView *bars = [NSStackView new]; bars.spacing = 6; bars.alignment = NSLayoutAttributeBottom;
        for (int i = 1; i <= 32; i++) {
            NSView *bar = [NSView new]; bar.wantsLayer = YES; bar.layer.borderWidth = 1; bar.layer.borderColor = EDTheme.lcdInk.CGColor;
            [bar.widthAnchor constraintEqualToConstant:14].active = YES; [bar.heightAnchor constraintEqualToConstant:150].active = YES; [bars addArrangedSubview:bar];
        }
        place(screen, bars, 80);
        NSTextField *note = [NSTextField wrappingLabelWithString:@"On the sampler this graph shows how loud each of the 32 voice channels is. It is live data that only the sampler's own display shows; neither SCSI (SMDI) nor sample dump reports it, so the bars stay empty here."];
        note.font = [NSFont systemFontOfSize:12]; note.textColor = EDTheme.lcdInk; note.translatesAutoresizingMaskIntoConstraints = NO; [screen addSubview:note];
        [NSLayoutConstraint activateConstraints:@[[note.leadingAnchor constraintEqualToAnchor:screen.leadingAnchor constant:40], [note.trailingAnchor constraintEqualToAnchor:screen.trailingAnchor constant:-40], [note.bottomAnchor constraintEqualToAnchor:screen.bottomAnchor constant:-14]]];
    }];
}

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
        u->_playBtn = [NSButton buttonWithTitle:@"▶  Play tone" target:u action:@selector(toggleTone:)]; u->_playBtn.bordered = NO; u->_playBtn.wantsLayer = YES;
        u->_playBtn.layer.backgroundColor = [EDTheme.lcdBackground shadowWithLevel:0.3].CGColor; u->_playBtn.layer.cornerRadius = 4;
        u->_playBtn.layer.borderWidth = 1.5; u->_playBtn.layer.borderColor = EDTheme.lcdInk.CGColor; u->_playBtn.font = [EDTheme lcdFont:15];
        [u setPlayTitle:@"▶  Play tone"];
        [u->_playBtn.widthAnchor constraintEqualToConstant:160].active = YES; place(screen, u->_playBtn, 250);
        NSTextField *note = [NSTextField wrappingLabelWithString:@"Reference tone through this Mac's output, for checking your audio chain. Starts at a low level; raise it with Gain. It stops when you press Done."];
        note.font = [NSFont systemFontOfSize:12]; note.textColor = EDTheme.lcdInk; note.translatesAutoresizingMaskIntoConstraints = NO; [screen addSubview:note];
        [NSLayoutConstraint activateConstraints:@[[note.leadingAnchor constraintEqualToAnchor:screen.leadingAnchor constant:40], [note.trailingAnchor constraintEqualToAnchor:screen.trailingAnchor constant:-40], [note.bottomAnchor constraintEqualToAnchor:screen.bottomAnchor constant:-14]]];
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
    _playBtn.attributedTitle = [[NSAttributedString alloc] initWithString:t attributes:@{NSFontAttributeName: [EDTheme lcdFont:15], NSForegroundColorAttributeName: EDTheme.lcdInk}];
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
    _playing = YES; [self setPlayTitle:@"■  Stop tone"];
}
- (void)stopTone {
    if (!_playing) return;
    [_engine stop]; _engine = nil; _source = nil; _playing = NO; [self setPlayTitle:@"▶  Play tone"];
}
@end
