/*

WormholeEntity.m

Oolite
Copyright (C) 2004-2011 Giles C Williams and contributors

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

#import "WormholeEntity.h"

#import "ShipEntity.h"
#import "OOSunEntity.h"
#import "OOPlanetEntity.h"
#import "PlayerEntity.h"
#import "ShipEntityLoadRestore.h"

#import "Universe.h"
#import "AI.h"
#import "OORoleSet.h"
#import "OOShipRegistry.h"
#import "OOShipGroup.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"
#import "OOLoggingExtended.h"

// Hidden interface
@interface WormholeEntity (Private)

-(id) init;

@end

// Static local functions
static void DrawWormholeCorona(GLfloat inner_radius, GLfloat outer_radius, int step, GLfloat z_distance, GLfloat *col4v1);


@implementation WormholeEntity (Private)

-(id) init
{
	if ((self = [super init]))
	{
		witch_mass = 0.0;
		shipsInTransit = [[NSMutableArray arrayWithCapacity:4] retain];
		collision_radius = 0.0;
		[self setStatus:STATUS_EFFECT];
		scanClass = CLASS_WORMHOLE;
		isWormhole = YES;
		scan_info = WH_SCANINFO_NONE;
		scan_time = 0;
		hasExitPosition = NO;
	}
	return self;
}

@end // Private interface implementation


//
// Public Wormhole Implementation
//

@implementation WormholeEntity

- (WormholeEntity*)initWithDict:(NSDictionary*)dict
{
	assert(dict != nil);

	if ((self = [self init]))
	{
		NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

		origin = RandomSeedFromString([dict oo_stringForKey:@"origin_seed"]);
		destination = RandomSeedFromString([dict oo_stringForKey:@"dest_seed"]);
		// Since these are new for 1.75.1, we must give them default values as we could be loading an old savegame
		originCoords = PointFromString( [dict oo_stringForKey:@"origin_coords" defaultValue:StringFromPoint(NSMakePoint(origin.d, origin.b))]);
		destinationCoords = PointFromString( [dict oo_stringForKey:@"dest_coords" defaultValue:StringFromPoint(NSMakePoint(destination.d, destination.b))]);

		// We only ever init from dictionary if we're loaded by the player, so
		// by definition we have been scanned
		scan_info = WH_SCANINFO_SCANNED;

		// Remember, times are stored as Ship Clock - but anything
		// saving/restoring wormholes from dictionaries should know this!
		expiry_time = [dict oo_doubleForKey:@"expiry_time"];
		arrival_time = [dict oo_doubleForKey:@"arrival_time"];
		// Since this is new for 1.75.1, we must give it a default values as we could be loading an old savegame
		estimated_arrival_time = [dict oo_doubleForKey:@"estimated_arrival_time" defaultValue:arrival_time];
		position = [dict oo_vectorForKey:@"position"];
		_misjump = [dict oo_boolForKey:@"misjump" defaultValue:NO];


		// Setup shipsInTransit
		NSArray * shipDictsArray = [dict oo_arrayForKey:@"ships"];
		NSEnumerator *shipDicts = [shipDictsArray objectEnumerator];
 		NSDictionary *currShipDict = nil;
		[shipsInTransit removeAllObjects];
		NSMutableDictionary *restoreContext = [NSMutableDictionary dictionary];
		
		while ((currShipDict = [shipDicts nextObject]) != nil)
		{
			NSDictionary *shipInfo = [currShipDict oo_dictionaryForKey:@"ship_info"];
			if (shipInfo != nil)
			{
				ShipEntity *ship = [ShipEntity shipRestoredFromDictionary:shipInfo
															  useFallback:YES
																  context:restoreContext];
				if (ship != nil)
				{
					[shipsInTransit addObject:[NSDictionary dictionaryWithObjectsAndKeys:
											   ship, @"ship",
											   [currShipDict objectForKey:@"time_delta"], @"time",
											   nil]];
				}
				else
				{
					OOLog(@"wormhole.load.warning", @"Wormhole ship \"%@\" failed to initialize - missing OXP or old-style saved wormhole data.", [shipInfo oo_stringForKey:@"ship_key"]);
				}
			}
		}
		[pool release];
	}
	return self;
}

- (WormholeEntity*) initWormholeTo:(Random_Seed) s_seed fromShip:(ShipEntity *) ship
{
	assert(ship != nil);

	if ((self = [self init]))
	{
		double		now = [PLAYER clockTimeAdjusted];
		double		distance;
		OOSunEntity	*sun = [UNIVERSE sun];
		
		_misjump = NO;
		origin = [UNIVERSE systemSeed];
		destination = s_seed;
		originCoords = [PLAYER galaxy_coordinates];
		destinationCoords = NSMakePoint(destination.d, destination.b);
		distance = distanceBetweenPlanetPositions(originCoords.x, originCoords.y, destinationCoords.x, destinationCoords.y);
		witch_mass = 200000.0; // MKW 2010.11.21 - originally the ship's mass was added twice - once here and once in suckInShip.  Instead, we give each wormhole a minimum mass.
		if ([ship isPlayer])
			witch_mass += [ship mass]; // The player ship never gets sucked in, so add its mass here.

		if (sun && ([sun willGoNova] || [sun goneNova]) && [ship mass] > 240000) 
			shrink_factor = [ship mass] / 240000; // don't allow longstanding wormholes in nova systems. (60 sec * WORMHOLE_SHRINK_RATE = 240 000)
		else
			shrink_factor = 1;
			
		collision_radius = 0.5 * M_PI * pow(witch_mass, 1.0/3.0);
		expiry_time = now + (witch_mass / WORMHOLE_SHRINK_RATE / shrink_factor);
		travel_time = (distance * distance * 3600); // Taken from PlayerEntity.h
		arrival_time = now + travel_time;
		estimated_arrival_time = arrival_time;
		position = [ship position];
		zero_distance = distance2([PLAYER position], position);
	}	
	return self;
}


- (void) setMisjump
{
	// Test for misjump first - it's entirely possibly that the wormhole
	// has already been marked for misjumping when another ship enters it.
	if (!_misjump)
	{
		double distance = distanceBetweenPlanetPositions(originCoords.x, originCoords.y, destinationCoords.x, destinationCoords.y);
		double time_adjust = distance * distance * (3600 - 2700); // NB: Time adjustment is calculated using original distance. Formula matches the one in [PlayerEntity witchJumpTo]
		arrival_time -= time_adjust;
		travel_time -= time_adjust;
		destinationCoords.x = (originCoords.x + destinationCoords.x) / 2;
		destinationCoords.y = (originCoords.y + destinationCoords.y) / 2;
		_misjump = YES;
	}
}


- (BOOL) withMisjump
{
	return _misjump;
}


- (BOOL) suckInShip:(ShipEntity *) ship
{
	if (!ship)
		return NO;

	double now = [PLAYER clockTimeAdjusted];

	if (now > arrival_time)
		return NO;	// far end of the wormhole!
	
	// MKW 2010.11.18 - calculate time it takes for ship to reach wormhole
	// This is for AI ships which get told to enter the wormhole even though they
	// may still be some distance from it when the player exits the system
	float d = distance(position, [ship position]);
	d -= [ship collisionRadius] + [self collisionRadius];
	if (d > 0.0f)
	{
		float afterburnerFactor = [ship hasFuelInjection] && [ship fuel] > MIN_FUEL ? [ship afterburnerFactor] : 1.0;
		float shipSpeed = [ship maxFlightSpeed] * afterburnerFactor;
		// MKW 2011.02.27 - calculate speed based on group leader, if any, to
		// try and prevent escorts from entering the wormhole before their mother.
		ShipEntity *leader = [[ship group] leader];
		if (leader && (leader != ship))
		{
			afterburnerFactor = [leader hasFuelInjection] && [leader fuel] > MIN_FUEL ? [leader afterburnerFactor] : 1.0;
			float leaderShipSpeed = [leader maxFlightSpeed] * afterburnerFactor;
			if (leaderShipSpeed < shipSpeed ) shipSpeed = leaderShipSpeed;
		}
		if (shipSpeed <= 0.0f ) shipSpeed = 0.1f;
		now += d / shipSpeed;
		if( now > expiry_time )
			return NO;
	}

	[shipsInTransit addObject:[NSDictionary dictionaryWithObjectsAndKeys:
						ship, @"ship",
						[NSNumber numberWithDouble: now + travel_time - arrival_time], @"time",
						[ship beaconCode], @"shipBeacon",	// in case a beacon code has been set, nil otherwise
						nil]];
	witch_mass += [ship mass];
	expiry_time = now + (witch_mass / WORMHOLE_SHRINK_RATE / shrink_factor);
	collision_radius = 0.5 * M_PI * pow(witch_mass, 1.0/3.0);

	[UNIVERSE addWitchspaceJumpEffectForShip:ship];
	
	// Should probably pass the wormhole, but they have no JS representation
	[ship setStatus:STATUS_ENTERING_WITCHSPACE];
	[ship doScriptEvent:OOJSID("shipWillEnterWormhole")];
	[[ship getAI] message:@"ENTERED_WITCHSPACE"];
	
	[UNIVERSE removeEntity:ship];
	[[ship getAI] clearStack];	// get rid of any preserved states
		
	return YES;
}


- (void) disgorgeShips
{
	double now = [PLAYER clockTimeAdjusted];
	int n_ships = [shipsInTransit count];
	NSMutableArray * shipsStillInTransit = [[NSMutableArray alloc] initWithCapacity:n_ships];
	
	int i;
	for (i = 0; i < n_ships; i++)
	{
		ShipEntity* ship = (ShipEntity*)[(NSDictionary*)[shipsInTransit objectAtIndex:i] objectForKey:@"ship"];
		NSString *shipBeacon = [(NSDictionary *)[shipsInTransit objectAtIndex:i] objectForKey:@"shipBeacon"];
		double	ship_arrival_time = arrival_time + [(NSNumber*)[(NSDictionary*)[shipsInTransit objectAtIndex:i] objectForKey:@"time"] doubleValue];
		double	time_passed = now - ship_arrival_time;

		if (ship_arrival_time > now)
		{
			[shipsStillInTransit addObject:[shipsInTransit objectAtIndex:i]];
		}
		else
		{
			// Only calculate exit position once so that all ships arrive from the same point
			if (!hasExitPosition)
			{
				position = [UNIVERSE getWitchspaceExitPosition];	// no need to reset PRNG.
				Quaternion	q1;
				quaternion_set_random(&q1);
				double		d1 = SCANNER_MAX_RANGE*((ranrot_rand() % 256)/256.0 - 0.5);
				if (abs(d1) < 750.0)	// no closer than 750m
					d1 += ((d1 > 0.0)? 750.0: -750.0);
				Vector		v1 = vector_forward_from_quaternion(q1);
				position.x += v1.x * d1; // randomise exit position
				position.y += v1.y * d1;
				position.z += v1.z * d1;
			}
			[ship setPosition: position];

			if (shipBeacon != nil)
			{
				[ship setBeaconCode:shipBeacon];
			}
	
			// Don't reduce bounty on misjump. Fixes #17992
			// - MKW 2011.03.10	
			if (!_misjump) [ship setBounty:[ship bounty]/2];	// adjust legal status for new system
		
			if ([ship cargoFlag] == CARGO_FLAG_FULL_PLENTIFUL)
				[ship setCargoFlag: CARGO_FLAG_FULL_SCARCE];
		
			if (now - ship_arrival_time < 2.0)
			{
				[ship witchspaceLeavingEffects]; // adds the ship to the universe with effects.
			}
			else
			{
				// arrived 2 seconds or more before the player. Rings have faded out.
				[ship setOrientation: [UNIVERSE getWitchspaceExitRotation]];
				[ship setPitch: 0.0];
				[ship setRoll: 0.0];
				[ship setSpeed: [ship maxFlightSpeed] * 0.25];
				[UNIVERSE addEntity:ship];	// AI and status get initialised here
			}

		
			// Should probably pass the wormhole, but they have no JS representation
			[ship doScriptEvent:OOJSID("shipExitedWormhole") andReactToAIMessage:@"EXITED WITCHSPACE"];
		
			// update the ships's position
			if (!hasExitPosition)
			{
				hasExitPosition = YES;
				[ship update: time_passed]; // do this only for one ship or the next ships might appear at very different locations.
				position = [ship position]; // e.g. when the player fist docks before following, time_passed is already > 10 minutes.
			}
			else if (now - ship_arrival_time > 1) // Only update the ship position if it was some time ago, otherwise we're in 'real time'.
			{
				// only update the time delay to the lead ship. Sign is not correct but updating gives a small spacial distribution.
				[ship update: (ship_arrival_time - arrival_time)];
			}
		}
	}
	[shipsInTransit release];
	shipsInTransit = shipsStillInTransit;
}

- (void) setExitPosition:(Vector)pos
{
	[self setPosition: pos];
	hasExitPosition = YES;
}

- (Random_Seed) origin
{
	return origin;
}

- (Random_Seed) destination
{
	return destination;
}

- (NSPoint) originCoordinates
{
	return originCoords;
}

- (NSPoint) destinationCoordinates
{
	return destinationCoords;
}

- (double) expiryTime
{
	return expiry_time;
}

- (double) arrivalTime
{
	return arrival_time;
}

- (double) estimatedArrivalTime
{
	return estimated_arrival_time;
}

- (double) travelTime
{
	return travel_time;
}

- (double) scanTime
{
	return scan_time;
}

- (BOOL) isScanned
{
	return scan_info > WH_SCANINFO_NONE;
}

- (void) setScannedAt:(double)p_scanTime
{
	if( scan_info == WH_SCANINFO_NONE )
	{
		scan_time = p_scanTime;
		scan_info = WH_SCANINFO_SCANNED;
	}
	// else we previously scanned this wormhole
}

- (WORMHOLE_SCANINFO) scanInfo
{
	return scan_info;
}

- (void) setScanInfo:(WORMHOLE_SCANINFO)p_scanInfo
{
	scan_info = p_scanInfo;
}

- (NSArray*) shipsInTransit
{
	return shipsInTransit;
}

- (void) dealloc
{
	[shipsInTransit release];
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	double now = [PLAYER clockTime];
	return [NSString stringWithFormat:@"destination: %@ ttl: %.2fs arrival: %@",
		_misjump ? (NSString *)@"Interstellar Space" : [UNIVERSE getSystemName:destination],
		expiry_time - now,
		ClockToString(arrival_time, false)];
}


- (NSString *) identFromShip:(ShipEntity*)ship
{
	if ([ship hasEquipmentItem:@"EQ_WORMHOLE_SCANNER"])
	{
		if ([self scanInfo] >= WH_SCANINFO_DESTINATION)
		{
			return [NSString stringWithFormat:DESC(@"wormhole-to-@"), [UNIVERSE getSystemName:destination]];
		}
		else
		{
			return DESC(@"wormhole-desc");
		}
	}
	else
	{
		OOLogERR(kOOLogInconsistentState, @"Wormhole identified when ship has no EQ_WORMHOLE_SCANNER.");
		/*
			This was previously an assertion, but a player reported hitting it.
			http://aegidian.org/bb/viewtopic.php?p=128110#p128110
			-- Ahruman 2011-01-27
		*/
		return nil;
	}

}


