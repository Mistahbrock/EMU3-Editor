// EMU3Filesystem.m: reads and writes E-mu EOS disk images.
// The bank-table offsets and the structures in EMU3Types.h follow emu3fs and emu3bm,
// Copyright (C) 2018 David García Goñi <dagargo@gmail.com>, GNU GPL version 3 or later.
// The rest is Copyright (C) 2026 Rhyno Audio. Part of EMU3 Disk Manager, free software under the GPLv3.

#import "NSData+EDWrite.h"
#import "EMU3Filesystem.h"
#import "EMU3File.h"
#import "EMU3Directory.h"
#import <errno.h>
#import <string.h>
#import <sys/mman.h>
#import <sys/stat.h>

NSString * const EMU3ErrorDomain = @"com.emu3diskmanager.error";

// ──────────────────────────────────────────────────────────────────────────────
// Superblock layout — confirmed from hex analysis of real .hda images.
// All fields are uint32 little-endian.
//
//   Offset 0x00: magic        "EMU3"
//   Offset 0x04: format_flags (version/disk type ID)
//   Offset 0x08: root_dir_block       (index of first root-directory block)
//   Offset 0x0C: [reserved]
//   Offset 0x10: [reserved]
//   Offset 0x14: [reserved]
//   Offset 0x18: [reserved]
//   Offset 0x1C: [reserved]
//   Offset 0x20: data_area_block      (first block of file-data area)
//   Offset 0x24: [reserved]
//   Offset 0x28: fat_start_block      (first block of cluster allocation table)
//   Offset 0x2C: slot_size_kb         (per-file slot size in KB; blocks = val × 2)
// ──────────────────────────────────────────────────────────────────────────────
#pragma pack(push,1)
typedef struct {
    char     magic[4];      // "EMU3"
    uint32_t fields[127];   // 127 × uint32 = 508 bytes; key indices in EMU3Types.h
} emu3_superblock_t;        // total = 512 bytes
#pragma pack(pop)

static inline uint32_t be32(const uint8_t *p) {
    return (uint32_t)((p[0]<<24) | (p[1]<<16) | (p[2]<<8) | p[3]);
}
static BOOL emu3_chunk_is_sample(const uint8_t *chunkID) {
    return memcmp(chunkID, "E3S1", 4) == 0 ||
           memcmp(chunkID, "E4s1", 4) == 0 ||
           memcmp(chunkID, "E4S1", 4) == 0 ||
           memcmp(chunkID, "ESND", 4) == 0;
}
static BOOL emu3_chunk_is_preset(const uint8_t *chunkID) {
    return memcmp(chunkID, "E3P1", 4) == 0 ||
           memcmp(chunkID, "E4P1", 4) == 0;
}

@interface EMU3Filesystem () {
    uint8_t        *_imageBytes;   // mmap or malloc backing
    NSUInteger      _imageSize;
    int             _fd;
    BOOL            _mmapped;
}
@property (nonatomic, readwrite) dispatch_queue_t ioQueue;   // Serial — all file I/O
@property (nonatomic, readwrite) NSURL          *imageURL;
@property (nonatomic, readwrite) EMU3Directory  *rootDirectory;
@property (nonatomic, readwrite) NSUInteger      totalBlocks;
@property (nonatomic, readwrite) NSUInteger      usedBlocks;
@property (nonatomic, readwrite) NSUInteger      freeBlocks;
@property (nonatomic, readwrite) NSUInteger      totalClusters;
@property (nonatomic, readwrite) BOOL            isReadOnly;
@property (nonatomic, readwrite) NSString       *volumeLabel;

// Parsed from superblock
@property (nonatomic) NSUInteger  rootDirBlock;
@property (nonatomic) NSUInteger  rootDirBlockCount;   // superblock dword 2: blocks reserved for the root directory
@property (nonatomic) NSUInteger  dirPoolStart;        // superblock dword 3: first block of the folder pool
@property (nonatomic) NSUInteger  dirPoolCount;        // superblock dword 4: number of blocks in the folder pool
@property (nonatomic) NSUInteger  dataAreaBlock;    // first block of file data area
@property (nonatomic) NSUInteger  slotSizeBlocks;   // (legacy, unused)
@property (nonatomic, readwrite) NSUInteger  clusterBlocks;    // blocks per cluster; a file is a FAT chain of clusters
@property (nonatomic) NSUInteger  maxClusterIndex;  // superblock dword 8: highest cluster number
@property (nonatomic) NSUInteger  fatBlockCount;    // superblock dword 6: blocks used by the allocation table
@property (nonatomic) NSUInteger  fatStartBlock;    // first block of FAT
@property (nonatomic) NSUInteger  usableClusterLimit; // clusters that fit completely inside the disk
@end

// ── edit gate: every modifying public method brackets its work with the optional editGateBegin/End blocks ──
@interface EMU3Filesystem (EditGate)
- (BOOL)_beginEditError:(NSError **)error;
- (void)_endEdit;
@end
typedef struct { __unsafe_unretained EMU3Filesystem *fs; BOOL active; } EMU3EditToken;
static void EMU3EditEnd(EMU3EditToken *t) { if (t->active) [t->fs _endEdit]; }
#define EMU3_GATED_EDIT \
    EMU3EditToken _edTok __attribute__((cleanup(EMU3EditEnd))) = { self, NO }; \
    if (![self _beginEditError:error]) return NO; \
    _edTok.active = YES;

@implementation EMU3Filesystem

- (BOOL)isReadOnly { return _isReadOnly || self.locked; }

- (void)dealloc {
    [self _unmapImage];
}

- (instancetype)initWithURL:(NSURL *)url error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    self.imageURL = url;
    self.ioQueue  = dispatch_queue_create("com.emu3diskmanager.io", DISPATCH_QUEUE_SERIAL);
    if (![self _mapImageWithError:error]) return nil;
    if (![self _parseFilesystemWithError:error]) {
        [self _unmapImage];
        return nil;
    }
    return self;
}

- (BOOL)reload:(NSError **)error {
    // Re-parse without remapping
    return [self _parseFilesystemWithError:error];
}

// Formats the image: erases all folders and banks and writes an empty EOS file system.
// Layout rules derived from images formatted by a real E-mu sampler (1 GB and 14 GB):
//   FAT blocks F6, clusters F8 = 256*F6-1, root dir = 7 blocks right after the FAT,
//   folder pool = F8/16 + 106 blocks, data area after the pool, cluster = 32 kB << (5 + log2(size/1 GB)), header field 9 = 0x100 | shift.
+ (BOOL)createFormattedImageAtURL:(NSURL *)url sizeBytes:(NSUInteger)bytes error:(NSError **)error {
    if (bytes < 64 * EMU3_BLOCK_SIZE || bytes % EMU3_BLOCK_SIZE) { if (error) *error = [NSError errorWithDomain:EMU3ErrorDomain code:EMU3ErrorInvalidParam userInfo:@{NSLocalizedDescriptionKey: @"Bad image size"}]; return NO; }
    int fd = open(url.fileSystemRepresentation, O_RDWR | O_CREAT | O_TRUNC, 0644);
    if (fd < 0 || ftruncate(fd, (off_t)bytes) != 0) {
        if (fd >= 0) close(fd);
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Could not create %@: %s", url.lastPathComponent, strerror(errno)]}];
        return NO;
    }
    close(fd);
    EMU3Filesystem *fs = [[EMU3Filesystem alloc] init];
    fs.imageURL = url; fs.ioQueue = dispatch_queue_create("com.emu3diskmanager.io", DISPATCH_QUEUE_SERIAL); fs->_fd = -1;
    if (![fs _mapImageWithError:error]) return NO;
    BOOL ok = [fs formatWithError:error];
    [fs closeImage];
    return ok;
}

- (BOOL)formatWithError:(NSError **)error {
    EMU3_GATED_EDIT
    if (self.isReadOnly || !_imageBytes) {
        if (error) *error = [self _errorCode:EMU3ErrorWriteFailed message:@"Image is read-only"];
        return NO;
    }
    // Largest disk the sampler (EOS 4.62 on the E6400) was measured to address: 512 GB. Beyond that the
    // SCSI format stalls (tested 1023 GB and 1 TB), so the file system stops at 512 GB.
    const NSUInteger kMaxBlocks = (NSUInteger)1 << 30;
    NSUInteger total = MIN((NSUInteger)(_imageSize / EMU3_BLOCK_SIZE), kMaxBlocks);   // 2^30 blocks = 512 GB
    NSInteger lg = (NSInteger)floor(log2((double)total / 2097152.0));   // 2097152 blocks = 1 GB
    // Measured on the sampler: 32 GB .. 512 GB disks all get a 4-block FAT and 1023 clusters of size/1024.
    BOOL floppy = total <= 8192;   // up to 4 MB: a floppy-sized volume
    NSInteger fatBlocks = floppy ? 3 : (lg >= 5 ? 4 : MAX(2, MIN(16, 4 + lg)));
    NSUInteger maxClusters = 256 * (NSUInteger)fatBlocks - 1;
    NSUInteger fatStart = 2;
    NSUInteger rootStart = fatStart + fatBlocks;
    NSUInteger rootCount = 7;
    NSUInteger poolStart = rootStart + rootCount;
    NSUInteger poolCount = maxClusters / 16 + 106;
    NSUInteger dataStart = poolStart + poolCount;
    if (total < dataStart + maxClusters) {
        if (error) *error = [self _errorCode:EMU3ErrorWriteFailed message:@"Image is too small to format"];
        return NO;
    }

    memset(_imageBytes, 0, dataStart * EMU3_BLOCK_SIZE);   // header, FAT, root and folder pool
    uint32_t f[12] = { (uint32_t)(total - 1), (uint32_t)rootStart, (uint32_t)rootCount,
                       (uint32_t)poolStart, (uint32_t)poolCount, (uint32_t)fatStart,
                       (uint32_t)fatBlocks, (uint32_t)dataStart, (uint32_t)maxClusters,
                       (uint32_t)(floppy ? 0x100 : 0x100 + MAX(1, MIN(14, 5 + lg))), 2048, 0x0D010000 };   // floppy: cluster size comes from the geometry (2 kB)
    memcpy(_imageBytes, "EMU3", 4);
    for (int i = 0; i < 12; i++) {
        uint32_t v = CFSwapInt32HostToLittle(f[i]);
        memcpy(_imageBytes + 4 + 4 * i, &v, 4);
    }
    // Block 0 ends with a checksum: the 16-bit sum of the first 255 little-endian words
    // (verified against both sampler-formatted reference images).
    uint16_t sum = 0;
    for (int i = 0; i < 255; i++) sum += (uint16_t)(_imageBytes[2 * i] | (_imageBytes[2 * i + 1] << 8));
    _imageBytes[510] = sum & 0xFF; _imageBytes[511] = sum >> 8;
    uint32_t nextFree = CFSwapInt32HostToLittle((uint32_t)poolStart);   // block 1: next free folder block
    memcpy(_imageBytes + EMU3_BLOCK_SIZE, &nextFree, 4);
    uint16_t reserved = CFSwapInt16HostToLittle(EMU3_USED_CLUSTER);     // FAT entry 0
    memcpy(_imageBytes + fatStart * EMU3_BLOCK_SIZE, &reserved, 2);
    if (msync(_imageBytes, dataStart * EMU3_BLOCK_SIZE, MS_SYNC) != 0) {
        if (error) *error = [self _errorCode:EMU3ErrorWriteFailed message:@"Could not flush the image to disk"];
        return NO;
    }
    if (![self _parseFilesystemWithError:error]) return NO;
    // The sampler's own format creates one empty "Default Folder" in the root.
    if (![self createDirectoryNamed:@"Default Folder" inDirectory:self.rootDirectory error:error]) return NO;
    uint32_t next = CFSwapInt32HostToLittle((uint32_t)(poolStart + 1));   // block 1: next free folder block
    memcpy(_imageBytes + EMU3_BLOCK_SIZE, &next, 4);
    msync(_imageBytes, dataStart * EMU3_BLOCK_SIZE, MS_SYNC);
    return YES;
}

