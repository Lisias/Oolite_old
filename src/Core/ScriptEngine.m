/*
 *
 *  Oolite
 *
 *  Created by Giles Williams on Sat Apr 03 2004.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

This file copyright (c) 2007, David Taylor
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

�	to copy, distribute, display, and perform the work
�	to make derivative works

Under the following conditions:

�	Attribution. You must give the original author credit.

�	Noncommercial. You may not use this work for commercial purposes.

�	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

/*
 * This file contains the core JavaSCript interfacing code.
 */

#import "ScriptEngine.h"
#import "OXPScript.h"

#include <stdio.h>
#include <string.h>

Universe *scriptedUniverse;
JSObject *xglob, *universeObj, *systemObj, *playerObj, *missionObj;

extern OXPScript *currentOXPScript;

NSString *JSValToNSString(JSContext *cx, jsval val) {
	JSString *str = JS_ValueToString(cx, val);
	char *chars = JS_GetStringBytes(str);
	return [NSString stringWithCString:chars];
}

JSBool GlobalGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp);

JSClass global_class = {
	"Oolite",0,
	JS_PropertyStub,JS_PropertyStub,JS_PropertyStub,JS_PropertyStub,
	JS_EnumerateStub,JS_ResolveStub,JS_ConvertStub,JS_FinalizeStub
};

enum global_propertyIds {
	GLOBAL_GALAXY_NUMBER, GLOBAL_PLANET_NUMBER, GLOBAL_DOCKED_AT_MAIN_STATION, GLOBAL_DOCKED_STATION_NAME, GLOBAL_MISSION_VARS,
	GLOBAL_GUI_SCREEN, GLOBAL_STATUS_STRING
};

JSPropertySpec Global_props[] = {
	{ "GalaxyNumber", GLOBAL_GALAXY_NUMBER, JSPROP_ENUMERATE, GlobalGetProperty },
	{ "PlanetNumber", GLOBAL_PLANET_NUMBER, JSPROP_ENUMERATE, GlobalGetProperty },
	{ "DockedAtMainStation", GLOBAL_DOCKED_AT_MAIN_STATION, JSPROP_ENUMERATE, GlobalGetProperty },
	{ "StationName", GLOBAL_DOCKED_STATION_NAME, JSPROP_ENUMERATE, GlobalGetProperty },
	{ "MissionVars", GLOBAL_MISSION_VARS, JSPROP_ENUMERATE, GlobalGetProperty },
	{ "GUIScreen", GLOBAL_GUI_SCREEN, JSPROP_ENUMERATE, GlobalGetProperty },
	{ "StatusString", GLOBAL_STATUS_STRING, JSPROP_ENUMERATE, GlobalGetProperty },
	{ 0 }
};

JSBool GlobalShowStatusScreen(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);

JSFunctionSpec Global_funcs[] = {
	{ "ShowStatusScreen", GlobalShowStatusScreen, 0, 0 },
	{ 0 }
};

JSBool GlobalShowStatusScreen(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	[playerEntity setGuiToStatusScreen];
}

JSBool GlobalGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp) {
	if (JSVAL_IS_INT(id)) {
		PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];

		switch (JSVAL_TO_INT(id)) {
			case GLOBAL_GALAXY_NUMBER: {
				NSNumber *gn = [playerEntity galaxy_number];
				*vp = INT_TO_JSVAL([gn intValue]);
				break;
			}

			case GLOBAL_PLANET_NUMBER: {
				*vp = INT_TO_JSVAL([[playerEntity planet_number] intValue]);
				break;
			}

			case GLOBAL_DOCKED_AT_MAIN_STATION: {
				BOOL b = [[playerEntity dockedAtMainStation_bool] isEqualToString:@"YES"];
				if (b == YES)
					*vp = BOOLEAN_TO_JSVAL(1);
				else
					*vp = BOOLEAN_TO_JSVAL(0);
				break;
			}

			case GLOBAL_DOCKED_STATION_NAME: {
				NSString *name = [playerEntity dockedStationName_string];
				const char *name_str = [name cString];
				JSString *js_name = JS_NewStringCopyZ(cx, name_str);
				*vp = STRING_TO_JSVAL(js_name);
				break;
			}

			case GLOBAL_GUI_SCREEN: {
				NSString *name = [playerEntity gui_screen_string];
				const char *name_str = [name cString];
				JSString *js_name = JS_NewStringCopyZ(cx, name_str);
				*vp = STRING_TO_JSVAL(js_name);
				break;
			}

			case GLOBAL_STATUS_STRING: {
				NSString *name = [playerEntity status_string];
				const char *name_str = [name cString];
				JSString *js_name = JS_NewStringCopyZ(cx, name_str);
				*vp = STRING_TO_JSVAL(js_name);
				break;
			}

			case GLOBAL_MISSION_VARS: {
				fprintf(stdout, "Creating MissionVars array\r\n");
				JSObject *mv = JS_DefineObject(cx, xglob, "MissionVars", &global_class, 0x00, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
				*vp = OBJECT_TO_JSVAL(mv);
				break;
			}
		}
	}

	return JS_TRUE;
}

