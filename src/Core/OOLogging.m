/*

OOLogging.m


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

Copyright (C) 2007 Jens Ayton

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


#define OOLOG_POISON_NSLOG 0

#import "OOLoggingExtended.h"
#import "OOPListParsing.h"
#import "OOFunctionAttributes.h"
#import "ResourceManager.h"
#import "OOCollectionExtractors.h"
#import "NSThreadOOExtensions.h"
#import "OOLogHeader.h"
#import "OOLogOutputHandler.h"

#undef NSLog		// We need to be able to call the real NSLog.


#define PER_THREAD_INDENTATION		1
#ifndef APPNAME
#define APPNAME						@"Oolite"
#endif


#if PER_THREAD_INDENTATION
	#if OOLITE_USE_TLS	// Define to use __thread keyword where supported
		#define USE_INDENT_GLOBALS	1
		#define THREAD_LOCAL		__thread
	#else
		#define USE_INDENT_GLOBALS	0
		static NSString * const kIndentLevelKey = @"org.aegidian.oolite.oolog.indentLevel";
		static NSString * const kIndentStackKey = @"org.aegidian.oolite.oolog.indentStack";
	#endif
#else
	#define USE_INDENT_GLOBALS		1
	#define THREAD_LOCAL
#endif


// Control flags for OOLogInternal() - like message classes, but less cool.
#define OOLOG_NOT_INITED			1
#define OOLOG_SETTING_SET			0
#define OOLOG_SETTING_RETRIEVE		0
#define OOLOG_METACLASS_LOOP		1
#define OOLOG_UNDEFINED_METACLASS	1
#define OOLOG_BAD_SETTING			1
#define OOLOG_BAD_DEFAULT_SETTING	1
#define OOLOG_BAD_POP_INDENT		1
#define OOLOG_EXCEPTION_IN_LOG		1


// Used to track OOLogPushIndent()/OOLogPopIndent() state.
typedef struct OOLogIndentStackElement OOLogIndentStackElement;
struct OOLogIndentStackElement
{
	OOLogIndentStackElement		*link;
	unsigned					indent;
};


// We could probably use less state variables.
static BOOL						sInited = NO;
static NSLock					*sLock = nil;
static NSMutableDictionary		*sExplicitSettings = nil;
static NSMutableDictionary		*sDerivedSettingsCache = nil;
#if USE_INDENT_GLOBALS
static THREAD_LOCAL unsigned	sIndentLevel = 0;
static THREAD_LOCAL OOLogIndentStackElement
								*sIndentStack = NULL;
#endif
static BOOL						sShowFunction = NO;
static BOOL						sShowFileAndLine = NO;
static BOOL						sShowClass = YES;
static BOOL						sDefaultDisplay = YES;
static BOOL						sShowApplication = NO;
static BOOL						sOverrideInEffect = NO;
static BOOL						sOverrideValue = NO;

// These specific values are used for true, false and inherit in the cache and explicitSettings dictionaries so we can use pointer comparison.
static NSString * const			kTrueToken = @"on";
static NSString * const			kFalseToken = @"off";
static NSString * const			kInheritToken = @"inherit";


// To avoid recursion/self-dependencies, OOLog gets its own logging function.
#define OOLogInternal(cond, format, ...) do { if ((cond)) { OOLogInternal_(OOLOG_FUNCTION_NAME, format, ## __VA_ARGS__); }} while (0)
static void OOLogInternal_(const char *inFunction, NSString *inFormat, ...);


// Functions used internally
static void LoadExplicitSettings(void);
static void LoadExplicitSettingsFromDictionary(NSDictionary *inDict);
static id ResolveDisplaySetting(NSString *inMessageClass);
static id ResolveMetaClassReference(NSString *inMetaClass, NSMutableSet *ioSeenMetaClasses);

OOINLINE unsigned GetIndentLevel(void) PURE_FUNC;
OOINLINE void SetIndentLevel(unsigned level);


#ifndef OOLOG_NO_FILE_NAME
static NSMutableDictionary		*sFileNamesCache = nil;
static NSString *AbbreviatedFileName(const char *inName);
#endif


// Given a boolean, return the appropriate value for the cache dictionary.
static inline id CacheValue(BOOL inValue) __attribute__((pure));
static inline id CacheValue(BOOL inValue)
{
	return inValue ? kTrueToken : kFalseToken;
}


/*	Inited()
	Test wether OOLoggingInit() has been called.
*/
static inline BOOL Inited(void)
{
	if (EXPECT(sInited)) return YES;
	OOLogInternal(OOLOG_NOT_INITED, @"ERROR: OOLoggingInit() has not been called.");
	return NO;
}


