/*

main.m

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

#import <AppKit/NSApplication.h>

#ifdef GNUSTEP
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSString.h>

#import "GameController.h"
#import "OOLoggingExtended.h"

GameController* controller;
#endif


#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


#ifdef OOLITE_SDL_MAC
#define main SDL_main
#endif


int main(int argc, char *argv[])
{
#ifdef GNUSTEP
	int i;
	
#if OOLITE_WINDOWS
	/*	Windows amibtiously starts apps with the C library locale set to the
		system locale rather than the "C" locale as per spec. Fixing here so
		numbers don't behave strangely.
	*/
	setlocale("C");
#endif

	// Need this because we're not using the default run loop's autorelease
	// pool.
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	OOLoggingInit();

	// dajt: allocate and set the NSApplication delegate manually because not
	// using NIB to do this
	controller = [[GameController alloc] init];
	
	// Release anything allocated during the controller initialisation that
	// is no longer required.
	[pool release];

	for (i = 1; i < argc; i++)
	{
		// The commented out lines below do not seem to do anything, at least on Windows.
		// The -fullscreen argument processing has been implemented in the loadFullscreenSettings
		// method, inside src/SDL/MyOpenGLView.m.
		/*
		 -------- Begin commented out section --------
		if (strcmp("-fullscreen", argv[i]) == 0)
			[controller setFullScreenMode: YES];
		--------- End commented out section --------
		*/

		if (strcmp("-load", argv[i]) == 0)
		{
			i++;
			if (i < argc)
				[controller setPlayerFileToLoad: [NSString stringWithCString: argv[i]]];
		}
	}

	// Call applicationDidFinishLaunching because NSApp is not running in
	// GNUstep port.
	[controller applicationDidFinishLaunching: nil];
#endif

	// never reached
	return 0;
}


#if OOLITE_SDL_MAC

@implementation NSWindow (SDLBugWorkaround)

- (void)release
{}

@end

#endif
