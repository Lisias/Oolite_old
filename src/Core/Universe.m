/*

Universe.m

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

#import "OOOpenGL.h"
#import "OOGLDefs.h"
#import "Universe.h"
#import "MyOpenGLView.h"
#import "GameController.h"
#import "ResourceManager.h"
#import "AI.h"
#import "GuiDisplayGen.h"
#import "HeadUpDisplay.h"
#import "OOSound.h"
#import "OOColor.h"
#import "OOCacheManager.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"
#import "OOConstToString.h"
#import "OOOpenGLExtensionManager.h"
#import "OOCPUInfo.h"
#import "OOMaterial.h"
#import "OOTexture.h"

#import "Octree.h"
#import "CollisionRegion.h"
#import "OOGraphicsResetManager.h"

#import "OOCharacter.h"

#import "PlayerEntity.h"
#import "PlayerEntityContracts.h"
#import "StationEntity.h"
#import "SkyEntity.h"
#import "DustEntity.h"
#import "PlanetEntity.h"
#import "WormholeEntity.h"
#import "RingEntity.h"
#import "ParticleEntity.h"

#define kOOLogUnconvertedNSLog @"unclassified.Universe"

#define MAX_NUMBER_OF_ENTITIES				200
#define MAX_NUMBER_OF_SOLAR_SYSTEM_ENTITIES 20


static NSString * const kOOLogUniversePopulate				= @"universe.populate";
static NSString * const kOOLogUniversePopulateWitchspace	= @"universe.populate.witchspace";
static NSString * const kOOLogScriptNoSystemForName			= @"script.debug.note.systemSeedForSystemName";
extern NSString * const kOOLogEntityVerificationError;
static NSString * const kOOLogEntityVerificationRebuild		= @"entity.linkedList.verify.rebuild";
static NSString * const kOOLogFoundBeacon					= @"beacon.list";


Universe *gSharedUniverse = nil;


static BOOL MaintainLinkedLists(Universe* uni);


static NSComparisonResult compareName(NSDictionary *dict1, NSDictionary *dict2, void * context);
static NSComparisonResult comparePrice(NSDictionary *dict1, NSDictionary *dict2, void * context);


@implementation Universe

- (id) initWithGameView:(MyOpenGLView *)inGameView
{	
    PlayerEntity	*player;
	int				i;
	
	if (gSharedUniverse != nil)
	{
		[self release];
		[NSException raise:NSInternalInconsistencyException format:@"%s: expected only one Universe to exist at a time.", __FUNCTION__];
	}
	
	self = [super init];
	[self setGameView:inGameView];
	gSharedUniverse = self;
	
	n_entities = 0;
	
	x_list_start = y_list_start = z_list_start = nil;
	
	firstBeacon = NO_TARGET;
	lastBeacon = NO_TARGET;
	
	no_update = NO;
	
	OOCPUInfoInit();
	
	// init OpenGL extension manager (must be done before any other threads might use it)
	[OOOpenGLExtensionManager sharedManager];
	
	[OOMaterial setUp];
	
	// Preload cache
	[OOCacheManager sharedCache];
	
	// init the Resource Manager
	[ResourceManager paths];
	
	reducedDetail = NO;
	
#if OOLITE_MAC_OS_X
	//// speech stuff
	speechSynthesizer = [[NSSpeechSynthesizer alloc] init];
	
	//Jester Speech Begin
	speechArray = [[ResourceManager arrayFromFilesNamed:@"speech_pronunciation_guide.plist" inFolder:@"Config" andMerge:YES] retain];
	//Jester Speech End
#endif
	
 	dumpCollisionInfo = NO;
	next_universal_id = 100;	// start arbitrarily above zero
	for (i = 0; i < MAX_ENTITY_UID; i++)
		entity_for_uid[i] = nil;
	
    entities =				[[NSMutableArray arrayWithCapacity:MAX_NUMBER_OF_ENTITIES] retain];
	
	sun_center_position[0] = 4000000.0;
	sun_center_position[1] = 0.0;
	sun_center_position[2] = 0.0;
	sun_center_position[3] = 1.0;
    //
    gui = [[GuiDisplayGen alloc] init]; // alloc retains
    displayGUI = NO;
	
	message_gui = [[GuiDisplayGen alloc]
					initWithPixelSize:NSMakeSize(480, 160)
							  columns:1
								 rows:8
							rowHeight:20
							 rowStart:20
								title:nil];
	[message_gui setCurrentRow:7];
	[message_gui setCharacterSize:NSMakeSize(16,20)];	// slightly narrower characters
	[message_gui setDrawPosition: make_vector(0.0, -40.0, 640.0)];
	[message_gui setAlpha:1.0];
	
	comm_log_gui = [[GuiDisplayGen alloc]
					initWithPixelSize:NSMakeSize(360, 120)
							  columns:1
								 rows:10
							rowHeight:12
							 rowStart:12
								title:nil];
	[comm_log_gui setCurrentRow:9];
	[comm_log_gui setBackgroundColor:[OOColor colorWithCalibratedRed:0.0 green:0.05 blue:0.45 alpha:0.5]];
	[comm_log_gui setTextColor:[OOColor whiteColor]];
	[comm_log_gui setAlpha:0.0];
	[comm_log_gui printLongText:@"Communications Log" Align:GUI_ALIGN_CENTER Color:[OOColor yellowColor] FadeTime:0 Key:nil AddToArray:nil];
	[comm_log_gui setDrawPosition: make_vector(0.0, 180.0, 640.0)];
	
	displayFPS = NO;
	
	time_delta = 0.0;
	universal_time = 0.0;
	
	shipdata = [[ResourceManager dictionaryFromFilesNamed:@"shipdata.plist" inFolder:@"Config" andMerge:YES] retain];
	
	shipyard = [[ResourceManager dictionaryFromFilesNamed:@"shipyard.plist" inFolder:@"Config" andMerge:YES] retain];
	
	commoditylists = [(NSDictionary *)[ResourceManager dictionaryFromFilesNamed:@"commodities.plist" inFolder:@"Config" andMerge:YES] retain];
	commoditydata = [[NSArray arrayWithArray:(NSArray *)[commoditylists objectForKey:@"default"]] retain];
	
	illegal_goods = [[ResourceManager dictionaryFromFilesNamed:@"illegal_goods.plist" inFolder:@"Config" andMerge:YES] retain];
	
	descriptions = [[ResourceManager dictionaryFromFilesNamed:@"descriptions.plist" inFolder:@"Config" andMerge:YES] retain];
	
	characters = [[ResourceManager dictionaryFromFilesNamed:@"characters.plist" inFolder:@"Config" andMerge:YES] retain];
	
	customsounds = [[ResourceManager dictionaryFromFilesNamed:@"customsounds.plist" inFolder:@"Config" andMerge:YES] retain];
	
	planetinfo = [[ResourceManager dictionaryFromFilesNamed:@"planetinfo.plist" inFolder:@"Config" mergeMode:MERGE_SMART cache:YES] retain];
	
	local_planetinfo_overrides = [[NSMutableDictionary alloc] initWithCapacity:8];
	
	missiontext = [[ResourceManager dictionaryFromFilesNamed:@"missiontext.plist" inFolder:@"Config" andMerge:YES] retain];
	
	equipmentdata = [[ResourceManager arrayFromFilesNamed:@"equipment.plist" inFolder:@"Config" andMerge:YES] retain];
	
	demo_ships = [[ResourceManager arrayFromFilesNamed:@"demoships.plist" inFolder:@"Config" andMerge:YES] retain];
	demo_ship_index = 0;
	
	breakPatternCounter = 0;
	
	cachedSun = nil;
	cachedPlanet = nil;
	cachedStation = nil;
	
	station = NO_TARGET;
	planet = NO_TARGET;
	sun = NO_TARGET;
	
	player = [[PlayerEntity alloc] init];	// alloc retains!
	[self addEntity:player];
	[player release];
	
	player->x_next = nil;	player->x_previous = nil;	x_list_start = player;
	player->y_next = nil;	player->y_previous = nil;	y_list_start = player;
	player->z_next = nil;	player->z_previous = nil;	z_list_start = player;
	
	[player setUpShipFromDictionary:[self getDictionaryForShip:[player ship_desc]]];	// ship desc is the standard cobra at this point

	[player setStatus:STATUS_START_GAME];
	[player setShowDemoShips: YES];
	
	[self setGalaxy_seed: [player galaxy_seed]];
	
	system_seed = [self findSystemAtCoords:[player galaxy_coordinates] withGalaxySeed:galaxy_seed];
	
	
	activeWormholes = [[NSMutableArray arrayWithCapacity:16] retain];
	
	characterPool = [[NSMutableArray arrayWithCapacity:256] retain];
	
	[self setUpSpace];
	
	if (cachedStation)  [player setPosition:cachedStation->position];
	
	[self setViewDirection:VIEW_GUI_DISPLAY];
	
	demo_ship = nil;
	
	universeRegion = [[CollisionRegion alloc] initAsUniverse];	// retained
	
	doProcedurallyTexturedPlanets = NO;
	
	[player sendMessageToScripts:@"startUp"];
		
    return self;
}


- (void) dealloc
{
	gSharedUniverse = nil;
	
    [currentMessage release];
    
	[gui release];
    [message_gui release];
	[comm_log_gui release];
	
	[entities release];
	[shipdata release];
	[shipyard release];
	
	[commoditylists release];
	[commoditydata release];
	
	[illegal_goods release];
	[descriptions release];
	[characters release];
	[customsounds release];
	[planetinfo release];
	[missiontext release];
	[equipmentdata release];
	[demo_ships release];
	[gameView release];
	
	#ifndef GNUSTEP
	[speechArray release];
	[speechSynthesizer release];
	#endif

	[local_planetinfo_overrides release];
	[activeWormholes release];				
	[characterPool release];
	[universeRegion release];
	
	int i;
	for (i = 0; i < 256; i++)  [system_names[i] release];
	
	[[OOCacheManager sharedCache] flush];
	
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
	if (weakRef == weakSelf)  weakSelf = nil;
}


- (BOOL) doProcedurallyTexturedPlanets
{
	return doProcedurallyTexturedPlanets;
}


- (void) setDoProcedurallyTexturedPlanets:(BOOL) value
{
	doProcedurallyTexturedPlanets = value;
}


- (BOOL) strict
{
	return strict;
}


- (void) setStrict:(BOOL) value
{
	if (strict == value)  return;
	
	strict = value;
	[OOTexture clearCache];	// Force reload of texutres, since search paths effectively change
	
	[self reinit];
}


- (void) reinit
{	
    PlayerEntity* player = [[PlayerEntity sharedPlayer] retain];
	Quaternion q0 = kIdentityQuaternion;
	int i;
	
	no_update = YES;
	
	[self removeAllEntitiesExceptPlayer:NO];
	
	[ResourceManager setUseAddOns:!strict];
	[ResourceManager loadScripts];
	
#ifndef GNUSTEP
	//// speech stuff
	
	if (speechArray)
		[speechArray autorelease];
	speechArray = [[ResourceManager arrayFromFilesNamed:@"speech_pronunciation_guide.plist" inFolder:@"Config" andMerge:YES] retain];
	
	////
#endif
	
	
	firstBeacon = NO_TARGET;
	lastBeacon = NO_TARGET;
	
	next_universal_id = 100;	// start arbitrarily above zero
	for (i = 0; i < MAX_ENTITY_UID; i++)
		entity_for_uid[i] = nil;
	
	sun_center_position[0] = 4000000.0;
	sun_center_position[1] = 0.0;
	sun_center_position[2] = 0.0;
	sun_center_position[3] = 1.0;
	
	[gui autorelease];
	gui = [[GuiDisplayGen alloc] init];
	
	[message_gui autorelease];
	message_gui = [[GuiDisplayGen alloc]
					initWithPixelSize:NSMakeSize(480, 160)
							  columns:1
								 rows:8
							rowHeight:20
							 rowStart:20
								title:nil];
	[message_gui setCurrentRow:7];
	[message_gui setCharacterSize:NSMakeSize(16,20)];	// slightly narrower characters
	[message_gui setDrawPosition: make_vector(0.0, -40.0, 640.0)];
	[message_gui setAlpha:1.0];
	
	[comm_log_gui autorelease];
	comm_log_gui = [[GuiDisplayGen alloc]
					initWithPixelSize:NSMakeSize(360, 120)
							  columns:1
								 rows:10
							rowHeight:12
							 rowStart:12
								title:nil];
	[comm_log_gui setCurrentRow:9];
	[comm_log_gui setBackgroundColor:[OOColor colorWithCalibratedRed:0.0 green:0.05 blue:0.45 alpha:0.5]];
	[comm_log_gui setTextColor:[OOColor whiteColor]];
	[comm_log_gui setAlpha:0.0];
	[comm_log_gui printLongText:@"Communications Log" Align:GUI_ALIGN_CENTER Color:[OOColor yellowColor] FadeTime:0 Key:nil AddToArray:nil];
	[comm_log_gui setDrawPosition: make_vector(0.0, 180.0, 640.0)];
	
	time_delta = 0.0;
	universal_time = 0.0;
	
	[shipdata autorelease];
	shipdata = [[ResourceManager dictionaryFromFilesNamed:@"shipdata.plist" inFolder:@"Config" andMerge:YES] retain];
	
	[shipyard autorelease];
	shipyard = [[ResourceManager dictionaryFromFilesNamed:@"shipyard.plist" inFolder:@"Config" andMerge:YES] retain];
	
	[commoditylists autorelease];
	commoditylists = [(NSDictionary *)[ResourceManager dictionaryFromFilesNamed:@"commodities.plist" inFolder:@"Config" andMerge:YES] retain];
	
	[commoditydata autorelease];
	commoditydata = [[NSArray arrayWithArray:(NSArray *)[commoditylists objectForKey:@"default"]] retain];
	
	[illegal_goods autorelease];
	illegal_goods = [[ResourceManager dictionaryFromFilesNamed:@"illegal_goods.plist" inFolder:@"Config" andMerge:YES] retain];
	
	[descriptions autorelease];
	descriptions = [[ResourceManager dictionaryFromFilesNamed:@"descriptions.plist" inFolder:@"Config" andMerge:YES ] retain];
	
	[characters autorelease];
	characters = [[ResourceManager dictionaryFromFilesNamed:@"characters.plist" inFolder:@"Config" andMerge:YES ] retain];
	
	[customsounds autorelease];
	customsounds = [[ResourceManager dictionaryFromFilesNamed:@"customsounds.plist" inFolder:@"Config" andMerge:YES ] retain];
	
	[planetinfo autorelease];
	planetinfo = [[ResourceManager dictionaryFromFilesNamed:@"planetinfo.plist" inFolder:@"Config" mergeMode:MERGE_SMART cache:YES] retain];
	
	[equipmentdata autorelease];
	equipmentdata = [[ResourceManager arrayFromFilesNamed:@"equipment.plist" inFolder:@"Config" andMerge:YES] retain];
	if (strict && ([equipmentdata count] > NUMBER_OF_STRICT_EQUIPMENT_ITEMS))
	{
		NSArray* strict_equipment = [equipmentdata subarrayWithRange:NSMakeRange(0, NUMBER_OF_STRICT_EQUIPMENT_ITEMS)];	// alloc retains
		[equipmentdata autorelease];
		equipmentdata = [strict_equipment retain];
	}
	
	[demo_ships autorelease];
	demo_ships = [[ResourceManager arrayFromFilesNamed:@"demoships.plist" inFolder:@"Config" andMerge:YES] retain];
	demo_ship_index = 0;
	
	breakPatternCounter = 0;
	
	cachedSun = nil;
	cachedPlanet = nil;
	cachedStation = nil;
	
	station = NO_TARGET;
	planet = NO_TARGET;
	sun = NO_TARGET;
	
	if (player == nil)
		player = [[PlayerEntity alloc] init];
	[self addEntity:player];
	
	[[gameView gameController] setPlayerFileToLoad:nil];		// reset Quicksave

	[self setGalaxy_seed: [player galaxy_seed]];

	system_seed = [self findSystemAtCoords:[player galaxy_coordinates] withGalaxySeed:galaxy_seed];
	
	if (activeWormholes)
		[activeWormholes autorelease];
	activeWormholes = [[NSMutableArray arrayWithCapacity:16] retain];
	
	[characterPool removeAllObjects];

	[self setUpSpace];

	demo_ship = nil;
	
	
	[player set_up];
	
	[player setUpShipFromDictionary:[self getDictionaryForShip:[player ship_desc]]];	// ship_desc is the standard Cobra at this point
	
	[player setStatus:STATUS_DOCKED];
	[self setViewDirection:VIEW_GUI_DISPLAY];
	[player setPosition:kZeroVector];
	[player setOrientation:q0];
	[player setGuiToIntro2Screen];
	[gui setText:(strict)? @"Strict Play Enabled":@"Unrestricted Play Enabled" forRow:1 align:GUI_ALIGN_CENTER];
	
	
	[player release];
	
	no_update = NO;
	
	[local_planetinfo_overrides removeAllObjects];

}


- (int) obj_count
{
	return [entities count];
}


#ifndef NDEBUG
- (void) obj_dump
{
	int				i;
	int				show_count = n_entities;
	
	if (!OOLogWillDisplayMessagesInClass(@"universe.objectDump"))  return;
	
	OOLog(@"universe.objectDump", @"DEBUG ENTITY DUMP: [entities count] = %d,\tn_entities = %d", [entities count], n_entities);
	
	OOLogIndent();
	for (i = 0; i < show_count; i++)
	{
		ShipEntity* se = (sortedEntities[i]->isShip)? (ShipEntity*)sortedEntities[i]: nil;
		OOLog(@"universe.objectDump", @"-> Ent:%d\t\t%@ mass %.2f %@", i, sortedEntities[i], [sortedEntities[i] mass], [se getAI]);
	}
	OOLogOutdent();
	
	if ([entities count] != n_entities)
	{
		OOLog(@"universe.objectDump", @"entities = %@", [entities description]);
	}
}
#endif


- (void) sleepytime: (id) thing
{
	// deal with the machine going to sleep
	PlayerEntity *player = [PlayerEntity sharedPlayer];
	if ((player)&&(player->status == STATUS_IN_FLIGHT))
	{
		[self displayMessage:@" Paused (press 'p') " forCount:1.0];
		[[gameView gameController] pause_game];
	}
}


- (void) setUpUniverseFromStation
{
	if (![self sun])
	{
		// we're in witchspace or this is the first launch...		
		// save the player
		PlayerEntity*	player = [PlayerEntity sharedPlayer];
		// save the docked craft
		Entity*			docked_station = [player docked_station];
		// jump to the nearest system
		Random_Seed s_seed = [self findSystemAtCoords:[player galaxy_coordinates] withGalaxySeed:[player galaxy_seed]];
		[player setSystem_seed:s_seed];
		
		// I think we need to do this too!
		[self setSystemTo: s_seed];
			
		// remove everything except the player and the docked station
		if (docked_station)
		{
			int index = 0;
			while ([entities count] > 2)
			{
				Entity* ent = [entities objectAtIndex:index];
				if ((ent != player)&&(ent != docked_station))
				{
					if (ent->isStation)  // clear out queues
						[(StationEntity *)ent clear];
					[self removeEntity:ent];
				}
				else
				{
					index++;	// leave that one alone
				}
			}
		}
		else
		{
			[self removeAllEntitiesExceptPlayer:NO];	// get rid of witchspace sky etc. if still extant
		}

		[self setUpSpace];	// first launch
	}
	station = [[self station] universalID];
	planet = [[self planet] universalID];
	sun = [[self sun] universalID];
	
	[self setViewDirection:VIEW_FORWARD];
	displayGUI = NO;
}


- (void) set_up_universe_from_witchspace
{
    PlayerEntity		*player;

    //
	// check the player is still around!
    //
	if ([entities count] == 0)
	{
		/*- the player ship -*/
		player = [[PlayerEntity alloc] init];	// alloc retains!
		
		[self addEntity:player];
		
		/*--*/
	}
	else
	{
		player = [[PlayerEntity sharedPlayer] retain];	// retained here
	}
	

	[self setUpSpace];
	
	[player leaveWitchspace];
	[player release];											// released here
	
	[self setViewDirection:VIEW_FORWARD];
	
	[comm_log_gui printLongText:[NSString stringWithFormat:@"%@ %@", [self generateSystemName:system_seed], [player dial_clock_adjusted]]
		Align:GUI_ALIGN_CENTER Color:[OOColor whiteColor] FadeTime:0 Key:nil AddToArray:[player comm_log]];
	
    //
	/* test stuff */
	displayGUI = NO;
	/* ends */
}


- (void) set_up_universe_from_misjump
{
    PlayerEntity		*player;

    //
	// check the player is still around!
    //
	if ([entities count] == 0)
	{
		/*- the player ship -*/
		player = [[PlayerEntity alloc] init];	// alloc retains!
		
		[self addEntity:player];
		
		/*--*/
	}
	else
	{
		player = [[PlayerEntity sharedPlayer] retain];	// retained here
	}
	

	[self set_up_witchspace];
	
	[player leaveWitchspace];
	[player release];											// released here
	
	[self setViewDirection:VIEW_FORWARD];
	
    //
	/* test stuff */
	displayGUI = NO;
	/* ends */
}


- (void) set_up_witchspace
{
	// new system is hyper-centric : witchspace exit point is origin

    Entity				*thing;
	PlayerEntity*		player = [PlayerEntity sharedPlayer];
	Quaternion			randomQ;
	
	NSMutableDictionary*	systeminfo = [NSMutableDictionary dictionaryWithCapacity:4];

	if (player)
	{
		Random_Seed		s1 = player->system_seed;
		Random_Seed		s2 = player->target_system_seed;
		NSString*		override_key = [self keyForInterstellarOverridesForSystemSeeds:s1 :s2 inGalaxySeed:galaxy_seed];
		
		// check at this point
		// for scripted overrides for this insterstellar area
		[systeminfo addEntriesFromDictionary:[planetinfo dictionaryForKey:PLANETINFO_UNIVERSAL_KEY]];
		[systeminfo addEntriesFromDictionary:[planetinfo dictionaryForKey:@"interstellar space"]];
		[systeminfo addEntriesFromDictionary:[planetinfo dictionaryForKey:override_key]];
		[systeminfo addEntriesFromDictionary:[local_planetinfo_overrides dictionaryForKey:override_key]];
	}
	
	[universeRegion clearSubregions];
	
	// fixed entities (part of the graphics system really) come first...
	
	/*- the sky backdrop -*/
	OOColor *col1 = [OOColor colorWithCalibratedRed:0.0 green:1.0 blue:0.5 alpha:1.0];
	OOColor *col2 = [OOColor colorWithCalibratedRed:0.0 green:1.0 blue:0.0 alpha:1.0];
	thing = [[SkyEntity alloc] initWithColors:col1:col2 andSystemInfo: systeminfo];	// alloc retains!
	[thing setScanClass: CLASS_NO_DRAW];
	quaternion_set_random(&randomQ);
	[thing setOrientation:randomQ];
	[self addEntity:thing]; // [entities addObject:thing];
	[thing release];
	/*--*/
	
	/*- the dust particle system -*/
	thing = [[DustEntity alloc] init];	// alloc retains!
	[thing setScanClass: CLASS_NO_DRAW];
	[self addEntity:thing];
	[thing release];
	/*--*/
	
	sun = NO_TARGET;
	station = NO_TARGET;
	planet = NO_TARGET;
	sun_center_position[0] = 0.0;
	sun_center_position[1] = 0.0;
	sun_center_position[2] = 0.0;
	sun_center_position[3] = 1.0;
	
	ranrot_srand([[NSDate date] timeIntervalSince1970]);   // reset randomiser with current time
	
	[self setLighting];
		
	OOLog(kOOLogUniversePopulateWitchspace, @"Populating witchspace ...");
	OOLogIndentIf(kOOLogUniversePopulateWitchspace);
	
	// actual thargoids and tharglets next...
	int n_thargs = 2 + (ranrot_rand() & 3);
	if (n_thargs < 1)
		n_thargs = 2;   // just to be sure
	int i;
	int thargoid_group = NO_TARGET;

	Vector		tharg_start_pos = [self getWitchspaceExitPosition];
	ranrot_srand([[NSDate date] timeIntervalSince1970]);   // reset randomiser with current time

	OOLog(kOOLogUniversePopulateWitchspace, @"... adding %d Thargoid warships", n_thargs);
	
	for (i = 0; i < n_thargs; i++)
	{
		Quaternion  tharg_quaternion;
		ShipEntity  *thargoid = [self newShipWithRole:@"thargoid"]; // is retained
		if (thargoid)
		{
			Vector		tharg_pos = tharg_start_pos;
			
			tharg_pos.x += 1.5 * SCANNER_MAX_RANGE * (randf() - 0.5);
			tharg_pos.y += 1.5 * SCANNER_MAX_RANGE * (randf() - 0.5);
			tharg_pos.z += 1.5 * SCANNER_MAX_RANGE * (randf() - 0.5);
			[thargoid setPosition:tharg_pos];
			quaternion_set_random(&tharg_quaternion);
			[thargoid setOrientation:tharg_quaternion];
			[thargoid setScanClass: CLASS_THARGOID];
			[thargoid setBounty:100];
			[thargoid setStatus:STATUS_IN_FLIGHT];
			[self addEntity:thargoid];
			if (thargoid_group == NO_TARGET)
				thargoid_group = [thargoid universalID];
			
			[thargoid setGroupID:thargoid_group];
			
			[thargoid release];
		}
	}
	
	// systeminfo might have a 'script_actions' resource we want to activate now...
	
	if ([systeminfo objectForKey:KEY_SCRIPT_ACTIONS])
	{
		NSArray* script_actions = (NSArray *)[systeminfo objectForKey:KEY_SCRIPT_ACTIONS];
		
		[player scriptActions:script_actions forTarget: nil];
	}
	
	OOLogOutdentIf(kOOLogUniversePopulateWitchspace);
}


- (void) setUpSpace
{
    Entity				*thing;
    ShipEntity			*nav_buoy;
    StationEntity		*a_station;
    PlanetEntity		*a_sun;
    PlanetEntity		*a_planet;
	
	Vector				stationPos;
	
	Vector				vf;

	NSDictionary		*systeminfo = [self generateSystemData:system_seed];
	int					techlevel = [(NSNumber *)[systeminfo objectForKey:KEY_TECHLEVEL] intValue];
	NSString			*stationDesc;
	OOColor				*bgcolor;
	OOColor				*pale_bgcolor;
	
	BOOL				sun_gone_nova = NO;
	if ([systeminfo objectForKey:@"sun_gone_nova"])
		sun_gone_nova = YES;
	
	[universeRegion clearSubregions];
	
	// fixed entities (part of the graphics system really) come first...
	[self setSky_clear_color:0.0 :0.0 :0.0 :0.0];
	
	// set the system seed for random number generation
	seed_for_planet_description(system_seed);
	
	/*- the sky backdrop -*/
	// colors...
	float h1 = randf();
	float h2 = h1 + 1.0 / (1.0 + (ranrot_rand() % 5));
	while (h2 > 1.0)
		h2 -= 1.0;
	OOColor *col1 = [OOColor colorWithCalibratedHue:h1 saturation:randf() brightness:0.5 + randf()/2.0 alpha:1.0];
	OOColor *col2 = [OOColor colorWithCalibratedHue:h2 saturation:0.5 + randf()/2.0 brightness:0.5 + randf()/2.0 alpha:1.0];
	
	thing = [[SkyEntity alloc] initWithColors:col1:col2 andSystemInfo: systeminfo];	// alloc retains!
	[thing setScanClass: CLASS_NO_DRAW];
	[self addEntity:thing]; // [entities addObject:thing];
	bgcolor = [(SkyEntity *)thing skyColor];
	pale_bgcolor = [bgcolor blendedColorWithFraction:0.5 ofColor:[OOColor whiteColor]];
	[thing release];
	/*--*/
	
	[self setLighting];
	
	/*- the dust particle system -*/
	thing = [[DustEntity alloc] init];	// alloc retains!
	[thing setScanClass: CLASS_NO_DRAW];
	[self addEntity:thing]; // [entities addObject:thing];
	[(DustEntity *)thing setDustColor:pale_bgcolor]; 
	[thing release];
	/*--*/
	
	
	// actual entities next...
	
	
	// set the system seed for random number generation
	seed_for_planet_description(system_seed);
	
	/*- space planet -*/
	a_planet = [[PlanetEntity alloc] initWithSeed: system_seed];	// alloc retains!
	double planet_radius = [a_planet getRadius];
	double planet_zpos = (12.0 + (ranrot_rand() & 3) - (ranrot_rand() & 3) ) * planet_radius; // 10..14 pr (planet radii) ahead
	
	[a_planet setPlanetType:PLANET_TYPE_GREEN];
	[a_planet setStatus:STATUS_ACTIVE];
	[a_planet setPositionX:0 y:0 z:planet_zpos];
	[a_planet setScanClass: CLASS_NO_DRAW];
	[a_planet setEnergy:  1000000.0];
	[self addEntity:a_planet]; // [entities addObject:a_planet];
	
	planet = [a_planet universalID];
	/*--*/
	
	// set the system seed for random number generation
	seed_for_planet_description(system_seed);
	
	/*- space sun -*/
	double		sunDistanceModifier = 20.0;
	if ([systeminfo objectForKey:@"sun_distance_modifier"])
		sunDistanceModifier = [[systeminfo objectForKey:@"sun_distance_modifier"] doubleValue];

	double		sun_distance = (sunDistanceModifier + (ranrot_rand() % 5) - (ranrot_rand() % 5) ) * planet_radius;
	double		sun_radius = (2.5 + randf() - randf() ) * planet_radius;
	Quaternion  q_sun;
	Vector		sunPos = kZeroVector;
	
	// here we need to check if the sun collides with (or is too close to) the witchpoint
	// otherwise at (for example) Maregais in Galaxy 1 we go BANG!
	do {
		sunPos = a_planet->position;
		
		quaternion_set_random(&q_sun);
		// set up planet's direction in space so it gets a proper day
		[a_planet setOrientation:q_sun];
		
		vf = vector_right_from_quaternion(q_sun);
		sunPos.x -= sun_distance * vf.x;	// back off from the planet by 16..24 pr
		sunPos.y -= sun_distance * vf.y;
		sunPos.z -= sun_distance * vf.z;
	
	} while (magnitude2(sunPos) < 16 * sun_radius * sun_radius);	// stay at least 4 radii away!
	
	a_sun = [[PlanetEntity alloc] initAsSunWithColor:pale_bgcolor];	// alloc retains!
	[a_sun setPlanetType:PLANET_TYPE_SUN];
	[a_sun setStatus:STATUS_ACTIVE];
	[a_sun setPosition:sunPos];
	sun_center_position[0] = sunPos.x;
	sun_center_position[1] = sunPos.y;
	sun_center_position[2] = sunPos.z;
	sun_center_position[3] = 1.0;
	[a_sun setRadius:sun_radius];			// 2.5 pr
	[a_sun setScanClass: CLASS_NO_DRAW];
	[a_sun setEnergy:  1000000.0];
	[self addEntity:a_sun];					// [entities addObject:a_sun];
	sun = [a_sun universalID];
	
	if (sun_gone_nova)
	{
		[a_sun setRadius: sun_radius + 600000];
		[a_sun setThrowSparks:YES];
		[a_sun setVelocity: kZeroVector];
	}
	/*--*/
		
	
	/*- space station -*/
	stationPos = a_planet->position;
	double  station_orbit = 2.0 * planet_radius;
	Quaternion  q_station;
	vf.z = -1;
	while (vf.z <= 0.0)						// keep station on the correct side of the planet
	{
		quaternion_set_random(&q_station);
		vf = vector_forward_from_quaternion(q_station);
	}
	stationPos.x -= station_orbit * vf.x;					// back away from the planet
	stationPos.y -= station_orbit * vf.y;
	stationPos.z -= station_orbit * vf.z;
	
	stationDesc = @"coriolis";
	if (techlevel > 10)
	{
		if (system_seed.f & 0x03)   // 3 out of 4 get this type
			stationDesc = @"dodecahedron";
		else
			stationDesc = @"icosahedron";
	}
	
	//// possibly systeminfo has an override for the station
	stationDesc = [systeminfo stringForKey:@"station" defaultValue:stationDesc];
	
	a_station = (StationEntity *)[self newShipWithRole:stationDesc];			   // retain count = 1
	if (a_station)
	{
		[a_station setStatus:STATUS_ACTIVE];
		[a_station setOrientation: q_station];
		[a_station setPosition: stationPos];
		[a_station setPitch: 0.0];
		[a_station setScanClass: CLASS_STATION];
		[a_station setPlanet:(PlanetEntity *)[self entityForUniversalID:planet]];
		[a_station set_equivalent_tech_level:techlevel];
		[self addEntity:a_station];
		station = [a_station universalID];
	}

	cachedSun = a_sun;
	cachedPlanet = a_planet;
	cachedStation = a_station;
	
	ranrot_srand([[NSDate date] timeIntervalSince1970]);   // reset randomiser with current time
	
	[self populateSpaceFromActiveWormholes];
	
	[self populateSpaceFromHyperPoint:[self getWitchspaceExitPosition] toPlanetPosition: a_planet->position andSunPosition: a_sun->position];
	
	/*- nav beacon -*/
	nav_buoy = [self newShipWithRole:@"buoy"];	// retain count = 1
	if (nav_buoy)
	{
		[nav_buoy setRoll:	0.10];	// zero for debugging
		[nav_buoy setPitch:	0.15];	// zero for debugging
		[nav_buoy setPosition: [cachedStation getBeaconPosition]];
		[nav_buoy setScanClass: CLASS_BUOY];
		[self addEntity:nav_buoy];
		[nav_buoy setStatus:STATUS_IN_FLIGHT];
		[nav_buoy release];
	}
	/*--*/
	
	/*- nav beacon witchpoint -*/
	Vector witchpoint = [self getWitchspaceExitPosition];	// witchpoint
	nav_buoy = [self newShipWithRole:@"buoy-witchpoint"];	// retain count = 1
	if (nav_buoy)
	{
		[nav_buoy setRoll:	0.10];
		[nav_buoy setPitch:	0.15];
		[nav_buoy setPosition:witchpoint];
		[nav_buoy setScanClass: CLASS_BUOY];
		[self addEntity:nav_buoy];
		[nav_buoy setStatus:STATUS_IN_FLIGHT];
		[nav_buoy release];
	}
	/*--*/
	
	if (sun_gone_nova)
	{
		Vector v0 = make_vector(0,0,34567.89);
		Vector planetPos = a_planet->position;
		double min_safe_dist2 = 5000000.0 * 5000000.0;
		while (magnitude2(a_sun->position) < min_safe_dist2)	// back off the planetary bodies
		{
			v0.z *= 2.0;
			planetPos = a_planet->position;
			[a_planet setPosition:vector_add(planetPos, v0)];
			[a_sun setPosition:vector_add(sunPos, v0)];
			sunPos = a_sun->position;
			[a_station setPosition:vector_add(stationPos, v0)];
			stationPos = a_station->position;
		}
		sun_center_position[0] = sunPos.x;
		sun_center_position[1] = sunPos.y;
		sun_center_position[2] = sunPos.z;
		sun_center_position[3] = 1.0;
				
		[self removeEntity:a_planet];	// and Poof! it's gone
		cachedPlanet = nil;
		int i;
		for (i = 0; i < 3; i++)
		{
			[self scatterAsteroidsAt:planetPos withVelocity:kZeroVector includingRockHermit:NO];
			[self scatterAsteroidsAt:kZeroVector withVelocity:kZeroVector includingRockHermit:NO];
		}
		
	}
	
	[a_sun release];
	[a_station release];
	[a_planet release];
	
	// NEW
	
	// systeminfo might have a 'script_actions' resource we want to activate now...
	
	if ([systeminfo objectForKey:KEY_SCRIPT_ACTIONS])
	{
		PlayerEntity* player = [PlayerEntity sharedPlayer];
		NSArray* script_actions = [systeminfo objectForKey:KEY_SCRIPT_ACTIONS];
		
		[player scriptActions: script_actions forTarget: nil];
	}
}


