// Command-line round-trip test for the E4B model. Build/run: see Tests/run-tests.sh
#import <Foundation/Foundation.h>
#import "EDBank.h"
static int fails = 0;
#define CHECK(c, m) do { if (!(c)) { printf("FAIL: %s\n", m); fails++; } else printf("ok:   %s\n", m); } while (0)
int main(int argc, char **argv) { @autoreleasepool {
    NSData *orig = [NSData dataWithContentsOfFile:@(argv[1])];
    NSError *e = nil; EDBank *b = [EDBank bankWithData:orig error:&e];
    CHECK(b != nil, "parse bank");
    CHECK(b.samples.count == 2 && b.presets.count == 1, "2 samples + 1 preset found");
    EDSample *s = b.samples[0];
    CHECK([s.name isEqualToString:@"Sine A"] && s.sampleRate == 44100, "sample name/rate");
    CHECK(s.frameCount == 1008 && s.loopEnabled && s.loopStart == 104 && s.loopEnd == 904, "frames + loop points");
    CHECK(!b.dirty, "clean after load");
    NSData *same = [b serializeWithError:&e];
    CHECK([same isEqualToData:orig], "unedited bank serializes byte-identical");
    s.loopStart = 200; s.loopEnd = 800; s.name = @"Renamed Sample X1"; s.loopEnabled = NO;
    EDSample *s2 = b.samples[1];
    NSMutableData *half = [[s2.left subdataWithRange:NSMakeRange(0, 400)] mutableCopy];   // shrink -> TOC must move
    [s2 replaceLeft:half right:nil];
    NSData *out = [b serializeWithError:&e];
    CHECK(out != nil, "serialize edited bank");
    EDBank *b2 = [EDBank bankWithData:out error:&e];
    CHECK(b2 && b2.samples.count == 2, "re-parse edited bank");
    EDSample *t = b2.samples[0];
    CHECK([t.name isEqualToString:@"Renamed Sample X"] && t.loopStart == 200 && t.loopEnd == 800 && !t.loopEnabled, "edits persisted (name cut to 16)");
    CHECK(b2.samples[1].frameCount == 200, "shrunk sample has 200 frames");
    NSData *again = [b2 serializeWithError:&e];
    CHECK([again isEqualToData:out], "edited bank is stable on a second round trip");
    // TOC positions must point at chunk headers in the new file
    const uint8_t *p = out.bytes; NSUInteger tocSize = (p[16]<<24)|(p[17]<<16)|(p[18]<<8)|p[19];
    BOOL tocOK = YES;
    for (NSUInteger r = 0; r < tocSize/32; r++) { const uint8_t *en = p + 20 + r*32; uint32_t pos = (en[8]<<24)|(en[9]<<16)|(en[10]<<8)|en[11];
        if (pos + 4 > out.length || memcmp(p + pos, en, 4) != 0) tocOK = NO; }
    CHECK(tocOK, "TOC1 positions point at matching chunk headers");
    NSURL *wav = [NSURL fileURLWithPath:@"/tmp/ed-selftest.wav"];
    CHECK([b.samples[0] writeWAVToURL:wav error:&e], "WAV export");
    EDSample *imp = b2.samples[1];
    CHECK([imp replaceAudioFromURL:wav error:&e] && imp.frameCount == 1008, "WAV round trip restores 1008 frames (export drops, import re-adds 4+4 guard frames)");
    // single-sample bank for "send to sampler disk"
    NSData *one = [EDBank singleSampleBankDataForSample:b.samples[1]];
    EDBank *ob = one ? [EDBank bankWithData:one error:&e] : nil;
    CHECK(ob && ob.samples.count == 1 && ob.presets.count == 0, "single-sample bank parses");
    CHECK(ob && [ob.samples[0].left isEqualToData:b.samples[1].left] && ob.samples[0].loopEnd == b.samples[1].loopEnd && [ob.samples[0].name isEqualToString:b.samples[1].name], "single-sample bank keeps audio, loop and name");
    CHECK(ob && [[ob serializeWithError:&e] length] == one.length, "single-sample bank re-serializes to the same size");
    printf(fails ? "\n%d FAILED\n" : "\nall passed\n", fails);
    return fails ? 1 : 0; } }
