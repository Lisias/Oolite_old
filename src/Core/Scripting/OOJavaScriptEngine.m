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

#import "OOJSVector.h"
#import "OOJSQuaternion.h"
#import "OOJSEntity.h"
#import "OOJSShip.h"
#import "OOJSStation.h"
#import "OOJSPlayer.h"
#import "jsarray.h"

#import "OOCollectionExtractors.h"
#import "Universe.h"
#import "PlanetEntity.h"
#import "NSStringOOExtensions.h"

#include <stdio.h>
#include <string.h>


extern NSString * const kOOLogDebugMessage;


static OOJavaScriptEngine *sSharedEngine = nil;
static JSObject *xglob, *systemObj, *missionObj;


extern OOJSScript *currentOOJSScript;


// For _bool scripting methods which always return @"YES" or @"NO" and nothing else.
OOINLINE jsval BooleanStringToJSVal(NSString *string) INLINE_PURE_FUNC;
OOINLINE jsval BooleanStringToJSVal(NSString *string)
{
	return BOOLEAN_TO_JSVAL([string isEqualToString:@"YES"]);
}


static void ReportJSError(JSContext *context, const char *message, JSErrorReport *report);


//===========================================================================
// MissionVars class
//===========================================================================

static JSBool MissionVarsGetProperty(JSContext *context, JSObject *obj, jsval name, jsval *vp);
static JSBool MissionVarsSetProperty(JSContext *context, JSObject *obj, jsval name, jsval *vp);


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


static JSBool MissionVarsGetProperty(JSContext *context, JSObject *obj, jsval name, jsval *vp)
{
	NSDictionary	*mission_variables = [OPlayerForScripting() mission_variables];
	
	if (JSVAL_IS_STRING(name))
	{
		NSString	*key = [@"mission_" stringByAppendingString:[NSString stringWithJavaScriptValue:name inContext:context]];
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
				JSBool ok = JS_NewDoubleValue(context, ds, vp);
				if (!ok) *vp = JSVAL_VOID;
			}
			else *vp = [value javaScriptValueInContext:context];
		}
	}
	return JS_TRUE;
}


static JSBool MissionVarsSetProperty(JSContext *context, JSObject *obj, jsval name, jsval *vp)
{
	NSDictionary *mission_variables = [OPlayerForScripting() mission_variables];

	if (JSVAL_IS_STRING(name))
	{
		NSString	*key = [@"mission_" stringByAppendingString:[NSString stringWithJavaScriptValue:name inContext:context]];
		NSString	*value = [NSString stringWithJavaScriptValue:*vp inContext:context];
		[mission_variables setValue:value forKey:key];
	}
	return JS_TRUE;
}

//===========================================================================
// Global object class
//===========================================================================

static JSBool GlobalGetProperty(JSContext *context, JSObject *obj, jsval name, jsval *vp);


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


static JSPropertySpec Global_props[] =
{
	// JS name					ID							flags
	{ "galaxyNumber",			GLOBAL_GALAXY_NUMBER,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY, GlobalGetProperty },
	{ "planetNumber",			GLOBAL_PLANET_NUMBER,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY, GlobalGetProperty },
	{ "missionVariables",		GLOBAL_MISSION_VARS,		JSPROP_PERMANENT | JSPROP_ENUMERATE, GlobalGetProperty },
	{ "guiScreen",				GLOBAL_GUI_SCREEN,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY, GlobalGetProperty },
	{ 0 }
};


