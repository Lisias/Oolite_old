/*

OOLogging.h
By Jens Ayton

More flexible alternative to NSLog().

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


#import "OOLogging.h"


#ifdef GNUSTEP	// We really need better target macros.
#define SHOW_APPLICATION	NO
#else
#define SHOW_APPLICATION	YES
#endif
#define APPNAME @"Oolite"


// Internal logging control flags - like message classes, but less cool.
#define OOLOG_SETTING_SET			0
#define OOLOG_SETTING_RETRIEVE		0
#define OOLOG_METACLASS_LOOP		1
#define OOLOG_UNDEFINED_METACLASS	1
#define OOLOG_BAD_SETTING			1
#define OOLOG_BAD_DEFAULT_SETTING	1


static BOOL					sInited = NO;
static NSLock				*sLock = nil;
static NSMutableDictionary	*sExplicitSettings = nil;
static NSMutableDictionary	*sDerivedSettingsCache = nil;
static NSMutableDictionary	*sFileNamesCache = nil;
static NSNumber				*sCacheTrue = nil, *sCacheFalse = nil;	// These are the only values that may appear in sDerivedSettingsCache.
static unsigned				sIndentLevel = 0;
static BOOL					sShowFunction = NO;
static BOOL					sShowFileAndLine = NO;
static BOOL					sShowClass = YES;
static BOOL					sDefaultDisplay = YES;
static BOOL					sShowApplication = SHOW_APPLICATION;
static BOOL					sOverrideInEffect = NO;
static BOOL					sOverrideValue = NO;


// To avoid recursion/self-dependencies, OOLog gets its own logging function.
#define OOLogInternal(cond, format, ...) do { if ((cond)) { OOLogInternal_(OOLOG_FUNCTION_NAME, format, ## __VA_ARGS__); }} while (0)
static void OOLogInternal_(const char *inFunction, NSString *inFormat, ...);


static void LoadExplicitSettings(void);
static void LoadExplicitSettingsFromDictionary(NSDictionary *inDict);
static NSString *AbbreviatedFileName(const char *inName);
static NSNumber *ResolveDisplaySetting(NSString *inMessageClass);
static NSNumber *ResolveMetaClassReference(NSString *inMetaClass, NSMutableSet *ioSeenMetaClasses);


// Function to do actual printing
static inline void PrimitiveLog(NSString *inString)
{
	#ifdef __COREFOUNDATION_CFSTRING__
		CFShow((CFStringRef)inString);
	#else
		NSLog(@"%@", inString);
	#endif
}


static inline NSNumber *CacheValue(BOOL inValue)
{
	return inValue ? sCacheTrue : sCacheFalse;
}


static inline BOOL Inited(void)
{
	if (__builtin_expect(sInited, YES)) return YES;
	PrimitiveLog(@"ERROR: OOLoggingInit() has not been called.");
	return NO;
}


BOOL OOLogWillDisplayMessagesInClass(NSString *inMessageClass)
{
	id				value = nil;
	
	if (!Inited()) return NO;
	
	[sLock lock];
	
	// Look for cached value
	value = [sDerivedSettingsCache objectForKey:inMessageClass];
	if (__builtin_expect(value == nil, 0))
	{
		// No cached value.
		value = ResolveDisplaySetting(inMessageClass);
		
		if (value != nil)
		{
			[sDerivedSettingsCache setObject:value forKey:inMessageClass];
		}
	}
	[sLock unlock];
	
	OOLogInternal(OOLOG_SETTING_RETRIEVE, @"%@ is %s", inMessageClass, (value == sCacheTrue) ? "on" : "off");
	return value == sCacheTrue;
}


void OOLogSetDisplayMessagesInClass(NSString *inClass, BOOL inFlag)
{
	id				value = nil;
	
	if (!Inited()) return;
	
	[sLock lock];
	value = [sExplicitSettings objectForKey:inClass];
	if (value == nil || [value boolValue] != inFlag)
	{
		OOLogInternal(OOLOG_SETTING_SET, @"Setting %@ to %s", inClass, inFlag ? "ON" : "OFF");
		
		value = [NSNumber numberWithBool:inFlag];
		[sExplicitSettings setObject:value forKey:inClass];
		
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
	NSRange			range;
	
	if (inClass == nil) return nil;
	
	range = [inClass rangeOfString:@"." options:NSCaseInsensitiveSearch | NSLiteralSearch | NSBackwardsSearch];	// Only NSBackwardsSearch is important, others are optimizations
	if (range.location == NSNotFound) return nil;
	
	return [inClass substringToIndex:range.location];
}


void OOLogIndent(void)
{
	// These could be handled with atomic updates, but aren’t called much, so let’s not introduce porting complexity.
	[sLock lock];
	++sIndentLevel;
	[sLock unlock];
}


void OOLogOutdent(void)
{
	[sLock lock];
	if (sIndentLevel != 0) --sIndentLevel;
	[sLock unlock];
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
	
	pool = [[NSAutoreleasePool alloc] init];
	
	if (!OOLogWillDisplayMessagesInClass(inMessageClass))
	{
		[pool release];
		return;
	}
	
	// Do argument substitution
	formattedMessage = [[[NSString alloc] initWithFormat:inFormat arguments:inArguments] autorelease];
	
	// Apply various prefix options
	if (sShowFunction)
	{
		if (sShowFileAndLine)
		{
			formattedMessage = [NSString stringWithFormat:@"%s (%@:%u): %@", inFunction, AbbreviatedFileName(inFile), inLine, formattedMessage];
		}
		else
		{
			formattedMessage = [NSString stringWithFormat:@"%s: %@", inFunction, formattedMessage];
		}
	}
	else
	{
		if (sShowFileAndLine)
		{
			formattedMessage = [NSString stringWithFormat:@"%@:%u: %@", AbbreviatedFileName(inFile), inLine, formattedMessage];
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
	if (sIndentLevel != 0)
	{
		#define INDENT_FACTOR	2		/* Spaces per indent level */
		#define MAX_INDENT		64		/* Maximum number of indentation _spaces_ */
		
		unsigned			indent;
							// String of 64 spaces (null-terminated)
		const char			spaces[MAX_INDENT + 1] =
							"                                                                ";
		const char			*indentString;
		
		indent = INDENT_FACTOR * sIndentLevel;
		if (MAX_INDENT < indent) indent = MAX_INDENT;
		indentString = &spaces[MAX_INDENT - indent];
		
		formattedMessage = [NSString stringWithFormat:@"%s%@", indentString, formattedMessage];
	}
	
	PrimitiveLog(formattedMessage);
	
	[pool release];
}


