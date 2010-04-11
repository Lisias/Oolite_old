/*

OOJSConsole.m


Oolite Debug OXP

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

#ifndef OO_EXCLUDE_DEBUG_SUPPORT

#import "OOJSConsole.h"
#import "OODebugMonitor.h"
#import <stdint.h>

#import "OOJavaScriptEngine.h"
#import "OOJSScript.h"
#import "OOJSVector.h"
#import "OOJSEntity.h"
#import "OOJSCall.h"
#import "OOLoggingExtended.h"
#import "OOConstToString.h"
#import "OOOpenGLExtensionManager.h"
#import "OODebugFlags.h"


@interface Entity (OODebugInspector)

// Method added by inspector in Debug OXP under OS X only.
- (void) inspect;

@end


NSString *OOPlatformDescription(void);


static JSObject *sConsolePrototype = NULL;
static JSObject *sConsoleSettingsPrototype = NULL;


static JSBool ConsoleGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool ConsoleSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);
static void ConsoleFinalize(JSContext *context, JSObject *this);

// Methods
static JSBool ConsoleConsoleMessage(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ConsoleClearConsole(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ConsoleScriptStack(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ConsoleInspectEntity(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ConsoleCallObjCMethod(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ConsoleIsExecutableJavaScript(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ConsoleDisplayMessagesInClass(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ConsoleSetDisplayMessagesInClass(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ConsoleWriteLogMarker(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);

static JSBool ConsoleSettingsDeleteProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool ConsoleSettingsGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool ConsoleSettingsSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);


static JSClass sConsoleClass =
{
	"Console",
	JSCLASS_HAS_PRIVATE | JSCLASS_IS_ANONYMOUS,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	ConsoleGetProperty,		// getProperty
	ConsoleSetProperty,		// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	ConsoleFinalize,		// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kConsole_debugFlags,		// debug flags, integer, read/write
	kConsole_shaderMode,		// shader mode, symbolic string, read/write
	kConsole_displayFPS,		// display FPS (and related info), boolean, read/write
	kConsole_glVendorString,	// OpenGL GL_VENDOR string, string, read-only
	kConsole_glRendererString,	// OpenGL GL_RENDERER string, string, read-only
	kConsole_platformDescription, // Information about system we're running on in unspecified format, string, read-only
	
	// Symbolic constants for debug flags:
	kConsole_DEBUG_LINKED_LISTS,
	kConsole_DEBUG_ENTITIES,
	kConsole_DEBUG_COLLISIONS,
	kConsole_DEBUG_DOCKING,
	kConsole_DEBUG_OCTREE,
	kConsole_DEBUG_OCTREE_TEXT,
	kConsole_DEBUG_BOUNDING_BOXES,
	kConsole_DEBUG_OCTREE_DRAW,
	kConsole_DEBUG_DRAW_NORMALS,
	kConsole_DEBUG_NO_DUST,
	kConsole_DEBUG_NO_SHADER_FALLBACK,
	
	kConsole_DEBUG_MISC
};


static JSPropertySpec sConsoleProperties[] =
{
	// JS name					ID							flags
	{ "debugFlags",				kConsole_debugFlags,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "shaderMode",				kConsole_shaderMode,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "displayFPS",				kConsole_displayFPS,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "glVendorString",			kConsole_glVendorString,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "glRendererString",		kConsole_glRendererString,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "platformDescription",	kConsole_platformDescription, JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	
#define DEBUG_FLAG_DECL(x) { #x, kConsole_##x, JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY }
	DEBUG_FLAG_DECL(DEBUG_LINKED_LISTS),
	DEBUG_FLAG_DECL(DEBUG_ENTITIES),
	DEBUG_FLAG_DECL(DEBUG_COLLISIONS),
	DEBUG_FLAG_DECL(DEBUG_DOCKING),
	DEBUG_FLAG_DECL(DEBUG_OCTREE),
	DEBUG_FLAG_DECL(DEBUG_OCTREE_TEXT),
	DEBUG_FLAG_DECL(DEBUG_BOUNDING_BOXES),
	DEBUG_FLAG_DECL(DEBUG_OCTREE_DRAW),
	DEBUG_FLAG_DECL(DEBUG_DRAW_NORMALS),
	DEBUG_FLAG_DECL(DEBUG_NO_DUST),
	DEBUG_FLAG_DECL(DEBUG_NO_SHADER_FALLBACK),
	
	DEBUG_FLAG_DECL(DEBUG_MISC),
#undef DEBUG_FLAG_DECL
	
	{ 0 }
};


static JSFunctionSpec sConsoleMethods[] =
{
	// JS name					Function					min args
	{ "consoleMessage",			ConsoleConsoleMessage,		2 },
	{ "clearConsole",			ConsoleClearConsole,		0 },
	{ "scriptStack",			ConsoleScriptStack,			0 },
	{ "inspectEntity",			ConsoleInspectEntity,		1 },
	{ "__callObjCMethod",		ConsoleCallObjCMethod,		1 },
	{ "isExecutableJavaScript",	ConsoleIsExecutableJavaScript, 2 },
	{ "displayMessagesInClass", ConsoleDisplayMessagesInClass, 1 },
	{ "setDisplayMessagesInClass", ConsoleSetDisplayMessagesInClass, 2 },
	{ "writeLogMarker",			ConsoleWriteLogMarker,		0 },
	{ 0 }
};


static JSClass sConsoleSettingsClass =
{
	"ConsoleSettings",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	ConsoleSettingsDeleteProperty, // delProperty
	ConsoleSettingsGetProperty, // getProperty
	ConsoleSettingsSetProperty, // setProperty
	JS_EnumerateStub,		// enumerate. FIXME: this should work.
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	ConsoleFinalize,		// finalize (same as Console)
	JSCLASS_NO_OPTIONAL_MEMBERS
};


static void InitOOJSConsole(JSContext *context, JSObject *global)
{
	sConsolePrototype = JS_InitClass(context, global, NULL, &sConsoleClass, NULL, 0, sConsoleProperties, sConsoleMethods, NULL, NULL);
	JSRegisterObjectConverter(&sConsoleClass, JSBasicPrivateObjectConverter);
	
	sConsoleSettingsPrototype = JS_InitClass(context, global, NULL, &sConsoleSettingsClass, NULL, 0, NULL, NULL, NULL, NULL);
	JSRegisterObjectConverter(&sConsoleSettingsClass, JSBasicPrivateObjectConverter);
}


JSObject *DebugMonitorToJSConsole(JSContext *context, OODebugMonitor *monitor)
{
	OOJavaScriptEngine		*engine = nil;
	JSObject				*object = NULL;
	JSObject				*settingsObject = NULL;
	jsval					value;
	
	engine = [OOJavaScriptEngine sharedEngine];
	
	if (sConsolePrototype == NULL)
	{
		InitOOJSConsole(context, [engine globalObject]);
	}
	
	// Create Console object
	object = JS_NewObject(context, &sConsoleClass, sConsolePrototype, NULL);
	if (object != NULL)
	{
		if (!JS_SetPrivate(context, object, [monitor weakRetain]))  object = NULL;
	}
	
	if (object != NULL)
	{
		// Create ConsoleSettings object
		settingsObject = JS_NewObject(context, &sConsoleSettingsClass, sConsoleSettingsPrototype, NULL);
		if (settingsObject != NULL)
		{
			if (!JS_SetPrivate(context, settingsObject, [monitor weakRetain]))  settingsObject = NULL;
		}
		if (settingsObject != NULL)
		{
			value = OBJECT_TO_JSVAL(settingsObject);
			if (!JS_SetProperty(context, object, "settings", &value))
			{
				settingsObject = NULL;
			}
		}

		if (settingsObject == NULL)  object = NULL;
	}
	
	return object;
	// Analyzer: object leaked. (x2) [Expected, objects are retained by JS object.]
}


static JSBool ConsoleGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	if (!JSVAL_IS_INT(name))  return YES;
	
	switch (JSVAL_TO_INT(name))
	{
#ifndef NDEBUG
		case kConsole_debugFlags:
			*outValue = INT_TO_JSVAL(gDebugFlags);
			break;
#endif		
			
		case kConsole_shaderMode:
			*outValue = [ShaderSettingToString([UNIVERSE shaderEffectsLevel]) javaScriptValueInContext:context];
			break;
			
		case kConsole_displayFPS:
			*outValue = BOOLToJSVal([UNIVERSE displayFPS]);
			break;
			
		case kConsole_glVendorString:
			*outValue = [[[OOOpenGLExtensionManager sharedManager] vendorString] javaScriptValueInContext:context];
			break;
			
		case kConsole_glRendererString:
			*outValue = [[[OOOpenGLExtensionManager sharedManager] rendererString] javaScriptValueInContext:context];
			break;
			
		case kConsole_platformDescription:
			*outValue = [OOPlatformDescription() javaScriptValueInContext:context];
			break;
			
#define DEBUG_FLAG_CASE(x) case kConsole_##x: *outValue = INT_TO_JSVAL(x); break;
		DEBUG_FLAG_CASE(DEBUG_LINKED_LISTS);
		DEBUG_FLAG_CASE(DEBUG_ENTITIES);
		DEBUG_FLAG_CASE(DEBUG_COLLISIONS);
		DEBUG_FLAG_CASE(DEBUG_DOCKING);
		DEBUG_FLAG_CASE(DEBUG_OCTREE);
		DEBUG_FLAG_CASE(DEBUG_OCTREE_TEXT);
		DEBUG_FLAG_CASE(DEBUG_BOUNDING_BOXES);
		DEBUG_FLAG_CASE(DEBUG_OCTREE_DRAW);
		DEBUG_FLAG_CASE(DEBUG_DRAW_NORMALS);
		DEBUG_FLAG_CASE(DEBUG_NO_DUST);
		DEBUG_FLAG_CASE(DEBUG_NO_SHADER_FALLBACK);
		
		DEBUG_FLAG_CASE(DEBUG_MISC);
#undef DEBUG_FLAG_CASE
			
		default:
			OOReportJSBadPropertySelector(context, @"Console", JSVAL_TO_INT(name));
			return NO;
	}
	
	return YES;
}


static JSBool ConsoleSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	int32						iValue;
	NSString					*sValue = nil;
	JSBool						bValue = NO;
	
	if (!JSVAL_IS_INT(name))  return YES;
	
	switch (JSVAL_TO_INT(name))
	{
#ifndef NDEBUG
		case kConsole_debugFlags:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				gDebugFlags = iValue;
			}
			break;
#endif		
		case kConsole_shaderMode:
			sValue = JSValToNSString(context, *value);
			if (sValue != nil)
			{
				OOShaderSetting setting = StringToShaderSetting(sValue);
				[UNIVERSE setShaderEffectsLevel:setting];
			}
			break;
			
		case kConsole_displayFPS:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[UNIVERSE setDisplayFPS:bValue];
			}
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"Console", JSVAL_TO_INT(name));
			return NO;
	}
	
	return YES;
}


static BOOL DoWeDefineAllDebugFlags(enum OODebugFlags flags)  GCC_ATTR((unused));
static BOOL DoWeDefineAllDebugFlags(enum OODebugFlags flags)
{
	/*	This function doesn't do anything, but will generate a warning
		(Enumeration value 'DEBUG_FOO' not handled in switch) if a debug flag
		is added without updating it. The point is that if you get such a
		warning, you should first add a JS symbolic constant for the flag,
		then add it to the switch to supress the warning.
		NOTE: don't add a default: to this switch, or I will have to hurt you.
		-- Ahruman 2010-04-11
	*/
	switch (flags)
	{
		case DEBUG_LINKED_LISTS:
		case DEBUG_ENTITIES:
		case DEBUG_COLLISIONS:
		case DEBUG_DOCKING:
		case DEBUG_OCTREE:
		case DEBUG_OCTREE_TEXT:
		case DEBUG_BOUNDING_BOXES:
		case DEBUG_OCTREE_DRAW:
		case DEBUG_DRAW_NORMALS:
		case DEBUG_NO_DUST:
		case DEBUG_NO_SHADER_FALLBACK:
		
		case DEBUG_MISC:
			return YES;
	}
	
	return NO;
}


