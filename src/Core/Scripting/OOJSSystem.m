/*
 
 OOJSSystem.m
 
 
 Oolite
 Copyright (C) 2004-2007 Giles C Williams and contributors
 
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

#import "OOJSSystem.h"
#import "OOJavaScriptEngine.h"

#import "OOJSVector.h"
#import "OOJSPlayer.h"
#import "Universe.h"
#import "PlanetEntity.h"
#import "PlayerEntityScriptMethods.h"

#import "OOCollectionExtractors.h"
#import "OOConstToString.h"


static JSObject *sSystemPrototype;

static Random_Seed sCurrentSystem;
static NSDictionary *sPlanetInfo;


static JSBool SystemGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool SystemSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);

static JSBool SystemToString(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemAddPlanet(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemAddMoon(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemSendAllShipsAway(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemSetSunNova(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemCountShipsWithRole(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemAddShips(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);

static JSBool SystemLegacyAddShips(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemLegacyAddSystemShips(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemLegacyAddShipsAt(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemLegacyAddShipsAtPrecisely(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemLegacyAddShipsWithinRadius(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemLegacySpawn(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemLegacySpawnShip(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


static JSClass sSystemClass =
{
	"System",
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


enum
{
	// Property IDs
	kSystem_ID,					// planet number, integer, read-only
	kSystem_name,				// name, string, read/write
	kSystem_description,		// description, string, read/write
	kSystem_inhabitantsDescription, // description of inhabitant species, string, read/write
	kSystem_goingNova,			// sun is going nova, boolean, read-only (should be moved to sun)
	kSystem_goneNova,			// sun has gone nova, boolean, read-only (should be moved to sun)
	kSystem_government,			// government ID, integer, read/write
	kSystem_governmentDescription,	// government ID description, string, read-only
	kSystem_economy,			// economy ID, integer, read/write
	kSystem_economyDescription,	// economy ID description, string, read-only
	kSystem_techLevel,			// tech level ID, integer, read/write
	kSystem_population,			// population, integer, read/write
	kSystem_productivity,		// productivity, integer, read/write
	kSystem_isInterstellarSpace, // is interstellar space, boolean, read-only
	kSystem_mainStation			// system's main station, Station, read-only
};


static JSPropertySpec sSystemProperties[] =
{
	// JS name					ID							flags
	{ "ID",						kSystem_ID,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "name",					kSystem_name,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "description",			kSystem_description,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "inhabitantsDescription",	kSystem_inhabitantsDescription, JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "goingNova",				kSystem_goingNova,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "goneNova",				kSystem_goneNova,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "government",				kSystem_government,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "governmentDescription",	kSystem_governmentDescription, JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "economy",				kSystem_economy,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "economyDescription",		kSystem_economyDescription,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "techLevel",				kSystem_techLevel,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "population",				kSystem_population,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "productivity",			kSystem_productivity,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "isInterstellarSpace",	kSystem_isInterstellarSpace, JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "mainStation",			kSystem_mainStation,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sSystemMethods[] =
{
	// JS name					Function					min args
	{ "toString",				SystemToString,				0 },
	{ "addPlanet",				SystemAddPlanet,			1 },
	{ "addMoon",				SystemAddMoon,				1 },
	{ "sendAllShipsAway",		SystemSendAllShipsAway,		1 },
	{ "setSunNova",				SystemSetSunNova,			1 },
	{ "countShipsWithRole",		SystemCountShipsWithRole,	1 },
	{ "addShips",				SystemAddShips,				3 },
	
	{ "legacy_addShips",		SystemLegacyAddShips,		2 },
	{ "legacy_addSystemShips",	SystemLegacyAddSystemShips,	3 },
	{ "legacy_addShipsAt",		SystemLegacyAddShipsAt,		6 },
	{ "legacy_addShipsAtPrecisely", SystemLegacyAddShipsAtPrecisely, 6 },
	{ "legacy_addShipsWithinRadius", SystemLegacyAddShipsWithinRadius, 7 },
	{ "legacy_spawn",			SystemLegacySpawn,			2 },
	{ "legacy_spawnShip",		SystemLegacySpawnShip,		1 },
	{ 0 }
};


void InitOOJSSystem(JSContext *context, JSObject *global)
{
    sSystemPrototype = JS_InitClass(context, global, NULL, &sSystemClass, NULL, 0, sSystemProperties, sSystemMethods, NULL, NULL);
	
	// Create system object as a property of the global object.
	JS_DefineObject(context, global, "system", &sSystemClass, sSystemPrototype, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
}


static JSBool SystemGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	id							result = nil;
	PlayerEntity				*player = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	
	player = OPlayerForScripting();
	if (!equal_seeds(sCurrentSystem, player->system_seed))
	{
		sCurrentSystem = player->system_seed;
		
		[sPlanetInfo release];
		sPlanetInfo = [[UNIVERSE generateSystemData:sCurrentSystem] retain];
	}
	
	switch (JSVAL_TO_INT(name))
	{
		case kSystem_ID:
			*outValue = INT_TO_JSVAL([player currentSystemID]);
			break;
		
		case kSystem_name:
			if ([UNIVERSE sun] != nil)
			{
				result = [sPlanetInfo objectForKey:KEY_NAME];
				if (result == nil)  result = [NSNull null];
			}
			else
			{
				result = @"Interstellar space";
			}
			break;
			
		case kSystem_description:
			result = [sPlanetInfo objectForKey:KEY_DESCRIPTION];
			if (result == nil)  result = [NSNull null];
			break;
			
		case kSystem_inhabitantsDescription:
			result = [sPlanetInfo objectForKey:KEY_INHABITANTS];
			if (result == nil)  result = [NSNull null];
			break;
		
		case kSystem_goingNova:
			*outValue = BOOLToJSVal([[UNIVERSE sun] willGoNova]);
			break;
		
		case kSystem_goneNova:
			*outValue = BOOLToJSVal([[UNIVERSE sun] goneNova]);
			break;
			
		case kSystem_government:
			*outValue = INT_TO_JSVAL([sPlanetInfo intForKey:KEY_GOVERNMENT]);
			break;
			
		case kSystem_governmentDescription:
			result = GovernmentToString([sPlanetInfo intForKey:KEY_GOVERNMENT]);
			if (result == nil)  result = [NSNull null];
			break;
			
		case kSystem_economy:
			*outValue = INT_TO_JSVAL([sPlanetInfo intForKey:KEY_ECONOMY]);
			break;
			
		case kSystem_economyDescription:
			result = EconomyToString([sPlanetInfo intForKey:KEY_ECONOMY]);
			if (result == nil)  result = [NSNull null];
			break;
		
		case kSystem_techLevel:
			*outValue = INT_TO_JSVAL([sPlanetInfo intForKey:KEY_TECHLEVEL]);
			break;
			
		case kSystem_population:
			*outValue = INT_TO_JSVAL([sPlanetInfo intForKey:KEY_POPULATION]);
			break;
			
		case kSystem_productivity:
			*outValue = INT_TO_JSVAL([sPlanetInfo intForKey:KEY_PRODUCTIVITY]);
			break;
			
		case kSystem_isInterstellarSpace:
			*outValue = BOOLToJSVal([UNIVERSE sun] == nil);
			break;
		
		case kSystem_mainStation:
			result = [UNIVERSE station];
			break;
		
		default:
			OOReportJavaScriptBadPropertySelector(context, @"System", JSVAL_TO_INT(name));
			return NO;
	}
	
	if (result != nil)  *outValue = [result javaScriptValueInContext:context];
	return YES;
}


static JSBool SystemSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	PlayerEntity				*player = nil;
	OOGalaxyID					galaxy;
	OOSystemID					system;
	NSString					*stringValue = nil;
	int32						iValue;
	
	if (!JSVAL_IS_INT(name))  return YES;
	
	player = OPlayerForScripting();
	if (!equal_seeds(sCurrentSystem, player->system_seed))
	{
		sCurrentSystem = player->system_seed;
		
		[sPlanetInfo release];
		sPlanetInfo = [[UNIVERSE generateSystemData:sCurrentSystem] retain];
	}
	
	galaxy = [player currentGalaxyID];
	system = [player currentSystemID];
	
	if (system == -1)  return YES;	// Can't change anything in interstellar space.
	
	switch (JSVAL_TO_INT(name))
	{
		case kSystem_name:
			stringValue = JSValToNSString(context, *value);
			if (stringValue != nil)  [UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_NAME value:stringValue];
			break;
			
		case kSystem_description:
			stringValue = JSValToNSString(context, *value);
			if (stringValue != nil)  [UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_DESCRIPTION value:stringValue];
			break;
			
		case kSystem_inhabitantsDescription:
			stringValue = JSValToNSString(context, *value);
			if (stringValue != nil)  [UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_INHABITANTS value:stringValue];
				break;
			
		case kSystem_government:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				if (7 < iValue)  iValue = 7;
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_GOVERNMENT value:[NSNumber numberWithInt:iValue]];
			}
			break;
			
		case kSystem_economy:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				if (7 < iValue)  iValue = 7;
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_ECONOMY value:[NSNumber numberWithInt:iValue]];
			}
			break;
			
		case kSystem_techLevel:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				if (15 < iValue)  iValue = 15;
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_TECHLEVEL value:[NSNumber numberWithInt:iValue]];
			}
			break;
			
		case kSystem_population:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_POPULATION value:[NSNumber numberWithInt:iValue]];
			}
			break;
			
		case kSystem_productivity:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_PRODUCTIVITY value:[NSNumber numberWithInt:iValue]];
			}
			break;
			
		default:
			OOReportJavaScriptBadPropertySelector(context, @"System", JSVAL_TO_INT(name));
			return NO;
	}
	
	return YES;
}


// *** Methods ***

static JSBool SystemToString(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString					*systemDesc = nil;
	PlayerEntity				*player = nil;
	
	player = [PlayerEntity sharedPlayer];
	systemDesc = [NSString stringWithFormat:@"<System %u:%u \"%@\">", [player currentGalaxyID], [player currentSystemID], [[UNIVERSE currentSystemData] objectForKey:KEY_NAME]];
	*outResult = [systemDesc javaScriptValueInContext:context];
	return YES;
}


static JSBool SystemAddPlanet(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity *player = OPlayerForScripting();
	
	if (argc > 0 && JSVAL_IS_STRING(argv[0]))
	{
		NSString *key = JSValToNSString(context, argv[0]);
		[player addPlanet:key];
	}
	return YES;
}


static JSBool SystemAddMoon(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity *player = OPlayerForScripting();
	
	if (argc > 0 && JSVAL_IS_STRING(argv[0]))
	{
		NSString *key = JSValToNSString(context, argv[0]);
		[player addMoon:key];
	}
	return YES;
}


static JSBool SystemSendAllShipsAway(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity *player = OPlayerForScripting();
	
	[player sendAllShipsAway];
	
	return YES;
}


static JSBool SystemSetSunNova(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity *player = OPlayerForScripting();
	
	NSString *key = JSValToNSString(context, argv[0]);
	[player setSunNovaIn:key];
		
	return YES;
}


static JSBool SystemCountShipsWithRole(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString			*role = nil;
	int					count;
	
	role = JSValToNSString(context, argv[0]);
	count = [UNIVERSE countShipsWithRole:role];
	*outResult = INT_TO_JSVAL(count);
	
	return YES;
}


#define DEFAULT_RADIUS 500.0

static JSBool SystemAddShips(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString			*role = nil;
	int32				count;
	Vector				where;
	double				radius = DEFAULT_RADIUS;
	uintN				consumed;
	
	role = JSValToNSString(context, argv[0]);
	if (!JS_ValueToInt32(context, argv[1], &count) || count < 1 || 64 < count)
	{
		OOReportJavaScriptError(context, @"System.%@(): expected positive count, got %@.", @"addShips", JSValToNSString(context, argv[1]));
		return YES;
	}
	
	if (!VectorFromArgumentList(context, @"System", @"addShips", argc - 2, argv + 2, &where, &consumed))  return YES;
	argc += 2 + consumed;
	argv += 2 + consumed;
	
	if (argc != 0 && JS_ValueToNumber(context, argv[0], &radius))
	{
		
	}
	
	OOReportJavaScriptError(context, @"System.addShips(): not implemented.");
	
	return YES;
}


static JSBool SystemLegacyAddShips(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString			*role = nil;
	int32				count;
	
	role = JSValToNSString(context, argv[0]);
	if (!JS_ValueToInt32(context, argv[1], &count) || count < 1 || 64 < count)
	{
		OOReportJavaScriptError(context, @"System.%@(): expected positive count, got %@.", @"legacy_addShips", JSValToNSString(context, argv[1]));
		return YES;
	}
	
	while (count--)  [UNIVERSE witchspaceShipWithRole:role];
	
	return YES;
}


static JSBool SystemLegacyAddSystemShips(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	jsdouble			position;
	NSString			*role = nil;
	int32				count;
	
	role = JSValToNSString(context, argv[0]);
	if (!JS_ValueToInt32(context, argv[1], &count) || count < 1 || 64 < count)
	{
		OOReportJavaScriptError(context, @"System.%@(): expected positive count, got %@.", @"legacy_addSystemShips", JSValToNSString(context, argv[1]));
		return YES;
	}
	
	JS_ValueToNumber(context, argv[2], &position);
	while (count--)  [UNIVERSE addShipWithRole:role nearRouteOneAt:position];
	
	return YES;
}


static JSBool SystemLegacyAddShipsAt(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OPlayerForScripting();
	Vector				where;
	NSString			*role = nil;
	int32				count;
	NSString			*coordScheme = nil;
	NSString			*arg = nil;
	
	role = JSValToNSString(context, argv[0]);
	if (!JS_ValueToInt32(context, argv[1], &count) || count < 1 || 64 < count)
	{
		OOReportJavaScriptError(context, @"System.%@(): expected positive count, got %@.", @"legacy_addShipsAt", JSValToNSString(context, argv[1]));
		return YES;
	}
	
	coordScheme = JSValToNSString(context, argv[2]);
	
	if (!VectorFromArgumentList(context, @"System", @"legacy_addShipsAt", argc - 3, argv + 3, &where, NULL))  return YES;
	
	arg = [NSString stringWithFormat:@"%@ %d %@ %f %f %f", role, count, coordScheme, where.x, where.y, where.z];
	[player addShipsAt:arg];
	
	return YES;
}


static JSBool SystemLegacyAddShipsAtPrecisely(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OPlayerForScripting();
	Vector				where;
	NSString			*role = nil;
	int32				count;
	NSString			*coordScheme = nil;
	NSString			*arg = nil;
	
	role = JSValToNSString(context, argv[0]);
	if (!JS_ValueToInt32(context, argv[1], &count) || count < 1 || 64 < count)
	{
		OOReportJavaScriptError(context, @"System.%@(): expected positive count, got %@.", @"legacy_addShipsAtPrecisely", JSValToNSString(context, argv[1]));
		return YES;
	}
	
	coordScheme = JSValToNSString(context, argv[2]);
	
	if (!VectorFromArgumentList(context, @"System", @"legacy_addShipsAtPrecisely", argc - 3, argv + 3, &where, NULL))  return YES;
	
	arg = [NSString stringWithFormat:@"%@ %d %@ %f %f %f", role, count, coordScheme, where.x, where.y, where.z];
	[player addShipsAtPrecisely:arg];
	
	return YES;
}


static JSBool SystemLegacyAddShipsWithinRadius(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OPlayerForScripting();
	Vector				where;
	jsdouble			radius;
	NSString			*role = nil;
	int32				count;
	NSString			*coordScheme = nil;
	NSString			*arg = nil;
	uintN				consumed = 0;
	
	role = JSValToNSString(context, argv[0]);
	if (!JS_ValueToInt32(context, argv[1], &count) || count < 1 || 64 < count)
	{
		OOReportJavaScriptError(context, @"System.%@(): expected positive count, got %@.", @"legacy_addShipWithinRadius", JSValToNSString(context, argv[1]));
		return YES;
	}
	
	coordScheme = JSValToNSString(context, argv[2]);
	
	if (!VectorFromArgumentList(context, @"System", @"legacy_addShipWithinRadius", argc - 3, argv + 3, &where, &consumed))  return YES;
	argc += consumed;
	argv += consumed;
	JS_ValueToNumber(context, argv[3], &radius);
	
	arg = [NSString stringWithFormat:@"%@ %d %@ %f %f %f %d", role, count, coordScheme, where.x, where.y, where.z, radius];
	[player addShipsWithinRadius:arg];
	
	return YES;
}


static JSBool SystemLegacySpawn(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OPlayerForScripting();
	NSString			*role = nil;
	int32				count;
	NSString			*arg = nil;
	
	role = JSValToNSString(context, argv[0]);
	if (!JS_ValueToInt32(context, argv[1], &count) || count < 1 || 64 < count)
	{
		OOReportJavaScriptError(context, @"System.%@(): expected positive count, got %@.", @"legacy_spawn", JSValToNSString(context, argv[1]));
		return YES;
	}
	
	arg = [NSString stringWithFormat:@"%@ %d", role, count];
	[player spawn:arg];
	
	return YES;
}


static JSBool SystemLegacySpawnShip(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OPlayerForScripting();
	
	[player spawnShip:JSValToNSString(context, argv[0])];
	return YES;
}