void OOLoggingInit(void)
{
	NSAutoreleasePool		*pool = nil;
	
	if (sInited) return;
	
	pool = [[NSAutoreleasePool alloc] init];
	sLock = [[NSLock alloc] init];
	if (sLock == nil) abort();
	
	LoadExplicitSettings();
	sInited = YES;
	[pool release];
}


NSString * const kOOLogSubclassResponsibility		= @"general.subclassresponsibility";
NSString * const kOOLogParameterError				= @"general.parametererror";
NSString * const kOOLogException					= @"exception";
NSString * const kOOLogFileNotFound					= @"files.notfound";
NSString * const kOOLogFileNotLoaded				= @"files.notloaded";
NSString * const kOOLogOpenGLError					= @"rendering.opengl.error";
NSString * const kOOLogOpenGLVersion				= @"rendering.opengl.version";
NSString * const kOOLogOpenGLShaderSupport			= @"rendering.opengl.shaders.support";
NSString * const kOOLogOpenGLExtensions				= @"rendering.opengl.extensions";
NSString * const kOOLogOpenGLExtensionsVAR			= @"rendering.opengl.extensions.var";
NSString * const kOOLogOpenGLStateDump				= @"rendering.opengl.statedump";


static void OOLogInternal_(const char *inFunction, NSString *inFormat, ...)
{
	va_list				args;
	NSString			*formattedMessage = nil;
	NSAutoreleasePool	*pool = nil;
	
	pool = [[NSAutoreleasePool alloc] init];
	
	
	va_start(args, inFormat);
	formattedMessage = [[[NSString alloc] initWithFormat:inFormat arguments:args] autorelease];
	va_end(args);
	
	formattedMessage = [NSString stringWithFormat:@"OOLogging internal - %s: %@", inFunction, formattedMessage];
	if (sShowApplication) formattedMessage = [APPNAME stringByAppendingString:formattedMessage];
	
	PrimitiveLog(formattedMessage);
	
	[pool release];
}


