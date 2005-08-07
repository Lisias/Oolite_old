/*
 *
 *  Oolite
 *
 *  Created by Giles Williams on Sat Apr 03 2004.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

Copyright (c) 2004, Giles C Williams
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


#import "GameController.h"
#import "Universe.h"
#import "ResourceManager.h"
#import "MyOpenGLView.h"
#import "TextureStore.h"

#ifdef LINUX
#include "oolite-linux.h"
#else
#import <OpenGL/OpenGL.h>
#endif

@implementation GameController

- (id) init
{
    self = [super init];
    //
	//NSLog(@"--- init GameController");
	//
   last_timeInterval = [NSDate timeIntervalSinceReferenceDate];
    delta_t = 0.01; // one hundredth of a second
	//
	my_mouse_x = my_mouse_y = 0;
	//
	playerFileToLoad = nil;
	expansionPathsToInclude = nil;
	pauseSelector = (SEL)nil;
	pauseTarget = nil;
	//
	game_is_paused = NO;
	
	//
	
    //
    return self;
}

- (void) dealloc
{
#ifndef GNUSTEP
	[[[NSWorkspace sharedWorkspace] notificationCenter]	removeObserver:universe];
#endif
	//
    if (timer)		[timer release];
    if (gameView)	[gameView release];
    if (universe)	[universe release];
	//
    if (playerFileToLoad)	[playerFileToLoad release];
    if (expansionPathsToInclude)	[expansionPathsToInclude release];
	//
    [super dealloc];
}

- (BOOL) game_is_paused
{
	return game_is_paused;
}

- (void) pause_game
{
	game_is_paused = YES;
}

- (void) unpause_game
{
	game_is_paused = NO;
}

- (BOOL) setDisplayWidth:(unsigned int) d_width Height:(unsigned int) d_height Refresh:(unsigned int) d_refresh
{
	NSDictionary *d_mode = [self findDisplayModeForWidth: d_width Height: d_height Refresh: d_refresh];
	if (d_mode)
	{
		// do stuff
		width = d_width;
		height = d_height;
		refresh = d_refresh;
		fullscreenDisplayMode = d_mode;
		//
		[[NSUserDefaults standardUserDefaults]   setInteger:width   forKey:@"display_width"];
		[[NSUserDefaults standardUserDefaults]   setInteger:height  forKey:@"display_height"];
		[[NSUserDefaults standardUserDefaults]   setInteger:refresh forKey:@"display_refresh"];
		//
		return YES;
	}
	return NO;
}

- (int) indexOfCurrentDisplayMode
{
   // TODO: see if fullscreen is actually practical with GNUstep
#ifndef GNUSTEP
    NSDictionary *mode;
	
	//NSLog(@"looking for a display mode that's %d x %d %dHz",width, height, refresh);
	
	mode = [self findDisplayModeForWidth: width Height: height Refresh: refresh];
	if (mode == nil)
		return NSNotFound;
	else
		return [displayModes indexOfObject:mode];
#else
   return NSNotFound; 
#endif   
}

- (NSDictionary *) findDisplayModeForWidth:(unsigned int) d_width Height:(unsigned int) d_height Refresh:(unsigned int) d_refresh
{
#ifndef GNUSTEP
    int i, modeCount;
    NSDictionary *mode;
    unsigned int modeWidth, modeHeight, modeRefresh;
	
    modeCount = [displayModes count];

	for (i = 0; i < modeCount; i++)
	{
        mode = [displayModes objectAtIndex: i];
        modeWidth = [[mode objectForKey: (NSString *)kCGDisplayWidth] intValue];
        modeHeight = [[mode objectForKey: (NSString *)kCGDisplayHeight] intValue];
        modeRefresh = [[mode objectForKey: (NSString *)kCGDisplayRefreshRate] intValue];
		if ((modeWidth == d_width)&&(modeHeight == d_height)&&(modeRefresh == d_refresh))
			return mode;
	}
#endif

	return nil;
}

- (NSArray *) displayModes
{
	return [NSArray arrayWithArray:displayModes];
}

/* GDC Example code here */

