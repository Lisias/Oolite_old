/*

	Oolite

	Octree.h
	
	Created by Giles Williams on 31/01/2006.


Copyright (c) 2005, Giles C Williams
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
#import "vector.h"

#define	OCTREE_MAX_DEPTH	5
#define	OCTREE_MIN_RADIUS	1.0
// 5 or 6 will be the final working resolution

extern int debug;

struct octree_struct
{
	GLfloat				radius;
	int*				octree;	
	unsigned char*		octree_collision;
};

typedef struct octree_struct Octree_details;

@interface Octree : NSObject
{
	GLfloat		radius;
	int			leafs;
	int*		octree;
	BOOL		hasCollision;
	
	unsigned char*		octree_collision;
}

- (GLfloat)	radius;
- (int)		leafs;
- (int*)	octree;
- (BOOL)	hasCollision;
- (void)	setHasCollision:(BOOL) value;
- (unsigned char*)	octree_collision;

- (Octree_details)	octreeDetails;

- (id) initWithRepresentationOfOctree:(GLfloat) octRadius :(NSObject*) octreeArray :(int) leafsize;
- (id) initWithDictionary:(NSDictionary*) dict;

- (Octree*) octreeScaledBy:(GLfloat) factor;

int copyRepresentationIntoOctree(NSObject* theRep, int* theBuffer, int atLocation, int nextFreeLocation);

Vector offsetForOctant(int oct, GLfloat r);

- (void) drawOctree;
- (void) drawOctreeFromLocation:(int) loc :(GLfloat) scale :(Vector) offset;

- (void) drawOctreeCollisions;
- (void) drawOctreeCollisionFromLocation:(int) loc :(GLfloat) scale :(Vector) offset;

BOOL	isHitByLine(int* octbuffer, unsigned char* collbuffer, int level, GLfloat rad, Vector v0, Vector v1, Vector off, int face_hit);
- (GLfloat) isHitByLine: (Vector) v0: (Vector) v1;

BOOL	isHitByOctree(	Octree_details axialDetails,
						Octree_details otherDetails, Vector delta, Triangle other_ijk);
- (BOOL) isHitByOctree:(Octree*) other withOrigin: (Vector) v0 andIJK: (Triangle) ijk;
- (BOOL) isHitByOctree:(Octree*) other withOrigin: (Vector) v0 andIJK: (Triangle) ijk andScales: (GLfloat) s1: (GLfloat) s2;

- (NSDictionary*) dict;

- (GLfloat) volume;
GLfloat volumeOfOctree(Octree_details octree_details);

@end