static void ConsoleFinalize(JSContext *context, JSObject *this)
{
	[(id)JS_GetPrivate(context, this) release];
	JS_SetPrivate(context, this, nil);
}


static JSBool ConsoleSettingsDeleteProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	NSString			*key = nil;
	id					monitor = nil;
	
	if (!JSVAL_IS_STRING(name))  return NO;
	
	key = [NSString stringWithJavaScriptValue:name inContext:context];
	
	monitor = JSObjectToObject(context, this);
	if (![monitor isKindOfClass:[OODebugMonitor class]])
	{
		OOReportJSError(context, @"Expected OODebugMonitor, got %@ in %s. %@", [monitor class], __PRETTY_FUNCTION__, @"This is an internal error, please report it.");
		return NO;
	}
	
	[monitor setConfigurationValue:nil forKey:key];
	*outValue = JSVAL_TRUE;
	return YES;
}


static JSBool ConsoleSettingsGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	NSString			*key = nil;
	id					value = nil;
	id					monitor = nil;
	
	if (!JSVAL_IS_STRING(name))  return YES;
	key = [NSString stringWithJavaScriptValue:name inContext:context];
	
	monitor = JSObjectToObject(context, this);
	if (![monitor isKindOfClass:[OODebugMonitor class]])
	{
		OOReportJSError(context, @"Expected OODebugMonitor, got %@ in %s. %@", [monitor class], __PRETTY_FUNCTION__, @"This is an internal error, please report it.");
		return NO;
	}
	
	value = [monitor configurationValueForKey:key];
	*outValue = [value javaScriptValueInContext:context];
	
	return YES;
}