//===========================================================================
// Universe proxy
//===========================================================================

JSBool UniverseGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp);

JSClass Universe_class = {
	"Universe", JSCLASS_HAS_PRIVATE,
	JS_PropertyStub,JS_PropertyStub,JS_PropertyStub,JS_PropertyStub,
	JS_EnumerateStub,JS_ResolveStub,JS_ConvertStub,JS_FinalizeStub
};

/*
enum Universe_propertyIds {
	UNI_PLAYER_ENTITY
};

JSPropertySpec Universe_props[] = {
	{ "PlayerEntity", UNI_PLAYER_ENTITY, JSPROP_ENUMERATE },
	{ 0 }
};
*/

JSBool UniverseLog(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool UniverseAddMessage(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool UniverseAddCommsMessage(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);

JSFunctionSpec Universe_funcs[] = {
	{ "AddMessage", UniverseAddMessage, 2, 0 },
	{ "AddCommsMessage", UniverseAddMessage, 2, 0 },
	{ "Log", UniverseLog, 1, 0 },
	{ 0 }
};

JSBool UniverseLog(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	JSString *str;
	str = JS_ValueToString(cx, argv[0]);
	fprintf(stdout, "LOG: %s\r\n", JS_GetStringBytes(str));
	return JS_TRUE;
}

JSBool UniverseAddMessage(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	JSBool ok;
	int32 count;
	if (argc != 2)
		return JS_FALSE;

	ok = JS_ValueToInt32(cx, argv[1], &count);
	NSString *str = JSValToNSString(cx, argv[0]);
	[scriptedUniverse addMessage: str forCount:(int)count];
	//[str dealloc];
	return JS_TRUE;
}

JSBool UniverseAddCommsMessage(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	JSBool ok;
	int32 count;
	if (argc != 2)
		return JS_FALSE;

	ok = JS_ValueToInt32(cx, argv[1], &count);
	NSString *str = JSValToNSString(cx, argv[0]);
	[scriptedUniverse addCommsMessage: str forCount:(int)count];
	//[str dealloc];
	return JS_TRUE;
}
/*
JSBool UniverseGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp) {
	if (JSVAL_IS_INT(id)) {
		PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];

		switch (JSVAL_TO_INT(id)) {
			case UNI_PLAYER_ENTITY: {
				JSObject *pe = JS_DefineObject(cx, universeObj, "PlayerEntity", &PlayerEntity_class, 0x00, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
				if (pe == 0x00) {
					return JS_FALSE;
				}
				JS_DefineProperties(cx, pe, playerEntity_props);

				*vp = OBJECT_TO_JSVAL(pe);
				break;
			}
		}
	}

	return JS_TRUE;
}
*/

//===========================================================================
// Player proxy
//===========================================================================

JSBool PlayerGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp);
JSBool PlayerSetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp);

JSClass Player_class = {
	"Player", JSCLASS_HAS_PRIVATE,
	JS_PropertyStub,JS_PropertyStub,PlayerGetProperty,PlayerSetProperty,
	JS_EnumerateStub,JS_ResolveStub,JS_ConvertStub,JS_FinalizeStub
};

