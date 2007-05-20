/*

OOMesh.m

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

#import "OOMesh.h"
#import "Universe.h"
#import "TextureStore.h"
#import "Geometry.h"
#import "ResourceManager.h"
#import "Entity.h"		// for NO_DRAW_DISTANCE_FACTOR.
#import "Octree.h"
#import "OOMaterial.h"
#import "OOBasicMaterial.h"
#import "OOCollectionExtractors.h"
#import "OOOpenGLExtensionManager.h"


static NSString * const kOOLogOpenGLExtensionsVAR			= @"rendering.opengl.extensions.var";
static NSString * const kOOLogOpenGLStateDump				= @"rendering.opengl.stateDump";
static NSString * const kOOLogMeshDataNotFound				= @"mesh.load.failed.fileNotFound";
static NSString * const kOOLogMeshTooManyVertices			= @"mesh.load.failed.tooManyVertices";
static NSString * const kOOLogMeshTooManyFaces				= @"mesh.load.failed.tooManyFaces";
static NSString * const kOOLogMeshTooManyMaterials			= @"mesh.load.failed.tooManyMaterials";


#define DEBUG_DRAW_NORMALS		0


@interface OOMesh (Private) <NSMutableCopying>

- (id)initWithName:(NSString *)name
materialDictionary:(NSDictionary *)materialDict
 shadersDictionary:(NSDictionary *)shadersDict
			smooth:(BOOL)smooth
	  shaderMacros:(NSDictionary *)macros
   defaultBindings:(NSDictionary *)defaults
shaderBindingTarget:(id<OOWeakReferenceSupport>)object;

- (void)setUpMaterialsWithMaterialsDictionary:(NSDictionary *)materialDict
							shadersDictionary:(NSDictionary *)shadersDict
								 shaderMacros:(NSDictionary *)macros
							  defaultBindings:(NSDictionary *)defaults
						  shaderBindingTarget:(id<OOWeakReferenceSupport>)target;

- (BOOL) loadData:(NSString *)filename;
- (void) checkNormalsAndAdjustWinding;
- (void) calculateVertexNormals;

- (NSDictionary*) modelData;
- (BOOL) setModelFromModelData:(NSDictionary*) dict;

- (Vector) normalForVertex:(int)v_index inSmoothGroup:(OOMeshSmoothGroup)smoothGroup;

- (void)regenerateDisplayList;

- (void) setUpVertexArrays;

- (void) calculateBoundingVolumes;

- (void)rescaleByX:(GLfloat)scaleX y:(GLfloat)scaleY z:(GLfloat)scaleZ;

#if DEBUG_DRAW_NORMALS
- (void)debugDrawNormals;
#endif

@end


@interface OOCacheManager (OOMesh)

+ (NSDictionary *)meshDataForName:(NSString *)inShipName;
+ (void)setMeshData:(NSDictionary *)inData forName:(NSString *)inShipName;

@end


@implementation OOMesh

+ (id)meshWithName:(NSString *)name
materialDictionary:(NSDictionary *)materialDict
 shadersDictionary:(NSDictionary *)shadersDict
			smooth:(BOOL)smooth
	  shaderMacros:(NSDictionary *)macros
   defaultBindings:(NSDictionary *)defaults
shaderBindingTarget:(id<OOWeakReferenceSupport>)object
{
	return [[[self alloc] initWithName:name
					materialDictionary:materialDict
					 shadersDictionary:shadersDict
								smooth:smooth
						  shaderMacros:macros
					   defaultBindings:defaults
				   shaderBindingTarget:object] autorelease];
}


- (id)init
{
    self = [super init];
	if (self == nil)  return nil;
	
    baseFile = @"No Model";
	
	return self;
}


- (void) dealloc
{
	unsigned				i;
	
	[baseFile release];
	[octree autorelease];
	
	[self regenerateDisplayList];
	
	for (i = 0; i != kOOMeshMaxMaterials; ++i)
	{
		[materials[i] release];
		[materialKeys[i] release];
	}
	
	[super dealloc];
}


- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p>{\"%@\", %u vertices, %u faces, radius: %g m smooth: %s}", [self class], self, [self modelName], [self vertexCount], [self faceCount], [self collisionRadius], isSmoothShaded ? "YES" : "NO"];
}


- (id)copyWithZone:(NSZone *)zone
{
	if (zone == [self zone])  return [self retain];	// OK because we're immutable seen from the outside
	else  return [self mutableCopyWithZone:zone];
}


- (NSString *) modelName
{
	return baseFile;
}


- (size_t)vertexCount
{
	return vertexCount;
}


- (size_t)faceCount
{
	return faceCount;
}


- (void)renderOpaqueParts
{
	if (EXPECT_NOT(baseFile == nil))
	{
		OOLog(kOOLogFileNotLoaded, @"***** ERROR no baseFile for entity %@", self);
		return;
	}
	
    int			ti;
	
	glPushAttrib(GL_ENABLE_BIT);
	
	if (isSmoothShaded)  glShadeModel(GL_SMOOTH);
	else  glShadeModel(GL_FLAT);
	
	glDisableClientState(GL_COLOR_ARRAY);
	glDisableClientState(GL_INDEX_ARRAY);
	glDisableClientState(GL_EDGE_FLAG_ARRAY);
	
	glEnableClientState(GL_VERTEX_ARRAY);
	glEnableClientState(GL_NORMAL_ARRAY);
	glEnableClientState(GL_TEXTURE_COORD_ARRAY);
	
	glVertexPointer(3, GL_FLOAT, 0, entityData.vertex_array);
	glNormalPointer(GL_FLOAT, 0, entityData.normal_array);
	glTexCoordPointer(2, GL_FLOAT, 0, entityData.texture_uv_array);
	
	glDisable(GL_BLEND);
	glEnable(GL_TEXTURE_2D);
	
	NS_DURING
		if (!listsReady)
		{
			displayList0 = glGenLists(materialCount);
			
			// Ensure all textures are loaded
			for (ti = 0; ti < materialCount; ti++)
			{
				[materials[ti] ensureFinishedLoading];
			}
		}
		
		for (ti = 0; ti < materialCount; ti++)
		{
			[materials[ti] apply];
			if (listsReady)
			{
				glCallList(displayList0 + ti);
			}
			else
			{
				glNewList(displayList0 + ti, GL_COMPILE_AND_EXECUTE);
				glDrawArrays(GL_TRIANGLES, triangle_range[ti].location, triangle_range[ti].length);
				glEndList();
			}
		}
		
		listsReady = YES;
		brokenInRender = NO;
	NS_HANDLER
		if (!brokenInRender)
		{
			OOLog(kOOLogException, @"***** %s for %@ encountered exception: %@ : %@ *****", __FUNCTION__, self, [localException name], [localException reason]);
			brokenInRender = YES;
		}
		if ([[localException name] hasPrefix:@"Oolite"])  [UNIVERSE handleOoliteException:localException];	// handle these ourself
		else  [localException raise];	// pass these on
	NS_ENDHANDLER
	
#if DEBUG_DRAW_NORMALS
	[self debugDrawNormals];
#endif
	
	[OOMaterial applyNone];
	CheckOpenGLErrors([NSString stringWithFormat:@"OOMesh after drawing %@", self]);
	
	glPopAttrib();
}


- (BOOL)hasOpaqueParts
{
	return YES;
}

- (GLfloat)collisionRadius
{
	return collisionRadius;
}


- (GLfloat)maxDrawDistance
{
	return maxDrawDistance;
}


- (Geometry *)geometry
{
	Geometry *result = [(Geometry *)[Geometry alloc] initWithCapacity:faceCount];
	int i;
	for (i = 0; i < faceCount; i++)
	{
		Triangle tri;
		tri.v[0] = vertices[faces[i].vertex[0]];
		tri.v[1] = vertices[faces[i].vertex[1]];
		tri.v[2] = vertices[faces[i].vertex[2]];
		[result addTriangle:tri];
	}
	return [result autorelease];
}


- (Octree *)octree
{
	if (octree == nil)
	{
		octree = [OOCacheManager octreeForModel:baseFile];
		if (octree == nil)
		{
			octree = [[self geometry] findOctreeToDepth:OCTREE_MAX_DEPTH];
			[OOCacheManager setOctree:octree forModel:baseFile];
		}
		[octree retain];
	}
	
	return octree;
}


- (BoundingBox)findSubentityBoundingBoxWithPosition:(Vector)position rotMatrix:(gl_matrix)rotMatrix
{
	// HACK! Should work out what the various bounding box things do and make it neat and consistant.
	BoundingBox result;
	Vector  v = vertices[0];
	mult_vector_gl_matrix(&v, rotMatrix);
	v.x += position.x;	v.y += position.y;	v.z += position.z;
	bounding_box_reset_to_vector(&result,v);
	int i;
    for (i = 1; i < vertexCount; i++)
    {
		v = vertices[i];
		mult_vector_gl_matrix(&v, rotMatrix);
		v.x += position.x;	v.y += position.y;	v.z += position.z;
		bounding_box_add_vector(&result,v);
    }

	return result;
}


- (OOMesh *)meshRescaledBy:(GLfloat)scaleFactor
{
	return [self meshRescaledByX:scaleFactor y:scaleFactor z:scaleFactor];
}


- (OOMesh *)meshRescaledByX:(GLfloat)scaleX y:(GLfloat)scaleY z:(GLfloat)scaleZ
{
	id					result = nil;
		
	result = [self mutableCopy];
	[result rescaleByX:scaleX y:scaleY z:scaleZ];
	return [result autorelease];
}


- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target
{
	unsigned				i;
	
	for (i = 0; i != kOOMeshMaxMaterials; ++i)
	{
		[materials[i] setBindingTarget:target];
	}
}


- (void)dumpSelfState
{
	NSMutableArray		*flags = nil;
	NSString			*flagsString = nil;
	
	[super dumpSelfState];
	
	if (baseFile != nil)  OOLog(@"dumpState.mesh", @"Model file: %@", baseFile);
	OOLog(@"dumpState.mesh", @"Vertex count: %u, face count: %u", vertexCount, faceCount);
	
	flags = [NSMutableArray array];
	#define ADD_FLAG_IF_SET(x)		if (x) { [flags addObject:@#x]; }
	ADD_FLAG_IF_SET(isSmoothShaded);
	flagsString = [flags count] ? [flags componentsJoinedByString:@", "] : @"none";
	OOLog(@"dumpState.mesh", @"Flags: %@", flagsString);
}

@end


@implementation OOMesh (Private)

- (id)initWithName:(NSString *)name
materialDictionary:(NSDictionary *)materialDict
 shadersDictionary:(NSDictionary *)shadersDict
			smooth:(BOOL)smooth
	  shaderMacros:(NSDictionary *)macros
   defaultBindings:(NSDictionary *)defaults
shaderBindingTarget:(id<OOWeakReferenceSupport>)target
{
	self = [super init];
	if (self == nil)  return nil;
	
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	isSmoothShaded = smooth != NO;
	
	if ([self loadData:name])
	{
		[self checkNormalsAndAdjustWinding];
		[self calculateBoundingVolumes];
		baseFile = [name copy];
		[self setUpMaterialsWithMaterialsDictionary:materialDict shadersDictionary:shadersDict shaderMacros:macros defaultBindings:defaults shaderBindingTarget:target];
	}
	else
	{
		[self release];
		self = nil;
	}
	
	[pool release];
	return self;
}


- (void)setUpMaterialsWithMaterialsDictionary:(NSDictionary *)materialDict
							shadersDictionary:(NSDictionary *)shadersDict
								 shaderMacros:(NSDictionary *)macros
							  defaultBindings:(NSDictionary *)defaults
						  shaderBindingTarget:(id<OOWeakReferenceSupport>)target
{
	OOMeshMaterialCount		i;
	OOMaterial				*material = nil;
	static OOBasicMaterial	*placeholderMaterial = nil;
	NSDictionary			*materialDefaults = nil;
	
	if (materialCount != 0)
	{
		for (i = 0; i != materialCount; ++i)
		{
			material = [OOMaterial materialWithName:materialKeys[i]
								 materialDictionary:materialDict
								  shadersDictionary:shadersDict
											 macros:macros
									defaultBindings:(NSDictionary *)defaults
									  bindingTarget:target];
			materials[i] = [material retain];
		}
	}
	else
	{
		if (placeholderMaterial == nil)
		{
			materialDefaults = [ResourceManager dictionaryFromFilesNamed:@"material-defaults.plist" inFolder:@"Config" andMerge:YES];
			placeholderMaterial = [[OOBasicMaterial alloc] initWithName:@"/placeholder/" configuration:[materialDefaults dictionaryForKey:@"no-textures-material"]];
		}
		material = [placeholderMaterial retain];
	}
}


- (id)mutableCopyWithZone:(NSZone *)zone
{
	OOMesh				*result = nil;
	OOMeshMaterialCount	i;
	
	result = (OOMesh *)NSCopyObject(self, 0, zone);
	
	if (result != nil)
	{
		[result->baseFile retain];
		[result->octree retain];
		
		for (i = 0; i != kOOMeshMaxMaterials; ++i)
		{
			[result->materialKeys[i] retain];
			[result->materials[i] retain];
		}
		
		// Reset unsharable GL state
		result->listsReady = NO;
	}
	
	return result;
}


- (void) reloadTextures
{
	unsigned				i;
	
	for (i = 0; i != kOOMeshMaxMaterials; ++i)
	{
		[materials[i] reloadTextures];
	}
	
	// Force the display list to be regenerated next time a frame is drawn.
	[self regenerateDisplayList];
}


- (void) regenerateDisplayList
{
	if (listsReady)
	{
		glDeleteLists(displayList0, materialCount);
		listsReady = NO;
	}
}


- (NSDictionary *)modelData
{
	NSNumber			*vertCnt = nil,
						*faceCnt = nil;
	NSData				*vertData = nil,
						*normData = nil,
						*faceData = nil;
	NSArray				*mtlKeys = nil;
	NSNumber			*smooth = nil;
	
	vertCnt = [NSNumber numberWithUnsignedInt:vertexCount];
	faceCnt = [NSNumber numberWithUnsignedInt:faceCount];
	
	vertData = [NSData dataWithBytesNoCopy:vertices length:sizeof *vertices * vertexCount freeWhenDone:NO];
	normData = [NSData dataWithBytesNoCopy:normals length:sizeof *normals * vertexCount freeWhenDone:NO];
	faceData = [NSData dataWithBytesNoCopy:faces length:sizeof *faces * faceCount freeWhenDone:NO];
	
	mtlKeys = [NSArray arrayWithObjects:materialKeys count:materialCount];
	smooth = [NSNumber numberWithBool:isSmoothShaded];
	
	if (vertCnt == nil || faceCnt == nil || vertData == nil || normData == nil || faceData == nil || mtlKeys == nil || smooth == nil)  return nil;
	
	return [NSDictionary dictionaryWithObjectsAndKeys:
						vertCnt, @"vertex count",
						vertData, @"vertex data",
						normData, @"normal data",
						faceCnt, @"face count",
						faceData, @"face data",
						mtlKeys, @"material keys",
						smooth, @"smooth",
						nil];
}


- (BOOL)setModelFromModelData:(NSDictionary *)dict
{
	NSNumber			*vertCnt = nil,
						*faceCnt = nil;
	NSData				*vertData = nil,
						*normData = nil,
						*faceData = nil;
	NSArray				*mtlKeys = nil;
	NSNumber			*smooth = nil;
	id					key = nil;
	unsigned			i;
	
	if (dict == nil)  return NO;
	
	vertCnt = [dict objectForKey:@"vertex count"];
	faceCnt = [dict objectForKey:@"face count"];
	
	vertData = [dict dataForKey:@"vertex data"];
	normData = [dict dataForKey:@"normal data"];
	faceData = [dict dataForKey:@"face data"];
	
	mtlKeys = [dict arrayForKey:@"material keys"];
	smooth = [dict objectForKey:@"smooth"];
	
	if (vertCnt == nil || faceCnt == nil || vertData == nil || normData == nil || faceData == nil || mtlKeys == nil || smooth == nil)  return NO;
	if (![vertCnt respondsToSelector:@selector(unsignedIntValue)])  return NO;
	if (![faceCnt respondsToSelector:@selector(unsignedIntValue)])  return NO;
	if (![smooth respondsToSelector:@selector(boolValue)])  return NO;
	
	vertexCount = [vertCnt unsignedIntValue];
	faceCount = [faceCnt unsignedIntValue];
	
	if ([vertData length] != sizeof *vertices * vertexCount || [vertData length] > sizeof(vertices))  return NO;
	if ([normData length] != sizeof *normals * vertexCount || [normData length] > sizeof(normals))  return NO;
	if ([faceData length] != sizeof *faces * faceCount || [faceData length] > sizeof(faces))  return NO;
	
	memcpy(vertices, [vertData bytes], [vertData length]);
	memcpy(normals, [normData bytes], [normData length]);
	memcpy(faces, [faceData bytes], [faceData length]);
	
	materialCount = [mtlKeys count];
	for (i = 0; i != materialCount; ++i)
	{
		key = [mtlKeys stringAtIndex:i];
		if (key != nil)  materialKeys[i] = [key retain];
		else  return NO;
	}
	
	isSmoothShaded = [smooth boolValue] != NO;
	
	return YES;
}


- (BOOL)loadData:(NSString *)filename
{
    NSScanner			*scanner;
	NSDictionary		*cacheData = nil;
    NSString			*data = nil;
    NSMutableArray		*lines;
    BOOL				failFlag = NO;
    NSString			*failString = @"***** ";
    int					i, j;
	NSMutableDictionary	*texFileName2Idx = nil;
	
	BOOL using_preloaded = NO;
	
	cacheData = [OOCacheManager meshDataForName:filename];
	if (cacheData != nil)
	{
		if ([self setModelFromModelData:cacheData]) using_preloaded = YES;
	}
	
	if (!using_preloaded)
	{
		texFileName2Idx = [NSMutableDictionary dictionary];
		
		data = [ResourceManager stringFromFilesNamed:filename inFolder:@"Models"];
		if (data == nil)
		{
			// Model not found
			OOLog(kOOLogMeshDataNotFound, @"ERROR - could not find %@", filename);
			return NO;
		}

		// strip out comments and commas between values
		//
		lines = [NSMutableArray arrayWithArray:[data componentsSeparatedByString:@"\n"]];
		for (i = 0; i < [ lines count]; i++)
		{
			NSString *line = [lines objectAtIndex:i];
			NSArray *parts;
			//
			// comments
			//
			parts = [line componentsSeparatedByString:@"#"];
			line = [parts objectAtIndex:0];
			parts = [line componentsSeparatedByString:@"//"];
			line = [parts objectAtIndex:0];
			//
			// commas
			//
			line = [[line componentsSeparatedByString:@","] componentsJoinedByString:@" "];
			//
			[lines replaceObjectAtIndex:i withObject:line];
		}
		data = [lines componentsJoinedByString:@"\n"];

		scanner = [NSScanner scannerWithString:data];

		// get number of vertices
		//
		[scanner setScanLocation:0];	//reset
		if ([scanner scanString:@"NVERTS" intoString:NULL])
		{
			int n_v;
			if ([scanner scanInt:&n_v])
				vertexCount = n_v;
			else
			{
				failFlag = YES;
				failString = [NSString stringWithFormat:@"%@Failed to read value of NVERTS\n",failString];
			}
		}
		else
		{
			failFlag = YES;
			failString = [NSString stringWithFormat:@"%@Failed to read NVERTS\n",failString];
		}

		if (vertexCount > kOOMeshMaxVertices)
		{
			OOLog(kOOLogMeshTooManyVertices, @"ERROR - model %@ has too many vertices (model has %d, maximum is %d)", filename, vertexCount, kOOMeshMaxVertices);
			return NO;
		}

		// get number of faces
		//
		//[scanner setScanLocation:0];	//reset
		if ([scanner scanString:@"NFACES" intoString:NULL])
		{
			int n_f;
			if ([scanner scanInt:&n_f])
				faceCount = n_f;
			else
			{
				failFlag = YES;
				failString = [NSString stringWithFormat:@"%@Failed to read value of NFACES\n",failString];
			}
		}
		else
		{
			failFlag = YES;
			failString = [NSString stringWithFormat:@"%@Failed to read NFACES\n",failString];
		}

		if (faceCount > kOOMeshMaxFaces)
		{
			OOLog(kOOLogMeshTooManyFaces, @"ERROR - model %@ has too many faces (model has %d, maximum is %d)", filename, faceCount, kOOMeshMaxFaces);
			return NO;
		}

		// get vertex data
		//
		//[scanner setScanLocation:0];	//reset
		if ([scanner scanString:@"VERTEX" intoString:NULL])
		{
			for (j = 0; j < vertexCount; j++)
			{
				float x, y, z;
				if (!failFlag)
				{
					if (![scanner scanFloat:&x])
						failFlag = YES;
					if (![scanner scanFloat:&y])
						failFlag = YES;
					if (![scanner scanFloat:&z])
						failFlag = YES;
					if (!failFlag)
					{
						vertices[j].x = x;	vertices[j].y = y;	vertices[j].z = z;
					}
					else
					{
						failString = [NSString stringWithFormat:@"%@Failed to read a value for vertex[%d] in VERTEX\n", failString, j];
					}
				}
			}
		}
		else
		{
			failFlag = YES;
			failString = [NSString stringWithFormat:@"%@Failed to find VERTEX data\n",failString];
		}

		// get face data
		//
		if ([scanner scanString:@"FACES" intoString:NULL])
		{
			for (j = 0; j < faceCount; j++)
			{
				int r, g, b;
				float nx, ny, nz;
				int n_v;
				if (!failFlag)
				{
					// colors
					//
					if (![scanner scanInt:&r])
						failFlag = YES;
					if (![scanner scanInt:&g])
						failFlag = YES;
					if (![scanner scanInt:&b])
						failFlag = YES;
					if (!failFlag)
					{
						faces[j].smoothGroup = r;
					}
					else
					{
						failString = [NSString stringWithFormat:@"%@Failed to read a color for face[%d] in FACES\n", failString, j];
					}

					// normal
					//
					if (![scanner scanFloat:&nx])
						failFlag = YES;
					if (![scanner scanFloat:&ny])
						failFlag = YES;
					if (![scanner scanFloat:&nz])
						failFlag = YES;
					if (!failFlag)
					{
						faces[j].normal.x = nx;
						faces[j].normal.y = ny;
						faces[j].normal.z = nz;
					}
					else
					{
						failString = [NSString stringWithFormat:@"%@Failed to read a normal for face[%d] in FACES\n", failString, j];
					}

					// vertices
					//
					if ([scanner scanInt:&n_v])
					{
						faces[j].n_verts = n_v;
					}
					else
					{
						failFlag = YES;
						failString = [NSString stringWithFormat:@"%@Failed to read number of vertices for face[%d] in FACES\n", failString, j];
					}
					//
					if (!failFlag)
					{
						int vi;
						for (i = 0; i < n_v; i++)
						{
							if ([scanner scanInt:&vi])
							{
								faces[j].vertex[i] = vi;
							}
							else
							{
								failFlag = YES;
								failString = [NSString stringWithFormat:@"%@Failed to read vertex[%d] for face[%d] in FACES\n", failString, i, j];
							}
						}
					}
				}
			}
		}
		else
		{
			failFlag = YES;
			failString = [NSString stringWithFormat:@"%@Failed to find FACES data\n",failString];
		}

		// get textures data
		//
		if ([scanner scanString:@"TEXTURES" intoString:NULL])
		{
			for (j = 0; j < faceCount; j++)
			{
				NSString	*materialKey;
				float	max_x, max_y;
				float	s, t;
				if (!failFlag)
				{
					// materialKey
					//
					[scanner scanCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:NULL];
					if (![scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&materialKey])
					{
						failFlag = YES;
						failString = [NSString stringWithFormat:@"%@Failed to read texture filename for face[%d] in TEXTURES\n", failString, j];
					}
					else
					{
						NSNumber *index = [texFileName2Idx objectForKey:materialKey];
						if (index != nil)
						{
							faces[j].materialIndex = [index unsignedIntValue];
						}
						else
						{
							if (materialCount == kOOMeshMaxMaterials)
							{
								OOLog(kOOLogMeshTooManyMaterials, @"ERROR - model %@ has too many materials (maximum is %d)", filename, kOOMeshMaxMaterials);
								return NO;
							}
							faces[j].materialIndex = materialCount;
							materialKeys[materialCount] = [materialKey retain];
							index = [NSNumber numberWithUnsignedInt:materialCount];
							[texFileName2Idx setObject:index forKey:materialKey];
							++materialCount;
						}
					}

					// texture size
					//
				   if (!failFlag)
					{
						if (![scanner scanFloat:&max_x])
							failFlag = YES;
						if (![scanner scanFloat:&max_y])
							failFlag = YES;
						if (failFlag)
							failString = [NSString stringWithFormat:@"%@Failed to read texture size for max_x and max_y in face[%d] in TEXTURES\n", failString, j];
					}

					// vertices
					//
					if (!failFlag)
					{
						for (i = 0; i < faces[j].n_verts; i++)
						{
							if (![scanner scanFloat:&s])
								failFlag = YES;
							if (![scanner scanFloat:&t])
								failFlag = YES;
							if (!failFlag)
							{
								faces[j].s[i] = s / max_x;    faces[j].t[i] = t / max_y;
							}
							else
								failString = [NSString stringWithFormat:@"%@Failed to read s t coordinates for vertex[%d] in face[%d] in TEXTURES\n", failString, i, j];
						}
					}
				}
			}
		}
		else
		{
			failFlag = YES;
			failString = [NSString stringWithFormat:@"%@Failed to find TEXTURES data (will use placeholder material)\n",failString];
			materialCount = 1;
		}
		
		[self checkNormalsAndAdjustWinding];
		
		if (failFlag)
		{
			OOLog(@"mesh.error", [NSString stringWithFormat:@"%@ ..... from %@ %@", failString, filename, (using_preloaded)? @"(from preloaded data)" :@"(from file)"]);
		}

		// check for smooth shading and recalculate normals
		if (isSmoothShaded)
			[self calculateVertexNormals];
		
		// save the resulting data for possible reuse
		[OOCacheManager setMeshData:[self modelData] forName:filename];
	}
	
	[self calculateBoundingVolumes];
	
	// set up vertex arrays for drawing
	[self setUpVertexArrays];
	
	return YES;
}


// FIXME: this isn't working, we're getting smoothed models with inside-out winding. --Ahruman
- (void) checkNormalsAndAdjustWinding
{
    Vector calculatedNormal;
    int i, j;
    for (i = 0; i < faceCount; i++)
    {
        Vector v0, v1, v2, norm;
        v0 = vertices[faces[i].vertex[0]];
        v1 = vertices[faces[i].vertex[1]];
        v2 = vertices[faces[i].vertex[2]];
        norm = faces[i].normal;
		calculatedNormal = normal_to_surface (v2, v1, v0);
        if ((norm.x == 0.0)&&(norm.y == 0.0)&&(norm.z == 0.0))
		{
			faces[i].normal = normal_to_surface (v0, v1, v2);
			norm = normal_to_surface (v0, v1, v2);
		}
        if ((norm.x*calculatedNormal.x < 0)||(norm.y*calculatedNormal.y < 0)||(norm.z*calculatedNormal.z < 0))
        {
            // normal lies in the WRONG direction!
            // reverse the winding
            int v[faces[i].n_verts];
            GLfloat s[faces[i].n_verts];
            GLfloat t[faces[i].n_verts];

            for (j = 0; j < faces[i].n_verts; j++)
            {
            	v[j] = faces[i].vertex[faces[i].n_verts - 1 - j];
            	s[j] = faces[i].s[faces[i].n_verts - 1 - j];
            	t[j] = faces[i].t[faces[i].n_verts - 1 - j];
            }
            for (j = 0; j < faces[i].n_verts; j++)
            {
            	faces[i].vertex[j] = v[j];
                faces[i].s[j] = s[j];
                faces[i].t[j] = t[j];
            }
        }
    }
}

- (void) calculateVertexNormals
{
	int i,j;
	float	triangle_area[faceCount];
	for (i = 0 ; i < faceCount; i++)
	{
		// calculate areas using Herons formula
		// in the form Area = sqrt(2*(a2*b2+b2*c2+c2*a2)-(a4+b4+c4))/4
		float	a2 = distance2( vertices[faces[i].vertex[0]], vertices[faces[i].vertex[1]]);
		float	b2 = distance2( vertices[faces[i].vertex[1]], vertices[faces[i].vertex[2]]);
		float	c2 = distance2( vertices[faces[i].vertex[2]], vertices[faces[i].vertex[0]]);
		triangle_area[i] = sqrt( 2.0 * (a2 * b2 + b2 * c2 + c2 * a2) - 0.25 * (a2 * a2 + b2 * b2 +c2 * c2));
	}
	for (i = 0; i < vertexCount; i++)
	{
		Vector normal_sum = kZeroVector;
		for (j = 0; j < faceCount; j++)
		{
			BOOL is_shared = ((faces[j].vertex[0] == i)||(faces[j].vertex[1] == i)||(faces[j].vertex[2] == i));
			if (is_shared)
			{
				float t = triangle_area[j]; // weight sum by area
				normal_sum.x += t * faces[j].normal.x;	normal_sum.y += t * faces[j].normal.y;	normal_sum.z += t * faces[j].normal.z;
			}
		}
		if (normal_sum.x||normal_sum.y||normal_sum.z)
			normal_sum = unit_vector(&normal_sum);
		else
			normal_sum.z = 1.0;
		normals[i] = normal_sum;
	}
}

- (Vector) normalForVertex:(int) v_index inSmoothGroup:(OOMeshSmoothGroup)smoothGroup
{
	int j;
	Vector normal_sum = kZeroVector;
	for (j = 0; j < faceCount; j++)
	{
		if (faces[j].smoothGroup == smoothGroup)
		{
			if ((faces[j].vertex[0] == v_index)||(faces[j].vertex[1] == v_index)||(faces[j].vertex[2] == v_index))
			{
				float	a2 = distance2( vertices[faces[j].vertex[0]], vertices[faces[j].vertex[1]]);
				float	b2 = distance2( vertices[faces[j].vertex[1]], vertices[faces[j].vertex[2]]);
				float	c2 = distance2( vertices[faces[j].vertex[2]], vertices[faces[j].vertex[0]]);
				float	t = sqrt( 2.0 * (a2 * b2 + b2 * c2 + c2 * a2) - 0.25 * (a2 * a2 + b2 * b2 +c2 * c2));
				normal_sum.x += t * faces[j].normal.x;	normal_sum.y += t * faces[j].normal.y;	normal_sum.z += t * faces[j].normal.z;
			}
		}
	}
	if (normal_sum.x||normal_sum.y||normal_sum.z)
		normal_sum = unit_vector(&normal_sum);
	else
		normal_sum.z = 1.0;
	return normal_sum;
}

- (void) setUpVertexArrays
{
	int fi, vi, mi;

	// if isSmoothShaded find any vertices that are between faces of different
	// smoothing groups and mark them as being on an edge and therefore NOT
	// smooth shaded
	BOOL is_edge_vertex[vertexCount];
	GLfloat smoothGroup[vertexCount];
	for (vi = 0; vi < vertexCount; vi++)
	{
		is_edge_vertex[vi] = NO;
		smoothGroup[vi] = -1;
	}
	if (isSmoothShaded)
	{
		for (fi = 0; fi < faceCount; fi++)
		{
			GLfloat rv = faces[fi].smoothGroup;
			int i;
			for (i = 0; i < 3; i++)
			{
				vi = faces[fi].vertex[i];
				if (smoothGroup[vi] < 0.0)	// unassigned
					smoothGroup[vi] = rv;
				else if (smoothGroup[vi] != rv)	// a different colour
					is_edge_vertex[vi] = YES;
			}
		}
	}


	// base model, flat or smooth shaded, all triangles
	int tri_index = 0;
	int uv_index = 0;
	int vertex_index = 0;
	
	// Iterate over material names
	for (mi = 0; mi != materialCount; ++mi)
	{
		triangle_range[mi].location = tri_index;
		
		for (fi = 0; fi < faceCount; fi++)
		{
			Vector normal;
			
			if (faces[fi].materialIndex == mi)
			{
				for (vi = 0; vi < 3; vi++)
				{
					int v = faces[fi].vertex[vi];
					if (isSmoothShaded)
					{
						if (is_edge_vertex[v])
							normal = [self normalForVertex:v inSmoothGroup:faces[fi].smoothGroup];
						else
							normal = normals[v];
					}
					else
					{
						normal = faces[fi].normal;
					}
					
					entityData.index_array[tri_index++] = vertex_index;
					entityData.normal_array[vertex_index] = normal;
					entityData.vertex_array[vertex_index++] = vertices[v];
					entityData.texture_uv_array[uv_index++] = faces[fi].s[vi];
					entityData.texture_uv_array[uv_index++] = faces[fi].t[vi];
				}
			}
		}
		triangle_range[mi].length = tri_index - triangle_range[mi].location;
	}
	
	entityData.n_triangles = tri_index;	// total number of triangle vertices
}


- (void) calculateBoundingVolumes
{
    int i;
	double d_squared, length_longest_axis, length_shortest_axis;
	GLfloat result;
	
	result = 0.0f;
	if (vertexCount)  bounding_box_reset_to_vector(&boundingBox,vertices[0]);
	else  bounding_box_reset(&boundingBox);

    for (i = 0; i < vertexCount; i++)
    {
        d_squared = vertices[i].x*vertices[i].x + vertices[i].y*vertices[i].y + vertices[i].z*vertices[i].z;
        if (d_squared > result)
			result = d_squared;
		bounding_box_add_vector(&boundingBox,vertices[i]);
    }

	length_longest_axis = boundingBox.max.x - boundingBox.min.x;
	if (boundingBox.max.y - boundingBox.min.y > length_longest_axis)
		length_longest_axis = boundingBox.max.y - boundingBox.min.y;
	if (boundingBox.max.z - boundingBox.min.z > length_longest_axis)
		length_longest_axis = boundingBox.max.z - boundingBox.min.z;

	length_shortest_axis = boundingBox.max.x - boundingBox.min.x;
	if (boundingBox.max.y - boundingBox.min.y < length_shortest_axis)
		length_shortest_axis = boundingBox.max.y - boundingBox.min.y;
	if (boundingBox.max.z - boundingBox.min.z < length_shortest_axis)
		length_shortest_axis = boundingBox.max.z - boundingBox.min.z;

	d_squared = (length_longest_axis + length_shortest_axis) * (length_longest_axis + length_shortest_axis) * 0.25; // square of average length
	maxDrawDistance = d_squared * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR;	// no longer based on the collision radius
	
	collisionRadius = sqrt(result);
}


- (void)rescaleByX:(GLfloat)scaleX y:(GLfloat)scaleY z:(GLfloat)scaleZ
{
	
	OOMeshVertexCount	i;
	BOOL				isotropic;
	Vector				*vertex = NULL, *normal = NULL;
	
	isotropic = (scaleX == scaleY && scaleY == scaleZ);
	
	for (i = 0; i != vertexCount; ++i)
	{
		vertex = &vertices[i];
		
		vertex->x *= scaleX;
		vertex->y *= scaleY;
		vertex->z *= scaleZ;
		
		if (!isotropic)
		{
			normal = &normals[i];
			// For efficiency freaks: let's assume some sort of adaptive branch prediction.
			normal->x *= scaleX;
			normal->y *= scaleY;
			normal->z *= scaleZ;
			*normal = vector_normal(*normal);
		}
	}
	
	[self calculateBoundingVolumes];
	[octree release];
	octree = nil;
}


- (BoundingBox)boundingBox
{
	return boundingBox;
}


- (BoundingBox) findBoundingBoxRelativeToPosition:(Vector)rpos InVectors:(Vector) _i :(Vector) _j :(Vector) _k
{
	Vector pv, rv;
	rv.x = dot_product(_i,rpos);
	rv.y = dot_product(_j,rpos);
	rv.z = dot_product(_k,rpos);
	BoundingBox result;
	bounding_box_reset_to_vector(&result,rv);
	int i;
    for (i = 0; i < vertexCount; i++)
    {
		pv.x = rpos.x + vertices[i].x;
		pv.y = rpos.y + vertices[i].y;
		pv.z = rpos.z + vertices[i].z;
		rv.x = dot_product(_i,pv);
		rv.y = dot_product(_j,pv);
		rv.z = dot_product(_k,pv);
		bounding_box_add_vector(&result,rv);
    }
	
	return result;
}


#if DEBUG_DRAW_NORMALS
- (void)debugDrawNormals
{
	unsigned			i, max = 0;
	Vector				v, n;
	float				length, blend;
	GLfloat				color[3];
	
	// Set up state
	glPushAttrib(GL_ENABLE_BIT);
	glDisable(GL_LIGHTING);
	glDisable(GL_TEXTURE_2D);
	
	// Find largest used triangle index
	for (i = 0; i != 3 * kOOMeshMaxFaces; ++i)
	{
		if (max < entityData.index_array[i])  max = entityData.index_array[i];
	}
	
	// Draw
	glBegin(GL_LINES);
	for (i = 0; i != max; ++i)
	{
		v = entityData.vertex_array[i];
		n = entityData.normal_array[i];
		
		length = magnitude2(n);
		blend = fabsf(length - 1) * 5.0;
		color[0] = MIN(blend, 1.0f);
		color[1] = 1.0f - color[0];
		color[2] = color[1];
		glColor3fv(color);
		
		glVertex3f(v.x, v.y, v.z);
		scale_vector(&n, 5.0f);
		v = vector_add(n, v);
		glVertex3f(v.x, v.y, v.z);
	}
	glEnd();
	
	glPopAttrib();
}
#endif

@end


// log a list of current states
//
// we need to report on the material properties
GLfloat stored_mat_ambient[4];
GLfloat stored_mat_diffuse[4];
GLfloat stored_mat_emission[4];
GLfloat stored_mat_specular[4];
GLfloat stored_mat_shininess[1];
//
GLfloat stored_current_color[4];
//
GLint stored_gl_shade_model[1];
//
GLint stored_gl_texture_env_mode[1];
//
GLint stored_gl_cull_face_mode[1];
//
GLint stored_gl_front_face[1];
//
GLint stored_gl_blend_src[1];
GLint stored_gl_blend_dst[1];
//
GLenum stored_errCode;
//
void LogOpenGLState()
{
	if (!OOLogWillDisplayMessagesInClass(kOOLogOpenGLStateDump)) return;
	
	// we need to report on the material properties
	GLfloat mat_ambient[4];
	GLfloat mat_diffuse[4];
	GLfloat mat_emission[4];
	GLfloat mat_specular[4];
	GLfloat mat_shininess[1];
	//
	GLfloat current_color[4];
	//
	GLint gl_shade_model[1];
	//
	GLint gl_texture_env_mode[1];
	NSString* tex_env_mode_string = nil;
	//
	GLint gl_cull_face_mode[1];
	NSString* cull_face_mode_string = nil;
	//
	GLint gl_front_face[1];
	NSString* front_face_string = nil;
	//
	GLint gl_blend_src[1];
	NSString* blend_src_string = nil;
	GLint gl_blend_dst[1];
	NSString* blend_dst_string = nil;
	//
	GLenum errCode;
	const GLubyte *errString;

	glGetMaterialfv( GL_FRONT, GL_AMBIENT, mat_ambient);
	glGetMaterialfv( GL_FRONT, GL_DIFFUSE, mat_diffuse);
	glGetMaterialfv( GL_FRONT, GL_EMISSION, mat_emission);
	glGetMaterialfv( GL_FRONT, GL_SPECULAR, mat_specular);
	glGetMaterialfv( GL_FRONT, GL_SHININESS, mat_shininess);
	//
	glGetFloatv( GL_CURRENT_COLOR, current_color);
	//
	glGetIntegerv( GL_SHADE_MODEL, gl_shade_model);
	//
	glGetIntegerv( GL_BLEND_SRC, gl_blend_src);
	switch (gl_blend_src[0])
	{
		case GL_ZERO:
			blend_src_string = @"GL_ZERO";
			break;
		case GL_ONE:
			blend_src_string = @"GL_ONE";
			break;
		case GL_DST_COLOR:
			blend_src_string = @"GL_DST_COLOR";
			break;
		case GL_SRC_COLOR:
			blend_src_string = @"GL_SRC_COLOR";
			break;
		case GL_ONE_MINUS_DST_COLOR:
			blend_src_string = @"GL_ONE_MINUS_DST_COLOR";
			break;
		case GL_ONE_MINUS_SRC_COLOR:
			blend_src_string = @"GL_ONE_MINUS_SRC_COLOR";
			break;
		case GL_SRC_ALPHA:
			blend_src_string = @"GL_SRC_ALPHA";
			break;
		case GL_DST_ALPHA:
			blend_src_string = @"GL_DST_ALPHA";
			break;
		case GL_ONE_MINUS_SRC_ALPHA:
			blend_src_string = @"GL_ONE_MINUS_SRC_ALPHA";
			break;
		case GL_ONE_MINUS_DST_ALPHA:
			blend_src_string = @"GL_ONE_MINUS_DST_ALPHA";
			break;
		case GL_SRC_ALPHA_SATURATE:
			blend_src_string = @"GL_SRC_ALPHA_SATURATE";
			break;
		default:
			break;
	}
	//
	glGetIntegerv( GL_BLEND_DST, gl_blend_dst);
	switch (gl_blend_dst[0])
	{
		case GL_ZERO:
			blend_dst_string = @"GL_ZERO";
			break;
		case GL_ONE:
			blend_dst_string = @"GL_ONE";
			break;
		case GL_DST_COLOR:
			blend_dst_string = @"GL_DST_COLOR";
			break;
		case GL_SRC_COLOR:
			blend_dst_string = @"GL_SRC_COLOR";
			break;
		case GL_ONE_MINUS_DST_COLOR:
			blend_dst_string = @"GL_ONE_MINUS_DST_COLOR";
			break;
		case GL_ONE_MINUS_SRC_COLOR:
			blend_dst_string = @"GL_ONE_MINUS_SRC_COLOR";
			break;
		case GL_SRC_ALPHA:
			blend_dst_string = @"GL_SRC_ALPHA";
			break;
		case GL_DST_ALPHA:
			blend_dst_string = @"GL_DST_ALPHA";
			break;
		case GL_ONE_MINUS_SRC_ALPHA:
			blend_dst_string = @"GL_ONE_MINUS_SRC_ALPHA";
			break;
		case GL_ONE_MINUS_DST_ALPHA:
			blend_dst_string = @"GL_ONE_MINUS_DST_ALPHA";
			break;
		case GL_SRC_ALPHA_SATURATE:
			blend_dst_string = @"GL_SRC_ALPHA_SATURATE";
			break;
		default:
			break;
	}
	//
	glGetIntegerv( GL_CULL_FACE_MODE, gl_cull_face_mode);
	switch (gl_cull_face_mode[0])
	{
		case GL_BACK:
			cull_face_mode_string = @"GL_BACK";
			break;
		case GL_FRONT:
			cull_face_mode_string = @"GL_FRONT";
			break;
		default:
			break;
	}
	//
	glGetIntegerv( GL_FRONT_FACE, gl_front_face);
	switch (gl_front_face[0])
	{
		case GL_CCW:
			front_face_string = @"GL_CCW";
			break;
		case GL_CW:
			front_face_string = @"GL_CW";
			break;
		default:
			break;
	}
	//
	glGetTexEnviv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, gl_texture_env_mode);
	switch (gl_texture_env_mode[0])
	{
		case GL_DECAL:
			tex_env_mode_string = @"GL_DECAL";
			break;
		case GL_REPLACE:
			tex_env_mode_string = @"GL_REPLACE";
			break;
		case GL_MODULATE:
			tex_env_mode_string = @"GL_MODULATE";
			break;
		case GL_BLEND:
			tex_env_mode_string = @"GL_BLEND";
			break;
		default:
			break;
	}
	//
	if ((errCode =glGetError()) != GL_NO_ERROR)
	{
		errString = gluErrorString(errCode);
		OOLog(kOOLogOpenGLError, @"OpenGL error: '%s' (%u) in: %@", errString, errCode);
	}

	/*-- MATERIALS --*/
	if ((stored_mat_ambient[0] != mat_ambient[0])||(stored_mat_ambient[1] != mat_ambient[1])||(stored_mat_ambient[2] != mat_ambient[2])||(stored_mat_ambient[3] != mat_ambient[2]))
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_AMBIENT ( %.2ff, %.2ff, %.2ff, %.2ff)",
			mat_ambient[0], mat_ambient[1], mat_ambient[2], mat_ambient[3]);
	if ((stored_mat_diffuse[0] != mat_diffuse[0])||(stored_mat_diffuse[1] != mat_diffuse[1])||(stored_mat_diffuse[2] != mat_diffuse[2])||(stored_mat_diffuse[3] != mat_diffuse[2]))
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_DIFFUSE ( %.2ff, %.2ff, %.2ff, %.2ff)",
			mat_diffuse[0], mat_diffuse[1], mat_diffuse[2], mat_diffuse[3]);
	if ((stored_mat_emission[0] != mat_emission[0])||(stored_mat_emission[1] != mat_emission[1])||(stored_mat_emission[2] != mat_emission[2])||(stored_mat_emission[3] != mat_emission[2]))
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_EMISSION ( %.2ff, %.2ff, %.2ff, %.2ff)",
			mat_emission[0], mat_emission[1], mat_emission[2], mat_emission[3]);
	if ((stored_mat_specular[0] != mat_specular[0])||(stored_mat_specular[1] != mat_specular[1])||(stored_mat_specular[2] != mat_specular[2])||(stored_mat_specular[3] != mat_specular[2]))
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_SPECULAR ( %.2ff, %.2ff, %.2ff, %.2ff)",
			mat_specular[0], mat_specular[1], mat_specular[2], mat_specular[3]);
	if (stored_mat_shininess[0] != mat_shininess[0])
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_SHININESS ( %.2ff)", mat_shininess[0]);
	stored_mat_ambient[0] = mat_ambient[0];	stored_mat_ambient[1] = mat_ambient[1];	stored_mat_ambient[2] = mat_ambient[2];	stored_mat_ambient[3] = mat_ambient[3];
	stored_mat_diffuse[0] = mat_diffuse[0];	stored_mat_diffuse[1] = mat_diffuse[1];	stored_mat_diffuse[2] = mat_diffuse[2];	stored_mat_diffuse[3] = mat_diffuse[3];
	stored_mat_emission[0] = mat_emission[0];	stored_mat_emission[1] = mat_emission[1];	stored_mat_emission[2] = mat_emission[2];	stored_mat_emission[3] = mat_emission[3];
	stored_mat_specular[0] = mat_specular[0];	stored_mat_specular[1] = mat_specular[1];	stored_mat_specular[2] = mat_specular[2];	stored_mat_specular[3] = mat_specular[3];
	stored_mat_shininess[0] = mat_shininess[0];
	/*-- MATERIALS --*/

	//
	/*-- LIGHTS --*/
	if (glIsEnabled(GL_LIGHTING))
	{
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHTING :ENABLED:");
		if (glIsEnabled(GL_LIGHT0))
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT0 :ENABLED:");
		if (glIsEnabled(GL_LIGHT1))
		{
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT1 :ENABLED:");
			GLfloat light_ambient[4];
			GLfloat light_diffuse[4];
			GLfloat light_specular[4];
			glGetLightfv(GL_LIGHT1, GL_AMBIENT, light_ambient);
			glGetLightfv(GL_LIGHT1, GL_DIFFUSE, light_diffuse);
			glGetLightfv(GL_LIGHT1, GL_SPECULAR, light_specular);
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT1 GL_AMBIENT ( %.2ff, %.2ff, %.2ff, %.2ff)",
				light_ambient[0], light_ambient[1], light_ambient[2], light_ambient[3]);
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT1 GL_DIFFUSE ( %.2ff, %.2ff, %.2ff, %.2ff)",
				light_diffuse[0], light_diffuse[1], light_diffuse[2], light_diffuse[3]);
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT1 GL_SPECULAR ( %.2ff, %.2ff, %.2ff, %.2ff)",
				light_specular[0], light_specular[1], light_specular[2], light_specular[3]);
		}
		if (glIsEnabled(GL_LIGHT2))
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT2 :ENABLED:");
		if (glIsEnabled(GL_LIGHT3))
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT3 :ENABLED:");
		if (glIsEnabled(GL_LIGHT4))
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT4 :ENABLED:");
		if (glIsEnabled(GL_LIGHT5))
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT5 :ENABLED:");
		if (glIsEnabled(GL_LIGHT6))
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT6 :ENABLED:");
		if (glIsEnabled(GL_LIGHT7))
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT7 :ENABLED:");
	}
	/*-- LIGHTS --*/

	OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_CURRENT_COLOR ( %.2ff, %.2ff, %.2ff, %.2ff)",
		current_color[0], current_color[1], current_color[2], current_color[3]);
	//
	OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_TEXTURE_ENV_MODE :%@:", tex_env_mode_string);
	//
	OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_SHADEMODEL :%@:",  (gl_shade_model[0] == GL_SMOOTH)? @"GL_SMOOTH": @"GL_FLAT");
	//
	if (glIsEnabled(GL_FOG))
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_FOG :ENABLED:");
	//
	if (glIsEnabled(GL_COLOR_MATERIAL))
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_COLOR_MATERIAL :ENABLED:");
	//
	if (glIsEnabled(GL_BLEND))
	{
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_BLEND :ENABLED:");
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_BLEND_FUNC (:%@:, :%@:)", blend_src_string, blend_dst_string);
	}
	//
	if (glIsEnabled(GL_CULL_FACE))
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_CULL_FACE :ENABLED:");
	//
	OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_CULL_FACE_MODE :%@:", cull_face_mode_string);
	//
	OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_FRONT_FACE :%@:", front_face_string);
}