- (void)closeImage {
    dispatch_sync(self.ioQueue, ^{ });          // let pending reads/writes finish
    if (_mmapped && _imageBytes && _imageBytes != MAP_FAILED) msync(_imageBytes, _imageSize, MS_SYNC);
    if (_fd >= 0) fsync(_fd);
    [self _unmapImage];
}

- (BOOL)synchronizeToDisk:(NSError **)error {
    if (!_mmapped || !_imageBytes || _imageBytes == MAP_FAILED || _imageSize == 0) return YES;
    if (msync(_imageBytes, _imageSize, MS_SYNC) == 0) return YES;

    if (error) {
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                     code:errno
                                 userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Could not flush image to disk: %s", strerror(errno)]}];
    }
    return NO;
}

// ──────────────────────────────────────────────────────────────────────────────
// mmap helpers
// ──────────────────────────────────────────────────────────────────────────────

- (BOOL)_mapImageWithError:(NSError **)error {
    const char *path = self.imageURL.fileSystemRepresentation;
    _fd = open(path, O_RDWR);
    BOOL readOnly = NO;
    if (_fd < 0) {
        _fd = open(path, O_RDONLY);
        readOnly = YES;
    }
    if (_fd < 0) {
        if (error) *error = [NSError errorWithDomain:EMU3ErrorDomain
                                                code:EMU3ErrorReadFailed
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:@"Cannot open file: %@",
                                                            self.imageURL.path]}];
        return NO;
    }
    struct stat st;
    fstat(_fd, &st);
    _imageSize = (NSUInteger)st.st_size;
    int prot = PROT_READ | (readOnly ? 0 : PROT_WRITE);
    _imageBytes = mmap(NULL, _imageSize, prot, MAP_SHARED, _fd, 0);
    if (_imageBytes == MAP_FAILED) {
        close(_fd);
        _fd = -1;
        if (error) *error = [NSError errorWithDomain:EMU3ErrorDomain
                                                code:EMU3ErrorReadFailed
                                            userInfo:@{NSLocalizedDescriptionKey:@"mmap failed"}];
        return NO;
    }
    _mmapped = YES;
    self.isReadOnly = readOnly;
    if (!readOnly) fcntl(_fd, F_NOCACHE, 1);   // do not fill RAM with data written to the image
    return YES;
}

- (void)_unmapImage {
    if (_mmapped && _imageBytes && _imageBytes != MAP_FAILED) {
        munmap(_imageBytes, _imageSize);
        _imageBytes = NULL;
        _mmapped = NO;
    }
    if (_fd >= 0) {
        close(_fd);
        _fd = -1;
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// Block access helpers
// ──────────────────────────────────────────────────────────────────────────────

- (const uint8_t *)_blockPtr:(NSUInteger)blockIdx {
    NSUInteger offset = blockIdx * EMU3_BLOCK_SIZE;
    if (offset + EMU3_BLOCK_SIZE > _imageSize) return NULL;
    return _imageBytes + offset;
}

- (uint8_t *)_mutableBlockPtr:(NSUInteger)blockIdx {
    NSUInteger offset = blockIdx * EMU3_BLOCK_SIZE;
    if (offset + EMU3_BLOCK_SIZE > _imageSize) return NULL;
    return _imageBytes + offset;
}

// FAT helpers (cluster allocation table)
- (uint16_t)_fatEntry:(NSUInteger)cluster {
    NSUInteger tableBlock = self.fatStartBlock + (cluster / EMU3_CLUSTER_ENTRIES_PER_BLOCK);
    NSUInteger entryOffset = (cluster % EMU3_CLUSTER_ENTRIES_PER_BLOCK) * 2;
    const uint8_t *p = [self _blockPtr:tableBlock];
    if (!p) return 0;
    return CFSwapInt16LittleToHost(*(const uint16_t *)(p + entryOffset));
}

- (void)_setFatEntry:(NSUInteger)cluster value:(uint16_t)value {
    NSUInteger tableBlock = self.fatStartBlock + (cluster / EMU3_CLUSTER_ENTRIES_PER_BLOCK);
    NSUInteger entryOffset = (cluster % EMU3_CLUSTER_ENTRIES_PER_BLOCK) * 2;
    uint8_t *p = [self _mutableBlockPtr:tableBlock];
    if (!p) return;
    *(uint16_t *)(p + entryOffset) = CFSwapInt16HostToLittle(value);   // no per-entry msync: flushed by the kernel / on close
}

- (NSUInteger)_lastCluster {
    NSUInteger byTable = self.fatBlockCount * EMU3_CLUSTER_ENTRIES_PER_BLOCK;
    NSUInteger last = self.maxClusterIndex;
    if (byTable > 0 && byTable - 1 < last) last = byTable - 1;
    if (self.usableClusterLimit > 0 && self.usableClusterLimit < last) last = self.usableClusterLimit;
    return last;
}

- (void)_recountFat {
    NSUInteger last = [self _lastCluster], used = 0;
    for (NSUInteger c = 1; c <= last; c++) if ([self _fatEntry:c] != EMU3_FREE_CLUSTER) used++;
    self.totalClusters = last;
    self.usedBlocks    = used * self.clusterBlocks;
    self.freeBlocks    = (last - used) * self.clusterBlocks;
}

- (NSUInteger)_firstBlockOfCluster:(NSUInteger)c {
    return self.dataAreaBlock + (c - 1) * self.clusterBlocks;
}

// Follow the allocation table from a file's first cluster.
- (NSArray<NSNumber *> *)_chainFromCluster:(NSUInteger)start {
    NSMutableArray *chain = [NSMutableArray array];
    NSUInteger last = [self _lastCluster], c = start;
    while (c >= 1 && c <= last && chain.count <= last) {
        [chain addObject:@(c)];
        uint16_t next = [self _fatEntry:c];
        if (next == 0x7FFF || next == EMU3_FREE_CLUSTER || next == EMU3_USED_CLUSTER) break;
        c = next;
    }
    return chain;
}

// ──────────────────────────────────────────────────────────────────────────────
// Filesystem parsing
// ──────────────────────────────────────────────────────────────────────────────

- (BOOL)_parseFilesystemWithError:(NSError **)error {
    if (_imageSize < EMU3_BLOCK_SIZE) {
        if (error) *error = [self _errorCode:EMU3ErrorNotEMU3Image
                                     message:@"File too small to be an E-MU disk image"];
        return NO;
    }

    if (memcmp(_imageBytes, "EMU3", 4) != 0) {
        if (error) *error = [self _errorCode:EMU3ErrorNotEMU3Image
                                     message:@"Not an E-MU 3/4 disk image (missing \"EMU3\" signature)"];
        return NO;
    }

    // Superblock fields are uint32 LE, starting at offset 4 (index 0 in fields[])
    // EMU3_SB_ROOT_DIR_BLOCK = index 2 → byte offset 0x08
    // EMU3_SB_DATA_AREA_BLOCK = index 8 → byte offset 0x20
    // EMU3_SB_FAT_START_BLOCK = index 10 → byte offset 0x28
    // EMU3_SB_SLOT_SIZE_KB    = index 11 → byte offset 0x2C
    const uint32_t *fields = (const uint32_t *)(_imageBytes + 4); // fields[0] = offset 0x04

    self.rootDirBlock   = CFSwapInt32LittleToHost(fields[EMU3_SB_ROOT_DIR_BLOCK - 1]);  // idx 1 = offset 0x08
    self.dataAreaBlock  = CFSwapInt32LittleToHost(fields[EMU3_SB_DATA_AREA_BLOCK - 1]); // idx 7 = offset 0x20
    self.fatStartBlock  = CFSwapInt32LittleToHost(fields[5]);   // dword 5 = offset 0x18 (verified on real disks)
    self.fatBlockCount  = CFSwapInt32LittleToHost(fields[6]);
    self.maxClusterIndex = CFSwapInt32LittleToHost(fields[8]);
    // Real EOS disks: root directory = blocks [root, root+count); folders live in the pool
    // [poolStart, poolStart+poolCount) which ends right before the data area.
    self.rootDirBlockCount = CFSwapInt32LittleToHost(fields[2]);
    self.dirPoolStart      = CFSwapInt32LittleToHost(fields[3]);
    self.dirPoolCount      = CFSwapInt32LittleToHost(fields[4]);
    NSUInteger headerLast = CFSwapInt32LittleToHost(fields[0]);   // last block number
    self.totalBlocks    = _imageSize / EMU3_BLOCK_SIZE;

    // Volume label: not stored in superblock — use filename
    NSString *imgName = self.imageURL.lastPathComponent;
    self.volumeLabel = imgName.length > 0 ? imgName : @"EMU3 Volume";

    // Cluster size: the header says it (field 9, low byte = log2(cluster / 32 kB): 64 MB disk 1, 1 GB disk 5, 14 GB disk 8).
    // Cross-checked against data area / cluster count (a within-2x match is required, otherwise a header written by an
    // older version of this app is assumed and the cluster size is derived from the geometry, rounded to the nearest power of two).
    {
        NSUInteger total = headerLast + 1;
        // NOT limited to the file size: CD images (.iso) are truncated copies of a larger disk,
        // but the geometry (and so the cluster size) comes from the header.
        NSUInteger avail = total > self.dataAreaBlock ? total - self.dataAreaBlock : 0;
        double per = self.maxClusterIndex > 0 ? (double)avail / self.maxClusterIndex : 0;
        NSUInteger cb = 0;
        uint32_t f9 = CFSwapInt32LittleToHost(fields[9]);
        NSUInteger shift = f9 & 0xFF;
        if (shift >= 1 && shift <= 14) {
            NSUInteger hb = (NSUInteger)64 << shift;
            if (per < 1 || (hb * 2 >= per && hb <= per * 2)) cb = hb;
        }
        if (cb == 0) {
            cb = per >= 1 ? (NSUInteger)pow(2.0, round(log2(per))) : 2048;
            if (cb < 1) cb = 1;
        }
        self.clusterBlocks = cb;
        // Clusters that would stick out past the end of the disk cannot be used (the 14 GB sampler format declares
        // 1791 clusters of 8 MB = 14.7 GB on a 14.0 GB disk).
        self.usableClusterLimit = avail / cb;
    }
    [self _recountFat];

    // Safety defaults
    if (self.rootDirBlock == 0)    self.rootDirBlock   = 6;
    if (self.dataAreaBlock == 0)   self.dataAreaBlock  = 175;
    if (self.fatStartBlock == 0)   self.fatStartBlock  = 2;
    // Sanity-check the directory layout; fall back to "everything between root and data".
    if (self.rootDirBlockCount == 0 || self.rootDirBlockCount > 64 ||
        self.dirPoolStart < self.rootDirBlock + self.rootDirBlockCount ||
        self.dirPoolStart + self.dirPoolCount > self.dataAreaBlock || self.dirPoolCount == 0) {
        self.rootDirBlockCount = 1;
        self.dirPoolStart = self.rootDirBlock + 1;
        self.dirPoolCount = self.dataAreaBlock > self.dirPoolStart ? self.dataAreaBlock - self.dirPoolStart : 0;
    }

    // Parse root directory
    EMU3Directory *root = [[EMU3Directory alloc] init];
    root.name    = self.volumeLabel;
    root.entryId = EMU3_I_ID_ROOT_DIR;
    for (NSUInteger i = 0; i < self.rootDirBlockCount; i++)
        [root.blockList addObject:@(self.rootDirBlock + i)];
    [self _parseDirectory:root];
    self.rootDirectory = root;
    return YES;
}

- (void)_parseDirectory:(EMU3Directory *)dir {
    for (NSNumber *blockNum in dir.blockList) {
        NSUInteger blockIdx = blockNum.unsignedIntegerValue;
        const uint8_t *blockData = [self _blockPtr:blockIdx];
        if (!blockData) continue;

        for (int i = 0; i < EMU3_ENTRIES_PER_BLOCK; i++) {
            const emu3_dentry_t *de = (const emu3_dentry_t *)(blockData + i * EMU3_DENTRY_SIZE);

            // Skip empty entries (null name)
            if (de->name[0] == 0) continue;

            NSString *name = [self _parseName:de->name];
            if (!name || name.length == 0) continue;

            // Primary indicator: the type byte (data[10]) distinguishes files from dirs.
            // Files always have type 0x80 / 0x81 / 0x83.  For a directory entry
            // that byte is block_list[4] (a block number, never a file-type code).
            // Secondary check: E4B0 props signature present → EIV bank file.
            uint8_t typeByte = de->data.fattrs.type;
            BOOL hasFileType = (typeByte == EMU3_FILE_TYPE_STANDARD ||
                                typeByte == EMU3_FILE_TYPE_SYSTEM    ||
                                typeByte == EMU3_FILE_TYPE_UPDATED);
            BOOL hasE4B0     = (de->data.fattrs.props[1] == 'E' &&
                                de->data.fattrs.props[2] == '4' &&
                                de->data.fattrs.props[3] == 'B' &&
                                de->data.fattrs.props[4] == '0');
            BOOL isFile = hasFileType || hasE4B0;
            uint8_t idByte = de->data.id;
            BOOL isDir  = !isFile && (idByte == EMU3_ID_DIR_TYPE_A || idByte == EMU3_ID_DIR_TYPE_B);

            if (isDir) {
                EMU3Directory *subdir = [[EMU3Directory alloc] init];
                subdir.name         = name;
                subdir.entryId      = idByte;
                subdir.parent       = dir;
                subdir.dentryBlock  = (NSInteger)blockIdx;
                subdir.dentryOffset = i;
                // block_list[7] follows unknown+id in the dentry data
                const emu3_dir_attrs_t *da = &de->data.dattrs;
                for (int b = 0; b < EMU3_BLOCKS_PER_DIR; b++) {
                    int16_t blk = (int16_t)CFSwapInt16LittleToHost(
                                    *(const uint16_t *)&da->block_list[b]);
                    if (blk > 0) [subdir.blockList addObject:@(blk)];
                }
                [self _parseDirectory:subdir];
                [dir.subdirectories addObject:subdir];
            } else {
                EMU3File *file       = [[EMU3File alloc] init];
                file.name            = name;
                file.entryId         = idByte;  // sequential entry ID within dir block
                file.dentryBlock     = (NSInteger)blockIdx;
                file.dentryOffset    = i;
                const emu3_file_attrs_t *fa = &de->data.fattrs;

                // fa->start_cluster = file_index (1-based slot number)
                // fa->clusters      = 1 (always; number of disk extents)
                // fa->blocks        = blocks_used (number of 512-byte blocks occupied)
                // fa->bytes         = partial-block byte count
                file.startCluster        = CFSwapInt16LittleToHost(fa->start_cluster);  // slot index
                file.clusterCount        = CFSwapInt16LittleToHost(fa->clusters);
                file.blocksInLastCluster = CFSwapInt16LittleToHost(fa->blocks);         // blocks_used
                file.bytesInLastBlock    = CFSwapInt16LittleToHost(fa->bytes);
                file.rawType             = fa->type;

                // File size: (blocks_used - 1) full blocks + bytes in last block
                if (file.blocksInLastCluster > 0) {
                    NSUInteger nCl = file.clusterCount > 0 ? file.clusterCount : 1;
                    NSUInteger totalBlk = (nCl - 1) * self.clusterBlocks + file.blocksInLastCluster;
                    file.fileSize = (totalBlk - 1) * EMU3_BLOCK_SIZE + file.bytesInLastBlock;
                } else {
                    file.fileSize = 0;
                }

                switch (fa->type) {
                    case EMU3_FILE_TYPE_SYSTEM:  file.fileType = EMU3FileTypeSystem; break;
                    case EMU3_FILE_TYPE_STANDARD:
                    case EMU3_FILE_TYPE_UPDATED: file.fileType = EMU3FileTypeBank;   break;
                    default:                     file.fileType = EMU3FileTypeUnknown; break;
                }

                [dir.files addObject:file];

                // Eagerly populate bank metadata so sample counts appear in table immediately
                // (without requiring user to expand the bank to see samples first)
                if (file.fileType == EMU3FileTypeBank) {
                    // Populate asynchronously to avoid blocking directory load
                    __weak typeof(self) weakSelf = self;
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        typeof(self) strongSelf = weakSelf;
                        if (!strongSelf) return;

                        [strongSelf populateBankMetadata:file error:nil];

                        // After metadata is populated, notify delegates to refresh table
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[NSNotificationCenter defaultCenter]
                                postNotificationName:@"EMU3BankMetadataUpdated"
                                object:file];
                        });
                    });
                }
            }
        }
    }
}

