/*

GameController.h

Main application controller class.

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


#import "OOCocoa.h"

#define MODE_WINDOWED			100
#define MODE_FULL_SCREEN		200

#define DISPLAY_MIN_COLOURS		32
#ifndef GNUSTEP
#define DISPLAY_MIN_WIDTH		640
#define DISPLAY_MIN_HEIGHT		480

/*	OS X apps are permitted to assume 800x600 screens. Under OS X, we always
	start up in windowed mode. Therefore, the default size fits an 800x600
	screen and leaves space for the menu bar and title bar.
*/
#define DISPLAY_DEFAULT_WIDTH	800
#define DISPLAY_DEFAULT_HEIGHT	540
#define DISPLAY_DEFAULT_REFRESH	75
#else
// *** Is there a reason for this difference? -- Ahruman
#define DISPLAY_MIN_WIDTH		800
#define DISPLAY_MIN_HEIGHT		600
#endif
#define DISPLAY_MAX_WIDTH		2400
#define DISPLAY_MAX_HEIGHT		1800

#define MINIMUM_GAME_TICK		0.25
// * reduced from 0.5s for tgape * //


@class MyOpenGLView;


#if OOLITE_MAC_OS_X
#define kOODisplayWidth			((NSString *)kCGDisplayWidth)
#define kOODisplayHeight		((NSString *)kCGDisplayHeight)
#define kOODisplayRefreshRate	((NSString *)kCGDisplayRefreshRate)
#define kOODisplayBitsPerPixel	((NSString *)kCGDisplayBitsPerPixel)
#define kOODisplayIOFlags		((NSString *)kCGDisplayIOFlags)
#else
#define kOODisplayWidth			(@"Width")
#define kOODisplayHeight		(@"Height")
#define kOODisplayRefreshRate	(@"RefreshRate")
#endif


@interface GameController : NSObject
{
#if OOLITE_HAVE_APPKIT
    IBOutlet NSTextField	*splashProgressTextField;
    IBOutlet NSView			*splashView;
    IBOutlet NSWindow		*gameWindow;
	IBOutlet NSTextView		*helpView;
#endif

#if OOLITE_SDL
	NSRect					fsGeometry;
	MyOpenGLView			*switchView;
#endif
	IBOutlet MyOpenGLView	*gameView;

	NSTimeInterval			last_timeInterval;
	double					delta_t;

	int						my_mouse_x, my_mouse_y;

	NSString				*playerFileDirectory;
	NSString				*playerFileToLoad;
	NSMutableArray			*expansionPathsToInclude;

	NSTimer					*timer;

	/*  GDC example code */

	NSMutableArray			*displayModes;

	unsigned int			width, height;
	unsigned int			refresh;
	BOOL					fullscreen;
	NSDictionary			*originalDisplayMode;
	NSDictionary			*fullscreenDisplayMode;

#if OOLITE_MAC_OS_X
	NSOpenGLContext			*fullScreenContext;
#endif

	BOOL					stayInFullScreenMode;

	/*  end of GDC */

	SEL						pauseSelector;
	NSObject				*pauseTarget;

	BOOL					gameIsPaused;
}

+ (id)sharedController;

- (void) applicationDidFinishLaunching: (NSNotification *)notification;
- (BOOL) gameIsPaused;
- (void) pause_game;
- (void) unpause_game;

#if OOLITE_HAVE_APPKIT
- (IBAction) goFullscreen:(id)sender;
#elif OOLITE_SDL
- (void) setFullScreenMode:(BOOL)fsm;
#endif
- (void) exitFullScreenMode;
- (BOOL) inFullScreenMode;

- (void) pauseFullScreenModeToPerform:(SEL) selector onTarget:(id) target;
- (void) exitApp;

- (BOOL) setDisplayWidth:(unsigned int) d_width Height:(unsigned int)d_height Refresh:(unsigned int) d_refresh;
- (NSDictionary *) findDisplayModeForWidth:(unsigned int)d_width Height:(unsigned int) d_height Refresh:(unsigned int) d_refresh;
- (NSArray *) displayModes;
- (int) indexOfCurrentDisplayMode;

- (NSString *) playerFileToLoad;
- (void) setPlayerFileToLoad:(NSString *)filename;

- (NSString *) playerFileDirectory;
- (void) setPlayerFileDirectory:(NSString *)filename;

- (void) loadPlayerIfRequired;

- (void) beginSplashScreen;
- (void) logProgress:(NSString*) message;
- (void) endSplashScreen;

- (void) startAnimationTimer;
- (void) stopAnimationTimer;

- (MyOpenGLView *) gameView;
- (void) setGameView:(MyOpenGLView *)view;

- (void)windowDidResize:(NSNotification *)aNotification;

- (void) playiTunesPlaylist:(NSString *)playlist_name;
- (void) pauseiTunes;

@end

