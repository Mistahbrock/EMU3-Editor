// Codec round trip plus an in-memory sender↔receiver handshake, including a corrupted packet and open-loop sending.
#import <Foundation/Foundation.h>
#import "EDSDS.h"

static int fails = 0;
#define CHECK(c, m) do { if (!(c)) { printf("FAIL: %s\n", m); fails++; } } while (0)

static EDSDSSample *makeSample(NSUInteger n) {
    NSMutableData *d = [NSMutableData dataWithLength:n * 2]; int16_t *p = d.mutableBytes;
    for (NSUInteger i = 0; i < n; i++) p[i] = (int16_t)((int)(i * 977) % 65536 - 32768);
    p[0] = -32768; if (n > 1) p[1] = 32767;
    EDSDSSample *s = [EDSDSSample new]; s.number = 130; s.sampleRate = 44100; s.frames = d;
    s.loopEnabled = YES; s.loopStart = n > 10 ? 10 : 0; s.loopEnd = n > 5 ? (uint32_t)n - 5 : (uint32_t)n - 1; return s;
}

int main(void) { @autoreleasepool {
    for (int bi = 0; bi < 2; bi++) for (NSNumber *nn in @[@1, @39, @40, @41, @59, @60, @61, @1000, @5001]) {
        uint8_t wbits = bi ? 14 : 16;
        NSUInteger n = nn.unsignedIntegerValue; EDSDSSample *s = makeSample(n); s.bits = wbits;
        uint32_t len = 0; uint8_t bits = 0;
        NSData *h = [EDSDSCodec headerForSample:s device:5];
        EDSDSSample *h2 = [EDSDSCodec parseHeader:h length:&len bits:&bits];
        CHECK(h2 && len == n && bits == wbits && h2.number == 130 && h2.loopStart == s.loopStart && h2.loopEnd == s.loopEnd && h2.loopEnabled, "header round trip");
        CHECK(llabs((long long)h2.sampleRate - 44100) <= 1, "rate round trip");
        NSMutableData *all = [NSMutableData data];
        NSArray *pk = [EDSDSCodec packetsForSample:s device:5];
        NSUInteger wpp = [EDSDSCodec wordsPerPacketForBits:wbits]; CHECK(pk.count == (n + wpp - 1) / wpp, "packet count"); CHECK(h2.bits == wbits, "bits in header");
        for (NSData *m in pk) { uint8_t pp; NSData *w = [EDSDSCodec parsePacket:m bits:wbits number:&pp]; CHECK(w != nil, "packet parse"); if (w) [all appendData:w]; }
        [all setLength:n * 2];
        if (wbits == 16) CHECK([all isEqualToData:s.frames], "sample data round trip");
        else { const int16_t *a = all.bytes, *b2 = s.frames.bytes; BOOL ok = YES; for (NSUInteger k = 0; k < n; k++) if ((a[k] & ~3) != (b2[k] & ~3)) ok = NO; CHECK(ok, "14-bit data keeps the top 14 bits"); }
    }
    // corrupted checksum is rejected
    NSMutableData *bad = [[[EDSDSCodec packetsForSample:makeSample(80) device:0] firstObject] mutableCopy];
    ((uint8_t *)bad.mutableBytes)[20] ^= 1; uint8_t pp;
    CHECK([EDSDSCodec parsePacket:bad bits:16 number:&pp] == nil, "bad checksum rejected");

    // in-memory handshake: sender -> receiver, 130 packets so the packet counter wraps at 128
    for (int mode = 0; mode < 4; mode++) {  // 3 = fast send (open loop) to a receiver that still acknowledges   // 0 clean, 1 corrupt one packet, 2 receiver silent (open loop)
        EDSDSEngine *tx = [EDSDSEngine new], *rx = [EDSDSEngine new]; tx.deviceID = rx.deviceID = 0; tx.openLoop = mode == 3;
        __block int corruptLeft = mode == 1 ? 1 : 0;
        tx.transmit = ^(NSData *m) {
            NSData *out = m;
            if (corruptLeft && ((const uint8_t *)m.bytes)[3] == 0x02 && ((const uint8_t *)m.bytes)[4] == 7) {
                NSMutableData *c = [m mutableCopy]; ((uint8_t *)c.mutableBytes)[30] ^= 0x10; out = c; corruptLeft--; }
            if (mode != 2) dispatch_async(dispatch_get_global_queue(0, 0), ^{ [rx deliver:out]; });
            else if (((const uint8_t *)m.bytes)[3] == 0x01 || ((const uint8_t *)m.bytes)[3] == 0x02) dispatch_async(dispatch_get_global_queue(0, 0), ^{ [rx deliver:out]; });
        };
        rx.transmit = ^(NSData *m) { if (mode != 2) dispatch_async(dispatch_get_global_queue(0, 0), ^{ [tx deliver:m]; }); };
        EDSDSSample *src = makeSample(5200);
        __block EDSDSSample *got = nil; __block NSError *re = nil;
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(0, 0), ^{ got = [rx receiveWithRequest:-1 headerTimeout:10 progress:nil error:&re]; dispatch_semaphore_signal(done); });
        [NSThread sleepForTimeInterval:0.1];
        NSError *se = nil; BOOL ok = [tx sendSample:src progress:nil error:&se];
        dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC));
        CHECK(ok, se.localizedDescription.UTF8String ?: "send failed");
        CHECK(got && [got.frames isEqualToData:src.frames] && got.loopEnd == src.loopEnd, re.localizedDescription.UTF8String ?: "handshake transfer mismatch");
    }
    printf(fails ? "SDS: %d failures\n" : "SDS tests passed\n", fails);
    return fails != 0;
} }
