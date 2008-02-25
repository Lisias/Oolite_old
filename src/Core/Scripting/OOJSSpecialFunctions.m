/*

OOJSSpecialFunctions.m


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

#import "OOJSSpecialFunctions.h"


static JSObject		*sSpecialFunctionsObject;


static JSBool SpecialJsWarning(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


static JSFunctionSpec sSpecialFunctionsMethods[] =
{
	// JS name					Function					min args
	{ "jsWarning",				SpecialJsWarning,			1 },
	{ 0 }
};


void InitOOJSSpecialFunctions(JSContext *context, JSObject *global)
{
	sSpecialFunctionsObject = JS_NewObject(context, NULL, NULL, NULL);
	JS_AddNamedRoot(context, &sSpecialFunctionsObject, "OOJSSpecialFunctions");
	JS_DefineFunctions(context, sSpecialFunctionsObject, sSpecialFunctionsMethods);
	JS_SealObject(context, sSpecialFunctionsObject, NO);
}


JSObject *JSSpecialFunctionsObject(void)
{
	return sSpecialFunctionsObject;
}


OOJSValue *JSSpecialFunctionsObjectWrapper(JSContext *context)
{
	return [OOJSValue valueWithJSObject:JSSpecialFunctionsObject() inContext:context];
}


static JSBool SpecialJsWarning(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOSetJSWarningOrErrorStackSkip(1);
	OOReportJavaScriptWarning(context, @"%@", [NSString stringWithJavaScriptValue:argv[0] inContext:context]);
	OOSetJSWarningOrErrorStackSkip(0);
	return YES;
}
