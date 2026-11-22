#import "EDSDS.h"

NSString * const EDSDSErrorDomain = @"EDSDS";
static const NSUInteger kGuardFrames = 4;   // keep equal to kGuard in EDBank.m

static NSError *SErr(NSString *m) { return [NSError errorWithDomain:EDSDSErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: m}]; }
static void put3(NSMutableData *d, uint32_t v) { uint8_t b[3] = {v & 0x7F, (v >> 7) & 0x7F, (v >> 14) & 0x7F}; [d appendBytes:b length:3]; }
static uint32_t get3(const uint8_t *p) { return p[0] | (p[1] << 7) | (p[2] << 14); }

@implementation EDSDSSample
- (instancetype)init { if ((self = [super init])) { _bits = 16; _name = @""; } return self; }
@end

@implementation EDSDSCodec
+ (NSUInteger)wordsPerPacketForBits:(uint8_t)bits { NSUInteger bpw = (bits + 6) / 7; return bpw ? 120 / bpw : 40; }

+ (NSData *)headerForSample:(EDSDSSample *)s device:(uint8_t)dev {
    NSMutableData *d = [NSMutableData data];
    uint32_t n = (uint32_t)(s.frames.length / 2);
    uint8_t h[] = {0xF0, 0x7E, dev & 0x7F, 0x01, s.number & 0x7F, (s.number >> 7) & 0x7F, s.bits ? s.bits : 16};
    [d appendBytes:h length:sizeof h];
    uint32_t rate = MAX(s.sampleRate, 1u);
    put3(d, (uint32_t)llround(1e9 / rate));
    put3(d, n);
    uint32_t ls = s.loopEnabled ? s.loopStart : 0, le = s.loopEnabled ? s.loopEnd : (n ? n - 1 : 0);
    put3(d, ls); put3(d, le);
    uint8_t t[] = {s.loopEnabled ? 0x00 : 0x7F, 0xF7};
    [d appendBytes:t length:2];
    return d;
}

+ (NSArray<NSData *> *)packetsForSample:(EDSDSSample *)s device:(uint8_t)dev {
    NSMutableArray *out = [NSMutableArray array];
    const int16_t *f = s.frames.bytes; NSUInteger n = s.frames.length / 2;
    uint8_t bits = s.bits ? s.bits : 16; NSUInteger bpw = (bits + 6) / 7, wpp = 120 / bpw;
    for (NSUInteger idx = 0, base = 0; base < n; idx++, base += wpp) {
        uint8_t m[127]; memset(m, 0, sizeof m);
        m[0] = 0xF0; m[1] = 0x7E; m[2] = dev & 0x7F; m[3] = 0x02; m[4] = idx & 0x7F;
        for (NSUInteger w = 0; w < wpp; w++) {
            uint16_t u = (base + w < n) ? ((uint16_t)f[base + w] ^ 0x8000) : 0x8000;
            uint8_t *o = m + 5 + w * bpw;
            o[0] = (u >> 9) & 0x7F;                         // the word is left-justified: the top `bits` bits are sent, MSB first
            if (bpw > 1) o[1] = (u >> 2) & 0x7F;
            if (bpw > 2) o[2] = (u & 0x03) << 5;
        }
        uint8_t cs = 0; for (int i = 1; i <= 124; i++) cs ^= m[i];
        m[125] = cs & 0x7F; m[126] = 0xF7;
        [out addObject:[NSData dataWithBytes:m length:127]];
    }
    return out;
}

+ (NSData *)requestForNumber:(uint16_t)n device:(uint8_t)dev {
    uint8_t m[] = {0xF0, 0x7E, dev & 0x7F, 0x03, n & 0x7F, (n >> 7) & 0x7F, 0xF7};
    return [NSData dataWithBytes:m length:sizeof m];
}
+ (NSData *)handshake:(uint8_t)code packet:(uint8_t)pp device:(uint8_t)dev {
    uint8_t m[] = {0xF0, 0x7E, dev & 0x7F, code, pp & 0x7F, 0xF7};
    return [NSData dataWithBytes:m length:sizeof m];
}