static void LoadExplicitSettings(void)
{
	NSString			*configPath = nil;
	NSDictionary		*dict = nil;
	NSUserDefaults		*prefs = nil;
	id					value = nil;
	
	if (sExplicitSettings != nil) return;
	
	sExplicitSettings = [[NSMutableDictionary alloc] init];
	
	sCacheTrue = [[NSNumber numberWithBool:YES] retain];
	sCacheFalse = [[NSNumber numberWithBool:NO] retain];
	
	// Load defaults from logcontrol.plist
	configPath = [[NSBundle mainBundle] pathForResource:@"logcontrol" ofType:@"plist"];
	dict = [NSDictionary dictionaryWithContentsOfFile:configPath];
	LoadExplicitSettingsFromDictionary(dict);
	
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
		if (value == sCacheTrue) sDefaultDisplay = YES;
		else if (value == sCacheFalse) sDefaultDisplay = NO;
		else OOLogInternal(OOLOG_BAD_DEFAULT_SETTING, @"_default may not be set to a metaclass, ignoring.");
		
		[sExplicitSettings removeObjectForKey:@"_default"];
	}
	value = [sExplicitSettings objectForKey:@"_override"];
	if (value != nil && [value respondsToSelector:@selector(boolValue)])
	{
		if (value == sCacheTrue)
		{
			sOverrideInEffect = YES;
			sOverrideValue = YES;
		}
		else if (value == sCacheFalse)
		{
			sOverrideInEffect = YES;
			sOverrideValue = NO;
		}
		else OOLogInternal(OOLOG_BAD_DEFAULT_SETTING, @"_override may not be set to a metaclass, ignoring.");
		
		[sExplicitSettings removeObjectForKey:@"_override"];
	}
	
	// Load display settings
	value = [prefs objectForKey:@"logging-show-app-name"];
	if (value != nil && [value respondsToSelector:@selector(boolValue)])
	{
		sShowApplication = [value boolValue];
	}
	value = [prefs objectForKey:@"logging-show-function"];
	if (value != nil && [value respondsToSelector:@selector(boolValue)])
	{
		sShowFunction = [value boolValue];
	}
	value = [prefs objectForKey:@"logging-show-file-and-line"];
	if (value != nil && [value respondsToSelector:@selector(boolValue)])
	{
		sShowFileAndLine = [value boolValue];
	}
	value = [prefs objectForKey:@"logging-show-class"];
	if (value != nil && [value respondsToSelector:@selector(boolValue)])
	{
		sShowClass = [value boolValue];
	}
	
	OOLogInternal(OOLOG_SETTING_SET, @"Settings: %@", sExplicitSettings);
}


static void LoadExplicitSettingsFromDictionary(NSDictionary *inDict)
{
	NSEnumerator		*keyEnum = nil;
	id					key = nil;
	id					value = nil;
	
	for (keyEnum = [inDict keyEnumerator]; (key = [keyEnum nextObject]); )
	{
		value = [inDict objectForKey:key];
		
		/*	Supported values:
			"yes", "true" or "on" -> sCacheTrue
			"no", "false" or "off" -> sCacheFalse
			"inherit" or "inherited" -> nil
			NSNumber -> sCacheTrue or sCacheFalse
			"$metaclass" -> "$metaclass"
		*/
		if ([value isKindOfClass:[NSString class]])
		{
			if (NSOrderedSame == [value caseInsensitiveCompare:@"yes"] ||
				NSOrderedSame == [value caseInsensitiveCompare:@"true"] ||
				NSOrderedSame == [value caseInsensitiveCompare:@"on"])
			{
				value = sCacheTrue;
			}
			else if (NSOrderedSame == [value caseInsensitiveCompare:@"no"] ||
				NSOrderedSame == [value caseInsensitiveCompare:@"false"] ||
				NSOrderedSame == [value caseInsensitiveCompare:@"off"])
			{
				value = sCacheFalse;
			}
			else if (NSOrderedSame == [value caseInsensitiveCompare:@"inherit"] ||
				NSOrderedSame == [value caseInsensitiveCompare:@"inherited"])
			{
				value = nil;
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


static NSString *AbbreviatedFileName(const char *inName)
{
	NSValue				*key = nil;
	NSString			*name = nil;
	
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


static NSNumber *ResolveDisplaySetting(NSString *inMessageClass)
{
	id					value = nil;
	NSMutableSet		*seenMetaClasses = nil;
	
	if (inMessageClass == nil) return CacheValue(sDefaultDisplay);
	
	value = [sExplicitSettings objectForKey:inMessageClass];
	
	// Simple case: explicit setting for this value
	if (value == sCacheTrue || value == sCacheFalse) return value;
	
	// Simplish case: nil == use inherited value
	if (value == nil) return ResolveDisplaySetting(OOLogGetParentMessageClass(inMessageClass));
	
	// Less simple case: should be a metaclass.
	seenMetaClasses = [NSMutableSet set];
	return ResolveMetaClassReference(value, seenMetaClasses);
}


static NSNumber *ResolveMetaClassReference(NSString *inMetaClass, NSMutableSet *ioSeenMetaClasses)
{
	id					value = nil;
	
	// All values should have been checked at load time, but what the hey.
	if (![inMetaClass hasPrefix:@"$"])
	{
		OOLogInternal(OOLOG_BAD_SETTING, @"Bad setting value \"%@\" (expected yes, no, inherit or $metaclass). Falling back to _default.", inMetaClass);
		return CacheValue(sDefaultDisplay);
	}
	
	[ioSeenMetaClasses addObject:inMetaClass];
	
	value = [sExplicitSettings objectForKey:inMetaClass];
	
	if (value == sCacheTrue || value == sCacheFalse) return value;
	if (value == nil)
	{
		OOLogInternal(OOLOG_UNDEFINED_METACLASS, @"Reference to undefined metaclass %@, falling back to _default.", inMetaClass);
		return CacheValue(sDefaultDisplay);
	}
	
	// If we get here, it should be a metaclass reference.
	return ResolveMetaClassReference(value, ioSeenMetaClasses);
}
