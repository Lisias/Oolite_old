/*

OOCollectionExtractors.h

Convenience extensions to Foundation collections to extract optional values.
In addition to being convenient, these perform type checking. Which is,
y'know, good to have.

Note on types: ideally, stdint.h types would be used for integers. However,
NSNumber doesn't do this, so doing so portably would add new complications.

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

#import <Foundation/Foundation.h>


BOOL EvaluateAsBoolean(id object, BOOL defaultValue);


@interface NSArray (OOExtractor)

- (char)charAtIndex:(unsigned)index defaultValue:(char)value;
- (short)shortAtIndex:(unsigned)index defaultValue:(short)value;
- (int)intAtIndex:(unsigned)index defaultValue:(int)value;
- (long)longAtIndex:(unsigned)index defaultValue:(long)value;
- (long long)longLongAtIndex:(unsigned)index defaultValue:(long long)value;

- (unsigned char)unsignedCharAtIndex:(unsigned)index defaultValue:(unsigned char)value;
- (unsigned short)unsignedShortAtIndex:(unsigned)index defaultValue:(unsigned short)value;
- (unsigned int)unsignedIntAtIndex:(unsigned)index defaultValue:(unsigned int)value;
- (unsigned long)unsignedLongAtIndex:(unsigned)index defaultValue:(unsigned long)value;
- (unsigned long long)unsignedLongLongAtIndex:(unsigned)index defaultValue:(unsigned long long)value;

- (BOOL)boolAtIndex:(unsigned)index defaultValue:(BOOL)value;
- (BOOL)fuzzyBooleanAtIndex:(unsigned)index defaultValue:(float)value;	// Reads a float in the range [0, 1], and returns YES with that probability.

- (float)floatAtIndex:(unsigned)index defaultValue:(float)value;
- (double)doubleAtIndex:(unsigned)index defaultValue:(double)value;

- (id)objectAtIndex:(unsigned)index defaultValue:(id)value;
- (NSString *)stringAtIndex:(unsigned)index defaultValue:(NSString *)value;
- (NSArray *)arrayAtIndex:(unsigned)index defaultValue:(NSArray *)value;
- (NSDictionary *)dictionaryAtIndex:(unsigned)index defaultValue:(NSDictionary *)value;
- (NSData *)dataAtIndex:(unsigned)index defaultValue:(NSData *)value;

@end


@interface NSDictionary (OOExtractor)

- (char)charForKey:(id)key defaultValue:(char)value;
- (short)shortForKey:(id)key defaultValue:(short)value;
- (int)intForKey:(id)key defaultValue:(int)value;
- (long)longForKey:(id)key defaultValue:(long)value;
- (long long)longLongForKey:(id)key defaultValue:(long long)value;

- (unsigned char)unsignedCharForKey:(id)key defaultValue:(unsigned char)value;
- (unsigned short)unsignedShortForKey:(id)key defaultValue:(unsigned short)value;
- (unsigned int)unsignedIntForKey:(id)key defaultValue:(unsigned int)value;
- (unsigned long)unsignedLongForKey:(id)key defaultValue:(unsigned long)value;
- (unsigned long long)unsignedLongLongForKey:(id)key defaultValue:(unsigned long long)value;

- (BOOL)boolForKey:(id)key defaultValue:(BOOL)value;
- (BOOL)fuzzyBooleanForKey:(id)key defaultValue:(float)value;	// Reads a float in the range [0, 1], and returns YES with that probability.

- (float)floatForKey:(id)key defaultValue:(float)value;
- (double)doubleForKey:(id)key defaultValue:(double)value;

- (id)objectForKey:(id)key defaultValue:(id)value;
- (NSString *)stringForKey:(id)key defaultValue:(NSString *)value;
- (NSArray *)arrayForKey:(id)key defaultValue:(NSArray *)value;
- (NSDictionary *)dictionaryForKey:(id)key defaultValue:(NSDictionary *)value;
- (NSData *)dataForKey:(id)key defaultValue:(NSData *)value;

@end


@interface NSUserDefaults (OOExtractor)

- (char)charForKey:(id)key defaultValue:(char)value;
- (short)shortForKey:(id)key defaultValue:(short)value;
- (int)intForKey:(id)key defaultValue:(int)value;
- (long)longForKey:(id)key defaultValue:(long)value;
- (long long)longLongForKey:(id)key defaultValue:(long long)value;

- (unsigned char)unsignedCharForKey:(id)key defaultValue:(unsigned char)value;
- (unsigned short)unsignedShortForKey:(id)key defaultValue:(unsigned short)value;
- (unsigned int)unsignedIntForKey:(id)key defaultValue:(unsigned int)value;
- (unsigned long)unsignedLongForKey:(id)key defaultValue:(unsigned long)value;
- (unsigned long long)unsignedLongLongForKey:(id)key defaultValue:(unsigned long long)value;

- (BOOL)boolForKey:(id)key defaultValue:(BOOL)value;
- (BOOL)fuzzyBooleanForKey:(id)key defaultValue:(float)value;	// Reads a float in the range [0, 1], and returns YES with that probability.

- (float)floatForKey:(id)key defaultValue:(float)value;
- (double)doubleForKey:(id)key defaultValue:(double)value;

- (id)objectForKey:(id)key defaultValue:(id)value;
- (NSString *)stringForKey:(id)key defaultValue:(NSString *)value;
- (NSArray *)arrayForKey:(id)key defaultValue:(NSArray *)value;
- (NSDictionary *)dictionaryForKey:(id)key defaultValue:(NSDictionary *)value;
- (NSData *)dataForKey:(id)key defaultValue:(NSData *)value;

@end
