#import <Foundation/Foundation.h>
#import "EMU3Types.h"

@interface EMU3File : NSObject

@property (nonatomic, copy)   NSString   *name;
@property (nonatomic, assign) EMU3FileType fileType;
@property (nonatomic, assign) uint8_t    rawType;     // on-disk type byte
@property (nonatomic, assign) uint8_t    entryId;
@property (nonatomic, assign) uint16_t   startCluster;
@property (nonatomic, assign) uint16_t   clusterCount;
@property (nonatomic, assign) uint16_t   blocksInLastCluster;
@property (nonatomic, assign) uint16_t   bytesInLastBlock;
@property (nonatomic, assign) NSUInteger fileSize;     // computed

// Directory entry location (for modification)
@property (nonatomic, assign) NSInteger  dentryBlock;  // block index in dir
@property (nonatomic, assign) NSInteger  dentryOffset; // entry index within block

// Resolved raw file data (lazy — call -[filesystem dataForFile:])
@property (nonatomic, strong) NSData    *cachedData;

- (BOOL)isDeleted;
- (NSString *)fileSizeString;
- (NSString *)fileTypeString;

// Bank metadata (populated if fileType == EMU3FileTypeBank)
@property (nonatomic, copy)   NSString        *bankName;
@property (nonatomic, assign) EMU3BankFormat   bankFormat;
@property (nonatomic, assign) NSUInteger       presetCount;
@property (nonatomic, assign) NSUInteger       sampleCount;
@property (nonatomic, assign) BOOL             metadataParsed;   // bank metadata already read

@end

// E-mu names may contain "/" (e.g. "FX/Analog Toms"), which is a path separator on the Mac.
// Temp/export files use U+2215 (DIVISION SLASH) instead, and it is mapped back on import.
static inline NSString *EMU3FileSafeName(NSString *name) {
    return [name stringByReplacingOccurrencesOfString:@"/" withString:@"\u2215"];
}
static inline NSString *EMU3NameFromFileName(NSString *name) {
    return [name stringByReplacingOccurrencesOfString:@"\u2215" withString:@"/"];
}
