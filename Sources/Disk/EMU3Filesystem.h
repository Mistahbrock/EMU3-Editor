#import <Foundation/Foundation.h>
#import "EMU3Types.h"

@class EMU3Directory;
@class EMU3File;

typedef void (^EMU3ProgressBlock)(double fraction, NSString *status);

// Error domain
extern NSString * const EMU3ErrorDomain;
typedef NS_ENUM(NSInteger, EMU3ErrorCode) {
    EMU3ErrorNotEMU3Image   = 1,
    EMU3ErrorReadFailed     = 2,
    EMU3ErrorWriteFailed    = 3,
    EMU3ErrorDiskFull       = 4,
    EMU3ErrorFileNotFound   = 5,
    EMU3ErrorInvalidParam   = 6,
    EMU3ErrorDirectoryFull  = 7,
};

@interface EMU3Filesystem : NSObject

// Serial queue — all file I/O must go through this to prevent data races
@property (nonatomic, readonly) dispatch_queue_t  ioQueue;

@property (nonatomic, readonly) NSURL            *imageURL;
@property (nonatomic, readonly) EMU3Directory    *rootDirectory;
@property (nonatomic, readonly) NSUInteger        totalBlocks;
@property (nonatomic, readonly) NSUInteger        usedBlocks;
@property (nonatomic, readonly) NSUInteger        freeBlocks;
@property (nonatomic, readonly) NSUInteger        clusterBlocks;   // blocks per allocation cluster (a bank takes whole clusters)
@property (nonatomic, readonly) NSUInteger        totalClusters;
@property (nonatomic, readonly) BOOL              isReadOnly;
@property (nonatomic, readonly) NSString         *volumeLabel;

// Open an existing .hda disk image
- (instancetype)initWithURL:(NSURL *)url error:(NSError **)error;

// Reload filesystem state from disk
- (BOOL)reload:(NSError **)error;

/// Flushes everything to disk and closes the image file (the object is unusable afterwards).
- (void)closeImage;

/// Optional guard around every modifying operation (used while the image is served to the sampler).
/// editGateBegin returns NO to refuse the operation; editGateEnd is called when it finished. They nest safely.
@property (atomic, copy) BOOL (^editGateBegin)(void);
@property (atomic, copy) void (^editGateEnd)(void);

/// While YES every write operation is refused (isReadOnly reports YES). Used for "sampler mode".
@property (atomic) BOOL locked;

/// Creates a new zero-filled image file of `bytes` and formats it with an empty EOS file system.
/// Floppy sizes (up to 4 MB) get a small layout: 3 FAT blocks, 2 kB clusters.
+ (BOOL)createFormattedImageAtURL:(NSURL *)url sizeBytes:(NSUInteger)bytes error:(NSError **)error;

/// Erases the whole image and writes an empty EOS file system (superblock, allocation table,
/// empty root directory) using the layout the sampler itself creates.
- (BOOL)formatWithError:(NSError **)error;

// Flush pending mmap writes to the backing image file.
- (BOOL)synchronizeToDisk:(NSError **)error;

// ──────────────────────────────────────────────────────────────────────────────
// File data access
// ──────────────────────────────────────────────────────────────────────────────

// Read raw bytes for a file (follows cluster chain)
- (NSData *)dataForFile:(EMU3File *)file error:(NSError **)error;

// Parse bank metadata from a bank file's raw data (non-destructive)
- (BOOL)populateBankMetadata:(EMU3File *)file error:(NSError **)error;

// ──────────────────────────────────────────────────────────────────────────────
// Filesystem operations (modify the image file)
// ──────────────────────────────────────────────────────────────────────────────

// Delete a file (marks dentry as deleted, frees clusters)
- (BOOL)deleteFile:(EMU3File *)file
       inDirectory:(EMU3Directory *)directory
             error:(NSError **)error;

// Copy a file to a destination directory (within the same image)
- (BOOL)copyFile:(EMU3File *)file
     toDirectory:(EMU3Directory *)destDir
            error:(NSError **)error;

// Move a file to a different directory (within the same image)
- (BOOL)moveFile:(EMU3File *)file
    fromDirectory:(EMU3Directory *)srcDir
      toDirectory:(EMU3Directory *)destDir
            error:(NSError **)error;

// Import an external file (raw bank data) into a directory
- (BOOL)importFileAtURL:(NSURL *)url
            toDirectory:(EMU3Directory *)destDir
                  error:(NSError **)error;

// Overwrite a file's contents in place, keeping its directory entry, bank id and first cluster.
- (BOOL)replaceContentsOfFile:(EMU3File *)file
                     withData:(NSData *)data
                        error:(NSError **)error;

// Export a file from the image to a host path
- (BOOL)exportFile:(EMU3File *)file
              toURL:(NSURL *)destURL
              error:(NSError **)error;

// Rename a file (changes the name field in the dentry, max 15 chars)
- (BOOL)renameFile:(EMU3File *)file
           newName:(NSString *)newName
       inDirectory:(EMU3Directory *)directory
             error:(NSError **)error;

// Rename a folder (changes the name in its directory entry, max 15 characters)
- (BOOL)renameDirectory:(EMU3Directory *)dir
                newName:(NSString *)newName
                  error:(NSError **)error;

// Create a new empty subdirectory inside a parent directory
- (BOOL)createDirectoryNamed:(NSString *)name
                 inDirectory:(EMU3Directory *)parent
                       error:(NSError **)error;

// Delete a directory and all its contents (recursive)
- (BOOL)deleteDirectory:(EMU3Directory *)dir
             fromParent:(EMU3Directory *)parent
                  error:(NSError **)error;

// ──────────────────────────────────────────────────────────────────────────────
// Sample export (from E4B0 bank files)
// ──────────────────────────────────────────────────────────────────────────────

// Get array of sample chunk IDs from a bank file (e.g., @[@"E4S0", @"E4S1", ...])
- (NSArray<NSString *> *)samplesFromBankFile:(EMU3File *)bankFile
                                        error:(NSError **)error;

// Export a sample from a bank file to a WAV file
// sampleIndex: 0-based index of the sample to export
// Returns YES on success, NO with error details on failure
- (BOOL)exportSampleAtIndex:(NSUInteger)sampleIndex
               fromBankFile:(EMU3File *)bankFile
                      toURL:(NSURL *)destURL
                      error:(NSError **)error;

@end