#ifndef GNUSTEP
static int _compareModes(id arg1, id arg2, void *context)
{
   // TODO: If fullscreen mode is practical in GNUstep
    NSDictionary *mode1 = (NSDictionary *)arg1;
    NSDictionary *mode2 = (NSDictionary *)arg2;
    int size1, size2;
    
    // Sort first on pixel count
    size1 = [[mode1 objectForKey: (NSString *)kCGDisplayWidth] intValue] *
            [[mode1 objectForKey: (NSString *)kCGDisplayHeight] intValue];
    size2 = [[mode2 objectForKey: (NSString *)kCGDisplayWidth] intValue] *
            [[mode2 objectForKey: (NSString *)kCGDisplayHeight] intValue];
    if (size1 != size2)
        return size1 - size2;
        
    // Then on refresh rate
    return (int)[[mode1 objectForKey: (NSString *)kCGDisplayRefreshRate] intValue] -
           (int)[[mode2 objectForKey: (NSString *)kCGDisplayRefreshRate] intValue];
}
#endif

- (void) getDisplayModes
{
#ifndef GNUSTEP
    unsigned int modeIndex, modeCount;
    NSArray *modes;
    NSDictionary *mode;
    unsigned int modeWidth, modeHeight, color, modeRefresh, flags;
	
    // Get the list of all available modes
    modes = [(NSArray *)CGDisplayAvailableModes(kCGDirectMainDisplay) retain];
    
    // Filter out modes that we don't want
    displayModes = [[NSMutableArray alloc] init];
    modeCount = [modes count];
    for (modeIndex = 0; modeIndex < modeCount; modeIndex++)
	{
        mode = [modes objectAtIndex: modeIndex];
        modeWidth = [[mode objectForKey: (NSString *)kCGDisplayWidth] intValue];
        modeHeight = [[mode objectForKey: (NSString *)kCGDisplayHeight] intValue];
        color = [[mode objectForKey: (NSString *)kCGDisplayBitsPerPixel] intValue];
        modeRefresh = [[mode objectForKey: (NSString *)kCGDisplayRefreshRate] intValue];
        flags = [[mode objectForKey: (NSString *)kCGDisplayIOFlags] intValue];
        
        if ((color < DISPLAY_MIN_COLOURS)||(modeWidth < DISPLAY_MIN_WIDTH)||(modeWidth > DISPLAY_MAX_WIDTH)||(modeHeight < DISPLAY_MIN_HEIGHT)||(modeHeight > DISPLAY_MAX_HEIGHT))
            continue;
        [displayModes addObject: mode];
    }

    // Sort the filtered modes
    [displayModes sortUsingFunction: _compareModes context: NULL];

	// ***JESTER_START*** 11/08/04
	// Powerbooks return several "identical modes" CGDisplayAvailableModes doesn't appear
	// to pick up refresh rates. Logged as Radar 3759831.
	// In order to deal with this, we'll just edit out the duplicates.
	
	unsigned int j;
	for(j = 0, mode = [displayModes objectAtIndex: j]; j + 1 < [displayModes count];)
	{
		modeWidth = [[mode objectForKey: (NSString *)kCGDisplayWidth] intValue];
		modeHeight = [[mode objectForKey: (NSString *)kCGDisplayHeight] intValue];
		modeRefresh = [[mode objectForKey: (NSString *)kCGDisplayRefreshRate] intValue];

		do
		{
			j = j + 1;
			NSDictionary *mode2 = [displayModes objectAtIndex: j];
			int modeWidth2 = [[mode2 objectForKey: (NSString *)kCGDisplayWidth] intValue];
			int modeHeight2 = [[mode2 objectForKey: (NSString *)kCGDisplayHeight] intValue];
			int modeRefresh2 = [[mode2 objectForKey: (NSString *)kCGDisplayRefreshRate] intValue];
			if(modeWidth == modeWidth2 && modeHeight == modeHeight2 && modeRefresh == modeRefresh2)
			{
				[displayModes removeObjectsFromIndices: &j numIndices: 1];
				j = j - 1;
			}
			else
			{
				mode = mode2;
				break;
			}
		} while(j + 1 < [displayModes count]);
	}
	// ***JESTER_END*** 11/08/04

    // Fill the popup with the resulting modes
    modeCount = [displayModes count];

    //NSLog(@"displayModes = %@", displayModes);
    int i;
	for (i = 0; i < modeCount; i++)
	{
        mode = [displayModes objectAtIndex: i];
        modeWidth = [[mode objectForKey: (NSString *)kCGDisplayWidth] intValue];
        modeHeight = [[mode objectForKey: (NSString *)kCGDisplayHeight] intValue];
        modeRefresh = [[mode objectForKey: (NSString *)kCGDisplayRefreshRate] intValue];
		//NSLog(@"()=> %d x %d at %dHz", modeWidth, modeHeight, modeRefresh);
	}
#endif // ifndef GNUSTEP
}
/* end GDC */

