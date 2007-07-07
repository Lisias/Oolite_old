/*

StationEntity.m

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

#import "StationEntity.h"
#import "ShipEntityAI.h"
#import "OOCollectionExtractors.h"
#import "OOStringParsing.h"

#import "Universe.h"
#import "HeadUpDisplay.h"

#import "PlayerEntityLegacyScriptEngine.h"
#import "PlanetEntity.h"
#import "ParticleEntity.h"

#import "AI.h"
#import "OOCharacter.h"

#import "OODebugGLDrawing.h"

#define kOOLogUnconvertedNSLog @"unclassified.StationEntity"


static NSDictionary* instructions(int station_id, Vector coords, float speed, float range, NSString* ai_message, NSString* comms_message, BOOL match_rotation);


@implementation StationEntity

- (void) acceptDistressMessageFrom:(ShipEntity *)other
{
	if (self != [UNIVERSE station])  return;
	
	int old_target = primaryTarget;
	primaryTarget = [[other getPrimaryTarget] universalID];
	[(ShipEntity *)[other getPrimaryTarget] markAsOffender:8];	// mark their card
	[self launchDefenseShip];
	primaryTarget = old_target;

}


- (int) equivalent_tech_level
{
	return equivalent_tech_level;
}


- (void) set_equivalent_tech_level:(int) value
{
	equivalent_tech_level = value;
}


- (double) port_radius
{
	return magnitude(port_position);
}


- (Vector) getPortPosition
{
	Vector result = position;
	result.x += port_position.x * v_right.x + port_position.y * v_up.x + port_position.z * v_forward.x;
	result.y += port_position.x * v_right.y + port_position.y * v_up.y + port_position.z * v_forward.y;
	result.z += port_position.x * v_right.z + port_position.y * v_up.z + port_position.z * v_forward.z;
	return result;
}


- (Vector) getBeaconPosition
{
	double buoy_distance = 10000.0;				// distance from station entrance
	Vector result = position;
	Vector v_f = vector_forward_from_quaternion(orientation);
	result.x += buoy_distance * v_f.x;
	result.y += buoy_distance * v_f.y;
	result.z += buoy_distance * v_f.z;
	return result;
}


- (double) equipment_price_factor
{
	return equipment_price_factor;
}


- (NSMutableArray *) localMarket
{
	return localMarket;
}


- (void) setLocalMarket:(NSArray *) some_market
{
	if (localMarket)
		[localMarket release];
	localMarket = [[NSMutableArray alloc] initWithArray:some_market];
}


- (NSMutableArray *) localPassengers
{
	return localPassengers;
}


- (void) setLocalPassengers:(NSArray *) some_market
{
	if (localPassengers)
		[localPassengers release];
	localPassengers = [[NSMutableArray alloc] initWithArray:some_market];
}


- (NSMutableArray *) localContracts
{
	return localContracts;
}


- (void) setLocalContracts:(NSArray *) some_market
{
	if (localContracts)
		[localContracts release];
	localContracts = [[NSMutableArray alloc] initWithArray:some_market];
}


- (NSMutableArray *) localShipyard
{
	return localShipyard;
}


- (void) setLocalShipyard:(NSArray *) some_market
{
	if (localShipyard)
		[localShipyard release];
	localShipyard = [[NSMutableArray alloc] initWithArray:some_market];
}


- (NSMutableArray *) initialiseLocalMarketWithSeed: (Random_Seed) s_seed andRandomFactor: (int) random_factor
{
	int rf = (random_factor ^ universalID) & 0xff;
	int economy = [[UNIVERSE generateSystemData:s_seed] intForKey:KEY_ECONOMY];
	if (localMarket)
		[localMarket release];
	localMarket = [[NSMutableArray alloc] initWithArray:[UNIVERSE commodityDataForEconomy:economy andStation:self andRandomFactor:rf]];
	return localMarket;
}


- (NSMutableArray *) initialiseLocalPassengersWithSeed: (Random_Seed) s_seed andRandomFactor: (int) random_factor
{
	if (localPassengers)
		[localPassengers release];
	localPassengers = [[NSMutableArray alloc] initWithArray:[UNIVERSE passengersForSystem:s_seed atTime:[[[PlayerEntity sharedPlayer] clock_number] intValue]]];
	return localPassengers;
}


- (NSMutableArray *) initialiseLocalContractsWithSeed: (Random_Seed) s_seed andRandomFactor: (int) random_factor
{
	if (localContracts)
		[localContracts release];
	localContracts = [[NSMutableArray alloc] initWithArray:[UNIVERSE contractsForSystem:s_seed atTime:[[[PlayerEntity sharedPlayer] clock_number] intValue]]];
	return localContracts;
}


- (void) setPlanet:(PlanetEntity *)planet_entity
{
	if (planet_entity)
		planet = [planet_entity universalID];
	else
		planet = NO_TARGET;
}


- (PlanetEntity *) planet
{
	return [UNIVERSE entityForUniversalID:planet];
}


- (void) sanityCheckShipsOnApproach
{
	unsigned i;
	NSArray*	ships = [shipsOnApproach allKeys];
	
	// Remove dead entities.
	// No enumerator because we mutate the dictionary.
	for (i = 0; i < [ships count]; i++)
	{
		int sid = [[ships objectAtIndex:i] intValue];
		if ((sid == NO_TARGET)||(![UNIVERSE entityForUniversalID:sid]))
		{
			[shipsOnApproach removeObjectForKey:[ships objectAtIndex:i]];
			if ([shipsOnApproach count] == 0)
				[shipAI message:@"DOCKING_COMPLETE"];
		}
	}
	
	if ([shipsOnApproach count] == 0)
	{
		last_launch_time = [UNIVERSE getTime];
		approach_spacing = 0.0;
	}
	
	ships = [shipsOnHold allKeys];
	for (i = 0; i < [ships count]; i++)
	{
		int sid = [[ships objectAtIndex:i] intValue];
		if ((sid == NO_TARGET)||(![UNIVERSE entityForUniversalID:sid]))
		{
			[shipsOnHold removeObjectForKey:[ships objectAtIndex:i]];
		}
	}
}


- (void) abortAllDockings
{
	unsigned i;
	NSArray*	ships = [shipsOnApproach allKeys];
	for (i = 0; i < [ships count]; i++)
	{
		int sid = [[ships objectAtIndex:i] intValue];
		if ([UNIVERSE entityForUniversalID:sid])
			[[(ShipEntity *)[UNIVERSE entityForUniversalID:sid] getAI] message:@"DOCKING_ABORTED"];
	}
	[shipsOnApproach removeAllObjects];
	
	ships = [shipsOnHold allKeys];
	for (i = 0; i < [ships count]; i++)
	{
		int sid = [[ships objectAtIndex:i] intValue];
		if ([UNIVERSE entityForUniversalID:sid])
			[[(ShipEntity *)[UNIVERSE entityForUniversalID:sid] getAI] message:@"DOCKING_ABORTED"];
	}
	[shipsOnHold removeAllObjects];
	
	[shipAI message:@"DOCKING_COMPLETE"];
	last_launch_time = [UNIVERSE getTime];
	approach_spacing = 0.0;
}


- (void) autoDockShipsOnApproach
{
	unsigned i;
	NSArray*	ships = [shipsOnApproach allKeys];
	for (i = 0; i < [ships count]; i++)
	{
		int sid = [(NSString *)[ships objectAtIndex:i] intValue];
		if ([UNIVERSE entityForUniversalID:sid])
			[(ShipEntity *)[UNIVERSE entityForUniversalID:sid] enterDock:self];
	}
	[shipsOnApproach removeAllObjects];
	
	ships = [shipsOnHold allKeys];
	for (i = 0; i < [ships count]; i++)
	{
		int sid = [(NSString *)[ships objectAtIndex:i] intValue];
		if ([UNIVERSE entityForUniversalID:sid])
			[(ShipEntity *)[UNIVERSE entityForUniversalID:sid] enterDock:self];
	}
	[shipsOnHold removeAllObjects];
	
	[shipAI message:@"DOCKING_COMPLETE"];
}

static NSDictionary* instructions(int station_id, Vector coords, float speed, float range, NSString* ai_message, NSString* comms_message, BOOL match_rotation)
{
	NSMutableDictionary* acc = [NSMutableDictionary dictionaryWithCapacity:8];
	[acc setObject:[NSString stringWithFormat:@"%.2f %.2f %.2f", coords.x, coords.y, coords.z] forKey:@"destination"];
	[acc setObject:[NSNumber numberWithFloat:speed] forKey:@"speed"];
	[acc setObject:[NSNumber numberWithFloat:range] forKey:@"range"];
	[acc setObject:[NSNumber numberWithInt:station_id] forKey:@"station_id"];
	[acc setObject:[NSNumber numberWithBool:match_rotation] forKey:@"match_rotation"];
	if (ai_message)
		[acc setObject:ai_message forKey:@"ai_message"];
	if (comms_message)
		[acc setObject:comms_message forKey:@"comms_message"];
	//
	return [NSDictionary dictionaryWithDictionary:acc];
}

// this routine does more than set coordinates - it provides a whole set of docking instructions and messages at each stage..
//
- (NSDictionary *) dockingInstructionsForShip:(ShipEntity *) ship
{	
	Vector		coords;
	
	int			ship_id = [ship universalID];
	NSString*   shipID = [NSString stringWithFormat:@"%d", ship_id];

	Vector launchVector = vector_forward_from_quaternion(quaternion_multiply(port_orientation, orientation));
	Vector temp = (fabsf(launchVector.x) < 0.8)? make_vector(1,0,0) : make_vector(0,1,0);
	temp = cross_product(launchVector, temp);	// 90 deg to launchVector & temp
	Vector vi = cross_product(launchVector, temp);
	Vector vj = cross_product(launchVector, vi);
	Vector vk = launchVector;
	
	if (!ship)
		return nil;
	
	if ((ship->isPlayer)&&([ship legalStatus] > 50))	// note: non-player fugitives dock as normal
	{
		// refuse docking to the fugitive player
		return instructions(universalID, ship->position, 0, 100, @"DOCKING_REFUSED", @"[station-docking-refused-to-fugitive]", NO);
	}
	
	if (no_docking_while_launching)
	{
		return instructions(universalID, ship->position, 0, 100, @"TRY_AGAIN_LATER", nil, NO);
	}
	
	[shipAI reactToMessage:@"DOCKING_REQUESTED"];	// react to the request	
	
	if	(magnitude2([self velocity]) > 1.0)		// no docking while moving
	{
		if (![shipsOnHold objectForKey:shipID])
			[self sendExpandedMessage: @"[station-acknowledges-hold-position]" toShip: ship];
		[shipsOnHold setObject: shipID forKey: shipID];
		[self performStop];
		return instructions(universalID, ship->position, 0, 100, @"HOLD_POSITION", nil, NO);
	}
	
	if	(fabs(flightPitch) > 0.01)		// no docking while pitching
	{
		if (![shipsOnHold objectForKey:shipID])
			[self sendExpandedMessage: @"[station-acknowledges-hold-position]" toShip: ship];
		[shipsOnHold setObject: shipID forKey: shipID];
		[self performStop];
		return instructions(universalID, ship->position, 0, 100, @"HOLD_POSITION", nil, NO);
	}
	
	// rolling is okay for some
	if	(fabs(flightPitch) > 0.01)		// rolling
	{
		Vector portPos = [self getPortPosition];
		Vector portDir = vector_forward_from_quaternion(port_orientation);		
		BOOL isOffCentre = (fabs(portPos.x) + fabs(portPos.y) > 0.0f)|(fabs(portDir.x) + fabs(portDir.y) > 0.0f);
		BOOL isRotatingStation = NO;
		if ([shipinfoDictionary objectForKey:@"rotating"])
			isRotatingStation = [[shipinfoDictionary objectForKey:@"rotating"] boolValue];
		if ((!isRotatingStation)&&(isOffCentre))
		{
			if (![shipsOnHold objectForKey:shipID])
				[self sendExpandedMessage: @"[station-acknowledges-hold-position]" toShip: ship];
			[shipsOnHold setObject: shipID forKey: shipID];
			[self performStop];
			return instructions(universalID, ship->position, 0, 100, @"HOLD_POSITION", nil, NO);
		}
	}
	
	// we made it thorugh holding!
	//
	if ([shipsOnHold objectForKey:shipID])
		[shipsOnHold removeObjectForKey:shipID];
	
	// check if this is a new ship on approach
	//
	if (![shipsOnApproach objectForKey:shipID])
	{
		Vector	delta = ship->position;
		delta.x -= position.x;	delta.y -= position.y;	delta.z -= position.z;
		float	ship_distance = sqrt(magnitude2(delta));

		[self addShipToShipsOnApproach: ship];
		
		if (ship_distance < 1000.0 + collision_radius + ship->collision_radius)	// too close - back off
			return instructions(universalID, position, 0, 5000, @"BACK_OFF", nil, NO);
		
		if (ship_distance > 12500.0)	// long way off - approach more closely
			return instructions(universalID, position, 0, 10000, @"APPROACH", nil, NO);
	}
	
	if (![shipsOnApproach objectForKey:shipID])
	{
		// some error has occurred - log it, and send the try-again message
		NSLog(@"ERROR - couldn't addShipToShipsOnApproach:%@ in %@ for some reason.", ship, self);
		//
		return instructions(universalID, ship->position, 0, 100, @"TRY_AGAIN_LATER", nil, NO);
	}


	//	shipsOnApproach now has an entry for the ship.
	//
	NSMutableArray* coordinatesStack = (NSMutableArray *)[shipsOnApproach objectForKey:shipID];

	if ([coordinatesStack count] == 0)
	{
		NSLog(@"DEBUG ERROR! -- coordinatesStack = %@", [coordinatesStack description]);
		
		return instructions(universalID, ship->position, 0, 100, @"HOLD_POSITION", nil, NO);
	}
	
	// get the docking information from the instructions	
	NSMutableDictionary* nextCoords = (NSMutableDictionary *)[coordinatesStack objectAtIndex:0];
	int docking_stage = [(NSNumber *)[nextCoords objectForKey:@"docking_stage"] intValue];
	float speedAdvised = [(NSNumber *)[nextCoords objectForKey:@"speed"] floatValue];
	float rangeAdvised = [(NSNumber *)[nextCoords objectForKey:@"range"] floatValue];
	BOOL match_rotation = ([nextCoords objectForKey:@"match_rotation"] != nil);
	NSString* comms_message = (NSString*)[nextCoords objectForKey:@"comms_message"];
	
	// calculate world coordinates from relative coordinates
	Vector rel_coords;
	rel_coords.x = [(NSNumber *)[nextCoords objectForKey:@"rx"] floatValue];
	rel_coords.y = [(NSNumber *)[nextCoords objectForKey:@"ry"] floatValue];
	rel_coords.z = [(NSNumber *)[nextCoords objectForKey:@"rz"] floatValue];
	coords = [self getPortPosition];
	coords.x += rel_coords.x * vi.x + rel_coords.y * vj.x + rel_coords.z * vk.x;
	coords.y += rel_coords.x * vi.y + rel_coords.y * vj.y + rel_coords.z * vk.y;
	coords.z += rel_coords.x * vi.z + rel_coords.y * vj.z + rel_coords.z * vk.z;
	
	// check if the ship is at the control point
	double max_allowed_range = 2.0 * rangeAdvised + ship->collision_radius;	// maximum distance permitted from control point - twice advised range
	Vector delta = ship->position;
	delta.x -= coords.x;	delta.y -= coords.y;	delta.z -= coords.z;

	if (magnitude2(delta) > max_allowed_range * max_allowed_range)	// too far from the coordinates - do not remove them from the stack!
	{
		if ((docking_stage == 1) &&(magnitude2(delta) < 1000000.0))	// 1km*1km
			speedAdvised *= 0.5;	// half speed
		
		return instructions(universalID, coords, speedAdvised, rangeAdvised, @"APPROACH_COORDINATES", nil, NO);
	}
	else
	{
		// reached the current coordinates okay..
	
		// get the NEXT coordinates
		nextCoords = (NSMutableDictionary *)[coordinatesStack objectAtIndex:1];
		docking_stage = [(NSNumber *)[nextCoords objectForKey:@"docking_stage"] intValue];
		speedAdvised = [(NSNumber *)[nextCoords objectForKey:@"speed"] floatValue];
		rangeAdvised = [(NSNumber *)[nextCoords objectForKey:@"range"] floatValue];
		match_rotation = ([nextCoords objectForKey:@"match_rotation"] != nil);
		comms_message = (NSString*)[nextCoords objectForKey:@"comms_message"];
		
		if (comms_message)
			[self sendExpandedMessage: comms_message toShip: ship];
				
		// calculate world coordinates from relative coordinates
		rel_coords.x = [(NSNumber *)[nextCoords objectForKey:@"rx"] floatValue];
		rel_coords.y = [(NSNumber *)[nextCoords objectForKey:@"ry"] floatValue];
		rel_coords.z = [(NSNumber *)[nextCoords objectForKey:@"rz"] floatValue];
		coords = [self getPortPosition];
		coords.x += rel_coords.x * vi.x + rel_coords.y * vj.x + rel_coords.z * vk.x;
		coords.y += rel_coords.x * vi.y + rel_coords.y * vj.y + rel_coords.z * vk.y;
		coords.z += rel_coords.x * vi.z + rel_coords.y * vj.z + rel_coords.z * vk.z;
		
		if ((id_lock[docking_stage] == NO_TARGET)
			&&(id_lock[docking_stage + 1] == NO_TARGET)	
			&&(id_lock[docking_stage + 2] == NO_TARGET))	// check three stages ahead
		{
			// approach is clear - move to next position
			//
			int i;	// clear any previously owned docking stages
			for (i = 1; i < MAX_DOCKING_STAGES; i++)
				if ((id_lock[i] == ship_id)||([UNIVERSE entityForUniversalID:id_lock[i]] == nil))
					id_lock[i] = NO_TARGET;
					
			if (docking_stage > 1)	// don't claim first docking stage
				id_lock[docking_stage] = ship_id;	// otherwise - claim this docking stage
			
			//remove the previous stage from the stack
			[coordinatesStack removeObjectAtIndex:0];
			
			return instructions(universalID, coords, speedAdvised, rangeAdvised, @"APPROACH_COORDINATES", nil, match_rotation);
		}
		else
		{
			// approach isn't clear - hold position..
			//
			[[ship getAI] message:@"HOLD_POSITION"];
			
			if (![nextCoords objectForKey:@"hold_message_given"])
			{
				// COMM-CHATTER
				[UNIVERSE clearPreviousMessage];
				[self sendExpandedMessage: @"[station-hold-position]" toShip: ship];
				[nextCoords setObject:@"YES" forKey:@"hold_message_given"];
			}

			return instructions(universalID, ship->position, 0, 100, @"HOLD_POSITION", nil, NO);
		}
	}
	
	// we should never reach here.
	return instructions(universalID, coords, 50, 10, @"APPROACH_COORDINATES", nil, NO);
}


- (void) addShipToShipsOnApproach:(ShipEntity *) ship
{		
	int			corridor_distance[] =	{	-1,	1,	3,	5,	7,	9,	11,	12,	12};
	int			corridor_offset[] =		{	0,	0,	0,	0,	0,	0,	1,	3,	12};
	int			corridor_speed[] =		{	48,	48,	48,	48,	36,	48,	64,	128, 512};	// how fast to approach the next point
	int			corridor_range[] =		{	24,	12,	6,	4,	4,	6,	15,	38,	96};	// how close you have to get to the target point
	int			corridor_rotate[] =		{	1,	1,	1,	1,	0,	0,	0,	0,	0};		// whether to match the station rotation
	int			corridor_count = 9;
	int			corridor_final_approach = 3;
	
	int			ship_id = [ship universalID];
	NSString*   shipID = [NSString stringWithFormat:@"%d", ship_id];

	Vector launchVector = vector_forward_from_quaternion(quaternion_multiply(port_orientation, orientation));
	Vector temp = (fabsf(launchVector.x) < 0.8)? make_vector(1,0,0) : make_vector(0,1,0);
	temp = cross_product(launchVector, temp);	// 90 deg to launchVector & temp
	Vector rightVector = cross_product(launchVector, temp);
	Vector upVector = cross_product(launchVector, rightVector);
	
	// will select a direction for offset based on the shipID
	//
	int offset_id = ship_id & 0xf;	// 16  point compass
	double c = cos(offset_id * M_PI * ONE_EIGHTH);
	double s = sin(offset_id * M_PI * ONE_EIGHTH);
	
	// test if this points at the ship
	Vector point1 = [self getPortPosition];
	point1.x += launchVector.x * corridor_offset[corridor_count - 1];
	point1.y += launchVector.x * corridor_offset[corridor_count - 1];
	point1.z += launchVector.x * corridor_offset[corridor_count - 1];
	Vector alt1 = point1;
	point1.x += c * upVector.x * corridor_offset[corridor_count - 1] + s * rightVector.x * corridor_offset[corridor_count - 1];
	point1.y += c * upVector.y * corridor_offset[corridor_count - 1] + s * rightVector.y * corridor_offset[corridor_count - 1];
	point1.z += c * upVector.z * corridor_offset[corridor_count - 1] + s * rightVector.z * corridor_offset[corridor_count - 1];
	alt1.x -= c * upVector.x * corridor_offset[corridor_count - 1] + s * rightVector.x * corridor_offset[corridor_count - 1];
	alt1.y -= c * upVector.y * corridor_offset[corridor_count - 1] + s * rightVector.y * corridor_offset[corridor_count - 1];
	alt1.z -= c * upVector.z * corridor_offset[corridor_count - 1] + s * rightVector.z * corridor_offset[corridor_count - 1];
	if (distance2(alt1, ship->position) < distance2(point1, ship->position))
	{
		s = -s;
		c = -c;	// turn 180 degrees
	}
	
	//
	NSMutableArray*		coordinatesStack =  [NSMutableArray arrayWithCapacity: MAX_DOCKING_STAGES];
	double port_depth = 250;	// 250m deep standard port
	//
	int i;
	for (i = corridor_count - 1; i >= 0; i--)
	{
		NSMutableDictionary*	nextCoords =	[NSMutableDictionary dictionaryWithCapacity:3];
		
		int offset = corridor_offset[i];
		
		// space out first coordinate further if there are many ships
		if ((i == corridor_count - 1) && offset)
			offset += approach_spacing / port_depth;
		
		[nextCoords setObject:[NSNumber numberWithInt: corridor_count - i] forKey:@"docking_stage"];

		[nextCoords setObject:[NSNumber numberWithFloat: s * port_depth * offset]				forKey:@"rx"];
		[nextCoords setObject:[NSNumber numberWithFloat: c * port_depth * offset]				forKey:@"ry"];
		[nextCoords setObject:[NSNumber numberWithFloat: port_depth * corridor_distance[i]]		forKey:@"rz"];

		[nextCoords setObject:[NSNumber numberWithFloat: corridor_speed[i]] forKey:@"speed"];

		[nextCoords setObject:[NSNumber numberWithFloat: corridor_range[i]] forKey:@"range"];
		
		if (corridor_rotate[i])
			[nextCoords setObject:@"YES" forKey:@"match_rotation"];
		
		if (i == corridor_final_approach)
		{
			if (self == [UNIVERSE station])
				[nextCoords setObject:@"[station-begin-final-aproach]" forKey:@"comms_message"];
			else
				[nextCoords setObject:@"[docking-begin-final-aproach]" forKey:@"comms_message"];
		}

		[coordinatesStack addObject:nextCoords];
	}
					
	[shipsOnApproach setObject:coordinatesStack forKey:shipID];
	
	approach_spacing += 500;  // space out incoming ships by 500m
	
	// COMM-CHATTER
	if (self == [UNIVERSE station])
		[self sendExpandedMessage: @"[station-welcome]" toShip: ship];
	else
		[self sendExpandedMessage: @"[docking-welcome]" toShip: ship];

}


- (void) abortDockingForShip:(ShipEntity *) ship
{
	int ship_id = [ship universalID];
	NSString*   shipID = [NSString stringWithFormat:@"%d",ship_id];
	if ([UNIVERSE entityForUniversalID:[ship universalID]])
		[[(ShipEntity *)[UNIVERSE entityForUniversalID:[ship universalID]] getAI] message:@"DOCKING_ABORTED"];
	
	if ([shipsOnHold objectForKey:shipID])
		[shipsOnHold removeObjectForKey:shipID];
	
	if ([shipsOnApproach objectForKey:shipID])
	{
		[shipsOnApproach removeObjectForKey:shipID];
		if ([shipsOnApproach count] == 0)
			[shipAI message:@"DOCKING_COMPLETE"];
	}
		
	int i;	// clear any previously owned docking stages
	for (i = 1; i < MAX_DOCKING_STAGES; i++)
		if ((id_lock[i] == ship_id)||([UNIVERSE entityForUniversalID:id_lock[i]] == nil))
			id_lock[i] = NO_TARGET;
			
}


- (Vector) portUpVector
{
	if (port_dimensions.x > port_dimensions.y)
	{
		return vector_up_from_quaternion(quaternion_multiply(port_orientation, orientation));
	}
	else
	{
		return vector_right_from_quaternion(quaternion_multiply(port_orientation, orientation));
	}
}


- (Vector) portUpVectorForShipsBoundingBox:(BoundingBox) bb
{
	BOOL twist = ((port_dimensions.x < port_dimensions.y) ^ (bb.max.x - bb.min.x < bb.max.y - bb.min.y));

	if (!twist)
	{
		return vector_up_from_quaternion(quaternion_multiply(port_orientation, orientation));
	}
	else
	{
		return vector_right_from_quaternion(quaternion_multiply(port_orientation, orientation));
	}
}


//////////////////////////////////////////////// from superclass

- (id) initWithDictionary:(NSDictionary *) dict
{
	self = [super initWithDictionary:dict];
	
	shipsOnApproach = [[NSMutableDictionary alloc] init]; // alloc retains
	shipsOnHold = [[NSMutableDictionary alloc] init]; // alloc retains
	launchQueue = [[NSMutableArray alloc] init]; // retained
	
	// local specials
	equivalent_tech_level = NSNotFound;
	equipment_price_factor = 1.0;
	
	max_scavengers = 3;
	max_defense_ships = 3;
	max_police = STATION_MAX_POLICE;
	
	docked_shuttles = ranrot_rand() % 4;   // 0..3;
	shuttle_launch_interval = 15.0 * 60.0;  // every 15 minutes
	last_shuttle_launch_time = - (ranrot_rand() % 60) * shuttle_launch_interval / 60.0;

	docked_traders = 3 + (ranrot_rand() & 7);   // 1..3;
	trader_launch_interval = 3600.0 / docked_traders;  // every few minutes
	last_trader_launch_time = 60.0 - trader_launch_interval; // in one minute's time
	
	last_patrol_report_time = 0.0;
	patrol_launch_interval = 300.0;	// 5 minutes
	last_patrol_report_time -= patrol_launch_interval;
	//
	isShip = YES;
	isStation = YES;
	
	return self;
}


- (void) dealloc
{
	[shipsOnApproach release];
	[shipsOnHold release];
	[launchQueue release];
	
	[localMarket release];
	[localPassengers release];
	[localContracts release];
	[localShipyard release];
	
    [super dealloc];
}


- (void) setUpShipFromDictionary:(NSDictionary *) dict
{
	unsigned		i;
	
	isShip = YES;
	isStation = YES;
	
	// ** Set up a the docking port
	// Look for subentity specifying position
	NSArray		*subs = [dict arrayForKey:@"subentities"];
	NSArray		*dockSubEntity = nil;
	
	for (i = 0; i < [subs count]; i++)
	{
		NSArray* details = ScanTokensFromString([subs objectAtIndex:i]);
		if (([details count] == 8) && ([[details objectAtIndex:0] hasPrefix:@"dock"]))  dockSubEntity = details;
	}
	
	if (dockSubEntity != nil)
	{
		port_position.x = [(NSString *)[dockSubEntity objectAtIndex:1] floatValue];
		port_position.y = [(NSString *)[dockSubEntity objectAtIndex:2] floatValue];
		port_position.z = [(NSString *)[dockSubEntity objectAtIndex:3] floatValue];
		port_orientation.w = [(NSString *)[dockSubEntity objectAtIndex:4] floatValue];
		port_orientation.x = [(NSString *)[dockSubEntity objectAtIndex:5] floatValue];
		port_orientation.y = [(NSString *)[dockSubEntity objectAtIndex:6] floatValue];
		port_orientation.z = [(NSString *)[dockSubEntity objectAtIndex:7] floatValue];
		quaternion_normalize(&port_orientation);
	}
	else
	{
		// No dock* subentity found, use defaults.
		double port_radius = [dict doubleForKey:@"port_radius" defaultValue:500.0];
		port_position = make_vector(0, 0, port_radius);
		port_orientation = kIdentityQuaternion;
	}
	
	// port_dimensions can be set for rock-hermits and other specials
	port_dimensions = make_vector(69, 69, 250);
	NSString *portDimensionsStr = [dict stringForKey:@"port_dimensions"];
	if (portDimensionsStr != nil)   // this can be set for rock-hermits and other specials
	{
		NSArray* tokens = [portDimensionsStr componentsSeparatedByString:@"x"];
		if ([tokens count] == 3)
		{
			port_dimensions = make_vector([[tokens objectAtIndex:0] floatValue],
										  [[tokens objectAtIndex:1] floatValue],
										  [[tokens objectAtIndex:2] floatValue]);
		}
	}
	
	[super setUpShipFromDictionary:dict];
	
	equivalent_tech_level = [dict intForKey:@"equivalent_tech_level" defaultValue:NSNotFound];
	max_scavengers = [dict intForKey:@"max_scavengers" defaultValue:3];
	max_defense_ships = [dict intForKey:@"max_defense_ships" defaultValue:3];
	max_police = [dict intForKey:@"max_police" defaultValue:STATION_MAX_POLICE];
	equipment_price_factor = [dict doubleForKey:@"equipment_price_factor" defaultValue:1.0];

	if ([self isRotatingStation])
	{
		docked_shuttles = ranrot_rand() & 3;   // 0..3;
		last_shuttle_launch_time = 0.0;
		shuttle_launch_interval = 15.0 * 60.0;  // every 15 minutes
		last_shuttle_launch_time = - (ranrot_rand() & 63) * shuttle_launch_interval / 60.0;

		docked_traders = 3 + (ranrot_rand() & 7);   // 1..3;
		trader_launch_interval = 3600.0 / docked_traders;  // every few minutes
		last_trader_launch_time = 60.0 - trader_launch_interval; // in one minute's time
	}
	else
	{
		docked_shuttles = 0;
		docked_traders = 0;   // 1..3;
	}
	
	[self setCrew:[NSArray arrayWithObject:[OOCharacter characterWithRole:@"police" andOriginalSystem:[UNIVERSE systemSeed]]]];
}


- (void) setDockingPortModel:(ShipEntity*) dock_model :(Vector) dock_pos :(Quaternion) dock_q
{
	port_model = dock_model;
	
	port_position = dock_pos;
	port_orientation = dock_q;

	BoundingBox bb = [port_model boundingBox];
	port_dimensions = make_vector(bb.max.x - bb.min.x, bb.max.y - bb.min.y, bb.max.z - bb.min.z);

	if (bb.max.z > 0.0)
	{
		Vector vk = vector_forward_from_quaternion(dock_q);
		port_position.x += bb.max.z * vk.x;
		port_position.y += bb.max.z * vk.y;
		port_position.z += bb.max.z * vk.z;
	}
	
}


- (BOOL) shipIsInDockingCorridor:(ShipEntity*) ship
{
	if ((!ship)||(!ship->isShip))
		return NO;
	
	Quaternion q0 = quaternion_multiply(port_orientation, orientation);
	Vector vi = vector_right_from_quaternion(q0);
	Vector vj = vector_up_from_quaternion(q0);
	Vector vk = vector_forward_from_quaternion(q0);
	
	Vector port_pos = [self getPortPosition];
	
	BoundingBox shipbb = [ship boundingBox];
	BoundingBox arbb = [ship findBoundingBoxRelativeToPosition: port_pos InVectors: vi : vj : vk];
	
	// port dimensions..
	GLfloat ww = port_dimensions.x;
	GLfloat hh = port_dimensions.y;
	GLfloat dd = port_dimensions.z;

	while (shipbb.max.x - shipbb.min.x > ww * 0.90)	ww *= 1.25;
	while (shipbb.max.y - shipbb.min.y > hh * 0.90)	hh *= 1.25;
	
	ww *= 0.5;
	hh *= 0.5;
	
#ifndef NDEBUG
	if ((ship->isPlayer)&&(gDebugFlags & DEBUG_DOCKING))
	{
		BOOL			inLane;
		float			range;
		unsigned		laneFlags = 0;
		
		if (arbb.max.x < ww)   laneFlags |= 1;
		if (arbb.min.x > -ww)  laneFlags |= 2;
		if (arbb.max.y < hh)   laneFlags |= 4;
		if (arbb.min.y > -hh)  laneFlags |= 8;
		inLane = laneFlags == 0xF;
		range = 0.90 * arbb.max.z + 0.10 * arbb.min.z;
		
		OOLog(@"docking.debug", @"Normalised port dimensions are %g x %g x %g.  Player bounding box is at %@-%@ -- %s (%X), range: %g",
			ww * 2.0, hh * 2.0, dd,
			VectorDescription(arbb.min), VectorDescription(arbb.max),
			inLane ? "in lane" : "out of lane", laneFlags,
			range);
	}
#endif

	if (arbb.max.z < -dd)
		return NO;

	if ((arbb.max.x < ww)&&(arbb.min.x > -ww)&&(arbb.max.y < hh)&&(arbb.min.y > -hh))
	{
		// in lane
		if (0.90 * arbb.max.z + 0.10 * arbb.min.z < 0.0)	// we're 90% in docking position!
			[ship enterDock:self];
		//
		return YES;
		//
	}
	
	if (ship->status == STATUS_LAUNCHING)
		return YES;
	
	// if close enough (within 50%) correct and add damage
	//
	if  ((arbb.min.x > -1.5 * ww)&&(arbb.max.x < 1.5 * ww)&&(arbb.min.y > -1.5 * hh)&&(arbb.max.y < 1.5 * hh))
	{
		if (arbb.min.z < 0.0)	// got our nose inside
		{
			GLfloat correction_factor = -arbb.min.z / (arbb.max.z - arbb.min.z);	// proportion of ship inside
		
			// damage the ship according to velocity but don't collide
			[ship takeScrapeDamage: 5 * [UNIVERSE getTimeDelta]*[ship flightSpeed] from:self];
			
			Vector delta;
			delta.x = 0.5 * (arbb.max.x + arbb.min.x) * correction_factor;
			delta.y = 0.5 * (arbb.max.y + arbb.min.y) * correction_factor;
			
			if ((arbb.max.x < ww)&&(arbb.min.x > -ww))	// x is okay - no need to correct
				delta.x = 0;
			if ((arbb.max.y > hh)&&(arbb.min.x > -hh))	// y is okay - no need to correct
				delta.y = 0;
				
			// adjust the ship back to the center of the port
			Vector pos = ship->position;
			pos.x -= delta.y * vj.x + delta.x * vi.x;
			pos.y -= delta.y * vj.y + delta.x * vi.y;
			pos.z -= delta.y * vj.z + delta.x * vi.z;
			[ship setPosition:pos];
		}
		
		// if far enough in - dock
		if (0.90 * arbb.max.z + 0.10 * arbb.min.z < 0.0)
			[ship enterDock:self];
		
		return YES;	// okay NOW we're in the docking corridor!
	}	
	//
	//
	return NO;
}


- (BOOL) dockingCorridorIsEmpty
{
	if (!UNIVERSE)
		return NO;
	
	double unitime = [UNIVERSE getTime];
	
	if (unitime < last_launch_time + STATION_DELAY_BETWEEN_LAUNCHES)	// leave sufficient pause between launches
		return NO;
	
	// check against all ships
	BOOL		isEmpty = YES;
	int			ent_count =		UNIVERSE->n_entities;
	Entity**	uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	Entity*		my_entities[ent_count];
	int i;
	int ship_count = 0;
	for (i = 0; i < ent_count; i++)
		if (uni_entities[i]->isShip)
			my_entities[ship_count++] = [uni_entities[i] retain];		//	retained

	for (i = 0; (i < ship_count)&&(isEmpty); i++)
	{
		ShipEntity*	ship = (ShipEntity*)my_entities[i];
		double		d2 = distance2(position, ship->position);
		if ((ship != self)&&(d2 < 25000000)&&(ship->status != STATUS_DOCKED))	// within 5km
		{
			Vector ppos = [self getPortPosition];
			d2 = distance2(ppos, ship->position);
			if (d2 < 4000000)	// within 2km of the port entrance
			{
				Quaternion q1 = orientation;
				q1 = quaternion_multiply(port_orientation, q1);
				//
				Vector v_out = vector_forward_from_quaternion(q1);
				Vector r_pos = make_vector(ship->position.x - ppos.x, ship->position.y - ppos.y, ship->position.z - ppos.z);
				if (r_pos.x||r_pos.y||r_pos.z)
					r_pos = unit_vector(&r_pos);
				else
					r_pos.z = 1.0;
				//
				double vdp = dot_product(v_out, r_pos); //== cos of the angle between r_pos and v_out
				//
				if (vdp > 0.86)
				{
					isEmpty = NO;
					last_launch_time = unitime;
				}
			}
		}
	}
	
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release];		//released

	return isEmpty;
}


- (void) clearDockingCorridor
{
	if (!UNIVERSE)
		return;
		
	// check against all ships
	BOOL		isClear = YES;
	int			ent_count =		UNIVERSE->n_entities;
	Entity**	uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	Entity*		my_entities[ent_count];
	int i;
	int ship_count = 0;
	for (i = 0; i < ent_count; i++)
		if (uni_entities[i]->isShip)
			my_entities[ship_count++] = [uni_entities[i] retain];		//	retained

	for (i = 0; i < ship_count; i++)
	{
		ShipEntity*	ship = (ShipEntity*)my_entities[i];
		double		d2 = distance2(position, ship->position);
		if ((ship != self)&&(d2 < 25000000)&&(ship->status != STATUS_DOCKED))	// within 5km
		{
			Vector ppos = [self getPortPosition];
			float time_out = -15.00;	// 15 secs
			do
			{
				isClear = YES;
				d2 = distance2(ppos, ship->position);
				if (d2 < 4000000)	// within 2km of the port entrance
				{
					Quaternion q1 = orientation;
					q1 = quaternion_multiply(port_orientation, q1);
					//
					Vector v_out = vector_forward_from_quaternion(q1);
					Vector r_pos = make_vector(ship->position.x - ppos.x, ship->position.y - ppos.y, ship->position.z - ppos.z);
					if (r_pos.x||r_pos.y||r_pos.z)
						r_pos = unit_vector(&r_pos);
					else
						r_pos.z = 1.0;
					//
					double vdp = dot_product(v_out, r_pos); //== cos of the angle between r_pos and v_out
					//
					if (vdp > 0.86)
					{
						isClear = NO;
						
						// okay it's in the way .. give it a wee nudge (0.25s)
						[ship update: 0.25];
						time_out += 0.25;
					}
					if (time_out > 0)
					{
						Vector v1 = vector_forward_from_quaternion(port_orientation);
						Vector spos = ship->position;
						spos.x += 3000.0 * v1.x;	spos.y += 3000.0 * v1.y;	spos.z += 3000.0 * v1.z; 
						[ship setPosition:spos]; // move 3km out of the way
					}
				}
			} while (!isClear);
		}
	}
	
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release];		//released

	return;
}


- (void) update:(double) delta_t
{
	BOOL isRockHermit = (scanClass == CLASS_ROCK);
	BOOL isMainStation = (self == [UNIVERSE station]);
	
	double unitime = [UNIVERSE getTime];
	
	[super update:delta_t];
	
	if (([launchQueue count] > 0)&&([shipsOnApproach count] == 0)&&[self dockingCorridorIsEmpty])
	{
		[self launchShip:(ShipEntity *)[launchQueue objectAtIndex:0]];
		[launchQueue removeObjectAtIndex:0];
	}
	if (([launchQueue count] == 0)&&(no_docking_while_launching))
		no_docking_while_launching = NO;	// launching complete
	if (approach_spacing > 0.0)
	{
		approach_spacing -= delta_t * 10.0;	// reduce by 10 m/s
		if (approach_spacing < 0.0)   approach_spacing = 0.0;
	}
	if ((docked_shuttles > 0)&&(!isRockHermit))
	{
		if (unitime > last_shuttle_launch_time + shuttle_launch_interval)
		{
			[self launchShuttle];
			docked_shuttles--;
			last_shuttle_launch_time = unitime;
		}
	}

	if ((docked_traders > 0)&&(!isRockHermit))
	{
		if (unitime > last_trader_launch_time + trader_launch_interval)
		{
			[self launchTrader];
			docked_traders--;
			last_trader_launch_time = unitime;
		}
	}
	
	// testing patrols
	if ((unitime > last_patrol_report_time + patrol_launch_interval)&&(isMainStation))
	{
		if (![self launchPatrol])
			last_patrol_report_time = unitime;
	}
	
}


- (void) clear
{
	if (launchQueue)
		[launchQueue removeAllObjects];
	if (shipsOnApproach)
		[shipsOnApproach removeAllObjects];
	if (shipsOnHold)
		[shipsOnHold removeAllObjects];
}


- (void) addShipToLaunchQueue:(ShipEntity *) ship
{
	[self sanityCheckShipsOnApproach];
	if (!launchQueue)
		launchQueue = [[NSMutableArray alloc] init]; // retained
	if (ship)
		[launchQueue addObject:ship];
}


- (unsigned) countShipsInLaunchQueueWithRole:(NSString *) a_role
{
	if ([launchQueue count] == 0)
		return 0;
	unsigned i;
	unsigned result = 0;
	for (i = 0; i < [launchQueue count]; i++)
	{
		if ([[(ShipEntity *)[launchQueue objectAtIndex:i] roles] isEqual:a_role])
			result++;
	}
	return result;
}


- (void) launchShip:(ShipEntity *) ship
{
	if ((!ship)||(!ship->isShip))
		return;
	
	Vector launchPos = position;
	Vector launchVel = velocity;
	double launchSpeed = 0.5 * [ship maxFlightSpeed];
	if ((maxFlightSpeed > 0)&&(flightSpeed > 0))
		launchSpeed = 0.5 * [ship maxFlightSpeed] * (1.0 + flightSpeed/maxFlightSpeed);
	Quaternion q1 = orientation;
	q1 = quaternion_multiply(port_orientation, q1);
	Vector launchVector = vector_forward_from_quaternion(q1);
	BoundingBox bb = [ship boundingBox];
	if ((port_dimensions.x < port_dimensions.y) ^ (bb.max.x - bb.min.x < bb.max.y - bb.min.y))
		quaternion_rotate_about_axis(&q1, launchVector, M_PI*0.5);  // to account for the slot being at 90 degrees to vertical
	[ship setOrientation:q1];
	// launch position
	launchPos.x += port_position.x * v_right.x + port_position.y * v_up.x + port_position.z * v_forward.x;
	launchPos.y += port_position.x * v_right.y + port_position.y * v_up.y + port_position.z * v_forward.y;
	launchPos.z += port_position.x * v_right.z + port_position.y * v_up.z + port_position.z * v_forward.z;
    [ship setPosition:launchPos];
	// launch speed
	launchVel.x += launchSpeed * launchVector.x;	launchVel.y += launchSpeed * launchVector.y;	launchVel.z += launchSpeed * launchVector.z;
	[ship setSpeed:sqrt(magnitude2(launchVel))];
	[ship setVelocity:launchVel];
	// orientation
	[ship setRoll:flightRoll];
	[ship setPitch:0.0];
	[ship setStatus: STATUS_LAUNCHING];
	[[ship getAI] reactToMessage:@"pauseAI: 2.0"]; // pause while launching
	[UNIVERSE addEntity:ship];
	last_launch_time = [UNIVERSE getTime];
	[ship resetTracking];	// resets stuff for tracking/exhausts
}


- (void) noteDockedShip:(ShipEntity *) ship
{
	// set last launch time to avoid clashes with outgoing ships
	last_launch_time = [UNIVERSE getTime];
	if ([[ship roles] isEqual:@"shuttle"])
		docked_shuttles++;
	if ([[ship roles] isEqual:@"trader"])
		docked_traders++;
	if ([[ship roles] isEqual:@"police"])
		police_launched--;
	if ([[ship roles] isEqual:@"hermit-ship"])
		police_launched--;
	if ([[ship roles] isEqual:@"defense_ship"])
		police_launched--;
	if ([[ship roles] isEqual:@"scavenger"]||[[ship roles] isEqual:@"miner"])	// treat miners and scavengers alike!
		scavengers_launched--;

	int			ship_id = [ship universalID];
	NSString*   shipID = [NSString stringWithFormat:@"%d", ship_id];
	[shipsOnApproach removeObjectForKey:shipID];
	if ([shipsOnApproach count] == 0)
		[shipAI message:@"DOCKING_COMPLETE"];
	
	int i;	// clear any previously owned docking stages
	for (i = 0; i < MAX_DOCKING_STAGES; i++)
		if ((id_lock[i] == ship_id)||([UNIVERSE entityForUniversalID:id_lock[i]] == nil))
			id_lock[i] = NO_TARGET;
	
	if (ship == [PlayerEntity sharedPlayer])	// ie. the player
	{
		//scripting
		if ([script_actions count])
		{
			[(PlayerEntity *)ship setScriptTarget:self];
			[(PlayerEntity *)ship scriptActions: script_actions forTarget: ship];
		}
	}
}


- (BOOL) collideWithShip:(ShipEntity *)other
{
	[self abortAllDockings];
	return [super collideWithShip:other];
}


- (BOOL) hasHostileTarget
{
	if (primaryTarget == NO_TARGET)
		return NO;
	if ((behaviour == BEHAVIOUR_AVOID_COLLISION)&&(previousCondition))
	{
		int old_behaviour = [(NSNumber*)[previousCondition objectForKey:@"behaviour"] intValue];
		return IsBehaviourHostile(old_behaviour);
	}
	return IsBehaviourHostile(behaviour)||(alert_level == STATION_ALERT_LEVEL_YELLOW)||(alert_level == STATION_ALERT_LEVEL_RED);
}


- (void)takeEnergyDamage:(double)amount from:(Entity *)ent becauseOf:(Entity *)other
{
	// If it's an energy mine...
	if (ent && ent->isParticle && ent->scanClass == CLASS_MINE)
	{
		// ...and this is the system's main station...
		if (self == [UNIVERSE station])
		{
			// ...then get angry...
			if (other && other->isShip)
			{
				[(ShipEntity*)other markAsOffender:96];
				[self setPrimaryAggressor:other];
				found_target = primaryAggressor;
			}
			[self increaseAlertLevel];
			[shipAI reactToMessage:@"ATTACKED"];	// note use the reactToMessage: method NOT the think-delayed message: method
			
			// ...and don't blow up.
			return;
		}
	}
	
	// Handle damage like a ship.
	[super takeEnergyDamage:amount from:ent becauseOf:other];
}


- (void)takeScrapeDamage:(double)amount from:(Entity *)ent
{
	// Stop damage if main station
	if (self != [UNIVERSE station])  [super takeScrapeDamage:amount from:ent];
}


- (void) takeHeatDamage:(double)amount
{
	// Stop damage if main station
	if (self != [UNIVERSE station])  [super takeHeatDamage:amount];
}

//////////////////////////////////////////////// extra AI routines


- (void) increaseAlertLevel
{
	switch (alert_level)
	{
		case STATION_ALERT_LEVEL_GREEN :
			alert_level = STATION_ALERT_LEVEL_YELLOW;
			[shipAI reactToMessage:@"YELLOW_ALERT"];
			break;
		
		case STATION_ALERT_LEVEL_YELLOW :
			alert_level = STATION_ALERT_LEVEL_RED;
			[shipAI reactToMessage:@"RED_ALERT"];
			break;
		
		case STATION_ALERT_LEVEL_RED:
			break;
	}
}


- (void) decreaseAlertLevel
{
	switch (alert_level)
	{
		case STATION_ALERT_LEVEL_RED :
			alert_level = STATION_ALERT_LEVEL_YELLOW;
			[shipAI reactToMessage:@"CONDITION_YELLOW"];
			break;
		
		case STATION_ALERT_LEVEL_YELLOW :
			alert_level = STATION_ALERT_LEVEL_GREEN;
			[shipAI reactToMessage:@"CONDITION_GREEN"];
			break;
		
		case STATION_ALERT_LEVEL_GREEN:
			break;
	}
}


- (void) launchPolice
{
	int techlevel = [self equivalent_tech_level];
	if (techlevel == NSNotFound)
		techlevel = 6;
	int police_target = primaryTarget;
	unsigned i;
	for (i = 0; (i < 4)&&(police_launched < max_police) ; i++)
	{
		ShipEntity  *police_ship;
		if (![UNIVERSE entityForUniversalID:police_target])
		{
			[shipAI reactToMessage:@"TARGET_LOST"];
			return;
		}
		
		if ((ranrot_rand() & 7) + 6 <= techlevel)
			police_ship = [UNIVERSE newShipWithRole:@"interceptor"];   // retain count = 1
		else
			police_ship = [UNIVERSE newShipWithRole:@"police"];   // retain count = 1
		if (police_ship)
		{
			if (![police_ship crew])
				[police_ship setCrew:[NSArray arrayWithObject:
					[OOCharacter randomCharacterWithRole: @"police"
					andOriginalSystem: [UNIVERSE systemSeed]]]];
				
			[police_ship setRoles:@"police"];
			[police_ship addTarget:[UNIVERSE entityForUniversalID:police_target]];
			[police_ship setScanClass: CLASS_POLICE];
			[police_ship setBounty:0];
			[[police_ship getAI] setStateMachine:@"policeInterceptAI.plist"];
			[self addShipToLaunchQueue:police_ship];
			[police_ship release];
			police_launched++;
		}
	}
	no_docking_while_launching = YES;
	[self abortAllDockings];
}


- (void) launchDefenseShip
{
	int defense_target = primaryTarget;
	ShipEntity  *defense_ship;
	NSString* defense_ship_key		= nil;
	NSString* defense_ship_role_key	= nil;
	NSString* defense_ship_ai		= @"policeInterceptAI.plist";
	
	int techlevel = [self equivalent_tech_level];
	if (techlevel == NSNotFound)
	techlevel = 6;
	if ((ranrot_rand() & 7) + 6 <= techlevel)
		defense_ship_role_key	= @"interceptor";
	else
		defense_ship_role_key	= @"police";
	
	if (police_launched >= max_defense_ships)   // shuttles are to rockhermits what police ships are to stations
		return;
	
	if (![UNIVERSE entityForUniversalID:defense_target])
	{
		[shipAI reactToMessage:@"TARGET_LOST"];
		return;
	}
		
	if ([shipinfoDictionary objectForKey:@"defense_ship"])
	{
		defense_ship_key = (NSString*)[shipinfoDictionary objectForKey:@"defense_ship"];
		defense_ship_ai = nil;
	}
	if ([shipinfoDictionary objectForKey:@"defense_ship_role"])
	{
		defense_ship_role_key = (NSString*)[shipinfoDictionary objectForKey:@"defense_ship_role"];
		defense_ship_ai = nil;
	}

	if (defense_ship_key)
	{
		defense_ship = [UNIVERSE newShipWithName:defense_ship_key];
		[defense_ship setRoles:@"defense_ship"];
	}
	else
	{
		defense_ship = [UNIVERSE newShipWithRole:defense_ship_role_key];
		[defense_ship setRoles:@"defense_ship"];
	}
	
	if (!defense_ship)
		return;
	
	police_launched++;
	
	if (![defense_ship crew])
		[defense_ship setCrew:[NSArray arrayWithObject:
			[OOCharacter randomCharacterWithRole: @"hunter"
			andOriginalSystem: [UNIVERSE systemSeed]]]];
				
	[defense_ship setOwner: self];
	[defense_ship setGroupID:universalID];	// who's your Daddy
	
	if (defense_ship_ai)
		[[defense_ship getAI] setStateMachine:defense_ship_ai];
	[defense_ship addTarget:[UNIVERSE entityForUniversalID:defense_target]];

	if ((scanClass != CLASS_ROCK)&&(scanClass != CLASS_STATION))
		[defense_ship setScanClass: scanClass];	// same as self

	[self addShipToLaunchQueue:defense_ship];
	[defense_ship release];
	no_docking_while_launching = YES;
	[self abortAllDockings];

}


- (void) launchScavenger
{
	ShipEntity  *scavenger_ship;
	
	unsigned scavs = [UNIVERSE countShipsWithRole:@"scavenger" inRange:SCANNER_MAX_RANGE ofEntity:self] + [self countShipsInLaunchQueueWithRole:@"scavenger"];
	
	if (scavs >= max_scavengers)  return;
	if (scavengers_launched >= max_scavengers)  return;
	
	scavengers_launched++;
		
	scavenger_ship = [UNIVERSE newShipWithRole:@"scavenger"];   // retain count = 1
	if (scavenger_ship)
	{
		if (![scavenger_ship crew])
			[scavenger_ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"hunter"
				andOriginalSystem: [UNIVERSE systemSeed]]]];
				
		[scavenger_ship setScanClass: CLASS_NEUTRAL];
		[scavenger_ship setGroupID:universalID];	// who's your Daddy
		[[scavenger_ship getAI] setStateMachine:@"scavengerAI.plist"];
		[self addShipToLaunchQueue:scavenger_ship];
		[scavenger_ship release];
	}
}


- (void) launchMiner
{
	ShipEntity  *miner_ship;
	
	int		n_miners = [UNIVERSE countShipsWithRole:@"miner" inRange:SCANNER_MAX_RANGE ofEntity:self] + [self countShipsInLaunchQueueWithRole:@"miner"];
	
	if (n_miners >= 1)	// just the one
		return;
	
	// count miners as scavengers...
	if (scavengers_launched >= max_scavengers)  return;
	
	miner_ship = [UNIVERSE newShipWithRole:@"miner"];   // retain count = 1
	if (miner_ship)
	{
		if (![miner_ship crew])
			[miner_ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"miner"
				andOriginalSystem: [UNIVERSE systemSeed]]]];
				
		scavengers_launched++;
		[miner_ship setScanClass: CLASS_NEUTRAL];
		[miner_ship setGroupID:universalID];	// who's your Daddy
		[[miner_ship getAI] setStateMachine:@"minerAI.plist"];
		[self addShipToLaunchQueue:miner_ship];
		[miner_ship release];
	}
}

/**Lazygun** added the following method. A complete rip-off of launchDefenseShip. 
*/
- (void) launchPirateShip
{
	//Pirate ships are launched from the same pool as defence ships.
	int defense_target = primaryTarget;
	ShipEntity  *pirate_ship;
	if (police_launched >= max_defense_ships)   // shuttles are to rockhermits what police ships are to stations
		return;
	if (![UNIVERSE entityForUniversalID:defense_target])
	{
		[shipAI reactToMessage:@"TARGET_LOST"];
		return;
	}
	
	police_launched++;
	
	// Yep! The standard hermit defence ships, even if they're the aggressor.
	pirate_ship = [UNIVERSE newShipWithRole:@"pirate"];   // retain count = 1
	// Nope, use standard pirates in a generic method.
	
	if (pirate_ship)
	{
		if (![pirate_ship crew])
			[pirate_ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"pirate"
				andOriginalSystem: [UNIVERSE systemSeed]]]];
				
		// set the owner of the ship to the station so that it can check back for docking later
		[pirate_ship setOwner:self];
		[pirate_ship setGroupID:universalID];	// who's your Daddy
		
		[pirate_ship addTarget:[UNIVERSE entityForUniversalID:defense_target]];
		[pirate_ship setScanClass: CLASS_NEUTRAL];
		//**Lazygun** added 30 Nov 04 to put a bounty on those pirates' heads.
		[pirate_ship setBounty: 10 + floor(randf() * 20)];	// modified for variety

		[self addShipToLaunchQueue:pirate_ship];
		[pirate_ship release];
		no_docking_while_launching = YES;
		[self abortAllDockings];
	}
}


