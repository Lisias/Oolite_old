/*

OOCASoundMixer.m


OOCASound - Core Audio sound implementation for Oolite.
Copyright (C) 2005-2008 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOCASoundInternal.h"
#import "OOCASoundChannel.h"
#import "NSThreadOOExtensions.h"
#import "OOCASoundDebugMonitor.h"


static NSString * const kOOLogSoundInspetorNotLoaded			= @"sound.mixer.inspector.loadFailed";
static NSString * const kOOLogSoundMixerOutOfChannels			= @"sound.mixer.outOfChannels";
static NSString * const kOOLogSoundMixerReplacingBrokenChannel	= @"sound.mixer.replacingBrokenChannel";
static NSString * const kOOLogSoundMixerFailedToConnectChannel	= @"sound.mixer.failedToConnectChannel";


@interface OOSoundMixer (Private)

- (void)pushChannel:(OOSoundChannel *)inChannel;
- (OOSoundChannel *)popChannel;

@end


static OOSoundMixer *sSingleton = nil;


#ifndef NDEBUG
id <OOCASoundDebugMonitor> gOOCASoundDebugMonitor = nil;

void OOSoundRegisterDebugMonitor(id <OOCASoundDebugMonitor> monitor)
{
	if (monitor != gOOCASoundDebugMonitor)
	{
		gOOCASoundDebugMonitor = monitor;
		[monitor soundDebugMonitorNoteChannelMaxCount:kMixerGeneralChannels];
	}
}
#endif


@implementation OOSoundMixer

+ (id) sharedMixer
{
	if (nil == sSingleton)
	{
		sSingleton = [[self alloc] init];
	}
	return sSingleton;
}


- (id)init
{
	OSStatus					err = noErr;
	BOOL						OK;
	uint32_t					idx = 0, count = kMixerGeneralChannels;
	OOSoundChannel				*temp;
	ComponentDescription		desc;
	
	if (!gOOSoundSetUp)  [OOSound setUp];
	
	self = [super init];
	if (nil != self)
	{
		_listLock = [[NSLock alloc] init];
		[_listLock ooSetName:@"OOSoundMixer list lock"];
		OK = nil != _listLock;
		
		if (OK)
		{
			// Create audio graph
			err = NewAUGraph(&_graph);
			
			// Add output node
			desc.componentType = kAudioUnitType_Output;
			desc.componentSubType = kAudioUnitSubType_DefaultOutput;
			desc.componentManufacturer = kAudioUnitManufacturer_Apple;
			desc.componentFlags = 0;
			desc.componentFlagsMask = 0;
			if (!err)  err = OOAUGraphAddNode(_graph, &desc, &_outputNode);
			
			// Add mixer node
			desc.componentType = kAudioUnitType_Mixer;
			desc.componentSubType = kAudioUnitSubType_StereoMixer;
			desc.componentManufacturer = kAudioUnitManufacturer_Apple;
			desc.componentFlags = 0;
			desc.componentFlagsMask = 0;
			if (!err)  err = OOAUGraphAddNode(_graph, &desc, &_mixerNode);
			
			// Connect mixer to output
			if (!err)  err = AUGraphConnectNodeInput(_graph, _mixerNode, 0, _outputNode, 0);
			
			// Open the graph (turn it into concrete AUs) and extract mixer AU
			if (!err)  err = AUGraphOpen(_graph);
			if (!err)  err = OOAUGraphNodeInfo(_graph, _mixerNode, NULL, &_mixerUnit);
			
			if (!err)  [self setMasterVolume:1.0];
			
			if (err)  OK = NO;
		}
		
		if (OK)
		{
			// Allocate channels
			do
			{
				temp = [[OOSoundChannel alloc] initWithID:count auGraph:_graph];
				if (nil != temp)
				{
					_channels[idx++] = temp;
					[temp setNext:_freeList];
					_freeList = temp;
				}
			} while (--count);
			
			if (noErr != AUGraphInitialize(_graph)) OK = NO;
		}
		
		if (OK)
		{
			// Force CA to do any lazy setup.
			AUGraphStart(_graph);
			AUGraphStop(_graph);
		}
		
		if (!OK)
		{
			static bool onlyOnce;
			if (!onlyOnce)
			{
				onlyOnce = YES;
				OOLog(@"sound.mixer.init.failed", @"Failed to initialize sound mixer - error %i ('%.4s')", err, &err);
			}
			[super release];
			self = nil;
		}
	}
	sSingleton = self;
	
	return sSingleton;
}


- (void)dealloc
{
	uint32_t					idx;
	
	if (NULL != _graph)
	{
		AUGraphStop(_graph);
		AUGraphUninitialize(_graph);
		AUGraphClose(_graph);
		DisposeAUGraph(_graph);
	}
	for (idx = 0; idx != kMixerGeneralChannels; ++idx)
	{
		[_channels[idx] release];
	}
	
	[super dealloc];
}


- (void)channel:(OOSoundChannel *)inChannel didFinishPlayingSound:(OOSound *)inSound
{
	uint32_t				ID;
		
	[inSound decrementPlayingCount];
	
	if (![inChannel isOK])
	{
		OOLog(kOOLogSoundMixerReplacingBrokenChannel, @"Sound mixer: replacing broken channel %@.", inChannel);
		ID = [inChannel ID];
		[inChannel release];
		inChannel = [[OOSoundChannel alloc] initWithID:ID auGraph:_graph];
	}
	
	[self pushChannel:inChannel];
}


- (void)update
{
#ifndef NDEBUG
	if (gOOCASoundDebugMonitor != nil)
	{
		[gOOCASoundDebugMonitor soundDebugMonitorNoteActiveChannelCount:_activeChannels];
		[gOOCASoundDebugMonitor soundDebugMonitorNoteChannelUseMask:_playMask];
		
		Float32 load;
		if (!AUGraphGetCPULoad(_graph, &load))
		{
			[gOOCASoundDebugMonitor soundDebugMonitorNoteAUGraphLoad:load];
		}
	}
#endif
	
	
#if SUPPORT_SOUND_INSPECTOR
	uint32_t					i;
	Float32						load;
	
	for (i = 0; i != kMixerGeneralChannels && i != 32; ++i)
	{
		[[checkBoxes cellWithTag:i] setIntValue:_playMask & (1 << i)];
	}
	
	if (_maxChannels < _activeChannels)
	{
		_maxChannels = _activeChannels;
		[maxField setIntValue:_maxChannels];
	}
	[currentField setIntValue:_activeChannels];
	
	if (!AUGraphGetCPULoad(_graph, &load))
	{
		[loadBar setDoubleValue:load];
		[loadField setObjectValue:[NSString stringWithFormat:@"%.2g%%", load * 100.0]];
	}
#endif
}


- (void)setMasterVolume:(float)inVolume
{
	AudioUnitSetParameter(_mixerUnit, kStereoMixerParam_Volume, kAudioUnitScope_Output, 0, inVolume / kOOAudioSlop, 0);
}


- (OOSoundChannel *)popChannel
{
	OOSoundChannel				*result;
	uint32_t					ID;
	
	[_listLock lock];
	result = _freeList;
	_freeList = [result next];
	
	if (nil != result)
	{
		if (0 == _activeChannels++)
		{
			AUGraphStart(_graph);
		}
		
		ID = [result ID] - 1;
		if (ID < 32) _playMask |= (1 << ID);
	}
	[_listLock unlock];
	
	return result;
}


- (void)pushChannel:(OOSoundChannel *)inChannel
{
	uint32_t					ID;
	
	assert(nil != inChannel);
	
	[_listLock lock];
	
	[inChannel setNext:_freeList];
	_freeList = inChannel;
	
	if (0 == --_activeChannels)
	{
		AUGraphStop(_graph);
	}
	ID = [inChannel ID] - 1;
	if (ID < 32) _playMask &= ~(1 << ID);
	[_listLock unlock];
}


- (BOOL)connectChannel:(OOSoundChannel *)inChannel
{
	AUNode						node;
	OSStatus					err;
	
	assert(nil != inChannel);
	
	node = [inChannel auSubGraphNode];
	err = AUGraphConnectNodeInput(_graph, node, 0, _mixerNode, [inChannel ID]);
	if (!err) err = AUGraphUpdate(_graph, NULL);
	
	if (err) OOLog(kOOLogSoundMixerFailedToConnectChannel, @"Sound mixer: failed to connect channel %@, error = %@.", inChannel, AudioErrorNSString(err));
	
	return !err;
}


- (OSStatus)disconnectChannel:(OOSoundChannel *)inChannel
{
	OSStatus					err;
	
	assert(nil != inChannel);
	
	err = AUGraphDisconnectNodeInput(_graph, _mixerNode, [inChannel ID]);
	if (noErr == err) AUGraphUpdate(_graph, NULL);
	
	return err;
}

@end


@implementation OOSoundMixer (Singleton)

/*	Canonical singleton boilerplate.
	See Cocoa Fundamentals Guide: Creating a Singleton Instance.
	See also +sharedMixer above.
	
	NOTE: assumes single-threaded access.
*/

+ (id)allocWithZone:(NSZone *)inZone
{
	if (sSingleton == nil)
	{
		sSingleton = [super allocWithZone:inZone];
		return sSingleton;
	}
	return nil;
}


- (id)copyWithZone:(NSZone *)inZone
{
	return self;
}


- (id)retain
{
	return self;
}


- (OOUInteger)retainCount
{
	return UINT_MAX;
}


- (void)release
{}


- (id)autorelease
{
	return self;
}

@end
