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
#define DEBUG_DUMP_RAW		(	0	&& DEBUG_DUMP)


#import "OOPlanetTextureGenerator.h"
#import "OOCollectionExtractors.h"

#ifndef TEXGEN_TEST_RIG
#import "OOColor.h"
#import "OOTexture.h"
#import "Universe.h"
#endif

#if DEBUG_DUMP
#import "MyOpenGLView.h"
#endif


#define FREE(x) do { if (0) { void *x__ = x; x__ = x__; } /* Preceeding is for type checking only. */ void **x_ = (void **)&(x); free(*x_); *x_ = NULL; } while (0)


#define PLANET_TEXTURE_OPTIONS	(kOOTextureMinFilterLinear | kOOTextureMagFilterLinear | kOOTextureRepeatS | kOOTextureNoShrink)


enum
{
	kRandomBufferSize		= 128
};


@interface OOPlanetTextureGenerator (Private)

- (NSString *) cacheKeyForType:(NSString *)type;
- (OOTextureGenerator *) normalMapGenerator;	// Must be called before generator is enqueued for rendering.
- (OOTextureGenerator *) atmosphereGenerator;	// Must be called before generator is enqueued for rendering.

#if DEBUG_DUMP_RAW
- (void) dumpNoiseBuffer:(float *)noise;
#endif

@end


/*	The planet generator actually generates two textures when shaders are
	active, but the texture loader interface assumes we only load/generate
	one texture per loader. Rather than complicate that, we use a mock
	generator for the normal/light map.
*/
@interface OOPlanetNormalMapGenerator: OOTextureGenerator
{
@private
	NSString				*_cacheKey;
	RANROTSeed				_seed;
}

- (id) initWithCacheKey:(NSString *)cacheKey seed:(RANROTSeed)seed;

- (void) completeWithData:(void *)data width:(unsigned)width height:(unsigned)height;

@end


//	Doing the same as above for the atmosphere.
@interface OOPlanetAtmosphereGenerator: OOTextureGenerator
{
@private
	NSString				*_cacheKey;
	RANROTSeed				_seed;
}

- (id) initWithCacheKey:(NSString *)cacheKey seed:(RANROTSeed)seed;

- (void) completeWithData:(void *)data width:(unsigned)width height:(unsigned)height;

@end


static FloatRGB FloatRGBFromDictColor(NSDictionary *dictionary, NSString *key);

static BOOL FillFBMBuffer(OOPlanetTextureGeneratorInfo *info);
static void FillRandomBuffer(float *randomBuffer, RANROTSeed seed);
static void AddNoise(OOPlanetTextureGeneratorInfo *info, float *randomBuffer, float octave, unsigned octaveMask, float scale, float *qxBuffer, int *ixBuffer);

static float QFactor(float *accbuffer, int x, int y, unsigned width, float polar_y_value, float bias, float polar_y);
static float GetQ(float *qbuffer, unsigned x, unsigned y, unsigned width, unsigned height, unsigned widthMask, unsigned heightMask);

static FloatRGB Blend(float fraction, FloatRGB a, FloatRGB b);
static void SetMixConstants(OOPlanetTextureGeneratorInfo *info, float temperatureFraction);
static FloatRGBA CloudMix(OOPlanetTextureGeneratorInfo *info, float q, float nearPole);
static FloatRGBA PlanetMix(OOPlanetTextureGeneratorInfo *info, float q, float nearPole);


enum
{
	kPlanetAspectRatio			= 1,		// Ideally, aspect ratio would be 2:1 - keeping it as 1:1 for now - Kaks 20091211
	kPlanetScaleOffset			= 8 - kPlanetAspectRatio,
	
	kPlanetScale256x256			= 1,
	kPlanetScale512x512,
	kPlanetScale1024x1024,
	kPlanetScale2048x2048,
	kPlanetScale4096x4096,
	
	kPlanetScaleReducedDetail	= kPlanetScale512x512,
	kPlanetScaleFullDetail		= kPlanetScale1024x1024
};


@implementation OOPlanetTextureGenerator

