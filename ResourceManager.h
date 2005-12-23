//
//  ResourceManager.h
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

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/


#import "OOCocoa.h"
#import "OOOpenGL.h"

#ifdef GNUSTEP
#import "SDLImage.h"
#endif


#define OOLITE_EXCEPTION_XML_PARSING_FAILURE	@"OOXMLException"
#define OOLITE_EXCEPTION_FATAL					@"OoliteFatalException"

@class OOSound, OOMusic;

typedef struct
{
	NSString*		tag;		// name of the tag
	NSObject*		content;	// content of tag
} OOXMLElement;

extern int debug;

BOOL always_include_addons;

@interface ResourceManager : NSObject
{
	NSMutableArray  *paths;
}

- (id) initIncludingAddOns: (BOOL) include_addons;

+ (NSString *) errors;
+ (NSMutableArray *) paths;
+ (NSMutableArray *) pathsUsingAddOns:(BOOL) include_addons;
+ (BOOL) areRequirementsFulfilled:(NSDictionary*) requirements;
+ (void) addExternalPath:(NSString *)filename;

+ (NSDictionary *) dictionaryFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername andMerge:(BOOL) mergeFiles;
+ (NSArray *) arrayFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername andMerge:(BOOL) mergeFiles;

+ (OOSound *) ooSoundNamed:(NSString *)filename inFolder:(NSString *)foldername;
+ (OOMusic *) ooMusicNamed:(NSString *)filename inFolder:(NSString *)foldername;

+ (NSImage *) imageNamed:(NSString *)filename inFolder:(NSString *)foldername;
+ (NSString *) stringFromFilesNamed:(NSString *)filename inFolder:(NSString *)foldername;
#ifdef GNUSTEP
+ (SDLImage *) surfaceNamed:(NSString *)filename inFolder:(NSString *)foldername;
#endif

+ (NSMutableArray *) scanTokensFromString:(NSString*) values;
+ (NSString *) decodeString:(NSString*) encodedString;
+ (OOXMLElement) parseOOXMLElement:(NSScanner*) scanner upTo:(NSString*)closingTag;
+ (NSObject*) parseXMLPropertyList:(NSString*)xmlString;
+ (NSObject*) objectFromXMLElement:(NSArray*) xmlElement;
+ (NSNumber*) trueFromXMLContent:(NSObject*) xmlContent;
+ (NSNumber*) falseFromXMLContent:(NSObject*) xmlContent;
+ (NSNumber*) realFromXMLContent:(NSObject*) xmlContent;
+ (NSNumber*) integerFromXMLContent:(NSObject*) xmlContent;
+ (NSString*) stringFromXMLContent:(NSObject*) xmlContent;
+ (NSDate*) dateFromXMLContent:(NSObject*) xmlContent;
+ (NSData*) dataFromXMLContent:(NSObject*) xmlContent;
+ (NSArray*) arrayFromXMLContent:(NSObject*) xmlContent;
+ (NSDictionary*) dictionaryFromXMLContent:(NSObject*) xmlContent;

+ (NSString*) stringFromGLFloats: (GLfloat*) float_array : (int) n_floats;
+ (void) GLFloatsFromString: (NSString*) float_string: (GLfloat*) float_array;

+ (NSString*) stringFromNSPoint: (NSPoint) point;
+ (NSPoint) NSPointFromString: (NSString*) point_string;

@end
