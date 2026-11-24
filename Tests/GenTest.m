// Generator: adding a new sample to an E4B bank survives a save / reload.
#import <Foundation/Foundation.h>
#import "EDBank.h"
static int fails = 0;
#define CHECK(c, m) do { if (!(c)) { printf("FAIL: %s\n", m); fails++; } else printf("ok:   %s\n", m); } while (0)
int main(int argc, char **argv) { @autoreleasepool {
    NSError *e = nil; EDBank *b = [EDBank bankWithData:[NSData dataWithContentsOfFile:@(argv[1])] error:&e];
    NSUInteger before = b.samples.count;
    NSMutableData *pcm = [NSMutableData dataWithLength:2000 * 2]; int16_t *p = pcm.mutableBytes; for (int i = 0; i < 2000; i++) p[i] = (int16_t)(12000 * sin(i * 0.1));
    EDSample *s = [b addSampleNamed:@"Org 888000000 C3" rate:48000 left:pcm right:nil loopStart:500 loopEnd:1499 loop:YES];
    CHECK(s && b.samples.count == before + 1, "sample added");
    CHECK(s.number == 3 && b.dirty, "lowest free number, bank dirty");
    NSData *out = [b serializeWithError:&e]; CHECK(out != nil, "serialize");
    EDBank *b2 = [EDBank bankWithData:out error:&e]; CHECK(b2 && b2.samples.count == before + 1, "reparse has the new sample");
    EDSample *t = b2.samples.lastObject;
    CHECK([t.name isEqualToString:@"Org 888000000 C3"] && t.number == 3 && t.sampleRate == 48000, "name, number, rate");
    CHECK(t.frameCount == 2008 && t.loopEnabled && t.loopStart == 504 && t.loopEnd == 1503, "frames (+8 guard) and loop");
    CHECK(memcmp((const uint8_t *)t.left.bytes + 8, pcm.bytes, 2000 * 2) == 0, "audio intact");
    NSData *again = [b2 serializeWithError:&e]; CHECK([again isEqualToData:out], "stable on a second round trip");
    CHECK([b2 removeSample:t] && b2.samples.count == before, "removable (undo)");
    printf(fails ? "%d FAILED\n" : "all ok\n", fails); return fails ? 1 : 0;
} }