// track the position and status of the lights
BOOL	sun_light_on = NO;
BOOL	demo_light_on = NO;
GLfloat	demo_light_position[] = DEMO_LIGHT_POSITION;
//
GLfloat docked_light_ambient[]	= { (GLfloat) 0.05, (GLfloat) 0.05, (GLfloat) 0.05, (GLfloat) 1.0};	// dark gray (low ambient)
GLfloat docked_light_diffuse[]	= { (GLfloat) 1.0, (GLfloat) 1.0, (GLfloat) 1.0, (GLfloat) 1.0};	// white
GLfloat docked_light_specular[]	= { (GLfloat) 1.0, (GLfloat) 1.0, (GLfloat) 0.5, (GLfloat) 1.0};	// yellow-white
- (void) setLighting
{
	/*
	
	GL_LIGHT1 is the sun and is active while a sun exists in space
	where there is no sun (witch/interstellar space) this is placed at the origin
	
	GL_LIGHT0 is the light for inside the station and needs to have its position reset
	relative to the player whenever demo ships or background scenes are to be shown
	
	*/
	
	NSDictionary*	systeminfo = [self generateSystemData:system_seed];
	PlanetEntity*	the_sun = [self sun];
	SkyEntity*		the_sky = nil;
	GLfloat			sun_pos[] = {4000000.0, 0.0, 0.0, 1.0};
	int i;
	for (i = n_entities - 1; i > 0; i--)
		if ((sortedEntities[i]) && ([sortedEntities[i] isKindOfClass:[SkyEntity class]]))
			the_sky = (SkyEntity*)sortedEntities[i];
	if (the_sun)
	{
		GLfloat	sun_ambient[] = { 0.0, 0.0, 0.0, 1.0};	// ambient light about 5%
		sun_diffuse[0] = the_sun->sun_diffuse[0];
		sun_diffuse[1] = the_sun->sun_diffuse[1];
		sun_diffuse[2] = the_sun->sun_diffuse[2];
		sun_diffuse[3] = the_sun->sun_diffuse[3];
		sun_specular[0] = the_sun->sun_specular[0];
		sun_specular[1] = the_sun->sun_specular[1];
		sun_specular[2] = the_sun->sun_specular[2];
		sun_specular[3] = the_sun->sun_specular[3];
		glLightfv(GL_LIGHT1, GL_AMBIENT, sun_ambient);
		glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_diffuse);
		glLightfv(GL_LIGHT1, GL_SPECULAR, sun_specular);
		sun_pos[0] = the_sun->position.x;
		sun_pos[1] = the_sun->position.y;
		sun_pos[2] = the_sun->position.z;
	}
	else
	{
		// witchspace
		GLfloat	sun_ambient[] = { 0.0, 0.0, 0.0, 1.0};	// ambient light nil
		stars_ambient[0] = 0.05;	stars_ambient[1] = 0.20;	stars_ambient[2] = 0.05;	stars_ambient[3] = 1.0;
		sun_diffuse[0] = 0.85;	sun_diffuse[1] = 1.0;	sun_diffuse[2] = 0.85;	sun_diffuse[3] = 1.0;
		sun_specular[0] = 0.95;	sun_specular[1] = 1.0;	sun_specular[2] = 0.95;	sun_specular[3] = 1.0;
		glLightfv(GL_LIGHT1, GL_AMBIENT, sun_ambient);
		glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_diffuse);
		glLightfv(GL_LIGHT1, GL_SPECULAR, sun_specular);
	}
	
	glLightfv(GL_LIGHT1, GL_POSITION, sun_pos);
	
	if (the_sky)
	{
		// ambient lighting!
		float r,g,b,a;
		[[the_sky skyColor] getRed:&r green:&g blue:&b alpha:&a];
		GLfloat ambient_level = [systeminfo floatForKey:@"ambient_level" defaultValue:1.0];
		stars_ambient[0] = ambient_level * 0.0625 * (1.0 + r) * (1.0 + r);
		stars_ambient[1] = ambient_level * 0.0625 * (1.0 + g) * (1.0 + g);
		stars_ambient[2] = ambient_level * 0.0625 * (1.0 + b) * (1.0 + b);
		stars_ambient[3] = 1.0;
	}
	
	// light for demo ships display..
	glLightfv(GL_LIGHT0, GL_AMBIENT, docked_light_ambient);
	glLightfv(GL_LIGHT0, GL_DIFFUSE, docked_light_diffuse);
	glLightfv(GL_LIGHT0, GL_SPECULAR, docked_light_specular);
	
	// glLightModel details...
	
	glLightModelfv(GL_LIGHT_MODEL_AMBIENT, stars_ambient);
	
	glDisable(GL_LIGHT0);
	demo_light_on = NO;
	glDisable(GL_LIGHT1);
	sun_light_on = NO;
}


- (void) populateSpaceFromActiveWormholes
{
	while ([activeWormholes count])
	{
		WormholeEntity* whole = (WormholeEntity*)[activeWormholes objectAtIndex:0];
		
		if (equal_seeds([whole destination], system_seed))
		{			
			// this is a wormhole to this system
			[whole disgorgeShips];
		}
		[activeWormholes removeObjectAtIndex:0];	// empty it out
	}
}


- (void) populateSpaceFromHyperPoint:(Vector) h1_pos toPlanetPosition:(Vector) p1_pos andSunPosition:(Vector) s1_pos
{
	int					i, r, escorts_added;
	NSDictionary		*systeminfo = [self generateSystemData:system_seed];
	NSAutoreleasePool	*pool = nil;

	BOOL				sun_gone_nova = NO;
	if ([systeminfo objectForKey:@"sun_gone_nova"])	// FIXME: this is never set anywhere. Obsolete flag? -- Ahruman
		sun_gone_nova = YES;
	
	int techlevel =		[[systeminfo objectForKey:KEY_TECHLEVEL] intValue];		// 0 .. 13
	int government =	[[systeminfo objectForKey:KEY_GOVERNMENT] intValue];	// 0 .. 7 (0 anarchic .. 7 most stable)
	int economy =		[[systeminfo objectForKey:KEY_ECONOMY] intValue];		// 0 .. 7 (0 richest .. 7 poorest)
	int thargoidChance = (system_seed.e < 127) ? 10 : 3; // if Human Colonials live here, there's a greater % chance the Thargoids will attack!
	Vector  lastPiratePosition = p1_pos;
	int		wolfPackCounter = 0;
	int		wolfPackGroup_id = NO_TARGET;
	
	ranrot_srand([[NSDate date] timeIntervalSince1970]);   // reset randomiser with current time
	
	OOLog(kOOLogUniversePopulate, @"Populating a system with economy %d, and government %d", economy, government);
	OOLogIndentIf(kOOLogUniversePopulate);
	
	// traders
	int trading_parties = (9 - economy);			// 2 .. 9
	if (government == 0) trading_parties *= 1.25;	// 25% more trade where there are no laws!
	if (trading_parties > 0)
		trading_parties = 1 + trading_parties * (randf()+randf());   // randomize 0..2
	while (trading_parties > 15)
		trading_parties = 1 + (ranrot_rand() % trading_parties);   // reduce
	
	OOLog(kOOLogUniversePopulate, @"... adding %d trading vessels", trading_parties);
	
	int skim_trading_parties = (ranrot_rand() & 3) + trading_parties * (ranrot_rand() & 31) / 120;	// about 12%
	
	OOLog(kOOLogUniversePopulate, @"... adding %d sun skimming vessels", skim_trading_parties);
	
	// pirates
	int anarchy = (8 - government);
	int raiding_parties = (ranrot_rand() % anarchy) + (ranrot_rand() % anarchy) + anarchy * trading_parties / 3;	// boosted
	if (raiding_parties > 0)
		raiding_parties =  raiding_parties * (randf()+randf());   // randomize
	while (raiding_parties > 25)
		raiding_parties = 12 + (ranrot_rand() % raiding_parties);   // reduce
	
	OOLog(kOOLogUniversePopulate, @"... adding %d pirate vessels", raiding_parties);

	int skim_raiding_parties = ((randf() < 0.14 * economy)? 1:0) + raiding_parties * (ranrot_rand() & 31) / 120;	// about 12%
	
	OOLog(kOOLogUniversePopulate, @"... adding %d sun skim pirates", skim_raiding_parties);
	
	// bounty-hunters and the law
	int hunting_parties = (1 + government) * trading_parties / 8;
	if (government == 0) hunting_parties *= 1.25;   // 25% more bounty hunters in an anarchy
	if (hunting_parties > 0)
		hunting_parties = hunting_parties * (randf()+randf());   // randomize
	while (hunting_parties > 15)
		hunting_parties = 5 + (ranrot_rand() % hunting_parties);   // reduce
	
	//debug
	if (hunting_parties < 1)
		hunting_parties = 1;
	
	OOLog(kOOLogUniversePopulate, @"... adding %d law/bounty-hunter vessels", hunting_parties);

	int skim_hunting_parties = ((randf() < 0.14 * government)? 1:0) + hunting_parties * (ranrot_rand() & 31) / 160;	// about 10%
	
	OOLog(kOOLogUniversePopulate, @"... adding %d sun skim law/bounty hunter vessels", skim_hunting_parties);
	
	int thargoid_parties = 0;
	while ((ranrot_rand() % 100) < thargoidChance)
		thargoid_parties++;

	OOLog(kOOLogUniversePopulate, @"... adding %d Thargoid warships", thargoid_parties);
	
	int rock_clusters = ranrot_rand() % 3;
	if (trading_parties + raiding_parties + hunting_parties < 10)
		rock_clusters += 1 + (ranrot_rand() % 3);

	rock_clusters *= 2;

	OOLog(kOOLogUniversePopulate, @"... adding %d asteroid clusters", rock_clusters);

	int total_clicks = trading_parties + raiding_parties + hunting_parties + thargoid_parties + rock_clusters + skim_hunting_parties + skim_raiding_parties + skim_trading_parties;
	
	OOLog(kOOLogUniversePopulate, @"... for a total of %d ships", total_clicks);
	OOLogOutdentIf(kOOLogUniversePopulate);
	
	Vector  v_route1 = p1_pos;
	v_route1.x -= h1_pos.x;	v_route1.y -= h1_pos.y;	v_route1.z -= h1_pos.z;
	double d_route1 = sqrt(v_route1.x*v_route1.x + v_route1.y*v_route1.y + v_route1.z*v_route1.z) - 60000.0; // -60km to avoid planet

	if (v_route1.x||v_route1.y||v_route1.z)
		v_route1 = unit_vector(&v_route1);
	else
		v_route1.z = 1.0;
	
	// add the traders to route1 (witchspace exit to space-station / planet)
	for (i = 0; (i < trading_parties)&&(!sun_gone_nova); i++)
	{
		pool = [[NSAutoreleasePool alloc] init];
		
		ShipEntity  *trader_ship;
		Vector		launch_pos = h1_pos;
		if (total_clicks < 3)   total_clicks = 3;
		r = 2 + (ranrot_rand() % (total_clicks - 2));  // find an empty slot
		double ship_location = d_route1 * r / total_clicks;
		launch_pos.x += ship_location * v_route1.x + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.y += ship_location * v_route1.y + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.z += ship_location * v_route1.z + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		trader_ship = [self newShipWithRole:@"trader"];   // retain count = 1
		if (trader_ship)
		{
			if (![trader_ship crew])
				[trader_ship setCrew:[NSArray arrayWithObject:
					[OOCharacter randomCharacterWithRole:@"trader"
					andOriginalSystem: systems[ranrot_rand() & 255]]]];
			
			if (trader_ship->scanClass == CLASS_NOT_SET)
				[trader_ship setScanClass: CLASS_NEUTRAL];
			[trader_ship setPosition:launch_pos];
			[trader_ship setBounty:0];
			[trader_ship setCargoFlag:CARGO_FLAG_FULL_SCARCE];
			[trader_ship setStatus:STATUS_IN_FLIGHT];
			
			if (([trader_ship escortCount] > 0)&&((ranrot_rand() % 7) < government))	// remove escorts if we feel safe
			{
				int nx = [trader_ship escortCount] - 2 * (1 + (ranrot_rand() & 3));	// remove 2,4,6, or 8 escorts
				[trader_ship setEscortCount:(nx > 0) ? nx : 0];
			}

			[self addEntity:trader_ship];
			[[trader_ship getAI] setStateMachine:@"route1traderAI.plist"];	// must happen after adding to the universe!
			[trader_ship release];
		}
		
		[pool release];
	}
	
	// add the raiders to route1 (witchspace exit to space-station / planet)
	for (i = 0; (i < raiding_parties)&&(!sun_gone_nova); i++)
	{
		pool = [[NSAutoreleasePool alloc] init];
		
		ShipEntity  *pirate_ship;
		Vector		launch_pos = h1_pos;
		if ((i > 0)&&((ranrot_rand() & 7) > wolfPackCounter))
		{
			// use last position
			launch_pos = lastPiratePosition;
			launch_pos.x += SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5)*0.1; // pack them closer together
			launch_pos.y += SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5)*0.1;
			launch_pos.z += SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5)*0.1;
			wolfPackCounter++;
		}
		else
		{
			// random position along route1
			if (total_clicks < 3)   total_clicks = 3;
			r = 2 + (ranrot_rand() % (total_clicks - 2));  // find an empty slot
			double ship_location = d_route1 * r / total_clicks;
			launch_pos.x += ship_location * v_route1.x + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
			launch_pos.y += ship_location * v_route1.y + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
			launch_pos.z += ship_location * v_route1.z + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
			lastPiratePosition = launch_pos;
			wolfPackCounter = 0;
		}
		pirate_ship = [self newShipWithRole:@"pirate"];   // retain count = 1
		if (pirate_ship)
		{
			if (![pirate_ship crew])
			{
				[pirate_ship setCrew:[NSArray arrayWithObject:
					[OOCharacter randomCharacterWithRole:@"pirate"
					andOriginalSystem: (randf() > 0.25)? systems[ranrot_rand() & 255]:system_seed]]];
			}
			
			if (pirate_ship->scanClass == CLASS_NOT_SET)
				[pirate_ship setScanClass: CLASS_NEUTRAL];
			[pirate_ship setPosition:launch_pos];
			[pirate_ship setStatus:STATUS_IN_FLIGHT];
			[pirate_ship setBounty: 20 + government + wolfPackCounter + (ranrot_rand() & 7)];
			[pirate_ship setCargoFlag: CARGO_FLAG_PIRATE];

			[self addEntity:pirate_ship];
			
			if (wolfPackCounter == 0)	// first ship
			{
				wolfPackGroup_id = [pirate_ship universalID];
			}
			[pirate_ship setGroupID:wolfPackGroup_id];
			
			[[pirate_ship getAI] setStateMachine:@"pirateAI.plist"];	// must happen after adding to the universe!
			[pirate_ship release];
		}
		
		[pool release];
	}
	
	// add the hunters and police ships to route1 (witchspace exit to space-station / planet)
	for (i = 0; (i < hunting_parties)&&(!sun_gone_nova); i++)
	{
		pool = [[NSAutoreleasePool alloc] init];
		
		ShipEntity  *hunter_ship;
		Vector		launch_pos = h1_pos;
		// random position along route1
		if (total_clicks < 3)   total_clicks = 3;
		r = 2 + (ranrot_rand() % (total_clicks - 2));  // find an empty slot
		double ship_location = d_route1 * r / total_clicks;
		launch_pos.x += ship_location * v_route1.x + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.y += ship_location * v_route1.y + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.z += ship_location * v_route1.z + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		
		escorts_added = 0;
		
		if ((ranrot_rand() & 7) < government)
		{
			if ((ranrot_rand() & 7) + 6 <= techlevel)
				hunter_ship = [self newShipWithRole:@"interceptor"];   // retain count = 1
			else
				hunter_ship = [self newShipWithRole:@"police"];   // retain count = 1
			if (hunter_ship)
			{
				if (![hunter_ship crew])
					[hunter_ship setCrew:[NSArray arrayWithObject:
						[OOCharacter randomCharacterWithRole:@"police"
						andOriginalSystem: (randf() > 0.05)? systems[ranrot_rand() & 255]:system_seed]]];
				
				[hunter_ship setRoles:@"police"];
				if (hunter_ship->scanClass == CLASS_NOT_SET)
					[hunter_ship setScanClass: CLASS_POLICE];
				while (((ranrot_rand() & 7) < government - 2)&&([hunter_ship escortCount] < 6))
				{
					[hunter_ship setEscortCount:[hunter_ship escortCount] + 2];
				}
				escorts_added = [hunter_ship escortCount];
			}
		}
		else
		{
			hunter_ship = [self newShipWithRole:@"hunter"];   // retain count = 1
			if ((hunter_ship)&&(hunter_ship->scanClass == CLASS_NOT_SET))
				[hunter_ship setScanClass: CLASS_NEUTRAL];
			if (![hunter_ship crew])
					[hunter_ship setCrew:[NSArray arrayWithObject:
					[OOCharacter randomCharacterWithRole:@"hunter"
					andOriginalSystem: (randf() > 0.75)? systems[ranrot_rand() & 255]:system_seed]]];
				
		}
		if (hunter_ship)
		{
			hunting_parties -= escorts_added / 2;	// reduce the number needed so we don't get huge swarms!
			
			[hunter_ship setPosition:launch_pos];
			[hunter_ship setStatus:STATUS_IN_FLIGHT];
			[hunter_ship setBounty:0];
			
			[self addEntity:hunter_ship];
			[[hunter_ship getAI] setStateMachine:@"route1patrolAI.plist"];	// must happen after adding to the universe!

			[hunter_ship release];
		}
		
		[pool release];
	}
	
	// add the thargoids to route1 (witchspace exit to space-station / planet) clustered together
	if (total_clicks < 3)   total_clicks = 3;
	r = 2 + (ranrot_rand() % (total_clicks - 2));  // find an empty slot
	double thargoid_location = d_route1 * r / total_clicks;
	for (i = 0; (i < thargoid_parties)&&(!sun_gone_nova); i++)
	{
		pool = [[NSAutoreleasePool alloc] init];
		
		ShipEntity  *thargoid_ship;
		Vector		launch_pos;
		launch_pos.x = h1_pos.x + thargoid_location * v_route1.x + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.y = h1_pos.y + thargoid_location * v_route1.y + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.z = h1_pos.z + thargoid_location * v_route1.z + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		thargoid_ship = [self newShipWithRole:@"thargoid"];   // retain count = 1
		if (thargoid_ship)
		{
			if (thargoid_ship->scanClass == CLASS_NOT_SET)
				[thargoid_ship setScanClass: CLASS_THARGOID];
			[thargoid_ship setPosition:launch_pos];
			[thargoid_ship setBounty:100];
			[thargoid_ship setStatus:STATUS_IN_FLIGHT];
			[self addEntity:thargoid_ship];
			[[thargoid_ship getAI] setState:@"GLOBAL"];
			[thargoid_ship release];
		}
		
		[pool release];
	}
	
	// add the asteroids to route1 (witchspace exit to space-station / planet) clustered together in a preset location.
	// set the system seed for random number generation
	int total_rocks = 0;
	seed_RNG_only_for_planet_description(system_seed);
	
	if (total_clicks < 3)   total_clicks = 3;
	for (i = 0; i < rock_clusters / 2 - 1; i++)
	{
		pool = [[NSAutoreleasePool alloc] init];
		
		int cluster_size = 1 + (ranrot_rand() % 6) + (ranrot_rand() % 6);
		r = 2 + (gen_rnd_number() % (total_clicks - 2));  // find an empty slot
		double asteroid_location = d_route1 * r / total_clicks;
		
		Vector	launch_pos = make_vector(h1_pos.x + asteroid_location * v_route1.x, h1_pos.y + asteroid_location * v_route1.y, h1_pos.z + asteroid_location * v_route1.z);
		total_rocks += [self	scatterAsteroidsAt: launch_pos
								withVelocity: kZeroVector
								includingRockHermit: (((ranrot_rand() & 31) <= cluster_size)&&(r < total_clicks * 2 / 3)&&(!sun_gone_nova))];
		
		[pool release];
	}
		
	
	//	Now do route2 planet -> sun
	
	
	Vector  v_route2 = s1_pos;
	v_route2.x -= p1_pos.x;	v_route2.y -= p1_pos.y;	v_route2.z -= p1_pos.z;
	double d_route2 = sqrt(magnitude2(v_route2));
	
	if (v_route2.x||v_route2.y||v_route2.z)
		v_route2 = unit_vector(&v_route1);
	else
		v_route2.x = 1.0;
	
	// add the traders to route2
	for (i = 0; (i < skim_trading_parties)&&(!sun_gone_nova); i++)
	{
		pool = [[NSAutoreleasePool alloc] init];
		
		ShipEntity*	trader_ship;
		Vector		launch_pos = p1_pos;
		double		start = 4.0 * [[self planet] getRadius];
		double		end = 3.0 * [[self sun] getRadius];
		double		max_length = d_route2 - (start + end);
		double		ship_location = randf() * max_length + start;
//
		launch_pos.x += ship_location * v_route2.x + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.y += ship_location * v_route2.y + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.z += ship_location * v_route2.z + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		trader_ship = [self newShipWithRole:@"sunskim-trader"];   // retain count = 1
		if (trader_ship)
		{
			if (![trader_ship crew])
				[trader_ship setCrew:[NSArray arrayWithObject:
					[OOCharacter randomCharacterWithRole:@"trader"
					andOriginalSystem: (randf() > 0.85)? systems[ranrot_rand() & 255]:system_seed]]];
				
			[trader_ship setRoles:@"trader"];	// set this to allow escorts to pair with the ship
			if ((trader_ship)&&(trader_ship->scanClass == CLASS_NOT_SET))
				[trader_ship setScanClass: CLASS_NEUTRAL];
			[trader_ship setPosition:launch_pos];
			[trader_ship setBounty:0];
			[trader_ship setCargoFlag:CARGO_FLAG_FULL_PLENTIFUL];
			[trader_ship setStatus:STATUS_IN_FLIGHT];
			
			if (([trader_ship escortCount] > 0)&&((ranrot_rand() % 7) < government))	// remove escorts if we feel safe
			{
				int nx = [trader_ship escortCount] - 2 * (1 + (ranrot_rand() & 3));	// remove 2,4,6, or 8 escorts
				[trader_ship setEscortCount:(nx > 0) ? nx : 0];
			}
			
			[self addEntity:trader_ship];
			[[trader_ship getAI] setStateMachine:@"route2sunskimAI.plist"];	// must happen after adding to the universe!

			[trader_ship release];
		}
		
		[pool release];
	}
	
	// add the raiders to route2
	for (i = 0; (i < skim_raiding_parties)&&(!sun_gone_nova); i++)
	{
		pool = [[NSAutoreleasePool alloc] init];
		
		ShipEntity*	pirate_ship;
		Vector		launch_pos = p1_pos;
		if ((i > 0)&&((ranrot_rand() & 7) > wolfPackCounter))
		{
			// use last position
			launch_pos = lastPiratePosition;
			launch_pos.x += SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5)*0.1; // pack them closer together
			launch_pos.y += SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5)*0.1;
			launch_pos.z += SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5)*0.1;
			wolfPackCounter++;
		}
		else
		{
			// random position along route2
			double		start = 4.0 * [[self planet] getRadius];
			double		end = 3.0 * [[self sun] getRadius];
			double		max_length = d_route2 - (start + end);
			double		ship_location = randf() * max_length + start;
			launch_pos.x += ship_location * v_route2.x + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
			launch_pos.y += ship_location * v_route2.y + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
			launch_pos.z += ship_location * v_route2.z + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
			lastPiratePosition = launch_pos;
			wolfPackCounter = 0;
		}
		pirate_ship = [self newShipWithRole:@"pirate"];   // retain count = 1
		if (pirate_ship)
		{
			if (![pirate_ship crew])
				[pirate_ship setCrew:[NSArray arrayWithObject:
					[OOCharacter randomCharacterWithRole:@"pirate"
					andOriginalSystem: (randf() > 0.25)? systems[ranrot_rand() & 255]:system_seed]]];

			if (pirate_ship->scanClass == CLASS_NOT_SET)
				[pirate_ship setScanClass: CLASS_NEUTRAL];
			[pirate_ship setPosition: launch_pos];
			[pirate_ship setStatus: STATUS_IN_FLIGHT];
			[pirate_ship setBounty: 20 + government + wolfPackCounter + (ranrot_rand() % 7)];
			[pirate_ship setCargoFlag: CARGO_FLAG_PIRATE];

			[self addEntity:pirate_ship];
			
			if (wolfPackCounter == 0)	// first ship
				wolfPackGroup_id = [pirate_ship universalID];

			[pirate_ship setGroupID:wolfPackGroup_id];
			
			[[pirate_ship getAI] setStateMachine:@"pirateAI.plist"];	// must happen after adding to the universe!
			[pirate_ship release];
		}
		
		[pool release];
	}
	
	// add the hunters and police ships to route2
	for (i = 0; (i < skim_hunting_parties)&&(!sun_gone_nova); i++)
	{
		pool = [[NSAutoreleasePool alloc] init];
		
		ShipEntity*	hunter_ship;
		Vector		launch_pos = p1_pos;
		double		start = 4.0 * [[self planet] getRadius];
		double		end = 3.0 * [[self sun] getRadius];
		double		max_length = d_route2 - (start + end);
		double		ship_location = randf() * max_length + start;

		launch_pos.x += ship_location * v_route2.x + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.y += ship_location * v_route2.y + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.z += ship_location * v_route2.z + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		
		escorts_added = 0;
		
		if ((ranrot_rand() & 7) < government)
		{
			if ((ranrot_rand() & 7) + 6 <= techlevel)
				hunter_ship = [self newShipWithRole:@"interceptor"];   // retain count = 1
			else
				hunter_ship = [self newShipWithRole:@"police"];   // retain count = 1
			if (hunter_ship)
			{
				if (![hunter_ship crew])
					[hunter_ship setCrew:[NSArray arrayWithObject:
						[OOCharacter randomCharacterWithRole:@"police"
						andOriginalSystem: (randf() > 0.05)? systems[ranrot_rand() & 255]:system_seed]]];
				
				[hunter_ship setRoles:@"police"];
				if (hunter_ship->scanClass == CLASS_NOT_SET)
					[hunter_ship setScanClass: CLASS_POLICE];
				while (((ranrot_rand() & 7) < government - 2)&&([hunter_ship escortCount] < 6))
				{
					[hunter_ship setEscortCount:[hunter_ship escortCount] + 2];
				}
				escorts_added = [hunter_ship escortCount];
			}
		}
		else
		{
			hunter_ship = [self newShipWithRole:@"hunter"];   // retain count = 1
			if ((hunter_ship)&&(hunter_ship->scanClass == CLASS_NOT_SET))
				[hunter_ship setScanClass: CLASS_NEUTRAL];
			if (![hunter_ship crew])
					[hunter_ship setCrew:[NSArray arrayWithObject:
						[OOCharacter randomCharacterWithRole:@"hunter"
						andOriginalSystem: (randf() > 0.75)? systems[ranrot_rand() & 255]:system_seed]]];
				
		}
		
		if (hunter_ship)
		{
			[hunter_ship setPosition:launch_pos];
			[hunter_ship setStatus:STATUS_IN_FLIGHT];
			[hunter_ship setBounty:0];

			[self addEntity:hunter_ship];
			[[hunter_ship getAI] setStateMachine:@"route2patrolAI.plist"];	// must happen after adding to the universe!
			
			if (randf() > 0.50)	// 50% chance
				[[hunter_ship getAI] setState:@"HEAD_FOR_PLANET"];
			else
				[[hunter_ship getAI] setState:@"HEAD_FOR_SUN"];
			
			[hunter_ship release];
		}
		
		[pool release];
	}

	// add the asteroids to route2 clustered together in a preset location.
	seed_RNG_only_for_planet_description(system_seed);	// set the system seed for random number generation
	
	if (total_clicks < 3)   total_clicks = 3;
	for (i = 0; i < rock_clusters / 2 + 1; i++)
	{
		pool = [[NSAutoreleasePool alloc] init];
		
		double	start = 6.0 * [[self planet] getRadius];
		double	end = 4.5 * [[self sun] getRadius];
		double	max_length = d_route2 - (start + end);
		double	asteroid_location = randf() * max_length + start;
		int cluster_size = 1 + (ranrot_rand() % 6) + (ranrot_rand() % 6);
		
		Vector	launch_pos = make_vector(p1_pos.x + asteroid_location * v_route2.x, p1_pos.y + asteroid_location * v_route2.y, p1_pos.z + asteroid_location * v_route2.z);
		total_rocks += [self	scatterAsteroidsAt: launch_pos
								withVelocity: kZeroVector
								includingRockHermit: (((ranrot_rand() & 31) <= cluster_size)&&(asteroid_location > 0.33 * max_length)&&(!sun_gone_nova))];
		[pool release];
	}
	
}


- (int) scatterAsteroidsAt:(Vector) spawnPos withVelocity:(Vector) spawnVel includingRockHermit:(BOOL) spawnHermit
{
	int rocks = 0;
	Vector		launch_pos;
	int i;
	int cluster_size = 1 + (ranrot_rand() % 6) + (ranrot_rand() % 6);
	for (i = 0; i < cluster_size; i++)
	{
		ShipEntity*	asteroid;
		int n_rocks = 2 + (ranrot_rand() % 5);
		launch_pos.x = spawnPos.x + SCANNER_MAX_RANGE * (randf() - randf());
		launch_pos.y = spawnPos.y + SCANNER_MAX_RANGE * (randf() - randf());
		launch_pos.z = spawnPos.z + SCANNER_MAX_RANGE * (randf() - randf());
		asteroid = [self newShipWithRole:@"asteroid"];   // retain count = 1
		if (asteroid)
		{
			if (asteroid->scanClass == CLASS_NOT_SET)
				[asteroid setScanClass: CLASS_ROCK];
			[asteroid setPosition:launch_pos];
			[asteroid setVelocity:spawnVel];
			[asteroid setStatus:STATUS_IN_FLIGHT];
			[asteroid setNumberOfMinedRocks: n_rocks];
			[self addEntity:asteroid];
			[[asteroid getAI] setState:@"GLOBAL"];
			[asteroid release];
			rocks++;
		}
	}
	// rock-hermit : chance is related to the number of asteroids
	// hermits are placed near to other asteroids for obvious reasons
	
	// hermits should not be placed too near the planet-end of route2,
	// or ships will dock there rather than at the main station !
	
	if (spawnHermit)
	{
		StationEntity*	hermit;
		launch_pos.x = spawnPos.x + 0.5 * SCANNER_MAX_RANGE * (randf() - randf());
		launch_pos.y = spawnPos.y + 0.5 * SCANNER_MAX_RANGE * (randf() - randf());
		launch_pos.z = spawnPos.z + 0.5 * SCANNER_MAX_RANGE * (randf() - randf());
		hermit = (StationEntity *)[self newShipWithRole:@"rockhermit"];   // retain count = 1
		if (hermit)
		{
			if (hermit->scanClass == CLASS_NOT_SET)
				[hermit setScanClass: CLASS_ROCK];
			[hermit setPosition:launch_pos];
			[hermit setVelocity:spawnVel];
			[hermit setStatus:STATUS_IN_FLIGHT];
			[self addEntity:hermit];
			[[hermit getAI] setState:@"GLOBAL"];
			[hermit release];
			cluster_size++;
		}
	}
	
	return rocks;
}


- (void) addShipWithRole:(NSString *) desc nearRouteOneAt:(double) route_fraction
{
	// adds a ship within scanner range of a point on route 1
	
	Entity* the_station = [self station];
	if (!the_station)
		return;
	Vector  h1_pos = [self getWitchspaceExitPosition];
	Vector  launch_pos = the_station->position;
	launch_pos.x -= h1_pos.x;		launch_pos.y -= h1_pos.y;		launch_pos.z -= h1_pos.z;
	launch_pos.x *= route_fraction; launch_pos.y *= route_fraction; launch_pos.z *= route_fraction;
	launch_pos.x += h1_pos.x;		launch_pos.y += h1_pos.y;		launch_pos.z += h1_pos.z;
	
	launch_pos.x += SCANNER_MAX_RANGE*(randf() - randf());
	launch_pos.y += SCANNER_MAX_RANGE*(randf() - randf());
	launch_pos.z += SCANNER_MAX_RANGE*(randf() - randf());
	
	ShipEntity  *ship;
	ship = [self newShipWithRole:desc];   // retain count = 1
	if (ship)
	{
		if (![ship crew])
			[ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: desc
				andOriginalSystem: systems[ranrot_rand() & 255]]]];
				
		if ((ship->scanClass == CLASS_NO_DRAW)||(ship->scanClass == CLASS_NOT_SET))
			[ship setScanClass: CLASS_NEUTRAL];
		[ship setPosition:launch_pos];
		[self addEntity:ship];
		[[ship getAI] setState:@"GLOBAL"];	// must happen after adding to the universe!
		
		[ship setStatus:STATUS_IN_FLIGHT];	// or ships that were 'demo' ships become invisible!
		
		[ship release];
	}
	
}