- (MyOpenGLView *) gameView
{
    return gameView;
}

- (Universe *) universe
{
    return universe;
}

- (void) setUniverse:(Universe *) theUniverse
{
    if (universe)	[universe release];
    universe = [theUniverse retain];
	if (gameView)   [universe setGameView:gameView];
}

- (void) setGameView:(MyOpenGLView *)view
{
    if (gameView)	[gameView release];
    gameView = [view retain];
	if (universe)   [universe setGameView:gameView];
	[gameView setGameController:self];
}



- (void) applicationDidFinishLaunching: (NSNotification*) notification
{
#ifdef GNUSTEP
	// A bunch of things get allocated while this method runs and an autorelease pool
	// is required. The one from main had to be released already because we never go
	// back there under GNUstep.
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	gameView = [MyOpenGLView alloc];
	[gameView setFullScreenMode: fullscreen];
	[gameView initWithFrame: NSMakeRect(0, 0, DISPLAY_MIN_WIDTH, DISPLAY_MIN_HEIGHT)];
	[gameView setGameController: self];
#endif

	//
	// ensure the gameView is drawn to, so OpenGL is initialised and so textures can initialse.
	//
	[gameView drawRect:[gameView bounds]];
	
	[self beginSplashScreen];
	[self logProgress:@"initialising..."];
	//
	// check user defaults
	//
	width = DISPLAY_MIN_WIDTH;	//  standard screen is 640x480 pixels, 32 bit color, 32 bit z-buffer, refresh rate 75Hz
	height = DISPLAY_MIN_HEIGHT;
    colorBits = 32;
    depthBits = 32;
    refresh = 75;
	//
	//NSLog(@"--- loading userdefaults");
	//
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	//
	if ([userDefaults objectForKey:@"display_width"])
		width = [userDefaults integerForKey:@"display_width"];
	if ([userDefaults objectForKey:@"display_height"])
		height = [userDefaults integerForKey:@"display_height"];
	if ([userDefaults objectForKey:@"display_refresh"])
		refresh = [userDefaults integerForKey:@"display_refresh"];
	
	/* GDC example code */

	[self logProgress:@"getting display modes..."];
	[self getDisplayModes];
	
	/* end GDC */
   
	fullscreenDisplayMode = [self findDisplayModeForWidth:width Height:height Refresh:refresh];
	if (fullscreenDisplayMode == nil)
	{
		// set full screen mode to first available mode
		fullscreenDisplayMode = [displayModes objectAtIndex:0];
#ifndef GNUSTEP
        width = [[fullscreenDisplayMode objectForKey: (NSString *)kCGDisplayWidth] intValue];
        height = [[fullscreenDisplayMode objectForKey: (NSString *)kCGDisplayHeight] intValue];
        refresh = [[fullscreenDisplayMode objectForKey: (NSString *)kCGDisplayRefreshRate] intValue];
#endif
	}
	
	// moved to before the Universe is created
	[self logProgress:@"loading selected expansion packs..."];
	if (expansionPathsToInclude)
	{
		int i;
		for (i = 0; i < [expansionPathsToInclude count]; i++)
			[ResourceManager addExternalPath: (NSString*)[expansionPathsToInclude objectAtIndex: i]];
	}
	
    // moved here to try to avoid initialising this before having an Open GL context
	[self logProgress:@"initialising universe..."];
    universe = [[Universe alloc] init];
	
	[universe setGameView:gameView];
		
	[self logProgress:@"loading player..."];
	[self loadPlayerIfRequired];

#ifndef GNUSTEP
	//
	// get the run loop and add the call to doStuff
	//
    NSTimeInterval ti = 0.01;
    
    timer = [[NSTimer timerWithTimeInterval:ti target:self selector:@selector(doStuff:) userInfo:self repeats:YES] retain];
    
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];

	
	// set up the window to accept mouseMoved events
	[gameWindow setAcceptsMouseMovedEvents:YES];
