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


#import <Foundation/Foundation.h>
#import "Universe.h"
#import "PlayerEntity.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import <jsapi.h>

#define OOJSENGINE_MONITOR_SUPPORT	(!defined(NDEBUG))


@protocol OOJavaScriptEngineMonitor;


@interface OOJavaScriptEngine : NSObject
{
	JSRuntime						*runtime;
	JSContext						*context;
	JSObject						*globalObject;
#if OOJSENGINE_MONITOR_SUPPORT
	id<OOJavaScriptEngineMonitor>	monitor;
#endif
}

+ (OOJavaScriptEngine *)sharedEngine;

- (JSContext *) context;

@end


void OOReportJavaScriptError(JSContext *context, NSString *format, ...);
void OOReportJavaScriptErrorWithArguments(JSContext *context, NSString *format, va_list args);
void OOReportJavaScriptWarning(JSContext *context, NSString *format, ...);
void OOReportJavaScriptWarningWithArguments(JSContext *context, NSString *format, va_list args);
void OOReportJavaScriptBadPropertySelector(JSContext *context, NSString *className, jsint selector);

/*	NumberFromArgumentList()
	
	Get a single number from an argument list. The optional outConsumed
	argument can be used to find out how many parameters were used (currently,
	this will be 0 on failure, otherwise 1).
	
	On failure, it will return NO, annd the number will be unaltered. If
	scriptClass and function are non-nil, a warning will be reported to the
	log.
*/
BOOL NumberFromArgumentList(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, double *outNumber, uintN *outConsumed);


/*	JSArrayFromArray()
	JSNewNSArrayValue()
	
	Convert an ObjC array to a JavaScript array.
	
	JSNewNSArrayValue() will return YES and set value to JSVAL_NULL if passed
	a nil array, but return NO and set value to JSVAL_VOID on failure.
	JSArrayFromArray() will return NULL if the count is 0 or if it fails.
*/
JSObject *JSArrayFromNSArray(JSContext *context, NSArray *array);
BOOL JSNewNSArrayValue(JSContext *context, NSArray *array, jsval *value);


OOINLINE jsval BOOLToJSVal(BOOL b) INLINE_CONST_FUNC;
OOINLINE jsval BOOLToJSVal(BOOL b)
{
	return BOOLEAN_TO_JSVAL(b != NO);
}


@interface NSObject (OOJavaScriptConversion)

/*	-javaScriptValueInContext:
	
	Return the JavaScript object representation of an object. The default
	implementation returns JSVAL_VOID. At this time, NSString, NSNumber,
	NSArray, NSNull, Entity and OOScript override this.
*/
- (jsval)javaScriptValueInContext:(JSContext *)context;

@end


@interface NSString (OOJavaScriptExtensions)

// Convert a JSString to an NSString.
+ (id)stringWithJavaScriptString:(JSString *)string;

// Convert an arbitrary JS object to an NSString, using JS_ValueToString.
+ (id)stringWithJavaScriptValue:(jsval)value inContext:(JSContext *)context;

// For diagnostic messages; produces things like @"(42, true, "a string", an object description)".
+ (id)stringWithJavaScriptParameters:(jsval *)params count:(uintN)count inContext:(JSContext *)context;

// Concatenate sequence of arbitrary JS objects into string.
+ (id)concatenationOfStringsFromJavaScriptValues:(jsval *)values count:(size_t)count separator:(NSString *)separator inContext:(JSContext *)context;

@end


OOINLINE NSString *JSValToNSString(JSContext *context, jsval value)
{
	return [NSString stringWithJavaScriptValue:value inContext:context];
}


NSString *JSPropertyAsString(JSContext *context, JSObject *object, const char *name);


id JSValueToObject(JSContext *context, jsval value);
id JSObjectToObject(JSContext *context, JSObject *object);


/*	Support for JSValueToObject()
	
	JSClassConverterCallback specifies the prototype for a callback function
	which converts a JavaScript object to an Objective-C object.
	
	JSBasicPrivateObjectConverter() is a JSClassConverterCallback which
	returns the JS object's private storage value. It automatically unpacks
	OOWeakReferences if relevant.
	
	JSRegisterObjectConverter() registers a callback for a specific JS class.
	It is not automatically propagated to subclasses.
*/
typedef id (*JSClassConverterCallback)(JSContext *context, JSObject *object);
id JSBasicPrivateObjectConverter(JSContext *context, JSObject *object);

void JSRegisterObjectConverter(JSClass *theClass, JSClassConverterCallback converter);


#if OOJSENGINE_MONITOR_SUPPORT

/*	Protocol for debugging "monitor" object.
	The monitor is an object -- in Oolite, or via Distributed Objects -- which
	is provided with debugging information by the OOJavaScriptEngine.
	Currently, this is implemented in the Debug OXP for Mac OS X only.
*/

@protocol OOJavaScriptEngineMonitor <NSObject>

// Sent for JS errors or warnings.
- (oneway void)jsEngine:(in byref OOJavaScriptEngine *)engine
				context:(in JSContext *)context
				  error:(in JSErrorReport *)errorReport
			withMessage:(in NSString *)message;

// Sent for JS log messages. Note: messageClass will be nil of Log() is used rather than LogWithClass().
- (oneway void)jsEngine:(in byref OOJavaScriptEngine *)engine
				context:(in JSContext *)context
			 logMessage:(in NSString *)message
				ofClass:(in NSString *)messageClass;

@end


@interface OOJavaScriptEngine (OOMonitorSupport)

- (void)setMonitor:(id<OOJavaScriptEngineMonitor>)monitor;

@end

#endif
