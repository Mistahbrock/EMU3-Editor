// EDBank.m — E4B (EOS) bank model. Copyright (C) 2026 Rhyno Audio. GPL-3.0-or-later.

#import "NSData+EDWrite.h"
#import "EDBank.h"
#import <AudioToolbox/AudioToolbox.h>
#import "EDLegacyBank.h"
#import "EDPreset+Params.h"

NSString * const EDErrorDomain = @"EMU3EditorErrorDomain";

static NSError *EDError(NSString *msg) {
    return [NSError errorWithDomain:EDErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: msg}];
}

static inline uint32_t rdBE32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]; }
static inline uint32_t rdLE32(const uint8_t *p) { return ((uint32_t)p[3] << 24) | (p[2] << 16) | (p[1] << 8) | p[0]; }
static inline uint16_t rdLE16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }
static inline uint16_t rdBE16(const uint8_t *p) { return (uint16_t)((p[0] << 8) | p[1]); }
static inline void wrBE32(uint8_t *p, uint32_t v) { p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v; }
static inline void wrLE32(uint8_t *p, uint32_t v) { p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24; }
static inline void wrLE16(uint8_t *p, uint16_t v) { p[0] = v; p[1] = v >> 8; }
static inline void wrBE16(uint8_t *p, uint16_t v) { p[0] = v >> 8; p[1] = v; }

static NSString *readName(const uint8_t *p, NSUInteger len) {
    NSUInteger n = len;
    while (n > 0 && (p[n - 1] == ' ' || p[n - 1] == 0)) n--;
    return [[NSString alloc] initWithBytes:p length:n encoding:NSISOLatin1StringEncoding] ?: @"";
}
static void writeName(uint8_t *p, NSUInteger len, NSString *s) {
    memset(p, ' ', len);
    NSData *d = [s dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES] ?: [NSData data];
    memcpy(p, d.bytes, MIN(d.length, len));
}

// E3S1 chunk-data offsets (chunk data starts at the 2-byte sample number)
enum { kHdrSize = 94, kNameOff = 0x02, kStartL = 0x16, kStartR = 0x1A, kEndL = 0x1E, kEndR = 0x22,
       kLoopStartL = 0x26, kLoopStartR = 0x2A, kLoopEndL = 0x2E, kLoopEndR = 0x32, kRate = 0x36, kFlags = 0x3C,
       kOffsetBase = 2 /* offsets are relative to the byte after the number */ };

// ───────────────────────────────────────────────────────────────────────────

@implementation EDChunk
@end

@interface EDSample ()
@property (nonatomic, readwrite) NSUInteger chunkIndex;
@property (nonatomic) BOOL eosFormat;                         // parsed from an E3S1 chunk
@property (nonatomic, strong) NSMutableData *header;         // first kHdrSize bytes, unknown fields preserved
@property (nonatomic, readwrite, copy) NSData *left;
@property (nonatomic, readwrite, copy, nullable) NSData *right;
@property (nonatomic, readwrite) BOOL dirty;
@end

@implementation EDSample

- (BOOL)hasLeft   { return (_flags & EDSampleFlagLeft)  != 0; }
- (BOOL)hasRight  { return (_flags & EDSampleFlagRight) != 0; }
- (BOOL)isStereo  { return self.hasLeft && self.hasRight; }
- (NSUInteger)frameCount { return _left.length / 2; }
- (const int16_t *)leftFrames  { return _left.bytes; }
- (const int16_t *)rightFrames { return _right.bytes; }
- (BOOL)loopEnabled { return (_flags & EDSampleFlagLoop) != 0; }
- (void)setLoopEnabled:(BOOL)on { _flags = on ? (_flags | EDSampleFlagLoop) : (_flags & ~EDSampleFlagLoop); _dirty = YES; }
- (BOOL)loopInRelease { return (_flags & EDSampleFlagLoopRelease) != 0; }
- (void)setLoopInRelease:(BOOL)on { _flags = on ? (_flags | EDSampleFlagLoopRelease) : (_flags & ~EDSampleFlagLoopRelease); _dirty = YES; }
- (void)setName:(NSString *)name { _name = [name.length > 16 ? [name substringToIndex:16] : name copy]; _dirty = YES; }
- (void)setNumber:(uint16_t)n { _number = n; _dirty = YES; }
- (void)setSampleRate:(uint32_t)r { _sampleRate = r; _dirty = YES; }
- (void)setLoopStart:(NSUInteger)v { _loopStart = v; _dirty = YES; }
- (void)setLoopEnd:(NSUInteger)v { _loopEnd = v; _dirty = YES; }

