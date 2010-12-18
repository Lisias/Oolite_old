/*

JoystickHandler.m
By Dylan Smith

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

*/

#import "JoystickHandlerSDL.h"
#import "OOLogging.h"

#define kOOLogUnconvertedNSLog @"unclassified.JoystickHandler"


@implementation JoystickHandlerSDL

- (id) init
{
   int i;

   // Find and open the sticks.
   numSticks=SDL_NumJoysticks();
   OOLog(@"joystickHandler.init", @"Number of joysticks detected: %d", numSticks);
   if(numSticks)
   {
      for(i = 0; i < numSticks; i++)
      {
         // it's doubtful MAX_STICKS will ever get exceeded, but
         // we need to be defensive.
         if(i > MAX_STICKS)
            break;

         stick[i]=SDL_JoystickOpen(i);
         if(!stick[i])
         {
            NSLog(@"Failed to open joystick #%d", i);
         }
      }
      SDL_JoystickEventState(SDL_ENABLE);
   }
   return [super init];
}


- (BOOL) handleSDLEvent: (SDL_Event *)evt
{
   BOOL rc=NO;
   switch(evt->type)
   {
      case SDL_JOYAXISMOTION:
         [self decodeAxisEvent: (JoyAxisEvent *)evt];
         rc=YES;
         break;
      case SDL_JOYBUTTONDOWN:
      case SDL_JOYBUTTONUP:
         [self decodeButtonEvent: (JoyButtonEvent *)evt];
         rc=YES;
         break;
      case SDL_JOYHATMOTION:
         [self decodeHatEvent: (JoyHatEvent *)evt];
         rc=YES;
         break;
      default:
         NSLog(@"JoystickHandler was sent an event it doesn't know");
   }
   return rc;
}



// Overrides
- (char*) getJoystickName: (int) num
{
	return (char*) SDL_JoystickName(num);
}

- (int16_t) getAxisWithStick:(int) stickNum axis:(int) axisNum 
{
	return SDL_JoystickGetAxis(stick[stickNum], axisNum);
}



@end
