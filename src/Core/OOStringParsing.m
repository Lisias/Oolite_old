/*

OOStringParsing.m

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

#import "OOStringParsing.h"
#import "OOLogging.h"
#import "NSScannerOOExtensions.h"
#import "legacy_random.h"
#import "Universe.h"
#import "PlayerEntity.h"
#import "PlayerEntityScripting.h"


static NSString * const kOOLogStringVectorConversion			= @"strings.conversion.vector";
static NSString * const kOOLogStringQuaternionConversion		= @"strings.conversion.quaternion";
static NSString * const kOOLogStringVecAndQuatConversion		= @"strings.conversion.vectorAndQuaternion";
static NSString * const kOOLogStringRandomSeedConversion		= @"strings.conversion.randomSeed";
static NSString * const kOOLogExpandDescriptionsRecursionLimitExceeded	= @"strings.expand.recursionLimit";
static NSString * const kOOLogDebugReplaceVariablesInString		= @"script.debug.replaceVariablesInString";


NSMutableArray *ScanTokensFromString(NSString *values)
{
	NSMutableArray			*result = nil;
	NSScanner				*scanner = nil;
	NSString				*token = nil;
	NSCharacterSet			*space_set = nil;
	
	if (values == nil)  return [NSArray array];
	
	result = [NSMutableArray arrayWithCapacity:8];
	
	space_set = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	scanner = [NSScanner scannerWithString:values];
	while (![scanner isAtEnd])
	{
		[scanner ooliteScanCharactersFromSet:space_set intoString:NULL];
		if ([scanner ooliteScanUpToCharactersFromSet:space_set intoString:&token])
		{
			[result addObject:[NSString stringWithString:token]];
		}
	}
	return result;
}

BOOL ScanVectorFromString(NSString *xyzString, Vector *outVector)
{
	GLfloat					xyz[] = {0.0, 0.0, 0.0};
	int						i = 0;
	NSString				*error = nil;
	NSScanner				*scanner = nil;
	
	if (xyzString == nil) return NO;
	else if (outVector == NULL) error = @"nil result pointer";
	
	if (!error) scanner = [NSScanner scannerWithString:xyzString];
	while (![scanner isAtEnd] && i < 3 && !error)
	{
		if (![scanner scanFloat:&xyz[i++]])  error = @"could not scan a float value.";
	}
	
	if (!error && i < 3)  error = @"found less than three float values.";
	
	if (!error)
	{
		*outVector = make_vector(xyz[0], xyz[1], xyz[2]);
		return YES;
	}
	else
	{
		 OOLog(kOOLogStringVectorConversion, @"***** ERROR cannot make vector from '%@': %@", xyzString, error);
		 return NO;
	}
}


BOOL ScanQuaternionFromString(NSString *wxyzString, Quaternion *outQuaternion)
{
	GLfloat					wxyz[] = {1.0, 0.0, 0.0, 0.0};
	int						i = 0;
	NSString				*error = nil;
	NSScanner				*scanner = nil;
	
	if (wxyzString == nil) return NO;
	else if (outQuaternion == NULL) error = @"nil result pointer";
	
	if (!error) scanner = [NSScanner scannerWithString:wxyzString];
	while (![scanner isAtEnd] && i < 4 && !error)
	{
		if (![scanner scanFloat:&wxyz[i++]])  error = @"could not scan a float value.";
	}
	
	if (!error && i < 4)  error = @"found less than four float values.";
	
	if (!error)
	{
		outQuaternion->w = wxyz[0];
		outQuaternion->x = wxyz[1];
		outQuaternion->y = wxyz[2];
		outQuaternion->z = wxyz[3];
		quaternion_normalise(outQuaternion);
		return YES;
	}
	else
	{
		OOLog(kOOLogStringQuaternionConversion, @"***** ERROR cannot make quaternion from '%@': %@", wxyzString, error);
		return NO;
	}
}

BOOL ScanVectorAndQuaternionFromString(NSString *xyzwxyzString, Vector *outVector, Quaternion *outQuaternion)
{
	GLfloat					xyzwxyz[] = { 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0};
	int						i = 0;
	NSString				*error = nil;
	NSScanner				*scanner = nil;
	
	if (xyzwxyzString == nil) return NO;
	else if (outVector == NULL || outQuaternion == NULL) error = @"nil result pointer";
	
	if (!error) scanner = [NSScanner scannerWithString:xyzwxyzString];
	while (![scanner isAtEnd] && i < 7 && !error)
	{
		if (![scanner scanFloat:&xyzwxyz[i++]])  error = @"Could not scan a float value.";
	}
	
	if (!error && i < 7)  error = @"Found less than seven float values.";
	
	if (error)
	{
		OOLog(kOOLogStringQuaternionConversion, @"***** ERROR cannot make vector and quaternion from '%@': %@", xyzwxyzString, error);
		return NO;
	}
	
	outVector->x = xyzwxyz[0];
	outVector->y = xyzwxyz[1];
	outVector->z = xyzwxyz[2];
	outQuaternion->w = xyzwxyz[3];
	outQuaternion->x = xyzwxyz[4];
	outQuaternion->y = xyzwxyz[5];
	outQuaternion->z = xyzwxyz[6];
	
	return YES;
}


Vector VectorFromString(NSString *xyzString, Vector defaultValue)
{
	Vector result;
	if (!ScanVectorFromString(xyzString, &result))  result = defaultValue;
	return result;
}


Quaternion QuaternionFromString(NSString *wxyzString, Quaternion defaultValue)
{
	Quaternion result;
	if (!ScanQuaternionFromString(wxyzString, &result))  result = defaultValue;
	return result;
}


NSString *StringFromPoint(NSPoint point)
{
	return [NSString stringWithFormat:@"%f %f", point.x, point.y];
}


NSPoint PointFromString(NSString *xyString)
{
	NSArray		*tokens = ScanTokensFromString(xyString);
	NSPoint		result = NSZeroPoint;
	
	int n_tokens = [tokens count];
	if (n_tokens == 2)
	{
		result.x = [[tokens objectAtIndex:0] floatValue];
		result.y = [[tokens objectAtIndex:1] floatValue];
	}
	return result;
}


Random_Seed RandomSeedFromString(NSString *abcdefString)
{
	Random_Seed				result;
	int						abcdef[] = { 0, 0, 0, 0, 0, 0};
	int						i = 0;
	NSString				*error = nil;
	NSScanner				*scanner = [NSScanner scannerWithString:abcdefString];
	
	while (![scanner isAtEnd] && i < 6 && !error)
	{
		if (![scanner scanInt:&abcdef[i++]])  error = @"could not scan a int value.";
	}
	
	if (!error && i < 6)  error = @"found less than six int values.";
	
	if (!error)
	{
		result.a = abcdef[0];
		result.b = abcdef[1];
		result.c = abcdef[2];
		result.d = abcdef[3];
		result.e = abcdef[4];
		result.f = abcdef[5];
	}
	else
	{
		OOLog(kOOLogStringRandomSeedConversion, @"***** ERROR cannot make Random_Seed from '%@': %@", abcdefString, error);
		result = nil_seed();
	}
	
	return result;
}


NSString *ExpandDescriptionForSeed(NSString *text, Random_Seed seed)
{
	// to enable variables to return strings that can be expanded (eg. @"[commanderName_string]")
	// we're going to loop until every expansion has been done!
	// but to check this does not infinitely recurse
	// we'll stop after 32 loops.
	
	int stack_check = 32;
	NSString	*old_desc = [NSString stringWithString:text];
	NSString	*result = text;
	
	do
	{
		old_desc = result;
		result = ExpandDescriptionsWithLocalsForSystemSeed(text, seed, nil);
	} while (--stack_check && ![result isEqual:old_desc]);
	
	if (!stack_check)
	{
		OOLog(kOOLogExpandDescriptionsRecursionLimitExceeded, @"***** ERROR: exceeded recusion limit trying to expand description \"%@\"", text);
		#if 0
			// What's the point of breaking? A bad description is better than falling to pieces.
			[NSException raise:OOLITE_EXCEPTION_LOOPING
						format:@"script stack overflow for expandDescription: \"%@\"", text];
		#endif
	}
	
	return result;
}


NSString *ExpandDescriptionForCurrentSystem(NSString *text)
{
	return ExpandDescriptionForSeed(text, [[PlayerEntity sharedPlayer] system_seed]);
}


NSString *ExpandDescriptionsWithLocalsForSystemSeed(NSString *text, Random_Seed seed, NSDictionary *locals)
{
	Universe			*universe = [Universe sharedUniverse];
	PlayerEntity		*player = [PlayerEntity sharedPlayer];
	NSMutableString		*partial = [text mutableCopy];
	NSMutableDictionary	*all_descriptions = [[universe descriptions] mutableCopy];
	id					value = nil;
	NSString			*part = nil, *before = nil, *after = nil, *middle = nil;
	int					sub, rnd, opt;
	int					p1, p2;
	
	// add in player info if required
	// -- this is now duplicated with new commanderXXX_string and commanderYYY_number methods in PlayerEntity Additions -- GILES
	
	if ([text rangeOfString:@"[commander_"].location != NSNotFound)
	{
		[all_descriptions setObject:[player commanderName_string] forKey:@"commander_name"];
		[all_descriptions setObject:[player commanderShip_string] forKey:@"commander_shipname"];
		[all_descriptions setObject:[player commanderRank_string] forKey:@"commander_rank"];
		[all_descriptions setObject:[player commanderLegalStatus_string] forKey:@"commander_legal_status"];
	}
	
	while ([partial rangeOfString:@"["].location != NSNotFound)
	{
		p1 = [partial rangeOfString:@"["].location;
		p2 = [partial rangeOfString:@"]"].location + 1;
		
		before = [partial substringWithRange:NSMakeRange(0, p1)];
		after = [partial substringWithRange:NSMakeRange(p2,[partial length] - p2)];
		middle = [partial substringWithRange:NSMakeRange(p1 + 1 , p2 - p1 - 2)];
		
		// check all_descriptions for an array that's keyed to middle
		value = [all_descriptions objectForKey:middle];
		if ([value isKindOfClass:[NSArray class]])
		{
			rnd = gen_rnd_number() % [value count];
			part = [NSString stringWithString:(NSString *)[value objectAtIndex:rnd]];
		}
		else if ([value isKindOfClass:[NSString class]])
		{
			part = [all_descriptions objectForKey:middle];
		}
		else if ([[middle stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"]] isEqual:@""])
		{
			// if all characters are all from the set "0123456789" interpret it as a number in system_description array
			if (![middle isEqual:@""])
			{
				sub = [middle intValue];
				
				rnd = gen_rnd_number();
				opt = 0;
				if (rnd >= 0x33) opt++;
				if (rnd >= 0x66) opt++;
				if (rnd >= 0x99) opt++;
				if (rnd >= 0xCC) opt++;
				
				part = [[[all_descriptions objectForKey:@"system_description"] objectAtIndex:sub] objectAtIndex:opt];
			}
			else
				part = @"";
		}
		else
		{
			// do replacement of mission and local variables here instead
			part = ReplaceVariables(middle, NULL, NULL);
		}
		
		partial = [NSMutableString stringWithFormat:@"%@%@%@",before,part,after];
	}
		
	[partial	replaceOccurrencesOfString:@"%H"
				withString:[universe generateSystemName:seed]
				options:NSLiteralSearch range:NSMakeRange(0, [partial length])];
	
	[partial	replaceOccurrencesOfString:@"%I"
				withString:[NSString stringWithFormat:@"%@ian",[universe generateSystemName:seed]]
				options:NSLiteralSearch range:NSMakeRange(0, [partial length])];
	
	[partial	replaceOccurrencesOfString:@"%R"
				withString:[universe getRandomDigrams]
				options:NSLiteralSearch range:NSMakeRange(0, [partial length])];

	return partial; 
}


NSString *ExpandDescriptionsWithLocalsForCurrentSystem(NSString *text, NSDictionary *locals)
{
	return ExpandDescriptionsWithLocalsForSystemSeed(text, [[PlayerEntity sharedPlayer] system_seed], locals);
}


NSString *ReplaceVariables(NSString *string, Entity *target, NSDictionary *localVariables)
{
	NSMutableString			*resultString = nil;
	NSMutableArray			*tokens = nil;
	NSEnumerator			*tokenEnum = nil;
	NSString				*token = nil;
	NSString				*replacement = nil;
	Entity					*effeciveTarget = nil;
	PlayerEntity			*player = nil;
	
	tokens = ScanTokensFromString(string);
	resultString = [NSMutableString stringWithString:string];
	player = [PlayerEntity sharedPlayer];
	if (target == nil) target = player;
	
	for (tokenEnum = [tokens objectEnumerator]; (token = [tokenEnum nextObject]); )
	{
		replacement = [player missionVariableForKey:token];
		if (replacement == nil)  replacement = [localVariables objectForKey:token];
		if (replacement == nil)
		{
			if ([token hasSuffix:@"_number"] || [token hasSuffix:@"_bool"] || [token hasSuffix:@"_string"])
			{
				SEL value_selector = NSSelectorFromString(token);
				if ([target respondsToSelector:value_selector]) effeciveTarget = target;
				else if (target != player && [player respondsToSelector:value_selector]) effeciveTarget = player;
				else effeciveTarget = nil;
				
				if (effeciveTarget != nil)  replacement = [[effeciveTarget performSelector:value_selector] description];
			}
			else if ([token hasPrefix:@"["] && [token hasSuffix:@"]"])
			{
				replacement = ExpandDescriptionForCurrentSystem(token);
			}
		}
		
		if (replacement != nil) [resultString replaceOccurrencesOfString:token withString:replacement options:NSLiteralSearch range:NSMakeRange(0, [resultString length])];
	}

	OOLog(kOOLogDebugReplaceVariablesInString, @"EXPANSION: \"%@\" becomes \"%@\"", string, resultString);

	return resultString;
}
