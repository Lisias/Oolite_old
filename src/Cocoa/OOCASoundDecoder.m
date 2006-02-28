//	
//	OOCASoundDecoder.m
//	CoreAudio sound implementation for Oolite
//	
/*

Copyright © 2005, Jens Ayton
All rights reserved.

This work is licensed under the Creative Commons Attribution-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#import "OOCASoundDecoder.h"
#import <stdio.h>
#import <vorbis/vorbisfile.h>


enum
{
	kMaxDecodeSize			= 1 << 20		// 2^20 frames = four megs of data
};


static void MixDown(float *inChan1, float *inChan2, float *outMix, size_t inCount);


@interface OOSoundCAVorbisCodec: OOCASoundDecoder
{
	OggVorbis_File			_vf;
	NSString				*_name;
	BOOL					_atEnd;
}

- (NSDictionary *)comments;

@end


@implementation OOCASoundDecoder

#ifndef NDEBUG
- (id)init
{
	NSLog(@"Invalid call of %s.", __PRETTY_FUNCTION__);
	[self release];
	return nil;
}
#endif


- (id)initWithPath:(NSString *)inPath
{
	[self release];
	self = nil;
	
	if ([[inPath pathExtension] isEqual:@"ogg"])
	{
		self = [[OOSoundCAVorbisCodec alloc] initWithPath:inPath];
	}
	
	return self;
}


+ (OOCASoundDecoder *)codecWithPath:(NSString *)inPath
{
	if ([[inPath pathExtension] isEqual:@"ogg"])
	{
		return [[[OOSoundCAVorbisCodec alloc] initWithPath:inPath] autorelease];
	}
	return nil;
}


- (size_t)readStereoToBufferL:(float *)ioBufferL bufferR:(float *)ioBufferR maxFrames:(size_t)inMax
{
	return 0;
}


- (BOOL)readMonoCreatingBuffer:(float **)outBuffer withFrameCount:(size_t *)outSize
{
	if (NULL != outBuffer) *outBuffer = NULL;
	if (NULL != outSize) *outSize = 0;
	
	return NO;
}


- (double)sampleRate
{
	return 0;
}


- (BOOL)atEnd
{
	return YES;
}


- (void)rewindToBeginning
{
	
}


- (NSString *)name
{
	return @"";
}

@end


@implementation OOSoundCAVorbisCodec

- (id)initWithPath:(NSString *)inPath
{
	BOOL				OK = NO;
	int					err;
	FILE				*file;
	
	_name = [[inPath lastPathComponent] retain];
	
	if (nil != inPath)
	{
		file = fopen([inPath UTF8String], "rb");
		if (NULL != file) 
		{
			err = ov_open(file, &_vf, NULL, 0);
			if (0 == err)
			{
				OK = YES;
			}
		}
	}
	
	if (!OK)
	{
		[self release];
		self = nil;
	}
	
	return self;
}


- (void)dealloc
{
	[_name release];
	ov_clear(&_vf);
	
	[super dealloc];
}


- (NSDictionary *)comments
{
	vorbis_comment			*comments;
	unsigned				i, count;
	NSMutableDictionary		*result = nil;
	NSString				*comment, *key, *value;
	NSRange					range;
	
	comments = ov_comment(&_vf, -1);
	if (NULL != comments)
	{
		count = comments->comments;
		if (0 != count)
		{
			result = [NSMutableDictionary dictionaryWithCapacity:count];
			for (i = 0; i != count; ++i)
			{
				comment = [[NSString alloc] initWithBytesNoCopy:comments->user_comments[i] length:comments->comment_lengths[i] encoding:NSUTF8StringEncoding freeWhenDone:NO];
				range = [comment rangeOfString:@"="];
				if (0 != range.length)
				{
					key = [comment substringToIndex:range.location];
					value = [comment substringFromIndex:range.location + 1];
				}
				else
				{
					key = comment;
					value = @"";
				}
				[result setObject:value forKey:key];
				
				[comment release];
			}
		}
	}
	
	return result;
}


- (size_t)readStereoToBufferL:(float *)ioBufferL bufferR:(float *)ioBufferR maxFrames:(size_t)inMax
{
	float					**src;
	unsigned				chanCount;
	unsigned				framesRead, size;
	size_t					remaining;
	unsigned				rightChan;
	
	// Note: for our purposes, a frame is a set of one sample for each channel.
	if (NULL == ioBufferL || NULL == ioBufferR || 0 == inMax) return 0;
	if (_atEnd) return inMax;
	
	remaining = inMax;
	do
	{
		chanCount = ov_info(&_vf, -1)->channels;
		framesRead = ov_read_float(&_vf, &src, remaining, NULL);
		if (framesRead <= 0)
		{
			if (OV_HOLE == framesRead) continue;
			//else:
			_atEnd = YES;
			break;
		}
		
		size = sizeof (float) * framesRead;
		
		rightChan = (1 == chanCount) ? 0 : 1;
		bcopy(src[0], ioBufferL, size);
		bcopy(src[rightChan], ioBufferR, size);
		
		remaining -= framesRead;
		ioBufferL += framesRead;
		ioBufferR += framesRead;
	} while (0 != remaining);
	
	return inMax - remaining;
}


- (BOOL)readMonoCreatingBuffer:(float **)outBuffer withFrameCount:(size_t *)outSize
{
	float					*buffer, *dst, **src;
	size_t					sizeInFrames, remaining;
	unsigned				chanCount;
	unsigned				framesRead;
	ogg_int64_t				totalSizeInFrames;
	BOOL					OK = YES;
	
	if (NULL != outBuffer) *outBuffer = NULL;
	if (NULL != outSize) *outSize = 0;
	if (NULL == outBuffer || NULL == outSize) OK = NO;
	
	if (OK)
	{
		totalSizeInFrames = ov_pcm_total(&_vf, -1);
		if (kMaxDecodeSize < totalSizeInFrames)
		{
			NSLog(@"Refusing to load %@ because its uncompressed size is over %u bytes.", [self name], kMaxDecodeSize * sizeof (float));
			OK = NO;
		}
		sizeInFrames = totalSizeInFrames;
	}
	
	if (OK)
	{
		buffer = malloc(sizeof (float) * sizeInFrames);
		if (!buffer) OK = NO;
	}
	
	if (OK && sizeInFrames)
	{
		remaining = sizeInFrames;
		dst = buffer;
		
		do
		{
			chanCount = ov_info(&_vf, -1)->channels;
			framesRead = ov_read_float(&_vf, &src, remaining, NULL);
			if (framesRead <= 0)
			{
				if (OV_HOLE == framesRead) continue;
				//else:
				break;
			}
			
			if (1 == chanCount) bcopy(src[0], dst, sizeof (float) * framesRead);
			else MixDown(src[0], src[1], dst, framesRead);
			
			remaining -= framesRead;
			dst += framesRead;
		} while (0 != remaining);
		
		sizeInFrames -= remaining;	// In case we stopped at an error
	}
	
	if (OK)
	{
		*outBuffer = buffer;
		*outSize = sizeInFrames;
	}
	return OK;
}


- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p>{\"%@\", comments=%@}", [self className], self, _name, [self comments]];
}


- (Float64)sampleRate
{
	return ov_info(&_vf, -1)->rate;
}


- (BOOL)atEnd
{
	return _atEnd;
}


- (void)rewindToBeginning
{
	if (!ov_pcm_seek(&_vf, 0)) _atEnd = NO;
}


- (NSString *)name
{
	NSDictionary			*comments;
	NSString				*result = nil;
	
	comments = [self comments];
	if (nil != comments)
	{
		result = [comments objectForKey:@"TITLE"];
		if (nil == result) result = [comments objectForKey:@"NAME"];
	}
	
	if (nil == result) result = [[_name retain] autorelease];
	if (nil == result) result = [super name];
	
	return result;
}

@end


// TODO: optimise, vectorise
static void MixDown(float *inChan1, float *inChan2, float *outMix, size_t inCount)
{
	while (inCount--)
	{
		*outMix++ = (*inChan1++ + *inChan2++) * 0.5f;
	}
}
