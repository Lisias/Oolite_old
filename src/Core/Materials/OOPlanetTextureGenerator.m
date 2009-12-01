/*

OOPlanetTextureGenerator.m

Generator for planet diffuse maps.


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


#define DEBUG_DUMP			(	1	&& !defined(NDEBUG))
#define DISABLE_SPECULAR	(	0	&& DEBUG_DUMP)	// No transparency in debug dump to make life easier.


#import "OOPlanetTextureGenerator.h"
#import "OOCollectionExtractors.h"
#import "OOColor.h"
#import "OOTexture.h"

#if DEBUG_DUMP
#import "Universe.h"
#import "MyOpenGLView.h"
#endif


enum
{
	kNoiseBufferSize		= 128
};


static FloatRGB FloatRGBFromDictColor(NSDictionary *dictionary, NSString *key);

static void FillNoiseBuffer(float *noiseBuffer, RANROTSeed seed);
static void AddNoise(float *buffer, unsigned width, unsigned height, unsigned octave, float scale, const float *noiseBuffer);

float QFactor(float *accbuffer, int x, int y, unsigned width, unsigned height, float polar_y_value, float impress, float bias);

static FloatRGBA PlanetMix(float q, float impress, float seaBias, FloatRGB landColor, FloatRGB seaColor, FloatRGB paleLandColor, FloatRGB paleSeaColor);


@implementation OOPlanetTextureGenerator

- (id) initWithPlanetInfo:(NSDictionary *)planetInfo
{
	if ((self = [super init]))
	{
		_landFraction = OOClamp_0_1_f([planetInfo oo_floatForKey:@"land_fraction" defaultValue:0.3]);
		_landColor = FloatRGBFromDictColor(planetInfo, @"land_color");
		_seaColor = FloatRGBFromDictColor(planetInfo, @"sea_color");
		_polarLandColor = FloatRGBFromDictColor(planetInfo, @"polar_land_color");
		_polarSeaColor = FloatRGBFromDictColor(planetInfo, @"polar_sea_color");
		[[planetInfo objectForKey:@"noise_map_seed"] getValue:&_seed];
		
		_width = 512;
		_height = 512;
	}
	
	return self;
}


+ (OOTexture *) planetTextureWithInfo:(NSDictionary *)planetInfo
{
	OOTexture *result = nil;
	OOPlanetTextureGenerator *generator = [[self alloc] initWithPlanetInfo:planetInfo];
	if (generator != nil)
	{
		result = [OOTexture textureWithGenerator:generator];
		[generator release];
	}
	
	return result;
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"seed: %u,%u", _seed.high, _seed.low];
}


- (uint32_t) textureOptions
{
	return [super textureOptions] | kOOTextureRepeatS | kOOTextureNoShrink;
}


- (NSString *) cacheKey
{
	return [NSString stringWithFormat:@"OOPlanetTextureGenerator-base\n\n%u,%u/%g/%u,%u/%f,%f,%f/%f,%f,%f/%f,%f,%f/%f,%f,%f",
			_width, _height, _landFraction, _seed.high, _seed.low,
			_landColor.r, _landColor.g, _landColor.b,
			_seaColor.r, _seaColor.g, _seaColor.b,
			_polarLandColor.r, _polarLandColor.g, _polarLandColor.b,
			_polarSeaColor.r, _polarSeaColor.g, _polarSeaColor.b];
}


- (BOOL)getResult:(void **)outData
		   format:(OOTextureDataFormat *)outFormat
			width:(uint32_t *)outWidth
		   height:(uint32_t *)outHeight
{
	BOOL waiting = NO;
	if (![self isReady])
	{
		waiting = true;
		OOLog(@"planetTex.temp", @"Waiting for generator %@", self);
	}
	
	BOOL result = [super getResult:outData format:outFormat width:outWidth height:outHeight];
	
	if (waiting)
	{
		OOLog(@"planetTex.temp", @"%s generator %@", result ? "Dequeued" : "Failed to dequeue", self);
	}
	else
	{
		OOLog(@"planetTex.temp", @"%s generator %@ without waiting.", result ? "Dequeued" : "Failed to dequeue", self);
	}
	
	return result;
}


- (void) loadTexture
{
	OOLog(@"planetTex.temp", @"Started generator %@", self);
	
	BOOL success = NO;
	
	uint8_t		*buffer = NULL, *px;
	float		*accBuffer = NULL;
	float		*randomBuffer = NULL;
	
	width = _width;
	height = _height;
	float seaBias = _landFraction - 1.0;
	
	buffer = malloc(4 * width * height);
	if (buffer == NULL)  goto END;
	px = buffer;
	
	accBuffer = calloc(sizeof (float), width * height);
	if (accBuffer == NULL)  goto END;
	
	randomBuffer = calloc(sizeof (float), kNoiseBufferSize * kNoiseBufferSize);
	if (randomBuffer == NULL)  goto END;
	FillNoiseBuffer(randomBuffer, _seed);
	
	// Generate basic Perlin noise.
	unsigned octave = 8;
	float scale = 0.5f;
	while (octave < height)
	{
		AddNoise(accBuffer, width, height, octave, scale, randomBuffer);
		octave *= 2;
		scale *= 0.5;
	}
	
	float impress = 1.0f;
	float poleValue = (impress + seaBias > 0.5f) ? 0.5f * (impress + seaBias) : 0.0f;
	
	unsigned x, y;
	for (y = 0; y < height; y++)
	{
		for (x = 0; x < width; x++)
		{
			float q = QFactor(accBuffer, x, y, width, height, poleValue, impress, seaBias);
			
			// FIXME: is it worth calculating this per point in a separate pass instead of calculating each value five times?
			float yN = QFactor(accBuffer, x, y - 1, width, height, poleValue, impress, seaBias);
			float yS = QFactor(accBuffer, x, y + 1, width, height, poleValue, impress, seaBias);
			float yW = QFactor(accBuffer, x - 1, y, width, height, poleValue, impress, seaBias);
			float yE = QFactor(accBuffer, x + 1, y, width, height, poleValue, impress, seaBias);
			
			Vector norm = vector_normal(make_vector(24.0f * (yW - yE), 24.0f * (yS - yN), 2.0f));
			
			FloatRGBA color = PlanetMix(q, impress, seaBias, _landColor, _seaColor, _polarLandColor, _polarSeaColor);
			
			/*	Terrain shading
				was: _powf(norm.z, 3.2). Changing exponent to 3 makes very
				little difference, other than being faster.
			*/
			GLfloat shade = norm.z * norm.z * norm.z;
			
			/*	We don't want terrain shading in the sea. The alpha channel
				of color is a measure of "seaishness" for the specular map,
				so we can recycle that to avoid branching.
			*/
			shade = color.a + (1.0f - color.a) * shade;
			
			*px++ = 255 * color.r * shade;
			*px++ = 255 * color.g * shade;
			*px++ = 255 * color.b * shade;
