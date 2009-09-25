/*

OOFlashEffectEntity.m


Oolite
Copyright (C) 2004-2009 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#import "OOFlashEffectEntity.h"
#import "Universe.h"
#import "PlayerEntity.h"
#import "OOColor.h"
#import "OOTexture.h"
#import "OOGraphicsResetManager.h"


#define kLaserFlashDuration			0.3f
#define kExplosionFlashDuration		0.4f
#define kGrowthRateFactor			150.0f	// if average flashSize is 80 then this is 12000
#define kMinExplosionGrowth			600.0f
#define kLaserFlashInitialSize		1.0f


static OOTexture *sFlashTexture = nil;


@interface OOFlashEffectEntity (Private)

// Designated initializer.
- (id) initWithPosition:(Vector)pos size:(float)size color:(OOColor *)color duration:(float)duration;

+ (void) setUpTexture;
+ (void) resetGraphicsState;

- (void) performUpdate:(OOTimeDelta)delta_t;

@end


@implementation OOFlashEffectEntity

- (id) initExplosionFlashWithPosition:(Vector)pos size:(float)size
{
	if ((self = [self initWithPosition:pos size:size color:[OOColor whiteColor] duration:kExplosionFlashDuration]))
	{
		_growthRate = fmaxf(_growthRate, kMinExplosionGrowth);
	}
	return self;
}


- (id) initLaserFlashWithPosition:(Vector)pos color:(OOColor *)color
{
	if ((self = [self initWithPosition:pos size:kLaserFlashInitialSize color:color duration:kLaserFlashDuration]))
	{
		
	}
	return self;
}

- (id) initWithPosition:(Vector)pos size:(float)size color:(OOColor *)color duration:(float)duration
{
	if ((self = [super initWithDiameter:size]))
	{
		[self setPosition:pos];
		_duration = duration;
		_growthRate = kGrowthRateFactor * size;
		[self setColor:color alpha:1.0f];
		assert([self collisionRadius] == 0 && [self energy] == 0 && magnitude([self velocity]) == 0);
	}
	return self;
}


- (void) update:(OOTimeDelta)delta_t
{
	[super update:delta_t];
	
	float tf = _duration * 0.667;
	float tf1 = _duration - tf;
	
	// Move as necessary.
	position = vector_add(position, vector_multiply_scalar(velocity, delta_t));
	
	// Scale up.
	_diameter += delta_t * _growthRate;
	
	// Fade in and out.
	OOTimeDelta lifeTime = [self timeElapsedSinceSpawn];
	_colorComponents[3] = (lifeTime < tf) ? (lifeTime / tf) : (_duration - lifeTime) / tf1;
	
	// Disappear as necessary.
	if (lifeTime > _duration)  [UNIVERSE removeEntity:self];
}


- (OOTexture *) texture
{
	if (sFlashTexture == nil)  [OOFlashEffectEntity	setUpTexture];
	return sFlashTexture;
}


+ (void) setUpTexture
{
	if (sFlashTexture == nil)
	{
		sFlashTexture = [[OOTexture textureWithName:@"oolite-particle-flash.png"
										   inFolder:@"Textures"
											options:kOOTextureMinFilterMipMap | kOOTextureMagFilterLinear | kOOTextureAlphaMask
										 anisotropy:kOOTextureDefaultAnisotropy
											lodBias:0.0] retain];
		[[OOGraphicsResetManager sharedManager] registerClient:(id<OOGraphicsResetClient>)[OOFlashEffectEntity class]];
	}
}


+ (void) resetGraphicsState
{
	[sFlashTexture release];
	sFlashTexture = nil;
}

@end