+ (EDSDSSample *)parseHeader:(NSData *)msg length:(uint32_t *)length bits:(uint8_t *)bits {
    const uint8_t *m = msg.bytes;
    if (msg.length != 21 || m[0] != 0xF0 || m[1] != 0x7E || m[3] != 0x01 || m[20] != 0xF7) return nil;
    uint8_t b = m[6]; if (b < 8 || b > 28) return nil;
    uint32_t period = get3(m + 7); if (!period) return nil;
    EDSDSSample *s = [EDSDSSample new];
    s.number = m[4] | (m[5] << 7);
    s.sampleRate = (uint32_t)llround(1e9 / period);
    *length = get3(m + 10); *bits = b; s.bits = b;
    s.loopStart = get3(m + 13); s.loopEnd = get3(m + 16);
    s.loopEnabled = m[19] != 0x7F;
    return s;
}

+ (NSData *)parsePacket:(NSData *)msg bits:(uint8_t)bits number:(uint8_t *)pp {
    const uint8_t *m = msg.bytes;
    if (msg.length != 127 || m[0] != 0xF0 || m[1] != 0x7E || m[3] != 0x02 || m[126] != 0xF7) return nil;
    uint8_t cs = 0; for (int i = 1; i <= 124; i++) cs ^= m[i];
    if ((cs & 0x7F) != m[125]) return nil;
    *pp = m[4];
    NSUInteger bpw = (bits + 6) / 7, wpp = 120 / bpw;
    NSMutableData *w = [NSMutableData dataWithLength:wpp * 2];
    int16_t *o = w.mutableBytes;
    for (NSUInteger i = 0; i < wpp; i++) {
        const uint8_t *p = m + 5 + i * bpw;
        uint16_t u = (uint16_t)(p[0] << 9);
        if (bpw > 1) u |= (uint16_t)(p[1] << 2);
        if (bpw > 2) u |= (uint16_t)(p[2] >> 5);
        o[i] = (int16_t)(u ^ 0x8000);
    }
    return w;
}
@end

// MARK: engine

@implementation EDSDSEngine {
    NSCondition *_cond;
    NSMutableArray<NSData *> *_inbox;
    NSString *_timing;
    BOOL _cancelled, _havePeer;
    uint8_t _peerID;
}
- (NSString *)timingSummary { return _timing ?: @""; }
- (uint8_t)replyID { return _havePeer ? _peerID : _deviceID; }
- (instancetype)init { if ((self = [super init])) { _cond = [NSCondition new]; _inbox = [NSMutableArray array]; } return self; }

- (void)deliver:(NSData *)m {
    const uint8_t *b = m.bytes;
    if (m.length < 5 || b[0] != 0xF0 || b[1] != 0x7E) return;
    [_cond lock]; _peerID = b[2]; _havePeer = YES; [_inbox addObject:m]; [_cond broadcast]; [_cond unlock];
}
- (void)cancel {
    [_cond lock]; _cancelled = YES; [_cond broadcast]; [_cond unlock];
    if (_transmit) _transmit([EDSDSCodec handshake:0x7D packet:0 device:[self replyID]]);
}
- (void)reset { [_cond lock]; _cancelled = NO; _havePeer = NO; [_inbox removeAllObjects]; [_cond unlock]; }

/// Waits for a message whose sub-ID is in `subs` (others are dropped). nil on timeout or cancel.
- (NSData *)waitFor:(const uint8_t *)subs count:(int)cnt timeout:(NSTimeInterval)t {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:t];
    [_cond lock];
    NSData *found = nil;
    while (!_cancelled) {
        while (_inbox.count) {
            NSData *m = _inbox.firstObject; [_inbox removeObjectAtIndex:0];
            for (int i = 0; i < cnt; i++) if (((const uint8_t *)m.bytes)[3] == subs[i]) { found = m; break; }
            if (found) break;
        }
        if (found || [end timeIntervalSinceNow] <= 0) break;
        [_cond waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:MIN(0.2, MAX([end timeIntervalSinceNow], 0.01))]];
    }
    [_cond unlock];
    return found;
}

