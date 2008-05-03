/*

OOProbabilitySet.m


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


IMPLEMENTATION NOTES
OOProbabilitySet is implemented as a class cluster with two abstract classes,
two special-case implementations for immutable sets with zero or one object,
and two general implementations (one mutable and one immutable). The general
implementations are the only non-trivial ones.

The general immutable implementation, OOConcreteProbabilitySet, consists of
two parallel arrays, one of objects and one of cumulative weights. The
"cumulative weight" for an entry is the sum of its weight and the cumulative
weight of the entry to the left (i.e., with a lower index), with the implicit
entry -1 having a cumulative weight of 0. Since weight cannot be negative,
this means that cumulative weights increase to the right (not strictly
increasing, though, since weights may be zero). We can thus find an object
with a given cumulative weight through a binary search.

OOConcreteMutableProbabilitySet is a naïve implementation using arrays. It
could be optimized, but isn't expected to be used much except for building
sets that will then be immutablized.

*/

#import "OOProbabilitySet.h"
#import "OOFunctionAttributes.h"
#import "OOCollectionExtractors.h"
#import "legacy_random.h"


static NSString * const	kObjectsKey = @"objects";
static NSString * const	kWeightsKey = @"weights";


@protocol OOProbabilitySetEnumerable <NSObject>

- (id) privObjectAtIndex:(unsigned long)index;

@end


@interface OOProbabilitySet (OOPrivate)

// Designated initializer. This must be used by subclasses, since init is overriden for public use.
- (id) initPriv;

@end


@interface OOEmptyProbabilitySet: OOProbabilitySet

+ (OOEmptyProbabilitySet *) singleton;

@end


@interface OOSingleObjectProbabilitySet: OOProbabilitySet
{
	id					_object;
	float				_weight;
}

- (id) initWithObject:(id)object weight:(float)weight;

@end


@interface OOConcreteProbabilitySet: OOProbabilitySet <OOProbabilitySetEnumerable>
{
	unsigned long		_count;
	id					*_objects;
	float				*_cumulativeWeights;	// Each cumulative weight is weight of object at this index + weight of all objects to left.
	float				_sumOfWeights;
}
@end


@interface OOConcreteMutableProbabilitySet: OOMutableProbabilitySet
{
	NSMutableArray		*_objects;
	NSMutableArray		*_weights;
	float				_sumOfWeights;
}
@end


@interface OOProbabilitySetEnumerator: NSEnumerator
{
	id					_enumerable;
	unsigned long		_index;
}

- (id) initWithEnumerable:(id<OOProbabilitySetEnumerable>)enumerable;

@end


static void ThrowAbstractionViolationException(id obj)  GCC_ATTR((noreturn));


@implementation OOProbabilitySet

// Abstract class just tosses allocations over to concrete class, and throws exception if you try to use it directly.

+ (id) probabilitySet
{
	return [OOEmptyProbabilitySet singleton];
}


+ (id) probabilitySetWithObjects:(id *)objects weights:(float *)weights count:(unsigned long)count
{
	return [[[self alloc] initWithObjects:objects weights:weights count:count] autorelease];
}


+ (id) probabilitySetWithPropertyListRepresentation:(NSDictionary *)plist
{
	return [[[self alloc] initWithPropertyListRepresentation:plist] autorelease];
}


- (id) init
{
	[self release];
	return [OOEmptyProbabilitySet singleton];
}


- (id) initWithObjects:(id *)objects weights:(float *)weights count:(unsigned)count
{
	NSZone *zone = [self zone];
	[self release];
	self = nil;
	
	// Zero objects: return empty-set singleton.
	if (count == 0)  return [OOEmptyProbabilitySet singleton];
	
	// If count is not zero and one of the paramters is nil, we've got us a programming error.
	if (objects == NULL || weights == NULL)
	{
		[NSException raise:NSInvalidArgumentException format:@"Attempt to create %@ with non-zero count but nil objects or weights.", @"OOProbabilitySet"];
	}
	
	// Single object: simple one-object set. Expected to be quite common.
	if (count == 1)  return [[OOSingleObjectProbabilitySet allocWithZone:zone] initWithObject:objects[0] weight:weights[0]];
	
	// Otherwise, use general implementation.
	return [[OOConcreteProbabilitySet allocWithZone:zone] initWithObjects:objects weights:weights count:count];
}


