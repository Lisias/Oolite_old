/*

OODeepCopy.m


Copyright (C) 2009-2011 Jens Ayton

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

#import "OODeepCopy.h"


id OODeepCopy(id object)
{
	NSAutoreleasePool			*pool = nil;
	NSMutableSet				*objects = nil;
	
	if (object == nil)  return nil;
	
	pool = [[NSAutoreleasePool alloc] init];
	objects = [NSMutableSet set];
	
	object = [object ooDeepCopyWithSharedObjects:objects];
	
	[pool release];
	
	return object;
}


@implementation NSObject (OODeepCopy)

- (id) ooDeepCopyWithSharedObjects:(NSMutableSet *)objects
{
	if ([self conformsToProtocol:@protocol(NSCopying)])
	{
		return [self copy];
	}
	else
	{
		return [self retain];
	}
}

@end


@implementation NSString (OODeepCopy)

- (id) ooDeepCopyWithSharedObjects:(NSMutableSet *)objects
{
	OOUInteger length = [self length];
	if (length == 0)  return [[NSString string] retain];
	if (length > 128)  return [self copy];
	
	id object = [objects member:self];
	if (object != nil && [object isKindOfClass:[NSString class]])
	{
		return [object retain];
	}
	else
	{
		object = [self copy];
		[objects addObject:object];
		return object;
	}
}

@end


@implementation NSValue (OODeepCopy)	// Includes NSNumber

- (id) ooDeepCopyWithSharedObjects:(NSMutableSet *)objects
{
	id object = [objects member:self];
	if (object != nil && [object isKindOfClass:[NSValue class]])
	{
		return [object retain];
	}
	else
	{
		object = [self copy];
		[objects addObject:object];
		return object;
	}
}

@end


@implementation NSArray (OODeepCopy)

- (id) ooDeepCopyWithSharedObjects:(NSMutableSet *)objects
{
	OOUInteger				i, count;
	id						*members = NULL;
	NSArray					*result = nil;
	BOOL					tempObjects = NO;
	
	count = [self count];
	if (count == 0)  return [[NSArray array] retain];
	
	members = malloc(sizeof *members * count);
	if (members == NULL)
	{
		[NSException raise:NSMallocException format:@"Failed to allocate space for %lu objects in %s.", (unsigned long)count, __PRETTY_FUNCTION__];
	}
	
	// Ensure there's an objects set even if passed nil.
	if (objects == nil)
	{
		objects = [[NSMutableSet alloc] init];
		tempObjects = YES;
	}
	
	[self getObjects:members];
	NS_DURING
		// Deep copy members.
		for (i = 0; i < count; i++)
		{
			members[i] = [members[i] ooDeepCopyWithSharedObjects:objects];
		}
	NS_HANDLER
		// Clean up and rethrow.
		free(members);
		if (tempObjects)  [objects release];
		[localException raise];
	NS_ENDHANDLER
	
#if !OOLITE_MAC_OS_X
	// Make NSArray of results.
	result = [[NSArray alloc] initWithObjects:members count:count];
	
	// Release objects.
	for (i = 0; i < count; i++)
	{
		[members[i] release];
	}
#else
	// Use CF to avoid redundant retain and release.
	CFArrayCallBacks arrayCB = kCFTypeArrayCallBacks;
	arrayCB.version = 0;
	arrayCB.retain = NULL;
	result = (NSArray *)CFArrayCreate(kCFAllocatorDefault, (const void **)members, count, &arrayCB);
#endif
	
	free(members);
	if (tempObjects)  [objects release];
	
	// Collections are not reused because comparing them is arbitrarily slow.
	return result;
}

@end


@implementation NSSet (OODeepCopy)

- (id) ooDeepCopyWithSharedObjects:(NSMutableSet *)objects
{
	OOUInteger				i, count;
	id						*members = NULL;
	NSSet					*result = nil;
	BOOL					tempObjects = NO;
	
	count = [self count];
	if (count == 0)  return [[NSSet set] retain];
	
	members = malloc(sizeof *members * count);
	if (members == NULL)
	{
		[NSException raise:NSMallocException format:@"Failed to allocate space for %lu objects in %s.", (unsigned long)count, __PRETTY_FUNCTION__];
	}
	
	// Ensure there's an objects set even if passed nil.
	if (objects == nil)
	{
		objects = [[NSMutableSet alloc] init];
		tempObjects = YES;
	}
	
	NS_DURING
		i = 0;
		id member = nil;
		// Deep copy members.
		foreach (member, self)
		{
			members[i] = [member ooDeepCopyWithSharedObjects:objects];
			i++;
		}
	NS_HANDLER
		// Clean up and rethrow.
		free(members);
		if (tempObjects)  [objects release];
		[localException raise];
	NS_ENDHANDLER
	
#if !OOLITE_MAC_OS_X
	// Make NSArray of results.
	result = [[NSSet alloc] initWithObjects:members count:count];
	
	// Release objects.
	for (i = 0; i < count; i++)
	{
		[members[i] release];
	}
#else
	// Use CF to avoid redundant retain and release.
	CFSetCallBacks setCB = kCFTypeSetCallBacks;
	setCB.version = 0;
	setCB.retain = NULL;
	result = (NSSet *)CFSetCreate(kCFAllocatorDefault, (const void **)members, count, &setCB);
#endif
	
	free(members);
	if (tempObjects)  [objects release];
	
	// Collections are not reused because comparing them is arbitrarily slow.
	return result;
}

@end


@implementation NSDictionary (OODeepCopy)

- (id) ooDeepCopyWithSharedObjects:(NSMutableSet *)objects
{
	OOUInteger				i, count;
	id						*keys = NULL;
	id						*values = NULL;
	NSDictionary			*result = nil;
	BOOL					tempObjects = NO;
	
	count = [self count];
	if (count == 0)  return [[NSDictionary dictionary] retain];
	
	keys = malloc(sizeof *keys * count);
	values = malloc(sizeof *values * count);
	if (keys == NULL || values == NULL)
	{
		free(keys);
		free(values);
		[NSException raise:NSMallocException format:@"Failed to allocate space for %lu objects in %s.", (unsigned long)count, __PRETTY_FUNCTION__];
	}
	
	// Ensure there's an objects set even if passed nil.
	if (objects == nil)
	{
		objects = [[NSMutableSet alloc] init];
		tempObjects = YES;
	}
	
	NS_DURING
		i = 0;
		id key = nil;
		// Deep copy members.
		foreachkey (key, self)
		{
			keys[i] = [key ooDeepCopyWithSharedObjects:objects];
			values[i] = [[self objectForKey:key] ooDeepCopyWithSharedObjects:objects];
			i++;
		}
	NS_HANDLER
		// Clean up and rethrow.
		free(keys);
		free(values);
		if (tempObjects)  [objects release];
		[localException raise];
	NS_ENDHANDLER
	
#if !OOLITE_MAC_OS_X
	// Make NSArray of results.
	result = [[NSDictionary alloc] initWithObjects:values forKeys:keys count:count];
	
	// Release objects.
	for (i = 0; i < count; i++)
	{
		[keys[i] release];
		[values[i] release];
	}
#else
	// Use CF to avoid redundant retain and release.
	CFDictionaryKeyCallBacks keyCB = kCFTypeDictionaryKeyCallBacks;
	CFDictionaryValueCallBacks valueCB = kCFTypeDictionaryValueCallBacks;
	keyCB.version = 0;
	keyCB.retain = NULL;
	valueCB.version = 0;
	valueCB.retain = NULL;
	result = (NSDictionary *)CFDictionaryCreate(kCFAllocatorDefault, (const void **)keys, (const void **)values, count, &keyCB, &valueCB);
#endif
	
	free(keys);
	free(values);
	if (tempObjects)  [objects release];
	
	// Collections are not reused because comparing them is arbitrarily slow.
	return result;
}

@end
