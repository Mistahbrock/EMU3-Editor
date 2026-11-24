// Hammond-style drawbar tone generator: renders an exactly periodic, seamlessly loopable organ tone.
// Ported from the Organ tool of Sample Surgeon. GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import "EDGenerator.h"
#import "EDTheme.h"
#import "EDGenScope.h"

static const int kHarm[9] = {1, 3, 2, 4, 6, 8, 10, 12, 16};          // harmonic number relative to the 16′ drawbar
static double amp(int v);
static NSString *const kFoot[9] = {@"16′", @"5⅓′", @"8′", @"4′", @"2⅔′", @"2′", @"1⅗′", @"1⅓′", @"1′"};

@interface EDOrganGenerator : NSObject <EDGeneratorPlugin>
@end

@implementation EDOrganGenerator {
    __weak id<EDGeneratorHost> _host;
    NSView *_view;
    int _bars[9];
    NSInteger _note;                 // MIDI note of the played key
    double _seconds, _rate, _attackMS, _level, _peakDB, _decayMS, _keyClick, _wheelLeak;
    EDDrawbarView *_drawbars; EDGenScope *_waveScope, *_specScope;
    NSTextField *_regLabel;
    NSMutableDictionary<NSString *, NSTextField *> *_valueLabels;
    NSMutableDictionary<NSString *, NSSlider *> *_paramSliders;
}
+ (NSString *)generatorIdentifier { return @"com.rhynoaudio.organ"; }
+ (NSString *)generatorName { return @"Organ"; }
+ (NSString *)generatorSummary { return @"Drawbar organ tone, exactly looped"; }

static void voicing(NSString *n, int *b, double *click, double *leak) {
    static const struct { const char *name; int bars[9]; double click, leak; } v[] = {
        {"Hammond B-3", {8,8,8,0,0,0,0,0,0}, 0.35, 0.35}, {"Hammond A-100 (vintage)", {8,8,8,8,0,0,0,0,4}, 0.6, 0.8},
        {"Hammond XK (modern)", {8,8,8,6,0,4,0,0,0}, 0.2, 0.1}, {"Vox Continental", {0,0,8,8,0,6,0,4,0}, 0.4, 0.5}, {"Farfisa Compact", {0,0,8,5,0,3,0,0,0}, 0, 0},
        {"Full organ 888 888 888", {8,8,8,8,8,8,8,8,8}, -1, -1}, {"Jimmy Smith 888 000 000", {8,8,8,0,0,0,0,0,0}, -1, -1}, {"Gospel 88 8800 000", {8,8,8,8,0,0,0,0,0}, -1, -1},
        {"Flute 00 8000 000", {0,0,8,0,0,0,0,0,0}, -1, -1}, {"Mellow 00 5300 000", {0,0,5,3,0,0,0,0,0}, -1, -1}, {"Rock 80 8000 008", {8,0,8,0,0,0,0,0,8}, -1, -1},
        {"Whistle 00 0000 888", {0,0,0,0,0,0,8,8,8}, -1, -1}};
    for (size_t i = 0; i < sizeof v / sizeof v[0]; i++) if ([n isEqualToString:@(v[i].name)]) {
        for (int k = 0; k < 9; k++) b[k] = v[i].bars[k];
        if (v[i].click >= 0) { *click = v[i].click; *leak = v[i].leak; }
        return;
    }
}
static NSArray<NSString *> *voicingNames(void) {
    return @[@"Hammond B-3", @"Hammond A-100 (vintage)", @"Hammond XK (modern)", @"Vox Continental", @"Farfisa Compact", @"Full organ 888 888 888", @"Jimmy Smith 888 000 000",
             @"Gospel 88 8800 000", @"Flute 00 8000 000", @"Mellow 00 5300 000", @"Rock 80 8000 008", @"Whistle 00 0000 888"];
}