- (void) launchShuttle
{
	ShipEntity  *shuttle_ship;
		
	shuttle_ship = [UNIVERSE newShipWithRole:@"shuttle"];   // retain count = 1
	
	if (shuttle_ship)
	{
		if (![shuttle_ship crew])
			[shuttle_ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"trader"
				andOriginalSystem: [UNIVERSE systemSeed]]]];
				
		[shuttle_ship setScanClass: CLASS_NEUTRAL];
		[shuttle_ship setCargoFlag:CARGO_FLAG_FULL_SCARCE];
		[[shuttle_ship getAI] setStateMachine:@"fallingShuttleAI.plist"];
		[self addShipToLaunchQueue:shuttle_ship];
		
		[shuttle_ship release];
	}
}


- (void) launchTrader
{
	BOOL		sunskimmer = (randf() < 0.1);	// 10%
	ShipEntity  *trader_ship = nil;
	
	if (!sunskimmer)  trader_ship = [UNIVERSE newShipWithRole:@"trader"];   // retain count = 1
	else  trader_ship = [UNIVERSE newShipWithRole:@"sunskim-trader"];   // retain count = 1
	
	if (trader_ship)
	{
		if (![trader_ship crew])
			[trader_ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"trader"
				andOriginalSystem: [UNIVERSE systemSeed]]]];
				
		[trader_ship setRoles:@"trader"];
		[trader_ship setScanClass: CLASS_NEUTRAL];
		[trader_ship setCargoFlag:CARGO_FLAG_FULL_PLENTIFUL];
		
		if (sunskimmer)
		{
			[[trader_ship getAI] setStateMachine:@"route2sunskimAI.plist"];
		}
		else
		{
			[[trader_ship getAI] setStateMachine:@"exitingTraderAI.plist"];
		}
		[self addShipToLaunchQueue:trader_ship];

		// add escorts to the trader
		int escorts = [trader_ship escortCount];
		//
		[trader_ship setEscortCount:0];
		while (escorts--)
			[self launchEscort];
			
		[trader_ship release];
	}
}


