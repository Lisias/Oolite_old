/*

OORoleSet.m


Copyright (C) 2007-2011 Jens Ayton

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

#import "OORoleSet.h"

#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"
#import "OOLogging.h"


@interface OORoleSet (OOPrivate)

- (id)initWithRolesAndProbabilities:(NSDictionary *)dict;

@end


@implementation OORoleSet

+ (id)roleSetWithString:(NSString *)roleString
{
	return [[[self alloc] initWithRoleString:roleString] autorelease];
}


+ (id)roleSetWithRole:(NSString *)role probability:(float)probability
{
	return [[[self alloc] initWithRole:role probability:probability] autorelease];
}

- (id)initWithRoleString:(NSString *)roleString
{
	NSDictionary			*dict = nil;
	
	dict = OOParseRolesFromString(roleString);
	return [self initWithRolesAndProbabilities:dict];
}


- (id)initWithRole:(NSString *)role probability:(float)probability
{
	NSDictionary			*dict = nil;
	
	if (role != nil && 0 <= probability)
	{
		dict = [NSDictionary dictionaryWithObject:[NSNumber numberWithFloat:probability] forKey:role];
	}
	return [self initWithRolesAndProbabilities:dict];
}


- (void)dealloc
{
	[_roleString autorelease];
	[_rolesAndProbabilities autorelease];
	[_roles autorelease];
	
	[super dealloc];
}


- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p>{%@}", [self class], self, [self roleString]];
}


- (BOOL)isEqual:(id)other
{
	if ([other isKindOfClass:[OORoleSet class]])
	{
		return [_rolesAndProbabilities isEqual:[other rolesAndProbabilities]];
	}
	else  return NO;
}


- (OOUInteger)hash
{
	return [_rolesAndProbabilities hash];
}


- (id)copyWithZone:(NSZone *)zone
{
	// Note: since object is immutable, a copy is no different from the original.
	return [self retain];
}


- (NSString *)roleString
{
	NSArray					*roles = nil;
	NSEnumerator			*roleEnum = nil;
	NSString				*role = nil;
	float					probability;
	NSMutableString			*result = nil;
	BOOL					first = YES;
	
	if (_roleString == nil)
	{
		// Construct role string. We always do this so that it's in a normalized form.
		result = [NSMutableString string];
		roles = [self sortedRoles];
		for (roleEnum = [roles objectEnumerator]; (role = [roleEnum nextObject]); )
		{
			if (!first)  [result appendString:@" "];
			else  first = NO;
			
			[result appendString:role];
			
			probability = [self probabilityForRole:role];
			if (probability != 1.0f)
			{
				[result appendFormat:@"(%g)", probability];
			}
		}
		
		_roleString = [result copy];
	}
	
	return _roleString;
}


- (BOOL)hasRole:(NSString *)role
{
	return role != nil && [_rolesAndProbabilities objectForKey:role] != nil;
}


- (float)probabilityForRole:(NSString *)role
{
	return [_rolesAndProbabilities oo_floatForKey:role defaultValue:0.0f];
}


- (BOOL)intersectsSet:(id)set
{
	if ([set isKindOfClass:[OORoleSet class]])  set = [set roles];
	else  if (![set isKindOfClass:[NSSet class]])  return NO;
	
	return [[self roles] intersectsSet:set];
}


- (NSSet *)roles
{
	if (_roles == nil)
	{
		_roles = [[NSSet alloc] initWithArray:[_rolesAndProbabilities allKeys]];
	}
	return _roles;
}


- (NSArray *)sortedRoles
{
	return [[_rolesAndProbabilities allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
}


- (NSDictionary *)rolesAndProbabilities
{
	return _rolesAndProbabilities;
}


- (NSString *)anyRole
{
	NSEnumerator			*roleEnum = nil;
	NSString				*role;
	float					prob, selected;
	
	selected = randf() * _totalProb;
	prob = 0.0f;
	
	if ([_rolesAndProbabilities count] == 0)  return nil;
	
	for (roleEnum = [_rolesAndProbabilities keyEnumerator]; (role = [roleEnum nextObject]); )
	{
		prob += [_rolesAndProbabilities oo_floatForKey:role];
		if (selected <= prob)  break;
	}
	if (role == nil)
	{
		role = [[self roles] anyObject];
		OOLog(@"roleSet.anyRole.failed", @"Could not get a weighted-random role from role set %@, returning unweighted selection %@. TotalProb: %g, selected: %g, prob at end: %f", self, role, _totalProb, selected, prob);
	}
	return role;
}


- (id)roleSetWithAddedRoleIfNotSet:(NSString *)role probability:(float)probability
{
	NSMutableDictionary		*dict = nil;
	
	if (role == nil || probability < 0 || ([self hasRole:role] && [self probabilityForRole:role] == probability))
	{
		return [[self copy] autorelease];
	}
	
	dict = [[_rolesAndProbabilities mutableCopy] autorelease];
	[dict setObject:[NSNumber numberWithFloat:probability] forKey:role];
	return [[[[self class] alloc] initWithRolesAndProbabilities:dict] autorelease];
}


- (id)roleSetWithAddedRole:(NSString *)role probability:(float)probability
{
	NSMutableDictionary		*dict = nil;
	
	if (role == nil || probability < 0 || [self hasRole:role])
	{
		return [[self copy] autorelease];
	}
	
	dict = [[_rolesAndProbabilities mutableCopy] autorelease];
	[dict setObject:[NSNumber numberWithFloat:probability] forKey:role];
	return [[[[self class] alloc] initWithRolesAndProbabilities:dict] autorelease];
}


- (id)roleSetWithRemovedRole:(NSString *)role
{
	NSMutableDictionary		*dict = nil;
	
	if (![self hasRole:role])  return [[self copy] autorelease];
	
	dict = [[_rolesAndProbabilities mutableCopy] autorelease];
	[dict removeObjectForKey:role];
	return [[[[self class] alloc] initWithRolesAndProbabilities:dict] autorelease];
}

@end


@implementation OORoleSet (OOPrivate)

- (id)initWithRolesAndProbabilities:(NSDictionary *)dict
{
	NSEnumerator			*roleEnum = nil;
	NSString				*role;
	float					prob;
	
	if (dict == nil)
	{
		[self release];
		return nil;
	}
	
	if ([super init] == nil)  return nil;
	
	// Note: _roles and _roleString are derived on the fly as needed.
	// MKW 20090815 - if we are re-initialising this OORoleSet object, we need
	//                to ensure that _roles and _roleString are cleared.
	// Why would we be re-initing? That's never valid. -- Ahruman 2010-02-06
	assert(_roles == nil && _roleString == nil);
	
	NSMutableDictionary		*tDict = [[dict mutableCopy] autorelease];
	float					thargProb = [dict oo_floatForKey:@"thargon" defaultValue:0.0f];
	
	if ( thargProb > 0.0f && [dict objectForKey:@"EQ_THARGON"] == nil)
	{
		OOLogWARN(@"roleSet.deprecated", @"The \"thargon\" role is deprecated, use \"EQ_THARGON\" instead.", role);
		[tDict setObject:[NSNumber numberWithFloat:thargProb] forKey:@"EQ_THARGON"];
		[tDict removeObjectForKey:@"thargon"];
	}
	
	_rolesAndProbabilities = [tDict copy];
	
	for (roleEnum = [dict keyEnumerator]; (role = [roleEnum nextObject]); )
	{
		prob = [dict oo_floatForKey:role defaultValue:-1];
		if (prob < 0)
		{
			OOLog(@"roleSet.badValue", @"Attempt to create a role set with negative or non-numerical probability for role %@.", role);
			[self release];
			return nil;
		}
		
		_totalProb += prob;
	}
	
	return self;
}

@end


NSDictionary *OOParseRolesFromString(NSString *string)
{
	NSMutableDictionary		*result = nil;
	NSArray					*tokens = nil;
	unsigned				i, count;
	NSString				*role = nil;
	float					probability;
	NSScanner				*scanner = nil;
	
	// Split string at spaces, sanity checks, set-up.
	if (string == nil)  return nil;
	
	tokens = ScanTokensFromString(string);
	count = [tokens count];
	if (count == 0)  return nil;
	
	result = [NSMutableDictionary dictionaryWithCapacity:count];
	
	// Scan tokens, looking for probabilities.
	for (i = 0; i != count; ++i)
	{
		role = [tokens objectAtIndex:i];
		
		probability = 1.0f;
		if ([role rangeOfString:@"("].location != NSNotFound)
		{
			scanner = [[NSScanner alloc] initWithString:role];
			[scanner scanUpToString:@"(" intoString:&role];
			[scanner scanString:@"(" intoString:NULL];
			if (![scanner scanFloat:&probability])	probability = 1.0f;
			// Ignore rest of string
			
			[scanner release];
		}
		
		if (0 <= probability)
		{
			[result setObject:[NSNumber numberWithFloat:probability] forKey:role];
		}
	}
	
	if ([result count] == 0)  result = nil;
	return result;
}
