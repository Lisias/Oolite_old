/*

OOJSScript.m

JavaScript support for Oolite
Copyright (C) 2007 David Taylor and Jens Ayton.

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


#import "OOJSScript.h"
#import "OOLogging.h"
#import "OOConstToString.h"
#import "Entity.h"
#import "OOJavaScriptEngine.h"
#import "NSStringOOExtensions.h"
#import "EntityOOJavaScriptExtensions.h"

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

static JSScript *LoadScriptWithName(JSContext *context, NSString *name, JSObject *object, NSString **outErrorMessage);

#if OO_CACHE_JS_SCRIPTS
static NSData *CompiledScriptData(JSContext *context, JSScript *script);
static JSScript *ScriptWithCompiledData(JSContext *context, NSData *data);
#endif


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

+ (id)scriptWithPath:(NSString *)path properties:(NSDictionary *)properties
{
	return [[[self alloc] initWithPath:path properties:properties] autorelease];
}


- (id)initWithPath:(NSString *)path properties:(NSDictionary *)properties
{
	return [self initWithPath:path properties:properties context:[[OOJavaScriptEngine sharedEngine] context]];
}


- (id)initWithPath:(NSString *)path properties:(NSDictionary *)properties context:(JSContext *)inContext
{
	NSString				*problem = nil;		// Acts as error flag.
	JSScript				*script = NULL;
	jsval					returnValue;
	NSEnumerator			*keyEnum = nil;
	NSString				*key = nil;
	id						property = nil;
	
	self = [super init];
	if (self == nil) problem = @"allocation failure";
	
	// Set up JS object
	if (!problem)
	{
		context = inContext;
		// Do we actually want parent to be the global object here?
		object = JS_NewObject(context, &sScriptClass, sScriptPrototype, NULL /*JS_GetGlobalObject(context)*/);
		if (object == NULL) problem = @"allocation failure";
	}
	
	if (!problem)
	{
		if (!JS_SetPrivate(context, object, [self weakRetain]))  problem = @"could not set private backreference";
	}
	
	if (!problem)
	{
		if (!JS_AddNamedRoot(context, &object, "Script object")) // note 2nd arg is a pointer-to-pointer
		{
			problem = @"could not add JavaScript root object";
		}
	}
	
	if (!problem)
	{
		script = LoadScriptWithName(context, path, object, &problem);
		if (JS_GetScriptObject(script) == NULL)
		{
			/*scriptObject = JS_NewScriptObject(context, script);
			if (!JS_AddNamedRoot(context, &scriptObject, "Cached script reference object")) 
			{
				problem = @"could not add JavaScript root object";
			}*/
		}
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
	
	// Run the script (allowing it to set up the properties we need, as well as setting up those event handlers)
    if (!problem)
	{
		if (!JS_ExecuteScript(context, object, script, &returnValue))
		{
			problem = @"could not run script";
		}
		
		// We don't need the script any more - the event handlers hang around as long as the JS object exists.
		JS_DestroyScript(context, script);
	}
	
	if (!problem)
	{
		// Get display attributes from script
		name = [[[self propertyNamed:@"name"] description] copy];
		if (name == nil)
		{
			name = [[self scriptNameFromPath:path] retain];
			[self setProperty:name named:@"name"];
		}
		
		version = [[[self propertyNamed:@"version"] description] copy];
		description = [[[self propertyNamed:@"description"] description] copy];
		
		OOLog(@"script.javaScript.load.success", @"Loaded JavaScript OXP: %@ -- %@", [self displayName], description ? description : @"(no description)");
	}
	
	if (problem)
	{
		OOLog(@"script.javaScript.load.failed", @"***** Error loading JavaScript script %@ -- %@", path, problem);
		[self release];
		self = nil;
	}

	return self;
}