BOOL OOLogWillDisplayMessagesInClass(NSString *inMessageClass)
{
	id				value = nil;
	
	if (!Inited()) return NO;
	
	if (sOverrideInEffect)  return sOverrideValue;
	
	[sLock lock];
	
	// Look for cached value
	value = [sDerivedSettingsCache objectForKey:inMessageClass];
	if (EXPECT_NOT(value == nil))
	{
		// No cached value.
		value = ResolveDisplaySetting(inMessageClass);
		
		if (value != nil)
		{
			if (EXPECT_NOT(sDerivedSettingsCache == nil)) sDerivedSettingsCache = [[NSMutableDictionary alloc] init];
			[sDerivedSettingsCache setObject:value forKey:inMessageClass];
		}
	}
	[sLock unlock];
	
	OOLogInternal(OOLOG_SETTING_RETRIEVE, @"%@ is %s", inMessageClass, (value == kTrueToken) ? "on" : "off");
	return value == kTrueToken;
}


void OOLogSetDisplayMessagesInClass(NSString *inClass, BOOL inFlag)
{
	id				value = nil;
	
	if (!Inited()) return;
	
	[sLock lock];
	value = [sExplicitSettings objectForKey:inClass];
	if (value == nil || value != CacheValue(inFlag))
	{
		OOLogInternal(OOLOG_SETTING_SET, @"Setting %@ to %s", inClass, inFlag ? "ON" : "OFF");
		
		[sExplicitSettings setObject:CacheValue(inFlag) forKey:inClass];
		
		// Clear cache and let it be rebuilt as needed. Cost of rebuilding cache is not sufficient to warrant complexity of a partial clear.
		[sDerivedSettingsCache release];
		sDerivedSettingsCache = nil;
	}
	else
	{
		OOLogInternal(OOLOG_SETTING_SET, @"Keeping %@ %s", inClass, inFlag ? "ON" : "OFF");
	}
	[sLock unlock];
}


NSString *OOLogGetParentMessageClass(NSString *inClass)
{
	NSRange					range;
	
	if (inClass == nil) return nil;
	
	range = [inClass rangeOfString:@"." options:NSCaseInsensitiveSearch | NSLiteralSearch | NSBackwardsSearch];	// Only NSBackwardsSearch is important, others are optimizations
	if (range.location == NSNotFound) return nil;
	
	return [inClass substringToIndex:range.location];
}


#if !OOLOG_SHORT_CIRCUIT

void OOLogIndentIf(NSString *inMessageClass)
{
	if (OOLogWillDisplayMessagesInClass(inMessageClass)) OOLogIndent();
}


void OOLogOutdentIf(NSString *inMessageClass)
{
	if (OOLogWillDisplayMessagesInClass(inMessageClass)) OOLogOutdent();
}

#endif


#if USE_INDENT_GLOBALS

#if OOLITE_USE_TLS
	#define INDENT_LOCK()		do {} while (0)
	#define INDENT_UNLOCK()		do {} while (0)
#else
	#define INDENT_LOCK()		[sLock lock]
	#define INDENT_UNLOCK()		[sLock unlock]
#endif


OOINLINE unsigned GetIndentLevel(void)
{
	return sIndentLevel;
}


OOINLINE void SetIndentLevel(unsigned value)
{
	sIndentLevel = value;
}


void OOLogPushIndent(void)
{
	OOLogIndentStackElement	*elem = NULL;
	
	elem = malloc(sizeof *elem);
	if (elem != NULL)
	{
		INDENT_LOCK();
		
		elem->indent = sIndentLevel;
		elem->link = sIndentStack;
		sIndentStack = elem;
		
		INDENT_UNLOCK();
	}
}


