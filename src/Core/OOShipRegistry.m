/*

OOShipRegistry.m


Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2008 Jens Ayton

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

#import "OOShipRegistry.h"
#import "OOCacheManager.h"
#import "ResourceManager.h"
#import "OOCollectionExtractors.h"
#import "NSDictionaryOOExtensions.h"
#import "OOProbabilitySet.h"
#import "OORoleSet.h"


static OOShipRegistry	*sSingleton = nil;

static NSString * const	kShipRegistryCacheName = @"ship registry";
static NSString * const	kShipDataCacheKey = @"ship data";
static NSString * const	kPlayerShipsCacheKey = @"player ships";
static NSString * const	kDemoShipsCacheKey = @"demo ships";
static NSString * const	kRoleWeightsCacheKey = @"role weights";
static NSString * const	kDefaultDemoShip = @"coriolis-station";


@interface OOShipRegistry (Loader)

- (void) loadShipData;
- (void) loadDemoShips;
- (void) loadCachedRoleProbabilitySets;
- (void) buildRoleProbabilitySets;

- (BOOL) applyLikeShips:(NSMutableDictionary *)ioData;
- (NSDictionary *) mergeShip:(NSDictionary *)child withParent:(NSDictionary *)parent;
- (BOOL) loadAndMergeShipyard:(NSMutableDictionary *)ioData;
- (BOOL) loadAndApplyShipDataOverrides:(NSMutableDictionary *)ioData;
- (BOOL) isValidShipEntry:(NSDictionary *)shipEntry name:(NSString *)name;
- (void) mergeShipRoles:(NSString *)roles forShipKey:(NSString *)shipKey intoProbabilityMap:(NSMutableDictionary *)probabilitySets;

@end


@implementation OOShipRegistry

+ (OOShipRegistry *) sharedRegistry
{
	if (sSingleton == nil)
	{
		[[self alloc] init];
	}
	
	return sSingleton;
}


- (id) init
{
	if ((self = [super init]))
	{
		NSAutoreleasePool		*pool = [[NSAutoreleasePool alloc] init];
		OOCacheManager			*cache = [OOCacheManager sharedCache];
		
		_shipData = [[cache objectForKey:kShipDataCacheKey inCache:kShipRegistryCacheName] retain];
		_playerShips = [[NSSet setWithArray:[cache objectForKey:kPlayerShipsCacheKey inCache:kShipRegistryCacheName]] retain];
		if ([_shipData count] == 0)	// Don't accept nil or empty
		{
			[self loadShipData];
			if ([_shipData count] == 0)
			{
				[NSException raise:@"OOShipRegistryLoadFailure" format:@"Could not load any ship data."];
			}
			if ([_playerShips count] == 0)
			{
				[NSException raise:@"OOShipRegistryLoadFailure" format:@"Could not load any player ships."];
			}
		}
		
		_demoShips = [[cache objectForKey:kDemoShipsCacheKey inCache:kShipRegistryCacheName] retain];
		if ([_demoShips count] == 0)
		{
			[self loadDemoShips];
			if ([_demoShips count] == 0)
			{
				[NSException raise:@"OOShipRegistryLoadFailure" format:@"Could not load or synthesize any demo ships."];
			}
		}
		
		[self loadCachedRoleProbabilitySets];
		if (_probabilitySets == nil)
		{
			[self buildRoleProbabilitySets];
			if ([_probabilitySets count] == 0)
			{
				[NSException raise:@"OOShipRegistryLoadFailure" format:@"Could not load or synthesize role probability sets."];
			}
		}
		
		[pool release];
	}
	return self;
}


- (void) dealloc
{
	[_shipData release];
	[_demoShips release];
	[_playerShips release];
	[_probabilitySets release];
	
	[super dealloc];
}


- (NSDictionary *) shipInfoForKey:(NSString *)key
{
	return [_shipData objectForKey:key];
}


- (NSArray *) shipKeysWithRole:(NSString *)role
{
	if (role == nil)  return nil;
	return [[_probabilitySets objectForKey:role] allObjects];
}


- (NSString *) randomShipKeyForRole:(NSString *)role
{
	if (role == nil)  return nil;
	return [[_probabilitySets objectForKey:role] randomObject];
}


- (NSArray *) demoShipKeys
{
	return _demoShips;
}


- (NSSet *) playerShipKeys
{
	return _playerShips;
}

@end


@implementation OOShipRegistry (Loader)

/*	-loadShipData
	
	Load the data for all ships. This consists of five stages:
		* Load merges shipdata.plist dictionary.
		* Apply all like_ship entries.
		* Load shipdata-overrides.plist and apply patches.
		* Load shipyard.plist, add shipyard data into ship dictionaries, and
		  create _playerShips array.
		* Build role->ship type probability sets.
*/
- (void) loadShipData
{
	NSMutableDictionary		*result = nil;
	NSEnumerator			*enumerator = nil;
	NSString				*key = nil;
	NSDictionary			*immutableResult = nil;
	
	[_shipData release];
	_shipData = nil;
	[_playerShips release];
	_playerShips = nil;
	
	// Load shipdata.plist.
	result = [[[ResourceManager dictionaryFromFilesNamed:@"shipdata.plist"
												inFolder:@"Config"
											   mergeMode:MERGE_BASIC
												   cache:NO] mutableCopy] autorelease];
	if (result == nil)  return;
	
	// Clean out any non-dictionaries.
	for (enumerator = [result keyEnumerator]; (key = [enumerator nextObject]); )
	{
		if (![self isValidShipEntry:[result objectForKey:key] name:key])
		{
			[result removeObjectForKey:key];
		}
	}
	
	// Resolve like_ship entries.
	if (![self applyLikeShips:result])  return;
	
	// Apply patches.
	if (![self loadAndApplyShipDataOverrides:result])  return;
	
	// Add shipyard entries into shipdata entries.
	if (![self loadAndMergeShipyard:result])  return;
	
	immutableResult = [[result copy] autorelease];
	
	_shipData = [immutableResult retain];
	[[OOCacheManager sharedCache] setObject:_shipData forKey:kShipDataCacheKey inCache:kShipRegistryCacheName];
}