- (BOOL)sendSample:(EDSDSSample *)s progress:(void (^)(double, NSString *))progress error:(NSError **)error {
    [self reset];
    NSArray<NSData *> *packets = [EDSDSCodec packetsForSample:s device:_deviceID];
    if (!packets.count) { if (error) *error = SErr(@"The sample is empty"); return NO; }
    if (s.frames.length / 2 > 0x1FFFFF) { if (error) *error = SErr(@"The sample is too long for SDS (max 2,097,151 words)"); return NO; }
    static const uint8_t hs[] = {0x7F, 0x7E, 0x7D, 0x7C};
    BOOL closed = NO; CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent(); double ackWait = 0; NSUInteger acks = 0;
    for (int attempt = 0; attempt < (_openLoop ? 1 : 3); attempt++) {
        _transmit([EDSDSCodec headerForSample:s device:_deviceID]);
        if (progress) progress(0, @"Header sent, waiting for the sampler…");
        NSData *r = [self waitFor:hs count:4 timeout:_openLoop ? 0.3 : 2.0];
        if (_openLoop && r) { closed = NO; break; }
        if (_cancelled) { if (error) *error = SErr(@"Cancelled"); return NO; }
        if (!r) break;                                   // no handshake in 2 s: open loop, as the standard allows
        uint8_t code = ((const uint8_t *)r.bytes)[3];
        if (code == 0x7F) { closed = YES; break; }
        if (code == 0x7D) { if (error) *error = SErr(@"The sampler cancelled the transfer"); return NO; }
        if (code == 0x7C) { r = [self waitFor:hs count:4 timeout:60]; if (r && ((const uint8_t *)r.bytes)[3] == 0x7F) { closed = YES; break; } }
    }
    for (NSUInteger i = 0; i < packets.count; i++) {
        int retries = 0;
        for (;;) {
            _transmit(packets[i]);
            if (!closed) { [NSThread sleepForTimeInterval:0.002]; break; }
            CFAbsoluteTime w0 = CFAbsoluteTimeGetCurrent();
            NSData *r = [self waitFor:hs count:4 timeout:3.0];
            ackWait += CFAbsoluteTimeGetCurrent() - w0; acks++;
            if (_cancelled) { if (error) *error = SErr(@"Cancelled"); return NO; }
            if (!r) { if (error) *error = SErr(@"The sampler stopped answering"); return NO; }
            const uint8_t *b = r.bytes; uint8_t code = b[3];
            if (code == 0x7C) { r = [self waitFor:hs count:4 timeout:60]; if (!r) { if (error) *error = SErr(@"The sampler stayed busy"); return NO; } code = ((const uint8_t *)r.bytes)[3]; }
            if (code == 0x7D) { if (error) *error = SErr(@"The sampler cancelled the transfer"); return NO; }
            if (code == 0x7F) break;
            if (++retries > 3) { if (error) *error = SErr(@"Too many transmission errors"); return NO; }
        }
        if (progress) progress((double)(i + 1) / packets.count, [NSString stringWithFormat:@"Sent packet %lu of %lu", (unsigned long)i + 1, (unsigned long)packets.count]);
    }
    double total = CFAbsoluteTimeGetCurrent() - t0;
    _timing = [NSString stringWithFormat:@"%.1f s for %lu packets (%.0f ms each; wire minimum is about 41 ms)%@", total, (unsigned long)packets.count, total * 1000 / packets.count,
               acks ? [NSString stringWithFormat:@"; the sampler took %.0f ms on average to acknowledge", ackWait * 1000 / acks] : (closed ? @"" : @"; sent without handshake")];
    return YES;
}

