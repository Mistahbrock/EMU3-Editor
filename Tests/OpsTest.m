// Sample tools: swap, mono/stereo, sample-rate convert, digital tuning, bit convert.
#import <Foundation/Foundation.h>
#import "EDBank.h"
#import "EDSample+Ops.h"
static int fails = 0;
#define CHECK(c, m) do { if (!(c)) { printf("FAIL: %s\n", m); fails++; } else printf("ok:   %s\n", m); } while (0)
int main(int argc, char **argv) { @autoreleasepool {
    NSError *e = nil; EDBank *b = [EDBank bankWithData:[NSData dataWithContentsOfFile:@(argv[1])] error:&e];
    EDSample *s = b.samples[0]; NSUInteger n0 = s.frameCount; NSUInteger ls = s.loopStart, le = s.loopEnd;
    CHECK(!s.isStereo, "test sample is mono");
    [s convertToStereo]; CHECK(s.isStereo && memcmp(s.leftFrames, s.rightFrames, n0 * 2) == 0, "mono to stereo duplicates");
    NSMutableData *r = [s.right mutableCopy]; int16_t *rp = r.mutableBytes; for (NSUInteger i = 0; i < n0; i++) rp[i] = (int16_t)(rp[i] / 2);
    NSData *l0 = [s.left copy], *r0 = [r copy]; [s replaceLeft:s.left right:r];
    [s swapChannels]; CHECK([s.left isEqualToData:r0] && [s.right isEqualToData:l0], "swap left and right");
    [s swapChannels]; [s convertToMono]; CHECK(!s.isStereo && s.frameCount == n0, "stereo to mono");
    const int16_t *m = s.leftFrames, *a = l0.bytes; BOOL ok = YES; for (NSUInteger i = 0; i < n0; i++) { int w = ((int)a[i] + (int)((const int16_t *)r0.bytes)[i]) / 2; if (m[i] != w) ok = NO; } CHECK(ok, "mono is the average");
    s.loopStart = ls; s.loopEnd = le;
    [s convertToSampleRate:22050];
    CHECK(s.sampleRate == 22050 && llabs((long)s.frameCount - (long)(n0 / 2)) <= 1, "22.05 kHz: half the frames");
    CHECK(llabs((long)s.loopStart - (long)(ls / 2)) <= 1 && llabs((long)s.loopEnd - (long)(le / 2)) <= 1, "loop points follow");
    [s convertToSampleRate:44100]; CHECK(llabs((long)s.frameCount - (long)n0) <= 2, "back to 44.1 kHz restores the length");
    NSUInteger n1 = s.frameCount; [s tuneByCents:1200]; CHECK(llabs((long)s.frameCount - (long)(n1 / 2)) <= 1 && s.sampleRate == 44100, "+1200 cents halves the length, rate unchanged");
    [s tuneByCents:-1200]; CHECK(llabs((long)s.frameCount - (long)n1) <= 2, "-1200 cents doubles it back");
    [s reduceToBits:4 dither:NO]; const int16_t *q = s.leftFrames; ok = YES; for (NSUInteger i = 0; i < s.frameCount; i++) if ((q[i] % 4096) != 0 && q[i] != 32767 && q[i] != -32768) ok = NO; CHECK(ok, "4-bit values are multiples of 4096");
    printf(fails ? "%d FAILED\n" : "all ok\n", fails);
    return fails ? 1 : 0;
} }
