#import "EDMIDIEditor.h"
#import "EDPreset+Params.h"
#import "EDTheme.h"
#import "EDMIDIPort.h"

// The MIDI tab mirrors the sampler's Master > MIDI menus (Mode, Cntrls 1, Cntrls 2, Prefs 1, Prefs 2) as one LCD screen with soft keys,
// plus a "Presets" page that edits MIDI A–D of every preset in the open bank.
// The master pages are a profile kept by the editor: the sampler stores these settings in its own flash memory and they are not part of a bank
// or reachable over SCSI/SDS, so the profile is there to be set to match the sampler. Device ID is shared with the MIDI Sample Dump panel.

static NSArray<NSString *> *range(NSInteger lo, NSInteger hi, NSString *fmt) {
    NSMutableArray *a = [NSMutableArray array]; for (NSInteger i = lo; i <= hi; i++) [a addObject:[NSString stringWithFormat:fmt, (long)i]]; return a;
}
static NSArray<NSString *> *xposeList(void) {   // -12 .. +12 semitones; the sampler shows 0 as "Off"
    NSMutableArray *a = [range(-12, 12, @"%+ld") mutableCopy]; a[12] = @"Off"; return a;
}
static NSArray<NSString *> *noteList(void) {   // MIDI notes 0..127 as the sampler shows them: C-1 .. G9, middle C (60) = C4
    static NSString *const names[12] = {@"C", @"C#", @"D", @"D#", @"E", @"F", @"F#", @"G", @"G#", @"A", @"A#", @"B"};
    NSMutableArray *a = [NSMutableArray array];
    for (int n = 0; n < 128; n++) [a addObject:[NSString stringWithFormat:@"%@%d", names[n % 12], n / 12 - 1]];
    return a;
}
static NSArray<NSString *> *fxTypesA(void) {   // EOS 4 manual, Master Effects A
    return @[@"Room 1", @"Room 2", @"Room 3", @"Hall 1", @"Hall 2", @"Plate", @"Delay", @"Panning Delay", @"Multitap 1", @"Multitap Pan", @"3 Tap", @"3 Tap Pan", @"Soft Room", @"Warm Room", @"Perfect Room", @"Tiled Room",
             @"Hard Plate", @"Warm Hall", @"Spacious Hall", @"Bright Hall", @"Bright Hall Pan", @"Bright Plate", @"BBall Court", @"Gymnasium", @"Cavern", @"Concert 9", @"Concert 10 Pan", @"Reverse Gate", @"Gate 2", @"Gate Pan",
             @"Concert 11", @"Medium Concert", @"Large Concert", @"Large Concert Pan", @"Canyon", @"DelayVerb 1", @"DelayVerb 2", @"DelayVerb 3", @"DelayVerb 4 Pan", @"DelayVerb 5 Pan", @"DelayVerb 6", @"DelayVerb 7", @"DelayVerb 8", @"DelayVerb 9"];
}
static NSArray<NSString *> *fxTypesB(void) {   // Master Effects B
    return @[@"Chorus 1", @"Chorus 2", @"Chorus 3", @"Chorus 4", @"Chorus 5", @"Doubling", @"Slapback", @"Flange 1", @"Flange 2", @"Flange 3", @"Flange 4", @"Flange 5", @"Flange 6", @"Flange 7", @"Big Chorus", @"Symphonic",
             @"Ensemble", @"Delay", @"Delay Stereo 1", @"Delay Stereo 2", @"Panning Delay", @"Delay Chorus", @"Pan Delay Chorus 1", @"Pan Delay Chorus 2", @"Dual Tap 1/3", @"Dual Tap 1/4", @"Vibrato",
             @"Distortion 1", @"Distortion 2", @"Distortion Flange", @"Distorted Chorus", @"Distorted Double"];
}
static NSArray<NSString *> *ccList(NSArray *extra) { return [extra arrayByAddingObjectsFromArray:range(0, 127, @"cc%ld")]; }

@implementation EDMIDIEditor {
    NSView *_screen; NSTextField *_title, *_prev, *_next, *_note, *_empty;
    NSStackView *_rows; NSScrollView *_tableScroll; NSTableView *_table;
    NSArray<NSDictionary *> *_pages; NSInteger _page; NSMutableDictionary<NSString *, NSString *> *_profile;
    NSMutableArray<NSButton *> *_softKeys; NSString *_menu; NSTextField *_msg; NSStackView *_actions; id _keyMonitor;
}

