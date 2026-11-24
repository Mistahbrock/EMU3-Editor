#import "EDGeneratorView.h"
#import "EDBank.h"
#import "EDPlayer.h"
#import "EDTheme.h"

// A flipped document view, so a scroll view shows its top first.
@interface EDGenFlipDoc : NSView
@end
@implementation EDGenFlipDoc
- (BOOL)isFlipped { return YES; }
@end

@implementation EDGeneratorView {
    NSArray<Class<EDGeneratorPlugin>> *_classes;
    NSMutableArray<id<EDGeneratorPlugin>> *_instances;
    NSMutableArray<NSButton *> *_listButtons;
    NSScrollView *_panelScroll;
    NSTextField *_status, *_empty;
    NSInteger _current;
    EDPlayer *_player;
    NSTimer *_refresh;
    BOOL _auditioning;
}

- (instancetype)initWithFrame:(NSRect)f {
    if (!(self = [super initWithFrame:f])) return nil;
    _classes = EDGeneratorRegistry.generators; _instances = [NSMutableArray array]; _listButtons = [NSMutableArray array]; _current = -1; _player = [EDPlayer new];
    for (NSUInteger i = 0; i < _classes.count; i++) [_instances addObject:(id)NSNull.null];
    [self build];
    if (_classes.count) [self select:0];
    return self;
}

- (void)build {
    NSTextField *cap = [NSTextField labelWithString:@"GENERATOR"]; cap.font = [NSFont systemFontOfSize:12 weight:NSFontWeightBold]; cap.textColor = EDTheme.labelWhite;
    NSView *capLine = [NSView new]; capLine.wantsLayer = YES; capLine.layer.backgroundColor = EDTheme.accent.CGColor; [capLine.heightAnchor constraintEqualToConstant:2].active = YES;
    NSStackView *list = [NSStackView new]; list.orientation = NSUserInterfaceLayoutOrientationVertical; list.alignment = NSLayoutAttributeLeading; list.spacing = 8;
    [list addArrangedSubview:cap]; [list addArrangedSubview:capLine]; [capLine.widthAnchor constraintEqualToAnchor:list.widthAnchor].active = YES;
    NSUInteger nBuiltIn = EDGeneratorRegistry.builtInGenerators.count;
    for (NSUInteger i = 0; i < _classes.count; i++) {
        if (i == nBuiltIn) {   // the "Add Ons" divider
            NSTextField *t = [NSTextField labelWithString:@"ADD ONS"]; t.font = [NSFont systemFontOfSize:11 weight:NSFontWeightBold]; t.textColor = [EDTheme.labelWhite colorWithAlphaComponent:0.7];
            NSView *ln = [NSView new]; ln.wantsLayer = YES; ln.layer.backgroundColor = [EDTheme.labelWhite colorWithAlphaComponent:0.25].CGColor; [ln.heightAnchor constraintEqualToConstant:1].active = YES;
            [list setCustomSpacing:16 afterView:list.arrangedSubviews.lastObject]; [list addArrangedSubview:t]; [list addArrangedSubview:ln]; [ln.widthAnchor constraintEqualToAnchor:list.widthAnchor].active = YES;
        }
        Class c = _classes[i];
        NSButton *b = [NSButton buttonWithTitle:[(id)c generatorName] target:self action:@selector(listPicked:)]; b.tag = (NSInteger)i; b.bezelStyle = NSBezelStyleRegularSquare; [b setButtonType:NSButtonTypePushOnPushOff]; b.toolTip = [(id)c generatorSummary];
        [b.widthAnchor constraintEqualToConstant:200].active = YES; [list addArrangedSubview:b]; [_listButtons addObject:b];
    }
    NSTextField *hint = [NSTextField wrappingLabelWithString:[NSString stringWithFormat:@"Add Ons (.addon) go in\n%@", EDGeneratorRegistry.addOnFolder.path.stringByAbbreviatingWithTildeInPath]];
    hint.font = [NSFont systemFontOfSize:11]; hint.textColor = [EDTheme.labelWhite colorWithAlphaComponent:0.6]; hint.preferredMaxLayoutWidth = 200; [list setCustomSpacing:20 afterView:_listButtons.lastObject ?: capLine]; [list addArrangedSubview:hint];

    _panelScroll = [NSScrollView new]; _panelScroll.hasVerticalScroller = YES; _panelScroll.drawsBackground = NO; _panelScroll.borderType = NSNoBorder;
    _empty = [NSTextField labelWithString:@"No generators available."]; _empty.textColor = EDTheme.labelWhite;

    NSButton *play = [NSButton buttonWithTitle:@"▶ Start (Space)" target:self action:@selector(audition:)];
    NSButton *stop = [NSButton buttonWithTitle:@"■ Stop" target:self action:@selector(stopPressed:)];
    NSButton *add = [NSButton buttonWithTitle:@"Add to Bank" target:self action:@selector(addPressed:)];
    NSButton *wav = [NSButton buttonWithTitle:@"Export WAV…" target:self action:@selector(exportWAV:)];
    for (NSButton *b in @[play, stop, add, wav]) b.bezelStyle = NSBezelStyleRegularSquare;
    _status = [NSTextField labelWithString:@"Pick a generator, shape the sound, then Audition or Add to Bank."]; _status.textColor = [EDTheme.labelWhite colorWithAlphaComponent:0.8]; _status.font = [NSFont systemFontOfSize:12];
    NSStackView *bar = [NSStackView stackViewWithViews:@[play, stop, add, wav, _status]]; bar.spacing = 10; bar.edgeInsets = NSEdgeInsetsMake(10, 20, 10, 20);

    for (NSView *v in @[list, _panelScroll, bar]) { v.translatesAutoresizingMaskIntoConstraints = NO; [self addSubview:v]; }
    NSView *divider = [NSView new]; divider.wantsLayer = YES; divider.layer.backgroundColor = [EDTheme.labelWhite colorWithAlphaComponent:0.15].CGColor; divider.translatesAutoresizingMaskIntoConstraints = NO; [self addSubview:divider];
    [NSLayoutConstraint activateConstraints:@[
        [list.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:24], [list.topAnchor constraintEqualToAnchor:self.topAnchor constant:24], [list.widthAnchor constraintEqualToConstant:200],
        [divider.leadingAnchor constraintEqualToAnchor:list.trailingAnchor constant:20], [divider.topAnchor constraintEqualToAnchor:self.topAnchor constant:16], [divider.bottomAnchor constraintEqualToAnchor:bar.topAnchor], [divider.widthAnchor constraintEqualToConstant:1],
        [_panelScroll.leadingAnchor constraintEqualToAnchor:divider.trailingAnchor], [_panelScroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor], [_panelScroll.topAnchor constraintEqualToAnchor:self.topAnchor], [_panelScroll.bottomAnchor constraintEqualToAnchor:bar.topAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor], [bar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor], [bar.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]]];
}

