//
//  Entity.h
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

#define DEBUG_ALL			0xffffffff
#define DEBUG_LINKED_LISTS	0x00000001
#define DEBUG_ENTITIES		0x00000002
#define DEBUG_COLLISIONS	0x00000004
#define DEBUG_SCRIPT		0x00000008

#define MAX_VERTICES_PER_ENTITY	320
#define MAX_FACES_PER_ENTITY	512
#define MAX_TEXTURES_PER_ENTITY	8
#define MAX_VERTICES_PER_FACE	16

#define	NUM_VERTEX_ARRAY_RANGES	16

#define PI	3.141592653589793

#define NO_DRAW_DISTANCE_FACTOR		512.0
#define ABSOLUTE_NO_DRAW_DISTANCE2	2500.0 * 2500.0 * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR
// ie. the furthest away thing we can draw is at 1280km (a 2.5km wide object would disappear at that range)

#define STATUS_EXPERIMENTAL			99
#define STATUS_EFFECT				10
#define STATUS_ACTIVE				5
#define STATUS_COCKPIT_DISPLAY					2
#define STATUS_TEST					1
#define STATUS_INACTIVE				0
#define STATUS_DEAD					-1
#define STATUS_START_GAME			-10
#define STATUS_IN_FLIGHT			100
#define STATUS_DOCKED				200
#define STATUS_AUTOPILOT_ENGAGED	300
#define STATUS_DOCKING				401
#define STATUS_LAUNCHING			402
#define STATUS_WITCHSPACE_COUNTDOWN 410
#define STATUS_ENTERING_WITCHSPACE  411
#define STATUS_EXITING_WITCHSPACE   412
#define STATUS_ESCAPE_SEQUENCE		500
#define STATUS_IN_HOLD				600
#define STATUS_BEING_SCOOPED		700
#define STATUS_HANDLING_ERROR		999

#define CLASS_NOT_SET	-1
#define CLASS_NO_DRAW	0
#define CLASS_NEUTRAL	1
#define CLASS_STATION	3
#define CLASS_TARGET	4
#define CLASS_CARGO		5
#define CLASS_MISSILE	6
#define CLASS_ROCK		7
#define CLASS_MINE		8
#define CLASS_THARGOID	9
#define CLASS_BUOY		10
#define CLASS_WORMHOLE	444
#define CLASS_PLAYER	100
#define CLASS_POLICE	999
#define CLASS_MILITARY	333

#define NO_TARGET		0

#define SCANNER_MAX_RANGE   25600.0
#define SCANNER_MAX_RANGE2  655360000.0

#define CLOSE_COLLISION_CHECK_MAX_RANGE2  1000000000.0


#define MODEL_FILE @"CORIOLIS.DAT"

#import "OOCocoa.h"
#include "vector.h"
#include "legacy_random.h"

@class Universe, Geometry, CollisionRegion;


struct face
{
	GLfloat red;
	GLfloat green;
	GLfloat blue;

	Vector	normal;

	int	n_verts;

	GLint	vertex[MAX_VERTICES_PER_FACE];

	Str255		textureFileStr255;
//	NSString	*textureFile;
	GLuint	texName;
	GLfloat	s[MAX_VERTICES_PER_FACE];
	GLfloat	t[MAX_VERTICES_PER_FACE];

};

typedef struct face Face;

typedef struct
{
	GLint	index_array[3 * MAX_FACES_PER_ENTITY];	// triangles
	GLfloat	texture_uv_array[ 3 * MAX_FACES_PER_ENTITY * 2];
	Vector vertex_array[3 * MAX_FACES_PER_ENTITY];
	Vector normal_array[3 * MAX_FACES_PER_ENTITY];

	GLuint	texName;

	int		n_triangles;

}	EntityData;	// per texture

typedef struct
{
	long	rangeSize;				// # of bytes in this VAR block
	void	*dataBlockPtr;			// ptr to the memory that we're making VAR
	Boolean	forceUpdate;			// true if data in VAR block needs updating
	Boolean	activated;				// set to true the first time we use it
} VertexArrayRangeType;

typedef struct
{
	double		timeframe;		// universal time for this frame
	Vector		position;		// position
	Quaternion	q_rotation;		// rotation
	Vector		k;			// direction vectors
} Frame;

extern int debug;

