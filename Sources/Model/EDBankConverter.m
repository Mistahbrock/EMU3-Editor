#import "EDBankConverter.h"
#import "EDBankInternal.h"
#import "EDLegacyBank.h"
#import "EDPreset+Params.h"

enum { kLegHdr = 142, kLegVox = 48, kE4Hdr = 84, kE4Vox = 284, kE4RefLen = 22 };

static void putBE32(NSMutableData *d, uint32_t v) { uint8_t b[4] = {v >> 24, v >> 16, v >> 8, v}; [d appendBytes:b length:4]; }

@implementation EDBankConverter

/// E4 preset data for one 3X preset.
static NSData *e4PresetFromLegacy(EDPreset *p, uint16_t number, NSMutableArray<NSString *> *warn) {
    const uint8_t *b = p.raw.bytes; NSUInteger len = p.raw.length;
    if (len < kLegHdr) return nil;
    NSUInteger zones = b[53], nv = len >= kLegHdr + 4 * zones ? (len - kLegHdr - 4 * zones) / kLegVox : 0;
    EDPreset *out = [EDPreset new];
    out.kind = EDPresetKindE4; out.raw = [EDPreset newE4PresetDataWithName:p.name number:number]; out.number = number;
    int velPL = MIN(b[45], 127), velPH = MIN(b[46], 127), velSL = MIN(b[47], 127), velSH = MIN(b[48], 127);
    if (b[46] == 0 && b[48] == 255) { velPL = 0; velPH = 127; velSL = 0; velSH = 127; }    // "0, 0 / 0, 255": both voices over the whole range
    // key ranges per zone: runs of consecutive keys (the key map has one zone number per key, 255 = none)
    int missing = 0;
    for (NSUInteger z = 0; z < zones; z++) {
        int run = -1;
        for (int i = 0; i <= 88; i++) {
            BOOL in = i < 88 && b[54 + i] == z;
            if (in && run < 0) run = i;
            if (!in && run >= 0) {
                int lo = 21 + run, hi = 21 + i - 1; run = -1;
                for (int sec = 0; sec < 2; sec++) {
                    uint8_t vi = b[kLegHdr + 4 * z + 2 + sec];
                    if (vi == 255) continue;
                    if (vi >= nv) { missing++; continue; }
                    const uint8_t *v = b + kLegHdr + 4 * zones + kLegVox * vi;
                    if (v[1] == 0) { missing++; continue; }
                    if (![out addVoiceWithSampleNumber:v[1]]) { missing++; continue; }
                    NSUInteger at = kE4Hdr + (kE4Vox + kE4RefLen) * ((const uint8_t *)out.raw.bytes)[21] - (kE4Vox + kE4RefLen) + 0;
                    uint8_t *w = (uint8_t *)out.raw.mutableBytes + at;
                    w[12] = lo; w[13] = lo; w[14] = hi; w[15] = hi;                        // key window: low, fade low, fade high, high
                    int vl = sec ? velSL : velPL, vh = sec ? velSH : velPH;
                    w[16] = vl; w[17] = vl; w[18] = vh; w[19] = vh;                        // velocity window
                }
            }
        }
    }
    if (missing) [warn addObject:[NSString stringWithFormat:@"%@: %d voice(s) skipped (no sample)", p.name, missing]];
    if (((const uint8_t *)out.raw.bytes)[21] == 0) [warn addObject:[NSString stringWithFormat:@"%@: no voices (empty key map)", p.name]];
    return out.raw;
}

+ (NSData *)e4bDataFromLegacyBank:(EDBank *)bank warnings:(NSArray<NSString *> **)warnings error:(NSError **)error {
    return [self e4bDataFromLegacyBank:bank presets:nil warnings:warnings error:error];
}

+ (NSData *)e4bDataFromLegacyBank:(EDBank *)bank presets:(NSArray<EDPreset *> *)only warnings:(NSArray<NSString *> **)warnings error:(NSError **)error {
    if (![bank isKindOfClass:[EDLegacyBank class]]) {
        if (error) *error = [NSError errorWithDomain:EDErrorDomain code:10 userInfo:@{NSLocalizedDescriptionKey: @"This is not an Emulator 3X / ESI-32 bank"}];
        return nil;
    }
    EDLegacyBank *lb = (EDLegacyBank *)bank;
    NSMutableArray<NSString *> *warn = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *parts = [NSMutableArray array];
    NSMutableSet<NSNumber *> *used = only ? [NSMutableSet set] : nil;
    for (EDPreset *p in (only ?: bank.presets)) {
        NSData *d = e4PresetFromLegacy(p, p.number, warn);
        if (!d) continue;
        [parts addObject:@{@"id": @"E4P1", @"data": d, @"number": @(p.number), @"name": p.name}];
        if (used) {     // sample numbers the converted voices refer to
            const uint8_t *b = d.bytes; NSUInteger q = kE4Hdr, n = b[21];
            for (NSUInteger v = 0; v < n && q + kE4Vox <= d.length; v++) {
                NSUInteger refs = b[q + 2];
                for (NSUInteger r = 0; r < refs && q + kE4Vox + kE4RefLen * (r + 1) <= d.length; r++) { const uint8_t *rf = b + q + kE4Vox + kE4RefLen * r; [used addObject:@((rf[8] << 8) | rf[9])]; }
                q += kE4Vox + kE4RefLen * refs;
            }
        }
    }
    for (EDSample *s in bank.samples) {
        if (used && ![used containsObject:@(s.number)]) continue;
        NSData *h = [lb originalHeaderForSample:s];
        NSData *d = h ? [EDBank e3s1ChunkDataForLegacySample:s header:h number:s.number] : nil;
        if (!d) { [warn addObject:[NSString stringWithFormat:@"Sample %u %@ was left out (empty or not understood)", s.number, s.name]]; continue; }
        [parts addObject:@{@"id": @"E3S1", @"data": d, @"number": @(s.number), @"name": s.name}];
    }
    if (parts.count == 0 || parts.count > 5000) {
        if (error) *error = [NSError errorWithDomain:EDErrorDomain code:11 userInfo:@{NSLocalizedDescriptionKey: @"Nothing to convert"}];
        return nil;
    }
    NSUInteger tocLen = 32 * parts.count, off = 12 + 8 + tocLen;
    NSMutableData *toc = [NSMutableData dataWithCapacity:tocLen], *body = [NSMutableData data];
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
    putBE32(out, (uint32_t)(12 + 8 + toc.length + body.length - 12));          // real banks declare the FORM size 4 bytes short
    [out appendBytes:"E4B0" length:4]; [out appendBytes:"TOC1" length:4]; putBE32(out, (uint32_t)toc.length);
    [out appendData:toc]; [out appendData:body];
    if (warnings) *warnings = warn;
    return out;
}
@end