#endif
	//
	[self endSplashScreen];

#ifdef GNUSTEP
	// Release anything allocated above that is not required.
	[pool release];
	[gameView pollControls];
#endif
}

- (void) loadPlayerIfRequired
{
	if (playerFileToLoad)
	{
		PlayerEntity	*player = (PlayerEntity *)[universe entityZero];
		//NSLog(@":::> Opening %@ now", playerFileToLoad);
		[player loadPlayerFromFile:playerFileToLoad];
		[player setStatus:STATUS_DOCKED];
		[player setGuiToStatusScreen];
		[universe setDisplayText:YES];
	}
}

- (void) beginSplashScreen
{
// splash screen is what is in the Main Window to begin with
// we'll swap out the content later when all the textures have been loaded

//	[splashView setFrame:[gameWindow frame]];
//	[gameWindow setContentView:splashView];
}

- (void) logProgress:(NSString*) message
{
//	NSLog(@"progress: %@", message);
#ifndef GNUSTEP
	[splashProgressTextField setStringValue:message];
	[splashProgressTextField display];	// **thanks Jens Ayton **
#endif
}

- (void) endSplashScreen
{
#ifndef GNUSTEP
	[gameWindow setContentView:gameView];
	[gameWindow makeFirstResponder:gameView];
#endif
}

- (void) doStuff: (id) sender
{
    //
    if (game_is_paused)
		delta_t = 0.0;  // no movement!
	else
	{
		delta_t = [NSDate timeIntervalSinceReferenceDate] - last_timeInterval;
		last_timeInterval += delta_t;
		if (delta_t > MINIMUM_GAME_TICK)
			delta_t = MINIMUM_GAME_TICK;		// peg the maximum pause (at 0.5->1.0 seconds) to protect against when the machine sleeps	
	}
	//
	if (universe)
		[universe update:delta_t];
	//
#ifdef GNUSTEP
   // GNUstep's fullscreen is actually just a full screen window.
   // So we use the same view regardless of mode.
   if(gameView)
      [gameView display];
   else
		NSLog(@"***** gameView not set : delta_t %f",(float)delta_t);
     
#else
	if (fullscreen)
	{
		if (universe)
			[universe drawFromEntity:0];
	}
	else
	{
		if (gameView)
			[gameView display];
		else
			NSLog(@"***** gameView not set : delta_t %f",(float)delta_t);
	}
#endif   
	//
}

