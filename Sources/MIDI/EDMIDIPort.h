// EDMIDIPort — CoreMIDI sysex transport for EDSDSEngine.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>

NS_ASSUME_NONNULL_BEGIN
@interface EDMIDIEndpointInfo : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) MIDIEndpointRef ref;
@end

@interface EDMIDIPort : NSObject
+ (NSArray<EDMIDIEndpointInfo *> *)destinations;
+ (NSArray<EDMIDIEndpointInfo *> *)sources;
/// Called for every complete system-exclusive message (F0 … F7) from the connected source.
@property (nonatomic, copy, nullable) void (^onSysex)(NSData *message);
- (BOOL)connectSource:(nullable EDMIDIEndpointInfo *)source destination:(nullable EDMIDIEndpointInfo *)dest error:(NSError **)error;
- (void)disconnect;
/// Queues the message (blocks only when 4 are already waiting); -flush waits for all of them to be sent.
- (void)sendSysex:(NSData *)message;
- (void)flush;
@end
NS_ASSUME_NONNULL_END
