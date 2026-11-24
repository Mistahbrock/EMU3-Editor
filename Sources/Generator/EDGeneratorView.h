// EDGeneratorView — the Generator page: a list of generators on the left, the selected generator's panel on the right, audition / add on the bottom.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>
#import "EDGenerator.h"

NS_ASSUME_NONNULL_BEGIN
@interface EDGeneratorView : NSView <EDGeneratorHost>
/// Called for "Add to Bank". Return the sample number it got, or 0 with *message set when it could not be added.
@property (nonatomic, copy, nullable) NSInteger (^addToBank)(EDGeneratedSample *sample, NSString *_Nullable *_Nonnull message);
@property (nonatomic, copy, nullable) BOOL (^bankAvailable)(void);
- (void)stopAudition;
/// Shows the generator with this identifier (e.g. "com.rhynoaudio.organ").
- (void)selectIdentifier:(NSString *)identifier;
@end
NS_ASSUME_NONNULL_END
