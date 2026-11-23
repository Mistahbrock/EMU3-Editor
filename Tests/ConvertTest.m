// Converts 3X banks to E4B and re-reads the result. Usage: converttest [-w out.e4b] file...
#import <Foundation/Foundation.h>
#import "EDBank.h"
#import "EDBankConverter.h"
#import "EDPreset+Params.h"
int main(int argc, char **argv) { @autoreleasepool {
    int banks = 0, bad = 0, pres = 0, smp = 0, warns = 0; const char *wr = NULL;
    for (int i = 1; i < argc; i++) { @autoreleasepool {
        if (!strcmp(argv[i], "-w") && i + 1 < argc) { wr = argv[++i]; continue; }
        NSData *d = [NSData dataWithContentsOfFile:@(argv[i])]; NSError *e = nil;
        EDBank *b = [EDBank bankWithData:d error:&e];
        if (!b || ![b.formType isEqualToString:@"3X"]) continue;
        NSArray *w = nil; NSData *o = [EDBankConverter e4bDataFromLegacyBank:b warnings:&w error:&e];
        if (!o) { printf("CONVERT FAIL %s: %s\n", argv[i], e.localizedDescription.UTF8String); bad++; continue; }
        EDBank *r = [EDBank bankWithData:o error:&e];
        if (!r) { printf("REPARSE FAIL %s: %s\n", argv[i], e.localizedDescription.UTF8String); bad++; continue; }
        banks++; warns += w.count;
        int lockedIn = 0, empty = 0; for (EDSample *s in b.samples) { if (s.locked) lockedIn++; else if (!s.frameCount) empty++; }
        if (r.samples.count + lockedIn + empty != b.samples.count || r.presets.count != b.presets.count) { printf("COUNT %s: %lu/%lu samples %lu/%lu presets\n", argv[i], (unsigned long)r.samples.count, (unsigned long)b.samples.count, (unsigned long)r.presets.count, (unsigned long)b.presets.count); bad++; }
        for (EDPreset *p in r.presets) if (![p validateStructure]) { printf("STRUCT %s %s\n", argv[i], p.name.UTF8String); bad++; break; }
        for (NSUInteger k = 0, j = 0; k < b.samples.count && j < r.samples.count; k++) {
            EDSample *x = b.samples[k]; if (x.locked || !x.frameCount) continue; EDSample *y = r.samples[j++];
            if (![x.left isEqualToData:y.left] || x.loopStart != y.loopStart || x.loopEnd != y.loopEnd || x.sampleRate != y.sampleRate || ![x.name isEqualToString:y.name] || x.number != y.number) { printf("SAMPLE MISMATCH %s #%u\n", argv[i], x.number); bad++; break; }
        }
        pres += r.presets.count; smp += r.samples.count;
        if (wr) { [o writeToFile:@(wr) atomically:YES]; wr = NULL; }
    } }
    printf("%d banks converted, %d presets, %d samples, %d warnings, %d problems\n", banks, pres, smp, warns, bad);
    return bad; } }
