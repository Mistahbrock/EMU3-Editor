// EDRemoteDisk — a SCSI disk read through the BlueSCSI board's USB passthrough (initiator mode), mirrored on demand into a sparse
// cache file, so the normal EOS file system code can browse it as if it were an image. Read-only: nothing is ever written to the drive.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Foundation/Foundation.h>
#import "EDSMDI.h"

NS_ASSUME_NONNULL_BEGIN
@interface EDRemoteDisk : NSObject
@property (nonatomic, readonly) NSURL *cacheURL;
@property (nonatomic, readonly) NSUInteger totalBlocks;
@property (nonatomic, readonly, copy) NSString *product;          // "CONNOR CFP1800 2.0"
@property (nonatomic, readonly) uint8_t target;
/// Called (any thread) with a short status text while blocks are being read.
@property (nonatomic, copy, nullable) void (^onStatus)(NSString *text);
- (instancetype)initWithExec:(EDSMDIExec)exec target:(uint8_t)target cacheURL:(NSURL *)cacheURL;
/// Blocking: INQUIRY, READ CAPACITY, creates the sparse cache file and reads the file system's header, allocation table and directories.
- (BOOL)prepareWithError:(NSError **)error;
/// Blocking until the blocks are in the cache file. On the main thread the run loop keeps running while it waits.
- (BOOL)ensureBlocks:(NSUInteger)first count:(NSUInteger)count;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
