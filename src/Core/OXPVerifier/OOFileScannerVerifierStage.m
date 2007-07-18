/*

OOFileScannerVerifierStage.m


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


/*	Design notes:
	In order to be able to look files up case-insenstively, but warn about
	case mismatches, the OOFileScannerVerifierStage builds its own
	representation of the file hierarchy. Dictionaries are used heavily: the
	_directoryListings is keyed by folder names mapped to lower case, and its
	entries map lowercase file names to actual case, that is, the case found
	in the file system. The companion dictionary _directoryCases maps
	lowercase directory names to actual case.
	
	The class design is based on the knowledge that Oolite uses a two-level
	namespace for files. Each file type has an appropriate folder, and files
	may either be in the appropriate folder or "bare". For instance, a texture
	file in an OXP may be either in the Textures subdirectory or in the root
	directory of the OXP. The root directory's contents are listed in
	_directoryListings with the empty string as key. This architecture means
	the OOFileScannerVerifierStage doesn't need to take full file system
	hierarchy into account.
*/

#import "OOFileScannerVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OOCollectionExtractors.h"
#import "ResourceManager.h"

NSString * const kOOFileScannerVerifierStageName	= @"Scanning files";


static BOOL CheckNameConflict(NSString *lcName, NSDictionary *directoryCases, NSDictionary *rootFiles, NSString **outExisting, NSString **outExistingType);


@interface OOFileScannerVerifierStage (OOPrivate)

- (void)scanForFiles;

- (void)checkRootFolders;
- (void)checkConfigFiles;

/*	Given an array of strings, return a dictionary mapping lowercase strings
	to the canonicial case given in the array. For instance, given
		(Foo, BAR)
	
	it will return
		{ foo = Foo; bar = BAR }
*/
- (NSDictionary *)lowercaseMap:(NSArray *)array;

- (NSDictionary *)scanDirectory:(NSString *)path;

@end


@implementation OOFileScannerVerifierStage

- (void)dealloc
{
	[_basePath release];
	[_usedFiles release];
	[_caseWarnings release];
	[_directoryListings release];
	[_directoryCases release];
	
	[super dealloc];
}


- (NSString *)name
{
	return kOOFileScannerVerifierStageName;
}


- (void)run
{
	NSAutoreleasePool			*pool = nil;
	
	_usedFiles = [[NSMutableSet alloc] init];
	_caseWarnings = [[NSMutableSet alloc] init];
	
	pool = [[NSAutoreleasePool alloc] init];
	[self scanForFiles];
	[pool release];
	
	pool = [[NSAutoreleasePool alloc] init];
	[self checkRootFolders];
	[self checkConfigFiles];
	[pool release];
}


- (BOOL)needsPostRun
{
	return YES;
}


- (void)postRun
{
	
}


- (BOOL)fileExists:(NSString *)file inFolder:(NSString *)folder referencedFrom:(NSString *)context checkBuiltIn:(BOOL)checkBuiltIn
{
	return [self pathForFile:file inFolder:folder referencedFrom:context checkBuiltIn:checkBuiltIn] != nil;
}


- (NSString *)pathForFile:(NSString *)file inFolder:(NSString *)folder referencedFrom:(NSString *)context checkBuiltIn:(BOOL)checkBuiltIn
{
	NSString				*lcName = nil,
							*lcDirName = nil,
							*realDirName = nil,
							*realFileName = nil,
							*path = nil,
							*expectedPath = nil;
	
	if (file == nil)  return nil;
	lcName = [file lowercaseString];
	
	if (folder != nil)
	{
		lcDirName = [folder lowercaseString];
		realFileName = [[_directoryListings objectForKey:lcDirName] objectForKey:lcName];
		
		if (realFileName != nil)
		{
			realDirName = [_directoryCases objectForKey:lcDirName];
			path = [realDirName stringByAppendingPathComponent:realFileName];
		}
	}
	
	if (path == nil)
	{
		realFileName = [[_directoryListings objectForKey:@""] objectForKey:lcName];
		
		if (realFileName != nil)
		{
			path = realFileName;
		}
	}
	
	if (path != nil)
	{
		[_usedFiles addObject:path];
		if (realDirName != nil && ![realDirName isEqual:folder])
		{
			// Case mismatch for folder name
			if ([_caseWarnings member:lcDirName] == nil)
			{
				[_caseWarnings addObject:lcDirName];
				OOLog(@"verifyOXP.files.caseMismatch", @"ERROR: Case mismatch: directory \"%@\" should be called \"%@\".", realDirName, folder);
			}
		}
		
		if (![realFileName isEqual:file])
		{
			// Case mismatch for file name
			if ([_caseWarnings member:lcName] == nil)
			{
				[_caseWarnings addObject:lcName];
				
				if (folder != nil)  expectedPath = [folder stringByAppendingPathComponent:file];
				else  expectedPath = file;
				
				if (context != nil)  context = [@" referenced in " stringByAppendingString:context];
				else  context = @"";
				
				OOLog(@"verifyOXP.files.caseMismatch", @"ERROR: Case mismatch: request for file \"%@\"%@ resolved to \"%@\".", expectedPath, context, path);
			}
		}
		
		return [_basePath stringByAppendingPathComponent:path];
	}
	
	// If we get here, the file wasn't found in the OXP.
	if (checkBuiltIn)  return [ResourceManager pathForFileNamed:file inFolder:folder];
	
	return nil;
}