- (void) startAnimationTimer
{
	if (timer == nil)
	{   
		NSTimeInterval ti = 0.01;
		timer = [[NSTimer timerWithTimeInterval:ti target:self selector:@selector(doStuff:) userInfo:self repeats:YES] retain];
		[[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
	}
}

- (void) stopAnimationTimer
{
    if (timer != nil)
	{
        [timer invalidate];
        [timer release];
        timer = nil;
    }
}



- (IBAction) goFullscreen:(id) sender
{

#ifdef GNUSTEP
  // TODO: what goes here?
#else
    //Scene *scene = [openGLView scene];
    CGLContextObj cglContext;
    CGDisplayErr err;
    long oldSwapInterval;
    long newSwapInterval;
	
	// empty the event queue and strip all keys - stop problems with hangover keys
	{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		NSEvent *event;
		while (event = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate distantPast] inMode:NSDefaultRunLoopMode dequeue:YES]);
		[pool release];
		[gameView clearKeys];
	}
		
	pauseTarget = sender;
	
	my_mouse_x = my_mouse_y = 0;
	
	while (pauseTarget)
	{
		CGPoint centerOfScreen = CGPointMake(width/2.0,height/2.0);

		pauseTarget = nil;
		
		//get the appropriate display mode for the selected values
		
		fullscreenDisplayMode = [self findDisplayModeForWidth:width Height:height Refresh:refresh];
		if (fullscreenDisplayMode == nil)
		{
			NSLog(@"***** unable to find suitable full screen mode");
			return;
		}
		
		originalDisplayMode = (NSDictionary *)CGDisplayCurrentMode(kCGDirectMainDisplay);
		//NSLog(@"originalDisplayMode = %@", originalDisplayMode);
		
		// Pixel Format Attributes for the FullScreen NSOpenGLContext
		NSOpenGLPixelFormatAttribute attrs[] = {

			// Specify that we want a full-screen OpenGL context.
			NSOpenGLPFAFullScreen,

			// We may be on a multi-display system (and each screen may be driven by a different renderer), so we need to specify which screen we want to take over.
			// For this demo, we'll specify the main screen.
			NSOpenGLPFAScreenMask, CGDisplayIDToOpenGLDisplayMask(kCGDirectMainDisplay),

			// Attributes Common to FullScreen and non-FullScreen
			NSOpenGLPFAColorSize, 32,
			NSOpenGLPFADepthSize, 32,
			NSOpenGLPFADoubleBuffer,
			NSOpenGLPFAAccelerated,
			0
		};
		long rendererID;

		// Create the FullScreen NSOpenGLContext with the attributes listed above.
		NSOpenGLPixelFormat *pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
		
		// Just as a diagnostic, report the renderer ID that this pixel format binds to.  CGLRenderers.h contains a list of known renderers and their corresponding RendererID codes.
		[pixelFormat getValues:&rendererID forAttribute:NSOpenGLPFARendererID forVirtualScreen:0];
		//NSLog(@"FullScreen pixelFormat RendererID = %08x", (unsigned)rendererID);

		// Create an NSOpenGLContext with the FullScreen pixel format.  By specifying the non-FullScreen context as our "shareContext", we automatically inherit all of the textures, display lists, and other OpenGL objects it has defined.
		fullScreenContext = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:[gameView openGLContext]];
		[pixelFormat release];
		pixelFormat = nil;

		if (fullScreenContext == nil)
		{
			NSLog(@"***** Failed to create fullScreenContext");
			return;
		}
		

		// Pause animation in the OpenGL view.  While we're in full-screen mode, we'll drive the animation actively
		// instead of using a timer callback.
		if (timer)
			[self stopAnimationTimer];

		// Take control of the display where we're about to go FullScreen.
		// this stops windows from being shuffled around.
		err = CGCaptureAllDisplays();
		if (err != CGDisplayNoErr)
		{
			[fullScreenContext release];
			fullScreenContext = nil;
			return;
		}

		// switch resolution!
        err = CGDisplaySwitchToMode(kCGDirectMainDisplay, (CFDictionaryRef)fullscreenDisplayMode);
        if (err != CGDisplayNoErr)
		{
            NSLog(@"***** Unable to change display mode.");
            return;
        }
		
		// Hide the cursor
		CGDisplayMoveCursorToPoint(kCGDirectMainDisplay,centerOfScreen);
        CGDisplayHideCursor(kCGDirectMainDisplay);
		
		// Enter FullScreen mode and make our FullScreen context the active context for OpenGL commands.
		[fullScreenContext setFullScreen];
		[fullScreenContext makeCurrentContext];
		
		// Save the current swap interval so we can restore it later, and then set the new swap interval to lock us to the display's refresh rate.
		cglContext = CGLGetCurrentContext();
		CGLGetParameter(cglContext, kCGLCPSwapInterval, &oldSwapInterval);
		newSwapInterval = 1;
		CGLSetParameter(cglContext, kCGLCPSwapInterval, &newSwapInterval);

		// Tell the scene the dimensions of the area it's going to render to, so it can set up an appropriate viewport and viewing transformation.
		[gameView initialiseGLWithSize:NSMakeSize(width,height)];
		
		// Now that we've got the screen, we enter a loop in which we alternately process input events and computer and render the next frame of our animation.
		// The shift here is from a model in which we passively receive events handed to us by the AppKit to one in which we are actively driving event processing.
		stayInFullScreenMode = YES;
		
		fullscreen = YES;
						
		BOOL past_first_mouse_delta = NO;
		
		while (stayInFullScreenMode)
		{
			NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

			// Check for and process input events.
			NSEvent *event;
			while (event = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:nil inMode:NSDefaultRunLoopMode dequeue:YES])
			{
				switch ([event type])
				{
					case NSLeftMouseDown:
						[gameView mouseDown:event];
						break;

					case NSRightMouseDown:
						my_mouse_x = my_mouse_y = 0;	// center mouse
						past_first_mouse_delta = NO;
						[gameView setVirtualJoystick:0.0 :0.0];
						break;

					case NSLeftMouseUp:
						[gameView mouseUp:event];
						break;
					
					case NSMouseMoved:
						CGGetLastMouseDelta(&mouse_dx, &mouse_dy);
						if (past_first_mouse_delta)
						{
							my_mouse_x += mouse_dx;
							my_mouse_y += mouse_dy;
						}
						else
							past_first_mouse_delta =YES;
						//NSLog(@".. %d, %d ..",my_mouse_x, my_mouse_y);
						[gameView setVirtualJoystick:(double)my_mouse_x/width :(double)my_mouse_y/height];
						CGDisplayMoveCursorToPoint(kCGDirectMainDisplay,centerOfScreen);
						break;
					
					case NSKeyDown:
						[gameView keyDown:event];
						break;

					case NSFlagsChanged:
						[gameView flagsChanged:event];
						break;

					case NSKeyUp:
						[gameView keyUp:event];
						break;

					default:
						break;
				}
			}

			// Update our stuff.        
			[self doStuff:self];

			[fullScreenContext flushBuffer];

			// Clean up any autoreleased objects that were created this time through the loop.
			[pool release];
		}
		
		// Clear the front and back framebuffers before switching out of FullScreen mode.
		// (This is not strictly necessary, but avoids an untidy flash of garbage.)
		glClearColor(0.0, 0.0, 0.0, 0.0);
		glClear(GL_COLOR_BUFFER_BIT);
		[fullScreenContext flushBuffer];
		glClear(GL_COLOR_BUFFER_BIT);
		[fullScreenContext flushBuffer];

		// Restore the previously set swap interval.
		CGLSetParameter(cglContext, kCGLCPSwapInterval, &oldSwapInterval);

		// Exit fullscreen mode and release our FullScreen NSOpenGLContext.
		[NSOpenGLContext clearCurrentContext];
		[fullScreenContext clearDrawable];
		[fullScreenContext release];
		fullScreenContext = nil;

		// switch resolution back!
        err = CGDisplaySwitchToMode(kCGDirectMainDisplay, (CFDictionaryRef)originalDisplayMode);
        if (err != CGDisplayNoErr)
		{
            NSLog(@"***** Unable to change display mode.");
            return;
        }
		
		// show the cursor
        CGDisplayShowCursor(kCGDirectMainDisplay);
		
		// Release control of the displays.
		CGReleaseAllDisplays();
		
		fullscreen = NO;
				
		// Resume animation timer firings.
		[self startAnimationTimer];

		// Mark our view as needing drawing.  (The animation has advanced while we were in FullScreen mode, so its current contents are stale.)
