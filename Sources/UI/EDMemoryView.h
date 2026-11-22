// EDMemoryView — the sampler's Master "Memory" screen (resident / preset / sample memory, used against total) for the open bank.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@interface EDMemoryView : NSView
@property (nonatomic) double residentTotalK, presetTotalK, sampleTotalMB;   // the sampler's memory sizes
@property (nonatomic) double residentUsedK, presetUsedK, sampleUsedMB;      // what the open bank needs
@end
NS_ASSUME_NONNULL_END