- (void) launchEscort
{
	ShipEntity  *escort_ship;
		
	escort_ship = [UNIVERSE newShipWithRole:@"escort"];   // retain count = 1
	
	if (escort_ship)
	{
		if (![escort_ship crew])
			[escort_ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"hunter"
				andOriginalSystem: [UNIVERSE systemSeed]]]];
				
		[escort_ship setScanClass: CLASS_NEUTRAL];
		[escort_ship setCargoFlag: CARGO_FLAG_FULL_PLENTIFUL];
		[[escort_ship getAI] setStateMachine:@"escortAI.plist"];
		[self addShipToLaunchQueue:escort_ship];
		
		[escort_ship release];
	}
}


- (BOOL) launchPatrol
{
	
	if (police_launched < max_police)
	{
		ShipEntity  *patrol_ship;
		int techlevel = [self equivalent_tech_level];
		if (techlevel == NSNotFound)
			techlevel = 6;
			
		police_launched++;
		
		if ((ranrot_rand() & 7) + 6 <= techlevel)
			patrol_ship = [UNIVERSE newShipWithRole:@"interceptor"];   // retain count = 1
		else
			patrol_ship = [UNIVERSE newShipWithRole:@"police"];   // retain count = 1
		if (patrol_ship)
		{
			if (![patrol_ship crew])
				[patrol_ship setCrew:[NSArray arrayWithObject:
					[OOCharacter randomCharacterWithRole: @"police"
					andOriginalSystem: [UNIVERSE systemSeed]]]];
				
			[patrol_ship switchLightsOff];
			[patrol_ship setScanClass: CLASS_POLICE];
			[patrol_ship setRoles:@"police"];
			[patrol_ship setBounty:0];
			[patrol_ship setGroupID:universalID];	// who's your Daddy
			[[patrol_ship getAI] setStateMachine:@"planetPatrolAI.plist"];
			[self addShipToLaunchQueue:patrol_ship];
			[self acceptPatrolReportFrom:patrol_ship];
			[patrol_ship release];
			return YES;
		}
	}
	return NO;
}