- (NSString *)_parseName:(const char *)raw {
    // Name is 16 bytes, may or may not be null-terminated, space-padded
    char buf[17] = {0};
    memcpy(buf, raw, EMU3_FILENAME_LEN);
    for (int i = EMU3_FILENAME_LEN - 1; i >= 0; i--) {
        if (buf[i] == ' ' || buf[i] == 0) buf[i] = 0;
        else break;
    }
    return buf[0] ? @(buf) : nil;
}

// ──────────────────────────────────────────────────────────────────────────────
// File data access
// ──────────────────────────────────────────────────────────────────────────────

- (NSData *)dataForFile:(EMU3File *)file error:(NSError **)error {
    // Thread-safe check: if already cached, return immediately
    @synchronized(file) {
        if (file.cachedData) return file.cachedData;
    }

    // A file is a chain of clusters; the last one is only partly used.
    NSArray<NSNumber *> *chain = [self _chainFromCluster:file.startCluster];
    NSUInteger lastBlocks = MIN((NSUInteger)file.blocksInLastCluster, self.clusterBlocks);
    if (chain.count == 0 || lastBlocks == 0) {
        @synchronized(file) { file.cachedData = [NSData data]; }
        return [NSData data];
    }
    NSMutableData *data = [NSMutableData dataWithCapacity:((chain.count - 1) * self.clusterBlocks + lastBlocks) * EMU3_BLOCK_SIZE];
    for (NSUInteger i = 0; i < chain.count; i++) {
        NSUInteger n = (i + 1 == chain.count) ? lastBlocks : self.clusterBlocks;
        NSUInteger sb = [self _firstBlockOfCluster:chain[i].unsignedIntegerValue];
        const uint8_t *first = [self _blockPtr:sb];
        const uint8_t *lastp = [self _blockPtr:sb + n - 1];
        if (first && lastp && lastp == first + (n - 1) * EMU3_BLOCK_SIZE) {
            [data appendBytes:first length:n * EMU3_BLOCK_SIZE];
        } else {
            for (NSUInteger b = 0; b < n; b++) {
                const uint8_t *q = [self _blockPtr:sb + b];
                if (!q) break;
                [data appendBytes:q length:EMU3_BLOCK_SIZE];
            }
        }
    }

    // Trim to exact file size
    if (file.fileSize > 0 && data.length > file.fileSize)
        [data setLength:file.fileSize];

    // Not cached: keeping every bank read so far in memory made big copies grow to many GB.
    // (cachedData is only used for banks that exist outside the image, see importFileAtURL.)
    return data;
}

// Debug logging for the bank parser is compiled out: it ran for every bank on every refresh.
#define EMU3DebugLog(...) do { } while (0)

- (BOOL)populateBankMetadata:(EMU3File *)file error:(NSError **)error {
    if (file.fileType != EMU3FileTypeBank) return YES;
    if (file.metadataParsed) return YES;          // parse each bank once, not on every refresh
    __block BOOL ok = NO;
    NSError *inner = nil;
    @autoreleasepool { ok = [self _parseBankMetadata:file error:&inner]; }
    if (!ok && error) *error = inner;
    if (ok) file.metadataParsed = YES;
    return ok;
}

