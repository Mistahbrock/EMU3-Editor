// EDSMDI — SMDI (SCSI Musical Data Interchange) client and the BlueSCSI initiator link.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
//
// SMDI messages travel inside SCSI SEND (0x0A) and RECEIVE (0x08) commands addressed to the sampler (a "processor" device):
//   message = "SMDI" + messageID (BE32) + additional length (BE24) + body
// Message layouts follow the published OpenSMDI library (Christian Nowak, LGPL), verified against an E-mu EOS 4.62 sampler.
// The Mac reaches the SCSI bus through the BlueSCSI firmware's USB passthrough (see docs/SMDI.md); any other SCSI path can be plugged in
// through EDSMDIExec.
#import <Foundation/Foundation.h>
#import "EDSDS.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const EDSMDIErrorDomain;
enum { EDSMDIErrorNoSample = 2, EDSMDIErrorRejected = 3, EDSMDIErrorTransport = 4, EDSMDIErrorCancelled = 5, EDSMDIErrorProtocol = 6 };

@interface EDSMDIResult : NSObject
@property (nonatomic) uint8_t result;       // 0 ok, 1 no target answered, 2 bus/data phase error, 3 request rejected
@property (nonatomic) uint8_t status;       // SCSI status byte (0 good, 2 check condition)
@property (nonatomic, copy) NSData *sense;
@property (nonatomic, copy) NSData *data;
@end

/// Runs one SCSI command: returns nil with `error` only on transport failure; SCSI-level failures are in the result.
typedef EDSMDIResult * _Nullable (^EDSMDIExec)(uint8_t target, NSData *cdb, NSData * _Nullable dataOut, uint32_t inLen, NSError * _Nullable * _Nullable error);

/// The BlueSCSI board in initiator mode with the passthrough firmware, reached over its second USB serial port.
@interface EDSMDIBoard : NSObject
/// All /dev/cu.usbmodem* ports (the passthrough is the second port of the board's pair).
+ (NSArray<NSString *> *)availablePorts;
+ (nullable NSString *)defaultPort;
/// The board's log console port that goes with a passthrough port (same name stem, lower interface number).
+ (nullable NSString *)consolePortForPassthrough:(NSString *)passthroughPort;
/// Asks the board to reboot into 'i' (SCSI initiator / SMDI) or 't' (SCSI target / disk) mode through its console port, then
/// waits for it to re-enumerate. Blocking (up to ~15 s): call it off the main thread. Returns the board's new passthrough port, or nil.
/// emu3linkd (the Disk Manager's login helper) keeps the board's passthrough port open and fights SMDI for its bytes.
/// Freezes it (SIGSTOP) for the SMDI session; a detached watchdog thaws it if this app dies. Returns its pid or 0 if none/unable.
+ (pid_t)suspendLinkHelper;
+ (void)resumeLinkHelper:(pid_t)pid;
+ (nullable NSString *)switchMode:(char)mode passthroughPort:(NSString *)port;
@property (nonatomic, readonly, copy, nullable) NSString *path;
@property (nonatomic, readonly) uint8_t ownID;
- (BOOL)openPath:(NSString *)path error:(NSError **)error;      // also pings the board
- (void)close;
- (EDSMDIExec)executor;
@end

@interface EDSMDIInfo : NSObject
@property (nonatomic) uint32_t number, length, periodNs, loopStart, loopEnd;
@property (nonatomic) uint8_t bits, channels, loopControl;
@property (nonatomic) uint16_t pitch;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, readonly) uint32_t sampleRate;
@end

/// One device that answered INQUIRY during a bus scan.
@interface EDSMDIDevice : NSObject
@property (nonatomic) uint8_t scsiID, deviceType;     // type 0 disk, 3 processor (samplers answer SMDI as a processor), 5 CD-ROM …
@property (nonatomic, copy) NSString *vendor, *product, *revision;
@property (nonatomic, readonly) NSString *typeName;
@property (nonatomic, readonly) BOOL looksLikeSampler;
@end

@interface EDSMDIClient : NSObject
/// INQUIRY every ID 0…7 except `host`; returns the ones that answered, in ID order.
+ (NSArray<EDSMDIDevice *> *)scanBus:(EDSMDIExec)exec skipping:(uint8_t)host cancelled:(BOOL (^ _Nullable)(void))cancelled;
/// The SMDI slave-identify reply of the last successful -masterIdentify: (raw, including the 11-byte message header).
@property (nonatomic, readonly, copy, nullable) NSData *identifyReply;
@property (nonatomic, copy) EDSMDIExec exec;
@property (nonatomic) uint8_t target;                  // sampler's SCSI ID (default 6)
@property (nonatomic, readonly, copy) NSString *timingSummary;
- (instancetype)initWithExec:(EDSMDIExec)exec target:(uint8_t)target;
- (void)cancel;                                        // any thread
- (BOOL)masterIdentify:(NSError **)error;
/// Header of sample `number` (1…999); nil with EDSMDIErrorNoSample when that slot is empty.
- (nullable EDSMDIInfo *)infoForSample:(uint32_t)number error:(NSError **)error;
- (BOOL)deleteSample:(uint32_t)number error:(NSError **)error;
- (BOOL)sendSample:(EDSDSSample *)s number:(uint32_t)number name:(NSString *)name
          progress:(nullable void (^)(double fraction, NSString *status))progress error:(NSError **)error;
- (nullable EDSDSSample *)receiveSample:(uint32_t)number info:(EDSMDIInfo * _Nullable * _Nullable)info
                               progress:(nullable void (^)(double fraction, NSString *status))progress error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
