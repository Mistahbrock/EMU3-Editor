// Simple Tones — the generator that ships with the editor: sine, triangle, saw, square and pulse, exactly looped.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import "EDGenerator.h"
#import "EDTheme.h"

@interface EDSimpleTonesGenerator : NSObject <EDGeneratorPlugin>
@end

@implementation EDSimpleTonesGenerator {
    __weak id<EDGeneratorHost> _host;
    NSView *_view;
    NSInteger _wave, _note, _rate;
    double _pw, _seconds, _level, _attack;
    NSMutableDictionary<NSString *, NSSlider *> *_sliders;
    NSMutableDictionary<NSString *, NSTextField *> *_vals;
}
+ (NSString *)generatorIdentifier { return @"com.rhynoaudio.simpletones"; }
+ (NSString *)generatorName { return @"Simple Tones"; }
+ (NSString *)generatorSummary { return @"Sine, triangle, saw, square and pulse, exactly looped"; }

static NSString *noteName(NSInteger n) { static NSString *nm[] = {@"C", @"C#", @"D", @"D#", @"E", @"F", @"F#", @"G", @"G#", @"A", @"A#", @"B"}; return [NSString stringWithFormat:@"%@%ld", nm[((n % 12) + 12) % 12], (long)(n / 12 - 1)]; }
static NSArray *waveNames(void) { return @[@"Sine", @"Triangle", @"Saw", @"Square", @"Pulse"]; }

- (instancetype)initWithHost:(id<EDGeneratorHost>)host {
    if (!(self = [super init])) return nil;
    _host = host; _wave = 0; _note = 48; _rate = 48000; _pw = 0.25; _seconds = 2; _level = 0.9; _attack = 0;
    _sliders = [NSMutableDictionary dictionary]; _vals = [NSMutableDictionary dictionary]; [self buildView];
    return self;
}
- (NSView *)view { return _view; }
- (NSTextField *)label:(NSString *)t { NSTextField *l = [NSTextField labelWithString:t]; l.font = [NSFont systemFontOfSize:12]; l.textColor = EDTheme.labelWhite; return l; }
- (double)valueFor:(NSString *)k { return [k isEqual:@"pw"] ? _pw : [k isEqual:@"seconds"] ? _seconds : [k isEqual:@"level"] ? _level : _attack; }

- (void)buildView {
    NSPopUpButton *wave = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [wave addItemsWithTitles:waveNames()]; wave.target = self; wave.action = @selector(wavePicked:);
    NSPopUpButton *note = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSInteger n = 24; n <= 96; n++) { [note addItemWithTitle:[NSString stringWithFormat:@"%@  (%ld)", noteName(n), (long)n]]; note.lastItem.tag = n; }
    [note selectItemWithTag:_note]; note.target = self; note.action = @selector(notePicked:);
    NSPopUpButton *rate = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSNumber *r in @[@32000, @44100, @48000]) { [rate addItemWithTitle:[NSString stringWithFormat:@"%@ Hz", r]]; rate.lastItem.tag = r.integerValue; }
    [rate selectItemWithTag:_rate]; rate.target = self; rate.action = @selector(ratePicked:);
    NSStackView *top = [NSStackView stackViewWithViews:@[[self label:@"Wave"], wave, [self label:@"Note"], note, [self label:@"Sample rate"], rate]]; top.spacing = 10;
    NSGridView *grid = [NSGridView gridViewWithNumberOfColumns:3 rows:0]; grid.rowSpacing = 6; grid.columnSpacing = 10;
    for (NSArray *p in @[@[@"pw", @"Pulse width", @0.05, @0.5], @[@"seconds", @"Length (s)", @0.5, @6], @[@"level", @"Level", @0.1, @1], @[@"attack", @"Attack (ms)", @0, @300]]) {
        NSSlider *s = [NSSlider sliderWithValue:[self valueFor:p[0]] minValue:[p[2] doubleValue] maxValue:[p[3] doubleValue] target:self action:@selector(moved:)]; s.identifier = p[0];
        [s.widthAnchor constraintEqualToConstant:260].active = YES; _sliders[p[0]] = s;
        NSTextField *v = [self label:@""]; v.alignment = NSTextAlignmentRight; [v.widthAnchor constraintEqualToConstant:60].active = YES; _vals[p[0]] = v;
        [grid addRowWithViews:@[[self label:p[1]], s, v]];
    }
    NSStackView *st = [NSStackView stackViewWithViews:@[top, grid]]; st.orientation = NSUserInterfaceLayoutOrientationVertical; st.alignment = NSLayoutAttributeLeading;
    st.spacing = 18; st.edgeInsets = NSEdgeInsetsMake(20, 24, 20, 24); _view = st; [self refresh];
}
- (void)refresh { for (NSString *k in _vals) _vals[k].stringValue = [k isEqual:@"attack"] ? [NSString stringWithFormat:@"%.0f", [self valueFor:k]] : [NSString stringWithFormat:@"%.2f", [self valueFor:k]]; }
- (void)wavePicked:(NSPopUpButton *)p { _wave = p.indexOfSelectedItem; [_host generatorChanged]; }
- (void)notePicked:(NSPopUpButton *)p { _note = p.selectedItem.tag; [_host generatorChanged]; }
- (void)ratePicked:(NSPopUpButton *)p { _rate = p.selectedItem.tag; [_host generatorChanged]; }
- (void)moved:(NSSlider *)s {
    NSString *k = s.identifier; if ([k isEqual:@"pw"]) _pw = s.doubleValue; else if ([k isEqual:@"seconds"]) _seconds = s.doubleValue; else if ([k isEqual:@"level"]) _level = s.doubleValue; else _attack = s.doubleValue;
    [self refresh]; [_host generatorChanged];
}

