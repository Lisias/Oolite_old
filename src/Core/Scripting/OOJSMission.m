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
#import "OOMusicController.h"


static JSBool MissionMarkSystem(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionUnmarkSystem(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionAddMessageText(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
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
	JS_PropertyStub,
	JS_EnumerateStub,
	JS_ResolveStub,
	JS_ConvertStub,
	JS_FinalizeStub
};


static JSFunctionSpec sMissionMethods[] =
{
	// JS name					Function					min args
	{ "addMessageText",			MissionAddMessageText,		1 },
	{ "markSystem",				MissionMarkSystem,			1 },
	{ "unmarkSystem",			MissionUnmarkSystem,		1 },
	{ "runScreen",				MissionRunScreen,			1 }, // the callback function is optional!
	{ "setInstructions",		MissionSetInstructions,		1 },
	{ "setInstructionsKey",		MissionSetInstructionsKey,	1 },
	{ 0 }
};


void InitOOJSMission(JSContext *context, JSObject *global)
{
	JSObject *missionPrototype = JS_InitClass(context, global, NULL, &sMissionClass, NULL, 0, NULL, sMissionMethods, NULL, NULL);
	JS_DefineObject(context, global, "mission", &sMissionClass, missionPrototype, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
	
	// Ensure JS objects are rooted.
	OOJS_AddGCValueRoot(context, &sCallbackFunction, "Pending mission callback function");
	OOJS_AddGCValueRoot(context, &sCallbackThis, "Pending mission callback this");
}


void MissionRunCallback()
{
	// don't do anything if we don't have a function.
	if (JSVAL_IS_NULL(sCallbackFunction))  return;
	
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
	
	OOJS_AddGCValueRoot(context, &cbFunction, "Mission callback function");
	OOJS_AddGCObjectRoot(context, &cbThis, "Mission callback this");
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


// *** Methods ***

// markSystem(systemCoords : String)
static JSBool MissionMarkSystem(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*params = nil;
	
	params = [NSString concatenationOfStringsFromJavaScriptValues:argv count:argc separator:@" " inContext:context];
	[player addMissionDestination:params];
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


// unmarkSystem(systemCoords : String)
static JSBool MissionUnmarkSystem(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*params = nil;
	
	params = [NSString concatenationOfStringsFromJavaScriptValues:argv count:argc separator:@" " inContext:context];
	[player removeMissionDestination:params];
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


// addMessageText(text : String)
static JSBool MissionAddMessageText(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*text = nil;
	
	// Found "FIXME: warning if no mission screen running.",,,
	// However: used routinely by the Constrictor mission in F7, without mission screens.
	text = JSValToNSString(context,argv[0]);
	[player addLiteralMissionText:text];
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


// setInstructionsKey(instructionsKey: String [, missionKey : String])
static JSBool MissionSetInstructionsKey(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	*outResult = [@"textKey" javaScriptValueInContext:context];
	return MissionSetInstructions(context, this, argc, argv, outResult);
	
	OOJS_NATIVE_EXIT
}


// setInstructions(instructions: String [, missionKey : String])
static JSBool MissionSetInstructions(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
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
	
	OOJS_NATIVE_EXIT
}


OOINLINE NSString *GetParameterString(JSContext *context, JSObject *object, const char *key)
{
	jsval value = JSVAL_NULL;
	if (JS_GetProperty(context, object, key, &value))
	{
		return JSValToNSString(context, value);
	}
	return nil;
}


// runScreen(params: dict, callBack:function) - if the callback function is null, emulate the old style runMissionScreen
static JSBool MissionRunScreen(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	jsval				function = JSVAL_NULL;
	jsval				value = JSVAL_NULL;
	JSObject			*params = JSVAL_NULL;
	
	// No mission screens during intro.
	if ([player guiScreen] == GUI_SCREEN_INTRO1 || [player guiScreen] == GUI_SCREEN_INTRO2)
	{
		*outResult = JSVAL_FALSE;
		return YES;
	}
	
	// Validate arguments.
	if (!JSVAL_IS_OBJECT(argv[0]) || JSVAL_IS_NULL(argv[0]))
	{
		OOReportJSBadArguments(context, @"mission", @"runScreen", argc, argv, nil, @"parameter object");
		return NO;
	}
	params = JSVAL_TO_OBJECT(argv[0]);
	
	if (argc > 1) function = argv[1];
	if (!JSVAL_IS_OBJECT(function) || (!JSVAL_IS_NULL(function) && !JS_ObjectIsFunction(context, JSVAL_TO_OBJECT(function))))
	{
		OOReportJSBadArguments(context, @"mission", @"runScreen", argc - 1, argv + 1, nil, @"function");
		return NO;
	}
	
	OOJSPauseTimeLimiter();
	
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
	
	// Apply settings.
	if (JS_GetProperty(context, params, "title", &value))
	{
		[player setMissionTitle:JSValToNSString(context, value)];
	}
	else
	{
		NSString *titleKey = GetParameterString(context, params, "titleKey");
		if (titleKey != nil)
		{
			titleKey = [[UNIVERSE missiontext] oo_stringForKey:titleKey];
			titleKey = ExpandDescriptionForCurrentSystem(titleKey);
			titleKey = [player replaceVariablesInString:titleKey];
			[player setMissionTitle:titleKey];
		}
	}
	
	[[OOMusicController	sharedController] setMissionMusic:GetParameterString(context, params, "music")];
	[player setMissionImage:GetParameterString(context, params, "overlay")];
	[player setMissionBackground:GetParameterString(context, params, "background")];
	
	if (JS_GetProperty(context, params, "model", &value))
	{
		if ([player status] == STATUS_IN_FLIGHT && JSVAL_IS_STRING(value))
		{
			OOReportJSWarning(context, @"Mission.runScreen: model will not be displayed while in flight.");
		}
		[player showShipModel:JSValToNSString(context, value)];
	}
	
	// Start the mission screen.
	sCallbackFunction = function;
	[player setGuiToMissionScreenWithCallback:!JSVAL_IS_NULL(sCallbackFunction)];
	
	// Apply more settings. (These must be done after starting the screen for legacy reasons.)
	NSString *message = GetParameterString(context, params, "message");
	if (message != nil)
	{
		[player addLiteralMissionText:message];
	}
	else
	{
		NSString *messageKey = GetParameterString(context, params, "messageKey");
		if (messageKey != nil)  [player addMissionText:messageKey];
	}
	
	[player setMissionChoices:GetParameterString(context, params, "choicesKey")];
	
	// now clean up!
	[player setMissionImage:nil];
	[player setMissionBackground:nil];
	[player setMissionTitle:nil];
	[player setMissionMusic:nil];
	
	OOJSResumeTimeLimiter();
	
	*outResult = JSVAL_TRUE;
	return YES;
	
	OOJS_NATIVE_EXIT
}