- (id) initWithPropertyListRepresentation:(NSDictionary *)plist
{
	NSArray					*objects = nil;
	NSArray					*weights = nil;
	unsigned long			i = 0, count = 0;
	id						*rawObjects = NULL;
	float					*rawWeights = NULL;
	
	objects = [plist arrayForKey:kObjectsKey];
	weights = [plist arrayForKey:kWeightsKey];
	
	// Validate
	if (objects == nil || weights == nil)  return nil;
	count = [objects count];
	if (count != [weights count])  return nil;
	
	// Extract contents.
	rawObjects = malloc(sizeof *rawObjects * count);
	rawWeights = malloc(sizeof *rawWeights * count);
	
	if (rawObjects != NULL || rawWeights != NULL)
	{
		// Extract objects.
		[objects getObjects:rawObjects];
		
		// Extract and convert weights.
		for (i = 0; i < count; ++i)
		{
			rawWeights[i] = fmaxf([weights floatAtIndex:i], 0.0f);
		}
		
		self = [self initWithObjects:rawObjects weights:rawWeights count:count];
	}
	else
	{
		self = nil;
	}
	
	// Clean up.
	free(rawObjects);
	free(rawWeights);
	
	return self;
}


- (id) initPriv
{
	return [super init];
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"count=%lu", [self count]];
}


- (NSDictionary *) propertyListRepresentation
{
	ThrowAbstractionViolationException(self);
}

- (id) randomObject
{
	ThrowAbstractionViolationException(self);
}


- (float) weightForObject:(id)object
{
	ThrowAbstractionViolationException(self);
}


- (float) sumOfWeights
{
	ThrowAbstractionViolationException(self);
}


- (unsigned long) count
{
	ThrowAbstractionViolationException(self);
}


- (NSArray *) allObjects
{
	ThrowAbstractionViolationException(self);
}


- (id) copyWithZone:(NSZone *)zone
{
	if (zone == [self zone])
	{
		return [self retain];
	}
	else
	{
		return [[OOProbabilitySet allocWithZone:zone] initWithPropertyListRepresentation:[self propertyListRepresentation]];
	}
}


- (id) mutableCopyWithZone:(NSZone *)zone
{
	return [[OOMutableProbabilitySet allocWithZone:zone] initWithPropertyListRepresentation:[self propertyListRepresentation]];
}

@end


@implementation OOProbabilitySet (OOExtendedProbabilitySet)

- (BOOL) containsObject:(id)object
{
	return [self weightForObject:object] >= 0.0f;
}


- (NSEnumerator *) objectEnumerator
{
	return [[self allObjects] objectEnumerator];
}


- (float) probabilityForObject:(id)object
{
	float weight = [self weightForObject:object];
	if (weight > 0)  weight /= [self sumOfWeights];
	
	return weight;
}

@end


static OOEmptyProbabilitySet *sOOEmptyProbabilitySetSingleton = nil;

@implementation OOEmptyProbabilitySet: OOProbabilitySet

+ (OOEmptyProbabilitySet *) singleton
{
	if (sOOEmptyProbabilitySetSingleton == nil)
	{
		[[self alloc] init];
	}
	
	return sOOEmptyProbabilitySetSingleton;
}


- (NSDictionary *) propertyListRepresentation
{
	NSArray *empty = [NSArray array];
	return [NSDictionary dictionaryWithObjectsAndKeys:empty, kObjectsKey, empty, kWeightsKey, nil];
}


- (id) randomObject
{
	return nil;
}


- (float) weightForObject:(id)object
{
	return -1.0f;
}


- (float) sumOfWeights
{
	return 0.0f;
}


- (unsigned long) count
{
	return 0;
}


- (NSArray *) allObjects
{
	return [NSArray array];
}

@end


@implementation OOEmptyProbabilitySet (Singleton)

