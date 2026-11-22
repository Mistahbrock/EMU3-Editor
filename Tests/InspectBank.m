// Prints what the model sees in real E4B banks and checks the unedited round trip. Usage: inspect file...
#import <Foundation/Foundation.h>
#import "EDBank.h"
int main(int argc, char **argv) { @autoreleasepool {
    int bad = 0, total = 0;
    for (int i = 1; i < argc; i++) {
        NSData *d = [NSData dataWithContentsOfFile:@(argv[i])]; NSError *e = nil;
        EDBank *b = [EDBank bankWithData:d error:&e];
        if (!b) { printf("%-40s PARSE FAIL: %s\n", argv[i], e.localizedDescription.UTF8String); bad++; continue; }
        NSData *out = [b serializeWithError:&e];
        BOOL same = [out isEqualToData:d];
        if (!same) bad++;
        if (getenv("QUIET") && same) { total++; continue; } printf("%-40s %lu chunks, %lu samples, %lu presets, roundtrip %s\n", argv[i], (unsigned long)b.chunks.count, (unsigned long)b.samples.count, (unsigned long)b.presets.count, same ? "IDENTICAL" : "DIFFERS");
        for (EDSample *s in b.samples) { if (s.number > 3 && s != b.samples.lastObject) continue;
            printf("   #%u %-16s %uHz frames=%lu loop=%d [%lu..%lu] flags=%04x %s\n", s.number, s.name.UTF8String, s.sampleRate, (unsigned long)s.frameCount, s.loopEnabled, (unsigned long)s.loopStart, (unsigned long)s.loopEnd, s.flags, s.right ? "stereo" : "mono"); }
    }
    if (getenv("QUIET")) printf("%d identical, %d problems\n", total, bad);
    return bad; } }
