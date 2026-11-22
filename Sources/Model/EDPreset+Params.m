#import "EDPreset+Params.h"
#import "EDBankInternal.h"
#import "EDDefaultPreset.h"

enum { kE4Header = 84, kE4Voice = 284, kE4Ref = 22, kLegHeader = 142, kLegVoice = 48 };

@implementation EDParam
+ (NSString *)noteName:(NSInteger)n {
    static NSString *const names[] = {@"C", @"C#", @"D", @"D#", @"E", @"F", @"F#", @"G", @"G#", @"A", @"A#", @"B"};
    if (n < 0 || n > 127) return [NSString stringWithFormat:@"%ld", (long)n];
    return [NSString stringWithFormat:@"%@%ld", names[n % 12], (long)(n / 12) - 2];   // middle C (60) = C3, as on E-mu samplers
}
- (NSString *)displayForValue:(NSInteger)v {
    NSString *n = self.names[@(v)]; if (n) return n;
    return self.isNote ? [EDParam noteName:v] : @"";
}
@end

// MARK: parameter tables

static EDParam *mk(NSString *group, NSString *label, EDParamScope sc, NSUInteger off, EDParamType t, NSInteger lo, NSInteger hi) {
    EDParam *p = [EDParam new]; p.group = group; p.label = label; p.scope = sc; p.offset = off; p.type = t; p.min = lo; p.max = hi; return p;
}
static void add(NSMutableArray *a, EDParam *p) { [a addObject:p]; }
static void window(NSMutableArray *a, NSString *g, NSString *name, EDParamScope sc, NSUInteger off, BOOL note) {
    NSArray *l = @[@"low", @"fade low", @"fade high", @"high"];
    for (int i = 0; i < 4; i++) { EDParam *p = mk(g, [NSString stringWithFormat:@"%@ %@", name, l[i]], sc, off + i, EDParamU8, 0, 127); p.isNote = note; add(a, p); }
}
static NSDictionary *filterNames(void) {
    return @{@0: @"4 Pole Low-pass", @1: @"2 Pole Low-pass", @2: @"6 Pole Low-pass", @8: @"2nd Order High-pass", @9: @"4th Order High-pass",
             @16: @"2nd Order Band-pass", @17: @"4th Order Band-pass", @18: @"Contrary Band-pass", @32: @"Swept EQ 1 octave",
             @33: @"Swept EQ 2->1 octave", @34: @"Swept EQ 3->1 octave", @64: @"Phaser 1", @65: @"Phaser 2", @66: @"Bat-Phaser",
             @72: @"Flanger Lite", @80: @"Vocal Ah-Ay-Ee", @81: @"Vocal Oo-Ah", @97: @"2EQ+Lowpass Morph", @104: @"Peak/Shelf Morph"};
}
static void envelope(NSMutableArray *a, NSString *g, NSUInteger base) {
    NSArray *st = @[@"Attack 1", @"Attack 2", @"Decay 1", @"Decay 2", @"Release 1", @"Release 2"];
    for (int i = 0; i < 6; i++) {
        add(a, mk(g, [st[i] stringByAppendingString:@" rate"], EDScopeVoice, base + i * 2, EDParamU8, 0, 127));
        add(a, mk(g, [st[i] stringByAppendingString:@" level"], EDScopeVoice, base + i * 2 + 1, EDParamS8, -127, 127));
    }
}
static void lfo(NSMutableArray *a, NSString *g, NSUInteger base) {
    add(a, mk(g, @"Rate", EDScopeVoice, base, EDParamU8, 0, 127));
    EDParam *sh = mk(g, @"Shape", EDScopeVoice, base + 1, EDParamU8, 0, 255);
    sh.names = @{@0: @"Triangle", @1: @"Sine", @2: @"Sawtooth", @3: @"Square", @14: @"Sine+noise", @255: @"Random"}; add(a, sh);
    add(a, mk(g, @"Delay", EDScopeVoice, base + 2, EDParamU8, 0, 127));
    add(a, mk(g, @"Variation %", EDScopeVoice, base + 3, EDParamU8, 0, 127));
    add(a, mk(g, @"Key sync", EDScopeVoice, base + 4, EDParamU8, 0, 1));
}
static void effect(NSMutableArray *a, NSString *g, NSUInteger base, NSInteger maxFx) {
    add(a, mk(g, @"Effect", EDScopePreset, base, EDParamU8, 0, maxFx));
    for (int i = 1; i <= 3; i++) add(a, mk(g, [NSString stringWithFormat:@"Parameter %d", i], EDScopePreset, base + i, EDParamU8, 0, 127));
    add(a, mk(g, @"Main send", EDScopePreset, base + 4, EDParamU8, 0, 100));
    for (int i = 1; i <= 3; i++) add(a, mk(g, [NSString stringWithFormat:@"Sub %d send", i], EDScopePreset, base + 4 + i, EDParamU8, 0, 100));
}