/*	Canonical singleton boilerplate.
	See Cocoa Fundamentals Guide: Creating a Singleton Instance.
	See also +singleton above.
	
	NOTE: assumes single-threaded access.
*/

+ (id) allocWithZone:(NSZone *)inZone
{
	if (sOOEmptyProbabilitySetSingleton == nil)
	{
		sOOEmptyProbabilitySetSingleton = [super allocWithZone:inZone];
		return sOOEmptyProbabilitySetSingleton;
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


@implementation OOSingleObjectProbabilitySet: OOProbabilitySet

- (id) initWithObject:(id)object weight:(float)weight
{
	if (object == nil)
	{
		[self release];
		return nil;
	}
	
	if ((self = [super initPriv]))
	{
		_object = [object retain];
		_weight = fmaxf(weight, 0.0f);
	}
	
	return self;
}


- (void) dealloc
{
	[_object release];
	
	[super dealloc];
}


- (NSDictionary *) propertyListRepresentation
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
			[NSArray arrayWithObject:_object], kObjectsKey,
			[NSArray arrayWithObject:[NSNumber numberWithFloat:_weight]], kWeightsKey,
			nil];
}


- (id) randomObject
{
	return _object;
}


- (float) weightForObject:(id)object
{
	if ([_object isEqual:object])  return _weight;
	else return -1.0f;
}


- (float) sumOfWeights
{
	return _weight;
}


- (unsigned long) count
{
	return 1;
}


- (NSArray *) allObjects
{
	return [NSArray arrayWithObject:_object];
}

@end


@implementation OOConcreteProbabilitySet

- (id) initWithObjects:(id *)objects weights:(float *)weights count:(unsigned)count
{
	unsigned long			i = 0;
	float					cuWeight = 0.0f;
	
	assert(count > 1 && objects != NULL && weights != NULL);
	
	if ((self = [super initPriv]))
	{
		// Allocate arrays
		_objects = malloc(sizeof *objects * count);
		_cumulativeWeights = malloc(sizeof *_cumulativeWeights * count);
		if (_objects == NULL || _cumulativeWeights == NULL)
		{
			[self release];
			return nil;
		}
		
		// Fill in arrays, retain objects, add up weights.
		for (i = 0; i != count; ++i)
		{
			_objects[i] = [objects[i] retain];
			cuWeight += weights[i];
			_cumulativeWeights[i] = cuWeight;
		}
		_count = count;
		_sumOfWeights = cuWeight;
	}
	
	return self;
}


- (void) dealloc
{
	unsigned long			i = 0;
	
	if (_objects != NULL)
	{
		for (i = 0; i < _count; ++i)
		{
			[_objects[i] release];
		}
		free(_objects);
		_objects = NULL;
	}
	
	if (_cumulativeWeights != NULL)
	{
		free(_cumulativeWeights);
		_cumulativeWeights = NULL;
	}
	
	[super dealloc];
}


- (NSDictionary *) propertyListRepresentation
{
	NSArray					*objects = nil;
	NSMutableArray			*weights = nil;
	float					cuWeight = 0.0f, sum = 0.0f;
	unsigned long			i = 0;
	
	objects = [NSArray arrayWithObjects:_objects count:_count];
	weights = [NSMutableArray arrayWithCapacity:_count];
	for (i = 0; i < _count; ++i)
	{
		cuWeight = _cumulativeWeights[i];
		[weights addFloat:cuWeight - sum];
		sum = cuWeight;
	}
	
	return [NSDictionary dictionaryWithObjectsAndKeys:
			objects, kObjectsKey,
			[[weights copy] autorelease], kWeightsKey,
			nil];
}

- (unsigned long) count
{
	return _count;
}


