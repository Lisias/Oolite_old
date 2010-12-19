/*

OOJSScript.m

JavaScript support for Oolite
Copyright (C) 2007-2010 David Taylor and Jens Ayton.

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

#ifndef OO_CACHE_JS_SCRIPTS
#define OO_CACHE_JS_SCRIPTS		1
#endif

// Enable support for old event handler names through changedScriptHandlers.plist.
#define SUPPORT_CHANGED_HANDLERS 0


#import "OOJSScript.h"
#import "OOLogging.h"
#import "OOConstToString.h"
#import "Entity.h"
#import "OOJavaScriptEngine.h"
#import "NSStringOOExtensions.h"
#import "EntityOOJavaScriptExtensions.h"

#if SUPPORT_CHANGED_HANDLERS
#import "ResourceManager.h"
#endif

#if OO_CACHE_JS_SCRIPTS
#import <jsxdrapi.h>
#import "OOCacheManager.h"
#endif


typedef struct RunningStack RunningStack;
struct RunningStack
{
	RunningStack		*back;
	OOJSScript			*current;
};


static JSObject			*sScriptPrototype;
static RunningStack		*sRunningStack = NULL;


static void AddStackToArrayReversed(NSMutableArray *array, RunningStack *stack);

static JSScript *LoadScriptWithName(JSContext *context, NSString *path, JSObject *object, JSObject **outScriptObject, NSString **outErrorMessage);

#if OO_CACHE_JS_SCRIPTS
static NSData *CompiledScriptData(JSContext *context, JSScript *script);
static JSScript *ScriptWithCompiledData(JSContext *context, NSData *data);
#endif

static NSString *StrippedName(NSString *string);


static JSClass sScriptClass =
{
	"Script",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,
	JS_PropertyStub,
	JS_PropertyStub,
	JS_PropertyStub,
	JS_EnumerateStub,
	JS_ResolveStub,
	JS_ConvertStub,
	JSObjectWrapperFinalize
};


static JSFunctionSpec sScriptMethods[] =
{
	// JS name					Function					min args
	{ "toString",				JSObjectWrapperToString,	0, },
	{ 0 }
};


@interface OOJSScript (OOPrivate)

- (NSString *)scriptNameFromPath:(NSString *)path;

@end


@implementation OOJSScript

+ (id) scriptWithPath:(NSString *)path properties:(NSDictionary *)properties
{
	return [[[self alloc] initWithPath:path properties:properties] autorelease];
}


- (id) initWithPath:(NSString *)path properties:(NSDictionary *)properties
{
	OOJavaScriptEngine		*engine = nil;
	JSContext				*context = NULL;
	NSString				*problem = nil;		// Acts as error flag.
	JSScript				*script = NULL;
	JSObject				*scriptObject = NULL;
	jsval					returnValue = JSVAL_VOID;
	NSEnumerator			*keyEnum = nil;
	NSString				*key = nil;
	id						property = nil;
	
	self = [super init];
	if (self == nil) problem = @"allocation failure";
	
	engine = [OOJavaScriptEngine sharedEngine];
	context = [engine acquireContext];
	JS_BeginRequest(context);
	
	// Set up JS object
	if (!problem)
	{
		_jsSelf = JS_NewObject(context, &sScriptClass, sScriptPrototype, NULL);
		if (_jsSelf == NULL) problem = @"allocation failure";
	}
	
	if (!problem && !OOJS_AddGCObjectRoot(context, &_jsSelf, "Script object"))
	{
		problem = @"could not add JavaScript root object";
	}
	
#if OO_NEW_JS
	if (!problem && !OOJS_AddGCObjectRoot(context, &scriptObject, "Script GC holder"))
	{
		problem = @"could not add JavaScript root object";
	}
#endif
	
	if (!problem)
	{
		if (!JS_SetPrivate(context, _jsSelf, [self weakRetain]))  problem = @"could not set private backreference";
	}
	
	// Push self on stack of running scripts.
	RunningStack stackElement =
	{
		.back = sRunningStack,
		.current = self
	};
	sRunningStack = &stackElement;
	
	filePath = [path retain];
	
	if (!problem)
	{
		script = LoadScriptWithName(context, path, _jsSelf, &scriptObject, &problem);
	}
	
	// Set properties.
	if (!problem && properties != nil)
	{
		for (keyEnum = [properties keyEnumerator]; (key = [keyEnum nextObject]); )
		{
			if ([key isKindOfClass:[NSString class]])
			{
				property = [properties objectForKey:key];
				[self defineProperty:property named:key];
			}
		}
	}
	
	/*	Set initial name (in case of script error during initial run).
		The "name" ivar is not set here, so the property can be fetched from JS
		if we fail during setup. However, the "name" ivar is set later so that
		the script object can't be renamed after the initial run. This could
		probably also be achieved by fiddling with JS property attributes.
	*/
	[self setProperty:[self scriptNameFromPath:path] named:@"name"];
	
	// Run the script (allowing it to set up the properties we need, as well as setting up those event handlers)
	if (!problem)
	{
		OOJSStartTimeLimiterWithTimeLimit(kOOJSLongTimeLimit);
		if (!JS_ExecuteScript(context, _jsSelf, script, &returnValue))
		{
			problem = @"could not run script";
		}
		OOJSStopTimeLimiter();
		
		// We don't need the script any more - the event handlers hang around as long as the JS object exists.
		JS_DestroyScript(context, script);
	}