- (BOOL)_parseBankMetadata:(EMU3File *)file error:(NSError **)error {
    if (file.fileType != EMU3FileTypeBank) return YES;

    NSData *data = [self dataForFile:file error:error];
    if (!data || data.length < 12) {
        if (file.sampleCount == 0) EMU3DebugLog(@"[Metadata] %@ → Data too short or missing (%lu bytes)", file.name, (unsigned long)data.length);
        return NO;
    }

    const uint8_t *bytes = data.bytes;
    BOOL isDebugBank = NO;  // Enable detailed logging for ALL banks to diagnose sample detection

    // Log the first 64 bytes to understand the actual format
    NSMutableString *hexDump = [NSMutableString string];
    NSMutableString *asciiDump = [NSMutableString string];
    for (int i = 0; i < MIN(64, (int)data.length); i++) {
        [hexDump appendFormat:@"%02x ", bytes[i]];
        unsigned char c = bytes[i];
        [asciiDump appendFormat:@"%c", (c >= 32 && c < 127) ? c : '.'];
    }
    EMU3DebugLog(@"[Metadata] %@ → File size: %lu bytes", file.name, (unsigned long)data.length);
    EMU3DebugLog(@"[Metadata] %@ → First 64 bytes hex: %@", file.name, hexDump);
    EMU3DebugLog(@"[Metadata] %@ → First 64 bytes ascii: %@", file.name, asciiDump);

    // Note: Don't set sampleCount based on samplesFromBankFile here
    // because samplesFromBankFile returns sample chunk IDs for export,
    // not the total sample count. The E4B/E3B parsing below will handle
    // accurate sample counting.

    // ── E4B/IFF format (EIV / Emulator IV) ──────────────────────────────────
    // Structure: "FORM" + BE-size(4) + "E4B*" + "TOC1" + BE-size(4) + entries…
    // E4B0, E4B1, E4B (with space), E3B, etc. are all valid variants
    // TOC1 entry (32 bytes): [4 type][4 BE-size][4 BE-offset][2 unk][16 name][2 unk]
    if (memcmp(bytes, "FORM", 4) == 0 && data.length >= 12) {
        char formType[5] = {0};
        memcpy(formType, bytes + 8, 4);

        // Check for E4B* or E3B* variants (E4B0, E4B1, E4B , E3B0, etc.)
        BOOL isEMUBankFormat = (memcmp(bytes + 8, "E4B", 3) == 0) ||
                               (memcmp(bytes + 8, "E3B", 3) == 0);

        if (isEMUBankFormat) {
            if (isDebugBank) EMU3DebugLog(@"[Format] %@ → Detected as E4B/E3B variant (IFF format): %.4s", file.name, formType);

            file.bankFormat = EMU3BankFormatEmulatorIV;  // Default to IV, can be E3 too

            {
                NSUInteger formEnd = MIN(data.length, 8 + (NSUInteger)be32(bytes + 4));
                if (formEnd <= 12) formEnd = data.length;

                NSInteger presets = 0, samples = 0;
                NSInteger topLevelChunks = 0;
                NSString *bankName = nil;

                for (NSUInteger off = 12; off + 8 <= formEnd; ) {
                    const uint8_t *chunk = bytes + off;
                    uint32_t chunkSize = be32(chunk + 4);
                    if (chunkSize > formEnd - off - 8) break;

                    topLevelChunks++;
                    char chunkId[5] = {0};
                    memcpy(chunkId, chunk, 4);

                    if (isDebugBank) {
                        EMU3DebugLog(@"[E4B0] %@ top-level chunk %ld: '%.4s' size=%u bytes",
                              file.name, (long)topLevelChunks, chunkId, chunkSize);
                    }

                    if (emu3_chunk_is_preset(chunk)) {
                        presets++;
                        if (!bankName && chunkSize >= 18) {
                            char nameBuf[17] = {0};
                            memcpy(nameBuf, chunk + 10, 16);
                            for (int i = 15; i >= 0 && (nameBuf[i] == ' ' || nameBuf[i] == 0); i--) nameBuf[i] = 0;
                            if (nameBuf[0]) bankName = @(nameBuf);
                        }
                    } else if (emu3_chunk_is_sample(chunk)) {
                        samples++;
                    }

                    NSUInteger paddedSize = chunkSize + (chunkSize & 1);
                    off += 8 + paddedSize;
                }

                if (topLevelChunks > 0) {
                    file.presetCount = presets;
                    file.sampleCount = samples;
                    file.bankName = bankName ?: file.name;
                    if (isDebugBank) EMU3DebugLog(@"[E4B0] %@ → FINAL Presets: %ld, Samples: %ld (from top-level chunks)",
                                           file.name, (long)presets, (long)samples);
                    return YES;
                }
            }

        // TOC1 starts at byte 12 ("TOC1" + 4-byte BE size + entries)
        if (data.length < 20) { file.bankName = file.name; return YES; }
        uint32_t toc1Size = CFSwapInt32BigToHost(*(const uint32_t *)(bytes + 16));
        NSUInteger toc1End = MIN(20 + toc1Size, data.length);

        if (isDebugBank) EMU3DebugLog(@"[E4B0] %@ → TOC1 size: %u, range: 20-%lu (data length: %lu)",
                               file.name, toc1Size, (unsigned long)toc1End, (unsigned long)data.length);

        NSInteger presets = 0, samples = 0;
        NSString *bankName = nil;
        NSInteger entryCount = 0;

        // Each TOC1 entry is 32 bytes
        for (NSUInteger off = 20; off + 32 <= toc1End; off += 32) {
            const uint8_t *e = bytes + off;
            char chunkId[5] = {0};
            memcpy(chunkId, e, 4);
            entryCount++;

            // Skip null/deleted entries (all zeros)
            BOOL isNullEntry = (e[0] == 0 && e[1] == 0 && e[2] == 0 && e[3] == 0);

            // Log ALL chunk types for Acid bank (unrecognized ones too)
            if (isDebugBank) {
                // Get size field from TOC1 entry (bytes [4:8], big-endian)
                __unused uint32_t chunkSize = CFSwapInt32BigToHost(*(const uint32_t *)(e + 4));

                if (isNullEntry) {
                    EMU3DebugLog(@"[E4B0] %@ entry %ld: [NULL/DELETED] (hex: %02x %02x %02x %02x) size=%u",
                          file.name, (long)entryCount, e[0], e[1], e[2], e[3], chunkSize);
                } else {
                    // Try to print as ASCII if possible, otherwise as hex
                    BOOL allPrintable = YES;
                    for (int i = 0; i < 4; i++) {
                        if (e[i] < 32 || e[i] > 126) allPrintable = NO;
                    }
                    if (allPrintable) {
                        EMU3DebugLog(@"[E4B0] %@ entry %ld: '%.4s' (hex: %02x %02x %02x %02x) size=%u bytes",
                              file.name, (long)entryCount, chunkId, e[0], e[1], e[2], e[3], chunkSize);
                    } else {
                        EMU3DebugLog(@"[E4B0] %@ entry %ld: '%c%c%c%c' (hex: %02x %02x %02x %02x) size=%u bytes [binary]",
                              file.name, (long)entryCount,
                              (e[0] >= 32 && e[0] <= 126) ? e[0] : '?',
                              (e[1] >= 32 && e[1] <= 126) ? e[1] : '?',
                              (e[2] >= 32 && e[2] <= 126) ? e[2] : '?',
                              (e[3] >= 32 && e[3] <= 126) ? e[3] : '?',
                              e[0], e[1], e[2], e[3], chunkSize);
                    }
                }
            }

            // Skip null entries
            if (isNullEntry) continue;

            if (memcmp(e, "E4P1", 4) == 0 ||
                memcmp(e, "E3P1", 4) == 0) {  // Also count E3 presets
                presets++;
                if (!bankName) {
                    // Name field: bytes [14:30] of the entry
                    char nameBuf[17] = {0};
                    memcpy(nameBuf, e + 14, 16);
                    for (int i = 15; i >= 0 && (nameBuf[i] == ' ' || nameBuf[i] == 0); i--) nameBuf[i] = 0;
                    if (nameBuf[0]) bankName = @(nameBuf);
                }
                if (isDebugBank) EMU3DebugLog(@"[E4B0] %@ ✓ Preset found: %.4s", file.name, chunkId);
            } else if (emu3_chunk_is_sample(e) ||
                       memcmp(e, "E3S", 3) == 0 ||
                       memcmp(e, "E4S", 3) == 0 ||
                       memcmp(e, "E4s", 3) == 0) {
                samples++;
                if (isDebugBank) EMU3DebugLog(@"[E4B0] %@ ✓ Sample found: %.4s", file.name, chunkId);
            } else {
                // Instruments (E3I, E4I), containers (RIFF, FORM), and unknown chunks
                if (isDebugBank) {
                    EMU3DebugLog(@"[E4B0] %@ - Other chunk (not counted as sample): %c%c%c%c",
                          file.name,
                          (e[0] >= 32 && e[0] <= 126) ? e[0] : '.',
                          (e[1] >= 32 && e[1] <= 126) ? e[1] : '.',
                          (e[2] >= 32 && e[2] <= 126) ? e[2] : '.',
                          (e[3] >= 32 && e[3] <= 126) ? e[3] : '.');
                }
            }
        }

        if (isDebugBank) EMU3DebugLog(@"[E4B0] %@ → TOC1 complete: %ld entries scanned, %ld presets, %ld samples",
                               file.name, (long)entryCount, (long)presets, (long)samples);

        // Use the detected sample count from chunk type analysis
        if (entryCount > 0 || samples > 0) {
            file.presetCount = presets;
            file.sampleCount = samples;  // Use the count from actual sample chunk detection
            file.bankName = bankName ?: file.name;
            if (isDebugBank) EMU3DebugLog(@"[E4B0] %@ → FINAL Presets: %ld, Samples: %ld (from chunk type detection)", file.name, (long)presets, (long)samples);
            return YES;
        }

        // If TOC1 was empty but this is an E4B file, still return success
        file.bankName = bankName ?: file.name;
        if (isDebugBank) EMU3DebugLog(@"[E4B0] %@ → FINAL Empty TOC1 (presets: %ld, samples: %ld)", file.name, (long)presets, (long)samples);
        return YES;
        } else if (isDebugBank) {
            EMU3DebugLog(@"[Format] %@ → Not an E4B/E3B format. Signature: %.4s", file.name, formType);
        }
    }

    // ── Legacy EIII / 3X / ESI-32 format ────────────────────────────────────
    // ONLY try legacy format if data starts with recognizable ASCII format string
    // This prevents garbage data from being misinterpreted as metadata
    BOOL looksLikeLegacyFormat = NO;

    if (data.length >= 16) {
        // Check if first bytes look like ASCII text (format string should be printable)
        const char *firstBytes = (const char *)bytes;
        BOOL allPrintable = YES;
        for (int i = 0; i < 15 && firstBytes[i] != 0; i++) {
            unsigned char c = (unsigned char)firstBytes[i];
            if (c < 32 || c > 126) {
                allPrintable = NO;
                break;
            }
        }

        if (allPrintable) {
            looksLikeLegacyFormat = YES;
            if (isDebugBank) EMU3DebugLog(@"[Legacy] %@ → Looks like legacy format (printable ASCII start)", file.name);
        } else {
            if (isDebugBank) EMU3DebugLog(@"[Legacy] %@ → NOT legacy format (non-ASCII bytes at start)", file.name);
            return YES;  // Don't try to parse as legacy if it doesn't look like legacy
        }
    }

    if (data.length < sizeof(emu3_bank_header_t)) {
        if (isDebugBank) EMU3DebugLog(@"[Legacy] %@ → Header too short (%lu bytes)", file.name, (unsigned long)data.length);
        return YES;
    }
    const emu3_bank_header_t *hdr = (const emu3_bank_header_t *)bytes;

    if (isDebugBank) EMU3DebugLog(@"[Legacy] %@ → Format string: '%.16s'", file.name, hdr->format);

    // Parse based on emu3bm format specifications
    // EIII: Presets at 0x6C (100 max), Samples at 0x204 (99 max)
    // 3X/ESI: Presets at 0x17CA (256 max), Samples at 0x1BD2 (999 max)

    NSInteger presetCount = 0, sampleCount = 0;

    // Check for EMULATOR THREE format
    if (memcmp(hdr->format, "EMULATOR THREE ", 16) == 0) {
        file.bankFormat = EMU3BankFormatEmulatorThree;
        if (isDebugBank) EMU3DebugLog(@"[EIII] %@ → Detected EMULATOR THREE, reading addresses", file.name);

        // Read preset address table at offset 0x6C (100 max)
        if (data.length >= 0x6C + 100 * 4) {
            const uint32_t *presetAddrs = (const uint32_t *)(bytes + 0x6C);
            for (NSInteger i = 0; i < 100; i++) {
                uint32_t addr = CFSwapInt32LittleToHost(presetAddrs[i]);
                uint32_t nextAddr = (i + 1 < 100) ? CFSwapInt32LittleToHost(presetAddrs[i + 1]) : 0;
                if (addr != nextAddr && addr != 0) {
                    presetCount++;
                } else {
                    break;
                }
            }
        }

        // Read sample address table at offset 0x204 (99 max)
        if (data.length >= 0x204 + 99 * 4) {
            const uint32_t *sampleAddrs = (const uint32_t *)(bytes + 0x204);
            for (NSInteger i = 0; i < 99; i++) {
                uint32_t addr = CFSwapInt32LittleToHost(sampleAddrs[i]);
                if (addr != 0) {
                    sampleCount++;
                } else {
                    break;
                }
            }
        }

        if (isDebugBank) EMU3DebugLog(@"[EIII] %@ → Presets: %ld, Samples: %ld", file.name, (long)presetCount, (long)sampleCount);

    }
    // Check for EMULATOR 3X or ESI-32 v3 format
    else if (memcmp(hdr->format, "EMULATOR 3X    ", 16) == 0 || memcmp(hdr->format, "EMU SI-32 v3   ", 16) == 0) {
        file.bankFormat = EMU3BankFormatEmulator3X;
        if (isDebugBank) EMU3DebugLog(@"[3X] %@ → Detected EMULATOR 3X/ESI-32 v3, reading addresses", file.name);

        // Read preset address table at offset 0x17CA (256 max)
        if (data.length >= 0x17CA + 256 * 4) {
            const uint32_t *presetAddrs = (const uint32_t *)(bytes + 0x17CA);
            for (NSInteger i = 0; i < 256; i++) {
                uint32_t addr = CFSwapInt32LittleToHost(presetAddrs[i]);
                uint32_t nextAddr = (i + 1 < 256) ? CFSwapInt32LittleToHost(presetAddrs[i + 1]) : 0;
                if (addr != nextAddr && addr != 0) {
                    presetCount++;
                } else {
                    break;
                }
            }
        }

        // Read sample address table at offset 0x1BD2 (999 max)
        if (data.length >= 0x1BD2 + 999 * 4) {
            const uint32_t *sampleAddrs = (const uint32_t *)(bytes + 0x1BD2);
            for (NSInteger i = 0; i < 999; i++) {
                uint32_t addr = CFSwapInt32LittleToHost(sampleAddrs[i]);
                if (addr != 0) {
                    sampleCount++;
                } else {
                    break;
                }
            }
        }

        if (isDebugBank) EMU3DebugLog(@"[3X] %@ → Presets: %ld, Samples: %ld", file.name, (long)presetCount, (long)sampleCount);

    }
    // Unknown format - log diagnostic info
    else {
        if (isDebugBank) {
            EMU3DebugLog(@"[Unknown] %@ → Format not recognized as EIII, 3X, or E4B", file.name);
            EMU3DebugLog(@"[Unknown] %@ → Expected EIII to start with 'EMULATOR THREE ' (bytes: 45 4d 55 4c 41 54 4f 52 20 54 48 52 45 45 20)", file.name);
            EMU3DebugLog(@"[Unknown] %@ → Expected 3X to start with 'EMULATOR 3X    ' (bytes: 45 4d 55 4c 41 54 4f 52 20 33 58 20...)", file.name);
            EMU3DebugLog(@"[Unknown] %@ → Expected E4B to start with 'FORM' (bytes: 46 4f 52 4d)", file.name);
            EMU3DebugLog(@"[Unknown] %@ → But got: %02x %02x %02x %02x %02x %02x %02x %02x", file.name,
                  bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7]);
        }
        return YES;
    }

    // Set the counts from address table parsing
    file.presetCount = presetCount;
    file.sampleCount = sampleCount;

    // Extract bank name if available
    if (data.length >= sizeof(emu3_bank_header_t)) {
        char nameBuf[17] = {0};
        memcpy(nameBuf, hdr->name, 16);
        for (int i = 15; i >= 0 && (nameBuf[i] == ' ' || nameBuf[i] == 0); i--) nameBuf[i] = 0;
        file.bankName = nameBuf[0] ? @(nameBuf) : file.name;
    }

    if (isDebugBank) EMU3DebugLog(@"[Legacy] %@ → FINAL: Presets: %ld, Samples: %ld, Format: %ld",
                           file.name, (long)file.presetCount, (long)file.sampleCount, (long)file.bankFormat);
    return YES;
}