- (EDSDSSample *)receiveWithRequest:(int)req headerTimeout:(NSTimeInterval)timeout progress:(void (^)(double, NSString *))progress error:(NSError **)error {
    [self reset];
    if (req >= 0) _transmit([EDSDSCodec requestForNumber:(uint16_t)req device:_deviceID]);
    if (progress) progress(0, req >= 0 ? @"Dump requested, waiting for the sampler…" : @"Waiting for the sampler to send a sample…");
    static const uint8_t hdrSub[] = {0x01}, dataSub[] = {0x02, 0x7D};
    NSData *hm = [self waitFor:hdrSub count:1 timeout:timeout];
    if (_cancelled) { if (error) *error = SErr(@"Cancelled"); return nil; }
    if (!hm) { if (error) *error = SErr(@"No sample header arrived (is the sampler's MIDI output connected and sending an SDS dump?)"); return nil; }
    uint32_t words = 0; uint8_t bits = 0;
    EDSDSSample *s = [EDSDSCodec parseHeader:hm length:&words bits:&bits];
    if (!s || !words) { if (error) *error = SErr(@"The sample header was not valid"); return nil; }
    if (bits > 16) { if (error) *error = SErr(@"Only samples up to 16 bits are supported"); return nil; }
    if (bits < 8) { if (error) *error = SErr(@"Word sizes below 8 bits are not supported"); return nil; }
    if (words > 16 * 1024 * 1024) { if (error) *error = SErr(@"The sample is too long"); return nil; }
    uint8_t rid = hm.length > 2 ? ((const uint8_t *)hm.bytes)[2] : _deviceID;
    if (progress) progress(0.001, [NSString stringWithFormat:@"Sampler is sending %u words at %u Hz (its device ID is %u)", words, s.sampleRate, rid]);
    _transmit([EDSDSCodec handshake:0x7F packet:0 device:rid]);
    NSMutableData *all = [NSMutableData data]; CFAbsoluteTime rt0 = CFAbsoluteTimeGetCurrent(), ackSent = 0; double turn = 0; NSUInteger turns = 0;
    NSUInteger wpp = [EDSDSCodec wordsPerPacketForBits:bits], nPackets = (words + wpp - 1) / wpp;
    for (NSUInteger i = 0; i < nPackets; i++) {
        uint8_t want = i & 0x7F; int retries = 0;
        for (;;) {
            NSData *m = [self waitFor:dataSub count:2 timeout:5.0];
            if (_cancelled) { if (error) *error = SErr(@"Cancelled"); return nil; }
            if (!m) { if (error) *error = SErr(@"The sampler stopped sending data"); return nil; }
            if (((const uint8_t *)m.bytes)[3] == 0x7D) { if (error) *error = SErr(@"The sampler cancelled the transfer"); return nil; }
            if (ackSent) { turn += CFAbsoluteTimeGetCurrent() - ackSent; turns++; ackSent = 0; }
            uint8_t pp = 0; NSData *w = [EDSDSCodec parsePacket:m bits:bits number:&pp];
            if (w && pp == want) { [all appendData:w]; _transmit([EDSDSCodec handshake:0x7F packet:want device:rid]); ackSent = CFAbsoluteTimeGetCurrent(); break; }
            if (w && pp == ((want - 1) & 0x7F)) { _transmit([EDSDSCodec handshake:0x7F packet:pp device:rid]); continue; }  // duplicate
            if (++retries > 3) { if (error) *error = SErr(@"Too many transmission errors"); return nil; }
            _transmit([EDSDSCodec handshake:0x7E packet:want device:rid]);
        }
        if (progress) progress((double)(i + 1) / nPackets, [NSString stringWithFormat:@"Received packet %lu of %lu", (unsigned long)i + 1, (unsigned long)nPackets]);
    }
    double rtotal = CFAbsoluteTimeGetCurrent() - rt0;
    _timing = [NSString stringWithFormat:@"%.1f s for %lu packets (%.0f ms each; wire minimum is about 41 ms); after each acknowledgement the sampler needed %.0f ms to send the next packet", rtotal, (unsigned long)nPackets, rtotal * 1000 / MAX(nPackets, 1), turns ? turn * 1000 / turns : 0.0];
    [all setLength:words * 2];
    s.frames = all;
    if (s.loopEnd >= words) s.loopEnd = words - 1;
    if (s.loopStart > s.loopEnd) s.loopStart = 0;
    return s;
}
@end

// MARK: bank sample bridge

@implementation EDSample (SDS)
- (EDSDSSample *)sdsRepresentation {
    EDSDSSample *s = [EDSDSSample new];
    NSUInteger n = self.frameCount, g = n > 2 * kGuardFrames ? kGuardFrames : 0;
    s.name = self.name ?: @"";
    s.number = self.number;                               // EOS keeps the sample number through a dump
    s.sampleRate = self.sampleRate;
    s.frames = [NSData dataWithBytes:self.leftFrames + g length:(n - 2 * g) * 2];
    s.loopEnabled = self.loopEnabled;
    s.loopStart = self.loopStart >= g ? (uint32_t)(self.loopStart - g) : 0;
    s.loopEnd = self.loopEnd >= g ? (uint32_t)(self.loopEnd - g) : 0;
    return s;
}
- (void)applySDSSample:(EDSDSSample *)s {
    NSUInteger got = s.frames.length / 2, n = got + 2 * kGuardFrames;
    NSMutableData *L = [NSMutableData dataWithLength:n * 2];
    memcpy((int16_t *)L.mutableBytes + kGuardFrames, s.frames.bytes, got * 2);
    self.sampleRate = s.sampleRate;
    [self replaceLeft:L right:nil];
    self.loopStart = s.loopEnabled ? s.loopStart + kGuardFrames : kGuardFrames;
    self.loopEnd = s.loopEnabled ? s.loopEnd + kGuardFrames : n - kGuardFrames - 1;
    self.loopEnabled = s.loopEnabled;
}
@end