/*	-loadDemoShips
	
	Load demoships.plist, and filter out non-existent ships. If no existing
	ships remain, try adding coriolis; if this fails, add any ship in
	shipdata.
*/
- (void) loadDemoShips
{
	NSEnumerator			*enumerator = nil;
	NSString				*key = nil;
	NSMutableArray			*demoShips = nil;
	
	[_demoShips release];
	_demoShips = nil;
	
	demoShips = [[[ResourceManager arrayFromFilesNamed:@"demoships.plist"
											  inFolder:@"Config"
											  andMerge:YES] mutableCopy] autorelease];
	
	for (enumerator = [demoShips objectEnumerator]; (key = [enumerator nextObject]); )
	{
		if (![key isKindOfClass:[NSString class]] || [self shipInfoForKey:key] == nil)
		{
			[demoShips removeObject:key];
		}
	}
	
	if ([demoShips count] == 0)
	{
		if ([self shipInfoForKey:kDefaultDemoShip] != nil)  [demoShips addObject:kDefaultDemoShip];
		else  [demoShips addObject:[[_shipData allKeys] objectAtIndex:0]];
	}
	
	_demoShips = [demoShips copy];
	[[OOCacheManager sharedCache] setObject:_demoShips forKey:kDemoShipsCacheKey inCache:kShipRegistryCacheName];
}


