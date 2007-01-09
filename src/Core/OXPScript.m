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

#import "OXPScript.h"

JSClass OXP_class = {
	"OXPScript", JSCLASS_HAS_PRIVATE,
	JS_PropertyStub,JS_PropertyStub,JS_PropertyStub,JS_PropertyStub,
	JS_EnumerateStub,JS_ResolveStub,JS_ConvertStub,JS_FinalizeStub
};

extern NSString *JSValToNSString(JSContext *cx, jsval val);

@implementation OXPScript

- (id) initWithContext: (JSContext *) context andFilename: (NSString *) filename
{
	// Check if file exists before doing anything else
	// ...

	self = [super init];

	obj = JS_NewObject(context, &OXP_class, 0x00, JS_GetGlobalObject(context));
	JS_AddRoot(context, &obj); // note 2nd arg is a pointer-to-pointer

	cx = context;

	jsval rval;
	JSBool ok;
    JSScript *script = JS_CompileFile(context, obj, [filename cString]);
    if (script != 0x00) {
		ok = JS_ExecuteScript(context, obj, script, &rval);
		if (ok) {
			ok = JS_GetProperty(context, obj, "Name", &rval);
			if (ok && JSVAL_IS_STRING(rval)) {
				name = JSValToNSString(context, rval);
			} else {
				// No name given in the script so use the filename
				name = [NSString stringWithString:filename];
			}
			ok = JS_GetProperty(context, obj, "Description", &rval);
			if (ok && JSVAL_IS_STRING(rval)) {
				description = JSValToNSString(context, rval);
			} else {
				description = @"";
			}
			ok = JS_GetProperty(context, obj, "Version", &rval);
			if (ok && JSVAL_IS_STRING(rval)) {
				version = JSValToNSString(context, rval);
			} else {
				version= @"";
			}
			NSLog(@"Loaded JavaScript OXP: %@ %@ %@", name, description, version);
		}
		JS_DestroyScript(context, script);
	}

	return self;
}

- (NSString *) name
{
	return name;
}

- (NSString *) description
{
	return description;
}

- (NSString *) version
{
	return version;
}

//
// Valid event names are "STATUS_DOCKED", "STATUS_EXITING_WITCHSPACE", "STATUS_IN_FLIGHT", and "STATUS_LAUNCHING".
//
- (BOOL) doEvent: (NSString *) eventName
{
	jsval rval;
	JSBool ok;

	ok = JS_GetProperty(cx, obj, [eventName cString], &rval);
	if (ok && !JSVAL_IS_VOID(rval)) {
		JSFunction *func = JS_ValueToFunction(cx, rval);
		if (func != 0x00) {
			ok = JS_CallFunction(cx, obj, func, 0, 0x00, &rval);
			if (ok)
				return YES;
		}
	}

	return NO;
}

@end
