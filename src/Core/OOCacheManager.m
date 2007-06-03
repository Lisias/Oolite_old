/*

OOCacheManager.m

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

#import "OOCacheManager.h"
#import "OOCache.h"
#import "OOPListParsing.h"


#define AUTO_PRUNE NO


static NSString * const kOOLogDataCacheFound				= @"dataCache.found";
static NSString * const kOOLogDataCacheNotFound				= @"dataCache.notFound";
static NSString * const kOOLogDataCacheRebuild				= @"dataCache.rebuild";
static NSString * const kOOLogDataCacheWriteSuccess			= @"dataCache.write.success";
static NSString * const kOOLogDataCacheWriteFailed			= @"dataCache.write.failed";
static NSString * const kOOLogDataCacheRetrieveSuccess		= @"dataCache.retrieve.success";
static NSString * const kOOLogDataCacheRetrieveFailed		= @"dataCache.retrieve.failed";
static NSString * const kOOLogDataCacheSetSuccess			= @"dataCache.set.success";
static NSString * const kOOLogDataCacheSetFailed			= @"dataCache.set.failed";
static NSString * const kOOLogDataCacheRemoveSuccess		= @"dataCache.remove.success";
static NSString * const kOOLogDataCacheClearSuccess			= @"dataCache.clear.success";
static NSString * const kOOLogDataCacheParamError			= @"general.error.parameterError.OOCacheManager";
static NSString * const kOOLogDataCacheBuildPathError		= @"dataCache.write.buildPath.failed";
static NSString * const kOOLogDataCacheSerializationError	= @"dataCache.write.serialize.failed";
static NSString * const kOOLogDataCacheRemovedOld			= @"dataCache.removedOld";

static NSString * const kCacheKeyVersion					= @"CFBundleVersion";	// Legacy name
static NSString * const kCacheKeyEndianTag					= @"endian tag";
static NSString * const kCacheKeyFormatVersion				= @"format version";
static NSString * const kCacheKeyCaches						= @"caches";


enum
{
	kEndianTagValue			= 0x12345678UL,
	kFormatVersionValue		= 4
};


static OOCacheManager *sSingleton = nil;


@interface OOCacheManager (Private)

- (void)loadCache;
- (void)write;
- (void)clear;
- (BOOL)dirty;
- (void)markClean;

- (void)buildCachesFromDictionary:(NSDictionary *)inDict;
- (NSDictionary *)dictionaryOfCaches;

@end


@interface OOCacheManager (PlatformSpecific)

- (void)platformInit;
- (NSDictionary *)loadDict;
- (BOOL)writeDict:(NSDictionary *)inDict;

@end


@implementation OOCacheManager

- (id)init
{
	self = [super init];
	if (self != nil)
	{
		[self platformInit];
		[self loadCache];
	}
	return self;
}


- (void)dealloc
{
	[self clear];
	
	[super dealloc];
}


- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p>{dirty=%s}", [self class], self, [self dirty] ? "yes" : "no"];
}


+ (id)sharedCache
{
	// NOTE: assumes single-threaded access.
	if (sSingleton == nil)
	{
		[[self alloc] init];
	}
	
	return sSingleton;
}


- (id)objectForKey:(NSString *)inKey inCache:(NSString *)inCacheKey
{
	OOCache					*cache = nil;
	id						result = nil;
	
	// Sanity check
	if (inCacheKey == nil || inKey == nil)
	{
		OOLog(kOOLogDataCacheParamError, @"Bad parameters -- nil key or cacheKey.");
		return nil;
	}
	
	cache = [caches objectForKey:inCacheKey];
	if (cache != nil)
	{
		result = [cache objectForKey:inKey];
		if (result != nil)
		{
			OOLog(kOOLogDataCacheRetrieveSuccess, @"Retrieved \"%@\" cache object %@.", inCacheKey, inKey);
		}
		else
		{
			OOLog(kOOLogDataCacheRetrieveFailed, @"Failed to retrive \"%@\" cache object %@ -- no such entry.", inCacheKey, inKey);
		}
	}
	else
	{
		OOLog(kOOLogDataCacheRetrieveFailed, @"Failed to retrive\"%@\" cache object %@ -- no such cache.", inCacheKey, inKey);
	}
	
	return result;
}



- (void)setObject:(id)inObject forKey:(NSString *)inKey inCache:(NSString *)inCacheKey
{
	OOCache					*cache = nil;
	
	// Sanity check
	if (inObject == nil || inCacheKey == nil || inKey == nil)  OOLog(kOOLogDataCacheParamError, @"Bad parameters -- nil object, key or cacheKey.");
	
	if (caches == nil)  return;
	
	cache = [caches objectForKey:inCacheKey];
	if (cache == nil)
	{
		cache = [[OOCache alloc] init];
		if (cache == nil)
		{
			OOLog(kOOLogDataCacheSetFailed, @"Failed to create cache for key \"%@\".", inCacheKey);
			return;
		}
		[cache setName:inCacheKey];
		[cache setAutoPrune:AUTO_PRUNE];
		[caches setObject:cache forKey:inCacheKey];
	}
	
	[cache setObject:inObject forKey:inKey];
	OOLog(kOOLogDataCacheSetSuccess, @"Updated entry %@ in cache \"%@\".", inKey, inCacheKey);
}


- (void)removeObjectForKey:(NSString *)inKey inCache:(NSString *)inCacheKey
{
	OOCache					*cache = nil;
	
	// Sanity check
	if (inCacheKey == nil || inKey == nil)  OOLog(kOOLogDataCacheParamError, @"Bad parameters -- nil key or cacheKey.");
	
	cache = [caches objectForKey:inCacheKey];
	if (cache != nil)
	{
		if (nil != [cache objectForKey:inKey])
		{
			[cache removeObjectForKey:inKey];
			OOLog(kOOLogDataCacheRemoveSuccess, @"Removed entry keyed %@ from cache \"%@\".", inKey, inCacheKey);
		}
		else
		{
			OOLog(kOOLogDataCacheRemoveSuccess, @"No need to remove non-existent entry keyed %@ from cache \"%@\".", inKey, inCacheKey);
		}
	}
	else
	{
		OOLog(kOOLogDataCacheRemoveSuccess, @"No need to remove entry keyed %@ from non-existent cache \"%@\".", inKey, inCacheKey);
	}
}


- (void)clearCache:(NSString *)inCacheKey
{
	// Sanity check
	if (inCacheKey == nil)  OOLog(kOOLogDataCacheParamError, @"Bad parameter -- nil cacheKey.");
	
	if (nil != [caches objectForKey:inCacheKey])
	{
		[caches removeObjectForKey:inCacheKey];
		OOLog(kOOLogDataCacheClearSuccess, @"Cleared cache \"%@\".", inCacheKey);
	}
	else
	{
		OOLog(kOOLogDataCacheClearSuccess, @"No need to clear non-existent cache \"%@\".", inCacheKey);
	}
}


- (void)clearAllCaches
{
	[caches release];
	caches = [[NSMutableDictionary alloc] init];
}


- (void)setPruneThreshold:(unsigned)inThreshold forCache:(NSString *)inCacheKey
{
	OOCache				*cache = nil;
	
	cache = [caches objectForKey:inCacheKey];
	if (cache != nil)
	{
		[cache setPruneThreshold:inThreshold];
	}
}


- (unsigned)pruneThresholdForCache:(NSString *)inCacheKey
{
	OOCache				*cache = nil;
	
	cache = [caches objectForKey:inCacheKey];
	if (cache != nil)  return [cache pruneThreshold];
	else  return kOOCacheDefaultPruneThreshold;
}


- (void)flush
{
	if ([self dirty])
	{
		[self write];
		[self markClean];
	}
}

@end


@implementation OOCacheManager (Private)

- (void)loadCache
{
	NSDictionary			*cache = nil;
	NSString				*cacheVersion = nil;
	NSString				*ooliteVersion = nil;
	NSData					*endianTag = nil;
	NSNumber				*formatVersion = nil;
	BOOL					accept = YES;
	uint32_t				endianTagValue = 0;
	
	ooliteVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:kCacheKeyVersion];
	
	[self clear];
	
	cache = [self loadDict];
	if (cache != nil)
	{
		// We have a cache
		OOLog(kOOLogDataCacheFound, @"Found data cache.");
		OOLogIndentIf(kOOLogDataCacheFound);
		
		cacheVersion = [cache objectForKey:kCacheKeyVersion];
		if (![cacheVersion isEqual:ooliteVersion])
		{
			OOLog(kOOLogDataCacheRebuild, @"Data cache version (%@) does not match Oolite version (%@), rebuilding cache.", cacheVersion, ooliteVersion);
			accept = NO;
		}
		
		formatVersion = [cache objectForKey:kCacheKeyFormatVersion];
		if (accept && [formatVersion unsignedIntValue] != kFormatVersionValue)
		{
			OOLog(kOOLogDataCacheRebuild, @"Data cache format (%@) is not supported format (%u), rebuilding cache.", formatVersion, kFormatVersionValue);
			accept = NO;
		}
		
		if (accept)
		{
			endianTag = [cache objectForKey:kCacheKeyEndianTag];
			if (![endianTag isKindOfClass:[NSData class]] || [endianTag length] != sizeof endianTagValue)
			{
				OOLog(kOOLogDataCacheRebuild, @"Data cache endian tag is invalid, rebuilding cache.");
				accept = NO;
			}
			else
			{
				endianTagValue = *(const uint32_t *)[endianTag bytes];
				if (endianTagValue != kEndianTagValue)
				{
					OOLog(kOOLogDataCacheRebuild, @"Data cache endianness is inappropriate for this system, rebuilding cache.");
					accept = NO;
				}
			}
		}
		
		if (accept)
		{
			// We have a cache, and it's the right format.
			[self buildCachesFromDictionary:[cache objectForKey:kCacheKeyCaches]];
		}
		
		OOLogOutdentIf(kOOLogDataCacheFound);
	}
	else
	{
		// No cache
		OOLog(kOOLogDataCacheNotFound, @"No data cache found, starting from scratch.");
	}
	
	// If loading failed, or there was a version or endianness conflict
	if (caches == nil) caches = [[NSMutableDictionary alloc] init];
}


- (void)write
{
	NSMutableDictionary		*newCache = nil;
	NSString				*ooliteVersion = nil;
	NSData					*endianTag = nil;
	NSNumber				*formatVersion = nil;
	NSDictionary			*pListRep = nil;
	uint32_t				endianTagValue = kEndianTagValue;
	
	if (caches == nil) return;
	
	OOLog(@"dataCache.willWrite", @"About to write data cache.");	// Added for 1.69 to detect possible write-related crash. -- Ahruman
	OOLogIndent();
	OOLog(@"dataCache.debug", @"- creating version number object.");
	ooliteVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:kCacheKeyVersion];
	OOLog(@"dataCache.debug", @"- creating endian tag object.");
	endianTag = [NSData dataWithBytes:&endianTagValue length:sizeof endianTagValue];
	OOLog(@"dataCache.debug", @"- creating format version object.");
	formatVersion = [NSNumber numberWithUnsignedInt:kFormatVersionValue];
	
	OOLog(@"dataCache.debug", @"- serializing caches.");
	OOLogIndent();
	pListRep = [self dictionaryOfCaches];
	OOLogOutdent();
	OOLogOutdent();
	if (ooliteVersion == nil || endianTag == nil || formatVersion == nil || pListRep == nil)
	{
		OOLog(@"dataCache.cantWrite", @"Failed to write data cache -- prerequisites not fulfilled. (This is an internal error, please report it.)");
		return;
	}
	OOLogIndent();
	OOLog(@"dataCache.debug", @"- verified all objects.");
	
	OOLog(@"dataCache.debug", @"- building cache dictionary object.");
	newCache = [NSMutableDictionary dictionaryWithCapacity:4];
	[newCache setObject:ooliteVersion forKey:kCacheKeyVersion];
	[newCache setObject:formatVersion forKey:kCacheKeyFormatVersion];
	[newCache setObject:endianTag forKey:kCacheKeyEndianTag];
	[newCache setObject:pListRep forKey:kCacheKeyCaches];
	
	OOLog(@"dataCache.debug", @"- writing dictionary.");
	OOLogOutdent();
	
	if ([self writeDict:newCache])
	{
		[self markClean];
		OOLog(kOOLogDataCacheWriteSuccess, @"Wrote data cache.");
	}
	else
	{
		OOLog(kOOLogDataCacheWriteFailed, @"Failed to write data cache.");
	}
}


- (void)clear
{
	[caches release];
	caches = nil;
}


- (BOOL)dirty
{
	NSEnumerator				*cacheEnum = nil;
	OOCache						*cache = nil;
	
	for (cacheEnum = [caches objectEnumerator]; (cache = [cacheEnum nextObject]); )
	{
		if ([cache dirty]) return YES;
	}
	return NO;
}


- (void)markClean
{
	NSEnumerator				*cacheEnum = nil;
	OOCache						*cache = nil;
	
	for (cacheEnum = [caches objectEnumerator]; (cache = [cacheEnum nextObject]); )
	{
		[cache markClean];
	}
}


- (void)buildCachesFromDictionary:(NSDictionary *)inDict
{
	NSEnumerator				*keyEnum = nil;
	id							key = nil;
	id							value = nil;
	OOCache						*cache = nil;
	
	if (inDict == nil ) return;
	
	[caches release];
	caches = [[NSMutableDictionary alloc] initWithCapacity:[inDict count]];
	
	for (keyEnum = [inDict keyEnumerator]; (key = [keyEnum nextObject]); )
	{
		value = [inDict objectForKey:key];
		cache = [[OOCache alloc] initWithPList:value];
		if (cache != nil)
		{
			[cache setName:key];
			[caches setObject:cache forKey:key];
			[cache release];
		}
	}
}


- (NSDictionary *)dictionaryOfCaches
{
	NSMutableDictionary			*dict = nil;
	NSEnumerator				*keyEnum = nil;
	id							key = nil;
	OOCache						*cache = nil;
	id							pList = nil;
	
	dict = [NSMutableDictionary dictionaryWithCapacity:[caches count]];
	for (keyEnum = [caches keyEnumerator]; (key = [keyEnum nextObject]); )
	{
		cache = [caches objectForKey:key];
		OOLog(@"dataCache.debug", @"- serializing cache \"%@\" -- %@.", key, cache);
		OOLogIndent();
		pList = [cache pListRepresentation];
		OOLogOutdent();
		if (pList != nil)  [dict setObject:pList forKey:key];
		else OOLog(@"dataCache.debug", @"  - serialization failed.");
	}
	
	return dict;
}

@end


@implementation OOCacheManager (PlatformSpecific)

- (BOOL)directoryExists:(NSString *)inPath create:(BOOL)inCreate;
{
	BOOL				exists, directory;
	NSFileManager		*fmgr =  [NSFileManager defaultManager];
	
	exists = [fmgr fileExistsAtPath:inPath isDirectory:&directory];
	
	if (exists && !directory)
	{
		OOLog(kOOLogDataCacheBuildPathError, @"Expected %@ to be a folder, but it is a file.", inPath);
		return NO;
	}
	if (!exists)
	{
		if (!inCreate) return NO;
		if (![fmgr createDirectoryAtPath:inPath attributes:nil])
		{
			OOLog(kOOLogDataCacheBuildPathError, @"Could not create folder %@.", inPath);
			return NO;
		}
	}
	
	return YES;
}


#if OOLITE_MAC_OS_X

- (NSString *)cachePathCreatingIfNecessary:(BOOL)inCreate
{
	NSString			*cachePath = nil;
	
	/*	Construct the path for the cache file, which is:
			~/Library/Caches/org.aegidian.oolite/Data Cache.plist
		In addition to generally being the right place to put caches,
		~/Library/Caches has the particular advantage of not being indexed by
		Spotlight or, in future, backed up by Time Machine.
	*/
	cachePath = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	cachePath = [cachePath stringByAppendingPathComponent:@"Caches"];
	if (![self directoryExists:cachePath create:inCreate]) return nil;
	cachePath = [cachePath stringByAppendingPathComponent:@"org.aegidian.oolite"];
	if (![self directoryExists:cachePath create:inCreate]) return nil;
	cachePath = [cachePath stringByAppendingPathComponent:@"Data Cache.plist"];
	return cachePath;
}


