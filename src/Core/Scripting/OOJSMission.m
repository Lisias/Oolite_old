/*

OOJSMission.m


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

#import "OOJSMission.h"
#import "OOJavaScriptEngine.h"
#import "OOJSScript.h"

#import "OOJSPlayer.h"
#import "PlayerEntityScriptMethods.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"


static JSBool MissionSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);

static JSBool MissionMarkSystem(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionUnmarkSystem(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionAddMessageText(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionSetMusic(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionSetInstructions(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionSetInstructionsKey(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionRunScreen(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);

//  Mission screen  callback varibables
static jsval			sCallbackFunction = JSVAL_NULL;
static jsval			sCallbackThis = JSVAL_NULL;
static OOJSScript		*sCallbackScript = nil;

static JSClass sMissionClass =
{
	"Mission",
	0,
	
	JS_PropertyStub,
	JS_PropertyStub,
	JS_PropertyStub,
	MissionSetProperty,
	JS_EnumerateStub,
	JS_ResolveStub,
	JS_ConvertStub,
	JS_FinalizeStub
};


enum
{
	// Property IDs
	kMission_title,				// title of mission screen, string.
	kMission_foreground,		// missionforeground image, string.
	kMission_background,		// mission background image, string.
	kMission_3DModel,			// mission 3D model: role, string.
};


static JSFunctionSpec sMissionMethods[] =
{
	// JS name					Function					min args
	{ "markSystem",				MissionMarkSystem,			1 },
	{ "unmarkSystem",			MissionUnmarkSystem,		1 },
	{ "addMessageText",			MissionAddMessageText,		1 },
	{ "setInstructions",		MissionSetInstructions,		1 },
	{ "setInstructionsKey",		MissionSetInstructionsKey,	1 },
	{ "runScreen",				MissionRunScreen,			0 },
	{ 0 }
};


void InitOOJSMission(JSContext *context, JSObject *global)
{
	JSObject *missionPrototype = JS_InitClass(context, global, NULL, &sMissionClass, NULL, 0, NULL, sMissionMethods, NULL, NULL);
	JS_DefineObject(context, global, "mission", &sMissionClass, missionPrototype, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
	
	// Ensure JS objects are rooted.
	OO_AddJSGCRoot(context, &sCallbackFunction, "Pending mission callback function");
	OO_AddJSGCRoot(context, &sCallbackThis, "Pending mission callback this");
}


void MissionRunCallback()
{
	// don't do anything if we don't have a function.
	if(JSVAL_IS_NULL(sCallbackFunction))  return;
	
	jsval				argval = JSVAL_VOID;
	jsval				rval = JSVAL_VOID;
	PlayerEntity		*player = OOPlayerForScripting();
	OOJavaScriptEngine	*engine  = [OOJavaScriptEngine sharedEngine];
	JSContext			*context = [engine acquireContext];
	
	/*	Create temporarily-rooted local copies of sCallbackFunction and
		sCallbackThis, then clear the statics. This must be done in advance
		since the callback might call runScreen() and clobber the statics.
	*/
	jsval				cbFunction = JSVAL_VOID;
	JSObject			*cbThis = NULL;
	OOJSScript			*cbScript = sCallbackScript;
	
	OO_AddJSGCRoot(context, &cbFunction, "Mission callback function");
	OO_AddJSGCRoot(context, &cbThis, "Mission callback this");
	cbFunction = sCallbackFunction;
	cbScript = sCallbackScript;
	JS_ValueToObject(context, sCallbackThis, &cbThis);
	
	sCallbackScript = nil;
	sCallbackFunction = JSVAL_VOID;
	sCallbackThis = JSVAL_VOID;
	
	argval = [[player missionChoice_string] javaScriptValueInContext:context];
	// now reset the mission choice silently, before calling the callback script.
	[player setMissionChoice:nil withEvent:NO];
	
	// Call the callback.
	NS_DURING
		[OOJSScript pushScript:cbScript];
		[engine callJSFunction:cbFunction
					 forObject:cbThis
						  argc:1
						  argv:&argval
						result:&rval];
	NS_HANDLER
		// Squash any exception, allow cleanup to happen and so forth.
		OOLog(kOOLogException, @"Ignoring exception %@:%@ during handling of mission screen completion callback.", [localException name], [localException reason]);
	NS_ENDHANDLER
	[OOJSScript popScript:cbScript];
	
	// Manage that memory.
	[engine releaseContext:context];
	[cbScript release];
	JS_RemoveRoot(context, &cbFunction);
	JS_RemoveRoot(context, &cbThis);
}