// ──────────────────────────────────────────────────────────────────────────────
// Slot allocation (the EIV filesystem uses fixed-size file slots, not chains)
// ──────────────────────────────────────────────────────────────────────────────

- (void)_freeChainFromCluster:(NSUInteger)start {
    for (NSNumber *c in [self _chainFromCluster:start]) [self _setFatEntry:c.unsignedIntegerValue value:EMU3_FREE_CLUSTER];
    [self _recountFat];
}

// Reserve `count` free clusters, linked into a chain (0x7FFF terminates). nil if not enough.
- (NSArray<NSNumber *> *)_allocateChainOfLength:(NSUInteger)count {
    NSMutableArray<NSNumber *> *found = [NSMutableArray arrayWithCapacity:count];
    NSUInteger last = [self _lastCluster];
    for (NSUInteger c = 1; c <= last && found.count < count; c++)
        if ([self _fatEntry:c] == EMU3_FREE_CLUSTER) [found addObject:@(c)];
    if (found.count < count) return nil;
    for (NSUInteger i = 0; i < count; i++) {
        uint16_t next = (i + 1 < count) ? (uint16_t)found[i + 1].unsignedIntegerValue : 0x7FFF;
        [self _setFatEntry:found[i].unsignedIntegerValue value:next];
    }
    [self _recountFat];
    return found;
}

// ──────────────────────────────────────────────────────────────────────────────
// Write data to a file slot (contiguous blocks starting at startBlock)
// ──────────────────────────────────────────────────────────────────────────────

// Bank data is written with pwrite() (not through the memory map) and without the file cache:
// writing GBs through the map left many GB of dirty pages in RAM and stalled the whole Mac
// when the image sits on an SD card.
- (BOOL)_writeData:(NSData *)data toChain:(NSArray<NSNumber *> *)chain {
    if (_fd < 0 || self.isReadOnly) return NO;
    const uint8_t *src = data.bytes;
    NSUInteger remaining = data.length;
    uint8_t tail[EMU3_BLOCK_SIZE];
    for (NSNumber *cn in chain) {
        if (remaining == 0) break;
        NSUInteger first = [self _firstBlockOfCluster:cn.unsignedIntegerValue];
        NSUInteger clusterBytes = self.clusterBlocks * EMU3_BLOCK_SIZE;
        NSUInteger n = MIN(remaining, clusterBytes);
        NSUInteger full = n / EMU3_BLOCK_SIZE * EMU3_BLOCK_SIZE;
        off_t off = (off_t)first * EMU3_BLOCK_SIZE;
        NSUInteger done = 0;
        while (done < full) {
            ssize_t w = pwrite(_fd, src + done, MIN(full - done, (NSUInteger)(4 * 1024 * 1024)), off + done);
            if (w <= 0) return NO;
            done += (NSUInteger)w;
        }
        if (n > full) {   // last partial block, zero padded
            memset(tail, 0, sizeof tail);
            memcpy(tail, src + full, n - full);
            if (pwrite(_fd, tail, EMU3_BLOCK_SIZE, off + full) != EMU3_BLOCK_SIZE) return NO;
        }
        src += n;
        remaining -= n;
    }
    return remaining == 0;
}

// ──────────────────────────────────────────────────────────────────────────────
// Directory entry helpers
// ──────────────────────────────────────────────────────────────────────────────

// Write a dentry at the given block/offset
- (void)_writeDentry:(emu3_dentry_t *)de blockIdx:(NSUInteger)blockIdx offset:(NSInteger)offset {
    uint8_t *blockData = [self _mutableBlockPtr:blockIdx];
    if (!blockData) return;
    memcpy(blockData + offset * EMU3_DENTRY_SIZE, de, EMU3_DENTRY_SIZE);
    msync(blockData, EMU3_BLOCK_SIZE, MS_ASYNC);
}

// Find a free dentry slot in a directory (returns YES and sets block/offset)
- (BOOL)_findFreeDentry:(EMU3Directory *)dir
              outBlock:(NSUInteger *)outBlock
             outOffset:(NSInteger *)outOffset {
    for (NSNumber *blockNum in dir.blockList) {
        NSUInteger blockIdx = blockNum.unsignedIntegerValue;
        const uint8_t *blockData = [self _blockPtr:blockIdx];
        if (!blockData) continue;
        for (int i = 0; i < EMU3_ENTRIES_PER_BLOCK; i++) {
            const emu3_dentry_t *de = (const emu3_dentry_t *)(blockData + i * EMU3_DENTRY_SIZE);
            if (de->name[0] == 0 || de->data.fattrs.type == EMU3_FILE_TYPE_DELETED) {
                *outBlock  = blockIdx;
                *outOffset = i;
                return YES;
            }
        }
    }

    // Directory is full: a sub-directory may own up to EMU3_BLOCKS_PER_DIR blocks (16 entries
    // each). Grow it by one block and record the block in the directory's own dentry.
    if (!self.isReadOnly && dir.parent && dir.dentryBlock >= 0 && dir.dentryOffset >= 0 &&
        dir.blockList.count < EMU3_BLOCKS_PER_DIR) {
        NSUInteger newBlock = [self _findFreeDirectoryBlock];
        uint8_t *bp = newBlock ? [self _mutableBlockPtr:newBlock] : NULL;
        uint8_t *pb = [self _mutableBlockPtr:(NSUInteger)dir.dentryBlock];
        if (bp && pb) {
            emu3_dentry_t *own = (emu3_dentry_t *)(pb + dir.dentryOffset * EMU3_DENTRY_SIZE);
            NSUInteger slot = dir.blockList.count;
            memset(bp, 0, EMU3_BLOCK_SIZE);
            for (NSUInteger k = slot + 1; k < EMU3_BLOCKS_PER_DIR; k++) own->data.dattrs.block_list[k] = (int16_t)-1;
            own->data.dattrs.block_list[slot] = (int16_t)CFSwapInt16HostToLittle((uint16_t)newBlock);
            msync(bp, EMU3_BLOCK_SIZE, MS_ASYNC);
            msync(pb, EMU3_BLOCK_SIZE, MS_ASYNC);
            [dir.blockList addObject:@(newBlock)];
            *outBlock  = newBlock;
            *outOffset = 0;
            return YES;
        }
    }
    return NO;
}

// Build a dentry for a file with the given slot index and data
- (emu3_dentry_t)_dentryForFile:(EMU3File *)file
                      fileIndex:(uint16_t)fileIndex
                       fileData:(NSData *)data
                       clusters:(NSUInteger)clusters
                      entryId:(uint8_t)entryId {
    emu3_dentry_t de;
    memset(&de, 0, sizeof(de));

    // Name — space-pad to 16 bytes
    const char *utf8 = file.name.UTF8String ?: "";
    size_t len = strlen(utf8);
    if (len > EMU3_FILENAME_LEN) len = EMU3_FILENAME_LEN;
    memset(de.name, ' ', EMU3_FILENAME_LEN);   // the sampler pads names with spaces, no terminator
    memcpy(de.name, utf8, len);

    de.data.unknown              = 0x00;
    de.data.id                   = entryId;  // sequential within dir block
    de.data.fattrs.start_cluster = CFSwapInt16HostToLittle(fileIndex);  // 1-based slot
    de.data.fattrs.clusters      = CFSwapInt16HostToLittle((uint16_t)clusters);   // chain length
    de.data.fattrs.type          = EMU3_FILE_TYPE_STANDARD;

    // blocks = ceil(data.length / 512); bytes = last partial block size
    NSUInteger totalBytes = data.length;
    NSUInteger totBlk = (totalBytes + EMU3_BLOCK_SIZE - 1) / EMU3_BLOCK_SIZE;
    if (totBlk == 0) totBlk = 1;
    // blocks = blocks used in the LAST cluster; bytes = bytes used in the last block
    uint16_t blocks = (uint16_t)(totBlk - (clusters - 1) * self.clusterBlocks);
    uint16_t bytes  = (uint16_t)(totalBytes - (totBlk - 1) * EMU3_BLOCK_SIZE);
    if (bytes == 0) bytes = EMU3_BLOCK_SIZE;
    de.data.fattrs.blocks = CFSwapInt16HostToLittle(blocks);
    de.data.fattrs.bytes  = CFSwapInt16HostToLittle(bytes);

    // props = "\x00E4B0" (EIV file marker)
    de.data.fattrs.props[0] = 0x00;
    de.data.fattrs.props[1] = 'E';
    de.data.fattrs.props[2] = '4';
    de.data.fattrs.props[3] = 'B';
    de.data.fattrs.props[4] = '0';
    return de;
}

// ──────────────────────────────────────────────────────────────────────────────
// Public operations
// ──────────────────────────────────────────────────────────────────────────────

- (BOOL)deleteFile:(EMU3File *)file
       inDirectory:(EMU3Directory *)directory
             error:(NSError **)error {
    EMU3_GATED_EDIT
    if (self.isReadOnly) {
        if (error) *error = [self _errorCode:EMU3ErrorWriteFailed message:@"Image is read-only"];
        return NO;
    }
    if (!file || !directory) {
        if (error) *error = [self _errorCode:EMU3ErrorInvalidParam message:@"No file selected"];
        return NO;
    }

    uint8_t *entryBlock = NULL;
    emu3_dentry_t *entry = NULL;

    if (file.dentryBlock >= 0 && file.dentryOffset >= 0 && file.dentryOffset < EMU3_ENTRIES_PER_BLOCK) {
        uint8_t *blockData = [self _mutableBlockPtr:(NSUInteger)file.dentryBlock];
        if (blockData) {
            emu3_dentry_t *candidate = (emu3_dentry_t *)(blockData + file.dentryOffset * EMU3_DENTRY_SIZE);
            NSString *candidateName = [self _parseName:candidate->name];
            if ([candidateName isEqualToString:file.name]) {
                entryBlock = blockData;
                entry = candidate;
            }
        }
    }

    if (!entry) {
        for (NSNumber *blockNum in directory.blockList) {
            uint8_t *blockData = [self _mutableBlockPtr:blockNum.unsignedIntegerValue];
            if (!blockData) continue;

            for (int i = 0; i < EMU3_ENTRIES_PER_BLOCK; i++) {
                emu3_dentry_t *candidate = (emu3_dentry_t *)(blockData + i * EMU3_DENTRY_SIZE);
                if (candidate->name[0] == 0) continue;

                NSString *candidateName = [self _parseName:candidate->name];
                uint8_t typeByte = candidate->data.fattrs.type;
                BOOL isFile = (typeByte == EMU3_FILE_TYPE_STANDARD ||
                               typeByte == EMU3_FILE_TYPE_SYSTEM ||
                               typeByte == EMU3_FILE_TYPE_UPDATED ||
                               (candidate->data.fattrs.props[1] == 'E' &&
                                candidate->data.fattrs.props[2] == '4' &&
                                candidate->data.fattrs.props[3] == 'B' &&
                                candidate->data.fattrs.props[4] == '0'));
                if (isFile && [candidateName isEqualToString:file.name]) {
                    entryBlock = blockData;
                    entry = candidate;
                    file.dentryBlock = (NSInteger)blockNum.unsignedIntegerValue;
                    file.dentryOffset = i;
                    break;
                }
            }
            if (entry) break;
        }
    }

    if (!entry) {
        if (error) *error = [self _errorCode:EMU3ErrorFileNotFound message:@"File entry not found in directory"];
        return NO;
    }

    memset(entry, 0, EMU3_DENTRY_SIZE);
    entry->data.fattrs.type = EMU3_FILE_TYPE_DELETED;
    msync(entryBlock, EMU3_BLOCK_SIZE, MS_ASYNC);

    [self _freeChainFromCluster:file.startCluster];
    file.rawType = EMU3_FILE_TYPE_DELETED;

    NSUInteger idx = [directory.files indexOfObjectPassingTest:^BOOL(EMU3File *obj, NSUInteger index, BOOL *stop) {
        return obj == file || ([obj.name isEqualToString:file.name] && obj.startCluster == file.startCluster);
    }];
    if (idx != NSNotFound) [directory.files removeObjectAtIndex:idx];
    return YES;
}