// check for OpenGL errors, reporting them if where is not nil
//
BOOL CheckOpenGLErrors(NSString* where)
{
	GLenum			errCode;
	const GLubyte	*errString = NULL;
	BOOL			errorOccurred = NO;
	
	// Short-circut here, because glGetError() is quite expensive.
	if (OOLogWillDisplayMessagesInClass(kOOLogOpenGLError))
	{
		errCode = glGetError();
		
		if (errCode != GL_NO_ERROR)
		{
			errorOccurred = YES;
			errString = gluErrorString(errCode);
			if (where == nil) where = @"<unknown>";
			
			OOLog(kOOLogOpenGLError, @"OpenGL error: '%s' (%u) in: %@", errString, errCode, where);
		}
	}
	return errorOccurred;
}

// keep track of various OpenGL states
//
static BOOL mygl_texture_2d;

void my_glEnable(GLenum gl_state)
{
	switch (gl_state)
	{
		case GL_TEXTURE_2D:
			if (mygl_texture_2d)
				return;
			mygl_texture_2d = YES;
			break;
		default:
			break;
	}
	glEnable(gl_state);
}
//
void my_glDisable(GLenum gl_state)
{
	switch (gl_state)
	{
		case GL_TEXTURE_2D:
			if (!mygl_texture_2d)
				return;
			mygl_texture_2d = NO;
			break;
		default:
			break;
	}
	glDisable(gl_state);
}


