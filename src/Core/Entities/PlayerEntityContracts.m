/*

PlayerEntityContracts.m

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

#import "PlayerEntity.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "PlayerEntityContracts.h"
#import "PlayerEntityControls.h"
#import "Universe.h"
#import "AI.h"
#import "OOColor.h"
#import "OOCharacter.h"
#import "StationEntity.h"
#import "GuiDisplayGen.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"
#import "OOConstToString.h"
#import "MyOpenGLView.h"
#import "NSStringOOExtensions.h"
#import "OOShipRegistry.h"
#import "OOEquipmentType.h"


static NSString * const kOOLogNoteShowShipyardModel = @"script.debug.note.showShipyardModel";


@interface PlayerEntity (ContractsPrivate)

- (OOCreditsQuantity) tradeInValue;
- (NSArray*) contractsListFromArray:(NSArray *) contracts_array forCargo:(BOOL) forCargo;

@end


@implementation PlayerEntity (Contracts)

- (NSString *) processEscapePods // removes pods from cargo bay and treats categories of characters carried
{
	if ([UNIVERSE strict])  return [NSString string];	// return a blank string
	
	unsigned		i;
	BOOL added_entry = NO; // to prevent empty lines for slaves and the rare empty report.
	NSMutableString	*result = [NSMutableString string];
	NSMutableArray	*rescuees = [NSMutableArray array];
	OOGovernmentID	government = [[[UNIVERSE currentSystemData] objectForKey:KEY_GOVERNMENT] intValue];
	if ([UNIVERSE inInterstellarSpace])  government = 1;	// equivalent to Feudal. I'm assuming any station in interstellar space is military. -- Ahruman 2008-05-29
	
	// step through the cargo removing crew from any escape pods
	// No enumerator because we're mutating the array -- Ahruman
	for (i = 0; i < [cargo count]; i++)
	{
		ShipEntity	*cargoItem = [cargo objectAtIndex:i];
		NSArray		*podCrew = [cargoItem crew];
		
		if (podCrew != nil)
		{
			// Has crew -> is escape pod.
			[rescuees addObjectsFromArray:podCrew];
			[cargoItem setCrew:nil];
			[cargo removeObjectAtIndex:i];
			i--;
		}
	}
	
	// step through the rescuees awarding insurance or bounty or adding to slaves
	for (i = 0; i < [rescuees count]; i++)
	{
		OOCharacter* rescuee = (OOCharacter*)[rescuees objectAtIndex: i];
		if ([rescuee script])
		{
			[self runUnsanitizedScriptActions:[rescuee script]
							allowingAIMethods:YES
							  withContextName:[NSString stringWithFormat:@"<character \"%@\" script>", [rescuee name]]
									forTarget:nil];
		}
		else if ([rescuee insuranceCredits])
		{
			// claim insurance reward
			[result appendFormat:DESC(@"rescue-reward-for-@@-@-credits"),
				[rescuee name], [rescuee shortDescription], OOStringFromDeciCredits([rescuee insuranceCredits] * 10, YES, NO)];
			credits += 10 * [rescuee insuranceCredits];
			added_entry = YES;
		}
		else if ([rescuee legalStatus])
		{
			// claim bounty for capture
			float reward = (5.0 + government) * [rescuee legalStatus];
			[result appendFormat:DESC(@"capture-reward-for-@@-@-credits"),
				[rescuee name], [rescuee shortDescription], OOStringFromDeciCredits(reward, YES, NO)];
			credits += reward;
			added_entry = YES;
		}
		else
		{
			// sell as slave - increase no. of slaves in manifest
			[self awardCargo:@"1 Slaves"];
		}
		if ((i < [rescuees count] - 1) && added_entry)
			[result appendString:@"\n"];
		added_entry = NO;
	}
	
	[self calculateCurrentCargo];
	
	return result;
}


- (NSString *) checkPassengerContracts	// returns messages from any passengers whose status have changed
{
	if (dockedStation != [UNIVERSE station])	// only drop off passengers or fulfil contracts at main station
		return nil;
	
	// check escape pods...
	// TODO
	
	NSMutableString		*result = [NSMutableString string];
	unsigned			i;
	
	// check passenger contracts
	for (i = 0; i < [passengers count]; i++)
	{
		NSDictionary* passenger_info = (NSDictionary *)[passengers objectAtIndex:i];
		NSString* passenger_name = [passenger_info oo_stringForKey:PASSENGER_KEY_NAME];
		int dest = [passenger_info oo_intForKey:CONTRACT_KEY_DESTINATION];
		Random_Seed dest_seed = [UNIVERSE systemSeedForSystemNumber:dest];
		// the system name can change via script
		NSString* passenger_dest_name = [UNIVERSE getSystemName: dest_seed];
		int dest_eta = [passenger_info oo_doubleForKey:CONTRACT_KEY_ARRIVAL_TIME] - ship_clock;
		
		if (equal_seeds( system_seed, dest_seed))
		{
			// we've arrived in system!
			if (dest_eta > 0)
			{
				// and in good time
				long long fee = [passenger_info oo_longLongForKey:CONTRACT_KEY_FEE];
				while ((randf() < 0.75)&&(dest_eta > 3600))	// delivered with more than an hour to spare and a decent customer?
				{
					fee *= 110;	// tip + 10%
					fee /= 100;
					dest_eta *= 0.5;
				}
				credits += 10 * fee;
				
				[result appendFormatLine:DESC(@"passenger-delivered-okay-@-@-@"), passenger_name, OOIntCredits(fee), passenger_dest_name];
				
				[passengers removeObjectAtIndex:i--];
				[self increasePassengerReputation];
			}
			else
			{
				// but we're late!
				long long fee = [passenger_info oo_longLongForKey:CONTRACT_KEY_FEE] / 2;	// halve fare
				while (randf() < 0.5)	// maybe halve fare a few times!
					fee /= 2;
				credits += 10 * fee;
				
				[result appendFormatLine:DESC(@"passenger-delivered-late-@-@-@"), passenger_name, OOIntCredits(fee), passenger_dest_name];
				
				[passengers removeObjectAtIndex:i--];
			}
		}
		else
		{
			if (dest_eta < 0)
			{
				// we've run out of time!
				[result appendFormatLine:DESC(@"passenger-failed-@"), passenger_name];
				
				[passengers removeObjectAtIndex:i--];
				[self decreasePassengerReputation];
			}
		}
	}
	
	// check cargo contracts
	for (i = 0; i < [contracts count]; i++)
	{
		NSDictionary* contract_info = [contracts oo_dictionaryAtIndex:i];
		NSString* contract_cargo_desc = [contract_info oo_stringForKey:CARGO_KEY_DESCRIPTION];
		int dest = [contract_info oo_intForKey:CONTRACT_KEY_DESTINATION];
		int dest_eta = [contract_info oo_doubleForKey:CONTRACT_KEY_ARRIVAL_TIME] - ship_clock;
		
		int premium = 10 * [contract_info oo_floatForKey:CONTRACT_KEY_PREMIUM];
		int fee = 10 * [contract_info oo_floatForKey:CONTRACT_KEY_FEE];
		
		int contract_cargo_type = [contract_info oo_intForKey:CARGO_KEY_TYPE];
		int contract_amount = [contract_info oo_intForKey:CARGO_KEY_AMOUNT];
		
		NSMutableArray* manifest = [NSMutableArray arrayWithArray:shipCommodityData];
		NSMutableArray* commodityInfo = [NSMutableArray arrayWithArray:[manifest oo_arrayAtIndex:contract_cargo_type]];
		int quantity_on_hand =  [commodityInfo oo_intAtIndex:MARKET_QUANTITY];
		
		if (equal_seeds(system_seed, [UNIVERSE systemSeedForSystemNumber:dest]))
		{
			// we've arrived in system!
			if (dest_eta > 0)
			{
				// and in good time
				if (quantity_on_hand >= contract_amount)
				{
					// with the goods too!
					
					// remove the goods...
					quantity_on_hand -= contract_amount;
					[commodityInfo replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:quantity_on_hand]];
					[manifest replaceObjectAtIndex:contract_cargo_type withObject:commodityInfo];
					if (shipCommodityData)
						[shipCommodityData release];
					shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
					// pay the premium and fee
					credits += fee + premium;
					
					[result appendFormatLine:DESC(@"cargo-delivered-okay-@-@"), contract_cargo_desc, OOCredits(fee + premium)];
					
					[contracts removeObjectAtIndex:i--];
					// repute++
					[self increaseContractReputation];
				}
				else
				{
					// see if the amount of goods delivered is acceptable
					
					float percent_delivered = 100.0 * (float)quantity_on_hand/(float)contract_amount;
					float acceptable_ratio = 100.0 - 10.0 * system_seed.a / 256.0; // down to 90%
					
					if (percent_delivered >= acceptable_ratio)
					{
						// remove the goods...
						[commodityInfo replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:0]];
						[manifest replaceObjectAtIndex:contract_cargo_type withObject:commodityInfo];
						[shipCommodityData release];
						shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
						// pay the premium and fee
						int shortfall = 100 - percent_delivered;
						int payment = percent_delivered * (fee + premium) / 100.0;
						credits += payment;
						
						[result appendFormatLine:DESC(@"cargo-delivered-short-@-@-d"), contract_cargo_desc, OOCredits(payment), shortfall];
						
						[contracts removeObjectAtIndex:i--];
						// repute unchanged
					}
					else
					{
						[result appendFormatLine:DESC(@"cargo-refused-short-%@"), contract_cargo_desc];
						// The player has still time to buy the missing goods elsewhere and fulfil the contract.
					}
				}
			}
			else
			{
				// but we're late!
				[result appendFormatLine:DESC(@"cargo-delivered-late-@"), contract_cargo_desc];

				[contracts removeObjectAtIndex:i--];
				// repute--
				[self decreaseContractReputation];
			}
		}
		else
		{
			if (dest_eta < 0)
			{
				// we've run out of time!
				[result appendFormatLine:DESC(@"cargo-failed-@"), contract_cargo_desc];
				
				[contracts removeObjectAtIndex:i--];
				// repute--
				[self decreaseContractReputation];
			}
		}
	}
	
	// check passenger_record for expired contracts
	NSArray* names = [passenger_record allKeys];
	for (i = 0; i < [names count]; i++)
	{
		double dest_eta = [(NSNumber*)[passenger_record objectForKey:[names objectAtIndex:i]] doubleValue] - ship_clock;
		if (dest_eta < 0)
		{
			// check they're not STILL on board
			BOOL on_board = NO;
			unsigned j;
			for (j = 0; j < [passengers count]; j++)
			{
				NSDictionary* passenger_info = (NSDictionary *)[passengers objectAtIndex:j];
				if ([[passenger_info objectForKey:PASSENGER_KEY_NAME] isEqual:[names objectAtIndex:i]])
					on_board = YES;
			}
			if (!on_board)
			{
				[passenger_record removeObjectForKey:[names objectAtIndex:i]];
			}
		}
	}
	
	// check contract_record for expired contracts
	NSArray* ids = [contract_record allKeys];
	for (i = 0; i < [ids count]; i++)
	{
		double dest_eta = [(NSNumber*)[contract_record objectForKey:[ids objectAtIndex:i]] doubleValue] - ship_clock;
		if (dest_eta < 0)
		{
			[contract_record removeObjectForKey:[ids objectAtIndex:i]];
		}
	}
	
	if ([result length] == 0)
	{
		result = nil;
	}
	else
	{
		// Should have a trailing \n
		[result deleteCharacterAtIndex:[result length] - 1];
	}
	
	return result;
}


- (void) addMessageToReport:(NSString*) report
{
	if ([report length] != 0)
	{
		if ([dockingReport length] == 0)
			[dockingReport appendString:report];
		else
			[dockingReport appendFormat:@"\n\n%@", report];
	}
}


- (NSDictionary*) reputation
{
	return reputation;
}


- (int) passengerReputation
{
	int good = [reputation oo_intForKey:PASSAGE_GOOD_KEY];
	int bad = [reputation oo_intForKey:PASSAGE_BAD_KEY];
	int unknown = [reputation oo_intForKey:PASSAGE_UNKNOWN_KEY];
	
	if (unknown > 0)
		unknown = 7 - (market_rnd % unknown);
	else
		unknown = 7;
	
	return (good + unknown - 2 * bad) / 2;	// return a number from -7 to +7
}


- (void) increasePassengerReputation
{
	int good = [reputation oo_intForKey:PASSAGE_GOOD_KEY];
	int bad = [reputation oo_intForKey:PASSAGE_BAD_KEY];
	int unknown = [reputation oo_intForKey:PASSAGE_UNKNOWN_KEY];
	
	if (bad > 0)
	{
		// shift a bean from bad to unknown
		bad--;
		if (unknown < 7)
			unknown++;
	}
	else
	{
		// shift a bean from unknown to good
		if (unknown > 0)
			unknown--;
		if (good < 7)
			good++;
	}
	[reputation oo_setInteger:good		forKey:PASSAGE_GOOD_KEY];
	[reputation oo_setInteger:bad		forKey:PASSAGE_BAD_KEY];
	[reputation oo_setInteger:unknown	forKey:PASSAGE_UNKNOWN_KEY];
}


- (void) decreasePassengerReputation
{
	int good = [reputation oo_intForKey:PASSAGE_GOOD_KEY];
	int bad = [reputation oo_intForKey:PASSAGE_BAD_KEY];
	int unknown = [reputation oo_intForKey:PASSAGE_UNKNOWN_KEY];
	
	if (good > 0)
	{
		// shift a bean from good to bad
		good--;
		if (bad < 7)
			bad++;
	}
	else
	{
		// shift a bean from unknown to bad
		if (unknown > 0)
			unknown--;
		if (bad < 7)
			bad++;
	}
	[reputation oo_setInteger:good		forKey:PASSAGE_GOOD_KEY];
	[reputation oo_setInteger:bad		forKey:PASSAGE_BAD_KEY];
	[reputation oo_setInteger:unknown	forKey:PASSAGE_UNKNOWN_KEY];
}


- (int) contractReputation
{
	int good = [reputation oo_intForKey:CONTRACTS_GOOD_KEY];
	int bad = [reputation oo_intForKey:CONTRACTS_BAD_KEY];
	int unknown = [reputation oo_intForKey:CONTRACTS_UNKNOWN_KEY];
	
	if (unknown > 0)
		unknown = 7 - (market_rnd % unknown);
	else
		unknown = 7;
	
	return (good + unknown - 2 * bad) / 2;	// return a number from -7 to +7
}


- (void) increaseContractReputation
{
	int good = [reputation oo_intForKey:CONTRACTS_GOOD_KEY];
	int bad = [reputation oo_intForKey:CONTRACTS_BAD_KEY];
	int unknown = [reputation oo_intForKey:CONTRACTS_UNKNOWN_KEY];
	
	if (bad > 0)
	{
		// shift a bean from bad to unknown
		bad--;
		if (unknown < 7)
			unknown++;
	}
	else
	{
		// shift a bean from unknown to good
		if (unknown > 0)
			unknown--;
		if (good < 7)
			good++;
	}
	[reputation oo_setInteger:good		forKey:CONTRACTS_GOOD_KEY];
	[reputation oo_setInteger:bad		forKey:CONTRACTS_BAD_KEY];
	[reputation oo_setInteger:unknown	forKey:CONTRACTS_UNKNOWN_KEY];
}


- (void) decreaseContractReputation
{
	int good = [reputation oo_intForKey:CONTRACTS_GOOD_KEY];
	int bad = [reputation oo_intForKey:CONTRACTS_BAD_KEY];
	int unknown = [reputation oo_intForKey:CONTRACTS_UNKNOWN_KEY];
	
	if (good > 0)
	{
		// shift a bean from good to bad
		good--;
		if (bad < 7)
			bad++;
	}
	else
	{
		// shift a bean from unknown to bad
		if (unknown > 0)
			unknown--;
		if (bad < 7)
			bad++;
	}
	[reputation oo_setInteger:good		forKey:CONTRACTS_GOOD_KEY];
	[reputation oo_setInteger:bad		forKey:CONTRACTS_BAD_KEY];
	[reputation oo_setInteger:unknown	forKey:CONTRACTS_UNKNOWN_KEY];
}


- (void) erodeReputation
{
	int c_good = [reputation oo_intForKey:CONTRACTS_GOOD_KEY];
	int c_bad = [reputation oo_intForKey:CONTRACTS_BAD_KEY];
	int c_unknown = [reputation oo_intForKey:CONTRACTS_UNKNOWN_KEY];
	int p_good = [reputation oo_intForKey:PASSAGE_GOOD_KEY];
	int p_bad = [reputation oo_intForKey:PASSAGE_BAD_KEY];
	int p_unknown = [reputation oo_intForKey:PASSAGE_UNKNOWN_KEY];
	
	if (c_unknown < 7)
	{
		if (c_bad > 0)
			c_bad--;
		else
		{
			if (c_good > 0)
				c_good--;
		}
		c_unknown++;
	}
	
	if (p_unknown < 7)
	{
		if (p_bad > 0)
			p_bad--;
		else
		{
			if (p_good > 0)
				p_good--;
		}
		p_unknown++;
	}
	
	[reputation setObject:[NSNumber numberWithInt:c_good]		forKey:CONTRACTS_GOOD_KEY];
	[reputation setObject:[NSNumber numberWithInt:c_bad]		forKey:CONTRACTS_BAD_KEY];
	[reputation setObject:[NSNumber numberWithInt:c_unknown]	forKey:CONTRACTS_UNKNOWN_KEY];
	[reputation setObject:[NSNumber numberWithInt:p_good]		forKey:PASSAGE_GOOD_KEY];
	[reputation setObject:[NSNumber numberWithInt:p_bad]		forKey:PASSAGE_BAD_KEY];
	[reputation setObject:[NSNumber numberWithInt:p_unknown]	forKey:PASSAGE_UNKNOWN_KEY];
	
}

- (void) setGuiToContractsScreen
{
	unsigned		i;
	NSMutableArray	*row_info = [NSMutableArray arrayWithCapacity:5];
	
	// set up initial markets if there are none
	StationEntity* the_station = [UNIVERSE station];
	if (![the_station localPassengers])
		[the_station setLocalPassengers:[NSMutableArray arrayWithArray:[UNIVERSE passengersForSystem:system_seed atTime:ship_clock]]];
	if (![the_station localContracts])
		[the_station setLocalContracts:[NSMutableArray arrayWithArray:[UNIVERSE contractsForSystem:system_seed atTime:ship_clock]]];
		
	NSMutableArray* passenger_market = [the_station localPassengers];
	NSMutableArray* contract_market = [the_station localContracts];
	
	// remove passenger contracts that the player has already agreed to or done
	for (i = 0; i < [passenger_market count]; i++)
	{
		NSDictionary* info = [passenger_market oo_dictionaryAtIndex:i];
		NSString* p_name = [info oo_stringForKey:PASSENGER_KEY_NAME];
		if ([passenger_record objectForKey:p_name])
			[passenger_market removeObjectAtIndex:i--];
	}

	// remove cargo contracts that the player has already agreed to or done
	for (i = 0; i < [contract_market count]; i++)
	{
		NSDictionary* info = [contract_market oo_dictionaryAtIndex:i];
		NSString* cid = [info oo_stringForKey:CARGO_KEY_ID];
		if ([contract_record objectForKey:cid])
			[contract_market removeObjectAtIndex:i--];
	}
		
	// if there are more than 5 contracts remove cargo contracts that are larger than the space available or cost more than can be afforded
	for (i = 0; ([contract_market count] > 5) && (i < [contract_market count]); i++)
	{
		NSDictionary	*info = [contract_market objectAtIndex:i];
		OOCargoQuantity	cargoSpaceRequired = [info oo_unsignedIntForKey:CARGO_KEY_AMOUNT];
		OOMassUnit		cargoUnits = [UNIVERSE unitsForCommodity:[info oo_intForKey:CARGO_KEY_TYPE]];
		
		if (cargoUnits == UNITS_KILOGRAMS)  cargoSpaceRequired /= 1000;
		if (cargoUnits == UNITS_GRAMS)  cargoSpaceRequired /= 1000000;
		
		float premium = [info oo_floatForKey:CONTRACT_KEY_PREMIUM];
		if ((cargoSpaceRequired > max_cargo - current_cargo)||(premium * 10 > credits))
			[contract_market removeObjectAtIndex:i--];
	}
		
	// GUI stuff
	{
		GuiDisplayGen *gui = [UNIVERSE gui];
		
		unsigned n_passengers = [passenger_market count];
		if (n_passengers > 5)
			n_passengers = 5;
		unsigned n_contracts = [contract_market count];
		if (n_contracts > 5)
			n_contracts = 5;
		
		[gui clear];
		[gui setTitle:[NSString stringWithFormat:DESC(@"@-contracts-title"),[UNIVERSE getSystemName:system_seed]]];
		
		OOGUITabSettings tab_stops;
		tab_stops[0] = 0;
		tab_stops[1] = 160;
		tab_stops[2] = 240;
		tab_stops[3] = -410;
		tab_stops[4] = -476;
		
		[gui setTabStops:tab_stops];
		
		[row_info addObject:DESC(@"contracts-passenger-name")];
		[row_info addObject:DESC(@"contracts-to")];
		[row_info addObject:DESC(@"contracts-within")];
		[row_info addObject:DESC(@"contracts-passenger-advance")];
		[row_info addObject:DESC(@"contracts-passenger-fee")];
		
		[gui setColor:[OOColor greenColor] forRow:GUI_ROW_PASSENGERS_LABELS];
		[gui setArray:[NSArray arrayWithArray:row_info] forRow:GUI_ROW_PASSENGERS_LABELS];
		
		BOOL can_take_passengers = (max_passengers > [passengers count]);
		
		for (i = 0; i < n_passengers; i++)
		{
			NSDictionary* passenger_info = [passenger_market oo_dictionaryAtIndex:i];
			NSString *Name = [passenger_info oo_stringForKey:PASSENGER_KEY_NAME];
			if([Name length] >27)	Name =[[Name substringToIndex:25] stringByAppendingString:@"..."];
			int dest_eta = [passenger_info oo_doubleForKey:CONTRACT_KEY_ARRIVAL_TIME] - ship_clock;
			[row_info removeAllObjects];
			[row_info addObject:[NSString stringWithFormat:@" %@ ",Name]];
			[row_info addObject:[NSString stringWithFormat:@" %@ ",[passenger_info oo_stringForKey:CONTRACT_KEY_DESTINATION_NAME]]];
			[row_info addObject:[NSString stringWithFormat:@" %@ ",[UNIVERSE shortTimeDescription:dest_eta]]];
			[row_info addObject:[NSString stringWithFormat:@" %@ ",[passenger_info oo_stringForKey:CONTRACT_KEY_PREMIUM]]];
			[row_info addObject:[NSString stringWithFormat:@" %@ ",[passenger_info oo_stringForKey:CONTRACT_KEY_FEE]]];
			[gui setColor:[OOColor yellowColor] forRow:GUI_ROW_PASSENGERS_START + i];
			[gui setArray:[NSArray arrayWithArray:row_info] forRow:GUI_ROW_PASSENGERS_START + i];
			if (can_take_passengers)
				[gui setKey:GUI_KEY_OK forRow:GUI_ROW_PASSENGERS_START + i];
			else
			{
				[gui setKey:GUI_KEY_SKIP forRow:GUI_ROW_PASSENGERS_START + i];
				[gui setColor:[OOColor grayColor] forRow:GUI_ROW_PASSENGERS_START + i];
			}
		}
		
		[row_info removeAllObjects];
		[row_info addObject:DESC(@"contracts-cargo-cargotype")];
		[row_info addObject:DESC(@"contracts-to")];
		[row_info addObject:DESC(@"contracts-within")];
		[row_info addObject:DESC(@"contracts-cargo-premium")];
		[row_info addObject:DESC(@"contracts-cargo-pays")];
		
		[gui setColor:[OOColor greenColor] forRow:GUI_ROW_CARGO_LABELS];
		[gui setArray:[NSArray arrayWithArray:row_info] forRow:GUI_ROW_CARGO_LABELS];
		
		for (i = 0; i < n_contracts; i++)
		{
			NSDictionary		*contract_info = [contract_market oo_dictionaryAtIndex:i];
			OOCargoQuantity		cargo_space_required = [contract_info oo_unsignedIntForKey:CARGO_KEY_AMOUNT];
			OOMassUnit			cargo_units = [UNIVERSE unitsForCommodity:[contract_info oo_unsignedIntForKey:CARGO_KEY_TYPE]];
			if (cargo_units == UNITS_KILOGRAMS)	cargo_space_required /= 1000;
			if (cargo_units == UNITS_GRAMS)		cargo_space_required /= 1000000;
			
			float premium = [(NSNumber *)[contract_info objectForKey:CONTRACT_KEY_PREMIUM] floatValue];
			BOOL not_possible = ((cargo_space_required > max_cargo - current_cargo)||(premium * 10 > credits));
			int dest_eta = [(NSNumber*)[contract_info objectForKey:CONTRACT_KEY_ARRIVAL_TIME] doubleValue] - ship_clock;
			[row_info removeAllObjects];
			[row_info addObject:[NSString stringWithFormat:@" %@ ",[contract_info objectForKey:CARGO_KEY_DESCRIPTION]]];
			[row_info addObject:[NSString stringWithFormat:@" %@ ",[contract_info objectForKey:CONTRACT_KEY_DESTINATION_NAME]]];
			[row_info addObject:[NSString stringWithFormat:@" %@ ",[UNIVERSE shortTimeDescription:dest_eta]]];
			[row_info addObject:[NSString stringWithFormat:@" %@ ",[contract_info oo_stringForKey:CONTRACT_KEY_PREMIUM]]];
			[row_info addObject:[NSString stringWithFormat:@" %@ ",[contract_info oo_stringForKey:CONTRACT_KEY_FEE]]];
			[gui setColor:[OOColor yellowColor] forRow:GUI_ROW_CARGO_START + i];
			[gui setArray:[NSArray arrayWithArray:row_info] forRow:GUI_ROW_CARGO_START + i];
			if (not_possible)
			{
				[gui setKey:GUI_KEY_SKIP forRow:GUI_ROW_CARGO_START + i];
				[gui setColor:[OOColor grayColor] forRow:GUI_ROW_CARGO_START + i];
			}
			else
				[gui setKey:GUI_KEY_OK forRow:GUI_ROW_CARGO_START + i];
		}
		
		[gui setText:[NSString stringWithFormat:DESC_PLURAL(@"contracts-cash-@-load-d-of-d-passengers-d-of-d-berths", max_passengers), OOCredits(credits), current_cargo, max_cargo, [passengers count], max_passengers]  forRow: GUI_ROW_MARKET_CASH];
		
		for (i = GUI_ROW_CARGO_START + n_contracts; i < GUI_ROW_MARKET_CASH; i++)
		{
			[gui setText:@"" forRow:i];
			[gui setColor:[OOColor greenColor] forRow:i];
		}
		
		[gui setSelectableRange:NSMakeRange(GUI_ROW_PASSENGERS_START, GUI_ROW_CARGO_START + n_contracts)];
		if ([[gui selectedRowKey] isEqual:GUI_KEY_SKIP])
			[gui setFirstSelectableRow];
		
		if (([gui selectedRow] >= GUI_ROW_PASSENGERS_START)&&([gui selectedRow] < (int)(GUI_ROW_PASSENGERS_START + n_passengers)))
		{
			NSString* long_info = (NSString*)[(NSDictionary*)[passenger_market objectAtIndex:[gui selectedRow] - GUI_ROW_PASSENGERS_START] objectForKey:CONTRACT_KEY_LONG_DESCRIPTION];
			[gui addLongText:long_info startingAtRow:GUI_ROW_CONTRACT_INFO_START align:GUI_ALIGN_LEFT];
		}
		if (([gui selectedRow] >= GUI_ROW_CARGO_START)&&([gui selectedRow] < (int)(GUI_ROW_CARGO_START + n_contracts)))
		{
			NSString* long_info = [[contract_market oo_dictionaryAtIndex:[gui selectedRow] - GUI_ROW_CARGO_START] oo_stringForKey:CONTRACT_KEY_LONG_DESCRIPTION];
			[gui addLongText:long_info startingAtRow:GUI_ROW_CONTRACT_INFO_START align:GUI_ALIGN_LEFT];
		}
		
		[gui setShowTextCursor:NO];
	}
	
	OOGUIScreenID oldScreen = gui_screen;
	gui_screen = GUI_SCREEN_CONTRACTS;

	[self setShowDemoShips: NO];
	[UNIVERSE setDisplayText: YES];
	[UNIVERSE setDisplayCursor: YES];
	[UNIVERSE setViewDirection: VIEW_GUI_DISPLAY];
	
	[self noteGuiChangeFrom:oldScreen to:gui_screen];
}


- (BOOL) addPassenger:(NSString*)Name start:(unsigned)start destination:(unsigned)Destination eta:(double)eta fee:(double)fee
{
	NSDictionary* passenger_info = [NSDictionary dictionaryWithObjectsAndKeys:
		Name,																	PASSENGER_KEY_NAME,
		[NSNumber numberWithInt:start],											CONTRACT_KEY_START,
		[NSNumber numberWithInt:Destination],									CONTRACT_KEY_DESTINATION,
		[NSNumber numberWithDouble:[[PlayerEntity sharedPlayer] clockTime]],	CONTRACT_KEY_DEPARTURE_TIME,
		[NSNumber numberWithDouble:eta],										CONTRACT_KEY_ARRIVAL_TIME,
		[NSNumber numberWithDouble:fee],										CONTRACT_KEY_FEE,
		[NSNumber numberWithInt:0],												CONTRACT_KEY_PREMIUM,
		NULL];
	
	// extra check, just in case. TODO: stop adding passengers with duplicate names?
	if ([passengers count] >= max_passengers) return NO;

	[passengers addObject:passenger_info];
	[passenger_record setObject:[NSNumber numberWithDouble:eta] forKey:Name];
	return YES;
}


- (BOOL) awardContract:(unsigned)qty commodity:(NSString*)commodity start:(unsigned)start
						destination:(unsigned)Destination eta:(double)eta fee:(double)fee
{
	OOCargoType Type = [UNIVERSE commodityForName: commodity];
	Random_Seed r_seed = [UNIVERSE marketSeed];
	int 		sr1 = r_seed.a * 0x10000 + r_seed.c * 0x100 + r_seed.e;
	int 		sr2 = r_seed.b * 0x10000 + r_seed.d * 0x100 + r_seed.f;
	NSString	*cargo_ID =[NSString stringWithFormat:@"%06x-%06x", sr1, sr2];
	
	// avoid duplicate cargo_IDs
	while ([contract_record objectForKey:cargo_ID] != nil)
	{
		sr2++;
		cargo_ID =[NSString stringWithFormat:@"%06x-%06x", sr1, sr2];
	}

	NSDictionary* cargo_info = [NSDictionary dictionaryWithObjectsAndKeys:
		cargo_ID,																CARGO_KEY_ID,
		[NSNumber numberWithInt:Type],											CARGO_KEY_TYPE,
		[NSNumber numberWithInt:qty],											CARGO_KEY_AMOUNT,
		[UNIVERSE describeCommodity:Type amount:qty],							CARGO_KEY_DESCRIPTION,
		[NSNumber numberWithInt:start],											CONTRACT_KEY_START,
		[NSNumber numberWithInt:Destination],									CONTRACT_KEY_DESTINATION,
		[NSNumber numberWithDouble:[[PlayerEntity sharedPlayer] clockTime]],	CONTRACT_KEY_DEPARTURE_TIME,
		[NSNumber numberWithDouble:eta],										CONTRACT_KEY_ARRIVAL_TIME,
		[NSNumber numberWithDouble:fee],										CONTRACT_KEY_FEE,
		[NSNumber numberWithInt:0],												CONTRACT_KEY_PREMIUM,
		NULL];
	
	// check available space
	
	OOCargoQuantity		cargoSpaceRequired = qty;
	OOMassUnit			contractCargoUnits	= [UNIVERSE unitsForCommodity:Type];
	
	if (contractCargoUnits == UNITS_KILOGRAMS)  cargoSpaceRequired /= 1000;
	if (contractCargoUnits == UNITS_GRAMS)  cargoSpaceRequired /= 1000000;
	
	if (cargoSpaceRequired > max_cargo - current_cargo) return NO;
	
	NSMutableArray* manifest =  [NSMutableArray arrayWithArray:shipCommodityData];
	NSMutableArray* manifest_commodity = [NSMutableArray arrayWithArray:[manifest oo_arrayAtIndex:Type]];
	qty += [manifest_commodity oo_intAtIndex:MARKET_QUANTITY];
	[manifest_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:qty]];
	[manifest replaceObjectAtIndex:Type withObject:[NSArray arrayWithArray:manifest_commodity]];

	[shipCommodityData release];
	shipCommodityData = [[NSArray arrayWithArray:manifest] retain];

	current_cargo = [self cargoQuantityOnBoard];

	[contracts addObject:cargo_info];
	[contract_record setObject:[NSNumber numberWithDouble:eta] forKey:cargo_ID];

	return YES;
}


- (BOOL) pickFromGuiContractsScreen
{
	GuiDisplayGen* gui = [UNIVERSE gui];
	
	NSMutableArray* passenger_market = [[UNIVERSE station] localPassengers];
	NSMutableArray* contract_market = [[UNIVERSE station] localContracts];
	
	if (([gui selectedRow] >= GUI_ROW_PASSENGERS_START)&&([gui selectedRow] < GUI_ROW_CARGO_START))
	{
		NSDictionary* passenger_info = (NSDictionary*)[passenger_market objectAtIndex:[gui selectedRow] - GUI_ROW_PASSENGERS_START];
		NSString* passenger_name = [passenger_info oo_stringForKey:PASSENGER_KEY_NAME];
		NSNumber* passenger_arrival_time = (NSNumber*)[passenger_info objectForKey:CONTRACT_KEY_ARRIVAL_TIME];
		int passenger_premium = [passenger_info oo_intForKey:CONTRACT_KEY_PREMIUM];
		if ([passengers count] >= max_passengers)
			return NO;
		[passengers addObject:passenger_info];
		[passenger_record setObject:passenger_arrival_time forKey:passenger_name];
		[passenger_market removeObject:passenger_info];
		credits += 10 * passenger_premium;
		
		if ([UNIVERSE autoSave]) [UNIVERSE setAutoSaveNow:YES];
		
		return YES;
	}
	
	if (([gui selectedRow] >= GUI_ROW_CARGO_START)&&([gui selectedRow] < GUI_ROW_MARKET_CASH))
	{
		NSDictionary		*contractInfo = nil;
		NSString			*contractID = nil;
		NSNumber			*contractArrivalTime = nil;
		OOCreditsQuantity	contractPremium;
		OOCargoQuantity		contractAmount;
		OOCargoType			contractCargoType;
		OOMassUnit			contractCargoUnits;
		OOCargoQuantity		cargoSpaceRequired;
		
		contractInfo		= [contract_market objectAtIndex:[gui selectedRow] - GUI_ROW_CARGO_START];
		contractID			= [contractInfo oo_stringForKey:CARGO_KEY_ID];
		contractArrivalTime	= [contractInfo oo_objectOfClass:[NSNumber class] forKey:CONTRACT_KEY_ARRIVAL_TIME];
		contractPremium		= [contractInfo oo_intForKey:CONTRACT_KEY_PREMIUM];
		contractAmount		= [contractInfo oo_intForKey:CARGO_KEY_AMOUNT];
		contractCargoType	= [contractInfo oo_intForKey:CARGO_KEY_TYPE];
		contractCargoUnits	= [UNIVERSE unitsForCommodity:contractCargoType];
		
		cargoSpaceRequired = contractAmount;
		if (contractCargoUnits == UNITS_KILOGRAMS)  cargoSpaceRequired /= 1000;
		if (contractCargoUnits == UNITS_GRAMS)  cargoSpaceRequired /= 1000000;
		
		// tests for refusal...
		if (cargoSpaceRequired > max_cargo - current_cargo)	// no room for cargo
			return NO;
			
		if (contractPremium * 10 > credits)					// can't afford contract
			return NO;
			
		// okay passed all tests ...
		
		// pay the premium
		credits -= 10 * contractPremium;
		// add commodity to what's being carried
		NSMutableArray* manifest =  [NSMutableArray arrayWithArray:shipCommodityData];
		NSMutableArray* manifest_commodity =	[NSMutableArray arrayWithArray:[manifest objectAtIndex:contractCargoType]];
		int manifest_quantity = [(NSNumber *)[manifest_commodity objectAtIndex:MARKET_QUANTITY] intValue];
		manifest_quantity += contractAmount;
		[manifest_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:manifest_quantity]];
		[manifest replaceObjectAtIndex:contractCargoType withObject:[NSArray arrayWithArray:manifest_commodity]];
		[shipCommodityData release];
		shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
		current_cargo = [self cargoQuantityOnBoard];
		
		[contracts addObject:contractInfo];
		[contract_record setObject:contractArrivalTime forKey:contractID];
		[contract_market removeObject:contractInfo];
		
		if ([UNIVERSE autoSave]) [UNIVERSE setAutoSaveNow:YES];
		
		return YES;
	}
	return NO;
}


- (void) highlightSystemFromGuiContractsScreen
{
	GuiDisplayGen	*gui = [UNIVERSE gui];

	NSArray			*passenger_market = [[UNIVERSE station] localPassengers];
	NSArray			*contract_market = [[UNIVERSE station] localContracts];

	NSDictionary	*contract_info = nil;
	NSString 		*dest_name = nil;
	
	if (([gui selectedRow] < GUI_ROW_CARGO_START) && ([gui selectedRow] >= GUI_ROW_PASSENGERS_START))
	{
		contract_info = (NSDictionary*)[passenger_market objectAtIndex:[gui selectedRow] - GUI_ROW_PASSENGERS_START];
	}
	else if (([gui selectedRow] >= GUI_ROW_CARGO_START) && ([gui selectedRow] < GUI_ROW_MARKET_CASH))
	{
		contract_info = (NSDictionary*)[contract_market objectAtIndex:[gui selectedRow] - GUI_ROW_CARGO_START];
	}
	dest_name = [contract_info oo_stringForKey:CONTRACT_KEY_DESTINATION_NAME];
	
	[self setGuiToLongRangeChartScreen];
	[UNIVERSE findSystemCoordinatesWithPrefix:[dest_name lowercaseString] exactMatch:YES]; // if dest_name is 'Ra', make sure there's only 1 result.
	[self targetNewSystem:1]; // now highlight the 1 result found.
}


- (NSArray*) passengerList
{
	return [self contractsListFromArray:passengers forCargo:NO];
}


- (NSArray*) contractList
{
	return [self contractsListFromArray:contracts forCargo:YES];
}


- (NSArray*) contractsListFromArray:(NSArray *) contracts_array forCargo:(BOOL) forCargo
{
	// check  contracts
	NSMutableArray	*result = [NSMutableArray arrayWithCapacity:5];
	NSString		*formatString = forCargo ? DESC(@"manifest-deliver-@-to-@within-@")
											: DESC(@"manifest-@-travelling-to-@-to-arrive-within-@");
	unsigned i;
	for (i = 0; i < [contracts_array count]; i++)
	{
		NSDictionary* contract_info = (NSDictionary *)[contracts_array objectAtIndex:i];
		NSString* label = [contract_info oo_stringForKey:forCargo ? CARGO_KEY_DESCRIPTION : PASSENGER_KEY_NAME];
		// the system name can change via script. The following PASSENGER_KEYs are identical to the corresponding CONTRACT_KEYs
		NSString* dest_name = [UNIVERSE getSystemName: [UNIVERSE systemSeedForSystemNumber:[contract_info oo_intForKey:CONTRACT_KEY_DESTINATION]]];
		int dest_eta = [contract_info oo_doubleForKey:CONTRACT_KEY_ARRIVAL_TIME] - ship_clock;
		[result addObject:[NSString stringWithFormat:formatString, label, dest_name, [UNIVERSE shortTimeDescription:dest_eta]]];
	}
	
	return result;
}


- (void) setGuiToManifestScreen
{	
	// GUI stuff
	{
		GuiDisplayGen* gui = [UNIVERSE gui];
		unsigned i = 0;
		
		unsigned	n_manifest_rows = 8;
		OOGUIRow	cargo_row = 2;
		OOGUIRow	passenger_row = 2;
		OOGUIRow	contracts_row = 2;
		OOGUIRow	missions_row = 2;
		
		OOGUITabSettings tab_stops;
		tab_stops[0] = 20;
		tab_stops[1] = 256;
		[gui setTabStops:tab_stops];
		
		NSArray*	cargoManifest = [self cargoList];
		NSArray*	passengerManifest = [self passengerList];
		NSArray*	contractManifest = [self contractList];
		NSArray*	missionsManifest = [self missionsList];
		
		unsigned rating = 0;
		unsigned kills[8] = { 0x0008,  0x0010,  0x0020,  0x0040,  0x0080,  0x0200,  0x0A00,  0x1900 };
		while ((rating < 8)&&(kills[rating] <= ship_kills))
		{
			rating ++;
		}
		
		current_cargo = [self cargoQuantityOnBoard];

		[gui clear];
		[gui setTitle:DESC(@"manifest-title")];
		
		[gui setText:[NSString stringWithFormat:DESC(@"manifest-cargo-d-d"), current_cargo, max_cargo]	forRow:cargo_row - 1];
		[gui setText:DESC(@"manifest-none")	forRow:cargo_row];
		[gui setColor:[OOColor yellowColor]	forRow:cargo_row - 1];
		[gui setColor:[OOColor greenColor]	forRow:cargo_row];
		
		if ([cargoManifest count] > 0)
		{
			for (i = 0; i < n_manifest_rows; i++)
			{
				NSMutableArray*		row_info = [NSMutableArray arrayWithCapacity:2];
				if (i < [cargoManifest count])
					[row_info addObject:[cargoManifest objectAtIndex:i]];
				else
					[row_info addObject:@""];
				if (i + n_manifest_rows < [cargoManifest count])
					[row_info addObject:[cargoManifest objectAtIndex:i + n_manifest_rows]];
				else
					[row_info addObject:@""];
				[gui setArray:(NSArray *)row_info forRow:cargo_row + i];
				[gui setColor:[OOColor greenColor] forRow:cargo_row + i];
			}
		}
		
		if ([cargoManifest count] < n_manifest_rows)
			passenger_row = cargo_row + [cargoManifest count] + 2;
		else
			passenger_row = cargo_row + n_manifest_rows + 2;
		
		[gui setText:[NSString stringWithFormat:DESC(@"manifest-passengers-d-d"), [passengerManifest count], max_passengers]	forRow:passenger_row - 1];
		[gui setText:DESC(@"manifest-none")	forRow:passenger_row];
		[gui setColor:[OOColor yellowColor]	forRow:passenger_row - 1];
		[gui setColor:[OOColor greenColor]	forRow:passenger_row];
		
		if ([passengerManifest count] > 0)
		{
			for (i = 0; i < [passengerManifest count]; i++)
			{
				[gui setText:(NSString*)[passengerManifest objectAtIndex:i] forRow:passenger_row + i];
				[gui setColor:[OOColor greenColor] forRow:passenger_row + i];
			}
		}
				
		contracts_row = passenger_row + [passengerManifest count] + 2;
		
		[gui setText:DESC(@"manifest-contracts")	forRow:contracts_row - 1];
		[gui setText:DESC(@"manifest-none")		forRow:contracts_row];
		[gui setColor:[OOColor yellowColor]	forRow:contracts_row - 1];
		[gui setColor:[OOColor greenColor]	forRow:contracts_row];
		
		if ([contractManifest count] > 0)
		{
			for (i = 0; i < [contractManifest count]; i++)
			{
				[gui setText:(NSString*)[contractManifest objectAtIndex:i] forRow:contracts_row + i];
				[gui setColor:[OOColor greenColor] forRow:contracts_row + i];
			}
		}
		
		if ([missionsManifest count] > 0)
		{
			missions_row = contracts_row + [contractManifest count] + 2;
			
			[gui setText:DESC(@"manifest-missions")	forRow:missions_row - 1];
			[gui setColor:[OOColor yellowColor]	forRow:missions_row - 1];
			
			if ([missionsManifest count] > 0)
			{
				for (i = 0; i < [missionsManifest count]; i++)
				{
					[gui setText:(NSString*)[missionsManifest objectAtIndex:i] forRow:missions_row + i];
					[gui setColor:[OOColor greenColor] forRow:missions_row + i];
				}
			}
		}
		[gui setShowTextCursor:NO];
	}
	/* ends */
	
	if (lastTextKey)
	{
		[lastTextKey release];
		lastTextKey = nil;
	}
	
	OOGUIScreenID oldScreen = gui_screen;
	gui_screen = GUI_SCREEN_MANIFEST;

	[self setShowDemoShips: NO];
	[UNIVERSE setDisplayText: YES];
	[UNIVERSE setDisplayCursor: NO];
	[UNIVERSE setViewDirection: VIEW_GUI_DISPLAY];
	
	[self noteGuiChangeFrom:oldScreen to:gui_screen];
}