- (void) loadCachedRoleProbabilitySets
{
	NSDictionary			*cachedSets = nil;
	NSMutableDictionary		*restoredSets = nil;
	NSEnumerator			*roleEnum = nil;
	NSString				*role = nil;
	
	cachedSets = [[OOCacheManager sharedCache] objectForKey:kRoleWeightsCacheKey inCache:kShipRegistryCacheName];
	if (cachedSets == nil)  return;
	
	restoredSets = [NSMutableDictionary dictionaryWithCapacity:[cachedSets count]];
	for (roleEnum = [cachedSets keyEnumerator]; (role = [roleEnum nextObject]); )
	{
		[restoredSets setObject:[OOProbabilitySet probabilitySetWithPropertyListRepresentation:[cachedSets objectForKey:role]] forKey:role];
	}
	
	_probabilitySets = [restoredSets copy];
}


- (void) buildRoleProbabilitySets
{
	NSMutableDictionary		*probabilitySets = nil;
	NSEnumerator			*shipEnum = nil;
	NSString				*shipKey = nil;
	NSDictionary			*shipEntry = nil;
	NSString				*roles = nil;
	NSEnumerator			*roleEnum = nil;
	NSString				*role = nil;
	OOProbabilitySet		*pset = nil;
	NSMutableDictionary		*cacheEntry = nil;
	
	probabilitySets = [NSMutableDictionary dictionary];
	
	// Build role sets
	for (shipEnum = [_shipData keyEnumerator]; (shipKey = [shipEnum nextObject]); )
	{
		shipEntry = [_shipData objectForKey:shipKey];
		roles = [shipEntry stringForKey:@"roles"];
		[self mergeShipRoles:roles forShipKey:shipKey intoProbabilityMap:probabilitySets];
	}
	
	// Convert role sets to immutable form, and build cache entry.
	cacheEntry = [NSMutableDictionary dictionaryWithCapacity:[probabilitySets count]];
	for (roleEnum = [probabilitySets keyEnumerator]; (role = [roleEnum nextObject]); )
	{
		pset = [probabilitySets objectForKey:role];
		pset = [[pset copy] autorelease];
		[probabilitySets setObject:pset forKey:role];
		[cacheEntry setObject:[pset propertyListRepresentation] forKey:role];
	}
	
	_probabilitySets = [probabilitySets copy];
	[[OOCacheManager sharedCache] setObject:cacheEntry forKey:kRoleWeightsCacheKey inCache:kShipRegistryCacheName];
}


/*	-applyLikeShips:
	
	Implement like_ship by copying inherited ship and overwriting with child
	ship values. Done iteratively to report recursive references of arbitrary
	depth. Also removes and reports ships whose like_ship entry does not
	resolve, and handles reference loops by removing all ships involved.
 
	We start with a set of keys all ships that have a like_ships entry. In
	each iteration, every ship whose like_ship entry does not refer to a ship
	which itself has a like_ship entry is finalized. If the set of pending
	ships does not shrink in an iteration, the remaining ships cannot be
	resolved (either their like_ships do not exist, or they form reference
	cycles) so we stop looping and report it.
*/
- (BOOL) applyLikeShips:(NSMutableDictionary *)ioData
{
	NSMutableSet			*remainingLikeShips = nil;
	NSEnumerator			*enumerator = nil;
	NSString				*key = nil;
	NSString				*parentKey = nil;
	NSDictionary			*shipEntry = nil;
	NSDictionary			*parentEntry = nil;
	unsigned				count, lastCount;
	
	// Build set of ships with like_ship references
	remainingLikeShips = [NSMutableSet set];
	for (enumerator = [ioData keyEnumerator]; (key = [enumerator nextObject]); )
	{
		shipEntry = [ioData objectForKey:key];
		if ([shipEntry stringForKey:@"like_ship"] != nil)
		{
			[remainingLikeShips addObject:key];
		}
	}
	
	count = lastCount = [remainingLikeShips count];
	while (count != 0)
	{
		for (enumerator = [remainingLikeShips objectEnumerator]; (key = [enumerator nextObject]); )
		{
			// Look up like_ship entry
			shipEntry = [ioData objectForKey:key];
			parentKey = [shipEntry objectForKey:@"like_ship"];
			if (![remainingLikeShips containsObject:parentKey])
			{
				// If parent is fully resolved, we can resolve this child.
				parentEntry = [ioData objectForKey:parentKey];
				shipEntry = [self mergeShip:shipEntry withParent:parentEntry];
				if (shipEntry != nil)
				{
					[remainingLikeShips removeObject:key];
					[ioData setObject:shipEntry forKey:key];
				}
			}
		}
		
		count = [remainingLikeShips count];
		if (count == lastCount)
		{
			// Fail: we couldn't resolve all like_ship entries.
			OOLog(@"shipData.merge.failed", @"***** ERROR: one or more shipdata.plist entries have like_ship references that cannot be resolved: %@", remainingLikeShips);
			break;
		}
		lastCount = count;
	}
	
	return YES;
}