- (BOOL)copyFile:(EMU3File *)file
     toDirectory:(EMU3Directory *)destDir
           error:(NSError **)error {
    EMU3_GATED_EDIT
    // Per-bank pool: a long batch must not pile up every bank's data until the loop ends.
    __block BOOL result = NO;
    NSError *inner = nil;    // the error must outlive the pool, so it is created outside of it
    @autoreleasepool { result = [self _copyFileImpl:file toDirectory:destDir error:&inner]; }
    if (!result && error) *error = inner;
    return result;
}

- (BOOL)_copyFileImpl:(EMU3File *)file
          toDirectory:(EMU3Directory *)destDir
                error:(NSError **)error {
    if (self.isReadOnly) {
        if (error) *error = [self _errorCode:EMU3ErrorWriteFailed message:@"Image is read-only"];
        return NO;
    }

    NSData *data = [self dataForFile:file error:error];
    if (!data) return NO;

    NSUInteger blocksNeeded = (data.length + EMU3_BLOCK_SIZE - 1) / EMU3_BLOCK_SIZE;
    if (blocksNeeded == 0) blocksNeeded = 1;

    NSUInteger clustersNeeded = (blocksNeeded + self.clusterBlocks - 1) / self.clusterBlocks;
    if (clustersNeeded * self.clusterBlocks > self.freeBlocks) {
        if (error) *error = [self _errorCode:EMU3ErrorDiskFull message:@"Not enough free space on image"];
        return NO;
    }

    // Find a free dentry slot in the destination directory
    NSUInteger destBlock = 0; NSInteger destOffset = 0;
    if (![self _findFreeDentry:destDir outBlock:&destBlock outOffset:&destOffset]) {
        if (error) *error = [self _errorCode:EMU3ErrorDirectoryFull message:@"Destination directory is full"];
        return NO;
    }

    NSArray<NSNumber *> *chain = [self _allocateChainOfLength:clustersNeeded];
    if (!chain) {
        if (error) *error = [self _errorCode:EMU3ErrorDiskFull message:@"Image is full (no free clusters)"];
        return NO;
    }
    uint16_t newFileIndex = (uint16_t)chain.firstObject.unsignedIntegerValue;

    // Entry id = lowest unused bank number in the folder
    NSMutableIndexSet *usedIds = [NSMutableIndexSet indexSet];
    for (EMU3File *f in destDir.files) [usedIds addIndex:f.entryId];
    uint8_t newEntryId = 0;
    while ([usedIds containsIndex:newEntryId]) newEntryId++;

    if (![self _writeData:data toChain:chain]) {
        for (NSNumber *c in chain) [self _setFatEntry:c.unsignedIntegerValue value:EMU3_FREE_CLUSTER];
        [self _recountFat];
        if (error) *error = [self _errorCode:EMU3ErrorWriteFailed message:@"Data write failed"];
        return NO;
    }

    EMU3File *newFile = [[EMU3File alloc] init];
    newFile.name     = file.name;
    newFile.fileType = file.fileType;
    emu3_dentry_t de = [self _dentryForFile:newFile
                                  fileIndex:newFileIndex
                                   fileData:data
                                   clusters:clustersNeeded
                                   entryId:newEntryId];
    [self _writeDentry:&de blockIdx:destBlock offset:destOffset];

    // Update in-memory model
    newFile.startCluster        = newFileIndex;
    newFile.clusterCount        = (uint16_t)clustersNeeded;
    newFile.blocksInLastCluster = (uint16_t)(blocksNeeded - (clustersNeeded - 1) * self.clusterBlocks);
    { NSUInteger rb = data.length - (blocksNeeded - 1) * EMU3_BLOCK_SIZE; newFile.bytesInLastBlock = (uint16_t)(rb == 0 ? EMU3_BLOCK_SIZE : rb); }
    newFile.fileSize            = data.length;
    newFile.rawType             = EMU3_FILE_TYPE_STANDARD;  // must be set or isDeleted returns YES
    newFile.entryId             = newEntryId;
    newFile.dentryBlock         = (NSInteger)destBlock;
    newFile.dentryOffset        = destOffset;
    [destDir.files addObject:newFile];
    return YES;
}

- (BOOL)moveFile:(EMU3File *)file
   fromDirectory:(EMU3Directory *)srcDir
     toDirectory:(EMU3Directory *)destDir
           error:(NSError **)error {
    EMU3_GATED_EDIT
    if (self.isReadOnly) {
        if (error) *error = [self _errorCode:EMU3ErrorWriteFailed message:@"Image is read-only"];
        return NO;
    }
    if (srcDir == destDir) return YES;

    // Copy dentry data first
    if (![self copyFile:file toDirectory:destDir error:error]) return NO;

    // Delete source dentry (don't free clusters — copy above allocated new ones; original stays)
    // Actually for a move we want to remove the source dentry and keep clusters pointing to destDir's copy.
    // The copyFile allocated new clusters and copied data, so we now delete the original.
    if (![self deleteFile:file inDirectory:srcDir error:error]) return NO;
    return YES;
}

- (BOOL)importFileAtURL:(NSURL *)url
            toDirectory:(EMU3Directory *)destDir
                  error:(NSError **)error {
    EMU3_GATED_EDIT
    __block BOOL result = NO;
    NSError *inner = nil;
    @autoreleasepool { result = [self _importFileImpl:url toDirectory:destDir error:&inner]; }
    if (!result && error) *error = inner;
    return result;
}

- (BOOL)_importFileImpl:(NSURL *)url
            toDirectory:(EMU3Directory *)destDir
                  error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
    if (!data) return NO;

    // Only bank/E-mu data may be stored: refuse audio and other foreign files, which would
    // otherwise be written to the disk as a broken "bank".
    if (data.length >= 12) {
        const uint8_t *b = data.bytes;
        BOOL riffWave = memcmp(b, "RIFF", 4) == 0 && memcmp(b + 8, "WAVE", 4) == 0;
        BOOL aiff     = memcmp(b, "FORM", 4) == 0 && (memcmp(b + 8, "AIFF", 4) == 0 || memcmp(b + 8, "AIFC", 4) == 0);
        if (riffWave || aiff) {
            if (error) *error = [self _errorCode:EMU3ErrorInvalidParam
                                         message:@"Audio files (WAV/AIFF) cannot be imported as banks"];
            return NO;
        }
    }

    // Use the filename without extension as the bank name (max 15 chars)
    NSString *name = EMU3NameFromFileName(url.lastPathComponent.stringByDeletingPathExtension);
    if (name.length > 15) name = [name substringToIndex:15];

    EMU3File *dummy      = [[EMU3File alloc] init];
    dummy.name           = name;
    dummy.fileType       = EMU3FileTypeBank;
    dummy.cachedData     = data;
    dummy.startCluster   = 0;  // will be assigned by copyFile
    return [self copyFile:dummy toDirectory:destDir error:error];
}

// Overwrites a file's data in place: same directory entry, same bank id, same first cluster.
// The cluster chain is grown or trimmed to fit; the entry's size fields are patched afterwards.
- (BOOL)replaceContentsOfFile:(EMU3File *)file withData:(NSData *)data error:(NSError **)error {
    EMU3_GATED_EDIT
    if (self.isReadOnly) { if (error) *error = [self _errorCode:EMU3ErrorWriteFailed message:@"Image is read-only"]; return NO; }
    if (file.startCluster == 0 || file.dentryBlock <= 0 || file.dentryOffset < 0 || data.length == 0) {
        if (error) *error = [self _errorCode:EMU3ErrorInvalidParam message:@"File has no directory entry to update"];
        return NO;
    }
    NSMutableArray<NSNumber *> *chain = [[self _chainFromCluster:file.startCluster] mutableCopy];
    if (chain.count == 0) { if (error) *error = [self _errorCode:EMU3ErrorReadFailed message:@"File has no cluster chain"]; return NO; }

    NSUInteger blocksNeeded = MAX((NSUInteger)1, (data.length + EMU3_BLOCK_SIZE - 1) / EMU3_BLOCK_SIZE);
    NSUInteger clustersNeeded = (blocksNeeded + self.clusterBlocks - 1) / self.clusterBlocks;

    // 1. grow before writing so a full disk fails without touching the old data
    if (clustersNeeded > chain.count) {
        NSUInteger extra = clustersNeeded - chain.count;
        if (extra * self.clusterBlocks > self.freeBlocks) { if (error) *error = [self _errorCode:EMU3ErrorDiskFull message:@"Not enough free space on image"]; return NO; }
        NSArray<NSNumber *> *more = [self _allocateChainOfLength:extra];
        if (!more) { if (error) *error = [self _errorCode:EMU3ErrorDiskFull message:@"Image is full (no free clusters)"]; return NO; }
        [self _setFatEntry:chain.lastObject.unsignedIntegerValue value:(uint16_t)more.firstObject.unsignedIntegerValue];
        [chain addObjectsFromArray:more];
    }
    // 2. write the data
    if (![self _writeData:data toChain:chain]) { if (error) *error = [self _errorCode:EMU3ErrorWriteFailed message:@"Data write failed"]; return NO; }
    // 3. trim surplus clusters
    if (clustersNeeded < chain.count) {
        [self _setFatEntry:chain[clustersNeeded - 1].unsignedIntegerValue value:EMU3_LAST_CLUSTER];
        for (NSUInteger i = clustersNeeded; i < chain.count; i++) [self _setFatEntry:chain[i].unsignedIntegerValue value:EMU3_FREE_CLUSTER];
    }
    [self _recountFat];
    // 4. patch the directory entry's size fields
    uint16_t blocks = (uint16_t)(blocksNeeded - (clustersNeeded - 1) * self.clusterBlocks);
    uint16_t bytes = (uint16_t)(data.length - (blocksNeeded - 1) * EMU3_BLOCK_SIZE);
    if (bytes == 0) bytes = EMU3_BLOCK_SIZE;
    uint8_t *bp = [self _mutableBlockPtr:(NSUInteger)file.dentryBlock];
    if (!bp) { if (error) *error = [self _errorCode:EMU3ErrorWriteFailed message:@"Directory block unavailable"]; return NO; }
    emu3_dentry_t *de = (emu3_dentry_t *)(bp + file.dentryOffset * EMU3_DENTRY_SIZE);
    de->data.fattrs.clusters = CFSwapInt16HostToLittle((uint16_t)clustersNeeded);
    de->data.fattrs.blocks   = CFSwapInt16HostToLittle(blocks);
    de->data.fattrs.bytes    = CFSwapInt16HostToLittle(bytes);
    msync(bp, EMU3_BLOCK_SIZE, MS_SYNC);

    file.clusterCount = (uint16_t)clustersNeeded; file.blocksInLastCluster = blocks; file.bytesInLastBlock = bytes;
    file.fileSize = data.length; file.cachedData = nil; file.metadataParsed = NO;
    return YES;
}

