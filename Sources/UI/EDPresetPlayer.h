// EDPresetPlayer — plays a preset on the Mac so edits can be heard while you make them. GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Foundation/Foundation.h>
#import "EDBank.h"

NS_ASSUME_NONNULL_BEGIN
/// A small polyphonic player for EOS presets: every voice and zone whose key and velocity windows contain the note sounds, at the pitch of
/// the note against the zone's root key, with volume, pan, tuning and the six-stage volume envelope. It is an audition, not an emulation of
/// the sampler: the filter, LFOs and cords are ignored, and the envelope times are an estimate.
@interface EDPresetPlayer : NSObject
/// Called on the main thread for a note played on a MIDI keyboard (velocity 0 = off).
@property (nonatomic, copy, nullable) void (^midiNote)(int key, int velocity, BOOL on);
/// Starts the note. Returns a short description of what sounds, or what is missing ("no zone covers this key").
- (NSString *)noteOn:(int)key velocity:(int)velocity preset:(EDPreset *)preset bank:(EDBank *)bank;
- (void)noteOff:(int)key;
- (void)allNotesOff;
/// The preset was edited: sounding notes pick up the new envelope, level, pan and tuning straight away.
- (void)presetChanged:(EDPreset *)preset;
/// Listens to every MIDI source for notes (delivered through `midiNote`).
- (void)startMIDIInput;
@end
NS_ASSUME_NONNULL_END