- (NSDictionary *) mergeShip:(NSDictionary *)child withParent:(NSDictionary *)parent
{
	NSMutableDictionary *result = [[parent mutableCopy] autorelease];
	if (result == nil)  return nil;
	
	[result addEntriesFromDictionary:child];
	[result removeObjectForKey:@"like_ship"];
	
	return [[result copy] autorelease];
}


- (BOOL) loadAndApplyShipDataOverrides:(NSMutableDictionary *)ioData
{
	NSEnumerator			*enumerator = nil;
	NSString				*key = nil;
	NSDictionary			*shipEntry = nil;
	NSDictionary			*overrides = nil;
	NSDictionary			*overridesEntry = nil;
	
	overrides = [ResourceManager dictionaryFromFilesNamed:@"shipdata-overrides.plist"
												 inFolder:@"Config"
												mergeMode:MERGE_SMART
													cache:NO];
	
	for (enumerator = [overrides keyEnumerator]; (key = [enumerator nextObject]); )
	{
		shipEntry = [ioData objectForKey:key];
		if (shipEntry != nil)
		{
			overridesEntry = [overrides objectForKey:key];
			if (![overridesEntry isKindOfClass:[NSDictionary class]])
			{
				OOLog(@"shipData.load.error", @"***** ERROR: the shipdata-overrides.plist entry \"%@\" is not a dictionary, ignoring.", key);
			}
			else
			{
				shipEntry = [shipEntry dictionaryByAddingEntriesFromDictionary:overridesEntry];
				[ioData setObject:shipEntry forKey:key];
			}
		}
	}
	
	return YES;
}


/*	-loadAndMergeShipyard:
	
	Load shipyard.plist, add its entries to appropriate shipyard entries as
	a dictionary under the key "shipyard", and build list of player ships.
	Before that, we strip out any "shipyard" entries already in shipdata, and
	apply any shipyard-overrides.plist stuff to shipyard.
*/
- (BOOL) loadAndMergeShipyard:(NSMutableDictionary *)ioData
{
	NSEnumerator			*enumerator = nil;
	NSString				*key = nil;
	NSDictionary			*shipEntry = nil;
	NSDictionary			*shipyard = nil;
	NSDictionary			*shipyardOverrides = nil;
	NSDictionary			*shipyardEntry = nil;
	NSDictionary			*shipyardOverridesEntry = nil;
	NSMutableSet			*playerShips = nil;
	
	// Strip out any shipyard stuff in shipdata (there shouldn't be any).
	for (enumerator = [ioData keyEnumerator]; (key = [enumerator nextObject]); )
	{
		shipEntry = [ioData objectForKey:key];
		if ([shipEntry objectForKey:@"shipyard"] != nil)
		{
			[ioData setObject:[shipEntry dictionaryByRemovingObjectForKey:@"shipyard"] forKey:key];
		}
	}
	
	shipyard = [ResourceManager dictionaryFromFilesNamed:@"shipyard.plist"
												inFolder:@"Config"
											   mergeMode:MERGE_BASIC
												   cache:NO];
	shipyardOverrides = [ResourceManager dictionaryFromFilesNamed:@"shipyard-overrides.plist"
														 inFolder:@"Config"
														mergeMode:MERGE_SMART
															cache:NO];
	
	playerShips = [NSMutableSet setWithCapacity:[shipyard count]];
	
	// Insert merged shipyard and shipyardOverrides entries.
	for (enumerator = [shipyard keyEnumerator]; (key = [enumerator nextObject]); )
	{
		shipEntry = [ioData objectForKey:key];
		if (shipEntry != nil)
		{
			shipyardEntry = [shipyard objectForKey:key];
			shipyardOverridesEntry = [shipyardOverrides objectForKey:key];
			shipyardEntry = [shipyardEntry dictionaryByAddingEntriesFromDictionary:shipyardOverridesEntry];
			
			shipEntry = [shipEntry dictionaryByAddingObject:shipyardEntry forKey:@"shipyard"];
			[ioData setObject:shipEntry forKey:key];
			
			[playerShips addObject:key];
		}
		// Else we have a shipyard entry with no matching shipdata entry, which we ignore.
	}
	
	_playerShips = [playerShips copy];
	[[OOCacheManager sharedCache] setObject:[_playerShips allObjects] forKey:kPlayerShipsCacheKey inCache:kShipRegistryCacheName];
	
	return YES;
}