@end


@implementation OOFileScannerVerifierStage (OOPrivate)

- (void)scanForFiles
{
	NSDirectoryEnumerator	*dirEnum = nil;
	NSString				*name = nil, *path = nil;
	NSMutableDictionary		*directoryListings = nil;
	NSMutableDictionary		*directoryCases = nil;
	NSMutableDictionary		*rootFiles = nil;
	NSDictionary			*dirFiles = nil;
	NSString				*type = nil;
	NSString				*lcName = nil;
	NSString				*existing = nil, *existingType = nil;
	
	_basePath = [[[self verifier] oxpPath] copy];
	
	directoryCases = [NSMutableDictionary dictionary];
	directoryListings = [NSMutableDictionary dictionary];
	rootFiles = [NSMutableDictionary dictionary];
	
	dirEnum = [[NSFileManager defaultManager] enumeratorAtPath:_basePath];
	while ((name = [dirEnum nextObject]))
	{
		path = [_basePath stringByAppendingPathComponent:name];
		type = [[dirEnum fileAttributes] fileType];
		lcName = [name lowercaseString];
		
		if ([type isEqualToString:NSFileTypeDirectory])
		{
			dirFiles = [self scanDirectory:path];
			if (!CheckNameConflict(lcName, directoryCases, rootFiles, &existing, &existingType))
			{
				[directoryListings setObject:dirFiles forKey:lcName];
				[directoryCases setObject:name forKey:lcName];
				[dirEnum skipDescendents];
			}
			else
			{
				OOLog(@"verifyOXP.scanFiles.overloadedName", @"ERROR: %@ named \"%@\" conflicts with %@ named \"%@\", ignoring. (OXPs must work on case-insensitive file systems!)", @"directory", name, existingType, existing);
			}
		}
		else if ([type isEqualToString:NSFileTypeRegular])
		{
			if (!CheckNameConflict(lcName, directoryCases, rootFiles, &existing, &existingType))
			{
				[rootFiles setObject:name forKey:lcName];
			}
			else
			{
				OOLog(@"verifyOXP.scanFiles.overloadedName", @"ERROR: %@ named \"%@\" conflicts with %@ named \"%@\", ignoring. (OXPs must work on case-insensitive file systems!)", @"file", name, existingType, existing);
			}
		}
		else if ([type isEqualToString:NSFileTypeSymbolicLink])
		{
			OOLog(@"verifyOXP.scanFiles.symLink", @"WARNING: \"%@\" is a symbolic link, ignoring.", name);
		}
		else
		{
			OOLog(@"verifyOXP.scanFiles.nonStandardFile", @"WARNING: \"%@\" is a non-standard file (%@), ignoring.", name, type);
		}
	}
	
	[directoryListings setObject:rootFiles forKey:@""];
	_directoryListings = [directoryListings copy];
	_directoryCases = [directoryCases copy];
}


- (void)checkRootFolders
{
	NSArray					*knownNames = nil;
	NSEnumerator			*nameEnum = nil;
	NSString				*name = nil;
	NSString				*lcName = nil;
	NSString				*actual = nil;
	
	knownNames = [[self verifier] configurationArrayForKey:@"knownRootDirectories"];
	for (nameEnum = [knownNames objectEnumerator]; (name = [nameEnum nextObject]); )
	{
		if (![name isKindOfClass:[NSString class]])  continue;
		
		lcName = [name lowercaseString];
		actual = [_directoryCases objectForKey:lcName];
		if (actual == nil)  continue;
		
		if (![actual isEqualToString:name])
		{
			OOLog(@"verifyOXP.files.caseMismatch", @"ERROR: Case mismatch: directory \"%@\" should be called \"%@\".", actual, name);
		}
		[_caseWarnings addObject:lcName];
	}
}


