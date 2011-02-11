/*

OOJSPlayerShip.h

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

#import "OOCollectionExtractors.h"
#import "OOJSPlayer.h"
#import "OOJSEntity.h"
#import "OOJSShip.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "EntityOOJavaScriptExtensions.h"

#import "PlayerEntity.h"
#import "PlayerEntityContracts.h"
#import "PlayerEntityScriptMethods.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "HeadUpDisplay.h"
#import "StationEntity.h"

#import "OOConstToJSString.h"
#import "OOConstToString.h"
#import "OOFunctionAttributes.h"
#import "OOEquipmentType.h"
#import "OOJSEquipmentInfo.h"


static JSObject		*sPlayerShipPrototype;
static JSObject		*sPlayerShipObject;


static JSBool PlayerShipGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool PlayerShipSetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);

static JSBool PlayerShipLaunch(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipRemoveAllCargo(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipUseSpecialCargo(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipEngageAutopilotToStation(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipDisengageAutopilot(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipAwardEquipmentToCurrentPylon(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipAddPassenger(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipAwardContract(JSContext *context, uintN argc, jsval *vp);

static BOOL ValidateContracts(JSContext *context, uintN argc, jsval *vp, BOOL isCargo);


static JSClass sPlayerShipClass =
{
	"PlayerShip",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	PlayerShipGetProperty,	// getProperty
	PlayerShipSetProperty,	// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	OOJSObjectWrapperFinalize,// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kPlayerShip_aftShield,						// aft shield charge level, nonnegative float, read/write
	kPlayerShip_aftShieldRechargeRate,			// aft shield recharge rate, positive float, read-only
	kPlayerShip_compassMode,					// compass mode, string, read-only
	kPlayerShip_compassTarget,					// object targeted by the compass, entity, read-only
	kPlayerShip_cursorCoordinates,				// cursor coordinates, vector, read only
	kPlayerShip_docked,							// docked, boolean, read-only
	kPlayerShip_dockedStation,					// docked station, entity, read-only
	kPlayerShip_forwardShield,					// forward shield charge level, nonnegative float, read/write
	kPlayerShip_forwardShieldRechargeRate,		// forward shield recharge rate, positive float, read-only
	kPlayerShip_fuelLeakRate,					// fuel leak rate, float, read/write
	kPlayerShip_galacticHyperspaceBehaviour,	// can be standard, all systems reachable or fixed coordinates, integer, read-only
	kPlayerShip_galacticHyperspaceFixedCoords,	// used when fixed coords behaviour is selected, vector, read-only
	kPlayerShip_galaxyCoordinates,				// galaxy coordinates, vector, read only
	kPlayerShip_hud,							// hud name identifier, string, read/write
	kPlayerShip_hudHidden,						// hud visibility, boolean, read/write
	kPlayerShip_maxAftShield,					// maximum aft shield charge level, positive float, read-only
	kPlayerShip_maxForwardShield,				// maximum forward shield charge level, positive float, read-only
	kPlayerShip_reticleTargetSensitive,			// target box changes color when primary target in crosshairs, boolean, read/write
	kPlayerShip_scoopOverride,					// Scooping
	kPlayerShip_scriptedMisjump,				// next jump will miss if set to true, boolean, read/write
	kPlayerShip_specialCargo,					// special cargo, string, read-only
	kPlayerShip_targetSystem,					// target system id, int, read-only
	kPlayerShip_viewDirection,					// view direction identifier, string, read-only
	kPlayerShip_weaponsOnline,					// weapons online status, boolean, read-only
};


static JSPropertySpec sPlayerShipProperties[] =
{
	// JS name						ID									flags
	{ "aftShield",						kPlayerShip_aftShield,						OOJS_PROP_READWRITE_CB },
	{ "aftShieldRechargeRate",			kPlayerShip_aftShieldRechargeRate,			OOJS_PROP_READONLY_CB },
	{ "compassMode",					kPlayerShip_compassMode,					OOJS_PROP_READONLY_CB },
	{ "compassTarget",					kPlayerShip_compassTarget,					OOJS_PROP_READONLY_CB },
	{ "cursorCoordinates",				kPlayerShip_cursorCoordinates,				OOJS_PROP_READONLY_CB },
	{ "docked",							kPlayerShip_docked,							OOJS_PROP_READONLY_CB },
	{ "dockedStation",					kPlayerShip_dockedStation,					OOJS_PROP_READONLY_CB },
	{ "forwardShield",					kPlayerShip_forwardShield,					OOJS_PROP_READWRITE_CB },
	{ "forwardShieldRechargeRate",		kPlayerShip_forwardShieldRechargeRate,		OOJS_PROP_READONLY_CB },
	{ "fuelLeakRate",					kPlayerShip_fuelLeakRate,					OOJS_PROP_READWRITE_CB },
	{ "galacticHyperspaceBehaviour",	kPlayerShip_galacticHyperspaceBehaviour,	OOJS_PROP_READWRITE_CB },
	{ "galacticHyperspaceFixedCoords",	kPlayerShip_galacticHyperspaceFixedCoords,	OOJS_PROP_READWRITE_CB },
	{ "galaxyCoordinates",				kPlayerShip_galaxyCoordinates,				OOJS_PROP_READONLY_CB },
	{ "hud",							kPlayerShip_hud,							OOJS_PROP_READWRITE_CB },
	{ "hudHidden",						kPlayerShip_hudHidden,						OOJS_PROP_READWRITE_CB },
	// manifest defined in OOJSManifest.m
	{ "maxAftShield",					kPlayerShip_maxAftShield,					OOJS_PROP_READONLY_CB },
	{ "maxForwardShield",				kPlayerShip_maxForwardShield,				OOJS_PROP_READONLY_CB },
	{ "reticleTargetSensitive",			kPlayerShip_reticleTargetSensitive,			OOJS_PROP_READWRITE_CB },
	{ "scoopOverride",					kPlayerShip_scoopOverride,					OOJS_PROP_READWRITE_CB },
	{ "scriptedMisjump",				kPlayerShip_scriptedMisjump,				OOJS_PROP_READWRITE_CB },
	{ "specialCargo",					kPlayerShip_specialCargo,					OOJS_PROP_READONLY_CB },
	{ "targetSystem",					kPlayerShip_targetSystem,					OOJS_PROP_READONLY_CB },
	{ "viewDirection",					kPlayerShip_viewDirection,					OOJS_PROP_READONLY_CB },
	{ "weaponsOnline",					kPlayerShip_weaponsOnline,					OOJS_PROP_READONLY_CB },
	{ 0 }			
};


static JSFunctionSpec sPlayerShipMethods[] =
{
	// JS name						Function							min args
	{ "addPassenger",					PlayerShipAddPassenger,						0 },
	{ "awardContract",					PlayerShipAwardContract,					0 },
	{ "awardEquipmentToCurrentPylon",	PlayerShipAwardEquipmentToCurrentPylon,		1 },
	{ "disengageAutopilot",				PlayerShipDisengageAutopilot,				0 },
	{ "engageAutopilotToStation",		PlayerShipEngageAutopilotToStation,			1 },
	{ "launch",							PlayerShipLaunch,							0 },
	{ "removeAllCargo",					PlayerShipRemoveAllCargo,					0 },
	{ "useSpecialCargo",				PlayerShipUseSpecialCargo,					1 },
	{ 0 }
};


void InitOOJSPlayerShip(JSContext *context, JSObject *global)
{
	sPlayerShipPrototype = JS_InitClass(context, global, JSShipPrototype(), &sPlayerShipClass, OOJSUnconstructableConstruct, 0, sPlayerShipProperties, sPlayerShipMethods, NULL, NULL);
	OOJSRegisterObjectConverter(&sPlayerShipClass, OOJSBasicPrivateObjectConverter);
	OOJSRegisterSubclass(&sPlayerShipClass, JSShipClass());
	
	PlayerEntity *player = [PlayerEntity sharedPlayer];	// NOTE: at time of writing, this creates the player entity. Don't use PLAYER here.
	
	// Create ship object as a property of the player object.
	sPlayerShipObject = JS_DefineObject(context, JSPlayerObject(), "ship", &sPlayerShipClass, sPlayerShipPrototype, OOJS_PROP_READONLY);
	JS_SetPrivate(context, sPlayerShipObject, OOConsumeReference([player weakRetain]));
	[player setJSSelf:sPlayerShipObject context:context];
	// Analyzer: object leaked. [Expected, object is retained by JS object.]
}


JSClass *JSPlayerShipClass(void)
{
	return &sPlayerShipClass;
}


JSObject *JSPlayerShipPrototype(void)
{
	return sPlayerShipPrototype;
}


JSObject *JSPlayerShipObject(void)
{
	return sPlayerShipObject;
}


@implementation PlayerEntity (OOJavaScriptExtensions)

- (NSString *) oo_jsClassName
{
	return @"PlayerShip";
}


- (void) setJSSelf:(JSObject *)val context:(JSContext *)context
{
	_jsSelf = val;
	OOJSAddGCObjectRoot(context, &_jsSelf, "Player jsSelf");
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(javaScriptEngineWillReset:)
												 name:kOOJavaScriptEngineWillResetNotification
											   object:[OOJavaScriptEngine sharedEngine]];
}


- (void) javaScriptEngineWillReset:(NSNotification *)notification
{
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:kOOJavaScriptEngineWillResetNotification
												  object:[OOJavaScriptEngine sharedEngine]];
	
	if (_jsSelf != NULL)
	{
		
		JSContext *context = OOJSAcquireContext();
		JS_RemoveObjectRoot(context, &_jsSelf);
		_jsSelf = NULL;
		OOJSRelinquishContext(context);
	}
}

@end


static JSBool PlayerShipGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale() || this == sPlayerShipPrototype))  { *value = JSVAL_VOID; return YES; }
	
	id							result = nil;
	PlayerEntity				*player = OOPlayerForScripting();
	
	switch (JSID_TO_INT(propID))
	{
		case kPlayerShip_fuelLeakRate:
			return JS_NewNumberValue(context, [player fuelLeakRate], value);
			
		case kPlayerShip_docked:
			*value = OOJSValueFromBOOL([player isDocked]);
			return YES;
			
		case kPlayerShip_dockedStation:
			result = [player dockedStation];
			break;
			
		case kPlayerShip_specialCargo:
			result = [player specialCargo];
			break;
			
		case kPlayerShip_reticleTargetSensitive:
			*value = OOJSValueFromBOOL([[player hud] reticleTargetSensitive]);
			return YES;
			
		case kPlayerShip_galacticHyperspaceBehaviour:
			*value = OOJSValueFromGalacticHyperspaceBehaviour(context, [player galacticHyperspaceBehaviour]);
			return YES;
			
		case kPlayerShip_galacticHyperspaceFixedCoords:
			return NSPointToVectorJSValue(context, [player galacticHyperspaceFixedCoords], value);
			
		case kPlayerShip_forwardShield:
			return JS_NewNumberValue(context, [player forwardShieldLevel], value);
			
		case kPlayerShip_aftShield:
			return JS_NewNumberValue(context, [player aftShieldLevel], value);
			
		case kPlayerShip_maxForwardShield:
			return JS_NewNumberValue(context, [player maxForwardShieldLevel], value);
			
		case kPlayerShip_maxAftShield:
			return JS_NewNumberValue(context, [player maxAftShieldLevel], value);
			
		case kPlayerShip_forwardShieldRechargeRate:
		case kPlayerShip_aftShieldRechargeRate:
			// No distinction made internally
			return JS_NewNumberValue(context, [player shieldRechargeRate], value);
			
		case kPlayerShip_galaxyCoordinates:
			return NSPointToVectorJSValue(context, [player galaxy_coordinates], value);
			
		case kPlayerShip_cursorCoordinates:
			return NSPointToVectorJSValue(context, [player cursor_coordinates], value);
			
		case kPlayerShip_targetSystem:
			*value = INT_TO_JSVAL([UNIVERSE findSystemNumberAtCoords:[player cursor_coordinates] withGalaxySeed:[player galaxy_seed]]);
			return YES;

		case kPlayerShip_scriptedMisjump:
			*value = OOJSValueFromBOOL([player scriptedMisjump]);
			return YES;
			
		case kPlayerShip_scoopOverride:
			*value = OOJSValueFromBOOL([player scoopOverride]);
			return YES;
			
		case kPlayerShip_compassTarget:
			result = [player compassTarget];
			break;
			
		case kPlayerShip_compassMode:
			*value = OOJSValueFromCompassMode(context, [player compassMode]);
			return YES;
			
		case kPlayerShip_hud:
			result = [[player hud] hudName];
			break;
			
		case kPlayerShip_hudHidden:
			*value = OOJSValueFromBOOL([[player hud] isHidden]);
			return YES;
			
		case kPlayerShip_weaponsOnline:
			*value = OOJSValueFromBOOL([player weaponsOnline]);
			return YES;
			
		case kPlayerShip_viewDirection:
			*value = OOJSValueFromViewID(context, [UNIVERSE viewDirection]);
			return YES;
		
		default:
			OOJSReportBadPropertySelector(context, this, propID, sPlayerShipProperties);
	}
	
	*value = OOJSValueFromNativeObject(context, result);
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool PlayerShipSetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale())) return YES;
	
	PlayerEntity				*player = OOPlayerForScripting();
	jsdouble					fValue;
	JSBool						bValue;
	NSString					*sValue = nil;
	OOGalacticHyperspaceBehaviour ghBehaviour;
	Vector						vValue;
	
	switch (JSID_TO_INT(propID))
	{
		case kPlayerShip_fuelLeakRate:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[player setFuelLeakRate:fValue];
				return YES;
			}
			break;
			
		case kPlayerShip_reticleTargetSensitive:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[[player hud] setReticleTargetSensitive:bValue];
				return YES;
			}
			break;
			
		case kPlayerShip_galacticHyperspaceBehaviour:
			ghBehaviour = OOGalacticHyperspaceBehaviourFromJSValue(context, *value);
			if (ghBehaviour != GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN)
			{
				[player setGalacticHyperspaceBehaviour:ghBehaviour];
				return YES;
			}
			break;
			
		case kPlayerShip_galacticHyperspaceFixedCoords:
			if (JSValueToVector(context, *value, &vValue))
			{
				[player setGalacticHyperspaceFixedCoordsX:OOClamp_0_max_f(vValue.x, 255.0f) y:OOClamp_0_max_f(vValue.y, 255.0f)];
				return YES;
			}
			break;
			
		case kPlayerShip_forwardShield:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[player setForwardShieldLevel:fValue];
				return YES;
			}
			break;
			
		case kPlayerShip_aftShield:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[player setAftShieldLevel:fValue];
				return YES;
			}
			break;
			
		case kPlayerShip_scriptedMisjump:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[player setScriptedMisjump:bValue];
				return YES;
			}
			break;
		case kPlayerShip_scoopOverride:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[player setScoopOverride:bValue];
				return YES;
			}
			break;
			
		case kPlayerShip_hud:
			sValue = OOStringFromJSValue(context, *value);
			if (sValue != nil)
			{
				[player switchHudTo:sValue];	// EMMSTRAN: logged error should be a JS warning.
				return YES;
			}
			else
			{
				[player resetHud];
				return YES;
			}
			break;
			
		case kPlayerShip_hudHidden:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[[player hud] setHidden:bValue];
				return YES;
			}
			break;
		
		default:
			OOJSReportBadPropertySelector(context, this, propID, sPlayerShipProperties);
			return NO;
	}
	
	OOJSReportBadPropertyValue(context, this, propID, sPlayerShipProperties, *value);
	return NO;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

// launch()
static JSBool PlayerShipLaunch(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;
	
	[OOPlayerForScripting() launchFromStation];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// removeAllCargo()
static JSBool PlayerShipRemoveAllCargo(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;
	
	PlayerEntity *player = OOPlayerForScripting();
	
	if ([player isDocked])
	{
		[player removeAllCargo];
		OOJS_RETURN_VOID;
	}
	else
	{
		OOJSReportError(context, @"PlayerShip.removeAllCargo only works when docked.");
		return NO;
	}
	
	OOJS_NATIVE_EXIT
}


// useSpecialCargo(name : String)
static JSBool PlayerShipUseSpecialCargo(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;
	
	PlayerEntity			*player = OOPlayerForScripting();
	NSString				*name = nil;
	
	name = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(name == nil))
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"useSpecialCargo", argc, OOJS_ARGV, nil, @"string (special cargo description)");
		return NO;
	}
	
	[player useSpecialCargo:OOStringFromJSValue(context, OOJS_ARGV[0])];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// engageAutopilotToStation(stationForDocking : Station) : Boolean
static JSBool PlayerShipEngageAutopilotToStation(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;
	
	PlayerEntity			*player = OOPlayerForScripting();
	StationEntity			*stationForDocking = nil;
	
	stationForDocking = OOJSNativeObjectOfClassFromJSValue(context, OOJS_ARGV[0], [StationEntity class]);
	if (stationForDocking == nil)
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"engageAutopilot", argc, OOJS_ARGV, nil, @"station");
		return NO;
	}
	
	OOJS_RETURN_BOOL([player engageAutopilotToStation:stationForDocking]);
	
	OOJS_NATIVE_EXIT
}


// disengageAutopilot()
static JSBool PlayerShipDisengageAutopilot(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;
	
	[OOPlayerForScripting() disengageAutopilot];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// awardEquipmentToCurrentPylon(externalTank: equipmentInfoExpression) : Boolean
static JSBool PlayerShipAwardEquipmentToCurrentPylon(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;
	
	PlayerEntity			*player = OOPlayerForScripting();
	NSString				*key = nil;
	OOEquipmentType			*eqType = nil;
	
	key = JSValueToEquipmentKey(context, OOJS_ARGV[0]);
	if (key != nil)  eqType = [OOEquipmentType equipmentTypeWithIdentifier:key];
	if (EXPECT_NOT(![eqType isMissileOrMine]))
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"awardEquipmentToCurrentPylon", argc, OOJS_ARGV, nil, @"equipment type (external store)");
		return NO;
	}
	
	OOJS_RETURN_BOOL([player assignToActivePylon:key]);
	
	OOJS_NATIVE_EXIT
}


// addPassenger(name: string, start: int, destination: int, eta: double, fee: double) : Boolean
static JSBool PlayerShipAddPassenger(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	BOOL				OK = YES;
	NSString			*name = nil;
	
	if (argc == 5)
	{
		name = OOStringFromJSValue(context, OOJS_ARGV[0]);
		if (EXPECT_NOT(name == nil || JSVAL_IS_INT(OOJS_ARGV[0])))
		{
			OOJSReportBadArguments(context, @"PlayerShip", @"addPassenger", argc, OOJS_ARGV, nil, @"string (name)");
			return NO;
		}
		OK = ValidateContracts(context, argc, vp, NO);
		if (!OK) return NO;
		
		if ([player passengerCount] >= [player passengerCapacity])
		{
			OK = NO;
		}
	}
	else
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"addPassenger", argc, OOJS_ARGV, nil, @"name, start, destination, eta, fee");
		return NO;
	}
	
	if (OK)
	{
		jsdouble		eta,fee;
		JS_ValueToNumber(context, OOJS_ARGV[3], &eta);
		JS_ValueToNumber(context, OOJS_ARGV[4], &fee);
		OK = [player addPassenger:name start:JSVAL_TO_INT(OOJS_ARGV[1]) destination:JSVAL_TO_INT(OOJS_ARGV[2]) eta:eta fee:fee];
	}
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


// awardContract(quantity: int, commodity: string, start: int, destination: int, eta: double, fee: double) : Boolean
static JSBool PlayerShipAwardContract(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	BOOL				OK = JSVAL_IS_INT(OOJS_ARGV[0]);
	NSString 			*key = nil;
	int 				qty = 0;
	
	if (OK && argc == 6)
	{
		key = OOStringFromJSValue(context, OOJS_ARGV[1]);
		if (EXPECT_NOT(key == nil || !JSVAL_IS_STRING(OOJS_ARGV[1])))
		{
			OOJSReportBadArguments(context, @"PlayerShip", @"awardContract", argc, OOJS_ARGV, nil, @"string (commodity identifier)");
			return NO;
		}
		OK = ValidateContracts(context, argc, vp, YES); // always go through validate contracts (cargo)
		if (!OK) return NO;
		
		qty = JSVAL_TO_INT(OOJS_ARGV[0]);
		
		if (qty < 1)
		{
			OK = NO;
		}
	}
	else
	{
		if (argc == 6) 
		{
			OOJSReportBadArguments(context, @"PlayerShip", @"awardContract", argc, OOJS_ARGV, nil, @"integer (cargo quantity)");
		}
		else
		{
			OOJSReportBadArguments(context, @"PlayerShip", @"awardContract", argc, OOJS_ARGV, nil, @"quantity, commodity, start, destination, eta, fee");
		}
		return NO;
	}
	
	if (OK)
	{
		jsdouble		eta,fee;
		JS_ValueToNumber(context, OOJS_ARGV[4], &eta);
		JS_ValueToNumber(context, OOJS_ARGV[5], &fee);
		// commodity key is case insensitive.
		OK = [player awardContract:qty commodity:key start:JSVAL_TO_INT(OOJS_ARGV[2]) destination:JSVAL_TO_INT(OOJS_ARGV[3]) eta:eta fee:fee];
	}
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


static BOOL ValidateContracts(JSContext *context, uintN argc, jsval *vp, BOOL isCargo)
{
	OOJS_PROFILE_ENTER
	
	unsigned		offset = isCargo ? 2 : 1;
	NSString		*functionName = isCargo ? @"awardContract" : @"addPassenger";
	jsdouble		fValue;
	
	if (!JSVAL_IS_INT(OOJS_ARGV[offset]) || JSVAL_TO_INT(OOJS_ARGV[offset]) > 255 || JSVAL_TO_INT(OOJS_ARGV[offset]) < 0)
	{
		OOJSReportBadArguments(context, @"PlayerShip", functionName, argc, OOJS_ARGV, nil, @"integer (system ID)");
		return NO;
	}
	if (!JSVAL_IS_INT(OOJS_ARGV[offset + 1]) || JSVAL_TO_INT(OOJS_ARGV[offset + 1]) > 255 || JSVAL_TO_INT(OOJS_ARGV[offset + 1]) < 0)
	{
		OOJSReportBadArguments(context, @"PlayerShip", functionName, argc - 1, &OOJS_ARGV[1], nil, @"integer (system ID)");
		return NO;
	}
	if(!JS_ValueToNumber(context, OOJS_ARGV[offset + 2], &fValue) || fValue <= [PLAYER clockTime])
	{
		OOJSReportBadArguments(context, @"PlayerShip", functionName, argc - 2, &OOJS_ARGV[2], nil, @"number (future time)");
		return NO;
	}
	if (!JS_ValueToNumber(context, OOJS_ARGV[offset + 3], &fValue) || fValue <= 0.0)
	{
		OOJSReportBadArguments(context, @"PlayerShip", functionName, argc - 3, &OOJS_ARGV[3], nil, @"number (credits quantity)");
		return NO;
	}
	
	return YES;
	
	OOJS_PROFILE_EXIT
}