//		[gameView initialiseGLWithSize:NSMakeSize(640,480)];
		[gameView setNeedsDisplay:YES];
		
		if (pauseTarget)
		{
			[pauseTarget performSelector:pauseSelector];
		}
		
	}
#endif // ...if GNUSTEP else

}

- (void) exitFullScreenMode
{
	//NSLog(@"in gameController exitFullScreenMode");
	stayInFullScreenMode = NO;
}

- (BOOL) inFullScreenMode
{
#ifdef GNUSTEP
	return [gameView inFullScreenMode];
#else
	return fullscreen;
#endif
}

#ifdef GNUSTEP
- (void) setFullScreenMode:(BOOL)fsm
{
	fullscreen = fsm;
}
#endif


- (void) pauseFullScreenModeToPerform:(SEL) selector onTarget:(id) target
{
	pauseSelector = selector;
	pauseTarget = target;
	stayInFullScreenMode = NO;
}

- (void) exitApp
{
#ifdef GNUSTEP
	SDL_Quit();
	exit(0);
#else
	[NSApp  terminate:self];
#endif
}

- (void)windowDidResize:(NSNotification *)aNotification
{
//	NSLog(@"Mwahhahaha");
	[gameView drawRect:[gameView bounds]];
}

// delegate methods
#ifndef GNUSTEP
- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
	if ([[filename pathExtension] isEqual:@"oolite-save"])
	{
		[self setPlayerFileToLoad:filename];
		return YES;
	}
	if ([[filename pathExtension] isEqual:@"oxp"]||[[filename pathExtension] isEqual:@"oolite_expansion_pack"])
	{
		BOOL dir_test;
		[[NSFileManager defaultManager] fileExistsAtPath:filename isDirectory:&dir_test];
		if (dir_test)
		{
//			NSLog(@"Including expansion pack : %@", filename);
			if (!expansionPathsToInclude)
				expansionPathsToInclude = [[NSMutableArray alloc] initWithCapacity: 4];	// retained
			[expansionPathsToInclude addObject: filename];
			return YES;
		}
	}
	return NO;
}
#endif

