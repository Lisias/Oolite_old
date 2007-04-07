/*

OOJSVector.m

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


#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import <objc/objc-runtime.h>
#import "OOConstToString.h"
#import "OOJSEntity.h"
#import "OOJSQuaternion.h"


static JSObject *sVectorPrototype;


static JSBool VectorGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool VectorSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);
static JSBool VectorConvert(JSContext *context, JSObject *this, JSType type, jsval *outValue);
static void VectorFinalize(JSContext *context, JSObject *this);
static JSBool VectorConstruct(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorEquality(JSContext *context, JSObject *this, jsval value, JSBool *outEqual);

// Methods
static JSBool VectorAdd(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorSubtract(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorDistanceTo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorSquaredDistanceTo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorMultiply(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorDot(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorAngleTo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorCross(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorTripleProduct(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorDirection(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorMagnitude(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorSquaredMagnitude(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorRotationTo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


static JSExtendedClass sVectorClass =
{
	{
		"Vector",
		JSCLASS_HAS_PRIVATE | JSCLASS_IS_EXTENDED,
		
		JS_PropertyStub,		// addProperty
		JS_PropertyStub,		// delProperty
		VectorGetProperty,		// getProperty
		VectorSetProperty,		// setProperty
		JS_EnumerateStub,		// enumerate
		JS_ResolveStub,			// resolve
		VectorConvert,			// convert
		VectorFinalize,			// finalize
		JSCLASS_NO_OPTIONAL_MEMBERS
	},
	VectorEquality,				// equality
	NULL,						// outerObject
	NULL,						// innerObject
	JSCLASS_NO_RESERVED_MEMBERS
};


enum
{
	// Property IDs
	kVector_x,
	kVector_y,
	kVector_z
};


static JSPropertySpec sVectorProperties[] =
{
	// JS name					ID							flags
	{ "x",						kVector_x,					JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "y",						kVector_y,					JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "z",						kVector_z,					JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ 0 }
};


static JSFunctionSpec sVectorMethods[] =
{
	// JS name					Function					min args
	{ "add",					VectorAdd,					1, },
	{ "subtract",				VectorSubtract,				1, },
	{ "distanceTo",				VectorDistanceTo,			1, },
	{ "squaredDistanceTo",		VectorSquaredDistanceTo,	1, },
	{ "multiply",				VectorMultiply,				1, },
	{ "dot",					VectorDot,					1, },
	{ "angleTo",				VectorAngleTo,				1, },
	{ "cross",					VectorCross,				1, },
	{ "tripleProduct",			VectorTripleProduct,		2, },
	{ "direction",				VectorDirection,			0, },
	{ "magnitude",				VectorMagnitude,			0, },
	{ "squaredMagnitude",		VectorSquaredMagnitude,		0, },
//	{ "rotateBy",				VectorRotateBy,				1, },	// TODO: Vector rotateBy(quaternionExpression)
	{ "rotationTo",				VectorRotationTo,			1, },
	{ 0 }
};


// *** Public ***

void InitOOJSVector(JSContext *context, JSObject *global)
{
    sVectorPrototype = JS_InitClass(context, global, NULL, &sVectorClass.base, VectorConstruct, 0, sVectorProperties, sVectorMethods, NULL, NULL);
}


JSObject *JSVectorWithVector(JSContext *context, Vector vector)
{
	JSObject				*result = NULL;
	Vector					*private = NULL;
	
	if (context == NULL) context = [[OOJavaScriptEngine sharedEngine] context];
	
	private = malloc(sizeof *private);
	if (private == NULL)  return NULL;
	
	*private = vector;
	
	result = JS_NewObject(context, &sVectorClass.base, sVectorPrototype, NULL);
	if (result != NULL)
	{
		if (!JS_SetPrivate(context, result, private))  result = NULL;
	}
	
	if (result == NULL) free(private);
	
	return result;
}


BOOL VectorToJSValue(JSContext *context, Vector vector, jsval *outValue)
{
	JSObject				*object = NULL;
	
	if (outValue == NULL) return NO;
	if (EXPECT_NOT(context == NULL))  context = [[OOJavaScriptEngine sharedEngine] context];
	
	object = JSVectorWithVector(context, vector);
	if (object == NULL) return NO;
	
	*outValue = OBJECT_TO_JSVAL(object);
	return YES;
}


BOOL JSValueToVector(JSContext *context, jsval value, Vector *outVector)
{
	if (!JSVAL_IS_OBJECT(value))  return NO;
	
	return JSVectorGetVector(context, JSVAL_TO_OBJECT(value), outVector);
}


BOOL JSVectorGetVector(JSContext *context, JSObject *vectorObj, Vector *outVector)
{
	Vector					*private = NULL;
	Entity					*entity = nil;
	
	if (outVector == NULL || vectorObj == NULL) return NO;
	if (EXPECT_NOT(context == NULL))  context = [[OOJavaScriptEngine sharedEngine] context];
	
	private = JS_GetInstancePrivate(context, vectorObj, &sVectorClass.base, NULL);
	if (private != NULL)	// If this is a (JS) Vector...
	{
		*outVector = *private;
		return YES;
	}
	
	// If it's an entity, use its position.
	if (JSEntityGetEntity(context, vectorObj, &entity))
	{
		*outVector = [entity position];
		return YES;
	}
	
	return NO;
}


BOOL JSVectorSetVector(JSContext *context, JSObject *vectorObj, Vector vector)
{
	Vector					*private = NULL;
	
	if (vectorObj == NULL) return NO;
	if (EXPECT_NOT(context == NULL))  context = [[OOJavaScriptEngine sharedEngine] context];
	
	private = JS_GetInstancePrivate(context, vectorObj, &sVectorClass.base, NULL);
	if (private != NULL)	// If this is a (JS) Vector...
	{
		*private = vector;
		return YES;
	}
	
	return NO;
}


BOOL VectorFromArgumentList(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, Vector *outVector, uintN *outConsumed)
{
	double				x, y, z;
	
	// Sanity checks.
	if (outConsumed != NULL)  *outConsumed = 0;
	if (EXPECT_NOT(argc == 0 || argv == NULL || outVector == NULL))
	{
		OOLogGenericParameterError();
		return NO;
	}
	
	if (EXPECT_NOT(context == NULL))  context = [[OOJavaScriptEngine sharedEngine] context];
	
	// Is first object a vector or entity?
	if (JSVAL_IS_OBJECT(argv[0]))
	{
		if (JSVectorGetVector(context, JSVAL_TO_OBJECT(argv[0]), outVector))
		{
			if (outConsumed != NULL)  *outConsumed = 1;
			return YES;
		}
	}
	
	// Otherwise, look for three numbers.
	if (argc < 3)  goto FAIL;
	
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[0], &x)))  goto FAIL;
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[1], &y)))  goto FAIL;
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[2], &z)))  goto FAIL;
	
	// Given a string, JS_ValueToNumber() returns YES but provides a NaN number.
	if (EXPECT_NOT(isnan(x) || isnan(y) || isnan(z))) goto FAIL;
	
	// We got our three numbers.
	*outVector = make_vector(x, y, z);
	if (outConsumed != NULL)  *outConsumed = 3;
	return YES;
	
FAIL:
	// Report bad parameters, if given a class and function.
	if (scriptClass != nil && function != nil)
	{
		OOReportJavaScriptWarning(context, @"%@.%@(): could not construct vector from parameters %@ -- expected Vector, Entity or three numbers.", scriptClass, function, [NSString stringWithJavaScriptParameters:argv count:argc inContext:context]);
	}
	return NO;
}


// *** Implementation stuff ***

static JSBool VectorGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	Vector				vector;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSVectorGetVector(context, this, &vector)) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kVector_x:
			JS_NewDoubleValue(context, vector.x, outValue);
			break;
		
		case kVector_y:
			JS_NewDoubleValue(context, vector.y, outValue);
			break;
		
		case kVector_z:
			JS_NewDoubleValue(context, vector.z, outValue);
			break;
		
		default:
			return YES;
	}
	
	return YES;
}


static JSBool VectorSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	Vector				vector;
	jsdouble			dval;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSVectorGetVector(context, this, &vector)) return NO;
	JS_ValueToNumber(context, *value, &dval);
	
	switch (JSVAL_TO_INT(name))
	{
		case kVector_x:
			vector.x = dval;
			break;
		
		case kVector_y:
			vector.y = dval;
			break;
		
		case kVector_z:
			vector.z = dval;
			break;
		
		default:
			return YES;
	}
	
	return JSVectorSetVector(context, this, vector);
}


static JSBool VectorConvert(JSContext *context, JSObject *this, JSType type, jsval *outValue)
{
	Vector					vector;
	
	switch (type)
	{
		case JSTYPE_VOID:		// Used for string concatenation.
		case JSTYPE_STRING:
			// Return description of vector
			if (!JSVectorGetVector(context, this, &vector))  return NO;
			*outValue = [VectorDescription(vector) javaScriptValueInContext:context];
			return YES;
		
		default:
			// Contrary to what passes for documentation, JS_ConvertStub is not a no-op.
			return JS_ConvertStub(context, this, type, outValue);
	}
}


static void VectorFinalize(JSContext *context, JSObject *this)
{
	Vector					*private = NULL;
	
	private = JS_GetInstancePrivate(context, this, &sVectorClass.base, NULL);
	if (private != NULL)
	{
		free(private);
	}
}


static JSBool VectorConstruct(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					vector = kZeroVector;
	Vector					*private = NULL;
	
	private = malloc(sizeof *private);
	if (private == NULL)  return NO;
	
	if (argc != 0) VectorFromArgumentList(context, NULL, NULL, argc, argv, &vector, NULL);
	
	*private = vector;
	
	if (!JS_SetPrivate(context, this, private))
	{
		free(private);
		return NO;
	}
	
	return YES;
}


static JSBool VectorEquality(JSContext *context, JSObject *this, jsval value, JSBool *outEqual)
{
	Vector					thisv, thatv;
	
	*outEqual = NO;
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	if (!JSVAL_IS_OBJECT(value)) return YES;
	if (!JSVectorGetVector(context, JSVAL_TO_OBJECT(value), &thatv)) return YES;
	
	*outEqual = vector_equal(thisv, thatv);
	return YES;
}


// *** Methods ***

// Vector add(vectorExpression)
static JSBool VectorAdd(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv, result;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	if (!VectorFromArgumentList(context, @"Vector", @"add", argc, argv, &thatv, NULL))  return YES;
	
	result = vector_add(thisv, thatv);
	
	return VectorToJSValue(context, result, outResult);
}


// Vector subtract(vectorExpression)
static JSBool VectorSubtract(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv, result;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	if (!VectorFromArgumentList(context, @"Vector", @"subtract", argc, argv, &thatv, NULL))  return YES;
	
	result = vector_subtract(thisv, thatv);
	
	return VectorToJSValue(context, result, outResult);
}


// Vector distanceTo(vectorExpression)
static JSBool VectorDistanceTo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv;
	GLfloat					result;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	if (!VectorFromArgumentList(context, @"Vector", @"distanceTo", argc, argv, &thatv, NULL))  return YES;
	
	result = distance(thisv, thatv);
	
	return JS_NewDoubleValue(context, result, outResult);
}


// Vector squaredDistanceTo(vectorExpression)
static JSBool VectorSquaredDistanceTo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv;
	GLfloat					result;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	if (!VectorFromArgumentList(context, @"Vector", @"squaredDistanceTo", argc, argv, &thatv, NULL))  return YES;
	
	result = distance2(thisv, thatv);
	
	return JS_NewDoubleValue(context, result, outResult);
}


// Vector multiply(double)
static JSBool VectorMultiply(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, result;
	double					scalar;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	if (!NumberFromArgumentList(context, @"Vector", @"multiply", argc, argv, &scalar, NULL))  return YES;
	
	result = vector_multiply_scalar(thisv, scalar);
	
	return VectorToJSValue(context, result, outResult);
}


// Vector dot(vectorExpression)
static JSBool VectorDot(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv;
	GLfloat					result;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	if (!VectorFromArgumentList(context, @"Vector", @"dot", argc, argv, &thatv, NULL))  return YES;
	
	result = dot_product(thisv, thatv);
	
	return JS_NewDoubleValue(context, result, outResult);
}


// double angleTo(vectorExpression)
static JSBool VectorAngleTo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv;
	GLfloat					result;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	if (!VectorFromArgumentList(context, @"Vector", @"angleTo", argc, argv, &thatv, NULL))  return YES;
	
	result = acosf(dot_product(vector_normal(thisv), vector_normal(thatv)));
	
	return JS_NewDoubleValue(context, result, outResult);
}


// Vector cross(vectorExpression)
static JSBool VectorCross(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv, result;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	if (!VectorFromArgumentList(context, @"Vector", @"cross", argc, argv, &thatv, NULL))  return YES;
	
	result = true_cross_product(thisv, thatv);
	
	return VectorToJSValue(context, result, outResult);
}


// Vector tripleProduct(vectorExpression, vectorExpression)
static JSBool VectorTripleProduct(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv, theotherv;
	GLfloat					result;
	uintN					consumed;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	if (!VectorFromArgumentList(context, @"Vector", @"tripleProduct", argc, argv, &thatv, &consumed))  return YES;
	argc += consumed;
	argv += consumed;
	if (!VectorFromArgumentList(context, @"Vector", @"tripleProduct", argc, argv, &theotherv, NULL))  return YES;
	
	result = triple_product(thisv, thatv, theotherv);
	
	return JS_NewDoubleValue(context, result, outResult);
}


// Vector direction()
static JSBool VectorDirection(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, result;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	
	result = vector_normal(thisv);
	
	return VectorToJSValue(context, result, outResult);
}


// double magnitude()
static JSBool VectorMagnitude(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv;
	GLfloat					result;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	
	result = magnitude(thisv);
	
	return JS_NewDoubleValue(context, result, outResult);
}


// double squaredMagnitude()
static JSBool VectorSquaredMagnitude(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv;
	GLfloat					result;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	
	result = magnitude2(thisv);
	
	return JS_NewDoubleValue(context, result, outResult);
}


// Quaternion rotationTo(vectorExpression)
static JSBool VectorRotationTo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv;
	double					limit;
	BOOL					gotLimit;
	Quaternion				result;
	uintN					consumed;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	if (!VectorFromArgumentList(context, @"Vector", @"rotationTo", argc, argv, &thatv, &consumed))  return YES;
	
	argc += consumed;
	argv += consumed;
	if (argc != 0)	// limit parameter is optional.
	{
		if (!NumberFromArgumentList(context, @"Vector", @"rotationTo", argc, argv, &limit,NULL))  return YES;
		gotLimit = YES;
	}
	else gotLimit = NO;
	
	if (gotLimit)  result = quaternion_limited_rotation_between(thisv, thatv, limit);
	else  result = quaternion_rotation_between(thisv, thatv);
	
	return QuaternionToJSValue(context, result, outResult);
}
