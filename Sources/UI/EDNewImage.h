// EDNewImage — "New Disk Image": the EMU3 Disk Manager's New Image panel, ported into the editor.
// Choose where (a mounted card/volume, the Disk Manager's image folder, or any folder), the size (8 MB .. 512 GB), the SCSI ID
// (the BlueSCSI name HD<id>0_<size>.hda), and whether to format it as an empty EOS disk. Refuses what cannot work (FAT32 files
// over 4 GB, a card on the BlueSCSI's own USB link) and offers a sparse file when the volume is too small.
// Derived from EMU3 Disk Manager (GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio).
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@interface EDNewImage : NSObject
/// Runs the panel. `status` gets progress text; `done` gets the new image's URL (not called when cancelled or failed).
+ (void)runWithStatus:(void (^)(NSString *text))status completion:(void (^)(NSURL *created))done;
@end
NS_ASSUME_NONNULL_END
