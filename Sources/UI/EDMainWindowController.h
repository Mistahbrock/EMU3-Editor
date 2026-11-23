// EDMainWindowController — the editor window: disk browser, sample list, waveform/loop editor, inspector.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "EDBank.h"

@interface EDMainWindowController : NSWindowController <NSWindowDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate,
                                                        NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSTabViewDelegate>
- (instancetype)init;
// state for the front panel
@property (nonatomic, readonly, nullable) EDBank *bank;
@property (nonatomic, readonly, copy, nullable) NSString *bankTitle;
@property (nonatomic, readonly, copy, nullable) NSString *diskTitle;     // disk image file name, if one is open
@property (nonatomic, readonly, copy, nullable) NSString *statusText;
@property (nonatomic, readonly) NSInteger selectedSampleIndex;
@property (nonatomic, readonly) NSInteger selectedPresetIndex;
@property (nonatomic, copy, nullable) void (^onModelChange)(void);        // bank, selection or title changed
- (void)selectSampleAtIndex:(NSInteger)i;
- (void)selectPresetAtIndex:(NSInteger)i;
- (void)showEditorTab:(nullable NSString *)ident;                         // @"samples" or @"presets"; brings the editor window to the front
- (BOOL)openURL:(NSURL *)url;                  // .hda/.iso/.img disk image or .e4b bank file
- (BOOL)confirmQuit;                           // YES when nothing is unsaved or the user chose to discard
// menu actions
- (IBAction)openDiskImage:(id)sender;
- (IBAction)openBankFile:(id)sender;
- (IBAction)saveBank:(id)sender;
- (IBAction)saveBankAs:(id)sender;
- (IBAction)exportWAV:(id)sender;
- (IBAction)importWAV:(id)sender;
- (IBAction)togglePlay:(id)sender;
- (IBAction)normalize:(id)sender;
- (IBAction)reverseSample:(id)sender;
- (IBAction)fadeIn:(id)sender;
- (IBAction)fadeOut:(id)sender;
- (IBAction)removeDC:(id)sender;
- (IBAction)cropToLoop:(id)sender;
- (IBAction)crossfadeLoop:(id)sender;
- (IBAction)sendToSamplerDisk:(id)sender;
- (IBAction)sdsTransfer:(id)sender;
- (IBAction)smdiTransfer:(id)sender;
- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (IBAction)zoomFit:(id)sender;
- (IBAction)zoomLoop:(id)sender;
- (IBAction)showMasterTab:(id)sender;
- (IBAction)showDiskTab:(id)sender;
- (IBAction)showSamplesTab:(id)sender;
- (IBAction)showPresetsTab:(id)sender;
- (IBAction)showMIDITab:(id)sender;
- (IBAction)showSetupTab:(id)sender;
- (IBAction)showBankTab:(id)sender;
- (IBAction)showFXTab:(id)sender;
- (IBAction)toggleFXBoard:(id)sender;
- (IBAction)showSamplerDisk:(id)sender;
- (IBAction)showAssignKeys:(id)sender;
- (IBAction)showChannelVolume:(id)sender;
- (IBAction)showTones:(id)sender;
- (IBAction)sendPresetToSamplerDisk:(id)sender;
- (IBAction)exportPresetBank:(id)sender;
@end