#if OO_NEW_JS
	JS_RemoveObjectRoot(context, &scriptObject);
#endif
	
	sRunningStack = stackElement.back;
	
	if (!problem)
	{
		// Get display attributes from script
		DESTROY(name);
		name = [StrippedName([[self propertyNamed:@"name"] description]) copy];
		if (name == nil)
		{
			name = [[self scriptNameFromPath:path] retain];
			[self setProperty:name named:@"name"];
		}
		
		version = [[[self propertyNamed:@"version"] description] copy];
		description = [[[self propertyNamed:@"description"] description] copy];
		
		OOLog(@"script.javaScript.load.success", @"Loaded JavaScript OXP: %@ -- %@", [self displayName], description ? description : (NSString *)@"(no description)");
	}
	
	DESTROY(filePath);	// Only used for error reporting during startup.
	
	if (problem)
	{
		OOLog(@"script.javaScript.load.failed", @"***** Error loading JavaScript script %@ -- %@", path, problem);
		[self release];
		self = nil;
	}
	
	JS_EndRequest(context);
	[engine releaseContext:context];
	
	return self;
	// Analyzer: object leaked. [Expected, object is retained by JS object.]
}


- (void) dealloc
{
	[name release];
	[description release];
	[version release];
	DESTROY(filePath);
	
	JSContext *context = [[OOJavaScriptEngine sharedEngine] acquireContext];
	JS_BeginRequest(context);
	
	JSObjectWrapperFinalize(context, _jsSelf);		// Release weakref to self
	JS_RemoveObjectRoot(context, &_jsSelf);			// Unroot jsSelf
	
	JS_EndRequest(context);
	[[OOJavaScriptEngine sharedEngine] releaseContext:context];
	
	[weakSelf weakRefDrop];
	
	[super dealloc];
}


- (NSString *)jsClassName
{
	return @"Script";
}


+ (OOJSScript *)currentlyRunningScript
{
	if (sRunningStack == NULL)  return NULL;
	return sRunningStack->current;
}


+ (NSArray *)scriptStack
{
	NSMutableArray			*result = nil;
	
	result = [NSMutableArray array];
	AddStackToArrayReversed(result, sRunningStack);
	return result;
}


- (id) weakRetain
{
	if (weakSelf == nil)  weakSelf = [OOWeakReference weakRefWithObject:self];
	return [weakSelf retain];
}


- (void) weakRefDied:(OOWeakReference *)weakRef
{
	if (weakRef == weakSelf)  weakSelf = nil;
}


- (NSString *) name
{
	if (name == nil)  name = [[self propertyNamed:@"name"] copy];
	if (name == nil)  return [self scriptNameFromPath:filePath];	// Special case for parse errors during load.
	return name;
}


- (NSString *) scriptDescription
{
	return description;
}


- (NSString *) version
{
	return version;
}


- (void)runWithTarget:(Entity *)target
{
	[self doEvent:@"tickle" withArguments:[NSArray arrayWithObject:[[PlayerEntity sharedPlayer] status_string]]];
}


