#import "EDLegacyBank.h"
#import "EDBankInternal.h"

enum { kHdr = 0x4C, kPresetTab = 0x17CA, kSampleTab = 0x1BD2, kPresetBase = 0x2B72, kSampleBase = 0x400000,
       kObjHdr = 0x5C, kMaxPresets = 256, kMaxSamples = 999,
       oName = 0x00, oStartL = 0x14, oStartR = 0x18, oEndL = 0x1C, oEndR = 0x20, oLoopStartL = 0x24, oLoopStartR = 0x28,
       oLoopEndL = 0x2C, oLoopEndR = 0x30, oRate = 0x34, oFlags = 0x3A, oDataOffL = 0x3C, oDataOffR = 0x40 };

static inline uint32_t rd32(const uint8_t *p) { return p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t)p[3] << 24); }
static inline uint16_t rd16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }
static inline void wr32(uint8_t *p, uint32_t v) { p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24; }
static inline void wr16(uint8_t *p, uint16_t v) { p[0] = v; p[1] = v >> 8; }
static NSString *rdName(const uint8_t *p) {
    NSUInteger n = 16; while (n > 0 && (p[n - 1] == ' ' || p[n - 1] == 0)) n--;
    return [[NSString alloc] initWithBytes:p length:n encoding:NSISOLatin1StringEncoding] ?: @"";
}
static void wrName(uint8_t *p, NSString *s) {
    memset(p, ' ', 16);
    NSData *d = [s dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES] ?: [NSData data];
    memcpy(p, d.bytes, MIN(d.length, (NSUInteger)16));
}
static NSError *legErr(NSString *m) { return [NSError errorWithDomain:EDErrorDomain code:3 userInfo:@{NSLocalizedDescriptionKey: m}]; }

/// One sample object as found in the file, plus what is needed to write it back.
@interface EDLegacySlot : NSObject
@property (nonatomic) NSUInteger tableIndex;    // index in the sample address table
@property (nonatomic) uint32_t address;         // original absolute address
@property (nonatomic, copy) NSData *object;     // original bytes
@property (nonatomic, strong) EDSample *sample;
@end
@implementation EDLegacySlot @end

@implementation EDLegacyBank {
    NSData *_original;
    NSArray<EDLegacySlot *> *_slots;                 // in address order
    NSArray<NSNumber *> *_presetStarts;              // file offsets of each preset
    NSMutableArray<EDSample *> *_samples;
    NSMutableArray<EDPreset *> *_presets;
    uint32_t _presetAreaEnd;
}

- (NSString *)formType { return @"3X"; }
- (NSArray<EDChunk *> *)chunks { return @[]; }
- (NSArray<EDSample *> *)samples { return _samples; }
- (NSArray<EDPreset *> *)presets { return _presets; }
- (BOOL)dirty {
    for (EDSample *s in _samples) if (s.dirty) return YES;
    for (EDPreset *p in _presets) if (p.dirty) return YES;
    return NO;
}

/// Builds an editable sample from an object, or a locked one when the object does not follow the known layout.
static EDSample *sampleFromObject(NSData *obj, NSUInteger number, NSUInteger tableIndex) {
    const uint8_t *b = obj.bytes;
    EDSample *s = [EDSample new];
    s.chunkIndex = tableIndex; s.number = (uint16_t)number;
    s.name = rdName(b + oName);
    s.sampleRate = rd32(b + oRate);
    uint16_t flags = rd16(b + oFlags);
    uint32_t sl = rd32(b + oStartL), sr = rd32(b + oStartR), el = rd32(b + oEndL), er = rd32(b + oEndR);
    uint32_t lsl = rd32(b + oLoopStartL), lel = rd32(b + oLoopEndL);
    BOOL hasL = flags & EDSampleFlagLeft, hasR = flags & EDSampleFlagRight;
    NSData *L = nil, *R = nil; BOOL ok = NO, rightOnly = hasR && !hasL;
    if (rightOnly) {      // right-only mono: audio at start_r; the L words mirror the R words (L = R - 0x5C)
        if (obj.length >= kObjHdr && sr == kObjHdr && (NSUInteger)er + 2 == obj.length && er + 2 > sr && ((er + 2 - sr) & 1) == 0) {
            L = [obj subdataWithRange:NSMakeRange(sr, er + 2 - sr)]; ok = YES;
            lsl = rd32(b + oLoopStartR); lel = rd32(b + oLoopEndR); sl = sr;
        }
    } else if (obj.length >= kObjHdr && hasL && sl == kObjHdr && (NSUInteger)el + 2 <= obj.length && el + 2 > sl && ((el + 2 - sl) & 1) == 0) {
        L = [obj subdataWithRange:NSMakeRange(sl, el + 2 - sl)];
        if (!hasR) ok = ((NSUInteger)el + 2 == obj.length);
        else if (sr == el + 2 && (NSUInteger)er + 2 == obj.length && er + 2 - sr == el + 2 - sl) R = [obj subdataWithRange:NSMakeRange(sr, er + 2 - sr)], ok = YES;
    }
    if (ok) {
        [s replaceLeft:L right:R];
        s.flags = flags;
        NSUInteger n = s.frameCount;
        s.loopStart = lsl >= sl ? MIN((lsl - sl) / 2, n - 1) : 0;
        s.loopEnd = lel >= sl ? MIN((lel - sl) / 2, n - 1) : 0;
    } else {
        [s replaceLeft:[NSData data] right:nil];
        s.flags = flags; s.locked = YES;
    }
    s.dirty = NO;
    return s;
}