/// Parses chunk data. Returns nil with *error when the chunk is not a well-formed mono/stereo 16-bit sample.
+ (instancetype)sampleFromChunkData:(NSData *)d index:(NSUInteger)idx error:(NSError **)error {
    if (d.length < kHdrSize) { if (error) *error = EDError(@"Sample chunk shorter than its header"); return nil; }
    const uint8_t *b = d.bytes;
    EDSample *s = [EDSample new];
    s.chunkIndex = idx;
    s.header = [NSMutableData dataWithBytes:b length:kHdrSize]; s.eosFormat = YES;
    s->_number = rdBE16(b);
    s->_name = readName(b + kNameOff, 16);
    s->_sampleRate = rdLE32(b + kRate);
    s->_flags = rdLE16(b + kFlags);

    uint32_t sL = rdLE32(b + kStartL), eL = rdLE32(b + kEndL), sR = rdLE32(b + kStartR), eR = rdLE32(b + kEndR);
    NSData *(^slice)(uint32_t, uint32_t) = ^NSData *(uint32_t st, uint32_t en) {
        if (en + 2 < st) return nil;
        NSUInteger from = (NSUInteger)st + kOffsetBase, len = (NSUInteger)en + 2 - st;
        if (len == 0 || (len & 1) || from < kHdrSize || from + len > d.length) return nil;
        return [d subdataWithRange:NSMakeRange(from, len)];
    };
    uint32_t refStart;
    if (s.hasLeft) {
        s->_left = slice(sL, eL);
        refStart = sL;
        if (s.hasRight) s->_right = slice(sR, eR);
        if (!s->_left || (s.hasRight && !s->_right)) { if (error) *error = EDError(@"Sample data range is outside the chunk"); return nil; }
    } else if (s.hasRight) {
        s->_left = slice(sR, eR);       // right-only sample: expose it as the first channel
        refStart = sR;
        if (!s->_left) { if (error) *error = EDError(@"Sample data range is outside the chunk"); return nil; }
    } else {
        s->_left = [NSData data];       // empty sample slot
        refStart = sL;
    }
    uint32_t lsL = rdLE32(b + kLoopStartL), leL = rdLE32(b + kLoopEndL);
    if (!s.hasLeft && s.hasRight) { lsL = rdLE32(b + kLoopStartR); leL = rdLE32(b + kLoopEndR); }
    s->_loopStart = lsL >= refStart ? (lsL - refStart) / 2 : 0;
    s->_loopEnd   = leL >= refStart ? (leL - refStart) / 2 : 0;
    if (s.frameCount) {
        s->_loopStart = MIN(s->_loopStart, s.frameCount - 1);
        s->_loopEnd   = MIN(s->_loopEnd,   s.frameCount - 1);
    }
    return s;
}

- (void)replaceLeft:(NSData *)left right:(NSData *)right {
    _left = [left copy];
    _right = right ? [right copy] : nil;
    // keep the flag word consistent with the channels that now exist
    // a right-channel-only sample stays right-only (its audio is held in `left`)
    BOOL rightOnly = (_flags & EDSampleFlagRight) && !(_flags & EDSampleFlagLeft) && right == nil;
    uint16_t f = _flags & ~(EDSampleFlagLeft | EDSampleFlagRight | EDSampleFlagStereo);
    if (rightOnly) f |= EDSampleFlagRight;
    else { f |= EDSampleFlagLeft; if (right) f |= EDSampleFlagRight | EDSampleFlagStereo; }
    _flags = f;
    NSUInteger n = self.frameCount;
    if (n) { _loopStart = MIN(_loopStart, n - 1); _loopEnd = MIN(_loopEnd, n - 1); }
    _dirty = YES;
}

/// Writes the model back into a fresh chunk payload (header fields patched in place, unknown bytes preserved).
- (NSData *)chunkData {
    NSMutableData *h = [self.header mutableCopy];
    uint8_t *p = h.mutableBytes;
    wrBE16(p, _number);
    writeName(p + kNameOff, 16, _name);
    wrLE32(p + kRate, _sampleRate);
    wrLE16(p + kFlags, _flags);

    NSUInteger n = self.frameCount, bytes = n * 2;
    uint32_t base = kHdrSize - kOffsetBase;         // 92: first data byte relative to the sample number
    uint32_t sL = base, eL = n ? (uint32_t)(base + bytes - 2) : base;
    uint32_t sR = sL, eR = eL;
    if (_right) { sR = (uint32_t)(base + bytes); eR = (uint32_t)(sR + bytes - 2); }
    wrLE32(p + kStartL, sL); wrLE32(p + kEndL, eL);
    wrLE32(p + kStartR, sR); wrLE32(p + kEndR, eR);
    wrLE32(p + kLoopStartL, (uint32_t)(sL + _loopStart * 2)); wrLE32(p + kLoopEndL, (uint32_t)(sL + _loopEnd * 2));
    wrLE32(p + kLoopStartR, (uint32_t)(sR + _loopStart * 2)); wrLE32(p + kLoopEndR, (uint32_t)(sR + _loopEnd * 2));

    NSMutableData *out = [h mutableCopy];
    [out appendData:_left];
    if (_right) [out appendData:_right];
    return out;
}

// MARK: WAV export

static const NSUInteger kGuard = 4;   // the sampler pads each channel with 4 zero frames