- (NSString *)oldCachePath
{
	NSString			*path = nil;
	
	path = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	path = [path stringByAppendingPathComponent:@"Application Support"];
	path = [path stringByAppendingPathComponent:@"Oolite"];
	path = [path stringByAppendingPathComponent:@"cache"];
	
	return path;
}


#define CACHE_PLIST_FORMAT	NSPropertyListBinaryFormat_v1_0

#else

- (NSString *)cachePathCreatingIfNecessary:(BOOL)inCreate
{
	NSString			*cachePath = nil;
	
	/*	Construct the path for the cache file, which is:
			~/Library/Caches/org.aegidian.oolite/Data Cache.plist
		In addition to generally being the right place to put caches,
		~/Library/Caches has the particular advantage of not being indexed by
		Spotlight or, in future, backed up by Time Machine.
	*/
	
	cachePath = [NSHomeDirectory() stringByAppendingPathComponent:@"GNUstep"];
	if (![self directoryExists:cachePath create:inCreate]) return nil;
	cachePath = [cachePath stringByAppendingPathComponent:@"Library"];
	if (![self directoryExists:cachePath create:inCreate]) return nil;
	cachePath = [cachePath stringByAppendingPathComponent:@"Oolite-cache"];
	
	return cachePath;
}


- (NSString *)oldCachePath
{
	return [[[NSHomeDirectory() stringByAppendingPathComponent:@"GNUstep"]
								stringByAppendingPathComponent:@"Library"]
								stringByAppendingPathComponent:@"Oolite-cache"];
}


