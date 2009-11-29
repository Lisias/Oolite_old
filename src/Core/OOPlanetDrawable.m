/*
 
 OOPlanetDrawable.m
 
 Oolite
 Copyright (C) 2004-2009 Giles C Williams and contributors
 
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

#import "OOPlanetDrawable.h"
#import "OOPlanetData.h"
#import "OOSingleTextureMaterial.h"
#import "OOOpenGL.h"
#import "OOMacroOpenGL.h"
#import "Universe.h"

#ifndef NDEBUG
#import "Entity.h"
#import "OODebugGLDrawing.h"
#endif


#define LOD_GRANULARITY	((float)(kOOPlanetDataLevels - 1))


@interface OOPlanetDrawable (Private)

- (void) recalculateTransform;

- (void) debugDrawNormals;

@end


@implementation OOPlanetDrawable

+ (id) planetWithTextureName:(NSString *)textureName radius:(float)radius eccentricity:(float)eccentricity
{
	OOPlanetDrawable *result = [[[self alloc] init] autorelease];
	[result setTextureName:textureName];
	[result setRadius:radius];
	[result setEccentricity:eccentricity];
	
	return result;
}


+ (id) atmosphereWithRadius:(float)radius eccentricity:(float)eccentricity
{
	OOPlanetDrawable *result = [[[self alloc] initAsAtmosphere] autorelease];
	[result setRadius:radius];
	[result setEccentricity:eccentricity];
	
	return result;
}


- (id) init
{
	if ((self = [super init]))
	{
		_radius = 1.0f;
		_eccentricity = 0.0f;
		[self recalculateTransform];
		[self setLevelOfDetail:0.5f];
	}
	
	return self;
}


- (id) initAsAtmosphere
{
	if ((self = [self init]))
	{
		_isAtmosphere = YES;
		[self setTextureName:@"oolite-temp-atmosphere.png"];
	}
	
	return self;
}


- (void) dealloc
{
	[_material release];
	
	[super dealloc];
}


- (NSString *) textureName
{
	return [_material name];
}


- (void) setTextureName:(NSString *)textureName
{
	if (![textureName isEqual:[self textureName]])
	{
		[_material release];
		_material = [[OOSingleTextureMaterial alloc] initWithName:textureName configuration:nil];
	}
}


- (float) radius
{
	return _radius;
}


- (void) setRadius:(float)radius
{
	_radius = fabsf(radius);
	[self recalculateTransform];
}


- (float) eccentricity
{
	return _eccentricity;
}


- (void) setEccentricity:(float)eccentricity
{
	_eccentricity = OOClamp_0_1_f(eccentricity);
	[self recalculateTransform];
}


- (float) levelOfDetail
{
	return (float)_lod / LOD_GRANULARITY;
}


- (void) setLevelOfDetail:(float)lod
{
	if (lod < 0.0f)  _lod = 0;
	else  _lod = roundf(lod * LOD_GRANULARITY);
}


- (void) calculateLevelOfDetailForViewDistance:(float)distance
{
	// FIXME
	[self setLevelOfDetail:1.0f];
}


- (void) renderOpaqueParts
{
	assert(_lod < kOOPlanetDataLevels);
	
	BOOL shaders = NO;//[UNIVERSE shaderEffectsLevel] > SHADERS_OFF;
	
	const OOPlanetDataLevel *data = &kPlanetData[_lod];
	OO_ENTER_OPENGL();
	
	OOGL(glPushAttrib(GL_ENABLE_BIT));
	OOGL(glShadeModel(GL_SMOOTH));
	
	if (_isAtmosphere)
	{
		OOGL(glEnable(GL_BLEND));
	}
	else
	{
		OOGL(glDisable(GL_BLEND));
	}
	
	[_material apply];
	
	// Scale the ball.
	glPushMatrix();
	GLMultOOMatrix(_transform);
	
	OOGL(glEnable(GL_LIGHTING));
	OOGL(glEnable(GL_TEXTURE_2D));
	
	OOGL(glDisableClientState(GL_COLOR_ARRAY));
	OOGL(glDisableClientState(GL_INDEX_ARRAY));
	OOGL(glDisableClientState(GL_EDGE_FLAG_ARRAY));
	
	OOGL(glEnableClientState(GL_VERTEX_ARRAY));
	OOGL(glEnableClientState(GL_TEXTURE_COORD_ARRAY));
	
	OOGL(glVertexPointer(3, GL_FLOAT, 0, kOOPlanetVertices));
	OOGL(glTexCoordPointer(2, GL_FLOAT, 0, kOOPlanetTexCoords));
	
	if (!shaders)
	{
		// FIXME: instead of GL_RESCALE_NORMAL, consider copying and transforming the vertex array for each planet.
		glEnable(GL_RESCALE_NORMAL);
		OOGL(glEnableClientState(GL_NORMAL_ARRAY));
		OOGL(glNormalPointer(GL_FLOAT, 0, kOOPlanetVertices));
		
	}
	
	OOGL(glDrawElements(GL_TRIANGLES, data->faceCount * 3, data->type, data->indices));
	
	glPopMatrix();
#ifndef NDEBUG
	if (gDebugFlags & DEBUG_DRAW_NORMALS)  [self debugDrawNormals];
#endif
	
	[OOMaterial applyNone];
	OOGL(glPopAttrib());
}


- (void) renderTranslucentParts
{
	[self renderOpaqueParts];
}


- (BOOL) hasOpaqueParts
{
	return !_isAtmosphere;
}


- (BOOL) hasTranslucentParts
{
	return _isAtmosphere;
}


- (GLfloat) collisionRadius
{
	return _radius;
}


- (GLfloat) maxDrawDistance
{
	// FIXME
	return INFINITY;
}


- (BoundingBox) boundingBox
{
	// FIXME: take eccentricity into account for y.
	return (BoundingBox){{ -_radius, -_radius, -_radius }, { _radius, _radius, _radius }};
}


- (void) setBindingTarget:(id<OOWeakReferenceSupport>)target
{
	[_material setBindingTarget:target];
}


- (void) dumpSelfState
{
	[super dumpSelfState];
	OOLog(@"dumpState.planetDrawable", @"radius: %g", [self radius]);
	OOLog(@"dumpState.planetDrawable", @"eccentricity: %g", [self eccentricity]);
	OOLog(@"dumpState.planetDrawable", @"LOD: %g", [self levelOfDetail]);
}


- (void) recalculateTransform
{
	// FIXME: teh eccentricities
	_transform = OOMatrixForScaleUniform(_radius);
}


#ifndef NDEBUG

- (void) debugDrawNormals
{
	OODebugWFState		state;
	
	OO_ENTER_OPENGL();
	
	state = OODebugBeginWireframe(NO);
	
	const OOPlanetDataLevel *data = &kPlanetData[_lod];
	unsigned i;
	
	OOGLBEGIN(GL_LINES);
	for (i = 0; i < data->vertexCount; i++)
	{
		/*	Fun sphere facts: the normalized coordinates of a point on a sphere at the origin
			is equal to the object-space normal of the surface at that point.
			Furthermore, we can construct the binormal (a vector pointing westward along the
			surface) as the cross product of the normal with the Y axis. (This produces
			singularities at the pole, but there have to be singularities according to the
			Hairy Ball Theorem.) The tangent (a vector north along the surface) is then the
			inverse of the cross product of the normal and binormal.
			
			(This comment courtesy of the in-development planet shader.)
		*/
		Vector v = make_vector(kOOPlanetVertices[i * 3], kOOPlanetVertices[i * 3 + 1], kOOPlanetVertices[i * 3 + 2]);
		Vector n = v;
		v = OOVectorMultiplyMatrix(v, _transform);
		
		glColor3f(0.0f, 1.0f, 1.0f);
		GLVertexOOVector(v);
		GLVertexOOVector(vector_add(v, vector_multiply_scalar(n, _radius * 0.05)));
		
		Vector b = cross_product(n, kBasisYVector);
		Vector t = vector_flip(true_cross_product(n, b));
		
		glColor3f(1.0f, 1.0f, 0.0f);
		GLVertexOOVector(v);
		GLVertexOOVector(vector_add(v, vector_multiply_scalar(t, _radius * 0.03)));
		
		glColor3f(0.0f, 1.0f, 0.0f);
		GLVertexOOVector(v);
		GLVertexOOVector(vector_add(v, vector_multiply_scalar(b, _radius * 0.03)));
	}
	OOGLEND();
	
	OODebugEndWireframe(state);
}

#endif

@end