static JSBool ConsoleSettingsSetProperty(JSContext *context, JSObject *this, jsval name, jsval *inValue)
{
	NSString			*key = nil;
	id					value = nil;
	id					monitor = nil;
	
	if (!JSVAL_IS_STRING(name))  return YES;
	key = [NSString stringWithJavaScriptValue:name inContext:context];
	
	monitor = JSObjectToObject(context, this);
	if (![monitor isKindOfClass:[OODebugMonitor class]])
	{
		OOReportJSError(context, @"Expected OODebugMonitor, got %@ in %s. %@", [monitor class], __PRETTY_FUNCTION__, @"This is an internal error, please report it.");
		return NO;
	}
	
	if (JSVAL_IS_NULL(*inValue) || JSVAL_IS_VOID(*inValue))
	{
		[monitor setConfigurationValue:nil forKey:key];
	}
	else
	{
		value = JSValueToObject(context, *inValue);
		if (value != nil)
		{
			[monitor setConfigurationValue:value forKey:key];
		}
		else
		{
			OOReportJSWarning(context, @"debugConsole.settings: could not convert %@ to native object.", [NSString stringWithJavaScriptValue:*inValue inContext:context]);
		}
	}
	
	return YES;
}


// *** Methods ***

// function consoleMessage(colorCode : String, message : String [, emphasisStart : Number, emphasisLength : Number]) : void
static JSBool ConsoleConsoleMessage(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	id					monitor = nil;
	NSString			*colorKey = nil,
						*message = nil;
	NSRange				emphasisRange = {0, 0};
	jsdouble			location, length;
	
	monitor = JSObjectToObject(context, this);
	if (![monitor isKindOfClass:[OODebugMonitor class]])
	{
		OOReportJSError(context, @"Expected OODebugMonitor, got %@ in %s. %@", [monitor class], __PRETTY_FUNCTION__, @"This is an internal error, please report it.");
		return NO;
	}
	
	colorKey = JSValToNSString(context,argv[0]);
	message = JSValToNSString(context,argv[1]);
	
	if (4 <= argc)
	{
		// Attempt to get two numbers, specifying an emphasis range.
		if (JS_ValueToNumber(context, argv[2], &location) &&
			JS_ValueToNumber(context, argv[3], &length))
		{
			emphasisRange = NSMakeRange(location, length);
		}
	}
	
	if (message == nil)
	{
		if (colorKey == nil)
		{
			OOReportJSWarning(context, @"Console.consoleMessage() called with no parameters.");
		}
		else
		{
			message = colorKey;
			colorKey = @"command-result";
		}
	}
	
	if (message != nil)
	{
		[monitor appendJSConsoleLine:message
							colorKey:colorKey
					   emphasisRange:emphasisRange];
	}
	
	return YES;
}


