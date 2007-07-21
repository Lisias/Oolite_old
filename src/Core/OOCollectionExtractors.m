/*

OOCollectionExtractors.m

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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2007 Jens Ayton

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

#import "OOCollectionExtractors.h"
#import <limits.h>
#import "OOMaths.h"
#import "OOStringParsing.h"


static NSSet *SetForObject(id object, NSSet *defaultValue);


@implementation NSArray (OOExtractor)

- (char)charAtIndex:(unsigned)index defaultValue:(char)value
{
	return OOCharFromObject([self objectAtIndex:index], value);
}


- (short)shortAtIndex:(unsigned)index defaultValue:(short)value
{
	return OOShortFromObject([self objectAtIndex:index], value);
}


- (int)intAtIndex:(unsigned)index defaultValue:(int)value
{
	return OOIntFromObject([self objectAtIndex:index], value);
}


- (long)longAtIndex:(unsigned)index defaultValue:(long)value
{
	return OOLongFromObject([self objectAtIndex:index], value);
}


- (long long)longLongAtIndex:(unsigned)index defaultValue:(long long)value
{
	return OOLongLongFromObject([self objectAtIndex:index], value);
}


- (unsigned char)unsignedCharAtIndex:(unsigned)index defaultValue:(unsigned char)value
{
	return OOUnsignedCharFromObject([self objectAtIndex:index], value);
}


- (unsigned short)unsignedShortAtIndex:(unsigned)index defaultValue:(unsigned short)value
{
	return OOUnsignedShortFromObject([self objectAtIndex:index], value);
}


- (unsigned int)unsignedIntAtIndex:(unsigned)index defaultValue:(unsigned int)value
{
	return OOUnsignedIntFromObject([self objectAtIndex:index], value);
}


- (unsigned long)unsignedLongAtIndex:(unsigned)index defaultValue:(unsigned long)value
{
	return OOUnsignedLongFromObject([self objectAtIndex:index], value);
}


- (unsigned long long)unsignedLongLongAtIndex:(unsigned)index defaultValue:(unsigned long long)value
{
	return OOUnsignedLongLongFromObject([self objectAtIndex:index], value);
}


- (BOOL)boolAtIndex:(unsigned)index defaultValue:(BOOL)value
{
	return OOBooleanFromObject([self objectAtIndex:index], value);
}


- (BOOL)fuzzyBooleanAtIndex:(unsigned)index defaultValue:(float)value
{
	return OOFuzzyBooleanFromObject([self objectAtIndex:index], value);
}


- (float)floatAtIndex:(unsigned)index defaultValue:(float)value
{
	return OOFloatFromObject([self objectAtIndex:index], value);
}


- (double)doubleAtIndex:(unsigned)index defaultValue:(double)value
{
	return OODoubleFromObject([self objectAtIndex:index], value);
}


- (float)nonNegativeFloatAtIndex:(unsigned)index defaultValue:(float)value
{
	return OONonNegativeFloatFromObject([self objectAtIndex:index], value);
}


- (double)nonNegativeDoubleAtIndex:(unsigned)index defaultValue:(double)value
{
	return OONonNegativeDoubleFromObject([self objectAtIndex:index], value);
}


- (id)objectAtIndex:(unsigned)index defaultValue:(id)value
{
	id					objVal = [self objectAtIndex:index];
	id					result;
	
	if (objVal != nil)  result = objVal;
	else  result = value;
	
	return result;
}


- (id)objectOfClass:(Class)class atIndex:(unsigned)index defaultValue:(id)value
{
	id					objVal = [self objectAtIndex:index];
	NSString			*result;
	
	if ([objVal isKindOfClass:class])  result = objVal;
	else  result = value;
	
	return result;
}


- (NSString *)stringAtIndex:(unsigned)index defaultValue:(NSString *)value
{
	return [self objectOfClass:[NSString class] atIndex:index defaultValue:value];
}


- (NSArray *)arrayAtIndex:(unsigned)index defaultValue:(NSArray *)value
{
	return [self objectOfClass:[NSArray class] atIndex:index defaultValue:value];
}


- (NSSet *)setAtIndex:(unsigned)index defaultValue:(NSSet *)value
{
	return SetForObject([self objectAtIndex:index], value);
}


- (NSDictionary *)dictionaryAtIndex:(unsigned)index defaultValue:(NSDictionary *)value
{
	return [self objectOfClass:[NSDictionary class] atIndex:index defaultValue:value];
}


- (NSData *)dataAtIndex:(unsigned)index defaultValue:(NSData *)value
{
	return [self objectOfClass:[NSData class] atIndex:index defaultValue:value];
}


- (struct Vector)vectorAtIndex:(unsigned)index defaultValue:(struct Vector)value
{
	return OOVectorFromObject([self objectAtIndex:index], value);
}


- (struct Quaternion)quaternionAtIndex:(unsigned)index defaultValue:(struct Quaternion)value;
{
	return OOQuaternionFromObject([self objectAtIndex:index], value);
}


- (char)charAtIndex:(unsigned)index
{
	return [self charAtIndex:index defaultValue:0];
}


- (short)shortAtIndex:(unsigned)index
{
	return [self shortAtIndex:index defaultValue:0];
}


- (int)intAtIndex:(unsigned)index
{
	return [self intAtIndex:index defaultValue:0];
}


- (long)longAtIndex:(unsigned)index
{
	return [self longAtIndex:index defaultValue:0];
}


- (long long)longLongAtIndex:(unsigned)index
{
	return [self longLongAtIndex:index defaultValue:0];
}


- (unsigned char)unsignedCharAtIndex:(unsigned)index
{
	return [self unsignedCharAtIndex:index defaultValue:0];
}


- (unsigned short)unsignedShortAtIndex:(unsigned)index
{
	return [self unsignedShortAtIndex:index defaultValue:0];
}


- (unsigned int)unsignedIntAtIndex:(unsigned)index
{
	return [self unsignedIntAtIndex:index defaultValue:0];
}


- (unsigned long)unsignedLongAtIndex:(unsigned)index
{
	return [self unsignedLongAtIndex:index defaultValue:0];
}


- (unsigned long long)unsignedLongLongAtIndex:(unsigned)index
{
	return [self unsignedLongLongAtIndex:index defaultValue:0];
}


- (BOOL)boolAtIndex:(unsigned)index
{
	return [self boolAtIndex:index defaultValue:NO];
}


- (BOOL)fuzzyBooleanAtIndex:(unsigned)index
{
	return [self fuzzyBooleanAtIndex:index defaultValue:0.0f];
}


- (float)floatAtIndex:(unsigned)index
{
	return OOFloatFromObject([self objectAtIndex:index], 0.0f);
}


- (double)doubleAtIndex:(unsigned)index
{
	return OODoubleFromObject([self objectAtIndex:index], 0.0);
}


- (float)nonNegativeFloatAtIndex:(unsigned)index
{
	return OONonNegativeFloatFromObject([self objectAtIndex:index], 0.0f);
}


- (double)nonNegativeDoubleAtIndex:(unsigned)index
{
	return OONonNegativeDoubleFromObject([self objectAtIndex:index], 0.0);
}


- (id)objectOfClass:(Class)class atIndex:(unsigned)index
{
	return [self objectOfClass:class atIndex:index defaultValue:nil];
}


- (NSString *)stringAtIndex:(unsigned)index
{
	return [self stringAtIndex:index defaultValue:nil];
}


- (NSArray *)arrayAtIndex:(unsigned)index
{
	return [self arrayAtIndex:index defaultValue:nil];
}


- (NSSet *)setAtIndex:(unsigned)index
{
	return [self setAtIndex:index defaultValue:nil];
}


- (NSDictionary *)dictionaryAtIndex:(unsigned)index
{
	return [self dictionaryAtIndex:index defaultValue:nil];
}


- (NSData *)dataAtIndex:(unsigned)index
{
	return [self dataAtIndex:index defaultValue:nil];
}


- (struct Vector)vectorAtIndex:(unsigned)index
{
	return [self vectorAtIndex:index defaultValue:kZeroVector];
}


- (struct Quaternion)quaternionAtIndex:(unsigned)index
{
	return [self quaternionAtIndex:index defaultValue:kIdentityQuaternion];
}

@end


@implementation NSDictionary (OOExtractor)

- (char)charForKey:(id)key defaultValue:(char)value
{
	return OOCharFromObject([self objectForKey:key], value);
}


- (short)shortForKey:(id)key defaultValue:(short)value
{
	return OOShortFromObject([self objectForKey:key], value);
}


- (int)intForKey:(id)key defaultValue:(int)value
{
	return OOIntFromObject([self objectForKey:key], value);
}


- (long)longForKey:(id)key defaultValue:(long)value
{
	return OOLongFromObject([self objectForKey:key], value);
}


- (long long)longLongForKey:(id)key defaultValue:(long long)value
{
	return OOLongLongFromObject([self objectForKey:key], value);
}


- (unsigned char)unsignedCharForKey:(id)key defaultValue:(unsigned char)value
{
	return OOUnsignedCharFromObject([self objectForKey:key], value);
}


- (unsigned short)unsignedShortForKey:(id)key defaultValue:(unsigned short)value
{
	return OOUnsignedShortFromObject([self objectForKey:key], value);
}


- (unsigned int)unsignedIntForKey:(id)key defaultValue:(unsigned int)value
{
	return OOUnsignedIntFromObject([self objectForKey:key], value);
}


- (unsigned long)unsignedLongForKey:(id)key defaultValue:(unsigned long)value
{
	return OOUnsignedLongFromObject([self objectForKey:key], value);
}


- (unsigned long long)unsignedLongLongForKey:(id)key defaultValue:(unsigned long long)value
{
	return OOUnsignedLongLongFromObject([self objectForKey:key], value);
}


- (BOOL)boolForKey:(id)key defaultValue:(BOOL)value
{
	return OOBooleanFromObject([self objectForKey:key], value);
}


- (BOOL)fuzzyBooleanForKey:(id)key defaultValue:(float)value
{
	return OOFuzzyBooleanFromObject([self objectForKey:key], value);
}


- (float)floatForKey:(id)key defaultValue:(float)value
{
	return OOFloatFromObject([self objectForKey:key], value);
}


- (double)doubleForKey:(id)key defaultValue:(double)value
{
	return OODoubleFromObject([self objectForKey:key], value);
}


- (float)nonNegativeFloatForKey:(id)key defaultValue:(float)value
{
	return OONonNegativeFloatFromObject([self objectForKey:key], value);
}


- (double)nonNegativeDoubleForKey:(id)key defaultValue:(double)value
{
	return OONonNegativeDoubleFromObject([self objectForKey:key], value);
}


- (id)objectForKey:(id)key defaultValue:(id)value
{
	id					objVal = [self objectForKey:key];
	id					result;
	
	if (objVal != nil)  result = objVal;
	else  result = value;
	
	return result;
}


- (id)objectOfClass:(Class)class forKey:(id)key defaultValue:(id)value
{
	id					objVal = [self objectForKey:key];
	id					result;
	
	if ([objVal isKindOfClass:class])  result = objVal;
	else  result = value;
	
	return result;
}


- (NSString *)stringForKey:(id)key defaultValue:(NSString *)value
{
	return [self objectOfClass:[NSString class] forKey:key defaultValue:value];
}


- (NSArray *)arrayForKey:(id)key defaultValue:(NSArray *)value
{
	return [self objectOfClass:[NSArray class] forKey:key defaultValue:value];
}


- (NSSet *)setForKey:(id)key defaultValue:(NSSet *)value
{
	return SetForObject([self objectForKey:key], value);
}


- (NSDictionary *)dictionaryForKey:(id)key defaultValue:(NSDictionary *)value
{
	return [self objectOfClass:[NSDictionary class] forKey:key defaultValue:value];
}


- (NSData *)dataForKey:(id)key defaultValue:(NSData *)value
{
	return [self objectOfClass:[NSData class] forKey:key defaultValue:value];
}


- (struct Vector)vectorForKey:(id)key defaultValue:(struct Vector)value
{
	return OOVectorFromObject([self objectForKey:key], value);
}


- (struct Quaternion)quaternionForKey:(id)key defaultValue:(struct Quaternion)value
{
	return OOQuaternionFromObject([self objectForKey:key], value);
}


- (char)charForKey:(id)key
{
	return [self charForKey:key defaultValue:0];
}


- (short)shortForKey:(id)key
{
	return [self shortForKey:key defaultValue:0];
}


- (int)intForKey:(id)key
{
	return [self intForKey:key defaultValue:0];
}


- (long)longForKey:(id)key
{
	return [self longForKey:key defaultValue:0];
}


- (long long)longLongForKey:(id)key
{
	return [self longLongForKey:key defaultValue:0];
}


- (unsigned char)unsignedCharForKey:(id)key
{
	return [self unsignedCharForKey:key defaultValue:0];
}


- (unsigned short)unsignedShortForKey:(id)key
{
	return [self unsignedShortForKey:key defaultValue:0];
}


- (unsigned int)unsignedIntForKey:(id)key
{
	return [self unsignedIntForKey:key defaultValue:0];
}


- (unsigned long)unsignedLongForKey:(id)key
{
	return [self unsignedLongForKey:key defaultValue:0];
}


- (unsigned long long)unsignedLongLongForKey:(id)key
{
	return [self unsignedLongLongForKey:key defaultValue:0];
}


- (BOOL)boolForKey:(id)key
{
	return [self boolForKey:key defaultValue:NO];
}


- (BOOL)fuzzyBooleanForKey:(id)key
{
	return [self fuzzyBooleanForKey:key defaultValue:0.0f];
}


- (float)floatForKey:(id)key
{
	return OOFloatFromObject([self objectForKey:key], 0.0f);
}


- (double)doubleForKey:(id)key
{
	return OODoubleFromObject([self objectForKey:key], 0.0);
}


- (float)nonNegativeFloatForKey:(id)key
{
	return OONonNegativeFloatFromObject([self objectForKey:key], 0.0f);
}


- (double)nonNegativeDoubleForKey:(id)key
{
	return OONonNegativeDoubleFromObject([self objectForKey:key], 0.0);
}


- (id)objectOfClass:(Class)class forKey:(id)key
{
	return [self objectOfClass:class forKey:key defaultValue:nil];
}


- (NSString *)stringForKey:(id)key
{
	return [self stringForKey:key defaultValue:nil];
}


- (NSArray *)arrayForKey:(id)key
{
	return [self arrayForKey:key defaultValue:nil];
}


- (NSSet *)setForKey:(id)key
{
	return [self setForKey:key defaultValue:nil];
}


- (NSDictionary *)dictionaryForKey:(id)key
{
	return [self dictionaryForKey:key defaultValue:nil];
}


- (NSData *)dataForKey:(id)key
{
	return [self dataForKey:key defaultValue:nil];
}


- (struct Vector)vectorForKey:(id)key
{
	return [self vectorForKey:key defaultValue:kZeroVector];
}


- (struct Quaternion)quaternionForKey:(id)key
{
	return [self quaternionForKey:key defaultValue:kIdentityQuaternion];
}

@end


@implementation NSUserDefaults (OOExtractor)

- (char)charForKey:(id)key defaultValue:(char)value
{
	return OOCharFromObject([self objectForKey:key], value);
}


- (short)shortForKey:(id)key defaultValue:(short)value
{
	return OOShortFromObject([self objectForKey:key], value);
}


- (int)intForKey:(id)key defaultValue:(int)value
{
	return OOIntFromObject([self objectForKey:key], value);
}


- (long)longForKey:(id)key defaultValue:(long)value
{
	return OOLongFromObject([self objectForKey:key], value);
}


- (long long)longLongForKey:(id)key defaultValue:(long long)value
{
	return OOLongLongFromObject([self objectForKey:key], value);
}


- (unsigned char)unsignedCharForKey:(id)key defaultValue:(unsigned char)value
{
	return OOUnsignedCharFromObject([self objectForKey:key], value);
}


- (unsigned short)unsignedShortForKey:(id)key defaultValue:(unsigned short)value
{
	return OOUnsignedShortFromObject([self objectForKey:key], value);
}


- (unsigned int)unsignedIntForKey:(id)key defaultValue:(unsigned int)value
{
	return OOUnsignedIntFromObject([self objectForKey:key], value);
}


- (unsigned long)unsignedLongForKey:(id)key defaultValue:(unsigned long)value
{
	return OOUnsignedLongFromObject([self objectForKey:key], value);
}


- (unsigned long long)unsignedLongLongForKey:(id)key defaultValue:(unsigned long long)value
{
	return OOUnsignedLongLongFromObject([self objectForKey:key], value);
}


- (BOOL)boolForKey:(id)key defaultValue:(BOOL)value
{
	return OOBooleanFromObject([self objectForKey:key], value);
}


- (BOOL)fuzzyBooleanForKey:(id)key defaultValue:(float)value
{
	return OOFuzzyBooleanFromObject([self objectForKey:key], value);
}


- (float)floatForKey:(id)key defaultValue:(float)value
{
	return OOFloatFromObject([self objectForKey:key], value);
}


- (double)doubleForKey:(id)key defaultValue:(double)value
{
	return OODoubleFromObject([self objectForKey:key], value);
}


- (float)nonNegativeFloatForKey:(id)key defaultValue:(float)value
{
	return OONonNegativeFloatFromObject([self objectForKey:key], value);
}


- (double)nonNegativeDoubleForKey:(id)key defaultValue:(double)value
{
	return OONonNegativeDoubleFromObject([self objectForKey:key], value);
}


- (id)objectForKey:(id)key defaultValue:(id)value
{
	id					objVal = [self objectForKey:key];
	id					result;
	
	if (objVal != nil)  result = objVal;
	else  result = value;
	
	return result;
}


- (id)objectOfClass:(Class)class forKey:(id)key defaultValue:(id)value
{
	id					objVal = [self objectForKey:key];
	id					result;
	
	if ([objVal isKindOfClass:class])  result = objVal;
	else  result = value;
	
	return result;
}


- (NSString *)stringForKey:(id)key defaultValue:(NSString *)value
{
	return [self objectOfClass:[NSString class] forKey:key defaultValue:value];
}


- (NSArray *)arrayForKey:(id)key defaultValue:(NSArray *)value
{
	return [self objectOfClass:[NSArray class] forKey:key defaultValue:value];
}


- (NSSet *)setForKey:(id)key defaultValue:(NSSet *)value
{
	return SetForObject([self objectForKey:key], value);
}


- (NSDictionary *)dictionaryForKey:(id)key defaultValue:(NSDictionary *)value
{
	return [self objectOfClass:[NSDictionary class] forKey:key defaultValue:value];
}


- (NSData *)dataForKey:(id)key defaultValue:(NSData *)value
{
	return [self objectOfClass:[NSData class] forKey:key defaultValue:value];
}


- (char)charForKey:(id)key
{
	return [self charForKey:key defaultValue:0];
}


- (short)shortForKey:(id)key
{
	return [self shortForKey:key defaultValue:0];
}


- (int)intForKey:(id)key
{
	return [self intForKey:key defaultValue:0];
}


- (long)longForKey:(id)key
{
	return [self longForKey:key defaultValue:0];
}


- (long long)longLongForKey:(id)key
{
	return [self longLongForKey:key defaultValue:0];
}


- (unsigned char)unsignedCharForKey:(id)key
{
	return [self unsignedCharForKey:key defaultValue:0];
}


- (unsigned short)unsignedShortForKey:(id)key
{
	return [self unsignedShortForKey:key defaultValue:0];
}


- (unsigned int)unsignedIntForKey:(id)key
{
	return [self unsignedIntForKey:key defaultValue:0];
}


- (unsigned long)unsignedLongForKey:(id)key
{
	return [self unsignedLongForKey:key defaultValue:0];
}


- (unsigned long long)unsignedLongLongForKey:(id)key
{
	return [self unsignedLongLongForKey:key defaultValue:0];
}


- (BOOL)fuzzyBooleanForKey:(id)key
{
	return [self fuzzyBooleanForKey:key defaultValue:0.0f];
}


- (double)doubleForKey:(id)key
{
	return OODoubleFromObject([self objectForKey:key], 0.0);
}


- (float)nonNegativeFloatForKey:(id)key
{
	return OONonNegativeFloatFromObject([self objectForKey:key], 0.0f);
}


- (double)nonNegativeDoubleForKey:(id)key
{
	return OONonNegativeDoubleFromObject([self objectForKey:key], 0.0);
}


- (id)objectOfClass:(Class)class forKey:(id)key
{
	return [self objectOfClass:class forKey:key defaultValue:nil];
}


- (NSSet *)setForKey:(id)key
{
	return [self setForKey:key defaultValue:nil];
}

@end


@implementation NSMutableArray (OOInserter)

- (void)addInteger:(long)value
{
	[self addObject:[NSNumber numberWithLong:value]];
}


- (void)addUnsignedInteger:(unsigned long)value
{
	[self addObject:[NSNumber numberWithUnsignedLong:value]];
}


- (void)addFloat:(double)value
{
	[self addObject:[NSNumber numberWithDouble:value]];
}


- (void)addBool:(BOOL)value
{
	[self addObject:[NSNumber numberWithBool:value]];
}


- (void)insertInteger:(long)value atIndex:(unsigned)index
{
	[self insertObject:[NSNumber numberWithLong:value] atIndex:index];
}


- (void)insertUnsignedInteger:(unsigned long)value atIndex:(unsigned)index;
{
	[self insertObject:[NSNumber numberWithUnsignedLong:value] atIndex:index];
}


- (void)insertFloat:(double)value atIndex:(unsigned)index
{
	[self insertObject:[NSNumber numberWithDouble:value] atIndex:index];
}


- (void)insertBool:(BOOL)value atIndex:(unsigned)index
{
	[self insertObject:[NSNumber numberWithBool:value] atIndex:index];
}

@end


@implementation NSMutableDictionary (OOInserter)

- (void)setInteger:(long)value forKey:(id)key
{
	[self setObject:[NSNumber numberWithLong:value] forKey:key];
}


- (void)setUnsignedInteger:(unsigned long)value forKey:(id)key
{
	[self setObject:[NSNumber numberWithUnsignedLong:value] forKey:key];
}


- (void)setFloat:(double)value forKey:(id)key
{
	[self setObject:[NSNumber numberWithDouble:value] forKey:key];
}


- (void)setBool:(BOOL)value forKey:(id)key
{
	[self setObject:[NSNumber numberWithBool:value] forKey:key];
}

@end


@implementation NSMutableSet (OOInserter)

- (void)addInteger:(long)value
{
	[self addObject:[NSNumber numberWithLong:value]];
}


- (void)addUnsignedInteger:(unsigned long)value
{
	[self addObject:[NSNumber numberWithUnsignedLong:value]];
}


- (void)addFloat:(double)value
{
	[self addObject:[NSNumber numberWithDouble:value]];
}


- (void)addBool:(BOOL)value
{
	[self addObject:[NSNumber numberWithBool:value]];
}

@end


long long OOLongLongFromObject(id object, long long defaultValue)
{
	long long llValue;
	
	if ([object respondsToSelector:@selector(longLongValue)])  llValue = [object longLongValue];
	else if ([object respondsToSelector:@selector(longValue)])  llValue = [object longValue];
	else if ([object respondsToSelector:@selector(intValue)])  llValue = [object intValue];
	else llValue = defaultValue;
	
	return llValue;
}


unsigned long long OOUnsignedLongLongFromObject(id object, unsigned long long defaultValue)
{
	unsigned long long ullValue;
	
	if ([object respondsToSelector:@selector(unsignedLongLongValue)])  ullValue = [object unsignedLongLongValue];
	else if ([object respondsToSelector:@selector(unsignedLongValue)])  ullValue = [object unsignedLongValue];
	else if ([object respondsToSelector:@selector(unsignedIntValue)])  ullValue = [object unsignedIntValue];
	else if ([object respondsToSelector:@selector(intValue)])  ullValue = [object intValue];
	else ullValue = defaultValue;
	
	return ullValue;
}


static BOOL IsBooleanString(id object, BOOL *outValue)  NONNULL_FUNC;


BOOL OOBooleanFromObject(id object, BOOL defaultValue)
{
	BOOL result;
	
	if (!IsBooleanString(object, &result))
	{
		if ([object respondsToSelector:@selector(boolValue)])  result = [object boolValue];
		else if ([object respondsToSelector:@selector(intValue)])  result = [object intValue] != 0;
		else result = defaultValue;
	}
	
	return result;
}


BOOL OOFuzzyBooleanFromObject(id object, BOOL defaultValue)
{
	BOOL result;
	
	if (!IsBooleanString(object, &result))
	{
		/*	This will always be NO for negative values and YES for values
			greater than 1, as expected. randf() is always less than 1, so
			< is the correct operator here.
		*/
		result = randf() < OOFloatFromObject(object, defaultValue ? 1.0f : 0.0f);
	}
	
	return result;
}


