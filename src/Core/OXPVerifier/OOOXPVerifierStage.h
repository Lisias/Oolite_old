/*

OOOXPVerifierStage.h

Pipeline stage for OXP verification pipeline managed by OOOXPVerifier.


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

#import "OOOXPVerifier.h"

#if OO_OXP_VERIFIER_ENABLED

@interface OOOXPVerifierStage: NSObject
{
@private
	OOOXPVerifier				*_verifier;
	NSMutableSet				*_dependencies;
	NSMutableSet				*_incompleteDependencies;
	NSMutableSet				*_dependents;
	BOOL						_canRun, _hasRun;
}

- (OOOXPVerifier *)verifier;

// Subclass responsibilities:

/*	Name of stage. Used for display and for dependency resolution; must be
	unique. The name should be a phrase describing what will be done, like
	"Scanning files" or "Verifying plist scripts".
*/
- (NSString *)name;
- (NSSet *)requiredStages;	// Names of stages that must be run before this one. Default: empty set.

/*	This is called once by the verifier.
	When it is called, all the verifier stages listed in -requiredStages will
	have run. At this point, it is possible to access them using the
	verifier's -stageWithName: method in order to query them about results.
	Stages whose dependencies have all run will be released, so the result of
	calling -stageWithName: with a name not in -requiredStages is undefined.
*/
- (void)run;

/*	Post-run: some verifier stage, like the file set stage, need to perform
	checks after all other stages are completed. Such stages must implement
	-needsPostRun to return YES.
*/
- (BOOL)needsPostRun;
- (void)postRun;

@end

#endif