- (BOOL) canCollide
{
	if ([PLAYER clockTime] > arrival_time)
	{
		return NO;	// far end of the wormhole!
	}
	return (witch_mass > 0.0);
}


- (BOOL) checkCloseCollisionWith:(Entity *)other
{
	return ![other isEffect];
}


- (void) update:(OOTimeDelta) delta_t
{
	[super update:delta_t];
	
	PlayerEntity	*player = PLAYER;
	assert(player != nil);
	rotMatrix = OOMatrixForBillboard(position, [player position]);
	double now = [player clockTimeAdjusted];
	
	if (witch_mass > 0.0)
	{

		witch_mass -= WORMHOLE_SHRINK_RATE * delta_t * shrink_factor;
		if (witch_mass < 0.0)
			witch_mass = 0.0;
		collision_radius = 0.5 * M_PI * pow(witch_mass, 1.0/3.0);
		no_draw_distance = collision_radius * collision_radius * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR;
	}

	scanClass = (witch_mass > 0.0)? CLASS_WORMHOLE : CLASS_NO_DRAW;
	
	if (now > expiry_time)
	{
		//position.x = position.y = position.z = 0;
		position = kZeroVector;
		[UNIVERSE removeEntity: self];
	}
}


- (void) drawEntity:(BOOL) immediate :(BOOL) translucent
{	
	if (!UNIVERSE)
		return;
	
	if ([UNIVERSE breakPatternHide])
		return;		// DON'T DRAW DURING BREAK PATTERN
	
	if (zero_distance > no_draw_distance)
		return;	// TOO FAR AWAY TO SEE
		
	if (witch_mass < 0.0)
		return;
	
	if (collision_radius <= 0.0)
		return;
	
	if (translucent)
	{
		// for now, a simple copy of the energy bomb draw routine
		float srzd = sqrtf(zero_distance);
		
		GLfloat	color_fv[4] = { 0.0, 0.0, 1.0, 0.25};
		
		OOGL(glDisable(GL_CULL_FACE));			// face culling
		OOGL(glDisable(GL_TEXTURE_2D));
		
		OOGL(glColor4fv(color_fv));
		OOGLBEGIN(GL_TRIANGLE_FAN);
			GLDrawBallBillboard(collision_radius, 4, srzd);
		OOGLEND();
				
		DrawWormholeCorona(0.67 * collision_radius, collision_radius, 4, srzd, color_fv);
					
		OOGL(glEnable(GL_CULL_FACE));			// face culling
	}
	CheckOpenGLErrors(@"WormholeEntity after drawing %@", self);
}