- (BOOL)writeWAVToURL:(NSURL *)url error:(NSError **)error {
    NSUInteger n = self.frameCount;
    NSUInteger g = (n > 2 * kGuard) ? kGuard : 0;
    NSUInteger len = n - 2 * g;
    uint16_t ch = _right ? 2 : 1;
    const int16_t *L = self.leftFrames, *R = _right ? self.rightFrames : NULL;
    NSMutableData *pcm = [NSMutableData dataWithLength:len * ch * 2];
    int16_t *o = pcm.mutableBytes;
    for (NSUInteger i = 0; i < len; i++) {
        o[i * ch] = L[i + g];
        if (R) o[i * ch + 1] = R[i + g];
    }
    BOOL loop = self.loopEnabled && _loopEnd > _loopStart + 1 && _loopStart >= g;
    uint32_t smplSize = loop ? (36 + 24) : 0;
    NSMutableData *w = [NSMutableData data];
    uint32_t riffSize = (uint32_t)(4 + 24 + 8 + pcm.length + (loop ? 8 + smplSize : 0));
    uint32_t rate = _sampleRate ?: 44100, byteRate = rate * ch * 2, v32;
    uint16_t v16;
#define W32(x) do { v32 = (x); [w appendBytes:&v32 length:4]; } while (0)
#define W16(x) do { v16 = (x); [w appendBytes:&v16 length:2]; } while (0)
    [w appendBytes:"RIFF" length:4]; W32(riffSize); [w appendBytes:"WAVE" length:4];
    [w appendBytes:"fmt " length:4]; W32(16); W16(1); W16(ch); W32(rate); W32(byteRate); W16(ch * 2); W16(16);
    [w appendBytes:"data" length:4]; W32((uint32_t)pcm.length); [w appendData:pcm];
    if (loop) {
        [w appendBytes:"smpl" length:4]; W32(smplSize);
        W32(0); W32(0); W32(rate ? 1000000000u / rate : 0); W32(60); W32(0); W32(0); W32(0); W32(1); W32(0);
        W32(0); W32(0); W32((uint32_t)(_loopStart - g)); W32((uint32_t)(_loopEnd - g)); W32(0); W32(0);
    }
#undef W32
#undef W16
    return [w ed_writeToURL:url error:error];
}

// MARK: audio import (any format AudioToolbox reads)

- (BOOL)replaceAudioFromURL:(NSURL *)url error:(NSError **)error {
    ExtAudioFileRef f = NULL;
    if (ExtAudioFileOpenURL((__bridge CFURLRef)url, &f) != noErr) { if (error) *error = EDError(@"Could not open the audio file"); return NO; }
    AudioStreamBasicDescription src = {0}; UInt32 sz = sizeof src;
    ExtAudioFileGetProperty(f, kExtAudioFileProperty_FileDataFormat, &sz, &src);
    UInt32 ch = src.mChannelsPerFrame >= 2 ? 2 : 1;
    AudioStreamBasicDescription dst = {0};
    dst.mSampleRate = src.mSampleRate; dst.mFormatID = kAudioFormatLinearPCM;
    dst.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    dst.mChannelsPerFrame = ch; dst.mBitsPerChannel = 16; dst.mBytesPerFrame = ch * 2; dst.mFramesPerPacket = 1;
    dst.mBytesPerPacket = ch * 2;
    if (ExtAudioFileSetProperty(f, kExtAudioFileProperty_ClientDataFormat, sizeof dst, &dst) != noErr) {
        ExtAudioFileDispose(f); if (error) *error = EDError(@"Unsupported audio format"); return NO;
    }
    SInt64 frames = 0; sz = sizeof frames;
    ExtAudioFileGetProperty(f, kExtAudioFileProperty_FileLengthFrames, &sz, &frames);
    if (frames <= 0 || frames > 64 * 1024 * 1024) { ExtAudioFileDispose(f); if (error) *error = EDError(@"Audio file is empty or too long"); return NO; }
    NSMutableData *buf = [NSMutableData dataWithLength:(NSUInteger)frames * ch * 2];
    AudioBufferList abl = {1, {{ch, (UInt32)buf.length, buf.mutableBytes}}};
    UInt32 got = (UInt32)frames;
    OSStatus st = ExtAudioFileRead(f, &got, &abl);
    ExtAudioFileDispose(f);
    if (st != noErr || got == 0) { if (error) *error = EDError(@"Could not read the audio data"); return NO; }

    NSUInteger n = got + 2 * kGuard;
    NSMutableData *L = [NSMutableData dataWithLength:n * 2], *R = ch == 2 ? [NSMutableData dataWithLength:n * 2] : nil;
    const int16_t *in = buf.bytes; int16_t *l = L.mutableBytes, *r = R.mutableBytes;
    for (UInt32 i = 0; i < got; i++) { l[kGuard + i] = in[i * ch]; if (r) r[kGuard + i] = in[i * ch + 1]; }
    self.sampleRate = (uint32_t)llround(src.mSampleRate);
    _loopStart = kGuard; _loopEnd = n - kGuard - 1;
    [self replaceLeft:L right:R];
    return YES;
}
@end