// Band-limited additive cycle: every harmonic below Nyquist, so nothing aliases at any pitch.
static double harmonic(NSInteger wave, int h, double pw) {
    switch (wave) {
        case 0: return h == 1 ? 1 : 0;
        case 1: return (h & 1) ? ((((h - 1) / 2) & 1) ? -1 : 1) / (double)(h * h) : 0;
        case 2: return 1.0 / h;
        case 3: return (h & 1) ? 1.0 / h : 0;
        default: return sin(M_PI * h * pw) / h;   // pulse: cosine series, handled below
    }
}
- (EDGeneratedSample *)render {
    double f = 440 * pow(2, (_note - 69) / 12.0), P = _rate / f, minLoop = MAX(0.25, MIN(_seconds, 1.0));
    NSInteger mStart = MAX(1, (NSInteger)ceil(minLoop * f)), bestM = mStart; double bestErr = INFINITY;
    for (NSInteger m = mStart; m < mStart + 60; m++) { double Lm = round(m * P), err = fabs(Lm / m - P) / P; if (err < bestErr) { bestErr = err; bestM = m; } if (err < 2e-5) break; }
    NSInteger L = (NSInteger)llround(bestM * P); int hMax = MAX(1, (int)(0.45 * _rate / f));
    double *y = calloc((size_t)L, sizeof(double));
    for (int h = 1; h <= hMax; h++) {
        double a = harmonic(_wave, h, _pw); if (a == 0) continue;
        double w = 2 * M_PI * (double)(h * bestM) / L, cw = cos(w), sw = sin(w), cc = 1, ss = 0;
        BOOL pulse = _wave == 4;
        for (NSInteger i = 0; i < L; i++) { y[i] += a * (pulse ? cc : ss); double nc = cc * cw - ss * sw; ss = ss * cw + cc * sw; cc = nc; }
    }
    double pk = 1e-9; for (NSInteger i = 0; i < L; i++) pk = MAX(pk, fabs(y[i]));
    double g = 0.9 * _level / pk; NSInteger att = (NSInteger)(_attack / 1000 * _rate);
    NSInteger introReps = att > 0 ? MAX(1, (NSInteger)ceil((double)att / L)) : 0, reps = MAX(introReps + 1, (NSInteger)ceil(_seconds * _rate / L)), total = L * reps;
    if (total > 8 * 1024 * 1024) { free(y); return nil; }
    NSMutableData *out = [NSMutableData dataWithLength:(size_t)total * 2]; int16_t *o = out.mutableBytes;
    for (NSInteger i = 0; i < total; i++) { double v = y[i % L] * g * 32767.0; if (i < att) v *= (double)i / att; o[i] = (int16_t)(v > 32767 ? 32767 : (v < -32768 ? -32768 : lrint(v))); }
    free(y);
    EDGeneratedSample *s = [EDGeneratedSample new];
    s.name = [NSString stringWithFormat:@"%@ %@", waveNames()[_wave], noteName(_note)]; s.sampleRate = (uint32_t)_rate; s.left = out; s.right = nil;
    s.loop = YES; s.loopStart = (NSUInteger)(L * introReps); s.loopEnd = (NSUInteger)(total - 1);
    return s;
}
@end
