// EDPresetLCD — the Preset Edit screens of the sampler (Global, Voice, Zone pages) drawn as green LCD pages.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>
#import "EDPreset+Params.h"

NS_ASSUME_NONNULL_BEGIN
@interface EDPresetLCD : NSView
@property (nonatomic, copy, nullable) NSInteger (^getValue)(EDParam *p, NSInteger voice, NSInteger ref);
@property (nonatomic, copy, nullable) void (^setValue)(EDParam *p, NSInteger voice, NSInteger ref, NSInteger value);
@property (nonatomic, copy, nullable) void (^navigate)(NSInteger voice, NSInteger ref);   // the voice / zone arrows
@property (nonatomic, copy, nullable) NSString *(^sampleName)(NSInteger number);
/// voice / ref are -1 when the preset itself (or a voice) is selected in the structure list.
- (void)showPreset:(nullable EDPreset *)p voice:(NSInteger)voice ref:(NSInteger)ref;
@end
NS_ASSUME_NONNULL_END
