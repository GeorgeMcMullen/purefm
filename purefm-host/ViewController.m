//
//  ViewController.m
//  purefm-host
//
//  Created by Paul Forgey on 4/6/20.
//  Copyright © 2020 Paul Forgey. All rights reserved.
//

#import "ViewController.h"
#import <AudioUnit/AudioUnit.h>
#import <CoreAudioKit/AUViewController.h>
#import <CoreMIDI/CoreMIDI.h>

@interface ViewController ()

@property (weak) IBOutlet NSPopUpButton *presetButton;

@end

@implementation ViewController {
    MIDIClientRef midiClient;
    MIDIPortRef midiPort;
}

- (NSURL *)presetsURL {
    NSURL *directoryURL = [NSURL fileURLWithPath:NSHomeDirectory()];
    NSArray< NSURL * > *urls = [[NSFileManager defaultManager] URLsForDirectory:NSLibraryDirectory
                                                                      inDomains:NSUserDomainMask];
    if ([urls count]) {
        NSString *presetDir = [NSString stringWithFormat:@"Audio/Presets/%@/%@",
                               self.audioUnit.manufacturerName,
                               self.audioUnit.name];
        directoryURL = [NSURL fileURLWithPath:presetDir relativeToURL:[urls objectAtIndex:0]];
    }
    return directoryURL;
}

- (IBAction)presetAction:(id)sender {
    if ([_presetButton indexOfSelectedItem] < 2) {
        return;
    }
    NSURL *url = [NSURL fileURLWithPath:[_presetButton titleOfSelectedItem]
                          relativeToURL:[self presetsURL]];
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data != nil) {
        NSError *error = nil;
        NSMutableDictionary *dict = [NSPropertyListSerialization propertyListWithData:data
                                                       options:NSPropertyListMutableContainersAndLeaves
                                                                format:nil
                                                                 error:&error];
        if (dict == nil) {
            // GarageBand (and possibly Logic?) seems to prefer this goofy encapsulated format
            if (data.length > 4) {
                UInt32 length;
                [data getBytes:&length length:4];
                if (length >= (data.length - 4)) {
                    data = [NSData dataWithBytes:((UInt32 const *)data.bytes)+1 length:length];
                    dict = [NSPropertyListSerialization propertyListWithData:data
                                                         options:NSPropertyListMutableContainersAndLeaves
                                                                      format:nil
                                                                       error:&error];
                }
            }
        }
        if (dict == nil) {
            NSLog(@"error deserializing: %@", error);
        } else {
            self.audioUnit.AUAudioUnit.fullState = dict;
        }
    }
}

- (void)refreshPresets {
    NSInteger count = [_presetButton numberOfItems];
    if (count > 2) {
        for (int i = 2; i < count; i++) {
            [_presetButton removeItemAtIndex:2];
        }
    }

    NSArray<NSURL *> *presets =
    [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[self presetsURL]
                                  includingPropertiesForKeys:nil
                                                     options:0
                                                       error:nil];
    NSMutableArray< NSString *> *names = [NSMutableArray arrayWithCapacity:[presets count]];
    for (NSURL *p in presets) {
        if ([p.pathExtension isEqualToString:@"aupreset"]) {
            [names addObject:p.lastPathComponent];
        }
    }
    for (NSString *n in [names sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
        [_presetButton addItemWithTitle:n];
    }
}

- (IBAction)saveAs:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.directoryURL = [self presetsURL];
    panel.allowedFileTypes = @[@"aupreset"];

    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSError *error = nil;
            if (![self.audioUnit.AUAudioUnit.fullState writeToURL:panel.URL error:&error]) {
                [[NSAlert alertWithError:error] runModal];
            }
        }
    }];
    [self refreshPresets];
}


- (void)viewDidLoad {
    [super viewDidLoad];

    OSStatus status = MIDIClientCreateWithBlock((CFStringRef)@"pure", &midiClient,
                                                ^(const MIDINotification * _Nonnull message) {
                                                    if (message->messageID == kMIDIMsgSetupChanged) {
                                                        [self rescanMIDI];
                                                    }
                                                });
    if (status != 0) {
        NSLog(@"MIDIClientCreate: %d", status);
        return;
    }

    self.engine = [[AVAudioEngine alloc] init];

    AudioComponentDescription desc;
    memset(&desc, 0, sizeof(desc));
    desc.componentType = kAudioUnitType_MusicDevice;
    desc.componentSubType = 'pure';
    desc.componentManufacturer = 'SHOE';

    [AVAudioUnit instantiateWithComponentDescription:desc
                                             options:kAudioComponentInstantiation_LoadOutOfProcess
                                   completionHandler:^(__kindof AVAudioUnit * _Nullable audioUnit, NSError * _Nullable error) {
        [self embedAudioUnit:audioUnit error:error];
    }];

}

- (void)rescanMIDI {
    NSLog(@"midi inputs changed");
    for (ItemCount i = 0; i < MIDIGetNumberOfSources(); ++i) {
        MIDIEndpointRef source = MIDIGetSource(i);
        if (source != 0) {
            MIDIPortConnectSource(midiPort, source, NULL);
        }
    }
}

- (void)embedAudioUnit:(AVAudioUnit *)unit error:(NSError *)error {
    if (error != NULL) {
        NSLog(@"Error loading audio unit: %@", error);
        return;
    }
    self.audioUnit = unit;
    [self refreshPresets];

    [_engine attachNode:unit];
    [_engine connect:unit
                  to:[_engine mainMixerNode]
              format:[[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.00 channels:2]];
    if (![_engine startAndReturnError:&error]) {
        NSLog(@"startAndReturnError: %@", error);
    }


    AUScheduleMIDIEventBlock block = _audioUnit.AUAudioUnit.scheduleMIDIEventBlock;

    OSStatus status = MIDIInputPortCreateWithBlock(midiClient,
                                                   (CFStringRef)@"pure-input",
                                                   &midiPort,
                                                   ^(MIDIPacketList const *list, void *refConn) {
                                                       MIDIPacket const *packet = &list->packet[0];
                                                       for (int i = 0; i < list->numPackets; ++i) {
                                                           block(AUEventSampleTimeImmediate,
                                                                 0,
                                                                 packet->length, packet->data);
                                                           packet = MIDIPacketNext(packet);
                                                       }
                                                   });
    if (status != 0) {
        NSLog(@"MIDIInputPortCreateWithBlock: %d", status);
    }
    [self rescanMIDI];

    [[unit AUAudioUnit] requestViewControllerWithCompletionHandler:^(AUViewControllerBase * _Nullable viewController) {
        if (viewController != nil) {
            [self addPluginView:(NSViewController *)viewController];
        } else {
            NSLog(@"nil viewController");
        }
    }];

}

- (void)addPluginView:(NSViewController *)viewController {
    viewController.view.frame = _extensionView.bounds;
    [_extensionView addSubview:viewController.view];
}

- (void)viewDidDisappear {
    if (_engine != nil) {
        [_engine stop];
        self.engine = nil;
    }
    if (midiPort != 0) {
        MIDIPortDispose(midiPort);
        midiPort = 0;
    }
    if (midiClient != 0) {
        MIDIClientDispose(midiClient);
        midiClient = 0;
    }
    self.audioUnit = nil;
}

@end
