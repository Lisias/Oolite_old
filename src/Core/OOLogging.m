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


static NSMutableDictionary	*sExplicitSettings = nil;
static NSMutableDictionary	*sDerivedSettingsCache = nil;
static NSMutableDictionary	*sFileNamesCache = nil;
static unsigned				sIndentLevel = 0;
static BOOL					sShowFunction = NO;
static BOOL					sShowFileAndLine = NO;
static BOOL					sShowClass = YES;
static BOOL					sDefaultDisplay = YES;
static BOOL					sShowApplication = SHOW_APPLICATION;
static BOOL					sOverrideInEffect = NO;
static BOOL					sOverrideValue = NO;


// Function to do actual printing
#ifdef __COREFOUNDATION_CFSTRING__
	#define OOLOG_PRIMITIVE_LOG(foo)	CFShow(foo)
#else
	#define OOLOG_PRIMITIVE_LOG(foo)	NSLog(@"%@", foo)
#endif


// To avoid recursion/self-dependencies, OOLog gets its own logging function.
#define OOLogInternal(cond, format, ...) do { if ((cond)) { OOLogInternal_(OOLOG_FUNCTION_NAME, format, ## __VA_ARGS__); }} while (0)
static void OOLogInternal_(const char *inFunction, NSString *inFormat, ...);


static void LoadExplicitSettings(void);
static void LoadExplicitSettingsFromDictionary(NSDictionary *inDict);
static id LogWillDisplayMessagesInClassObj(NSString *inMessageClass);
static NSString *AbbreviatedFileName(const char *inName);


BOOL OOLogWillDisplayMessagesInClass(NSString *inMessageClass)
{
	BOOL result = [LogWillDisplayMessagesInClassObj(inMessageClass) boolValue];
	OOLogInternal(OOLOG_SETTING_RETRIEVE, @"%@ is %s", inMessageClass, result ? "on" : "off");
	
	return result;
}


void OOLogSetDisplayMessagesInClass(NSString *inClass, BOOL inFlag)
{
	id				value = nil;
	
	if (sExplicitSettings == nil) LoadExplicitSettings();
	
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
	++sIndentLevel;
}


void OOLogOutdent(void)
{
	if (sIndentLevel != 0) --sIndentLevel;
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
	
	OOLOG_PRIMITIVE_LOG(formattedMessage);
	
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
	
	OOLOG_PRIMITIVE_LOG(formattedMessage);
	
	[pool release];
}


static void LoadExplicitSettings(void)
{
	NSString			*configPath = nil;
	NSDictionary		*dict = nil;
	NSUserDefaults		*prefs = nil;
	id					value = nil;
	
	sExplicitSettings = [[NSMutableDictionary alloc] init];
	
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
		sDefaultDisplay = [value boolValue];
		[sExplicitSettings removeObjectForKey:@"_default"];
	}
	value = [sExplicitSettings objectForKey:@"_override"];
	if (value != nil && [value respondsToSelector:@selector(boolValue)])
	{
		sOverrideInEffect = YES;
		sOverrideValue = [value boolValue];
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
	BOOL				boolValue, gotBoolValue;
	
	for (keyEnum = [inDict keyEnumerator]; (key = [keyEnum nextObject]); )
	{
		value = [inDict objectForKey:key];
		gotBoolValue = NO;
		
		// This is complicated a tad by the desire to support "inherited" - which just causes the key to be ignored and inheritance behaviour to take effect.
		if ([value isKindOfClass:[NSString class]])
		{
			if (NSOrderedSame == [value caseInsensitiveCompare:@"yes"] ||
				NSOrderedSame == [value caseInsensitiveCompare:@"true"] ||
				NSOrderedSame == [value caseInsensitiveCompare:@"on"])
			{
				boolValue = YES;
				gotBoolValue = YES;
			}
			else if (NSOrderedSame == [value caseInsensitiveCompare:@"no"] ||
				NSOrderedSame == [value caseInsensitiveCompare:@"false"] ||
				NSOrderedSame == [value caseInsensitiveCompare:@"off"])
			{
				boolValue = NO;
				gotBoolValue = YES;
			}
		}
		else if ([value respondsToSelector:@selector(boolValue)])
		{
			boolValue = [value boolValue];
			gotBoolValue = YES;
		}
		
		if (gotBoolValue)
		{
			[sExplicitSettings setObject:[NSNumber numberWithBool:boolValue] forKey:key];
		}
	}
}


static id LogWillDisplayMessagesInClassObj(NSString *inMessageClass)
{
	id					directValue = nil;
	id					value = nil;
	
	if (inMessageClass == nil) return [NSNumber numberWithBool:sDefaultDisplay];
	if (sOverrideInEffect) return [NSNumber numberWithBool:sOverrideValue];
	if (sExplicitSettings == nil) LoadExplicitSettings();
	
	// Use cached value if possible
	directValue = [sDerivedSettingsCache objectForKey:inMessageClass];
	
	// If no cached value, look for explicit value
	if (directValue == nil) directValue = [sExplicitSettings objectForKey:inMessageClass];
	value = directValue;
	
	// If no cached or explicit value, use inherited value
	if (value == nil) value = LogWillDisplayMessagesInClassObj(OOLogGetParentMessageClass(inMessageClass));
	
	// Maintain cache
	if (directValue == nil && value != nil)
	{
		if (sDerivedSettingsCache == nil) sDerivedSettingsCache = [[NSMutableDictionary alloc] init];
		[sDerivedSettingsCache setObject:value forKey:inMessageClass];
	}
	
	return value;
}


static NSString *AbbreviatedFileName(const char *inName)
{
	NSValue				*key = nil;
	NSString			*name = nil;
	
	key = [NSValue valueWithPointer:inName];
	name = [sFileNamesCache objectForKey:key];
	if (name == nil)
	{
		name = [[NSString stringWithUTF8String:inName] lastPathComponent];
		if (sFileNamesCache == nil) sFileNamesCache = [[NSMutableDictionary alloc] init];
		[sFileNamesCache setObject:name forKey:key];
	}
	
	return name;
}