// ───────────────────────────────────────────────────────────────────────────

@interface EDPreset ()
@property (nonatomic, readwrite) NSUInteger chunkIndex;
@property (nonatomic, readwrite) NSMutableData *raw;
@property (nonatomic, readwrite) BOOL dirty;
- (void)loadFromChunkData:(NSData *)d index:(NSUInteger)i;
@end

@implementation EDPreset
- (void)loadFromChunkData:(NSData *)d index:(NSUInteger)i {
    const uint8_t *b = d.bytes;
    _chunkIndex = i; _raw = [d mutableCopy];
    _number = rdBE16(b); _name = readName(b + 2, 16); _dirty = NO;
}
- (void)setName:(NSString *)name { _name = [name.length > 16 ? [name substringToIndex:16] : name copy]; _dirty = YES; }
- (void)setNumber:(uint16_t)n { _number = n; _dirty = YES; }
- (NSData *)chunkData {
    NSMutableData *d = [_raw mutableCopy];
    if (d.length >= 18) { wrBE16(d.mutableBytes, _number); writeName((uint8_t *)d.mutableBytes + 2, 16, _name); }
    return d;
}
@end

// ───────────────────────────────────────────────────────────────────────────

@interface EDBank () {
    NSMutableArray<EDChunk *> *_chunks;
    NSMutableArray<EDSample *> *_samples;
    NSMutableArray<EDPreset *> *_presets;
    NSArray<EDSample *> *_loadedSamples;   // same for the sample list
    NSArray<EDPreset *> *_loadedPresets;   // preset list as loaded: a different list (added, removed, reordered) means the bank changed
    NSInteger _tocChunk;          // index of TOC1 in _chunks, -1 when absent
    BOOL _tocBigEndian;           // byte order of the size/position fields in TOC records
    NSInteger _tocPosDelta;       // position field = chunk header offset + delta
    NSInteger _tocSizeBias;       // chunk payload size minus the TOC record's size field (the sampler excludes the 2-byte number)
    NSData *_trailer;             // bytes after the last well-formed chunk, kept verbatim
    NSInteger _formSizeDelta;     // declared FORM size minus (file end - 8); E-mu writes it 4 short
    NSMutableArray<NSNumber *> *_tocMap;  // TOC record index -> chunk index (or -1)
}
@property (nonatomic, readwrite) NSString *formType;
@end

@implementation EDBank

static void putBE32(NSMutableData *d, uint32_t v) { uint8_t b[4] = {v >> 24, v >> 16, v >> 8, v}; [d appendBytes:b length:4]; }
+ (NSData *)singleSampleBankDataForSample:(EDSample *)sample {
    if (sample.locked || !sample.eosFormat || sample.header.length < 94) return nil;
    NSMutableData *chunk = [[sample chunkData] mutableCopy];
    uint16_t number = 1;                                         // a one-sample bank always holds sample 1
    ((uint8_t *)chunk.mutableBytes)[0] = number >> 8; ((uint8_t *)chunk.mutableBytes)[1] = number & 0xFF;
    NSUInteger tocData = 32, off = 12 + 8 + tocData;            // FORM(8) E4B0(4) + TOC1 header(8) + records
    NSMutableData *toc = [NSMutableData dataWithCapacity:tocData];
    [toc appendBytes:"E3S1" length:4];
    putBE32(toc, (uint32_t)chunk.length - 2);                    // the sampler's TOC size field is the chunk size minus 2
    putBE32(toc, (uint32_t)off);                                 // position of the chunk header
    uint8_t num[2] = {number >> 8, number & 0xFF}; [toc appendBytes:num length:2];
    NSMutableData *name = [NSMutableData dataWithLength:16]; memset(name.mutableBytes, ' ', 16);
    NSData *nb = [sample.name dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES];
    memcpy(name.mutableBytes, nb.bytes, MIN(nb.length, 16)); [toc appendData:name];
    [toc appendBytes:"\0\0" length:2];
    NSMutableData *out = [NSMutableData data];
    [out appendBytes:"FORM" length:4];
    NSUInteger total = 12 + 8 + toc.length + 8 + chunk.length + (chunk.length & 1);
    putBE32(out, (uint32_t)(total - 12));                        // real banks declare the FORM size 4 bytes short
    [out appendBytes:"E4B0" length:4];
    [out appendBytes:"TOC1" length:4]; putBE32(out, (uint32_t)toc.length); [out appendData:toc];
    [out appendBytes:"E3S1" length:4]; putBE32(out, (uint32_t)chunk.length); [out appendData:chunk];
    if (chunk.length & 1) [out appendBytes:"\0" length:1];
    return out;
}

