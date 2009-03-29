/*

OOJSPlanet.m


Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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

#import "OOJSPlanet.h"
#import "OOJSEntity.h"
#import "OOJavaScriptEngine.h"
#import "OOJSSun.h"

#import "PlanetEntity.h"


DEFINE_JS_OBJECT_GETTER(JSPlanetGetPlanetEntity, PlanetEntity)


static JSObject		*sPlanetPrototype;


static JSBool PlanetGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);

static JSBool PlanetSetTexture(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


static JSExtendedClass sPlanetClass =
{
	{
		"Planet",
		JSCLASS_HAS_PRIVATE | JSCLASS_IS_EXTENDED,
		
		JS_PropertyStub,		// addProperty
		JS_PropertyStub,		// delProperty
		PlanetGetProperty,		// getProperty
		JS_PropertyStub,		// setProperty
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
	kPlanet_isMainPlanet,		// Is [UNIVERSE planet], boolean, read-only
	kPlanet_hasAtmosphere,
	kPlanet_radius,				// Radius of planet in metres.
};


static JSPropertySpec sPlanetProperties[] =
{
	// JS name					ID							flags
	{ "isMainPlanet",			kPlanet_isMainPlanet,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "hasAtmosphere",			kPlanet_hasAtmosphere,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "radius",					kPlanet_radius,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sPlanetMethods[] =
{
	// JS name					Function					min args
	{ "setTexture",				PlanetSetTexture,				1 },
	{ 0 }
};


void InitOOJSPlanet(JSContext *context, JSObject *global)
{
	sPlanetPrototype = JS_InitClass(context, global, JSEntityPrototype(), &sPlanetClass.base, NULL, 0, sPlanetProperties, sPlanetMethods, NULL, NULL);
	JSRegisterObjectConverter(&sPlanetClass.base, JSBasicPrivateObjectConverter);
}


@implementation PlanetEntity (OOJavaScriptExtensions)

- (BOOL) isVisibleToScripts
{
	return YES;
}


- (void)getJSClass:(JSClass **)outClass andPrototype:(JSObject **)outPrototype
{
	if ([self planetType] == PLANET_TYPE_SUN)
	{
		OOSunGetClassAndPrototype(outClass, outPrototype);
	}
	else
	{
		*outClass = &sPlanetClass.base;
		*outPrototype = sPlanetPrototype;
	}
}


- (NSString *)jsClassName
{
	switch ([self planetType]) {
		case PLANET_TYPE_SUN:
			return @"Sun";
		case PLANET_TYPE_GREEN:
			return @"Planet";
		case PLANET_TYPE_MOON:
			return @"Moon";
		default:
			return @"Unknown";
	}

}

@end


static JSBool PlanetGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	BOOL						OK = NO;
	PlanetEntity				*planet = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSPlanetGetPlanetEntity(context, this, &planet)) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kPlanet_isMainPlanet:
			*outValue = BOOLToJSVal(planet == [UNIVERSE planet]);
			OK = YES;
			break;
			
		case kPlanet_radius:
			OK = JS_NewDoubleValue(context, [planet radius], outValue);
			break;
			
		case kPlanet_hasAtmosphere:
			*outValue = BOOLToJSVal([planet hasAtmosphere]);
			OK = YES;
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"Planet", JSVAL_TO_INT(name));
	}
	return OK;
}


static JSBool PlanetSetTexture(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlanetEntity			*thisEnt = nil;
	NSString				*name = nil;
	PlayerEntity			*player = [PlayerEntity sharedPlayer];
	
	if (!JSPlanetGetPlanetEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	name = [NSString stringWithJavaScriptValue:*argv inContext:context];
	// can now retexture at any time, eg during huge surface explosion
	if (name != nil)
	{
		if ([thisEnt setUpPlanetFromTexture:name])  return YES;
		else  OOReportJSError(context, @"Planet.%@(\"%@\"): cannot set texture for planet.", @"setTexture", name);
	}
	else
	{
		OOReportJSError(context, @"Planet.%@(): no texture name specified.", @"setTexture");
	}
	return NO;
}