- (id) initWithPlanetInfo:(NSDictionary *)planetInfo
{
	if ((self = [super init]))
	{
		_info.landFraction = OOClamp_0_1_f([planetInfo oo_floatForKey:@"land_fraction" defaultValue:0.3]);
		_info.landColor = FloatRGBFromDictColor(planetInfo, @"land_color");
		_info.seaColor = FloatRGBFromDictColor(planetInfo, @"sea_color");
		_info.paleLandColor = FloatRGBFromDictColor(planetInfo, @"polar_land_color");
		_info.polarSeaColor = FloatRGBFromDictColor(planetInfo, @"polar_sea_color");
		[[planetInfo objectForKey:@"noise_map_seed"] getValue:&_info.seed];
		
		if ([planetInfo objectForKey:@"cloud_alpha"])
		{
			// we have an atmosphere:
			_info.cloudAlpha = [planetInfo oo_floatForKey:@"cloud_alpha" defaultValue:1.0f];
			_info.cloudFraction = OOClamp_0_1_f([planetInfo oo_floatForKey:@"cloud_fraction" defaultValue:0.3]);
			_info.airColor = FloatRGBFromDictColor(planetInfo, @"air_color");
			_info.cloudColor = FloatRGBFromDictColor(planetInfo, @"cloud_color");
			_info.paleAirColor = FloatRGBFromDictColor(planetInfo, @"polar_air_color");
			_info.paleCloudColor = FloatRGBFromDictColor(planetInfo, @"polar_cloud_color");
		}
		
#ifndef TEXGEN_TEST_RIG
		if ([UNIVERSE reducedDetail])
		{
			_planetScale = kPlanetScaleReducedDetail;
		}
		else
		{
			_planetScale = kPlanetScaleFullDetail;
		}
#else
		_planetScale = kPlanetScale4096x4096;
#endif
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


+ (BOOL) generatePlanetTexture:(OOTexture **)texture andAtmosphere:(OOTexture **)atmosphere withInfo:(NSDictionary *)planetInfo
{
	NSParameterAssert(texture != NULL);
	
	OOPlanetTextureGenerator *diffuseGen = [[[self alloc] initWithPlanetInfo:planetInfo] autorelease];
	if (diffuseGen == nil)  return NO;
	
	OOTextureGenerator *atmoGen = [diffuseGen atmosphereGenerator];
	if (atmoGen == nil)  return NO;
	
	*atmosphere = [OOTexture textureWithGenerator:atmoGen];
	if (*atmosphere == nil)  return NO;
	
	*texture = [OOTexture textureWithGenerator:diffuseGen];
	
	return *texture != nil;
}


+ (BOOL) generatePlanetTexture:(OOTexture **)texture secondaryTexture:(OOTexture **)secondaryTexture withInfo:(NSDictionary *)planetInfo
{
	NSParameterAssert(texture != NULL);
	
	OOPlanetTextureGenerator *diffuseGen = [[[self alloc] initWithPlanetInfo:planetInfo] autorelease];
	if (diffuseGen == nil)  return NO;
	
	if (secondaryTexture != NULL)
	{
		OOTextureGenerator *normalGen = [diffuseGen normalMapGenerator];
		if (normalGen == nil)  return NO;
		
		*secondaryTexture = [OOTexture textureWithGenerator:normalGen];
		if (*secondaryTexture == nil)  return NO;
	}
	
	*texture = [OOTexture textureWithGenerator:diffuseGen];
	
	return *texture != nil;
}


+ (BOOL) generatePlanetTexture:(OOTexture **)texture secondaryTexture:(OOTexture **)secondaryTexture andAtmosphere:(OOTexture **)atmosphere withInfo:(NSDictionary *)planetInfo
{
	NSParameterAssert(texture != NULL);
	
	OOPlanetTextureGenerator *diffuseGen = [[[self alloc] initWithPlanetInfo:planetInfo] autorelease];
	if (diffuseGen == nil)  return NO;
	
	if (secondaryTexture != NULL)
	{
		OOTextureGenerator *normalGen = [diffuseGen normalMapGenerator];
		if (normalGen == nil)  return NO;
		
		*secondaryTexture = [OOTexture textureWithGenerator:normalGen];
		if (*secondaryTexture == nil)  return NO;
	}
	
	OOTextureGenerator *atmoGen = [diffuseGen atmosphereGenerator];
	if (atmoGen == nil)  return NO;
	
	*atmosphere = [OOTexture textureWithGenerator:atmoGen];
	if (*atmosphere == nil)
	{
		*secondaryTexture = nil;
		return NO;
	}
	
	*texture = [OOTexture textureWithGenerator:diffuseGen];
	
	return *texture != nil;
}


- (void) dealloc
{
	DESTROY(_nMapGenerator);
	DESTROY(_atmoGenerator);
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"seed: %u,%u land: %g", _info.seed.high, _info.seed.low, _info.landFraction];
}


- (uint32_t) textureOptions
{
	return PLANET_TEXTURE_OPTIONS;
}


- (NSString *) cacheKey
{
	NSString *type =(_nMapGenerator == nil) ? @"diffuse-baked" : @"diffuse-raw";
	if (_atmoGenerator != nil) type = [NSString stringWithFormat:@"%@-atmo", type];
	return [self cacheKeyForType:type];
}


- (NSString *) cacheKeyForType:(NSString *)type
{
	return [NSString stringWithFormat:@"OOPlanetTextureGenerator-%@@%u\n%u,%u/%g/%u,%u/%f,%f,%f/%f,%f,%f/%f,%f,%f/%f,%f,%f",
			type, _planetScale,
			_info.width, _info.height, _info.landFraction, _info.seed.high, _info.seed.low,
			_info.landColor.r, _info.landColor.g, _info.landColor.b,
			_info.seaColor.r, _info.seaColor.g, _info.seaColor.b,
			_info.paleLandColor.r, _info.paleLandColor.g, _info.paleLandColor.b,
			_info.polarSeaColor.r, _info.polarSeaColor.g, _info.polarSeaColor.b];
}


- (OOTextureGenerator *) normalMapGenerator
{
	if (_nMapGenerator == nil)
	{
		_nMapGenerator = [[OOPlanetNormalMapGenerator alloc] initWithCacheKey:[self cacheKeyForType:@"normal"] seed:_info.seed];
	}
	return _nMapGenerator;
}


- (OOTextureGenerator *) atmosphereGenerator
{
	if (_atmoGenerator == nil)
	{
		_atmoGenerator = [[OOPlanetAtmosphereGenerator alloc] initWithCacheKey:[self cacheKeyForType:@"atmo"] seed:_info.seed];
	}
	return _atmoGenerator;
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
		OOLog(@"planetTex.temp", @"%s generator %@", "Waiting for", self);
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
	BOOL generateNormalMap = (_nMapGenerator != nil);
	BOOL generateAtmosphere = (_atmoGenerator != nil);
	
	uint8_t		*buffer = NULL, *px = NULL;
	uint8_t		*nBuffer = NULL, *npx = NULL;
	uint8_t		*aBuffer = NULL, *apx = NULL;
	float		*randomBuffer = NULL;
	
	height = _info.height = 1 << (_planetScale + kPlanetScaleOffset);
	width = _info.width = height * kPlanetAspectRatio;
	
#define FAIL_IF(cond)  do { if (EXPECT_NOT(cond))  goto END; } while (0)
#define FAIL_IF_NULL(x)  FAIL_IF((x) == NULL)
	
	buffer = malloc(4 * width * height);
	FAIL_IF_NULL(buffer);
	px = buffer;
	
	if (generateNormalMap)
	{
		nBuffer = malloc(4 * width * height);
		FAIL_IF_NULL(nBuffer);
		npx = nBuffer;
	}
	
	if (generateAtmosphere)
	{
		aBuffer = malloc(4 * width * height);
		FAIL_IF_NULL(aBuffer);
		apx = aBuffer;
	}
	
	FAIL_IF(!FillFBMBuffer(&_info));
	
	//TODO: sort out CloudMix
	float paleClouds = (_info.cloudFraction * _info.fbmBuffer[0] < 1.0f - _info.cloudFraction) ? 0.0f : 1.0f;
	float poleValue = (_info.landFraction > 0.5f) ? 0.5f * _info.landFraction : 0.0f;
	float seaBias = _info.landFraction - 1.0f;
	
	/*	The system key 'polar_sea_colour' was used as 'paleSeaColour'.
		The generated texture had presumably iceberg covered shallows.
		paleSeaColour is now a pale blend of sea and land colours, giving
		a softer transition colour for the shallows - those have also been
		widened from 1.73 to smooth out the coast / deep sea boundary.
		-- Kaks
	*/
	_info.paleSeaColor = Blend(0.45f, _info.polarSeaColor, Blend(0.7f, _info.seaColor, _info.landColor));
	float normalScale = 1 << _planetScale;
	if (!generateNormalMap)  normalScale *= 3.0f;
	
	unsigned x, y;
	FloatRGBA color;
	FloatRGBA cloudColor = (FloatRGBA){_info.cloudColor.r, _info.cloudColor.g, _info.cloudColor.b, 1.0f};
	Vector norm;
	float q, yN, yS, yW, yE, nearPole;
	GLfloat shade;
	float rHeight = 1.0f / height;
	float fy, fHeight = height;
	// The second parameter is the temperature fraction. Most favourable: 1.0f,  little ice. Most unfavourable: 0.0f, frozen planet. TODO: make it dependent on ranrot / planetinfo key...
	SetMixConstants(&_info, 0.95f);	// no need to recalculate them inside each loop!
	
	// first pass, calculate q.
	_info.qBuffer = malloc(width * height * sizeof (float));
	FAIL_IF_NULL(_info.qBuffer);
	
	for (y = 0, fy = 0.0f; y < height; y++, fy++)
	{
		nearPole = (2.0f * fy - fHeight) * rHeight;
		nearPole *= nearPole;
		
		for (x = 0; x < width; x++)
		{
			_info.qBuffer[y * width + x] = QFactor(_info.fbmBuffer, x, y, width, poleValue, seaBias, nearPole);
		}
	}
	
	// second pass, use q.
	float cloudAlpha = _info.cloudAlpha;
	float cloudFraction = _info.cloudFraction;
	unsigned widthMask = width - 1;
	unsigned heightMask = height - 1;
	
	for (y = 0, fy = 0.0f; y < height; y++, fy++)
	{
		nearPole = (2.0f * fy - fHeight) * rHeight;
		nearPole *= nearPole;
		
		for (x = 0; x < width; x++)
		{
			q = _info.qBuffer[y * width + x];	// no need to use GetQ, x and y are always within bounds.
			yN = GetQ(_info.qBuffer, x, y - 1, width, height, widthMask, heightMask);	// recalculates x & y if they go out of bounds.
			yS = GetQ(_info.qBuffer, x, y + 1, width, height, widthMask, heightMask);
			yW = GetQ(_info.qBuffer, x - 1, y, width, height, widthMask, heightMask);
			yE = GetQ(_info.qBuffer, x + 1, y, width, height, widthMask, heightMask);
			
			color = PlanetMix(&_info, q, nearPole);
			
			norm = vector_normal(make_vector(normalScale * (yW - yE), normalScale * (yS - yN), 1.0f));
			if (generateNormalMap)
			{
				shade = 1.0f;
				
				// Flatten in the sea.
				norm = OOVectorInterpolate(norm, kBasisZVector, color.a);
				
				// Put norm in normal map, scaled from [-1..1] to [0..255].
				*npx++ = 127.5f * (norm.y + 1.0f);
				*npx++ = 127.5f * (-norm.x + 1.0f);
				*npx++ = 127.5f * (norm.z + 1.0f);
				
				*npx++ = 255.0f * color.a;	// Specular channel.
			}
			else
			{
				//	Terrain shading - lambertian lighting from straight above.
				shade = norm.z;
				
				/*	We don't want terrain shading in the sea. The alpha channel
					of color is a measure of "seaishness" for the specular map,
					so we can recycle that to avoid branching.
					-- Ahruman
				*/
				shade += color.a - color.a * shade;	// equivalent to - but slightly faster than - previous implementation.
			}
			
			*px++ = 255.0f * color.r * shade;
			*px++ = 255.0f * color.g * shade;
			*px++ = 255.0f * color.b * shade;
			
			*px++ = 0;	// FIXME: light map goes here.
			
			if (generateAtmosphere)
			{
				//TODO: sort out CloudMix
				if (NO) 
				{
					q = QFactor(_info.fbmBuffer, x, y, width, paleClouds, cloudFraction, nearPole);
					color = CloudMix(&_info, q, nearPole);
				}
				else
				{
					q = _info.fbmBuffer[y * width + x];
					q *= q;
					color = cloudColor;
				}
				*apx++ = 255.0f * color.r;
				*apx++ = 255.0f * color.g;
				*apx++ = 255.0f * color.b;
				*apx++ = 255.0f * cloudAlpha * q;
			}
		}
	}
	
	success = YES;
	format = kOOTextureDataRGBA;
	
END:
	FREE(_info.fbmBuffer);
	FREE(_info.qBuffer);
	FREE(randomBuffer);
	if (success)
	{
		data = buffer;
		if (generateNormalMap) [_nMapGenerator completeWithData:nBuffer width:width height:height];
		if (generateAtmosphere) [_atmoGenerator completeWithData:aBuffer width:width height:height];
	}
	else
	{
		FREE(buffer);
		FREE(nBuffer);
		FREE(aBuffer);
	}
	DESTROY(_nMapGenerator);
	DESTROY(_atmoGenerator);
	
	OOLog(@"planetTex.temp", @"Completed generator %@ %@successfully", self, success ? @"" : @"un");
	
#if DEBUG_DUMP
	if (success)
	{
		NSString *diffuseName = [NSString stringWithFormat:@"planet-%u-%u-diffuse-new", _info.seed.high, _info.seed.low];
		NSString *lightsName = [NSString stringWithFormat:@"planet-%u-%u-lights-new", _info.seed.high, _info.seed.low];
		
		[[UNIVERSE gameView] dumpRGBAToRGBFileNamed:diffuseName
								   andGrayFileNamed:lightsName
											  bytes:buffer
											  width:width
											 height:height
										   rowBytes:width * 4];
	}
#endif
}


#if DEBUG_DUMP_RAW

- (void) dumpNoiseBuffer:(float *)noise
{
	NSString *noiseName = [NSString stringWithFormat:@"planet-%u-%u-noise-new", _seed.high, _seed.low];
	
	uint8_t *noiseMap = malloc(width * height);
	unsigned x, y;
	for (y = 0; y < height; y++)
	{
		for (x = 0; x < width; x++)
		{
			noiseMap[y * width + x] = 255.0f * noise[y * width + x];
		}
	}
	
	[[UNIVERSE gameView] dumpGrayToFileNamed:noiseName
									   bytes:noiseMap
									   width:width
									  height:height
									rowBytes:width];
	FREE(noiseMap);
}

#endif

@end


OOINLINE float Lerp(float v0, float v1, float fraction)
{
	// Linear interpolation - equivalent to v0 * (1.0f - fraction) + v1 * fraction.
	return v0 + fraction * (v1 - v0);
}


static FloatRGB Blend(float fraction, FloatRGB a, FloatRGB b)
{
	return (FloatRGB)
	{
		Lerp(b.r, a.r, fraction),
		Lerp(b.g, a.g, fraction),
		Lerp(b.b, a.b, fraction)
	};
}


static FloatRGBA CloudMix(OOPlanetTextureGeneratorInfo *info, float q, float nearPole)
{
#define AIR_ALPHA				(0.05f)
#define CLOUD_ALPHA				(0.50f)
#define POLAR_AIR_ALPHA			(0.34f)
#define POLAR_CLOUD_ALPHA		(0.75f)

#define POLAR_BOUNDARY			(0.66f)
#define RECIP_CLOUD_BOUNDARY	(200.0f)
#define CLOUD_BOUNDARY			(1.0f / RECIP_CLOUD_BOUNDARY)

	FloatRGB result = info->cloudColor;
	float alpha = info->cloudAlpha;
	float portion = 0.0f;
	
	q -= CLOUD_BOUNDARY;
	
	if (nearPole > POLAR_BOUNDARY)
	{
		portion = nearPole > POLAR_BOUNDARY + 0.06f ? 1.0f : 0.4f + (nearPole - POLAR_BOUNDARY) * 10.0f;	// x * 10 == ((x / 0.06) * 0.6
		
		if (q <= 0.0f)
		{
			alpha *= Lerp(POLAR_CLOUD_ALPHA, CLOUD_ALPHA, portion);
			if (q >= -CLOUD_BOUNDARY)
			{
				portion = -q * 0.5f * RECIP_CLOUD_BOUNDARY + 0.5f;
				result = Blend(portion, info->paleCloudColor, info->paleAirColor);
			}
			else
			{
				result = info->paleCloudColor;
			}
		}
		else 
		{
			alpha *= portion * POLAR_AIR_ALPHA;
			if (q < CLOUD_BOUNDARY)
			{
				result = Blend(q * RECIP_CLOUD_BOUNDARY, info->paleAirColor, info->paleCloudColor);
			}
			else
			{
				result = info->paleAirColor;
			}
		}
	}
	else
	{
		if (q <= 0.0f)
		{
			if (q >= -CLOUD_BOUNDARY){
				portion = -q * 0.5f * RECIP_CLOUD_BOUNDARY + 0.5f;
				alpha *=  portion * CLOUD_ALPHA;
				result = Blend(portion, info->cloudColor, info->airColor);
			}
			else
			{
				result = info->cloudColor;
				alpha *= CLOUD_ALPHA;
			}
		}
		else if (q < CLOUD_BOUNDARY)
		{
			alpha *= AIR_ALPHA;
			result = Blend(q * RECIP_CLOUD_BOUNDARY, info->airColor, info->cloudColor);
		}
		else if (q >= CLOUD_BOUNDARY)
		{
			alpha *= AIR_ALPHA;
			result = info->airColor;
		}
	}

	return (FloatRGBA){ result.r, result.g, result.b, alpha};
}


static FloatRGBA PlanetMix(OOPlanetTextureGeneratorInfo *info, float q, float nearPole)
{
	// (q > mix_polarCap + mix_polarCap - nearPole) ==  ((nearPole + q) / 2 > mix_polarCap)
	float phi = info->mix_polarCap + info->mix_polarCap - nearPole;
	
#define RECIP_COASTLINE_PORTION		(160.0f)
#define COASTLINE_PORTION			(1.0f / RECIP_COASTLINE_PORTION)
#define SHALLOWS					(2.0f * COASTLINE_PORTION)	// increased shallows area.
#define RECIP_SHALLOWS				(1.0f / SHALLOWS)
	
	const FloatRGB white = { 1.0f, 1.0f, 1.0f };
	FloatRGB diffuse;
	// windows specular 'fix': 0 was showing pitch black continents when on the dark side, 0.01 shows the same shading as on macs.
	// TODO: a less hack-like fix.
	float specular = 0.01f;
	
	if (q <= 0.0f)
	{
		// Below datum - sea.
		if (q > -SHALLOWS)
		{
			// Coastal waters.
			diffuse = Blend(-q * RECIP_SHALLOWS, info->seaColor, info->paleSeaColor);
		}
		else
		{
			// Open sea.
			diffuse = info->seaColor;
		}
		specular = 1.0f;
	}
	else if (q < COASTLINE_PORTION)
	{
		// Coastline.
		specular = q * RECIP_COASTLINE_PORTION;
		diffuse = Blend(specular, info->landColor, info->paleSeaColor);
		specular = 1.0f - specular;
	}
	else if (q > 1.0f)
	{
		// High up - snow-capped peaks. -- Question: does q ever get higher than 1.0 ? --Kaks 20091228
		diffuse = white;
	}
	else if (q > info->mix_hi)
	{
		diffuse = Blend((q - info->mix_hi) * info->mix_ih, white, info->paleLandColor);	// Snowline.
	}
	else
	{
		// Normal land.
		diffuse = Blend((info->mix_hi - q) * info->mix_oh, info->landColor, info->paleLandColor);
	}
	
	if (q > phi)	 // (nearPole + q) / 2 > pole
	{
#if 1	// toggle polar caps on & off.

		// thinner to thicker ice.
		specular = q > phi + 0.02f ? 1.0f : 0.4f + (q - phi) * 30.0f;	// (q - phi) * 30 == ((q-phi) / 0.02) * 0.6
		diffuse = Blend(specular, info->polarSeaColor, diffuse);
		specular = specular * 0.5f; // softer contours under ice, but still contours.
		
#endif
	}
	
	return (FloatRGBA){ diffuse.r, diffuse.g, diffuse.b, specular };
}


static FloatRGB FloatRGBFromDictColor(NSDictionary *dictionary, NSString *key)
{
	OOColor *color = [dictionary objectForKey:key];
	NSCAssert1([color isKindOfClass:[OOColor class]], @"Expected OOColor, got %@", [color class]);
	
	return (FloatRGB){ [color redComponent], [color greenComponent], [color blueComponent] };
}


static void FillRandomBuffer(float *randomBuffer, RANROTSeed seed)
{
	unsigned i, len = kRandomBufferSize * kRandomBufferSize;
	for (i = 0; i < len; i++)
	{
		randomBuffer[i] = randfWithSeed(&seed);
	}
}


OOINLINE float Hermite(float q)
{
	return 3.0f * q * q - 2.0f * q * q * q;
}


#if __BIG_ENDIAN_
#define iman_ 1
#else
#define iman_ 0
#endif

 // (same behaviour as, but faster than, FLOAT->INT)
 //Works OK for -32728 to 32727.99999236688
inline long fast_floor(double val)
{
   val += 68719476736.0 * 1.5;
   return (((long*)&val)[iman_] >> 16);
}


static void AddNoise(OOPlanetTextureGeneratorInfo *info, float *randomBuffer, float octave, unsigned octaveMask, float scale, float *qxBuffer, int *ixBuffer)
{
	unsigned	x, y;
	unsigned	width = info->width, height = info->height;
	int			ix, jx, iy, jy;
	float		rr = octave / width;
	float		fx, fy, qx, qy, rix, rjx, rfinal;
	float		*dst = info->fbmBuffer;
	
	for (fy = 0, y = 0; y < height; fy++, y++)
	{
		qy = fy * rr;
		iy = fast_floor(qy);
		jy = (iy + 1) & octaveMask;
		qy = Hermite(qy - iy);
		iy &= (kRandomBufferSize - 1);
		jy &= (kRandomBufferSize - 1);
		
		for (fx = 0, x = 0; x < width; fx++, x++)
		{
			if (y == 0)
			{
				// first pass: initialise buffers.
				qx = fx * rr;
				ix = fast_floor(qx);
				qx -= ix;
				ix &= (kRandomBufferSize - 1);
				ixBuffer[x] = ix;
				qxBuffer[x] = Hermite(qx);
			}
			else
			{
				// later passes: grab the stored values.
				ix = ixBuffer[x];
				qx = qxBuffer[x];
			}
			
			jx = (ix + 1) & octaveMask;
			jx &= (kRandomBufferSize - 1);
			
			rix = Lerp(randomBuffer[iy * kRandomBufferSize + ix], randomBuffer[iy * kRandomBufferSize + jx], qx);
			rjx = Lerp(randomBuffer[jy * kRandomBufferSize + ix], randomBuffer[jy * kRandomBufferSize + jx], qx);
			rfinal = Lerp(rix, rjx, qy);
			
			*dst++ += scale * rfinal;
		}
	}
}


static BOOL FillFBMBuffer(OOPlanetTextureGeneratorInfo *info)
{
	NSCParameterAssert(info != NULL);
	
	BOOL OK = NO;
	
	// Allocate result buffer.
	info->fbmBuffer = calloc(info->width * info->height, sizeof (float));
	FAIL_IF_NULL(info->fbmBuffer);
	
	// Allocate the temporary buffers we need in one fell swoop, to avoid administrative overhead.
	size_t randomBufferSize = kRandomBufferSize * kRandomBufferSize * sizeof (float);
	size_t qxBufferSize = info->width * sizeof (float);
	size_t ixBufferSize = info->width * sizeof (int);
	char *sharedBuffer = malloc(randomBufferSize + qxBufferSize + ixBufferSize);
	FAIL_IF_NULL(sharedBuffer);
	
	float *randomBuffer = (float *)sharedBuffer;
	float *qxBuffer = (float *)(sharedBuffer + randomBufferSize);
	int *ixBuffer = (int *)(sharedBuffer + randomBufferSize + qxBufferSize);
	
	// Get us some value noise.
	FillRandomBuffer(randomBuffer, info->seed);
	
	// Generate basic fBM noise.
	unsigned height = info->height;
	unsigned octaveMask = 8 * kPlanetAspectRatio;
	float octave = octaveMask;
	octaveMask -= 1;
	float scale = 0.5f;
	
	while ((octaveMask + 1) < height)
	{
		AddNoise(info, randomBuffer, octave, octaveMask, scale, qxBuffer, ixBuffer);
		octave *= 2.0f;
		octaveMask = (octaveMask << 1) | 1;
		scale *= 0.5f;
	}
	
#if DEBUG_DUMP_RAW
	[self dumpNoiseBuffer:info->fbmBuffer];
#endif
	
	OK = YES;
END:
	FREE(sharedBuffer);
	return OK;
}


static float QFactor(float *accbuffer, int x, int y, unsigned width, float polar_y_value, float bias, float polar_y)
{
	float q = accbuffer[y * width + x];	// 0.0 -> 1.0
	q += bias;
	
	// Polar Y smooth.
	q = q * (1.0f - polar_y) + polar_y * polar_y_value;

	return q;
}


static float GetQ(float *qbuffer, unsigned x, unsigned y, unsigned width, unsigned height, unsigned widthMask, unsigned heightMask)
{
	// Correct Y wrapping mode, unoptimised.
	//if (y < 0) { y = -y - 1; x += width / 2; }
	//else if (y >= height) { y = height - (y - height)  - 1; x += width / 2; }
	// now let's wrap x.
	//x = x % width;

	// Correct Y wrapping mode, faster method. In the following lines of code, both
	// width and height are assumed to be powers of 2: 512, 1024, 2048, etc...
	if (y & height) { y = (y ^ heightMask) & heightMask; x += width >> 1; }
	// x wrapping.
	x &= widthMask;
	return  qbuffer[y * width + x];
}


static void SetMixConstants(OOPlanetTextureGeneratorInfo *info, float temperatureFraction)
{
	info->mix_hi = 0.66667f * info->landFraction;
	info->mix_oh = 1.0f / info->mix_hi;
	info->mix_ih = 1.0f / (1.0f - info->mix_hi);
	info->mix_polarCap = temperatureFraction * (0.28f + 0.24f * info->landFraction);	// landmasses make the polar cap proportionally bigger, but not too much bigger.
}


@implementation OOPlanetNormalMapGenerator

- (id) initWithCacheKey:(NSString *)cacheKey seed:(RANROTSeed)seed
{
	if ((self = [super init]))
	{
		_cacheKey = [cacheKey copy];
		_seed = seed;
	}
	return self;
}


- (void) dealloc
{
	DESTROY(_cacheKey);
	
	[super dealloc];
}


- (NSString *) cacheKey
{
	return _cacheKey;
}


- (uint32_t) textureOptions
{
	return PLANET_TEXTURE_OPTIONS;
}


- (BOOL) enqueue
{
	/*	This generator doesn't do any work, so it doesn't need to be queued
		at the normal time.
		(The alternative would be for it to block a work thread waiting for
		the real generator to complete, which seemed silly.)
	*/
	return YES;
}


- (void) loadTexture
{
	// Do nothing.
}


- (void) completeWithData:(void *)data_ width:(unsigned)width_ height:(unsigned)height_
{
	data = data_;
	width = width_;
	height = height_;
	format = kOOTextureDataRGBA;
	
	// Enqueue so superclass can apply texture options and so forth.
	[super enqueue];
	
#if DEBUG_DUMP
	NSString *normalName = [NSString stringWithFormat:@"planet-%u-%u-normal-new", _seed.high, _seed.low];
	NSString *specularName = [NSString stringWithFormat:@"planet-%u-%u-specular-new", _seed.high, _seed.low];
	
	[[UNIVERSE gameView] dumpRGBAToRGBFileNamed:normalName
							   andGrayFileNamed:specularName
										  bytes:data
										  width:width
										 height:height
									   rowBytes:width * 4];
#endif
}

@end


@implementation OOPlanetAtmosphereGenerator

- (id) initWithCacheKey:(NSString *)cacheKey seed:(RANROTSeed)seed
{
	if ((self = [super init]))
	{
		_cacheKey = [cacheKey copy];
		_seed = seed;
	}
	return self;
}


- (void) dealloc
{
	DESTROY(_cacheKey);
	
	[super dealloc];
}


- (NSString *) cacheKey
{
	return _cacheKey;
}


- (uint32_t) textureOptions
{
	return PLANET_TEXTURE_OPTIONS;
}


- (BOOL) enqueue
{
	return YES;
}


- (void) loadTexture
{
	// Do nothing.
}


- (void) completeWithData:(void *)data_ width:(unsigned)width_ height:(unsigned)height_
{
	data = data_;
	width = width_;
	height = height_;
	format = kOOTextureDataRGBA;
	
	// Enqueue so superclass can apply texture options and so forth.
	[super enqueue];
	
#if DEBUG_DUMP
	NSString *rgbName = [NSString stringWithFormat:@"planet-%u-%u-atmosphere-rgb-new", _seed.high, _seed.low];
	NSString *alphaName = [NSString stringWithFormat:@"planet-%u-%u-atmosphere-alpha-new", _seed.high, _seed.low];
	
	[[UNIVERSE gameView] dumpRGBAToRGBFileNamed:rgbName
							   andGrayFileNamed:alphaName
										  bytes:data
										  width:width
										 height:height
									   rowBytes:width * 4];
#endif
}

@end