float OOFloatFromObject(id object, float defaultValue)
{
	float result;
	
	if ([object respondsToSelector:@selector(floatValue)])  result = [object floatValue];
	else if ([object respondsToSelector:@selector(doubleValue)])  result = [object doubleValue];
	else if ([object respondsToSelector:@selector(intValue)])  result = [object intValue];
	else result = defaultValue;
	
	return result;
}


double OODoubleFromObject(id object, double defaultValue)
{
	double result;
	
	if ([object respondsToSelector:@selector(doubleValue)])  result = [object doubleValue];
	else if ([object respondsToSelector:@selector(floatValue)])  result = [object floatValue];
	else if ([object respondsToSelector:@selector(intValue)])  result = [object intValue];
	else result = defaultValue;
	
	return result;
}


float OONonNegativeFloatFromObject(id object, float defaultValue)
{
	float result;
	
	if ([object respondsToSelector:@selector(floatValue)])  result = [object floatValue];
	else if ([object respondsToSelector:@selector(doubleValue)])  result = [object doubleValue];
	else if ([object respondsToSelector:@selector(intValue)])  result = [object intValue];
	else return defaultValue;	// Don't clamp default
	
	return OOMax_f(result, 0.0f);
}


double OONonNegativeDoubleFromObject(id object, double defaultValue)
{
	double result;
	
	if ([object respondsToSelector:@selector(doubleValue)])  result = [object doubleValue];
	else if ([object respondsToSelector:@selector(floatValue)])  result = [object floatValue];
	else if ([object respondsToSelector:@selector(intValue)])  result = [object intValue];
	else return defaultValue;	// Don't clamp default
	
	return OOMax_d(result, 0.0f);
}