- (NSString *) playerFileToLoad
{
	return playerFileToLoad;
}

- (void) setPlayerFileToLoad:(NSString *)filename
{
	if (playerFileToLoad)
		[playerFileToLoad autorelease];
	playerFileToLoad = nil;
	if ([[filename pathExtension] isEqual:@"oolite-save"])
		playerFileToLoad = [[NSString stringWithString:filename] retain];
}

// only OS X has these two methods
#ifdef GNUSTEP
- (void) playiTunesPlaylist:(NSString *)playlist_name
{
}

- (void) pauseiTunes
{
}

#else
- (void) playiTunesPlaylist:(NSString *)playlist_name
{
	NSString *ootunesScriptString = [NSString stringWithFormat:@"tell application \"iTunes\"\nif playlist \"%@\" exists then\nset song repeat of playlist \"%@\" to all\nset shuffle of playlist \"%@\" to true\nplay some track of playlist \"%@\"\nend if\nend tell", playlist_name, playlist_name, playlist_name, playlist_name];
	NSAppleScript *ootunesScript = [[NSAppleScript alloc] initWithSource:ootunesScriptString];
	NSDictionary *errDict = nil;
	[ootunesScript executeAndReturnError:&errDict];
	if (errDict)
		NSLog(@"DEBUG ootunes returned :%@", [errDict description]);
	[ootunesScript release]; 
}

- (void) pauseiTunes
{
	NSString *ootunesScriptString = [NSString stringWithFormat:@"tell application \"iTunes\"\npause\nend tell"];
	NSAppleScript *ootunesScript = [[NSAppleScript alloc] initWithSource:ootunesScriptString];
	NSDictionary *errDict = nil;
	[ootunesScript executeAndReturnError:&errDict];
	if (errDict)
		NSLog(@"DEBUG ootunes returned :%@", [errDict description]);
	[ootunesScript release]; 
}
#endif

@end