void OOLogPopIndent(void)
{
	INDENT_LOCK();
	
	OOLogIndentStackElement	*elem = sIndentStack;
	
	if (elem != NULL)
	{
		sIndentStack = elem->link;
		sIndentLevel = elem->indent;
		free(elem);
	}
	else
	{
		OOLogInternal(OOLOG_BAD_POP_INDENT, @"OOLogPopIndent(): state stack underflow.");
	}
	INDENT_UNLOCK();
}

#else	// !USE_INDENT_GLOBALS

#define INDENT_LOCK()			do {} while (0)
#define INDENT_UNLOCK()			do {} while (0)


OOINLINE unsigned GetIndentLevel(void)
{
	NSMutableDictionary *threadDict = [[NSThread currentThread] threadDictionary];
	return [[threadDict objectForKey:kIndentLevelKey] unsignedIntValue];
}


OOINLINE void SetIndentLevel(unsigned value)
{
	NSMutableDictionary *threadDict = [[NSThread currentThread] threadDictionary];
	[threadDict setObject:[NSNumber numberWithUnsignedInt:value] forKey:kIndentLevelKey];
}


void OOLogPushIndent(void)
{
	OOLogIndentStackElement	*elem = NULL;
	NSMutableDictionary		*threadDict = nil;
	NSValue					*val = nil;
	
	elem = malloc(sizeof *elem);
	if (elem != NULL)
	{
		threadDict = [[NSThread currentThread] threadDictionary];
		val = [threadDict objectForKey:kIndentStackKey];
		
		elem->indent = [[threadDict objectForKey:kIndentLevelKey] intValue];
		elem->link = [val pointerValue];
		[threadDict setObject:[NSValue valueWithPointer:elem] forKey:kIndentStackKey];
	}
}


void OOLogPopIndent(void)
{
	OOLogIndentStackElement	*elem = NULL;
	NSMutableDictionary		*threadDict = nil;
	NSValue					*val = nil;
	
	threadDict = [[NSThread currentThread] threadDictionary];
	val = [threadDict objectForKey:kIndentStackKey];
	
	elem = [val pointerValue];
	
	if (elem != NULL)
	{
		[threadDict setObject:[NSNumber numberWithUnsignedInt:elem->indent] forKey:kIndentLevelKey];
		[threadDict setObject:[NSValue valueWithPointer:elem->link] forKey:kIndentStackKey];
		free(elem);
	}
	else
	{
		OOLogInternal(OOLOG_BAD_POP_INDENT, @"OOLogPopIndent(): state stack underflow.");
	}
}

#endif	// USE_INDENT_GLOBALS


void OOLogIndent(void)
{
	INDENT_LOCK();

	SetIndentLevel(GetIndentLevel() + 1);
	
	INDENT_UNLOCK();
}


void OOLogOutdent(void)
{
	INDENT_LOCK();
	
	unsigned indentLevel = GetIndentLevel();
	if (indentLevel != 0)  SetIndentLevel(indentLevel - 1);
	
	INDENT_UNLOCK();
}


void OOLogWithFunctionFileAndLine(NSString *inMessageClass, const char *inFunction, const char *inFile, unsigned long inLine, NSString *inFormat, ...)
{
	va_list				args;
	
	va_start(args, inFormat);
	OOLogWithFunctionFileAndLineAndArguments(inMessageClass, inFunction, inFile, inLine, inFormat, args);
	va_end(args);
}


