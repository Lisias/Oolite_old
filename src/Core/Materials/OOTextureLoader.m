/*

OOTextureLoader.m

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

#import "OOTextureLoader.h"
#import "OOPNGTextureLoader.h"
#import "OOFunctionAttributes.h"
#import "OOCollectionExtractors.h"
#import "OOMaths.h"
#import "Universe.h"
#import "OOTextureScaling.h"


typedef struct
{
	OOTextureLoader			*head,
							*tail;
} LoaderQueue;


static NSConditionLock		*sQueueLock = nil;
OOTextureLoader				*sQueueHead = nil, *sQueueTail = nil;
static GLint				sGLMaxSize = 0;
static uint32_t				sUserMaxSize;
static BOOL					sReducedDetail;
static BOOL					sHaveNPOTTextures = NO;	// TODO: support "true" non-power-of-two textures.


enum
{
	kConditionNoData = 1,
	kConditionQueuedData
};


@interface OOTextureLoader (OOPrivate)

// Manipulate queue (call without lock acquired)
- (void)queue;
- (void)unqueue;

@end

@interface OOTextureLoader (OOTextureLoadingThread)

+ (void)queueTask;
- (void)performLoad;
- (void)applySettings;

@end


@implementation OOTextureLoader

+ (id)loaderWithPath:(NSString *)path options:(uint32_t)options
{
	NSString				*extension = nil;
	id						result = nil;
	
	if (path == nil) return nil;
	
	// Set up loading thread and queue lock
	if (sQueueLock == nil)
	{
		sQueueLock = [[NSConditionLock alloc] initWithCondition:kConditionNoData];
		if (sQueueLock != nil)  [NSThread detachNewThreadSelector:@selector(queueTask) toTarget:self withObject:nil];
	}
	if (sQueueLock == nil)
	{
		OOLog(@"textureLoader.detachThread", @"Could not start texture-loader thread.");
		return nil;
	}
	
	// Load two maximum sizes - graphics hardware limit and user-specified limit.
	if (sGLMaxSize == 0)
	{
		glGetIntegerv(GL_MAX_TEXTURE_SIZE, &sGLMaxSize);
		if (sGLMaxSize < 64)  sGLMaxSize = 64;
		
		sUserMaxSize = [[NSUserDefaults standardUserDefaults] unsignedIntForKey:@"max-texture-size" defaultValue:UINT_MAX];
		sUserMaxSize = OORoundUpToPowerOf2(sUserMaxSize);
		if (sUserMaxSize < 64)  sUserMaxSize = 64;
	}
	
	// Get reduced detail setting (every time, in case it changes; we don't want to call through to Universe on the loading thread in case the implementation becomes non-trivial
	sReducedDetail = [UNIVERSE reducedDetail];
	
	// Get a suitable loader.
	extension = [[path pathExtension] lowercaseString];
	if ([extension isEqualToString:@"png"])
	{
		result = [[OOPNGTextureLoader alloc] initWithPath:path options:options];
	}
	else
	{
		OOLog(@"textureLoader.unknownType", @"Can't use %@ as a texture - extension \"%@\" does not identify a known type.", path, extension);
	}
	
	if (result != nil)  [result queue];
	
	return [result autorelease];
}


- (id)initWithPath:(NSString *)inPath options:(uint32_t)options
{
	self = [super init];
	if (self == nil)  return nil;
	
	path = [inPath copy];
	completionLock = [[NSLock alloc] init];
	
	if (EXPECT_NOT(path == nil || completionLock == nil))
	{
		[self release];
		return nil;
	}
	
	[completionLock lock];	// Will be unlocked when loading is done.
	
	generateMipMaps = (options & kOOTextureFilterMask) == kOOTextureFilterDefault;
	scaleAsNormalMap = (options & kOOTextureIsNormalMap) != 0;
	avoidShrinking = (options & kOOTextureNoShrink) != 0;
	
	return self;
}


- (void)dealloc
{
	if (EXPECT_NOT(next != nil || prev != nil))  [self unqueue];
	[path release];
	[completionLock release];
	
	[super dealloc];
}


- (NSString *)description
{
	NSString			*state = nil;
	
	if (ready)
	{
		if (data != NULL)  state = @"ready";
		else  state = @"failed";
	}
	else  state = @"loading";
	
	return [NSString stringWithFormat:@"<%@ %p>{%@ -- ready:%@}", [self class], self, path, state];
}


- (BOOL)isReady
{
	return ready;
}


- (BOOL)getResult:(void **)outData
			width:(uint32_t *)outWidth
		   height:(uint32_t *)outHeight
{
	if (!ready)
	{
		priority = YES;
		[completionLock lock];	// Block until ready
		[completionLock release];
		completionLock = nil;
	}
	
	if (EXPECT(outData != NULL))  *outData = data;
	if (EXPECT(outWidth != NULL))  *outWidth = width;
	if (EXPECT(outHeight != NULL))  *outHeight = height;
	
	return data != nil;
}


- (void)loadTexture
{
	OOLog(kOOLogSubclassResponsibility, @"%s is a subclass responsibility!", __PRETTY_FUNCTION__);
}


@end


@implementation OOTextureLoader (OOPrivate)

- (void)queue
{
	if (EXPECT_NOT(prev != nil || next != nil))
	{
		// Already queued.
		return;
	}
	
	[sQueueLock lock];
	
	[self retain];		// Will be released in +queueTask.
	prev = sQueueTail;
	// Already established that next is nil above.
	
	if (sQueueTail != nil)  sQueueTail->next = self;
	sQueueTail = self;
	
	if (sQueueHead == nil)  sQueueHead = self;
	
	[sQueueLock unlockWithCondition:kConditionQueuedData];
}


- (void)unqueue
{
	if (EXPECT_NOT(prev == nil && next == nil))
	{
		// Not queued.
		return;
	}
	
	[sQueueLock lock];
	
	if (next != nil)  next->prev = prev;
	if (prev != nil)  prev->next = next;
	
	if (sQueueHead == self)  sQueueHead = next;
	if (sQueueTail == self)  sQueueTail = prev;
	
	[sQueueLock unlockWithCondition:(sQueueHead != nil) ? kConditionQueuedData : kConditionNoData];
}

@end


/*** Methods performed on the loader thread. ***/

