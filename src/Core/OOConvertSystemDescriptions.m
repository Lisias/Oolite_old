//
//  OOConvertSystemDescriptions.m
//  systemdescriptiontest
//
//  Created by Jens Ayton on 2008-12-14.
//  Copyright 2008 Jens Ayton. All rights reserved.
//

#import "OOCocoa.h"
#import "OOConvertSystemDescriptions.h"
#import "OldSchoolPropertyListWriting.h"
#import "OOCollectionExtractors.h"
#import "ResourceManager.h"
#import	"Universe.h"


static NSMutableDictionary *InitKeyToIndexDict(NSDictionary *dict, NSMutableSet **outUsedIndices);
static NSString *IndexToKey(OOUInteger index, NSDictionary *indicesToKeys, BOOL useFallback);
static NSArray *ConvertIndicesToKeys(NSArray *entry, NSDictionary *indicesToKeys);
static NSNumber *KeyToIndex(NSString *key, NSMutableDictionary *ioKeysToIndices, NSMutableSet *ioUsedIndicies, OOUInteger *ioSlotCache);
static NSArray *ConvertKeysToIndices(NSArray *entry, NSMutableDictionary *ioKeysToIndices, NSMutableSet *ioUsedIndicies, OOUInteger *ioSlotCache);
static OOUInteger HighestIndex(NSMutableDictionary *sparseArray);	// Actually returns highest index + 1, which is fine.


void CompileSystemDescriptions(BOOL asXML)
{
	NSDictionary		*sysDescDict = nil;
	NSArray				*sysDescArray = nil;
	NSDictionary		*keyMap = nil;
	NSData				*data = nil;
	NSString			*error = nil;
	
	sysDescDict = [ResourceManager dictionaryFromFilesNamed:@"sysdesc.plist"
												   inFolder:@"Config"
												   andMerge:NO];
	if (sysDescDict == nil)
	{
		OOLog(@"sysdesc.compile.failed.fileNotFound", @"Could not load a dictionary from sysdesc.plist, ignoring --compile-sysdesc option.");
		return;
	}
	
	keyMap = [ResourceManager dictionaryFromFilesNamed:@"sysdesc_key_table.plist"
											  inFolder:@"Config"
											  andMerge:NO];
	// keyMap is optional, so no nil check
	
	sysDescArray = OOConvertSystemDescriptionsToArrayFormat(sysDescDict, keyMap);
	if (sysDescArray == nil)
	{
		OOLog(@"sysdesc.compile.failed.conversion", @"Could not convert sysdesc.plist to descriptions.plist format for some reason.");
		return;
	}
	
	sysDescDict = [NSDictionary dictionaryWithObject:sysDescArray forKey:@"system_description"];
	
	if (asXML)
	{
		data = [NSPropertyListSerialization dataFromPropertyList:sysDescDict
														  format:NSPropertyListXMLFormat_v1_0
												errorDescription:&error];
	}
	else
	{
		data = [sysDescDict oldSchoolPListFormatWithErrorDescription:&error];
	}
	
	if (data == nil)
	{
		OOLog(@"sysdesc.compile.failed.XML", @"Could not convert translated sysdesc.plist to property list: %@.", error);
		return;
	}
	
	if ([ResourceManager writeDiagnosticData:data toFileNamed:@"sysdesc-compiled.plist"])
	{
		OOLog(@"sysdesc.compile.success", @"Wrote translated sysdesc.plist to sysdesc-compiled.plist.");
	}
	else
	{
		OOLog(@"sysdesc.compile.failed.writeFailure", @"Could not write translated sysdesc.plist to sysdesc-compiled.plist.");
	}
}


void ExportSystemDescriptions(BOOL asXML)
{
	NSArray				*sysDescArray = nil;
	NSDictionary		*sysDescDict = nil;
	NSDictionary		*keyMap = nil;
	NSData				*data = nil;
	NSString			*error = nil;
	
	sysDescArray = [[UNIVERSE descriptions] arrayForKey:@"system_description"];
	
	keyMap = [ResourceManager dictionaryFromFilesNamed:@"sysdesc_key_table.plist"
											  inFolder:@"Config"
											  andMerge:NO];
	// keyMap is optional, so no nil check
	
	sysDescDict = OOConvertSystemDescriptionsToDictionaryFormat(sysDescArray, keyMap);
	if (sysDescArray == nil)
	{
		OOLog(@"sysdesc.export.failed.conversion", @"Could not convert system_description do sysdesc.plist format for some reason.");
		return;
	}
	
	if (asXML)
	{
		data = [NSPropertyListSerialization dataFromPropertyList:sysDescDict
														  format:NSPropertyListXMLFormat_v1_0
												errorDescription:&error];
	}
	else
	{
		data = [sysDescDict oldSchoolPListFormatWithErrorDescription:&error];
	}
	
	if (data == nil)
	{
		OOLog(@"sysdesc.export.failed.XML", @"Could not convert translated system_description to XML property list: %@.", error);
		return;
	}
	
	if ([ResourceManager writeDiagnosticData:data toFileNamed:@"sysdesc.plist"])
	{
		OOLog(@"sysdesc.export.success", @"Wrote translated system_description to sysdesc.plist.");
	}
	else
	{
		OOLog(@"sysdesc.export.failed.writeFailure", @"Could not write translated system_description to sysdesc.plist.");
	}
}