void OOLogWithFunctionFileAndLineAndArguments(NSString *inMessageClass, const char *inFunction, const char *inFile, unsigned long inLine, NSString *inFormat, va_list inArguments)
{
	NSAutoreleasePool	*pool = nil;
	NSString			*formattedMessage = nil;
	unsigned			indentLevel;
	
	if (inFormat == nil)  return;
	
#if !OOLOG_SHORT_CIRCUIT
	if (!OOLogWillDisplayMessagesInClass(inMessageClass))  return;
#endif
	
	pool = [[NSAutoreleasePool alloc] init];
	NS_DURING
		// Do argument substitution
		formattedMessage = [[[NSString alloc] initWithFormat:inFormat arguments:inArguments] autorelease];
		
		// Apply various prefix options
	#ifndef OOLOG_NO_FILE_NAME
		if (sShowFileAndLine && inFile != NULL)
		{
			if (sShowFunction)
			{
				formattedMessage = [NSString stringWithFormat:@"%s (%@:%u): %@", inFunction, AbbreviatedFileName(inFile), inLine, formattedMessage];
			}
			else
			{
				formattedMessage = [NSString stringWithFormat:@"%@:%u: %@", AbbreviatedFileName(inFile), inLine, formattedMessage];
			}
		}
		else
	#endif
		{
			if (sShowFunction)
			{
				formattedMessage = [NSString stringWithFormat:@"%s: %@", inFunction, formattedMessage];
			}
		}
		
		if (sShowClass)
		{
			if (sShowFunction || sShowFileAndLine)
			{
				formattedMessage = [NSString stringWithFormat:@"[%@] %@", inMessageClass, formattedMessage];
			}
			else
			{
				formattedMessage = [NSString stringWithFormat:@"[%@]: %@", inMessageClass, formattedMessage];
			}
		}
		
		if (sShowApplication)
		{
			if (sShowClass)
			{
				formattedMessage = [NSString stringWithFormat:@"%@ %@", APPNAME, formattedMessage];
			}
			else if (sShowFunction || sShowFileAndLine)
			{
				formattedMessage = [NSString stringWithFormat:@"%@ - %@", APPNAME, formattedMessage];
			}
			else
			{
				formattedMessage = [NSString stringWithFormat:@"%@: %@", APPNAME, formattedMessage];
			}
		}
		
		// Apply indentation
		indentLevel = GetIndentLevel();
		if (indentLevel != 0)
		{
			#define INDENT_FACTOR	2		/* Spaces per indent level */
			#define MAX_INDENT		64		/* Maximum number of indentation _spaces_ */
			
			unsigned			indent;
								// String of 64 spaces (null-terminated)
			const char			spaces[MAX_INDENT + 1] =
								"                                                                ";
			const char			*indentString;
			
			indent = INDENT_FACTOR * indentLevel;
			if (MAX_INDENT < indent) indent = MAX_INDENT;
			indentString = &spaces[MAX_INDENT - indent];
			
			formattedMessage = [NSString stringWithFormat:@"%s%@", indentString, formattedMessage];
		}
		
		OOLogOutputHandlerPrint(formattedMessage);
	NS_HANDLER
		OOLogInternal(OOLOG_EXCEPTION_IN_LOG, @"***** Exception thrown during logging: %@ : %@", [localException name], [localException reason]);
	NS_ENDHANDLER
	
	[pool release];
}


void OOLogGenericParameterErrorForFunction(const char *inFunction)
{
	OOLog(kOOLogParameterError, @"***** %s: bad parameters. (This is an internal programming error, please report it.)", inFunction);
}


void OOLogGenericSubclassResponsibilityForFunction(const char *inFunction)
{
	OOLog(kOOLogSubclassResponsibility, @"***** %s is a subclass responsibility. (This is an internal programming error, please report it.)", inFunction);
}


BOOL OOLogShowApplicationName(void)
{
	return sShowApplication;
}


void OOLogSetShowApplicationName(BOOL flag)
{
	flag = !!flag;	// YES or NO, not 42.
	
	if (flag != sShowApplication)
	{
		sShowApplication = flag;
		[[NSUserDefaults standardUserDefaults] setBool:flag forKey:@"logging-show-app-name"];
	}
}


BOOL OOLogShowFunction(void)
{
	return sShowFunction;
}


void OOLogSetShowFunction(BOOL flag)
{
	flag = !!flag;	// YES or NO, not 42.
	
	if (flag != sShowFunction)
	{
		sShowFunction = flag;
		[[NSUserDefaults standardUserDefaults] setBool:flag forKey:@"logging-show-function"];
	}
}


BOOL OOLogShowFileAndLine(void)
{
	return sShowFileAndLine;
}