@implementation OOTextureLoader (OOTextureLoadingThread)

+ (void)queueTask
{
	NSAutoreleasePool			*pool = nil;
	OOTextureLoader				*loader = nil;
	
	for (;;)
	{
		pool = [[NSAutoreleasePool alloc] init];
		
		[sQueueLock lockWhenCondition:kConditionQueuedData];
		loader = sQueueHead;
		if (EXPECT(loader != nil))
		{
			// TODO: search for first item with priority bit set.
			sQueueHead = loader->next;
			if (sQueueTail == loader)  sQueueTail = nil;
			[sQueueLock unlockWithCondition:(sQueueHead != nil) ? kConditionQueuedData : kConditionNoData];
			
			[loader performLoad];
			[loader release];	// Was retained in -queue.
		}
		else
		{
			OOLog(@"textureLoader.queueTask.inconsistency", @"***** Texture loader queue state was data-available when queue was empty!");
			[sQueueLock unlockWithCondition:kConditionNoData];
		}
		
		[pool release];
	}
}


- (void)performLoad
{
	next = prev = nil;
	
	NS_DURING
		[self loadTexture];
		if (data != NULL)  [self applySettings];
	NS_HANDLER
		OOLog(kOOLogException, @"***** Exception loading texture %@: %@ (%@).", path, [localException name], [localException reason]);
		
		// Be sure to signal load failure
		if (data != NULL)
		{
			free(data);
			data = NULL;
		}
	NS_ENDHANDLER
	
	ready = YES;
	[completionLock unlock];	// Signal readyness
}


- (void)applySettings
{
	uint32_t			desiredWidth, desiredHeight;
	BOOL				rescale;
	void				*newData = NULL;
	size_t				newSize;
	
	if (rowBytes == 0)  rowBytes = width * 4;
	
	// Work out appropriate final size for textures.
	if (!sHaveNPOTTextures)
	{
		desiredWidth = OORoundUpToPowerOf2((2 * width) / 3);
		desiredHeight = OORoundUpToPowerOf2((2 * width) / 3);
	}
	else
	{
		desiredWidth = width;
		desiredHeight = height;
	}
	
	desiredWidth = MIN(desiredWidth, sGLMaxSize);
	desiredHeight = MIN(desiredHeight, sGLMaxSize);
	
	if (!avoidShrinking)
	{
		desiredWidth = MIN(desiredWidth, sUserMaxSize);
		desiredHeight = MIN(desiredHeight, sUserMaxSize);
		
		if (sReducedDetail)
		{
			if (512 < desiredWidth)  desiredWidth /= 2;
			if (512 < desiredHeight)  desiredHeight /= 2;
		}
	}
	
	// Rescale if needed.
	rescale = (width != desiredWidth || height != desiredHeight);
	if (rescale)
	{
		newSize = desiredWidth * desiredHeight;
		if (generateMipMaps)  newSize = (newSize * 4) / 3;
		
		newData = malloc(newSize);
		if (generateMipMaps && newData == NULL)
		{
			// Try again without space for mipmaps
			generateMipMaps = NO;
			newSize = desiredWidth * desiredHeight;
			newData = malloc(newSize);
		}
		if (newData == NULL)
		{
			free(data);
			data = NULL;	// Signal failure
			return;
		}
		
		if (!scaleAsNormalMap)
		{
			ScalePixMap(data, width, height, rowBytes, newData, desiredWidth, desiredHeight);
		}
		else
		{
			ScaleNormalMap(data, width, height, rowBytes, newData, desiredWidth, desiredHeight);
		}
		
		// Replace data with new, scaled data.
		free(data);
		data = newData;
		width = desiredWidth;
		height = desiredHeight;
	}
	
	// Generate mip maps if needed.
	if (generateMipMaps && !rescale)
	{
		// Make space...
		newData = realloc(data, (width * height * 4) / 3);
		if (newData != nil)  data = newData;
		else  generateMipMaps = NO;
	}
	if (generateMipMaps)
	{
		if (!scaleAsNormalMap)
		{
			GenerateMipMaps(data, width, height);
		}
		else
		{
			GenerateNormalMapMipMaps(data, width, height);
		}
	}
	
	// All done.
}

@end