static NSArray<EDParam *> *e4Params(EDParamScope scope) {
    static NSArray *tab[3];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *h = [NSMutableArray array];
        EDParam *lc = mk(@"Preset", @"Link count", EDScopePreset, 20, EDParamU8, 0, 254); lc.readOnly = YES; add(h, lc);
        EDParam *vc = mk(@"Preset", @"Voice count", EDScopePreset, 21, EDParamU8, 0, 255); vc.readOnly = YES; add(h, vc);
        add(h, mk(@"Preset", @"Transpose", EDScopePreset, 26, EDParamS8, -24, 24));
        add(h, mk(@"Preset", @"Volume dB", EDScopePreset, 27, EDParamS8, -96, 10));
        for (int i = 0; i < 4; i++) add(h, mk(@"MIDI", [NSString stringWithFormat:@"MIDI %c", 'A' + i], EDScopePreset, 56 + i, EDParamS8, -1, 127));
        effect(h, @"Effect A", 60, 44); effect(h, @"Effect B", 68, 27);
        tab[0] = h;

        NSMutableArray *v = [NSMutableArray array];
        add(v, mk(@"Voice", @"Group", EDScopeVoice, 3, EDParamU8, 0, 31));
        add(v, mk(@"Voice", @"Assign group", EDScopeVoice, 25, EDParamU8, 0, 23));
        EDParam *sc = mk(@"Voice", @"Sample count", EDScopeVoice, 2, EDParamU8, 1, 255); sc.readOnly = YES; add(v, sc);
        add(v, mk(@"Voice", @"Delay", EDScopeVoice, 26, EDParamU16BE, 0, 10000));
        add(v, mk(@"Voice", @"Start offset", EDScopeVoice, 31, EDParamU8, 0, 127));
        window(v, @"Windows", @"Key", EDScopeVoice, 12, YES);
        window(v, @"Windows", @"Velocity", EDScopeVoice, 16, NO);
        window(v, @"Windows", @"Realtime", EDScopeVoice, 20, NO);
        add(v, mk(@"Tuning", @"Transpose", EDScopeVoice, 32, EDParamS8, -24, 24));
        add(v, mk(@"Tuning", @"Coarse tune", EDScopeVoice, 33, EDParamS8, -72, 24));
        add(v, mk(@"Tuning", @"Fine tune", EDScopeVoice, 34, EDParamS8, -64, 64));
        add(v, mk(@"Tuning", @"Non-transpose", EDScopeVoice, 36, EDParamU8, 0, 1));
        add(v, mk(@"Glide", @"Glide rate", EDScopeVoice, 35, EDParamU8, 0, 127));
        add(v, mk(@"Glide", @"Glide curve", EDScopeVoice, 51, EDParamU8, 0, 8));
        add(v, mk(@"Glide", @"Solo mode", EDScopeVoice, 37, EDParamU8, 0, 8));
        add(v, mk(@"Chorus", @"Stereo width", EDScopeVoice, 39, EDParamS8, -128, 127));
        add(v, mk(@"Chorus", @"Amount %", EDScopeVoice, 40, EDParamU8, 0, 127));
        add(v, mk(@"Chorus", @"ITD", EDScopeVoice, 42, EDParamU8, 0, 255));
        add(v, mk(@"Output", @"Volume dB", EDScopeVoice, 52, EDParamS8, -96, 10));
        add(v, mk(@"Output", @"Pan", EDScopeVoice, 53, EDParamS8, -64, 63));
        add(v, mk(@"Output", @"Sub mix", EDScopeVoice, 54, EDParamU8, 0, 7));
        add(v, mk(@"Output", @"Amp envelope depth", EDScopeVoice, 55, EDParamU8, 0, 16));
        EDParam *ft = mk(@"Filter", @"Filter type", EDScopeVoice, 56, EDParamU8, 0, 127); ft.names = filterNames(); add(v, ft);
        add(v, mk(@"Filter", @"Frequency", EDScopeVoice, 58, EDParamU8, 0, 255));
        add(v, mk(@"Filter", @"Resonance", EDScopeVoice, 59, EDParamU8, 0, 127));
        for (int i = 3; i <= 8; i++) add(v, mk(@"Filter", [NSString stringWithFormat:@"Parameter %d", i], EDScopeVoice, 59 + i, EDParamU8, 0, 255));
        envelope(v, @"Volume envelope", 108); envelope(v, @"Filter envelope", 122); envelope(v, @"Aux envelope", 136);
        lfo(v, @"LFO 1", 150); lfo(v, @"LFO 2", 158);
        add(v, mk(@"Lag", @"Lag 0", EDScopeVoice, 165, EDParamU8, 0, 10)); add(v, mk(@"Lag", @"Lag 1", EDScopeVoice, 167, EDParamU8, 0, 10));
        for (int i = 0; i < 24; i++) {
            NSString *g = [NSString stringWithFormat:@"Cord %d", i + 1];
            add(v, mk(g, @"Source", EDScopeVoice, 188 + i * 4, EDParamU8, 0, 255));
            add(v, mk(g, @"Destination", EDScopeVoice, 188 + i * 4 + 1, EDParamU8, 0, 255));
            add(v, mk(g, @"Amount %", EDScopeVoice, 188 + i * 4 + 2, EDParamS8, -127, 127));
        }
        tab[1] = v;

        NSMutableArray *r = [NSMutableArray array];
        EDParam *sn = mk(@"Sample", @"Sample number", EDScopeRef, 8, EDParamU16BE, 0, 2999); sn.isSample = YES; add(r, sn);
        EDParam *rk = mk(@"Sample", @"Root key", EDScopeRef, 12, EDParamU8, 0, 127); rk.isNote = YES; add(r, rk);
        add(r, mk(@"Sample", @"Fine tune", EDScopeRef, 10, EDParamS16BE, -64, 64));
        add(r, mk(@"Sample", @"Volume dB", EDScopeRef, 13, EDParamS8, -96, 10));
        add(r, mk(@"Sample", @"Pan", EDScopeRef, 14, EDParamS8, -64, 63));
        window(r, @"Windows", @"Key", EDScopeRef, 0, YES);
        window(r, @"Windows", @"Velocity", EDScopeRef, 4, NO);
        tab[2] = r;
    });
    return tab[scope];
}