- (BOOL) isValidShipEntry:(NSDictionary *)shipEntry name:(NSString *)name
{
	// Quick checks for obvious problems. Not complete validation, just basic sanity checking.
	if (![shipEntry isKindOfClass:[NSDictionary class]])
	{
		OOLog(@"shipData.load.badEntry", @"***** ERROR: the shipdata.plist entry \"%@\" is not a dictionary, ignoring.", name);
		return NO;
	}
	if ([shipEntry stringForKey:@"like_ship"] == nil)	// Keys may be inherited, so we only check "root" ships.
	{
		if ([[shipEntry stringForKey:@"roles"] length] == 0)
		{
			OOLog(@"shipData.load.error", @"***** ERROR: the shipdata.plist entry \"%@\" specifies no %@, ignoring.", name, @"roles");
			return NO;
		}
		if ([[shipEntry stringForKey:@"model"] length] == 0)
		{
			OOLog(@"shipData.load.error", @"***** ERROR: the shipdata.plist entry \"%@\" specifies no %@, ignoring.", name, @"model");
			return NO;
		}
	}
	return YES;
}


- (void) mergeShipRoles:(NSString *)roles
			 forShipKey:(NSString *)shipKey
	 intoProbabilityMap:(NSMutableDictionary *)probabilitySets
{
	NSDictionary			*rolesAndWeights = nil;
	NSEnumerator			*roleEnum = nil;
	NSString				*role = nil;
	OOMutableProbabilitySet	*probSet = nil;
	
	/*	probabilitySets is a dictionary whose keys are roles and whose values
		are mutable probability sets, whose values are ship keys.
	*/
	
	rolesAndWeights = OOParseRolesFromString(roles);
	for (roleEnum = [rolesAndWeights keyEnumerator]; (role = [roleEnum nextObject]); )
	{
		probSet = [probabilitySets objectForKey:role];
		if (probSet == nil)
		{
			probSet = [OOMutableProbabilitySet probabilitySet];
			[probabilitySets setObject:probSet forKey:role];
		}
		
		[probSet setWeight:[rolesAndWeights floatForKey:role] forObject:shipKey];
	}
}

@end


@implementation OOShipRegistry (Singleton)

/*	Canonical singleton boilerplate.
	See Cocoa Fundamentals Guide: Creating a Singleton Instance.
	See also +sharedRegistry above.
	
	NOTE: assumes single-threaded access.
*/

+ (id) allocWithZone:(NSZone *)inZone
{
	if (sSingleton == nil)
	{
		sSingleton = [super allocWithZone:inZone];
		return sSingleton;
	}
	return nil;
}


- (id) copyWithZone:(NSZone *)inZone
{
	return self;
}


- (id) retain
{
	return self;
}


- (unsigned) retainCount
{
	return UINT_MAX;
}


- (void) release
{}


- (id) autorelease
{
	return self;
}

@end