- (void)selectIdentifier:(NSString *)ident {
    for (NSUInteger i = 0; i < _classes.count; i++) if ([[(id)_classes[i] generatorIdentifier] isEqualToString:ident]) { [self select:(NSInteger)i]; return; }
}
- (void)listPicked:(NSButton *)b { [self select:b.tag]; }
- (void)select:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)_classes.count) return;
    [self stopAudition]; _current = i;
    for (NSButton *b in _listButtons) b.state = b.tag == i ? NSControlStateValueOn : NSControlStateValueOff;
    if (_instances[i] == (id)NSNull.null) _instances[i] = [(id<EDGeneratorPlugin>)[(id)_classes[i] alloc] initWithHost:self];
    NSView *v = _instances[i].view; v.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *doc = [EDGenFlipDoc new]; doc.translatesAutoresizingMaskIntoConstraints = NO; [doc addSubview:v];
    NSClipView *clip = _panelScroll.contentView;   // the panel sits in the middle of the page, both ways; it scrolls when it is bigger than the window
    _panelScroll.documentView = doc;
    [NSLayoutConstraint activateConstraints:@[
        [doc.leadingAnchor constraintEqualToAnchor:clip.leadingAnchor], [doc.topAnchor constraintEqualToAnchor:clip.topAnchor],
        [doc.widthAnchor constraintGreaterThanOrEqualToAnchor:clip.widthAnchor], [doc.heightAnchor constraintGreaterThanOrEqualToAnchor:clip.heightAnchor],
        [v.centerXAnchor constraintEqualToAnchor:doc.centerXAnchor], [v.centerYAnchor constraintEqualToAnchor:doc.centerYAnchor],
        [v.leadingAnchor constraintGreaterThanOrEqualToAnchor:doc.leadingAnchor], [v.topAnchor constraintGreaterThanOrEqualToAnchor:doc.topAnchor]]];
    [self say:[NSString stringWithFormat:@"%@ — %@", [(id)_classes[i] generatorName], [(id)_classes[i] generatorSummary]]];
}
- (id<EDGeneratorPlugin>)plugin { return _current >= 0 ? _instances[_current] : nil; }
- (void)say:(NSString *)t { _status.stringValue = t; }