/// 3X presets: header and voice layout from emu3bm's structs, checked on 3,354 presets; only the sample reference
/// of a voice is named — the other voice bytes are exposed raw.
static NSArray<EDParam *> *legacyParams(EDParamScope scope, NSUInteger zones) {
    NSMutableArray *a = [NSMutableArray array];
    if (scope == EDScopePreset) {
        for (int i = 0; i < 12; i++) add(a, mk(@"Realtime controls", [NSString stringWithFormat:@"Control %d", i + 1], EDScopePreset, 16 + i, EDParamS8, -128, 127));
        add(a, mk(@"Preset", @"Pitch bend range", EDScopePreset, 44, EDParamU8, 0, 255));
        add(a, mk(@"Preset", @"Primary velocity low", EDScopePreset, 45, EDParamU8, 0, 255));
        add(a, mk(@"Preset", @"Primary velocity high", EDScopePreset, 46, EDParamU8, 0, 255));
        add(a, mk(@"Preset", @"Secondary velocity low", EDScopePreset, 47, EDParamU8, 0, 255));
        add(a, mk(@"Preset", @"Secondary velocity high", EDScopePreset, 48, EDParamU8, 0, 255));
        add(a, mk(@"Preset", @"Link preset (LSB)", EDScopePreset, 49, EDParamU8, 0, 255));
        add(a, mk(@"Preset", @"Link preset (MSB)", EDScopePreset, 50, EDParamU8, 0, 255));
        EDParam *nz = mk(@"Preset", @"Zones", EDScopePreset, 53, EDParamU8, 0, 255); nz.readOnly = YES; add(a, nz);
        for (NSUInteger k = 0; k < zones; k++) {
            NSString *g = @"Zone voices";
            EDParam *p1 = mk(g, [NSString stringWithFormat:@"Zone %lu primary voice", (unsigned long)k], EDScopePreset, kLegHeader + 4 * k + 2, EDParamU8, 0, 255);
            EDParam *p2 = mk(g, [NSString stringWithFormat:@"Zone %lu secondary voice", (unsigned long)k], EDScopePreset, kLegHeader + 4 * k + 3, EDParamU8, 0, 255);
            p1.names = p2.names = @{@255: @"none"}; add(a, p1); add(a, p2);
        }
        for (int i = 0; i < 88; i++) {
            EDParam *p = mk(@"Key map (zone per key)", [EDParam noteName:21 + i], EDScopePreset, 54 + i, EDParamU8, 0, 255);
            p.names = @{@255: @"—"}; add(a, p);
        }
    } else if (scope == EDScopeVoice) {
        EDParam *s = mk(@"Voice", @"Sample number", EDScopeVoice, 1, EDParamU8, 0, 255); s.isSample = YES; add(a, s);
        for (int i = 0; i < kLegVoice; i++) if (i != 1) add(a, mk(@"Raw bytes (not decoded)", [NSString stringWithFormat:@"Byte 0x%02X", i], EDScopeVoice, i, EDParamU8, 0, 255));
    }
    return a;
}

