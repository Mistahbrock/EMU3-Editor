// New preset / new voice: adds them to a bank, saves, re-parses, and checks structure, TOC records and the untouched samples. Usage: newpresettest bank.e4b
#import <Foundation/Foundation.h>
#import "EDBank.h"
#import "EDPreset+Params.h"
#define CHECK(c, ...) do { if (!(c)) { printf("FAIL: " __VA_ARGS__); printf("\n"); return 1; } } while (0)
static uint32_t be32(const uint8_t *p) { return (p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]; }
// every TOC record must point at a chunk with the same id whose size matches (payload minus the bank's constant bias)
static int checkTOC(NSData *out, NSUInteger expectRecords) {
    const uint8_t *p = out.bytes; NSUInteger off = 12; NSMutableArray *offs = [NSMutableArray array]; int toc = -1;
    while (off + 8 <= out.length) { uint32_t sz = be32(p + off + 4); if (sz > out.length) break; [offs addObject:@(off)]; if (!memcmp(p + off, "TOC1", 4)) toc = (int)offs.count - 1; off += 8 + sz + (sz & 1); }
    if (toc < 0) return 0;
    NSUInteger to = [offs[toc] unsignedIntegerValue]; uint32_t tsz = be32(p + to + 4); NSUInteger records = tsz / 32;
    CHECK(records == expectRecords, "TOC has %lu records, expected %lu", (unsigned long)records, (unsigned long)expectRecords);
    for (NSUInteger r = 0; r < records; r++) { const uint8_t *e = p + to + 8 + r * 32; uint32_t pos = be32(e + 8), sz = be32(e + 4);
        CHECK(pos + 8 <= out.length && !memcmp(p + pos, e, 4), "TOC record %lu points at the wrong chunk", (unsigned long)r);
        uint32_t csz = be32(p + pos + 4); CHECK(csz == sz + 2 || csz == sz, "TOC record %lu size %u vs chunk %u", (unsigned long)r, sz, csz); }
    return 0;
}
int main(int argc, char **argv) { @autoreleasepool {
    NSData *d = [NSData dataWithContentsOfFile:@(argv[1])]; NSError *e = nil;
    EDBank *b = [EDBank bankWithData:d error:&e]; CHECK(b, "parse");
    NSUInteger presets0 = b.presets.count, samples0 = b.samples.count, chunks0 = b.chunks.count;
    NSUInteger toc0 = 0; for (EDChunk *c in b.chunks) if ([c.ident isEqual:@"TOC1"]) toc0 = c.data.length / 32;
    EDPreset *p = [b addPresetNamed:@"Brand New Preset X"]; CHECK(p, "addPreset");
    CHECK([p.name isEqualToString:@"Brand New Preset"], "name truncated to 16 chars, got '%s'", p.name.UTF8String);
    CHECK(b.presets.count == presets0 + 1 && b.chunks.count == chunks0 + 1, "counts");
    CHECK([p validateStructure] && [p voiceCount] == 0, "empty preset is valid");
    NSInteger sn = b.samples.firstObject.number;
    CHECK([p addVoiceWithSampleNumber:sn], "addVoice"); CHECK([p addVoiceWithSampleNumber:sn], "addVoice 2");
    CHECK([p validateStructure] && [p voiceCount] == 2 && [p refCountInVoice:1] == 1, "two voices, one ref each");
    EDParam *sample = nil; for (EDParam *q in [p paramsForScope:EDScopeRef]) if (q.isSample) sample = q;
    CHECK([p valueOfParam:sample voice:1 ref:0] == sn, "sample number stored");
    CHECK([p removeVoice:1] && [p voiceCount] == 1 && [p validateStructure], "delete voice");
    NSData *out = [b serializeWithError:&e]; CHECK(out, "serialize: %s", e.localizedDescription.UTF8String);
    EDBank *b2 = [EDBank bankWithData:out error:&e]; CHECK(b2, "reparse");
    CHECK(b2.presets.count == presets0 + 1 && b2.samples.count == samples0, "reparsed counts: %lu presets %lu samples", (unsigned long)b2.presets.count, (unsigned long)b2.samples.count);
    EDPreset *q = nil; for (EDPreset *x in b2.presets) if ([x.name isEqual:@"Brand New Preset"]) q = x;
    CHECK(q && [q validateStructure] && [q voiceCount] == 1, "new preset survives the round trip");
    CHECK(checkTOC(out, toc0 ? toc0 + 1 : 0) == 0, "TOC");
    for (NSUInteger i = 0; i < samples0; i++) CHECK([b2.samples[i].left isEqualToData:b.samples[i].left], "sample %lu audio changed", (unsigned long)i);
    // second round trip is stable
    NSData *out2 = [b2 serializeWithError:&e]; CHECK([out2 isEqualToData:out], "re-saving changes the bytes");
    // undo: removing the preset restores the original bytes
    CHECK([b removePreset:p], "removePreset");
    NSData *back = [b serializeWithError:&e]; EDBank *b3 = [EDBank bankWithData:back error:&e];
    CHECK(b3.presets.count == presets0 && b3.chunks.count == chunks0, "undo restores the chunk list");
    CHECK(!b.dirty, "after undoing a new preset the bank is clean again");
    CHECK(checkTOC(back, toc0) == 0, "TOC after undo");
    // delete an existing preset: the saved bank has one preset fewer, the TOC stays consistent, and undo restores the exact original bytes
    NSData *orig = [b serializeWithError:&e]; CHECK([orig isEqualToData:d], "unedited bank does not round-trip identically");
    EDPreset *victim = b.presets.firstObject; NSString *vname = victim.name;
    NSDictionary *st = [b detachPreset:victim]; CHECK(st, "detachPreset");
    CHECK(b.dirty, "deleting marks the bank as changed");
    NSData *gone = [b serializeWithError:&e]; EDBank *g = [EDBank bankWithData:gone error:&e];
    CHECK(g && g.presets.count == presets0 - 1 && g.samples.count == samples0, "deleted preset is gone, samples kept");
    for (EDPreset *x in g.presets) CHECK(![x.name isEqual:vname] || presets0 > 1, "deleted preset still present");
    CHECK(checkTOC(gone, toc0 ? toc0 - 1 : 0) == 0, "TOC after delete");
    [b reattachPreset:st];
    NSData *restored = [b serializeWithError:&e]; CHECK([restored isEqualToData:d], "undoing the delete does not restore the original bytes");
    // a bank holding one preset and the samples it uses
    {
        EDBank *src = [EDBank bankWithData:d error:&e]; EDPreset *sp = src.presets.firstObject;
        if ([sp voiceCount] == 0) CHECK([sp addVoiceWithSampleNumber:src.samples.firstObject.number], "voice for the export test");
        NSArray *missing = nil; NSData *pb = [src bankDataForPreset:sp missingSamples:&missing]; CHECK(pb, "bankDataForPreset");
        EDBank *x = [EDBank bankWithData:pb error:&e]; CHECK(x, "exported bank parses: %s", e.localizedDescription.UTF8String);
        EDParam *sprm = nil; for (EDParam *q in [sp paramsForScope:EDScopeRef]) if (q.isSample) sprm = q;
        NSMutableSet *used = [NSMutableSet set]; for (NSInteger v = 0; v < [sp voiceCount]; v++) for (NSInteger r = 0; r < [sp refCountInVoice:v]; r++) [used addObject:@([sp valueOfParam:sprm voice:v ref:r])];
        CHECK(x.presets.count == 1 && x.samples.count + missing.count == used.count, "exported bank: %lu presets, %lu samples, %lu missing, preset uses %lu", (unsigned long)x.presets.count, (unsigned long)x.samples.count, (unsigned long)missing.count, (unsigned long)used.count);
        CHECK([x.presets[0].name isEqualToString:sp.name] && [x.presets[0] validateStructure], "exported preset intact");
        for (EDSample *xs in x.samples) { EDSample *orig = nil; for (EDSample *o in src.samples) if (o.number == xs.number) orig = o; CHECK(orig && [orig.left isEqualToData:xs.left] && [orig.name isEqualToString:xs.name], "exported sample %u differs", xs.number); }
        NSData *again = [x serializeWithError:&e]; CHECK([again isEqualToData:pb], "exported bank is not stable when re-saved");
        CHECK(checkTOC(pb, 1 + x.samples.count) == 0, "TOC of the exported bank");
        printf("exported bank: 1 preset + %lu samples (%lu bytes)\n", (unsigned long)x.samples.count, (unsigned long)pb.length);
    }
    printf("new preset / voice tests passed (%lu presets, %lu samples, TOC records %lu)\n", (unsigned long)presets0, (unsigned long)samples0, (unsigned long)toc0);
    return 0; } }