- (Vector) coordinatesForPosition:(Vector) pos withCoordinateSystem:(NSString *) system returningScalar:(GLfloat*) my_scalar
{
	/*	the point is described using a system selected by a string
		consisting of a three letter code.
		
		The first letter indicates the feature that is the origin of the coordinate system.
			w => witchpoint
			s => sun
			p => planet
			
		The next letter indicates the feature on the 'z' axis of the coordinate system.
			w => witchpoint
			s => sun
			p => planet
			
		Then the 'y' axis of the system is normal to the plane formed by the planet, sun and witchpoint.
		And the 'x' axis of the system is normal to the y and z axes.
		So:
			ps:		z axis = (planet -> sun)		y axis = normal to (planet - sun - witchpoint)	x axis = normal to y and z axes
			pw:		z axis = (planet -> witchpoint)	y axis = normal to (planet - witchpoint - sun)	x axis = normal to y and z axes
			sp:		z axis = (sun -> planet)		y axis = normal to (sun - planet - witchpoint)	x axis = normal to y and z axes
			sw:		z axis = (sun -> witchpoint)	y axis = normal to (sun - witchpoint - planet)	x axis = normal to y and z axes
			wp:		z axis = (witchpoint -> planet)	y axis = normal to (witchpoint - planet - sun)	x axis = normal to y and z axes
			ws:		z axis = (witchpoint -> sun)	y axis = normal to (witchpoint - sun - planet)	x axis = normal to y and z axes
			
		The third letter denotes the units used:
			m:		meters
			p:		planetary radii
			s:		solar radii
			u:		distance between first two features indicated (eg. spu means that u = distance from sun to the planet)
		
		in witchspace (== no sun) coordinates are absolute irrespective of the system used
		
	*/
	
	NSString* l_sys = [system lowercaseString];
	if ([l_sys length] != 3)
		return kZeroVector;
	PlanetEntity* the_planet = [self planet];
	PlanetEntity* the_sun = [self sun];
	if ((!the_planet)||(!the_sun))
	{
		if (my_scalar)
			*my_scalar = 1.0;
		return pos;
	}
	Vector  w_pos = [self getWitchspaceExitPosition];
	Vector  p_pos = the_planet->position;
	Vector  s_pos = the_sun->position;
	
	const char* c_sys = [l_sys lossyCString];
	Vector p0 = make_vector(1,0,0);
	Vector p1 = make_vector(0,1,0);
	Vector p2 = make_vector(0,0,1);
	
	switch (c_sys[0])
	{
		case 'w':
			p0 = w_pos;
			switch (c_sys[1])
			{
				case 'p':
					p1 = p_pos;	p2 = s_pos;	break;
				case 's':
					p1 = s_pos;	p2 = p_pos;	break;
				default:
					return kZeroVector;
			}
			break;
		case 'p':		
			p0 = p_pos;
			switch (c_sys[1])
			{
				case 'w':
					p1 = w_pos;	p2 = s_pos;	break;
				case 's':
					p1 = s_pos;	p2 = w_pos;	break;
				default:
					return kZeroVector;
			}
			break;
		case 's':
			p0 = s_pos;
			switch (c_sys[1])
			{
				case 'w':
					p1 = w_pos;	p2 = p_pos;	break;
				case 'p':
					p1 = p_pos;	p2 = w_pos;	break;
				default:
					return kZeroVector;
			}
			break;
		default:
			return kZeroVector;
	}
	Vector k = make_vector(p1.x - p0.x, p1.y - p0.y, p1.z - p0.z);
	if (k.x||k.y||k.z)
		k = unit_vector(&k);	//	'forward'
	else
		k.z = 1.0;
	Vector v = make_vector(p2.x - p0.x, p2.y - p0.y, p2.z - p0.z);
	if (v.x||v.y||v.z)
		v = unit_vector(&v);		//	temporary vector in plane of 'forward' and 'right'
	else
		v.x = 1.0;
	Vector j = cross_product(k, v);	// 'up'
	Vector i = cross_product(j, k);	// 'right'
	GLfloat scalar = 1.0;
	switch (c_sys[2])
	{
		case 'p':
			scalar = ([self planet])? [self planet]->collision_radius: 5000;	break;
		case 's':
			scalar = ([self sun])? [self sun]->collision_radius: 100000;	break;
		case 'u':
			scalar = sqrt(magnitude2(make_vector(p1.x - p0.x, p1.y - p0.y, p1.z - p0.z)));	break;
		case 'm':
			scalar = 1.0;	break;
		default:
			return kZeroVector;
	}
	if (my_scalar)
		*my_scalar = scalar;
	
	// result = p0 + ijk
	Vector result = p0;	// origin
	result.x += scalar * (pos.x * i.x + pos.y * j.x + pos.z * k.x);
	result.y += scalar * (pos.x * i.y + pos.y * j.y + pos.z * k.y);
	result.z += scalar * (pos.x * i.z + pos.y * j.z + pos.z * k.z);
	
	return result;
}


- (NSString *) expressPosition:(Vector) pos inCoordinateSystem:(NSString *) system
{
	
	NSString* l_sys = [system lowercaseString];
	if ([l_sys length] != 3)
		return nil;
	PlanetEntity* the_planet = [self planet];
	PlanetEntity* the_sun = [self sun];
	if ((!the_planet)||(!the_sun))
	{
		return [NSString stringWithFormat:@"%@ %.2f %.2f %.2f", system, pos.x, pos.y, pos.z];
	}
	Vector  w_pos = [self getWitchspaceExitPosition];
	Vector  p_pos = the_planet->position;
	Vector  s_pos = the_sun->position;
	
	const char* c_sys = [l_sys lossyCString];
	Vector p0 = make_vector(1,0,0);
	Vector p1 = make_vector(0,1,0);
	Vector p2 = make_vector(0,0,1);
	
	switch (c_sys[0])
	{
		case 'w':
			p0 = w_pos;
			switch (c_sys[1])
			{
				case 'p':
					p1 = p_pos;	p2 = s_pos;	break;
				case 's':
					p1 = s_pos;	p2 = p_pos;	break;
				default:
					return nil;
			}
			break;
		case 'p':		
			p0 = p_pos;
			switch (c_sys[1])
			{
				case 'w':
					p1 = w_pos;	p2 = s_pos;	break;
				case 's':
					p1 = s_pos;	p2 = w_pos;	break;
				default:
					return nil;
			}
			break;
		case 's':
			p0 = s_pos;
			switch (c_sys[1])
			{
				case 'w':
					p1 = w_pos;	p2 = p_pos;	break;
				case 'p':
					p1 = p_pos;	p2 = w_pos;	break;
				default:
					return nil;
			}
			break;
		default:
			return nil;
	}
	Vector k = make_vector(p1.x - p0.x, p1.y - p0.y, p1.z - p0.z);
	if (k.x||k.y||k.z)
		k = unit_vector(&k);			//	'z' axis in m
	else
		k.z = 1.0;
	Vector v = make_vector(p2.x - p0.x, p2.y - p0.y, p2.z - p0.z);
	if (v.x||v.y||v.z)
		v = unit_vector(&v);		//	temporary vector in plane of 'forward' and 'right'
	else
		v.x = 1.0;
	Vector j = cross_product(k, v);	// 'y' axis in m
	Vector i = cross_product(j, k);	// 'x' axis in m
	GLfloat scalar = 1.0;
	switch (c_sys[2])
	{
		case 'p':
			scalar = 1.0 / (([self planet])? [self planet]->collision_radius: 5000);	break;
		case 's':
			scalar = 1.0 / (([self sun])? [self sun]->collision_radius: 100000);	break;
		case 'u':
			scalar = 1.0 / sqrt(magnitude2(make_vector(p1.x - p0.x, p1.y - p0.y, p1.z - p0.z)));	break;
		case 'm':
			scalar = 1.0;	break;
		default:
			return nil;
	}
	
	// result = p0 + ijk
	Vector r_pos = make_vector(pos.x - p0.x, pos.y - p0.y, pos.z - p0.z);
	Vector result = make_vector(	scalar * (r_pos.x * i.x + r_pos.y * i.y + r_pos.z * i.z),
									scalar * (r_pos.x * j.x + r_pos.y * j.y + r_pos.z * j.z),
									scalar * (r_pos.x * k.x + r_pos.y * k.y + r_pos.z * k.z) ); // scalar * dot_products
	
	return [NSString stringWithFormat:@"%@ %.2f %.2f %.2f", system, result.x, result.y, result.z];
}


- (Vector) coordinatesFromCoordinateSystemString:(NSString *) system_x_y_z
{
	NSArray* tokens = ScanTokensFromString(system_x_y_z);
	if ([tokens count] != 4)
	{
		// Not necessarily an error.
		return make_vector(0,0,0);
	}
	GLfloat dummy;
	return [self coordinatesForPosition:make_vector([[tokens objectAtIndex:1] floatValue], [[tokens objectAtIndex:2] floatValue], [[tokens objectAtIndex:3] floatValue]) withCoordinateSystem:(NSString *)[tokens objectAtIndex:0] returningScalar:&dummy];
}


- (BOOL) addShipWithRole:(NSString *) desc nearPosition:(Vector) pos withCoordinateSystem:(NSString *) system
{
	// initial position
	GLfloat scalar = 1.0;
	Vector launch_pos = [self coordinatesForPosition:pos withCoordinateSystem:system returningScalar:&scalar];
	//	randomise
	GLfloat rfactor = scalar;
	if (rfactor > SCANNER_MAX_RANGE)
		rfactor = SCANNER_MAX_RANGE;
	if (rfactor < 1000)
		rfactor = 1000;
	launch_pos.x += rfactor*(randf() - randf());
	launch_pos.y += rfactor*(randf() - randf());
	launch_pos.z += rfactor*(randf() - randf());
	
	ShipEntity  *ship;
	ship = [self newShipWithRole:desc];   // retain count = 1
	if (ship)
	{
		if (![ship crew])
			[ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: desc
				andOriginalSystem: systems[ranrot_rand() & 255]]]];
				
		if ((ship->scanClass == CLASS_NO_DRAW)||(ship->scanClass == CLASS_NOT_SET))
			[ship setScanClass: CLASS_NEUTRAL];
		[ship setPosition:launch_pos];
		[self addEntity:ship];
		[[ship getAI] setState:@"GLOBAL"];	// must happen after adding to the universe!
		[ship setStatus:STATUS_IN_FLIGHT];	// or ships that were 'demo' ships become invisible!
		[ship release];
		return YES;
	}
	
	return NO;
}


- (BOOL) addShips:(int) howMany withRole:(NSString *) desc atPosition:(Vector) pos withCoordinateSystem:(NSString *) system
{
	// initial bounding box
	GLfloat scalar = 1.0;
	Vector launch_pos = [self coordinatesForPosition:pos withCoordinateSystem:system returningScalar:&scalar];
	GLfloat distance_from_center = 0.0;
	Vector v_from_center, ship_pos;
	Vector ship_positions[howMany];
	int i = 0;
	int	scale_up_after = 0;
	int	current_shell = 0;
	GLfloat	walk_factor = 2.0;
	while (i < howMany)
	{
		ShipEntity  *ship;
		ship = [self newShipWithRole:desc];   // retain count = 1
		if (!ship)
			return NO;
		if (![ship crew])
			[ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: desc
				andOriginalSystem: systems[ranrot_rand() & 255]]]];
		
		GLfloat safe_distance2 = 2.0 * ship->collision_radius * ship->collision_radius * PROXIMITY_WARN_DISTANCE2;
		
		BOOL safe;
		
		int limit_count = 8;
		
		v_from_center = kZeroVector;
		do
		{
			do
			{
				v_from_center.x += walk_factor * (randf() - 0.5);
				v_from_center.y += walk_factor * (randf() - 0.5);
				v_from_center.z += walk_factor * (randf() - 0.5);	// drunkards walk
			} while ((v_from_center.x == 0.0)&&(v_from_center.y == 0.0)&&(v_from_center.z == 0.0));
			v_from_center = unit_vector(&v_from_center);	// guaranteed non-zero
						
			ship_pos = make_vector(	launch_pos.x + distance_from_center * v_from_center.x,
									launch_pos.y + distance_from_center * v_from_center.y,
									launch_pos.z + distance_from_center * v_from_center.z);
			
			// check this position against previous ship positions in this shell
			safe = YES;
			int j = i - 1;
			while (safe && (j >= current_shell))
			{
				safe = (safe && (distance2(ship_pos, ship_positions[j]) > safe_distance2));
				j--;
			}
			if (!safe)
			{
				limit_count--;
				if (!limit_count)	// give up and expand the shell
				{
					limit_count = 8;
					distance_from_center += sqrt(safe_distance2);	// expand to the next distance
				}
			}
			
			
		} while (!safe);
		
		if ((ship->scanClass == CLASS_NO_DRAW)||(ship->scanClass == CLASS_NOT_SET))
			[ship setScanClass: CLASS_NEUTRAL];
		[ship setPosition:ship_pos];
		
		Quaternion qr;
		quaternion_set_random(&qr);
		[ship setOrientation:qr];
		
		[self addEntity:ship];
		[[ship getAI] setState:@"GLOBAL"];	// must happen after adding to the universe!
		[ship setStatus:STATUS_IN_FLIGHT];	// or ships that were 'demo' ships become invisible!
		[ship release];
		
		ship_positions[i] = ship_pos;
		i++;
		if (i > scale_up_after)
		{
			current_shell = i;
			scale_up_after += 1 + 2 * i;
			distance_from_center += sqrt(safe_distance2);	// fill the next shell
		}
	}
	return YES;
}


- (BOOL) addShips:(int) howMany withRole:(NSString *) desc nearPosition:(Vector) pos withCoordinateSystem:(NSString *) system
{
	// initial bounding box
	GLfloat scalar = 1.0;
	Vector launch_pos = [self coordinatesForPosition:pos withCoordinateSystem:system returningScalar:&scalar];
	GLfloat rfactor = scalar;
	if (rfactor > SCANNER_MAX_RANGE)
		rfactor = SCANNER_MAX_RANGE;
	if (rfactor < 1000)
		rfactor = 1000;
	BoundingBox	launch_bbox;
	bounding_box_reset_to_vector(&launch_bbox, make_vector(launch_pos.x - rfactor, launch_pos.y - rfactor, launch_pos.z - rfactor));
	bounding_box_add_xyz(&launch_bbox, launch_pos.x + rfactor, launch_pos.y + rfactor, launch_pos.z + rfactor);
	
	return [self addShips: howMany withRole: desc intoBoundingBox: launch_bbox];
}


- (BOOL) addShips:(int) howMany withRole:(NSString *) desc nearPosition:(Vector) pos withCoordinateSystem:(NSString *) system withinRadius:(GLfloat) radius
{
	// initial bounding box
	GLfloat scalar = 1.0;
	Vector launch_pos = [self coordinatesForPosition:pos withCoordinateSystem:system returningScalar:&scalar];
	GLfloat rfactor = radius;
	if (rfactor < 1000)
		rfactor = 1000;
	BoundingBox	launch_bbox;
	bounding_box_reset_to_vector(&launch_bbox, make_vector(launch_pos.x - rfactor, launch_pos.y - rfactor, launch_pos.z - rfactor));
	bounding_box_add_xyz(&launch_bbox, launch_pos.x + rfactor, launch_pos.y + rfactor, launch_pos.z + rfactor);
	
	return [self addShips: howMany withRole: desc intoBoundingBox: launch_bbox];
}


- (BOOL) addShips:(int) howMany withRole:(NSString *) desc intoBoundingBox:(BoundingBox) bbox
{
	if (howMany < 1)
		return YES;
	if (howMany > 1)
	{
		// divide the number of ships in two
		int h0 = howMany / 2;
		int h1 = howMany - h0;
		// split the bounding box into two along its longest dimension
		GLfloat lx = bbox.max.x - bbox.min.x;
		GLfloat ly = bbox.max.y - bbox.min.y;
		GLfloat lz = bbox.max.z - bbox.min.z;
		BoundingBox bbox0 = bbox;
		BoundingBox bbox1 = bbox;
		if ((lx > lz)&&(lx > ly))	// longest dimension is x
		{
			bbox0.min.x += 0.5 * lx;
			bbox1.max.x -= 0.5 * lx;
		}
		else
		{
			if (ly > lz)	// longest dimension is y
			{
				bbox0.min.y += 0.5 * ly;
				bbox1.max.y -= 0.5 * ly;
			}
			else			// longest dimension is z
			{
				bbox0.min.z += 0.5 * lz;
				bbox1.max.z -= 0.5 * lz;
			}
		}
		// place half the ships into each bounding box
		return ([self addShips: h0 withRole: desc intoBoundingBox: bbox0] && [self addShips: h1 withRole: desc intoBoundingBox: bbox1]);
	}
	
	//	randomise within the bounding box (biased towards the center of the box)
	Vector pos = make_vector(bbox.min.x, bbox.min.y, bbox.min.z);
	pos.x += 0.5 * (randf() + randf()) * (bbox.max.x - bbox.min.x);
	pos.y += 0.5 * (randf() + randf()) * (bbox.max.y - bbox.min.y);
	pos.z += 0.5 * (randf() + randf()) * (bbox.max.z - bbox.min.z);
	
	
	ShipEntity  *ship;
	ship = [self newShipWithRole:desc];   // retain count = 1
	if (ship)
	{
		if (![ship crew])
			[ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: desc
				andOriginalSystem: systems[ranrot_rand() & 255]]]];
				
		if ((ship->scanClass == CLASS_NO_DRAW)||(ship->scanClass == CLASS_NOT_SET))
			[ship setScanClass: CLASS_NEUTRAL];
		[ship setPosition: pos];
		[self addEntity:ship];
		[[ship getAI] setState:@"GLOBAL"];	// must happen after adding to the universe!
		[ship setStatus:STATUS_IN_FLIGHT];	// or ships that were 'demo' ships become invisible!
		[ship release];
		
		return YES;	// success at last!
	}
	return NO;
}


- (BOOL) spawnShip:(NSString *) shipdesc
{
	ShipEntity* ship;
	NSDictionary* shipdict = nil;
	
	shipdict = [self getDictionaryForShip:shipdesc];
	if (shipdict == nil)  return NO;
	
	ship = [self newShipWithName:shipdesc];	// retain count is 1
	
	if (ship == nil)  return NO;
	
	// set any spawning characteristics
	NSDictionary* spawndict = [shipdict objectForKey:@"spawn"];
	// position
	if ([spawndict objectForKey:@"position"])
	{
		Vector pos = kZeroVector;
		NSString* positionString = [spawndict objectForKey:@"position"];
		NSArray* positiontokens = ScanTokensFromString(positionString);
		if ([positiontokens count] == 4)
		{
			GLfloat scalar;
			pos = make_vector(	[[positiontokens objectAtIndex:1] floatValue],
								[[positiontokens objectAtIndex:2] floatValue],
								[[positiontokens objectAtIndex:3] floatValue]);
			pos = [self coordinatesForPosition:pos withCoordinateSystem:(NSString *)[positiontokens objectAtIndex:0] returningScalar:&scalar];
		}
		[ship setPosition:pos];
	}
	// facing_position
	if ([spawndict objectForKey:@"facing_position"])
	{
		Vector pos, rpos;
		Vector spos = [ship position];
		Quaternion q1;
		NSString* positionString = [spawndict objectForKey:@"facing_position"];
		NSArray* positiontokens = ScanTokensFromString(positionString);
		if ([positiontokens count] == 4)
		{
			GLfloat scalar;
			pos = make_vector(	[[positiontokens objectAtIndex:1] floatValue],
								[[positiontokens objectAtIndex:2] floatValue],
								[[positiontokens objectAtIndex:3] floatValue]);
			rpos = [self coordinatesForPosition:pos withCoordinateSystem:(NSString *)[positiontokens objectAtIndex:0] returningScalar:&scalar];
		}
		rpos.x -= spos.x;	rpos.y -= spos.y;	rpos.z -= spos.z; // position relative to ship
		if (rpos.x || rpos.y || rpos.z)
		{
			rpos = unit_vector(&rpos);
			q1 = quaternion_rotation_between(make_vector(0,0,1), rpos);
			
			GLfloat check = dot_product(vector_forward_from_quaternion(q1), rpos);
			if (check < 0)
				quaternion_rotate_about_axis(&q1, vector_right_from_quaternion(q1), M_PI);	// 180 degree flip
			
			[ship setOrientation:q1];
		}
	}

	[self addEntity:ship];
	[[ship getAI] setState:@"GLOBAL"];	// must happen after adding to the universe!
	[ship setStatus:STATUS_IN_FLIGHT];	// or ships that were 'demo' ships become invisible!
	[ship release];

	return YES;
}


- (void) witchspaceShipWithRole:(NSString *) desc
{
	// adds a ship exiting witchspace (corollary of when ships leave the system)
	ShipEntity  *ship;
	ship = [self newShipWithRole:desc];   // retain count = 1
	if (ship)
	{
		if ((ship->scanClass == CLASS_NO_DRAW)||(ship->scanClass == CLASS_NOT_SET))
			[ship setScanClass: CLASS_NEUTRAL];
		if ([desc isEqual:@"trader"])
		{
			[ship setCargoFlag: CARGO_FLAG_FULL_SCARCE];
			if (randf() > 0.10)
				[[ship getAI] setStateMachine:@"route1traderAI.plist"];
			else
				[[ship getAI] setStateMachine:@"route2sunskimAI.plist"];	// route3 really, but the AI's the same
		}
		if ([desc isEqual:@"pirate"])
		{
			[ship setCargoFlag: CARGO_FLAG_PIRATE];
			[ship setBounty: (ranrot_rand() & 7) + (ranrot_rand() & 7) + ((randf() < 0.05)? 63 : 23)];	// they already have a price on their heads
		}
		if (![ship crew])
			[ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: desc
				andOriginalSystem: systems[ranrot_rand() & 255]]]];
		
		[ship leaveWitchspace];				// gets added to the universe here!
		[[ship getAI] setState:@"GLOBAL"];	// must happen after adding to the universe!
		[ship setStatus:STATUS_IN_FLIGHT];	// or ships may not werk rite d'uh!

		[ship release];
	}
}


- (void) spawnShipWithRole:(NSString *) desc near:(Entity *) entity
{
	// adds a ship within the collision radius of the other entity
	if (!entity)
		return;
	ShipEntity  *ship;
	Vector		spawn_pos = entity->position;
	Quaternion	spawn_q;	quaternion_set_random(&spawn_q);
	Vector		vf = vector_forward_from_quaternion(spawn_q);
	GLfloat		offset = (randf() + randf()) * entity->collision_radius;
	spawn_pos.x += offset * vf.x;	spawn_pos.y += offset * vf.y;	spawn_pos.z += offset * vf.z;
	ship = [self newShipWithRole:desc];   // retain count = 1
	if (ship)
	{
		if (![ship crew])
			[ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: desc
				andOriginalSystem: systems[ranrot_rand() & 255]]]];
				
		if (ship->scanClass <= CLASS_NO_DRAW)
			[ship setScanClass: CLASS_NEUTRAL];
		[ship setPosition:spawn_pos];
		[ship setOrientation:spawn_q];
		[self addEntity:ship];
		[[ship getAI] setState:@"GLOBAL"];	// must happen after adding to the universe!
		[ship setStatus:STATUS_IN_FLIGHT];
		[ship release];
	}
}


- (void) set_up_break_pattern:(Vector) pos quaternion:(Quaternion) q
{
	int				i;
	RingEntity*		ring;
	
	[self setViewDirection:VIEW_FORWARD];
	
	q.w = -q.w;		// reverse the quaternion because this is from the player's viewpoint
	
	Vector			v = vector_forward_from_quaternion(q);
		
	for (i = 1; i < 11; i++)
	{
		ring = [[RingEntity alloc] init];
		[ring setPositionX:pos.x+v.x*i*50.0 y:pos.y+v.y*i*50.0 z:pos.z+v.z*i*50.0]; // ahead of the player
		[ring setOrientation:q];
		[ring setVelocity:v];
		[ring setLifetime:i*50.0];
		[ring setScanClass: CLASS_NO_DRAW];
		[self addEntity:ring]; // [entities addObject:ring];
		breakPatternCounter++;
		[ring release];
    }
}


- (void) game_over
{
	PlayerEntity*   player = [[PlayerEntity sharedPlayer] retain];

	
	[self removeAllEntitiesExceptPlayer:NO];	// don't want to restore afterwards
	
	[player set_up];						//reset the player
	[player setUpShipFromDictionary:[self getDictionaryForShip:[player ship_desc]]];	// ship_desc is the standard Cobra at this point
	
	[[gameView gameController] loadPlayerIfRequired];
	
	[self setGalaxy_seed: [player galaxy_seed]];
	system_seed = [self findSystemAtCoords:[player galaxy_coordinates] withGalaxySeed:galaxy_seed];
	
	
	if (![self station])
		[self setUpSpace];
	
	if (![[self station] localMarket])
		[[self station] initialiseLocalMarketWithSeed:system_seed andRandomFactor:[player random_factor]];
	
	[player setStatus:STATUS_DOCKED];
	[player setGuiToStatusScreen];
	displayGUI = YES;
	
	[player release];    
	
}


- (void) set_up_intro1
{
	PlayerEntity* player = [PlayerEntity sharedPlayer];
	ShipEntity		*ship;
	Quaternion		q2;
	q2.x = 0.0;   q2.y = 0.0;   q2.z = 0.0; q2.w = 1.0;
	quaternion_rotate_about_y(&q2,M_PI);
	
	// in status demo : draw ships and display text
	
	[player setStatus: STATUS_START_GAME];
	[player setShowDemoShips: YES];
	displayGUI = YES;
	
	/*- cobra -*/
	ship = [self newShipWithName:PLAYER_SHIP_DESC];   // retain count = 1   // shows the cobra-player ship
	if (ship)
	{
		[ship setStatus: STATUS_COCKPIT_DISPLAY];
		[ship setOrientation:q2];
		[ship setPositionX:0.0f y:0.0f z:3.6f * ship->collision_radius];	// some way ahead
		
		[ship setScanClass: CLASS_NO_DRAW];
		[ship setRoll:M_PI/5.0];
		[ship setPitch:M_PI/10.0];
		[[ship getAI] setStateMachine:@"nullAI.plist"];
		[self addEntity:ship];
		
		demo_ship = ship;
		
		[ship release];
	}
	
	[self setViewDirection:VIEW_GUI_DISPLAY];
	displayGUI = YES;
	
	
}


- (void) set_up_intro2
{
	ShipEntity		*ship;
	Quaternion		q2;
	q2.x = 0.0;   q2.y = 0.0;   q2.z = 0.0; q2.w = 1.0;
	quaternion_rotate_about_y(&q2,M_PI);
	
	// in status demo draw ships and display text
	
	[self removeDemoShips];
	[[PlayerEntity sharedPlayer] setStatus: STATUS_START_GAME];
	[[PlayerEntity sharedPlayer] setShowDemoShips: YES];
	displayGUI = YES;
	
	/*- demo ships -*/
	demo_ship_index = 0;
	ship = [self newShipWithName:[demo_ships objectAtIndex:0]];   // retain count = 1
	if (ship)
	{
		[ship setOrientation:q2];
		[ship setPositionX:0.0f y:0.0f z:3.6f * ship->collision_radius];
		[ship setDestination: ship->position];	// ideal position
		
		[ship setScanClass: CLASS_NO_DRAW];
		[ship setRoll:M_PI/5.0];
		[ship setPitch:M_PI/10.0];
		[[ship getAI] setStateMachine:@"nullAI.plist"];
		[self addEntity:ship];
		
		// set status here because addEntity may affect status
		[ship setStatus:STATUS_COCKPIT_DISPLAY];
		
		demo_ship = ship;
		
		[gui setText:[ship name] forRow:19 align:GUI_ALIGN_CENTER];
		[gui setColor:[OOColor whiteColor] forRow:19];
		
		[ship release];
	}
	
	[self setViewDirection:VIEW_GUI_DISPLAY];
	displayGUI = YES;
	
	demo_stage = DEMO_SHOW_THING;
	demo_stage_time = universal_time + 3.0;
	
}


- (void) selectIntro2Previous
{
	demo_stage = DEMO_SHOW_THING;
	demo_ship_index = (demo_ship_index + [demo_ships count] - 2) % [demo_ships count];
	demo_stage_time  = universal_time - 1.0;	// force change
}


- (void) selectIntro2Next
{
	demo_stage = DEMO_SHOW_THING;
	demo_stage_time  = universal_time - 1.0;	// force change
}


- (StationEntity *) station
{
	if (cachedStation)
		return cachedStation;
	
	if (![self entityForUniversalID:station])
	{
		int i;
		station = NO_TARGET;
		cachedStation = nil;
		int ent_count = n_entities;
		int station_count = 0;
		Entity* my_entities[ent_count];
		for (i = 0; i < ent_count; i++)
			if (sortedEntities[i]->isStation)
				my_entities[station_count++] = [sortedEntities[i] retain];
		for (i = 0; ((i < station_count)&&(station == NO_TARGET)) ; i++)
		{
			Entity* thing = my_entities[i];
			if (thing->scanClass == CLASS_STATION)
			{
				cachedStation = (StationEntity *)thing;
				station = [thing universalID];
			}
		}
		for (i = 0; i < station_count; i++)
			[my_entities[i] release];
	}
	
	return cachedStation;
}


- (PlanetEntity *) planet
{
	if (cachedPlanet)
		return cachedPlanet;
	
	if (![self entityForUniversalID:planet])
	{
		int i;
		planet = NO_TARGET;
		cachedPlanet = nil;
		int ent_count = n_entities;
		int planet_count = 0;
		Entity* my_entities[ent_count];
		for (i = 0; i < ent_count; i++)
			if (sortedEntities[i]->isPlanet)
				my_entities[planet_count++] = [sortedEntities[i] retain];
		for (i = 0; ((i < planet_count)&&(planet == NO_TARGET)) ; i++)
		{
			PlanetEntity* thing = (PlanetEntity *)my_entities[i];
			if ([thing getPlanetType] == PLANET_TYPE_GREEN)
			{
				cachedPlanet = thing;
				planet = [cachedPlanet universalID];
			}
		}
		for (i = 0; i < planet_count; i++)
			[my_entities[i] release];
	}
	return cachedPlanet;
}


- (PlanetEntity *) sun
{
	if (cachedSun)
		return cachedSun;
	
	if (![self entityForUniversalID:sun])
	{
		int i;
		sun = NO_TARGET;
		cachedSun = nil;
		int ent_count = n_entities;
		int planet_count = 0;
		Entity* my_entities[ent_count];
		for (i = 0; i < ent_count; i++)
			if (sortedEntities[i]->isPlanet)
				my_entities[planet_count++] = [sortedEntities[i] retain];
		for (i = 0; ((i < planet_count)&&(sun == NO_TARGET)) ; i++)
		{
			PlanetEntity* thing = (PlanetEntity *)my_entities[i];
			if ([thing getPlanetType] == PLANET_TYPE_SUN)
			{
				cachedSun = (PlanetEntity*)thing;
				sun = [cachedSun universalID];
			}
		}
		for (i = 0; i < planet_count; i++)
			[my_entities[i] release];
	}
	return cachedSun;
}


- (void) resetBeacons
{
	ShipEntity* beaconShip = [self firstBeacon];
	while (beaconShip)
	{
		firstBeacon = [beaconShip nextBeaconID];
		[beaconShip setNextBeacon:nil];
		beaconShip = (ShipEntity *)[self entityForUniversalID:firstBeacon];
	}
	firstBeacon = NO_TARGET;
	lastBeacon = NO_TARGET;
}


- (ShipEntity *) firstBeacon
{
	return (ShipEntity *)[self entityForUniversalID:firstBeacon];
}


- (ShipEntity *) lastBeacon
{
	return (ShipEntity *)[self entityForUniversalID:lastBeacon];
}


- (void) setNextBeacon:(ShipEntity *) beaconShip
{
	if ([beaconShip isBeacon])
	{
		[beaconShip setNextBeacon:nil];
		if ([self lastBeacon])
			[[self lastBeacon] setNextBeacon:beaconShip];
		lastBeacon = [beaconShip universalID];
		if (![self firstBeacon])
			firstBeacon = lastBeacon;
	}
	else
	{
		OOLog(@"universe.beacon.error", @"INTERNAL ERROR! Universe setNextBeacon:%@ where the ship has no beaconChar set", beaconShip);
	}
}


- (GLfloat *) sky_clear_color
{
	return sky_clear_color;
}


- (void) setSky_clear_color:(GLfloat) red :(GLfloat) green :(GLfloat) blue :(GLfloat) alpha
{
	sky_clear_color[0] = red;
	sky_clear_color[1] = green;
	sky_clear_color[2] = blue;
	sky_clear_color[3] = alpha;
	air_resist_factor = alpha;
}  


- (BOOL) breakPatternOver
{
	return (breakPatternCounter == 0);
}


- (BOOL) breakPatternHide
{
	Entity* player = [PlayerEntity sharedPlayer];
	return ((breakPatternCounter > 5)||(!player)||(player->status == STATUS_DOCKING));
}


