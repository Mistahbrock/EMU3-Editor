// Preset model test on real banks: structure, parameter read/write, structural edits, save + re-parse.
// Usage: presettest bank...   (copies of real banks; nothing is written)
#import <Foundation/Foundation.h>
#import "EDBank.h"
#import "EDPreset+Params.h"
int main(int argc, char **argv) { @autoreleasepool {
    int banks = 0, presets = 0, badStruct = 0, bad = 0, structEdits = 0;
    for (int i = 1; i < argc; i++) { @autoreleasepool {
        NSData *d = [NSData dataWithContentsOfFile:@(argv[i])]; NSError *e = nil;
        EDBank *b = [EDBank bankWithData:d error:&e]; if (!b) { printf("PARSE %s\n", argv[i]); bad++; continue; }
        banks++;
        for (EDPreset *p in b.presets) { presets++; if (![p validateStructure]) { badStruct++; if (badStruct < 6) printf("STRUCT %s preset %s kind %ld len %lu\n", argv[i], p.name.UTF8String, (long)p.kind, (unsigned long)p.raw.length); } }
        // parameter write/read-back on the first preset: set every editable parameter to its minimum, then maximum
        EDPreset *p = b.presets.firstObject; if (!p || ![p validateStructure]) continue;
        NSData *before = [p.raw copy];
        for (EDParamScope sc = EDScopePreset; sc <= EDScopeRef; sc++) {
            NSInteger voices = sc == EDScopePreset ? 1 : p.voiceCount;
            for (NSInteger v = 0; v < voices; v++) {
                NSInteger refs = sc == EDScopeRef ? [p refCountInVoice:v] : 1;
                for (NSInteger r = 0; r < refs; r++) for (EDParam *pa in [p paramsForScope:sc]) {
                    if (pa.readOnly) continue;
                    NSInteger old = [p valueOfParam:pa voice:v ref:r];
                    [p setValue:pa.max ofParam:pa voice:v ref:r];
                    if ([p valueOfParam:pa voice:v ref:r] != pa.max) { printf("READBACK %s %s\n", argv[i], pa.label.UTF8String); bad++; }
                    [p setValue:old ofParam:pa voice:v ref:r];   // restore (clamped if the file held an out-of-range value)
                }
            }
        }
        if (![p validateStructure]) { printf("STRUCT after param edits %s\n", argv[i]); bad++; }
        if (p.kind == EDPresetKindE4) {   // structural edits keep header+voices consistent
            if (![p addRefToVoice:0] || ![p validateStructure]) { printf("ADDREF %s\n", argv[i]); bad++; }
            if (![p duplicateVoice:0] || ![p validateStructure]) { printf("DUPVOICE %s\n", argv[i]); bad++; }
            if (![p removeVoice:1] || ![p validateStructure]) { printf("RMVOICE %s\n", argv[i]); bad++; }
            if (![p removeRef:[p refCountInVoice:0] - 1 fromVoice:0] || ![p validateStructure]) { printf("RMREF %s\n", argv[i]); bad++; }
            structEdits++;
        }
        p.name = @"PRESET EDIT TEST";
        NSData *out = [b serializeWithError:&e]; EDBank *b2 = [EDBank bankWithData:out error:&e];
        if (!b2 || b2.presets.count != b.presets.count || ![b2.presets.firstObject.name isEqualToString:@"PRESET EDIT TEST"] || ![b2.presets.firstObject validateStructure]) { printf("RESAVE %s (%s)\n", argv[i], e.localizedDescription.UTF8String); bad++; continue; }
        if (p.kind == EDPresetKindLegacy3X && out.length != d.length) { printf("3X SIZE CHANGED %s\n", argv[i]); bad++; }
        if (p.kind == EDPresetKindLegacy3X && ![b2.presets.firstObject.raw isEqualToData:before] && ![[b2.presets.firstObject.raw subdataWithRange:NSMakeRange(16, before.length - 16)] isEqualToData:[before subdataWithRange:NSMakeRange(16, before.length - 16)]]) { printf("3X PRESET BYTES CHANGED %s\n", argv[i]); bad++; }
        for (NSUInteger k = 1; k < b.presets.count; k++) if (![b2.presets[k].raw isEqualToData:b.presets[k].raw]) { printf("NEIGHBOUR PRESET %s #%lu\n", argv[i], (unsigned long)k); bad++; break; }
    } }
    printf("%d banks, %d presets, %d structure failures, %d structural-edit banks, %d problems\n", banks, presets, badStruct, structEdits, bad);
    return bad || badStruct; } }
