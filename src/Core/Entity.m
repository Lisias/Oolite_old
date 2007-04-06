/*

Entity.m

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

#import "Entity.h"
#import "PlayerEntity.h"

#import "OOMaths.h"
#import "Geometry.h"
#import "Universe.h"
#import "GameController.h"
#import "TextureStore.h"
#import "ResourceManager.h"
#import "OOConstToString.h"

#import "CollisionRegion.h"

#import "NSScannerOOExtensions.h"

#define kOOLogUnconvertedNSLog @"unclassified.Entity"


static NSString * const kOOLogEntityAddToList				= @"entity.linkedList.add";
static NSString * const kOOLogEntityAddToListError			= @"entity.linkedList.add.error";
static NSString * const kOOLogEntityRemoveFromList			= @"entity.linkedList.remove";
static NSString * const kOOLogEntityRemoveFromListError		= @"entity.linkedList.remove.error";
	   NSString * const kOOLogEntityVerificationError		= @"entity.linkedList.verify.error";
static NSString * const kOOLogEntityUpdateError				= @"entity.linkedList.update.error";
static NSString * const kOOLogOpenGLExtensionsVAR			= @"rendering.opengl.extensions.var";
static NSString * const kOOLogOpenGLStateDump				= @"rendering.opengl.stateDump";
static NSString * const kOOLogEntityDataNotFound			= @"entity.loadMesh.error.fileNotFound";
static NSString * const kOOLogEntityTooManyVertices			= @"entity.loadMesh.error.tooManyVertices";
static NSString * const kOOLogEntityTooManyFaces			= @"entity.loadMesh.error.tooManyFaces";


// global flag for VAR
BOOL global_usingVAR;
BOOL global_testForVAR;


@interface Entity (Private)

- (void) loadData:(NSString *)filename;
- (void) checkNormalsAndAdjustWinding;
- (void) calculateVertexNormals;

- (NSDictionary*) modelData;
- (BOOL) setModelFromModelData:(NSDictionary*) dict;

- (Vector) normalForVertex:(int)v_index withSharedRedValue:(GLfloat)red_value;

@end


@interface OOCacheManager (Models)

+ (NSDictionary *)meshDataForName:(NSString *)inShipName;
+ (void)setMeshData:(NSDictionary *)inData forName:(NSString *)inShipName;

@end


@implementation Entity

- (id) init
{
    self = [super init];
    //
	q_rotation = kIdentityQuaternion;
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
    //
	position = make_vector( 0.0f, 0.0f, 0.0f);
	//
	zero_distance = 0.0;  //  10 km
	no_draw_distance = 100000.0;  //  10 km
	//
	distanceTravelled = 0.0;
	//
	energy =	0.0;
	//
	collision_radius = 0.0;
	//
	collidingEntities = [(NSMutableArray *)[NSMutableArray alloc] initWithCapacity:16];   // alloc automatically retains
	//
	scanClass = CLASS_NOT_SET;
	//
	universalID = NO_TARGET;
	//
	isSmoothShaded = NO;
    //
    n_vertices = 0;
    n_faces = 0;
    //
    displayListName = 0;
    //
    status = STATUS_COCKPIT_DISPLAY;
    //
    basefile = @"No Model";
	//
	throw_sparks = NO;
	//
	usingVAR = NO;
	//
	isParticle = NO;
	isRing = NO;
	isShip = NO;
	isStation = NO;
	isPlanet = NO;
	isPlayer = NO;
	isSky = NO;
	isSubentity = NO;
	//
	isSunlit = YES;
	shadingEntityID = NO_TARGET;
	//
	collisionRegion = nil;
	//
	collisionTestFilter = NO;
	x_next = x_previous = nil;
	y_next = y_previous = nil;
	z_next = z_previous = nil;
	//
	collision_chain = nil;
	//
    return self;
}


- (void) dealloc
{
	[basefile release];
	[collidingEntities release];
	[trackLock release];
	[collisionRegion release];
	[weakSelf weakRefDrop];
	
	[super dealloc];
}


- (id)weakRetain
{
	if (weakSelf == nil)  weakSelf = [OOWeakReference weakRefWithObject:self];
	return [weakSelf retain];
}


- (void)weakRefDied:(OOWeakReference *)weakRef
{
	assert(weakRef == weakSelf);
	weakSelf = nil;
}


- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p>{%u position=%@ scanClass=%@ status=%@}", [self class], self, [self universalID], VectorDescription([self position]), ScanClassToString([self scanClass]), EntityStatusToString([self status])];
}


- (void) addToLinkedLists
{
	if (debug & DEBUG_LINKED_LISTS)
		OOLog(kOOLogEntityAddToList, @"DEBUG adding entity %@ to linked lists", self);
	//
	// insert at the start
	if (UNIVERSE)
	{
		x_previous = nil; x_next = UNIVERSE->x_list_start;
		// move UP the list
		while ((x_next)&&(x_next->position.x - x_next->collision_radius < position.x - collision_radius))
		{
			x_previous = x_next;
			x_next = x_next->x_next;
		}	
		if (x_next)		x_next->x_previous = self;
		if (x_previous) x_previous->x_next = self;
		else			UNIVERSE->x_list_start = self;
		
		y_previous = nil; y_next = UNIVERSE->y_list_start;
		// move UP the list
		while ((y_next)&&(y_next->position.y - y_next->collision_radius < position.y - collision_radius))
		{
			y_previous = y_next;
			y_next = y_next->y_next;
		}	
		if (y_next)		y_next->y_previous = self;
		if (y_previous) y_previous->y_next = self;
		else			UNIVERSE->y_list_start = self;

		z_previous = nil; z_next = UNIVERSE->z_list_start;
		// move UP the list
		while ((z_next)&&(z_next->position.z - z_next->collision_radius < position.z - collision_radius))
		{
			z_previous = z_next;
			z_next = z_next->z_next;
		}	
		if (z_next)		z_next->z_previous = self;
		if (z_previous) z_previous->z_next = self;
		else			UNIVERSE->z_list_start = self;
				
	}
	
	if (debug & DEBUG_LINKED_LISTS)
		if (![self checkLinkedLists])
		{
			OOLog(kOOLogEntityAddToListError, @"DEBUG LINKED LISTS - problem encountered while adding %@ to linked lists", self);
			[UNIVERSE obj_dump];
		
			exit(-1);
		}

}

- (void) removeFromLinkedLists
{
	if (debug & DEBUG_LINKED_LISTS)
		OOLog(kOOLogEntityRemoveFromList, @"DEBUG removing entity %@ from linked lists", self);

	if ((x_next == nil)&&(x_previous == nil))	// removed already!
		return;

	// make sure the starting point is still correct
	if (UNIVERSE)
	{
		if ((UNIVERSE->x_list_start == self)&&(x_next))
				UNIVERSE->x_list_start = x_next;
		if ((UNIVERSE->y_list_start == self)&&(y_next))
				UNIVERSE->y_list_start = y_next;
		if ((UNIVERSE->z_list_start == self)&&(z_next))
				UNIVERSE->z_list_start = z_next;
	}
	//
	if (x_previous)		x_previous->x_next = x_next;
	if (x_next)			x_next->x_previous = x_previous;
	//
	if (y_previous)		y_previous->y_next = y_next;
	if (y_next)			y_next->y_previous = y_previous;
	//
	if (z_previous)		z_previous->z_next = z_next;
	if (z_next)			z_next->z_previous = z_previous;
	//
	x_previous = nil;	x_next = nil;
	y_previous = nil;	y_next = nil;
	z_previous = nil;	z_next = nil;

	if (debug & DEBUG_LINKED_LISTS)
		if (![self checkLinkedLists])
		{
			OOLog(kOOLogEntityRemoveFromListError, @"DEBUG LINKED LISTS - problem encountered while removing %@ from linked lists", self);
			[UNIVERSE obj_dump];
		
			exit(-1);
		}
}

- (BOOL) checkLinkedLists
{
	// DEBUG check for loops
	if (UNIVERSE->n_entities > 0)
	{
		int n;
		Entity	*check, *last;
		//
		last = nil;
		//
		n = UNIVERSE->n_entities;
		check = UNIVERSE->x_list_start;
		while ((n--)&&(check))
		{
			last = check;
			check = check->x_next;
		}
		if ((check)||(n > 0))
		{
			OOLog(kOOLogEntityVerificationError, @"Broken x_next %@ list (%d) ***", UNIVERSE->x_list_start, n);
			return NO;
		}
		//
		n = UNIVERSE->n_entities;
		check = last;
		while ((n--)&&(check))	check = check->x_previous;
		if ((check)||(n > 0))
		{
			OOLog(kOOLogEntityVerificationError, @"Broken x_previous %@ list (%d) ***", UNIVERSE->x_list_start, n);
			return NO;
		}
		//
		n = UNIVERSE->n_entities;
		check = UNIVERSE->y_list_start;
		while ((n--)&&(check))
		{
			last = check;
			check = check->y_next;
		}
		if ((check)||(n > 0))
		{
			OOLog(kOOLogEntityVerificationError, @"Broken y_next %@ list (%d) ***", UNIVERSE->y_list_start, n);
			return NO;
		}
		//
		n = UNIVERSE->n_entities;
		check = last;
		while ((n--)&&(check))	check = check->y_previous;
		if ((check)||(n > 0))
		{
			OOLog(kOOLogEntityVerificationError, @"Broken y_previous %@ list (%d) ***", UNIVERSE->y_list_start, n);
			return NO;
		}
		//
		n = UNIVERSE->n_entities;
		check = UNIVERSE->z_list_start;
		while ((n--)&&(check))
		{
			last = check;
			check = check->z_next;
		}
		if ((check)||(n > 0))
		{
			OOLog(kOOLogEntityVerificationError, @"Broken z_next %@ list (%d) ***", UNIVERSE->z_list_start, n);
			return NO;
		}
		//
		n = UNIVERSE->n_entities;
		check = last;
		while ((n--)&&(check))	check = check->z_previous;
		if ((check)||(n > 0))
		{
			OOLog(kOOLogEntityVerificationError, @"Broken z_previous %@ list (%d) ***", UNIVERSE->z_list_start, n);
			return NO;
		}
	}
	return YES;
}

- (void) updateLinkedLists
{
	if (!UNIVERSE)
		return;	// not in the UNIVERSE - don't do this!
	if ((x_next == nil)&&(x_previous == nil))
		return;	// not in the lists - don't do this!

	if (debug & DEBUG_LINKED_LISTS)
		if (![self checkLinkedLists])
		{
			OOLog(kOOLogEntityVerificationError, @"DEBUG LINKED LISTS problem encountered before updating linked lists for %@", self);
			[UNIVERSE obj_dump];
		
			exit(-1);
		}

	// update position in linked list for position.x
	// take self out of list..
	if (x_previous)		x_previous->x_next = x_next;
	if (x_next)			x_next->x_previous = x_previous;
	// sink DOWN the list
	while ((x_previous)&&(x_previous->position.x - x_previous->collision_radius > position.x - collision_radius))
	{
		x_next = x_previous;
		x_previous = x_previous->x_previous;
	}
	// bubble UP the list
	while ((x_next)&&(x_next->position.x - x_next->collision_radius < position.x - collision_radius))
	{
		x_previous = x_next;
		x_next = x_next->x_next;
	}
	if (x_next)		// insert self into the list before x_next..
		x_next->x_previous = self;
	if (x_previous)	// insert self into the list after x_previous..
		x_previous->x_next = self;
	if ((x_previous == nil)&&(UNIVERSE))	// if we're the first then tell the UNIVERSE!
			UNIVERSE->x_list_start = self;
	
	// update position in linked list for position.y
	// take self out of list..
	if (y_previous)		y_previous->y_next = y_next;
	if (y_next)			y_next->y_previous = y_previous;
	// sink DOWN the list
	while ((y_previous)&&(y_previous->position.y - y_previous->collision_radius > position.y - collision_radius))
	{
		y_next = y_previous;
		y_previous = y_previous->y_previous;
	}
	// bubble UP the list
	while ((y_next)&&(y_next->position.y - y_next->collision_radius < position.y - collision_radius))
	{
		y_previous = y_next;
		y_next = y_next->y_next;
	}
	if (y_next)		// insert self into the list before y_next..
		y_next->y_previous = self;
	if (y_previous)	// insert self into the list after y_previous..
		y_previous->y_next = self;
	if ((y_previous == nil)&&(UNIVERSE))	// if we're the first then tell the UNIVERSE!
			UNIVERSE->y_list_start = self;
	
	// update position in linked list for position.z
	// take self out of list..
	if (z_previous)		z_previous->z_next = z_next;
	if (z_next)			z_next->z_previous = z_previous;
	// sink DOWN the list
	while ((z_previous)&&(z_previous->position.z - z_previous->collision_radius > position.z - collision_radius))
	{
		z_next = z_previous;
		z_previous = z_previous->z_previous;
	}
	// bubble UP the list
	while ((z_next)&&(z_next->position.z - z_next->collision_radius < position.z - collision_radius))
	{
		z_previous = z_next;
		z_next = z_next->z_next;
	}
	if (z_next)		// insert self into the list before z_next..
		z_next->z_previous = self;
	if (z_previous)	// insert self into the list after z_previous..
		z_previous->z_next = self;
	if ((z_previous == nil)&&(UNIVERSE))	// if we're the first then tell the UNIVERSE!
			UNIVERSE->z_list_start = self;
	
	// done
	if (debug & DEBUG_LINKED_LISTS)
		if (![self checkLinkedLists])
		{
			OOLog(kOOLogEntityUpdateError, @"DEBUG LINKED LISTS problem encountered after updating linked lists for %@", self);
			[UNIVERSE obj_dump];
		
			exit(-1);
		}
}


- (void) wasAddedToUniverse
{
	// Do nothing
}


- (void) wasRemovedFromUniverse
{
	// Do nothing
}


- (void) warnAboutHostiles
{
	// do nothing for now, this can be expanded in sub classes
	OOLog(@"general.error.subclassResponsibility.Entity-warnAboutHostiles", @"***** Entity does nothing in warnAboutHostiles");
}

- (CollisionRegion*) collisionRegion
{
	return collisionRegion;
}

- (void) setCollisionRegion: (CollisionRegion*) region
{
	if (collisionRegion) [collisionRegion release];
	collisionRegion = [region retain];
}

- (void) setUniversalID:(UniversalID)uid
{
	universalID = uid;
}

- (UniversalID) universalID
{
	return universalID;
}

- (BOOL) throwingSparks
{
	return throw_sparks;
}

- (void) setThrowSparks:(BOOL) value
{
	throw_sparks = value;
}

- (void) throwSparks;
{
	// do nothing for now
}

- (BOOL) isSmoothShaded
{
	return isSmoothShaded;
}
- (void) setSmoothShaded:(BOOL) value
{
	isSmoothShaded = value;
}

- (void) setOwner:(Entity *) ent
{
	UniversalID	owner_id = [ent universalID];
	
	if ([UNIVERSE entityForUniversalID:owner_id] == ent)	// check to make sure it's kosher
		owner = owner_id;
	else
		owner = NO_TARGET;
}

- (Entity *) owner
{
	return [UNIVERSE entityForUniversalID:owner];
}


- (void) setModelName:(NSString *) modelName
{
	// use our own pool to save big memory
	NSAutoreleasePool* mypool = [[NSAutoreleasePool alloc] init];
	// clear old data
	if (basefile)	[basefile release];
    basefile = [modelName retain];
	//
	[self regenerateDisplayList];
    //
		
	NS_DURING
		[self loadData:basefile];
	NS_HANDLER
		if ([[localException name] isEqual: OOLITE_EXCEPTION_DATA_NOT_FOUND])
		{
			OOLog(kOOLogFileNotFound, @"***** Oolite Data Not Found Exception : '%@' in [Entity setModelName:] *****", [localException reason]);
		}
		[localException retain];
		[mypool release];
		[localException autorelease];
		[localException raise];
	NS_ENDHANDLER

    //
    [self checkNormalsAndAdjustWinding];
    //
	// set the collision radius
	//
	collision_radius = [self findCollisionRadius];
	actual_radius = collision_radius;
	
	[mypool release];
}


- (NSString *) modelName
{
	return basefile;
}

- (void) setPosition:(Vector) posn
{
	position = posn;
}

- (void) setPositionX:(GLfloat)x y:(GLfloat)y z:(GLfloat)z
{
	position.x = x;
	position.y = y;
	position.z = z;
}

- (double) zeroDistance
{
	return zero_distance;
}

- (Vector) relativePosition
{
	return relativePosition;
}

- (NSComparisonResult) compareZeroDistance:(Entity *)otherEntity;
{
	if ((otherEntity)&&(zero_distance > otherEntity->zero_distance))
		return NSOrderedAscending;
	else
		return NSOrderedDescending;
}

- (Geometry*) geometry
{
	Geometry* result = [(Geometry *)[Geometry alloc] initWithCapacity: n_faces];
	int i;
	for (i = 0; i < n_faces; i++)
	{
		Triangle tri;
		tri.v[0] = vertices[faces[i].vertex[0]];
		tri.v[1] = vertices[faces[i].vertex[1]];
		tri.v[2] = vertices[faces[i].vertex[2]];
		[result addTriangle: tri];
	}
	return [result autorelease];
}

- (BoundingBox) boundingBox
{
	return boundingBox;
}

- (GLfloat) mass
{
	return mass;
}

- (void) setQRotation:(Quaternion) quat
{
	q_rotation = quat;
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
}

- (Quaternion) QRotation
{
	return q_rotation;
}

- (void) setVelocity:(Vector) vel
{
	velocity = vel;
}

- (Vector) velocity
{
	return velocity;
}

- (double) speed
{
	return magnitude2(velocity);
}

- (GLfloat) distanceTravelled
{
	return distanceTravelled;
}

- (void) setDistanceTravelled: (GLfloat) value
{
	distanceTravelled = value;
}

- (void) setStatus:(EntityStatus) stat
{
	status = stat;
}

- (EntityStatus) status
{
	return status;
}

- (void) setScanClass:(ScanClass)sClass
{
	scanClass = sClass;
}

- (ScanClass) scanClass
{
	return scanClass;
}


- (void) setEnergy:(GLfloat) amount
{
	energy = amount;
}


- (GLfloat) energy
{
	return energy;
}


- (void) setMaxEnergy:(GLfloat)amount
{
	maxEnergy = amount;
}


- (GLfloat) maxEnergy
{
	return maxEnergy;
}


- (void) applyRoll:(GLfloat) roll andClimb:(GLfloat) climb
{
	if ((roll == 0.0)&&(climb == 0.0)&&(!hasRotated))
		return;

	if (roll)
		quaternion_rotate_about_z( &q_rotation, -roll);
	if (climb)
		quaternion_rotate_about_x( &q_rotation, -climb);

    quaternion_normalize(&q_rotation);
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
}

- (void) applyRoll:(GLfloat) roll climb:(GLfloat) climb andYaw:(GLfloat) yaw
{
	if ((roll == 0.0)&&(climb == 0.0)&&(yaw == 0.0)&&(!hasRotated))
		return;

	if (roll)
		quaternion_rotate_about_z( &q_rotation, -roll);
	if (climb)
		quaternion_rotate_about_x( &q_rotation, -climb);
	if (yaw)
		quaternion_rotate_about_y( &q_rotation, -yaw);

    quaternion_normalize(&q_rotation);
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
}

- (void) moveForward:(double) amount
{
    Vector		forward = vector_forward_from_quaternion(q_rotation);
	distanceTravelled += amount;
	position.x += amount * forward.x;
	position.y += amount * forward.y;
	position.z += amount * forward.z;
}

- (GLfloat *) rotationMatrix
{
    return rotMatrix;
}

- (GLfloat *) drawRotationMatrix
{
    return rotMatrix;
}

- (Vector) position
{
    return position;
}

- (Vector) viewpointPosition
{
    return position;
}

- (Vector) viewpointOffset
{
	return make_vector( 0.0f, 0.0f, 0.0f);
}

- (BOOL) canCollide
{
	return YES;
}

- (double) collisionRadius
{
	return collision_radius;
}

- (void) setCollisionRadius:(double) amount
{
	collision_radius = amount;
}

- (NSMutableArray *) collisionArray
{
	return collidingEntities;
}


- (void) drawEntity:(BOOL) immediate :(BOOL) translucent
{
    // draw the thing !
    //
    int ti;
    GLfloat mat_ambient[] = { 1.0, 1.0, 1.0, 1.0 };
    GLfloat mat_no[] =		{ 0.0, 0.0, 0.0, 1.0 };

	NS_DURING

		if (isSmoothShaded)
			glShadeModel(GL_SMOOTH);
		else
			glShadeModel(GL_FLAT);

		if (!translucent)
		{
			if (basefile)
			{
				// calls moved here because they are unsupported in display lists
				//
				glDisableClientState(GL_COLOR_ARRAY);
				glDisableClientState(GL_INDEX_ARRAY);
				glDisableClientState(GL_EDGE_FLAG_ARRAY);
				//
				glEnableClientState(GL_VERTEX_ARRAY);
				glEnableClientState(GL_NORMAL_ARRAY);
				glEnableClientState(GL_TEXTURE_COORD_ARRAY);

				glVertexPointer( 3, GL_FLOAT, 0, entityData.vertex_array);
				glNormalPointer( GL_FLOAT, 0, entityData.normal_array);
				glTexCoordPointer( 2, GL_FLOAT, 0, entityData.texture_uv_array);

				if (immediate)
				{

#ifdef GNUSTEP
           			// TODO: Find out what these APPLE functions can be replaced with
#else
					if (usingVAR)
						glBindVertexArrayAPPLE(gVertexArrayRangeObjects[0]);
#endif

					//
					// gap removal (draws flat polys)
					//
					glDisable(GL_TEXTURE_2D);
					GLfloat amb_diff0[] = { 0.5, 0.5, 0.5, 1.0};
					glMaterialfv( GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, amb_diff0);
					glMaterialfv( GL_FRONT_AND_BACK, GL_EMISSION, mat_no);
					glColor4f( 0.25, 0.25, 0.25, 1.0);	// gray
					glDepthMask(GL_FALSE); // don't write to depth buffer
					glDrawArrays( GL_TRIANGLES, 0, entityData.n_triangles);	// draw in gray to mask the edges
					glDepthMask(GL_TRUE);

					//
					// now the textures ...
					//
					glEnable(GL_TEXTURE_2D);
					glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
					glMaterialfv( GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, mat_ambient);
					glMaterialfv( GL_FRONT_AND_BACK, GL_EMISSION, mat_no);

					for (ti = 1; ti <= n_textures; ti++)
					{
						glBindTexture(GL_TEXTURE_2D, texture_name[ti]);
						glDrawArrays( GL_TRIANGLES, triangle_range[ti].location, triangle_range[ti].length);
					}
				}
				else
				{
					if (displayListName != 0)
					{
						glCallList(displayListName);
					}
					else
					{
						[self initialiseTextures];
						[self generateDisplayList];
					}
				}
			}
			else
			{
				OOLog(kOOLogFileNotLoaded, @"ERROR no basefile for entity %@");
			}
		}
		if (!isSmoothShaded) glShadeModel(GL_SMOOTH);
		CheckOpenGLErrors([NSString stringWithFormat:@"Entity after drawing %@", self]);

	NS_HANDLER

		OOLog(kOOLogException, @"***** [Entity drawEntity::] encountered exception: %@ : %@ *****",[localException name], [localException reason]);
		OOLog(kOOLogException, @"***** Removing entity %@ from UNIVERSE *****", self);
		[UNIVERSE removeEntity:self];
		if ([[localException name] hasPrefix:@"Oolite"])
			[UNIVERSE handleOoliteException:localException];	// handle these ourself
		else
			[localException raise];	// pass these on

	NS_ENDHANDLER
}

- (void) drawSubEntity:(BOOL) immediate :(BOOL) translucent
{
	Entity* my_owner = [UNIVERSE entityForUniversalID:owner];
	if (my_owner)
	{
		// this test provides an opportunity to do simple LoD culling
		//
		zero_distance = my_owner->zero_distance;
		if (zero_distance > no_draw_distance)
		{
			return; // TOO FAR AWAY
		}
	}
	if (status == STATUS_ACTIVE)
	{
		Vector abspos = position;  // STATUS_ACTIVE means it is in control of it's own orientation
		Entity*		last = nil;
		Entity*		father = my_owner;
		GLfloat*	r_mat = [father drawRotationMatrix];
		while ((father)&&(father != last))
		{
			mult_vector_gl_matrix(&abspos, r_mat);
			Vector pos = father->position;
			abspos.x += pos.x;	abspos.y += pos.y;	abspos.z += pos.z;
			last = father;
			father = [father owner];
			r_mat = [father drawRotationMatrix];
		}
		glPopMatrix();  // one down
		glPushMatrix();
				// position and orientation is absolute
		glTranslated( abspos.x, abspos.y, abspos.z);

		glMultMatrixf(rotMatrix);

		[self drawEntity:immediate :translucent];
	}
	else
	{
		glPushMatrix();

		glTranslated( position.x, position.y, position.z);
		glMultMatrixf(rotMatrix);

		[self drawEntity:immediate :translucent];

		glPopMatrix();
	}
}

- (void) reloadTextures
{
#ifdef WIN32
    int fi;

	// Force the entity to reload the textures for each face by clearing the face's texture name.
    for (fi = 0; fi < n_faces; fi++)
        faces[fi].texName = 0;

	// Force the display list to be regenerated next time a frame is drawn.
	[self regenerateDisplayList];
#endif
}


- (void) initialiseTextures
{
    // roll out each face and texture in turn
    //
    int fi,ti ;

	if (!UNIVERSE)
		return;

    for (fi = 0; fi < n_faces; fi++)
    {
		NSString* texture = [NSString stringWithUTF8String:(char*)faces[fi].textureFileStr255];
        if ((faces[fi].texName == 0)&&(texture))
        {
			 faces[fi].texName = [TextureStore getTextureNameFor: texture];
        }
    }

	for (ti = 1; ti <= n_textures; ti++)
	{
		if (!texture_name[ti])
		{
			texture_name[ti] = [TextureStore getTextureNameFor: [NSString stringWithUTF8String: (char*)texture_file[ti]]];
		}
	}
}

- (void) regenerateDisplayList
{
	glDeleteLists(displayListName,1);
	displayListName = 0;
}

- (void) generateDisplayList
{
	displayListName = glGenLists(1);
	if (displayListName != 0)
	{
		glNewList(displayListName, GL_COMPILE);
		[self drawEntity:YES:NO];	//	immediate YES	translucent NO
		glEndList();
		//
		CheckOpenGLErrors([NSString stringWithFormat:@"Entity after generateDisplayList for %@", self]);
		//
	}
}

- (void) update:(double) delta_t
{
	PlayerEntity *player = [PlayerEntity sharedPlayer];
	if (player)
	{
		if (status != STATUS_COCKPIT_DISPLAY)
			relativePosition = vector_between( player->position, position);
		else
			relativePosition = position;
		//
		zero_distance = magnitude2( relativePosition);
	}
	else
		zero_distance = -1;

	hasMoved = ((position.x != lastPosition.x)||(position.y != lastPosition.y)||(position.z != lastPosition.z));
	lastPosition = position;
	hasRotated = ((q_rotation.w != lastQRotation.w)||(q_rotation.x != lastQRotation.x)||(q_rotation.y != lastQRotation.y)||(q_rotation.z != lastQRotation.z));
	lastQRotation = q_rotation;
}

- (void) saveToLastFrame
{
	double t_now = [UNIVERSE getTime];
	if (t_now >= trackTime + 0.1)		// update every 1/10 of a second
	{
		// save previous data
		trackTime = t_now;
		track[trackIndex].position =	position;
		track[trackIndex].q_rotation =	q_rotation;
		track[trackIndex].timeframe =	trackTime;
		track[trackIndex].k =	vector_forward_from_quaternion(q_rotation);
		trackIndex = (trackIndex + 1 ) & 0xff;
	}
}

- (void) savePosition:(Vector)pos atTime:(double)t_time atIndex:(int)t_index
{
	trackTime = t_time;
	track[t_index].position = pos;
	track[t_index].timeframe =	t_time;
	trackIndex = (t_index + 1 ) & 0xff;
}

- (void) saveFrame:(Frame)frame atIndex:(int)t_index
{
	track[t_index] = frame;
	trackTime = frame.timeframe;
	trackIndex = (t_index + 1 ) & 0xff;
}

// reset frames
//
- (void) resetFramesFromFrame:(Frame) resetFrame withVelocity:(Vector) vel1
{
	Vector		v1 = make_vector( 0.1 * vel1.x, 0.1 * vel1.y, 0.1 * vel1.z);
	double		t_now = [UNIVERSE getTime];
	Vector		pos = resetFrame.position;
	Vector		vk = resetFrame.k;
	Quaternion	qr = resetFrame.q_rotation;
	int i;
	for (i = 0; i < 256; i++)
	{
		track[255-i].position = make_vector(pos.x - i * v1.x, pos.y - i * v1.y, pos.z - i * v1.z);
		track[255-i].timeframe = t_now - 0.1 * i;
		track[255-i].q_rotation = qr;
		track[255-i].k = vk;
	}
	trackTime = t_now;
	trackIndex = 0;
}

- (BOOL) resetToTime:(double) t_frame	// timeframe is relative to now ie. -0.5 = half a second ago.
{
	if (t_frame >= 0)
		return NO;

	Frame	selectedFrame = [self frameAtTime:t_frame];
	[self setPosition:selectedFrame.position];
	[self setQRotation:selectedFrame.q_rotation];
	return YES;
}

- (Frame) frameAtTime:(double) t_frame	// t_frame is relative to now ie. -0.5 = half a second ago.
{
	Frame result;
	result.position = position;
	result.q_rotation = q_rotation;
	result.timeframe = [UNIVERSE getTime];
	result.k = vector_forward_from_quaternion(q_rotation);
	//
	if (t_frame >= 0.0)
		return result;
	//
	double moment_in_time = [UNIVERSE getTime] + t_frame;
	if (moment_in_time >= trackTime)					// between the last saved frame and now
	{
		int t1 = (trackIndex - 1)&0xff;	// last saved moment
		double period = result.timeframe - trackTime;
		double f0 = (result.timeframe - moment_in_time)/period;
		double f1 = 1.0 - f0;
		Vector posn;
		posn.x =	f0 * result.position.x + f1 * track[t1].position.x;
		posn.y =	f0 * result.position.y + f1 * track[t1].position.y;
		posn.z =	f0 * result.position.z + f1 * track[t1].position.z;
		Quaternion qrot;
		qrot.w =	f0 * result.q_rotation.w + f1 * track[t1].q_rotation.w;
		qrot.x =	f0 * result.q_rotation.x + f1 * track[t1].q_rotation.x;
		qrot.y =	f0 * result.q_rotation.y + f1 * track[t1].q_rotation.y;
		qrot.z =	f0 * result.q_rotation.z + f1 * track[t1].q_rotation.z;
		result.position = posn;
		result.q_rotation = qrot;
		result.timeframe = moment_in_time;
		result.k = vector_forward_from_quaternion(qrot);
		return result;
	}
	//
	if (moment_in_time < track[trackIndex].timeframe)	// more than 256 frames back
	{
		return track[trackIndex];
	}
	//
	int t1 = (trackIndex - 1)&0xff;
	while (moment_in_time < track[t1].timeframe)
		t1 = (t1 - 1) & 0xff;
	int t0 = (t1 + 1) & 0xff;
	// interpolate between t0 and t1
	double period = track[0].timeframe - track[1].timeframe;
	double f0 = (track[t0].timeframe - moment_in_time)/period;
	double f1 = 1.0 - f0;
	Vector posn;
	posn.x =	f0 * track[t0].position.x + f1 * track[t1].position.x;
	posn.y =	f0 * track[t0].position.y + f1 * track[t1].position.y;
	posn.z =	f0 * track[t0].position.z + f1 * track[t1].position.z;
	Quaternion qrot;
	qrot.w =	f0 * track[t0].q_rotation.w + f1 * track[t1].q_rotation.w;
	qrot.x =	f0 * track[t0].q_rotation.x + f1 * track[t1].q_rotation.x;
	qrot.y =	f0 * track[t0].q_rotation.y + f1 * track[t1].q_rotation.y;
	qrot.z =	f0 * track[t0].q_rotation.z + f1 * track[t1].q_rotation.z;
	result.position = posn;
	result.q_rotation = qrot;
	result.timeframe = moment_in_time;
	result.k = vector_forward_from_quaternion(qrot);
	return result;
}

- (Frame) frameAtTime:(double) t_frame fromFrame:(Frame) frame_zero	// t_frame is relative to now ie. -0.5 = half a second ago.
{
	Frame result = frame_zero;
	//
	if (t_frame >= 0.0)
		return result;
	//
	double moment_in_time = [UNIVERSE getTime] + t_frame;
	if (moment_in_time > trackTime)					// between the last saved frame and now
	{
		Frame fr1 = track[(trackIndex - 1)&0xff];	// last saved moment
		double period = (moment_in_time - t_frame) - trackTime;
		double f1 =	-t_frame/period;
		double f0 =	1.0 - f1;
		
		Vector posn;
		posn.x =	f0 * result.position.x + f1 * fr1.position.x;
		posn.y =	f0 * result.position.y + f1 * fr1.position.y;
		posn.z =	f0 * result.position.z + f1 * fr1.position.z;
		Quaternion qrot;
		qrot.w =	f0 * result.q_rotation.w + f1 * fr1.q_rotation.w;
		qrot.x =	f0 * result.q_rotation.x + f1 * fr1.q_rotation.x;
		qrot.y =	f0 * result.q_rotation.y + f1 * fr1.q_rotation.y;
		qrot.z =	f0 * result.q_rotation.z + f1 * fr1.q_rotation.z;
		result.position = posn;
		result.q_rotation = qrot;
		result.timeframe = moment_in_time;
		result.k = vector_forward_from_quaternion(qrot);
		return result;
	}
	//
	if (moment_in_time < track[trackIndex].timeframe)	// more than 256 frames back
	{
		return track[trackIndex];
	}
	//
	int t1 = (trackIndex - 1)&0xff;
	while (moment_in_time < track[t1].timeframe)
		t1 = (t1 - 1) & 0xff;
	int t0 = (t1 + 1) & 0xff;
	// interpolate between t0 and t1
	double period = track[t0].timeframe - track[t1].timeframe;
	double f0 = (moment_in_time - track[t1].timeframe)/period;
	double f1 = 1.0 - f0;
	
	Vector posn;
	posn.x =	f0 * track[t0].position.x + f1 * track[t1].position.x;
	posn.y =	f0 * track[t0].position.y + f1 * track[t1].position.y;
	posn.z =	f0 * track[t0].position.z + f1 * track[t1].position.z;
	Quaternion qrot;
	qrot.w =	f0 * track[t0].q_rotation.w + f1 * track[t1].q_rotation.w;
	qrot.x =	f0 * track[t0].q_rotation.x + f1 * track[t1].q_rotation.x;
	qrot.y =	f0 * track[t0].q_rotation.y + f1 * track[t1].q_rotation.y;
	qrot.z =	f0 * track[t0].q_rotation.z + f1 * track[t1].q_rotation.z;
	result.position = posn;
	result.q_rotation = qrot;
	result.timeframe = moment_in_time;
	result.k = vector_forward_from_quaternion(qrot);
	return result;
}

- (NSDictionary*) modelData
{
	NSMutableDictionary*	mdict = [NSMutableDictionary dictionaryWithCapacity:8];
	[mdict setObject:[NSNumber numberWithInt: n_vertices]	forKey:@"n_vertices"];
	[mdict setObject:[NSData dataWithBytes: vertices		length: sizeof(Vector)*n_vertices]	forKey:@"vertices"];
	[mdict setObject:[NSData dataWithBytes: vertex_normal	length: sizeof(Vector)*n_vertices]	forKey:@"normals"];
	[mdict setObject:[NSNumber numberWithInt: n_faces] forKey:@"n_faces"];
	[mdict setObject:[NSData dataWithBytes: faces			length: sizeof(Face)*n_faces]		forKey:@"faces"];
	return [NSDictionary dictionaryWithDictionary:mdict];
}

- (BOOL) setModelFromModelData:(NSDictionary*) dict
{
	n_vertices = [[dict objectForKey:@"n_vertices"] intValue];
	n_faces = [[dict objectForKey:@"n_faces"] intValue];
	NSData* vdata = (NSData*)[dict objectForKey:@"vertices"];
	NSData* ndata = (NSData*)[dict objectForKey:@"normals"];
	NSData* fdata = (NSData*)[dict objectForKey:@"faces"];
	if ((vdata) && (ndata) && (fdata))
	{
		Vector* vbytes = (Vector*)[vdata bytes];
		Vector* nbytes = (Vector*)[ndata bytes];
		Face* fbytes = (Face*)[fdata bytes];
		int i;
		for (i = 0; i < n_vertices; i++)
		{
			vertices[i] = vbytes[i];
			vertex_normal[i] = nbytes[i];
		}
		for (i = 0; i < n_faces; i++)
		{
			faces[i] = fbytes[i];
		}
		return YES;
	}
	else
	{
		return NO;
	}
}

- (void) loadData:(NSString *) filename
{
    NSScanner			*scanner;
	NSDictionary		*cacheData = nil;
    NSString			*data = nil;
    NSMutableArray		*lines;
    BOOL				failFlag = NO;
    NSString			*failString = @"***** ";
    int					i, j;

	BOOL using_preloaded = NO;
	
	// TODO: rejigger this to look for the file and check modification date.
	cacheData = [OOCacheManager meshDataForName:filename];
	if (cacheData != nil)
	{
		if ([self setModelFromModelData:cacheData]) using_preloaded = YES;
	}
	
	if (!using_preloaded)
	{
		data = [ResourceManager stringFromFilesNamed:filename inFolder:@"Models"];
		if (data == nil)
		{
			// Model not found
			OOLog(kOOLogEntityDataNotFound, @"ERROR - could not find %@", filename);
			NSException* myException = [NSException
				exceptionWithName: OOLITE_EXCEPTION_DATA_NOT_FOUND
				reason:[NSString stringWithFormat:@"No data for model called '%@' could be found in %@.", filename, [ResourceManager paths]]
				userInfo:nil];
			[myException raise];
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
		if ([scanner scanString:@"NVERTS" intoString:(NSString **)nil])
		{
			int n_v;
			if ([scanner scanInt:&n_v])
				n_vertices = n_v;
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

		if (n_vertices > MAX_VERTICES_PER_ENTITY)
		{
			OOLog(kOOLogEntityTooManyVertices, @"ERROR - model %@ has too many vertices (model has %d, maximum is %d)", filename, n_vertices, MAX_VERTICES_PER_ENTITY);
			failFlag = YES;
			// ERROR model file not found
			NSException* myException = [NSException
				exceptionWithName:@"OoliteException"
				reason:[NSString stringWithFormat:@"ERROR - model %@ has too many vertices (model has %d, maximum is %d)", filename, n_vertices, MAX_VERTICES_PER_ENTITY]
				userInfo:nil];
			[myException raise];
		}

		// get number of faces
		//
		//[scanner setScanLocation:0];	//reset
		if ([scanner scanString:@"NFACES" intoString:(NSString **)nil])
		{
			int n_f;
			if ([scanner scanInt:&n_f])
				n_faces = n_f;
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

		if (n_faces > MAX_FACES_PER_ENTITY)
		{
			OOLog(kOOLogEntityTooManyFaces, @"ERROR - model %@ has too many faces (model has %d, maximum is %d)", filename, n_faces, MAX_FACES_PER_ENTITY);
			failFlag = YES;
			// ERROR model file not found
			NSException* myException = [NSException
				exceptionWithName:@"OoliteException"
				reason:[NSString stringWithFormat:@"ERROR - model %@ has too many faces (model has %d, maximum is %d)", filename, n_faces, MAX_FACES_PER_ENTITY]
				userInfo:nil];
			[myException raise];
		}

		// get vertex data
		//
		//[scanner setScanLocation:0];	//reset
		if ([scanner scanString:@"VERTEX" intoString:(NSString **)nil])
		{
			for (j = 0; j < n_vertices; j++)
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
		if ([scanner scanString:@"FACES" intoString:(NSString **)nil])
		{
			for (j = 0; j < n_faces; j++)
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
						faces[j].red = r/255.0;    faces[j].green = g/255.0;    faces[j].blue = b/255.0;
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
						faces[j].normal.x = nx;    faces[j].normal.y = ny;    faces[j].normal.z = nz;
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
		if ([scanner scanString:@"TEXTURES" intoString:(NSString **)nil])
		{
			for (j = 0; j < n_faces; j++)
			{
				NSString	*texfile;
				float	max_x, max_y;
				float	s, t;
				if (!failFlag)
				{
					// texfile
					//
					[scanner scanCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:(NSString **)nil];
					if (![scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&texfile])
					{
						failFlag = YES;
						failString = [NSString stringWithFormat:@"%@Failed to read texture filename for face[%d] in TEXTURES\n", failString, j];
					}
					else
					{
//						faces[j].textureFile = [texfile retain];
						strlcpy( (char*)faces[j].textureFileStr255, [texfile UTF8String], 256);
					}
					faces[j].texName = 0;

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
			failString = [NSString stringWithFormat:@"%@Failed to find TEXTURES data\n",failString];
		}

		

		// check normals before creating new textures
		//
		[self checkNormalsAndAdjustWinding];

		if ((failFlag)&&([failString rangeOfString:@"TEXTURES"].location != NSNotFound))
		{
			[self fakeTexturesWithImageFile:@"metal.png" andMaxSize:NSMakeSize(256.0,256.0)];
		}

		if (failFlag)
			NSLog([NSString stringWithFormat:@"%@ ..... from %@ %@", failString, filename, (using_preloaded)? @"(from preloaded data)" : @"(from file)"]);

		// check for smooth shading and recalculate normals
		if (isSmoothShaded)
			[self calculateVertexNormals];
		//

		// save the resulting data for possible reuse
		[OOCacheManager setMeshData:[self modelData] forName:filename];
	}
	
	// set the collision radius
	//
	collision_radius = [self findCollisionRadius];
	actual_radius = collision_radius;

	// set up vertex arrays for drawing
	//
	[self setUpVertexArrays];
	//
	usingVAR = [self OGL_InitVAR];
	//
	if (usingVAR)
	{
		[self OGL_AssignVARMemory:sizeof(EntityData) :(void *)&entityData :0];
	}
	//
}


// FIXME: this isn't working, we're getting smoothed models with inside-out winding. --ahruman
- (void) checkNormalsAndAdjustWinding
{
    Vector calculatedNormal;
    int i, j;
    for (i = 0; i < n_faces; i++)
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
	float	triangle_area[n_faces];
	for (i = 0 ; i < n_faces; i++)
	{
		// calculate areas using Herons formula
		// in the form Area = sqrt(2*(a2*b2+b2*c2+c2*a2)-(a4+b4+c4))/4
		float	a2 = distance2( vertices[faces[i].vertex[0]], vertices[faces[i].vertex[1]]);
		float	b2 = distance2( vertices[faces[i].vertex[1]], vertices[faces[i].vertex[2]]);
		float	c2 = distance2( vertices[faces[i].vertex[2]], vertices[faces[i].vertex[0]]);
		triangle_area[i] = sqrt( 2.0 * (a2 * b2 + b2 * c2 + c2 * a2) - 0.25 * (a2 * a2 + b2 * b2 +c2 * c2));
	}
	for (i = 0; i < n_vertices; i++)
	{
		Vector normal_sum = make_vector( 0.0f, 0.0f, 0.0f);
		for (j = 0; j < n_faces; j++)
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
		vertex_normal[i] = normal_sum;
	}
}

- (Vector) normalForVertex:(int) v_index withSharedRedValue:(GLfloat) red_value
{
	int j;
	Vector normal_sum = make_vector( 0.0f, 0.0f, 0.0f);
	for (j = 0; j < n_faces; j++)
	{
		if (faces[j].red == red_value)
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
	NSMutableDictionary*	texturesProcessed = [NSMutableDictionary dictionaryWithCapacity:MAX_TEXTURES_PER_ENTITY];

	int face, fi, vi, texi;

	// if isSmoothShaded find any vertices that are between faces of two different colour (by red value)
	// and mark them as being on an edge and therefore NOT smooth shaded
	BOOL is_edge_vertex[n_vertices];
	GLfloat red_value[n_vertices];
	for (vi = 0; vi < n_vertices; vi++)
	{
		is_edge_vertex[vi] = NO;
		red_value[vi] = -1;
	}
	if (isSmoothShaded)
	{
		for (fi = 0; fi < n_faces; fi++)
		{
			GLfloat rv = faces[fi].red;
			int i;
			for (i = 0; i < 3; i++)
			{
				vi = faces[fi].vertex[i];
				if (red_value[vi] < 0.0)	// unassigned
					red_value[vi] = rv;
				else if (red_value[vi] != rv)	// a different colour
					is_edge_vertex[vi] = YES;
			}
		}
	}


	// base model, flat or smooth shaded, all triangles
	int tri_index = 0;
	int uv_index = 0;
	int vertex_index = 0;
	entityData.texName = 0;

	texi = 1; // index of first texture

	for (face = 0; face < n_faces; face++)
	{
		NSString* tex_string = [NSString stringWithUTF8String: (char*)faces[face].textureFileStr255];
		if (![texturesProcessed objectForKey:tex_string])
		{
			// do this texture
			triangle_range[texi].location = tri_index;
			strlcpy( (char*)texture_file[texi], (char*)faces[face].textureFileStr255, 256);
			texture_name[texi] = faces[face].texName;

			for (fi = 0; fi < n_faces; fi++)
			{
				Vector normal = make_vector( 0.0, 0.0, 1.0);
				int v;
				if (!isSmoothShaded)
					normal = faces[fi].normal;
				if (strcmp( (char*)faces[fi].textureFileStr255, (char*)faces[face].textureFileStr255) == 0)
				{
					for (vi = 0; vi < 3; vi++)
					{
						v = faces[fi].vertex[vi];
						if (isSmoothShaded)
						{
							if (is_edge_vertex[v])
								normal = [self normalForVertex: v withSharedRedValue: faces[fi].red];
							else
								normal = vertex_normal[v];
						}
						else
							normal = faces[fi].normal;
						entityData.index_array[tri_index++] = vertex_index;
						entityData.normal_array[vertex_index] = normal;
						entityData.vertex_array[vertex_index++] = vertices[v];
						entityData.texture_uv_array[uv_index++] = faces[fi].s[vi];
						entityData.texture_uv_array[uv_index++] = faces[fi].t[vi];
					}
				}
			}
			triangle_range[texi].length = tri_index - triangle_range[texi].location;

			//finally...
			[texturesProcessed setObject:tex_string forKey:tex_string];	// note this texture done
			texi++;
		}
	}
	entityData.n_triangles = tri_index;	// total number of triangle vertices
	triangle_range[0] = NSMakeRange( 0, tri_index);

	n_textures = texi - 1;
}





- (double) findCollisionRadius
{
    int i;
	double d_squared, result, length_longest_axis, length_shortest_axis;

	result = 0.0;
	if (n_vertices)
		bounding_box_reset_to_vector(&boundingBox,vertices[0]);
	else
		bounding_box_reset(&boundingBox);

    for (i = 0; i < n_vertices; i++)
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
	no_draw_distance = d_squared * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR;	// no longer based on the collision radius

	mass =	(boundingBox.max.x - boundingBox.min.x) * (boundingBox.max.y - boundingBox.min.y) * (boundingBox.max.z - boundingBox.min.z);

	return sqrt(result);
}


- (BoundingBox) findBoundingBoxRelativeTo:(Entity *)other InVectors:(Vector) _i :(Vector) _j :(Vector) _k
{
	NSLog(@"DEBUG ** DEPRECATED [Entity findBoundingBoxRelativeTo:(Entity *)other InVectors:(Vector) _i :(Vector) _j :(Vector) _k] CALLED **");

	Vector pv, rv;
	Vector  rpos = position;
	Vector  opv = (other)? other->position : rpos;
	rpos.x -= opv.x;	rpos.y -= opv.y;	rpos.z -= opv.z;
	rv.x = dot_product(_i,rpos);
	rv.y = dot_product(_j,rpos);
	rv.z = dot_product(_k,rpos);
	BoundingBox result;
	bounding_box_reset_to_vector(&result,rv);
	int i;
    for (i = 0; i < n_vertices; i++)
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

- (BoundingBox) findBoundingBoxRelativeToPosition:(Vector)opv InVectors:(Vector) _i :(Vector) _j :(Vector) _k
{

	Vector pv, rv;
	Vector  rpos = position;
	rpos.x -= opv.x;	rpos.y -= opv.y;	rpos.z -= opv.z;
	rv.x = dot_product(_i,rpos);
	rv.y = dot_product(_j,rpos);
	rv.z = dot_product(_k,rpos);
	BoundingBox result;
	bounding_box_reset_to_vector(&result,rv);
	int i;
    for (i = 0; i < n_vertices; i++)
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

- (BOOL) checkCloseCollisionWith:(Entity *)other
{
	return YES;
}



- (void) takeEnergyDamage:(double) amount from:(Entity *) ent becauseOf:(Entity *) other
{
}

- (NSString *) toString
{
    // produce a file from the original data
    int i,j, r,g,b;
    NSString *result;
    NSString *boilerplate = @"# This is a file adapted from the model files for Java Elite\n# which in turn are based on the data released by Ian Bell\n# in the file b7051600.zip at\n# http://www.users.waitrose.com/~elitearc2/elite/archive/b7051600.zip\n#";
    result = [NSString stringWithFormat:@"%@\n# %@\n#\n\nNVERTS %d\nNFACES %d\n\nVERTEX\n", boilerplate, basefile, n_vertices, n_faces];
    for (i = 0; i < n_vertices; i++)
    {
        result = [NSString stringWithFormat:@"%@%f,\t%f,\t%f\n", result, vertices[i].x, vertices[i].y, vertices[i].z];
        if ((i % 5)==4)
            result = [NSString stringWithFormat:@"%@\n", result];
    }
    result = [NSString stringWithFormat:@"%@\nFACES\n", result];
	
    for (j = 0; j < n_faces; j++)
    {
        r = (int)(faces[j].red * 255.0);	g = (int)(faces[j].green * 255.0);	b = (int)(faces[j].blue * 255.0);
        result = [NSString stringWithFormat:@"%@%d, %d, %d,\t", result, r, g, b];
        result = [NSString stringWithFormat:@"%@%f, %f, %f,\t", result, faces[j].normal.x, faces[j].normal.y, faces[j].normal.z];
        result = [NSString stringWithFormat:@"%@%d,\t", result, faces[j].n_verts];
        for (i = 0; i < faces[j].n_verts; i++)
        {
            result = [NSString stringWithFormat:@"%@%d ", result, faces[j].vertex[i]];
        }
        result = [NSString stringWithFormat:@"%@\n", result];
    }
    if (UNIVERSE)
    {
        result = [NSString stringWithFormat:@"%@\nTEXTURES\n", result];
        for (j = 0; j < n_faces; j++)
        {
//            NSSize	texSize = [TextureStore getSizeOfTexture:faces[j].textureFile];
//            result = [NSString stringWithFormat:@"%@%@\t%d %d", result, faces[j].textureFile, (int)texSize.width, (int)texSize.height];
			NSString* texture = [NSString stringWithUTF8String: (char*)faces[j].textureFileStr255];
            NSSize	texSize = [TextureStore getSizeOfTexture: texture];
            result = [NSString stringWithFormat:@"%@%@\t%d %d", result, texture, (int)texSize.width, (int)texSize.height];
            for (i = 0; i < faces[j].n_verts; i++)
            {
                int s = (int)(faces[j].s[i] * texSize.width);
                int t = (int)(faces[j].t[i] * texSize.height);
                result = [NSString stringWithFormat:@"%@\t%d %d", result, s, t];
            }
            result = [NSString stringWithFormat:@"%@\n", result];
        }
    }
    result = [NSString stringWithFormat:@"%@\nEND\n", result];

    return result;
}

- (void) fakeTexturesWithImageFile: (NSString *) textureFile andMaxSize:(NSSize) maxSize
{
    int i, j, k;
    Vector vec;
    int nf = 0;
    int		fi[MAX_FACES_PER_ENTITY];
    float	max_s, min_s, max_t, min_t, st_width, st_height;
    float	tolerance;
    Face	fa[MAX_FACES_PER_ENTITY];
    int		faces_to_match;
    BOOL	face_matched[MAX_FACES_PER_ENTITY];

    tolerance = 1.00;
    faces_to_match = n_faces;
    for (i = 0; i < n_faces; i++)
    {
	    face_matched[i] = NO;
    }
	while (faces_to_match > 0)
    {
        tolerance -= 0.05;

        // Top (+y) first
        vec.x = 0.0;	vec.y = 1.0;	vec.z = 0.0;
        // build list of faces that face in that direction...
        nf = 0;
        max_s = -999999.0; min_s = 999999.0;
        max_t = -999999.0; min_t = 999999.0;
        for (i = 0; i < n_faces; i++)
        {
            float s, t;
            float g = dot_product(vec, faces[i].normal) * sqrt(2.0);
            if ((g >= tolerance)&&(!face_matched[i]))
            {
                fi[nf++] = i;
                face_matched[i] = YES;
                faces_to_match--;
                for (j = 0; j < faces[i].n_verts; j++)
                {
                    s = vertices[faces[i].vertex[j]].x;
                    t = vertices[faces[i].vertex[j]].z;
                    max_s = (max_s > s) ? max_s:s ;	min_s = (min_s < s) ? min_s:s ;
                    max_t = (max_t > t) ? max_t:t ;	min_t = (min_t < t) ? min_t:t ;
                }
            }
        }
        //
        st_width = max_s - min_s;
        st_height = max_t - min_t;
		
        for (j = 0; j < nf; j++)
        {
            i = fi[j];
			
			strlcpy( (char*)fa[i].textureFileStr255, [[NSString stringWithFormat:@"top_%@", textureFile] UTF8String], 256);
            for (k = 0; k < faces[i].n_verts; k++)
            {
                float s, t;
                s = vertices[faces[i].vertex[k]].x;
                t = vertices[faces[i].vertex[k]].z;
                fa[i].s[k] = (s - min_s) * maxSize.width / st_width;
                fa[i].t[k] = (t - min_t) * maxSize.height / st_height;
				//
				// TESTING
				//
				fa[i].t[k] = maxSize.height - fa[i].t[k];	// REVERSE t locations
            }
        }

        // Bottom (-y)
        vec.x = 0.0;	vec.y = -1.0;	vec.z = 0.0;
        // build list of faces that face in that direction...
        nf = 0;
        max_s = -999999.0; min_s = 999999.0;
        max_t = -999999.0; min_t = 999999.0;
        for (i = 0; i < n_faces; i++)
        {
            float s, t;
            float g = dot_product(vec, faces[i].normal) * sqrt(2.0);
            if ((g >= tolerance)&&(!face_matched[i]))
            {
                fi[nf++] = i;
                face_matched[i] = YES;
                faces_to_match--;
                for (j = 0; j < faces[i].n_verts; j++)
                {
                    s = -vertices[faces[i].vertex[j]].x;
                    t = -vertices[faces[i].vertex[j]].z;
                    max_s = (max_s > s) ? max_s:s ;	min_s = (min_s < s) ? min_s:s ;
                    max_t = (max_t > t) ? max_t:t ;	min_t = (min_t < t) ? min_t:t ;
                }
            }
        }
        st_width = max_s - min_s;
        st_height = max_t - min_t;
        for (j = 0; j < nf; j++)
        {
            i = fi[j];
            //fa[i] = faces[i];
//            fa[i].textureFile = [NSString stringWithFormat:@"bottom_%@", textureFile];
//			strlcpy( (char*)fa[i].textureFileStr255, [fa[i].textureFile UTF8String], 256);
			strlcpy( (char*)fa[i].textureFileStr255, [[NSString stringWithFormat:@"bottom_%@", textureFile] UTF8String], 256);
            for (k = 0; k < faces[i].n_verts; k++)
            {
                float s, t;
                s = -vertices[faces[i].vertex[k]].x;
                t = -vertices[faces[i].vertex[k]].z;
                fa[i].s[k] = (s - min_s) * maxSize.width / st_width;
                fa[i].t[k] = (t - min_t) * maxSize.height / st_height;
            }
        }

        // Right (+x)
        vec.x = 1.0;	vec.y = 0.0;	vec.z = 0.0;
        // build list of faces that face in that direction...
        nf = 0;
        max_s = -999999.0; min_s = 999999.0;
        max_t = -999999.0; min_t = 999999.0;
        for (i = 0; i < n_faces; i++)
        {
            float s, t;
            float g = dot_product(vec, faces[i].normal) * sqrt(2.0);
            if ((g >= tolerance)&&(!face_matched[i]))
            {
                fi[nf++] = i;
                face_matched[i] = YES;
                faces_to_match--;
                for (j = 0; j < faces[i].n_verts; j++)
                {
                    s = vertices[faces[i].vertex[j]].z;
                    t = vertices[faces[i].vertex[j]].y;
                    max_s = (max_s > s) ? max_s:s ;	min_s = (min_s < s) ? min_s:s ;
                    max_t = (max_t > t) ? max_t:t ;	min_t = (min_t < t) ? min_t:t ;
                }
            }
        }
        st_width = max_s - min_s;
        st_height = max_t - min_t;
        for (j = 0; j < nf; j++)
        {
            i = fi[j];
            //fa[i] = faces[i];
//            fa[i].textureFile = [NSString stringWithFormat:@"right_%@", textureFile];
//			strlcpy( (char*)fa[i].textureFileStr255, [fa[i].textureFile UTF8String], 256);
			strlcpy( (char*)fa[i].textureFileStr255, [[NSString stringWithFormat:@"right_%@", textureFile] UTF8String], 256);
            for (k = 0; k < faces[i].n_verts; k++)
            {
                float s, t;
                s = vertices[faces[i].vertex[k]].z;
                t = vertices[faces[i].vertex[k]].y;
                fa[i].s[k] = (s - min_s) * maxSize.width / st_width;
                fa[i].t[k] = (t - min_t) * maxSize.height / st_height;
            }
        }

        // Left (-x)
        vec.x = -1.0;	vec.y = 0.0;	vec.z = 0.0;
        // build list of faces that face in that direction...
        nf = 0;
        max_s = -999999.0; min_s = 999999.0;
        max_t = -999999.0; min_t = 999999.0;
        for (i = 0; i < n_faces; i++)
        {
            float s, t;
            float g = dot_product(vec, faces[i].normal) * sqrt(2.0);
            if ((g >= tolerance)&&(!face_matched[i]))
            {
                fi[nf++] = i;
                face_matched[i] = YES;
                faces_to_match--;
                for (j = 0; j < faces[i].n_verts; j++)
                {
                    s = -vertices[faces[i].vertex[j]].z;
                    t = -vertices[faces[i].vertex[j]].y;
                    max_s = (max_s > s) ? max_s:s ;	min_s = (min_s < s) ? min_s:s ;
                    max_t = (max_t > t) ? max_t:t ;	min_t = (min_t < t) ? min_t:t ;
                }
            }
        }
        st_width = max_s - min_s;
        st_height = max_t - min_t;
        for (j = 0; j < nf; j++)
        {
            i = fi[j];
            //fa[i] = faces[i];
//            fa[i].textureFile = [NSString stringWithFormat:@"left_%@", textureFile];
//			strlcpy( (char*)fa[i].textureFileStr255, [fa[i].textureFile UTF8String], 256);
			strlcpy( (char*)fa[i].textureFileStr255, [[NSString stringWithFormat:@"left_%@", textureFile] UTF8String], 256);
            for (k = 0; k < faces[i].n_verts; k++)
            {
                float s, t;
                s = -vertices[faces[i].vertex[k]].z;
                t = -vertices[faces[i].vertex[k]].y;
                fa[i].s[k] = (s - min_s) * maxSize.width / st_width;
                fa[i].t[k] = (t - min_t) * maxSize.height / st_height;
            }
        }

        // Front (+z)
        vec.x = 0.0;	vec.y = 0.0;	vec.z = 1.0;
        // build list of faces that face in that direction...
        nf = 0;
        max_s = -999999.0; min_s = 999999.0;
        max_t = -999999.0; min_t = 999999.0;
        for (i = 0; i < n_faces; i++)
        {
            float s, t;
            float g = dot_product(vec, faces[i].normal) * sqrt(2.0);
            if ((g >= tolerance)&&(!face_matched[i]))
            {
                fi[nf++] = i;
                face_matched[i] = YES;
                faces_to_match--;
                for (j = 0; j < faces[i].n_verts; j++)
                {
                    s = vertices[faces[i].vertex[j]].x;
                    t = vertices[faces[i].vertex[j]].y;
                    max_s = (max_s > s) ? max_s:s ;	min_s = (min_s < s) ? min_s:s ;
                    max_t = (max_t > t) ? max_t:t ;	min_t = (min_t < t) ? min_t:t ;
                }
            }
        }
        st_width = max_s - min_s;
        st_height = max_t - min_t;
        for (j = 0; j < nf; j++)
        {
            i = fi[j];
            //fa[i] = faces[i];
//            fa[i].textureFile = [NSString stringWithFormat:@"front_%@", textureFile];
//			strlcpy( (char*)fa[i].textureFileStr255, [fa[i].textureFile UTF8String], 256);
			strlcpy( (char*)fa[i].textureFileStr255, [[NSString stringWithFormat:@"front_%@", textureFile] UTF8String], 256);
            for (k = 0; k < faces[i].n_verts; k++)
            {
                float s, t;
                s = vertices[faces[i].vertex[k]].x;
                t = vertices[faces[i].vertex[k]].y;
                fa[i].s[k] = (s - min_s) * maxSize.width / st_width;
                fa[i].t[k] = (t - min_t) * maxSize.height / st_height;
            }
        }

        // Back (-z)
        vec.x = 0.0;	vec.y = 0.0;	vec.z = -1.0;
        // build list of faces that face in that direction...
        nf = 0;
        max_s = -999999.0; min_s = 999999.0;
        max_t = -999999.0; min_t = 999999.0;
        for (i = 0; i < n_faces; i++)
        {
            float s, t;
            float g = dot_product(vec, faces[i].normal) * sqrt(2.0);
            if ((g >= tolerance)&&(!face_matched[i]))
            {
                fi[nf++] = i;
                face_matched[i] = YES;
                faces_to_match--;
                for (j = 0; j < faces[i].n_verts; j++)
                {
                    s = -vertices[faces[i].vertex[j]].x;
                    t = -vertices[faces[i].vertex[j]].y;
                    max_s = (max_s > s) ? max_s:s ;	min_s = (min_s < s) ? min_s:s ;
                    max_t = (max_t > t) ? max_t:t ;	min_t = (min_t < t) ? min_t:t ;
                }
            }
        }
        st_width = max_s - min_s;
        st_height = max_t - min_t;
        for (j = 0; j < nf; j++)
        {
            i = fi[j];
            //fa[i] = faces[i];
//            fa[i].textureFile = [NSString stringWithFormat:@"back_%@", textureFile];
//			strlcpy( (char*)fa[i].textureFileStr255, [fa[i].textureFile UTF8String], 256);
			strlcpy( (char*)fa[i].textureFileStr255, [[NSString stringWithFormat:@"back_%@", textureFile] UTF8String], 256);
            for (k = 0; k < faces[i].n_verts; k++)
            {
                float s, t;
                s = -vertices[faces[i].vertex[k]].x;
                t = -vertices[faces[i].vertex[k]].y;
                fa[i].s[k] = (s - min_s) * maxSize.width / st_width;
                fa[i].t[k] = (t - min_t) * maxSize.height / st_height;
            }
        }
    }

    for (i = 0; i < n_faces; i++)
    {
        NSString *result;
		
		strlcpy( (char*)faces[i].textureFileStr255, (char*)fa[i].textureFileStr255, 256);
		faces[i].texName = 0;
        for (j = 0; j < faces[i].n_verts; j++)
        {
            faces[i].s[j] = fa[i].s[j] / maxSize.width;
            faces[i].t[j] = fa[i].t[j] / maxSize.height;
        }
		
        result = [NSString stringWithFormat:@"%s\t%d %d", faces[i].textureFileStr255, (int)maxSize.width, (int)maxSize.height];
    }

}

// COMMON OGL STUFF

- (BOOL) OGL_InitVAR
{
	short			i;
	static char*	s;

	if (global_testForVAR)
	{
		global_testForVAR = NO;	// no need for further tests after this

		// see if we have supported hardware
		s = (char *)glGetString(GL_EXTENSIONS);	// get extensions list

		if (strstr(s, "GL_APPLE_vertex_array_range") == 0)
		{
			global_usingVAR &= NO;
			OOLog(kOOLogOpenGLExtensionsVAR, @"Vertex Array Range optimisation - not supported");
			return NO;
		}
		else
		{
			OOLog(kOOLogOpenGLExtensionsVAR, @"Vertex Array Range optimisation - supported");
			global_usingVAR |= YES;
		}
	}

	if (!global_usingVAR)
		return NO;
#ifdef GNUSTEP
   // TODO: Find out what these APPLE functions do
#else
	glGenVertexArraysAPPLE(NUM_VERTEX_ARRAY_RANGES, &gVertexArrayRangeObjects[0]);
#endif

	// INIT OUR DATA
	//
	// None of the VAR objects has been assigned to any data yet,
	// so here we just initialize our info.  We'll assign the VAR objects
	// to data later.
	//

	for (i = 0; i < NUM_VERTEX_ARRAY_RANGES; i++)
	{
		gVertexArrayRangeData[i].rangeSize		= 0;
		gVertexArrayRangeData[i].dataBlockPtr	= nil;
		gVertexArrayRangeData[i].forceUpdate	= true;
		gVertexArrayRangeData[i].activated		= false;
	}

	return YES;
}

- (void) OGL_AssignVARMemory:(long) size :(void *) data :(Byte) whichVAR
{
	if (whichVAR >= NUM_VERTEX_ARRAY_RANGES)
	{
		NSLog(@"VAR is out of range!");
		exit(-1);
	}

	gVertexArrayRangeData[whichVAR].rangeSize 		= size;
	gVertexArrayRangeData[whichVAR].dataBlockPtr 	= data;
	gVertexArrayRangeData[whichVAR].forceUpdate 	= true;
}

- (void) OGL_UpdateVAR
{
	long	size;
	Byte	i;

	for (i = 0; i < NUM_VERTEX_ARRAY_RANGES; i++)
	{
		// SEE IF THIS VAR IS USED

		size = gVertexArrayRangeData[i].rangeSize;
		if (size == 0)
			continue;


		// SEE IF VAR NEEDS UPDATING

		if (!gVertexArrayRangeData[i].forceUpdate)
			continue;

#ifdef GNUSTEP
      // TODO: find out what non-AAPL OpenGL stuff is equivalent
#else
		// BIND THIS VAR OBJECT SO WE CAN DO STUFF TO IT

		glBindVertexArrayAPPLE(gVertexArrayRangeObjects[i]);

		// SEE IF THIS IS THE FIRST TIME IN

		if (!gVertexArrayRangeData[i].activated)
		{
			glVertexArrayRangeAPPLE(size, gVertexArrayRangeData[i].dataBlockPtr);
			glVertexArrayParameteriAPPLE(GL_VERTEX_ARRAY_STORAGE_HINT_APPLE,GL_STORAGE_SHARED_APPLE);

					// you MUST call this flush to get the data primed!

			glFlushVertexArrayRangeAPPLE(size, gVertexArrayRangeData[i].dataBlockPtr);
			glEnableClientState(GL_VERTEX_ARRAY_RANGE_APPLE);
			gVertexArrayRangeData[i].activated = true;
		}

		// ALREADY ACTIVE, SO JUST UPDATING

		else
		{
			glFlushVertexArrayRangeAPPLE(size, gVertexArrayRangeData[i].dataBlockPtr);
		}
#endif

		gVertexArrayRangeData[i].forceUpdate = false;
	}
}

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

@end


static NSString * const kOOCacheMeshes = @"meshes";

@implementation OOCacheManager (Models)

+ (NSDictionary *)meshDataForName:(NSString *)inShipName
{
	return [[self sharedCache] objectForKey:inShipName inCache:kOOCacheMeshes];
}


+ (void)setMeshData:(NSDictionary *)inData forName:(NSString *)inShipName
{
	[[self sharedCache] setObject:inData forKey:inShipName inCache:kOOCacheMeshes];
}

@end
