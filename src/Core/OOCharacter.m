//
//  OOCharacter.m
//  Oolite
/*
 *
 *  Oolite
 *
 *  Created by Giles Williams on Thu Nov 03 2004.
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

#import "OOCharacter.h"

#import "Universe.h"


@implementation OOCharacter

- (NSString*) description
{
	NSString* result = [[NSString alloc] initWithFormat:@"<OOCharacter : %@, %@. %@. Bounty %d.  Insurance %d.>",
		[self name], [self shortDescription], [self longDescription], [self legalStatus], [self insuranceCredits]];
	return [result autorelease];
}

- (void) dealloc
{
	if (name)
		[name release];
	if (shortDescription)
		[shortDescription release];
	if (longDescription)
		[longDescription release];
	if (script_actions)
		[script_actions release];
	[super dealloc];
}

- (id) initWithGenSeed:(Random_Seed) g_seed andOriginalSystemSeed:(Random_Seed) s_seed inUniverse:(Universe*) uni
{
	self = [super init];
	
	// do character set-up
	//
	genSeed = g_seed;
	originSystemSeed = s_seed;
	universe = uni;
	//
	[self basicSetUp];
	
	return self;
}

- (id) initWithRole:(NSString*) role andOriginalSystemSeed:(Random_Seed) s_seed inUniverse:(Universe*) uni
{
	self = [super init];
	
	// do character set-up
	//
	originSystemSeed = s_seed;
	make_pseudo_random_seed( &genSeed);
	universe = uni;
	//
	[self basicSetUp];
	
	[self castInRole: role];
	
	return self;
}

+ (OOCharacter*) characterWithRole:(NSString*) c_role andOriginalSystem:(Random_Seed) o_seed inUniverse:(Universe*) uni
{
	return [[[OOCharacter alloc] initWithRole: c_role andOriginalSystemSeed: o_seed inUniverse: uni] autorelease];
}

+ (OOCharacter*) randomCharacterWithRole:(NSString*) c_role andOriginalSystem:(Random_Seed) o_seed inUniverse:(Universe*) uni
{
	Random_Seed r_seed;
	r_seed.a = (ranrot_rand() & 0xff);
	r_seed.b = (ranrot_rand() & 0xff);
	r_seed.c = (ranrot_rand() & 0xff);
	r_seed.d = (ranrot_rand() & 0xff);
	r_seed.e = (ranrot_rand() & 0xff);
	r_seed.f = (ranrot_rand() & 0xff);
	
	OOCharacter	*castmember = [[[OOCharacter alloc] initWithGenSeed: r_seed andOriginalSystemSeed: o_seed inUniverse: uni] autorelease];
	
	if ([castmember castInRole: c_role])
		return castmember;
	else
	{
		NSLog(@"DEBUG ***** couldn't cast character in role '%@'", c_role);
		return castmember;
	}
}

+ (OOCharacter*) characterWithDictionary:(NSDictionary*) c_dict inUniverse:(Universe*) uni
{
	OOCharacter	*castmember = [[[OOCharacter alloc] init] autorelease];
	[castmember setUniverse: uni];
	[castmember setCharacterFromDictionary: c_dict];
	return castmember;
}


- (NSString*) planetOfOrigin
{
	// determine the planet of origin
	NSDictionary* originInfo = [universe generateSystemData: originSystemSeed];
	return [originInfo objectForKey: KEY_NAME];
}

- (NSString*) species
{
	// determine the character's species
	int species = genSeed.f & 0x03;	// 0-1 native to home system, 2 human colonial, 3 other
	NSString* speciesString = (species == 3)? [universe generateSystemInhabitants: genSeed plural:NO]:[universe generateSystemInhabitants: originSystemSeed plural:NO];
	return [[speciesString lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

- (void) basicSetUp
{	
	// save random seeds for restoration later
	RNG_Seed saved_seed = currentRandomSeed();
	// set RNG to character seed
	seed_for_planet_description( genSeed);

	// determine the planet of origin
	NSDictionary* originInfo = [universe generateSystemData: originSystemSeed];
	NSString* planetName = [originInfo objectForKey: KEY_NAME];
	int government = [[originInfo objectForKey:KEY_GOVERNMENT] intValue]; // 0 .. 7 (0 anarchic .. 7 most stable)
	int criminal_tendency = government ^ 0x07;

	// determine the character's species
	NSString* speciesString = [self species];
	
	// determine the character's name
	seed_RNG_only_for_planet_description( genSeed);
	NSString* genName;
	if ([speciesString hasPrefix:@"human"])
		genName = [NSString stringWithFormat:@"%@ %@", [universe expandDescription:@"%R" forSystem: genSeed], [universe expandDescription:@"[nom]" forSystem: genSeed]];
	else
		genName = [NSString stringWithFormat:@"%@ %@", [universe expandDescription:@"%R" forSystem: genSeed], [universe expandDescription:@"%R" forSystem: genSeed]];
	
	[self setName: genName];
	
	[self setShortDescription: [NSString stringWithFormat:[universe expandDescription:@"[character-a-@-from-@]" forSystem: genSeed], speciesString, planetName]];
	[self setLongDescription: [self shortDescription]];
	
	// determine legal_status for a completely random character
	NSString *legalDesc;
	[self setLegalStatus: 0];	// clean
	int legal_index = gen_rnd_number() & gen_rnd_number() & 0x03;
	while (((gen_rnd_number() & 0xf) < criminal_tendency)&&(legal_index < 3))
		legal_index++;
	if (legal_index == 3)	// criminal
		[self setLegalStatus: criminal_tendency + criminal_tendency * (gen_rnd_number() & 0x03) + (gen_rnd_number() & gen_rnd_number() & 0x7f)];
	legal_index = 0;
	if (legalStatus)	legal_index = (legalStatus <= 50) ? 1 : 2;
	switch (legal_index)
	{
		case 0:
			legalDesc = @"clean";
			break;
		case 1:
			legalDesc = @"an offender";
			break;
		case 2:
			legalDesc = @"a fugitive";
			break;
		default:
			// never should get here
			legalDesc = @"an unperson";
	}

	// if clean - determine insurance level (if any)
	[self setInsuranceCredits: 0];
	if (legal_index == 0)
	{
		int insurance_index = gen_rnd_number() & gen_rnd_number() & 0x03;
		switch (insurance_index)
		{
			case 1:
				[self setInsuranceCredits: 125];
				break;
			case 2:
				[self setInsuranceCredits: 250];
				break;
			case 3:
				[self setInsuranceCredits: 500];
		}
	}
	
	// restore random seed
	setRandomSeed( saved_seed);
}

- (BOOL) castInRole:(NSString*) role
{
	BOOL specialSetUpDone = NO;
	
	NSString *legalDesc;
	if ([[role lowercaseString] isEqual:@"pirate"])
	{
		// determine legal_status for a completely random character
		int sins = 0x08 | (genSeed.a & genSeed.b);
		[self setLegalStatus: sins & 0x7f];
		int legal_index = (legalStatus <= 50) ? 1 : 2;
		switch (legal_index)
		{
			case 1:
				legalDesc = @"offender";
				break;
			case 2:
				legalDesc = @"fugitive";
				break;
		}
		[self setLongDescription:
			[universe expandDescription:
				[NSString stringWithFormat:@"%@ is a [21] %@ from %@", [self name], legalDesc, [self planetOfOrigin]]
				forSystem: genSeed]];
		
//		NSLog(@">>>>> %@", self);
		
		specialSetUpDone = YES;
	}
	
	if ([[role lowercaseString] isEqual:@"trader"])
	{
		legalDesc = @"clean";
		[self setLegalStatus: 0];	// clean

		int insurance_index = gen_rnd_number() & 0x03;
		switch (insurance_index)
		{
			case 0:
				[self setInsuranceCredits: 0];
				break;
			case 1:
				[self setInsuranceCredits: 125];
				break;
			case 2:
				[self setInsuranceCredits: 250];
				break;
			case 3:
				[self setInsuranceCredits: 500];
		}
		specialSetUpDone = YES;
	}
	
	if ([[role lowercaseString] isEqual:@"hunter"])
	{
		legalDesc = @"clean";
		[self setLegalStatus: 0];	// clean
		int insurance_index = gen_rnd_number() & 0x03;
		if (insurance_index == 3)
			[self setInsuranceCredits: 500];
		specialSetUpDone = YES;
	}
	
	if ([[role lowercaseString] isEqual:@"police"])
	{
		legalDesc = @"clean";
		[self setLegalStatus: 0];	// clean
		[self setInsuranceCredits: 125];
		specialSetUpDone = YES;
	}
	
	if ([[role lowercaseString] isEqual:@"miner"])
	{
		legalDesc = @"clean";
		[self setLegalStatus: 0];	// clean
		[self setInsuranceCredits: 25];
		specialSetUpDone = YES;
	}
	
	if ([[role lowercaseString] isEqual:@"passenger"])
	{
		legalDesc = @"clean";
		[self setLegalStatus: 0];	// clean
		int insurance_index = gen_rnd_number() & 0x03;
		switch (insurance_index)
		{
			case 0:
				[self setInsuranceCredits: 25];
				break;
			case 1:
				[self setInsuranceCredits: 125];
				break;
			case 2:
				[self setInsuranceCredits: 250];
				break;
			case 3:
				[self setInsuranceCredits: 500];
		}
		specialSetUpDone = YES;
	}
	
	if ([[role lowercaseString] isEqual:@"slave"])
	{
		legalDesc = @"clean";
		[self setLegalStatus: 0];	// clean
		[self setInsuranceCredits: 0];
		specialSetUpDone = YES;
	}
	
	// do long description here
	//
	
	return specialSetUpDone;
}

- (NSString*)	name
{
	return name;
}
- (NSString*)	shortDescription
{
	return shortDescription;
}
- (NSString*)	longDescription
{
	return longDescription;
}
- (Random_Seed)	originSystemSeed
{
	return originSystemSeed;
}
- (Random_Seed)	genSeed
{
	return genSeed;
}
- (int)			legalStatus
{
	return legalStatus;
}
- (int)			insuranceCredits
{
	return insuranceCredits;
}
- (NSArray*)	script
{
	return script_actions;
}

- (void) setUniverse: (Universe*) uni
{
	universe = uni;
}
- (void) setName: (NSString*) value
{
	if (name)
		[name autorelease];
	name = [value retain];
}
- (void) setShortDescription: (NSString*) value
{
	if (shortDescription)
		[shortDescription autorelease];
	shortDescription = [value retain];
}
- (void) setLongDescription: (NSString*) value
{
	if (longDescription)
		[longDescription autorelease];
	longDescription = [value retain];
}
- (void) setOriginSystemSeed: (Random_Seed) value
{
	originSystemSeed = value;
}
- (void) setGenSeed: (Random_Seed) value
{
	genSeed = value;
}
- (void) setLegalStatus: (int) value
{
	legalStatus = value;
}
- (void) setInsuranceCredits: (int) value
{
	insuranceCredits = value;
}
- (void) setScript: (NSArray*) some_actions
{
	if (script_actions)
		[script_actions autorelease];
	if (some_actions)
		script_actions = [some_actions retain];
	else
		script_actions = nil;
}

- (void) setCharacterFromDictionary:(NSDictionary*) dict
{
	if ([dict objectForKey:@"origin"])
	{
		if (([[dict objectForKey:@"origin"] intValue] > 0) || [[[dict objectForKey:@"origin"] stringValue] isEqual:@"0"])
			[self setOriginSystemSeed:[universe systemSeedForSystemNumber:[[dict objectForKey:@"origin"] intValue]]];
		else
			[self setOriginSystemSeed:[universe systemSeedForSystemName:[[dict objectForKey:@"origin"] stringValue]]];
	}	
	if ([dict objectForKey:@"random_seed"])
	{
		Random_Seed g_seed = [Entity seedFromString:[[dict objectForKey:@"random_seed"] stringValue]];
		[self setGenSeed: g_seed];
		[self basicSetUp];
	}
	if ([dict objectForKey:@"role"])
		[self castInRole:[dict objectForKey:@"name"]];
	if ([dict objectForKey:@"name"])
		[self setName:[dict objectForKey:@"name"]];
	if ([dict objectForKey:@"short_description"])
		[self setShortDescription:[dict objectForKey:@"short_description"]];
	if ([dict objectForKey:@"long_description"])
		[self setLongDescription:[dict objectForKey:@"long_description"]];
	if ([dict objectForKey:@"legal_status"])
		[self setLegalStatus:[[dict objectForKey:@"legal_status"] intValue]];
	if ([dict objectForKey:@"bounty"])
		[self setLegalStatus:[[dict objectForKey:@"bounty"] intValue]];
	if ([dict objectForKey:@"insurance"])
		[self setInsuranceCredits:[[dict objectForKey:@"insurance"] intValue]];
	if ([dict objectForKey:@"script_actions"])
		[self setScript:[dict objectForKey:@"script_actions"]];
		
}

@end