NSArray *OOConvertSystemDescriptionsToArrayFormat(NSDictionary *descriptionsInDictionaryFormat, NSDictionary *indicesToKeys)
{
	NSMutableDictionary		*result = nil;
	NSAutoreleasePool		*pool = nil;
	NSString				*key = nil;
	NSArray					*entry = nil;
	NSEnumerator			*keyEnum = nil;
	NSMutableDictionary		*keysToIndices = nil;
	NSMutableSet			*usedIndices = nil;
	OOUInteger				slotCache = 0;
	NSNumber				*index = nil;
	OOUInteger				i, count;
	NSMutableArray			*realResult = nil;
	
	pool = [[NSAutoreleasePool alloc] init];
	
	// Use a dictionary as a sparse array.
	result = [NSMutableDictionary dictionaryWithCapacity:[descriptionsInDictionaryFormat count]];
	
	keysToIndices = InitKeyToIndexDict(indicesToKeys, &usedIndices);
	
	for (keyEnum = [descriptionsInDictionaryFormat keyEnumerator]; (key = [keyEnum nextObject]); )
	{
		entry = ConvertKeysToIndices([descriptionsInDictionaryFormat objectForKey:key], keysToIndices, usedIndices, &slotCache);
		index = KeyToIndex(key, keysToIndices, usedIndices, &slotCache);
		
		[result setObject:entry forKey:index];
	}
	
	count = HighestIndex(result);
	realResult = [NSMutableArray arrayWithCapacity:count];
	for (i = 0; i < count; i++)
	{
		entry = [result objectForKey:[NSNumber numberWithUnsignedInt:i]];
		if (entry == nil)  entry = [NSArray array];
		[realResult addObject:entry];
	}
	
	[realResult retain];
	[pool release];
	return [realResult autorelease];
}


NSDictionary *OOConvertSystemDescriptionsToDictionaryFormat(NSArray *descriptionsInArrayFormat, NSDictionary *indicesToKeys)
{
	NSMutableDictionary		*result = nil;
	NSAutoreleasePool		*pool = nil;
	NSArray					*entry = nil;
	NSEnumerator			*entryEnum = nil;
	NSString				*key = nil;
	OOUInteger				i = 0;
	
	result = [NSMutableDictionary dictionaryWithCapacity:[descriptionsInArrayFormat count]];
	pool = [[NSAutoreleasePool alloc] init];
	
	for (entryEnum = [descriptionsInArrayFormat objectEnumerator]; (entry = [entryEnum nextObject]); )
	{
		entry = ConvertIndicesToKeys(entry, indicesToKeys);
		key = IndexToKey(i, indicesToKeys, YES);
		++i;
		
		[result setObject:entry forKey:key];
	}
	
	[pool release];
	return result;
}