// function clearConsole() : void
static JSBool ConsoleClearConsole(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	id					monitor = nil;
	
	monitor = JSObjectToObject(context, this);
	if (![monitor isKindOfClass:[OODebugMonitor class]])
	{
		OOReportJSError(context, @"Expected OODebugMonitor, got %@ in %s. %@", [monitor class], __PRETTY_FUNCTION__, @"This is an internal error, please report it.");
		return NO;
	}
	
	[monitor clearJSConsole];
	return YES;
}


// function scriptStack() : Array
static JSBool ConsoleScriptStack(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSArray				*result = nil;
	
	result = [OOJSScript scriptStack];
	*outResult = [result javaScriptValueInContext:context];
	return YES;
}


// function inspectEntity(entity : Entity) : void
static JSBool ConsoleInspectEntity(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Entity				*entity = nil;
	
	if (JSValueToEntity(context, argv[0], &entity))
	{
		if ([entity respondsToSelector:@selector(inspect)])
		{
			[entity inspect];
		}
	}
	
	return YES;
}


// function __callObjCMethod(selector : String [, ...]) : Object
static JSBool ConsoleCallObjCMethod(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	id						object = nil;
	
	object = JSObjectToObject(context, this);
	if (object == nil)
	{
		OOReportJSError(context, @"Attempt to call __callObjCMethod() for non-Objective-C object %@.", [NSString stringWithJavaScriptValue:OBJECT_TO_JSVAL(this) inContext:context]);
		return NO;
	}
	
	return OOJSCallObjCObjectMethod(context, object, [object jsClassName], argc, argv, outResult);
}