- (jsval) functionValueNamed:(NSString *)eventName contextWithRequest:(JSContext *)context
{
	BOOL						OK;
	jsval						value;
	JSObject					*fakeRoot;	// Unneeded, but oldjs JS_GetMethod needs it to exist.
	
	// FIXME: this should be caching name->jsid mappings.
	OK = JS_GetMethod(context, _jsSelf, [eventName UTF8String], &fakeRoot, &value);
	
#if SUPPORT_CHANGED_HANDLERS
	if (!OK || JSVAL_IS_VOID(value))
	{
		// Look up event name in renaming table.
		static NSDictionary		*changedHandlers = nil;
		static NSMutableSet		*notedChanges = nil;
		id						oldNames = nil;
		NSEnumerator			*oldNameEnum = nil;
		NSString				*oldName = nil;
		NSString				*key = nil;
		
		if (notedChanges == nil)
		{
			notedChanges = [[NSMutableSet alloc] init];
			changedHandlers = [ResourceManager dictionaryFromFilesNamed:@"changedScriptHandlers.plist"
															   inFolder:@"Config"
															   andMerge:NO];
			[changedHandlers retain];
		}
		oldNames = [changedHandlers objectForKey:eventName];
		if ([oldNames isKindOfClass:[NSString class]])  oldNames = [NSArray arrayWithObject:oldNames];
		if ([oldNames isKindOfClass:[NSArray class]])
		{
			for (oldNameEnum = [oldNames objectEnumerator]; (oldName = [oldNameEnum nextObject]) && JSVAL_IS_VOID(value) && OK; )
			{
				OK = JS_GetMethod(context, _jsSelf, [oldName UTF8String], NULL, value);
				
				if (OK && !JSVAL_IS_VOID(value))
				{
					key = [NSString stringWithFormat:@"%@\n%@", self->name, oldName];
					if (![notedChanges containsObject:key])
					{
						[notedChanges addObject:key];
						OOReportJSWarning(context, @"The event handler %@ has been renamed to %@. The script %@ must be updated. The old form will not be supported in future versions of Oolite.", oldName, eventName, self->name);
					}
				}
			}
		}
	}
#endif
	
	if (OK)  return value;
	else  return JSVAL_VOID;
}


- (BOOL)doEvent:(NSString *)eventName withArguments:(NSArray *)arguments
{
	BOOL					OK = YES;
	jsval					value = JSVAL_VOID;
	jsval					function;
	uintN					i, argc;
	jsval					*argv = NULL;
	OOJavaScriptEngine		*engine = nil;
	JSContext				*context = NULL;
	
	engine = [OOJavaScriptEngine sharedEngine];
	context = [engine acquireContext];
	JS_BeginRequest(context);
	
	function = [self functionValueNamed:eventName contextWithRequest:context];
	if (!JSVAL_IS_VOID(function))
	{
		OOLog(@"script.trace.javaScript.event", @"Calling [%@].%@()", [self name], eventName);
		OOLogIndentIf(@"script.trace.javaScript.event");
		
		// Push self on stack of running scripts.
		RunningStack stackElement =
		{
			.back = sRunningStack,
			.current = self
		};
		sRunningStack = &stackElement;
		
		// Convert arguments to JS values and make them temporarily un-garbage-collectable.
		argc = [arguments count];
		if (argc != 0)
		{
			argv = malloc(sizeof *argv * argc);
			if (argv != NULL)
			{
				for (i = 0; i != argc; ++i)
				{
					argv[i] = [[arguments objectAtIndex:i] javaScriptValueInContext:context];
					OOJS_AddGCValueRoot(context, &argv[i], "JSScript event parameter");
				}
			}
			else  argc = 0;
		}
		
		// Actually call the function.
		OOJSStartTimeLimiter();
		OK = JS_CallFunctionValue(context, _jsSelf, function, argc, argv, &value);
		OOJSStopTimeLimiter();
		
		// Re-garbage-collectibalize the arguments and free the array.
		if (argv != NULL)
		{
			for (i = 0; i != argc; ++i)
			{
				JS_RemoveValueRoot(context, &argv[i]);
			}
			free(argv);
		}
		
		// Pop running scripts stack
		sRunningStack = stackElement.back;
		
		JS_ClearNewbornRoots(context);
		
		OOLogOutdentIf(@"script.trace.javaScript.event");
	}
	else
	{
		// No function
		OK = YES;
	}
	
	JS_EndRequest(context);
	[engine releaseContext:context];
	
	return OK;
}