static JSBool MissionSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	PlayerEntity				*player = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	
	player = OOPlayerForScripting();
	
	switch (JSVAL_TO_INT(name))
	{
		case kMission_title:
			[player setMissionTitle:JSValToNSString(context,*value)];
			break;
		
		case kMission_foreground:
			// If value can't be converted to a string this will clear the foreground image.
			[player setMissionImage:JSValToNSString(context,*value)];
			break;
		
		case kMission_3DModel:
			// If value can't be converted to a string this will clear the (entity/ship) model.
			if([player status] == STATUS_IN_FLIGHT && JSVAL_IS_STRING(*value)) OOReportJSWarning(context, @"Mission.runScreen: model will not be displayed while in flight.");
			[player showShipModel:JSValToNSString(context, *value)];
			break;
		
		case kMission_background:
			// If value can't be converted to a string this will clear the background image.
			[player setMissionBackground:JSValToNSString(context,*value)];
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"Mission", JSVAL_TO_INT(name));
			return NO;
	}
	
	return YES;
}


// *** Methods ***

// markSystem(systemCoords : String)
static JSBool MissionMarkSystem(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*params = nil;
	
	params = [NSString concatenationOfStringsFromJavaScriptValues:argv count:argc separator:@" " inContext:context];
	[player addMissionDestination:params];
	
	return YES;
}


// unmarkSystem(systemCoords : String)
static JSBool MissionUnmarkSystem(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*params = nil;
	
	params = [NSString concatenationOfStringsFromJavaScriptValues:argv count:argc separator:@" " inContext:context];
	[player removeMissionDestination:params];
	
	return YES;
}


// addMessageText(text : String)
static JSBool MissionAddMessageText(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*text = nil;
	
	text = JSValToNSString(context,argv[0]);
	[player addLiteralMissionText:text];
	
	return YES;
}


// setMusic(musicName : String)
static JSBool MissionSetMusic(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*key = nil;
	
	key =  JSValToNSString(context,argv[0]);
	[player setMissionMusic:key];
	
	return YES;
}


// setChoicesKey(choicesKey : String)
static JSBool MissionSetChoicesKey(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*key = nil;
	
	key = JSValToNSString(context,argv[0]);
	[player setMissionChoices:key];
	
	return YES;
}


// setInstructionsKey(instructionsKey: String [, missionKey : String])
static JSBool MissionSetInstructionsKey(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	*outResult = [@"textKey" javaScriptValueInContext:context];
	return MissionSetInstructions(context, this, argc, argv, outResult);
}


// setInstructions(instructions: String [, missionKey : String])
static JSBool MissionSetInstructions(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*text = nil;
	NSString			*missionKey = nil;
	
	text = JSValToNSString(context,argv[0]);
	if ([text isKindOfClass:[NSNull class]])  text = nil;
	
	if (argc > 1)
	{
		missionKey = [NSString stringWithJavaScriptValue:argv[1] inContext:context];
	}
	else
	{
		missionKey = [[OOJSScript currentlyRunningScript] name];
	}
	
	if (text != nil)
	{
		if ([@"textKey" isEqualTo:JSValToNSString(context,*outResult)])
			[player setMissionDescription:text forMission:missionKey];
		else
			[player setMissionInstructions:text forMission:missionKey];
	}
	else
	{
		[player clearMissionDescriptionForMission:missionKey];
	}
	
	*outResult = JSVAL_VOID;	
	return YES;
}


