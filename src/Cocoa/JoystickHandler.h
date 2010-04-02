/*

JoystickHandler.h

Non-functional JoystickHandler. Useful version lives in LeopardFeatures.


Oolite
Copyright (C) 2004-2010 Giles C Williams and contributors

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

Copyright (C) 2006-2010 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOCocoa.h"
#import "OOFunctionAttributes.h"

OO_MAC_BEGIN_EXPORT


#define STICK_AXISUNASSIGNED -10.0

// Enums are used here rather than a more complex ObjC object because
// these are required very frequently (once per frame) so must be light
// on CPU cycles (try and avoid too many objc sendmsgs).
// Controls that can be an axis
typedef enum
{
  AXIS_ROLL,
  AXIS_PITCH,
  AXIS_YAW,
  AXIS_PRECISION,
  AXIS_THRUST,
  AXIS_VIEWX,
  AXIS_VIEWY,
  AXIS_end
} OOJoystickAxisFunction;

// Controls that can be a button
typedef enum
{
  BUTTON_INCTHRUST,
  BUTTON_DECTHRUST,
  BUTTON_SCANNERZOOM,
  BUTTON_JETTISON,
  BUTTON_COMPASSMODE,
  BUTTON_COMMSLOG,
  BUTTON_DOCKCPU,
  BUTTON_DOCKCPUFAST,
  BUTTON_DOCKCPUTARGET,
  BUTTON_FUELINJECT,
  BUTTON_HYPERSPEED,
  BUTTON_HYPERDRIVE,
  BUTTON_GALACTICDRIVE,
  BUTTON_FIRE,
  BUTTON_ARMMISSILE,
  BUTTON_LAUNCHMISSILE,
  BUTTON_UNARM,
#if TARGET_INCOMING_MISSILES
  BUTTON_TARGETINCOMINGMISSILE,
#endif
  BUTTON_CYCLEMISSILE,
  BUTTON_ENERGYBOMB,
  BUTTON_ID,
  BUTTON_ECM,
  BUTTON_ESCAPE,
  BUTTON_CLOAK,
  BUTTON_PRECISION,
  BUTTON_VIEWFORWARD,
  BUTTON_VIEWAFT,
  BUTTON_VIEWPORT,
  BUTTON_VIEWSTARBOARD,
  BUTTON_end
} OOJoystickButtonFunction;

// Stick constants
#define MAX_STICKS 4
#define MAX_AXES  16
#define MAX_REAL_BUTTONS  64
#define MAX_HATS  0
#define MAX_BUTTONS (MAX_REAL_BUTTONS + 4 * MAX_HATS)
#define STICK_NOFUNCTION -1
#define STICK_AXISUNASSIGNED -10.0
#define STICK_PRECISIONDIV 98304 // 3 times more precise
#define STICK_NORMALDIV 32768
#define STICK_PRECISIONFAC (STICK_PRECISIONDIV/STICK_NORMALDIV)
#define STICK_DEADZONE	0.05

// Kind of stick device (these are bits - if any more are added,
// the next one is 4 and so on).
#define HW_AXIS 1
#define HW_BUTTON 2

// The threshold at which an axis can trigger a call back.
// The max of abs(axis) is 32767.
#define AXCBTHRESH 20000

// Dictionary keys - used in the defaults file
#define AXIS_SETTINGS @"JoystickAxes"	// NSUserDefaults
#define BUTTON_SETTINGS @"JoystickButs"	// NSUserDefaults
#define STICK_ISAXIS @"isAxis"			// YES=axis NO=button
#define STICK_NUMBER @"stickNum"		// Stick number 0 to 4
#define STICK_AXBUT  @"stickAxBt"		// Axis or button number
#define STICK_FUNCTION @"stickFunc"		// Function of axis/button


@interface JoystickHandler: NSObject
{
@private
	BOOL butstate[BUTTON_end];
}

+ (id) sharedStickHandler;

- (OOUInteger) getNumSticks;
- (NSPoint) getRollPitchAxis;
- (NSPoint) getViewAxis;
- (double) getAxisState:(OOJoystickAxisFunction)function;
- (double) getSensitivity;
- (const BOOL *) getAllButtonStates;

// Subclass interface
+ (BOOL) setStickHandlerClass:(Class)stickHandlerClass;
- (void) setButtonState:(BOOL)state forButton:(OOJoystickButtonFunction)button;

@end


OO_MAC_END_EXPORT
