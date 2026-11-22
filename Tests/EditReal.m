// Edits a real bank in memory (rename + loop move + shrink), saves, re-parses and validates the TOC. Usage: editreal file
#import <Foundation/Foundation.h>
#import "EDBank.h"
int main(int argc, char **argv) { @autoreleasepool {
    NSData *d = [NSData dataWithContentsOfFile:@(argv[1])]; NSError *e = nil;
    EDBank *b = [EDBank bankWithData:d error:&e]; EDSample *s = b.samples[0], *l = b.samples.lastObject;
    s.name = @"EDITED NAME"; s.loopStart = s.loopStart + 2; s.loopEnd = s.loopEnd - 2;
    NSData *half = [l.left subdataWithRange:NSMakeRange(0, (l.frameCount / 2) * 2)];
    [l replaceLeft:half right:l.right ? [l.right subdataWithRange:NSMakeRange(0, half.length)] : nil];
    NSData *out = [b serializeWithError:&e]; EDBank *b2 = [EDBank bankWithData:out error:&e];
    if (!b2) { printf("FAIL reparse: %s\n", e.localizedDescription.UTF8String); return 1; }
    printf("name=%s loop=%lu..%lu lastFrames %lu->%lu, size %lu->%lu\n", b2.samples[0].name.UTF8String, (unsigned long)b2.samples[0].loopStart,
           (unsigned long)b2.samples[0].loopEnd, (unsigned long)l.frameCount*2, (unsigned long)b2.samples.lastObject.frameCount, (unsigned long)d.length, (unsigned long)out.length);
    // validate TOC: each record's position must hit a chunk with the same id, size must equal payload-2, name must match
    const uint8_t *p = out.bytes; int toc = -1; NSUInteger off = 12; int ok = 0, bad = 0;
    NSMutableArray *offs = [NSMutableArray array];
    while (off + 8 <= out.length) { uint32_t sz = (p[off+4]<<24)|(p[off+5]<<16)|(p[off+6]<<8)|p[off+7]; if (sz > out.length) break;
        [offs addObject:@(off)]; if (!memcmp(p+off, "TOC1", 4)) toc = (int)offs.count-1; off += 8 + sz + (sz&1); }
    if (toc >= 0) { NSUInteger to = [offs[toc] unsignedIntegerValue]; uint32_t tsz = (p[to+4]<<24)|(p[to+5]<<16)|(p[to+6]<<8)|p[to+7];
        for (NSUInteger r = 0; r < tsz/32; r++) { const uint8_t *en = p + to + 8 + r*32;
            uint32_t sz = (en[4]<<24)|(en[5]<<16)|(en[6]<<8)|en[7], pos = (en[8]<<24)|(en[9]<<16)|(en[10]<<8)|en[11];
            uint32_t csz = pos + 8 <= out.length ? (p[pos+4]<<24)|(p[pos+5]<<16)|(p[pos+6]<<8)|p[pos+7] : 0;
            if (pos + 8 <= out.length && !memcmp(p+pos, en, 4) && csz == sz + 2) ok++; else { bad++; printf("bad TOC record %lu\n", (unsigned long)r); } } }
    printf("TOC records ok=%d bad=%d, trailing bytes %lu\n", ok, bad, (unsigned long)(out.length - off));
    return bad; } }
