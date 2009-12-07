/*

Universe.h

Manages a lot of stuff that isn't managed somewhere else.

Oolite
Copyright (C) 2004-2009 Giles C Williams and contributors

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
#import "OOOpenGL.h"
#import "legacy_random.h"
#import "OOMaths.h"
#import "OOColor.h"
#import "OOWeakReference.h"
#import "OOTypes.h"
#import "OOSound.h"


#if OOLITE_ESPEAK
#include <espeak/speak_lib.h>
#endif

@class	GameController, CollisionRegion, MyOpenGLView, GuiDisplayGen,
		Entity, ShipEntity, StationEntity, OOPlanetEntity, OOSunEntity,
		PlayerEntity, OORoleSet;


typedef BOOL (*EntityFilterPredicate)(Entity *entity, void *parameter);


#define CROSSHAIR_SIZE						32.0

enum
{
	MARKET_NAME								= 0,
	MARKET_QUANTITY							= 1,
	MARKET_PRICE							= 2,
	MARKET_BASE_PRICE						= 3,
	MARKET_ECO_ADJUST_PRICE					= 4,
	MARKET_ECO_ADJUST_QUANTITY  			= 5,
	MARKET_BASE_QUANTITY					= 6,
	MARKET_MASK_PRICE						= 7,
	MARKET_MASK_QUANTITY					= 8,
	MARKET_UNITS							= 9
};


enum
{
	EQUIPMENT_TECH_LEVEL_INDEX				= 0,
	EQUIPMENT_PRICE_INDEX					= 1,
	EQUIPMENT_SHORT_DESC_INDEX				= 2,
	EQUIPMENT_KEY_INDEX						= 3,
	EQUIPMENT_LONG_DESC_INDEX				= 4,
	EQUIPMENT_EXTRA_INFO_INDEX				= 5
};


#define MAX_MESSAGES						5

#define PROXIMITY_WARN_DISTANCE				20.0
#define PROXIMITY_WARN_DISTANCE2			(PROXIMITY_WARN_DISTANCE * PROXIMITY_WARN_DISTANCE)
#define PROXIMITY_AVOID_DISTANCE_FACTOR		10.0

#define SUN_SKIM_RADIUS_FACTOR				1.15470053838	// 2 sqrt(3) / 3. Why? I have no idea. -- Ahruman 2009-10-04
#define SUN_SPARKS_RADIUS_FACTOR			2.0

#define KEY_TECHLEVEL						@"techlevel"
#define KEY_ECONOMY							@"economy"
#define KEY_GOVERNMENT						@"government"
#define KEY_POPULATION						@"population"
#define KEY_PRODUCTIVITY					@"productivity"
#define KEY_RADIUS							@"radius"
#define KEY_NAME							@"name"
#define KEY_INHABITANT						@"inhabitant"
#define KEY_INHABITANTS						@"inhabitants"
#define KEY_DESCRIPTION						@"description"
#define KEY_SHORT_DESCRIPTION				@"short_description"

#define KEY_CHANCE							@"chance"
#define KEY_PRICE							@"price"
#define KEY_OPTIONAL_EQUIPMENT				@"optional_equipment"
#define KEY_STANDARD_EQUIPMENT				@"standard_equipment"
#define KEY_EQUIPMENT_MISSILES				@"missiles"
#define KEY_EQUIPMENT_FORWARD_WEAPON		@"forward_weapon_type"
#define KEY_EQUIPMENT_AFT_WEAPON			@"aft_weapon_type"
#define KEY_EQUIPMENT_PORT_WEAPON			@"port_weapon_type"
#define KEY_EQUIPMENT_STARBOARD_WEAPON		@"starboard_weapon_type"
#define KEY_EQUIPMENT_EXTRAS				@"extras"
#define KEY_WEAPON_FACINGS					@"weapon_facings"

#define SHIPYARD_KEY_ID						@"id"
#define SHIPYARD_KEY_SHIPDATA_KEY			@"shipdata_key"
#define SHIPYARD_KEY_SHIP					@"ship"
#define SHIPYARD_KEY_PRICE					@"price"
#define SHIPYARD_KEY_DESCRIPTION			@"description"

#define PLANETINFO_UNIVERSAL_KEY			@"universal"

#define MAX_ENTITY_UID						1000

#define	NUMBER_OF_STRICT_EQUIPMENT_ITEMS	16

#define	UNIVERSE_MAX_ENTITIES				2048

#define OOLITE_EXCEPTION_LOOPING			@"OoliteLoopingException"
#define OOLITE_EXCEPTION_DATA_NOT_FOUND		@"OoliteDataNotFoundException"
#define OOLITE_EXCEPTION_FATAL				@"OoliteFatalException"

#define BILLBOARD_DEPTH						50000.0

#define TIME_ACCELERATION_FACTOR_MIN		0.0625f
#define TIME_ACCELERATION_FACTOR_DEFAULT	1.0f
#define TIME_ACCELERATION_FACTOR_MAX		16.0f


#ifndef OO_LOCALIZATION_TOOLS
#define OO_LOCALIZATION_TOOLS	1
#endif


@interface Universe: OOWeakRefObject
{
@public
	// use a sorted list for drawing and other activities
	Entity					*sortedEntities[UNIVERSE_MAX_ENTITIES];
	unsigned				n_entities;
	
	int						cursor_row;
	
	// collision optimisation sorted lists
	Entity					*x_list_start, *y_list_start, *z_list_start;
	
	GLfloat					stars_ambient[4];
	
@private
	// colors
	GLfloat					sun_diffuse[4];
	GLfloat					sun_specular[4];

	OOViewID				viewDirection;	// read only
	
	OOMatrix				viewMatrix;
	
	GLfloat					airResistanceFactor;
	
	MyOpenGLView			*gameView;
	
	int						next_universal_id;
	Entity					*entity_for_uid[MAX_ENTITY_UID];

	NSMutableArray			*entities;
	
	OOUniversalID			firstBeacon, lastBeacon;
	
	GLfloat					skyClearColor[4];
	
	NSString				*currentMessage;
	OOTimeAbsolute			messageRepeatTime;
	
	GuiDisplayGen			*gui;
	GuiDisplayGen			*message_gui;
	GuiDisplayGen			*comm_log_gui;
	
	BOOL					displayGUI;
	BOOL					displayCursor;
	
	BOOL					autoSaveNow;
	BOOL					autoSave;
	BOOL					wireframeGraphics;
	BOOL					reducedDetail;
	OOShaderSetting			shaderEffectsLevel;
	
	BOOL					displayFPS;		
			
	OOTimeAbsolute			universal_time;
	OOTimeDelta				time_delta;
	
	OOTimeAbsolute			demo_stage_time;
	OOTimeAbsolute			demo_start_time;
	GLfloat					demo_start_z;
	int						demo_stage;
	int						demo_ship_index;
	NSArray					*demo_ships;
	
	GLfloat					sun_center_position[4];
	
	BOOL					dumpCollisionInfo;
	
	NSDictionary			*commodityLists;		// holds data on commodities for various types of station, loaded at initialisation
	NSArray					*commodityData;			// holds data on commodities extracted from commodityLists
	
	NSDictionary			*illegal_goods;			// holds the legal penalty for illicit commodities, loaded at initialisation
	NSDictionary			*descriptions;			// holds descriptive text for lots of stuff, loaded at initialisation
	NSDictionary			*customsounds;			// holds descriptive audio for lots of stuff, loaded at initialisation
	NSDictionary			*characters;			// holds descriptons of characters
	NSDictionary			*planetInfo;			// holds overrides for individual planets, keyed by "g# p#" where g# is the galaxy number 0..7 and p# the planet number 0..255
	NSDictionary			*missiontext;			// holds descriptive text for missions, loaded at initialisation
	NSArray					*equipmentData;			// holds data on available equipment, loaded at initialisation
	NSSet					*pirateVictimRoles;		// Roles listed in pirateVictimRoles.plist.
	NSDictionary			*autoAIMap;				// Default AIs for roles from autoAImap.plist.
	
	Random_Seed				galaxy_seed;
	Random_Seed				system_seed;
	Random_Seed				target_system_seed;
	
	Random_Seed				systems[256];			// hold pregenerated universe info
	NSString				*system_names[256];		// hold pregenerated universe info
	BOOL					system_found[256];		// holds matches for input strings
	
	int						breakPatternCounter;
	
	ShipEntity				*demo_ship;
	
	StationEntity			*cachedStation;
	OOPlanetEntity			*cachedPlanet;
	OOSunEntity				*cachedSun;
	NSMutableArray			*allPlanets;
	
	BOOL					strict;
	
	BOOL					no_update;
	
	float					time_acceleration_factor;
	
	NSMutableDictionary		*localPlanetInfoOverrides;
	
	NSException				*exception;
	
	NSMutableArray			*activeWormholes;
	
	NSMutableArray			*characterPool;
	
	CollisionRegion			*universeRegion;
	
	// check and maintain linked lists occasionally
	BOOL					doLinkedListMaintenanceThisUpdate;
	
	// experimental proc-genned textures
#if ALLOW_PROCEDURAL_PLANETS
	BOOL					doProcedurallyTexturedPlanets;
#endif
	
	NSMutableArray			*entitiesDeadThisUpdate;
	int				framesDoneThisUpdate;
	
#if OOLITE_SPEECH_SYNTH
#if OOLITE_MAC_OS_X
	NSSpeechSynthesizer		*speechSynthesizer;		// use this from OS X 10.3 onwards
#elif OOLITE_ESPEAK
	const espeak_VOICE		**espeak_voices;
	unsigned int			espeak_voice_count;
#endif
	NSArray					*speechArray;
#endif
}

- (id)initWithGameView:(MyOpenGLView *)gameView;

#if ALLOW_PROCEDURAL_PLANETS
- (BOOL) doProcedurallyTexturedPlanets;
- (void) setDoProcedurallyTexturedPlanets:(BOOL) value;
#endif

- (BOOL) strict;
- (void) setStrict:(BOOL) value;
- (void) setStrict:(BOOL)value fromSaveGame: (BOOL)saveGame;

- (void) reinitAndShowDemo:(BOOL)showDemo;


- (int) obj_count;
#ifndef NDEBUG
- (void) obj_dump;
#endif

- (void) sleepytime: (id) thing;

- (void) setUpUniverseFromStation;
- (void) set_up_universe_from_witchspace;
- (void) set_up_universe_from_misjump;
- (void) set_up_witchspace;
- (void) setUpSpace;
- (void) setLighting;
- (OOPlanetEntity *) setUpPlanet;

- (void) populateSpaceFromActiveWormholes;
- (void) populateSpaceFromHyperPoint:(Vector) h1_pos toPlanetPosition:(Vector) p1_pos andSunPosition:(Vector) s1_pos;
- (int)	scatterAsteroidsAt:(Vector) spawnPos withVelocity:(Vector) spawnVel includingRockHermit:(BOOL) spawnHermit;
- (void) addShipWithRole:(NSString *) desc nearRouteOneAt:(double) route_fraction;
- (Vector) coordinatesForPosition:(Vector) pos withCoordinateSystem:(NSString *) system returningScalar:(GLfloat*) my_scalar;
- (NSString *) expressPosition:(Vector) pos inCoordinateSystem:(NSString *) system;
- (Vector) coordinatesFromCoordinateSystemString:(NSString *) system_x_y_z;
- (BOOL) addShipWithRole:(NSString *) desc nearPosition:(Vector) pos withCoordinateSystem:(NSString *) system;
- (BOOL) addShips:(int) howMany withRole:(NSString *) desc atPosition:(Vector) pos withCoordinateSystem:(NSString *) system;
- (BOOL) addShips:(int) howMany withRole:(NSString *) desc nearPosition:(Vector) pos withCoordinateSystem:(NSString *) system;
- (BOOL) addShips:(int) howMany withRole:(NSString *) desc nearPosition:(Vector) pos withCoordinateSystem:(NSString *) system withinRadius:(GLfloat) radius;
- (BOOL) addShips:(int) howMany withRole:(NSString *) desc intoBoundingBox:(BoundingBox) bbox;
- (BOOL) spawnShip:(NSString *) shipdesc;
- (void) witchspaceShipWithPrimaryRole:(NSString *)role;
- (ShipEntity *) spawnShipWithRole:(NSString *) desc near:(Entity *) entity;

- (BOOL) roleIsPirateVictim:(NSString *)role;

- (void) set_up_break_pattern:(Vector) pos quaternion:(Quaternion) q forDocking:(BOOL) forDocking;
- (void) game_over;

- (void) setupIntroFirstGo: (BOOL) justCobra;
- (void) selectIntro2Previous;
- (void) selectIntro2Next;

- (StationEntity *) station;
- (OOPlanetEntity *) planet;
- (OOSunEntity *) sun;
- (NSArray *) planets;	// Note: does not include sun.

// Turn main station into just another station, for blowUpStation.
- (void) unMagicMainStation;

- (void) resetBeacons;
- (ShipEntity *) firstBeacon;
- (ShipEntity *) lastBeacon;
- (void) setNextBeacon:(ShipEntity *) beaconShip;

- (GLfloat *) skyClearColor;
// Note: the alpha value is also air resistance!
- (void) setSkyColorRed:(GLfloat)red green:(GLfloat)green blue:(GLfloat)blue alpha:(GLfloat)alpha;

- (BOOL) breakPatternOver;
- (BOOL) breakPatternHide;

- (ShipEntity *) newShipWithRole:(NSString *)role;		// Selects ship using role weights, applies auto_ai, respects conditions
- (ShipEntity *) newShipWithName:(NSString *)shipKey;	// Does not apply auto_ai or respect conditions

- (NSString *)defaultAIForRole:(NSString *)role;		// autoAImap.plist lookup

- (OOCargoQuantity) maxCargoForShip:(NSString *) desc;

- (OOCreditsQuantity) getEquipmentPriceForKey:(NSString *) eq_key;

- (int) legal_status_of_manifest:(NSArray *)manifest;

- (NSArray *) getContainersOfGoods:(OOCargoQuantity)how_many scarce:(BOOL)scarce;
- (NSArray *) getContainersOfDrugs:(OOCargoQuantity) how_many;
- (NSArray *) getContainersOfCommodity:(NSString*) commodity_name :(OOCargoQuantity) how_many;
- (void) fillCargopodWithRandomCargo:(ShipEntity *)cargopod;

- (OOCargoType) getRandomCommodity;
- (OOCargoQuantity) getRandomAmountOfCommodity:(OOCargoType) co_type;

- (NSArray *) commodityDataForType:(OOCargoType)type;
- (OOCargoType) commodityForName:(NSString *) co_name;
- (NSString *) symbolicNameForCommodity:(OOCargoType) co_type;
- (NSString *) displayNameForCommodity:(OOCargoType) co_type;
- (OOMassUnit) unitsForCommodity:(OOCargoType) co_type;
- (NSString *) describeCommodity:(OOCargoType) co_type amount:(OOCargoQuantity) co_amount;

- (void) setGameView:(MyOpenGLView *)view;
- (MyOpenGLView *) gameView;
- (GameController *) gameController;
- (NSDictionary *) gameSettings;

- (void) drawUniverse;
- (void) drawMessage;

// Used to draw subentities. Should be getting this from camera.
- (OOMatrix) viewMatrix;

- (id) entityForUniversalID:(OOUniversalID)u_id;

- (BOOL) addEntity:(Entity *) entity;
- (BOOL) removeEntity:(Entity *) entity;
- (void) ensureEntityReallyRemoved:(Entity *)entity;
- (void) removeAllEntitiesExceptPlayer:(BOOL) restore;
- (void) removeDemoShips;

- (BOOL) isVectorClearFromEntity:(Entity *) e1 toDistance:(double)dist fromPoint:(Vector) p2;
- (Entity*) hazardOnRouteFromEntity:(Entity *) e1 toDistance:(double)dist fromPoint:(Vector) p2;
- (Vector) getSafeVectorFromEntity:(Entity *) e1 toDistance:(double)dist fromPoint:(Vector) p2;

- (OOUniversalID) getFirstEntityHitByLaserFromEntity:(ShipEntity *)srcEntity inView:(OOViewID)viewdir offset:(Vector)offset rangeFound:(GLfloat*)range_ptr;
- (Entity *) getFirstEntityTargetedByPlayer;

- (NSArray *) getEntitiesWithinRange:(double)range ofEntity:(Entity *)entity;
- (unsigned) countShipsWithRole:(NSString *)role inRange:(double)range ofEntity:(Entity *)entity;
- (unsigned) countShipsWithRole:(NSString *)role;
- (unsigned) countShipsWithPrimaryRole:(NSString *)role inRange:(double)range ofEntity:(Entity *)entity;
- (unsigned) countShipsWithPrimaryRole:(NSString *)role;
- (void) sendShipsWithPrimaryRole:(NSString *)role messageToAI:(NSString *)message;


// General count/search methods. Pass range of -1 and entity of nil to search all of system.
- (unsigned) countEntitiesMatchingPredicate:(EntityFilterPredicate)predicate
								  parameter:(void *)parameter
									inRange:(double)range
								   ofEntity:(Entity *)entity;
- (unsigned) countShipsMatchingPredicate:(EntityFilterPredicate)predicate
							   parameter:(void *)parameter
								 inRange:(double)range
								ofEntity:(Entity *)entity;
- (NSMutableArray *) findEntitiesMatchingPredicate:(EntityFilterPredicate)predicate
										 parameter:(void *)parameter
										   inRange:(double)range
										  ofEntity:(Entity *)entity;
- (id) findOneEntityMatchingPredicate:(EntityFilterPredicate)predicate
							parameter:(void *)parameter;
- (NSMutableArray *) findShipsMatchingPredicate:(EntityFilterPredicate)predicate
									  parameter:(void *)parameter
										inRange:(double)range
									   ofEntity:(Entity *)entity;
- (id) nearestEntityMatchingPredicate:(EntityFilterPredicate)predicate
							parameter:(void *)parameter
					 relativeToEntity:(Entity *)entity;
- (id) nearestShipMatchingPredicate:(EntityFilterPredicate)predicate
						  parameter:(void *)parameter
				   relativeToEntity:(Entity *)entity;


- (OOTimeAbsolute) getTime;
- (OOTimeDelta) getTimeDelta;

- (void) findCollisionsAndShadows;
- (NSString*) collisionDescription;
- (void) dumpCollisions;

- (void) setViewDirection:(OOViewID) vd;
- (OOViewID) viewDirection;

- (NSString *) soundNameForCustomSoundKey:(NSString *)key;

- (void) clearPreviousMessage;
- (void) setMessageGuiBackgroundColor:(OOColor *) some_color;
- (void) displayMessage:(NSString *) text forCount:(OOTimeDelta) count;
- (void) displayCountdownMessage:(NSString *) text forCount:(OOTimeDelta) count;
- (void) addDelayedMessage:(NSString *) text forCount:(OOTimeDelta) count afterDelay:(OOTimeDelta) delay;
- (void) addDelayedMessage:(NSDictionary *) textdict;
- (void) addMessage:(NSString *) text forCount:(OOTimeDelta) count;
- (void) addMessage:(NSString *) text forCount:(OOTimeDelta) count forceDisplay:(BOOL) forceDisplay;
- (void) addCommsMessage:(NSString *) text forCount:(OOTimeDelta) count;
- (void) addCommsMessage:(NSString *) text forCount:(OOTimeDelta) count andShowComms:(BOOL)showComms logOnly:(BOOL)logOnly;
- (void) showCommsLog:(OOTimeDelta) how_long;

- (void) update:(OOTimeDelta)delta_t;

- (float) timeAccelerationFactor;
- (void) setTimeAccelerationFactor:(float)newTimeAccelerationFactor;

- (void) filterSortedLists;

///////////////////////////////////////

- (void) setGalaxy_seed:(Random_Seed) gal_seed;
- (void) setGalaxy_seed:(Random_Seed) gal_seed andReinit:(BOOL) forced;

- (void) setSystemTo:(Random_Seed) s_seed;

- (Random_Seed) systemSeed;
- (Random_Seed) systemSeedForSystemNumber:(OOSystemID) n;
- (Random_Seed) systemSeedForSystemName:(NSString *)sysname;
- (OOSystemID) systemIDForSystemSeed:(Random_Seed)seed;
- (OOSystemID) currentSystemID;

- (NSDictionary *) descriptions;
- (NSDictionary *) characters;
- (NSDictionary *) missiontext;

- (NSString *)descriptionForKey:(NSString *)key;	// String, or random item from array
- (NSString *)descriptionForArrayKey:(NSString *)key index:(unsigned)index;	// Indexed item from array
- (BOOL) descriptionBooleanForKey:(NSString *)key;	// Boolean from descriptions.plist, for configuration.

- (NSString *) keyForPlanetOverridesForSystemSeed:(Random_Seed) s_seed inGalaxySeed:(Random_Seed) g_seed;
- (NSString *) keyForInterstellarOverridesForSystemSeeds:(Random_Seed) s_seed1 :(Random_Seed) s_seed2 inGalaxySeed:(Random_Seed) g_seed;
- (NSDictionary *) generateSystemData:(Random_Seed) system_seed;
- (NSDictionary *) generateSystemData:(Random_Seed) s_seed useCache:(BOOL) useCache;
- (NSDictionary *) currentSystemData;	// Same as generateSystemData:systemSeed unless in interstellar space.
- (BOOL) inInterstellarSpace;

- (void)setObject:(id)object forKey:(NSString *)key forPlanetKey:(NSString *)planetKey;

- (void) setSystemDataKey:(NSString*) key value:(NSObject*) object;
- (void) setSystemDataForGalaxy:(OOGalaxyID) gnum planet:(OOSystemID) pnum key:(NSString *)key value:(id)object;
- (id) getSystemDataForGalaxy:(OOGalaxyID) gnum planet:(OOSystemID) pnum key:(NSString *)key;
- (NSString *) getSystemName:(Random_Seed) s_seed;
- (NSString *) getSystemInhabitants:(Random_Seed) s_seed;
- (NSString *) getSystemInhabitants:(Random_Seed) s_seed plural:(BOOL)plural;
- (NSString *) generateSystemName:(Random_Seed) system_seed;
- (NSString *) generatePhoneticSystemName:(Random_Seed) s_seed;
- (NSString *) generateSystemInhabitants:(Random_Seed) s_seed plural:(BOOL)plural;
- (NSPoint) coordinatesForSystem:(Random_Seed)s_seed;
- (Random_Seed) findSystemAtCoords:(NSPoint) coords withGalaxySeed:(Random_Seed) gal_seed;

- (NSArray*) nearbyDestinationsWithinRange:(double) range;
- (Random_Seed) findNeighbouringSystemToCoords:(NSPoint) coords withGalaxySeed:(Random_Seed) gal_seed;
- (Random_Seed) findConnectedSystemAtCoords:(NSPoint) coords withGalaxySeed:(Random_Seed) gal_seed;
- (int) findSystemNumberAtCoords:(NSPoint) coords withGalaxySeed:(Random_Seed) gal_seed;
- (NSPoint) findSystemCoordinatesWithPrefix:(NSString *) p_fix;
- (NSPoint) findSystemCoordinatesWithPrefix:(NSString *) p_fix exactMatch:(BOOL) exactMatch;
- (BOOL*) systems_found;
- (NSString*) systemNameIndex:(OOSystemID) index;
- (NSDictionary *) routeFromSystem:(OOSystemID) start toSystem:(OOSystemID) goal optimizedBy:(OORouteType) optimizeBy;
- (NSArray *) neighboursToSystem:(OOSystemID) system_number;

- (NSMutableDictionary *) localPlanetInfoOverrides;
- (void) setLocalPlanetInfoOverrides:(NSDictionary*) dict;

- (NSDictionary *) planetInfo;

- (NSArray *) equipmentData;
- (NSDictionary *) commodityLists;
- (NSArray *) commodityData;

- (BOOL) generateEconomicDataWithEconomy:(OOEconomyID) economy andRandomFactor:(int) random_factor;
- (NSArray *) commodityDataForEconomy:(OOEconomyID) economy andStation:(StationEntity *)some_station andRandomFactor:(int) random_factor;

double estimatedTimeForJourney(double distance, int hops);
- (NSString *) timeDescription:(OOTimeDelta) interval;
- (NSString *) shortTimeDescription:(OOTimeDelta) interval;

- (Random_Seed) marketSeed;
- (NSArray *) passengersForSystem:(Random_Seed) s_seed atTime:(OOTimeAbsolute) current_time;
- (NSArray *) contractsForSystem:(Random_Seed) s_seed atTime:(OOTimeAbsolute) current_time;
- (NSArray *) shipsForSaleForSystem:(Random_Seed) s_seed withTL:(OOTechLevelID) specialTL atTime:(OOTimeAbsolute) current_time;

/* Calculate base cost, before depreciation */
- (OOCreditsQuantity) tradeInValueForCommanderDictionary:(NSDictionary*) cmdr_dict;