- (NSDictionary *)defaults {
    NSMutableDictionary *d = [@{@"basic": @"1", @"mode": @"omni", @"devid": [NSUserDefaults.standardUserDefaults stringForKey:@"SDSDevice"] ?: @"0", @"local": @"on",
        @"pitch": @"ptwheel", @"mod": @"cc1", @"press": @"chnpres", @"pedal": @"cc3", @"sw1": @"64", @"sw2": @"65", @"sw3": @"66",
        @"vcurve": @"linear", @"c7sens": @"31", @"c7curve": @"logarithmic", @"gpedal": @"off", @"rcvpc": @"on", @"sendpc": @"on", @"magic": @"off",
        @"tuneoff": @"+0/64", @"xpose": @"Off", @"audition": @"C4", @"synatk": @"Fast", @"fxa": @"Room 1", @"fxb": @"Chorus 1", @"fxon": @"Enabled", @"fxctl": @"Master Settings", @"headroom": @"3 dB", @"oboost": @"+0 dB", @"ofmt": @"analog", @"dither": @"off", @"aesboost": @"off", @"oclock": @"48kHz",
        @"contrast": @"+0", @"wrap": @"on", @"saver": @"Never", @"scsiid": @"6", @"term": @"on", @"avoid": @"7", @"diskbtn": @"Last", @"combine": @"off", @"fracloop": @"off", @"autoload": @"off", @"memprefer": @"405 K", @"seqmem": @"1 K"} mutableCopy];
    NSInteger ccs[12] = {21, 22, 23, 24, 25, 26, 27, 28, 70, 71, 72, 73};
    for (int i = 0; i < 12; i++) d[[NSString stringWithFormat:@"midi%c", 'a' + i]] = [NSString stringWithFormat:@"cc%ld", (long)ccs[i]];
    return d;
}

