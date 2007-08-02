/*

OOJavaScriptEngine.h

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

#import "OOJavaScriptEngine.h"
#import "OOJSScript.h"
#import "OOCollectionExtractors.h"
#import "Universe.h"
#import "PlanetEntity.h"
#import "NSStringOOExtensions.h"
#import "OOJSVector.h"
#import "OOJSEntity.h"
#import "OOJSShip.h"
#import "jsarray.h"

#include <stdio.h>
#include <string.h>


extern NSString * const kOOLogDebugMessage;


static OOJavaScriptEngine *sSharedEngine = nil;
static JSObject *xglob, *systemObj, *playerObj, *missionObj;


extern OOJSScript *currentOOJSScript;


OOINLINE jsval BOOLToJSVal(BOOL b) INLINE_CONST_FUNC;
OOINLINE jsval BOOLToJSVal(BOOL b)
{
	return BOOLEAN_TO_JSVAL(b != NO);
}


// For _bool scripting methods which always return @"YES" or @"NO" and nothing else.
OOINLINE jsval BooleanStringToJSVal(NSString *string) INLINE_PURE_FUNC;
OOINLINE jsval BooleanStringToJSVal(NSString *string)
{
	return BOOLEAN_TO_JSVAL([string isEqualToString:@"YES"]);
}


/*	All JS functions which talk to the player entity should call Player() to
	ensure that the script target (for the legacy system) is set correctly.
	Additionally, all such functions should _always_ call Player(), to ensure
	consistent state.
*/
OOINLINE PlayerEntity *Player(void)
{
	PlayerEntity *player = [PlayerEntity sharedPlayer];
	[player setScriptTarget:player];
	
	return player;
}


#define JSValToNSString(cx, val) [NSString stringWithJavaScriptValue:val inContext:cx]


static void ReportJSError(JSContext *cx, const char *message, JSErrorReport *report);


//===========================================================================
// MissionVars class
//===========================================================================

static JSBool MissionVarsGetProperty(JSContext *cx, JSObject *obj, jsval name, jsval *vp);
static JSBool MissionVarsSetProperty(JSContext *cx, JSObject *obj, jsval name, jsval *vp);


static JSClass MissionVars_class =
{
	"MissionVariables",
	0,
	
	JS_PropertyStub,
	JS_PropertyStub,
	MissionVarsGetProperty,
	MissionVarsSetProperty,
	JS_EnumerateStub,
	JS_ResolveStub,
	JS_ConvertStub,
	JS_FinalizeStub
};


static JSBool MissionVarsGetProperty(JSContext *cx, JSObject *obj, jsval name, jsval *vp)
{
	NSDictionary	*mission_variables = [Player() mission_variables];
	
	if (JSVAL_IS_STRING(name))
	{
		NSString	*key = [@"mission_" stringByAppendingString:[NSString stringWithJavaScriptValue:name inContext:cx]];
		NSString	*value = [mission_variables objectForKey:key];
		
		if (value == nil)
		{
			*vp = JSVAL_VOID;
		}
		else
		{
			/*	The point of this code is to try and tell the JS interpreter to treat numeric strings
				as numbers where possible so that standard arithmetic works as you'd expect rather than
				1+1 == "11". So a JSVAL_DOUBLE is returned if possible, otherwise a JSVAL_STRING is returned.
			*/
			
			BOOL	isNumber = NO;
			double	dVal;
			
			dVal = [value doubleValue];
			if (dVal != 0) isNumber = YES;
			else
			{
				NSCharacterSet *notZeroSet = [[NSCharacterSet characterSetWithCharactersInString:@"-0. "] invertedSet];
				if ([value rangeOfCharacterFromSet:notZeroSet].location == NSNotFound) isNumber = YES;
			}
			if (isNumber)
			{
				jsdouble ds = [value doubleValue];
				JSBool ok = JS_NewDoubleValue(cx, ds, vp);
				if (!ok) *vp = JSVAL_VOID;
			}
			else *vp = [value javaScriptValueInContext:cx];
		}
	}
	return JS_TRUE;
}


static JSBool MissionVarsSetProperty(JSContext *cx, JSObject *obj, jsval name, jsval *vp)
{
	NSDictionary *mission_variables = [Player() mission_variables];

	if (JSVAL_IS_STRING(name))
	{
		NSString	*key = [@"mission_" stringByAppendingString:[NSString stringWithJavaScriptValue:name inContext:cx]];
		NSString	*value = [NSString stringWithJavaScriptValue:*vp inContext:cx];
		[mission_variables setValue:value forKey:key];
	}
	return JS_TRUE;
}

//===========================================================================
// Global object class
//===========================================================================

static JSBool GlobalGetProperty(JSContext *cx, JSObject *obj, jsval name, jsval *vp);