void OOLogSetShowFileAndLine(BOOL flag)
{
	flag = !!flag;	// YES or NO, not 42.
	
	if (flag != sShowFileAndLine)
	{
		sShowFileAndLine = flag;
		[[NSUserDefaults standardUserDefaults] setBool:flag forKey:@"logging-show-file-and-line"];
	}
}


BOOL OOLogShowMessageClass(void)
{
	return sShowClass;
}


void OOLogSetShowMessageClass(BOOL flag)
{
	flag = !!flag;	// YES or NO, not 42.
	
	if (flag != sShowClass)
	{
		sShowClass = flag;
		[[NSUserDefaults standardUserDefaults] setBool:flag forKey:@"logging-show-class"];
	}
}


void OOLogSetShowMessageClassTemporary(BOOL flag)
{
	sShowClass = !!flag;	// YES or NO, not 42.
}


void OOLoggingInit(void)
{
	NSAutoreleasePool		*pool = nil;
	
	if (sInited) return;
	
	pool = [[NSAutoreleasePool alloc] init];
	
	OOLogOutputHandlerInit();
	
	sLock = [[NSLock alloc] init];
	[sLock ooSetName:@"OOLogging lock"];
	if (sLock == nil) exit(EXIT_FAILURE);
	
	LoadExplicitSettings();
	sInited = YES;
	
	OOPrintLogHeader();
	
	[pool release];
}


void OOLoggingTerminate(void)
{
	if (!sInited) return;
	
	OOLogOutputHandlerClose();
	
	/*	We do not set sInited to NO. Instead, the output handler is required
		to be able to handle working even after being closed. Under OS X, this
		is done by writing to stderr in this case; on other platforms, NSLog()
		is used and OOLogOutputHandlerClose() is a no-op.
	*/
}


void OOLogInsertMarker(void)
{
	static unsigned		lastMarkerID = 0;
	unsigned			thisMarkerID;
	NSString			*marker = nil;
	
	[sLock lock];
	thisMarkerID = ++lastMarkerID;
	[sLock unlock];
	
	marker = [NSString stringWithFormat:@"\n\n========== [Marker %u] ==========", thisMarkerID];
	OOLogOutputHandlerPrint(marker);
}


NSString * const kOOLogSubclassResponsibility		= @"general.error.subclassResponsibility";
NSString * const kOOLogParameterError				= @"general.error.parameterError";
NSString * const kOOLogDeprecatedMethod				= @"general.error.deprecatedMethod";
NSString * const kOOLogAllocationFailure			= @"general.error.allocationFailure";
NSString * const kOOLogInconsistentState			= @"general.error.inconsistentState";
NSString * const kOOLogException					= @"exception";
NSString * const kOOLogFileNotFound					= @"files.notFound";
NSString * const kOOLogFileNotLoaded				= @"files.notLoaded";
NSString * const kOOLogOpenGLError					= @"rendering.opengl.error";
NSString * const kOOLogUnconvertedNSLog				= @"unclassified";


/*	OOLogInternal_()
	Implementation of OOLogInternal(), private logging function used by
	OOLogging so it doesn’t depend on itself (and risk recursiveness).
*/
static void OOLogInternal_(const char *inFunction, NSString *inFormat, ...)
{
	va_list				args;
	NSString			*formattedMessage = nil;
	NSAutoreleasePool	*pool = nil;
	
	pool = [[NSAutoreleasePool alloc] init];
	
	NS_DURING
		va_start(args, inFormat);
		formattedMessage = [[[NSString alloc] initWithFormat:inFormat arguments:args] autorelease];
		va_end(args);
		
		formattedMessage = [NSString stringWithFormat:@"OOLogging internal - %s: %@", inFunction, formattedMessage];
		if (sShowApplication) formattedMessage = [NSString stringWithFormat:@"%@: %@", APPNAME, formattedMessage];
		
		OOLogOutputHandlerPrint(formattedMessage);
	NS_HANDLER
		fprintf(stderr, "***** Exception in OOLogInternal_(): %s : %s", [[localException name] UTF8String], [[localException reason] UTF8String]);
	NS_ENDHANDLER
	
	[pool release];
}


