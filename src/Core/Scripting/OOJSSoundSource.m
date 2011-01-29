/*

OOJSSoundSource.m

Oolite
Copyright (C) 2004-2011 Giles C Williams and contributors

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
#import "ResourceManager.h"


static JSObject *sSoundSourcePrototype;


static JSBool SoundSourceGetProperty(OOJS_PROP_ARGS);
static JSBool SoundSourceSetProperty(OOJS_PROP_ARGS);
static JSBool SoundSourceConstruct(OOJS_NATIVE_ARGS);

// Methods
static JSBool SoundSourcePlay(OOJS_NATIVE_ARGS);
static JSBool SoundSourceStop(OOJS_NATIVE_ARGS);
static JSBool SoundSourcePlayOrRepeat(OOJS_NATIVE_ARGS);


static JSClass sSoundSourceClass =
{
	"SoundSource",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	SoundSourceGetProperty,	// getProperty
	SoundSourceSetProperty,	// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	OOJSObjectWrapperFinalize, // finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kSoundSource_sound,
	kSoundSource_isPlaying,
	kSoundSource_loop,
	kSoundSource_repeatCount
};


static JSPropertySpec sSoundSourceProperties[] =
{
	// JS name					ID							flags
	{ "sound",					kSoundSource_sound,			OOJS_PROP_READWRITE_CB },
	{ "isPlaying",				kSoundSource_isPlaying,		OOJS_PROP_READONLY_CB },
	{ "loop",					kSoundSource_loop,			OOJS_PROP_READWRITE_CB },
	{ "repeatCount",			kSoundSource_repeatCount,	OOJS_PROP_READWRITE_CB },
	{ 0 }
};


static JSFunctionSpec sSoundSourceMethods[] =
{
	// JS name					Function					min args
	{ "toString",				OOJSObjectWrapperToString,	0, },
	{ "play",					SoundSourcePlay,			0, },
	{ "stop",					SoundSourceStop,			0, },
	{ "playOrRepeat",			SoundSourcePlayOrRepeat,	0, },
	{ 0 }
};


DEFINE_JS_OBJECT_GETTER(JSSoundSourceGetSoundSource, &sSoundSourceClass, sSoundSourcePrototype, OOSoundSource)


// *** Public ***

void InitOOJSSoundSource(JSContext *context, JSObject *global)
{
	sSoundSourcePrototype = JS_InitClass(context, global, NULL, &sSoundSourceClass, SoundSourceConstruct, 0, sSoundSourceProperties, sSoundSourceMethods, NULL, NULL);
	OOJSRegisterObjectConverter(&sSoundSourceClass, OOJSBasicPrivateObjectConverter);
}


static JSBool SoundSourceConstruct(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(!OOJS_IS_CONSTRUCTING))
	{
		OOJSReportError(context, @"SoundSource() cannot be called as a function, it must be used as a constructor (as in new SoundSource()).");
		return NO;
	}
	
	OOJS_RETURN_OBJECT([[[OOSoundSource alloc] init] autorelease]);
	
	OOJS_NATIVE_EXIT
}


// *** Implementation stuff ***

static JSBool SoundSourceGetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOSoundSource				*soundSource = nil;
	
	if (!JSSoundSourceGetSoundSource(context, this, &soundSource)) return NO;
	
	switch (OOJS_PROPID_INT)
	{
		case kSoundSource_sound:
			*value = OOJSValueFromNativeObject(context, [soundSource sound]);
			break;
			
		case kSoundSource_isPlaying:
			*value = OOJSValueFromBOOL([soundSource isPlaying]);
			break;
			
		case kSoundSource_loop:
			*value = OOJSValueFromBOOL([soundSource loop]);
			break;
			
		case kSoundSource_repeatCount:
			*value = INT_TO_JSVAL([soundSource repeatCount]);
			break;
		
		default:
			OOJSReportBadPropertySelector(context, @"SoundSource", OOJS_PROPID_INT);
			return NO;
	}
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool SoundSourceSetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	BOOL						OK = NO;
	OOSoundSource				*soundSource = nil;
	int32						iValue;
	JSBool						bValue;
	
	if (!JSSoundSourceGetSoundSource(context, this, &soundSource)) return NO;
	
	switch (OOJS_PROPID_INT)
	{
		case kSoundSource_sound:
			[soundSource setSound:SoundFromJSValue(context, *value)];
			OK = YES;
			break;
			
		case kSoundSource_loop:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[soundSource setLoop:bValue];
				OK = YES;
			}
			break;
			
		case kSoundSource_repeatCount:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue > 100)  iValue = 100;
				if (100 < 1)  iValue = 1;
				[soundSource setRepeatCount:iValue];
				OK = YES;
			}
			break;
		
		default:
			OOJSReportBadPropertySelector(context, @"SoundSource", OOJS_PROPID_INT);
	}
	
	return OK;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

// play([count : Number])
static JSBool SoundSourcePlay(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	OOSoundSource			*thisv = nil;
	int32					count = 0;
	
	if (EXPECT_NOT(!JSSoundSourceGetSoundSource(context, OOJS_THIS, &thisv)))  return NO;
	if (argc > 0 && !JSVAL_IS_VOID(OOJS_ARG(0)) && !JS_ValueToInt32(context, OOJS_ARG(0), &count))
	{
		OOJSReportBadArguments(context, @"SoundSource", @"play", argc, OOJS_ARGV, nil, @"integer count or no argument");
		return NO;
	}
	
	if (count > 0)
	{
		if (count > 100)  count = 100;
		[thisv setRepeatCount:count];
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	[thisv play];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// stop()
static JSBool SoundSourceStop(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	OOSoundSource			*thisv = nil;
	
	if (EXPECT_NOT(!JSSoundSourceGetSoundSource(context, OOJS_THIS, &thisv)))  return NO;
	
	OOJS_BEGIN_FULL_NATIVE(context)
	[thisv stop];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// playOrRepeat()
static JSBool SoundSourcePlayOrRepeat(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	OOSoundSource			*thisv = nil;
	
	if (EXPECT_NOT(!JSSoundSourceGetSoundSource(context, OOJS_THIS, &thisv)))  return NO;
	
	OOJS_BEGIN_FULL_NATIVE(context)
	[thisv playOrRepeat];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


@implementation OOSoundSource (OOJavaScriptExtentions)

- (jsval) oo_jsValueInContext:(JSContext *)context
{
	JSObject					*jsSelf = NULL;
	jsval						result = JSVAL_NULL;
	
	jsSelf = JS_NewObject(context, &sSoundSourceClass, sSoundSourcePrototype, NULL);
	if (jsSelf != NULL)
	{
		if (!JS_SetPrivate(context, jsSelf, [self retain]))  jsSelf = NULL;
	}
	if (jsSelf != NULL)  result = OBJECT_TO_JSVAL(jsSelf);
	
	return result;
}


- (NSString *) oo_jsClassName
{
	return @"SoundSource";
}

@end