- (ShipEntity *) newShipWithRole:(NSString *) desc
{
	unsigned				i, j, found = 0;
	ShipEntity				*ship = nil;
	NSString				*search = nil;
	NSAutoreleasePool		*pool = nil;
	NSEnumerator			*shipEnum = nil;
	NSString				*shipKey = nil;
	NSMutableArray			*foundShips = nil;
	NSMutableArray			*foundChance = nil;
	float					foundf = 0.0, selectedf;
	
	pool = [[NSAutoreleasePool alloc] init];
	
	search = [ScanTokensFromString(desc) componentsJoinedByString:@"_"];
	foundShips = [NSMutableArray array];
	foundChance = [NSMutableArray array];
	
	/*	FIXME: this sucks.
		Checking conditions if there's no role match seems pointless, for one.
		Also, the search is silly. We ought to have a dictionary of roles to
		sets of ship definitions. Ship definitions should be a class, not just
		raw dictionaries. And roles within each ship definition/ship class
		should be something better than a string, too.
		-- Ahruman
	*/
	
	for (shipEnum = [shipdata keyEnumerator]; (shipKey = [shipEnum nextObject]); )
	{
		NSDictionary*	shipDict = [shipdata objectForKey:shipKey];
		NSArray*		shipRoles = ScanTokensFromString([shipDict objectForKey:@"roles"]);
		
		if ([shipDict objectForKey:@"conditions"])
		{
			PlayerEntity* player = [PlayerEntity sharedPlayer];
			if ((player) && (player->isPlayer) && (![player checkCouplet: shipDict onEntity: player]))
				shipRoles = [NSArray array];	// empty array - ship does not meet conditions listed
		}
		
		for (j = 0; j < [shipRoles count]; j++)
		{
			NSString* putative_roles = [shipRoles objectAtIndex:j];
			
			GLfloat chance = 1.0;
			if (putative_roles)
			{
				if ([putative_roles hasPrefix:search] && ([putative_roles rangeOfString:@"("].location != NSNotFound))
				{
					NSScanner* scanner = [NSScanner scannerWithString:putative_roles];	// scanner
					NSString* scanrole;
					[scanner scanUpToString:@"(" intoString:&scanrole];					// look for '('
					[scanner scanString:@"(" intoString:(NSString**)nil];				// skip over it
					if (![scanner scanFloat:&chance])	chance = 1.0;					// try to scan a float
					putative_roles = [NSString stringWithString:scanrole];				// ignore from '(' onwards (lazy)
					
				}
		
				if ([putative_roles isEqual:search] && (chance > 0.0))
				{
					[foundShips addObject:shipKey];
					[foundChance addObject:[NSNumber numberWithFloat:chance]];
					found++;
					foundf += chance;
				}
			}
		}
	}

	i = 0;
	
	if (found > 1)
	{
		selectedf = randf() * foundf;
		while (selectedf > [[foundChance objectAtIndex:i] floatValue])
		{
			selectedf -= [[foundChance objectAtIndex:i] floatValue];
			i++;
		}
		
		if (i >= found)	// sanity check
			i = 0;
		
	}
	
	if (found)
	{
		ship = [self newShipWithName:(NSString *)[foundShips objectAtIndex:i]];	// may return nil if not found!
		[ship setRoles:search];											// set its roles to this one particular chosen role
	}
	else
	{
		/*	Note: this is a common "error", since the game will look for
			special containers by looking up a ship using the commodity name
			as a ship role.
		*/
#ifndef NDEBUG
		if (gDebugFlags & DEBUG_MISC)
		{
			OOLog(@"universe.newShip.unknownRole", @"DEBUG [Universe newShipWithRole: %@] couldn't find a ship!", search);
		}
#endif
	}
	
	[pool release];	// tidy everything up
	
	// check a trader has fuel
	if ([ship fuel] == 0 &&([[ship roles] rangeOfString:@"trader"].location != NSNotFound))
	{
		[ship setFuel: PLAYER_MAX_FUEL];
	}
	
	return ship;
}


- (ShipEntity *) newShipWithName:(NSString *) desc
{
	NSDictionary	*shipDict = nil;
	ShipEntity		*ship = nil;

	shipDict = [self getDictionaryForShip:desc];

	if (shipDict == nil)  return nil;

	BOOL		isStation = NO;
	NSString	*shipRoles = [shipDict objectForKey:@"roles"];
	if (shipRoles)  isStation = ([shipRoles rangeOfString:@"station"].location != NSNotFound)||([shipRoles rangeOfString:@"carrier"].location != NSNotFound);
	if (!isStation)  isStation = [shipDict boolForKey:@"isCarrier" defaultValue:NO];
	
	volatile Class shipClass;
	if (!isStation)  shipClass = [ShipEntity class];
	else  shipClass = [StationEntity class];
	
	NS_DURING
		ship =[[shipClass alloc] initWithDictionary:shipDict];
	NS_HANDLER
		[ship release];
		ship = nil;
		
		if ([[localException name] isEqual:OOLITE_EXCEPTION_DATA_NOT_FOUND])
		{
			OOLog(kOOLogException, @"***** Oolite Exception : '%@' in [Universe newShipWithName: %@ ] *****", [localException reason], desc);
		}
		else  [localException raise];
	NS_ENDHANDLER

	return ship;   // retain count = 1
}


- (NSDictionary *)getDictionaryForShip:(NSString *)desc
{
	static NSDictionary		*cachedResult = nil;
	static NSString			*cachedKey = nil;
	
	if (desc == nil)  return nil;
	if ([desc isEqualToString:cachedKey])  return [[cachedResult retain] autorelease];
	
	NSMutableDictionary *shipdict = [[[shipdata objectForKey:desc] mutableCopy] autorelease];
	if (shipdict == nil)
	{
		/*	There used to be an attempt to throw a OOLITE_EXCEPTION_SHIP_NOT_FOUND
			exception here. However, it never worked -- the line above was
			broken so an empty dictionary was created instead, which was
			rather pointless. Once this was fixed, it turned out there are OXPs
			causing bad ships to be created, which wasn't noticed because the
			exception wasn't handled.
			-- Ahruman
		*/	 
		return nil;
	}
	// check if this is based upon a different ship
	// TODO: move all like_ship handling into one place. (Actually, it may be that this already _is_ that place and all others are redundant.) Should probably fold resolved like_ships back into dictionary. -- Ahruman
	while ([shipdict objectForKey:@"like_ship"])
	{
		NSString*		other_shipdesc = (NSString *)[shipdict objectForKey:@"like_ship"];
		NSDictionary*	other_shipdict = nil;
		
		if (other_shipdesc != nil)
		{
			other_shipdict = [self getDictionaryForShip:other_shipdesc];
		}
		if (other_shipdict != nil)
		{
			[shipdict removeObjectForKey:@"like_ship"];	// so it may inherit a new one from the like_ship
			NSMutableDictionary* this_shipdict = [NSMutableDictionary dictionaryWithDictionary:other_shipdict]; // basics from that one
			[this_shipdict addEntriesFromDictionary:shipdict];	// overrides from this one
			shipdict = [NSMutableDictionary dictionaryWithDictionary:this_shipdict];	// synthesis'
		}
	}
	
	[cachedResult release];
	cachedResult = [shipdict copy];
	[cachedKey release];
	cachedKey = [desc copy];
	
	return shipdict;
}


- (OOCargoQuantity) maxCargoForShip:(NSString *) desc
{
	NSDictionary			*dict = nil;
	
	dict = [self getDictionaryForShip:desc];
	
	if (dict)
	{
		return [dict unsignedIntForKey:@"max_cargo" defaultValue:0];
	}
	else  return 0;
}


- (OOCreditsQuantity) getPriceForWeaponSystemWithKey:(NSString *)weapon_key
{
	unsigned				i, count;
	NSArray					*itemData = nil;
	NSString				*itemType = nil;
	
	count = [equipmentdata count];
	for (i = 0; i < count; i++)
	{
		itemData = [equipmentdata arrayAtIndex:i];
		itemType = [itemData stringAtIndex:EQUIPMENT_KEY_INDEX];
		
		if ([itemType isEqual:weapon_key])
		{
			return [itemData intAtIndex:EQUIPMENT_PRICE_INDEX];
		}
	}
	return 0;
}


- (int) legal_status_of_manifest:(NSArray *)manifest
{
	unsigned				i, count;
	unsigned				penalty = 0;
	NSString				*commodity = nil;
	OOCargoQuantity			amount;
	NSArray					*entry = nil;
	unsigned				penaltyPerUnit;
	
	count = [manifest count];
	for (i = 0; i < count; i++)
	{
		entry = [manifest arrayAtIndex:i];
		commodity = [entry stringAtIndex:MARKET_NAME];
		amount = [entry unsignedIntAtIndex:MARKET_QUANTITY];
		
		penaltyPerUnit = [illegal_goods unsignedIntForKey:commodity defaultValue:0];
		penalty += amount * penaltyPerUnit;
	}
	return penalty;
}


- (NSArray *) getContainersOfPlentifulGoods:(OOCargoQuantity) how_many
{
	// build list of goods allocating 0..100 for each based on how
	// much of each quantity there is. Use a ratio of n x 100/64
	NSMutableArray  *accumulator = [NSMutableArray arrayWithCapacity:how_many];
	int quantities[[commoditydata count]];
	int total_quantity = 0;
	unsigned i;
	for (i = 0; i < [commoditydata count]; i++)
	{
		int q = [(NSNumber *)[(NSArray *)[commoditydata objectAtIndex:i] objectAtIndex:MARKET_QUANTITY] intValue];
		if (q < 0)  q = 0;
		if (q > 64) q = 64;
		q *= 100;   q/= 64;
		quantities[i] = q;
		total_quantity += q;
	}
	// quantities is now used to determine which good get into the containers
	for (i = 0; i < how_many; i++)
	{
		ShipEntity* container = [self newShipWithRole:@"cargopod"];	// retained
		
		// look for a pre-set filling
		int co_type = [container getCommodityType];
		int co_amount = [container getCommodityAmount];
		
		int qr;
		// select a random point in the histogram
		#if __POWERPC__ || defined(NO_DIV_ZERO_EXCEPTION)
			qr = ranrot_rand() % total_quantity;
		#else
			if (0 != total_quantity) qr = ranrot_rand() % total_quantity;
			else qr = 0;
		#endif
		
		if ((co_type == NSNotFound)||(co_amount == 0))
		{
			// choose a random filling
			// select a random point in the histogram
			int qr = ranrot_rand() % total_quantity;
			co_type = 0;
			while (qr > 0)
			{
				qr -= quantities[co_type++];
			}
			co_type--;
			
			co_amount = [self getRandomAmountOfCommodity:co_type];
			
			ShipEntity* special_container = [self newShipWithRole: [self nameForCommodity:co_type]];
			if (special_container)
			{
				[container release];
				container = special_container;
			}
		}
		
		// into the barrel it goes...
		if (container != nil)
		{
			[container setScanClass: CLASS_CARGO];
			[container setCommodity:co_type andAmount:co_amount];
			[accumulator addObject:container];
			[container release];	// released
		}
	}
	return [NSArray arrayWithArray:accumulator];	
}


- (NSArray *) getContainersOfScarceGoods:(OOCargoQuantity) how_many
{
	// build list of goods allocating 0..100 for each based on how
	// much of each quantity there is. Use a ratio of (64 - n) x 100/64
	NSMutableArray  *accumulator = [NSMutableArray arrayWithCapacity:how_many];
	int quantities[[commoditydata count]];
	int total_quantity = 0;
	unsigned i;
	for (i = 0; i < [commoditydata count]; i++)
	{
		int q = 64 - [(NSNumber *)[(NSArray *)[commoditydata objectAtIndex:i] objectAtIndex:MARKET_QUANTITY] intValue];
		if (q < 0)  q = 0;
		if (q > 64) q = 64;
		q *= 100;   q/= 64;
		quantities[i] = q;
		total_quantity += q;
	}
	// quantities is now used to determine which good get into the containers
	for (i = 0; i < how_many; i++)
	{
		ShipEntity* container = [self newShipWithRole:@"cargopod"];
		
		// look for a pre-set filling
		int co_type = [container getCommodityType];
		int co_amount = [container getCommodityAmount];
		
		if ((co_type == NSNotFound)||(co_amount == 0))
		{
			// choose a random filling
			// select a random point in the histogram
			int qr = ranrot_rand() % total_quantity;
			co_type = 0;
			while (qr > 0)
			{
				qr -= quantities[co_type++];
			}
			co_type--;
			
			co_amount = [self getRandomAmountOfCommodity:co_type];
			
			ShipEntity* special_container = [self newShipWithRole: [self nameForCommodity:co_type]];
			if (special_container)
			{
				[container release];
				container = special_container;
			}
		}
		
		if (container)
		{
			[container setScanClass: CLASS_CARGO];
			[container setCommodity:co_type andAmount:co_amount];
			[accumulator addObject:container];
			[container release];
		}
	}
	return [NSArray arrayWithArray:accumulator];	
}


- (NSArray *) getContainersOfDrugs:(OOCargoQuantity) how_many
{
	return [self getContainersOfCommodity:@"Narcotics" :how_many];	
}


- (NSArray *) getContainersOfCommodity:(NSString*) commodity_name :(OOCargoQuantity) how_many
{
	NSMutableArray  *accumulator = [NSMutableArray arrayWithCapacity:how_many];
	int commodity_type = [self commodityForName: commodity_name];
	if (commodity_type == NSNotFound)
		return [NSArray array]; // empty array
	int commodity_units = [self unitsForCommodity:commodity_type];
	int how_much = how_many;
	while (how_much > 0)
	{
		ShipEntity* container = [self newShipWithRole: commodity_name];	// try the commodity name first
		if (!container)
			container = [self newShipWithRole:@"cargopod"];
		int amount = 1;
		if (commodity_units != 0)
			amount += ranrot_rand() & (15 * commodity_units);
		if (amount > how_much)
			amount = how_much;
		// into the barrel it goes...
		if (container)
		{
			[container setScanClass: CLASS_CARGO];
			[container setCommodity:commodity_type andAmount:amount];
			[accumulator addObject:container];
			[container release];
		}
		else
		{
			OOLog(@"universe.createContainer.failed", @"***** ERROR failed to find a container to fill with %@ *****", commodity_name);
		}
		how_much -= amount;
	}
	return [NSArray arrayWithArray:accumulator];	
}


- (OOCargoType) getRandomCommodity
{
	int cd = ranrot_rand() % [commoditydata count];
	return cd;
}


- (OOCargoQuantity) getRandomAmountOfCommodity:(OOCargoType) co_type
{
	OOMassUnit		units;
	unsigned		commidityIndex = (unsigned)co_type;
	
	if (co_type < 0 || [commoditydata count] <= commidityIndex)  return 0;
	
	units = [[commoditydata arrayAtIndex:commidityIndex] intAtIndex:MARKET_UNITS];
	switch (units)
	{
		case 0 :	// TONNES
			return 1;
			break;
		case 1 :	// KILOGRAMS
			return 1 + (ranrot_rand() % 6) + (ranrot_rand() % 6) + (ranrot_rand() % 6);
			break;
		case 2 :	// GRAMS
			return 4 + 3 * (ranrot_rand() % 6) + 2 * (ranrot_rand() % 6) + (ranrot_rand() % 6);
			break;
	}
	return 1;
}


- (NSArray *)commidityDataForType:(OOCargoType)type
{
	if (type < 0 || [commoditydata count] <= (unsigned)type)  return nil;
	
	return [commoditydata objectAtIndex:type];
}


- (OOCargoType) commodityForName:(NSString *) co_name
{
	unsigned		i, count;
	NSString		*capName = [co_name capitalizedString];
	
	count = [commoditydata count];
	for (i = 0; i < count; i++)
	{
		if ([capName isEqual:[commoditydata objectAtIndex:MARKET_NAME]])
			return i;
	}
	return NSNotFound;
}


- (NSString *) nameForCommodity:(OOCargoType) co_type
{
	NSArray			*commodity = [self commidityDataForType:co_type];
	
	if (commodity == nil)  return @"";
	
	return [NSString stringWithFormat:@"%@",[commoditydata objectAtIndex:MARKET_NAME]];
}


- (OOMassUnit) unitsForCommodity:(OOCargoType)co_type
{
	NSArray			*commodity = [self commidityDataForType:co_type];
	
	if (commodity == nil)  return NSNotFound;
	
	return [[commodity objectAtIndex:MARKET_UNITS] intValue];
}



- (NSString *) describeCommodity:(OOCargoType) co_type amount:(OOCargoQuantity) co_amount
{
	int				units;
	NSString		*unitDesc = nil, *typeDesc = nil;
	NSArray			*commodity = [self commidityDataForType:co_type];
	
	if (commodity == nil) return @"";
	
	units = [commodity intAtIndex:MARKET_UNITS];
	switch (units)
	{
		case UNITS_KILOGRAMS :	// KILOGRAMS
			unitDesc = @"kilogram";
			break;
		case UNITS_GRAMS :	// GRAMS
			unitDesc = @"gram";
			break;
		case UNITS_TONS :	// TONNES
		default :
			unitDesc = @"ton";
			break;
	}
	if (co_amount != 1)  unitDesc = [unitDesc stringByAppendingString:@"s"];
	
	typeDesc = [commodity objectAtIndex:MARKET_NAME];
	
	return [NSString stringWithFormat:@"%d %@ %@",co_amount, unitDesc, typeDesc];
}

////////////////////////////////////////////////////

- (void) setGameView:(MyOpenGLView *)view
{
    [gameView release];
    gameView = view;
    [gameView retain];
}


- (MyOpenGLView *) gameView
{
    return gameView;
}


- (GameController *) gameController
{
	return [gameView gameController];
}


void	setSunLight(BOOL yesno)
{
	if (yesno != sun_light_on)
	{
		if (yesno)
			glEnable(GL_LIGHT1);
		else
			glDisable(GL_LIGHT1);
		sun_light_on = yesno;
	}
}
void	setDemoLight(BOOL yesno, Vector position)
{
	if (yesno != demo_light_on)
	{
		if ((demo_light_position[0] != position.x)||(demo_light_position[1] != position.y)||(demo_light_position[2] != position.z))
		{
			demo_light_position[0] = position.x;
			demo_light_position[1] = position.y;
			demo_light_position[2] = position.z;
			glLightfv(GL_LIGHT0, GL_POSITION, demo_light_position);
		}
		if (yesno)
			glEnable(GL_LIGHT0);
		else
			glDisable(GL_LIGHT0);
		demo_light_on = yesno;
	}
}


// global rotation matrix definitions
GLfloat	fwd_matrix[] = {		1.0f, 0.0f, 0.0f, 0.0f,		0.0f, 1.0f, 0.0f, 0.0f,		0.0f, 0.0f, 1.0f, 0.0f,		0.0f, 0.0f, 0.0f, 1.0f};
GLfloat	aft_matrix[] = {		-1.0f, 0.0f, 0.0f, 0.0f,	0.0f, 1.0f, 0.0f, 0.0f,		0.0f, 0.0f, -1.0f, 0.0f,	0.0f, 0.0f, 0.0f, 1.0f};
GLfloat	port_matrix[] = {		0.0f, 0.0f, -1.0f, 0.0f,	0.0f, 1.0f, 0.0f, 0.0f,		1.0f, 0.0f, 0.0f, 0.0f,		0.0f, 0.0f, 0.0f, 1.0f};
GLfloat	starboard_matrix[] = {	0.0f, 0.0f, 1.0f, 0.0f,		0.0f, 1.0f, 0.0f, 0.0f,		-1.0f, 0.0f, 0.0f, 0.0f,	0.0f, 0.0f, 0.0f, 1.0f};
GLfloat* custom_matrix;

- (void) drawFromEntity:(OOUniversalID) n
{
	if (!no_update)
	{
		NS_DURING
			
			no_update = YES;	// block other attempts to draw
			
			int i, v_status;
			Vector	position, obj_position, view_dir, view_up;
			BOOL inGUIMode = NO;
			
			
			// use a non-mutable copy so this can't be changed under us.
			
			int			ent_count =	n_entities;
			Entity*		my_entities[ent_count];
			int			draw_count = 0;
			for (i = 0; i < ent_count; i++)
			{
				// we check to see that we draw only the things that need to be drawn!
				Entity* e = sortedEntities[i]; // ordered NEAREST -> FURTHEST AWAY
				double	zd2 = e->zero_distance;
				if ((e->isSky)||(e->isPlanet))
				{
					my_entities[draw_count++] = [e retain];	// planets and sky are always drawn!
					continue;
				}
				if ((zd2 > ABSOLUTE_NO_DRAW_DISTANCE2)||((e->isShip)&&(zd2 > e->no_draw_distance)))
					continue;
				// it passed all drawing tests - and it's not a planet or the sky - we can add it to the list
				my_entities[draw_count++] = [e retain];		//	retained
			}
			
			Entity	*viewthing = nil;
			Entity	*drawthing = nil;
			
			position.x = 0.0;	position.y = 0.0;	position.z = 0.0;

			if (n < n_entities)
			{
				viewthing = [entities objectAtIndex:n];
			}
			
			if ((viewthing)&&(viewthing->isPlayer))
			{
				inGUIMode = [(PlayerEntity*)viewthing showDemoShips];
				custom_matrix = [(PlayerEntity*)viewthing customViewMatrix];
				/* -- */
			}
			else
			{
				OOLog(kOOLogInconsistentState, @"***** Universe trying to draw from the view of an entity NOT the player");
				// throw an exception here...
				[NSException raise:@"OoliteException"
							format:@"Universe cannot draw from a non-player entity."];
			}
						
			position = [viewthing viewpointPosition];
			v_status = viewthing->status;
			
			GLfloat* view_matrix = fwd_matrix;
			switch (viewDirection)
			{
				case VIEW_FORWARD:
					view_matrix = fwd_matrix; break;
				case VIEW_AFT:
					view_matrix = aft_matrix; break;
				case VIEW_PORT:
					view_matrix = port_matrix; break;
				case VIEW_STARBOARD:
					view_matrix = starboard_matrix; break;
				/* GILES custom view points */
				case VIEW_CUSTOM:
					view_matrix = custom_matrix;
				/* -- */
			}
			
			CheckOpenGLErrors(@"Universe before doing anything");
			
			glEnable(GL_LIGHTING);
			glEnable(GL_DEPTH_TEST);
			glEnable(GL_CULL_FACE);			// face culling
			glDepthMask(GL_TRUE);	// restore write to depth buffer

			if (!displayGUI)
				glClearColor(sky_clear_color[0], sky_clear_color[1], sky_clear_color[2], sky_clear_color[3]);
			else
				glClearColor(0.0, 0.0, 0.0, 0.0);

			glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
			glLoadIdentity();	// reset matrix                         

			gluLookAt(0.0, 0.0, 0.0,	0.0, 0.0, 1.0,	0.0, 1.0, 0.0);

			// HACK BUSTED
			glScalef(  -1.0,  1.0,	1.0);   // flip left and right

			gl_matrix saved_flat_matrix;
			glGetFloatv(GL_MODELVIEW_MATRIX, saved_flat_matrix);
			glPushMatrix(); // save this flat viewpoint

			view_up.x = 0.0;	view_up.y = 1.0;	view_up.z = 0.0;
			switch (viewDirection)
			{
				default:
				case VIEW_FORWARD :
					view_dir.x = 0.0;   view_dir.y = 0.0;   view_dir.z = 1.0;
					break;
				case VIEW_AFT :
					view_dir.x = 0.0;   view_dir.y = 0.0;   view_dir.z = -1.0;
					break;
				case VIEW_PORT :
					view_dir.x = -1.0;   view_dir.y = 0.0;   view_dir.z = 0.0;
					break;
				case VIEW_STARBOARD :
					view_dir.x = 1.0;   view_dir.y = 0.0;   view_dir.z = 0.0;
					break;
				case VIEW_CUSTOM :
					view_dir = [(PlayerEntity*)viewthing customViewForwardVector];
					view_up = [(PlayerEntity*)viewthing customViewUpVector];
					break;
			}

			gluLookAt(view_dir.x, view_dir.y, view_dir.z, 0.0, 0.0, 0.0, view_up.x, view_up.y, view_up.z);

			if ((!displayGUI) || (inGUIMode))
			{
				// set up the light for demo ships
				Vector demo_light_origin = DEMO_LIGHT_POSITION;
				
				////
				
				if (!inGUIMode)
				{
					// rotate the view
					glMultMatrixf([viewthing rotationMatrix]);
					// translate the view
					glTranslatef(-position.x, -position.y, -position.z);
				}
				
				////
				
				// position the sun and docked lights correctly
				glLightfv(GL_LIGHT1, GL_POSITION, sun_center_position);	// this is necessary or the sun will move with the player
				
				if (inGUIMode)
				{
					// light for demo ships display.. 
					glLightfv(GL_LIGHT0, GL_AMBIENT, docked_light_ambient);
					glLightfv(GL_LIGHT0, GL_DIFFUSE, docked_light_diffuse);
					glLightfv(GL_LIGHT0, GL_SPECULAR, docked_light_specular);
					
					demo_light_on = NO;	// be contrary - force enabling of the light
					setDemoLight(YES, demo_light_origin);
					sun_light_on = YES;	// be contrary - force disabling of the light
					setSunLight(NO);
					glLightModelfv(GL_LIGHT_MODEL_AMBIENT, docked_light_ambient);
				}
				else
				{
					demo_light_on = YES;	// be contrary - force disabling of the light
					setDemoLight(NO, demo_light_origin);
					sun_light_on = NO;	// be contrary - force enabling of the light
					setSunLight(YES);
					glLightModelfv(GL_LIGHT_MODEL_AMBIENT, stars_ambient);
				}
				
				// turn on lighting
				glEnable(GL_LIGHTING);
				
				int		furthest = draw_count - 1;
				int		nearest = 0;
				BOOL	bpHide = [self breakPatternHide];
				
				//		DRAW ALL THE OPAQUE ENTITIES
				
				for (i = furthest; i >= nearest; i--)
				{
					int d_status;
					drawthing = my_entities[i];
					d_status = drawthing->status;
					
					if (bpHide && !drawthing->isImmuneToBreakPatternHide)  continue;
					
					GLfloat flat_ambdiff[4]	= {1.0, 1.0, 1.0, 1.0};   // for alpha
					GLfloat mat_no[4]		= {0.0, 0.0, 0.0, 1.0};   // nothing
					
					if (((d_status == STATUS_COCKPIT_DISPLAY)&&(inGUIMode)) || ((d_status != STATUS_COCKPIT_DISPLAY)&&(!inGUIMode)))
					{
						// reset material properties
						glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, flat_ambdiff);
						glMaterialfv(GL_FRONT_AND_BACK, GL_EMISSION, mat_no);

						// atmospheric fog
						BOOL fogging = ((air_resist_factor > 0.01)&&(!drawthing->isPlanet));
						
						glPushMatrix();
						obj_position = drawthing->position;
						if (drawthing != viewthing)
						{
							//translate the object
							glTranslatef(obj_position.x,obj_position.y,obj_position.z);
							//rotate the object
							glMultMatrixf([drawthing drawRotationMatrix]);
						}
						else
						{
							Vector viewOffset = [viewthing viewpointOffset];
							// get saved viewpoint
							glLoadMatrixf(saved_flat_matrix);
							// rotate according to view direction
							glMultMatrixf(view_matrix);
							//translate the object  from the viewpoint
							glTranslatef(-viewOffset.x, -viewOffset.y, -viewOffset.z);
							
						}

						// atmospheric fog
						if (fogging)
						{
							double fog_scale = 0.50 * BILLBOARD_DEPTH / air_resist_factor;
							double half_scale = fog_scale * 0.50;
							glEnable(GL_FOG);
							glFogi(GL_FOG_MODE, GL_LINEAR);
							glFogfv(GL_FOG_COLOR, sky_clear_color);
							glHint(GL_FOG_HINT, GL_NICEST);
							glFogf(GL_FOG_START, half_scale);
							glFogf(GL_FOG_END, fog_scale);
						}
						
						// lighting
						if (inGUIMode)
						{
							setDemoLight(YES, demo_light_origin);
							setSunLight(NO);
						}
						else
						{
							setSunLight(drawthing->isSunlit);
							setDemoLight(NO, demo_light_origin);
						}
	
						// draw the thing
						
						[drawthing drawEntity:NO:NO];
						
						// atmospheric fog
						if (fogging)
							glDisable(GL_FOG);
						
						glPopMatrix();
						
					}
				}
				
				
				//		DRAW ALL THE TRANSLUCENT entsInDrawOrder
				
				glDepthMask(GL_FALSE);				// don't write to depth buffer
				glDisable(GL_LIGHTING);
				
				for (i = furthest; i >= nearest; i--)
				{
					int d_status;
					drawthing = my_entities[i];
					d_status = drawthing->status;
					
					if (bpHide && !drawthing->isImmuneToBreakPatternHide)  continue;
					
					if (((d_status == STATUS_COCKPIT_DISPLAY)&&(inGUIMode)) || ((d_status != STATUS_COCKPIT_DISPLAY)&&(!inGUIMode)))
					{
						// experimental - atmospheric fog
						BOOL fogging = (air_resist_factor > 0.01);
						
						glPushMatrix();
						obj_position = drawthing->position;
						if (drawthing != viewthing)
						{
							//translate the object
							glTranslatef(obj_position.x,obj_position.y,obj_position.z);
							//rotate the object
							glMultMatrixf([drawthing drawRotationMatrix]);
						}
						else
						{
							Vector viewOffset = [viewthing viewpointOffset];
							// get saved viewpoint
							glLoadMatrixf(saved_flat_matrix);
							// rotate according to view direction
							glMultMatrixf(view_matrix);
							//translate the object  from the viewpoint
							glTranslatef(-viewOffset.x, -viewOffset.y, -viewOffset.z);
						}
						
						// atmospheric fog
						if (fogging)
						{
							double fog_scale = 0.50 * BILLBOARD_DEPTH / air_resist_factor;
							double half_scale = fog_scale * 0.50;
							glEnable(GL_FOG);
							glFogi(GL_FOG_MODE, GL_LINEAR);
							glFogfv(GL_FOG_COLOR, sky_clear_color);
							glHint(GL_FOG_HINT, GL_NICEST);
							glFogf(GL_FOG_START, half_scale);
							glFogf(GL_FOG_END, fog_scale);
						}
						
						// draw the thing
						[drawthing drawEntity:NO:YES];
						
						// atmospheric fog
						if (fogging)
							glDisable(GL_FOG);
						
						glPopMatrix();
					}
				}
								
				glDepthMask(GL_TRUE);	// restore write to depth buffer
			}
			
			glPopMatrix(); //restore saved flat viewpoint

			glDisable(GL_LIGHTING);				// disable lighting
			glDisable(GL_DEPTH_TEST);			// disable depth test
			glDisable(GL_CULL_FACE);			// face culling
			glDepthMask(GL_FALSE);				// don't write to depth buffer

			GLfloat	line_width = [gameView viewSize].width / 1024.0; // restore line size
			if (line_width < 1.0)  line_width = 1.0;
			glLineWidth(line_width);

			[self drawMessage];

			if ((v_status != STATUS_DEAD)&&(v_status != STATUS_ESCAPE_SEQUENCE))
			{
				if (!displayGUI)
					[self drawCrosshairs];
				if ((viewthing->isPlayer)&&([(PlayerEntity *)viewthing hud]))
				{
					HeadUpDisplay *the_hud = [(PlayerEntity *)viewthing hud];
					[the_hud setLine_width:line_width];
					[the_hud drawLegends];
					[the_hud drawDials];
				}
			}
			
			glFlush();	// don't wait around for drawing to complete
			
			// clear errors - and announce them
			CheckOpenGLErrors(@"Universe after all entity drawing is done.");
			
			for (i = 0; i < draw_count; i++)
				[my_entities[i] release];		//	released
			
			no_update = NO;	// allow other attempts to draw
			
		NS_HANDLER
		
			if ([[localException name] hasPrefix:@"Oolite"])
				[self handleOoliteException:localException];
			else
			{
				OOLog(kOOLogException, @"***** Exception: %@ : %@ *****",[localException name], [localException reason]);
				[localException raise];
			}
		
		NS_ENDHANDLER
	}
}