- (NSString*) brochureDescriptionWithDictionary:(NSDictionary*) dict standardEquipment:(NSArray*) extras optionalEquipment:(NSArray*) options;

- (Vector) getWitchspaceExitPosition;
- (Quaternion) getWitchspaceExitRotation;

- (Vector) getSunSkimStartPositionForShip:(ShipEntity*) ship;
- (Vector) getSunSkimEndPositionForShip:(ShipEntity*) ship;

- (NSArray*) listBeaconsWithCode:(NSString*) code;

- (void) allShipsDoScriptEvent:(NSString*) event andReactToAIMessage:(NSString*) message;

///////////////////////////////////////

- (void) clearGUIs;

- (GuiDisplayGen *) gui;
- (GuiDisplayGen *) comm_log_gui;
- (GuiDisplayGen *) message_gui;

- (void) resetCommsLogColor;

- (void) setDisplayCursor:(BOOL) value;
- (BOOL) displayCursor;

- (void) setDisplayText:(BOOL) value;
- (BOOL) displayGUI;

- (void) setDisplayFPS:(BOOL) value;
- (BOOL) displayFPS;

- (void) setAutoSave:(BOOL) value;
- (BOOL) autoSave;

- (void) setWireframeGraphics:(BOOL) value;
- (BOOL) wireframeGraphics;

