/*

OOFileScannerVerifierStage.h

OOOXPVerifierStage which keeps track of which files are used and ensures file
name capitalization is consistent. It also provides the file lookup service
for other stages.


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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2007 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOOXPVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

extern NSString * const kOOFileScannerVerifierStageName;


@interface OOFileScannerVerifierStage: OOOXPVerifierStage
{
	NSString					*_basePath;
	NSMutableSet				*_usedFiles;
	NSMutableSet				*_caseWarnings;
	NSDictionary				*_directoryListings;
	NSDictionary				*_directoryCases;
}

/*	This method does the following:
		A.	Checks whether a file exists.
		B.	Checks whether case matches, and logs a warning otherwise.
		C.	Maintains list of files which are referred to.
		D.	Optionally falls back on Oolite's built-in files.
	
	For example, to test whether a texture referenced in a shipdata.plist entry
	exists, one would use:
	[fileScanner fileExists:textureName inFolder:@"Textures" referencedFrom:@"shipdata.plist" checkBuiltIn:YES];
*/
- (BOOL)fileExists:(NSString *)file inFolder:(NSString *)folder referencedFrom:(NSString *)context checkBuiltIn:(BOOL)checkBuiltIn;

//	This method performs all the checks the previous one does, but also returns a file path.
- (NSString *)pathForFile:(NSString *)file inFolder:(NSString *)folder referencedFrom:(NSString *)context checkBuiltIn:(BOOL)checkBuiltIn;

@end

#endif
