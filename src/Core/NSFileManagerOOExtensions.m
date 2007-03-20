/*

NSFileManagerOOExtensions.m

This extends NSFileManager and adds some methods to insulate the
main oolite code from the gory details of creating/chdiring to the
commander save directory.

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

#include <stdlib.h>
#import "NSFileManagerOOExtensions.h"
#import "ResourceManager.h"
#import "OOPListParsing.h"

@implementation NSFileManager (OOExtensions)

- (NSArray *)commanderContents
{
	if([self chdirToDefaultCommanderPath])
	{
		NSMutableArray *contents=[NSMutableArray arrayWithArray:[self directoryContentsAtPath: @"."]];

		// at this point we should strip out any files not loadable as Oolite saved games
		int i;
		for (i = 0; i < [contents count]; i++)
		{
			NSString* path = (NSString*)[contents objectAtIndex:i];
			
			// check file extension
			if (![[path pathExtension] isEqual:@"oolite-save"])
			{
				NSLog(@">>>> %@ is not a saved game", path);
				[contents removeObjectAtIndex: i--];
				continue;
			}
			
			// check can parse the file okay
			NSDictionary* cdr = OODictionaryFromFile(path); 
			if(!cdr)
			{
				NSLog(@">>>> %@ could not be parsed as a saved game", path);
				[contents removeObjectAtIndex: i--];
				continue;
			}
			
		}
		return contents;
	}
	return nil;
}

- (NSArray *) commanderContentsOfPath:(NSString*) savePath
{
	BOOL pathIsDirectory = NO;
	if ([[NSFileManager defaultManager] fileExistsAtPath:savePath isDirectory:&pathIsDirectory] && pathIsDirectory)
	{
		NSMutableArray *contents=[NSMutableArray arrayWithArray:[self directoryContentsAtPath: savePath]];
				
		// at this point we should strip out any files not loadable as Oolite saved games
		int i;
		for (i = 0; i < [contents count]; i++)
		{
			NSString* path = [savePath stringByAppendingPathComponent: (NSString*)[contents objectAtIndex:i]];
			
			// check if it's a directory
			if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&pathIsDirectory] && pathIsDirectory)
			{
//				NSLog(@">>>> %@ is a directory", path);	// we're going to keep directories
			}
			else
			{
				
				// check file extension
				if (![[path pathExtension] isEqual:@"oolite-save"])
				{
//					NSLog(@">>>> %@ is not a saved game", path);
					[contents removeObjectAtIndex: i--];
					continue;
				}
				
				// check to see if we can parse the file okay
				NSDictionary* cdr = OODictionaryFromFile(path); 
				if(!cdr)
				{
					NSLog(@">>>> %@ could not be parsed as a saved game", path);
					[contents removeObjectAtIndex: i--];
					continue;
				}
			}
			
			// all okay - we can use this path!
			[contents replaceObjectAtIndex: i withObject: path];
			
		}
				
		return contents;
	}
	else
	{
         NSLog(@"DEBUG ERROR! Path '%@' could not be found", savePath);
         return nil;
	}
}

- (BOOL)chdirToDefaultCommanderPath
{
   NSString *savedir=
      [NSHomeDirectory() stringByAppendingPathComponent:@SAVEDIR];
   if(![self changeCurrentDirectoryPath: savedir])
   {
      // it probably doesn't exist.
      if(![self createDirectoryAtPath: savedir attributes: nil])
      {
         NSLog(@"Unable to create: %@", savedir);
         return NO;
      }
      if(![self changeCurrentDirectoryPath: savedir])
      {
         NSLog(@"Created %@ but couldn't chdir to it", savedir);
         return NO;
      }
   }
   NSLog(@"CWD is %@", savedir);
      
   return YES;
}

- (NSString*) defaultCommanderPath
{
	NSString* savedir = [NSHomeDirectory() stringByAppendingPathComponent:@SAVEDIR];
	BOOL pathIsDirectory = NO;
	
	// does it exist?
	if (![[NSFileManager defaultManager] fileExistsAtPath:savedir isDirectory:&pathIsDirectory])
	{
		// it doesn't exist.
		if([self createDirectoryAtPath: savedir attributes: nil])
		{
			NSLog(@"DEBUG creating %@", savedir);
			return savedir;
		}
		else
		{
			NSLog(@"ERROR ***** Unable to create: %@ saved games will go to the home directory *****", savedir);
			return NSHomeDirectory();
		}
	}
	
	// is it a directory?
	if (!pathIsDirectory)
	{
		NSLog(@"ERROR ***** %@ is not a directory, saved games will go to the home directory *****", savedir);
		return NSHomeDirectory();
	}
	
	return savedir;
}

@end