- (BOOL)exportFile:(EMU3File *)file toURL:(NSURL *)destURL error:(NSError **)error {
    NSData *data = [self dataForFile:file error:error];
    if (!data) return NO;
    return [data ed_writeToURL:destURL error:error];
}

- (BOOL)renameFile:(EMU3File *)file
           newName:(NSString *)newName
       inDirectory:(EMU3Directory *)directory
             error:(NSError **)error {
    EMU3_GATED_EDIT
    if (self.isReadOnly) {
        if (error) *error = [self _errorCode:EMU3ErrorWriteFailed message:@"Image is read-only"];
        return NO;
    }
    if (newName.length == 0 || newName.length > EMU3_FILENAME_LEN - 1) {
        if (error) *error = [self _errorCode:EMU3ErrorInvalidParam
                                     message:@"Name must be 1–15 characters"];
        return NO;
    }

    uint8_t *blockData = [self _mutableBlockPtr:(NSUInteger)file.dentryBlock];
    if (!blockData) {
        if (error) *error = [self _errorCode:EMU3ErrorFileNotFound message:@"Dentry block not found"];
        return NO;
    }
    emu3_dentry_t *de = (emu3_dentry_t *)(blockData + file.dentryOffset * EMU3_DENTRY_SIZE);
    memset(de->name, ' ', EMU3_FILENAME_LEN);
    const char *utf8 = newName.UTF8String;
    size_t len = MIN(strlen(utf8), (size_t)(EMU3_FILENAME_LEN - 1));
    memcpy(de->name, utf8, len);
    msync(blockData, EMU3_BLOCK_SIZE, MS_ASYNC);

    file.name = newName;
    return YES;
}

- (BOOL)renameDirectory:(EMU3Directory *)dir
                newName:(NSString *)newName
                  error:(NSError **)error {
    EMU3_GATED_EDIT
    if (self.isReadOnly) {
        if (error) *error = [self _errorCode:EMU3ErrorWriteFailed message:@"Image is read-only"];
        return NO;
    }
    if (!dir || dir == self.rootDirectory) {
        if (error) *error = [self _errorCode:EMU3ErrorInvalidParam message:@"This folder cannot be renamed"];
        return NO;
    }
    if (newName.length == 0 || newName.length > EMU3_FILENAME_LEN - 1) {
        if (error) *error = [self _errorCode:EMU3ErrorInvalidParam message:@"Name must be 1–15 characters"];
        return NO;
    }
    EMU3Directory *parent = dir.parent ?: self.rootDirectory;
    for (EMU3Directory *sib in parent.subdirectories) {
        if (sib != dir && [sib.name caseInsensitiveCompare:newName] == NSOrderedSame) {
            if (error) *error = [self _errorCode:EMU3ErrorInvalidParam message:@"A folder with this name already exists"];
            return NO;
        }
    }
    // Locate the folder's entry: the recorded position, else search the parent's blocks by old name.
    emu3_dentry_t *de = NULL;
    uint8_t *blockData = NULL;
    if (dir.dentryBlock > 0 && dir.dentryOffset >= 0 && dir.dentryOffset < EMU3_ENTRIES_PER_BLOCK) {
        blockData = [self _mutableBlockPtr:(NSUInteger)dir.dentryBlock];
        if (blockData) {
            emu3_dentry_t *cand = (emu3_dentry_t *)(blockData + dir.dentryOffset * EMU3_DENTRY_SIZE);
            uint8_t idb = cand->data.id;
            if (cand->name[0] != 0 && (idb == EMU3_ID_DIR_TYPE_A || idb == EMU3_ID_DIR_TYPE_B) &&
                [[self _parseName:cand->name] isEqualToString:dir.name]) de = cand;
        }
    }
    if (!de) {
        for (NSNumber *bn in parent.blockList) {
            uint8_t *bd = [self _mutableBlockPtr:bn.unsignedIntegerValue];
            if (!bd) continue;
            for (int i = 0; i < EMU3_ENTRIES_PER_BLOCK && !de; i++) {
                emu3_dentry_t *cand = (emu3_dentry_t *)(bd + i * EMU3_DENTRY_SIZE);
                uint8_t idb = cand->data.id;
                if (cand->name[0] != 0 && (idb == EMU3_ID_DIR_TYPE_A || idb == EMU3_ID_DIR_TYPE_B) &&
                    [[self _parseName:cand->name] isEqualToString:dir.name]) { de = cand; blockData = bd; }
            }
            if (de) break;
        }
    }
    if (!de) {
        if (error) *error = [self _errorCode:EMU3ErrorFileNotFound message:@"Folder entry not found"];
        return NO;
    }
    memset(de->name, ' ', EMU3_FILENAME_LEN);
    const char *utf8 = newName.UTF8String;
    memcpy(de->name, utf8, MIN(strlen(utf8), (size_t)(EMU3_FILENAME_LEN - 1)));
    msync(blockData, EMU3_BLOCK_SIZE, MS_ASYNC);
    dir.name = newName;
    return YES;
}

// ──────────────────────────────────────────────────────────────────────────────
// Directory block allocation helpers
// ──────────────────────────────────────────────────────────────────────────────

- (void)_collectDirectoryBlocks:(EMU3Directory *)dir into:(NSMutableSet<NSNumber *> *)set {
    for (NSNumber *b in dir.blockList) [set addObject:b];
    for (EMU3Directory *sub in dir.subdirectories)
        [self _collectDirectoryBlocks:sub into:set];
}

// On real EOS disks every folder entry in the root has id 0x80 except the last one (0x40).
- (void)_normalizeFolderIdsInRoot {
    uint8_t *lastPtr = NULL;
    for (NSNumber *blockNum in self.rootDirectory.blockList) {
        uint8_t *bd = [self _mutableBlockPtr:blockNum.unsignedIntegerValue];
        if (!bd) continue;
        for (int i = 0; i < EMU3_ENTRIES_PER_BLOCK; i++) {
            emu3_dentry_t *de = (emu3_dentry_t *)(bd + i * EMU3_DENTRY_SIZE);
            if (de->name[0] == 0) continue;
            if (de->data.id == EMU3_ID_DIR_TYPE_A || de->data.id == EMU3_ID_DIR_TYPE_B) {
                de->data.id = EMU3_ID_DIR_TYPE_B;
                lastPtr = (uint8_t *)&de->data.id;
            }
        }
    }
    if (lastPtr) *lastPtr = EMU3_ID_DIR_TYPE_A;
}

// Find the first block in the folder pool not
// already owned by any existing directory.
- (NSUInteger)_findFreeDirectoryBlock {
    NSMutableSet<NSNumber *> *used = [NSMutableSet set];
    [self _collectDirectoryBlocks:self.rootDirectory into:used];
    for (NSUInteger b = self.dirPoolStart; b < self.dirPoolStart + self.dirPoolCount; b++) {
        if (![used containsObject:@(b)]) return b;
    }
    return 0;
}

// ──────────────────────────────────────────────────────────────────────────────
// Directory operations
// ──────────────────────────────────────────────────────────────────────────────

- (BOOL)createDirectoryNamed:(NSString *)name
                 inDirectory:(EMU3Directory *)parent
                       error:(NSError **)error {
    EMU3_GATED_EDIT
    if (self.isReadOnly) {
        if (error) *error = [self _errorCode:EMU3ErrorWriteFailed message:@"Image is read-only"];
        return NO;
    }
    if (name.length == 0 || name.length > EMU3_FILENAME_LEN - 1) {
        if (error) *error = [self _errorCode:EMU3ErrorInvalidParam
                                     message:@"Name must be 1–15 characters"];
        return NO;
    }

    // EOS has exactly one level of folders: root -> folder -> banks.
    if (parent != self.rootDirectory) {
        if (error) *error = [self _errorCode:EMU3ErrorInvalidParam
                                     message:@"E-mu disks only support one level of folders"];
        return NO;
    }

    // Find free dentry slot in parent
    NSUInteger parentBlock = 0; NSInteger parentOffset = 0;
    if (![self _findFreeDentry:parent outBlock:&parentBlock outOffset:&parentOffset]) {
        if (error) *error = [self _errorCode:EMU3ErrorDirectoryFull
                                     message:@"Parent directory is full"];
        return NO;
    }

    // Find a free metadata block for the new directory's contents
    NSUInteger newBlock = [self _findFreeDirectoryBlock];
    if (newBlock == 0) {
        if (error) *error = [self _errorCode:EMU3ErrorDiskFull
                                     message:@"No free directory block available"];
        return NO;
    }

    // Zero the new directory block
    uint8_t *bp = [self _mutableBlockPtr:newBlock];
    if (!bp) {
        if (error) *error = [self _errorCode:EMU3ErrorWriteFailed message:@"Block write failed"];
        return NO;
    }
    memset(bp, 0, EMU3_BLOCK_SIZE);
    msync(bp, EMU3_BLOCK_SIZE, MS_ASYNC);

    // Build the directory dentry
    emu3_dentry_t de;
    memset(&de, 0, sizeof(de));
    const char *utf8 = name.UTF8String ?: "";
    size_t len = MIN(strlen(utf8), (size_t)EMU3_FILENAME_LEN);
    memset(de.name, ' ', EMU3_FILENAME_LEN);   // space padded like the sampler
    memcpy(de.name, utf8, len);
    de.data.unknown = 0;
    de.data.id = EMU3_ID_DIR_TYPE_A;   // 0x40 = last folder; earlier ones are re-marked 0x80 below
    de.data.dattrs.block_list[0] = (int16_t)CFSwapInt16HostToLittle((uint16_t)newBlock);
    for (int k = 1; k < EMU3_BLOCKS_PER_DIR; k++) de.data.dattrs.block_list[k] = (int16_t)-1;   // unused = 0xFFFF

    [self _writeDentry:&de blockIdx:parentBlock offset:parentOffset];

    // Update in-memory model
    EMU3Directory *newDir    = [[EMU3Directory alloc] init];
    newDir.name              = name;
    newDir.entryId           = EMU3_ID_DIR_TYPE_A;
    newDir.parent            = parent;
    newDir.dentryBlock       = (NSInteger)parentBlock;
    newDir.dentryOffset      = parentOffset;
    [newDir.blockList addObject:@(newBlock)];
    [parent.subdirectories addObject:newDir];
    [self _normalizeFolderIdsInRoot];
    return YES;
}