- (void) drawCrosshairs
{
    PlayerEntity*   playerShip = [PlayerEntity sharedPlayer];

	if (viewDirection == VIEW_CUSTOM)	return;	// don't try to draw cross hairs in a custom view

	int	weapon	= [playerShip weaponForView:viewDirection];
	if ((playerShip)&&((playerShip->status == STATUS_IN_FLIGHT)||(playerShip->status == STATUS_WITCHSPACE_COUNTDOWN)))
	{	
		GLfloat k0 = CROSSHAIR_SIZE;
		GLfloat k1 = CROSSHAIR_SIZE / 2.0;
		GLfloat k2 = CROSSHAIR_SIZE / 4.0;
		GLfloat k3 = 3.0 * CROSSHAIR_SIZE / 4.0;
		GLfloat z1 = [gameView display_z];
		GLfloat cx_col0[4] = { 0.0, 1.0, 0.0, 0.25};
		GLfloat cx_col1[4] = { 0.0, 1.0, 0.0, 0.50};
		GLfloat cx_col2[4] = { 0.0, 1.0, 0.0, 0.75};
		glDisable(GL_TEXTURE_2D);						// important to do this to avoid disappearing crosshairs!
		glEnable(GL_LINE_SMOOTH);						// alpha blending for lines
		glLineWidth(2.0);
		
		switch (weapon)
		{
			case WEAPON_NONE :
				glBegin(GL_LINES);
				glColor4fv(cx_col0);	glVertex3f(k3, 0.0, z1);	glColor4fv(cx_col2);	glVertex3f(k1, 0.0, z1);
				glColor4fv(cx_col0);	glVertex3f(-k3, 0.0, z1);   glColor4fv(cx_col2);	glVertex3f(-k1, 0.0, z1);
				glEnd();
				break;
			case WEAPON_MILITARY_LASER :
				glBegin(GL_LINES);
				glColor4fv(cx_col0);	glVertex3f(k2, k0, z1);		glColor4fv(cx_col1);	glVertex3f(0.0, k3, z1);
				glColor4fv(cx_col0);	glVertex3f(k2, -k0, z1);	glColor4fv(cx_col1);	glVertex3f(0.0, -k3, z1);
				glColor4fv(cx_col0);	glVertex3f(k0, k2, z1);		glColor4fv(cx_col1);	glVertex3f(k3, 0.0, z1);
				glColor4fv(cx_col0);	glVertex3f(-k0, k2, z1);	glColor4fv(cx_col1);	glVertex3f(-k3, 0.0, z1);
				glColor4fv(cx_col0);	glVertex3f(-k2, k0, z1);	glColor4fv(cx_col1);	glVertex3f(0.0, k3, z1);
				glColor4fv(cx_col0);	glVertex3f(-k2, -k0, z1);   glColor4fv(cx_col1);	glVertex3f(0.0, -k3, z1);
				glColor4fv(cx_col0);	glVertex3f(k0, -k2, z1);	glColor4fv(cx_col1);	glVertex3f(k3, 0.0, z1);
				glColor4fv(cx_col0);	glVertex3f(-k0, -k2, z1);   glColor4fv(cx_col1);	glVertex3f(-k3, 0.0, z1);
				
				glColor4fv(cx_col1);	glVertex3f(0.0, k3, z1);	glColor4fv(cx_col2);	glVertex3f(0.0, k1, z1);
				glColor4fv(cx_col1);	glVertex3f(0.0, -k3, z1);   glColor4fv(cx_col2);	glVertex3f(0.0, -k1, z1);
				glColor4fv(cx_col1);	glVertex3f(k3, 0.0, z1);	glColor4fv(cx_col2);	glVertex3f(k1, 0.0, z1);
				glColor4fv(cx_col1);	glVertex3f(-k3, 0.0, z1);   glColor4fv(cx_col2);	glVertex3f(-k1, 0.0, z1);
				glEnd();
				break;
			case WEAPON_MINING_LASER :
				glBegin(GL_LINES);
				glColor4fv(cx_col0);	glVertex3f(k1, k0, z1);		glColor4fv(cx_col2);	glVertex3f(k1, k1, z1);
				glColor4fv(cx_col0);	glVertex3f(k1, -k0, z1);	glColor4fv(cx_col2);	glVertex3f(k1, -k1, z1);
				glColor4fv(cx_col0);	glVertex3f(k0, k1, z1);		glColor4fv(cx_col2);	glVertex3f(k1, k1, z1);
				glColor4fv(cx_col0);	glVertex3f(-k0, k1, z1);	glColor4fv(cx_col2);	glVertex3f(-k1, k1, z1);
				glColor4fv(cx_col0);	glVertex3f(-k1, k0, z1);	glColor4fv(cx_col2);	glVertex3f(-k1, k1, z1);
				glColor4fv(cx_col0);	glVertex3f(-k1, -k0, z1);   glColor4fv(cx_col2);	glVertex3f(-k1, -k1, z1);
				glColor4fv(cx_col0);	glVertex3f(k0, -k1, z1);	glColor4fv(cx_col2);	glVertex3f(k1, -k1, z1);
				glColor4fv(cx_col0);	glVertex3f(-k0, -k1, z1);   glColor4fv(cx_col2);	glVertex3f(-k1, -k1, z1);
				glEnd();
				break;
			case WEAPON_BEAM_LASER :
				glBegin(GL_LINES);
				glColor4fv(cx_col0);	glVertex3f(k2, k0, z1);		glColor4fv(cx_col2);	glVertex3f(0.0, k1, z1);
				glColor4fv(cx_col0);	glVertex3f(k2, -k0, z1);	glColor4fv(cx_col2);	glVertex3f(0.0, -k1, z1);
				glColor4fv(cx_col0);	glVertex3f(k0, k2, z1);		glColor4fv(cx_col2);	glVertex3f(k1, 0.0, z1);
				glColor4fv(cx_col0);	glVertex3f(-k0, k2, z1);	glColor4fv(cx_col2);	glVertex3f(-k1, 0.0, z1);
				glColor4fv(cx_col0);	glVertex3f(-k2, k0, z1);	glColor4fv(cx_col2);	glVertex3f(0.0, k1, z1);
				glColor4fv(cx_col0);	glVertex3f(-k2, -k0, z1);   glColor4fv(cx_col2);	glVertex3f(0.0, -k1, z1);
				glColor4fv(cx_col0);	glVertex3f(k0, -k2, z1);	glColor4fv(cx_col2);	glVertex3f(k1, 0.0, z1);
				glColor4fv(cx_col0);	glVertex3f(-k0, -k2, z1);   glColor4fv(cx_col2);	glVertex3f(-k1, 0.0, z1);
				glEnd();
				break;
			case WEAPON_PULSE_LASER :
			default :
				glBegin(GL_LINES);
				glColor4fv(cx_col0);	glVertex3f(0.0, k0, z1);	glColor4fv(cx_col2);	glVertex3f(0.0, k1, z1);
				glColor4fv(cx_col0);	glVertex3f(0.0, -k0, z1);   glColor4fv(cx_col2);	glVertex3f(0.0, -k1, z1);
				glColor4fv(cx_col0);	glVertex3f(k0, 0.0, z1);	glColor4fv(cx_col2);	glVertex3f(k1, 0.0, z1);
				glColor4fv(cx_col0);	glVertex3f(-k0, 0.0, z1);   glColor4fv(cx_col2);	glVertex3f(-k1, 0.0, z1);
				glEnd();
				break;
		}
		
		glLineWidth(1.0);
	}
}


- (void) drawMessage
{
	glDisable(GL_TEXTURE_2D);	// for background sheets
	
	if (message_gui)
		[message_gui drawGUI:[message_gui alpha] drawCursor:NO];

	if (comm_log_gui)
		[comm_log_gui drawGUI:[comm_log_gui alpha] drawCursor:NO];

	if (displayGUI)
	{
		if (displayCursor)
			cursor_row = [gui drawGUI:1.0 drawCursor:YES];
		else
			[gui drawGUI:1.0 drawCursor:NO];
	}
}


- (id)entityForUniversalID:(OOUniversalID)u_id
{
	if (u_id == 100)
		return [PlayerEntity sharedPlayer];	// the player
	
	if ((u_id == NO_TARGET)||(!entity_for_uid[u_id]))
		return nil;
		
	Entity* ent = entity_for_uid[u_id];
	if (ent->isParticle)	// particles SHOULD NOT HAVE U_IDs!
		return nil;
	int ent_status = ent->status;
	if (ent_status == STATUS_DEAD)
		return nil;
	if (ent_status == STATUS_DOCKED)
		return nil;

	return ent;
}


static BOOL MaintainLinkedLists(Universe* uni)
{
	BOOL result;
	
	if (!uni)
		return NO;
	
	result = YES;
	
	// DEBUG check for loops and short lists
	if (uni->n_entities > 0)
	{
		int n;
		Entity	*check, *last;
		
		last = nil;
		
		n = uni->n_entities;
		check = uni->x_list_start;
		while ((n--)&&(check))
		{
			last = check;
			check = check->x_next;
		}
		if ((check)||(n > 0))
		{
			OOLog(kOOLogEntityVerificationError, @"Broken x_next %@ list (%d) ***", uni->x_list_start, n);
			result = NO;
		}
		
		n = uni->n_entities;
		check = last;
		while ((n--)&&(check))	check = check->x_previous;
		if ((check)||(n > 0))
		{
			OOLog(kOOLogEntityVerificationError, @"Broken x_previous %@ list (%d) ***", uni->x_list_start, n);
			if (result)
			{
				OOLog(kOOLogEntityVerificationRebuild, @"REBUILDING x_previous list from x_next list");
				check = uni->x_list_start;
				check->x_previous = nil;
				while (check->x_next)
				{
					last = check;
					check = check->x_next;
					check->x_previous = last;
				}
			}
		}
		
		n = uni->n_entities;
		check = uni->y_list_start;
		while ((n--)&&(check))
		{
			last = check;
			check = check->y_next;
		}
		if ((check)||(n > 0))
		{
			OOLog(kOOLogEntityVerificationError, @"Broken *** broken y_next %@ list (%d) ***", uni->y_list_start, n);
			result = NO;
		}
		
		n = uni->n_entities;
		check = last;
		while ((n--)&&(check))	check = check->y_previous;
		if ((check)||(n > 0))
		{
			OOLog(kOOLogEntityVerificationError, @"Broken y_previous %@ list (%d) ***", uni->y_list_start, n);
			if (result)
			{
				OOLog(kOOLogEntityVerificationRebuild, @"REBUILDING y_previous list from y_next list");
				check = uni->y_list_start;
				check->y_previous = nil;
				while (check->y_next)
				{
					last = check;
					check = check->y_next;
					check->y_previous = last;
				}
			}
		}
		
		n = uni->n_entities;
		check = uni->z_list_start;
		while ((n--)&&(check))
		{
			last = check;
			check = check->z_next;
		}
		if ((check)||(n > 0))
		{
			OOLog(kOOLogEntityVerificationError, @"Broken z_next %@ list (%d) ***", uni->z_list_start, n);
			result = NO;
		}
		
		n = uni->n_entities;
		check = last;
		while ((n--)&&(check))	check = check->z_previous;
		if ((check)||(n > 0))
		{
			OOLog(kOOLogEntityVerificationError, @"Broken z_previous %@ list (%d) ***", uni->z_list_start, n);
			if (result)
			{
				OOLog(kOOLogEntityVerificationRebuild, @"REBUILDING z_previous list from z_next list");
				check = uni->z_list_start;
				check->z_previous = nil;
				while (check->z_next)
				{
					last = check;
					check = check->z_next;
					check->z_previous = last;
				}
			}
		}
	}
	
	if (!result)
	{
		OOLog(kOOLogEntityVerificationRebuild, @"Rebuilding all linked lists from scratch");
		NSArray* allEntities = uni->entities;
		uni->x_list_start = nil;
		uni->y_list_start = nil;
		uni->z_list_start = nil;
		int n_ents = [allEntities count];
		int i;
		for (i = 0; i < n_ents; i++)
		{
			Entity* ent = (Entity*)[allEntities objectAtIndex:i];
			ent->x_next = nil;
			ent->x_previous = nil;
			ent->y_next = nil;
			ent->y_previous = nil;
			ent->z_next = nil;
			ent->z_previous = nil;
			[ent addToLinkedLists];
		}
	}
	
	return result;
}


- (BOOL) addEntity:(Entity *) entity
{
	if (entity)
	{
#ifndef NDEBUG
		if (gDebugFlags & DEBUG_ENTITIES)
			OOLog(@"universe.addEntity", @"Adding entity: %@", entity);
#endif
		
		int index = n_entities;
		
		// don't add things twice!
		if ([entities containsObject:entity])
			return YES;
			
		if (n_entities >= UNIVERSE_MAX_ENTITIES - 1)
		{
			// throw an exception here...
			OOLog(@"universe.addEntity.failed", @"***** Universe cannot addEntity:%@ -- Universe is full (%d entities out of %d)", entity, n_entities, UNIVERSE_MAX_ENTITIES);
#ifndef NDEBUG
			[self obj_dump];
#endif
			[NSException raise:@"OoliteException"
						format:@"Maximum number of entities (%d) in Universe reached. Cannot add %@", UNIVERSE_MAX_ENTITIES, entity];
		}
		
		if (!(entity->isParticle))
		{
			while (entity_for_uid[next_universal_id] != nil)	// skip allocated numbers
			{
				next_universal_id++;						// increment keeps idkeys unique
				if (next_universal_id >= MAX_ENTITY_UID)
					next_universal_id = 0;
				while (next_universal_id == NO_TARGET)		// these are the null values - avoid them!
					next_universal_id++;
			}
			[entity setUniversalID:next_universal_id];
			entity_for_uid[next_universal_id] = entity;
			if (entity->isShip)
			{
				ShipEntity* se = (ShipEntity *)entity;
				[[se getAI] setOwner:se];
				[[se getAI] setState:@"GLOBAL"];
				if ([se isBeacon])
					[self setNextBeacon:se];
				if (se->isStation)
				{					
					// check if it is a proper rotating station (ie. roles contains the word "station")
					if ([(StationEntity*)se isRotatingStation])
					{
						// check for station_roll override
						NSDictionary*	systeminfo = [self generateSystemData:system_seed];
						double stationRoll = [systeminfo doubleForKey:@"station_roll" defaultValue:0.4];
						
						[se setRoll: stationRoll];
						[(StationEntity*)se setPlanet:[self planet]];
						[se setStatus:STATUS_ACTIVE];
					}
					else
					{
						[se setRoll: 0.0];
						[(StationEntity*)se setPlanet:[self planet]];
						[se setStatus:STATUS_ACTIVE];
					}
				}
			}
		}
		else
			[entity setUniversalID:NO_TARGET];
		
		// lighting considerations
		entity->isSunlit = YES;
		entity->shadingEntityID = NO_TARGET;
		
		// add it to the universe
		[entities addObject:entity];
		[entity wasAddedToUniverse];
		
		// maintain sorted list (and for the scanner relative position)
		Vector entity_pos = entity->position;
		Vector delta = vector_between(entity_pos, ((PlayerEntity *)[PlayerEntity sharedPlayer])->position);
		double z_distance = magnitude2(delta);
		entity->zero_distance = z_distance;
		entity->relativePosition = delta;
		index = n_entities;
		sortedEntities[index] = entity;
		entity->zero_index = index;
		while ((index > 0)&&(z_distance < sortedEntities[index - 1]->zero_distance))	// bubble into place
		{
			sortedEntities[index] = sortedEntities[index - 1];
			sortedEntities[index]->zero_index = index;
			index--;
			sortedEntities[index] = entity;
			entity->zero_index = index;
		}

		
		// increase n_entities...
		n_entities++;

		// add entity to linked lists
		[entity addToLinkedLists];	// position and universe have been set - so we can do this
		if ([entity canCollide])	// filter only collidables disappearing
			doLinkedListMaintenanceThisUpdate = YES;
		
		if (entity->isWormhole)
			[activeWormholes addObject:entity];
		
		return YES;
	}
	return NO;
}


- (BOOL) removeEntity:(Entity *) entity
{
	if (entity)
	{
		// remove reference to entity in linked lists
		if ([entity canCollide])	// filter only collidables disappearing
			doLinkedListMaintenanceThisUpdate = YES;
		
		[entity removeFromLinkedLists];
		
		// moved forward ^^
		// remove from the reference dictionary
		int old_id = [entity universalID];
		entity_for_uid[old_id] = nil;
		[entity setUniversalID:NO_TARGET];
		[entity wasRemovedFromUniverse];
		
		// maintain sorted lists
		int index = entity->zero_index;

		int n = 1;
		if (index >= 0)
		{
			if (sortedEntities[index] != entity)
			{
				OOLog(kOOLogInconsistentState, @"DEBUG Universe removeEntity:%@ ENTITY IS NOT IN THE RIGHT PLACE IN THE ZERO_DISTANCE SORTED LIST -- FIXING...", entity);
				unsigned i;
				index = -1;
				for (i = 0; (i < n_entities)&&(index == -1); i++)
					if (sortedEntities[i] == entity)
						index = i;
				if (index == -1)
					 OOLog(kOOLogInconsistentState, @"DEBUG Universe removeEntity:%@ ENTITY IS NOT IN THE ZERO_DISTANCE SORTED LIST -- CONTINUING...", entity);
			}
 			if (index != -1)
			{
				while ((unsigned)index < n_entities)
				{
					while (((unsigned)index + n < n_entities)&&(sortedEntities[index + n] == entity))
						n++;	// ie there's a duplicate entry for this entity
					sortedEntities[index] = sortedEntities[index + n];	// copy entity[index + n] -> entity[index] (preserves sort order)
					if (sortedEntities[index])
						sortedEntities[index]->zero_index = index;				// give it its correct position
					index++;
				}
				if (n > 1)
					 OOLog(kOOLogInconsistentState, @"DEBUG Universe removeEntity: REMOVED %d EXTRA COPIES OF %@ FROM THE ZERO_DISTANCE SORTED LIST", n - 1, entity);
				while (n--)
				{
					n_entities--;
					sortedEntities[n_entities] = nil;
				}
			}
			entity->zero_index = -1;	// it's GONE!
		}
		
		// remove from the definitive list
		if ([entities containsObject:entity])
		{
			if (entity->isRing)
				breakPatternCounter--;

			if (entity->isShip)
			{
				int bid = firstBeacon;
				ShipEntity* se = (ShipEntity*)entity;
				if ([se isBeacon])
				{
					if (bid == old_id)
						firstBeacon = [se nextBeaconID];
					else
					{
						ShipEntity* beacon = (ShipEntity*)[self entityForUniversalID:bid];
						while ((beacon != nil)&&([beacon nextBeaconID] != old_id))
							beacon = (ShipEntity*)[self entityForUniversalID:[beacon nextBeaconID]];
						
						[beacon setNextBeacon:(ShipEntity*)[self entityForUniversalID:[se nextBeaconID]]];
						
						while ([beacon nextBeaconID] != NO_TARGET)
							beacon = (ShipEntity*)[self entityForUniversalID:[beacon nextBeaconID]];
						lastBeacon = [beacon universalID];
					}
				}
				[se setBeaconChar:0];
			}
			
			
			if (entity->isWormhole)
				[activeWormholes removeObject:entity];
			
			[entities removeObject:entity];
			
			return YES;
		}
	}
	return NO;
}


- (void) removeAllEntitiesExceptPlayer:(BOOL) restore
{
	BOOL updating = no_update;
	no_update = YES;			// no drawing while we do this!
	
#ifndef NDEBUG
	Entity* p0 = [entities objectAtIndex:0];
	if (!(p0->isPlayer))
	{
		OOLog(kOOLogInconsistentState, @"***** First entity is not the player in Universe.removeAllEntitiesExceptPlayer - exiting.");
		exit(1);
	}
#endif
	
	// preserve wormholes
	NSArray* savedWormholes = [NSArray arrayWithArray:activeWormholes];
	
	while ([entities count] > 1)
	{
		Entity* ent = [entities objectAtIndex:1];
		if (ent->isStation)  // clear out queues
			[(StationEntity *)ent clear];
		[self removeEntity:ent];
	}
	
	[activeWormholes addObjectsFromArray:savedWormholes];	// will be cleared out by populateFromActiveWormholes
	
	// maintain sorted list
	n_entities = 1;
	
	cachedSun = nil;
	cachedPlanet = nil;
	cachedStation = nil;
	firstBeacon = NO_TARGET;
	lastBeacon = NO_TARGET;
	
	no_update = updating;	// restore drawing
}


- (void) removeDemoShips
{
	int i;
	int ent_count = n_entities;
	Entity* my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
		my_entities[i] = [sortedEntities[i] retain];
	if (ent_count > 1)
	{
		for (i = 1; i < ent_count; i++)
		{
			Entity* ent = my_entities[i];
			if (ent->status == STATUS_COCKPIT_DISPLAY)
				[self removeEntity:ent];
		}
	}
	for (i = 0; i < ent_count; i++)
		[my_entities[i] release];
	demo_ship = nil;
}


- (BOOL) isVectorClearFromEntity:(Entity *) e1 toDistance:(double)dist fromPoint:(Vector) p2
{
	if (!e1)
		return NO;

	Vector  f1;
	Vector p1 = e1->position;
	Vector v1 = p2;
	v1.x -= p1.x;   v1.y -= p1.y;   v1.z -= p1.z;   // vector from entity to p2
	
	double  nearest = sqrt(v1.x*v1.x + v1.y*v1.y + v1.z*v1.z) - dist;  // length of vector
	
	if (nearest < 0.0)
		return YES;			// within range already!
	
	int i;
	int ent_count = n_entities;
	Entity* my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
		my_entities[i] = [sortedEntities[i] retain]; //	retained
	
	if (v1.x || v1.y || v1.z)
		f1 = unit_vector(&v1);   // unit vector in direction of p2 from p1
	else
		f1 = make_vector(0, 0, 1);
	
	for (i = 0; i < ent_count ; i++)
	{
		Entity *e2 = my_entities[i];
		if ((e2 != e1)&&([e2 canCollide]))
		{
			Vector epos = e2->position;
			epos.x -= p1.x;	epos.y -= p1.y;	epos.z -= p1.z; // epos now holds vector from p1 to this entities position
			
			double d_forward = dot_product(epos,f1);	// distance along f1 which is nearest to e2's position
			
			if ((d_forward > 0)&&(d_forward < nearest))
			{
				double cr = 1.10 * (e2->collision_radius + e1->collision_radius); //  10% safety margin
				Vector p0 = e1->position;
				p0.x += d_forward * f1.x;	p0.y += d_forward * f1.y;	p0.z += d_forward * f1.z;
				// p0 holds nearest point on current course to center of incident object
				Vector epos = e2->position;
				p0.x -= epos.x;	p0.y -= epos.y;	p0.z -= epos.z;
				// compare with center of incident object
				double  dist2 = p0.x * p0.x + p0.y * p0.y + p0.z * p0.z;
				if (dist2 < cr*cr)
				{
					for (i = 0; i < ent_count; i++)
						[my_entities[i] release]; //	released
					return NO;
				}
			}
		}
	}
	for (i = 0; i < ent_count; i++)
		[my_entities[i] release]; //	released
	return YES;
}


- (Entity*) hazardOnRouteFromEntity:(Entity *) e1 toDistance:(double)dist fromPoint:(Vector) p2
{
	if (!e1)
		return nil;

	Vector f1;
	Vector p1 = e1->position;
	Vector v1 = p2;
	v1.x -= p1.x;   v1.y -= p1.y;   v1.z -= p1.z;   // vector from entity to p2
	
	double  nearest = sqrt(v1.x*v1.x + v1.y*v1.y + v1.z*v1.z) - dist;  // length of vector
	
	if (nearest < 0.0)
		return nil;			// within range already!
	
	Entity* result = nil;
	int i;
	int ent_count = n_entities;
	Entity* my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
		my_entities[i] = [sortedEntities[i] retain]; //	retained

	if (v1.x || v1.y || v1.z)
		f1 = unit_vector(&v1);   // unit vector in direction of p2 from p1
	else
		f1 = make_vector(0, 0, 1);
	
	for (i = 0; (i < ent_count) && (!result) ; i++)
	{
		Entity *e2 = my_entities[i];
		if ((e2 != e1)&&([e2 canCollide]))
		{
			Vector epos = e2->position;
			epos.x -= p1.x;	epos.y -= p1.y;	epos.z -= p1.z; // epos now holds vector from p1 to this entities position
			
			double d_forward = dot_product(epos,f1);	// distance along f1 which is nearest to e2's position
			
			if ((d_forward > 0)&&(d_forward < nearest))
			{
				double cr = 1.10 * (e2->collision_radius + e1->collision_radius); //  10% safety margin
				Vector p0 = e1->position;
				p0.x += d_forward * f1.x;	p0.y += d_forward * f1.y;	p0.z += d_forward * f1.z;
				// p0 holds nearest point on current course to center of incident object
				Vector epos = e2->position;
				p0.x -= epos.x;	p0.y -= epos.y;	p0.z -= epos.z;
				// compare with center of incident object
				double  dist2 = p0.x * p0.x + p0.y * p0.y + p0.z * p0.z;
				if (dist2 < cr*cr)
					result = e2;
			}
		}
	}
	for (i = 0; i < ent_count; i++)
		[my_entities[i] release]; //	released
	return result;
}


- (Vector) getSafeVectorFromEntity:(Entity *) e1 toDistance:(double)dist fromPoint:(Vector) p2
{
	// heuristic three
	
	if (!e1)
	{
		OOLog(kOOLogParameterError, @"***** No entity set in Universe getSafeVectorFromEntity:toDistance:fromPoint:");
		return kZeroVector;
	}
	
	Vector  f1;
	Vector  result = p2;
	int i;
	int ent_count = n_entities;
	Entity* my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
		my_entities[i] = [sortedEntities[i] retain];	// retained
	Vector p1 = e1->position;
	Vector v1 = p2;
	v1.x -= p1.x;   v1.y -= p1.y;   v1.z -= p1.z;   // vector from entity to p2
	
	double  nearest = sqrt(v1.x*v1.x + v1.y*v1.y + v1.z*v1.z) - dist;  // length of vector
	
	if (v1.x || v1.y || v1.z)
		f1 = unit_vector(&v1);   // unit vector in direction of p2 from p1
	else
		f1 = make_vector(0, 0, 1);
		
	for (i = 0; i < ent_count; i++)
	{
		Entity *e2 = my_entities[i];
		if ((e2 != e1)&&([e2 canCollide]))
		{
			Vector epos = e2->position;
			epos.x -= p1.x;	epos.y -= p1.y;	epos.z -= p1.z;
			double d_forward = dot_product(epos,f1);
			if ((d_forward > 0)&&(d_forward < nearest))
			{
				double cr = 1.20 * (e2->collision_radius + e1->collision_radius); //  20% safety margin
					
				Vector p0 = e1->position;
				p0.x += d_forward * f1.x;	p0.y += d_forward * f1.y;	p0.z += d_forward * f1.z;
				// p0 holds nearest point on current course to center of incident object
								
				Vector epos = e2->position;
				p0.x -= epos.x;	p0.y -= epos.y;	p0.z -= epos.z;
				// compare with center of incident object
				
				double  dist2 = p0.x * p0.x + p0.y * p0.y + p0.z * p0.z;
								
				if (dist2 < cr*cr)
				{
					result = e2->position;			// center of incident object
					nearest = d_forward;
					
					if (dist2 == 0.0)
					{
						// ie. we're on a line through the object's center !
						// jitter the position somewhat!
						result.x += ((ranrot_rand() % 1024) - 512)/512.0; //   -1.0 .. +1.0
						result.y += ((ranrot_rand() % 1024) - 512)/512.0; //   -1.0 .. +1.0
						result.z += ((ranrot_rand() % 1024) - 512)/512.0; //   -1.0 .. +1.0
					}
					
					Vector  nearest_point = p1;
					nearest_point.x += d_forward * f1.x;	nearest_point.y += d_forward * f1.y;	nearest_point.z += d_forward * f1.z;
					// nearest point now holds nearest point on line to center of incident object
					
					Vector outward = nearest_point;
					outward.x -= result.x;	outward.y -= result.y;	outward.z -= result.z;
					if (outward.x||outward.y||outward.z)
						outward = unit_vector(&outward);
					else
						outward.y = 1.0;
					// outward holds unit vector through the nearest point on the line from the center of incident object
					
					Vector backward = p1;
					backward.x -= result.x;	backward.y -= result.y;	backward.z -= result.z;
					if (backward.x||backward.y||backward.z)
						backward = unit_vector(&backward);
					else
						backward.z = -1.0;
					// backward holds unit vector from center of the incident object to the center of the ship
					
					Vector dd = result;
					dd.x -= p1.x; dd.y -= p1.y; dd.z -= p1.z;
					double current_distance = sqrt (dd.x*dd.x + dd.y*dd.y + dd.z*dd.z);
					
					// sanity check current_distance
					if (current_distance < cr * 1.25)	// 25% safety margin
						current_distance = cr * 1.25;
					if (current_distance > cr * 5.0)	// up to 2 diameters away 
						current_distance = cr * 5.0;
										
					// choose a point that's three parts backward and one part outward
					
					result.x += 0.25 * (outward.x * current_distance) + 0.75 * (backward.x * current_distance);		// push 'out' by this amount
					result.y += 0.25 * (outward.y * current_distance) + 0.75 * (backward.y * current_distance);
					result.z += 0.25 * (outward.z * current_distance) + 0.75 * (backward.z * current_distance);
					
				}
			}
		}
	}
	for (i = 0; i < ent_count; i++)
		[my_entities[i] release]; //	released
	return result;
}


- (int) getFirstEntityHitByLaserFromEntity:(Entity *) e1 inView:(int) viewdir offset:(Vector) offset rangeFound:(GLfloat*)range_ptr
{
	if (!e1)
		return NO_TARGET;
	
	BOOL debug_laser = e1->isPlayer;

	BOOL isSubentity = NO;
	ShipEntity  *hit_entity = nil;
	ShipEntity  *hit_subentity = nil;
	
	Vector p0 = e1->position;
	Quaternion q1 = e1->orientation;
	if (e1->isPlayer)
		q1.w = -q1.w;   //  reverse for player viewpoint
	
	ShipEntity* parent = (ShipEntity*)[e1 owner];
	if ((e1->isShip)&&(parent)&&(parent != e1)&&(parent->isShip)&&([parent->sub_entities containsObject:e1]))
	{	// we're a subentity!
		BoundingBox bbox = [e1 boundingBox];
		Vector midfrontplane = make_vector(0.5 * (bbox.max.x + bbox.min.x), 0.5 * (bbox.max.y + bbox.min.y), bbox.max.z);
		p0 = [(ShipEntity*)e1 absolutePositionForSubentityOffset:midfrontplane];
		q1 = parent->orientation;
		if (parent->isPlayer)
			q1.w = -q1.w;
		isSubentity = YES;
	}
	
	int		result = NO_TARGET;
	double  nearest;
	if (e1->isShip)
		nearest = [(ShipEntity *)e1 weaponRange];
	else
		nearest = PARTICLE_LASER_LENGTH;
	
	int i;
	int ent_count = n_entities;
	int ship_count = 0;
	ShipEntity* my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
	{
		Entity* ent = sortedEntities[i];
		if ((ent->isShip) && (ent != e1) && (ent != parent) && [ent canCollide])
			my_entities[ship_count++] = [ent retain];	// retained
	}
	
	Vector u1 = vector_up_from_quaternion(q1);
	Vector f1 = vector_forward_from_quaternion(q1);
	Vector r1 = vector_right_from_quaternion(q1);
	p0.x += offset.x * r1.x + offset.y * u1.x + offset.z * f1.x;
	p0.y += offset.x * r1.y + offset.y * u1.y + offset.z * f1.y;
	p0.z += offset.x * r1.z + offset.y * u1.z + offset.z * f1.z;
	switch (viewdir)
	{
		case VIEW_AFT :
			quaternion_rotate_about_axis(&q1, u1, M_PI);
			break;
		case VIEW_PORT :
			quaternion_rotate_about_axis(&q1, u1, M_PI/2.0);
			break;
		case VIEW_STARBOARD :
			quaternion_rotate_about_axis(&q1, u1, -M_PI/2.0);
			break;
	}
	f1 = vector_forward_from_quaternion(q1);
	r1 = vector_right_from_quaternion(q1);
	Vector p1 = make_vector(p0.x + nearest *f1.x, p0.y + nearest *f1.y, p0.z + nearest *f1.z);	//endpoint
	
	for (i = 0; i < ship_count; i++)
	{
		ShipEntity *e2 = my_entities[i];
		
		debug_laser = ((e1->isPlayer) && ([(ShipEntity*)e1 primaryTargetID] == [e2 universalID]));
		
		// check outermost bounding sphere
		GLfloat cr = e2->collision_radius;
		Vector rpos = vector_between(p0, e2->position);
		Vector v_off = make_vector(dot_product(rpos, r1), dot_product(rpos, u1), dot_product(rpos, f1));
		if ((v_off.z > 0.0)&&(v_off.z < nearest + cr)								// ahead AND within range
			&&(v_off.x < cr)&&(v_off.x > -cr)&&(v_off.y < cr)&&(v_off.y > -cr)		// AND not off to one side or another
			&&(v_off.x*v_off.x + v_off.y*v_off.y < cr*cr))							// AND not off to both sides
		{
			//  within the bounding sphere - do further tests
			GLfloat ar = e2->collision_radius;
			if ((v_off.z > 0.0)&&(v_off.z < nearest + ar)								// ahead AND within range
				&&(v_off.x < ar)&&(v_off.x > -ar)&&(v_off.y < ar)&&(v_off.y > -ar)		// AND not off to one side or another
				&&(v_off.x*v_off.x + v_off.y*v_off.y < ar*ar))							// AND not off to both sides
			{
				ShipEntity* entHit = (ShipEntity*)nil;
				GLfloat hit = [(ShipEntity*)e2 doesHitLine:p0:p1:&entHit];	// octree detection
				
				if ((hit > 0.0)&&(hit < nearest))
				{
					if (entHit->isSubentity)
						hit_subentity = entHit;
					hit_entity = e2;
					nearest = hit;
					p1 = make_vector(p0.x + nearest *f1.x, p0.y + nearest *f1.y, p0.z + nearest *f1.z);
				}
			}

		}
	}

	
	if (hit_entity)
	{
		result = [hit_entity universalID];
		if ((hit_subentity)&&[hit_entity->sub_entities containsObject:hit_subentity])
			hit_entity->subentity_taking_damage = hit_subentity;
		if (range_ptr != (GLfloat *)nil)
			range_ptr[0] = (GLfloat)nearest;
	}
	
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release]; //	released
	
	return result;
}


- (int) getFirstEntityTargettedByPlayer:(PlayerEntity*) player
{
	if ((!player)||(!player->isPlayer))
		return NO_TARGET;
	
	ShipEntity*	hit_entity = nil;
	
	int		result = NO_TARGET;
	double  nearest = SCANNER_MAX_RANGE - 10;	// 10m shorter than range at which target is lost
	int i;
	
	int ent_count = n_entities;
	int ship_count = 0;
	Entity* my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
		if ((sortedEntities[i]->isShip)&&(sortedEntities[i] != player))
			my_entities[ship_count++] = [sortedEntities[i] retain];	// retained

	Vector p1 = player->position;
	Quaternion q1 = player->orientation;
	q1.w = -q1.w;   //  reverse for player viewpoint
	Vector u1 = vector_up_from_quaternion(q1);
	Vector f1 = vector_forward_from_quaternion(q1);
	Vector r1 = vector_right_from_quaternion(q1);
	Vector offset = [player weaponViewOffset];
	p1.x += offset.x * r1.x + offset.y * u1.x + offset.z * f1.x;
	p1.y += offset.x * r1.y + offset.y * u1.y + offset.z * f1.y;
	p1.z += offset.x * r1.z + offset.y * u1.z + offset.z * f1.z;
	switch (viewDirection)
	{
		case VIEW_AFT :
			quaternion_rotate_about_axis(&q1, u1, M_PI);
			break;
		case VIEW_PORT :
			quaternion_rotate_about_axis(&q1, u1, 0.5 * M_PI);
			break;
		case VIEW_STARBOARD :
			quaternion_rotate_about_axis(&q1, u1, -0.5 * M_PI);
			break;
	}
	f1 = vector_forward_from_quaternion(q1);
	r1 = vector_right_from_quaternion(q1);
	for (i = 0; i < ship_count; i++)
	{
		ShipEntity *e2 = (ShipEntity *)my_entities[i];
		if ([e2 canCollide]&&(e2->scanClass != CLASS_NO_DRAW))
		{
			Vector rp = e2->position;
			rp.x -= p1.x;	rp.y -= p1.y;	rp.z -= p1.z;
			double dist2 = magnitude2(rp);
			if (dist2 < nearest * nearest)
			{
				double df = dot_product(f1,rp);
				if ((df > 0.0)&&(df < nearest))
				{
					double du = dot_product(u1,rp);
					double dr = dot_product(r1,rp);
					double cr = e2->collision_radius;
					if (du*du + dr*dr < cr*cr)
					{
						hit_entity = e2;
						nearest = sqrt(dist2);
					}
				}
			}
		}
	}
	// check for MASC'M
	if ((hit_entity) && [hit_entity isJammingScanning] && (![player hasMilitaryScannerFilter]))
		hit_entity = nil;
	
	if (hit_entity)
		result = [hit_entity universalID];
	
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release]; //	released
	
	return result;
}