- (id) privObjectForWeight:(float)target
{
	/*	Select an object at random. This is a binary search in the cumulative
		weights array. Since weights of zero are allowed, there may be several
		objects with the same cumulative weight, in which case we select the
		leftmost, i.e. the one where the delta is non-zero.
	*/
	
	unsigned long				low = 0, high = _count - 1, idx = 0;
	float						weight;
	
	while (low < high)
	{
		idx = (low + high) / 2;
		weight = _cumulativeWeights[idx];
		if (weight > target)
		{
			if (EXPECT_NOT(idx == 0))  break;
			high = idx - 1;
		}
		else if (weight < target)  low = idx + 1;
		else break;
	}
	
	if (weight > target)
	{
		while (idx > 0 && _cumulativeWeights[idx - 1] >= target)  --idx;
	}
	else
	{
		while (idx < (_count - 1) && _cumulativeWeights[idx] < target)  ++idx;
	}
	
	assert(idx < _count);
	id result = _objects[idx];
	return result;
}


- (id) randomObject
{
	if (_sumOfWeights <= 0.0f)  return nil;
	return [self privObjectForWeight:randf() * _sumOfWeights];
}


- (float) weightForObject:(id)object
{
	unsigned long				i;
	
	// Can't have nil in collection.
	if (object == nil)  return -1.0f;
	
	// Perform linear search, then get weight by subtracting cumulative weight from cumulative weight to left.
	for (i = 0; i < _count; ++i)
	{
		if ([_objects[i] isEqual:object])
		{
			float leftWeight = (i != 0) ? _cumulativeWeights[i - 1] : 0.0f;
			return _cumulativeWeights[i] - leftWeight;
		}
	}
	
	// If we got here, object not found.
	return -1.0f;
}


- (float) sumOfWeights
{
	return _sumOfWeights;
}


- (NSArray *) allObjects
{
	return [NSArray arrayWithObjects:_objects count:_count];
}


- (NSEnumerator *) objectEnumerator
{
	return [[[OOProbabilitySetEnumerator alloc] initWithEnumerable:self] autorelease];
}


- (id) privObjectAtIndex:(unsigned long)index
{
	return (index < _count) ? _objects[index] : nil;
}

@end


@implementation OOMutableProbabilitySet

+ (id) probabilitySet
{
	return [[[OOConcreteMutableProbabilitySet alloc] initPriv] autorelease];
}


- (id) init
{
	NSZone *zone = [self zone];
	[self release];
	return [[OOConcreteMutableProbabilitySet allocWithZone:zone] initPriv];
}


- (id) initWithObjects:(id *)objects weights:(float *)weights count:(unsigned)count
{
	NSZone *zone = [self zone];
	[self release];
	return [[OOConcreteMutableProbabilitySet allocWithZone:zone] initWithObjects:objects weights:weights count:count];
}


- (id) initWithPropertyListRepresentation:(NSDictionary *)plist
{
	NSZone *zone = [self zone];
	[self release];
	return [[OOConcreteMutableProbabilitySet allocWithZone:zone] initWithPropertyListRepresentation:plist];
}


- (id) copyWithZone:(NSZone *)zone
{
	return [[OOProbabilitySet allocWithZone:zone] initWithPropertyListRepresentation:[self propertyListRepresentation]];
}


- (void) setWeight:(float)weight forObject:(id)object
{
	ThrowAbstractionViolationException(self);
}


- (void) removeObject:(id)object
{
	ThrowAbstractionViolationException(self);
}

@end


@implementation OOConcreteMutableProbabilitySet

- (id) initPriv
{
	if ((self = [super initPriv]))
	{
		_objects = [[NSMutableArray alloc] init];
		_weights = [[NSMutableArray alloc] init];
	}
	
	return self;
}


- (id) initWithObjects:(id *)objects weights:(float *)weights count:(unsigned)count
{
	unsigned long			i = 0;
	
	// Validate parameters.
	if (count != 0 && (objects == NULL || weights == NULL))
	{
		[self release];
		[NSException raise:NSInvalidArgumentException format:@"Attempt to create %@ with non-zero count but nil objects or weights.", @"OOMutableProbabilitySet"];
	}
	
	// Set up & go.
	if ((self == [self initPriv]))
	{
		for (i = 0; i != count; ++i)
		{
			[self setWeight:fmaxf(weights[i], 0.0f) forObject:objects[i]];
		}
	}
	
	return self;
}