- (void) setGuiToDeliveryReportScreenWithText:(NSString*) report
{
	GuiDisplayGen* gui = [UNIVERSE gui];
	
	
	// GUI stuff
	{
		[gui clear];
		[gui setTitle:ExpandDescriptionForCurrentSystem(@"[arrival-report-title]")];
		
		// report might be a multi-line message
		
		if ([report rangeOfString:@"\n"].location != NSNotFound)
		{
			int text_row = 1;
			NSArray	*sections = [report componentsSeparatedByString:@"\n"];
			unsigned	i;
			for (i = 0; i < [sections count]; i++)
				text_row = [gui addLongText:(NSString *)[sections objectAtIndex:i] startingAtRow:text_row align:GUI_ALIGN_LEFT];
		}
		else
		{
			(void)[gui addLongText:report startingAtRow:1 align:GUI_ALIGN_LEFT];
		}

		[gui setText:[NSString stringWithFormat:DESC_PLURAL(@"contracts-cash-@-load-d-of-d-passengers-d-of-d-berths", max_passengers), OOCredits(credits), current_cargo, max_cargo, [passengers count], max_passengers]  forRow: GUI_ROW_MARKET_CASH];
		
		[gui setText:@"press-space-commander" forRow:21 align:GUI_ALIGN_CENTER];
		[gui setColor:[OOColor yellowColor] forRow:21];
		
		[gui setShowTextCursor:NO];
	}
	/* ends */
	

	if (lastTextKey)
	{
		[lastTextKey release];
		lastTextKey = nil;
	}
	
	gui_screen = GUI_SCREEN_REPORT;

	[self setShowDemoShips: NO];
	[UNIVERSE setDisplayText: YES];
	[UNIVERSE setDisplayCursor: NO];
	[UNIVERSE setViewDirection: VIEW_GUI_DISPLAY];
}