static JSBool GlobalLog(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool GlobalLogWithClass(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval);


static JSFunctionSpec Global_funcs[] =
{
	{ "Log", GlobalLog, 1, 0 },
	{ "LogWithClass", GlobalLogWithClass, 2, 0 },
	{ 0 }
};


static JSBool GlobalLog(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	NSString *logString = [NSString concatenationOfStringsFromJavaScriptValues:argv count:argc separator:@", " inContext:context];
	OOLog(kOOLogDebugMessage, logString);
	return JS_TRUE;
}


static JSBool GlobalLogWithClass(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	NSString *logString = [NSString concatenationOfStringsFromJavaScriptValues:argv + 1 count:argc - 1 separator:@", " inContext:context];
	OOLog([NSString stringWithJavaScriptValue:argv[0] inContext:context], logString);
	return JS_TRUE;
}


static JSBool GlobalGetProperty(JSContext *context, JSObject *obj, jsval name, jsval *vp)
{
	if (!JSVAL_IS_INT(name)) return JS_TRUE;
	
	PlayerEntity				*player = OPlayerForScripting();
	id							result = nil;
	
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

		case GLOBAL_MISSION_VARS:
		{
			JSObject *mv = JS_DefineObject(context, xglob, "missionVariables", &MissionVars_class, 0x00, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
			*vp = OBJECT_TO_JSVAL(mv);
			break;
		}
		
		default:
			OOReportJavaScriptBadPropertySelector(context, @"Global", JSVAL_TO_INT(name));
			return NO;
	}
	
	if (result != nil) *vp = [result javaScriptValueInContext:context];
	return JS_TRUE;
}


//===========================================================================
// Universe (solar system) proxy
//===========================================================================

static JSBool SystemGetProperty(JSContext *context, JSObject *obj, jsval name, jsval *vp);
static JSBool SystemSetProperty(JSContext *context, JSObject *obj, jsval name, jsval *vp);

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


static JSBool SystemAddPlanet(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemAddMoon(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemSendAllShipsAway(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemSetSunNova(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemCountShipsWithRole(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemAddShips(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemAddSystemShips(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemAddShipsAt(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemAddShipsAtPrecisely(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemAddShipsWithinRadius(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemSpawn(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool SystemSpawnShip(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval);


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


static JSBool SystemAddPlanet(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity *player = OPlayerForScripting();
	
	if (argc > 0 && JSVAL_IS_STRING(argv[0]))
	{
		NSString *key = JSValToNSString(context, argv[0]);
		[player addPlanet:key];
	}
	return JS_TRUE;
}


static JSBool SystemAddMoon(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity *player = OPlayerForScripting();
	
	if (argc > 0 && JSVAL_IS_STRING(argv[0]))
	{
		NSString *key = JSValToNSString(context, argv[0]);
		[player addMoon:key];
	}
	return JS_TRUE;
}


static JSBool SystemSendAllShipsAway(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity *player = OPlayerForScripting();
	
	[player sendAllShipsAway];
	
	return JS_TRUE;
}


static JSBool SystemSetSunNova(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity *player = OPlayerForScripting();
	
	if (argc > 0)
	 {
		NSString *key = JSValToNSString(context, argv[0]);
		[player setSunNovaIn:key];
	}
	return JS_TRUE;
}


static Random_Seed currentSystem;
static NSDictionary *planetinfo = nil;

static JSBool SystemGetProperty(JSContext *context, JSObject *obj, jsval name, jsval *vp)
{
	if (!JSVAL_IS_INT(name))  return JS_TRUE;

	PlayerEntity				*player = OPlayerForScripting();
	id							result = nil;
	
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
		
		default:
			OOReportJavaScriptBadPropertySelector(context, @"System", JSVAL_TO_INT(name));
			return NO;
	}
	
	if (result != nil)  *vp = [result javaScriptValueInContext:context];
	return JS_TRUE;
}


static JSBool SystemSetProperty(JSContext *context, JSObject *obj, jsval name, jsval *vp)
{
	if (!JSVAL_IS_INT(name))  return JS_TRUE;
	
	PlayerEntity	*player = OPlayerForScripting();
	
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
			[UNIVERSE setSystemDataForGalaxy:gn planet:pn key:KEY_NAME value:JSValToNSString(context, *vp)];
			break;

			case SYS_DESCRIPTION:
			[UNIVERSE setSystemDataForGalaxy:gn planet:pn key:KEY_DESCRIPTION value:JSValToNSString(context, *vp)];
			break;

		case SYS_INHABITANTS:
			[UNIVERSE setSystemDataForGalaxy:gn planet:pn key:KEY_INHABITANTS value:JSValToNSString(context, *vp)];
			break;

		case SYS_GOING_NOVA:
			*vp = BOOLToJSVal([[UNIVERSE sun] willGoNova]);
			break;

		case SYS_GONE_NOVA:
			*vp = BOOLToJSVal([[UNIVERSE sun] goneNova]);
			break;

		case SYS_GOVT_ID:
			[UNIVERSE setSystemDataForGalaxy:gn planet:pn key:KEY_GOVERNMENT value:[NSNumber numberWithInt:[JSValToNSString(context, *vp) intValue]]];
			break;

		case SYS_ECONOMY_ID:
			[UNIVERSE setSystemDataForGalaxy:gn planet:pn key:KEY_ECONOMY value:[NSNumber numberWithInt:[JSValToNSString(context, *vp) intValue]]];
			break;

		case SYS_TECH_LVL:
			[UNIVERSE setSystemDataForGalaxy:gn planet:pn key:KEY_TECHLEVEL value:[NSNumber numberWithInt:[JSValToNSString(context, *vp) intValue]]];
			break;

		case SYS_POPULATION:
			[UNIVERSE setSystemDataForGalaxy:gn planet:pn key:KEY_POPULATION value:[NSNumber numberWithInt:[JSValToNSString(context, *vp) intValue]]];
			break;

		case SYS_PRODUCTIVITY:
			[UNIVERSE setSystemDataForGalaxy:gn planet:pn key:KEY_PRODUCTIVITY value:[NSNumber numberWithInt:[JSValToNSString(context, *vp) intValue]]];
			break;
		
		default:
			OOReportJavaScriptBadPropertySelector(context, @"System", JSVAL_TO_INT(name));
			return NO;
	}
	return JS_TRUE;
}


static JSBool SystemCountShipsWithRole(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	NSString			*role = nil;
	int					count;
	
	if (argc == 1)
	{
		role = JSValToNSString(context, argv[0]);
		count = [UNIVERSE countShipsWithRole:role];
		*rval = INT_TO_JSVAL(count);
	}
	return JS_TRUE;
}


static JSBool SystemAddShips(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	NSString			*role = nil;
	int					count;
	
	if (argc == 2)
	{
		role = JSValToNSString(context, argv[0]);
		count = JSVAL_TO_INT(argv[1]);

		while (count--)  [UNIVERSE witchspaceShipWithRole:role];
	}
	return JS_TRUE;
}


static JSBool SystemAddSystemShips(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	jsdouble			position;
	NSString			*role = nil;
	int					count;
	
	if (argc == 3)
	{
		role = JSValToNSString(context, argv[0]);
		count = JSVAL_TO_INT(argv[1]);
		
		JS_ValueToNumber(context, argv[2], &position);
		while (count--)  [UNIVERSE addShipWithRole:role nearRouteOneAt:position];
	}
	return JS_TRUE;
}


static JSBool SystemAddShipsAt(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OPlayerForScripting();
	jsdouble			x, y, z;
	NSString			*role = nil;
	int					count;
	NSString			*coordScheme = nil;
	NSString			*arg = nil;
	
	if (argc == 6)
	{
		role = JSValToNSString(context, argv[0]);
		count = JSVAL_TO_INT(argv[1]);
		coordScheme = JSValToNSString(context, argv[2]);
		
		JS_ValueToNumber(context, argv[3], &x);
		JS_ValueToNumber(context, argv[4], &y);
		JS_ValueToNumber(context, argv[5], &z);
		
		arg = [NSString stringWithFormat:@"%@ %d %@ %f %f %f", role, count, coordScheme, x, y, z];
		[player addShipsAt:arg];
	}
	return JS_TRUE;
}


static JSBool SystemAddShipsAtPrecisely(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OPlayerForScripting();
	jsdouble			x, y, z;
	NSString			*role = nil;
	int					count;
	NSString			*coordScheme = nil;
	NSString			*arg = nil;
	
	if (argc == 6)
	{
		role = JSValToNSString(context, argv[0]);
		count = JSVAL_TO_INT(argv[1]);
		coordScheme = JSValToNSString(context, argv[2]);
		
		JS_ValueToNumber(context, argv[3], &x);
		JS_ValueToNumber(context, argv[4], &y);
		JS_ValueToNumber(context, argv[5], &z);
		
		arg = [NSString stringWithFormat:@"%@ %d %@ %f %f %f", role, count, coordScheme, x, y, z];
		[player addShipsAtPrecisely:arg];
	}
	return JS_TRUE;
}


static JSBool SystemAddShipsWithinRadius(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OPlayerForScripting();
	jsdouble			x, y, z, radius;
	NSString			*role = nil;
	int					count;
	NSString			*coordScheme = nil;
	NSString			*arg = nil;
	
	if (argc == 7)
	{
		role = JSValToNSString(context, argv[0]);
		count = JSVAL_TO_INT(argv[1]);
		coordScheme = JSValToNSString(context, argv[2]);
		
		JS_ValueToNumber(context, argv[3], &x);
		JS_ValueToNumber(context, argv[4], &y);
		JS_ValueToNumber(context, argv[5], &z);
		JS_ValueToNumber(context, argv[6], &radius);
		
		arg = [NSString stringWithFormat:@"%@ %d %@ %f %f %f %d", role, count, coordScheme, x, y, z, radius];
		[player addShipsWithinRadius:arg];
	}
	return JS_TRUE;
}


static JSBool SystemSpawn(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OPlayerForScripting();
	NSString			*role = nil;
	int					count;
	NSString			*arg = nil;
	
	if (argc == 2)
	{
		role = JSValToNSString(context, argv[0]);
		count = JSVAL_TO_INT(argv[1]);
		
		arg = [NSString stringWithFormat:@"%@ %d", role, count];
		[player spawn:arg];
	}
	return JS_TRUE;
}


static JSBool SystemSpawnShip(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OPlayerForScripting();
	
	if (argc == 1)
	{
		[player spawnShip:JSValToNSString(context, argv[0])];
	}
	return JS_TRUE;
}


//===========================================================================
// Mission class
//===========================================================================

static JSBool MissionGetProperty(JSContext *context, JSObject *obj, jsval name, jsval *vp);
static JSBool MissionSetProperty(JSContext *context, JSObject *obj, jsval name, jsval *vp);


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


static JSBool MissionShowMissionScreen(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool MissionShowShipModel(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool MissionResetMissionChoice(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool MissionMarkSystem(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool MissionUnmarkSystem(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval);


static JSFunctionSpec Mission_funcs[] =
{
	{ "showMissionScreen", MissionShowMissionScreen, 0, 0 },
	{ "showShipModel", MissionShowShipModel, 1, 0 },
	{ "resetMissionChoice", MissionResetMissionChoice, 0, 0 },
	{ "markSystem", MissionMarkSystem, 1, 0 },
	{ "unmarkSystem", MissionUnmarkSystem, 1, 0 },
	{ 0 }
};


static JSBool MissionGetProperty(JSContext *context, JSObject *obj, jsval name, jsval *vp)
{
	if (!JSVAL_IS_INT(name))  return JS_TRUE;

	PlayerEntity				*player = OPlayerForScripting();
	id							result = nil;

	switch (JSVAL_TO_INT(name))
	{
		case MISSION_CHOICE:
			result = [player missionChoice_string];
			if (result == nil) result = @"None";
			break;
		
		default:
			OOReportJavaScriptBadPropertySelector(context, @"Mission", JSVAL_TO_INT(name));
			return NO;
	}
	
	if (result != nil) *vp = [result javaScriptValueInContext:context];
	return JS_TRUE;
}


static JSBool MissionSetProperty(JSContext *context, JSObject *obj, jsval name, jsval *vp)
{
	if (!JSVAL_IS_INT(name))  return JS_TRUE;

	PlayerEntity				*player = OPlayerForScripting();

	switch (JSVAL_TO_INT(name))
	{
		case MISSION_TEXT:
			if (JSVAL_IS_STRING(*vp))
			{
				JSString *jskey = JS_ValueToString(context, *vp);
				[player addMissionText: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
			}
			break;
		
		case MISSION_MUSIC:
			if (JSVAL_IS_STRING(*vp))
			{
				JSString *jskey = JS_ValueToString(context, *vp);
				[player setMissionMusic: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
			}
			break;
		
		case MISSION_IMAGE:
			if (JSVAL_IS_STRING(*vp))
			{
				NSString *str = JSValToNSString(context, *vp);
				if ([str length] == 0)
					str = @"none";
				[player setMissionImage:str];
			}
			break;
		
		case MISSION_CHOICES:
			if (JSVAL_IS_STRING(*vp))
			{
				JSString *jskey = JS_ValueToString(context, *vp);
				[player setMissionChoices: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
			}
			break;
		
		case MISSION_INSTRUCTIONS:
		
			if (JSVAL_IS_STRING(*vp))
			{
				JSString *jskey = JS_ValueToString(context, *vp);
				NSString *ins = [NSString stringWithCString:JS_GetStringBytes(jskey)];
				if ([ins length])
					[player setMissionDescription:ins forMission:[currentOOJSScript name]];
				else
					[player clearMissionDescriptionForMission:[currentOOJSScript name]];
			}
			break;
		
		default:
			OOReportJavaScriptBadPropertySelector(context, @"Mission", JSVAL_TO_INT(name));
			return NO;
	}
	return JS_TRUE;
}


static JSBool MissionShowMissionScreen(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OPlayerForScripting();
	
	[player setGuiToMissionScreen];
	
	return JS_TRUE;
}


static JSBool MissionShowShipModel(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OPlayerForScripting();
	JSString			*jskey = NULL;
	
	if (argc > 0 && JSVAL_IS_STRING(argv[0]))
	{
		jskey = JS_ValueToString(context, argv[0]);
		[player showShipModel: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
	}
	return JS_TRUE;
}


static JSBool MissionResetMissionChoice(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OPlayerForScripting();
	
	[player resetMissionChoice];
	
	return JS_TRUE;
}


static JSBool MissionMarkSystem(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OPlayerForScripting();
	NSString			*params = nil;
	
	params = [NSString concatenationOfStringsFromJavaScriptValues:argv count:argc separator:@" " inContext:context];
	[player addMissionDestination:params];
	
	return JS_TRUE;
}


static JSBool MissionUnmarkSystem(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OPlayerForScripting();
	NSString			*params = nil;
	
	player = [NSString concatenationOfStringsFromJavaScriptValues:argv count:argc separator:@" " inContext:context];
	[player removeMissionDestination:params];
	
	return JS_TRUE;
}


static void ReportJSError(JSContext *context, const char *message, JSErrorReport *report)
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

	/* initialize the JS run time, and return result in runtime */
	runtime = JS_NewRuntime(8L * 1024L * 1024L);

	/* if runtime does not have a value, end the program here */
	if (!runtime)
	{
		OOLog(@"script.javaScript.init.error", @"FATAL ERROR: failed to create JavaScript %@.", @"runtime");
		exit(1);
	}

	/* create a context and associate it with the JS run time */
	context = JS_NewContext(runtime, 8192);
	JS_SetOptions(context, JSOPTION_VAROBJFIX | JSOPTION_STRICT | JSOPTION_NATIVE_BRANCH_CALLBACK);
	
	/* if context does not have a value, end the program here */
	if (!context)
	{
		OOLog(@"script.javaScript.init.error", @"FATAL ERROR: failed to create JavaScript %@.", @"context");
		exit(1);
	}

	JS_SetErrorReporter(context, ReportJSError);

	/* create the global object here */
	globalObject = JS_NewObject(context, &global_class, NULL, NULL);
	xglob = globalObject;

	/* initialize the built-in JS objects and the global object */
	JS_InitStandardClasses(context, globalObject);
	JS_DefineProperties(context, globalObject, Global_props);
	JS_DefineFunctions(context, globalObject, Global_funcs);

	systemObj = JS_DefineObject(context, globalObject, "system", &System_class, NULL, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
	JS_DefineProperties(context, systemObj, System_props);
	JS_DefineFunctions(context, systemObj, System_funcs);

	missionObj = JS_DefineObject(context, globalObject, "mission", &Mission_class, NULL, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
	JS_DefineProperties(context, missionObj, Mission_props);
	JS_DefineFunctions(context, missionObj, Mission_funcs);
	
	InitOOJSVector(context, globalObject);
	InitOOJSQuaternion(context, globalObject);
	InitOOJSEntity(context, globalObject);
	InitOOJSShip(context, globalObject);
	InitOOJSStation(context, globalObject);
	InitOOJSPlayer(context, globalObject);
	
	OOLog(@"script.javaScript.init.success", @"Set up JavaScript context.");
	
	sSharedEngine = self;
	return self;
}


- (void) dealloc
{
	sSharedEngine = nil;
	
	JS_DestroyContext(context);
	JS_DestroyRuntime(runtime);
	
	[super dealloc];
}


- (JSContext *) context
{
	return context;
}

@end


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
	JS_ReportError(context, "%s", [msg UTF8String]);
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


void OOReportJavaScriptBadPropertySelector(JSContext *context, NSString *className, jsint selector)
{
	OOReportJavaScriptError(context, @"Internal error: bad property identifier %i in property accessor for class %@.", selector, className);
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


@implementation NSObject (OOJavaScriptConversion)

- (jsval)javaScriptValueInContext:(JSContext *)context
{
	return JSVAL_NULL;
}

@end


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


@implementation NSArray (OOJavaScriptConversion)

- (jsval)javaScriptValueInContext:(JSContext *)context
{
	return OBJECT_TO_JSVAL(JSArrayFromNSArray(context, self));
}

@end


@implementation NSNumber (OOJavaScriptConversion)

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


@implementation NSNull (OOJavaScriptConversion)

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