// MARK: rendering helpers

/// An EDSample for the player / WAV export: the generated frames with the 4-frame guard the sampler's samples carry.
- (EDSample *)tempSampleFor:(EDGeneratedSample *)g {
    const NSUInteger guard = 4; NSUInteger frames = g.left.length / 2, n = frames + 2 * guard;
    NSMutableData *L = [NSMutableData dataWithLength:n * 2], *R = g.right ? [NSMutableData dataWithLength:n * 2] : nil;
    memcpy((uint8_t *)L.mutableBytes + guard * 2, g.left.bytes, frames * 2); if (R) memcpy((uint8_t *)R.mutableBytes + guard * 2, g.right.bytes, MIN(g.right.length, frames * 2));
    EDSample *s = [EDSample new]; s.sampleRate = g.sampleRate; s.name = g.name; [s replaceLeft:L right:R];
    s.loopStart = guard + g.loopStart; s.loopEnd = guard + g.loopEnd; s.loopEnabled = g.loop;
    return s;
}
- (nullable EDGeneratedSample *)renderNow {
    EDGeneratedSample *g = [self.plugin render];
    if (!g || g.left.length < 8) { [self say:@"Nothing to make — check the settings."]; return nil; }
    return g;
}

// MARK: EDGeneratorHost

- (void)generatorAudition:(EDGeneratedSample *)g { [_player playSample:[self tempSampleFor:g]]; _auditioning = YES; }
- (void)generatorStop { [self stopAudition]; }
- (void)generatorChanged {
    if (!_auditioning) return;
    [_refresh invalidate]; _refresh = [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:NO block:^(NSTimer *t) { [self restartAudition]; }];   // follow the knobs while it plays
}
- (void)restartAudition { EDGeneratedSample *g = [self.plugin render]; if (g) [self generatorAudition:g]; else [self stopAudition]; }
- (void)stopAudition { [_refresh invalidate]; _refresh = nil; [_player stop]; _auditioning = NO; }

// MARK: buttons

/// Space starts / stops the audition (unless a text field is being edited).
- (BOOL)performKeyEquivalent:(NSEvent *)e {
    NSEventModifierFlags m = e.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask & ~NSEventModifierFlagCapsLock;
    if (m == 0 && [e.charactersIgnoringModifiers isEqualToString:@" "] && ![self.window.firstResponder isKindOfClass:NSText.class]) {
        if (_auditioning) { [self stopAudition]; [self say:@"Stopped."]; } else [self audition:nil];
        return YES;
    }
    return [super performKeyEquivalent:e];
}
- (void)audition:(id)s { EDGeneratedSample *g = [self renderNow]; if (!g) return; [self generatorAudition:g]; [self say:[NSString stringWithFormat:@"Playing %@ — %.1f s at %u Hz%@", g.name, (double)(g.left.length / 2) / g.sampleRate, g.sampleRate, g.loop ? @", looped" : @""]]; }
- (void)stopPressed:(id)s { [self stopAudition]; [self say:@"Stopped."]; }
- (void)addPressed:(id)s {
    EDGeneratedSample *g = [self renderNow]; if (!g) return;
    if (self.bankAvailable && !self.bankAvailable()) { [self say:@"Open or create an EOS bank first (File ▸ New Bank), then add the sample to it."]; NSBeep(); return; }
    NSString *msg = nil; NSInteger n = self.addToBank ? self.addToBank(g, &msg) : 0;
    [self say:n > 0 ? [NSString stringWithFormat:@"Added \"%@\" to the bank as sample #%ld. Find it on the Samples tab.", g.name, (long)n] : (msg ?: @"Could not add the sample.")];
}
- (void)exportWAV:(id)s {
    EDGeneratedSample *g = [self renderNow]; if (!g) return;
    NSSavePanel *p = [NSSavePanel savePanel]; p.nameFieldStringValue = [g.name stringByAppendingString:@".wav"]; p.allowedFileTypes = @[@"wav"];
    if ([p runModal] != NSModalResponseOK) return;
    NSError *e = nil; BOOL ok = [[self tempSampleFor:g] writeWAVToURL:p.URL error:&e];
    [self say:ok ? [NSString stringWithFormat:@"Saved %@", p.URL.lastPathComponent] : (e.localizedDescription ?: @"Could not save the WAV file.")];
}
@end
