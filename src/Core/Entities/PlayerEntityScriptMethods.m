/*

PlayerEntityScriptMethods.m

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

#import "PlayerEntityScriptMethods.h"

#import "Universe.h"
#import "OOCollectionExtractors.h"
#import "OOConstToString.h"


@implementation PlayerEntity (ScriptMethods)

- (NSString *) playerName
{
	return [[player_name retain] autorelease];
}


- (unsigned) score
{
	return ship_kills;
}


- (void) setScore:(unsigned)value
{
	ship_kills = value;
}


- (double)creditBalance
{
	return 0.1 * (double)credits;
}


- (void)setCreditBalance:(double)value
{
	value = round(value * 10.0);
	credits = OOClamp_0_max_d(value, (double)ULONG_MAX);
}


- (float)fuelLeakRate
{
	return fuel_leak_rate;
}


- (void)setFuelLeakRate:(float)value
{
	fuel_leak_rate = OOMax_f(value, 0.0f);
}


- (NSString *) dockedStationName
{
	return [(ShipEntity *)dockedStation name];
}


- (NSString *) dockedStationDisplayName
{
	return [(ShipEntity *)dockedStation displayName];
}


- (BOOL) dockedAtMainStation
{
	return status == STATUS_DOCKED && dockedStation == [UNIVERSE station];
}


- (BOOL) canAwardCargoType:(OOCargoType)type amount:(OOCargoQuantity)amount
{
	if (type == CARGO_NOT_CARGO)  return NO;
	if ([UNIVERSE unitsForCommodity:type] == UNITS_TONS)
	{
		if ([self specialCargo] != nil)  return NO;
		if (amount > [self availableCargoSpace])  return NO;
	}
	
	return YES;
}


- (void) awardCargoType:(OOCargoType)type amount:(OOCargoQuantity)amount
{
	OOMassUnit				unit;
	NSArray					*commodityArray = nil;
	
	commodityArray = [UNIVERSE commodityDataForType:type];
	if (commodityArray == nil)  return;
	
	OOLog(@"script.debug.note.awardCargo", @"Going to award cargo: %d x '%@'", amount, CommodityDisplayNameForCommodityArray(commodityArray));
	
	unit = [commodityArray intAtIndex:MARKET_UNITS];
	
	if (status != STATUS_DOCKED)
	{
		// in-flight
		while (amount)
		{
			if (unit != UNITS_TONS)
			{
				if (specialCargo)
				{
					NSMutableArray* manifest =  [NSMutableArray arrayWithArray:shipCommodityData];
					NSMutableArray* manifest_commodity =	[NSMutableArray arrayWithArray:(NSArray *)[manifest objectAtIndex:type]];
					int manifest_quantity = [(NSNumber *)[manifest_commodity objectAtIndex:MARKET_QUANTITY] intValue];
					manifest_quantity += amount;
					amount = 0;
					[manifest_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:manifest_quantity]];
					[manifest replaceObjectAtIndex:type withObject:[NSArray arrayWithArray:manifest_commodity]];
					[shipCommodityData release];
					shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
				}
				else
				{
					int amount_per_container = (unit == UNITS_KILOGRAMS)? 1000 : 1000000;
					while (amount > 0)
					{
						int smaller_quantity = 1 + ((amount - 1) % amount_per_container);
						if ([cargo count] < max_cargo)
						{
							ShipEntity* container = [UNIVERSE newShipWithRole:@"cargopod"];
							if (container)
							{
								// Shouldn't there be a [UNIVERSE addEntity:] here? -- Ahruman
								[container wasAddedToUniverse];
								[container setScanClass: CLASS_CARGO];
								[container setCommodity:type andAmount:smaller_quantity];
								[cargo addObject:container];
								[container release];
							}
						}
						amount -= smaller_quantity;
					}
				}
			}
			else
			{
				// put each ton in a separate container
				while (amount)
				{
					if ([cargo count] < max_cargo)
					{
						ShipEntity* container = [UNIVERSE newShipWithRole:@"cargopod"];
						if (container)
						{
							// Shouldn't there be a [UNIVERSE addEntity:] here? -- Ahruman
							[container wasAddedToUniverse];
							[container setScanClass: CLASS_CARGO];
							[container setStatus:STATUS_IN_HOLD];
							[container setCommodity:type andAmount:1];
							[cargo addObject:container];
							[container release];
						}
					}
					amount--;
				}
			}
		}
	}
	else
	{	// docked
		// like purchasing a commodity
		NSMutableArray* manifest =  [NSMutableArray arrayWithArray:shipCommodityData];
		NSMutableArray* manifest_commodity =	[NSMutableArray arrayWithArray:(NSArray *)[manifest objectAtIndex:type]];
		int manifest_quantity = [(NSNumber *)[manifest_commodity objectAtIndex:MARKET_QUANTITY] intValue];
		while ((amount)&&(current_cargo < max_cargo))
		{
			manifest_quantity++;
			amount--;
			if (unit == UNITS_TONS)
				current_cargo++;
		}
		[manifest_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:manifest_quantity]];
		[manifest replaceObjectAtIndex:type withObject:[NSArray arrayWithArray:manifest_commodity]];
		[shipCommodityData release];
		shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
	}
}


- (OOGalaxyID) currentGalaxyID
{
	return galaxy_number;
}


- (OOSystemID) currentSystemID
{
	if ([UNIVERSE sun] == nil)  return -1;	// Interstellar space
	return [UNIVERSE currentSystemID];
}


- (void) setMissionChoice:(NSString *)newChoice
{
	BOOL equal = [newChoice isEqualToString:missionChoice] || (newChoice == missionChoice);	// Catch both being nil as well
	if (!equal)
	{
		if (newChoice == nil)
		{
			NSString *oldChoice = missionChoice;
			[missionChoice autorelease];
			missionChoice = nil;
			
			[self doScriptEvent:@"missionChoiceWasReset" withArgument:oldChoice];
		}
		else
		{
			[missionChoice release];
			missionChoice = [newChoice copy];
		}
	}
}


- (OOTimeDelta) scriptTimer
{
	return script_time;
}


- (unsigned) systemPseudoRandom100
{
	seed_RNG_only_for_planet_description(system_seed);
	return (gen_rnd_number() * 256 + gen_rnd_number()) % 100;
}


- (unsigned) systemPseudoRandom256
{
	seed_RNG_only_for_planet_description(system_seed);
	return gen_rnd_number();
}


- (double) systemPseudoRandomFloat
{
	Random_Seed seed = system_seed;
	seed_RNG_only_for_planet_description(system_seed);
	unsigned a = gen_rnd_number();
	unsigned b = gen_rnd_number();
	unsigned c = gen_rnd_number();
	system_seed = seed;
	
	a = (a << 16) | (b << 8) | c;
	return (double)a / (double)0x01000000;
	
}

@end
