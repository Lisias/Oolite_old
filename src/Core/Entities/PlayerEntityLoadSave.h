/*

PlayerEntityLoadSave.h

Created for the Oolite-Linux project (but is portable)

LoadSave has been separated out into a separate category because
PlayerEntity.m has gotten far too big and is in danger of becoming
the whole general mish mash.

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

#define LABELROW 1
#define BACKROW 2 
#define STARTROW 3
#define ENDROW 16
#define MOREROW 16
#define NUMROWS 13
#define COLUMNS 2
#define INPUTROW 21
#define CDRDESCROW 18
#define SAVE_OVERWRITE_WARN_ROW	5
#define SAVE_OVERWRITE_YES_ROW	8
#define SAVE_OVERWRITE_NO_ROW	9

@interface PlayerEntity (LoadSave)

- (BOOL) loadPlayer;	// Returns NO on immediate failure, i.e. when using an OS X modal open panel which is cancelled.
- (void) savePlayer;
- (void) quicksavePlayer;

- (NSString *) commanderSelector;
- (void) saveCommanderInputHandler;
- (void) overwriteCommanderInputHandler;

- (BOOL) loadPlayerFromFile:(NSString *)fileToOpen;


@end