static void DrawWormholeCorona(GLfloat inner_radius, GLfloat outer_radius, int step, GLfloat z_distance, GLfloat *col4v1)
{
	if (outer_radius >= z_distance) // inside the sphere
		return;
	int i;
	
	NSRange				activity = { 0.34, 1.0 };
	
	GLfloat				s0, c0, s1, c1;
	
	GLfloat				r0, r1;
	GLfloat				rv0, rv1, q;
	
	GLfloat				theta, delta, halfStep;
	
	r0 = outer_radius * z_distance / sqrt(z_distance * z_distance - outer_radius * outer_radius); 
	r1 = inner_radius * z_distance / sqrt(z_distance * z_distance - inner_radius * inner_radius); 
	
	delta = step * M_PI / 180.0f;
	halfStep = 0.5f * delta;
	theta = 0.0f;
		
	OOGLBEGIN(GL_TRIANGLE_STRIP);
		for (i = 0; i < 360; i += step )
		{
			theta += delta;
			
			rv0 = randf();
			rv1 = randf();
			
			q = activity.location + rv0 * activity.length;
			
			s0 = r0 * sinf(theta);
			c0 = r0 * cosf(theta);
			glColor4f(col4v1[0] * q, col4v1[1] * q, col4v1[2] * q, col4v1[3] * rv0);
			glVertex3f(s0, c0, 0.0);

			s1 = r1 * sinf(theta - halfStep) * 0.5 * (1.0 + rv1);
			c1 = r1 * cosf(theta - halfStep) * 0.5 * (1.0 + rv1);
			glColor4f(col4v1[0], col4v1[1], col4v1[2], 0.0);
			glVertex3f(s1, c1, 0.0);
			
		}
		// repeat last values to close
		rv0 = randf();
		rv1 = randf();
			
		q = activity.location + rv0 * activity.length;
		
		s0 = 0.0f;	// r0 * sinf(0);
		c0 = r0;	// r0 * cosf(0);
		glColor4f(col4v1[0] * q, col4v1[1] * q, col4v1[2] * q, col4v1[3] * rv0);
		glVertex3f(s0, c0, 0.0);

		s1 = r1 * sinf(halfStep) * 0.5 * (1.0 + rv1);
		c1 = r1 * cosf(halfStep) * 0.5 * (1.0 + rv1);
		glColor4f(col4v1[0], col4v1[1], col4v1[2], 0.0);
		glVertex3f(s1, c1, 0.0);
	OOGLEND();
}