- (void) dealloc
{
	[name release];
	[description release];
	[version release];
	[weakSelf weakRefDrop];
	JS_RemoveRoot(context, &object);
//	if (scriptObject != NULL)  JS_RemoveRoot(context, &scriptObject);
	
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


- (BOOL)doEvent:(NSString *)eventName withArguments:(NSArray *)arguments
{
	BOOL			OK;
	jsval			value;
	JSFunction		*function;
	uintN			i, argc;
	jsval			*argv = NULL;
	RunningStack	stackElement;
	
	OK = JS_GetProperty(context, object, [eventName cString], &value);
	if (OK && !JSVAL_IS_VOID(value))
	{
		function = JS_ValueToFunction(context, value);
		if (function != NULL)
		{
			// Push self on stack of running scripts
			stackElement.back = sRunningStack;
			stackElement.current = self;
			sRunningStack = &stackElement;
			
			// Convert arguments to JS values and make them temporarily un-garbage-collectable
			argc = [arguments count];
			if (argc != 0)
			{
				argv = malloc(sizeof *argv * argc);
				if (argv != NULL)
				{
					for (i = 0; i != argc; ++i)
					{
						argv[i] = [[arguments objectAtIndex:i] javaScriptValueInContext:context];
						if (JSVAL_IS_GCTHING(argv[i]))  JS_AddNamedRoot(context, &argv[i], "JSScript event parameter");
					}
				}
				else  argc = 0;
			}
			
			// Actually call the function
			OK = JS_CallFunction(context, object, function, argc, argv, &value);
			
			// Re-garbage-collectibalize the arguments and free the array
			if (argv != NULL)
			{
				for (i = 0; i != argc; ++i)
				{
					if (JSVAL_IS_GCTHING(argv[i]))  JS_RemoveRoot(context, &argv[i]);
				}
				free(argv);
			}
			
			// Pop running scripts stack
			sRunningStack = stackElement.back;
			
			JS_ClearNewbornRoots(context);
			
			// FIXME: should probably be JS_MaybeGC(), and moved to a higher level.
			// Here for stress testing of sorts.
			JS_GC(context);
			
			return OK;
		}
	}

	return NO;
}


- (id)propertyNamed:(NSString *)propName
{
	BOOL						OK;
	jsval						value = JSVAL_VOID;
	
	if (propName == nil)  return nil;
	
	OK = JS_GetProperty(context, object, [propName UTF8String], &value);
	if (!OK || JSVAL_IS_VOID(value))  return nil;
	
	return JSValueToObject(context, value);
}


- (BOOL)setProperty:(id)value named:(NSString *)propName
{
	jsval						jsValue;
	
	if (value == nil || propName == nil)  return NO;
	
	jsValue = [value javaScriptValueInContext:context];
	if (!JSVAL_IS_VOID(jsValue))
	{
		return JS_DefineProperty(context, object, [propName UTF8String], jsValue, NULL, NULL, JSPROP_ENUMERATE);
	}
	return NO;
}


- (BOOL)defineProperty:(id)value named:(NSString *)propName
{
	jsval						jsValue;
	
	if (value == nil || propName == nil)  return NO;
	
	jsValue = [value javaScriptValueInContext:context];
	if (!JSVAL_IS_VOID(jsValue))
	{
		return JS_DefineProperty(context, object, [propName UTF8String], jsValue, NULL, NULL, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
	}
	return NO;
}


- (jsval)javaScriptValueInContext:(JSContext *)context
{
	return OBJECT_TO_JSVAL(object);
}


+ (void)pushScript:(OOJSScript *)script
{
	RunningStack			*element = NULL;
	
	if (script == nil)  return;
	
	element = malloc(sizeof *element);
	if (element == NULL)  exit(EXIT_FAILURE);
	
	element->back = sRunningStack;
	element->current = script;
	sRunningStack = element;
}


+ (void)popScript:(OOJSScript *)script
{
	RunningStack			*element = NULL;
	
	if (script == nil)  return;
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
	
	return [theName stringByAppendingString:@".anon-script"];
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


static JSScript *LoadScriptWithName(JSContext *context, NSString *path, JSObject *object, NSString **outErrorMessage)
{
#if OO_CACHE_JS_SCRIPTS
	OOCacheManager				*cache = nil;
#endif
	NSString					*fileContents = nil;
	NSData						*data = nil;
	JSScript					*script = NULL;
	
	assert(outErrorMessage != NULL);
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
