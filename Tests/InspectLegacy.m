// Scans 3X banks: parse, unedited round trip, edited round trip. Usage: inspectlegacy file...
#import <Foundation/Foundation.h>
#import "EDBank.h"
#import "EDSample+Ops.h"
int main(int argc, char **argv) { @autoreleasepool {
    int total = 0, bad = 0, samples = 0, locked = 0, presets = 0;
    for (int i = 1; i < argc; i++) { @autoreleasepool {
        NSData *d = [NSData dataWithContentsOfFile:@(argv[i])]; NSError *e = nil;
        EDBank *b = [EDBank bankWithData:d error:&e];
        if (!b) { printf("PARSE FAIL %s: %s\n", argv[i], e.localizedDescription.UTF8String); bad++; continue; }
        total++; samples += b.samples.count; presets += b.presets.count;
        for (EDSample *s in b.samples) if (s.locked) locked++;
        NSData *out = [b serializeWithError:&e];
        if (![out isEqualToData:d]) { printf("NOT IDENTICAL %s\n", argv[i]); bad++; continue; }
        // edited round trip on the first editable sample: rename, loop move, gain (same size) ...
        EDSample *s = nil; for (EDSample *x in b.samples) if (!x.locked && x.frameCount > 100) { s = x; break; }
        if (s) {
            NSUInteger n = s.frameCount, ls = s.loopStart, le = s.loopEnd;
            s.name = @"EDIT TEST"; s.loopStart = ls + 1; s.loopEnd = le - 1; [s applyGainDB:-3];
            NSData *o1 = [b serializeWithError:&e]; EDBank *b2 = [EDBank bankWithData:o1 error:&e];
            if (!b2 || o1.length != d.length) { printf("EDIT SAME-SIZE FAIL %s (%s)\n", argv[i], e.localizedDescription.UTF8String); bad++; continue; }
            EDSample *t = b2.samples[[b.samples indexOfObject:s]];
            if (![t.name isEqualToString:@"EDIT TEST"] || t.loopStart != ls + 1 || t.loopEnd != le - 1 || t.frameCount != n) { printf("EDIT MISMATCH %s\n", argv[i]); bad++; continue; }
            // ... then shrink it: every other sample must be untouched and the bank must stay consistent
            [s cropToFrom:10 to:n - 20];
            NSData *o2 = [b serializeWithError:&e]; EDBank *b3 = [EDBank bankWithData:o2 error:&e];
            if (!b3 || b3.samples.count != b.samples.count) { printf("RESIZE FAIL %s (%s)\n", argv[i], e.localizedDescription.UTF8String); bad++; continue; }
            for (NSUInteger k = 0; k < b.samples.count; k++) {
                EDSample *x = b.samples[k], *y = b3.samples[k];
                if (x == s) { if (y.frameCount != x.frameCount) { printf("RESIZE LEN %s\n", argv[i]); bad++; } continue; }
                if (![x.left isEqualToData:y.left] || x.loopStart != y.loopStart || ![x.name isEqualToString:y.name]) { printf("RESIZE NEIGHBOUR %s #%lu (edited #%lu) left %d loop %d name %d locked %d/%d len %lu/%lu\n", argv[i], (unsigned long)k, (unsigned long)[b.samples indexOfObject:s], [x.left isEqualToData:y.left], x.loopStart == y.loopStart, [x.name isEqualToString:y.name], x.locked, y.locked, (unsigned long)x.left.length, (unsigned long)y.left.length); bad++; break; }
            }
        }
    } }
    printf("%d banks, %d samples (%d locked), %d presets, %d problems\n", total, samples, locked, presets, bad);
    return bad; } }