- (NSArray *) getEntitiesWithinRange:(double) range1 ofEntity:(Entity *) e1
{
	if (!e1)
		return nil;
	NSMutableArray *hitlist = [NSMutableArray arrayWithCapacity:4];
	int i;
	int ent_count = n_entities;
	Entity* my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
		my_entities[i] = [sortedEntities[i] retain];	// retained

	Vector p1 = e1->position;
	for (i = 0; i < ent_count; i++)
	{
		Entity *e2 = my_entities[i];
		if ((e2 != e1)&&([e2 canCollide]))
		{
			Vector p2 = e2->position;
			p2.x -= p1.x;	p2.y -= p1.y;	p2.z -= p1.z;
			double cr = range1 + e2->collision_radius;
			double d2 = p2.x*p2.x + p2.y*p2.y + p2.z*p2.z - cr*cr;
			if (d2 < 0)
				[hitlist addObject:e2];
		}
	}
	for (i = 0; i < ent_count; i++)
		[my_entities[i] release]; //	released
	return  [NSArray arrayWithArray:hitlist];
}


- (unsigned) countShipsWithRole:(NSString *) desc inRange:(double) range1 ofEntity:(Entity *)e1
{
	if (!e1)  return 0;
	
	unsigned	i, found;
	unsigned	ent_count = n_entities;
	unsigned	ship_count = 0;
	Entity		*my_entities[ent_count];
	
	for (i = 0; i < ent_count; i++)
		if (sortedEntities[i]->isShip)
			my_entities[ship_count++] = [sortedEntities[i] retain];	// retained

	found = 0;
	Vector p1 = e1->position;
	for (i = 0; i < ship_count; i++)
	{
		Entity *e2 = my_entities[i];
		if ((e2 != e1)&&([[(ShipEntity *)e2 roles] isEqual:desc]))
		{
			Vector p2 = e2->position;
			p2.x -= p1.x;	p2.y -= p1.y;	p2.z -= p1.z;
			double cr = range1 + e2->collision_radius;
			double d2 = p2.x*p2.x + p2.y*p2.y + p2.z*p2.z - cr*cr;
			if (d2 < 0)
				found++;
		}
	}
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release]; //	released
	return  found;
}


- (unsigned) countShipsWithRole:(NSString *) desc
{
	unsigned	i, found;
	unsigned	ent_count = n_entities;
	unsigned	ship_count = 0;
	Entity		*my_entities[ent_count];
	
	for (i = 0; i < ent_count; i++)
		if (sortedEntities[i]->isShip)
			my_entities[ship_count++] = [sortedEntities[i] retain];	// retained

	found = 0;
	for (i = 0; i < ship_count; i++)
	{
		Entity *e2 = my_entities[i];
		if (([[(ShipEntity *)e2 roles] isEqual:desc]))
			found++;
	}
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release]; //	released
	return  found;
}


- (void) sendShipsWithRole:(NSString *) desc messageToAI:(NSString *) ms
{
	int i, found;
	int ent_count = n_entities;
	int ship_count = 0;
	Entity* my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
		if (sortedEntities[i]->isShip)
			my_entities[ship_count++] = [sortedEntities[i] retain];	// retained

	found = 0;
	for (i = 0; i < ship_count; i++)
	{
		Entity *e2 = my_entities[i];
		if ([[(ShipEntity *)e2 roles] isEqual:desc])
			[[(ShipEntity *)e2 getAI] reactToMessage:ms];
	}
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release]; //	released
}


- (OOTimeAbsolute) getTime
{
	return universal_time;
}


- (OOTimeDelta) getTimeDelta
{
	return time_delta;
}


- (void) findCollisionsAndShadows
{
	unsigned i;
	
	[universeRegion clearEntityList];
	
	for (i = 0; i < n_entities; i++)
		[universeRegion checkEntity: sortedEntities[i]];	//	sorts out which region it's in
	
	[universeRegion findCollisions];
	
	// do check for entities that can't see the sun!
	[universeRegion findShadowedEntities];
	
}


- (NSString*) collisionDescription
{
	if (universeRegion)
		return	[NSString stringWithFormat:@"c%d", universeRegion->checks_this_tick];
	else
		return	@"-";
}


- (void) dumpCollisions
{
	dumpCollisionInfo = YES;
}


- (void) setViewDirection:(OOViewID) vd
{
	NSString	*ms = nil;
	
	if ((viewDirection == vd)&&(vd != VIEW_CUSTOM)&&(!displayGUI))
		return;
	
	switch (vd)
	{
		case VIEW_FORWARD :
#ifdef GNUSTEP
         [gameView setMouseInDeltaMode: YES];
#endif
			ms = @"Forward View";
			displayGUI = NO;   // switch off any text displays
			break;
		case VIEW_AFT :
#ifdef GNUSTEP
         [gameView setMouseInDeltaMode: YES];
#endif
			ms = @"Aft View";
			displayGUI = NO;   // switch off any text displays
			break;
		case VIEW_PORT :
#ifdef GNUSTEP
         [gameView setMouseInDeltaMode: YES];
#endif
			ms = @"Port View";
			displayGUI = NO;   // switch off any text displays
			break;
		case VIEW_STARBOARD :
#ifdef GNUSTEP
         [gameView setMouseInDeltaMode: YES];
#endif
			ms = @"Starboard View";
			displayGUI = NO;   // switch off any text displays
			break;
		/* GILES custom views */
		
		case VIEW_CUSTOM :
#ifdef GNUSTEP
         [gameView setMouseInDeltaMode: YES];
#endif
			ms = [[PlayerEntity sharedPlayer] customViewDescription];
			displayGUI = NO;   // switch off any text displays
			break;
			
		/* -- */
		default :
#ifdef GNUSTEP
         [gameView setMouseInDeltaMode: NO];
#endif
			break;
	}
	if ((viewDirection != vd)|(viewDirection = VIEW_CUSTOM))
	{
		viewDirection = vd;
		if (ms)
			[self addMessage:ms forCount:3];
	}
}


- (OOViewID) viewDir
{
	return viewDirection;
}


- (BOOL) playCustomSound:(NSString*)key
{
	if ([customsounds objectForKey:key])
	{
		OOSound* sound = [ResourceManager ooSoundNamed:(NSString*)[customsounds objectForKey:key] inFolder:@"Sounds"];
		if (sound)
		{
			if (![sound isPlaying])
				[sound play];
			return YES;
		}
	}
	return NO;
}


- (BOOL) stopCustomSound:(NSString*)key
{
	if ([customsounds objectForKey:key])
	{
		OOSound* sound = [ResourceManager ooSoundNamed:[customsounds stringForKey:key] inFolder:@"Sounds"];
		if (sound)
		{
			return [sound stop];
		}
	}
	return NO;
}


- (BOOL) isPlayingCustomSound:(NSString*)key
{
	if ([customsounds objectForKey:key])
	{
		OOSound* sound = [ResourceManager ooSoundNamed:[customsounds stringForKey:key] inFolder:@"Sounds"];
		if (sound)
			return [sound isPlaying];
	}
	return NO;
}


- (void) clearPreviousMessage
{
	if (currentMessage)	[currentMessage release];
	currentMessage = nil;
}


- (void) setMessageGuiBackgroundColor:(OOColor *) some_color
{
	[message_gui setBackgroundColor:some_color];
}


- (void) displayMessage:(NSString *) text forCount:(int) count
{
	if (![currentMessage isEqual:text])
    {
		if (currentMessage)	[currentMessage release];
		currentMessage = [text retain];
		
		[message_gui printLongText:text Align:GUI_ALIGN_CENTER Color:[OOColor yellowColor] FadeTime:(float)count Key:nil AddToArray:nil];
    }
}


- (void) displayCountdownMessage:(NSString *) text forCount:(int) count
{
	if (![currentMessage isEqual:text])
    {
		if (currentMessage)	[currentMessage release];
		currentMessage = [text retain];
		
		[message_gui printLineNoScroll:text Align:GUI_ALIGN_CENTER Color:[OOColor yellowColor] FadeTime:(float)count Key:nil AddToArray:nil];
    }
}


- (void) addDelayedMessage:(NSString *) text forCount:(int) count afterDelay:(double) delay
{
	SEL _addDelayedMessageSelector = @selector(addDelayedMessage:);
	NSMutableDictionary *msgDict = [NSMutableDictionary dictionaryWithCapacity:2];
	[msgDict setObject:text forKey:@"message"];
	[msgDict setObject:[NSNumber numberWithInt:count] forKey:@"duration"];
	[self performSelector:_addDelayedMessageSelector withObject:msgDict afterDelay:delay];
}


- (void) addDelayedMessage:(NSDictionary *) textdict
{
	NSString *msg = (NSString *)[textdict objectForKey:@"message"];
	if (!msg)
		return;
	int msg_duration = 3;
	if ([textdict objectForKey:@"duration"])
		msg_duration = [(NSNumber *)[textdict objectForKey:@"duration"] intValue];
	[self addMessage:msg forCount:msg_duration];
}


- (void) addMessage:(NSString *) text forCount:(int) count
{
	if (![currentMessage isEqual:text])
	{
	#ifndef GNUSTEP
		PlayerEntity* player = [PlayerEntity sharedPlayer];
		//speech synthesis
		if ([player speech_on])
		{
			NSString* systemName = [self generateSystemName:system_seed];
			NSString* systemSaid = [self generatePhoneticSystemName:system_seed];
			NSString* h_systemName = [self generateSystemName:[player target_system_seed]];
			NSString* h_systemSaid = [self generatePhoneticSystemName:[player target_system_seed]];
			
			NSString *spoken_text = text;
			if(nil != speechArray)
			{
				NSEnumerator *speechEnumerator = [speechArray objectEnumerator];
				NSArray *thePair;
				while (nil != (thePair = (NSArray*) [speechEnumerator nextObject]))
				{
					NSString *original_phrase = (NSString*)[thePair objectAtIndex: 0];
					NSString *replacement_phrase = (NSString*)[thePair objectAtIndex: 1];
					
					spoken_text = [[spoken_text componentsSeparatedByString: original_phrase] componentsJoinedByString: replacement_phrase];
				}
				spoken_text = [[spoken_text componentsSeparatedByString: systemName] componentsJoinedByString: systemSaid];
				spoken_text = [[spoken_text componentsSeparatedByString: h_systemName] componentsJoinedByString: h_systemSaid];
			}

			if ([self isSpeaking])
				[self stopSpeaking];
			[self startSpeakingString:spoken_text];
			
		}
	#endif	// !def GNUSTEP
		
		[message_gui printLongText:text Align:GUI_ALIGN_CENTER Color:[OOColor yellowColor] FadeTime:(float)count Key:nil AddToArray:nil];
		
		if (currentMessage)	[currentMessage release];
		currentMessage = [text retain];
    }
}


- (void) addCommsMessage:(NSString *) text forCount:(int) count
{
	if (![currentMessage isEqual:text])
    {
		PlayerEntity* player = [PlayerEntity sharedPlayer];
		
		if ([player speech_on])
		{
			if ([self isSpeaking])
				[self stopSpeaking];
			[self startSpeakingString:@"Incoming message."];
		}
		
		[message_gui printLongText:text Align:GUI_ALIGN_CENTER Color:[OOColor greenColor] FadeTime:(float)count Key:nil AddToArray:nil];
		
		[comm_log_gui printLongText:text Align:GUI_ALIGN_LEFT Color:nil FadeTime:0.0 Key:nil AddToArray:[player comm_log]];
		[comm_log_gui setAlpha:1.0];
		[comm_log_gui fadeOutFromTime:[self getTime] OverDuration:6.0];
		
		if (currentMessage)	[currentMessage release];
		currentMessage = [text retain];
    }
}


- (void) showCommsLog:(double) how_long
{
	[comm_log_gui setAlpha:1.0];
	[comm_log_gui fadeOutFromTime:[self getTime] OverDuration:how_long];
}


- (void) update:(double) delta_t
{
    if (!no_update)
	{
		NSString * volatile update_stage = @"initialisation";
		NS_DURING
			int i;
			PlayerEntity*	player = [PlayerEntity sharedPlayer];
			int				ent_count = n_entities;
			Entity*			my_entities[ent_count];
			BOOL			inGUIMode = [player showDemoShips];
			
			sky_clear_color[0] = 0.0;
			sky_clear_color[1] = 0.0;
			sky_clear_color[2] = 0.0;
			sky_clear_color[3] = 0.0;
			
			// use a retained copy so this can't be changed under us.
			for (i = 0; i < ent_count; i++)
				my_entities[i] = [sortedEntities[i] retain];	// explicitly retain each one
			
			time_delta = delta_t;
			universal_time += delta_t;
			
			update_stage = @"demo management";
			if ((demo_stage)&&(player)&&(inGUIMode)&&(universal_time > demo_stage_time)&&([player guiScreen] == GUI_SCREEN_INTRO2))
			{
				if (ent_count > 1)
				{
					Vector		vel;
					Quaternion	q2 = kIdentityQuaternion;
					
					quaternion_rotate_about_y(&q2,M_PI);
					
					#define DEMO2_VANISHING_DISTANCE	400.0
					
					switch (demo_stage)
					{
						case DEMO_FLY_IN:
							[demo_ship setVelocity:kZeroVector];
							[demo_ship setPosition:[demo_ship destination]];	// ideal position
							demo_stage = DEMO_SHOW_THING;
							demo_stage_time = universal_time + 6.0;
							break;
						case DEMO_SHOW_THING:
							vel = make_vector(0, 0, DEMO2_VANISHING_DISTANCE * demo_ship->collision_radius);
							[demo_ship setVelocity:vel];
							demo_stage = DEMO_FLY_OUT;
							demo_stage_time = universal_time + 1.5;
							break;
						case DEMO_FLY_OUT:
							// change the demo_ship here
							[self removeEntity:demo_ship];
							demo_ship = nil;
							
							NSString		*shipDesc = nil;
							NSDictionary	*shipDict = nil;
							
							demo_ship_index = (demo_ship_index + 1) % [demo_ships count];
							shipDesc = [demo_ships objectAtIndex:demo_ship_index];
							
							if ([shipDesc isKindOfClass:[NSString class]])
							{
								shipDict = [self getDictionaryForShip:shipDesc];
								if (shipDict)
								{
									// Failure means we don't change demo_stage, so we'll automatically try again.
									demo_ship = [[ShipEntity alloc] initWithDictionary:shipDict];
								}
							}
							
							if (demo_ship != nil)
							{
								[self addEntity:demo_ship];
								[[demo_ship getAI] setStateMachine:@"nullAI.plist"];
								[demo_ship setOrientation:q2];
								[demo_ship setPositionX:0.0f y:0.0f z:DEMO2_VANISHING_DISTANCE * demo_ship->collision_radius];
								[demo_ship setDestination: make_vector(0.0f, 0.0f, DEMO2_VANISHING_DISTANCE * 0.01f * demo_ship->collision_radius)];	// ideal position
								vel = make_vector(0, 0, -DEMO2_VANISHING_DISTANCE * demo_ship->collision_radius);
								[demo_ship setVelocity:vel];
								[demo_ship setScanClass: CLASS_NO_DRAW];
								[demo_ship setRoll:M_PI/5.0];
								[demo_ship setPitch:M_PI/10.0];
								[gui setText:[demo_ship name] forRow:19 align:GUI_ALIGN_CENTER];
								
								demo_stage = DEMO_FLY_IN;
								demo_stage_time = universal_time + 1.5;
							}
							break;
					}
				}
			}
						
			
			update_stage = @"update:entity";
			for (i = 0; i < ent_count; i++)
			{
				Entity *thing = my_entities[i];
				
				[thing update:delta_t];
				
				// maintain sorted lists
				
				double z_distance = thing->zero_distance;
				
				// zero_index first..
				int index = thing->zero_index;
				while ((index > 0)&&(z_distance < sortedEntities[index - 1]->zero_distance))
				{
					sortedEntities[index] = sortedEntities[index - 1];	// bubble up the list, usually by just one position
					sortedEntities[index - 1 ] = thing;
					thing->zero_index = index - 1;
					sortedEntities[index]->zero_index = index;
					index--;
				}
				
				// done maintaining sorted lists
				
				// update deterministic AI
				
				if (thing->isShip)
				{
					AI* theShipsAI = [(ShipEntity *)thing getAI];
					if (theShipsAI)
					{
						double thinkTime = [theShipsAI nextThinkTime];
						if ((universal_time > thinkTime)||(thinkTime == 0.0))
						{
							[theShipsAI setNextThinkTime:universal_time + [theShipsAI thinkTimeInterval]];
							[theShipsAI think];
						}
					}
				}
				
				////
			}
			
			update_stage = @"updating linked lists";
			for (i = 0; i < ent_count; i++)
				[my_entities[i] updateLinkedLists];
			
			
			// detect collisions and light ships that can see the sun
			
			update_stage = @"collision and shadow detection";
			[self filterSortedLists];
			[self findCollisionsAndShadows];
			
			// do any required check and maintenance of linked lists
			
			if (doLinkedListMaintenanceThisUpdate)
			{
				MaintainLinkedLists(self);
				doLinkedListMaintenanceThisUpdate = NO;
			}
			
			// dispose of the non-mutable copy and everything it references neatly
			
			update_stage = @"clean up";
			for (i = 0; i < ent_count; i++)
				[my_entities[i] release];	// explicitly release each one

		NS_HANDLER
			if ([[localException name] hasPrefix:@"Oolite"])
				[self handleOoliteException:localException];
			else
			{
				OOLog(kOOLogException, @"***** Exception during during %@ in [Universe update:] : %@ : %@ *****", update_stage, [localException name], [localException reason]);
				[localException raise];
			}
		NS_ENDHANDLER
	}
}


- (void) filterSortedLists
{
	Entity	*e0, *next;
	GLfloat start, finish, next_start, next_finish;
	
	// using the z_list - set or clear collisionTestFilter and clear collision_chain
	e0 = z_list_start;
	while (e0)
	{
		e0->collisionTestFilter = (![e0 canCollide]);
		e0->collision_chain = nil;
		e0 = e0->z_next;
	}
	// done.
	
	// start with the z_list
	e0 = z_list_start;
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.z - e0->collision_radius;
		finish = start + 2.0f * e0->collision_radius;
		next = e0->z_next;
		while ((next)&&(next->collisionTestFilter))	// next has been eliminated from the list of possible colliders - so skip it
			next = next->z_next;
		if (next)
		{
			next_start = next->position.z - next->collision_radius;
			if (next_start < finish)
			{
				// e0 and next overlap
				while ((next)&&(next_start < finish))
				{
					// skip forward to the next gap or the end of the list
					next_finish = next_start + 2.0f * next->collision_radius;
					if (next_finish > finish)
						finish = next_finish;
					e0 = next;
					next = e0->z_next;
					while ((next)&&(next->collisionTestFilter))	// next has been eliminated - so skip it
						next = next->z_next;
					if (next)
						next_start = next->position.z - next->collision_radius;
				}
				// now either (next == nil) or (next_start >= finish)-which would imply a gap!
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter = YES;
			}
		}
		else // (next == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter = YES;
		}
		e0 = next;
	}
	// done! list filtered
	
	// then with the y_list, z_list singletons now create more gaps..
	e0 = y_list_start;
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.y - e0->collision_radius;
		finish = start + 2.0f * e0->collision_radius;
		next = e0->y_next;
		while ((next)&&(next->collisionTestFilter))	// next has been eliminated from the list of possible colliders - so skip it
			next = next->y_next;
		if (next)
		{

			next_start = next->position.y - next->collision_radius;
			if (next_start < finish)
			{
				// e0 and next overlap
				while ((next)&&(next_start < finish))
				{
					// skip forward to the next gap or the end of the list
					next_finish = next_start + 2.0f * next->collision_radius;
					if (next_finish > finish)
						finish = next_finish;
					e0 = next;
					next = e0->y_next;
					while ((next)&&(next->collisionTestFilter))	// next has been eliminated - so skip it
						next = next->y_next;
					if (next)
						next_start = next->position.y - next->collision_radius;
				}
				// now either (next == nil) or (next_start >= finish)-which would imply a gap!
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter = YES;
			}
		}
		else // (next == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter = YES;
		}
		e0 = next;
	}
	// done! list filtered
	
	// finish with the x_list
	e0 = x_list_start;
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.x - e0->collision_radius;
		finish = start + 2.0f * e0->collision_radius;
		next = e0->x_next;
		while ((next)&&(next->collisionTestFilter))	// next has been eliminated from the list of possible colliders - so skip it
			next = next->x_next;
		if (next)
		{
			next_start = next->position.x - next->collision_radius;
			if (next_start < finish)
			{
				// e0 and next overlap
				while ((next)&&(next_start < finish))
				{
					// skip forward to the next gap or the end of the list
					next_finish = next_start + 2.0f * next->collision_radius;
					if (next_finish > finish)
						finish = next_finish;
					e0 = next;
					next = e0->x_next;
					while ((next)&&(next->collisionTestFilter))	// next has been eliminated - so skip it
						next = next->x_next;
					if (next)
						next_start = next->position.x - next->collision_radius;
				}
				// now either (next == nil) or (next_start >= finish)-which would imply a gap!
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter = YES;
			}
		}
		else // (next == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter = YES;
		}
		e0 = next;
	}
	// done! list filtered
	
	// repeat the y_list - so gaps from the x_list influence singletons
	e0 = y_list_start;
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.y - e0->collision_radius;
		finish = start + 2.0f * e0->collision_radius;
		next = e0->y_next;
		while ((next)&&(next->collisionTestFilter))	// next has been eliminated from the list of possible colliders - so skip it
			next = next->y_next;
		if (next)
		{

			next_start = next->position.y - next->collision_radius;
			if (next_start < finish)
			{
				// e0 and next overlap
				while ((next)&&(next_start < finish))
				{
					// skip forward to the next gap or the end of the list
					next_finish = next_start + 2.0f * next->collision_radius;
					if (next_finish > finish)
						finish = next_finish;
					e0 = next;
					next = e0->y_next;
					while ((next)&&(next->collisionTestFilter))	// next has been eliminated - so skip it
						next = next->y_next;
					if (next)
						next_start = next->position.y - next->collision_radius;
				}
				// now either (next == nil) or (next_start >= finish)-which would imply a gap!
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter = YES;
			}
		}
		else // (next == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter = YES;
		}
		e0 = next;
	}
	// done! list filtered
	
	// finally, repeat the z_list - this time building collision chains...
	e0 = z_list_start;
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.z - e0->collision_radius;
		finish = start + 2.0f * e0->collision_radius;
		next = e0->z_next;
		while ((next)&&(next->collisionTestFilter))	// next has been eliminated from the list of possible colliders - so skip it
			next = next->z_next;
		if (next)
		{

			next_start = next->position.z - next->collision_radius;
			if (next_start < finish)
			{
				// e0 and next overlap
				while ((next)&&(next_start < finish))
				{
					// chain e0 to next in collision
					e0->collision_chain = next;
					// skip forward to the next gap or the end of the list
					next_finish = next_start + 2.0f * next->collision_radius;
					if (next_finish > finish)
						finish = next_finish;
					e0 = next;
					next = e0->z_next;
					while ((next)&&(next->collisionTestFilter))	// next has been eliminated - so skip it
						next = next->z_next;
					if (next)
						next_start = next->position.z - next->collision_radius;
				}
				// now either (next == nil) or (next_start >= finish)-which would imply a gap!
				e0->collision_chain = nil;	// end the collision chain
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter = YES;
			}
		}
		else // (next == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter = YES;
		}
		e0 = next;
	}
	// done! list filtered
}


- (void) setGalaxy_seed:(Random_Seed) gal_seed
{
	int						i;
	Random_Seed				g_seed = gal_seed;
	NSAutoreleasePool		*pool = nil;

	if (!equal_seeds(galaxy_seed, gal_seed)) {
		galaxy_seed = gal_seed;
	
		// systems
		for (i = 0; i < 256; i++)
		{
			pool = [[NSAutoreleasePool alloc] init];
			
			systems[i] = g_seed;
			if (system_names[i])	[system_names[i] release];
			system_names[i] = [[self getSystemName:g_seed] retain];
			rotate_seed(&g_seed);
			rotate_seed(&g_seed);
			rotate_seed(&g_seed);
			rotate_seed(&g_seed);
			
			[pool release];
		}
	}
}


- (void) setSystemTo:(Random_Seed) s_seed
{
	NSDictionary*   systemData;
	PlayerEntity*   player = [PlayerEntity sharedPlayer];
	
	[self setGalaxy_seed: [player galaxy_seed]];

	system_seed = s_seed;
	target_system_seed = s_seed;
	
	systemData =		[[self generateSystemData:target_system_seed] retain];  // retained
	int economy =		[(NSNumber *)[systemData objectForKey:KEY_ECONOMY] intValue];
	
	[self generateEconomicDataWithEconomy:economy andRandomFactor:([player random_factor] ^ station)&0xff];
	
	[systemData release];   // released
}


- (Random_Seed) systemSeed
{
	return system_seed;
}


- (Random_Seed) systemSeedForSystemNumber:(int) n
{
	return systems[n & 0xff];
}


- (Random_Seed) systemSeedForSystemName:(NSString*) sysname
{
	int i;
	NSString *pname = [[sysname lowercaseString] capitalizedString];
	for (i = 0; i < 256; i++)
	{
		if ([pname isEqual:[self getSystemName: systems[i]]])
			return systems[i];
	}
	OOLog(kOOLogScriptNoSystemForName, @"SCRIPT ERROR could not find a system with the name '%@' in this galaxy", sysname);
	return kNilRandomSeed;
}


- (NSDictionary *) shipyard
{
	return shipyard;
}


- (NSDictionary *) descriptions
{
	return descriptions;
}


- (NSDictionary *) characters
{
	return characters;
}


- (NSDictionary *) missiontext
{
	return missiontext;
}


- (NSString *)descriptionForKey:(NSString *)key
{
	return [descriptions stringForKey:key];
}


- (NSString *) keyForPlanetOverridesForSystemSeed:(Random_Seed) s_seed inGalaxySeed:(Random_Seed) g_seed
{
	Random_Seed g0 = {0x4a, 0x5a, 0x48, 0x02, 0x53, 0xb7};
	int pnum = [self findSystemNumberAtCoords:NSMakePoint(s_seed.d,s_seed.b) withGalaxySeed:g_seed];
	int gnum = 0;
	while (((g_seed.a != g0.a)||(g_seed.b != g0.b)||(g_seed.c != g0.c)||(g_seed.d != g0.d)||(g_seed.e != g0.e)||(g_seed.f != g0.f))&&(gnum < 8))
	{
		gnum++;
		g0.a = rotate_byte_left(g0.a);
		g0.b = rotate_byte_left(g0.b);
		g0.c = rotate_byte_left(g0.c);
		g0.d = rotate_byte_left(g0.d);
		g0.e = rotate_byte_left(g0.e);
		g0.f = rotate_byte_left(g0.f);
	}
	return [NSString stringWithFormat:@"%d %d", gnum, pnum];
}


- (NSString *) keyForInterstellarOverridesForSystemSeeds:(Random_Seed) s_seed1 :(Random_Seed) s_seed2 inGalaxySeed:(Random_Seed) g_seed
{
	Random_Seed g0 = {0x4a, 0x5a, 0x48, 0x02, 0x53, 0xb7};
	int pnum1 = [self findSystemNumberAtCoords:NSMakePoint(s_seed1.d,s_seed1.b) withGalaxySeed:g_seed];
	int pnum2 = [self findSystemNumberAtCoords:NSMakePoint(s_seed2.d,s_seed2.b) withGalaxySeed:g_seed];
	if (pnum1 > pnum2)
	{	// swap them
		int t = pnum1;	pnum1 = pnum2;	pnum2 = t;
	}
	int gnum = 0;
	while (((g_seed.a != g0.a)||(g_seed.b != g0.b)||(g_seed.c != g0.c)||(g_seed.d != g0.d)||(g_seed.e != g0.e)||(g_seed.f != g0.f))&&(gnum < 8))
	{
		gnum++;
		g0.a = rotate_byte_left(g0.a);
		g0.b = rotate_byte_left(g0.b);
		g0.c = rotate_byte_left(g0.c);
		g0.d = rotate_byte_left(g0.d);
		g0.e = rotate_byte_left(g0.e);
		g0.f = rotate_byte_left(g0.f);
	}
	return [NSString stringWithFormat:@"interstellar: %d %d %d", gnum, pnum1, pnum2];
}


- (NSDictionary *) generateSystemData:(Random_Seed) s_seed
{
	static NSDictionary	*cachedResult = nil;
	static Random_Seed	cachedSeed = {0};
	
	// Cache hit ratio is over 95% during respawn, about 80% during initial set-up.
	if (EXPECT(cachedResult != nil && equal_seeds(cachedSeed, s_seed)))  return [[cachedResult retain] autorelease];
	
	[cachedResult release];
	cachedResult = nil;
	cachedSeed = s_seed;
	
	NSMutableDictionary* systemdata = [[NSMutableDictionary alloc] initWithCapacity:8];
	
	int government = (s_seed.c / 8) & 7;
	
	int economy = s_seed.b & 7;
	if (government < 2)
		economy = economy | 2;
	
	int techlevel = (economy ^ 7) + (s_seed.d & 3) + (government / 2) + (government & 1);
	
	int population = (techlevel * 4) + government + economy + 1;
	
	int productivity = ((economy ^ 7) + 3) * (government + 4) * population * 8;
	
	int radius = (((s_seed.f & 15) + 11) * 256) + s_seed.d;
	
	NSString *name = [self generateSystemName:s_seed];
	NSString *inhabitants = [self generateSystemInhabitants:s_seed plural:YES];
	NSString *description = DescriptionForSystem(s_seed);
	
	NSString *override_key = [self keyForPlanetOverridesForSystemSeed:s_seed inGalaxySeed:galaxy_seed];
	
	[systemdata setObject:[NSNumber numberWithInt:government]		forKey:KEY_GOVERNMENT];
	[systemdata setObject:[NSNumber numberWithInt:economy]			forKey:KEY_ECONOMY];
	[systemdata setObject:[NSNumber numberWithInt:techlevel]		forKey:KEY_TECHLEVEL];
	[systemdata setObject:[NSNumber numberWithInt:population]		forKey:KEY_POPULATION];
	[systemdata setObject:[NSNumber numberWithInt:productivity]		forKey:KEY_PRODUCTIVITY];
	[systemdata setObject:[NSNumber numberWithInt:radius]			forKey:KEY_RADIUS];
	[systemdata setObject:name			forKey:KEY_NAME];
	[systemdata setObject:inhabitants	forKey:KEY_INHABITANTS];
	[systemdata setObject:description	forKey:KEY_DESCRIPTION];
	
	// check at this point
	// for scripted overrides for this planet
	if ([planetinfo objectForKey:PLANETINFO_UNIVERSAL_KEY])
		[systemdata addEntriesFromDictionary:(NSDictionary *)[planetinfo objectForKey:PLANETINFO_UNIVERSAL_KEY]];
	if ([planetinfo objectForKey:override_key])
		[systemdata addEntriesFromDictionary:(NSDictionary *)[planetinfo objectForKey:override_key]];
	if ([local_planetinfo_overrides objectForKey:override_key])
		[systemdata addEntriesFromDictionary:(NSDictionary *)[local_planetinfo_overrides objectForKey:override_key]];

	cachedResult = [systemdata copy];
	
	return cachedResult;
}


- (NSDictionary *) currentSystemData
{
	return [self generateSystemData:system_seed];
}


- (void) setSystemDataKey:(NSString*) key value:(NSObject*) object
{
	NSString*	override_key = [self keyForPlanetOverridesForSystemSeed:system_seed inGalaxySeed:galaxy_seed];
	
	if ([local_planetinfo_overrides objectForKey:override_key] == nil)
		[local_planetinfo_overrides setObject:[NSMutableDictionary dictionaryWithCapacity:8] forKey:override_key];
	
	NSMutableDictionary*	local_overrides = (NSMutableDictionary*)[local_planetinfo_overrides objectForKey:override_key];
	[local_overrides setObject:object forKey:key];
}


- (void) setSystemDataForGalaxy:(int) gnum planet:(int) pnum key:(NSString*) key value:(NSObject*) object
{
	NSString*	override_key = [NSString stringWithFormat:@"%d %d", gnum, pnum];

	if ([local_planetinfo_overrides objectForKey:override_key] == nil)
		[local_planetinfo_overrides setObject:[NSMutableDictionary dictionaryWithCapacity:8] forKey:override_key];

	NSMutableDictionary*	local_overrides = (NSMutableDictionary*)[local_planetinfo_overrides objectForKey:override_key];
	[local_overrides setObject:object forKey:key];
}


- (NSString *) getSystemName:(Random_Seed) s_seed
{
	NSDictionary	*systemDic =	[self generateSystemData:s_seed];
	NSString		*name =			(NSString *)[systemDic objectForKey:KEY_NAME];
	return [name capitalizedString];
}


- (NSString *) getSystemInhabitants:(Random_Seed) s_seed
{
	NSDictionary	*systemDic =	[self generateSystemData:s_seed];
	NSString		*inhabitants =  (NSString *)[systemDic objectForKey:KEY_INHABITANTS];
	return inhabitants;
}


- (NSString *) generateSystemName:(Random_Seed) s_seed
{
	int i;
		
	NSString*			digrams = [descriptions objectForKey:@"digrams"];
	NSMutableString*	name = [NSMutableString stringWithCapacity:256];
	int size = 4;
	
	if ((s_seed.a & 0x40) == 0)
		size = 3;
	
	for (i = 0; i < size; i++)
	{
		NSString *c1, *c2;
		int x = s_seed.f & 0x1f;
		if (x != 0)
		{
			x += 12;	x *= 2;
			c1 = [digrams substringWithRange:NSMakeRange(x,1)];
			c2 = [digrams substringWithRange:NSMakeRange(x+1,1)];
			[name appendString:c1];
			if (![c2 isEqual:@"'"])		[name appendString:c2];
		}
		rotate_seed(&s_seed);
	}
	
	return [name capitalizedString];
}


- (NSString *) generatePhoneticSystemName:(Random_Seed) s_seed
{
	int i;
		
	NSString*			phonograms = [descriptions objectForKey:@"phonograms"];
	NSMutableString*	name = [NSMutableString stringWithCapacity:256];
	int size = 4;
	
	if ((s_seed.a & 0x40) == 0)
		size = 3;
	
	for (i = 0; i < size; i++)
	{
		NSString *c1;
		int x = s_seed.f & 0x1f;
		if (x != 0)
		{
			x += 12;	x *= 4;
			c1 = [phonograms substringWithRange:NSMakeRange(x,4)];
			[name appendString:c1];
		}
		rotate_seed(&s_seed);
	}
	
	return [NSString stringWithFormat:@"[[inpt PHON]]%@[[inpt TEXT]]", name];
}