- (NSArray<EDChunk *> *)chunks { return _chunks; }
- (NSArray<EDSample *> *)samples { return _samples; }
- (NSArray<EDPreset *> *)presets { return _presets; }
- (void)markClean { for (EDSample *s in _samples) s.dirty = NO; for (EDPreset *p in _presets) p.dirty = NO; _loadedPresets = [_presets copy]; _loadedSamples = [_samples copy]; }
- (BOOL)dirty {
    if (_loadedPresets && ![_presets isEqualToArray:_loadedPresets]) return YES;
    if (_loadedSamples && ![_samples isEqualToArray:_loadedSamples]) return YES;
    for (EDSample *s in _samples) if (s.dirty) return YES;
    for (EDPreset *p in _presets) if (p.dirty) return YES;
    return NO;
}

+ (instancetype)bankWithData:(NSData *)data error:(NSError **)error {
    const uint8_t *b = data.bytes;
    if (data.length >= 16 && (memcmp(b, "EMULATOR 3X", 11) == 0 || memcmp(b, "EMU SI-32 v3", 12) == 0))
        return [EDLegacyBank legacyBankWithData:data error:error];
    if (data.length < 12 || memcmp(b, "FORM", 4) != 0 || memcmp(b + 8, "E4B", 3) != 0) {
        if (error) *error = EDError(@"Not an E4B (EOS) bank file");
        return nil;
    }
    EDBank *bank = [EDBank new];
    bank.formType = [[NSString alloc] initWithBytes:b + 8 length:4 encoding:NSISOLatin1StringEncoding];
    bank->_chunks = [NSMutableArray array];
    bank->_samples = [NSMutableArray array];
    bank->_presets = [NSMutableArray array];
    bank->_tocChunk = -1;
    NSMutableArray<NSNumber *> *offsets = [NSMutableArray array];   // original header offset of each chunk

    // Walk the chunks to the end of the data. The FORM size is not trusted: the sampler declares it 4 bytes
    // short (it leaves out the form type), so its difference to the real size is remembered and written back.
    NSUInteger formEnd = data.length, off = 12;
    while (off + 8 <= formEnd) {
        uint32_t size = rdBE32(b + off + 4);
        BOOL idOK = YES;
        for (int k = 0; k < 4; k++) if (b[off + k] < 0x20 || b[off + k] > 0x7e) idOK = NO;
        if (!idOK || size > formEnd - off - 8) break;        // not a chunk: everything from here is trailer
        EDChunk *c = [EDChunk new];
        c.ident = [[NSString alloc] initWithBytes:b + off length:4 encoding:NSISOLatin1StringEncoding];
        c.data = [NSMutableData dataWithBytes:b + off + 8 length:size];
        [offsets addObject:@(off)];
        [bank->_chunks addObject:c];
        off += 8 + size + (size & 1);
    }
    if (bank->_chunks.count == 0) { if (error) *error = EDError(@"Bank contains no chunks"); return nil; }
    if (off < data.length) bank->_trailer = [data subdataWithRange:NSMakeRange(off, data.length - off)];
    bank->_formSizeDelta = (NSInteger)rdBE32(b + 4) - ((NSInteger)data.length - 8);

    for (NSUInteger i = 0; i < bank->_chunks.count; i++) {
        EDChunk *c = bank->_chunks[i];
        if ([c.ident isEqualToString:@"TOC1"] && bank->_tocChunk < 0) bank->_tocChunk = (NSInteger)i;
        else if ([c.ident isEqualToString:@"E3S1"] || [c.ident isEqualToString:@"E4S1"]) {
            NSError *e = nil;
            EDSample *s = [EDSample sampleFromChunkData:c.data index:i error:&e];
            if (!s) { if (error) *error = e; return nil; }
            [bank->_samples addObject:s];
        } else if ([c.ident isEqualToString:@"E4P1"] || [c.ident isEqualToString:@"E3P1"]) {
            if (c.data.length < 18) continue;
            EDPreset *p = [EDPreset new];
            [p loadFromChunkData:c.data index:i];
            [bank->_presets addObject:p];
        }
    }
    [bank resolveTOCWithOffsets:offsets];
    for (EDSample *s in bank->_samples) s.dirty = NO;
    for (EDPreset *p in bank->_presets) p.dirty = NO;
    bank->_loadedPresets = [bank->_presets copy]; bank->_loadedSamples = [bank->_samples copy];
    return bank;
}

