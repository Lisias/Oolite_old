/*

OOJSScript.h

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


#import "OOScript.h"
#import "OOWeakReference.h"
#import <jsapi.h>


@interface OOJSScript: OOScript <OOWeakReferenceSupport>
{
	JSContext			*context;
	JSObject			*object;
	
	NSString			*name;
	NSString			*description;
	NSString			*version;
	
	OOWeakReference		*weakSelf;
}

+ (id)scriptWithPath:(NSString *)path properties:(NSDictionary *)properties;

- (id)initWithPath:(NSString *)path properties:(NSDictionary *)properties;
- (id)initWithPath:(NSString *)path properties:(NSDictionary *)properties context:(JSContext *)context;

+ (OOJSScript *)currentlyRunningScript;
+ (NSArray *)scriptStack;

@end


void InitOOJSScript(JSContext *context, JSObject *global);