/*	LoadExplicitSettings()
	Read settings from logcontrol.plist, merge in settings from preferences.
*/
static void LoadExplicitSettings(void)
{
	NSEnumerator		*rootEnum = nil;
	NSString			*basePath = nil;
	NSString			*configPath = nil;
	NSDictionary		*dict = nil;
	NSUserDefaults		*prefs = nil;
	id					value = nil;
	
	if (sExplicitSettings != nil) return;
	
	sExplicitSettings = [[NSMutableDictionary alloc] init];
	
	rootEnum = [[ResourceManager rootPaths] objectEnumerator];
	while ((basePath = [rootEnum nextObject]))
	{
		configPath = [[basePath stringByAppendingPathComponent:@"Config"]
								stringByAppendingPathComponent:@"logcontrol.plist"];
		dict = OODictionaryFromFile(configPath);
		if (dict == nil)
		{
			configPath = [basePath stringByAppendingPathComponent:@"logcontrol.plist"];
			dict = OODictionaryFromFile(configPath);
		}
		if (dict != nil)
		{
			LoadExplicitSettingsFromDictionary(dict);
		}
	}
	
	// Get overrides from preferences
	prefs = [NSUserDefaults standardUserDefaults];
	dict = [prefs objectForKey:@"logging-enable"];
	if ([dict isKindOfClass:[NSDictionary class]])
	{
		LoadExplicitSettingsFromDictionary(dict);
	}
	
	// Get _default and _override value
	value = [sExplicitSettings objectForKey:@"_default"];
	if (value != nil && [value respondsToSelector:@selector(boolValue)])
	{
		if (value == kTrueToken) sDefaultDisplay = YES;
		else if (value == kFalseToken) sDefaultDisplay = NO;
		else OOLogInternal(OOLOG_BAD_DEFAULT_SETTING, @"_default may not be set to a metaclass, ignoring.");
		
		[sExplicitSettings removeObjectForKey:@"_default"];
	}
	value = [sExplicitSettings objectForKey:@"_override"];
	if (value != nil && [value respondsToSelector:@selector(boolValue)])
	{
		if (value == kTrueToken)
		{
			sOverrideInEffect = YES;
			sOverrideValue = YES;
		}
		else if (value == kFalseToken)
		{
			sOverrideInEffect = YES;
			sOverrideValue = NO;
		}
		else OOLogInternal(OOLOG_BAD_DEFAULT_SETTING, @"_override may not be set to a metaclass, ignoring.");
		
		[sExplicitSettings removeObjectForKey:@"_override"];
	}
	
	// Load display settings
	sShowApplication = [prefs boolForKey:@"logging-show-app-name" defaultValue:sShowApplication];
	sShowFunction = [prefs boolForKey:@"logging-show-function" defaultValue:sShowFunction];
	sShowFileAndLine = [prefs boolForKey:@"logging-show-file-and-line" defaultValue:sShowFileAndLine];
	sShowClass = [prefs boolForKey:@"logging-show-class" defaultValue:sShowClass];
	
	OOLogInternal(OOLOG_SETTING_SET, @"Settings: %@", sExplicitSettings);
}