#if DISABLE_SPECULAR
			*px++ = 255;
#else
			*px++ = 255 * color.a;
#endif
		}
	}
	success = YES;
	format = kOOTextureDataRGBA;
	
END:
	free(accBuffer);
	free(randomBuffer);
	if (success)  data = buffer;
	else  free(buffer);
	
	OOLog(@"planetTex.temp", @"Completed generator %@ %@successfully", self, success ? @"" : @"un");
	
#if DEBUG_DUMP
	if (success)
	{
		[[UNIVERSE gameView] dumpRGBAToFileNamed:[NSString stringWithFormat:@"planet-%u-%u-new", _seed.high, _seed.low]
										   bytes:buffer
										   width:width
										  height:height
										rowBytes:width * 4];
	}
#endif
}

@end


static FloatRGB Blend(float fraction, FloatRGB a, FloatRGB b)
{
	float prime = 1.0f - fraction;
	
	return (FloatRGB)
	{
		fraction * a.r + prime * b.r,
		fraction * a.g + prime * b.g,
		fraction * a.b + prime * b.b,
	};
}


static FloatRGBA PlanetMix(float q, float impress, float seaBias, FloatRGB landColor, FloatRGB seaColor, FloatRGB paleLandColor, FloatRGB paleSeaColor)
{
	float maxq = impress + seaBias;
	
	float hi = 0.66667 * maxq;
	float oh = 1.0 / hi;
	float ih = 1.0 / (1.0 - hi);
#define RECIP_COASTLINE_PORTION		(150.0f)
#define COASTLINE_PORTION			(1.0f / RECIP_COASTLINE_PORTION)
	
	const FloatRGB white = { 1.0f, 1.0f, 1.0f };
	FloatRGB result;
	float specular = 0.0f;
	
	// Offset to reduce coastline-lowering effect of r2823 coastline smoothing improvement.
	q -= COASTLINE_PORTION;
	
	if (q <= 0.0f)
	{
		if (q > -COASTLINE_PORTION)
		{
			// Coastal waters
			result = Blend(-q * RECIP_COASTLINE_PORTION, seaColor, paleSeaColor);
			specular = -(q * RECIP_COASTLINE_PORTION);
		}
		else
		{
			// Open sea
			result = seaColor;
			specular = 1.0;
		}
	}
	else if (q > 1.0)
	{
		result = white;
	}
	else if (q < COASTLINE_PORTION)
	{
		// Coastline
		result = Blend(q * RECIP_COASTLINE_PORTION, landColor, paleSeaColor);
	}
	else if (q > hi)
	{
		result = Blend((q - hi) * ih, white, paleLandColor);	// Snow-capped peaks
	}
	else
	{
		result = Blend((hi - q) * oh, landColor, paleLandColor);
	}
	
	return (FloatRGBA){ result.r, result.g, result.b, specular };
}