- (NSDictionary *) getDict
{
	NSMutableDictionary *myDict = [NSMutableDictionary dictionary];

	[myDict setObject:StringFromRandomSeed(origin) forKey:@"origin_seed"];
	[myDict setObject:StringFromRandomSeed(destination) forKey:@"dest_seed"];
	[myDict setObject:StringFromPoint(originCoords) forKey:@"origin_coords"];
	[myDict setObject:StringFromPoint(destinationCoords) forKey:@"dest_coords"];
	// Anything converting a wormhole to a dictionary should already have 
	// modified its time to shipClock time
	[myDict oo_setFloat:(expiry_time) forKey:@"expiry_time"];
	[myDict oo_setFloat:(arrival_time) forKey:@"arrival_time"];
	[myDict oo_setFloat:(estimated_arrival_time) forKey:@"estimated_arrival_time"];
	[myDict oo_setVector:position forKey:@"position"];
	[myDict oo_setBool:_misjump forKey:@"misjump"];
	
	NSMutableArray * shipArray = [NSMutableArray arrayWithCapacity:[shipsInTransit count]];
	NSEnumerator * ships = [shipsInTransit objectEnumerator];
	NSDictionary * currShipDict = nil;
	NSMutableDictionary *context = [NSMutableDictionary dictionary];
	while ((currShipDict = [ships nextObject]) != nil)
	{
		id ship = [currShipDict objectForKey:@"ship"];
		[shipArray addObject:[NSDictionary dictionaryWithObjectsAndKeys:
							  [NSNumber numberWithDouble:[currShipDict oo_doubleForKey:@"time"]], @"time_delta",
							  [ship savedShipDictionaryWithContext:context], @"ship_info",
							  nil]];
	}
	[myDict setObject:shipArray forKey:@"ships"];

	return myDict;
}

