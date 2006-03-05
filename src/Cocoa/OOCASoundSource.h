//	
//	OOCASoundSource.h
//	CoreAudio sound implementation for Oolite
//	
/*

Copyright © 2005, Jens Ayton
All rights reserved.

This work is licensed under the Creative Commons Attribution-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#import <Foundation/Foundation.h>
#import "vector.h"
#import "OOCASoundReferencePoint.h"

@class OOSound, OOCASoundChannel;


@interface OOSoundSource: NSObject
{
	OOCASoundChannel			*_channel;
	BOOL						_playing, _loop;
	uint8_t						_playCount;
}

// Positional audio attributes are ignored in this implementation
- (void)setPositional:(BOOL)inPositional;
- (void)setPosition:(Vector)inPosition;
- (void)setVelocity:(Vector)inVelocity;
- (void)setOrientation:(Vector)inOrientation;
- (void)setConeAngle:(float)inAngle;
- (void)setGainInsideCone:(float)inInside outsideCone:(float)inOutside;
- (void)positionRelativeTo:(OOSoundReferencePoint *)inPoint;

- (void)setLoop:(BOOL)inLoop;

- (void)playSound:(OOSound *)inSound;
// repeatCount lets a sound be played a fixed number of times. If looping is on, it will play the specified number of times after looping is switched off.
- (void)playSound:(OOSound *)inSound repeatCount:(uint8_t)inCount;
// -playOrRepeatSound will increment the repeat count if the sound is already playing.
- (void)playOrRepeatSound:(OOSound *)inSound;
- (void)stop;
- (BOOL)isPlaying;

@end