- (id)propertyNamed:(NSString *)propName
{
	BOOL						OK;
	jsval						value = JSVAL_VOID;
	JSContext					*context = NULL;
	id							result = nil;
	
	if (propName == nil)  return nil;
	
	context = [[OOJavaScriptEngine sharedEngine] acquireContext];
	OK = JSGetNSProperty(NULL, _jsSelf, propName, &value);
	if (OK && !JSVAL_IS_VOID(value))  result = JSValueToObject(context, value);
	[[OOJavaScriptEngine sharedEngine] releaseContext:context];
	
	return result;
}


- (BOOL)setProperty:(id)value named:(NSString *)propName
{
	jsval						jsValue;
	JSContext					*context = NULL;
	BOOL						result = NO;
	
	if (value == nil || propName == nil)  return NO;
	
	context = [[OOJavaScriptEngine sharedEngine] acquireContext];
	jsValue = [value javaScriptValueInContext:context];
	if (!JSVAL_IS_VOID(jsValue))
	{
		result = JSDefineNSProperty(context, _jsSelf, propName, jsValue, NULL, NULL, JSPROP_ENUMERATE);
	}
	[[OOJavaScriptEngine sharedEngine] releaseContext:context];
	return result;
}


- (BOOL)defineProperty:(id)value named:(NSString *)propName
{
	jsval						jsValue;
	JSContext					*context = NULL;
	BOOL						result = NO;
	
	if (value == nil || propName == nil)  return NO;
	
	context = [[OOJavaScriptEngine sharedEngine] acquireContext];
	jsValue = [value javaScriptValueInContext:context];
	if (!JSVAL_IS_VOID(jsValue))
	{
		result = JSDefineNSProperty(context, _jsSelf, propName, jsValue, NULL, NULL, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
	}
	[[OOJavaScriptEngine sharedEngine] releaseContext:context];
	return result;
}


- (jsval)javaScriptValueInContext:(JSContext *)context
{
	return OBJECT_TO_JSVAL(_jsSelf);
}


+ (void)pushScript:(OOJSScript *)script
{
	RunningStack			*element = NULL;
	
	element = malloc(sizeof *element);
	if (element == NULL)  exit(EXIT_FAILURE);
	
	element->back = sRunningStack;
	element->current = script;
	sRunningStack = element;
}


+ (void)popScript:(OOJSScript *)script
{
	RunningStack			*element = NULL;
	
	assert(sRunningStack->current == script);
	
	element = sRunningStack;
	sRunningStack = sRunningStack->back;
	free(element);
}

@end


@implementation OOJSScript (OOPrivate)



/*	Generate default name for script which doesn't set its name property when
	first run.
 
	The generated name is <name>.anon-script, where <name> is selected as
	follows:
	* If path is nil (futureproofing), use the address of the script object.
	* If the file's name is something other than script.*, use the file name.
	* If the containing directory is something other than Config, use the
	containing directory's name.
	* Otherwise, use the containing directory's parent (which will generally
														be an OXP root directory).
	* If either of the two previous steps results in an empty string, fall
	back on the full path.
*/
- (NSString *)scriptNameFromPath:(NSString *)path
{
	NSString		*lastComponent = nil;
	NSString		*truncatedPath = nil;
	NSString		*theName = nil;
	
	if (path == nil) theName = [NSString stringWithFormat:@"%p", self];
	else
	{
		lastComponent = [path lastPathComponent];
		if (![lastComponent hasPrefix:@"script."]) theName = lastComponent;
		else
		{
			truncatedPath = [path stringByDeletingLastPathComponent];
			if (NSOrderedSame == [[truncatedPath lastPathComponent] caseInsensitiveCompare:@"Config"])
			{
				truncatedPath = [truncatedPath stringByDeletingLastPathComponent];
			}
			if (NSOrderedSame == [[truncatedPath pathExtension] caseInsensitiveCompare:@"oxp"])
			{
				truncatedPath = [truncatedPath stringByDeletingPathExtension];
			}
			
			lastComponent = [truncatedPath lastPathComponent];
			theName = lastComponent;
		}
	}
	
	if (0 == [theName length]) theName = path;
	
	return StrippedName([theName stringByAppendingString:@".anon-script"]);
}

@end


@implementation OOScript (OOJavaScriptConversion)

- (jsval)javaScriptValueInContext:(JSContext *)context
{
	return JSVAL_NULL;
}

@end


void InitOOJSScript(JSContext *context, JSObject *global)
{
	sScriptPrototype = JS_InitClass(context, global, NULL, &sScriptClass, NULL, 0, NULL, sScriptMethods, NULL, NULL);
	JSRegisterObjectConverter(&sScriptClass, JSBasicPrivateObjectConverter);
}


static void AddStackToArrayReversed(NSMutableArray *array, RunningStack *stack)
{
	if (stack != NULL)
	{
		AddStackToArrayReversed(array, stack->back);
		[array addObject:stack->current];
	}
}


static JSScript *LoadScriptWithName(JSContext *context, NSString *path, JSObject *object, JSObject **outScriptObject, NSString **outErrorMessage)
{
#if OO_CACHE_JS_SCRIPTS
	OOCacheManager				*cache = nil;
#endif
	NSString					*fileContents = nil;
	NSData						*data = nil;
	JSScript					*script = NULL;
	
	NSCParameterAssert(outScriptObject != NULL && outErrorMessage != NULL);
	*outErrorMessage = nil;
	
#if OO_CACHE_JS_SCRIPTS
	// Look for cached compiled script
	cache = [OOCacheManager sharedCache];
	data = [cache objectForKey:path inCache:@"compiled JavaScript scripts"];
	if (data != nil)
	{
		script = ScriptWithCompiledData(context, data);
	}
#endif
	
	if (script == NULL)
	{
		fileContents = [NSString stringWithContentsOfUnicodeFile:path];
		if (fileContents != nil)  data = [fileContents utf16DataWithBOM:NO];
		if (data == nil)  *outErrorMessage = @"could not load file";
		else
		{
			script = JS_CompileUCScript(context, object, [data bytes], [data length] / sizeof(unichar), [path UTF8String], 1);
#if OO_NEW_JS
			if (script != NULL)  *outScriptObject = JS_NewScriptObject(context, script);
#endif
			if (script == NULL)  *outErrorMessage = @"compilation failed";
		}
		
#if OO_CACHE_JS_SCRIPTS
		if (script != NULL)
		{
			// Write compiled script to cache
			data = CompiledScriptData(context, script);
			[cache setObject:data forKey:path inCache:@"compiled JavaScript scripts"];
		}
#endif
	}
	
	return script;
}


#if OO_CACHE_JS_SCRIPTS
static NSData *CompiledScriptData(JSContext *context, JSScript *script)
{
	JSXDRState					*xdr = NULL;
	NSData						*result = nil;
	uint32						length;
	void						*bytes = NULL;
	
	xdr = JS_XDRNewMem(context, JSXDR_ENCODE);
	if (xdr != NULL)
	{
		if (JS_XDRScript(xdr, &script))
		{
			bytes = JS_XDRMemGetData(xdr, &length);
			if (bytes != NULL)
			{
				result = [NSData dataWithBytes:bytes length:length];
			}
		}
		JS_XDRDestroy(xdr);
	}
	
	return result;
}


static JSScript *ScriptWithCompiledData(JSContext *context, NSData *data)
{
	JSXDRState					*xdr = NULL;
	JSScript					*result = NULL;
	
	if (data == nil)  return NULL;
	
	xdr = JS_XDRNewMem(context, JSXDR_DECODE);
	if (xdr != NULL)
	{
		JS_XDRMemSetData(xdr, (void *)[data bytes], [data length]);
		if (!JS_XDRScript(xdr, &result))  result = NULL;
		
		JS_XDRMemSetData(xdr, NULL, 0);	// Don't let it be freed by XDRDestroy
		JS_XDRDestroy(xdr);
	}
	
	return result;
}
#endif


static NSString *StrippedName(NSString *string)
{
	static NSCharacterSet *invalidSet = nil;
	if (invalidSet == nil)  invalidSet = [[NSCharacterSet characterSetWithCharactersInString:@"_ \t\n\r\v"] retain];
	
	return [string stringByTrimmingCharactersInSet:invalidSet];
}
