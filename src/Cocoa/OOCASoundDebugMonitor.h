/*

OOCASoundDebugMonitor.h

Protocol for debugging information for sound system.


OOCASound - Core Audio sound implementation for Oolite.
Copyright (C) 2005-2010 Jens Ayton

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


#ifndef NDEBUG

@protocol OOCASoundDebugMonitor

- (void) soundDebugMonitorNoteChannelMaxCount:(OOUInteger)maxChannels;
- (void) soundDebugMonitorNoteActiveChannelCount:(OOUInteger)usedChannels;
- (void) soundDebugMonitorNoteChannelUseMask:(uintmax_t)channelMask;	// Bit mask for used channels; if usedChannels & (1 << 0), channel 0 is in use etc.

- (void) soundDebugMonitorNoteAUGraphLoad:(float)load;

@end


extern void OOSoundRegisterDebugMonitor(id <OOCASoundDebugMonitor> monitor);

#endif