// runScreen(params: dict, callBack:function) - if the callback function is null, emulate the old style runMissionScreen
static JSBool MissionRunScreen(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	jsval				function = JSVAL_NULL;
	jsval				value = JSVAL_NULL;
	jsval				noWarning = [@"noWarning" javaScriptValueInContext:context];
	JSObject			*params = JS_NewObject(context, NULL, NULL, NULL);
	
	if ([player guiScreen] == GUI_SCREEN_INTRO1 || [player guiScreen] == GUI_SCREEN_INTRO2)
	{
		*outResult = JSVAL_FALSE;
		return YES;
	}
	
	if (argc>0) {
		if (!JSVAL_IS_NULL(argv[0]) && !JSVAL_IS_OBJECT(argv[0]))
		{
			OOReportJSWarning(context, @"Mission.runScreen: expected %@ instead of '%@'.", @"object", [NSString stringWithJavaScriptValue:argv[0] inContext:context]);
			*outResult = JSVAL_FALSE;
			return YES;
		}
		
		if (!JSVAL_IS_NULL(argv[0]) && JSVAL_IS_OBJECT(argv[0])) params = JSVAL_TO_OBJECT(argv[0]);
	}
	
	if (argc > 1) function = argv[1];
	if (!JSVAL_IS_OBJECT(function) || (!JSVAL_IS_NULL(function) && !JS_ObjectIsFunction(context, JSVAL_TO_OBJECT(function))))
	{
		OOReportJSWarning(context, @"Mission.runScreen: expected %@ instead of '%@'.", @"function", [NSString stringWithJavaScriptValue:argv[1] inContext:context]);
		*outResult = JSVAL_FALSE;
		return YES;
	}
	
	if (function != JSVAL_NULL)
	{
		sCallbackScript = [[[OOJSScript currentlyRunningScript] weakRefUnderlyingObject] retain];
		if (argc > 2)
		{
			sCallbackThis = argv[2];
		}
		else
		{
			sCallbackThis = [sCallbackScript javaScriptValueInContext:context];
		}
	}
	
	if (JS_GetProperty(context, params, "title", &value) && !JSVAL_IS_NULL(value) && !JSVAL_IS_VOID(value))
	{
		MissionSetProperty(context, this, INT_TO_JSVAL(kMission_title), &value);
	}
	else
	{
		if (JS_GetProperty(context, params, "titleKey", &value) && !JSVAL_IS_NULL(value) && !JSVAL_IS_VOID(value))
		{
			NSString *titleKey = [[UNIVERSE missiontext] oo_stringForKey:JSValToNSString(context, value)];
			titleKey = ExpandDescriptionForCurrentSystem(titleKey);
			titleKey = [player replaceVariablesInString:titleKey];
			[player setMissionTitle:titleKey];
		}
	}
	
	if (JS_GetProperty(context, params, "music", &value))
		MissionSetMusic(context, this, 1, &value, &noWarning);
	
	// Make sure the overlay is not set! (could be set as legacy script's 'background')
	value = JSVAL_NULL;
	MissionSetProperty(context, this, INT_TO_JSVAL(kMission_foreground), &value);
	
	if (JS_GetProperty(context, params, "overlay", &value))
		MissionSetProperty(context, this, INT_TO_JSVAL(kMission_foreground), &value);
	
	if (JS_GetProperty(context, params, "model", &value))
		MissionSetProperty(context, this, INT_TO_JSVAL(kMission_3DModel), &value);
	
	if (JS_GetProperty(context, params, "background", &value))
		MissionSetProperty(context, this, INT_TO_JSVAL(kMission_background), &value);
	
	sCallbackFunction = function;
	[player setGuiToMissionScreenWithCallback:!JSVAL_IS_NULL(sCallbackFunction)];
		
	if (JS_GetProperty(context, params, "message", &value) && !JSVAL_IS_NULL(value) && !JSVAL_IS_VOID(value))
		[player addLiteralMissionText: JSValToNSString(context, value)];
	else
	{
		if (JS_GetProperty(context, params, "messageKey", &value))
			[player addMissionText: JSValToNSString(context, value)];
	}
	
	if (JS_GetProperty(context, params, "choicesKey", &value))
		MissionSetChoicesKey(context, this, 1, &value, &noWarning);
	
	// now clean up!
	value = JSVAL_NULL;
	MissionSetProperty(context, this, INT_TO_JSVAL(kMission_foreground), &value);
	MissionSetProperty(context, this, INT_TO_JSVAL(kMission_background), &value);
	MissionSetProperty(context, this, INT_TO_JSVAL(kMission_title), &value);
	MissionSetMusic(context, this, 1, &value, &noWarning);
	
	*outResult = JSVAL_TRUE;
	return YES;
}
