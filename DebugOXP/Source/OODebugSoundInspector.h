/*

OODebugSoundInspector.h
olite Debug OXP


Copyright (C) 2010 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOCASoundDebugMonitor.h"


@interface OODebugSoundInspector: NSObject <OOCASoundDebugMonitor>
{
@private
	IBOutlet NSPanel				*_inspectorWindow;
	IBOutlet NSMatrix				*_checkBoxes;
	IBOutlet NSTextField			*_currentField;
	IBOutlet NSTextField			*_maxField;
	IBOutlet NSLevelIndicator		*_loadBar;
	
	OOUInteger						_channelCount;
	OOUInteger						_channelCountHighWaterMark;
	OOUInteger						_loadHighWaterMark;
}

- (IBAction) show:(id)sender;

@end