- (id) initWithPropertyListRepresentation:(NSDictionary *)plist
{
	BOOL					OK = YES;
	NSArray					*objects = nil;
	NSArray					*weights = nil;
	unsigned long			i = 0, count = 0;
	
	if (!(self = [super initPriv]))  OK = NO;
	
	if (OK)
	{
		objects = [plist arrayForKey:kObjectsKey];
		weights = [plist arrayForKey:kWeightsKey];
		
		// Validate
		if (objects == nil || weights == nil)  OK = NO;
		count = [objects count];
		if (count != [weights count])  OK = NO;
	}
	
	if (OK)
	{
		for (i = 0; i <= count; ++i)
		{
			[self setWeight:[weights floatAtIndex:i] forObject:[objects objectAtIndex:i]];
		}
	}
	
	if (!OK)
	{
		[self release];
		self = nil;
	}
	
	return self;
}


- (void) dealloc
{
	[_objects release];
	[_weights release];
	
	[super dealloc];
}


- (NSDictionary *) propertyListRepresentation
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
			_objects, kObjectsKey,
			_weights, kWeightsKey,
			nil];
}


- (unsigned long) count
{
	return [_objects count];
}


- (id) randomObject
{
	float					target = 0.0f, sum = 0.0f;
	unsigned				i = 0, count = 0;
	
	target = randf() * _sumOfWeights;
	count = [_objects count];
	if (count == 0 || _sumOfWeights <= 0.0f)  return nil;
	
	for (i = 0; i < count; ++i)
	{
		sum += [_weights floatAtIndex:i];
		if (sum >= target)  return [_objects objectAtIndex:i];
	}
	
	OOLog(@"probabilitySet.broken", @"%s fell off end, returning first object. Sum = %f, target = %f, count = %u. This is an internal error, please report it.", __PRETTY_FUNCTION__, _sumOfWeights, target, count);
	return [_objects objectAtIndex:0];
}


- (float) weightForObject:(id)object
{
	float					result = -1.0f;
	
	if (object != nil)
	{
		unsigned long index = [_objects indexOfObject:object];
		if (index != NSNotFound)
		{
			result = [_weights floatAtIndex:index];
			if (index != 0)  result -= [_weights floatAtIndex:index - 1];
		}
	}
	return result;
}


- (float) sumOfWeights
{
	return _sumOfWeights;
}


- (NSArray *) allObjects
{
	return [[_objects copy] autorelease];
}


- (NSEnumerator *) objectEnumerator
{
	return [_objects objectEnumerator];
}


- (void) setWeight:(float)weight forObject:(id)object
{
	if (object == nil)  return;
	
	weight = fmaxf(weight, 0.0f);
	unsigned long index = [_objects indexOfObject:object];
	if (index == NSNotFound)
	{
		[_objects addObject:object];
		[_weights addFloat:weight];
		_sumOfWeights += weight;
	}
	else
	{
		_sumOfWeights -= [_weights floatAtIndex:index];
		_sumOfWeights += weight;
		[_weights replaceObjectAtIndex:index withObject:[NSNumber numberWithFloat:weight]];
	}
}


- (void) removeObject:(id)object
{
	if (object != nil)  return;
	
	unsigned long index = [_objects indexOfObject:object];
	if (index != NSNotFound)
	{
		[_objects removeObjectAtIndex:index];
		_sumOfWeights -= [_weights floatAtIndex:index];
		[_weights removeObjectAtIndex:index];
	}
}

@end


@implementation OOProbabilitySetEnumerator

- (id) initWithEnumerable:(id<OOProbabilitySetEnumerable>)enumerable
{
	if ((self = [super init]))
	{
		_enumerable = [enumerable retain];
	}
	
	return self;
}


- (void) dealloc
{
	[_enumerable release];
	
	[super dealloc];
}


- (id) nextObject
{
	if (_index < [_enumerable count])
	{
		return [_enumerable privObjectAtIndex:_index++];
	}
	else
	{
		[_enumerable release];
		_enumerable = nil;
		return nil;
	}
}

@end


static void ThrowAbstractionViolationException(id obj)
{
	[NSException raise:NSGenericException format:@"Attempt to use abstract class %@ - this indicates an incorrect initialization.", [obj class]];
	abort();	// unreachable
}