static FloatRGB FloatRGBFromDictColor(NSDictionary *dictionary, NSString *key)
{
	OOColor *color = [dictionary objectForKey:key];
	NSCAssert1([color isKindOfClass:[OOColor class]], @"Expected OOColor, got %@", [color class]);
	
	return (FloatRGB){ [color redComponent], [color greenComponent], [color blueComponent] };
}


static void FillNoiseBuffer(float *noiseBuffer, RANROTSeed seed)
{
	NSCParameterAssert(noiseBuffer != NULL);
	
	unsigned i;
	for (i = 0; i < kNoiseBufferSize * kNoiseBufferSize; i++)
	{
		noiseBuffer[i] = randfWithSeed(&seed);
	}
}


static float lerp(float v0, float v1, float q)
{
	return v0 + q * (v1 - v0);
}


static void AddNoise(float *buffer, unsigned width, unsigned height, unsigned octave, float scale, const float *noiseBuffer)
{
	unsigned x, y;
	float r = (float)height / (float)octave;
	
	for (y = 0; y < height; y++)
	{
		for (x = 0; x < width; x++)
		{
			// FIXME: do this with less float/int conversions.
			int ix = floor( (float)x / r);
			int jx = (ix + 1) % octave;
			int iy = floor( (float)y / r);
			int jy = (iy + 1) % octave;
			float qx = x / r - ix;
			float qy = y / r - iy;
			ix &= 127;
			iy &= 127;
			jx &= 127;
			jy &= 127;
			float rix = lerp( noiseBuffer[iy * kNoiseBufferSize + ix], noiseBuffer[iy * kNoiseBufferSize + jx], qx);
			float rjx = lerp( noiseBuffer[jy * kNoiseBufferSize + ix], noiseBuffer[jy * kNoiseBufferSize + jx], qx);
			float rfinal = scale * lerp( rix, rjx, qy);
			
			buffer[y * width + x] += rfinal;
		}
	}
}


float QFactor(float *accbuffer, int x, int y, unsigned width, unsigned height, float polar_y_value, float impress, float bias)
{
	x = (x + width) % width;
	// FIXME: wrong wrapping mode for Y, should flip to other hemisphere.
	y = (y + height) % height;
	
	float q = accbuffer[y * width + x];	// 0.0 -> 1.0
	
	q = q * impress + bias;
	
	// Polar Y smooth. FIXME: float/int conversions.
	float polar_y = (2.0f * y - width) / (float) width;
	polar_y *= polar_y;
	q = q * (1.0 - polar_y) + polar_y * polar_y_value;
	
	return q;
}
