// EDGenerator — the Add On interface of the Generator: a generator makes a sample from a few parameters (an organ tone, a fractal, …).
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
//
// A generator is a class that conforms to EDGeneratorPlugin. Built-in ones are registered by EDGeneratorRegistry; others are loaded as bundles
// (extension .addon) from  ~/Library/Application Support/EMU3 Editor/Add Ons/  — the bundle's principal class must conform to the protocol.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// What a generator hands to the host: plain 16-bit frames, no guard padding (the host adds what the sampler expects).
@interface EDGeneratedSample : NSObject
@property (nonatomic, copy) NSString *name;            // up to 16 characters
@property (nonatomic) uint32_t sampleRate;
@property (nonatomic, copy) NSData *left;               // int16 frames
@property (nonatomic, copy, nullable) NSData *right;    // int16 frames, same length as left; nil = mono
@property (nonatomic) BOOL loop;
@property (nonatomic) NSUInteger loopStart, loopEnd;    // frame indexes (loopEnd inclusive)
@end

/// What the host offers to a generator.
@protocol EDGeneratorHost <NSObject>
/// Plays a generated sample (looping when it has a loop) until -generatorStop or the next call.
- (void)generatorAudition:(EDGeneratedSample *)sample;
- (void)generatorStop;
/// Tells the host the parameters changed (it may refresh the audition).
- (void)generatorChanged;
@end

@protocol EDGeneratorPlugin <NSObject>
@property (class, nonatomic, readonly) NSString *generatorIdentifier;   // stable, e.g. "com.rhynoaudio.organ"
@property (class, nonatomic, readonly) NSString *generatorName;         // shown in the list
@property (class, nonatomic, readonly) NSString *generatorSummary;      // one line under the name
- (instancetype)initWithHost:(id<EDGeneratorHost>)host;
/// The parameter panel. Created once; the host sizes it to the available space.
@property (nonatomic, readonly) NSView *view;
/// Renders the current settings. nil when there is nothing to make (for example every drawbar is off).
- (nullable EDGeneratedSample *)render;
@end

@interface EDGeneratorRegistry : NSObject
/// Built-in generator classes plus those loaded from the Add On folder, in list order.
+ (NSArray<Class<EDGeneratorPlugin>> *)builtInGenerators;   // ship with the editor (Simple Tones)
+ (NSArray<Class<EDGeneratorPlugin>> *)addOns;              // Add Ons: shipped extras plus bundles from the Add Ons folder
+ (NSArray<Class<EDGeneratorPlugin>> *)generators;          // built-ins first, then Add Ons
+ (NSURL *)addOnFolder;          // in use: Settings ▸ Add Ons, else "Add Ons" inside the Disk images folder set in Settings, else the default
+ (NSURL *)defaultAddOnFolder;   // ~/Library/Application Support/EMU3 Editor/Add Ons
@end

NS_ASSUME_NONNULL_END
