#import "EMU3File.h"

@implementation EMU3File

- (BOOL)isDeleted {
    return self.rawType == EMU3_FILE_TYPE_DELETED;
}

- (NSString *)fileSizeString {
    return EMU3FormatBytes(self.fileSize);
}

- (NSString *)fileTypeString {
    switch (self.fileType) {
        case EMU3FileTypeBank:   return @"Bank";
        case EMU3FileTypeSystem: return @"System";
        default:                 return @"File";
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<EMU3File: %@ (%@) %@>",
            self.name, self.fileTypeString, self.fileSizeString];
}

@end
