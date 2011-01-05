/*

OOJSGlobal.m


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

#import "OOJSGlobal.h"
#import "OOJavaScriptEngine.h"

#import "OOJSPlayer.h"
#import "PlayerEntityScriptMethods.h"
#import "OOStringParsing.h"
#import "OOConstToString.h"
#import "OOCollectionExtractors.h"
#import "OOTexture.h"
#import "GuiDisplayGen.h"
#import "MyOpenGLView.h"

#import "NSFileManagerOOExtensions.h"


#if OOJSENGINE_MONITOR_SUPPORT

@interface OOJavaScriptEngine (OOMonitorSupportInternal)

- (void)sendMonitorLogMessage:(NSString *)message
			 withMessageClass:(NSString *)messageClass
					inContext:(JSContext *)context;

@end

#endif


extern NSString * const kOOLogDebugMessage;


static JSBool GlobalGetProperty(OOJS_PROP_ARGS);
static JSBool GlobalSetProperty(OOJS_PROP_ARGS);

static JSBool GlobalLog(OOJS_NATIVE_ARGS);
static JSBool GlobalExpandDescription(OOJS_NATIVE_ARGS);
static JSBool GlobalExpandMissionText(OOJS_NATIVE_ARGS);
static JSBool GlobalDisplayNameForCommodity(OOJS_NATIVE_ARGS);
static JSBool GlobalRandomName(OOJS_NATIVE_ARGS);
static JSBool GlobalRandomInhabitantsDescription(OOJS_NATIVE_ARGS);
static JSBool GlobalSetScreenBackground(OOJS_NATIVE_ARGS);
static JSBool GlobalSetScreenOverlay(OOJS_NATIVE_ARGS);

#ifndef NDEBUG
static JSBool GlobalTakeSnapShot(OOJS_NATIVE_ARGS);
#endif


static JSClass sGlobalClass =
{
	"Global",
	JSCLASS_GLOBAL_FLAGS,
	
	JS_PropertyStub,
	JS_PropertyStub,
	GlobalGetProperty,
	GlobalSetProperty,
	JS_EnumerateStub,
	JS_ResolveStub,
	JS_ConvertStub,
	JS_FinalizeStub
};


enum
{
	// Property IDs
	kGlobal_galaxyNumber,		// galaxy number, integer, read-only
	kGlobal_global,				// global.global.global.global, integer, read-only
	kGlobal_guiScreen,			// current GUI screen, string, read-only
	kGlobal_timeAccelerationFactor	// time acceleration, float, read/write
};


static JSPropertySpec sGlobalProperties[] =
{
	// JS name					ID							flags
	{ "galaxyNumber",			kGlobal_galaxyNumber,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "guiScreen",				kGlobal_guiScreen,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "timeAccelerationFactor",	kGlobal_timeAccelerationFactor,	JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ 0 }
};


static JSFunctionSpec sGlobalMethods[] =
{
	// JS name							Function								min args
	{ "log",							GlobalLog,							1 },
	{ "expandDescription",				GlobalExpandDescription,			1 },
	{ "expandMissionText",				GlobalExpandMissionText,			1 },
	{ "displayNameForCommodity",		GlobalDisplayNameForCommodity,		1 },
	{ "randomName",						GlobalRandomName,					0 },
	{ "randomInhabitantsDescription",	GlobalRandomInhabitantsDescription,	1 },
	{ "setScreenBackground",			GlobalSetScreenBackground,			1 },
	{ "setScreenOverlay",				GlobalSetScreenOverlay,				1 },
#ifndef NDEBUG
	{ "takeSnapShot",					GlobalTakeSnapShot,					1 },
#endif
	{ 0 }
};


void CreateOOJSGlobal(JSContext *context, JSObject **outGlobal)
{
	assert(outGlobal != NULL);
	
#if OO_NEW_JS
	*outGlobal = JS_NewCompartmentAndGlobalObject(context, &sGlobalClass, NULL);
#else
	*outGlobal = JS_NewObject(context, &sGlobalClass, NULL, NULL);
#endif
	JS_SetGlobalObject(context, *outGlobal);
	JS_DefineProperty(context, *outGlobal, "global", OBJECT_TO_JSVAL(*outGlobal), NULL, NULL, JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY);
}


void SetUpOOJSGlobal(JSContext *context, JSObject *global)
{
	JS_DefineProperties(context, global, sGlobalProperties);
	JS_DefineFunctions(context, global, sGlobalMethods);
}


static JSBool GlobalGetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*player = OOPlayerForScripting();
	id							result = nil;
	
	switch (OOJS_PROPID_INT)
	{
		case kGlobal_galaxyNumber:
			*value = INT_TO_JSVAL([player currentGalaxyID]);
			break;
			
		case kGlobal_guiScreen:
			result = [player gui_screen_string];
			break;
			
		case kGlobal_timeAccelerationFactor:
			JS_NewDoubleValue(context, [UNIVERSE timeAccelerationFactor], value);
			break;
			
		default:
			OOJSReportBadPropertySelector(context, @"Global", OOJS_PROPID_INT);
			return NO;
	}
	
	if (result != nil)  *value = [result oo_jsValueInContext:context];
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool GlobalSetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	BOOL						OK = NO;
	jsdouble					fValue;
	
	switch (OOJS_PROPID_INT)
	{
		case kGlobal_timeAccelerationFactor:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[UNIVERSE setTimeAccelerationFactor:fValue];
				OK = YES;
			}
			break;
	
		default:
			OOJSReportBadPropertySelector(context, @"Global", OOJS_PROPID_INT);
	}
	
	return OK;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

// log([messageClass : String,] message : string, ...)
static JSBool GlobalLog(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*message = nil;
	NSString			*messageClass = nil;
	
	if (argc < 2)
	{
		messageClass = kOOLogDebugMessage;
		message = OOStringFromJSValue(context, OOJS_ARG(0));
	}
	else
	{
		messageClass = OOStringFromJSValue(context, OOJS_ARG(0));
		message = [NSString concatenationOfStringsFromJavaScriptValues:OOJS_ARGV + 1 count:argc - 1 separator:@", " inContext:context];
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	OOLog(messageClass, @"%@", message);
	
#if OOJSENGINE_MONITOR_SUPPORT
	[[OOJavaScriptEngine sharedEngine] sendMonitorLogMessage:message
											withMessageClass:nil
												   inContext:context];
#endif
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// expandDescription(description : String [, overrides : object (dictionary)]) : String
static JSBool GlobalExpandDescription(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*string = nil;
	NSDictionary		*overrides = nil;
	
	string = OOStringFromJSValue(context, OOJS_ARG(0));
	if (string == nil)
	{
		OOJSReportBadArguments(context, nil, @"expandDescription", argc, OOJS_ARGV, nil, @"string");
		return NO;
	}
	if (argc > 1)
	{
		overrides = OOJSDictionaryFromStringTable(context, OOJS_ARG(1));
	}
	
	string = ExpandDescriptionsWithOptions(string, [PLAYER system_seed], overrides, nil, nil);
	OOJS_RETURN_OBJECT(string);
	
	OOJS_NATIVE_EXIT
}


// expandMissionText(textKey : String [, overrides : object (dictionary)]) : String
static JSBool GlobalExpandMissionText(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*string = nil;
	NSMutableString		*mString = nil;
	NSDictionary		*overrides = nil;
	
	string = OOStringFromJSValue(context, OOJS_ARG(0));
	if (string == nil)
	{
		OOJSReportBadArguments(context, nil, @"expandMissionText", argc, OOJS_ARGV, nil, @"string");
		return NO;
	}
	if (argc > 1)
	{
		overrides = OOJSDictionaryFromStringTable(context, OOJS_ARG(1));
	}
	
	string = [[UNIVERSE missiontext] oo_stringForKey:string];
	if (string != nil)
	{
		string = ExpandDescriptionsWithOptions(string, [PLAYER system_seed], overrides, nil, nil);
		mString = [NSMutableString stringWithString:string];
		[mString replaceOccurrencesOfString:@"\\n" withString:@"\n" options:0 range:(NSRange){ 0, [mString length] }];
		string = mString;
	}
	
	OOJS_RETURN_OBJECT(string);
	
	OOJS_NATIVE_EXIT
}


// displayNameForCommodity(commodityName : String) : String
static JSBool GlobalDisplayNameForCommodity(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*string = nil;
	
	string = OOStringFromJSValue(context,OOJS_ARG(0));
	if (string == nil)
	{
		OOJSReportBadArguments(context, nil, @"displayNameForCommodity", argc, OOJS_ARGV, nil, @"string");
		return NO;
	}
	string = CommodityDisplayNameForSymbolicName(string);
	OOJS_RETURN_OBJECT(string);
	
	OOJS_NATIVE_EXIT
}


// randomName() : String
static JSBool GlobalRandomName(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*string = nil;
	
	string = RandomDigrams();
	OOJS_RETURN_OBJECT(string);
	
	OOJS_NATIVE_EXIT
}


// randomInhabitantsDescription() : String
static JSBool GlobalRandomInhabitantsDescription(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*string = nil;
	Random_Seed			aSeed;
	JSBool				isPlural = YES;
	
	if (!JS_ValueToBoolean(context, OOJS_ARG(0), &isPlural))  isPlural = NO;
	
	make_pseudo_random_seed(&aSeed);
	string = [UNIVERSE generateSystemInhabitants:aSeed plural:isPlural];
	OOJS_RETURN_OBJECT(string);
	
	OOJS_NATIVE_EXIT
}


// setScreenBackground(name : String) : Boolean
static JSBool GlobalSetScreenBackground(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString 		*value = OOStringFromJSValue(context, OOJS_ARG(0));
	PlayerEntity	*player = OOPlayerForScripting();
	BOOL			result = NO;
	
	if ([UNIVERSE viewDirection] == VIEW_GUI_DISPLAY)
	{
		result = [[UNIVERSE gui] setBackgroundTextureName:value];
		// add some permanence to the override if we're in the equip ship screen
		if (result && [player guiScreen] == GUI_SCREEN_EQUIP_SHIP)  [player setTempBackground:value];
	}
	
	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}


// setScreenOverlay(name : String) : Boolean
static JSBool GlobalSetScreenOverlay(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	BOOL			result = NO;
	NSString 		*value = OOStringFromJSValue(context, OOJS_ARG(0));
	
	if ([UNIVERSE viewDirection] == VIEW_GUI_DISPLAY)
	{
		result = [[UNIVERSE gui] setForegroundTextureName:value];
	}
	
	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}


#ifndef NDEBUG
// takeSnapShot([name : alphanumeric String]) : Boolean
static JSBool GlobalTakeSnapShot(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString				*value = nil;
	NSMutableCharacterSet	*allowedChars = (NSMutableCharacterSet *)[NSMutableCharacterSet alphanumericCharacterSet];
	
	[allowedChars addCharactersInString:@"_-"];
	
	if (argc > 0)
	{
		value = OOStringFromJSValue(context, OOJS_ARG(0));
		if (EXPECT_NOT(value == nil || [value rangeOfCharacterFromSet:[allowedChars invertedSet]].location != NSNotFound))
		{
			OOJSReportBadArguments(context, nil, @"takeSnapShot", argc, OOJS_ARGV, nil, @"alphanumeric string");
			return NO;
		}
	}
	
	NSString				*playerFileDirectory = [[NSFileManager defaultManager] defaultCommanderPath];
	// OOLITE_LEOPARD is true for mac osx >= 10.5, this method should work in both gnustep & osx < 10.5
#if !OOLITE_LEOPARD
	NSDictionary			*attr = [[NSFileManager defaultManager] fileSystemAttributesAtPath:playerFileDirectory];
#else
	// this method should work for osx >= 10.5 (the method above is deprecated in 10.5)
	NSError					*error = nil;
	NSDictionary			*attr = [[NSFileManager defaultManager] attributesOfFileSystemForPath:playerFileDirectory error:&error];
	if (!error)
#endif
	{
		double freeSpace = [attr oo_doubleForKey:NSFileSystemFreeSize];
		if (freeSpace < 1073741824) // less than 1 GB free on disk?
		{
			OOJSReportWarning(context, @"takeSnapShot: function disabled when free disk space is less than 1GB.");
			OOJS_RETURN_BOOL(NO);
		}
	}
	
	
	OOJS_RETURN_BOOL([[UNIVERSE gameView] snapShot:value]);
	
	OOJS_NATIVE_EXIT
}
#endif
