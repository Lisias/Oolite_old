/*

OODebugController.m


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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2007 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OODebugController.h"

#if OO_INCLUDE_DEBUG_CONTROLLER

#import "ResourceManager.h"

#import "OOGraphicsResetManager.h"
#import "OOTexture.h"
#import "OOLogging.h"
#import "Universe.h"
#import "OOOpenGL.h"
#import "OOCacheManager.h"
#import "PlayerEntity.h"
#import "OOCollectionExtractors.h"


static OODebugController *sSingleton = nil;


@interface OODebugController (Private)

- (void)insertDebugMenu;
- (void)setUpLogMessageClassMenu;

@end


@implementation OODebugController

- (id)init
{
	NSString					*nibPath = nil;
	
	self = [super init];
	if (self != nil)
	{
		_bundle = [[NSBundle bundleForClass:[self class]] retain];
		
		nibPath = [_bundle pathForResource:@"OODebugController" ofType:@"nib"];
		if (nibPath == nil)
		{
			OOLog(@"debugOXP.load.failed", @"Could not find OODebugController.oxp.");
			[self release];
			self = nil;
		}
		else
		{
			[NSBundle loadNibFile:nibPath externalNameTable:[NSDictionary dictionaryWithObject:self forKey:@"NSOwner"] withZone:nil];
			
			[self insertDebugMenu];
			[self setUpLogMessageClassMenu];
			OOLog(@"debugOXP.success", @"Success!");
		}
	}
	
	return self;
}


- (void)dealloc
{
	if (sSingleton == self)  sSingleton = nil;
	
	[menu release];
	[logMessageClassPanel release];
	[logPrefsWindow release];
	[createShipPanel release];
	
	[_bundle release];
	
	[super dealloc];
}


+ (id)sharedDebugController
{
	// NOTE: assumes single-threaded first access. See header.
	if (sSingleton == nil)  [[self alloc] init];
	return sSingleton;
}


- (void)awakeFromNib
{
	[logPrefsWindow center];
}


#pragma mark -

- (IBAction)graphicsResetAction:sender
{
	[[OOGraphicsResetManager sharedManager] resetGraphicsState];
}


- (IBAction)clearTextureCacheAction:sender
{
	[OOTexture clearCache];
}


- (IBAction)resetAndClearAction:sender
{
	[OOTexture clearCache];
	[[OOGraphicsResetManager sharedManager] resetGraphicsState];
}


- (IBAction)dumpEntityListAction:sender
{
	BOOL						wasEnabled;
	
	wasEnabled = OOLogWillDisplayMessagesInClass(@"universe.objectDump");
	OOLogSetDisplayMessagesInClass(@"universe.objectDump", YES);
	
	[UNIVERSE obj_dump];
	
	OOLogSetDisplayMessagesInClass(@"universe.objectDump", wasEnabled);
}


- (IBAction)dumpPlayerStateAction:sender
{
	[[PlayerEntity sharedPlayer] dumpState];
}


- (IBAction)createShipAction:sender
{
	NSString					*role = nil;
	
	role = [[NSUserDefaults standardUserDefaults] stringForKey:@"debug-create-ship-panel-last-role"];
	if (role != nil)
	{
		[createShipPanelTextField setStringValue:role];
	}
	
	[NSApp runModalForWindow:createShipPanel];
	[createShipPanel orderOut:self];
}


- (IBAction)clearAllCachesAction:sender
{
	[[OOCacheManager sharedCache] clearAllCaches];
}


- (IBAction)toggleThisLogMessageClassAction:sender
{
	NSString					*msgClass = nil;
	
	if ([sender respondsToSelector:@selector(representedObject)])
	{
		msgClass = [sender representedObject];
		OOLogSetDisplayMessagesInClass(msgClass, !OOLogWillDisplayMessagesInClass(msgClass));
	}
}


- (IBAction)otherLogMessageClassAction:sender
{
	[NSApp runModalForWindow:logMessageClassPanel];
	[logMessageClassPanel orderOut:self];
}


- (IBAction)logMsgClassPanelEnableAction:sender
{
	NSString					*msgClass = nil;
	
	msgClass = [logMsgClassPanelTextField stringValue];
	if ([msgClass length] != 0)  OOLogSetDisplayMessagesInClass(msgClass, YES);
	
	[NSApp stopModal];
}


- (IBAction)logMsgClassPanelDisableAction:sender
{
	NSString					*msgClass = nil;
	
	msgClass = [logMsgClassPanelTextField stringValue];
	if ([msgClass length] != 0)  OOLogSetDisplayMessagesInClass(msgClass, NO);
	
	[NSApp stopModal];
}


- (IBAction)toggleThisDebugFlagAction:sender
{
	gDebugFlags ^= [sender tag];
}


- (IBAction)showLogPreferencesAction:sender
{
	[logShowAppNameCheckBox setState:OOLogShowApplicationName()];
	[logShowFunctionCheckBox setState:OOLogShowFunction()];
	[logShowFileAndLineCheckBox setState:OOLogShowFileAndLine()];
	[logShowMessageClassCheckBox setState:OOLogShowMessageClass()];
	
	[logPrefsWindow makeKeyAndOrderFront:self];
}


- (IBAction)logSetShowAppNameAction:sender
{
	OOLogSetShowApplicationName([sender state]);
}


- (IBAction)logSetShowFunctionAction:sender
{
	OOLogSetShowFunction([sender state]);
}


- (IBAction)logSetShowFileAndLineAction:sender
{
	OOLogSetShowFileAndLine([sender state]);
}


- (IBAction)logSetShowMessageClassAction:sender
{
	OOLogSetShowMessageClass([sender state]);
}


- (IBAction)insertLogSeparatorAction:sender
{
	OOLogInsertMarker();
}


- (IBAction)createShipPanelOKAction:sender
{
	NSString					*shipRole = nil;
	
	shipRole = [createShipPanelTextField stringValue];
	if ([shipRole length] != 0)
	{
		[self performSelector:@selector(spawnShip:) withObject:shipRole afterDelay:0.1f];
		[[NSUserDefaults standardUserDefaults] setObject:shipRole forKey:@"debug-create-ship-panel-last-role"];
	}
	
	[NSApp stopModal];	
}


- (void)spawnShip:(NSString *)shipRole
{
	[UNIVERSE addShipWithRole:shipRole nearRouteOneAt:1.0];
}


- (IBAction)modalPanelCancelAction:sender
{
	[NSApp stopModal];
}


#pragma mark -

- (BOOL)validateMenuItem:(id <NSMenuItem>)menuItem
{
	SEL							action = NULL;
	NSString					*msgClass = nil;
	uint32_t					tag;
	
	action = [menuItem action];
	
	if (action == @selector(toggleThisLogMessageClassAction:))
	{
		msgClass = [menuItem representedObject];
		[menuItem setState:OOLogWillDisplayMessagesInClass(msgClass)];
		return YES;
	}
	if (action == @selector(toggleThisDebugFlagAction:))
	{
		tag = [menuItem tag];
		[menuItem setState:(gDebugFlags & tag) == tag];
		return YES;
	}
	
	return [self respondsToSelector:action];
}

@end


@implementation OODebugController (Private)

- (void)insertDebugMenu
{
	NSMenuItem					*item = nil;
	
	[menu setTitle:@"Debug"];
	item = [[NSMenuItem alloc] initWithTitle:@"Debug" action:nil keyEquivalent:@""];
	[item setSubmenu:menu];
	[[NSApp mainMenu] addItem:item];
	[item release];
}


- (void)setUpLogMessageClassMenu
{
	NSArray						*definitions = nil;
	unsigned					i, count, inserted = 0;
	NSString					*title = nil, *key = nil;
	NSMenuItem					*item = nil;
	
	definitions = [ResourceManager arrayFromFilesNamed:@"debugLogMessageClassesMenu.plist" inFolder:@"Config" andMerge:YES];
	count = [definitions count] / 2;
	
	for (i = 0; i != count; ++i)
	{
		title = [definitions stringAtIndex:i * 2];
		key = [definitions stringAtIndex:i * 2 + 1];
		if (title == nil || key == nil)  continue;
		
		item = [[NSMenuItem alloc] initWithTitle:title
										  action:@selector(toggleThisLogMessageClassAction:)
								   keyEquivalent:@""];
		[item setTarget:self];
		[item setRepresentedObject:key];
		
		[logMessageClassSubMenu insertItem:item atIndex:inserted++];
		[item release];
	}
}

@end


@implementation OODebugController (Singleton)

/*	Canonical singleton boilerplate.
	See Cocoa Fundamentals Guide: Creating a Singleton Instance.
	See also +sharedDebugController above.
*/

+ (id)allocWithZone:(NSZone *)inZone
{
	if (sSingleton == nil)
	{
		sSingleton = [super allocWithZone:inZone];
		return sSingleton;
	}
	return nil;
}


- (id)copyWithZone:(NSZone *)inZone
{
	return self;
}


- (id)retain
{
	return self;
}


- (unsigned)retainCount
{
	return UINT_MAX;
}


- (void)release
{}


- (id)autorelease
{
	return self;
}

@end

#endif	// NDEBUG