- (instancetype)initWithFrame:(NSRect)f {
    if (!(self = [super initWithFrame:f])) return nil;
    _profile = [self.defaults mutableCopy];
    NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:@"SamplerMIDIProfile"]; if (saved) [_profile addEntriesFromDictionary:saved];
    { NSInteger k = [_profile[@"audition"] integerValue]; if ([_profile[@"audition"] length] && [_profile[@"audition"] rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location == NSNotFound && k >= 0 && k < 128) _profile[@"audition"] = noteList()[k]; }   // older profiles stored the note number
    if ([_profile[@"xpose"] isEqual:@"+0"]) _profile[@"xpose"] = @"Off";   // the sampler shows 0 semitones as "Off"
    NSArray *onoff = @[@"off", @"on"];
    NSMutableArray *midiRows = [NSMutableArray array];
    for (int i = 0; i < 12; i++) [midiRows addObject:@[[NSString stringWithFormat:@"midi%c", 'a' + i], [NSString stringWithFormat:@"Midi%c", 'A' + i], ccList(@[@"off"])]];
    _pages = @[
        @{@"menu": @"MIDI", @"soft": @"Mode", @"title": @"MIDI Mode", @"next": @"MIDI Controllers 1", @"fk": @[@"F1", @"F2", @"F3"], @"percol": @3, @"rows": @[
            @[@"basic", @"Basic Channel", range(1, 16, @"%ld")], @[@"mode", @"MIDI mode", @[@"omni", @"poly", @"multi"]],
            @[@"devid", @"MIDI Device ID", range(0, 127, @"%ld")],
            @[@"ifout", @"MIDI Interface Out", @[]], @[@"ifin", @"MIDI Interface In", @[]]]},
        @{@"menu": @"MIDI", @"soft": @"Cntrls 1", @"title": @"MIDI Controllers 1", @"prev": @"MIDI Mode", @"next": @"MIDI Controllers 2", @"fk": @[@"F1", @"F2", @"F3", @"F4", @"F5", @"", @""], @"rows": @[
            @[@"pitch", @"Pitch Control", ccList(@[@"ptwheel", @"chnpres", @"off"])], @[@"mod", @"Mod Control", ccList(@[@"ptwheel", @"chnpres", @"off"])],
            @[@"press", @"Pressure Control", ccList(@[@"chnpres", @"ptwheel", @"off"])], @[@"pedal", @"Pedal Control", ccList(@[@"chnpres", @"ptwheel", @"off"])],
            @[@"sw1", @"Switch 1 Control", range(0, 127, @"%ld")], @[@"sw2", @"Switch 2 Control", range(0, 127, @"%ld")], @[@"sw3", @"Switch 3 Control", range(0, 127, @"%ld")]]},
        @{@"menu": @"MIDI", @"soft": @"Cntrls 2", @"title": @"MIDI Controllers 2", @"prev": @"MIDI Controllers 1", @"next": @"MIDI Preferences 1", @"rows": midiRows},
        @{@"menu": @"MIDI", @"soft": @"Prefs 1", @"title": @"MIDI Preferences", @"prev": @"MIDI Controllers 2", @"next": @"MIDI Preferences 2", @"fk": @[@"F1", @"F2", @"F3", @"F4"], @"rows": @[
            @[@"vcurve", @"Velocity Curve", [@[@"linear"] arrayByAddingObjectsFromArray:range(2, 14, @"curve %ld")]], @[@"c7sens", @"Ctrl#7 Sensitivity", range(0, 31, @"%ld")],
            @[@"c7curve", @"Ctrl#7 Curve", @[@"linear", @"logarithmic", @"squared"]], @[@"gpedal", @"Global pedal override", onoff]]},
        @{@"menu": @"MIDI", @"soft": @"Prefs 2", @"title": @"MIDI Preferences 2", @"prev": @"MIDI Preferences 1", @"fk": @[@"F1", @"F2", @"F3"], @"rows": @[
            @[@"rcvpc", @"Rcv Program Change", onoff], @[@"sendpc", @"Send Program Change", onoff], @[@"magic", @"Magic load preset", onoff]]},
        @{@"menu": @"MIDI", @"soft": @"Presets", @"title": @"Preset MIDI", @"prev": @"MIDI Preferences 2", @"table": @YES},
        // Master > Setup (EOS 4.62 menu texts; value ranges from the EOS 4.0 manual)
        @{@"menu": @"Setup", @"soft": @"Tune", @"title": @"Tuning", @"next": @"Output", @"fk": @[@"F1", @"F2", @"F3", @"F4"], @"rows": @[
            @[@"tuneoff", @"Tuning Offset", range(-64, 64, @"%+ld/64")], @[@"xpose", @"Transposition", xposeList()], @[@"audition", @"Audition Key", noteList()], @[@"synatk", @"Synth Attack", @[@"Fast", @"Slow"]]]},
        @{@"menu": @"Setup", @"soft": @"Output", @"title": @"Output", @"prev": @"Tuning", @"next": @"Miscellaneous", @"fk": @[@"F1", @"F2", @"F3", @"F4", @"F5", @"F6"], @"rows": @[
            @[@"headroom", @"Headroom", range(0, 15, @"%ld dB")], @[@"oboost", @"Output Boost", @[@"+0 dB", @"+12 dB"]],
            @[@"ofmt", @"Output Format", @[@"analog", @"S/PDIF", @"AES pro"]], @[@"aesboost", @"AES Boost", onoff], @[@"oclock", @"Output Clock", @[@"44.1kHz", @"48kHz"]], @[@"dither", @"ADAT Output Dither", onoff]]},
        @{@"menu": @"Setup", @"soft": @"Misc", @"title": @"Miscellaneous", @"prev": @"Output", @"next": @"SCSI / Disk", @"fk": @[@"F1", @"F2", @"F3"], @"rows": @[
            @[@"contrast", @"Contrast", range(-8, 7, @"%+ld")], @[@"wrap", @"Wrap Field Selection", onoff],
            @[@"saver", @"Screen Saver", @[@"Never", @"10 min", @"20 min", @"30 min", @"40 min", @"50 min", @"60 min"]]]},
        @{@"menu": @"Setup", @"soft": @"SCSI", @"title": @"SCSI / Disk", @"prev": @"Miscellaneous", @"next": @"Import Options", @"fk": @[@"F1", @"F2", @"F3", @"F4", @"F5"], @"rows": @[
            @[@"scsiid", @"SCSI ID", range(0, 7, @"%ld")], @[@"term", @"SCSI termination", onoff], @[@"avoid", @"Avoid Host on ID", range(0, 7, @"%ld")],
            @[@"diskbtn", @"Disk Button goes to", @[@"Sprint", @"Last"]]]},
        @{@"menu": @"Setup", @"soft": @"Import", @"title": @"Import Options", @"prev": @"SCSI / Disk", @"next": @"Memory Configuration", @"fk": @[@"F1", @"F2"], @"rows": @[
            @[@"combine", @"Combine L/R into stereo", onoff], @[@"fracloop", @"Adjust Akai/Ensoniq fractional loops", onoff]]},
        // CPU RAM is shared: Preset + Sequence = 406 K on the E6400 (as shown on the sampler's own screen); Sequence follows Preset
        @{@"menu": @"Setup", @"soft": @"Memory", @"title": @"Memory Configuration", @"prev": @"Import Options", @"rows": @[
            @[@"memprefer", @"Preset Memory", range(1, 405, @"%ld K")], @[@"seqmem", @"Sequence Memory", range(1, 405, @"%ld K"), @"derived"]]},
        // Master > FX (needs the effects board; EOS 4 manual, Master Effects)
        @{@"menu": @"FX", @"soft": @"A", @"title": @"Master Effects A", @"next": @"Master Effects B", @"fk": @[@"F1"], @"rows": @[@[@"fxa", @"Effect A", fxTypesA()]]},
        @{@"menu": @"FX", @"soft": @"B", @"title": @"Master Effects B", @"prev": @"Master Effects A", @"next": @"Effects Setup", @"fk": @[@"F1"], @"rows": @[@[@"fxb", @"Effect B", fxTypesB()]]},
        @{@"menu": @"FX", @"soft": @"Setup", @"title": @"Effects Setup", @"prev": @"Master Effects B", @"fk": @[@"F1", @"F2"], @"rows": @[
            @[@"fxon", @"Effects", @[@"Enabled", @"Bypassed"]], @[@"fxctl", @"Multimode Effects Control", [@[@"Master Settings"] arrayByAddingObjectsFromArray:range(1, 16, @"Channel %ld")]]]},
        // Master > Bank
        @{@"menu": @"Bank", @"soft": @"Erase", @"title": @"Erase Bank", @"next": @"Rename Bank", @"message": @"The sampler's Erase clears all presets, samples and sequences of the bank in its RAM.\n\nHere you can clear every preset, or every preset and sample, of the open bank. Nothing is written until you save (or auto-save runs); reopen the bank to get it back.",
          @"actions": @[@[@"Erase All Presets…", @"erasePresets"], @[@"Erase All Presets and Samples…", @"eraseAll"]]},
        @{@"menu": @"Bank", @"soft": @"Name", @"title": @"Rename Bank", @"prev": @"Erase Bank", @"next": @"Bank Auto-Load", @"message": @"Bank: %@\n\nThe sampler asks for a bank name when you save. In the editor the bank name is its file name: use Save Bank As to give it a new one.",
          @"actions": @[@[@"Save Bank As…", @"saveAs"]]},
        @{@"menu": @"Bank", @"soft": @"Auto", @"title": @"Bank Auto-Load", @"prev": @"Rename Bank", @"next": @"Resident FLASH", @"fk": @[@"F1"], @"rows": @[
            @[@"autoload", @"Auto-Load Bank", onoff]]},
        @{@"menu": @"Bank", @"soft": @"Flash", @"title": @"Resident FLASH", @"prev": @"Bank Auto-Load", @"message": @"Erase Resident Bank\nCompact Resident Bank\nCopy RAM to Resident (RAM->F)\nCopy Resident to RAM (F->RAM)\n\nThese act on the sampler's resident flash memory and are run on the sampler itself. They cannot be done from the editor."}];

    // the LCD screen
    _screen = [NSView new]; _screen.wantsLayer = YES; _screen.layer.backgroundColor = EDTheme.lcdBackground.CGColor; _screen.layer.cornerRadius = 0;
    _screen.layer.borderWidth = EDTheme.lcdFrameWidth; _screen.layer.borderColor = NSColor.blackColor.CGColor;
    _title = [NSTextField labelWithString:@""]; _title.font = [EDTheme lcdFont:26]; _title.textColor = EDTheme.lcdInk; _title.alignment = NSTextAlignmentCenter;
    _prev = [NSTextField labelWithString:@""]; _next = [NSTextField labelWithString:@""];
    for (NSTextField *t in @[_prev, _next]) { t.font = [EDTheme lcdFont:12]; t.textColor = EDTheme.lcdInk; }
    _next.alignment = NSTextAlignmentRight;
    _rows = [NSStackView new]; _rows.orientation = NSUserInterfaceLayoutOrientationHorizontal; _rows.alignment = NSLayoutAttributeTop; _rows.spacing = 40; _rows.distribution = NSStackViewDistributionFill;

    _msg = [NSTextField wrappingLabelWithString:@""]; _msg.font = [EDTheme lcdFont:15]; _msg.textColor = EDTheme.lcdInk;
    _actions = [NSStackView new]; _actions.spacing = 12;

    _table = [EDLCDTableView new]; _table.dataSource = self; _table.delegate = self; _table.rowHeight = 26;
    NSArray *cols = @[@[@"num", @"#", @60], @[@"name", @"Preset", @260], @[@"m0", @"MIDI A", @120], @[@"m1", @"MIDI B", @120], @[@"m2", @"MIDI C", @120], @[@"m3", @"MIDI D", @120]];
    for (NSArray *c in cols) { NSTableColumn *tc = [[NSTableColumn alloc] initWithIdentifier:c[0]]; tc.title = c[1]; tc.width = [c[2] doubleValue]; [_table addTableColumn:tc]; }
    [EDTheme styleLCDTable:_table];
    _tableScroll = [NSScrollView new]; _tableScroll.documentView = _table; _tableScroll.hasVerticalScroller = YES; _tableScroll.drawsBackground = NO; _tableScroll.borderType = NSNoBorder;
    _empty = [NSTextField labelWithString:@"Open a bank to edit the MIDI settings of its presets."]; _empty.font = [EDTheme lcdFont:14]; _empty.textColor = EDTheme.lcdInk;

    for (NSView *v in @[_title, _prev, _next, _rows, _tableScroll, _empty, _msg, _actions, _screen]) v.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView *v in @[_title, _prev, _next, _rows, _tableScroll, _empty, _msg, _actions]) [_screen addSubview:v];
    [self addSubview:_screen];

    // soft keys like F1…F6
    _softKeys = [NSMutableArray array];
    NSStackView *keys = [NSStackView new]; keys.spacing = 12; keys.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSInteger i = 0; i < 6; i++) {
        NSButton *b = [EDTheme lcdButton:@"" target:self action:@selector(softKey:)];
        b.tag = i;
        [b.widthAnchor constraintEqualToConstant:130].active = YES; [_softKeys addObject:b]; [keys addArrangedSubview:b];
    }
    _note = [NSTextField wrappingLabelWithString:@""];
    _note.textColor = NSColor.secondaryLabelColor; _note.font = [NSFont systemFontOfSize:12]; _note.translatesAutoresizingMaskIntoConstraints = NO;
    [_screen addSubview:keys]; [self addSubview:_note];   // the soft keys live in the green screen
    [EDTheme addGlareTo:_screen];

    [NSLayoutConstraint activateConstraints:@[
        [_screen.topAnchor constraintEqualToAnchor:self.topAnchor constant:40], [_screen.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_screen.widthAnchor constraintEqualToConstant:1100], [_screen.heightAnchor constraintGreaterThanOrEqualToConstant:430],
        [_screen.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:20], [_screen.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-20],
        [keys.leadingAnchor constraintEqualToAnchor:_screen.leadingAnchor constant:16], [keys.bottomAnchor constraintEqualToAnchor:_screen.bottomAnchor constant:-14],
        [_title.topAnchor constraintEqualToAnchor:_screen.topAnchor constant:14], [_title.centerXAnchor constraintEqualToAnchor:_screen.centerXAnchor],
        [_prev.topAnchor constraintEqualToAnchor:_screen.topAnchor constant:14], [_prev.leadingAnchor constraintEqualToAnchor:_screen.leadingAnchor constant:16],
        [_next.topAnchor constraintEqualToAnchor:_screen.topAnchor constant:14], [_next.trailingAnchor constraintEqualToAnchor:_screen.trailingAnchor constant:-16],
        [_rows.topAnchor constraintEqualToAnchor:_title.bottomAnchor constant:24], [_rows.leadingAnchor constraintEqualToAnchor:_screen.leadingAnchor constant:40],
        [_msg.topAnchor constraintEqualToAnchor:_title.bottomAnchor constant:24], [_msg.leadingAnchor constraintEqualToAnchor:_screen.leadingAnchor constant:40], [_msg.trailingAnchor constraintEqualToAnchor:_screen.trailingAnchor constant:-40],
        [_actions.topAnchor constraintEqualToAnchor:_msg.bottomAnchor constant:22], [_actions.leadingAnchor constraintEqualToAnchor:_screen.leadingAnchor constant:40],
        [_tableScroll.topAnchor constraintEqualToAnchor:_title.bottomAnchor constant:16], [_tableScroll.leadingAnchor constraintEqualToAnchor:_screen.leadingAnchor constant:12],
        [_tableScroll.trailingAnchor constraintEqualToAnchor:_screen.trailingAnchor constant:-12], [_tableScroll.bottomAnchor constraintEqualToAnchor:keys.topAnchor constant:-10],
        [_empty.centerXAnchor constraintEqualToAnchor:_tableScroll.centerXAnchor], [_empty.centerYAnchor constraintEqualToAnchor:_tableScroll.centerYAnchor],
        [keys.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_note.leadingAnchor constraintEqualToAnchor:_screen.leadingAnchor], [_note.trailingAnchor constraintEqualToAnchor:_screen.trailingAnchor],
        [_note.topAnchor constraintEqualToAnchor:_screen.bottomAnchor constant:14],
        [_note.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12]]];   // the green screen stretches down to the note, which sits at the bottom
    [self setMenu:@"MIDI"];
    return self;
}