- (void) launchShipWithRole:(NSString*) role
{
	ShipEntity  *ship = [UNIVERSE newShipWithRole: role];   // retain count = 1
	if (ship)
	{
		if (![ship crew])
			[ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: role
				andOriginalSystem: [UNIVERSE systemSeed]]]];
		[ship setRoles: role];
		[ship setGroupID: universalID];	// who's your Daddy
		[self addShipToLaunchQueue:ship];
		[ship release];
	}
}


- (void) becomeExplosion
{
	// launch docked ships if possible
	PlayerEntity* player = [PlayerEntity sharedPlayer];
	if ((player)&&(player->status == STATUS_DOCKED)&&([player docked_station] == self))
	{
		// undock the player!
		[player leaveDock:self];
		[UNIVERSE setViewDirection:VIEW_FORWARD];
		[UNIVERSE setDisplayCursor:NO];
		[player warnAboutHostiles];	// sound a klaxon
	}
	
	if (scanClass == CLASS_ROCK)	// ie we're a rock hermit or similar
	{
		// set the roles so that we break up into rocks!
		roles = @"asteroid";
		being_mined = YES;
	}
	
	// finally bite the bullet
	[super becomeExplosion];
}


- (void) acceptPatrolReportFrom:(ShipEntity*) patrol_ship
{
	last_patrol_report_time = [UNIVERSE getTime];
}