- (NSString *) generateSystemInhabitants:(Random_Seed) s_seed plural:(BOOL) plural
{
	NSMutableString* inhabitants= [NSMutableString stringWithCapacity:256];

	if (s_seed.e < 127)
	{
		if (plural)
		{
			// TODO: use plist
			[inhabitants appendString:@"Human Colonials"];
		}
		else
		{
			[inhabitants appendString:@"Human Colonial"];
		}
	}
	else
	{
		int inhab = (s_seed.f / 4) & 7;
		if (inhab < 3)
			[inhabitants appendString:(NSString *)[(NSArray *)[(NSArray *)[descriptions objectForKey:KEY_INHABITANTS] objectAtIndex:0] objectAtIndex:inhab]];
		
		inhab = s_seed.f / 32;
		if (inhab < 6)
		{
			[inhabitants appendString:@" "];
			[inhabitants appendString:(NSString *)[(NSArray *)[(NSArray *)[descriptions objectForKey:KEY_INHABITANTS] objectAtIndex:1] objectAtIndex:inhab]];
		}

		inhab = (s_seed.d ^ s_seed.b) & 7;
		if (inhab < 6)
		{
			[inhabitants appendString:@" "];
			[inhabitants appendString:(NSString *)[(NSArray *)[(NSArray *)[descriptions objectForKey:KEY_INHABITANTS] objectAtIndex:2] objectAtIndex:inhab]];
		}

		inhab = (inhab + (s_seed.f & 3)) & 7;
		[inhabitants appendString:@" "];
		[inhabitants appendString:(NSString *)[(NSArray *)[(NSArray *)[descriptions objectForKey:KEY_INHABITANTS] objectAtIndex:plural ? 4 : 3] objectAtIndex:inhab]];
	}
	
	return inhabitants;
}


- (Random_Seed) findSystemAtCoords:(NSPoint) coords withGalaxySeed:(Random_Seed) gal_seed
{
	if (!equal_seeds(gal_seed, galaxy_seed))
		[self setGalaxy_seed:gal_seed];

	Random_Seed system = gal_seed;
	int distance, dx, dy;
	int i;
    int min_dist = 10000;

	for (i = 0; i < 256; i++)
	{
		dx = abs(coords.x - systems[i].d);
		dy = abs(coords.y - systems[i].b);

		if (dx > dy)
			distance = (dx + dx + dy) / 2;
		else
			distance = (dx + dy + dy) / 2;

		if ((distance == min_dist)&&(coords.y > systems[i].b))	// with coincident systems choose only if ABOVE
		{
			system = systems[i];
		}
		if (distance < min_dist)
		{
			min_dist = distance;
			system = systems[i];
		}
	}

	return system;
}


- (NSArray*) nearbyDestinationsWithinRange:(double) range
{
	Random_Seed here = [self systemSeed];
	int i;
    NSMutableArray* result = [NSMutableArray arrayWithCapacity:16];

	// make list of connected systems
	for (i = 0; i < 256; i++)
	{
		double dist = distanceBetweenPlanetPositions(here.d, here.b, systems[i].d, systems[i].b);
		if ((dist > 0) && (dist <= range) && (dist <= 7.0))	// limit to systems within 7LY
		{
			[result addObject: [NSDictionary dictionaryWithObjectsAndKeys:
				StringFromRandomSeed(systems[i]), @"system_seed",
				[NSNumber numberWithDouble:dist], @"distance",
				[self getSystemName:systems[i]], @"name",
				nil]];
		}
	}
	
	return result;
}


- (Random_Seed) findNeighbouringSystemToCoords:(NSPoint) coords withGalaxySeed:(Random_Seed) gal_seed
{
	if (!equal_seeds(gal_seed, galaxy_seed))
		[self setGalaxy_seed:gal_seed];

	Random_Seed system = gal_seed;
	double distance;
	int n,i,j;
    double min_dist = 10000.0;

	// make list of connected systems
	BOOL connected[256];
	for (i = 0; i < 256; i++)
	   connected[i] = NO;
	connected[0] = YES;			// system zero is always connected (true for galaxies 0..7)
	for (n = 0; n < 3; n++)		//repeat three times for surety
	{
		for (i = 0; i < 256; i++)   // flood fill out from system zero
		{
			for (j = 0; j < 256; j++)
			{
				double dist = distanceBetweenPlanetPositions(systems[i].d, systems[i].b, systems[j].d, systems[j].b);
				if (dist <= 7.0)
				{
					connected[j] |= connected[i];
					connected[i] |= connected[j];
				}
			}
		}
	}
	
	for (i = 0; i < 256; i++)
	{
		distance = distanceBetweenPlanetPositions((int)coords.x, (int)coords.y, systems[i].d, systems[i].b);
		if ((connected[i])&&(distance < min_dist)&&(distance != 0.0))
		{
			min_dist = distance;
			system = systems[i];
		}
	}

	return system;
}


- (Random_Seed) findConnectedSystemAtCoords:(NSPoint) coords withGalaxySeed:(Random_Seed) gal_seed
{
	if (!equal_seeds(gal_seed, galaxy_seed))
		[self setGalaxy_seed:gal_seed];

	Random_Seed system = gal_seed;
	double distance;
	int n,i,j;
    double min_dist = 10000.0;

	// make list of connected systems
	BOOL connected[256];
	for (i = 0; i < 256; i++)
	   connected[i] = NO;
	connected[0] = YES;			// system zero is always connected (true for galaxies 0..7)
	for (n = 0; n < 3; n++)		//repeat three times for surety
	{
		for (i = 0; i < 256; i++)   // flood fill out from system zero
		{
			for (j = 0; j < 256; j++)
			{
				double dist = distanceBetweenPlanetPositions(systems[i].d, systems[i].b, systems[j].d, systems[j].b);
				if (dist <= 7.0)
				{
					connected[j] |= connected[i];
					connected[i] |= connected[j];
				}
			}
		}
	}
	
	for (i = 0; i < 256; i++)
	{
		distance = distanceBetweenPlanetPositions((int)coords.x, (int)coords.y, systems[i].d, systems[i].b);
		if ((connected[i])&&(distance < min_dist))
		{
			min_dist = distance;
			system = systems[i];
		}
	}

	return system;
}


- (int) findSystemNumberAtCoords:(NSPoint) coords withGalaxySeed:(Random_Seed) gal_seed
{
	if (!equal_seeds(gal_seed, galaxy_seed))
		[self setGalaxy_seed:gal_seed];

	int system = NSNotFound;
	int distance, dx, dy;
	int i;
    int min_dist = 10000;

	for (i = 0; i < 256; i++)
	{
		dx = abs(coords.x - systems[i].d);
		dy = abs(coords.y - systems[i].b);

		if (dx > dy)
			distance = (dx + dx + dy) / 2;
		else
			distance = (dx + dy + dy) / 2;

		if (distance < min_dist)
		{
			min_dist = distance;
			system = i;
		}
	}
	return system;
}


- (NSPoint) findSystemCoordinatesWithPrefix:(NSString *) p_fix withGalaxySeed:(Random_Seed) gal_seed
{
	if (!equal_seeds(gal_seed, galaxy_seed))
		[self setGalaxy_seed:gal_seed];

	NSPoint system_coords = NSMakePoint(-1.0,-1.0);
	int i;
	int n_matches = 0;
	int result = -1;
	for (i = 0; i < 256; i++)
	{
		system_found[i] = NO;
		if ([[system_names[i] lowercaseString] hasPrefix:p_fix])
		{
			system_found[i] = ([p_fix length] > 2);
			if (result < 0)
			{
				system_coords.x = systems[i].d;
				system_coords.y = systems[i].b;
				result = i;
			}
			n_matches++;
		}
	}
	if (n_matches == 1)
		system_found[result] = YES;	// no matter how few letters
	
	return system_coords;
}


- (BOOL*) systems_found
{
	return (BOOL*)system_found;
}


- (NSString*) systemNameIndex:(int) index;
{
	return system_names[index & 255];
}


- (NSDictionary *) routeFromSystem:(int) start ToSystem:(int) goal
{
	NSMutableArray*	route = [NSMutableArray arrayWithCapacity:255];
	
	// value checks
	if ((start < 0)||(start > 255)||(goal < 0)||(goal > 255))
		return nil;
	
	// use A* algorithm to determine shortest route
	
	// for this we need the neighbouring (<= 7LY distant) systems
	// listed for each system[]
	
	NSMutableArray* neighbour_systems = [NSMutableArray arrayWithCapacity:256];
	unsigned i;
	for (i = 0; i < 256; i++)
		[neighbour_systems addObject:[self neighboursToSystem:i]];	// each is retained as it goes in
	
	// each node must store these values:
	// g(X) cost_from_start == distance from node to parent_node + g(parent node)
	// h(X) cost_to_goal (heuristic estimate) == distance from node to goal
	// f(X) total_cost_estimate == g(X) + h(X)
	// parent_node
	
	// each node will be stored as a NSDictionary
	
	// two lists of nodes are required:
	// open_nodes (yet to be explored) = a priority list where the next node always has the lowest f(X)
	// closed_nodes (explored)
	
	// the open list will be stored as an NSMutableArray of indices to node_open with additions to the priority queue
	// being inserted into the correct position, a list of pointers also tracks each node
	
	NSMutableArray* open_nodes = [NSMutableArray arrayWithCapacity:256];
	NSDictionary* node_open[256];
	
	// the closed list is a simple array of flags
	
	BOOL node_closed[256];
	
	// initialise the lists:
	for (i = 0; i < 256; i++)
	{
		node_closed[i] = NO;
		node_open[i] = nil;
	}
	
	// initialise the start node
	int location = start;
	double cost_from_start = 0.0;
	double cost_to_goal = distanceBetweenPlanetPositions(systems[start].d, systems[start].b, systems[goal].d, systems[goal].b);
	double total_cost_estimate = cost_from_start + cost_to_goal;
	NSDictionary* parent_node = nil;
	
	NSDictionary* startNode = [NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithInt:location],					@"location",
		[NSNumber numberWithDouble:cost_from_start],		@"cost_from_start",
		[NSNumber numberWithDouble:cost_to_goal],			@"cost_to_goal",
		[NSNumber numberWithDouble:total_cost_estimate],	@"total_cost_estimate",
		NULL];
	
	// push start node on open
	[open_nodes addObject:[NSNumber numberWithInt:start]];
	node_open[start] = startNode;
	
	// process the list until success or failure
	while ([open_nodes count] > 0)
	{
		// pop the node from open list
		location = [(NSNumber*)[open_nodes objectAtIndex:0] intValue];
		
		NSDictionary* node = node_open[location];
		[open_nodes removeObjectAtIndex:0];
				
		cost_from_start =		[(NSNumber*)[node objectForKey:@"cost_from_start"]		doubleValue];
		cost_to_goal =			[(NSNumber*)[node objectForKey:@"cost_to_goal"]			doubleValue];
		total_cost_estimate =	[(NSNumber*)[node objectForKey:@"total_cost_estimate"]	doubleValue];
		parent_node =			(NSDictionary *)[node objectForKey:@"parent_node"];
		
		// if at goal we're done!
		if (location == goal)
		{
			// construct route backwards from this location
			double total_cost = total_cost_estimate;
			while (parent_node)
			{
				[route insertObject:[node objectForKey:@"location"] atIndex:0];
				node = parent_node;
				location =				[(NSNumber*)[node objectForKey:@"location"]				intValue];
				cost_from_start =		[(NSNumber*)[node objectForKey:@"cost_from_start"]		doubleValue];
				cost_to_goal =			[(NSNumber*)[node objectForKey:@"cost_to_goal"]			doubleValue];
				total_cost_estimate =	[(NSNumber*)[node objectForKey:@"total_cost_estimate"]	doubleValue];
				parent_node =			(NSDictionary *)[node objectForKey:@"parent_node"];
			}
			[route insertObject:[NSNumber numberWithInt:start] atIndex:0];
			return [NSDictionary dictionaryWithObjectsAndKeys:
				route,									@"route",
				[NSNumber numberWithDouble:total_cost],	@"distance",
				NULL];	// we're done!
		}
		else
		{
			NSArray* neighbours = (NSArray *)[neighbour_systems objectAtIndex:location];
			
			for (i = 0; i < [neighbours count]; i++)
			{
				int newLocation = [neighbours intAtIndex:i];
				double newCostFromStart = cost_from_start + distanceBetweenPlanetPositions(systems[newLocation].d, systems[newLocation].b, systems[location].d, systems[location].b);
				double newCostToGoal = distanceBetweenPlanetPositions(systems[newLocation].d, systems[newLocation].b, systems[goal].d, systems[goal].b);
				double newTotalCostEstimate = newCostFromStart + newCostToGoal;
				
				// ignore this node if it exists and there's no improvement
				BOOL ignore_node = node_closed[newLocation];
				if (node_open[newLocation])
				{
					if ([(NSNumber*)[node_open[newLocation] objectForKey:@"cost_from_start"] doubleValue] <= newCostFromStart)
						ignore_node = YES;
				}
				if (!ignore_node)
				{
					// store the new or improved information
					NSDictionary* newNode = [NSDictionary dictionaryWithObjectsAndKeys:
						[NSNumber numberWithInt:newLocation],				@"location",
						[NSNumber numberWithDouble:newCostFromStart],		@"cost_from_start",
						[NSNumber numberWithDouble:newCostToGoal],			@"cost_to_goal",
						[NSNumber numberWithDouble:newTotalCostEstimate],	@"total_cost_estimate",
						node,												@"parent_node",
						NULL];
					// remove node from closed list
					node_closed[newLocation] = NO;
					// add node to open list
					node_open[newLocation] = newNode;
					// add node to priority queue
					unsigned p = 0;
					while (p < [open_nodes count])
					{
						NSDictionary* node_ref = node_open[[(NSNumber*)[open_nodes objectAtIndex:p] intValue]];
						if ([node_ref doubleForKey:@"total_cost_estimate"] > newTotalCostEstimate)
						{
							[open_nodes insertObject:[NSNumber numberWithInt:newLocation] atIndex:p];
							p = 99999;
						}
						p++;
					}
					if (p < 256)	// not found a place, add it on the end
						[open_nodes addObject:[NSNumber numberWithInt:newLocation]];
					
				}
			}
		}
		node_closed[location] = YES;
	}
	
	// if we get here, we've failed to find a route
	
	return nil;
}


- (NSArray *) neighboursToSystem: (int) system_number
{
	NSMutableArray *neighbours = [NSMutableArray arrayWithCapacity:32];
	double distance;
	int i;
	for (i = 0; i < 256; i++)
	{
		distance = distanceBetweenPlanetPositions(systems[system_number].d, systems[system_number].b, systems[i].d, systems[i].b);
		if ((distance <= 7.0)&&(i != system_number))
		{
			[neighbours addObject:[NSNumber numberWithInt:i]];
		}
	}
	return neighbours;
}


- (NSMutableDictionary*) local_planetinfo_overrides;
{
	return local_planetinfo_overrides;
}


- (void) setLocal_planetinfo_overrides:(NSDictionary*) dict
{
	if (local_planetinfo_overrides)
		[local_planetinfo_overrides release];
	local_planetinfo_overrides = [[NSMutableDictionary dictionaryWithDictionary:dict] retain];
}


- (NSDictionary*) planetinfo
{
	return planetinfo;
}


- (NSArray *) equipmentdata
{
	return equipmentdata;
}


- (NSDictionary *) commoditylists
{
	return commoditylists;
}


- (NSArray *) commoditydata
{
	return commoditydata;
}


- (BOOL) generateEconomicDataWithEconomy:(int) economy andRandomFactor:(int) random_factor
{
	StationEntity *some_station = [self station];
	NSString *station_roles = [some_station roles];
	if (![commoditylists objectForKey:station_roles])
		station_roles = @"default";

	NSArray *newcommoditydata = [[self commodityDataForEconomy:economy andStation:some_station andRandomFactor:random_factor] retain];
	[commoditydata release];
	commoditydata = newcommoditydata;
	return YES;
}


- (NSArray *) commodityDataForEconomy:(int) economy andStation:(StationEntity *)some_station andRandomFactor:(int) random_factor
{
	NSString *station_roles = [some_station roles];
	
	if ([[self currentSystemData] objectForKey:@"market"])
	{
		station_roles = (NSString*)[[self currentSystemData] objectForKey:@"market"];
	}
	
	if (![commoditylists objectForKey:station_roles])
	{
		station_roles = @"default";
	}
		
	NSMutableArray *ourEconomy = [NSMutableArray arrayWithArray:(NSArray *)[commoditylists objectForKey:station_roles]];
	unsigned i;
	
	for (i = 0; i < [ourEconomy count]; i++)
	{
		NSMutableArray *commodityInfo = [[ourEconomy objectAtIndex:i] mutableCopy];
		
		int base_price =			[commodityInfo intAtIndex:MARKET_BASE_PRICE];
		int eco_adjust_price =		[commodityInfo intAtIndex:MARKET_ECO_ADJUST_PRICE];
		int eco_adjust_quantity =	[commodityInfo intAtIndex:MARKET_ECO_ADJUST_QUANTITY];
		int base_quantity =			[commodityInfo intAtIndex:MARKET_BASE_QUANTITY];
		int mask_price =			[commodityInfo intAtIndex:MARKET_MASK_PRICE];
		int mask_quantity =			[commodityInfo intAtIndex:MARKET_MASK_QUANTITY];
		
		int price =		(base_price + (random_factor & mask_price) + (economy * eco_adjust_price)) & 255;
		int quantity =  (base_quantity + (random_factor & mask_quantity) - (economy * eco_adjust_quantity)) & 255;
		
		if (quantity > 127) quantity = 0;
		quantity &= 63;
		
		[commodityInfo replaceObjectAtIndex:MARKET_PRICE withObject:[NSNumber numberWithInt:price * 4]];
		[commodityInfo replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:quantity]];
		
		[ourEconomy replaceObjectAtIndex:i withObject:[NSArray arrayWithArray:commodityInfo]];
		[commodityInfo release];	// release, done
	}
		
	return [NSArray arrayWithArray:ourEconomy];
}


double estimatedTimeForJourney(double distance, int hops)
{
	int min_hops = (hops > 1)? (hops - 1) : 1;
	return 2000 * hops + 4000 * distance * distance / min_hops;
}