// Left / Right arrow = PREV / NEXT page of the sampler menu being shown (not while a field is being edited).
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (_keyMonitor) { [NSEvent removeMonitor:_keyMonitor]; _keyMonitor = nil; }
    if (!self.window) return;
    __weak EDMIDIEditor *w = self;
    _keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *e) {
        EDMIDIEditor *me = w; if (!me || e.window != me.window || me.isHiddenOrHasHiddenAncestor) return e;
        if (e.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift)) return e;
        if (e.keyCode != 123 && e.keyCode != 124) return e;
        if ([me.window.firstResponder isKindOfClass:[NSText class]]) return e;
        return [me stepPage:e.keyCode == 124 ? 1 : -1] ? nil : e;
    }];
}
- (BOOL)stepPage:(NSInteger)d {
    NSMutableArray *idx = [NSMutableArray array];
    for (NSInteger gi = 0; gi < (NSInteger)_pages.count; gi++) if ([_pages[gi][@"menu"] isEqual:_menu]) [idx addObject:@(gi)];
    NSInteger pos = [idx indexOfObject:@(_page)], to = pos + d;
    if (pos == NSNotFound || to < 0 || to >= (NSInteger)idx.count) return NO;
    [self showPage:[idx[to] integerValue]]; return YES;
}
- (void)softKey:(NSButton *)b { [self showPage:b.tag]; }
// The soft keys follow the sampler's menu: "MIDI" (Master > MIDI) or "Setup" (Master > Setup).
- (void)setMenu:(NSString *)m {
    _menu = m; NSInteger k = 0, first = -1;
    for (NSInteger gi = 0; gi < (NSInteger)_pages.count; gi++) {
        if (![_pages[gi][@"menu"] isEqual:m]) continue;
        NSButton *b = _softKeys[k++]; b.title = _pages[gi][@"soft"]; b.tag = gi; b.hidden = NO; if (first < 0) first = gi;
    }
    for (; k < (NSInteger)_softKeys.count; k++) _softKeys[k].hidden = YES;
    _note.stringValue = [m isEqual:@"Bank"] ? @"Bank mirrors the sampler's Master ▸ Bank menu. Erase and Rename work on the open bank in the editor; Auto-Load and the resident FLASH functions belong to the sampler itself."
        : [m isEqual:@"FX"] ? @"FX mirrors the sampler's Master ▸ FX menu (effects board): the master effect types and the Effects Setup page. The sampler keeps them in its own memory and they cannot be read over SCSI, so set them here to match it."
        : [m isEqual:@"MIDI"] ? @"Mode, Cntrls and Prefs mirror the sampler's Master ▸ MIDI menus. The sampler keeps these in its own flash memory; they cannot be read over SCSI or sample dump, so set them here to match it. The device ID is shared with MIDI Sample Dump. The Presets page edits MIDI A–D inside the bank."
        : @"Tune, Output, Misc, SCSI and Import mirror the sampler's Master ▸ Setup menus (value ranges from the EOS manual). They live in the sampler's flash memory and cannot be read or written from here, so this is a reference profile to match the sampler by hand.";
    [self showPage:first];
}
- (void)showPage:(NSInteger)i {
    _page = i; NSDictionary *pg = _pages[i];
    for (NSButton *b in _softKeys) b.state = b.tag == i ? NSControlStateValueOn : NSControlStateValueOff;
    _title.stringValue = pg[@"title"]; _prev.stringValue = pg[@"prev"] ? [@"◀ PREV\n" stringByAppendingString:pg[@"prev"]] : @""; _next.stringValue = pg[@"next"] ? [@"NEXT ▶\n" stringByAppendingString:pg[@"next"]] : @"";
    BOOL isTable = [pg[@"table"] boolValue], isMsg = pg[@"message"] != nil;
    _msg.hidden = !isMsg; _actions.hidden = !isMsg;
    for (NSView *v in _actions.arrangedSubviews.copy) { [_actions removeArrangedSubview:v]; [v removeFromSuperview]; }
    if (isMsg) {
        _msg.stringValue = [(NSString *)pg[@"message"] containsString:@"%@"] ? [NSString stringWithFormat:pg[@"message"], self.bankTitle ?: @"(no bank open)"] : pg[@"message"];
        for (NSArray *a in pg[@"actions"]) {
            NSButton *b = [EDTheme lcdKey:a[0] target:self action:@selector(pageAction:)]; b.identifier = a[1];
            b.enabled = _bank != nil; [_actions addArrangedSubview:b];
        }
    }
    _rows.hidden = isTable; _tableScroll.hidden = !isTable; _empty.hidden = !isTable || _bank.presets.count > 0;
    for (NSView *v in _rows.arrangedSubviews.copy) { [_rows removeArrangedSubview:v]; [v removeFromSuperview]; }
    if (isTable) {
        for (NSInteger k = 0; k < 4; k++) {
            NSString *cc = _profile[[NSString stringWithFormat:@"midi%c", (char)('a' + k)]];
            [_table.tableColumns[2 + k].headerCell setStringValue:[NSString stringWithFormat:@"MIDI %c  (%@)", (char)('A' + k), cc]];
        }
        [_table.headerView setNeedsDisplay:YES]; [_table reloadData]; return;
    }
    NSArray *rows = pg[@"rows"], *fk = pg[@"fk"]; NSInteger perCol = pg[@"percol"] ? [pg[@"percol"] integerValue] : 4, ncol = (rows.count + perCol - 1) / perCol;
    for (NSInteger c = 0; c < ncol; c++) {
        NSStackView *col = [NSStackView new]; col.orientation = NSUserInterfaceLayoutOrientationVertical; col.alignment = NSLayoutAttributeLeading; col.spacing = 10;
        for (NSInteger r = c * perCol; r < MIN((NSInteger)rows.count, (c + 1) * perCol); r++) [col addArrangedSubview:[self rowViewFor:rows[r] fkey:r < (NSInteger)fk.count ? fk[r] : @""]];
        [_rows addArrangedSubview:col];
    }
}
- (NSView *)rowViewFor:(NSArray *)spec fkey:(NSString *)fk {
    NSTextField *box = [NSTextField labelWithString:fk]; box.font = [EDTheme lcdFont:12]; box.textColor = EDTheme.lcdInk; box.alignment = NSTextAlignmentCenter;
    box.wantsLayer = YES; box.layer.borderWidth = fk.length ? 1.5 : 0; box.layer.borderColor = EDTheme.lcdInk.CGColor; [box.widthAnchor constraintEqualToConstant:28].active = YES;
    NSTextField *lab = [NSTextField labelWithString:spec[1]]; lab.font = [EDTheme lcdFont:17]; lab.textColor = EDTheme.lcdInk; [lab.widthAnchor constraintGreaterThanOrEqualToConstant:210].active = YES;
    NSPopUpButton *pop = [[EDWheelPopUp alloc] initWithFrame:NSZeroRect pullsDown:NO]; pop.bordered = NO; pop.font = [EDTheme lcdFont:17]; pop.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];   // dark arrows on the green
    NSDictionary *attr = @{NSFontAttributeName: [EDTheme lcdFont:17], NSForegroundColorAttributeName: EDTheme.lcdInk};
    // the MIDI interface rows list the CoreMIDI ports present right now; the choice is shared with the MIDI Sample Dump panel (SDSOut / SDSIn)
    NSArray *options = spec[2]; NSString *current = nil; BOOL isIf = [spec[0] isEqual:@"ifout"] || [spec[0] isEqual:@"ifin"];
    if (isIf) {
        BOOL out = [spec[0] isEqual:@"ifout"]; NSMutableArray *names = [NSMutableArray array];
        for (EDMIDIEndpointInfo *e in (out ? EDMIDIPort.destinations : EDMIDIPort.sources)) [names addObject:e.name];
        if (!names.count) [names addObject:out ? @"(no MIDI outputs found)" : @"(no MIDI inputs found)"];
        options = names; current = [NSUserDefaults.standardUserDefaults stringForKey:out ? @"SDSOut" : @"SDSIn"];
    }
    for (NSString *o in options) { NSMenuItem *mi = [pop.menu addItemWithTitle:o action:nil keyEquivalent:@""]; mi.attributedTitle = [[NSAttributedString alloc] initWithString:o attributes:attr]; }
    [EDTheme styleLCDPopup:pop]; [pop selectItemWithTitle:isIf ? (current ?: options[0]) : (_profile[spec[0]] ?: options[0])]; if (isIf && pop.indexOfSelectedItem < 0) [pop selectItemAtIndex:0]; pop.identifier = spec[0]; pop.target = self; pop.action = @selector(profileChanged:);
    if (spec.count > 3) pop.enabled = NO;
    [pop.widthAnchor constraintGreaterThanOrEqualToConstant:130].active = YES;
    NSStackView *row = [NSStackView stackViewWithViews:@[box, lab, pop]]; row.spacing = 8; row.alignment = NSLayoutAttributeCenterY;
    return row;
}
- (void)pageAction:(NSButton *)b { if (self.action) self.action(b.identifier); }
- (void)setBankTitle:(NSString *)t { _bankTitle = [t copy]; if (_pages[_page][@"message"]) [self showPage:_page]; }
- (void)profileChanged:(NSPopUpButton *)p {
    if ([p.identifier isEqual:@"ifout"] || [p.identifier isEqual:@"ifin"]) {
        NSString *t = p.titleOfSelectedItem; if ([t hasPrefix:@"(no MIDI"]) return;
        [NSUserDefaults.standardUserDefaults setObject:t forKey:[p.identifier isEqual:@"ifout"] ? @"SDSOut" : @"SDSIn"]; return;
    }
    _profile[p.identifier] = p.titleOfSelectedItem;
    if ([p.identifier isEqual:@"memprefer"]) {   // Sequence Memory takes whatever Preset Memory leaves of the 406 K
        NSInteger v = p.titleOfSelectedItem.integerValue; _profile[@"seqmem"] = [NSString stringWithFormat:@"%ld K", (long)(406 - v)];
        if (self.memoryChanged) self.memoryChanged(v);
        [NSUserDefaults.standardUserDefaults setObject:_profile forKey:@"SamplerMIDIProfile"]; [self showPage:_page]; return;
    }
    [NSUserDefaults.standardUserDefaults setObject:_profile forKey:@"SamplerMIDIProfile"];
    if ([p.identifier isEqual:@"contrast"]) { [EDTheme setLcdContrast:p.titleOfSelectedItem.integerValue]; [self showPage:_page]; return; }   // like the sampler: the screens change at once
    if ([p.identifier isEqual:@"devid"]) [NSUserDefaults.standardUserDefaults setObject:p.titleOfSelectedItem forKey:@"SDSDevice"];   // same device ID as the sample dump panel
}

