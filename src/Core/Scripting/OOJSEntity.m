/*

OOJSEntity.m

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

#import "OOJSEntity.h"
#import "OOJSVector.h"
#import "OOJSQuaternion.h"
#import "OOJavaScriptEngine.h"
#import "OOConstToString.h"
#import "EntityOOJavaScriptExtensions.h"
#import "OOJSCall.h"

#import "OOJSPlayer.h"
#import "PlayerEntity.h"
#import "ShipEntity.h"


static JSObject		*sEntityPrototype;


static JSBool EntityGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool EntitySetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);


static JSExtendedClass sEntityClass =
{
	{
		"Entity",
		JSCLASS_HAS_PRIVATE | JSCLASS_IS_EXTENDED,
		
		JS_PropertyStub,		// addProperty
		JS_PropertyStub,		// delProperty
		EntityGetProperty,		// getProperty
		EntitySetProperty,		// setProperty
		JS_EnumerateStub,		// enumerate
		JS_ResolveStub,			// resolve
		JS_ConvertStub,			// convert
		JSObjectWrapperFinalize,// finalize
		JSCLASS_NO_OPTIONAL_MEMBERS
	},
	JSObjectWrapperEquality,	// equality
	NULL,						// outerObject
	NULL,						// innerObject
	JSCLASS_NO_RESERVED_MEMBERS
};


enum
{
	// Property IDs
	kEntity_distanceTravelled,	// distance travelled, double, read-only.
	kEntity_energy,				// energy, double, read-write.
	kEntity_heading,			// heading, vector, read-only (like orientation but ignoring twist angle)
	kEntity_mass,				// mass, double, read-only
	kEntity_maxEnergy,			// maxEnergy, double, read-only.
	kEntity_orientation,		// orientation, quaternion, read/write
	kEntity_owner,				// owner, Entity, read-only. (Parent ship for subentities, station for defense ships, launching ship for missiles etc)
	kEntity_position,			// position in system space, Vector, read/write
	kEntity_scanClass,			// scan class, string, read-only
	kEntity_spawnTime,			// spawn time, double, read-only.
	kEntity_status,				// entity status, string, read-only
	kEntity_isPlanet,			// is planet, boolean, read-only.
	kEntity_isPlayer,			// is player, boolean, read-only.
	kEntity_isShip,				// is ship, boolean, read-only.
	kEntity_isStation,			// is station, boolean, read-only.
	kEntity_isSubEntity,		// is subentity, boolean, read-only.
	kEntity_isSun,				// is sun, boolean, read-only.
	kEntity_isValid,			// is not stale, boolean, read-only.
};


static JSPropertySpec sEntityProperties[] =
{
	// JS name					ID							flags
	{ "distanceTravelled",		kEntity_distanceTravelled,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "energy",					kEntity_energy,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "heading",				kEntity_heading,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "mass",					kEntity_mass,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "maxEnergy",				kEntity_maxEnergy,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "orientation",			kEntity_orientation,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "owner",					kEntity_owner,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "position",				kEntity_position,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "scanClass",				kEntity_scanClass,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "spawnTime",				kEntity_spawnTime,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "status",					kEntity_status,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isPlanet",				kEntity_isPlanet,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isPlayer",				kEntity_isPlayer,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isShip",					kEntity_isShip,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isStation",				kEntity_isStation,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isSubEntity",			kEntity_isSubEntity,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isSun",					kEntity_isSun,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isValid",				kEntity_isValid,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sEntityMethods[] =
{
	// JS name					Function					min args
	{ "toString",				JSObjectWrapperToString,	0 },
	{ 0 }
};


void InitOOJSEntity(JSContext *context, JSObject *global)
{
	sEntityPrototype = JS_InitClass(context, global, NULL, &sEntityClass.base, NULL, 0, sEntityProperties, sEntityMethods, NULL, NULL);
	JSRegisterObjectConverter(&sEntityClass.base, JSBasicPrivateObjectConverter);
}


BOOL JSValueToEntity(JSContext *context, jsval value, Entity **outEntity)
{
	if (JSVAL_IS_OBJECT(value))
	{
		return JSEntityGetEntity(context, JSVAL_TO_OBJECT(value), outEntity);
	}
	
	return NO;
}


JSClass *JSEntityClass(void)
{
	return &sEntityClass.base;
}


JSObject *JSEntityPrototype(void)
{
	return sEntityPrototype;
}


BOOL EntityFromArgumentList(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, Entity **outEntity, uintN *outConsumed)
{
	OOJS_PROFILE_ENTER
	
	// Sanity checks.
	if (outConsumed != NULL)  *outConsumed = 0;
	if (EXPECT_NOT(argc == 0 || argv == NULL || outEntity == NULL))
	{
		OOLogGenericParameterError();
		return NO;
	}
	
	// Get value, if possible.
	if (EXPECT_NOT(!JSValueToEntity(context, argv[0], outEntity)))
	{
		// Failed; report bad parameters, if given a class and function.
		if (scriptClass != nil && function != nil)
		{
			OOReportJSWarning(context, @"%@.%@(): expected entity or universal ID, got %@.", scriptClass, function, [NSString stringWithJavaScriptParameters:argv count:1 inContext:context]);
			return NO;
		}
	}
	
	// Success.
	if (outConsumed != NULL)  *outConsumed = 1;
	return YES;
	
	OOJS_PROFILE_EXIT
}


static JSBool EntityGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	if (!JSVAL_IS_INT(name))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	BOOL						OK = NO;
	Entity						*entity = nil;
	id							result = nil;
	
	JSEntityGetEntity(context, this, &entity);
	if (entity == nil)
	{
		if (JSVAL_TO_INT(name) == kEntity_isValid)  *outValue = JSVAL_FALSE;
		else  *outValue = JSVAL_VOID;
		
		return YES;
	}
	
	switch (JSVAL_TO_INT(name))
	{
		case kEntity_position:
			OK = VectorToJSValue(context, [entity position], outValue);
			break;
		
		case kEntity_orientation:
			OK = QuaternionToJSValue(context, [entity normalOrientation], outValue);
			break;
		
		case kEntity_heading:
			OK = VectorToJSValue(context, vector_forward_from_quaternion([entity normalOrientation]), outValue);
			break;
		
		case kEntity_status:
			result = EntityStatusToString([entity status]);
			break;
		
		case kEntity_scanClass:
			result = ScanClassToString([entity scanClass]);
			break;
		
		case kEntity_mass:
			OK = JS_NewDoubleValue(context, [entity mass], outValue);
			break;
		
		case kEntity_owner:
			result = [entity owner];
			if (result == entity)  result = nil;
			if (result == nil)  result = [NSNull null];
			break;
		
		case kEntity_energy:
			OK = JS_NewDoubleValue(context, [entity energy], outValue);
			break;
		
		case kEntity_maxEnergy:
			OK = JS_NewDoubleValue(context, [entity maxEnergy], outValue);
			break;
		
		case kEntity_isValid:
			*outValue = JSVAL_TRUE;
			OK = YES;
			break;
		
		case kEntity_isShip:
			*outValue = BOOLToJSVal([entity isShip]);
			OK = YES;
			break;
		
		case kEntity_isStation:
			*outValue = BOOLToJSVal([entity isStation]);
			OK = YES;
			break;
			
		case kEntity_isSubEntity:
			*outValue = BOOLToJSVal([entity isSubEntity]);
			OK = YES;
			break;
		
		case kEntity_isPlayer:
			*outValue = BOOLToJSVal([entity isPlayer]);
			OK = YES;
			break;
			
		case kEntity_isPlanet:
			*outValue = BOOLToJSVal([entity isPlanet] && ![entity isSun]);
			OK = YES;
			break;
			
		case kEntity_isSun:
			*outValue = BOOLToJSVal([entity isSun]);
			OK = YES;
			break;
		
		case kEntity_distanceTravelled:
			OK = JS_NewDoubleValue(context, [entity distanceTravelled], outValue);
			break;
		
		case kEntity_spawnTime:
			OK = JS_NewDoubleValue(context, [entity spawnTime], outValue);
			break;
		
		default:
			OOReportJSBadPropertySelector(context, @"Entity", JSVAL_TO_INT(name));
	}
	
	if (result != nil)
	{
		*outValue = [result javaScriptValueInContext:context];
		OK = YES;
	}
	return OK;
	
	OOJS_NATIVE_EXIT
}


static JSBool EntitySetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	if (!JSVAL_IS_INT(name))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	BOOL				OK = NO;
	Entity				*entity = nil;
	double				fValue;
	Vector				vValue;
	Quaternion			qValue;
	
	if (EXPECT_NOT(!JSEntityGetEntity(context, this, &entity))) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kEntity_position:
			if (JSValueToVector(context, *value, &vValue))
			{
				[entity setPosition:vValue];
				if ([entity isShip]) [(ShipEntity *)entity resetExhaustPlumes];
				OK = YES;
			}
			break;
			
		case kEntity_orientation:
			if (JSValueToQuaternion(context, *value, &qValue))
			{
				[entity setNormalOrientation:qValue];
				OK = YES;
			}
			break;
			
		case kEntity_energy:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				fValue = OOClamp_0_max_d(fValue, [entity maxEnergy]);
				[entity setEnergy:fValue];
				OK = YES;
			}
			break;
		
		default:
			OOReportJSBadPropertySelector(context, @"Entity", JSVAL_TO_INT(name));
	}
	
	return OK;
	
	OOJS_NATIVE_EXIT
}