// MARK: layout

@implementation EDPreset (Params)

- (BOOL)isE4 { return self.kind == EDPresetKindE4; }
- (BOOL)canEditStructure { return self.kind == EDPresetKindE4; }
- (const uint8_t *)bytes { return self.raw.bytes; }

- (NSArray<EDParam *> *)paramsForScope:(EDParamScope)scope {
    if (self.kind == EDPresetKindE4) return e4Params(scope);
    return legacyParams(scope, self.raw.length > 53 ? ((const uint8_t *)self.raw.bytes)[53] : 0);
}

- (NSUInteger)e4VoiceBase:(NSInteger)v {
    const uint8_t *b = self.raw.bytes; NSUInteger len = self.raw.length, q = kE4Header;
    for (NSInteger i = 0; i < v; i++) { if (q + kE4Voice > len) return NSNotFound; q += kE4Voice + kE4Ref * b[q + 2]; }
    return q + kE4Voice <= len ? q : NSNotFound;
}
- (NSUInteger)legVoiceBase:(NSInteger)v {
    NSUInteger q = kLegHeader + 4 * (self.raw.length > 53 ? ((const uint8_t *)self.raw.bytes)[53] : 0) + kLegVoice * v;
    return q + kLegVoice <= self.raw.length ? q : NSNotFound;
}

- (NSInteger)voiceCount {
    if (self.kind == EDPresetKindE4) { NSInteger n = 0; while ([self e4VoiceBase:n] != NSNotFound) n++; return MIN(n, (NSInteger)(self.raw.length > 21 ? ((const uint8_t *)self.raw.bytes)[21] : 0)); }
    if (self.raw.length < kLegHeader) return 0;
    NSUInteger zones = ((const uint8_t *)self.raw.bytes)[53];
    return self.raw.length >= kLegHeader + 4 * zones ? (NSInteger)((self.raw.length - kLegHeader - 4 * zones) / kLegVoice) : 0;
}
- (NSInteger)refCountInVoice:(NSInteger)v {
    if (self.kind != EDPresetKindE4) return 0;
    NSUInteger q = [self e4VoiceBase:v]; return q == NSNotFound ? 0 : ((const uint8_t *)self.raw.bytes)[q + 2];
}

- (NSUInteger)baseForParam:(EDParam *)p voice:(NSInteger)v ref:(NSInteger)r {
    switch (p.scope) {
        case EDScopePreset: return 0;
        case EDScopeVoice: return self.kind == EDPresetKindE4 ? [self e4VoiceBase:v] : [self legVoiceBase:v];
        case EDScopeRef: { NSUInteger q = [self e4VoiceBase:v]; if (q == NSNotFound || r < 0 || r >= ((const uint8_t *)self.raw.bytes)[q + 2]) return NSNotFound; return q + kE4Voice + kE4Ref * r; }
    }
}