- (void) setGuiToDockingReportScreen
{
	GuiDisplayGen* gui = [UNIVERSE gui];
	
	int text_row = 1;
	
	[dockingReport setString:[dockingReport stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
	
	// GUI stuff
	{
		[gui clear];
		[gui setTitle:ExpandDescriptionForCurrentSystem(@"[arrival-report-title]")];
		

		// dockingReport might be a multi-line message
		
		while (([dockingReport length] > 0)&&(text_row < 18))
		{
			if ([dockingReport rangeOfString:@"\n"].location != NSNotFound)
			{
				while (([dockingReport rangeOfString:@"\n"].location != NSNotFound)&&(text_row < 18))
				{
					int line_break = [dockingReport rangeOfString:@"\n"].location;
					NSString* line = [dockingReport substringToIndex:line_break];
					[dockingReport deleteCharactersInRange: NSMakeRange( 0, line_break + 1)];
					text_row = [gui addLongText:line startingAtRow:text_row align:GUI_ALIGN_LEFT];
				}
				[dockingReport setString:[dockingReport stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
			}
			else
			{
				text_row = [gui addLongText:[NSString stringWithString:dockingReport] startingAtRow:text_row align:GUI_ALIGN_LEFT];
				[dockingReport setString:@""];
			}
		}

		[gui setText:[NSString stringWithFormat:DESC_PLURAL(@"contracts-cash-@-load-d-of-d-passengers-d-of-d-berths", max_passengers), OOCredits(credits), current_cargo, max_cargo, [passengers count], max_passengers]  forRow: GUI_ROW_MARKET_CASH];
		
		[gui setText:DESC(@"press-space-commander") forRow:21 align:GUI_ALIGN_CENTER];
		[gui setColor:[OOColor yellowColor] forRow:21];
		
		[gui setShowTextCursor:NO];
	}
	/* ends */
	

	if (lastTextKey)
	{
		[lastTextKey release];
		lastTextKey = nil;
	}
	
	gui_screen = GUI_SCREEN_REPORT;

	[self setShowDemoShips: NO];
	[UNIVERSE setDisplayText: YES];
	[UNIVERSE setDisplayCursor: NO];
	[UNIVERSE setViewDirection: VIEW_GUI_DISPLAY];
}

// ---------------------------------------------------------------------- 

static NSMutableDictionary* currentShipyard = nil;

- (void) setGuiToShipyardScreen:(unsigned) skip
{
	unsigned i;
	
	// set up initial market if there is none
	StationEntity	*the_station;
	OOTechLevelID	station_tl;
	
	if (dockedStation)
	{
		the_station  = dockedStation;
		station_tl = [dockedStation equivalentTechLevel];
	}
	else
	{
		the_station  = [UNIVERSE station];
		station_tl = NSNotFound;
	}
	if (![the_station localShipyard])
		[the_station setLocalShipyard:[UNIVERSE shipsForSaleForSystem:system_seed withTL:station_tl atTime:ship_clock]];
		
	NSMutableArray* shipyard = [the_station localShipyard];
		
	// remove ships that the player has already bought
	for (i = 0; i < [shipyard count]; i++)
	{
		NSDictionary* info = (NSDictionary *)[shipyard objectAtIndex:i];
		NSString* ship_id = [info oo_stringForKey:SHIPYARD_KEY_ID];
		if ([shipyard_record objectForKey:ship_id])
			[shipyard removeObjectAtIndex:i--];
	}
	
	if (currentShipyard) [currentShipyard release];
	currentShipyard = [[NSMutableDictionary alloc] initWithCapacity:[shipyard count]];

	for (i = 0; i < [shipyard count]; i++)
	{
		[currentShipyard setObject:[shipyard objectAtIndex:i]
							forKey:[[shipyard oo_dictionaryAtIndex:i] oo_stringForKey:SHIPYARD_KEY_ID]];
	}
	
	unsigned n_ships = [shipyard count];

	//error check
	if (skip >= n_ships)  skip = n_ships - 1;
	if (skip < 2)  skip = 0;
	
	// GUI stuff
	{
		GuiDisplayGen* gui = [UNIVERSE gui];
		
		[gui clear];
		[gui setTitle:[NSString stringWithFormat:DESC(@"@-shipyard-title"),[UNIVERSE getSystemName:system_seed]]];
		
		OOGUITabSettings tab_stops;
		tab_stops[0] = 0;
		tab_stops[1] = -258;
		tab_stops[2] = 270;
		tab_stops[3] = 370;
		tab_stops[4] = 450;
		[gui setTabStops:tab_stops];
		
		int n_rows = MAX_ROWS_SHIPS_FOR_SALE;
		int start_row = GUI_ROW_SHIPYARD_START;
		int previous = 0;
		
		if (n_ships <= MAX_ROWS_SHIPS_FOR_SALE)
			skip = 0;
		else
		{
			if (skip > 0)
			{
				n_rows -= 1;
				start_row += 1;
				previous = skip - MAX_ROWS_SHIPS_FOR_SALE + 2;
				if (previous < 2)
					previous = 0;
			}
			if (skip + n_rows < n_ships)
				n_rows -= 1;
		}
		
		if (n_ships > 0)
		{
			[gui setColor:[OOColor greenColor] forRow:GUI_ROW_SHIPYARD_LABELS];
			[gui setArray:[NSArray arrayWithObjects:DESC(@"shipyard-shiptype"), DESC(@"shipyard-price"),
					DESC(@"shipyard-cargo"), DESC(@"shipyard-speed"), nil] forRow:GUI_ROW_SHIPYARD_LABELS];

			if (skip > 0)
			{
				[gui setColor:[OOColor greenColor] forRow:GUI_ROW_SHIPYARD_START];
				[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-back"), @" <-- ", nil] forRow:GUI_ROW_SHIPYARD_START];
				[gui setKey:[NSString stringWithFormat:@"More:%d", previous] forRow:GUI_ROW_SHIPYARD_START];
			}
			for (i = 0; i < (n_ships - skip) && (int)i < n_rows; i++)
			{
				NSDictionary* ship_info = [shipyard oo_dictionaryAtIndex:i + skip];
				OOCreditsQuantity ship_price = [ship_info oo_unsignedLongLongForKey:SHIPYARD_KEY_PRICE];
				[gui setColor:[OOColor yellowColor] forRow:start_row + i];
				[gui setArray:[NSArray arrayWithObjects:
						[NSString stringWithFormat:@" %@ ",[[ship_info oo_dictionaryForKey:SHIPYARD_KEY_SHIP] oo_stringForKey:@"display_name" defaultValue:[[ship_info oo_dictionaryForKey:SHIPYARD_KEY_SHIP] oo_stringForKey:KEY_NAME]]],
						OOIntCredits(ship_price),
						nil]
					forRow:start_row + i];
				[gui setKey:(NSString*)[ship_info objectForKey:SHIPYARD_KEY_ID] forRow:start_row + i];
			}
			if (i < n_ships - skip)
			{
				[gui setColor:[OOColor greenColor] forRow:start_row + i];
				[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-more"), @" --> ", nil] forRow:start_row + i];
				[gui setKey:[NSString stringWithFormat:@"More:%d", n_rows + skip] forRow:start_row + i];
				i++;
			}

			[gui setSelectableRange:NSMakeRange( GUI_ROW_SHIPYARD_START, i + start_row - GUI_ROW_SHIPYARD_START)];
			[self showShipyardInfoForSelection];
		}
		else
		{
			[gui setText:DESC(@"shipyard-no-ships-available-for-purchase") forRow:GUI_ROW_NO_SHIPS align:GUI_ALIGN_CENTER];
			[gui setColor:[OOColor greenColor] forRow:GUI_ROW_NO_SHIPS];
			
			[gui setNoSelectedRow];
		}
		
		[self showTradeInInformationFooter];
		
		[gui setShowTextCursor:NO];
	}
	
	gui_screen = GUI_SCREEN_SHIPYARD;
	
	// the following are necessary...

	[self setShowDemoShips: (n_ships > 0)];
	[UNIVERSE setDisplayText: YES];
	[UNIVERSE setDisplayCursor: YES];
	[UNIVERSE setViewDirection: VIEW_GUI_DISPLAY];
}


- (void) showShipyardInfoForSelection
{
	unsigned		i;
	GuiDisplayGen	*gui = [UNIVERSE gui];
	OOGUIRow		sel_row = [gui selectedRow];
	
	if (sel_row <= 0)
		return;
	
	NSMutableArray* row_info = [NSMutableArray arrayWithArray:(NSArray*)[gui objectForRow:GUI_ROW_SHIPYARD_LABELS]];
	while ([row_info count] < 4)
		[row_info addObject:@""];
	
	NSString* key = [gui keyForRow:sel_row];
	
	NSDictionary* info = (NSDictionary *)[currentShipyard objectForKey:key];

	// clean up the display ready for the newly-selected ship (if there is one)
	[row_info replaceObjectAtIndex:2 withObject:@""];
	[row_info replaceObjectAtIndex:3 withObject:@""];
	for (i = GUI_ROW_SHIPYARD_INFO_START; i < GUI_ROW_MARKET_CASH - 1; i++)
	{
		[gui setText:@"" forRow:i];
		[gui setColor:[OOColor greenColor] forRow:i];
	}
	[UNIVERSE removeDemoShips];

	if (info)
	{
		// the key is a particular ship - show the details
		NSString *sales_pitch = (NSString*)[info objectForKey:KEY_SHORT_DESCRIPTION];
		NSDictionary *shipDict = [info oo_dictionaryForKey:SHIPYARD_KEY_SHIP];
		
		int cargo_rating = [shipDict oo_intForKey:@"max_cargo"];
		int cargo_extra;
		cargo_extra = [shipDict oo_intForKey:@"extra_cargo" defaultValue:15];
		float speed_rating = 0.001 * [shipDict oo_intForKey:@"max_flight_speed"];
		
		NSArray *ship_extras = [info oo_arrayForKey:KEY_EQUIPMENT_EXTRAS];
		for (i = 0; i < [ship_extras count]; i++)
		{
			if ([[ship_extras oo_stringAtIndex:i] isEqualToString:@"EQ_CARGO_BAY"])
				cargo_rating += cargo_extra;
			else if ([[ship_extras oo_stringAtIndex:i] isEqualToString:@"EQ_PASSENGER_BERTH"])
				cargo_rating -= 5;
		}
		
		[row_info replaceObjectAtIndex:2 withObject:[NSString stringWithFormat:DESC(@"shipyard-cargo-d-tc"), cargo_rating]];
		[row_info replaceObjectAtIndex:3 withObject:[NSString stringWithFormat:DESC(@"shipyard-speed-f-ls"), speed_rating]];
		
		if ([gui addLongText:sales_pitch startingAtRow:GUI_ROW_SHIPYARD_INFO_START align:GUI_ALIGN_LEFT] < GUI_ROW_MARKET_CASH - 1)
		{
			[self showTradeInInformationFooter];
		}
		
		// now display the ship
		[self showShipyardModel:shipDict];
	}
	else
	{
		// the key is a particular model of ship which we must expand...
		// build an array from the entries for that model in the currentShipyard TODO
		// 
	}

	[gui setArray:[NSArray arrayWithArray:row_info] forRow:GUI_ROW_SHIPYARD_LABELS];
}


- (void) showTradeInInformationFooter
{
	GuiDisplayGen *gui = [UNIVERSE gui];
	OOCreditsQuantity tradeIn = [self tradeInValue];
	[gui setText:[NSString stringWithFormat:DESC(@"shipyard-your-@-trade-in-value-@"), [self displayName], OOCredits(tradeIn)]  forRow: GUI_ROW_MARKET_CASH - 1];
	[gui setText:[NSString stringWithFormat:DESC(@"shipyard-total-available-%@-%@-plus-%@-trade"), OOCredits(credits + tradeIn), OOCredits(credits), OOCredits(tradeIn)]  forRow: GUI_ROW_MARKET_CASH];
}


- (void) showShipyardModel: (NSDictionary *)shipDict
{
	ShipEntity		*ship;
		
	if (!dockedStation)
		return;
	
	Quaternion		q2 = { (GLfloat)0.707f, (GLfloat)0.707f, (GLfloat)0.0f, (GLfloat)0.0f };
	
	ship = [[ShipEntity alloc] initWithDictionary:shipDict];
	[ship wasAddedToUniverse];
	
	GLfloat cr = [ship collisionRadius];
	OOLog(kOOLogNoteShowShipyardModel, @"::::: showShipyardModel:'%@'.", [ship name]);
	[ship setOrientation: q2];
	
	[ship setPositionX:1.2 * cr y:0.8 * cr z:6.4 * cr];
	[ship setStatus: STATUS_COCKPIT_DISPLAY];
	[ship setScanClass: CLASS_NO_DRAW];
	[ship setRoll: M_PI/10.0];
	[ship setPitch: M_PI/25.0];
	if([ship pendingEscortCount] > 0) [ship setPendingEscortCount:0];
	[UNIVERSE addEntity: ship];
	[[ship getAI] setStateMachine: @"nullAI.plist"];
	
	[ship release];
	
}


- (OOCreditsQuantity) tradeInValue
{
	// returns down to ship_trade_in_factor% of the full credit value of your ship
	
	/*	FIXME: the trade-in value can be more than the sale value, and
		ship_trade_in_factor starts at 100%, so it can be profitable to sit
		and buy the same ship over and over again. This bug predates Oolite
		1.65.
		Partial fix: make effective trade-in value 75% * ship_trade_in_factor%
		of the "raw" trade-in value. This still allows profitability! A better
		solution would be to unify the price calculation for trade-in and
		for-sale ships.
		-- Ahruman 20070707, fix applied 20070708
	*/
	unsigned long long value = [UNIVERSE tradeInValueForCommanderDictionary:[self commanderDataDictionary]];
	value = ((value * 75 * ship_trade_in_factor) + 5000) / 10000;	// Multiply by two percentages, divide by 100*100. The +5000 is to get normal rounding.
	return value * 10;
}


- (BOOL) buySelectedShip
{
	GuiDisplayGen* gui = [UNIVERSE gui];
	int sel_row = [gui selectedRow];
	
	if (sel_row <= 0)
		return NO;
	
	NSString* key = [gui keyForRow:sel_row];

	if ([key hasPrefix:@"More:"])
	{
		int from_ship = [[[key componentsSeparatedByString:@":"] objectAtIndex:1] intValue];
		if (from_ship < 0)  from_ship = 0;
		
		[self setGuiToShipyardScreen:from_ship];
		if ([[UNIVERSE gui] selectedRow] < 0)
			[[UNIVERSE gui] setSelectedRow:GUI_ROW_SHIPYARD_START];
		if (from_ship == 0)
			[[UNIVERSE gui] setSelectedRow:GUI_ROW_SHIPYARD_START + MAX_ROWS_SHIPS_FOR_SALE - 1];
		return YES;
	}
	
	// first check you can afford it!
	NSDictionary* ship_info = [currentShipyard oo_dictionaryForKey:key];
	OOCreditsQuantity price = [ship_info oo_unsignedLongLongForKey:SHIPYARD_KEY_PRICE];
	OOCreditsQuantity trade_in = [self tradeInValue];
	
	if (credits + trade_in < price * 10)
		return NO;	// you can't afford it!
	
	// sell all the commodities carried
	unsigned i;
	for (i = 0; i < [shipCommodityData count]; i++)
	{
		[self trySellingCommodity:i all:YES];
	}
	
	// We tried to sell everything. If there are still items present in our inventory, it
	// means that the market got saturated (quantity in station > 127 t) before we could sell
	// it all. Everything that could not be sold will be lost. -- Nikos 20083012
	if (current_cargo)
	{
		// Zero out our manifest.
		NSMutableArray* manifest =  [NSMutableArray arrayWithArray:shipCommodityData];
		for (i = 0; i < [manifest count]; i++)
		{
			NSMutableArray* manifest_commodity = [NSMutableArray arrayWithArray:[manifest oo_arrayAtIndex:i]];
			[manifest_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:0]];
			[manifest replaceObjectAtIndex:i withObject:manifest_commodity];
		}
		[shipCommodityData release];
		shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
		current_cargo = 0;
	}
	
	// drop all passengers
	[passengers removeAllObjects];
		
	// contracts stay the same, so if you default - tough!
	// okay we need to switch the model used, lots of the stats, and add all the extras
	// pay over the mazoolah
	credits -= 10 * price - trade_in;
	
	// change ship_desc
	if (ship_desc)
	{
		[self clearSubEntities];
		[ship_desc release];
	}
	ship_desc = [[ship_info oo_stringForKey:SHIPYARD_KEY_SHIPDATA_KEY] copy];
	NSDictionary *shipDict = [ship_info oo_dictionaryForKey:SHIPYARD_KEY_SHIP];
	
	// get a full tank for free
	[self setFuel:[self fuelCapacity]];
	
	// this ship has a clean record
	legalStatus = 0;
	
	// get forward_weapon aft_weapon port_weapon starboard_weapon from ship_info
	aft_weapon = EquipmentStringToWeaponTypeSloppy([shipDict oo_stringForKey:@"aft_weapon_type"]);
	port_weapon = EquipmentStringToWeaponTypeSloppy([shipDict oo_stringForKey:@"port_weapon_type"]);
	starboard_weapon = EquipmentStringToWeaponTypeSloppy([shipDict oo_stringForKey:@"starboard_weapon_type"]);
	forward_weapon = EquipmentStringToWeaponTypeSloppy([shipDict oo_stringForKey:@"forward_weapon_type"]);
	
	// get basic max_cargo
	max_cargo = [UNIVERSE maxCargoForShip:ship_desc];
	
	// ensure all missiles are tidied up and start at pylon 0
	[self tidyMissilePylons];

	// get missiles from ship_info
	missiles = [shipDict oo_unsignedIntForKey:@"missiles"];
	
	// reset max_passengers
	max_passengers = 0;
	
	// reset and refill extra_equipment then set flags from it
	
	// keep track of portable equipment..
	
	NSMutableSet	*portable_equipment = [NSMutableSet set];
	NSEnumerator	*eqEnum = nil;
	NSString		*eq_desc = nil;
	OOEquipmentType	*item = nil;
	
	for (eqEnum = [self equipmentEnumerator]; (eq_desc = [eqEnum nextObject]);)
	{
		item = [OOEquipmentType equipmentTypeWithIdentifier:eq_desc];
		if ([item isPortableBetweenShips])  [portable_equipment addObject:eq_desc];
	}
	
	// remove ALL
	[self removeAllEquipment];
	
	// restore  portable equipment
	for (eqEnum = [portable_equipment objectEnumerator]; (eq_desc = [eqEnum nextObject]); )
	{
		[self addEquipmentItem:eq_desc];
	}
	
	// refill from ship_info
	NSArray* extras = [ship_info oo_arrayForKey:KEY_EQUIPMENT_EXTRAS];
	for (i = 0; i < [extras count]; i++)
	{
		NSString* eq_key = [extras oo_stringAtIndex:i];
		if ([eq_key isEqualToString:@"EQ_PASSENGER_BERTH"])
		{
			max_passengers++;
			max_cargo -= 5;
		}
		else
		{
			[self addEquipmentItem:eq_key];
		}
	}
	
	// add bought ship to shipyard_record
	[shipyard_record setObject:ship_desc forKey:[ship_info objectForKey:SHIPYARD_KEY_ID]];
	
	// remove the ship from the localShipyard
	[[dockedStation localShipyard] removeObjectAtIndex:sel_row - GUI_ROW_SHIPYARD_START];
	
	// perform the transformation
	NSDictionary* cmdr_dict = [self commanderDataDictionary];	// gather up all the info
	if (![self setCommanderDataFromDictionary:cmdr_dict])  return NO;

	[self setStatus:STATUS_DOCKED];
	
	// adjust the clock forward by an hour
	ship_clock_adjust += 3600.0;
	
	// finally we can get full hock if we sell it back
	ship_trade_in_factor = 100;
	
	if ([UNIVERSE autoSave])  [UNIVERSE setAutoSaveNow:YES];
	
	return YES;
}


@end

