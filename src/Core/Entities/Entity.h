/*

Entity.h

Base class for entities, i.e. drawable world objects.

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


#import "OOCocoa.h"
#import "OOMaths.h"
#import "OOCacheManager.h"
#import "OOTypes.h"
#import "OOWeakReference.h"

@class Universe, Geometry, CollisionRegion, ShipEntity;


#ifndef NDEBUG

#define DEBUG_ALL					0xffffffff
#define DEBUG_LINKED_LISTS			0x00000001
#define DEBUG_ENTITIES				0x00000002
#define DEBUG_COLLISIONS			0x00000004
#define DEBUG_DOCKING				0x00000008
#define DEBUG_OCTREE				0x00000010
#define DEBUG_OCTREE_TEXT			0x00000020
#define DEBUG_BOUNDING_BOXES		0x00000040
#define DEBUG_OCTREE_DRAW			0x00000080
#define DEBUG_DRAW_NORMALS			0x00000100
#define DEBUG_NO_DUST				0x00000200
#define DEBUG_MISC					0x10000000


extern uint32_t gDebugFlags;
extern uint32_t gLiveEntityCount;
extern size_t gTotalEntityMemory;

#endif

#define NO_DRAW_DISTANCE_FACTOR		512.0
#define ABSOLUTE_NO_DRAW_DISTANCE2	(2500.0 * 2500.0 * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR)
// ie. the furthest away thing we can draw is at 1280km (a 2.5km wide object would disappear at that range)


#define SCANNER_MAX_RANGE			25600.0
#define SCANNER_MAX_RANGE2			655360000.0

#define CLOSE_COLLISION_CHECK_MAX_RANGE2 1000000000.0


@interface Entity: OOWeakRefObject
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
	OOUniversalID			universalID;			// used to reference the entity
	
	unsigned				isRing: 1,
							isShip: 1,
							isStation: 1,
							isPlanet: 1,
							isPlayer: 1,
							isSky: 1,
							isWormhole: 1,
							isSubEntity: 1,
							hasMoved: 1,
							hasRotated: 1,
							hasCollided: 1,
							isSunlit: 1,
							collisionTestFilter: 1,
							throw_sparks: 1,
							isImmuneToBreakPatternHide: 1,
							isExplicitlyNotMainStation: 1;
	
	OOScanClass				scanClass;
	
	GLfloat					zero_distance;
	GLfloat					no_draw_distance;		// 10 km initially
	GLfloat					collision_radius;
	Vector					position;
	Quaternion				orientation;
	
	int						zero_index;
	
	// Linked lists of entites, sorted by position on each (world) axis
	Entity					*x_previous, *x_next;
	Entity					*y_previous, *y_next;
	Entity					*z_previous, *z_next;
	
	Entity					*collision_chain;
	
	OOUniversalID			shadingEntityID;
	
	Vector					relativePosition;
	
	Entity					*collider;
	
	CollisionRegion			*collisionRegion;		// initially nil - then maintained
	
@protected
	Vector					lastPosition;
	Quaternion				lastOrientation;
	
	GLfloat					distanceTravelled;		// set to zero initially
	
	OOMatrix				rotMatrix;
	
	Vector					velocity;
	
	GLfloat					energy;
	GLfloat					maxEnergy;
	
	BoundingBox				boundingBox;
	GLfloat					mass;
	
	NSMutableArray			*collidingEntities;
	
	OOTimeAbsolute			spawnTime;
	
	struct JSObject			*jsSelf;
	
@private
	OOWeakReference			*_owner;
	OOEntityStatus			_status;
}

- (BOOL) isShip;
- (BOOL) isStation;
- (BOOL) isSubEntity;
- (BOOL) isPlayer;
- (BOOL) isPlanet;
- (BOOL) isSun;
- (BOOL) isSky;
- (BOOL) isWormhole;

- (BOOL) validForAddToUniverse;
- (void) addToLinkedLists;
- (void) removeFromLinkedLists;

- (void) updateLinkedLists;

- (void) wasAddedToUniverse;
- (void) wasRemovedFromUniverse;

- (void) warnAboutHostiles;

- (CollisionRegion*) collisionRegion;
- (void) setCollisionRegion:(CollisionRegion*)region;

- (void) setUniversalID:(OOUniversalID)uid;
- (OOUniversalID) universalID;

- (BOOL) throwingSparks;
- (void) setThrowSparks:(BOOL)value;
- (void) throwSparks;

- (void) setOwner:(Entity *)ent;
- (id)owner;
- (ShipEntity *)parentEntity;	// owner if self is subentity of owner, otherwise nil.
- (ShipEntity *)rootShipEntity;	// like parentEntity, but recursive.

- (void) setPosition:(Vector)posn;
- (void) setPositionX:(GLfloat)x y:(GLfloat)y z:(GLfloat)z;
- (Vector) position;

- (Vector) absolutePositionForSubentity;
- (Vector) absolutePositionForSubentityOffset:(Vector) offset;

- (double) zeroDistance;
- (Vector) relativePosition;
- (NSComparisonResult) compareZeroDistance:(Entity *)otherEntity;

- (BoundingBox) boundingBox;

- (GLfloat) mass;

- (Quaternion) orientation;
- (void) setOrientation:(Quaternion) quat;
- (Quaternion) normalOrientation;	// Historical wart: orientation.w is reversed for player; -normalOrientation corrects this.
- (void) setNormalOrientation:(Quaternion) quat;
- (void) orientationChanged;

- (void) setVelocity:(Vector)vel;
- (Vector) velocity;
- (double) speed;

- (GLfloat) distanceTravelled;
- (void) setDistanceTravelled:(GLfloat)value;


- (void) setStatus:(OOEntityStatus)stat;
- (OOEntityStatus) status;

- (void) setScanClass:(OOScanClass)sClass;
- (OOScanClass) scanClass;

- (void) setEnergy:(GLfloat)amount;
- (GLfloat) energy;

- (void) setMaxEnergy:(GLfloat)amount;
- (GLfloat) maxEnergy;

- (void) applyRoll:(GLfloat)roll andClimb:(GLfloat)climb;
- (void) applyRoll:(GLfloat)roll climb:(GLfloat) climb andYaw:(GLfloat)yaw;
- (void) moveForward:(double)amount;

- (OOMatrix) rotationMatrix;
- (OOMatrix) drawRotationMatrix;
- (OOMatrix) transformationMatrix;
- (OOMatrix) drawTransformationMatrix;

- (BOOL) canCollide;
- (GLfloat) collisionRadius;
- (void) setCollisionRadius:(GLfloat)amount;
- (NSMutableArray *)collisionArray;

- (void) update:(OOTimeDelta) delta_t;

- (BOOL) checkCloseCollisionWith:(Entity *)other;

- (void) takeEnergyDamage:(double) amount from:(Entity *) ent becauseOf:(Entity *) other;

- (void) dumpState;		// General "describe situtation verbosely in log" command.
- (void) dumpSelfState;	// Subclasses should override this, not -dumpState, and call throught to super first.

// Subclass repsonsibilities
- (double) findCollisionRadius;
- (Geometry*) geometry;
- (void) drawEntity:(BOOL)immediate :(BOOL)translucent;

// For shader bindings.
- (GLfloat) universalTime;
- (GLfloat) spawnTime;
- (GLfloat) timeElapsedSinceSpawn;

@end