- (void) acceptDockingClearanceRequestFrom:(ShipEntity *)other
{
	if (self != [UNIVERSE station])  return;
	
	// check
	if ([shipsOnApproach count])
	{
		[self sendExpandedMessage:@"Please wait until all ships have completed their approach." toShip:other];
		return;
	}
	if ([launchQueue count])
	{
		[self sendExpandedMessage:@"Please wait until launching ships have cleared %H Station." toShip:other];
		return;
	}
	if (last_launch_time < [UNIVERSE getTime])
	{
		last_launch_time = [UNIVERSE getTime] + 126;
		[self sendExpandedMessage:@"You are cleared to dock within the next two minutes. Please proceeed." toShip:other];
	}
}


- (NSString *) roles
{
	NSArray* all_roles = ScanTokensFromString([shipinfoDictionary objectForKey:@"roles"]);
	if ([all_roles count])
		return (NSString *)[all_roles objectAtIndex:0];
	else
		return @"station";
}


- (BOOL) isRotatingStation
{
	if ([shipinfoDictionary boolForKey:@"rotating" defaultValue:NO])  return YES;
	return [[shipinfoDictionary objectForKey:@"roles"] rangeOfString:@"rotating-station"].location != NSNotFound;	// legacy
}


- (BOOL) hasShipyard
{
	if ([UNIVERSE strict])
		return NO;
	if ([UNIVERSE station] == self)
		return YES;
	if ([shipinfoDictionary objectForKey:@"hasShipyard"])
	{
		PlayerEntity	*player = [PlayerEntity sharedPlayer];
		NSObject		*determinant = [shipinfoDictionary objectForKey:@"hasShipyard"];
		if ([determinant isKindOfClass:[NSArray class]])
		{
			NSArray *conditions = (NSArray *)determinant;
			BOOL success = YES;
			unsigned i;
			for (i = 0; (i < [conditions count])&&(success); i++)
				success &= [player scriptTestCondition:(NSString *)[conditions objectAtIndex:i]];
			return success;
		}
		if ([determinant isKindOfClass:[NSNumber class]])
		{
			float chance = [(NSNumber*)determinant floatValue];;
			return (randf() < chance);
		}
	}
	return NO;
}