#define CACHE_PLIST_FORMAT	NSPropertyListXMLFormat_v1_0	// NSPropertyListGNUstepBinaryFormat

#endif


- (void)platformInit
{
	// Since the cache location has changed, we delete the old cache (if any).
	NSString			*path = [self oldCachePath];
	NSFileManager		*fmgr;
	
	fmgr = [NSFileManager defaultManager];
	if ([fmgr fileExistsAtPath:path])
	{
		OOLog(kOOLogDataCacheRemovedOld, @"Removed old data cache.");
		[fmgr removeFileAtPath:path handler:nil];
	}
}


- (NSDictionary *)loadDict
{
	NSString *path = [self cachePathCreatingIfNecessary:NO];
	if (path == nil) return nil;
	return [NSDictionary dictionaryWithContentsOfFile:path];
}


- (BOOL)writeDict:(NSDictionary *)inDict
{
	NSString			*path = nil;
	NSData				*plist = nil;
	NSString			*errorDesc = nil;
	
	path = [self cachePathCreatingIfNecessary:YES];
	if (path == nil) return NO;
	
	plist = [NSPropertyListSerialization dataFromPropertyList:inDict format:CACHE_PLIST_FORMAT errorDescription:&errorDesc];
	if (plist == nil)
	{
		OOLog(kOOLogDataCacheSerializationError, @"Could not convert data cache to property list data: %@", errorDesc);
		return NO;
	}
	
	return [plist writeToFile:path atomically:NO];
}

@end


@implementation OOCacheManager (Singleton)

/*	Canonical singleton boilerplate.
	See Cocoa Fundamentals Guide: Creating a Singleton Instance.
	See also +sharedCache above.
	
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


- (unsigned)retainCount
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