- (instancetype)initWithHost:(id<EDGeneratorHost>)host {
    if (!(self = [super init])) return nil;
    _host = host; _note = 48; _seconds = 2; _rate = 48000; _attackMS = 0; _level = 1; _peakDB = 0; _decayMS = 0; _keyClick = 0; _wheelLeak = 0;
    int init[9] = {8, 8, 8, 0, 0, 0, 0, 0, 0}; for (int i = 0; i < 9; i++) _bars[i] = init[i];
    _valueLabels = [NSMutableDictionary dictionary]; _paramSliders = [NSMutableDictionary dictionary];
    [self buildView];
    return self;
}
- (NSView *)view { return _view; }

- (NSTextField *)label:(NSString *)t size:(CGFloat)sz {
    NSTextField *l = [NSTextField labelWithString:t]; l.font = [NSFont systemFontOfSize:sz]; l.textColor = EDTheme.labelWhite; return l;
}
static NSString *noteName(NSInteger n) { static NSString *nm[] = {@"C", @"C#", @"D", @"D#", @"E", @"F", @"F#", @"G", @"G#", @"A", @"A#", @"B"}; return [NSString stringWithFormat:@"%@%ld", nm[((n % 12) + 12) % 12], (long)(n / 12 - 1)]; }

- (void)buildView {
    NSMutableArray *rows = [NSMutableArray array];
    _drawbars = [EDDrawbarView new]; for (int i = 0; i < 9; i++) [_drawbars setLevel:_bars[i] at:i];
    __weak typeof(self) ws = self; _drawbars.onChange = ^{ [ws drawbarsMoved]; };
    _waveScope = [EDGenScope new]; _waveScope.caption = @"One cycle"; _specScope = [EDGenScope new]; _specScope.spectrum = YES; _specScope.caption = @"Harmonics";
    for (EDGenScope *sc in @[_waveScope, _specScope]) { [sc.widthAnchor constraintEqualToConstant:180].active = YES; [sc.heightAnchor constraintEqualToConstant:110].active = YES; }
    NSStackView *scopes = [NSStackView stackViewWithViews:@[_waveScope, _specScope]]; scopes.orientation = NSUserInterfaceLayoutOrientationVertical; scopes.spacing = 10;
    NSStackView *bars = [NSStackView stackViewWithViews:@[_drawbars, scopes]]; bars.spacing = 16; bars.alignment = NSLayoutAttributeTop;
    [rows addObject:bars];
    _regLabel = [self label:@"" size:14]; _regLabel.font = [NSFont monospacedSystemFontOfSize:14 weight:NSFontWeightBold];
    NSPopUpButton *pre = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [pre addItemWithTitle:@"Voicing…"]; [pre addItemsWithTitles:voicingNames()]; pre.target = self; pre.action = @selector(voicingPicked:);
    NSButton *off = [NSButton buttonWithTitle:@"All off" target:self action:@selector(allOff:)];
    NSStackView *regRow = [NSStackView stackViewWithViews:@[[self label:@"Registration" size:12], _regLabel, pre, off]]; regRow.spacing = 12; [rows addObject:regRow];
    // note
    NSPopUpButton *note = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSInteger n = 24; n <= 96; n++) { NSString *t = [NSString stringWithFormat:@"%@  (%ld)", noteName(n), (long)n]; [note addItemWithTitle:t]; note.lastItem.tag = n; }
    [note selectItemWithTag:_note]; note.target = self; note.action = @selector(notePicked:);
    NSPopUpButton *rate = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSNumber *r in @[@32000, @44100, @48000]) { [rate addItemWithTitle:[NSString stringWithFormat:@"%@ Hz", r]]; rate.lastItem.tag = r.integerValue; }
    [rate selectItemWithTag:(NSInteger)_rate]; rate.target = self; rate.action = @selector(ratePicked:);
    NSStackView *nr = [NSStackView stackViewWithViews:@[[self label:@"Note" size:12], note, [self label:@"Sample rate" size:12], rate]]; nr.spacing = 10; [rows addObject:nr];
    // parameters
    NSArray *params = @[@[@"seconds", @"Length (s)", @0.5, @6, @1], @[@"level", @"Loop level", @0.1, @1, @1], @[@"attack", @"Attack (ms)", @0, @200, @0], @[@"peak", @"Attack peak (dB)", @0, @12, @0],
                        @[@"decay", @"Decay to loop (ms)", @0, @600, @0], @[@"click", @"Key click", @0, @1, @0], @[@"leak", @"Tonewheel leak", @0, @1, @0]];
    NSGridView *grid = [NSGridView gridViewWithNumberOfColumns:3 rows:0]; grid.rowSpacing = 6; grid.columnSpacing = 10;
    for (NSArray *p in params) {
        NSSlider *s = [NSSlider sliderWithValue:[self valueFor:p[0]] minValue:[p[2] doubleValue] maxValue:[p[3] doubleValue] target:self action:@selector(paramMoved:)]; s.identifier = p[0];
        [s.widthAnchor constraintEqualToConstant:260].active = YES; _paramSliders[p[0]] = s;
        NSTextField *v = [self label:@"" size:12]; v.alignment = NSTextAlignmentRight; [v.widthAnchor constraintEqualToConstant:60].active = YES; _valueLabels[p[0]] = v;
        [grid addRowWithViews:@[[self label:p[1] size:12], s, v]];
    }
    [rows addObject:grid];
    NSStackView *st = [NSStackView stackViewWithViews:rows]; st.orientation = NSUserInterfaceLayoutOrientationVertical; st.alignment = NSLayoutAttributeLeading; st.spacing = 18;
    st.edgeInsets = NSEdgeInsetsMake(20, 24, 20, 24); _view = st;
    [self refreshLabels];
}
- (double)valueFor:(NSString *)k {
    if ([k isEqual:@"seconds"]) return _seconds; if ([k isEqual:@"level"]) return _level; if ([k isEqual:@"attack"]) return _attackMS; if ([k isEqual:@"peak"]) return _peakDB;
    if ([k isEqual:@"decay"]) return _decayMS; if ([k isEqual:@"click"]) return _keyClick; return _wheelLeak;
}
- (void)setValue:(double)v for:(NSString *)k {
    if ([k isEqual:@"seconds"]) _seconds = v; else if ([k isEqual:@"level"]) _level = v; else if ([k isEqual:@"attack"]) _attackMS = v; else if ([k isEqual:@"peak"]) _peakDB = v;
    else if ([k isEqual:@"decay"]) _decayMS = v; else if ([k isEqual:@"click"]) _keyClick = v; else _wheelLeak = v;
}
- (NSString *)registration {
    return [NSString stringWithFormat:@"%d%d %d%d%d%d %d%d%d", _bars[0], _bars[1], _bars[2], _bars[3], _bars[4], _bars[5], _bars[6], _bars[7], _bars[8]];
}
- (void)updateScopes {
    double sp[20] = {0}; for (int i = 0; i < 9; i++) sp[kHarm[i]] += amp(_bars[i]);
    NSMutableArray *w = [NSMutableArray array], *h = [NSMutableArray array]; double pk = 1e-9, top = 1e-9;
    double y[256]; for (int i = 0; i < 256; i++) { y[i] = 0; for (int k = 1; k < 20; k++) y[i] += sp[k] * sin(2 * M_PI * k * i / 256.0); pk = MAX(pk, fabs(y[i])); }
    for (int i = 0; i < 256; i++) [w addObject:@(y[i] / pk)];
    for (int k = 1; k < 20; k++) top = MAX(top, sp[k]); for (int k = 1; k < 20; k++) [h addObject:@(sp[k] / top)];
    _waveScope.values = w; _specScope.values = h;
}
- (void)refreshLabels {
    _regLabel.stringValue = [self registration]; [self updateScopes];
    for (NSString *k in _valueLabels) {
        double v = [self valueFor:k]; NSString *t = ([k isEqual:@"attack"] || [k isEqual:@"decay"]) ? [NSString stringWithFormat:@"%.0f", v] : ([k isEqual:@"peak"] ? [NSString stringWithFormat:@"%.1f", v] : [NSString stringWithFormat:@"%.2f", v]);
        _valueLabels[k].stringValue = t;
    }
}
- (void)syncControls { for (int i = 0; i < 9; i++) [_drawbars setLevel:_bars[i] at:i]; for (NSString *k in _paramSliders) _paramSliders[k].doubleValue = [self valueFor:k]; [self refreshLabels]; }
- (void)drawbarsMoved { for (int i = 0; i < 9; i++) _bars[i] = [_drawbars levelAt:i]; [self refreshLabels]; [_host generatorChanged]; }
- (void)paramMoved:(NSSlider *)s { [self setValue:s.doubleValue for:s.identifier]; [self refreshLabels]; [_host generatorChanged]; }
- (void)notePicked:(NSPopUpButton *)p { _note = p.selectedItem.tag; [_host generatorChanged]; }
- (void)ratePicked:(NSPopUpButton *)p { _rate = p.selectedItem.tag; [_host generatorChanged]; }
- (void)allOff:(id)s { for (int i = 0; i < 9; i++) _bars[i] = 0; [self syncControls]; [_host generatorChanged]; }
- (void)voicingPicked:(NSPopUpButton *)p {
    if (p.indexOfSelectedItem == 0) return;
    voicing(p.titleOfSelectedItem, _bars, &_keyClick, &_wheelLeak); [p selectItemAtIndex:0]; [self syncControls]; [_host generatorChanged];
}

