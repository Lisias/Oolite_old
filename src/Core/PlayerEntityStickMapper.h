/*

PlayerEntityStickMapper.h

Joystick support for SDL implementation of Oolite.

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

#import "PlayerEntity.h"
#import "GuiDisplayGen.h"
#import "MyOpenGLView.h"
#import "Universe.h"

#define STICKNAME_ROW   1
#define HEADINGROW      3
#define FUNCSTART_ROW   4
#define INSTRUCT_ROW    20

// Dictionary keys
#define KEY_GUIDESC  @"guiDesc"
#define KEY_ALLOWABLE @"allowable"
#define KEY_AXISFN @"axisfunc"
#define KEY_BUTTONFN @"buttonfunc"

@interface PlayerEntity (StickMapper)

   - (void) setGuiToStickMapperScreen;
   - (void) stickMapperInputHandler: (GuiDisplayGen *)gui
                               view: (MyOpenGLView *)gameView;
   // Callback method
   - (void) updateFunction: (NSDictionary *)hwDict;

   // internal methods
   - (void) removeFunction: (int)selFunctionIdx;
   - (NSArray *)getStickFunctionList;
   - (void)displayFunctionList: (GuiDisplayGen *)gui;
   - (NSString *)describeStickDict: (NSDictionary *)stickDict;
   - (NSString *)hwToString: (int)hwFlags;

   // Future: populate via plist
   - (NSDictionary *)makeStickGuiDict: (NSString *)what 
                            allowable: (int)allowable
                               axisfn: (int)axisfn
                                butfn: (int)butfn;
                              
@end