/// Works out how TOC records refer to chunks, trying both byte orders and header-vs-data offsets.
- (void)resolveTOCWithOffsets:(NSArray<NSNumber *> *)offsets {
    _tocMap = [NSMutableArray array];
    if (_tocChunk < 0) return;
    NSData *toc = _chunks[_tocChunk].data;
    NSUInteger records = toc.length / 32;
    const uint8_t *t = toc.bytes;
    NSInteger bestScore = -1;
    for (int be = 0; be < 2; be++) for (NSInteger delta = 0; delta <= 8; delta += 8) {
        NSInteger score = 0;
        for (NSUInteger r = 0; r < records; r++) {
            const uint8_t *e = t + r * 32;
            uint32_t pos = be ? rdBE32(e + 8) : rdLE32(e + 8);
            for (NSUInteger c = 0; c < offsets.count; c++)
                if ((NSInteger)offsets[c].unsignedIntegerValue + delta == (NSInteger)pos &&
                    memcmp(e, [_chunks[c].ident UTF8String], 4) == 0) { score++; break; }
        }
        if (score > bestScore) { bestScore = score; _tocBigEndian = be; _tocPosDelta = delta; }
    }
    for (NSUInteger r = 0; r < records; r++) {
        const uint8_t *e = t + r * 32;
        uint32_t pos = _tocBigEndian ? rdBE32(e + 8) : rdLE32(e + 8);
        NSInteger found = -1;
        for (NSUInteger c = 0; c < offsets.count; c++)
            if ((NSInteger)offsets[c].unsignedIntegerValue + _tocPosDelta == (NSInteger)pos &&
                memcmp(e, [_chunks[c].ident UTF8String], 4) == 0) { found = (NSInteger)c; break; }
        [_tocMap addObject:@(found)];
    }
    // size field = payload size minus a constant (2 on real banks); take the most common difference
    NSCountedSet *diffs = [NSCountedSet set];
    for (NSUInteger r = 0; r < records; r++) {
        NSInteger ci = _tocMap[r].integerValue; if (ci < 0) continue;
        const uint8_t *e = t + r * 32; uint32_t sz = _tocBigEndian ? rdBE32(e + 4) : rdLE32(e + 4);
        [diffs addObject:@((NSInteger)_chunks[ci].data.length - (NSInteger)sz)];
    }
    NSUInteger best = 0; _tocSizeBias = 0;
    for (NSNumber *d in diffs) if ([diffs countForObject:d] > best) { best = [diffs countForObject:d]; _tocSizeBias = d.integerValue; }
}

- (void)patchTOCRecordForChunk:(NSUInteger)chunk number:(uint16_t)number name:(NSString *)name {
    uint8_t *t = _chunks[_tocChunk].data.mutableBytes;
    for (NSUInteger r = 0; r < _tocMap.count; r++) {
        if (_tocMap[r].integerValue != (NSInteger)chunk) continue;
        wrBE16(t + r * 32 + 12, number); writeName(t + r * 32 + 14, 16, name);
    }
}

// MARK: adding and removing presets

/// Chunks at or after `at` move by `by`: fix every stored chunk index.
- (void)shiftChunkIndicesFrom:(NSUInteger)at by:(NSInteger)by {
    for (EDSample *s in _samples) if (s.chunkIndex >= at) s.chunkIndex = (NSUInteger)((NSInteger)s.chunkIndex + by);
    for (EDPreset *p in _presets) if (p.chunkIndex >= at) p.chunkIndex = (NSUInteger)((NSInteger)p.chunkIndex + by);
    if (_tocChunk >= (NSInteger)at) _tocChunk += by;
    for (NSUInteger r = 0; r < _tocMap.count; r++) if (_tocMap[r].integerValue >= (NSInteger)at) _tocMap[r] = @(_tocMap[r].integerValue + by);
}

- (EDPreset *)addPresetNamed:(NSString *)name {
    if (![_formType hasPrefix:@"E4B"]) return nil;
    uint16_t number = 0; { BOOL used; do { used = NO; for (EDPreset *p in _presets) if (p.number == number) { used = YES; number++; break; } } while (used && number < 999); }
    NSUInteger at = _chunks.count;
    if (_presets.count) { at = 0; for (EDPreset *p in _presets) at = MAX(at, p.chunkIndex + 1); }
    EDChunk *c = [EDChunk new]; c.ident = @"E4P1"; c.data = [EDPreset newE4PresetDataWithName:name number:number];
    // table-of-contents record goes after the record of the chunk before it
    NSInteger recordAt = -1;
    if (_tocChunk >= 0) { for (NSUInteger r = 0; r < _tocMap.count; r++) if (_tocMap[r].integerValue == (NSInteger)at - 1) recordAt = (NSInteger)r + 1; if (recordAt < 0) recordAt = (NSInteger)_tocMap.count; }
    [self shiftChunkIndicesFrom:at by:1];
    [_chunks insertObject:c atIndex:at];
    if (_tocChunk >= 0) {
        uint8_t rec[32] = {0}; memcpy(rec, "E4P1", 4); wrBE16(rec + 12, number); writeName(rec + 14, 16, name);
        [_chunks[_tocChunk].data replaceBytesInRange:NSMakeRange((NSUInteger)recordAt * 32, 0) withBytes:rec length:32];
        [_tocMap insertObject:@(at) atIndex:(NSUInteger)recordAt];
    }
    EDPreset *p = [EDPreset new]; [p loadFromChunkData:c.data index:at]; p.dirty = YES;
    [_presets addObject:p]; return p;
}