// MARK: rendering

static double amp(int v) { return v <= 0 ? 0 : pow(10, (v - 8) * 3 / 20.0); }

- (EDGeneratedSample *)render {
    BOOL any = NO; for (int i = 0; i < 9; i++) if (_bars[i] > 0) any = YES; if (!any) return nil;
    double f0 = 440 * pow(2, (_note - 69) / 12.0) / 2, P = _rate / f0;                  // master (16′) frequency and period in frames
    double minLoop = MAX(0.25, MIN(_seconds, 1.0));
    NSInteger mStart = MAX(1, (NSInteger)ceil(minLoop * f0)), bestM = mStart; double bestErr = INFINITY;
    for (NSInteger m = mStart; m < mStart + 60; m++) {                                  // the cycle count with the least pitch error
        double Lm = round(m * P), err = fabs(Lm / m - P) / P;
        if (err < bestErr) { bestErr = err; bestM = m; }
        if (err < 2e-5) break;
    }
    NSInteger L = (NSInteger)llround(bestM * P);
    double sp[20] = {0}; for (int i = 0; i < 9; i++) sp[kHarm[i]] += amp(_bars[i]);
    if (_wheelLeak > 0) { double top = 0; for (int h = 0; h < 20; h++) top = MAX(top, sp[h]); static const int leak[] = {5, 7, 9, 11, 13, 14, 15}; for (int k = 0; k < 7; k++) sp[leak[k]] += 0.02 * _wheelLeak * top; }
    double *y = calloc((size_t)L, sizeof(double));
    for (int h = 1; h < 20; h++) if (sp[h] > 0) { double w = 2 * M_PI * (double)(h * bestM) / L; for (NSInteger i = 0; i < L; i++) y[i] += sp[h] * sin(w * i); }
    double pk = 1e-9; for (NSInteger i = 0; i < L; i++) pk = MAX(pk, fabs(y[i]));
    double g = 0.8 * _level / pk;
    BOOL click = _keyClick > 0, shaped = _attackMS > 0 || (_peakDB > 0 && _decayMS > 0), intro = click || shaped;
    NSInteger nEnv = shaped ? (NSInteger)((_attackMS + _decayMS) / 1000 * _rate * 1.1) + 8 : 0;
    NSInteger introReps = intro ? MAX(1, (NSInteger)ceil((double)MAX(nEnv, (NSInteger)(0.02 * _rate)) / L)) : 0;
    NSInteger reps = MAX(introReps + 1, (NSInteger)ceil(_seconds * _rate / L));
    NSInteger total = L * reps;
    if (total > 8 * 1024 * 1024) { free(y); return nil; }
    float *ch = malloc(sizeof(float) * (size_t)total);
    for (NSInteger r = 0; r < reps; r++) for (NSInteger i = 0; i < L; i++) ch[r * L + i] = (float)(y[i] * g);
    if (shaped) {   // each harmonic ramps in on its own (higher drawbars speak sooner); the overshoot then falls in a straight line to the loop level
        double Pk = pow(10, _peakDB / 20); NSInteger N = MIN(L * introReps, nEnv);
        for (NSInteger i = 0; i < N; i++) {
            double tm = (double)i / _rate * 1000, over = 1;
            if (tm < _attackMS) over = Pk; else if (_decayMS > 0 && tm < _attackMS + _decayMS) { double u = (tm - _attackMS) / _decayMS; over = Pk + (1 - Pk) * u; }
            double v = 0;
            for (int h = 1; h < 20; h++) if (sp[h] > 0) {
                double e = 1; if (_attackMS > 0) { double ah = MAX(0.002, _attackMS / 1000 / (1 + 0.35 * (h - 1))); e = MIN(1, tm / 1000 / ah); }
                v += sp[h] * sin(2 * M_PI * (double)(h * bestM) / L * i) * e;
            }
            ch[i] = (float)(v * g * over);
        }
    }
    if (click) {    // a few ms of decaying, high-passed noise at the note start, plus a tiny tone ramp when there is no attack
        uint64_t rng = 0xC11CC11C1234ULL | 1; double prev = 0;
        if (!shaped) { NSInteger ramp = MAX(1, (NSInteger)(0.003 * _rate)); for (NSInteger i = 0; i < ramp; i++) ch[i] *= (float)i / ramp; }
        NSInteger len = (NSInteger)(0.012 * _rate);
        for (NSInteger i = 0; i < MIN(len, total); i++) {
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; double x = ((double)(rng >> 11) / 9007199254740992.0) * 2 - 1;
            double hp = x - prev; prev = x; ch[i] += (float)(hp * exp(-(double)i / (0.0025 * _rate)) * 0.6 * _keyClick);
        }
        double cp = 0; for (NSInteger i = 0; i < MIN(total, len * 2); i++) cp = MAX(cp, fabs(ch[i]));
        if (cp > 0.98) { float k = (float)(0.98 / cp); for (NSInteger i = 0; i < MIN(len * 4, total); i++) ch[i] *= k; }
    }
    NSMutableData *out = [NSMutableData dataWithLength:(size_t)total * 2]; int16_t *o = out.mutableBytes;
    for (NSInteger i = 0; i < total; i++) { double v = ch[i] * 32767.0; o[i] = (int16_t)(v > 32767 ? 32767 : (v < -32768 ? -32768 : lrint(v))); }
    free(y); free(ch);
    EDGeneratedSample *s = [EDGeneratedSample new];
    NSMutableString *regs = [NSMutableString string]; for (int i = 0; i < 9; i++) [regs appendFormat:@"%d", _bars[i]];
    s.name = [NSString stringWithFormat:@"Org %@ %@", regs, noteName(_note)]; s.sampleRate = (uint32_t)_rate; s.left = out; s.right = nil;
    s.loop = YES; s.loopStart = (NSUInteger)(L * introReps); s.loopEnd = (NSUInteger)(L * reps - 1);
    return s;
}
@end