- (void)checkConfigFiles
{
	NSArray					*knownNames = nil;
	NSEnumerator			*nameEnum = nil;
	NSString				*name = nil,
							*lcName = nil,
							*realFileName = nil;
	BOOL					inConfigDir;
	
	knownNames = [[self verifier] configurationArrayForKey:@"knownConfigFiles"];
	for (nameEnum = [knownNames objectEnumerator]; (name = [nameEnum nextObject]); )
	{
		if (![name isKindOfClass:[NSString class]])  continue;
		
		/*	In theory, we could use -fileExists:inFolder:referencedFrom:checkBuiltIn:
			here, but we want a different error message.
		*/
		
		lcName = [name lowercaseString];
		realFileName = [[_directoryListings objectForKey:@"config"] objectForKey:lcName];
		inConfigDir = realFileName != nil;
		if (!inConfigDir)  realFileName = [[_directoryListings objectForKey:@""] objectForKey:lcName];
		if (realFileName == nil)  continue;
		
		if (![realFileName isEqualToString:name])
		{
			if (inConfigDir)  realFileName = [@"Config" stringByAppendingPathComponent:realFileName];
			OOLog(@"verifyOXP.files.caseMismatch", @"ERROR: Case mismatch: configuration file \"%@\" should be called \"%@\".", realFileName, name);
		}
	}
}


- (NSDictionary *)lowercaseMap:(NSArray *)array
{
	unsigned				i, count;
	NSString				*canonical = nil,
							*lowercase = nil;
	NSMutableDictionary		*result = nil;
	
	count = [array count];
	if (count == 0)  return [NSDictionary dictionary];
	result = [NSMutableDictionary dictionaryWithCapacity:count];
	
	for (i = 0; i != count; ++i)
	{
		canonical = [array stringAtIndex:i];
		if (canonical != nil)
		{
			lowercase = [canonical lowercaseString];
			[result setObject:canonical forKey:lowercase];
		}
	}
	
	return result;
}


- (NSDictionary *)scanDirectory:(NSString *)path
{
	NSDirectoryEnumerator	*dirEnum = nil;
	NSMutableDictionary		*result = nil;
	NSString				*name = nil,
							*lcName = nil,
							*type = nil,
							*dirName = nil,
							*relativeName = nil,
							*existing = nil;
	
	result = [NSMutableDictionary dictionary];
	dirName = [path lastPathComponent];
	
	dirEnum = [[NSFileManager defaultManager] enumeratorAtPath:path];
	while ((name = [dirEnum nextObject]))
	{
		type = [[dirEnum fileAttributes] fileType];
		relativeName = [dirName stringByAppendingPathComponent:name];
		
		if ([type isEqualToString:NSFileTypeRegular])
		{
			lcName = [name lowercaseString];
			existing = [result objectForKey:lcName];
			
			if (existing == nil)
			{
				[result setObject:name forKey:lcName];
			}
			else
			{
				OOLog(@"verifyOXP.scanFiles.overloadedName", @"ERROR: %@ named \"%@\" conflicts with %@ named \"%@\", ignoring. (OXPs must work on case-insensitive file systems!)", @"file", relativeName, @"file", [dirName stringByAppendingPathComponent:existing]);
			}
		}
		else
		{
			if ([type isEqualToString:NSFileTypeSymbolicLink])
			{
				[dirEnum skipDescendents];
				OOLog(@"verifyOXP.scanFiles.symLink", @"WARNING: \"%@\" is a nested directory, ignoring.", relativeName);
			}
			else if ([type isEqualToString:NSFileTypeSymbolicLink])
			{
				OOLog(@"verifyOXP.scanFiles.symLink", @"WARNING: \"%@\" is a symbolic link, ignoring.", relativeName);
			}
			else
			{
				OOLog(@"verifyOXP.scanFiles.nonStandardFile", @"WARNING: \"%@\" is a non-standard file (%@), ignoring.", name, relativeName);
			}
		}
	}
	
	return result;
}

@end


static BOOL CheckNameConflict(NSString *lcName, NSDictionary *directoryCases, NSDictionary *rootFiles, NSString **outExisting, NSString **outExistingType)
{
	NSString			*existing = nil;
	
	existing = [directoryCases objectForKey:lcName];
	if (existing != nil)
	{
		if (outExisting != NULL)  *outExisting = existing;
		if (outExistingType != NULL)  *outExisting = @"directory";
		return YES;
	}
	
	existing = [rootFiles objectForKey:lcName];
	if (existing != nil)
	{
		if (outExisting != NULL)  *outExisting = existing;
		if (outExistingType != NULL)  *outExisting = @"file";
		return YES;
	}
	
	return NO;
}

#endif