static JSClass global_class =
{
	"Oolite",
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


enum global_propertyIDs
{
	GLOBAL_GALAXY_NUMBER,
	GLOBAL_PLANET_NUMBER,
	GLOBAL_MISSION_VARS,
	GLOBAL_GUI_SCREEN
};


// TODO: most of these should be properties of Player class.
static JSPropertySpec Global_props[] =
{
	// JS name					ID							flags
	{ "galaxyNumber",			GLOBAL_GALAXY_NUMBER,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY, GlobalGetProperty },
	{ "planetNumber",			GLOBAL_PLANET_NUMBER,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY, GlobalGetProperty },
	{ "missionVariables",		GLOBAL_MISSION_VARS,		JSPROP_PERMANENT | JSPROP_ENUMERATE, GlobalGetProperty },
	{ "guiScreen",				GLOBAL_GUI_SCREEN,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY, GlobalGetProperty },
	{ 0 }
};


static JSBool GlobalLog(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool GlobalLogWithClass(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);


static JSFunctionSpec Global_funcs[] =
{
	{ "Log", GlobalLog, 1, 0 },
	{ "LogWithClass", GlobalLogWithClass, 2, 0 },
	{ 0 }
};


static JSBool GlobalLog(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	NSString *logString = [NSString concatenationOfStringsFromJavaScriptValues:argv count:argc separator:@", " inContext:cx];
	OOLog(kOOLogDebugMessage, logString);
	return JS_TRUE;
}


static JSBool GlobalLogWithClass(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	NSString *logString = [NSString concatenationOfStringsFromJavaScriptValues:argv + 1 count:argc - 1 separator:@", " inContext:cx];
	OOLog([NSString stringWithJavaScriptValue:argv[0] inContext:cx], logString);
	return JS_TRUE;
}


static JSBool GlobalGetProperty(JSContext *cx, JSObject *obj, jsval name, jsval *vp)
{
	if (!JSVAL_IS_INT(name)) return JS_TRUE;
	
	PlayerEntity				*player = Player();
	id<OOJavaScriptConversion>	result = nil;
	
	switch (JSVAL_TO_INT(name))
	{
		case GLOBAL_GALAXY_NUMBER:
			result = [player galaxy_number];
			break;
		
		case GLOBAL_PLANET_NUMBER:
			result = [player planet_number];
			break;

		case GLOBAL_GUI_SCREEN:
			result = [player gui_screen_string];
			break;

		case GLOBAL_MISSION_VARS: {
			JSObject *mv = JS_DefineObject(cx, xglob, "missionVariables", &MissionVars_class, 0x00, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
			*vp = OBJECT_TO_JSVAL(mv);
			break;
		}
	}
	
	if (result != nil) *vp = [result javaScriptValueInContext:cx];
	return JS_TRUE;
}


//===========================================================================
// Player proxy
//===========================================================================

static JSBool PlayerGetProperty(JSContext *cx, JSObject *obj, jsval name, jsval *vp);
static JSBool PlayerSetProperty(JSContext *cx, JSObject *obj, jsval name, jsval *vp);


static JSClass Player_class =
{
	"Player",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,
	JS_PropertyStub,
	PlayerGetProperty,
	PlayerSetProperty,
	JS_EnumerateStub,
	JS_ResolveStub,
	JS_ConvertStub,
	JS_FinalizeStub
};


enum Player_propertyIDs
{
	PE_SHIP_DESCRIPTION,
	PE_COMMANDER_NAME,
	PE_SCORE,
	PE_CREDITS,
	PE_LEGAL_STATUS,
	PE_FUEL_LEVEL,
	PE_FUEL_LEAK_RATE,
	PE_ALERT_CONDITION,
	PE_STATUS_STRING,
	PE_DOCKED_AT_MAIN_STATION,
	PE_DOCKED_STATION_NAME,
	PE_POSITION,
	PE_VELOCITY,
	
	// Special handling -- these correspond to ALERT_FLAG_FOO (PlayerEntity.h). 0x10 is shifted left by the low nybble to get the alert mask.
	PE_DOCKED					= 0xA0,
	PE_ALERT_MASS_LOCKED		= 0xA1,
	PE_ALERT_TEMPERATURE		= 0xA2,
	PE_ALERT_ALTITUTE			= 0xA3,
	PE_ALERT_ENERGY				= 0xA4,
	PE_ALERT_HOSTILES			= 0xA5
};


static JSPropertySpec Player_props[] =
{
	// JS name					ID							flags
	{ "shipDescription",		PE_SHIP_DESCRIPTION,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "name",					PE_COMMANDER_NAME,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "score",					PE_SCORE,					JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "credits",				PE_CREDITS,					JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "legalStatus",			PE_LEGAL_STATUS,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "fuel",					PE_FUEL_LEVEL,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "fuelLeakRate",			PE_FUEL_LEAK_RATE,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "alertCondition",			PE_ALERT_CONDITION,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "docked",					PE_DOCKED,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "alertTemperature",		PE_ALERT_TEMPERATURE,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "alertMassLocked",		PE_ALERT_MASS_LOCKED,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "alertAltitude",			PE_ALERT_ALTITUTE,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "alertEnergy",			PE_ALERT_ENERGY,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "alertHostiles",			PE_ALERT_HOSTILES,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "status",					PE_STATUS_STRING,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "dockedAtMainStation",	PE_DOCKED_AT_MAIN_STATION,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "stationName",			PE_DOCKED_STATION_NAME,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "position",				PE_POSITION,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "velocity",				PE_VELOCITY,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSBool PlayerAwardEquipment(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool PlayerRemoveEquipment(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool PlayerHasEquipment(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool PlayerLaunch(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool PlayerCall(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool PlayerAwardCargo(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool PlayerRemoveAllCargo(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool PlayerUseSpecialCargo(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);


static JSFunctionSpec Player_funcs[] =
{
	// JS name					Function					min args
	{ "awardEquipment",			PlayerAwardEquipment,		1 },
	{ "removeEquipment",		PlayerRemoveEquipment,		1 },
	{ "hasEquipment",			PlayerHasEquipment,			1 },
	{ "launch",					PlayerLaunch,				0 },
	{ "call",					PlayerCall,					1 },
	{ "awardCargo",				PlayerAwardCargo,			2 },
	{ "removeAllCargo",			PlayerRemoveAllCargo,		0 },
	{ "useSpecialCargo",		PlayerUseSpecialCargo,		1 },
	{ 0 }
};


static JSBool PlayerAwardCargo(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = Player();
	NSString			*amount_type = nil;
	
	amount_type = [NSString stringWithFormat:@"%@ %@", JSValToNSString(cx, argv[1]), JSValToNSString(cx, argv[0])];
	[player awardCargo:amount_type];
	
	return JS_TRUE;
}

static JSBool PlayerRemoveAllCargo(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = Player();
	
	[player removeAllCargo];
	
	return JS_TRUE;
}


static JSBool PlayerUseSpecialCargo(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = Player();
	
	if (argc == 1)
	{
		[player useSpecialCargo:JSValToNSString(cx, argv[0])];
	}
	return JS_TRUE;
}

static JSBool PlayerAwardEquipment(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = Player();
	
	if (argc > 0 && JSVAL_IS_STRING(argv[0]))
	{
		JSString *jskey = JS_ValueToString(cx, argv[0]);
		[player awardEquipment: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
	}
	return JS_TRUE;
}


static JSBool PlayerRemoveEquipment(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = Player();
	
	if (argc > 0 && JSVAL_IS_STRING(argv[0]))
	{
		JSString *jskey = JS_ValueToString(cx, argv[0]);
		[player removeEquipment: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
	}
	return JS_TRUE;
}


static JSBool PlayerHasEquipment(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = Player();
	
	if (argc > 0 && JSVAL_IS_STRING(argv[0]))
	{
		NSString *key = [NSString stringWithJavaScriptValue:argv[0] inContext:cx];
		*rval = BOOLToJSVal([player hasExtraEquipment:key]);
	}
	return JS_TRUE;
}


static JSBool PlayerLaunch(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity *player = Player();
	
	[player launchFromStation];
	
	return JS_TRUE;
}


static JSBool PlayerCall(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity	*player = Player();
	NSString		*selectorString = nil;
	SEL				selector = NULL;
	NSString		*paramString = nil;
	BOOL			haveParameter = NO;
	
	selectorString = [NSString stringWithJavaScriptValue:argv[0] inContext:cx];
	
	// Join all parameters together with spaces.
	if (1 < argc && [selectorString hasSuffix:@":"])
	{
		haveParameter = YES;
		paramString = [NSString concatenationOfStringsFromJavaScriptValues:argv + 1 count:argc - 1 separator:@" " inContext:cx];
	}
	
	selector = NSSelectorFromString(selectorString);
	if ([player respondsToSelector:selector])
	{
		OOLog(@"script.trace.javaScript.call", @"Player.call: selector = %@, paramters = \"%@\"", selectorString, paramString);
		OOLogIndentIf(@"script.trace.javaScript.call");
		
		if (haveParameter)  [player performSelector:selector withObject:paramString];
		else  [player performSelector:selector];
		
		OOLogOutdentIf(@"script.trace.javaScript.call");
		return JS_TRUE;
	}
	else
	{
		OOLog(@"script.javaScript.call.badSelector", @"**** Error in script %@: Player does not respond to call(%@).", [currentOOJSScript displayName], selectorString);
		return JS_FALSE;
	}
}


static JSBool PlayerGetProperty(JSContext *cx, JSObject *obj, jsval name, jsval *vp)
{

	if (!JSVAL_IS_INT(name))  return JS_TRUE;
	
	PlayerEntity				*player = Player();
	id<OOJavaScriptConversion>	result = nil;
	
	uint8_t ID = JSVAL_TO_INT(name);
	switch (ID)
	{
		case PE_SHIP_DESCRIPTION:
			result = [player commanderShip_string];
			break;

		case PE_COMMANDER_NAME:
			result = [player commanderName_string];
			break;

		case PE_SCORE:
			result = [player score_number];
			break;

		case PE_LEGAL_STATUS:
			result = [player legalStatus_number];
			break;

		case PE_CREDITS:
			result = [player credits_number];
			break;

		case PE_FUEL_LEVEL:
			result = [player fuel_level_number];
			break;

		case PE_FUEL_LEAK_RATE:
			result = [player fuel_leak_rate_number];
			break;

		case PE_ALERT_CONDITION:
			*vp = INT_TO_JSVAL([player alertCondition]);
			break;
		
		case PE_DOCKED_AT_MAIN_STATION:
			*vp = BooleanStringToJSVal([player dockedAtMainStation_bool]);
			break;
		
		case PE_DOCKED_STATION_NAME:
			result = [player dockedStationName_string];
			break;

		case PE_STATUS_STRING:
			result = [player status_string];
			break;
		
		case PE_POSITION:
			VectorToJSValue(cx, [player position], vp);
			break;
		
		case PE_VELOCITY:
			VectorToJSValue(cx, [player velocity], vp);
			break;
		
		default:
			if ((ID & 0xF0) == 0xA0)
			{
				unsigned flags = [player alertFlags];
				unsigned mask = 0x10 << ((unsigned)ID & 0xF);
				*vp = BOOLToJSVal((flags & mask) != 0);
			}
	}
	
	if (result != nil) *vp = [result javaScriptValueInContext:cx];
	return JS_TRUE;
}


static JSBool PlayerSetProperty(JSContext *cx, JSObject *obj, jsval name, jsval *vp)
{
	if (!JSVAL_IS_INT(name))  return JS_TRUE;
	
	PlayerEntity	*player = Player();
	NSString		*value = [NSString stringWithJavaScriptValue:*vp inContext:cx];
	
	switch (JSVAL_TO_INT(name))
	{
		case PE_SCORE:
			[player setKills:[value intValue]];
			break;

		case PE_LEGAL_STATUS:
			[player setLegalStatus:value];
			break;
		
		case PE_CREDITS:
			[player setCredits:[value intValue]];
			break;

		case PE_FUEL_LEVEL:
			[player setCredits:(int)([value doubleValue] * 10.0)];
			break;

		case PE_FUEL_LEAK_RATE:
			[player setFuelLeak:value];
			break;
	}
	return JS_TRUE;
}


//===========================================================================
// Universe (solar system) proxy
//===========================================================================

static JSBool SystemGetProperty(JSContext *cx, JSObject *obj, jsval name, jsval *vp);
static JSBool SystemSetProperty(JSContext *cx, JSObject *obj, jsval name, jsval *vp);

static JSClass System_class =
{
	"Universe",
	0,
	
	JS_PropertyStub,
	JS_PropertyStub,
	SystemGetProperty,
	SystemSetProperty,
	JS_EnumerateStub,
	JS_ResolveStub,
	JS_ConvertStub,
	JS_FinalizeStub
};


enum System_propertyIDs
{
	SYS_ID,
	SYS_NAME,
	SYS_DESCRIPTION,
	SYS_GOING_NOVA,
	SYS_GONE_NOVA,
	SYS_GOVT_STR,
	SYS_GOVT_ID,
	SYS_ECONOMY_STR,
	SYS_ECONOMY_ID,
	SYS_TECH_LVL,
	SYS_POPULATION,
	SYS_PRODUCTIVITY,
	SYS_INHABITANTS
};


static JSPropertySpec System_props[] =
{
	// JS name					ID							flags
	{ "ID",						SYS_ID,						JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "name",					SYS_NAME,					JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "description",			SYS_DESCRIPTION,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "inhabitantsDescription",	SYS_INHABITANTS,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "goingNova",				SYS_GOING_NOVA,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "goneNova",				SYS_GONE_NOVA,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "government",				SYS_GOVT_ID,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "governmentDescription",	SYS_GOVT_STR,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "economy",				SYS_ECONOMY_ID,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "economyDescription",		SYS_ECONOMY_STR,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "techLevel",				SYS_TECH_LVL,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "population",				SYS_POPULATION,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "productivity",			SYS_PRODUCTIVITY,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ 0 }
};


static JSBool SystemAddPlanet(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemAddMoon(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemSendAllShipsAway(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemSetSunNova(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemCountShipsWithRole(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemAddShips(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemAddSystemShips(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemAddShipsAt(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemAddShipsAtPrecisely(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemAddShipsWithinRadius(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemSpawn(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemSpawnShip(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);


static JSFunctionSpec System_funcs[] =
{
	// JS name					Function					min args
	{ "addPlanet",				SystemAddPlanet,			1 },
	{ "addMoon",				SystemAddMoon,				1 },
	{ "sendAllShipsAway",		SystemSendAllShipsAway,		1 },
	{ "setSunNova",				SystemSetSunNova,			1 },
	{ "countShipsWithRole",		SystemCountShipsWithRole,	1, 0 },
	{ "legacy_addShips",		SystemAddShips,				2, 0 },
	{ "legacy_addSystemShips",	SystemAddSystemShips,		3, 0 },
	{ "legacy_addShipsAt",		SystemAddShipsAt,			6, 0 },
	{ "legacy_addShipsAtPrecisely", SystemAddShipsAtPrecisely, 6, 0 },
	{ "legacy_addShipsWithinRadius", SystemAddShipsWithinRadius, 7, 0 },
	{ "legacy_spawn",			SystemSpawn,				2, 0 },
	{ "legacy_spawnShip",		SystemSpawnShip,			1, 0 },
	{ 0 }
};


static JSBool SystemAddPlanet(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity *player = Player();
	
	if (argc > 0 && JSVAL_IS_STRING(argv[0]))
	{
		NSString *key = JSValToNSString(cx, argv[0]);
		[player addPlanet:key];
	}
	return JS_TRUE;
}


static JSBool SystemAddMoon(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity *player = Player();
	
	if (argc > 0 && JSVAL_IS_STRING(argv[0]))
	{
		NSString *key = JSValToNSString(cx, argv[0]);
		[player addMoon:key];
	}
	return JS_TRUE;
}


static JSBool SystemSendAllShipsAway(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity *player = Player();
	
	[player sendAllShipsAway];
	
	return JS_TRUE;
}


static JSBool SystemSetSunNova(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity *player = Player();
	
	if (argc > 0)
	 {
		NSString *key = JSValToNSString(cx, argv[0]);
		[player setSunNovaIn:key];
	}
	return JS_TRUE;
}


static Random_Seed currentSystem;
static NSDictionary *planetinfo = nil;

static JSBool SystemGetProperty(JSContext *cx, JSObject *obj, jsval name, jsval *vp)
{
	if (!JSVAL_IS_INT(name))  return JS_TRUE;

	PlayerEntity				*player = Player();
	id<OOJavaScriptConversion>	result = nil;
	
	if (!equal_seeds(currentSystem, player->system_seed))
	{
		currentSystem = player->system_seed;
		
		[planetinfo release];
		planetinfo = [[UNIVERSE generateSystemData:currentSystem] retain];
	}

	switch (JSVAL_TO_INT(name))
	{
		case SYS_ID:
			result = [player planet_number];
			break;

		case SYS_NAME:
			if ([UNIVERSE sun] != nil)
			{
				result = [planetinfo objectForKey:KEY_NAME];
				if (result == nil) result = @"None";	// TODO: should this return JSVAL_VOID instead? Other cases below. -- ahruman
			}
			else
			{
				// Witchspace. (Hmm, does a system that's gone nova have a sun? If not, -[PlayerEntity planet_number] is broken, too.
				result = @"Interstellar space";
			}
			break;

		case SYS_DESCRIPTION:
			result = [planetinfo objectForKey:KEY_DESCRIPTION];
			if (result == nil) result = @"None";
			break;

		case SYS_INHABITANTS:
			result = [planetinfo objectForKey:KEY_INHABITANTS];
			if (result == nil) result = @"None";
			break;
		
		case SYS_GOING_NOVA:
			*vp = BooleanStringToJSVal([player sunWillGoNova_bool]);
			break;

		case SYS_GONE_NOVA:
			*vp = BooleanStringToJSVal([player sunGoneNova_bool]);
			break;

		case SYS_GOVT_ID:
			result = [player systemGovernment_number];
			break;

		case SYS_GOVT_STR:
			result = [player systemGovernment_string];
			break;

		case SYS_ECONOMY_ID:
			result = [player systemEconomy_number];
			break;

		case SYS_ECONOMY_STR:
			result = [player systemEconomy_string];
			break;

		case SYS_TECH_LVL:
			result = [player systemTechLevel_number];
			break;

		case SYS_POPULATION:
			result = [player systemPopulation_number];
			break;

		case SYS_PRODUCTIVITY:
			result = [player systemProductivity_number];
			break;
	}
	
	if (result != nil)  *vp = [result javaScriptValueInContext:cx];
	return JS_TRUE;
}


static JSBool SystemSetProperty(JSContext *cx, JSObject *obj, jsval name, jsval *vp)
{
	if (!JSVAL_IS_INT(name))  return JS_TRUE;
	
	PlayerEntity	*player = Player();
	
	if (!equal_seeds(currentSystem, player->system_seed))
	{
		currentSystem = player->system_seed;
		if (planetinfo)  [planetinfo release];

		planetinfo = [[UNIVERSE generateSystemData:currentSystem] retain];
	}
	int gn = [[player galaxy_number] intValue];
	int pn = [[player planet_number] intValue];
	
	switch (JSVAL_TO_INT(name))
	{
		case SYS_NAME:
			[UNIVERSE setSystemDataForGalaxy:gn planet:pn key:KEY_NAME value:JSValToNSString(cx, *vp)];
			break;

			case SYS_DESCRIPTION:
			[UNIVERSE setSystemDataForGalaxy:gn planet:pn key:KEY_DESCRIPTION value:JSValToNSString(cx, *vp)];
			break;

		case SYS_INHABITANTS:
			[UNIVERSE setSystemDataForGalaxy:gn planet:pn key:KEY_INHABITANTS value:JSValToNSString(cx, *vp)];
			break;

		case SYS_GOING_NOVA:
			*vp = BOOLToJSVal([[UNIVERSE sun] willGoNova]);
			break;

		case SYS_GONE_NOVA:
			*vp = BOOLToJSVal([[UNIVERSE sun] goneNova]);
			break;

		case SYS_GOVT_ID:
			[UNIVERSE setSystemDataForGalaxy:gn planet:pn key:KEY_GOVERNMENT value:[NSNumber numberWithInt:[JSValToNSString(cx, *vp) intValue]]];
			break;

		case SYS_ECONOMY_ID:
			[UNIVERSE setSystemDataForGalaxy:gn planet:pn key:KEY_ECONOMY value:[NSNumber numberWithInt:[JSValToNSString(cx, *vp) intValue]]];
			break;

		case SYS_TECH_LVL:
			[UNIVERSE setSystemDataForGalaxy:gn planet:pn key:KEY_TECHLEVEL value:[NSNumber numberWithInt:[JSValToNSString(cx, *vp) intValue]]];
			break;

		case SYS_POPULATION:
			[UNIVERSE setSystemDataForGalaxy:gn planet:pn key:KEY_POPULATION value:[NSNumber numberWithInt:[JSValToNSString(cx, *vp) intValue]]];
			break;

		case SYS_PRODUCTIVITY:
			[UNIVERSE setSystemDataForGalaxy:gn planet:pn key:KEY_PRODUCTIVITY value:[NSNumber numberWithInt:[JSValToNSString(cx, *vp) intValue]]];
			break;
	}
	return JS_TRUE;
}


static JSBool SystemCountShipsWithRole(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	NSString			*role = nil;
	int					count;
	
	if (argc == 1)
	{
		role = JSValToNSString(cx, argv[0]);
		count = [UNIVERSE countShipsWithRole:role];
		*rval = INT_TO_JSVAL(count);
	}
	return JS_TRUE;
}


static JSBool SystemAddShips(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	NSString			*role = nil;
	int					count;
	
	if (argc == 2)
	{
		role = JSValToNSString(cx, argv[0]);
		count = JSVAL_TO_INT(argv[1]);

		while (count--)  [UNIVERSE witchspaceShipWithRole:role];
	}
	return JS_TRUE;
}


static JSBool SystemAddSystemShips(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	jsdouble			position;
	NSString			*role = nil;
	int					count;
	
	if (argc == 3)
	{
		role = JSValToNSString(cx, argv[0]);
		count = JSVAL_TO_INT(argv[1]);
		
		JS_ValueToNumber(cx, argv[2], &position);
		while (count--)  [UNIVERSE addShipWithRole:role nearRouteOneAt:position];
	}
	return JS_TRUE;
}


static JSBool SystemAddShipsAt(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = Player();
	jsdouble			x, y, z;
	NSString			*role = nil;
	int					count;
	NSString			*coordScheme = nil;
	NSString			*arg = nil;
	
	if (argc == 6)
	{
		role = JSValToNSString(cx, argv[0]);
		count = JSVAL_TO_INT(argv[1]);
		coordScheme = JSValToNSString(cx, argv[2]);
		
		JS_ValueToNumber(cx, argv[3], &x);
		JS_ValueToNumber(cx, argv[4], &y);
		JS_ValueToNumber(cx, argv[5], &z);
		
		arg = [NSString stringWithFormat:@"%@ %d %@ %f %f %f", role, count, coordScheme, x, y, z];
		[player addShipsAt:arg];
	}
	return JS_TRUE;
}


static JSBool SystemAddShipsAtPrecisely(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = Player();
	jsdouble			x, y, z;
	NSString			*role = nil;
	int					count;
	NSString			*coordScheme = nil;
	NSString			*arg = nil;
	
	if (argc == 6)
	{
		role = JSValToNSString(cx, argv[0]);
		count = JSVAL_TO_INT(argv[1]);
		coordScheme = JSValToNSString(cx, argv[2]);
		
		JS_ValueToNumber(cx, argv[3], &x);
		JS_ValueToNumber(cx, argv[4], &y);
		JS_ValueToNumber(cx, argv[5], &z);
		
		arg = [NSString stringWithFormat:@"%@ %d %@ %f %f %f", role, count, coordScheme, x, y, z];
		[player addShipsAtPrecisely:arg];
	}
	return JS_TRUE;
}


static JSBool SystemAddShipsWithinRadius(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = Player();
	jsdouble			x, y, z, radius;
	NSString			*role = nil;
	int					count;
	NSString			*coordScheme = nil;
	NSString			*arg = nil;
	
	if (argc == 7)
	{
		role = JSValToNSString(cx, argv[0]);
		count = JSVAL_TO_INT(argv[1]);
		coordScheme = JSValToNSString(cx, argv[2]);
		
		JS_ValueToNumber(cx, argv[3], &x);
		JS_ValueToNumber(cx, argv[4], &y);
		JS_ValueToNumber(cx, argv[5], &z);
		JS_ValueToNumber(cx, argv[6], &radius);
		
		arg = [NSString stringWithFormat:@"%@ %d %@ %f %f %f %d", role, count, coordScheme, x, y, z, radius];
		[player addShipsWithinRadius:arg];
	}
	return JS_TRUE;
}


static JSBool SystemSpawn(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = Player();
	NSString			*role = nil;
	int					count;
	NSString			*arg = nil;
	
	if (argc == 2)
	{
		role = JSValToNSString(cx, argv[0]);
		count = JSVAL_TO_INT(argv[1]);
		
		arg = [NSString stringWithFormat:@"%@ %d", role, count];
		[player spawn:arg];
	}
	return JS_TRUE;
}


static JSBool SystemSpawnShip(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = Player();
	
	if (argc == 1)
	{
		[player spawnShip:JSValToNSString(cx, argv[0])];
	}
	return JS_TRUE;
}


//===========================================================================
// Mission class
//===========================================================================

static JSBool MissionGetProperty(JSContext *cx, JSObject *obj, jsval name, jsval *vp);
static JSBool MissionSetProperty(JSContext *cx, JSObject *obj, jsval name, jsval *vp);


static JSClass Mission_class =
{
	"Mission",
	0,
	
	JS_PropertyStub,
	JS_PropertyStub,
	MissionGetProperty,
	MissionSetProperty,
	JS_EnumerateStub,
	JS_ResolveStub,
	JS_ConvertStub,
	JS_FinalizeStub
};


enum Mission_propertyIDs
{
	MISSION_TEXT, MISSION_MUSIC, MISSION_IMAGE, MISSION_CHOICES, MISSION_CHOICE, MISSION_INSTRUCTIONS
};

static JSPropertySpec Mission_props[] =
{
	{ "missionScreenTextKey", MISSION_TEXT, JSPROP_ENUMERATE },
	{ "musicFileName", MISSION_MUSIC, JSPROP_ENUMERATE },
	{ "imageFileName", MISSION_IMAGE, JSPROP_ENUMERATE },
	{ "choicesKey", MISSION_CHOICES, JSPROP_ENUMERATE },
	{ "choice", MISSION_CHOICE, JSPROP_ENUMERATE },
	{ "instructionsKey", MISSION_INSTRUCTIONS, JSPROP_ENUMERATE },
	{ 0 }
};


static JSBool MissionShowMissionScreen(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool MissionShowShipModel(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool MissionResetMissionChoice(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool MissionMarkSystem(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool MissionUnmarkSystem(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);


static JSFunctionSpec Mission_funcs[] =
{
	{ "showMissionScreen", MissionShowMissionScreen, 0, 0 },
	{ "showShipModel", MissionShowShipModel, 1, 0 },
	{ "resetMissionChoice", MissionResetMissionChoice, 0, 0 },
	{ "markSystem", MissionMarkSystem, 1, 0 },
	{ "unmarkSystem", MissionUnmarkSystem, 1, 0 },
	{ 0 }
};


static JSBool MissionGetProperty(JSContext *cx, JSObject *obj, jsval name, jsval *vp)
{
	if (!JSVAL_IS_INT(name))  return JS_TRUE;

	PlayerEntity				*player = Player();
	id<OOJavaScriptConversion>	result = nil;

	switch (JSVAL_TO_INT(name))
	{
		case MISSION_CHOICE:
			result = [player missionChoice_string];
			if (result == nil) result = @"None";
			break;
	}
	
	if (result != nil) *vp = [result javaScriptValueInContext:cx];
	return JS_TRUE;
}


static JSBool MissionSetProperty(JSContext *cx, JSObject *obj, jsval name, jsval *vp)
{
	if (!JSVAL_IS_INT(name))  return JS_TRUE;

	PlayerEntity				*player = Player();

	switch (JSVAL_TO_INT(name)) {
		case MISSION_TEXT: {
			if (JSVAL_IS_STRING(*vp)) {
				JSString *jskey = JS_ValueToString(cx, *vp);
				[player addMissionText: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
			}
			break;
		}
		case MISSION_MUSIC: {
			if (JSVAL_IS_STRING(*vp)) {
				JSString *jskey = JS_ValueToString(cx, *vp);
				[player setMissionMusic: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
			}
			break;
		}
		case MISSION_IMAGE: {
			if (JSVAL_IS_STRING(*vp)) {
				NSString *str = JSValToNSString(cx, *vp);
				if ([str length] == 0)
					str = @"none";
				[player setMissionImage:str];
			}
			break;
		}
		case MISSION_CHOICES: {
			if (JSVAL_IS_STRING(*vp)) {
				JSString *jskey = JS_ValueToString(cx, *vp);
				[player setMissionChoices: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
			}
			break;
		}
		case MISSION_INSTRUCTIONS: {
			if (JSVAL_IS_STRING(*vp)) {
				JSString *jskey = JS_ValueToString(cx, *vp);
				NSString *ins = [NSString stringWithCString:JS_GetStringBytes(jskey)];
				if ([ins length])
					[player setMissionDescription:ins forMission:[currentOOJSScript name]];
				else
					[player clearMissionDescriptionForMission:[currentOOJSScript name]];
			}
			break;
		}
	}
	return JS_TRUE;
}


static JSBool MissionShowMissionScreen(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = Player();
	
	[player setGuiToMissionScreen];
	
	return JS_TRUE;
}


static JSBool MissionShowShipModel(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = Player();
	JSString			*jskey = NULL;
	
	if (argc > 0 && JSVAL_IS_STRING(argv[0]))
	{
		jskey = JS_ValueToString(cx, argv[0]);
		[player showShipModel: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
	}
	return JS_TRUE;
}


static JSBool MissionResetMissionChoice(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = Player();
	
	[player resetMissionChoice];
	
	return JS_TRUE;
}


static JSBool MissionMarkSystem(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = Player();
	NSString			*params = nil;
	
	params = [NSString concatenationOfStringsFromJavaScriptValues:argv count:argc separator:@" " inContext:cx];
	[player addMissionDestination:params];
	
	return JS_TRUE;
}


static JSBool MissionUnmarkSystem(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = Player();
	NSString			*params = nil;
	
	player = [NSString concatenationOfStringsFromJavaScriptValues:argv count:argc separator:@" " inContext:cx];
	[player removeMissionDestination:params];
	
	return JS_TRUE;
}


static void ReportJSError(JSContext *cx, const char *message, JSErrorReport *report)
{
	NSString		*severity = nil;
	NSString		*messageText = nil;
	NSString		*lineBuf = nil;
	NSString		*messageClass = nil;
	NSString		*highlight = @"*****";
	
	// Type of problem: error, warning or exception? (Strict flag wilfully ignored.)
	if (report->flags & JSREPORT_EXCEPTION) severity = @"exception";
	else if (report->flags & JSREPORT_WARNING)
	{
		severity = @"warning";
		highlight = @"-----";
	}
	else severity = @"error";
	
	// The error message itself
	messageText = [NSString stringWithUTF8String:message];
	
	// Get offending line, if present, and trim trailing line breaks
	lineBuf = [NSString stringWithUTF16String:report->uclinebuf];
	while ([lineBuf hasSuffix:@"\n"] || [lineBuf hasSuffix:@"\r"])  lineBuf = [lineBuf substringToIndex:[lineBuf length] - 1];
	
	// Log message class
	messageClass = [NSString stringWithFormat:@"script.javaScript.%@.%u", severity, report->errorNumber];
	
	// First line: problem description
	OOLog(messageClass, @"%@ JavaScript %@: %@", highlight, severity, messageText);
	
	// Second line: where error occured, and line if provided. (The line is only provided for compile-time errors, not run-time errors.)
	if ([lineBuf length] != 0)
	{
		OOLog(messageClass, @"      %s, line %d: %@", report->filename, report->lineno, lineBuf);
	}
	else
	{
		OOLog(messageClass, @"      %s, line %d.", report->filename, report->lineno);
	}
}


//===========================================================================
// JavaScript engine initialisation and shutdown
//===========================================================================

@implementation OOJavaScriptEngine

+ (OOJavaScriptEngine *)sharedEngine
{
	if (sSharedEngine == nil) [[self alloc] init];
	
	return sSharedEngine;
}


- (id) init
{
	assert(sSharedEngine == nil);
	
	self = [super init];
	
	assert(sizeof(jschar) == sizeof(unichar));

	/*set up global JS variables, including global and custom objects */

	/* initialize the JS run time, and return result in rt */
	rt = JS_NewRuntime(8L * 1024L * 1024L);

	/* if rt does not have a value, end the program here */
	if (!rt)
	{
		OOLog(@"script.javaScript.init.error", @"FATAL ERROR: failed to create JavaScript %@.", @"runtime");
		exit(1);
	}

	/* create a context and associate it with the JS run time */
	cx = JS_NewContext(rt, 8192);
	JS_SetOptions(cx, JSOPTION_VAROBJFIX | JSOPTION_STRICT | JSOPTION_NATIVE_BRANCH_CALLBACK);
	
	/* if cx does not have a value, end the program here */
	if (!cx)
	{
		OOLog(@"script.javaScript.init.error", @"FATAL ERROR: failed to create JavaScript %@.", @"context");
		exit(1);
	}

	JS_SetErrorReporter(cx, ReportJSError);

	/* create the global object here */
	glob = JS_NewObject(cx, &global_class, NULL, NULL);
	xglob = glob;

	/* initialize the built-in JS objects and the global object */
	builtins = JS_InitStandardClasses(cx, glob);
	JS_DefineProperties(cx, glob, Global_props);
	JS_DefineFunctions(cx, glob, Global_funcs);

	systemObj = JS_DefineObject(cx, glob, "system", &System_class, NULL, JSPROP_ENUMERATE);
	JS_DefineProperties(cx, systemObj, System_props);
	JS_DefineFunctions(cx, systemObj, System_funcs);

	missionObj = JS_DefineObject(cx, glob, "mission", &Mission_class, NULL, JSPROP_ENUMERATE);
	JS_DefineProperties(cx, missionObj, Mission_props);
	JS_DefineFunctions(cx, missionObj, Mission_funcs);
	
	InitOOJSVector(cx, glob);
	InitOOJSEntity(cx, glob);
	InitOOJSShip(cx, glob);
	
	playerObj = JS_DefineObject(cx, glob, "player", &Player_class, JSShipPrototype(), JSPROP_ENUMERATE);
	JS_DefineProperties(cx, playerObj, Player_props);
	JS_DefineFunctions(cx, playerObj, Player_funcs);
	JS_SetPrivate(cx, playerObj, [[PlayerEntity sharedPlayer] weakRetain]);
	JSEntityRegisterEntitySubclass(&Player_class);
	
	OOLog(@"script.javaScript.init.success", @"Set up JavaScript context.");
	
	sSharedEngine = self;
	return self;
}


- (void) dealloc
{
	sSharedEngine = nil;
	
	JS_DestroyContext(cx);
	JS_DestroyRuntime(rt);
	
	[super dealloc];
}


- (JSContext *) context
{
	return cx;
}

@end


JSObject *JSPlayerObject(void)
{
	return playerObj;
}


void OOReportJavaScriptError(JSContext *context, NSString *format, ...)
{
	va_list					args;
	
	va_start(args, format);
	OOReportJavaScriptErrorWithArguments(context, format, args);
	va_end(args);
}


void OOReportJavaScriptErrorWithArguments(JSContext *context, NSString *format, va_list args)
{
	NSString				*msg = nil;
	
	msg = [[NSString alloc] initWithFormat:format arguments:args];
	JS_ReportWarning(context, "%s", [msg UTF8String]);
	[msg release];
}


void OOReportJavaScriptWarning(JSContext *context, NSString *format, ...)
{
	va_list					args;
	
	va_start(args, format);
	OOReportJavaScriptWarningWithArguments(context, format, args);
	va_end(args);
}


void OOReportJavaScriptWarningWithArguments(JSContext *context, NSString *format, va_list args)
{
	NSString				*msg = nil;
	
	msg = [[NSString alloc] initWithFormat:format arguments:args];
	JS_ReportWarning(context, "%s", [msg UTF8String]);
	[msg release];
}


BOOL NumberFromArgumentList(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, double *outNumber, uintN *outConsumed)
{
	double					value;
	
	// Sanity checks.
	if (outConsumed != NULL)  *outConsumed = 0;
	if (EXPECT_NOT(argc == 0 || argv == NULL || outNumber == NULL))
	{
		OOLogGenericParameterError();
		return NO;
	}
	
	// Get value, if possible.
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[0], &value) || isnan(value)))
	{
		// Failed; report bad parameters, if given a class and function.
		if (scriptClass != nil && function != nil)
		{
			OOReportJavaScriptWarning(context, @"%@.%@(): expected number, got %@.", scriptClass, function, [NSString stringWithJavaScriptParameters:argv count:1 inContext:context]);
			return NO;
		}
	}
	
	// Success.
	*outNumber = value;
	if (outConsumed != NULL)  *outConsumed = 1;
	return YES;
}


BOOL JSArgumentsFromArray(JSContext *context, NSArray *array, uintN *outArgc, jsval **outArgv)
{
	if (outArgc != NULL) *outArgc = 0;
	if (outArgv != NULL) *outArgv = NULL;
	
	if (array == nil)  return YES;
	
	// Sanity checks.
	if (outArgc == NULL || outArgv == NULL)
	{
		OOLogGenericParameterError();
		return NO;
	}
	if (context == NULL) context = [[OOJavaScriptEngine sharedEngine] context];
	
	uintN					i = 0, argc = [array count];
	NSEnumerator			*objectEnum = nil;
	id						object = nil;
	jsval					*argv = NULL;
	
	if (argc == 0) return YES;
	
	// Allocate result buffer
	argv = malloc(sizeof *argv * argc);
	if (argv == NULL)
	{
		OOLog(kOOLogAllocationFailure, @"Failed to allocate space for %u JavaScript parameters.", argc);
		return NO;
	}
	
	// Convert objects
	JSContext * volatile vCtxt = context;
	for (objectEnum = [array objectEnumerator]; (object = [objectEnum nextObject]); )
	{
		argv[i] = JSVAL_VOID;
		
		NS_DURING
			if ([object respondsToSelector:@selector(javaScriptValueInContext:)])
			{
				argv[i] = [object javaScriptValueInContext:vCtxt];
			}
		NS_HANDLER
		NS_ENDHANDLER
		++i;
	}
	
	*outArgc = argc;
	*outArgv = argv;
	return YES;
}


JSObject *JSArrayFromNSArray(JSContext *context, NSArray *array)
{
	uintN					count;
	jsval					*values;
	JSObject				*result = NULL;
	
	if (JSArgumentsFromArray(context, array, &count, &values))
	{
		result = js_NewArrayObject(context, count, values);
	}
	if (values != NULL)  free(values);
	
	return result;
}


@implementation NSString (OOJavaScriptExtensions)

// Convert a JSString to an NSString.
+ (id)stringWithJavaScriptString:(JSString *)string
{
	jschar					*chars = NULL;
	size_t					length;
	
	chars = JS_GetStringChars(string);
	length = JS_GetStringLength(string);
	
	return [NSString stringWithCharacters:chars length:length];
}


+ (id)stringWithJavaScriptValue:(jsval)value inContext:(JSContext *)context
{
	JSString				*string = NULL;
	
	string = JS_ValueToString(context, value);	// Calls the value's convert method if needed.
	return [NSString stringWithJavaScriptString:string];
}


+ (id)stringWithJavaScriptParameters:(jsval *)params count:(uintN)count inContext:(JSContext *)context
{
	if (params == nil && count != 0) return nil;
	
	uintN					i;
	jsval					val;
	NSMutableString			*result = [NSMutableString string];
	NSString				*valString = nil;
	
	for (i = 0; i != count; ++i)
	{
		if (i != 0)  [result appendString:@", "];
		else  [result appendString:@"("];
		
		val = params[i];
		valString = [self stringWithJavaScriptValue:val inContext:context];
		if (JSVAL_IS_STRING(val))
		{
			[result appendFormat:@"\"%@\"", valString];
		}
		else
		{
			[result appendString:valString];
		}
	}
	
	[result appendString:@")"];
	return result;
}


- (jsval)javaScriptValueInContext:(JSContext *)context
{
	size_t					length;
	unichar					*buffer = NULL;
	JSString				*string = NULL;
	
	length = [self length];
	buffer = malloc(length * sizeof *buffer);
	if (buffer == NULL) return JSVAL_VOID;
	
	[self getCharacters:buffer];
	
	string = JS_NewUCStringCopyN(context, buffer, length);
	free(buffer);
	
	return STRING_TO_JSVAL(string);
}


+ (id)concatenationOfStringsFromJavaScriptValues:(jsval *)values count:(size_t)count separator:(NSString *)separator inContext:(JSContext *)context
{
	size_t					i;
	NSMutableString			*result = nil;
	NSString				*element = nil;
	
	if (count < 1) return nil;
	if (values == NULL) return NULL;
	
	for (i = 0; i != count; ++i)
	{
		element = [NSString stringWithJavaScriptValue:values[i] inContext:context];
		if (result == nil) result = [element mutableCopy];
		else
		{
			if (separator != nil) [result appendString:separator];
			[result appendString:element];
		}
	}
	
	return result;
}

@end


@implementation NSArray (OOJavaScriptExtensions)

- (jsval)javaScriptValueInContext:(JSContext *)context
{
	return OBJECT_TO_JSVAL(JSArrayFromNSArray(context, self));
}

@end


@implementation NSNumber (OOJavaScriptExtensions)

- (jsval)javaScriptValueInContext:(JSContext *)context
{
	jsval					result;
	BOOL					isFloat = NO;
	const char				*type;
	long long				longLongValue;
	
	if (self == [NSNumber numberWithBool:YES])
	{
		/*	Under OS X, at least, numberWithBool: returns one of two singletons.
			There is no other way to reliably identify a boolean NSNumber.
			Fun, eh? */
		result = JSVAL_TRUE;
	}
	else if (self == [NSNumber numberWithBool:NO])
	{
		result = JSVAL_FALSE;
	}
	else
	{
		longLongValue = [self longLongValue];
		if (longLongValue < (long long)JSVAL_INT_MIN || (long long)JSVAL_INT_MAX < longLongValue)
		{
			// values outside JSVAL_INT range are returned as doubles.
			isFloat = YES;
		}
		else
		{
			// Check value type.
			type = [self objCType];
			if (type[0] == 'f' || type[0] == 'd') isFloat = YES;
		}
		
		if (isFloat)
		{
			if (!JS_NewDoubleValue(context, [self doubleValue], &result)) result = JSVAL_VOID;
		}
		else
		{
			result = INT_TO_JSVAL(longLongValue);
		}
	}
	
	return result;
}

@end


@implementation NSNull (OOJavaScriptExtensions)

- (jsval)javaScriptValueInContext:(JSContext *)context
{
	return JSVAL_NULL;
}

@end


NSString *JSPropertyAsString(JSContext *context, JSObject *object, const char *name)
{
	JSBool					OK;
	jsval					returnValue;
	NSString				*result = nil;
	
	if (context == NULL || object == NULL || name == NULL) return nil;
	
	OK = JS_GetProperty(context, object, name, &returnValue);
	if (OK && !JSVAL_IS_VOID(returnValue))
	{
		result = [NSString stringWithJavaScriptValue:returnValue inContext:context];
	}
	
	return result;
}