- (NSString*) description
{
#ifndef NDEBUG
	if (gDebugFlags & DEBUG_ENTITIES)
	{
		NSString* result = [[NSString alloc] initWithFormat:@"<StationEntity %@ %d (%@)%@%@ // %@>",
			name, universalID, roles, (UNIVERSE == nil)? @" (not in UNIVERSE)":@"", ([self isRotatingStation])? @" (rotating)":@"", collisionRegion];
		return [result autorelease];
	}
#endif
	return [NSString stringWithFormat:@"<StationEntity %@ %d>", name, universalID];
}


- (void)dumpSelfState
{
	NSMutableArray		*flags = nil;
	NSString			*flagsString = nil;
	NSString			*alertString = nil;
	
	[super dumpSelfState];
	
	switch (alert_level)
	{
		case STATION_ALERT_LEVEL_GREEN:
			alertString = @"green";
			break;
		
		case STATION_ALERT_LEVEL_YELLOW:
			alertString = @"yellow";
			break;
		
		case STATION_ALERT_LEVEL_RED:
			alertString = @"red";
			break;
		
		default:
			alertString = @"*** ERROR: UNKNOWN ALERT LEVEL ***";
	}
	
	OOLog(@"dumpState.stationEntity", @"Alert level: %@", alertString);
	OOLog(@"dumpState.stationEntity", @"Max police: %u", max_police);
	OOLog(@"dumpState.stationEntity", @"Max defence ships: %u", max_defense_ships);
	OOLog(@"dumpState.stationEntity", @"Police launched: %u", police_launched);
	OOLog(@"dumpState.stationEntity", @"Max scavengers: %u", max_scavengers);
	OOLog(@"dumpState.stationEntity", @"Scavengers launched: %u", scavengers_launched);
	OOLog(@"dumpState.stationEntity", @"Docked shuttles: %u", docked_shuttles);
	OOLog(@"dumpState.stationEntity", @"Docked traders: %u", docked_traders);
	OOLog(@"dumpState.stationEntity", @"Equivalent tech level: %i", equivalent_tech_level);
	OOLog(@"dumpState.stationEntity", @"Equipment price factor: %g", equipment_price_factor);
	
	flags = [NSMutableArray array];
	#define ADD_FLAG_IF_SET(x)		if (x) { [flags addObject:@#x]; }
	ADD_FLAG_IF_SET(no_docking_while_launching);
	if ([self isRotatingStation]) { [flags addObject:@"rotatingStation"]; }
	flagsString = [flags count] ? [flags componentsJoinedByString:@", "] : @"none";
	OOLog(@"dumpState.stationEntity", @"Flags: %@", flagsString);
}

@end


#ifndef NDEBUG

@implementation StationEntity (OOWireframeDockingBox)


- (void)drawEntity:(BOOL)immediate :(BOOL)translucent
{
	Vector				adjustedPosition;
	Vector				halfDimensions;
	
	[super drawEntity:immediate:translucent];
	
	if (gDebugFlags & DEBUG_BOUNDING_BOXES)
	{
		OODebugDrawBasisAtOrigin(50.0f);
		
		gl_matrix matrix;
		quaternion_into_gl_matrix(port_orientation, matrix);
		glPushMatrix();
		glMultMatrixf(matrix);
		
		halfDimensions = vector_multiply_scalar(port_dimensions, 0.5f);
		adjustedPosition = port_position;
		adjustedPosition.z -= halfDimensions.z;
		
		OODebugDrawColoredBoundingBoxBetween(vector_subtract(adjustedPosition, halfDimensions), vector_add(adjustedPosition, halfDimensions), [OOColor redColor]);
		OODebugDrawBasisAtOrigin(30.0f);
		
		glPopMatrix();
	}
}

@end

#endif
