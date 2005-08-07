//
//  TextureStore.m
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

#ifdef GNUSTEP
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

#ifdef LINUX
#include "oolite-linux.h"
#else
#import <OpenGL/gl.h>
#endif

#import "ResourceManager.h"

#import "TextureStore.h"


@implementation TextureStore

- (id) init
{
    self = [super init];
    //
    textureDictionary = [[NSMutableDictionary dictionaryWithCapacity:5] retain];
    //
    return self;
}

- (void) dealloc
{
    if (textureDictionary) [textureDictionary release];
    //
    [super dealloc];
}

- (GLuint) getTextureNameFor:(NSString *)filename
{
#ifndef GNUSTEP
    NSBitmapImageRep	*bitmapImageRep;
    NSImage		*texImage, *image;
#else
	SDLImage *texImage;
#endif
    NSRect		textureRect = NSMakeRect(0.0,0.0,4.0,4.0);
    NSSize		imageSize;
    NSData		*textureData;
    GLuint		texName;
	
	int			n_planes;
    
    if (![textureDictionary objectForKey:filename])
    {
        NSMutableDictionary*	texProps = [NSMutableDictionary dictionaryWithCapacity:3];  // autoreleased
#ifndef GNUSTEP        
        texImage = [ResourceManager imageNamed:filename inFolder:@"Textures"];
#else
		texImage = [ResourceManager surfaceNamed:filename inFolder:@"Textures"];
#endif
        if (!texImage)
        {
            NSLog(@"***** Couldn't find texture : %@", filename);
			// ERROR no closing bracket for tag
			NSException* myException = [NSException
				exceptionWithName: @"OoliteException"
				reason: [NSString stringWithFormat:@"Oolite couldn't find texture : %@ on any search-path.", filename]
				userInfo: nil];
			[myException raise];
			return 0;
        }

#ifndef GNUSTEP        
        imageSize = [texImage size];
#else
		imageSize = NSMakeSize([texImage surface]->w, [texImage surface]->h);
#endif
        while (textureRect.size.width < imageSize.width)
            textureRect.size.width *= 2.0;
        while (textureRect.size.height < imageSize.height)
            textureRect.size.height *= 2.0;
        
        textureRect.origin= NSMakePoint(0.0,0.0);

        //  NSLog(@"textureSize = %f %f",textureRect.size.width,textureRect.size.height);
#ifndef GNUSTEP    
        image = [[NSImage alloc] initWithSize:textureRect.size]; // is retained
        
        // draw the texImage into an image of an appropriate size
        //
        [image lockFocus];
        
		[[NSColor clearColor] set];
        NSRectFill(textureRect);
        
		[texImage drawAtPoint:NSMakePoint(0.0,0.0) fromRect:NSMakeRect(0.0,0.0,imageSize.width,imageSize.height) operation:NSCompositeSourceOver fraction:1.0];
        bitmapImageRep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:textureRect];// is retained
        
//  NSLog(@"TextureStore bitMapImageRep for %@: has %d numberOfPlanes, %d samplesPerPixel", filename, [bitmapImageRep numberOfPlanes], [bitmapImageRep samplesPerPixel]);
		
		n_planes = [bitmapImageRep samplesPerPixel];
		
		[image unlockFocus];
    
        textureData = [[NSData dataWithBytes:[bitmapImageRep bitmapData] length:(int)(textureRect.size.width*textureRect.size.height*n_planes)] retain];
#else
		double zoomx = textureRect.size.width / imageSize.width;
		double zoomy = textureRect.size.height / imageSize.height;
#ifdef WIN32
		SDL_Surface* scaledImage = [texImage surface];
#else
		SDL_Surface* scaledImage = zoomSurface([texImage surface], zoomx, zoomy, SMOOTHING_OFF);
#endif
		SDL_LockSurface(scaledImage);
		textureData = [[NSData dataWithBytes:scaledImage->pixels length:scaledImage->w * scaledImage->h * scaledImage->format->BytesPerPixel] retain];

		n_planes = scaledImage->format->BytesPerPixel;

		SDL_UnlockSurface(scaledImage);
		SDL_FreeSurface(scaledImage);
#endif
                
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glGenTextures(1, &texName);			// get a new unique texture name
        glBindTexture(GL_TEXTURE_2D, texName);	// initialise it
    
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);	// adjust this
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);	// adjust this
    
        if (n_planes == 4)
			glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, textureRect.size.width, textureRect.size.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, [textureData bytes]);
		else
			glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, textureRect.size.width, textureRect.size.height, 0, GL_RGB, GL_UNSIGNED_BYTE, [textureData bytes]);
    
        // add to dictionary
        //
        [texProps setObject:textureData forKey:@"textureData"];
        [texProps setObject:[NSNumber numberWithInt:texName] forKey:@"texName"];
        [texProps setObject:[NSNumber numberWithInt:textureRect.size.width] forKey:@"width"];
        [texProps setObject:[NSNumber numberWithInt:textureRect.size.height] forKey:@"height"];

        [textureDictionary setObject:texProps forKey:filename];
        
#ifndef GNUSTEP        
        [image autorelease]; // is released
        
        [bitmapImageRep autorelease];// is released
#endif

		[textureData autorelease];// is released (retain count has been incremented by adding it to the texProps dictionary) 
    
    }
    else
    {
        texName = (GLuint)[(NSNumber *)[[textureDictionary objectForKey:filename] objectForKey:@"texName"] intValue];
    }
    return texName;
}

- (NSSize) getSizeOfTexture:(NSString *)filename
{
    NSSize size = NSMakeSize(0.0, 0.0);	// zero size
    if ([textureDictionary objectForKey:filename])
    {
        size.width = [(NSNumber *)[[textureDictionary objectForKey:filename] objectForKey:@"width"] intValue];
        size.height = [(NSNumber *)[[textureDictionary objectForKey:filename] objectForKey:@"height"] intValue];
    }
    return size;
}

- (void) reloadTextures
{
	[textureDictionary removeAllObjects];
	return;
}

@end