@interface Entity : NSObject
{
    // the base object for ships/stations/anything actually
	//////////////////////////////////////////////////////
	//
	// @public variables:
	//
	// we forego encapsulation for some variables in order to
	// lose the overheads of Obj-C accessor methods...
	//
	@public
		//
		BOOL	isParticle;
		BOOL	isRing;
		BOOL	isShip;
		BOOL	isStation;
		BOOL	isPlanet;
		BOOL	isPlayer;
		BOOL	isSky;
		BOOL	isWormhole;
		//
		BOOL	isSubentity;
		//
		int			scan_class;
		double		zero_distance;
		double		no_draw_distance;  //  10 km initially
		GLfloat		collision_radius;
		GLfloat		actual_radius;
		Vector		position;
		Quaternion	q_rotation;
		int			status;
		//
		int			zero_index;
		BOOL		collisionTestFilter;
		// replace x_index etc. with linked lists..
		Entity	*x_previous, *x_next;
		Entity	*y_previous, *y_next;
		Entity	*z_previous, *z_next;
		//
		Entity	*collision_chain;
		
		//
		// experimental lighting:
		BOOL		isSunlit;
		int			shadingEntityID;
		//
		// to keep track of changes:
		BOOL	has_moved;
		BOOL	has_rotated;
		BOOL	has_collided;
		//
		Vector	relative_position;
		//
		Entity*	collider;
		//
		int			universal_id;				// used to reference the entity
		//
		CollisionRegion*	collision_region;		// initially nil - then maintained

	@protected
	//
	//////////////////////////////////////////////////////
	//
    //
    Universe	*universe;
	//
	Vector	last_position;
	Quaternion last_q_rotation;
	//
	double  distance_travelled; // set to zero initially
	//
    Matrix	rotation;
    gl_matrix	rotMatrix;
    //
	Vector		velocity;
	//
	Quaternion	subentity_rotational_velocity;
	//
	// positions+rotations for trails and trackbacks
	Frame	track[256];
	int		track_index;
	double	track_time;
	NSLock	*trackLock;
	//
	double  energy;
	double  max_energy;
	//
	NSMutableArray  *collidingEntities;
    //
    int			n_vertices, n_faces;
    Vector		vertices[MAX_VERTICES_PER_ENTITY];
	//
	//new...
    Vector		vertex_normal[MAX_VERTICES_PER_ENTITY];
	BOOL		is_smooth_shaded;
	//
    Face		faces[MAX_FACES_PER_ENTITY];
	BoundingBox boundingBox;
	GLfloat		mass;			// calculated as volume of bounding box
    GLuint		displayListName;
    //
    NSString	*basefile;
	//
	int			owner;
	//

	// very new
	int			n_textures;
	EntityData	entityData;
	NSRange		triangle_range[MAX_TEXTURES_PER_ENTITY];
	Str255		texture_file[MAX_TEXTURES_PER_ENTITY];
	GLuint		texture_name[MAX_TEXTURES_PER_ENTITY];

	BOOL		throw_sparks;

	// COMMON OGL STUFF

	BOOL					usingVAR;

	GLuint					gVertexArrayRangeObjects[NUM_VERTEX_ARRAY_RANGES];	// OpenGL's VAR object references
	VertexArrayRangeType	gVertexArrayRangeData[NUM_VERTEX_ARRAY_RANGES];		// our info about each VAR block

}

+ (void) setDataStore:(Universe *)univ; // class methods, they set the underlying data_storage universe
+ (Universe *) dataStore;

+ (Vector) vectorFromString:(NSString*) xyzString;
+ (Quaternion) quaternionFromString:(NSString*) wxyzString;
+ (Random_Seed) seedFromString:(NSString*) abcdefString;

+ (BOOL) scanVector:(Vector *) vector_ptr andQuaternion:(Quaternion *) quaternion_ptr fromString:(NSString*) xyzwxyzString;

+ (NSMutableArray *) scanTokensFromString:(NSString*) values;

- (id) init;
- (void) dealloc;

- (void) addToLinkedLists;
- (void) removeFromLinkedLists;
- (void) updateLinkedLists;

- (void) warnAboutHostiles;

- (Universe *) universe;
- (void) setUniverse:(Universe *)univ;

- (CollisionRegion*) collision_region;
- (void) setCollisionRegion: (CollisionRegion*) region;

- (void) setUniversal_id:(int)uid;
- (int) universal_id;

