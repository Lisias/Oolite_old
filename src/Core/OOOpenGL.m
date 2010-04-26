/*

OOOpenGL.m

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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

#import "OOOpenGL.h"
#import "OOLogging.h"
#import "OOMaths.h"
#import "OOMacroOpenGL.h"
#import "OOFunctionAttributes.h"
#import "OOOpenGLExtensionManager.h"


static NSString * const kOOLogOpenGLStateDump				= @"rendering.opengl.stateDump";


BOOL CheckOpenGLErrors(NSString *format, ...)
{
	GLenum			errCode;
	const GLubyte	*errString = NULL;
	BOOL			errorOccurred = NO;
	va_list			args;
	static BOOL		noReenter;
	
	if (noReenter)  return NO;
	noReenter = YES;
	
	OO_ENTER_OPENGL();
	
	// Short-circut here, because glGetError() is quite expensive.
	if (OOLogWillDisplayMessagesInClass(kOOLogOpenGLError))
	{
		for (;;)
		{
			errCode = glGetError();
			
			if (errCode == GL_NO_ERROR)  break;
			
			errorOccurred = YES;
			errString = gluErrorString(errCode);
			if (format == nil) format = @"<unknown>";
			
			va_start(args, format);
			format = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
			va_end(args);
			OOLog(kOOLogOpenGLError, @"OpenGL error: \"%s\" (%#x), context: %@", errString, errCode, format);
		}
	}
	
#if OO_CHECK_GL_HEAVY
	if (errorOccurred)
	{
		OOLogIndent();
		LogOpenGLState();
		OOLogOutdent();
		while (glGetError() != 0) {}	// Suppress any errors caused by LogOpenGLState().
	}
#endif
	
	noReenter = NO;
	return errorOccurred;
}


void GLDebugWireframeModeOn(void)
{
	OO_ENTER_OPENGL();
	
	OOGL(glPushAttrib(GL_POLYGON_BIT | GL_LINE_BIT | GL_TEXTURE_BIT));
	OOGL(glLineWidth(1.0f));
	OOGL(glPolygonMode(GL_FRONT_AND_BACK, GL_LINE));
	OOGL(glDisable(GL_TEXTURE_2D));
}


void GLDebugWireframeModeOff(void)
{
	OO_ENTER_OPENGL();
	
	OOGL(glPopAttrib());
}


void GLDrawBallBillboard(GLfloat radius, GLfloat step, GLfloat z_distance)
{
	if (EXPECT_NOT((radius <= 0)||(step < 1)))  return;
	if (EXPECT_NOT(radius >= z_distance))  return;	// inside the sphere
	
	GLfloat			i, delta;
	GLfloat			s, c;
	GLfloat			r;
	
	OO_ENTER_OPENGL();
	
	r = radius * z_distance / sqrt(z_distance * z_distance - radius * radius);
	delta = step * M_PI / 180.0f;	// Convert step from degrees to radians
	
	glVertex3i(0, 0, 0);
	for (i = 0; i < (M_PI * 2.0); i += delta)
	{
		s = r * sinf(i);
		c = r * cosf(i);
		glVertex3f(s, c, 0.0);
	}
	glVertex3f(0.0, r, 0.0);	//repeat the zero value to close
}


static void GLDrawOvalPoints(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat step);

static void GLDrawOvalPoints(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat step)
{
	GLfloat			ww = 0.5 * siz.width;
	GLfloat			hh = 0.5 * siz.height;
	GLfloat			theta;
	GLfloat			delta;
	
	OO_ENTER_OPENGL();
	
	delta = step * M_PI / 180.0f;
	
	for (theta = 0.0f; theta < (2.0f * M_PI); theta += delta)
	{
		glVertex3f(x + ww * sinf(theta), y + hh * cosf(theta), z);
	}
	glVertex3f(x, y + hh, z);
}


void GLDrawOval(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat step)
{
	OO_ENTER_OPENGL();
	
	OOGLBEGIN(GL_LINE_STRIP);
	GLDrawOvalPoints(x, y, z, siz, step);
	OOGLEND();
}


void GLDrawFilledOval(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat step)
{
	OO_ENTER_OPENGL();
	
	OOGLBEGIN(GL_TRIANGLE_FAN);
	GLDrawOvalPoints(x, y, z, siz, step);
	OOGLEND();
}


enum
{
	// Number of cached texture names. Unused texture names are cheap, so we use lots.
	kTextureNameCacheMaxSize		= 128,
	
	// Number of texture names to discard at a time when cache overflows.
	kTextureNameCacheFlushCount		= kTextureNameCacheMaxSize / 4
};

static GLuint		sTextureNameCache[kTextureNameCacheMaxSize];
static unsigned		sTextureNameCacheSize = 0;
static BOOL			sTextureNameCacheEnabled = YES;


GLuint GLAllocateTextureName(void)
{
	OO_ENTER_OPENGL();
	
	if (!sTextureNameCacheEnabled)
	{
		OOLog(@"textureNameCache.allocate.uncached", @"Request for texture name while cache disabled.");
		
		GLuint result;
		OOGL(glGenTextures(1, &result));
		return result;
	}
	
	OOLog(@"textureNameCache.allocate", @"Request for texture name while cache size is %u.", sTextureNameCacheSize);
	
	if (sTextureNameCacheSize == 0)
	{
		OOLog(@"textureNameCache.fill", @"Adding %u elements to texture names cache.", kTextureNameCacheMaxSize);
		// Allocate a block of names.
		OOGL(glGenTextures(kTextureNameCacheMaxSize, sTextureNameCache));
		sTextureNameCacheSize = kTextureNameCacheMaxSize;
	}
	
	assert(sTextureNameCacheSize != 0);
	
	return sTextureNameCache[--sTextureNameCacheSize];
}


void GLRecycleTextureName(GLuint name, GLuint mipLevels)
{
	if (name == 0 || !sTextureNameCacheEnabled)  return;
	
	OOLog(@"textureNameCache.recycle", @"Recycling texture name while cache size is %u.", sTextureNameCacheSize);
	
	OO_ENTER_OPENGL();
	
	if (sTextureNameCacheSize == kTextureNameCacheMaxSize)
	{
		OOLog(@"textureNameCache.flush", @"Deleting %u elements from texture names cache.", kTextureNameCacheFlushCount);
		// No more space; delete several elements (to avoid a series of individual deletes)
		sTextureNameCacheSize -= kTextureNameCacheFlushCount;
		OOGL(glDeleteTextures(kTextureNameCacheFlushCount, &sTextureNameCache[sTextureNameCacheSize]));
	}
	
	assert(sTextureNameCacheSize < kTextureNameCacheMaxSize);
	
	GLuint		i;
	uint8_t		junk[4];
	
	for (i = 0; i != mipLevels; ++i)
	{
		OOGL(glBindTexture(GL_TEXTURE_2D, name));
		OOGL(glTexImage2D(GL_TEXTURE_2D, i, GL_RGBA, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, junk));
	}
	
	sTextureNameCache[sTextureNameCacheSize++] = name;
}


void GLDropCachedTextureNames(void)
{
	OOLog(@"textureNameCache.reset", @"Dropping texture cache.");
	sTextureNameCacheSize = 0;
}


void GLSetTextureNameCacheEnabled(BOOL enabled)
{
	if (enabled != sTextureNameCacheEnabled)
	{
		sTextureNameCacheEnabled = enabled;
		OOLog(@"textureNameCache.toggle", @"%@ texture cache.", enabled ? @"Enabled" : @"Disabled");
	}
}


// ======== LogOpenGLState() and helpers ========

#ifndef NDEBUG

static NSString *GLColorToString(GLfloat color[4]);
static NSString *GLEnumToString(GLenum value);

static void GLDumpLightState(unsigned lightIdx);
static void GLDumpMaterialState(void);
static void GLDumpCullingState(void);
static void GLDumpFogState(void);
static void GLDumpStateFlags(void);


void LogOpenGLState(void)
{
	unsigned			i;
	
	if (!OOLogWillDisplayMessagesInClass(kOOLogOpenGLStateDump))  return;
	
	OO_ENTER_OPENGL();
	
	OOLog(kOOLogOpenGLStateDump, @"OpenGL state dump:");
	OOLogIndent();
	
	GLDumpMaterialState();
	GLDumpCullingState();
	if (glIsEnabled(GL_LIGHTING))
	{
		OOLog(kOOLogOpenGLStateDump, @"Lighting: enabled");
		for (i = 0; i != 8; ++i)
		{
			GLDumpLightState(i);
		}
	}
	else
	{
		OOLog(kOOLogOpenGLStateDump, @"Lighting: disabled");
	}

	GLDumpFogState();
	GLDumpStateFlags();
	
	CheckOpenGLErrors(@"After state dump");
	
	OOLogOutdent();
}


static NSString *GLColorToString(GLfloat color[4])
{
	#define COLOR_EQUAL(color, r, g, b, a)  (color[0] == (r) && color[1] == (g) && color[2] == (b) && color[3] == (a))
	#define COLOR_CASE(r, g, b, a, str)  do { if (COLOR_EQUAL(color, (r), (g), (b), (a)))  return (str); } while (0)
	
	COLOR_CASE(1, 1, 1, 1, @"white");
	COLOR_CASE(0, 0, 0, 1, @"black");
	COLOR_CASE(0, 0, 0, 0, @"clear");
	COLOR_CASE(1, 0, 0, 1, @"red");
	COLOR_CASE(0, 1, 0, 1, @"green");
	COLOR_CASE(0, 0, 1, 1, @"blue");
	COLOR_CASE(0, 1, 1, 1, @"cyan");
	COLOR_CASE(1, 0, 1, 1, @"magenta");
	COLOR_CASE(1, 1, 0, 1, @"yellow");
	
	return [NSString stringWithFormat:@"(%.2ff, %.2ff, %.2ff, %.2ff)", color[0], color[1], color[2], color[3]];
}


static void GLDumpLightState(unsigned lightIdx)
{
	BOOL			enabled;
	GLenum			lightID = GL_LIGHT0 + lightIdx;
	GLfloat			color[4];
	
	OO_ENTER_OPENGL();
	
	OOGL(enabled = glIsEnabled(lightID));
	OOLog(kOOLogOpenGLStateDump, @"Light %u: %s", lightIdx, enabled ? "ENABLED" : "disabled");
	
	if (enabled)
	{
		OOLogIndent();
		
		OOGL(glGetLightfv(GL_LIGHT1, GL_AMBIENT, color));
		OOLog(kOOLogOpenGLStateDump, @"Ambient: %@", GLColorToString(color));
		OOGL(glGetLightfv(GL_LIGHT1, GL_DIFFUSE, color));
		OOLog(kOOLogOpenGLStateDump, @"Diffuse: %@", GLColorToString(color));
		OOGL(glGetLightfv(GL_LIGHT1, GL_SPECULAR, color));
		OOLog(kOOLogOpenGLStateDump, @"Specular: %@", GLColorToString(color));
		
		OOLogOutdent();
	}
}


static void GLDumpMaterialState(void)
{
	GLfloat					color[4];
	GLfloat					shininess;
	GLint					shadeModel,
							blendSrc,
							blendDst,
							texMode;
	BOOL					blending;
	
	OO_ENTER_OPENGL();
	
	OOLog(kOOLogOpenGLStateDump, @"Material state:");
	OOLogIndent();
	
	OOGL(glGetMaterialfv(GL_FRONT, GL_AMBIENT, color));
	OOLog(kOOLogOpenGLStateDump, @"Ambient: %@", GLColorToString(color));
	
	OOGL(glGetMaterialfv(GL_FRONT, GL_DIFFUSE, color));
	OOLog(kOOLogOpenGLStateDump, @"Diffuse: %@", GLColorToString(color));
	
	OOGL(glGetMaterialfv(GL_FRONT, GL_EMISSION, color));
	OOLog(kOOLogOpenGLStateDump, @"Emission: %@", GLColorToString(color));
	
	OOGL(glGetMaterialfv(GL_FRONT, GL_SPECULAR, color));
	OOLog(kOOLogOpenGLStateDump, @"Specular: %@", GLColorToString(color));
	
	OOGL(glGetMaterialfv(GL_FRONT, GL_SHININESS, &shininess));
	OOLog(kOOLogOpenGLStateDump, @"Shininess: %g", shininess);
	
	OOGL(OOLog(kOOLogOpenGLStateDump, @"Colour material: %s", glIsEnabled(GL_COLOR_MATERIAL) ? "ENABLED" : "disabled"));
	
	OOGL(glGetFloatv(GL_CURRENT_COLOR, color));
	OOLog(kOOLogOpenGLStateDump, @"Current color: %@", GLColorToString(color));
	
	OOGL(glGetIntegerv(GL_SHADE_MODEL, &shadeModel));
	OOLog(kOOLogOpenGLStateDump, @"Shade model: %@", GLEnumToString(shadeModel));
	
	OOGL(blending = glIsEnabled(GL_BLEND));
	OOLog(kOOLogOpenGLStateDump, @"Blending: %s", blending ? "ENABLED" : "disabled");
	if (blending)
	{
		OOGL(glGetIntegerv(GL_BLEND_SRC, &blendSrc));
		OOGL(glGetIntegerv(GL_BLEND_DST, &blendDst));
		OOLog(kOOLogOpenGLStateDump, @"Blend function: %@, %@", GLEnumToString(blendSrc), GLEnumToString(blendDst));
	}
	
	OOGL(glGetTexEnviv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, &texMode));
	OOLog(kOOLogOpenGLStateDump, @"Texture env mode: %@", GLEnumToString(texMode));
	
#if OO_MULTITEXTURE
	if ([[OOOpenGLExtensionManager sharedManager] textureUnitCount] > 1)
	{
		GLint textureUnit;
		OOGL(glGetIntegerv(GL_ACTIVE_TEXTURE_ARB, &textureUnit));
		OOLog(kOOLogOpenGLStateDump, @"Active texture unit: %@", GLEnumToString(textureUnit));
		
		OOGL(glGetIntegerv(GL_CLIENT_ACTIVE_TEXTURE_ARB, &textureUnit));
		OOLog(kOOLogOpenGLStateDump, @"Active client texture unit: %@", GLEnumToString(textureUnit));
	}
#endif
	
	OOLogOutdent();
}


static void GLDumpCullingState(void)
{
	GLint					value;
	
	OO_ENTER_OPENGL();
	
	OOGL(glGetIntegerv(GL_CULL_FACE_MODE, &value));
	OOLog(kOOLogOpenGLStateDump, @"Cull face mode: %@", GLEnumToString(value));
	
	OOGL(glGetIntegerv(GL_FRONT_FACE, &value));
	OOLog(kOOLogOpenGLStateDump, @"Front face direction: %@", GLEnumToString(value));
}


static void GLDumpFogState(void)
{
	BOOL					enabled;
	GLint					value;
	GLfloat					start,
							end,
							density,
							index;
	GLfloat					color[4];
	
	OO_ENTER_OPENGL();
	
	OOGL(enabled = glIsEnabled(GL_FOG));
	OOLog(kOOLogOpenGLStateDump, @"Fog: %s", enabled ? "ENABLED" : "disabled");
	if (enabled)
	{
		OOLogIndent();
		
		OOGL(glGetIntegerv(GL_FOG_MODE, &value));
		OOLog(kOOLogOpenGLStateDump, @"Fog mode: *@", GLEnumToString(value));
		
		OOGL(glGetFloatv(GL_FOG_COLOR, color));
		OOLog(kOOLogOpenGLStateDump, @"Fog colour: %@", GLColorToString(color));
		
		OOGL(glGetFloatv(GL_FOG_START, &start));
		OOGL(glGetFloatv(GL_FOG_START, &end));
		OOLog(kOOLogOpenGLStateDump, @"Fog start, end: %g, %g", start, end);
		
		OOGL(glGetFloatv(GL_FOG_DENSITY, &density));
		OOLog(kOOLogOpenGLStateDump, @"Fog density: %g", density);
		
		OOGL(glGetFloatv(GL_FOG_DENSITY, &index));
		OOLog(kOOLogOpenGLStateDump, @"Fog index: %g", index);
		
		OOLogOutdent();
	}
}


static void GLDumpStateFlags(void)
{
	OO_ENTER_OPENGL();
	
#define DUMP_STATE_FLAG(x) OOLog(kOOLogOpenGLStateDump, @ #x ": %s", glIsEnabled(x) ? "ENABLED" : "disabled")
#define DUMP_GET_FLAG(x) do { GLboolean flag; glGetBooleanv(x, &flag); OOLog(kOOLogOpenGLStateDump, @ #x ": %s", flag ? "ENABLED" : "disabled"); } while (0)
	
	OOLog(kOOLogOpenGLStateDump, @"Selected state flags:");
	OOLogIndent();
	
	DUMP_STATE_FLAG(GL_VERTEX_ARRAY);
	DUMP_STATE_FLAG(GL_NORMAL_ARRAY);
	DUMP_STATE_FLAG(GL_TEXTURE_COORD_ARRAY);
	DUMP_STATE_FLAG(GL_COLOR_ARRAY);
	DUMP_STATE_FLAG(GL_INDEX_ARRAY);
	DUMP_STATE_FLAG(GL_EDGE_FLAG_ARRAY);
	DUMP_STATE_FLAG(GL_TEXTURE_2D);
	DUMP_STATE_FLAG(GL_DEPTH_TEST);
	DUMP_GET_FLAG(GL_DEPTH_WRITEMASK);
	DUMP_GET_FLAG(GL_DITHER);
	DUMP_STATE_FLAG(GL_POINT_SMOOTH);
	DUMP_STATE_FLAG(GL_LINE_SMOOTH);
	
	OOLogOutdent();
	
#undef DUMP_STATE_FLAG
}


#define CASE(x)		case x: return @#x

static NSString *GLEnumToString(GLenum value)
{
	switch (value)
	{
		// ShadingModel
		CASE(GL_FLAT);
		CASE(GL_SMOOTH);
		
		// BlendingFactorSrc/BlendingFactorDest
		CASE(GL_ZERO);
		CASE(GL_ONE);
		CASE(GL_DST_COLOR);
		CASE(GL_SRC_COLOR);
		CASE(GL_ONE_MINUS_DST_COLOR);
		CASE(GL_ONE_MINUS_SRC_COLOR);
		CASE(GL_SRC_ALPHA);
		CASE(GL_DST_ALPHA);
		CASE(GL_ONE_MINUS_SRC_ALPHA);
		CASE(GL_ONE_MINUS_DST_ALPHA);
		CASE(GL_SRC_ALPHA_SATURATE);
		
		// TextureEnvMode
		CASE(GL_MODULATE);
		CASE(GL_DECAL);
		CASE(GL_BLEND);
		CASE(GL_REPLACE);
		
		// FrontFaceDirection
		CASE(GL_CW);
		CASE(GL_CCW);
		
		// CullFaceMode
		CASE(GL_FRONT);
		CASE(GL_BACK);
		CASE(GL_FRONT_AND_BACK);
		
		// FogMode
		CASE(GL_LINEAR);
		CASE(GL_EXP);
		CASE(GL_EXP2);
		
#if OO_MULTITEXTURE
		// Texture units
#ifdef GL_TEXTURE0
#define TEXCASE CASE
#else
#define TEXCASE(x) CASE(x##_ARB)
#endif
		TEXCASE(GL_TEXTURE0);
		TEXCASE(GL_TEXTURE1);
		TEXCASE(GL_TEXTURE2);
		TEXCASE(GL_TEXTURE3);
		TEXCASE(GL_TEXTURE4);
		TEXCASE(GL_TEXTURE5);
		TEXCASE(GL_TEXTURE6);
		TEXCASE(GL_TEXTURE7);
		TEXCASE(GL_TEXTURE8);
		TEXCASE(GL_TEXTURE9);
		TEXCASE(GL_TEXTURE10);
		TEXCASE(GL_TEXTURE11);
		TEXCASE(GL_TEXTURE12);
		TEXCASE(GL_TEXTURE13);
		TEXCASE(GL_TEXTURE14);
		TEXCASE(GL_TEXTURE15);
#endif
		
		default: return [NSString stringWithFormat:@"unknown: %u", value];
	}
}

#else

void LogOpenGLState(void)
{
	
}

#endif