+ (instancetype)legacyBankWithData:(NSData *)data error:(NSError **)error {
    const uint8_t *b = data.bytes;
    if (data.length < kSampleTab + 4 * kMaxSamples + 16) { if (error) *error = legErr(@"File is too small for an Emulator 3X bank"); return nil; }
    uint32_t nPre = rd32(b + 0x30), nSmp = rd32(b + 0x34);
    if ((uint64_t)kHdr + nPre + nSmp != data.length || kHdr + nPre < kPresetBase) {
        if (error) *error = legErr(@"Bank sizes in the header do not match the file; not editing it"); return nil;
    }
    EDLegacyBank *bank = [EDLegacyBank new];
    bank->_original = [data copy];
    bank->_samples = [NSMutableArray array]; bank->_presets = [NSMutableArray array];
    bank->_presetAreaEnd = kHdr + nPre;

    // presets
    NSMutableArray *starts = [NSMutableArray array];
    for (int i = 0; i + 1 < kMaxPresets; i++) {
        uint32_t a = rd32(b + kPresetTab + 4 * i), n = rd32(b + kPresetTab + 4 * (i + 1));
        if (n <= a || (uint64_t)kPresetBase + n > data.length || (uint64_t)kPresetBase + a + 16 > data.length) break;
        NSData *raw = [data subdataWithRange:NSMakeRange(kPresetBase + a, n - a)];
        EDPreset *p = [EDPreset new];
        p.chunkIndex = (NSUInteger)i; p.raw = [raw mutableCopy]; p.kind = EDPresetKindLegacy3X;
        p.number = (uint16_t)i; p.name = rdName(raw.bytes); p.dirty = NO;
        [bank->_presets addObject:p]; [starts addObject:@(kPresetBase + a)];
    }
    bank->_presetStarts = starts;

    // samples, in address order (the table is ascending on every bank seen)
    NSMutableArray<EDLegacySlot *> *slots = [NSMutableArray array];
    for (int i = 0; i < kMaxSamples; i++) {
        uint32_t a = rd32(b + kSampleTab + 4 * i); if (!a) continue;
        EDLegacySlot *sl = [EDLegacySlot new]; sl.tableIndex = i; sl.address = a; [slots addObject:sl];
    }
    [slots sortUsingComparator:^NSComparisonResult(EDLegacySlot *x, EDLegacySlot *y) { return x.address < y.address ? NSOrderedAscending : (x.address > y.address); }];
    uint32_t sampleEnd = kSampleBase + nSmp;
    for (NSUInteger k = 0; k < slots.count; k++) {
        EDLegacySlot *sl = slots[k];
        uint32_t next = k + 1 < slots.count ? slots[k + 1].address : sampleEnd;
        if (sl.address < kSampleBase || next <= sl.address || next > sampleEnd || next - sl.address < kObjHdr) {
            if (error) *error = legErr(@"Sample address table is inconsistent; not editing this bank"); return nil;
        }
        sl.object = [data subdataWithRange:NSMakeRange(kHdr + nPre + (sl.address - kSampleBase), next - sl.address)];
        sl.sample = sampleFromObject(sl.object, sl.tableIndex + 1, sl.tableIndex);
    }
    bank->_slots = slots;
    NSArray *byTable = [slots sortedArrayUsingComparator:^NSComparisonResult(EDLegacySlot *x, EDLegacySlot *y) { return x.tableIndex < y.tableIndex ? NSOrderedAscending : (x.tableIndex > y.tableIndex); }];
    for (EDLegacySlot *sl in byTable) [bank->_samples addObject:sl.sample];
    return bank;
}

- (NSData *)originalHeaderForSample:(EDSample *)sample {
    for (EDLegacySlot *sl in _slots) if (sl.sample == sample && sl.object.length >= kObjHdr) return [sl.object subdataWithRange:NSMakeRange(0, kObjHdr)];
    return nil;
}