// function isExecutableJavaScript(this : Object, string : String) : Boolean
static JSBool ConsoleIsExecutableJavaScript(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	JSObject				*target = NULL;
	JSString				*string = NULL;
	
	*outResult = JSVAL_FALSE;
	if (argc < 2)  return YES;
	if (!JS_ValueToObject(context, argv[0], &target) || !JSVAL_IS_STRING(argv[1]))  return YES;	// Fail silently
	string = JSVAL_TO_STRING(argv[1]);
	
	*outResult = BOOLEAN_TO_JSVAL(JS_BufferIsCompilableUnit(context, target, JS_GetStringBytes(string), JS_GetStringLength(string)));
	return YES;
}


// function displayMessagesInClass(class : String) : Boolean
static JSBool ConsoleDisplayMessagesInClass(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString				*messageClass = nil;
	
	messageClass = [NSString stringWithJavaScriptValue:argv[0] inContext:context];
	*outResult = BOOLEAN_TO_JSVAL(OOLogWillDisplayMessagesInClass(messageClass));
	
	return YES;
}


// function setDisplayMessagesInClass(class : String, flag : Boolean) : void
static JSBool ConsoleSetDisplayMessagesInClass(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString				*messageClass = nil;
	JSBool					flag;
	
	messageClass = JSValToNSString(context, argv[0]);
	if (messageClass != nil && JS_ValueToBoolean(context, argv[1], &flag))
	{
		OOLogSetDisplayMessagesInClass(messageClass, flag);
	}
	
	return YES;
}


// function writeLogMarker() : void
static JSBool ConsoleWriteLogMarker(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOLogInsertMarker();
	return YES;
}

#endif /* OO_EXCLUDE_DEBUG_SUPPORT */