- (BOOL) throwingSparks;
- (void) setThrowSparks:(BOOL) value;
- (void) throwSparks;

- (BOOL) isSmoothShaded;
- (void) setSmoothShaded:(BOOL) value;

- (void) setOwner:(Entity *) ent;
- (Entity *) owner;

- (void) setModel:(NSString *) modelName;
- (NSString *) getModel;

- (void) setPosition:(Vector) posn;
- (void) setPosition:(GLfloat) x:(GLfloat) y:(GLfloat) z;
- (Vector) getPosition;
- (Vector) getViewpointPosition;
- (Vector) getViewpointOffset;

- (double) getZeroDistance;
- (Vector) relative_position;
- (NSComparisonResult) compareZeroDistance:(Entity *)otherEntity;

- (Geometry*) getGeometry;
- (BoundingBox) getBoundingBox;

- (GLfloat) mass;

- (void) setQRotation:(Quaternion) quat;
- (Quaternion) QRotation;

- (void) setVelocity:(Vector) vel;
- (Vector) getVelocity;
- (double) getVelocityAsSpeed;

- (double) distance_travelled;
- (void) setDistanceTravelled: (double) value;

- (void) setStatus:(int) stat;
- (int) getStatus;

- (void) setScanClass:(int) s_class;
- (int) scanClass;

- (void) setEnergy:(double) amount;
- (double) getEnergy;

- (void) applyRoll:(GLfloat) roll andClimb:(GLfloat) climb;
- (void) applyRoll:(GLfloat) roll climb:(GLfloat) climb andYaw:(GLfloat) yaw;
- (void) moveForward:(double) amount;

- (GLfloat *) rotationMatrix;
- (GLfloat *) drawRotationMatrix;

- (BOOL) canCollide;
- (double) collisionRadius;
- (void) setCollisionRadius:(double) amount;
- (NSMutableArray *) collisionArray;

- (void) drawEntity:(BOOL) immediate :(BOOL) translucent;
- (void) drawSubEntity:(BOOL) immediate :(BOOL) translucent;
- (void) reloadTextures;
- (void) initialiseTextures;
- (void) regenerateDisplayList;
- (void) generateDisplayList;

- (void) update:(double) delta_t;
- (void) saveToLastFrame;
- (void) savePosition:(Vector)pos atTime:(double)t_time atIndex:(int)t_index;
- (void) saveFrame:(Frame)frame atIndex:(int)t_index;
- (void) resetFramesFromFrame:(Frame) resetFrame withVelocity:(Vector) vel1;
- (BOOL) resetToTime:(double) t_frame;
- (Frame) frameAtTime:(double) t_frame;	// timeframe is relative to now ie. -0.5 = half a second ago.
- (Frame) frameAtTime:(double) t_frame fromFrame:(Frame) frame_zero;	// t_frame is relative to now ie. -0.5 = half a second ago.

- (NSDictionary*) modelData;
- (void) setModelFromModelData:(NSDictionary*) dict;

- (void) loadData:(NSString *) filename;
- (void) checkNormalsAndAdjustWinding;
- (void) calculateVertexNormals;

- (void) setUpVertexArrays;

- (double) findCollisionRadius;

- (BoundingBox) findBoundingBoxRelativeTo:(Entity *)other InVectors:(Vector) _i :(Vector) _j :(Vector) _k;

- (BoundingBox) findBoundingBoxRelativeToPosition:(Vector)opv InVectors:(Vector) _i :(Vector) _j :(Vector) _k;

- (BOOL) checkCloseCollisionWith:(Entity *)other;

- (void) takeEnergyDamage:(double) amount from:(Entity *) ent becauseOf:(Entity *) other;

- (void) fakeTexturesWithImageFile: (NSString *) textureFile andMaxSize:(NSSize) maxSize;

- (NSString *) toString;
/*--
- (NSDictionary *) toDictionary;
--*/

// COMMON OGL ROUTINES

- (BOOL) OGL_InitVAR;

- (void) OGL_AssignVARMemory:(long) size :(void *) data :(Byte) whichVAR;

- (void) OGL_UpdateVAR;

// log a list of current states
//
void logGLState();

// check for OpenGL errors, reporting them if where is not nil
//
BOOL checkGLErrors(NSString* where);

// keep track of various OpenGL states
//
BOOL mygl_texture_2d;
//
void my_glEnable(GLenum gl_state);
void my_glDisable(GLenum gl_state);

@end