/// Writes an edited sample into a fresh object, keeping the header bytes that are not understood.
static NSData *objectFromSample(EDSample *s, NSData *orig) {
    NSMutableData *h = [[orig subdataWithRange:NSMakeRange(0, kObjHdr)] mutableCopy];
    uint8_t *p = h.mutableBytes;
    wrName(p + oName, s.name);
    wr32(p + oRate, s.sampleRate);
    wr16(p + oFlags, s.flags);
    NSUInteger n = s.frameCount, bytes = n * 2;
    uint32_t sl = kObjHdr, el = (uint32_t)(sl + bytes - 2);
    BOOL rightOnly = (s.flags & EDSampleFlagRight) && !(s.flags & EDSampleFlagLeft);
    if (rightOnly) {
        uint32_t oldEr = rd32(p + oEndR), oldLsr = rd32(p + oLoopStartR), oldLer = rd32(p + oLoopEndR);
        uint32_t lsr = (uint32_t)(sl + s.loopStart * 2), ler = (uint32_t)(sl + s.loopEnd * 2);
        wr32(p + oStartR, sl); wr32(p + oEndR, el); wr32(p + oLoopStartR, lsr); wr32(p + oLoopEndR, ler);
        // the L words mirror the R words; keep whatever offset the file used
        wr32(p + oEndL, rd32(p + oEndL) + (el - oldEr));
        wr32(p + oLoopStartL, rd32(p + oLoopStartL) + (lsr - oldLsr));
        wr32(p + oLoopEndL, rd32(p + oLoopEndL) + (ler - oldLer));
        NSMutableData *o = h; [o appendData:s.left]; return o;
    }
    uint32_t oldEl = rd32(p + oEndL), oldLsl = rd32(p + oLoopStartL), oldLel = rd32(p + oLoopEndL);
    uint32_t lsl = (uint32_t)(sl + s.loopStart * 2), lel = (uint32_t)(sl + s.loopEnd * 2);
    wr32(p + oStartL, sl); wr32(p + oEndL, el); wr32(p + oLoopStartL, lsl); wr32(p + oLoopEndL, lel);
    if (s.right) {
        uint32_t sr = el + 2, er = (uint32_t)(sr + bytes - 2);
        wr32(p + oStartR, sr); wr32(p + oEndR, er);
        wr32(p + oLoopStartR, (uint32_t)(sr + s.loopStart * 2)); wr32(p + oLoopEndR, (uint32_t)(sr + s.loopEnd * 2));
    } else {
        // mono: the R words mirror the L words (observed: R = L - 0x5C); keep whatever offset the file used
        wr32(p + oEndR, rd32(p + oEndR) + (el - oldEl));
        wr32(p + oLoopStartR, rd32(p + oLoopStartR) + (lsl - oldLsl));
        wr32(p + oLoopEndR, rd32(p + oLoopEndR) + (lel - oldLel));
    }
    NSMutableData *out = h;
    [out appendData:s.left];
    if (s.right) [out appendData:s.right];
    return out;
}

- (NSData *)serializeWithError:(NSError **)error {
    NSMutableData *out = [[_original subdataWithRange:NSMakeRange(0, _presetAreaEnd)] mutableCopy];
    uint8_t *w = out.mutableBytes;
    for (EDPreset *pr in _presets) if (pr.dirty) {        // presets keep their size in 3X banks, so they are rewritten in place
        wrName((uint8_t *)pr.raw.mutableBytes, pr.name);
        NSUInteger at = _presetStarts[pr.chunkIndex].unsignedIntegerValue;
        if (at + pr.raw.length <= out.length) [out replaceBytesInRange:NSMakeRange(at, pr.raw.length) withBytes:pr.raw.bytes];
    }

    uint32_t total = 0;
    NSMutableArray<NSData *> *objs = [NSMutableArray array];
    for (EDLegacySlot *sl in _slots) {
        NSData *obj = (sl.sample.dirty && !sl.sample.locked) ? objectFromSample(sl.sample, sl.object) : sl.object;
        [objs addObject:obj];
    }
    uint32_t addr = kSampleBase;
    for (NSUInteger k = 0; k < _slots.count; k++) {
        EDLegacySlot *sl = _slots[k];
        NSMutableData *obj = [objs[k] mutableCopy];
        int64_t shift = (int64_t)addr - sl.address;
        if (shift != 0 && obj.length >= kObjHdr) {          // data offsets are relative to the sample area: they move with the object
            uint8_t *o = obj.mutableBytes;
            wr32(o + oDataOffL, (uint32_t)(rd32(o + oDataOffL) + shift)); wr32(o + oDataOffR, (uint32_t)(rd32(o + oDataOffR) + shift));
        }
        wr32(w + kSampleTab + 4 * sl.tableIndex, addr);
        addr += (uint32_t)obj.length; total += (uint32_t)obj.length;
        objs[k] = obj;
    }
    uint32_t sampleBlocks = (total + 511) / 512, presetBlocks = rd32(w + 0x3C);
    wr32(w + 0x34, total); wr32(w + 0x40, sampleBlocks); wr32(w + 0x48, presetBlocks + sampleBlocks);
    for (NSData *o in objs) [out appendData:o];
    return out;
}
@end