- (NSData *)bankDataForPreset:(EDPreset *)preset missingSamples:(NSArray<NSNumber *> **)missing {
    if (![_formType hasPrefix:@"E4B"] || preset.kind != EDPresetKindE4 || ![_presets containsObject:preset]) return nil;
    // sample numbers used by the preset's zones, in first-use order
    NSMutableArray<NSNumber *> *used = [NSMutableArray array]; EDParam *sp = nil;
    for (EDParam *q in [preset paramsForScope:EDScopeRef]) if (q.isSample) sp = q;
    for (NSInteger v = 0; v < [preset voiceCount]; v++) for (NSInteger r = 0; r < [preset refCountInVoice:v]; r++) {
        NSNumber *n = @([preset valueOfParam:sp voice:v ref:r]); if (![used containsObject:n]) [used addObject:n]; }
    NSMutableArray<NSNumber *> *gone = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *parts = [NSMutableArray array];       // ident, data, number, name
    [parts addObject:@{@"id": @"E4P1", @"data": [preset chunkData], @"number": @(preset.number), @"name": preset.name}];
    for (NSNumber *n in used) {
        EDSample *found = nil; for (EDSample *sm in _samples) if (sm.number == n.integerValue) { found = sm; break; }
        if (!found) { [gone addObject:n]; continue; }
        [parts addObject:@{@"id": _chunks[found.chunkIndex].ident, @"data": [found chunkData], @"number": @(found.number), @"name": found.name}];
    }
    if (missing) *missing = gone;
    NSUInteger off = 12 + 8 + 32 * parts.count; NSMutableData *toc = [NSMutableData data], *body = [NSMutableData data];
    for (NSDictionary *pt in parts) {
        NSData *cd = pt[@"data"]; NSString *ident = pt[@"id"];
        [toc appendBytes:ident.UTF8String length:4]; putBE32(toc, (uint32_t)cd.length - 2); putBE32(toc, (uint32_t)(off + body.length));
        uint16_t num = [pt[@"number"] unsignedShortValue]; uint8_t nb[2] = {num >> 8, num & 0xFF}; [toc appendBytes:nb length:2];
        NSMutableData *name = [NSMutableData dataWithLength:16]; memset(name.mutableBytes, ' ', 16);
        NSData *enc = [pt[@"name"] dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES]; memcpy(name.mutableBytes, enc.bytes, MIN(enc.length, 16));
        [toc appendData:name]; [toc appendBytes:"\0\0" length:2];
        [body appendBytes:ident.UTF8String length:4]; putBE32(body, (uint32_t)cd.length); [body appendData:cd];
        if (cd.length & 1) [body appendBytes:"\0" length:1];
    }
    NSMutableData *out = [NSMutableData data]; [out appendBytes:"FORM" length:4];
    NSUInteger total = 12 + 8 + toc.length + body.length;
    putBE32(out, (uint32_t)(total - 12));                                  // real banks declare the FORM size 4 bytes short
    [out appendBytes:"E4B0" length:4]; [out appendBytes:"TOC1" length:4]; putBE32(out, (uint32_t)toc.length); [out appendData:toc]; [out appendData:body];
    return out;
}

- (BOOL)removePreset:(EDPreset *)preset { return [self detachPreset:preset] != nil; }

/// Removes a sample chunk and its table-of-contents record (E4B banks only). Presets that used it keep a dangling number, like on the sampler.
- (BOOL)removeSample:(EDSample *)sample {
    if (![_formType hasPrefix:@"E4B"] || ![_samples containsObject:sample]) return NO;
    NSUInteger at = sample.chunkIndex;
    if (_tocChunk >= 0) for (NSUInteger r = 0; r < _tocMap.count; r++) if (_tocMap[r].integerValue == (NSInteger)at) {
        [_chunks[_tocChunk].data replaceBytesInRange:NSMakeRange(r * 32, 32) withBytes:NULL length:0]; [_tocMap removeObjectAtIndex:r]; break; }
    [_chunks removeObjectAtIndex:at]; [_samples removeObject:sample];
    [self shiftChunkIndicesFrom:at + 1 by:-1];
    return YES;
}
- (void)eraseAllPresetsAndSamples {
    for (EDPreset *p in [_presets copy]) [self removePreset:p];
    for (EDSample *s in [_samples copy]) [self removeSample:s];
    if ([_formType hasPrefix:@"E4B"] && _chunks.count == 0) {   // keep an empty table of contents so the empty bank is still a valid file
        EDChunk *toc = [EDChunk new]; toc.ident = @"TOC1"; toc.data = [NSMutableData data];
        [_chunks addObject:toc]; _tocChunk = 0; [_tocMap removeAllObjects];
    }
}