- (NSInteger)valueOfParam:(EDParam *)p voice:(NSInteger)v ref:(NSInteger)r {
    NSUInteger base = [self baseForParam:p voice:v ref:r]; if (base == NSNotFound) return 0;
    NSUInteger o = base + p.offset; const uint8_t *b = self.raw.bytes; NSUInteger w = (p.type == EDParamU16BE || p.type == EDParamS16BE) ? 2 : 1;
    if (o + w > self.raw.length) return 0;
    switch (p.type) {
        case EDParamU8: return b[o];
        case EDParamS8: return (int8_t)b[o];
        case EDParamU16BE: return (b[o] << 8) | b[o + 1];
        case EDParamS16BE: return (int16_t)((b[o] << 8) | b[o + 1]);
    }
}
- (void)setValue:(NSInteger)val ofParam:(EDParam *)p voice:(NSInteger)v ref:(NSInteger)r {
    if (p.readOnly) return;
    NSUInteger base = [self baseForParam:p voice:v ref:r]; if (base == NSNotFound) return;
    NSUInteger o = base + p.offset; uint8_t *b = self.raw.mutableBytes; NSUInteger w = (p.type == EDParamU16BE || p.type == EDParamS16BE) ? 2 : 1;
    if (o + w > self.raw.length) return;
    val = MAX(p.min, MIN(p.max, val));
    if (w == 1) b[o] = (uint8_t)val; else { b[o] = (uint8_t)((val >> 8) & 0xFF); b[o + 1] = (uint8_t)(val & 0xFF); }
    self.dirty = YES;
}

// MARK: structural edits (E4)