- (BOOL)deleteDirectory:(EMU3Directory *)dir
             fromParent:(EMU3Directory *)parent
                  error:(NSError **)error {
    EMU3_GATED_EDIT
    if (self.isReadOnly) {
        if (error) *error = [self _errorCode:EMU3ErrorWriteFailed message:@"Image is read-only"];
        return NO;
    }
    if (!dir) {
        if (error) *error = [self _errorCode:EMU3ErrorInvalidParam message:@"No folder selected"];
        return NO;
    }
    if (!parent) parent = dir.parent;
    if (!parent) {
        if (error) *error = [self _errorCode:EMU3ErrorInvalidParam message:@"Folder parent not found"];
        return NO;
    }

    for (EMU3File *f in [dir.files copy]) {
        NSError *childError = nil;
        if (![self deleteFile:f inDirectory:dir error:&childError]) {
            if (error) *error = childError ?: [self _errorCode:EMU3ErrorWriteFailed message:@"Could not delete a file inside the folder"];
            return NO;
        }
    }
    for (EMU3Directory *sub in [dir.subdirectories copy]) {
        NSError *childError = nil;
        if (![self deleteDirectory:sub fromParent:dir error:&childError]) {
            if (error) *error = childError ?: [self _errorCode:EMU3ErrorWriteFailed message:@"Could not delete a nested folder"];
            return NO;
        }
    }

    for (NSNumber *blockNum in dir.blockList) {
        uint8_t *bp = [self _mutableBlockPtr:blockNum.unsignedIntegerValue];
        if (!bp) {
            if (error) *error = [self _errorCode:EMU3ErrorWriteFailed message:@"Folder data block not found in image"];
            return NO;
        }
        memset(bp, 0, EMU3_BLOCK_SIZE);
        msync(bp, EMU3_BLOCK_SIZE, MS_ASYNC);
    }

    BOOL clearedDentry = NO;
    if (dir.dentryBlock >= 0 && dir.dentryOffset >= 0 && dir.dentryOffset < EMU3_ENTRIES_PER_BLOCK) {
        uint8_t *pb = [self _mutableBlockPtr:(NSUInteger)dir.dentryBlock];
        if (pb) {
            memset(pb + dir.dentryOffset * EMU3_DENTRY_SIZE, 0, EMU3_DENTRY_SIZE);
            msync(pb, EMU3_BLOCK_SIZE, MS_ASYNC);
            clearedDentry = YES;
        }
    }

    if (!clearedDentry) {
        for (NSNumber *blockNum in parent.blockList) {
            NSUInteger blockIdx = blockNum.unsignedIntegerValue;
            uint8_t *blockData = [self _mutableBlockPtr:blockIdx];
            if (!blockData) continue;

            for (int i = 0; i < EMU3_ENTRIES_PER_BLOCK; i++) {
                emu3_dentry_t *de = (emu3_dentry_t *)(blockData + i * EMU3_DENTRY_SIZE);
                if (de->name[0] == 0) continue;

                NSString *name = [self _parseName:de->name];
                uint8_t idByte = de->data.id;
                BOOL isDir = (idByte == EMU3_ID_DIR_TYPE_A || idByte == EMU3_ID_DIR_TYPE_B);
                if (isDir && [name isEqualToString:dir.name]) {
                    memset(de, 0, EMU3_DENTRY_SIZE);
                    msync(blockData, EMU3_BLOCK_SIZE, MS_ASYNC);
                    dir.dentryBlock = (NSInteger)blockIdx;
                    dir.dentryOffset = i;
                    clearedDentry = YES;
                    break;
                }
            }
            if (clearedDentry) break;
        }
    }

    if (clearedDentry && parent == self.rootDirectory) [self _normalizeFolderIdsInRoot];

    if (!clearedDentry) {
        if (error) *error = [self _errorCode:EMU3ErrorFileNotFound message:@"Folder entry not found in parent directory"];
        return NO;
    }

    NSUInteger idx = [parent.subdirectories indexOfObjectPassingTest:^BOOL(EMU3Directory *obj, NSUInteger index, BOOL *stop) {
        return obj == dir || [obj.name isEqualToString:dir.name];
    }];
    if (idx != NSNotFound) [parent.subdirectories removeObjectAtIndex:idx];
    return YES;
}

// ──────────────────────────────────────────────────────────────────────────────
// Sample export
// ──────────────────────────────────────────────────────────────────────────────

- (NSArray<NSString *> *)samplesFromBankFile:(EMU3File *)bankFile error:(NSError **)error {
    if (bankFile.fileType != EMU3FileTypeBank) {
        if (error) *error = [self _errorCode:EMU3ErrorInvalidParam message:@"Not a bank file"];
        return @[];
    }

    NSData *data = [self dataForFile:bankFile error:error];
    if (!data || data.length < 12) return @[];

    NSMutableArray<NSString *> *samples = [NSMutableArray array];
    const uint8_t *bytes = data.bytes;

    if (memcmp(bytes, "FORM", 4) == 0 && data.length >= 12) {
        NSUInteger formEnd = MIN(data.length, 8 + (NSUInteger)be32(bytes + 4));
        if (formEnd <= 12) formEnd = data.length;

        for (NSUInteger off = 12; off + 8 <= formEnd; ) {
            const uint8_t *chunk = bytes + off;
            uint32_t chunkSize = be32(chunk + 4);
            if (chunkSize > formEnd - off - 8) break;

            if (emu3_chunk_is_sample(chunk)) {
                char chunkID[5] = {0};
                memcpy(chunkID, chunk, 4);
                [samples addObject:[NSString stringWithFormat:@"%s_%03lu",
                                    chunkID, (unsigned long)(samples.count + 1)]];
            }

            NSUInteger paddedSize = chunkSize + (chunkSize & 1);
            off += 8 + paddedSize;
        }

        if (samples.count > 0) return samples;

        if (data.length < 20) return samples;
        uint32_t toc1Size = CFSwapInt32BigToHost(*(const uint32_t *)(bytes + 16));
        NSUInteger toc1End = MIN(20 + toc1Size, data.length);

        // Scan TOC1 entries for sample chunks
        for (NSUInteger off = 20; off + 32 <= toc1End; off += 32) {
            const uint8_t *e = bytes + off;
            char chunkID[5] = {0};
            memcpy(chunkID, e, 4);

            // Detect all sample chunk types (same as in populateBankMetadata)
            if ((emu3_chunk_is_sample(e) ||
                 memcmp(e, "E3S", 3) == 0 ||
                 memcmp(e, "E4S", 3) == 0 ||
                 memcmp(e, "E4s", 3) == 0 ||
                 memcmp(e, "RIFF", 4) == 0 ||
                 memcmp(e, "FORM", 4) == 0 ||
                 memcmp(e, "E3I", 3) == 0 ||
                 memcmp(e, "E4I", 3) == 0)) {
                [samples addObject:@(chunkID)];
            }
        }
    }

    return samples;
}

- (BOOL)exportSampleAtIndex:(NSUInteger)sampleIndex
               fromBankFile:(EMU3File *)bankFile
                      toURL:(NSURL *)destURL
                      error:(NSError **)error {
    NSArray<NSString *> *samples = [self samplesFromBankFile:bankFile error:error];
    if (sampleIndex >= samples.count && sampleIndex >= bankFile.sampleCount) {
        if (error) *error = [self _errorCode:EMU3ErrorInvalidParam message:@"Sample index out of range"];
        return NO;
    }

    NSData *bankData = [self dataForFile:bankFile error:error];
    if (!bankData) return NO;

    NSString *sampleID = samples[sampleIndex];
    const uint8_t *bytes = bankData.bytes;

    // Find the sample chunk in the IFF file.
    // IFF structure: FORM [size] [type] [chunks...]
    // Each chunk: [4-byte ID] [4-byte BE size] [data...]
    NSUInteger searchStart = 12;  // After "FORM" + size + "E4B0"
    NSUInteger foundOffset = 0;
    uint32_t foundSize = 0;
    BOOL foundChunk = NO;

    if (memcmp(bytes, "FORM", 4) == 0 && bankData.length >= 12) {
        NSUInteger formEnd = MIN(bankData.length, 8 + (NSUInteger)be32(bytes + 4));
        if (formEnd <= 12) formEnd = bankData.length;
        NSUInteger currentSample = 0;

        while (searchStart + 8 <= formEnd) {
            const uint8_t *chunkPos = bytes + searchStart;
            uint32_t chunkSize = be32(chunkPos + 4);
            if (chunkSize > formEnd - searchStart - 8) break;

            if (emu3_chunk_is_sample(chunkPos)) {
                if (currentSample == sampleIndex) {
                    foundChunk = YES;
                    foundOffset = searchStart + 8;  // Skip ID and size
                    foundSize = chunkSize;
                    break;
                }
                currentSample++;
            }

            NSUInteger paddedSize = chunkSize + (chunkSize & 1);
            searchStart += 8 + paddedSize;
        }
    }

    if (!foundChunk) {
        searchStart = 12;
        while (searchStart + 8 <= bankData.length) {
            const uint8_t *chunkPos = bytes + searchStart;
            uint32_t chunkSize = be32(chunkPos + 4);
            if (memcmp(chunkPos, sampleID.UTF8String, 4) == 0) {
                foundChunk = YES;
                foundOffset = searchStart + 8;  // Skip ID and size
                foundSize = chunkSize;
                break;
            }
            NSUInteger paddedSize = chunkSize + (chunkSize & 1);
            searchStart += 8 + paddedSize;
        }
    }

    if (!foundChunk) {
        if (error) *error = [self _errorCode:EMU3ErrorReadFailed message:@"Sample chunk not found"];
        return NO;
    }

    // Extract sample data and write as WAV
    const uint8_t *sampleData = bytes + foundOffset;
    uint32_t sampleSize = foundSize ?: (uint32_t)(bankData.length - foundOffset);

    // Create minimal WAV header
    // Assumes 16-bit mono PCM at 44.1kHz (standard E-MU format)
    NSMutableData *wavData = [NSMutableData data];

    uint16_t numChannels = 1;
    uint32_t sampleRate = 44100;
    uint16_t bitsPerSample = 16;
    uint32_t byteRate = sampleRate * numChannels * (bitsPerSample / 8);
    uint16_t blockAlign = numChannels * (bitsPerSample / 8);
    uint32_t dataSize = sampleSize;

    // RIFF header
    [wavData appendBytes:"RIFF" length:4];
    uint32_t fileSize = 36 + dataSize;
    [wavData appendBytes:&fileSize length:4];
    [wavData appendBytes:"WAVE" length:4];

    // fmt subchunk
    [wavData appendBytes:"fmt " length:4];
    uint32_t fmtSize = 16;
    [wavData appendBytes:&fmtSize length:4];
    uint16_t audioFormat = 1;  // PCM
    [wavData appendBytes:&audioFormat length:2];
    [wavData appendBytes:&numChannels length:2];
    [wavData appendBytes:&sampleRate length:4];
    [wavData appendBytes:&byteRate length:4];
    [wavData appendBytes:&blockAlign length:2];
    [wavData appendBytes:&bitsPerSample length:2];

    // data subchunk
    [wavData appendBytes:"data" length:4];
    [wavData appendBytes:&dataSize length:4];
    [wavData appendBytes:sampleData length:sampleSize];

    // Write to file
    if (![wavData writeToURL:destURL atomically:YES]) {
        if (error) *error = [self _errorCode:EMU3ErrorWriteFailed message:@"Failed to write sample file"];
        return NO;
    }

    return YES;
}

// ──────────────────────────────────────────────────────────────────────────────
// Error helper
// ──────────────────────────────────────────────────────────────────────────────

- (NSError *)_errorCode:(EMU3ErrorCode)code message:(NSString *)msg {
    return [NSError errorWithDomain:EMU3ErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: msg}];
}


static NSString * const kEMU3EditDepthKey = @"emu3.editDepth";

- (BOOL)_beginEditError:(NSError **)error {
    NSMutableDictionary *td = NSThread.currentThread.threadDictionary;
    NSInteger depth = [td[kEMU3EditDepthKey] integerValue];
    if (depth == 0) {
        BOOL (^gate)(void) = self.editGateBegin;
        if (gate && !gate()) {
            if (error) *error = [self _errorCode:EMU3ErrorWriteFailed
                message:@"The sampler is using this disk right now. Wait a few seconds until it is idle and try again."];
            return NO;
        }
    }
    td[kEMU3EditDepthKey] = @(depth + 1);
    return YES;
}

- (void)_endEdit {
    NSMutableDictionary *td = NSThread.currentThread.threadDictionary;
    NSInteger depth = [td[kEMU3EditDepthKey] integerValue] - 1;
    td[kEMU3EditDepthKey] = @(MAX(depth, 0));
    if (depth == 0) { void (^end)(void) = self.editGateEnd; if (end) end(); }
}

@end
