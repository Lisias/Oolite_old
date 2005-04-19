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
#ifdef GNUSTEP
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <AppKit/NSOpenGLView.h>
#else
#import <Cocoa/Cocoa.h>
#endif
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <OpenGL/glext.h>

#define MAX_CLEAR_DEPTH		100000000.0
// 100 000 km.

#define NUM_KEYS			320

@class Entity, GameController, OpenGLSprite;

enum GameViewKeys
{
	gvArrowKeyUp = 255,
	gvArrowKeyDown = 254,
	gvArrowKeyLeft = 253,
	gvArrowKeyRight = 252,
	gvFunctionKey1 = 241,
	gvFunctionKey2 = 242,
	gvFunctionKey3 = 243,
	gvFunctionKey4 = 244,
	gvFunctionKey5 = 245,
	gvFunctionKey6 = 246,
	gvFunctionKey7 = 247,
	gvFunctionKey8 = 248,
	gvFunctionKey9 = 249,
	gvFunctionKey10 = 250,
	gvFunctionKey11 = 251,
	gvMouseLeftButton = 301,
	gvHomeKey = 302,
	gvNumberKey0 = 48,
	gvNumberKey1 = 49,
	gvNumberKey2 = 50,
	gvNumberKey3 = 51,
	gvNumberKey4 = 52,
	gvNumberKey5 = 53,
	gvNumberKey6 = 54,
	gvNumberKey7 = 55,
	gvNumberKey8 = 56,
	gvNumberKey9 = 57
};
	
extern int debug;

@interface MyOpenGLView : NSOpenGLView
{
	IBOutlet GameController  *gameController;
	
	OpenGLSprite* splashSprite;
	
	BOOL keys[NUM_KEYS];
	BOOL opt, ctrl, command, shift;
	BOOL allowingStringInput;
	BOOL isAlphabetKeyDown;
	
	int keycodetrans[255];
	
	BOOL	m_glContextInitialized;
    NSPoint	mouseDragStartPoint;
    double 	squareX,squareY;
	
	NSMutableString	*typedString;
		
	NSSize  viewSize;
	GLfloat display_z;
	
//	GLuint	splashScreenTexture;
	
	NSPoint virtualJoystickPosition;
}

// override
- (id) initWithFrame:(NSRect)frameRect;
- (void) dealloc;

- (void) allowStringInput: (BOOL) value;
- (BOOL) allowingStringInput;
- (NSString *) typedString;
- (void) resetTypedString;
- (void) setTypedString:(NSString*) value;

- (NSSize) viewSize;
- (GLfloat) display_z;

- (GameController *) gameController;
- (void) setGameController:(GameController *) controller;

- (void) initialiseGLWithSize:(NSSize) v_size;

- (void)drawRect:(NSRect)rect;

- (void) snapShot;

// These are standard methods in NSView.
- (void)mouseDown:(NSEvent *)theEvent;
- (void)mouseUp:(NSEvent *)theEvent;
- (void)mouseDragged:(NSEvent *)theEvent;

- (void) setVirtualJoystick:(double) vmx :(double) vmy;
- (NSPoint) virtualJoystickPosition;

 - (void) clearKeys;
 - (BOOL) isAlphabetKeyDown;
 - (BOOL) isDown: (int) key;
 - (BOOL) isOptDown;
 - (BOOL) isCtrlDown;
 - (BOOL) isCommandDown;
 - (BOOL) isShiftDown;
 - (int) numKeys;

@end