- (NSArray *) passengersForSystem:(Random_Seed) s_seed atTime:(double) current_time
{
	PlayerEntity* player = [PlayerEntity sharedPlayer];
	
	int player_repute = [player passengerReputation];
	
	int random_factor = current_time;
	random_factor = (random_factor >> 24) &0xff;
	
	// passenger departure time is generated by passenger_seed.a << 16 + passenger_seed.b << 8 + passenger_seed.c
	// added to (long)(current_time) & 0xffffffffff000000
	// to give a time somewhen in the 97 days before and after the current_time
	
	int start = [self findSystemNumberAtCoords:NSMakePoint(s_seed.d, s_seed.b) withGalaxySeed:galaxy_seed];
	NSString* native_species = [self generateSystemInhabitants:s_seed plural:NO];
	
	// adjust basic seed by market random factor
	Random_Seed passenger_seed = s_seed;
	passenger_seed.a ^= random_factor;		// XOR
	passenger_seed.b ^= passenger_seed.a;	// XOR
	passenger_seed.c ^= passenger_seed.b;	// XOR
	passenger_seed.d ^= passenger_seed.c;	// XOR
	passenger_seed.e ^= passenger_seed.d;	// XOR
	passenger_seed.f ^= passenger_seed.e;	// XOR
	
	NSMutableArray*	resultArray = [NSMutableArray arrayWithCapacity:255];
	int i = 0;
	
	for (i = 0; i < 256; i++)
	{
		long long reference_time = 0x1000000 * floor(current_time / 0x1000000);

		long long passenger_time = passenger_seed.a * 0x10000 + passenger_seed.b * 0x100 + passenger_seed.c;
		double passenger_departure_time = reference_time + passenger_time;
		
		if (passenger_departure_time < 0)
			passenger_departure_time += 0x1000000;	// roll it around
		
		double days_until_departure = (passenger_departure_time - current_time) / 86400.0;
		
		
		int passenger_destination = passenger_seed.d;	// system number 0..255
		Random_Seed destination_seed = systems[passenger_destination];
		NSDictionary* destinationInfo = [self generateSystemData:destination_seed];
		int destination_government = [(NSNumber*)[destinationInfo objectForKey:KEY_GOVERNMENT] intValue];
		
		int pick_up_factor = destination_government + floor(days_until_departure) - 7;	// lower for anarchies (gov 0)
				
		if ((days_until_departure > 0.0)&&(pick_up_factor <= player_repute)&&(passenger_seed.d != start))
		{
			// determine the passenger's species
			int passenger_species = passenger_seed.f & 3;	// 0-1 native, 2 human colonial, 3 other
			NSString* passenger_species_string = [NSString stringWithString:native_species];
			if (passenger_species == 2)
				passenger_species_string = @"Human Colonial";
			if (passenger_species == 3)
			{
				passenger_species_string = [self generateSystemInhabitants:passenger_seed plural:NO];
			}
			passenger_species_string = [[passenger_species_string lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			
			// determine the passenger's name
			seed_RNG_only_for_planet_description(passenger_seed);
			NSString* passenger_name = [NSString stringWithFormat:@"%@ %@", ExpandDescriptionForSeed(@"%R", passenger_seed), ExpandDescriptionForSeed(@"%R", passenger_seed)];
			if ([passenger_species_string hasPrefix:@"human"])
				passenger_name = [NSString stringWithFormat:@"%@ %@", ExpandDescriptionForSeed(@"%R", passenger_seed), ExpandDescriptionForSeed(@"[nom]", passenger_seed)];
			
			// determine information about the route...
			NSDictionary* routeInfo = [self routeFromSystem:start ToSystem:passenger_destination];
			
			// some routes are impossible!
			if (routeInfo)
			{
				NSString* destination_name = [self generateSystemName:destination_seed];
				
				double route_length = [(NSNumber *)[routeInfo objectForKey:@"distance"] doubleValue];
				int route_hops = [(NSArray *)[routeInfo objectForKey:@"route"] count] - 1;
				
				// 50 cr per hop + 8..15 cr per LY + bonus for low government level of destination
				int fee = route_hops * 50 + route_length * (8 + (passenger_seed.e & 7)) + 5 * (7 - destination_government) * (7 - destination_government);
				
				fee = cunningFee(fee);
				
				// premium = 20% of fee
				int premium = fee * 20 / 100;
				fee -= premium;
				
				// 1hr per LY*LY, + 30 mins per hop
				double passenger_arrival_time = passenger_departure_time + estimatedTimeForJourney(route_length, route_hops); 
				
					
				NSString* long_description = [NSString stringWithFormat:
					@"%@, a %@, wishes to go to %@.",
					passenger_name, passenger_species_string, destination_name];
					
				long_description = [NSString stringWithFormat:
					@"%@ The route is %.1f light years long, a minimum of %d jumps.", long_description,
					route_length, route_hops];
					
				long_description = [NSString stringWithFormat:
					@"%@ You will need to depart within %@, in order to arrive within %@ time.", long_description,
					[self shortTimeDescription:(passenger_departure_time - current_time)], [self shortTimeDescription:(passenger_arrival_time - current_time)]];
				
				long_description = [NSString stringWithFormat:
					@"%@ Will pay %d Cr: %d Cr in advance, and %d Cr on arrival.", long_description,
					premium + fee, premium, fee];
				
				NSDictionary* passenger_info_dictionary = [NSDictionary dictionaryWithObjectsAndKeys:
					passenger_name,											PASSENGER_KEY_NAME,
					destination_name,										PASSENGER_KEY_DESTINATION_NAME,
					[NSNumber numberWithInt:start],							PASSENGER_KEY_START,
					[NSNumber numberWithInt:passenger_destination],			PASSENGER_KEY_DESTINATION,
					long_description,										PASSENGER_KEY_LONG_DESCRIPTION,
					[NSNumber numberWithDouble:passenger_departure_time],	PASSENGER_KEY_DEPARTURE_TIME,
					[NSNumber numberWithDouble:passenger_arrival_time],		PASSENGER_KEY_ARRIVAL_TIME,
					[NSNumber numberWithInt:fee],							PASSENGER_KEY_FEE,
					[NSNumber numberWithInt:premium],						PASSENGER_KEY_PREMIUM,
					NULL];
				
				[resultArray addObject:passenger_info_dictionary];
			}
		}
		
		// next passenger
		rotate_seed(&passenger_seed);
		rotate_seed(&passenger_seed);
		rotate_seed(&passenger_seed);
		rotate_seed(&passenger_seed);
	
	}
	
	return [NSArray arrayWithArray:resultArray];
}


- (NSString *) timeDescription:(double) interval
{
	double r_time = interval;
	NSString* result = @"";
	
	if (r_time > 86400)
	{
		int days = floor(r_time / 86400);
		r_time -= 86400 * days;
		result = [NSString stringWithFormat:@"%@ %d day%@", result, days, (days > 1) ? @"s" : @""];
	}
	if (r_time > 3600)
	{
		int hours = floor(r_time / 3600);
		r_time -= 3600 * hours;
		result = [NSString stringWithFormat:@"%@ %d hour%@", result, hours, (hours > 1) ? @"s" : @""];
	}
	if (r_time > 60)
	{
		int mins = floor(r_time / 60);
		r_time -= 60 * mins;
		result = [NSString stringWithFormat:@"%@ %d minute%@", result, mins, (mins > 1) ? @"s" : @""];
	}
	if (r_time > 0)
	{
		int secs = floor(r_time);
		result = [NSString stringWithFormat:@"%@ %d second%@", result, secs, (secs > 1) ? @"s" : @""];
	}
	return [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}


- (NSString *) shortTimeDescription:(double) interval
{
	double r_time = interval;
	NSString* result = @"";
	int parts = 0;
	
	if (interval <= 0.0)
		return @"no time";
	
	if ((parts < 2)&&(r_time > 86400))
	{
		int days = floor(r_time / 86400);
		r_time -= 86400 * days;
		result = [NSString stringWithFormat:@"%@ %d day%@", result, days, (days > 1) ? @"s" : @""];
		parts++;
	}
	if ((parts < 2)&&(r_time > 3600))
	{
		int hours = floor(r_time / 3600);
		r_time -= 3600 * hours;
		result = [NSString stringWithFormat:@"%@ %d hr%@", result, hours, (hours > 1) ? @"s" : @""];
		parts++;
	}
	if ((parts < 2)&&(r_time > 60))
	{
		int mins = floor(r_time / 60);
		r_time -= 60 * mins;
		result = [NSString stringWithFormat:@"%@ %d min%@", result, mins, (mins > 1) ? @"s" : @""];
		parts++;
	}
	if ((parts < 2)&&(r_time > 0))
	{
		int secs = floor(r_time);
		result = [NSString stringWithFormat:@"%@ %d sec%@", result, secs, (secs > 1) ? @"s" : @""];
		parts++;
	}
	return [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}


- (NSArray *) contractsForSystem:(Random_Seed) s_seed atTime:(double) current_time
{
	PlayerEntity* player = [PlayerEntity sharedPlayer];
	
	int player_repute = [player contractReputation];
	
	int random_factor = current_time;
	random_factor = (random_factor >> 24) &0xff;
	
	// contract departure time is generated by contract_seed.a << 16 + contract_seed.b << 8 + contract_seed.c
	// added to (long)(current_time + 0x800000) & 0xffffffffff000000
	// to give a time somewhen in the 97 days before and after the current_time
	
	int start = [self findSystemNumberAtCoords:NSMakePoint(s_seed.d, s_seed.b) withGalaxySeed:galaxy_seed];
	
	// adjust basic seed by market random factor
	Random_Seed contract_seed = s_seed;
	contract_seed.f ^= random_factor;	// XOR back to front
	contract_seed.e ^= contract_seed.f;	// XOR
	contract_seed.d ^= contract_seed.e;	// XOR
	contract_seed.c ^= contract_seed.d;	// XOR
	contract_seed.b ^= contract_seed.c;	// XOR
	contract_seed.a	^= contract_seed.b;	// XOR
	
	NSMutableArray*	resultArray = [NSMutableArray arrayWithCapacity:255];
	int i = 0;
	
	NSArray* localMarket;
	if ([[self station] localMarket])
		localMarket = [[self station] localMarket];
	else
		localMarket = [[self station] initialiseLocalMarketWithSeed:s_seed andRandomFactor:random_factor];
	
	for (i = 0; i < 256; i++)
	{
		long long reference_time = 0x1000000 * floor(current_time / 0x1000000);
		
		long long contract_time = contract_seed.a * 0x10000 + contract_seed.b * 0x100 + contract_seed.c;
		double contract_departure_time = reference_time + contract_time;
		
		if (contract_departure_time < 0)
			contract_departure_time += 0x1000000; //	wrap around
		
		double days_until_departure = (contract_departure_time - current_time) / 86400.0;
		
		// determine the destination
		int contract_destination = contract_seed.d;	// system number 0..255
		Random_Seed destination_seed = systems[contract_destination];
		
		NSDictionary* destinationInfo = [self generateSystemData:destination_seed];
		int destination_government = [(NSNumber*)[destinationInfo objectForKey:KEY_GOVERNMENT] intValue];
		
		int pick_up_factor = destination_government + floor(days_until_departure) - 7;	// lower for anarchies (gov 0)
						
		if ((days_until_departure > 0.0)&&(pick_up_factor <= player_repute)&&(contract_seed.d != start))
		{			
			int destination_economy = [(NSNumber*)[destinationInfo objectForKey:KEY_ECONOMY] intValue];
			NSArray* destinationMarket = [self commodityDataForEconomy:destination_economy andStation:[self station] andRandomFactor:random_factor];
			
			// now we need a commodity that's both plentiful here and scarce there...
			// build list of goods allocating 0..100 for each based on how
			// much of each quantity there is. Use a ratio of n x 100/64
			int quantities[[localMarket count]];
			int total_quantity = 0;
			unsigned i;
			for (i = 0; i < [localMarket count]; i++)
			{
				// -- plentiful here
				int q = [[localMarket arrayAtIndex:i] intAtIndex:MARKET_QUANTITY];
				if (q < 0)  q = 0;
				if (q > 64) q = 64;
				quantities[i] = q;
				// -- and scarce there
				q = 64 - [[destinationMarket arrayAtIndex:i] intAtIndex:MARKET_QUANTITY];
				if (q < 0)  q = 0;
				if (q > 64) q = 64;
				quantities[i] *= q;	// multiply plentiful factor x scarce factor
				total_quantity += quantities[i];
			}
			int co_type, co_amount, qr, unit;
			
			// seed random number generator
			int super_rand1 = contract_seed.a * 256 * 256 + contract_seed.c * 256 + contract_seed.e;
			int super_rand2 = contract_seed.b * 256 * 256 + contract_seed.d * 256 + contract_seed.f;
			ranrot_srand(super_rand2);
			
			// select a random point in the histogram
			qr = super_rand2 % total_quantity;
						
			co_type = 0;
			while (qr > 0)
			{
				qr -= quantities[co_type++];
			}
			co_type--;
			
			// units
			unit = [self unitsForCommodity:co_type];
			
			if ((unit == UNITS_TONS)||([player contractReputation] == 7))	// only the best reputation gets to carry gold/platinum/jewels
			{
				// how much?...
				co_amount = 0;
				while (co_amount < 30)
					co_amount += (1 + (ranrot_rand() & 31)) * (1 + (ranrot_rand() & 15)) * [self getRandomAmountOfCommodity:co_type];
					
				// calculate a quantity discount
				int discount = 10 + floor (0.1 * co_amount);
				if (discount > 35)
					discount = 35;
				
				int price_per_unit = [(NSNumber *)[(NSArray *)[localMarket objectAtIndex:co_type] objectAtIndex:MARKET_PRICE] intValue] * (100 - discount) / 100 ;
				
				// what is that worth locally
				float local_cargo_value = 0.1 * co_amount * price_per_unit;
				
				// and the mark-up
				float destination_cargo_value = 0.1 * co_amount * [(NSNumber *)[(NSArray *)[destinationMarket objectAtIndex:co_type] objectAtIndex:MARKET_PRICE] intValue] * (200 + discount) / 200 ;
				
				// total profit
				float profit_for_trip = destination_cargo_value - local_cargo_value;
				
				if (profit_for_trip > 100.0)	// overheads!!
				{
					// determine information about the route...
					NSDictionary* routeInfo = [self routeFromSystem:start ToSystem:contract_destination];
					
					// some routes are impossible!
					if (routeInfo)
					{
						NSString* destination_name = [self generateSystemName:destination_seed];
						
						double route_length = [(NSNumber *)[routeInfo objectForKey:@"distance"] doubleValue];
						int route_hops = [(NSArray *)[routeInfo objectForKey:@"route"] count] - 1;
						
						// percentage taken by contracter
						int contractors_share = 90 + destination_government;
						// less 5% per op to a minimum of 10%
						contractors_share -= route_hops * 10;
						if (contractors_share < 10)
							contractors_share = 10;
						int contract_share = 100 - contractors_share;
						
						// what the contract pays
						float fee = profit_for_trip * contract_share / 100;
						
						fee = cunningFee(fee);

						// premium = local price
						float premium = local_cargo_value;
						
						// 1hr per LY*LY, + 30 mins per hop
						double contract_arrival_time = contract_departure_time + estimatedTimeForJourney(route_length, route_hops); 
						
						NSString* long_description = [NSString stringWithFormat:
							@"Deliver a cargo of %@ to %@.",
							[self describeCommodity:co_type amount:co_amount], destination_name];
							
						long_description = [NSString stringWithFormat:
							@"%@ The route is %.1f light years long, a minimum of %d jumps.", long_description,
							route_length, route_hops];
							
						long_description = [NSString stringWithFormat:
							@"%@ You will need to depart within %@, in order to arrive within %@ time.", long_description,
							[self shortTimeDescription:(contract_departure_time - current_time)], [self shortTimeDescription:(contract_arrival_time - current_time)]];
						
						long_description = [NSString stringWithFormat:
							@"%@ The contract will cost you %.1f Cr, and pay a total of %.1f Cr.", long_description,
							premium, premium + fee];

						NSDictionary* contract_info_dictionary = [NSDictionary dictionaryWithObjectsAndKeys:
							[NSString stringWithFormat:@"%06x-%06x", super_rand1, super_rand2 ],CONTRACT_KEY_ID,
							[NSNumber numberWithInt:start],										CONTRACT_KEY_START,
							[NSNumber numberWithInt:contract_destination],						CONTRACT_KEY_DESTINATION,
							destination_name,													CONTRACT_KEY_DESTINATION_NAME,
							[NSNumber numberWithInt:co_type],									CONTRACT_KEY_CARGO_TYPE,
							[NSNumber numberWithInt:co_amount],									CONTRACT_KEY_CARGO_AMOUNT,
							[self describeCommodity:co_type amount:co_amount],					CONTRACT_KEY_CARGO_DESCRIPTION,
							long_description,													CONTRACT_KEY_LONG_DESCRIPTION,
							[NSNumber numberWithDouble:contract_departure_time],				CONTRACT_KEY_DEPARTURE_TIME,
							[NSNumber numberWithDouble:contract_arrival_time],					CONTRACT_KEY_ARRIVAL_TIME,
							[NSNumber numberWithFloat:fee],										CONTRACT_KEY_FEE,
							[NSNumber numberWithFloat:premium],									CONTRACT_KEY_PREMIUM,
							NULL];
						
						[resultArray addObject:contract_info_dictionary];
					}
				}
			}
		}
		
		// next contract
		rotate_seed(&contract_seed);
		rotate_seed(&contract_seed);
		rotate_seed(&contract_seed);
		rotate_seed(&contract_seed);
	
	}
	
	return [NSArray arrayWithArray:resultArray];
}


- (NSArray *) shipsForSaleForSystem:(Random_Seed) s_seed withTL:(int) specialTL atTime:(double) current_time
{
	int random_factor = current_time;
	random_factor = (random_factor >> 24) &0xff;
	
	// ship sold time is generated by ship_seed.a << 16 + ship_seed.b << 8 + ship_seed.c
	// added to (long)(current_time + 0x800000) & 0xffffffffff000000
	// to give a time somewhen in the 97 days before and after the current_time
		
	// adjust basic seed by market random factor
	Random_Seed ship_seed = s_seed;
	ship_seed.f ^= random_factor;	// XOR back to front
	ship_seed.e ^= ship_seed.f;	// XOR
	ship_seed.d ^= ship_seed.e;	// XOR
	ship_seed.c ^= ship_seed.d;	// XOR
	ship_seed.b ^= ship_seed.c;	// XOR
	ship_seed.a	^= ship_seed.b;	// XOR
	
	NSMutableDictionary		*resultDictionary = [NSMutableDictionary dictionary];
	
	float tech_price_boost = (ship_seed.a + ship_seed.b) / 256.0;
	unsigned i;
	
	for (i = 0; i < 256; i++)
	{
		long long reference_time = 0x1000000 * floor(current_time / 0x1000000);
		
		long long c_time = ship_seed.a * 0x10000 + ship_seed.b * 0x100 + ship_seed.c;
		double ship_sold_time = reference_time + c_time;
		
		if (ship_sold_time < 0)
			ship_sold_time += 0x1000000;	// wraparound
		
		double days_until_sale = (ship_sold_time - current_time) / 86400.0;
		
		NSMutableArray* keysForShips = [NSMutableArray arrayWithArray:[shipyard allKeys]];
		unsigned si;
		for (si = 0; si < [keysForShips count]; si++)
		{
			//eliminate any ships that fail a 'conditions test'
			NSString		*key = [keysForShips stringAtIndex: si];
			NSDictionary	*dict = [shipyard dictionaryForKey: key];
			if ([dict objectForKey:@"conditions"])
			{
				PlayerEntity* player = [PlayerEntity sharedPlayer];
				if ((player) && (player->isPlayer) && (![player checkCouplet: dict onEntity: player]))
					[keysForShips removeObjectAtIndex: si--];
			}
		}
		
		
		NSDictionary* systemInfo = [self generateSystemData:system_seed];
		int techlevel = [systemInfo intForKey:KEY_TECHLEVEL];
		
		if (specialTL != NSNotFound)
			techlevel = specialTL;
		
		int ship_index = (ship_seed.d * 0x100 + ship_seed.e) % [keysForShips count];
		
		NSString* ship_key = [keysForShips objectAtIndex:ship_index];
		NSDictionary* ship_info = [shipyard dictionaryForKey:ship_key];
		int ship_techlevel = [ship_info intForKey:KEY_TECHLEVEL];
		
		double chance = 1.0 - pow(1.0 - [ship_info doubleForKey:KEY_CHANCE], techlevel - ship_techlevel);
		
		// seed random number generator
		int super_rand1 = ship_seed.a * 0x10000 + ship_seed.c * 0x100 + ship_seed.e;
		int super_rand2 = ship_seed.b * 0x10000 + ship_seed.d * 0x100 + ship_seed.f;
		ranrot_srand(super_rand2);
		
		NSDictionary* ship_base_dict = nil;
		
		ship_base_dict = [self getDictionaryForShip:ship_key];
		
		if ((days_until_sale > 0.0) && (days_until_sale < 30.0) && (ship_techlevel < techlevel) && (randf() < chance) && (ship_base_dict != nil))
		{			
			NSMutableDictionary* ship_dict = [NSMutableDictionary dictionaryWithDictionary:ship_base_dict];
			NSMutableString* description = [NSMutableString stringWithCapacity:256];
			NSMutableString* short_description = [NSMutableString stringWithCapacity:256];
			int price = [(NSNumber*)[ship_info objectForKey:KEY_PRICE] intValue];
			int base_price = price;
			NSMutableArray* extras = [NSMutableArray arrayWithArray:[(NSDictionary*)[ship_info objectForKey:KEY_STANDARD_EQUIPMENT] objectForKey:KEY_EQUIPMENT_EXTRAS]];
			NSString* fwd_weapon_string = (NSString*)[(NSDictionary*)[ship_info objectForKey:KEY_STANDARD_EQUIPMENT] objectForKey:KEY_EQUIPMENT_FORWARD_WEAPON];
			NSMutableArray* options = [NSMutableArray arrayWithArray:(NSArray*)[ship_info objectForKey:KEY_OPTIONAL_EQUIPMENT]];
			int max_cargo = 0;
			if ([ship_dict objectForKey:@"max_cargo"])
				max_cargo = [(NSNumber*)[ship_dict objectForKey:@"max_cargo"] intValue];

//			// more info for potential purchasers - how to reveal this I'm not yet sure...
//			NSString* brochure_desc = [self brochureDescriptionWithDictionary: ship_dict standardEquipment: extras optionalEquipment: options];
//			NSLog(@"%@ Brochure description : \"%@\"", [ship_dict objectForKey:KEY_NAME], brochure_desc);
			
			[description appendFormat:@"%@:", [ship_dict objectForKey:KEY_NAME]];
			[short_description appendFormat:@"%@:", [ship_dict objectForKey:KEY_NAME]];
			
			
			int fwd_weapon = WEAPON_NONE;
			if ([fwd_weapon_string isEqual:@"EQ_WEAPON_PULSE_LASER"])
				fwd_weapon = WEAPON_PULSE_LASER;
			if ([fwd_weapon_string isEqual:@"EQ_WEAPON_BEAM_LASER"])
				fwd_weapon = WEAPON_BEAM_LASER;
			if ([fwd_weapon_string isEqual:@"EQ_WEAPON_MINING_LASER"])
				fwd_weapon = WEAPON_MINING_LASER;
			if ([fwd_weapon_string isEqual:@"EQ_WEAPON_MILITARY_LASER"])
				fwd_weapon = WEAPON_MILITARY_LASER;
			if ([fwd_weapon_string isEqual:@"EQ_WEAPON_THARGOID_LASER"])
				fwd_weapon = WEAPON_THARGOID_LASER;
			
			int passenger_berths = 0;
			BOOL customised = NO;
			BOOL weapon_customised = NO;
			NSString* fwd_weapon_desc = nil;
			
			NSString* short_extras_string = @" Plus %@.";
			
			// customise the ship
			while ((randf() < chance) && ([options count]))
			{
				chance *= chance;	//decrease the chance of a further customisation
				int option_index = ranrot_rand() % [options count];
				NSString* equipment = (NSString*)[options objectAtIndex:option_index];
				int eq_index = NSNotFound;
				unsigned q;
				for (q = 0; (q < [equipmentdata count])&&(eq_index == NSNotFound) ; q++)
				{
					if ([equipment isEqual:[(NSArray*)[equipmentdata objectAtIndex:q] objectAtIndex:EQUIPMENT_KEY_INDEX]])
						eq_index = q;
				}
				if (eq_index != NSNotFound)
				{
					NSArray* equipment_info = (NSArray*)[equipmentdata objectAtIndex:eq_index];
					int eq_price = [(NSNumber*)[equipment_info objectAtIndex:EQUIPMENT_PRICE_INDEX] intValue] / 10;
					int eq_techlevel = [(NSNumber*)[equipment_info objectAtIndex:EQUIPMENT_TECH_LEVEL_INDEX] intValue];
					NSString* eq_short_desc = (NSString*)[equipment_info objectAtIndex:EQUIPMENT_SHORT_DESC_INDEX];
					NSString* eq_long_desc = (NSString*)[equipment_info objectAtIndex:EQUIPMENT_LONG_DESC_INDEX];
					
					if (eq_techlevel > techlevel)
					{
						// cap maximum tech level
						if (eq_techlevel > 15)
							eq_techlevel = 15;
						// higher tech items are rarer!
						if (randf() * (eq_techlevel - techlevel) < 1.0)
						{
							eq_price *= tech_price_boost + eq_techlevel - techlevel;
						}
						else
						{
							eq_price = 0;	// bar this upgrade
						}
					}
					
					if (eq_price > 0)
					{
						if (![equipment hasPrefix:@"EQ_WEAPON"])
						{
							if ([equipment isEqual:@"EQ_PASSENGER_BERTH"])
							{
								if ((max_cargo >= 5) && (randf() < chance))
								{
									max_cargo -= 5;
									price += eq_price * 90 / 100;
									[extras addObject:equipment];
									if (passenger_berths == 0)
									{
										[description appendFormat:@" Extra XX=NPB=XXPassenger BerthXX=PPB=XX (%@)", [eq_long_desc lowercaseString]];
										[short_description appendFormat:@" Extra XX=NPB=XXPassenger BerthXX=PPB=XX."];
									}
									passenger_berths++;
									customised = YES;
								}
								else
								{
									[options removeObject:equipment];	// remove the option if there's no space left
								}
							}
							else
							{
								price += eq_price * 90 / 100;
								[extras addObject:equipment];
								[description appendFormat:@" Extra %@ (%@)", eq_short_desc, [eq_long_desc lowercaseString]];
								[short_description appendFormat:short_extras_string, eq_short_desc];
								short_extras_string = @" %@.";
								customised = YES;
							}
						}
						else
						{
							int new_weapon = WEAPON_NONE;
							if ([equipment  isEqual:@"EQ_WEAPON_PULSE_LASER"])
								new_weapon = WEAPON_PULSE_LASER;
							if ([equipment  isEqual:@"EQ_WEAPON_BEAM_LASER"])
								new_weapon = WEAPON_BEAM_LASER;
							if ([equipment  isEqual:@"EQ_WEAPON_MINING_LASER"])
								new_weapon = WEAPON_MINING_LASER;
							if ([equipment  isEqual:@"EQ_WEAPON_MILITARY_LASER"])
								new_weapon = WEAPON_MILITARY_LASER;
							if ([equipment  isEqual:@"EQ_WEAPON_THARGOID_LASER"])
								new_weapon = WEAPON_THARGOID_LASER;
							if (new_weapon > fwd_weapon)
							{
								price -= [self getPriceForWeaponSystemWithKey:fwd_weapon_string] * 90 / 1000;	// 90% credits
								price += eq_price * 90 / 100;
								fwd_weapon_string = equipment;
								fwd_weapon = new_weapon;
								[ship_dict setObject:fwd_weapon_string forKey:@"forward_weapon_type"];
								weapon_customised = YES;
								fwd_weapon_desc = eq_short_desc;
							}
						}
					}
				}
				if ([equipment hasSuffix:@"ENERGY_UNIT"])	// remove ALL the energy unit add-ons
				{
					unsigned q;
					for (q = 0; q < [options count]; q++)
					{
						if ([[options objectAtIndex:q] hasSuffix:@"ENERGY_UNIT"])
							[options removeObjectAtIndex:q--];
					}
				}
				else
				{
					if (![equipment isEqual:@"EQ_PASSENGER_BERTH"])	// let this get added multiple times
						[options removeObject:equipment];
				}
			}
			
			if (passenger_berths)
			{
				NSString* npb = (passenger_berths > 1)? [NSString stringWithFormat:@"%d ", passenger_berths] : @"";
				NSString* ppb = (passenger_berths > 1)? @"s" : @"";
				[description replaceOccurrencesOfString:@"XX=NPB=XX" withString:npb options:NSCaseInsensitiveSearch range:NSMakeRange(0, [description length])];
				[description replaceOccurrencesOfString:@"XX=PPB=XX" withString:ppb options:NSCaseInsensitiveSearch range:NSMakeRange(0, [description length])];
				[short_description replaceOccurrencesOfString:@"XX=NPB=XX" withString:npb options:NSCaseInsensitiveSearch range:NSMakeRange(0, [short_description length])];
				[short_description replaceOccurrencesOfString:@"XX=PPB=XX" withString:ppb options:NSCaseInsensitiveSearch range:NSMakeRange(0, [short_description length])];
			}
			
			if (!customised)
			{
				[description appendString:@" Standard customer model."];
				[short_description appendString:@" Standard customer model."];
			}
			
			if (weapon_customised)
			{
				[description appendFormat:@" Forward weapon has been upgraded to a %@.", [fwd_weapon_desc lowercaseString]];
				[short_description appendFormat:@" Forward weapon upgraded to %@.", [fwd_weapon_desc lowercaseString]];
			}
			
			price = base_price + cunningFee(price - base_price);
				
			[description appendFormat:@" Selling price %d Cr.", price];
			[short_description appendFormat:@" Price %d Cr.", price];

			NSString* ship_id = [NSString stringWithFormat:@"%06x-%06x", super_rand1, super_rand2];

			NSDictionary* ship_info_dictionary = [NSDictionary dictionaryWithObjectsAndKeys:
				ship_id,						SHIPYARD_KEY_ID,
				ship_key,						SHIPYARD_KEY_SHIPDATA_KEY,
				ship_dict,						SHIPYARD_KEY_SHIP,
				description,					SHIPYARD_KEY_DESCRIPTION,
				short_description,				KEY_SHORT_DESCRIPTION,
				[NSNumber numberWithInt:price],	SHIPYARD_KEY_PRICE,
				extras,							KEY_EQUIPMENT_EXTRAS,
				NULL];
			
			[resultDictionary setObject:ship_info_dictionary forKey:ship_id];	// should order them fairly randomly
		}
		
		// next contract
		rotate_seed(&ship_seed);
		rotate_seed(&ship_seed);
		rotate_seed(&ship_seed);
		rotate_seed(&ship_seed);
	}
	
	NSMutableArray *resultArray = [[[resultDictionary allValues] mutableCopy] autorelease];
	[resultArray sortUsingFunction:compareName context:nil];
	
	// remove identically priced ships of the same name
	i = 1;
	
	while (i < [resultArray count])
	{
		if (compareName([resultArray objectAtIndex:i - 1], [resultArray objectAtIndex:i], nil) == NSOrderedSame )
		{
			[resultArray removeObjectAtIndex: i];
		}
		else
		{
			i++;
		}
	}
	
	return [NSArray arrayWithArray:resultArray];
}

static NSComparisonResult compareName(NSDictionary *dict1, NSDictionary *dict2, void * context)
{
	NSDictionary	*ship1 = [dict1 objectForKey:SHIPYARD_KEY_SHIP];
	NSDictionary	*ship2 = [dict2 objectForKey:SHIPYARD_KEY_SHIP];
	NSString		*name1 = [ship1 objectForKey:KEY_NAME];
	NSString		*name2 = [ship2 objectForKey:KEY_NAME];
	
	NSComparisonResult result = [name1 compare:name2];
	if (result != NSOrderedSame)
		return result;
	else
		return comparePrice(dict1, dict2, context);
}

static NSComparisonResult comparePrice(NSDictionary *dict1, NSDictionary *dict2, void * context)
{
	NSNumber		*price1 = [dict1 objectForKey:SHIPYARD_KEY_PRICE];
	NSNumber		*price2 = [dict2 objectForKey:SHIPYARD_KEY_PRICE];
	
	return [price1 compare:price2];
}


- (OOCreditsQuantity) tradeInValueForCommanderDictionary:(NSDictionary*) cmdr_dict
{
	OOCreditsQuantity result = 0;
	
	// get basic information about the commander's craft
	
	NSString* cmdr_ship_desc = [cmdr_dict objectForKey:@"ship_desc"];
	int cmdr_fwd_weapon = [[cmdr_dict objectForKey:@"forward_weapon"] intValue];
	int cmdr_fwd_weapon_value = 0;
	int cmdr_other_weapons_value = 0;
	int cmdr_aft_weapon = [[cmdr_dict objectForKey:@"aft_weapon"] intValue];
	int cmdr_port_weapon = [[cmdr_dict objectForKey:@"port_weapon"] intValue];
	int cmdr_starboard_weapon = [[cmdr_dict objectForKey:@"starboard_weapon"] intValue];
	int cmdr_missiles = [[cmdr_dict objectForKey:@"missiles"] intValue];
	int cmdr_missiles_value = cmdr_missiles * [self getPriceForWeaponSystemWithKey:@"EQ_MISSILE"] / 10;
	int cmdr_max_passengers = [[cmdr_dict objectForKey:@"max_passengers"] intValue];
	NSMutableArray* cmdr_extra_equipment = [NSMutableArray arrayWithArray:[[cmdr_dict objectForKey:@"extra_equipment"] allKeys]];
	
	// given the ship model (from cmdr_ship_desc)
	// get the basic information about the standard customer model for that craft
	NSDictionary* shipyard_info = [shipyard objectForKey:cmdr_ship_desc];
	NSDictionary* basic_info = [shipyard_info objectForKey:KEY_STANDARD_EQUIPMENT];
	int base_price = [[shipyard_info objectForKey:SHIPYARD_KEY_PRICE] intValue];
	int base_missiles = [[basic_info objectForKey:KEY_EQUIPMENT_MISSILES] intValue];
	int base_missiles_value = base_missiles * [self getPriceForWeaponSystemWithKey:@"EQ_MISSILE"] / 10;
	NSString* base_fwd_weapon_key = [basic_info objectForKey:KEY_EQUIPMENT_FORWARD_WEAPON];
	int base_weapon_value = [self getPriceForWeaponSystemWithKey:base_fwd_weapon_key] / 10;
	NSArray* base_extra_equipment = [basic_info objectForKey:KEY_EQUIPMENT_EXTRAS];
	
	// work out weapon values
	if (cmdr_fwd_weapon)
	{
		NSString* weapon_key = WeaponTypeToEquipmentString(cmdr_fwd_weapon);
		cmdr_fwd_weapon_value = [self getPriceForWeaponSystemWithKey:weapon_key] / 10;
	}
	if (cmdr_aft_weapon)
	{
		NSString* weapon_key = WeaponTypeToEquipmentString(cmdr_aft_weapon);
		cmdr_other_weapons_value += [self getPriceForWeaponSystemWithKey:weapon_key] / 10;
	}
	if (cmdr_port_weapon)
	{
		NSString* weapon_key = WeaponTypeToEquipmentString(cmdr_port_weapon);
		cmdr_other_weapons_value += [self getPriceForWeaponSystemWithKey:weapon_key] / 10;
	}
	if (cmdr_starboard_weapon)
	{
		NSString* weapon_key = WeaponTypeToEquipmentString(cmdr_starboard_weapon);
		cmdr_other_weapons_value += [self getPriceForWeaponSystemWithKey:weapon_key] / 10;
	}
	
	// remove from cmdr_extra_equipment any items in base_extra_equipment
	unsigned i;
	int j;
	for (i = 0; i < [base_extra_equipment count]; i++)
	{
		NSString* standard_option = [base_extra_equipment objectAtIndex:i];
		for (j = 0; j < (int)[cmdr_extra_equipment count]; j++)
		{
			if ([[cmdr_extra_equipment objectAtIndex:j] isEqual:standard_option])
				[cmdr_extra_equipment removeObjectAtIndex:j--];
			if ((j > 0)&&([[cmdr_extra_equipment objectAtIndex:j] isEqual:@"EQ_PASSENGER_BERTH"]))
				[cmdr_extra_equipment removeObjectAtIndex:j--];
		}
	}
	
	int extra_equipment_value = cmdr_max_passengers * [self getPriceForWeaponSystemWithKey:@"EQ_PASSENGER_BERTH"] / 10;
	for (i = 0; i < [cmdr_extra_equipment count]; i++)
		extra_equipment_value += [self getPriceForWeaponSystemWithKey:[cmdr_extra_equipment stringAtIndex:i]] / 10;
	
	// final reckoning
	result = base_price;
	
	// add on extra weapons - base weapons
	result += cmdr_fwd_weapon_value - base_weapon_value;
	result += cmdr_other_weapons_value;
	
	// add on missile values
	result += cmdr_missiles_value - base_missiles_value;
	
	// add on equipment
	result += extra_equipment_value;
	
	return result;
}


- (NSString*) brochureDescriptionWithDictionary:(NSDictionary*) dict standardEquipment:(NSArray*) extras optionalEquipment:(NSArray*) options
{
	NSMutableArray* mut_extras = [NSMutableArray arrayWithArray:extras];
	NSString* allOptions = [options componentsJoinedByString:@" "];
	
	NSMutableString* desc = [NSMutableString stringWithFormat:@"The %@.", [dict objectForKey: KEY_NAME]];

	// cargo capacity and expansion
	int max_cargo = 0;
	if ([dict objectForKey:@"max_cargo"])
		max_cargo = [(NSNumber*)[dict objectForKey:@"max_cargo"] intValue];
	if (max_cargo)
	{
		int extra_cargo = 15;
		if ([dict objectForKey:@"extra_cargo"])
			extra_cargo = [(NSNumber*)[dict objectForKey:@"extra_cargo"] intValue];
		[desc appendFormat:@" Cargo capacity %dt", max_cargo];
		BOOL canExpand = ([allOptions rangeOfString:@"EQ_CARGO_BAY"].location != NSNotFound);
		if (canExpand)
			[desc appendFormat:@" (expandable to %dt at most starports)", max_cargo + extra_cargo];
		[desc appendString:@"."];
	}

	// speed
	float top_speed = [dict intForKey:@"max_flight_speed"];
	[desc appendFormat:@" Top speed %.3fLS.", 0.001 * top_speed];

	// passenger berths
	if ([mut_extras count])
	{
		unsigned n_berths = 0;
		unsigned i;
		for (i = 0; i < [mut_extras count]; i++)
		{
			NSString* item_key = (NSString*)[mut_extras objectAtIndex:i];
			if ([item_key isEqual:@"EQ_PASSENGER_BERTH"])
			{
				n_berths++;
				[mut_extras removeObjectAtIndex:i--];
			}
		}
		if (n_berths)
		{
			if (n_berths == 1)
				[desc appendString:@" Includes luxury accomodation for a single passenger."];
			else
				[desc appendFormat:@" Includes luxury accomodation for %d passengers.", n_berths];
		}
	}
	
	// standard fittings
	if ([mut_extras count])
	{
		[desc appendString:@"\nComes with"];
		unsigned i, j;
		for (i = 0; i < [mut_extras count]; i++)
		{
			NSString* item_key = (NSString*)[mut_extras objectAtIndex:i];
			NSString* item_desc = nil;
			for (j = 0; ((j < [equipmentdata count])&&(!item_desc)) ; j++)
			{
				NSString*   eq_type			= (NSString *)[(NSArray *)[equipmentdata objectAtIndex:j] objectAtIndex:EQUIPMENT_KEY_INDEX];
				if ([eq_type isEqual: item_key])
					item_desc = (NSString *)[(NSArray *)[equipmentdata objectAtIndex:j] objectAtIndex:EQUIPMENT_SHORT_DESC_INDEX];
			}
			if (item_desc)
			{
				int c = [mut_extras count] - i;
				switch (c)
				{
					case 1:
						[desc appendFormat:@" %@ fitted as standard.", item_desc];
						break;
					case 2:
						[desc appendFormat:@" %@ and", item_desc];
						break;
					default:
						[desc appendFormat:@" %@,", item_desc];
						break;
				}
			}
		}
	}
	
	// optional fittings
	if ([options count])
	{
		[desc appendString:@"\nCan additionally be outfitted with"];
		unsigned i, j;
		for (i = 0; i < [options count]; i++)
		{
			NSString* item_key = (NSString*)[options objectAtIndex:i];
			NSString* item_desc = nil;
			for (j = 0; ((j < [equipmentdata count])&&(!item_desc)) ; j++)
			{
				NSString*   eq_type			= (NSString *)[(NSArray *)[equipmentdata objectAtIndex:j] objectAtIndex:EQUIPMENT_KEY_INDEX];
				if ([eq_type isEqual: item_key])
					item_desc = (NSString *)[(NSArray *)[equipmentdata objectAtIndex:j] objectAtIndex:EQUIPMENT_SHORT_DESC_INDEX];
			}
			if (item_desc)
			{
				int c = [options count] - i;
				switch (c)
				{
					case 1:
						[desc appendFormat:@" %@ at suitably equipped starports.", item_desc];
						break;
					case 2:
						[desc appendFormat:@" %@ and/or", item_desc];
						break;
					default:
						[desc appendFormat:@" %@,", item_desc];
						break;
				}
			}
		}
	}

	return desc;
}


- (Vector) getWitchspaceExitPosition
{
	Vector result;
	seed_RNG_only_for_planet_description(system_seed);

	// new system is hyper-centric : witchspace exit point is origin
	result.x = 0.0;
	result.y = 0.0;
	result.z = 0.0;
	
	result.x += SCANNER_MAX_RANGE*(gen_rnd_number()/256.0 - 0.5);   // offset by a set amount, up to 12.8 km
	result.y += SCANNER_MAX_RANGE*(gen_rnd_number()/256.0 - 0.5);
	result.z += SCANNER_MAX_RANGE*(gen_rnd_number()/256.0 - 0.5);
	
	return result;
}


- (Quaternion) getWitchspaceExitRotation
{
	// this should be fairly close to {0,0,0,1}
	Quaternion q_result;
	seed_RNG_only_for_planet_description(system_seed);

	
	q_result.x = (gen_rnd_number() - 128)/1024.0;
	q_result.y = (gen_rnd_number() - 128)/1024.0;
	q_result.z = (gen_rnd_number() - 128)/1024.0;
	q_result.w = 1.0;
	quaternion_normalize(&q_result);
	
	return q_result;
}


- (Vector) getSunSkimStartPositionForShip:(ShipEntity*) ship
{
	if (!ship)
	{
		OOLog(kOOLogParameterError, @"***** No ship set in Universe getSunSkimStartPositionForShip:");
		return kZeroVector;
	}
	PlanetEntity* the_sun = [self sun];
	// get vector from sun position to ship
	if (!the_sun)
	{
		OOLog(kOOLogInconsistentState, @"***** No sun set in Universe getSunSkimStartPositionForShip:");
		return kZeroVector;
	}
	Vector v0 = the_sun->position;
	Vector v1 = ship->position;
	v1.x -= v0.x;	v1.y -= v0.y;	v1.z -= v0.z;	// vector from sun to ship
	if (v1.x||v1.y||v1.z)
		v1 = unit_vector(&v1);
	else
		v1.z = 1.0;
	double radius = SUN_SKIM_RADIUS_FACTOR * the_sun->collision_radius - 250.0; // 250 m inside the skim radius
	v1.x *= radius;	v1.y *= radius;	v1.z *= radius;
	v1.x += v0.x;	v1.y += v0.y;	v1.z += v0.z;
	
	return v1;
}


- (Vector) getSunSkimEndPositionForShip:(ShipEntity*) ship
{
	PlanetEntity* the_sun = [self sun];
	if (!ship)
	{
		OOLog(kOOLogParameterError, @"***** No ship set in Universe getSunSkimEndPositionForShip:");
		return kZeroVector;
	}
	// get vector from sun position to ship
	if (!the_sun)
	{
		OOLog(kOOLogInconsistentState, @"***** No sun set in Universe getSunSkimEndPositionForShip:");
		return kZeroVector;
	}
	Vector v0 = the_sun->position;
	Vector v1 = ship->position;
	v1.x -= v0.x;	v1.y -= v0.y;	v1.z -= v0.z;
	if (v1.x||v1.y||v1.z)
		v1 = unit_vector(&v1);
	else
		v1.z = 1.0;
	Vector v2 = make_vector(randf()-0.5, randf()-0.5, randf()-0.5);	// random vector
	if (v2.x||v2.y||v2.z)
		v2 = unit_vector(&v2);
	else
		v2.x = 1.0;
	Vector v3 = cross_product(v1, v2);	// random vector at 90 degrees to v1 and v2 (random Vector)
	if (v3.x||v3.y||v3.z)
		v3 = unit_vector(&v3);
	else
		v3.y = 1.0;
	double radius = the_sun->collision_radius * SUN_SKIM_RADIUS_FACTOR - 250.0; // 250 m inside the skim radius
	v1.x *= radius;	v1.y *= radius;	v1.z *= radius;
	v1.x += v0.x;	v1.y += v0.y;	v1.z += v0.z;
	v1.x += 15000 * v3.x;	v1.y += 15000 * v3.y;	v1.z += 15000 * v3.z;	// point 15000m at a tangent to sun from v1
	v1.x -= v0.x;	v1.y -= v0.y;	v1.z -= v0.z;
	if (v1.x||v1.y||v1.z)
		v1 = unit_vector(&v1);
	else
		v1.z = 1.0;
	v1.x *= radius;	v1.y *= radius;	v1.z *= radius;
	v1.x += v0.x;	v1.y += v0.y;	v1.z += v0.z;
	
	return v1;
}


- (NSArray*) listBeaconsWithCode:(NSString*) code
{
	NSMutableArray* result = [NSMutableArray array];
	ShipEntity* beacon = [self firstBeacon];
	while (beacon)
	{
		NSString* beacon_code = [beacon beaconCode];
		OOLog(kOOLogFoundBeacon, @"Beacon: %@ has code %@", beacon, beacon_code);
		if ([beacon_code rangeOfString:code options: NSCaseInsensitiveSearch].location != NSNotFound)
			[result addObject:beacon];
		beacon = (ShipEntity*)[self entityForUniversalID:[beacon nextBeaconID]];
	}
	return [result sortedArrayUsingSelector:@selector(compareBeaconCodeWith:)];
}


- (void) allShipAIsReactToMessage:(NSString*) message
{
	int i;
	int ent_count = n_entities;
	int ship_count = 0;
	ShipEntity* my_ships[ent_count];
	for (i = 0; i < ent_count; i++)
		if (sortedEntities[i]->isShip)
			my_ships[ship_count++] = [sortedEntities[i] retain];	// retained

	for (i = 0; i < ship_count; i++)
	{
		ShipEntity* se = my_ships[i];
		[[se getAI] reactToMessage:message];
		[se release]; //	released
	}
}

///////////////////////////////////////

- (GuiDisplayGen *) gui
{
	return gui;
}


- (GuiDisplayGen *) comm_log_gui
{
	return comm_log_gui;
}


- (GuiDisplayGen *) message_gui
{
	return message_gui;
}


- (void) clearGUIs
{
	[gui clear];
	[message_gui clear];
	[comm_log_gui clear];
	[comm_log_gui printLongText:@"Communications Log" Align:GUI_ALIGN_CENTER Color:[OOColor yellowColor] FadeTime:0 Key:nil AddToArray:nil];
}


- (void) resetCommsLogColor
{
	[comm_log_gui setTextColor:[OOColor whiteColor]];
}


- (void) setDisplayCursor:(BOOL) value
{
	displayCursor = value;
	
#ifdef GNUSTEP
	if ([gameView inFullScreenMode])
	{
		if (displayCursor == YES)
		{
			// *** Is the query actually necessary or meaningful? -- Jens
			if (SDL_ShowCursor(SDL_QUERY) == SDL_DISABLE)
				SDL_ShowCursor(SDL_ENABLE);
		}
		else
		{
			if (SDL_ShowCursor(SDL_QUERY) == SDL_ENABLE)
				SDL_ShowCursor(SDL_DISABLE);
		}
	}
#endif
}


- (BOOL) displayCursor
{
	return displayCursor;
}


- (void) setDisplayText:(BOOL) value
{
	displayGUI = value;
}


- (BOOL) displayGUI
{
	return displayGUI;
}


- (void) setDisplayFPS:(BOOL) value
{
	displayFPS = value;
}


- (BOOL) displayFPS
{
	return displayFPS;
}


- (void) setReducedDetail:(BOOL) value
{
	reducedDetail = value;
}


- (BOOL) reducedDetail
{
	return reducedDetail;
}


- (void) handleOoliteException:(NSException*) ooliteException
{
	if (ooliteException)
	{
		if ([[ooliteException name] isEqual: OOLITE_EXCEPTION_FATAL])
		{
			exception = [ooliteException retain];
			
			PlayerEntity* player = [PlayerEntity sharedPlayer];
			[player setStatus:STATUS_HANDLING_ERROR];
			
			OOLog(kOOLogException, @"***** Handling Fatal : %@ : %@ *****",[exception name], [exception reason]);
			NSString* exception_msg = [NSString stringWithFormat:@"Exception : %@ : %@ Please take a screenshot and/or press esc or Q to quit.", [exception name], [exception reason]];
			[self addMessage:exception_msg forCount:30.0];
			[[self gameController] pause_game];
		}
		else
		{
			OOLog(kOOLogException, @"***** Handling Non-fatal : %@ : %@ *****",[ooliteException name], [ooliteException reason]);
		}
	}
}


// speech routines
//
- (void) startSpeakingString:(NSString *) text
{
#ifndef GNUSTEP
	if ([OOSound respondsToSelector:@selector(masterVolume)])
		[speechSynthesizer startSpeakingString:[NSString stringWithFormat:@"[[volm %.3f]]%@", 0.3333333f * [OOSound masterVolume], text]];
	else
		[speechSynthesizer startSpeakingString:text];
#endif
}
//
- (void) stopSpeaking
{
#ifndef GNUSTEP
	[speechSynthesizer stopSpeaking];
#endif
}
//
- (BOOL) isSpeaking
{
#ifndef GNUSTEP
	return [speechSynthesizer isSpeaking];
#else
	return NO;
#endif
}
//
////

@end