struct Vector OOVectorFromObject(id object, struct Vector defaultValue)
{
	Vector result = defaultValue;
	
	if ([object isKindOfClass:[NSString class]])
	{
		// This will only write result if a valid vector is found, and will write an error message otherwise.
		ScanVectorFromString(object, &result);
	}
	else if ([object isKindOfClass:[NSArray class]] && [object count] == 3)
	{
		result.x = [object floatAtIndex:0];
		result.y = [object floatAtIndex:1];
		result.z = [object floatAtIndex:2];
	}
	else if ([object isKindOfClass:[NSDictionary class]])
	{
		// Require at least one of the keys x, y, or z
		if ([object objectForKey:@"x"] != nil ||
			[object objectForKey:@"y"] != nil ||
			[object objectForKey:@"z"] != nil)
		{
			// Note: uses 0 for unknown components rather than components of defaultValue.
			result.x = [object floatForKey:@"x" defaultValue:0.0f];
			result.y = [object floatForKey:@"y" defaultValue:0.0f];
			result.z = [object floatForKey:@"z" defaultValue:0.0f];
		}
	}
	
	return result;
}


struct Quaternion OOQuaternionFromObject(id object, struct Quaternion defaultValue)
{
	Quaternion result = defaultValue;
	
	if ([object isKindOfClass:[NSString class]])
	{
		// This will only write result if a valid quaternion is found, and will write an error message otherwise.
		ScanQuaternionFromString(object, &result);
	}
	else if ([object isKindOfClass:[NSArray class]] && [object count] == 4)
	{
		result.w = [object floatAtIndex:0];
		result.x = [object floatAtIndex:1];
		result.y = [object floatAtIndex:2];
		result.z = [object floatAtIndex:3];
	}
	else if ([object isKindOfClass:[NSDictionary class]])
	{
		// Require at least one of the keys w, x, y, or z
		if ([object objectForKey:@"w"] != nil ||
			[object objectForKey:@"x"] != nil ||
			[object objectForKey:@"y"] != nil ||
			[object objectForKey:@"z"] != nil)
		{
			// Note: uses 0 for unknown components rather than components of defaultValue.
			result.w = [object floatForKey:@"w" defaultValue:0.0f];
			result.x = [object floatForKey:@"x" defaultValue:0.0f];
			result.y = [object floatForKey:@"y" defaultValue:0.0f];
			result.z = [object floatForKey:@"z" defaultValue:0.0f];
		}
	}
	
	return result;
}


static BOOL IsBooleanString(id object, BOOL *outValue)
{
	if ([object isKindOfClass:[NSString class]])
	{
		if (NSOrderedSame == [object caseInsensitiveCompare:@"yes"] ||
			NSOrderedSame == [object caseInsensitiveCompare:@"true"] ||
			NSOrderedSame == [object caseInsensitiveCompare:@"on"] ||
			[object intValue] != 0)
		{
			*outValue = YES;
			return YES;
		}
		else if (NSOrderedSame == [object caseInsensitiveCompare:@"no"] ||
				 NSOrderedSame == [object caseInsensitiveCompare:@"false"] ||
				 NSOrderedSame == [object caseInsensitiveCompare:@"off"] ||
				 NSOrderedSame == [object caseInsensitiveCompare:@"0"] ||
				 NSOrderedSame == [object caseInsensitiveCompare:@"-0"])
		{
			*outValue = NO;
			return YES;
		}
	}
	
	return NO;
}


static NSSet *SetForObject(id object, NSSet *defaultValue)
{
	if ([object isKindOfClass:[NSArray class]])  return [NSSet setWithArray:object];
	else if ([object isKindOfClass:[NSSet class]])  return [[object copy] autorelease];
	
	else return defaultValue;
}