- (BOOL)addRefToVoice:(NSInteger)v {
    if (!self.canEditStructure) return NO;
    NSUInteger q = [self e4VoiceBase:v]; if (q == NSNotFound) return NO;
    uint8_t *b = self.raw.mutableBytes; NSUInteger n = b[q + 2]; if (n == 0 || n >= 94) return NO;
    NSUInteger last = q + kE4Voice + kE4Ref * (n - 1), at = q + kE4Voice + kE4Ref * n;
    if (at > self.raw.length) return NO;
    NSData *copy = [self.raw subdataWithRange:NSMakeRange(last, kE4Ref)];
    [self.raw replaceBytesInRange:NSMakeRange(at, 0) withBytes:copy.bytes length:kE4Ref];
    b = self.raw.mutableBytes; b[q + 2] = (uint8_t)(n + 1);
    NSUInteger sz = ((b[q] << 8) | b[q + 1]) + kE4Ref; b[q] = sz >> 8; b[q + 1] = sz & 0xFF;
    self.dirty = YES; return YES;
}
- (BOOL)removeRef:(NSInteger)r fromVoice:(NSInteger)v {
    if (!self.canEditStructure) return NO;
    NSUInteger q = [self e4VoiceBase:v]; if (q == NSNotFound) return NO;
    uint8_t *b = self.raw.mutableBytes; NSUInteger n = b[q + 2]; if (n <= 1 || r < 0 || r >= (NSInteger)n) return NO;
    [self.raw replaceBytesInRange:NSMakeRange(q + kE4Voice + kE4Ref * r, kE4Ref) withBytes:NULL length:0];
    b = self.raw.mutableBytes; b[q + 2] = (uint8_t)(n - 1);
    NSUInteger sz = ((b[q] << 8) | b[q + 1]) - kE4Ref; b[q] = sz >> 8; b[q + 1] = sz & 0xFF;
    self.dirty = YES; return YES;
}
- (NSUInteger)e4VoiceLength:(NSUInteger)q { return kE4Voice + kE4Ref * ((const uint8_t *)self.raw.bytes)[q + 2]; }
- (BOOL)duplicateVoice:(NSInteger)v {
    if (!self.canEditStructure) return NO;
    NSUInteger q = [self e4VoiceBase:v]; if (q == NSNotFound) return NO;
    uint8_t *b = self.raw.mutableBytes; if (b[21] >= 255) return NO;
    NSUInteger len = [self e4VoiceLength:q];
    if (q + len > self.raw.length) return NO;
    NSData *copy = [self.raw subdataWithRange:NSMakeRange(q, len)];
    [self.raw replaceBytesInRange:NSMakeRange(q + len, 0) withBytes:copy.bytes length:len];
    ((uint8_t *)self.raw.mutableBytes)[21]++;
    self.dirty = YES; return YES;
}
- (BOOL)addVoiceWithSampleNumber:(NSInteger)sampleNumber {
    if (!self.canEditStructure || self.raw.length < kE4Header) return NO;
    const uint8_t *b = self.raw.bytes; NSUInteger n = b[21], q = kE4Header, len = self.raw.length;
    if (n >= 255) return NO;
    for (NSUInteger i = 0; i < n; i++) { if (q + kE4Voice > len) return NO; q += kE4Voice + kE4Ref * b[q + 2]; if (q > len) return NO; }
    uint8_t v[kE4Voice + kE4Ref];
    memcpy(v, kDefaultVoice, kE4Voice); memcpy(v + kE4Voice, kDefaultRef, kE4Ref);
    v[0] = (kE4Voice + kE4Ref) >> 8; v[1] = (kE4Voice + kE4Ref) & 0xFF; v[2] = 1; v[3] = 0;     // size, one sample, group 0
    memcpy(v + 12, "\x00\x00\x00\x7f", 4); memcpy(v + 16, "\x00\x00\x00\x7f", 4); memcpy(v + 20, "\x00\x00\x00\x7f", 4);   // key, velocity, realtime windows: full range
    uint8_t *r = v + kE4Voice;
    memcpy(r, "\x00\x00\x00\x7f", 4); memcpy(r + 4, "\x00\x00\x00\x7f", 4);                // zone key and velocity windows: full range
    int sn = (int)MAX(0, MIN(2999, sampleNumber)); r[8] = sn >> 8; r[9] = sn & 0xFF; r[10] = r[11] = 0; r[12] = 60; r[13] = 0; r[14] = 0;   // sample, fine tune, root C3, 0 dB, centre
    [self.raw replaceBytesInRange:NSMakeRange(q, len - q) withBytes:v length:sizeof v];          // anything after the last voice is not part of the preset
    ((uint8_t *)self.raw.mutableBytes)[21] = (uint8_t)(n + 1);
    self.dirty = YES; return YES;
}
+ (NSMutableData *)newE4PresetDataWithName:(NSString *)name number:(uint16_t)number {
    NSMutableData *d = [NSMutableData dataWithBytes:kDefaultPresetHeader length:kE4Header]; uint8_t *b = d.mutableBytes;
    b[0] = number >> 8; b[1] = number & 0xFF;
    memset(b + 2, ' ', 16); NSData *nm = [name dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES]; memcpy(b + 2, nm.bytes, MIN(nm.length, 16));
    b[20] = 0; b[21] = 0;                                  // no links, no voices
    memset(b + 64, 0, 4); memset(b + 72, 0, 4);            // effect sends off (the template came from a preset that used reverb)
    return d;
}
- (BOOL)removeVoice:(NSInteger)v {
    if (!self.canEditStructure) return NO;
    NSUInteger q = [self e4VoiceBase:v]; if (q == NSNotFound) return NO;
    uint8_t *b = self.raw.mutableBytes; if (b[21] <= 1) return NO;
    NSUInteger len = [self e4VoiceLength:q];
    if (q + len > self.raw.length) return NO;
    [self.raw replaceBytesInRange:NSMakeRange(q, len) withBytes:NULL length:0];
    ((uint8_t *)self.raw.mutableBytes)[21]--;
    self.dirty = YES; return YES;
}

- (BOOL)validateStructure {
    const uint8_t *b = self.raw.bytes; NSUInteger len = self.raw.length;
    if (self.kind == EDPresetKindLegacy3X) {
        if (len < kLegHeader) return NO;
        NSUInteger z = b[53]; return len >= kLegHeader + 4 * z && (len - kLegHeader - 4 * z) % kLegVoice == 0;
    }
    if (len < kE4Header) return NO;
    NSUInteger q = kE4Header;
    for (int i = 0; i < b[21]; i++) {
        if (q + kE4Voice > len) return NO;
        NSUInteger sz = (b[q] << 8) | b[q + 1], expect = kE4Voice + kE4Ref * b[q + 2];
        if (sz != expect) return NO;
        q += expect;
    }
    return q == len;
}
@end
