//
//  purefmDSPKernel.mm
//  purefm
//
//  Created by Paul Forgey on 4/6/20.
//  Copyright © 2020 Paul Forgey. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <CoreAudioKit/AUViewController.h>
#import "DSPKernel.hpp"
#import "BufferedAudioBus.hpp"
#import "purefmDSPKernel.hpp"
#import "purefmDSPKernelAdapter.h"
#import "State.h"

@implementation purefmDSPKernelAdapter {
    // C++ members need to be ivars; they would be copied on access if they were properties.
    purefmDSPKernel   _kernel;
    BufferedOutputBus _outputBus;
}

- (instancetype)init {

    if (self = [super init]) {
        AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:1];
        
        // Create the input and output busses.
        _outputBus.init(format, 8);
    }
    return self;
}

- (void)setPatch:(const patch_ptr::pointer &)patch {
    _kernel.setPatch(patch);
}

- (struct status const *)status {
    return _kernel.getStatus();
}

- (AUAudioUnitBus *)outputBus {
    return _outputBus.bus;
}

- (AUAudioFrameCount)maximumFramesToRender {
    return _kernel.maximumFramesToRender();
}

- (void)setMaximumFramesToRender:(AUAudioFrameCount)maximumFramesToRender {
    _kernel.setMaximumFramesToRender(maximumFramesToRender);
}

- (void)allocateRenderResources {
    _outputBus.allocateRenderResources(self.maximumFramesToRender);
    _kernel.init(self.outputBus.format.channelCount, self.outputBus.format.sampleRate);
    _kernel.reset();
}

- (void)deallocateRenderResources {
    _outputBus.deallocateRenderResources();
}

// MARK: AUAudioUnit (AUAudioUnitImplementation)

// Subclassers must provide a AUInternalRenderBlock (via a getter) to implement rendering.
- (AUInternalRenderBlock)internalRenderBlock {
    /*
     Capture in locals to avoid ObjC member lookups. If "self" is captured in
     render, we're doing it wrong.
     */
    // Specify captured objects are mutable.
    __block purefmDSPKernel *state = &_kernel;
    __block BufferedOutputBus *output = &_outputBus;

    return ^AUAudioUnitStatus(AudioUnitRenderActionFlags 				*actionFlags,
                              const AudioTimeStamp       				*timestamp,
                              AVAudioFrameCount           				frameCount,
                              NSInteger                   				outputBusNumber,
                              AudioBufferList            				*outputData,
                              const AURenderEvent        				*realtimeEventListHead,
                              AURenderPullInputBlock __unsafe_unretained pullInputBlock) {

        if (frameCount > state->maximumFramesToRender()) {
            return kAudioUnitErr_TooManyFramesToProcess;
        }

        /*
         Important:
         If the caller passed non-null output pointers (outputData->mBuffers[x].mData), use those.

         If the caller passed null output buffer pointers, process in memory owned by the Audio Unit
         and modify the (outputData->mBuffers[x].mData) pointers to point to this owned memory.
         The Audio Unit is responsible for preserving the validity of this memory until the next call to render,
         or deallocateRenderResources is called.

         If your algorithm cannot process in-place, you will need to preallocate an output buffer
         and use it here.

         See the description of the canProcessInPlace property.
         */

        // If passed null output buffer pointers, process in-place in the input buffer.
        output->prepareOutputBufferList(outputData, frameCount, false);

        state->setBuffers(nullptr, outputData);
        state->processWithEvents(timestamp, frameCount, realtimeEventListHead, nil /* MIDIOutEventBlock */);

        return noErr;
    };
}

@end