enum Player_propertyIds {
	PE_SHIP_DESCRIPTION, PE_COMMANDER_NAME, PE_SCORE, PE_CREDITS, PE_LEGAL_STATUS,
	PE_FUEL_LEVEL, PE_FUEL_LEAK_RATE
};

JSPropertySpec Player_props[] = {
	{ "ShipDescription", PE_SHIP_DESCRIPTION, JSPROP_ENUMERATE },
	{ "CommanderName", PE_COMMANDER_NAME, JSPROP_ENUMERATE },
	{ "Score", PE_SCORE, JSPROP_ENUMERATE },
	{ "Credits", PE_CREDITS, JSPROP_ENUMERATE },
	{ "LegalStatus", PE_LEGAL_STATUS, JSPROP_ENUMERATE },
	{ "Fuel", PE_FUEL_LEVEL, JSPROP_ENUMERATE },
	{ "FuelLeakRate", PE_FUEL_LEAK_RATE, JSPROP_ENUMERATE },
	{ 0 }
};

JSBool PlayerAwardEquipment(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool PlayerRemoveEquipment(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool PlayerHasEquipment(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool PlayerLaunch(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool PlayerCall(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);

JSFunctionSpec Player_funcs[] = {
	{ "AwardEquipment", PlayerAwardEquipment, 1, 0 },
	{ "RemoveEquipment", PlayerRemoveEquipment, 1, 0 },
	{ "HasEquipment", PlayerHasEquipment, 1, 0 },
	{ "Launch", PlayerLaunch, 0, 0 },
	{ "Call", PlayerCall, 2, 0 },
	{ 0 }
};

JSBool PlayerAwardEquipment(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	if (argc > 0 && JSVAL_IS_STRING(argv[0])) {
		JSString *jskey = JS_ValueToString(cx, argv[0]);
		[playerEntity awardEquipment: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
	}
	return JS_TRUE;
}

JSBool PlayerRemoveEquipment(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	if (argc > 0 && JSVAL_IS_STRING(argv[0])) {
		JSString *jskey = JS_ValueToString(cx, argv[0]);
		[playerEntity removeEquipment: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
	}
	return JS_TRUE;
}

JSBool PlayerHasEquipment(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	if (argc > 0 && JSVAL_IS_STRING(argv[0])) {
		JSString *jskey = JS_ValueToString(cx, argv[0]);
		BOOL b = [playerEntity has_extra_equipment: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
		if (b == YES)
			*rval = BOOLEAN_TO_JSVAL(1);
		else
			*rval = BOOLEAN_TO_JSVAL(0);
	}
	return JS_TRUE;
}

JSBool PlayerLaunch(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	[playerEntity launchFromStation];
	return JS_TRUE;
}

JSBool PlayerCall(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	if (argc > 0) {
		JSString *jskey = JS_ValueToString(cx, argv[0]);
		NSString *selectorString = [NSString stringWithCString:JS_GetStringBytes(jskey)];
		SEL _selector = NSSelectorFromString(selectorString);
		if ([playerEntity respondsToSelector:_selector]) {
			if (argc == 1)
				[playerEntity performSelector:_selector];
			else {
				JSString *jsparam = JS_ValueToString(cx, argv[1]);
				NSString *valueString = [NSString stringWithCString:JS_GetStringBytes(jsparam)];
				[playerEntity performSelector:_selector withObject:valueString];
			}
		}
	}

	return JS_TRUE;
}

JSBool PlayerGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp) {
	JSBool ok;
	jsdouble *dp;

	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];

	if (JSVAL_IS_INT(id)) {
		switch (JSVAL_TO_INT(id)) {
			case PE_SHIP_DESCRIPTION: {
				NSString *ship_desc = [playerEntity commanderShip_string];
				const char *ship_desc_str = [ship_desc cString];
				JSString *js_ship_desc = JS_NewStringCopyZ(cx, ship_desc_str);
				*vp = STRING_TO_JSVAL(js_ship_desc);
				break;
			}

			case PE_COMMANDER_NAME: {
				NSString *ship_desc = [playerEntity commanderName_string];
				const char *ship_desc_str = [ship_desc cString];
				JSString *js_ship_desc = JS_NewStringCopyZ(cx, ship_desc_str);
				*vp = STRING_TO_JSVAL(js_ship_desc);
				break;
			}

			case PE_SCORE: {
				jsdouble ds = [[playerEntity score_number] doubleValue];
				dp = JS_NewDouble(cx, ds);
				ok = (dp != 0x00);
				if (ok)
					*vp = DOUBLE_TO_JSVAL(dp);
				break;
			}

			case PE_LEGAL_STATUS: {
				jsdouble ds = [[playerEntity legalStatus_number] doubleValue];
				dp = JS_NewDouble(cx, ds);
				ok = (dp != 0x00);
				if (ok)
					*vp = DOUBLE_TO_JSVAL(dp);
				break;
			}

			case PE_CREDITS: {
				jsdouble ds = [[playerEntity credits_number] doubleValue];
				dp = JS_NewDouble(cx, ds);
				ok = (dp != 0x00);
				if (ok)
					*vp = DOUBLE_TO_JSVAL(dp);
				break;
			}

			case PE_FUEL_LEVEL: {
				jsdouble ds = [[playerEntity fuel_level_number] doubleValue];
				dp = JS_NewDouble(cx, ds);
				ok = (dp != 0x00);
				if (ok)
					*vp = DOUBLE_TO_JSVAL(dp);
				break;
			}
			case PE_FUEL_LEAK_RATE: {
				jsdouble ds = [[playerEntity fuel_leak_rate_number] doubleValue];
				dp = JS_NewDouble(cx, ds);
				ok = (dp != 0x00);
				if (ok)
					*vp = DOUBLE_TO_JSVAL(dp);
				break;
			}
		}
	}
	return JS_TRUE;
}

JSBool PlayerSetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp) {
	JSBool ok;
	jsdouble *dp;

	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];

	if (JSVAL_IS_INT(id)) {
		switch (JSVAL_TO_INT(id)) {
			case PE_CREDITS: {
				jsdouble d;
				ok = JS_ValueToNumber(cx, *vp, &d);
				fprintf(stdout, "set credits (double) = %f\r\n", d);
				float fs = [[playerEntity credits_number] floatValue];
				double ds = (double)fs;
				double diff = d - ds;
				fprintf(stdout, "diff is (double) = %f\r\n", diff);
				[playerEntity awardCredits: [[NSNumber numberWithDouble:diff] stringValue]];
				break;
			}
		}
	}
	return JS_TRUE;
}

//===========================================================================
// System (solar system) proxy
//===========================================================================

JSBool SystemGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp);

JSClass System_class = {
	"System", JSCLASS_HAS_PRIVATE,
	JS_PropertyStub,JS_PropertyStub,SystemGetProperty,JS_PropertyStub,
	JS_EnumerateStub,JS_ResolveStub,JS_ConvertStub,JS_FinalizeStub
};

enum System_propertyIds {
	SYS_ID, SYS_NAME, SYS_DESCRIPTION, SYS_GOING_NOVA, SYS_GONE_NOVA, SYS_GOVT_STR, SYS_GOVT_ID, SYS_ECONOMY_ID,
	SYS_TECH_LVL, SYS_POPULATION, SYS_PRODUCTIVITY, SYS_INHABITANTS
};

JSPropertySpec System_props[] = {
	{ "Id", SYS_ID, JSPROP_ENUMERATE },
	{ "Name", SYS_NAME, JSPROP_ENUMERATE },
	{ "Description", SYS_DESCRIPTION, JSPROP_ENUMERATE },
	{ "InhabitantsDescription", SYS_INHABITANTS, JSPROP_ENUMERATE },
	{ "GoingNova", SYS_GOING_NOVA, JSPROP_ENUMERATE },
	{ "GoneNova", SYS_GONE_NOVA, JSPROP_ENUMERATE },
	{ "GovernmentDescription", SYS_GOVT_STR, JSPROP_ENUMERATE },
	{ "GovernmentId", SYS_GOVT_ID, JSPROP_ENUMERATE },
	{ "EconomyId", SYS_ECONOMY_ID, JSPROP_ENUMERATE },
	{ "TechLevel", SYS_TECH_LVL, JSPROP_ENUMERATE },
	{ "Population", SYS_POPULATION, JSPROP_ENUMERATE },
	{ "Productivity", SYS_PRODUCTIVITY, JSPROP_ENUMERATE },
	{ 0 }
};

static Random_Seed currentSystem;
static NSDictionary *planetinfo = nil;

JSBool SystemGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp) {
	JSBool ok;
	jsdouble *dp;

	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	if ( !equal_seeds(currentSystem, playerEntity->system_seed)) {
		fprintf(stdout, "Current system has changed, regenerating local copy of planetinfo\r\n");
		currentSystem = playerEntity->system_seed;
		if (planetinfo)
			[planetinfo release];

		planetinfo = [[scriptedUniverse generateSystemData:currentSystem] retain];
	}

	if (JSVAL_IS_INT(id)) {
		switch (JSVAL_TO_INT(id)) {
			case SYS_ID: {
				*vp = INT_TO_JSVAL([[playerEntity planet_number] intValue]);
				break;
			}

			case SYS_NAME: {
				NSString *ship_desc = (NSString *)[planetinfo objectForKey:KEY_NAME];
				if (!ship_desc) {
					ship_desc = @"None";
				}
				const char *ship_desc_str = [ship_desc cString];
				JSString *js_ship_desc = JS_NewStringCopyZ(cx, ship_desc_str);
				*vp = STRING_TO_JSVAL(js_ship_desc);
				break;
			}

			case SYS_DESCRIPTION: {
				NSString *ship_desc = (NSString *)[planetinfo objectForKey:KEY_DESCRIPTION];
				if (!ship_desc) {
					ship_desc = @"None";
				}
				const char *ship_desc_str = [ship_desc cString];
				JSString *js_ship_desc = JS_NewStringCopyZ(cx, ship_desc_str);
				*vp = STRING_TO_JSVAL(js_ship_desc);
				break;
			}

			case SYS_INHABITANTS: {
				NSString *ship_desc = (NSString *)[planetinfo objectForKey:KEY_INHABITANTS];
				if (!ship_desc) {
					ship_desc = @"None";
				}
				const char *ship_desc_str = [ship_desc cString];
				JSString *js_ship_desc = JS_NewStringCopyZ(cx, ship_desc_str);
				*vp = STRING_TO_JSVAL(js_ship_desc);
				break;
			}

			case SYS_GOING_NOVA: {
				BOOL b = [[playerEntity sunWillGoNova_bool] isEqualToString:@"YES"];
				if (b == YES)
					*vp = BOOLEAN_TO_JSVAL(1);
				else
					*vp = BOOLEAN_TO_JSVAL(0);
				break;
			}

			case SYS_GONE_NOVA: {
				BOOL b = [[playerEntity sunGoneNova_bool] isEqualToString:@"YES"];
				if (b == YES)
					*vp = BOOLEAN_TO_JSVAL(1);
				else
					*vp = BOOLEAN_TO_JSVAL(0);
				break;
			}

			case SYS_GOVT_STR: {
				NSString *ship_desc = [playerEntity systemGovernment_string];
				const char *ship_desc_str = [ship_desc cString];
				JSString *js_ship_desc = JS_NewStringCopyZ(cx, ship_desc_str);
				*vp = STRING_TO_JSVAL(js_ship_desc);
				break;
			}

			case SYS_GOVT_ID: {
				double fs = (double)[[playerEntity systemGovernment_number] doubleValue];
				dp = JS_NewDouble(cx, fs);
				ok = (dp != 0x00);
				if (ok)
					*vp = DOUBLE_TO_JSVAL(dp);
				break;
			}

			case SYS_ECONOMY_ID: {
				double fs = (double)[[playerEntity systemEconomy_number] doubleValue];
				dp = JS_NewDouble(cx, fs);
				ok = (dp != 0x00);
				if (ok)
					*vp = DOUBLE_TO_JSVAL(dp);
				break;
			}

			case SYS_TECH_LVL: {
				double fs = (double)[[playerEntity systemTechLevel_number] doubleValue];
				dp = JS_NewDouble(cx, fs);
				ok = (dp != 0x00);
				if (ok)
					*vp = DOUBLE_TO_JSVAL(dp);
				break;
			}

			case SYS_POPULATION: {
				double fs = (double)[[playerEntity systemPopulation_number] doubleValue];
				dp = JS_NewDouble(cx, fs);
				ok = (dp != 0x00);
				if (ok)
					*vp = DOUBLE_TO_JSVAL(dp);
				break;
			}

			case SYS_PRODUCTIVITY: {
				double fs = (double)[[playerEntity systemProductivity_number] doubleValue];
				dp = JS_NewDouble(cx, fs);
				ok = (dp != 0x00);
				if (ok)
					*vp = DOUBLE_TO_JSVAL(dp);
				break;
			}
		}
	}
	return JS_TRUE;
}

//===========================================================================
// Mission class
//===========================================================================

JSBool MissionGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp);
JSBool MissionSetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp);