static NSString * const kOOCacheMeshes = @"OOMesh";

@implementation OOCacheManager (OOMesh)

+ (NSDictionary *)meshDataForName:(NSString *)inShipName
{
	return [[self sharedCache] objectForKey:inShipName inCache:kOOCacheMeshes];
}


+ (void)setMeshData:(NSDictionary *)inData forName:(NSString *)inShipName
{
	if (inData != nil && inShipName != nil)
	{
		[[self sharedCache] setObject:inData forKey:inShipName inCache:kOOCacheMeshes];
	}
}

@end



static NSString * const kOOCacheOctrees = @"octrees";

@implementation OOCacheManager (Octree)

+ (Octree *)octreeForModel:(NSString *)inKey
{
	NSDictionary		*dict = nil;
	Octree				*result = nil;
	
	dict = [[self sharedCache] objectForKey:inKey inCache:kOOCacheOctrees];
	if (dict != nil)
	{
		result = [[Octree alloc] initWithDictionary:dict];
		[result autorelease];
	}
	
	return result;
}


+ (void)setOctree:(Octree *)inOctree forModel:(NSString *)inKey
{
	if (inOctree != nil && inKey != nil)
	{
		[[self sharedCache] setObject:[inOctree dict] forKey:inKey inCache:kOOCacheOctrees];
	}
}

@end
