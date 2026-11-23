// Import presets from one bank into another: copies the presets with their samples, saves, re-parses, and checks the table of contents,
// unique numbers, and that every voice points at a sample that exists in the destination. Usage: importtest dest.e4b source.e4b
#import <Foundation/Foundation.h>
#import "EDBank.h"
#import "EDPreset+Params.h"
#define CHECK(c, ...) do { if (!(c)) { printf("FAIL: " __VA_ARGS__); printf("\n"); return 1; } } while (0)
static uint32_t be32(const uint8_t *p) { return (p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]; }
int main(int argc, char **argv) { @autoreleasepool {
    NSError *e = nil;
    EDBank *dst = [EDBank bankWithData:[NSData dataWithContentsOfFile:@(argv[1])] error:&e]; CHECK(dst, "parse dest");
    EDBank *src = [EDBank bankWithData:[NSData dataWithContentsOfFile:@(argv[2])] error:&e]; CHECK(src, "parse source");
    NSUInteger p0 = dst.presets.count, s0 = dst.samples.count;
    NSMutableArray *pick = [NSMutableArray array]; for (EDPreset *p in src.presets) if (p.kind == EDPresetKindE4 && pick.count < 3 && [p voiceCount] > 0) [pick addObject:p];
    CHECK(pick.count, "source has no presets");
    NSUInteger copied = 0; NSArray *missing = nil;
    NSArray *added = [dst importPresets:pick fromBank:src samplesCopied:&copied missingSamples:&missing]; CHECK(added.count == pick.count, "added %lu of %lu", (unsigned long)added.count, (unsigned long)pick.count);
    CHECK(dst.presets.count == p0 + pick.count && dst.samples.count == s0 + copied, "counts");
    CHECK(dst.dirty, "bank should be dirty");
    NSData *out = [dst serializeWithError:&e]; CHECK(out, "serialize");
    EDBank *re = [EDBank bankWithData:out error:&e]; CHECK(re, "re-parse");
    CHECK(re.presets.count == p0 + pick.count && re.samples.count == s0 + copied, "re-parsed counts %lu/%lu", (unsigned long)re.presets.count, (unsigned long)re.samples.count);
    NSMutableSet *sn = [NSMutableSet set]; for (EDSample *s in re.samples) { CHECK(![sn containsObject:@(s.number)], "duplicate sample number %u", s.number); [sn addObject:@(s.number)]; }
    NSMutableSet *pn = [NSMutableSet set]; for (EDPreset *p in re.presets) { CHECK(![pn containsObject:@(p.number)], "duplicate preset number %u", p.number); [pn addObject:@(p.number)]; }
    // TOC: every record points at a chunk with the same id
    const uint8_t *b = out.bytes; NSUInteger off = 12, toc = 0; NSMutableArray *offs = [NSMutableArray array];
    while (off + 8 <= out.length) { uint32_t sz = be32(b + off + 4); [offs addObject:@(off)]; if (!memcmp(b + off, "TOC1", 4)) toc = off; off += 8 + sz + (sz & 1); }
    for (NSUInteger r = 0; toc && r < be32(b + toc + 4) / 32; r++) { const uint8_t *rec = b + toc + 8 + r * 32; uint32_t pos = be32(rec + 8);
        CHECK(pos + 8 <= out.length && !memcmp(b + pos, rec, 4), "TOC record %lu wrong", (unsigned long)r); }
    // new presets' voices resolve (unless the source lacked the sample)
    for (NSUInteger i = p0; i < re.presets.count; i++) { EDPreset *p = re.presets[i]; EDParam *sp = nil; for (EDParam *q in [p paramsForScope:EDScopeRef]) if (q.isSample) sp = q;
        for (NSInteger v = 0; v < [p voiceCount]; v++) for (NSInteger r = 0; r < [p refCountInVoice:v]; r++) { NSInteger n = [p valueOfParam:sp voice:v ref:r];
            if (![missing containsObject:@(n)]) CHECK([sn containsObject:@(n)], "preset '%s' voice %ld points at missing sample %ld", p.name.UTF8String, (long)v, (long)n); } }
    // existing samples unchanged
    for (NSUInteger i = 0; i < s0; i++) CHECK([re.samples[i].name isEqualToString:dst.samples[i].name], "existing sample %lu changed", (unsigned long)i);
    printf("import ok: %lu presets, %lu samples copied, %lu missing\n", (unsigned long)added.count, (unsigned long)copied, (unsigned long)missing.count);
    return 0;
} }