- (NSDictionary *)detachPreset:(EDPreset *)preset {
    if (![_formType hasPrefix:@"E4B"] || ![_presets containsObject:preset]) return nil;
    NSUInteger at = preset.chunkIndex, index = [_presets indexOfObject:preset];
    EDChunk *chunk = _chunks[at]; NSInteger record = -1; NSData *recordBytes = nil;
    if (_tocChunk >= 0) for (NSUInteger r = 0; r < _tocMap.count; r++) if (_tocMap[r].integerValue == (NSInteger)at) {
        record = (NSInteger)r; recordBytes = [_chunks[_tocChunk].data subdataWithRange:NSMakeRange(r * 32, 32)];
        [_chunks[_tocChunk].data replaceBytesInRange:NSMakeRange(r * 32, 32) withBytes:NULL length:0]; [_tocMap removeObjectAtIndex:r]; break; }
    [_chunks removeObjectAtIndex:at]; [_presets removeObject:preset];
    [self shiftChunkIndicesFrom:at + 1 by:-1];
    return @{@"preset": preset, @"chunk": chunk, @"at": @(at), @"index": @(index), @"record": @(record), @"recordBytes": recordBytes ?: [NSData data]};
}

- (void)reattachPreset:(NSDictionary *)st {
    NSUInteger at = [st[@"at"] unsignedIntegerValue]; EDPreset *p = st[@"preset"];
    [self shiftChunkIndicesFrom:at by:1];
    [_chunks insertObject:st[@"chunk"] atIndex:at];
    NSInteger record = [st[@"record"] integerValue];
    if (_tocChunk >= 0 && record >= 0) {
        NSData *rb = st[@"recordBytes"];
        [_chunks[_tocChunk].data replaceBytesInRange:NSMakeRange((NSUInteger)record * 32, 0) withBytes:rb.bytes length:32];
        [_tocMap insertObject:@(at) atIndex:(NSUInteger)record];
    }
    p.chunkIndex = at;
    [_presets insertObject:p atIndex:MIN([st[@"index"] unsignedIntegerValue], _presets.count)];
}

- (NSData *)serializeWithError:(NSError **)error {
    // 1. regenerate chunk payloads of edited samples / presets
    NSMutableArray<NSNumber *> *oldSizes = [NSMutableArray array];
    for (EDChunk *c in _chunks) [oldSizes addObject:@(c.data.length)];
    for (EDSample *s in _samples) if (s.dirty) _chunks[s.chunkIndex].data = [[s chunkData] mutableCopy];
    for (EDPreset *p in _presets) if (p.dirty) _chunks[p.chunkIndex].data = [[p chunkData] mutableCopy];

    // 2. new layout offsets
    NSMutableArray<NSNumber *> *newOff = [NSMutableArray array];
    NSUInteger off = 12;
    for (EDChunk *c in _chunks) { [newOff addObject:@(off)]; off += 8 + c.data.length + (c.data.length & 1); }

    // 3. patch TOC records (size / position); refuse when sizes changed but the TOC cannot be mapped
    if (_tocChunk >= 0) {
        NSMutableData *toc = _chunks[_tocChunk].data;
        uint8_t *t = toc.mutableBytes;
        for (NSUInteger r = 0; r < _tocMap.count; r++) {
            NSInteger ci = _tocMap[r].integerValue;
            uint8_t *e = t + r * 32;
            if (ci < 0) continue;
            uint32_t size = (uint32_t)((NSInteger)_chunks[ci].data.length - _tocSizeBias), pos = (uint32_t)(newOff[ci].unsignedIntegerValue + _tocPosDelta);
            if (_tocBigEndian) { wrBE32(e + 4, size); wrBE32(e + 8, pos); } else { wrLE32(e + 4, size); wrLE32(e + 8, pos); }
        }
        for (EDSample *sm in _samples) if (sm.dirty) [self patchTOCRecordForChunk:sm.chunkIndex number:sm.number name:sm.name];
        for (EDPreset *pr in _presets) if (pr.dirty) [self patchTOCRecordForChunk:pr.chunkIndex number:pr.number name:pr.name];
        for (NSUInteger c = 0; c < _chunks.count; c++) {
            if ((NSInteger)c == _tocChunk) continue;
            BOOL listed = [_tocMap containsObject:@(c)];
            if (!listed && ![oldSizes[c] isEqualToNumber:@(_chunks[c].data.length)] ) {
                if (error) *error = EDError(@"A resized chunk is not listed in the bank's table of contents; refusing to save");
                return nil;
            }
        }
    }

    // 4. write
    NSMutableData *out = [NSMutableData dataWithCapacity:off];
    uint8_t head[12]; memcpy(head, "FORM", 4); wrBE32(head + 4, (uint32_t)((NSInteger)(off + _trailer.length) - 8 + _formSizeDelta));
    memcpy(head + 8, [_formType UTF8String], 4);
    [out appendBytes:head length:12];
    for (EDChunk *c in _chunks) {
        uint8_t h[8]; memcpy(h, [c.ident UTF8String], 4); wrBE32(h + 4, (uint32_t)c.data.length);
        [out appendBytes:h length:8]; [out appendData:c.data];
        if (c.data.length & 1) { uint8_t z = 0; [out appendBytes:&z length:1]; }
    }
    if (_trailer) [out appendData:_trailer];
    return out;
}
@end
