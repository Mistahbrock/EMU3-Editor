// Erase all presets and samples: the bank must still serialize, reload empty, and a sample added back must survive a round trip.
#import <Foundation/Foundation.h>
#import "EDBank.h"
int main(int argc, char **argv) { @autoreleasepool {
    NSData *d = [NSData dataWithContentsOfFile:@(argv[1])]; NSError *e = nil;
    EDBank *b = [EDBank bankWithData:d error:&e]; if (!b) { fprintf(stderr, "load failed\n"); return 1; }
    NSUInteger ns = b.samples.count, np = b.presets.count; if (!ns && !np) { fprintf(stderr, "test bank is empty\n"); return 1; }
    [b eraseAllPresetsAndSamples];
    if (b.samples.count || b.presets.count) { fprintf(stderr, "not empty after erase\n"); return 1; }
    if (!b.dirty) { fprintf(stderr, "erased bank should report unsaved changes\n"); return 1; }
    NSData *out = [b serializeWithError:&e]; if (!out) { fprintf(stderr, "serialize failed: %s\n", e.localizedDescription.UTF8String); return 1; }
    EDBank *r = [EDBank bankWithData:out error:&e]; if (!r) { fprintf(stderr, "reload failed: %s (%lu bytes)\n", e.localizedDescription.UTF8String, (unsigned long)out.length); return 1; }
    if (r.samples.count || r.presets.count) { fprintf(stderr, "reloaded bank not empty\n"); return 1; }
    [b markClean]; if (b.dirty) { fprintf(stderr, "markClean left the bank dirty\n"); return 1; }
    EDPreset *p = [b addPresetNamed:@"After"]; if (!p || !b.dirty) { fprintf(stderr, "add after erase failed\n"); return 1; }
    NSData *out2 = [b serializeWithError:&e]; EDBank *r2 = out2 ? [EDBank bankWithData:out2 error:&e] : nil;
    if (!r2 || r2.presets.count != 1) { fprintf(stderr, "round trip after add failed\n"); return 1; }
    printf("erase tests passed (%lu samples, %lu presets erased)\n", (unsigned long)ns, (unsigned long)np);
} return 0; }