/*	LoadExplicitSettingsFromDictionary()
	Helper for LoadExplicitSettings().
*/
static void LoadExplicitSettingsFromDictionary(NSDictionary *inDict)
{
	NSEnumerator		*keyEnum = nil;
	id					key = nil;
	id					value = nil;
	
	for (keyEnum = [inDict keyEnumerator]; (key = [keyEnum nextObject]); )
	{
		value = [inDict objectForKey:key];
		
		/*	Supported values:
			"yes", "true" or "on" -> kTrueToken
			"no", "false" or "off" -> kFalseToken
			"inherit" or "inherited" -> nil
			NSNumber -> kTrueToken or kFalseToken
			"$metaclass" -> "$metaclass"
		*/
		if ([value isKindOfClass:[NSString class]])
		{
			if (NSOrderedSame == [value caseInsensitiveCompare:@"yes"] ||
				NSOrderedSame == [value caseInsensitiveCompare:@"true"] ||
				NSOrderedSame == [value caseInsensitiveCompare:@"on"])
			{
				value = kTrueToken;
			}
			else if (NSOrderedSame == [value caseInsensitiveCompare:@"no"] ||
				NSOrderedSame == [value caseInsensitiveCompare:@"false"] ||
				NSOrderedSame == [value caseInsensitiveCompare:@"off"])
			{
				value = kFalseToken;
			}
			else if (NSOrderedSame == [value caseInsensitiveCompare:@"inherit"] ||
				NSOrderedSame == [value caseInsensitiveCompare:@"inherited"])
			{
				value = nil;
				[sExplicitSettings removeObjectForKey:key];
			}
			else if (![value hasPrefix:@"$"])
			{
				OOLogInternal(OOLOG_BAD_SETTING, @"Bad setting value \"%@\" (expected yes, no, inherit or $metaclass).", value);
				value = nil;
			}
		}
		else if ([value respondsToSelector:@selector(boolValue)])
		{
			value = CacheValue([value boolValue]);
		}
		else
		{
			OOLogInternal(OOLOG_BAD_SETTING, @"Bad setting value \"%@\" (expected yes, no, inherit or $metaclass).", value);
			value = nil;
		}
		
		if (value != nil)
		{
			[sExplicitSettings setObject:value forKey:key];
		}
	}
}


#ifndef OOLOG_NO_FILE_NAME
/*	AbbreviatedFileName()
	Map full file paths provided by __FILE__ to more mananagable file names,
	with caching.
*/
static NSString *AbbreviatedFileName(const char *inName)
{
	NSValue				*key = nil;
	NSString			*name = nil;
	
	if (inName == NULL)  return @"unspecified file";
	
	[sLock lock];
	key = [NSValue valueWithPointer:inName];
	name = [sFileNamesCache objectForKey:key];
	if (name == nil)
	{
		name = [[NSString stringWithUTF8String:inName] lastPathComponent];
		if (sFileNamesCache == nil) sFileNamesCache = [[NSMutableDictionary alloc] init];
		[sFileNamesCache setObject:name forKey:key];
	}
	[sLock unlock];
	
	return name;
}
#endif


/*	Look up setting for a message class in explicit settings, resolving
	inheritance and metaclasses.
*/
static id ResolveDisplaySetting(NSString *inMessageClass)
{
	id					value = nil;
	NSMutableSet		*seenMetaClasses = nil;
	
	if (inMessageClass == nil) return CacheValue(sDefaultDisplay);
	
	value = [sExplicitSettings objectForKey:inMessageClass];
	
	// Simple case: explicit setting for this value
	if (value == kTrueToken || value == kFalseToken) return value;
	
	// Simplish case: use inherited value
	if (value == nil || value == kInheritToken) return ResolveDisplaySetting(OOLogGetParentMessageClass(inMessageClass));
	
	// Less simple case: should be a metaclass.
	seenMetaClasses = [NSMutableSet set];
	return ResolveMetaClassReference(value, seenMetaClasses);
}


/*	Resolve a metaclass reference, recursively if necessary. The
	ioSeenMetaClasses dictionary is used to avoid loops.
*/
static id ResolveMetaClassReference(NSString *inMetaClass, NSMutableSet *ioSeenMetaClasses)
{
	id					value = nil;
	
	// All values should have been checked at load time, but what the hey.
	if (![inMetaClass isKindOfClass:[NSString class]] || ![inMetaClass hasPrefix:@"$"])
	{
		OOLogInternal(OOLOG_BAD_SETTING, @"Bad setting value \"%@\" (expected yes, no, inherit or $metaclass). Falling back to _default.", inMetaClass);
		return CacheValue(sDefaultDisplay);
	}
	
	[ioSeenMetaClasses addObject:inMetaClass];
	
	value = [sExplicitSettings objectForKey:inMetaClass];
	
	if (value == kTrueToken || value == kFalseToken) return value;
	if (value == nil)
	{
		OOLogInternal(OOLOG_UNDEFINED_METACLASS, @"Reference to undefined metaclass %@, falling back to _default.", inMetaClass);
		return CacheValue(sDefaultDisplay);
	}
	
	// If we get here, it should be a metaclass reference.
	return ResolveMetaClassReference(value, ioSeenMetaClasses);
}
