/*

Geometry.h

Class for reasoning about triangle meshes, in particular for the creation of
octtrees for collision-detection purposes.

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

#import "OOCocoa.h"

#import "OOMaths.h"

@class ShipEntity, Octree;

@interface Geometry : NSObject
{
	// a geometry essentially consists of a whole bunch of Triangles.
	int			n_triangles;			// how many triangles in the geometry
	int			max_triangles;			// how many triangles are allowed in the geometry before expansion
	Triangle*	triangles;				// pointer to an array of triangles which we'll grow as necessary...
	BOOL		isConvex;				// set at initialisation to NO
}

- (id) initWithCapacity:(unsigned)amount;

- (BOOL) isConvex;
- (void) setConvex:(BOOL) value;

- (void) addTriangle:(Triangle) tri;

- (BOOL) testHasGeometry;
- (BOOL) testIsConvex;
- (BOOL) testCornersWithinGeometry:(GLfloat) corner;
- (GLfloat) findMaxDimensionFromOrigin;

- (Octree*) findOctreeToDepth: (int) depth;
- (id) octreeWithinRadius:(GLfloat) octreeRadius toDepth: (int) depth;

- (void) translate:(Vector) offset;
- (void) scale:(GLfloat) scalar;

- (void) x_axisSplitBetween:(Geometry*) g_plus :(Geometry*) g_minus :(GLfloat) x;
- (void) y_axisSplitBetween:(Geometry*) g_plus :(Geometry*) g_minus :(GLfloat) y;
- (void) z_axisSplitBetween:(Geometry*) g_plus :(Geometry*) g_minus :(GLfloat) z;

@end
