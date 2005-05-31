#import <AppKit/NSApplication.h>

#ifdef GNUSTEP
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSString.h>

#import "GameController.h"

GameController* controller;
#endif

int debug = NO;

int main(int argc, const char *argv[])
{
#ifdef GNUSTEP
	// This is still necessary for NSFont calls.
	[NSApplication sharedApplication];

	// Need this because we're not using the default run loop's autorelease
	// pool.
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	// dajt: allocate and set the NSApplication delegate manually because not
	// using NIB to do this
	controller = [[GameController alloc] init];
	
	// Release anything allocated during the controller initialisation that
	// is no longer required.
	[pool release];

	if (argc > 1)
		[controller setPlayerFileToLoad: [NSString stringWithCString: argv[argc - 1]]];

	// Call applicationDidFinishLaunching because NSApp is not running in
	// GNUstep port.
	[controller applicationDidFinishLaunching: nil];
#else
	return NSApplicationMain(argc, argv);
#endif

	// never reached
	return 0;
}

/*
 * This is called from a couple of places, and having it here saves one more
 * AppKit dependency.
 */
void NSBeep()
{
}
