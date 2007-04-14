/*

OOOpenGLExtensionManager.m

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

#import "OOOpenGLExtensionManager.h"
#import "OOLogging.h"
#import "OOFunctionAttributes.h"


static NSString * const kOOLogOpenGLShaderSupport		= @"rendering.opengl.shader.support";


static OOOpenGLExtensionManager *sSingleton = nil;


// Read integer from string, advancing string to end of read data.
static unsigned IntegerFromString(const GLubyte **ioString);


@implementation OOOpenGLExtensionManager

- (id)init
{
	NSString			*extensionString = nil;
	NSArray				*components = nil;
	const GLubyte		*versionString = nil, *curr = nil;
	
	self = [super init];
	if (self != nil)
	{
		lock = [[NSLock alloc] init];
		
		extensionString = [NSString stringWithUTF8String:(char *)glGetString(GL_EXTENSIONS)];
		components = [extensionString componentsSeparatedByString:@" "];
		extensions = [[NSSet alloc] initWithArray:components];
		
		vendor = [[NSString alloc] initWithUTF8String:(const char *)glGetString(GL_VENDOR)];
		renderer = [[NSString alloc] initWithUTF8String:(const char *)glGetString(GL_RENDERER)];
		
		versionString = glGetString(GL_VERSION);
		if (versionString != NULL)
		{
			/*	String is supposed to be "major.minorFOO" or
				"major.minor.releaseFOO" where FOO is an empty string or
				a string beginning with space.
			*/
			curr = versionString;
			major = IntegerFromString(&curr);
			if (*curr == '.')
			{
				curr++;
				minor = IntegerFromString(&curr);
			}
			if (*curr == '.')
			{
				curr++;
				release = IntegerFromString(&curr);
			}
		}
		
		OOLog(@"rendering.opengl.version", @"OpenGL renderer version: %u.%u.%u (\"%s\")\nVendor: %@\nRenderer: %@", major, minor, release, versionString, vendor, renderer);
		OOLog(@"rendering.opengl.extensions", @"OpenGL extensions (%u):\n%@", [extensions count], extensionString);
	}
	return self;
}


- (void)dealloc
{
	[extensions release];
	[lock release];
	
	[super dealloc];
}


+ (id)sharedManager
{
	// NOTE: assumes single-threaded first access. See header.
	if (sSingleton == nil)  [[self alloc] init];
	return sSingleton;
}


- (BOOL)haveExtension:(NSString *)extension
{
	[lock lock];
	BOOL result = [extensions containsObject:extension];
	[lock unlock];
	return result;
}


- (BOOL)shadersSupported
{
#ifndef NO_SHADERS
	if (EXPECT(testedForShaders))  return shadersAvailable;
	
	[lock lock];
	testedForShaders = YES;
	
	if (major == 1 && minor < 5)
	{
		OOLog(kOOLogOpenGLShaderSupport, @"Shaders will not be used (OpenGL version < 1.5).");
		goto END;
	}
	
	const NSString		*requiredExtension[] = 
						{
							@"GL_ARB_multitexture",
							@"GL_ARB_shader_objects",
							@"GL_ARB_shading_language_100",
							@"GL_ARB_fragment_shader",
							@"GL_ARB_vertex_shader",
							@"GL_ARB_fragment_program",
							@"GL_ARB_vertex_program",
							nil	// sentinel - don't remove!
						};
	NSString			**required = NULL;
	
	for (required = requiredExtension; *required != nil; ++required)
	{
		if (![extensions containsObject:*required])	// Note to people cleaning up: can't use haveExtension: because we've already got the lock.
		{
			OOLog(kOOLogOpenGLShaderSupport, @"Shaders will not be used (OpenGL extension %@ is not available).", *required);
			goto END;
		}
	}
	
#if OOLITE_WINDOWS
	glGetObjectParameterivARB = (PFNGLGETOBJECTPARAMETERIVARBPROC)wglGetProcAddress("glGetObjectParameterivARB");
	glCreateShaderObjectARB = (PFNGLCREATESHADEROBJECTARBPROC)wglGetProcAddress("glCreateShaderObjectARB");
	glGetInfoLogARB = (PFNGLGETINFOLOGARBPROC)wglGetProcAddress("glGetInfoLogARB");
	glCreateProgramObjectARB = (PFNGLCREATEPROGRAMOBJECTARBPROC)wglGetProcAddress("glCreateProgramObjectARB");
	glAttachObjectARB = (PFNGLATTACHOBJECTARBPROC)wglGetProcAddress("glAttachObjectARB");
	glDeleteObjectARB = (PFNGLDELETEOBJECTARBPROC)wglGetProcAddress("glDeleteObjectARB");
	glLinkProgramARB = (PFNGLLINKPROGRAMARBPROC)wglGetProcAddress("glLinkProgramARB");
	glCompileShaderARB = (PFNGLCOMPILESHADERARBPROC)wglGetProcAddress("glCompileShaderARB");
	glShaderSourceARB = (PFNGLSHADERSOURCEARBPROC)wglGetProcAddress("glShaderSourceARB");
	glUseProgramObjectARB = (PFNGLUSEPROGRAMOBJECTARBPROC)wglGetProcAddress("glUseProgramObjectARB");
	glActiveTextureARB = (PFNGLACTIVETEXTUREARBPROC)wglGetProcAddress("glActiveTextureARB");
	glGetUniformLocationARB = (PFNGLGETUNIFORMLOCATIONARBPROC)wglGetProcAddress("glGetUniformLocationARB");
	glUniform1iARB = (PFNGLUNIFORM1IARBPROC)wglGetProcAddress("glUniform1iARB");
	glUniform1fARB = (PFNGLUNIFORM1FARBPROC)wglGetProcAddress("glUniform1fARB");
#endif
	
	shadersAvailable = YES;
	
END:
	[lock unlock];
	return shadersAvailable;
#else
	// NO_SHADERS
	return NO;
#endif
}


- (unsigned)majorVersionNumber
{
	return major;
}


- (unsigned)minorVersionNumber
{
	return minor;
}


- (unsigned)releaseVersionNumber
{
	return release;
}


- (void)getVersionMajor:(unsigned *)outMajor minor:(unsigned *)outMinor release:(unsigned *)outRelease
{
	if (outMajor != NULL)  *outMajor = major;
	if (outMinor != NULL)  *outMinor = minor;
	if (outRelease != NULL)  *outRelease = release;
}

@end


static unsigned IntegerFromString(const GLubyte **ioString)
{
	if (EXPECT_NOT(ioString == NULL))  return 0;
	
	unsigned		result = 0;
	const GLubyte	*curr = *ioString;
	
	while ('0' <= *curr && *curr <= '9')
	{
		result = result * 10 + *curr++ - '0';
	}
	
	*ioString = curr;
	return result;
}


@implementation OOOpenGLExtensionManager (Singleton)

/*	Canonical singleton boilerplate.
	See Cocoa Fundamentals Guide: Creating a Singleton Instance.
	See also +sharedManager above.
	
	// NOTE: assumes single-threaded first access.
*/

+ (id)allocWithZone:(NSZone *)inZone
{
	if (sSingleton == nil)
	{
		sSingleton = [super allocWithZone:inZone];
		return sSingleton;
	}
	return nil;
}


- (id)copyWithZone:(NSZone *)inZone
{
	return self;
}


- (id)retain
{
	return self;
}


- (unsigned)retainCount
{
	return UINT_MAX;
}


- (void)release
{}


- (id)autorelease
{
	return self;
}

@end