- (NSString *) scanInfoString
{
	switch(scan_info)
	{
		case WH_SCANINFO_NONE: return @"WH_SCANINFO_NONE";
		case WH_SCANINFO_SCANNED: return @"WH_SCANINFO_SCANNED";
		case WH_SCANINFO_COLLAPSE_TIME: return @"WH_SCANINFO_COLLAPSE_TIME";
		case WH_SCANINFO_ARRIVAL_TIME: return @"WH_SCANINFO_ARRIVAL_TIME";
		case WH_SCANINFO_DESTINATION: return @"WH_SCANINFO_DESTINATION";
		case WH_SCANINFO_SHIP: return @"WH_SCANINFO_SHIP";
	}
	return @"WH_SCANINFO_UNDEFINED"; // should never get here
}

- (void)dumpSelfState
{
	[super dumpSelfState];
	OOLog(@"dumpState.wormholeEntity", @"Origin                 : %@", [UNIVERSE getSystemName:origin]);
	OOLog(@"dumpState.wormholeEntity", @"Destination            : %@", [UNIVERSE getSystemName:destination]);
	OOLog(@"dumpState.wormholeEntity", @"Expiry Time            : %@", ClockToString(expiry_time, false));
	OOLog(@"dumpState.wormholeEntity", @"Arrival Time           : %@", ClockToString(arrival_time, false));
	OOLog(@"dumpState.wormholeEntity", @"Projected Arrival Time : %@", ClockToString(estimated_arrival_time, false));
	OOLog(@"dumpState.wormholeEntity", @"Scanned Time           : %@", ClockToString(scan_time, false));
	OOLog(@"dumpState.wormholeEntity", @"Scanned State          : %@", [self scanInfoString]);

	OOLog(@"dumpState.wormholeEntity", @"Mass                   : %.2lf", witch_mass);
	OOLog(@"dumpState.wormholeEntity", @"Ships                  : %d", [shipsInTransit count]);
	unsigned i;
	for (i = 0; i < [shipsInTransit count]; ++i)
	{
		NSDictionary *shipDict = [shipsInTransit oo_dictionaryAtIndex:i];
		ShipEntity* ship = (ShipEntity*)[shipDict objectForKey:@"ship"];
		double	ship_arrival_time = arrival_time + [shipDict oo_doubleForKey:@"time"];
		OOLog(@"dumpState.wormholeEntity.ships", @"Ship %d: %@  mass %.2f  arrival time %@", i+1, ship, [ship mass], ClockToString(ship_arrival_time, false));
	}
}

@end