- (void) setReducedDetail:(BOOL) value;
- (BOOL) reducedDetail;

- (void) setShaderEffectsLevel:(OOShaderSetting)value;
- (OOShaderSetting) shaderEffectsLevel;
- (BOOL) useShaders;

- (void) handleOoliteException:(NSException*) ooliteException;

- (GLfloat)airResistanceFactor;

// speech routines
//
- (void) startSpeakingString:(NSString *) text;
//
- (void) stopSpeaking;
//
- (BOOL) isSpeaking;
//
#if OOLITE_ESPEAK
- (NSString *) voiceName:(unsigned int) index;
- (unsigned int) voiceNumber:(NSString *) name;
- (unsigned int) nextVoice:(unsigned int) index;
- (unsigned int) prevVoice:(unsigned int) index;
- (unsigned int) setVoice:(unsigned int) index withGenderM:(BOOL) isMale;
#endif
//
////

//autosave 
- (void) setAutoSaveNow:(BOOL) value;
- (BOOL) autoSaveNow;

- (int) framesDoneThisUpdate;
- (void) resetFramesDoneThisUpdate;

@end


/*	Use UNIVERSE to refer to the global universe object.
	The purpose of this is that it makes UNIVERSE essentially a read-only
	global with zero overhead.
*/
extern Universe *gSharedUniverse;
#ifndef NDEBUG
OOINLINE Universe *GetUniverse(void) INLINE_CONST_FUNC;
OOINLINE Universe *GetUniverse(void)
{
	return gSharedUniverse;
}
#define UNIVERSE GetUniverse()
#else
#define UNIVERSE gSharedUniverse	// Just in case the overhead isn't zero. :-p
#endif


// Only for use with string literals, and only for looking up strings.
NSString *DESC_(NSString *key);
NSString *DESC_PLURAL_(NSString *key, int count);
#define DESC(key)	(DESC_(key ""))
#define DESC_PLURAL(key,count)	(DESC_PLURAL_(key, count))


@interface OOSound (OOCustomSounds)

+ (id) soundWithCustomSoundKey:(NSString *)key;
- (id) initWithCustomSoundKey:(NSString *)key;

@end


@interface OOSoundSource (OOCustomSounds)

+ (id) sourceWithCustomSoundKey:(NSString *)key;
- (id) initWithCustomSoundKey:(NSString *)key;

- (void) playCustomSoundWithKey:(NSString *)key;

@end
