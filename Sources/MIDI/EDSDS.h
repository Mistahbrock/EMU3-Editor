// EDSDS — MIDI Sample Dump Standard (SDS) codec and handshake engine.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
//
// Message layout (MIDI 1.0 Sample Dump Standard):
//   Header   F0 7E dd 01 sl sm bits pppppp(3) llllll(3) ssssss(3) eeeeee(3) type F7
//   Packet   F0 7E dd 02 pp <120 data bytes = 40 words × 3> cc F7      (cc = XOR of 7E..data)
//   Request  F0 7E dd 03 sl sm F7
//   ACK 7F / NAK 7E / CANCEL 7D / WAIT 7C:  F0 7E dd <code> pp F7
// Words are unsigned and left-justified: 16-bit signed sample ^ 0x8000, 7 bits per byte, MSB first.
#import <Foundation/Foundation.h>
#import "EDBank.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const EDSDSErrorDomain;

/// One mono sample as carried by SDS.
@interface EDSDSSample : NSObject
@property (nonatomic) uint16_t number;
@property (nonatomic, copy) NSString *name;       // optional, carried by SMDI (SDS has no names)
@property (nonatomic) uint32_t sampleRate;
@property (nonatomic) uint8_t bits;                // word size on the wire, 14 or 16 (default 16)
@property (nonatomic, copy) NSData *frames;      // host-order int16
@property (nonatomic) BOOL loopEnabled;
@property (nonatomic) uint32_t loopStart, loopEnd;   // frame indexes into `frames`
@end

@interface EDSDSCodec : NSObject
+ (NSData *)headerForSample:(EDSDSSample *)s device:(uint8_t)dev;
+ (NSArray<NSData *> *)packetsForSample:(EDSDSSample *)s device:(uint8_t)dev;
+ (NSData *)requestForNumber:(uint16_t)n device:(uint8_t)dev;
+ (NSData *)handshake:(uint8_t)code packet:(uint8_t)pp device:(uint8_t)dev;
/// Parses a header message; nil if it is not a valid 16-bit-or-less header. `length` is the word count.
+ (nullable EDSDSSample *)parseHeader:(NSData *)msg length:(uint32_t *)length bits:(uint8_t *)bits;
/// Parses a data packet for the given word size; returns the words (host int16) or nil when the checksum or size is wrong. `pp` gets the packet number.
+ (nullable NSData *)parsePacket:(NSData *)msg bits:(uint8_t)bits number:(uint8_t *)pp;
/// Words carried by one data packet for a given word size (120 data bytes per packet).
+ (NSUInteger)wordsPerPacketForBits:(uint8_t)bits;
@end

/// Blocking send/receive with handshaking. Transport-agnostic: feed incoming messages with -deliver:, outgoing go to `transmit`.
@interface EDSDSEngine : NSObject
@property (nonatomic, copy) void (^transmit)(NSData *message);
@property (nonatomic) uint8_t deviceID;
/// Send without waiting for ACKs (wire speed, no error recovery). The standard allows it; the sampler must tolerate it.
@property (nonatomic) BOOL openLoop;
/// After a transfer: where the time went (average packet and handshake turnaround).
@property (nonatomic, readonly, copy) NSString *timingSummary;
- (void)deliver:(NSData *)message;                 // any thread
- (void)cancel;                                    // any thread; aborts a running transfer
- (BOOL)sendSample:(EDSDSSample *)s progress:(nullable void (^)(double fraction, NSString *status))progress error:(NSError **)error;
/// requestNumber < 0: just wait for the sampler to start a dump. Blocks up to `timeout` seconds for the header.
- (nullable EDSDSSample *)receiveWithRequest:(int)requestNumber headerTimeout:(NSTimeInterval)timeout
                                    progress:(nullable void (^)(double fraction, NSString *status))progress error:(NSError **)error;
@end

/// Conversion between sample-bank samples (with their 4 guard frames per side) and SDS samples.
@interface EDSample (SDS)
- (EDSDSSample *)sdsRepresentation;
- (void)applySDSSample:(EDSDSSample *)s;
@end

NS_ASSUME_NONNULL_END