- (void)setBank:(EDBank *)b { _bank = b; [self reload]; }
- (void)reload { [_table reloadData]; _empty.hidden = ![_pages[_page][@"table"] boolValue] || _bank.presets.count > 0; }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return _bank ? (NSInteger)_bank.presets.count : 0; }

- (EDParam *)midiParam:(NSInteger)i of:(EDPreset *)p {
    NSMutableArray *m = [NSMutableArray array];
    for (EDParam *q in [p paramsForScope:EDScopePreset]) if ([q.group isEqual:@"MIDI"]) [m addObject:q];
    return i < (NSInteger)m.count ? m[i] : nil;
}
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)r {
    EDPreset *p = _bank.presets[r]; NSString *i = c.identifier;
    if ([i isEqual:@"num"]) return @(p.number);
    if ([i isEqual:@"name"]) return p.name;
    EDParam *q = [self midiParam:[[i substringFromIndex:1] integerValue] of:p];
    return q ? @([p valueOfParam:q voice:0 ref:0]) : @"–";
}
- (NSTableRowView *)tableView:(NSTableView *)t rowViewForRow:(NSInteger)r { return [EDTheme lcdRowView]; }
- (void)tableView:(NSTableView *)t willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)c row:(NSInteger)r {
    if ([cell isKindOfClass:[NSTextFieldCell class]]) { [(NSTextFieldCell *)cell setFont:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]]; [(NSTextFieldCell *)cell setTextColor:EDTheme.lcdInk]; [(NSTextFieldCell *)cell setDrawsBackground:NO]; }
}
- (BOOL)tableView:(NSTableView *)t shouldEditTableColumn:(NSTableColumn *)c row:(NSInteger)r {
    return [c.identifier hasPrefix:@"m"] && [self midiParam:0 of:_bank.presets[r]] != nil;
}
- (void)setValue:(NSInteger)v param:(NSInteger)i preset:(EDPreset *)p {
    EDParam *q = [self midiParam:i of:p]; if (!q) return;
    NSInteger old = [p valueOfParam:q voice:0 ref:0]; if (old == v) return;
    [[self.undoManager prepareWithInvocationTarget:self] setValue:old param:i preset:p];
    [self.undoManager setActionName:[NSString stringWithFormat:@"Change %@", q.label]];
    [p setValue:v ofParam:q voice:0 ref:0]; [_table reloadData]; if (self.edited) self.edited();
}
- (void)tableView:(NSTableView *)t setObjectValue:(id)o forTableColumn:(NSTableColumn *)c row:(NSInteger)r {
    [self setValue:[o integerValue] param:[[c.identifier substringFromIndex:1] integerValue] preset:_bank.presets[r]];
}
@end