JSClass Mission_class = {
	"Mission", JSCLASS_HAS_PRIVATE,
	JS_PropertyStub,JS_PropertyStub,MissionGetProperty,MissionSetProperty,
	JS_EnumerateStub,JS_ResolveStub,JS_ConvertStub,JS_FinalizeStub
};

enum Mission_propertyIds {
	MISSION_TEXT, MISSION_MUSIC, MISSION_IMAGE, MISSION_CHOICES, MISSION_CHOICE, MISSION_INSTRUCTIONS
};

JSPropertySpec Mission_props[] = {
	{ "MissionScreenTextKey", MISSION_TEXT, JSPROP_ENUMERATE },
	{ "MusicFilename", MISSION_MUSIC, JSPROP_ENUMERATE },
	{ "ImageFilename", MISSION_IMAGE, JSPROP_ENUMERATE },
	{ "ChoicesKey", MISSION_CHOICES, JSPROP_ENUMERATE },
	{ "Choice", MISSION_CHOICE, JSPROP_ENUMERATE },
	{ "Instructions", MISSION_INSTRUCTIONS, JSPROP_ENUMERATE },
	{ 0 }
};

JSBool MissionShowMissionScreen(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool MissionShowShipModel(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool MissionResetMissionChoice(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool MissionMarkSystem(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool MissionUnmarkSystem(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);

JSFunctionSpec Mission_funcs[] = {
	{ "ShowMissionScreen", MissionShowMissionScreen, 0, 0 },
	{ "ShowShipModel", MissionShowShipModel, 1, 0 },
	{ "ResetMissionChoice", MissionResetMissionChoice, 0, 0 },
	{ "MarkSystem", MissionMarkSystem, 1, 0 },
	{ "UnmarkSystem", MissionUnmarkSystem, 1, 0 },
	{ 0 }
};

JSBool MissionGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp) {
	JSBool ok;
	jsdouble *dp;

	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];

	if (JSVAL_IS_INT(id)) {
		switch (JSVAL_TO_INT(id)) {
			case MISSION_CHOICE: {
				NSString *ship_desc = [playerEntity missionChoice_string];
				if (!ship_desc)
					ship_desc = @"";
				const char *ship_desc_str = [ship_desc cString];
				JSString *js_ship_desc = JS_NewStringCopyZ(cx, ship_desc_str);
				*vp = STRING_TO_JSVAL(js_ship_desc);
				break;
			}
		}
	}
	return JS_TRUE;
}

JSBool MissionSetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp) {
	JSBool ok;
	jsdouble *dp;

	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];

	if (JSVAL_IS_INT(id)) {
		switch (JSVAL_TO_INT(id)) {
			case MISSION_TEXT: {
				if (JSVAL_IS_STRING(*vp)) {
					JSString *jskey = JS_ValueToString(cx, *vp);
					[playerEntity addMissionText: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
				}
				break;
			}
			case MISSION_MUSIC: {
				if (JSVAL_IS_STRING(*vp)) {
					JSString *jskey = JS_ValueToString(cx, *vp);
					[playerEntity setMissionMusic: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
				}
				break;
			}
			case MISSION_IMAGE: {
				if (JSVAL_IS_STRING(*vp)) {
					JSString *jskey = JS_ValueToString(cx, *vp);
					[playerEntity setMissionImage: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
				}
				break;
			}
			case MISSION_CHOICES: {
				if (JSVAL_IS_STRING(*vp)) {
					JSString *jskey = JS_ValueToString(cx, *vp);
					[playerEntity setMissionChoices: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
				}
				break;
			}
			case MISSION_INSTRUCTIONS: {
				if (JSVAL_IS_STRING(*vp)) {
					JSString *jskey = JS_ValueToString(cx, *vp);
					NSString *ins = [NSString stringWithCString:JS_GetStringBytes(jskey)];
					if ([ins length])
						[playerEntity setMissionDescription:ins forMission:[currentOXPScript name]];
					else
						[playerEntity clearMissionDescriptionForMission:[currentOXPScript name]];
				}
				break;
			}
		}
	}
	return JS_TRUE;
}

JSBool MissionShowMissionScreen(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	[playerEntity setGuiToMissionScreen];
	return JS_TRUE;
}

JSBool MissionShowShipModel(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	if (argc > 0 && JSVAL_IS_STRING(argv[0])) {
		JSString *jskey = JS_ValueToString(cx, argv[0]);
		[playerEntity showShipModel: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
	}
	return JS_TRUE;
}

JSBool MissionResetMissionChoice(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	[playerEntity resetMissionChoice];
	return JS_TRUE;
}

JSBool MissionMarkSystem(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	return JS_TRUE;
}

JSBool MissionUnmarkSystem(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	return JS_TRUE;
}


@implementation ScriptEngine

//===========================================================================
// JavaScript engine initialisation and shutdown
//===========================================================================

- (id) initWithUniverse: (Universe *)universe
{
	self = [super init];
	scriptedUniverse = universe;

	/*set up global JS variables, including global and custom objects */

	/* initialize the JS run time, and return result in rt */
	rt = JS_NewRuntime(8L * 1024L * 1024L);

	/* if rt does not have a value, end the program here */
	if (!rt) {
		[super dealloc];
		exit(1); //return nil;
	}

	/* create a context and associate it with the JS run time */
	cx = JS_NewContext(rt, 8192);
	NSLog(@"created context");
	
	/* if cx does not have a value, end the program here */
	if (cx == NULL) {
		[super dealloc];
		exit(1); //return nil;
	}

	/* create the global object here */
	glob = JS_NewObject(cx, &global_class, NULL, NULL);
	xglob = glob;

	/* initialize the built-in JS objects and the global object */
	builtins = JS_InitStandardClasses(cx, glob);
	JS_DefineProperties(cx, glob, Global_props);
	JS_DefineFunctions(cx, glob, Global_funcs);

	universeObj = JS_DefineObject(cx, glob, "Universe", &Universe_class, NULL, JSPROP_ENUMERATE);
	//JS_DefineProperties(cx, universeObj, Universe_props);
	JS_DefineFunctions(cx, universeObj, Universe_funcs);

	systemObj = JS_DefineObject(cx, glob, "System", &System_class, NULL, JSPROP_ENUMERATE);
	JS_DefineProperties(cx, systemObj, System_props);

	playerObj = JS_DefineObject(cx, glob, "Player", &Player_class, NULL, JSPROP_ENUMERATE);
	JS_DefineProperties(cx, playerObj, Player_props);
	JS_DefineFunctions(cx, playerObj, Player_funcs);

	missionObj = JS_DefineObject(cx, glob, "Mission", &Mission_class, NULL, JSPROP_ENUMERATE);
	JS_DefineProperties(cx, missionObj, Mission_props);
	JS_DefineFunctions(cx, missionObj, Mission_funcs);
	
	return self;
}

- (void) dealloc
{
	// free up the OXPScripts too!

	JS_DestroyContext(cx);
	/* Before exiting the application, free the JS run time */
	JS_DestroyRuntime(rt);
	[super dealloc];
}

- (JSContext *) context
{
	return cx;
}

@end
