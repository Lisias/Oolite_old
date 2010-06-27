/*

OOJSSound.m

Oolite
Copyright (C) 2004-2010 Giles C Williams and contributors

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

#import "OOJSSound.h"
#import "OOJavaScriptEngine.h"
#import "OOSound.h"
#import "OOMusicController.h"
#import "ResourceManager.h"
#import "Universe.h"


static JSObject *sSoundPrototype;


DEFINE_JS_OBJECT_GETTER(JSSoundGetSound, OOSound)


static OOSound *GetNamedSound(NSString *name);


static JSBool SoundGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);

// Static methods
static JSBool SoundStaticLoad(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SoundStaticPlayMusic(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SoundStaticStopMusic(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


static JSExtendedClass sSoundClass =
{
	{
		"Sound",
		JSCLASS_HAS_PRIVATE | JSCLASS_IS_EXTENDED,
		
		JS_PropertyStub,		// addProperty
		JS_PropertyStub,		// delProperty
		SoundGetProperty,		// getProperty
		JS_PropertyStub,		// setProperty
		JS_EnumerateStub,		// enumerate
		JS_ResolveStub,			// resolve
		JS_ConvertStub,			// convert
		JSObjectWrapperFinalize, // finalize
		JSCLASS_NO_OPTIONAL_MEMBERS
	},
	JSObjectWrapperEquality,	// equality. Relies on the fact that the resource manager will always return the same object for a given sound name.
	NULL,						// outerObject
	NULL,						// innerObject
	JSCLASS_NO_RESERVED_MEMBERS
};


enum
{
	// Property IDs
	kSound_name
};


static JSPropertySpec sSoundProperties[] =
{
	// JS name					ID							flags
	{ "name",					kSound_name,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sSoundMethods[] =
{
	// JS name					Function					min args
	{ "toString",				JSObjectWrapperToString,	0, },
	{ 0 }
};


static JSFunctionSpec sSoundStaticMethods[] =
{
	// JS name					Function					min args
	{ "load",					SoundStaticLoad,			1, },
	{ "playMusic",				SoundStaticPlayMusic,		1, },
	{ "stopMusic",				SoundStaticStopMusic,		0, },
	{ 0 }
};


// *** Public ***

void InitOOJSSound(JSContext *context, JSObject *global)
{
	sSoundPrototype = JS_InitClass(context, global, NULL, &sSoundClass.base, NULL, 0, sSoundProperties, sSoundMethods, NULL, sSoundStaticMethods);
	JSRegisterObjectConverter(&sSoundClass.base, JSBasicPrivateObjectConverter);
}


OOSound *SoundFromJSValue(JSContext *context, jsval value)
{
	OOJS_PROFILE_ENTER
	
	if (JSVAL_IS_STRING(value))
	{
		return GetNamedSound(JSValToNSString(context, value));
	}
	else
	{
		return JSValueToObjectOfClass(context, value, [OOSound class]);
	}
	
	OOJS_PROFILE_EXIT
}


// *** Implementation stuff ***

static JSBool SoundGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	OOJS_NATIVE_ENTER(context)
	
	OOSound						*sound = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (EXPECT_NOT(!JSSoundGetSound(context, this, &sound))) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kSound_name:
			*outValue = [[sound name] javaScriptValueInContext:context];
			break;
		
		default:
			OOReportJSBadPropertySelector(context, @"Sound", JSVAL_TO_INT(name));
			return NO;
	}
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


static OOSound *GetNamedSound(NSString *name)
{
	OOSound						*sound = nil;
	
	if ([name hasPrefix:@"["] && [name hasSuffix:@"["])
	{
		sound = [OOSound soundWithCustomSoundKey:name];
	}
	else
	{
		sound = [ResourceManager ooSoundNamed:name inFolder:@"Sounds"];
	}
	
	return sound;
}


// *** Static methods ***

// load(name : String) : Sound
static JSBool SoundStaticLoad(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString					*name = nil;
	OOSound						*sound = nil;
	
	name = JSValToNSString(context, argv[0]);
	if (name == nil)
	{
		OOReportJSBadArguments(context, @"Sound", @"load", argc, argv, nil, @"string");
		return NO;
	}
	
	OOJSPauseTimeLimiter();
	sound = GetNamedSound(name);
	*outResult = [sound javaScriptValueInContext:context];
	if (*outResult == JSVAL_VOID)  *outResult = JSVAL_NULL;	// No sound by that name
	OOJSResumeTimeLimiter();
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


// playMusic(name : String [, loop : Boolean])
static JSBool SoundStaticPlayMusic(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString					*name = nil;
	JSBool						loop = NO;
	
	name = JSValToNSString(context, argv[0]);
	if (name == nil)
	{
		OOReportJSBadArguments(context, @"Sound", @"playMusic", 1, &argv[0], nil, @"string");
		return NO;
	}
	if (argc >= 2)
	{
		if (!JS_ValueToBoolean(context, argv[1], &loop))
		{
			OOReportJSBadArguments(context, @"Sound", @"playMusic", 1, &argv[1], nil, @"boolean");
			return NO;
		}
	}
	
	OOJSPauseTimeLimiter();
	[[OOMusicController sharedController] playMusicNamed:name loop:loop];
	OOJSResumeTimeLimiter();
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool SoundStaticStopMusic(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString					*name = nil;
	
	OOJSPauseTimeLimiter();
	if (argc > 0)
	{
		name = JSValToNSString(context, argv[0]);
		if (name == nil)
		{
			OOReportJSBadArguments(context, @"Sound", @"stopMusic", argc, argv, nil, @"string or no argument");
			return NO;
		}
		[[OOMusicController sharedController] stopMusicNamed:name];
	}
	else
	{
		[[OOMusicController sharedController] stop];
	}
	OOJSResumeTimeLimiter();
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


@implementation OOSound (OOJavaScriptExtentions)

- (jsval) javaScriptValueInContext:(JSContext *)context
{
	JSObject					*jsSelf = NULL;
	jsval						result = JSVAL_NULL;
	
	jsSelf = JS_NewObject(context, &sSoundClass.base, sSoundPrototype, NULL);
	if (jsSelf != NULL)
	{
		if (!JS_SetPrivate(context, jsSelf, [self retain]))  jsSelf = NULL;
	}
	if (jsSelf != NULL)  result = OBJECT_TO_JSVAL(jsSelf);
	
	return result;
}


- (NSString *) javaScriptDescription
{
	return [NSString stringWithFormat:@"[Sound \"%@\"]", [self name]];
}


- (NSString *) jsClassName
{
	return @"Sound";
}

@end