NSString *OOStringifySystemDescriptionLine(NSString *line, NSDictionary *indicesToKeys, BOOL useFallback)
{
	OOUInteger				p1, p2;
	NSRange					searchRange;
	NSString				*before = nil, *after = nil, *middle = nil;
	NSString				*key = nil;
	
	searchRange.location = 0;
	searchRange.length = [line length];
	
	while ([line rangeOfString:@"[" options:NSLiteralSearch range:searchRange].location != NSNotFound)
	{
		p1 = [line rangeOfString:@"[" options:NSLiteralSearch range:searchRange].location;
		p2 = [line rangeOfString:@"]" options:NSLiteralSearch range:searchRange].location + 1;
		
		before = [line substringWithRange:NSMakeRange(0, p1)];
		after = [line substringWithRange:NSMakeRange(p2,[line length] - p2)];
		middle = [line substringWithRange:NSMakeRange(p1 + 1 , p2 - p1 - 2)];
		
		if ([[middle stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"]] isEqual:@""] && ![middle isEqual:@""])
		{
			// Found [] around integers only
			key = IndexToKey([middle intValue], indicesToKeys, useFallback);
			if (key != nil)
			{
				line = [NSString stringWithFormat:@"%@[#%@]%@", before, key, after];
			}
		}
		
		searchRange.length -= p2 - searchRange.location;
		searchRange.location = [line length] - searchRange.length;
	}
	return line;
}


static NSMutableDictionary *InitKeyToIndexDict(NSDictionary *dict, NSMutableSet **outUsedIndices)
{
	NSEnumerator			*keyEnum = nil;
	NSString				*key = nil;
	NSNumber				*number = nil;
	NSMutableDictionary		*result = nil;
	NSMutableSet			*used = nil;
	
	assert(outUsedIndices != NULL);
	
	result = [NSMutableDictionary dictionaryWithCapacity:[dict count]];
	used = [NSMutableSet setWithCapacity:[dict count]];
	
	for (keyEnum = [dict keyEnumerator]; (key = [keyEnum nextObject]); )
	{
		// Convert keys of dict to array indices
		number = [NSNumber numberWithInt:[key intValue]];
		[result setObject:number forKey:[dict objectForKey:key]];
		[used addObject:number];
	}
	
	*outUsedIndices = used;
	return result;
}


static NSString *IndexToKey(OOUInteger index, NSDictionary *indicesToKeys, BOOL useFallback)
{
	NSString *result = [indicesToKeys objectForKey:[NSString stringWithFormat:@"%u", index]];
	if (result == nil && useFallback)  result = [NSString stringWithFormat:@"block_%u", index];
	
	return result;
}


static NSArray *ConvertIndicesToKeys(NSArray *entry, NSDictionary *indicesToKeys)
{
	NSEnumerator			*lineEnum = nil;
	NSString				*line = nil;
	NSMutableArray			*result = nil;
	
	result = [NSMutableArray arrayWithCapacity:[entry count]];
	
	for (lineEnum = [entry objectEnumerator]; (line = [lineEnum nextObject]); )
	{
		[result addObject:OOStringifySystemDescriptionLine(line, indicesToKeys, YES)];
	}
	
	return result;
}


static NSNumber *KeyToIndex(NSString *key, NSMutableDictionary *ioKeysToIndices, NSMutableSet *ioUsedIndicies, OOUInteger *ioSlotCache)
{
	NSNumber				*result = nil;
	
	assert(ioSlotCache != NULL);
	
	result = [ioKeysToIndices objectForKey:key];
	if (result == nil)
	{
		// Search for free index
		do
		{
			result = [NSNumber numberWithUnsignedInt:(*ioSlotCache)++];
		}
		while ([ioUsedIndicies containsObject:result]);
		
		[ioKeysToIndices setObject:result forKey:key];
		[ioUsedIndicies addObject:result];
		OOLog(@"sysdesc.compile.unknownKey", @"Assigning key \"%@\" to index %@.", key, result);
	}
	
	return result;
}


static NSArray *ConvertKeysToIndices(NSArray *entry, NSMutableDictionary *ioKeysToIndices, NSMutableSet *ioUsedIndicies, OOUInteger *ioSlotCache)
{
	NSEnumerator			*lineEnum = nil;
	NSString				*line = nil;
	OOUInteger				p1, p2;
	NSRange					searchRange;
	NSMutableArray			*result = nil;
	NSString				*before = nil, *after = nil, *middle = nil;
	
	result = [NSMutableArray arrayWithCapacity:[entry count]];
	
	for (lineEnum = [entry objectEnumerator]; (line = [lineEnum nextObject]); )
	{
		searchRange.location = 0;
		searchRange.length = [line length];
		
		while ([line rangeOfString:@"[" options:NSLiteralSearch range:searchRange].location != NSNotFound)
		{
			p1 = [line rangeOfString:@"[" options:NSLiteralSearch range:searchRange].location;
			p2 = [line rangeOfString:@"]" options:NSLiteralSearch range:searchRange].location + 1;
			
			before = [line substringWithRange:NSMakeRange(0, p1)];
			after = [line substringWithRange:NSMakeRange(p2,[line length] - p2)];
			middle = [line substringWithRange:NSMakeRange(p1 + 1 , p2 - p1 - 2)];
			
			if ([middle length] > 1 && [middle hasPrefix:@"#"])
			{
				// Found [] around key
				line = [NSString stringWithFormat:@"%@[%@]%@", before, KeyToIndex([middle substringFromIndex:1], ioKeysToIndices, ioUsedIndicies, ioSlotCache), after];
			}
			
			searchRange.length -= p2 - searchRange.location;
			searchRange.location = [line length] - searchRange.length;
		}
		
		[result addObject:line];
	}
	
	return result;
}


static OOUInteger HighestIndex(NSMutableDictionary *sparseArray)
{
	NSEnumerator			*keyEnum = nil;
	NSNumber				*key = nil;
	OOUInteger				curr, highest = 0;
	
	for (keyEnum = [sparseArray keyEnumerator]; (key = [keyEnum nextObject]); )
	{
		curr = [key intValue];
		if (highest < curr)  highest = curr;
	}
	
	return highest;
}
