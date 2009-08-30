/*

ShipEntity.h

Entity subclass representing a ship, or various other flying things like cargo
pods and stations (a subclass).

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

#import "OOEntityWithDrawable.h"

@class	OOColor, StationEntity, ParticleEntity, PlanetEntity, WormholeEntity,
		AI, Octree, OOMesh, OOScript, OORoleSet, OOShipGroup, OOEquipmentType;

#ifdef OO_BRAIN_AI
@class OOBrain;
#endif


#define MAX_TARGETS						24
#define RAIDER_MAX_CARGO				5
#define MERCHANTMAN_MAX_CARGO			125

#define LAUNCH_DELAY					2.0f

#define PIRATES_PREFER_PLAYER			YES

#define TURRET_MINIMUM_COS				0.20f

#define AFTERBURNER_BURNRATE			0.25f
#define AFTERBURNER_NPC_BURNRATE		1.0f
#define AFTERBURNER_TIME_PER_FUEL		4.0f

#define CLOAKING_DEVICE_ENERGY_RATE		12.8f
#define CLOAKING_DEVICE_MIN_ENERGY		128
#define CLOAKING_DEVICE_START_ENERGY	0.75f

#define MILITARY_JAMMER_ENERGY_RATE		3
#define MILITARY_JAMMER_MIN_ENERGY		128

#define COMBAT_IN_RANGE_FACTOR			0.035f
#define COMBAT_OUT_RANGE_FACTOR			0.500f
#define COMBAT_WEAPON_RANGE_FACTOR		1.200f

#define SHIP_COOLING_FACTOR				1.0f
#define SHIP_INSULATION_FACTOR			0.00175f
#define SHIP_MAX_CABIN_TEMP				256.0f
#define SHIP_MIN_CABIN_TEMP				60.0f
#define EJECTA_TEMP_FACTOR				0.85f		// Ejected items have 85% of parent's temperature
#define DEFAULT_HYPERSPACE_SPIN_TIME	15.0f

#define SUN_TEMPERATURE					1250.0f

#define MAX_ESCORTS						16
#define ESCORT_SPACING_FACTOR			3.0

#define SHIPENTITY_MAX_MISSILES			16

#define TURRET_SHOT_SPEED				2000.0f

#define TRACTOR_FORCE					2500.0f

#define AIMS_AGGRESSOR_SWITCHED_TARGET	@"AGGRESSOR_SWITCHED_TARGET"

// number of vessels considered when scanning around
#define MAX_SCAN_NUMBER					16

#define BASELINE_SHIELD_LEVEL			128.0f			// Max shield level with no boosters.

#define	MIN_FUEL						0				// minimum fuel required for afterburner use

@interface ShipEntity: OOEntityWithDrawable
{
@public
	// derived variables
	OOTimeDelta				shot_time;					// time elapsed since last shot was fired
	
	// navigation
	Vector					v_forward, v_up, v_right;	// unit vectors derived from the direction faced
	
	// variables which are controlled by instincts/AI
	Vector					destination;				// for flying to/from a set point
	OOUniversalID			primaryTarget;				// for combat or rendezvous
	GLfloat					desired_range;				// range to which to journey/scan
	GLfloat					desired_speed;				// speed at which to travel
	OOBehaviour				behaviour;					// ship's behavioural state
	
	BoundingBox				totalBoundingBox;			// records ship configuration
	
@protected
	//set-up
	NSDictionary			*shipinfoDictionary;
	
	Quaternion				subentityRotationalVelocity;
	
	//scripting
	OOScript				*script;
	
	//docking instructions
	NSDictionary			*dockingInstructions;
	
	OOUniversalID			last_escort_target;			// last target an escort was deployed after
	unsigned				found_hostiles;				// number of hostiles found
	
	OOColor					*laser_color;
	
	// per ship-type variables
	//
	GLfloat					maxFlightSpeed;				// top speed			(160.0 for player)  (200.0 for fast raider)
	GLfloat					max_flight_roll;			// maximum roll rate	(2.0 for player)	(3.0 for fast raider)
	GLfloat					max_flight_pitch;			// maximum pitch rate   (1.0 for player)	(1.5 for fast raider) also radians/sec for (* turrets *)
	GLfloat					max_flight_yaw;
	GLfloat					cruiseSpeed;				// 80% of top speed
	
	GLfloat					thrust;						// acceleration
	float					hyperspaceMotorSpinTime;	// duration of hyperspace countdown
	
	// TODO: stick all equipment in a list, and move list from playerEntity to shipEntity. -- Ahruman
	unsigned				military_jammer_active: 1,	// military_jammer
	
							docking_match_rotation: 1,
	
	
							pitching_over: 1,			// set to YES if executing a sharp loop
							reportAIMessages: 1,		// normally NO, suppressing AI message reporting
	
							being_mined: 1,				// normally NO, set to Yes when fired on by mining laser
	
							being_fined: 1,
	
							isHulk: 1,					// This is used to distinguish abandoned ships from cargo
							trackCloseContacts: 1,
	
							isNearPlanetSurface: 1,		// check for landing on planet
							isFrangible: 1,				// frangible => subEntities can be damaged individually
							cloaking_device_active: 1,	// cloaking_device
							cloakPassive: 1,		// cloak deactivates when main weapons or missiles are fired
							canFragment: 1,				// Can it break into wreckage?
							suppressExplosion: 1,		// Avoid exploding on death (script hook)
							suppressAegisMessages: 1,	// No script/AI messages sent by -checkForAegis,
							isMissile: 1,				// Whether this was launched by fireMissile (used to track submunitions).
							isUnpiloted: 1,			// Is meant to not have crew
	
	// scripting
							haveExecutedSpawnAction: 1,
							noRocks: 1;
	
	OOFuelQuantity			fuel;						// witch-space fuel
	GLfloat					fuel_accumulator;
	
	OOCargoQuantity			likely_cargo;				// likely amount of cargo (for merchantmen, this is what is spilled as loot)
	OOCargoQuantity			max_cargo;					// capacity of cargo hold
	OOCargoQuantity			extra_cargo;				// capacity of cargo hold extension (if any)
	OOCargoType				cargo_type;					// if this is scooped, this is indicates contents
	OOCargoFlag				cargo_flag;					// indicates contents for merchantmen
	OOCreditsQuantity		bounty;						// bounty (if any)
	
	GLfloat					energy_recharge_rate;		// recharge rate for energy banks
	
	OOWeaponType			forward_weapon_type;		// type of forward weapon (allows lasers, plasma cannon, others)
	OOWeaponType			aft_weapon_type;			// type of aft weapon (allows lasers, plasma cannon, others)
	GLfloat					weapon_energy;				// energy used/delivered by weapon
	GLfloat					weaponRange;				// range of the weapon (in meters)
	
	GLfloat					scannerRange;				// typically 25600
	
	unsigned				missiles;					// number of on-board missiles
	NSString				*missileRole;
	
#ifdef OO_BRAIN_AI
	OOBrain					*brain;						// brain controlling ship, could be a character brain or the autopilot
#endif
	AI						*shipAI;					// ship's AI system
	
	NSString				*name;						// descriptive name
	NSString				*displayName;					// name shown on screen
	OORoleSet				*roleSet;					// Roles a ship can take, eg. trader, hunter, police, pirate, scavenger &c.
	NSString				*primaryRole;				// "Main" role of the ship.
	
	// AI stuff
	Vector					jink;						// x and y set factors for offsetting a pursuing ship's position
	Vector					coordinates;				// for flying to/from a set point
	Vector					reference;					// a direction vector of magnitude 1 (* turrets *)
	OOUniversalID			primaryAggressor;			// recorded after an attack
	OOUniversalID			targetStation;				// for docking
	OOUniversalID			found_target;				// from scans
	OOUniversalID			target_laser_hit;			// u-id for the entity hit by the last laser shot
	OOUniversalID			owner_id;					// u-id for the controlling owner of this entity (* turrets *)
	double					launch_time;				// time at which launched
	
	GLfloat					frustration,				// degree of dissatisfaction with the current behavioural state, factor used to test this
							success_factor;
	
	int						patrol_counter;				// keeps track of where the ship is along a patrol route
	
	OOUniversalID			proximity_alert;			// id of a ShipEntity within 2x collision_radius
	NSMutableDictionary		*previousCondition;			// restored after collision avoidance
	
	// derived variables
	float					weapon_recharge_rate;		// time between shots
	int						shot_counter;				// number of shots fired
	double					cargo_dump_time;			// time cargo was last dumped
	
	NSMutableArray			*cargo;						// cargo containers go in here

	int						commodity_type;				// type of commodity in a container
	int						commodity_amount;			// 1 if unit is TONNES (0), possibly more if precious metals KILOGRAMS (1)
														// or gem stones GRAMS (2)
	
	// navigation
	GLfloat					flightSpeed;				// current speed
	GLfloat					flightRoll;					// current roll rate
	GLfloat					flightPitch;				// current pitch rate
	GLfloat					flightYaw;					// current yaw rate
	
	float					accuracy;
	float					pitch_tolerance;
	
	OOAegisStatus			aegis_status;				// set to YES when within the station's protective zone

	
	double					messageTime;				// counts down the seconds a radio message is active for
	
	double					next_spark_time;			// time of next spark when throwing sparks
	
	int						thanked_ship_id;			// last ship thanked
	
	Vector					collision_vector;			// direction of colliding thing.
	
	// beacons
	NSString				*beaconCode;
	char					beaconChar;					// character displayed for this beacon
	OOUniversalID			nextBeaconID;				// next beacon in sequence
	
	//position of gun ports
	Vector					forwardWeaponOffset,
							aftWeaponOffset,
							portWeaponOffset,
							starboardWeaponOffset;
	
	// crew (typically one OOCharacter - the pilot)
	NSArray					*crew;
	
	// close contact / collision tracking
	NSMutableDictionary		*closeContactsInfo;
	
	NSString				*lastRadioMessage;
	
	// scooping...
	Vector					tractor_position;
	
	// from player entity moved here now we're doing more complex heat stuff
	float					ship_temperature;
	
	// for advanced scanning etc.
	ShipEntity*				scanned_ships[MAX_SCAN_NUMBER + 1];
	GLfloat					distance2_scanned_ships[MAX_SCAN_NUMBER + 1];
	unsigned				n_scanned_ships;
	
	// advanced navigation
	Vector					navpoints[32];
	unsigned				next_navpoint_index;
	unsigned				number_of_navpoints;
	
	// Collision detection
	Octree					*octree;
	
#ifndef NDEBUG
	// DEBUGGING
	OOBehaviour				debugLastBehaviour;
#endif
	
	uint16_t				entity_personality;			// Per-entity random number. Exposed to shaders and scripts.
	NSDictionary			*scriptInfo;				// script_info dictionary from shipdata.plist, exposed to scripts.
	
	NSMutableArray			*subEntities;
	
@private
	OOWeakReference			*_subEntityTakingDamage;	//	frangible => subEntities can be damaged individually
	
	NSMutableSet			*_equipment;
	float					_heatInsulation;
	
	OOWeakReference			*_lastPlanet;				// remember last aegis planet
	
	OOShipGroup				*_group;
	OOShipGroup				*_escortGroup;
	uint8_t					_maxEscortCount;
	uint8_t					_pendingEscortCount;
}

// ship brains
- (void) setStateMachine:(NSString *) ai_desc;
- (void) setAI:(AI *) ai;
- (AI *) getAI;
- (void) setShipScript:(NSString *) script_name;
- (void) removeScript;
- (OOScript *) shipScript;
- (double) frustration;

- (void) interpretAIMessage:(NSString *)message;

#ifdef OO_BRAIN_AI
- (OOBrain *)brain;
- (void)setBrain:(OOBrain*) aBrain;
#endif

- (OOMesh *)mesh;
- (void)setMesh:(OOMesh *)mesh;

- (NSArray *)subEntities;
- (unsigned) subEntityCount;
- (BOOL) hasSubEntity:(ShipEntity *)sub;

- (NSEnumerator *)subEntityEnumerator;
- (NSEnumerator *)shipSubEntityEnumerator;
- (NSEnumerator *)particleSubEntityEnumerator;
- (NSEnumerator *)flasherEnumerator;
- (NSEnumerator *)exhaustEnumerator;

- (ShipEntity *) subEntityTakingDamage;
- (void) setSubEntityTakingDamage:(ShipEntity *)sub;

- (void) clearSubEntities;	// Releases and clears subentity array, after making sure subentities don't think ship is owner.

// octree collision hunting
- (GLfloat)doesHitLine:(Vector) v0: (Vector) v1;
- (GLfloat)doesHitLine:(Vector) v0: (Vector) v1 :(ShipEntity**) hitEntity;
- (GLfloat)doesHitLine:(Vector) v0: (Vector) v1 withPosition:(Vector) o andIJK:(Vector) i :(Vector) j :(Vector) k;	// for subentities

- (BoundingBox) findBoundingBoxRelativeToPosition:(Vector)opv InVectors:(Vector) _i :(Vector) _j :(Vector) _k;

- (Vector)absoluteTractorPosition;

// beacons
- (NSString *)beaconCode;
- (void)setBeaconCode:(NSString *)bcode;
- (BOOL)isBeacon;
- (char)beaconChar;
- (int)nextBeaconID;
- (void)setNextBeacon:(ShipEntity*) beaconShip;

- (void) setUpEscorts;

- (id)initWithDictionary:(NSDictionary *) dict;
- (BOOL)setUpShipFromDictionary:(NSDictionary *) dict;
- (BOOL)setUpSubEntities:(NSDictionary *) shipDict;
- (NSDictionary *)shipInfoDictionary;

- (void) setDefaultWeaponOffsets;

- (BOOL)isFrangible;

- (void)respondToAttackFrom:(Entity *)from becauseOf:(Entity *)other;

// Equipment
- (BOOL) hasEquipmentItem:(id)equipmentKeys includeWeapons:(BOOL)includeWeapons;	// This can take a string or an set or array of strings. If a collection, returns YES if ship has _any_ of the specified equipment. If includeWeapons is NO, missiles and primary weapons are not checked.
- (BOOL) hasEquipmentItem:(id)equipmentKeys;			// Short for hasEquipmentItem:foo includeWeapons:NO
- (BOOL) hasAllEquipment:(id)equipmentKeys includeWeapons:(BOOL)includeWeapons;		// Like hasEquipmentItem:includeWeapons:, but requires _all_ elements in collection.
- (BOOL) hasAllEquipment:(id)equipmentKeys;				// Short for hasAllEquipment:foo includeWeapons:NO
- (BOOL) canAddEquipment:(NSString *)equipmentKey;		// Test ability to add equipment, taking equipment-specific constriants into account. 
- (BOOL) equipmentValidToAdd:(NSString *)equipmentKey;	// Actual test if equipment satisfies validation criteria.
- (void) addEquipmentItem:(NSString *)equipmentKey;
- (void) addEquipmentItem:(NSString *)equipmentKey withValidation:(BOOL)validateAddition;
/*	NOTE: for legacy reasons, canAddEquipment: returns YES if given a missile
	or mine type, but addEquipmentItem: does nothing in those cases. This
	should probably be cleaned up by making addEquipmentItem: mount stores.
*/
- (NSEnumerator *) equipmentEnumerator;
- (unsigned) equipmentCount;
- (void) removeEquipmentItem:(NSString *)equipmentKey;
- (void) removeAllEquipment;

// Internal, subject to change. Use the methods above instead.
- (BOOL) hasOneEquipmentItem:(NSString *)itemKey includeMissiles:(BOOL)includeMissiles;
- (BOOL) hasPrimaryWeapon:(OOWeaponType)weaponType;
- (void) removeExternalStore:(OOEquipmentType *)eqType;

// Passengers - not supported for NPCs, but interface is here for genericity.
- (unsigned) passengerCount;
- (unsigned) passengerCapacity;

- (unsigned) missileCount;
- (unsigned) missileCapacity;

// Tests for the various special-cased equipment items
- (BOOL) hasScoop;
- (BOOL) hasECM;
- (BOOL) hasCloakingDevice;
- (BOOL) hasMilitaryScannerFilter;
- (BOOL) hasMilitaryJammer;
- (BOOL) hasExpandedCargoBay;
- (BOOL) hasShieldBooster;
- (BOOL) hasMilitaryShieldEnhancer;
- (BOOL) hasHeatShield;
- (BOOL) hasFuelInjection;
- (BOOL) hasEnergyBomb;
- (BOOL) hasEscapePod;
- (BOOL) hasDockingComputer;
- (BOOL) hasGalacticHyperdrive;

// Shield information derived from equipment. NPCs can't have shields, but that should change at some point.
- (float) shieldBoostFactor;
- (float) maxForwardShieldLevel;
- (float) maxAftShieldLevel;
- (float) shieldRechargeRate;

- (float) afterburnerFactor;

// Behaviours
- (void) behaviour_stop_still:(double) delta_t;
- (void) behaviour_idle:(double) delta_t;
- (void) behaviour_tumble:(double) delta_t;
- (void) behaviour_tractored:(double) delta_t;
- (void) behaviour_track_target:(double) delta_t;
- (void) behaviour_intercept_target:(double) delta_t;
- (void) behaviour_attack_target:(double) delta_t;
- (void) behaviour_fly_to_target_six:(double) delta_t;
- (void) behaviour_attack_mining_target:(double) delta_t;
- (void) behaviour_attack_fly_to_target:(double) delta_t;
- (void) behaviour_attack_fly_from_target:(double) delta_t;
- (void) behaviour_running_defense:(double) delta_t;
- (void) behaviour_flee_target:(double) delta_t;
- (void) behaviour_fly_range_from_destination:(double) delta_t;
- (void) behaviour_face_destination:(double) delta_t;
- (void) behaviour_formation_form_up:(double) delta_t;
- (void) behaviour_fly_to_destination:(double) delta_t;
- (void) behaviour_fly_from_destination:(double) delta_t;
- (void) behaviour_avoid_collision:(double) delta_t;
- (void) behaviour_track_as_turret:(double) delta_t;
- (void) behaviour_fly_thru_navpoints:(double) delta_t;


- (void) resetTracking;

- (GLfloat *) scannerDisplayColorForShip:(ShipEntity*)otherShip :(BOOL)isHostile :(BOOL)flash;

- (BOOL)isCloaked;
- (void)setCloaked:(BOOL)cloak;

- (BOOL) isJammingScanning;

- (void) addSubEntity:(Entity *) subent;
- (void) addExhaust:(ParticleEntity *) exhaust;
- (void) addFlasher:(ParticleEntity *) flasher;

- (void) applyThrust:(double) delta_t;

- (void) avoidCollision;
- (void) resumePostProximityAlert;

- (double) messageTime;
- (void) setMessageTime:(double) value;

//- (int) groupID;
//- (void) setGroupID:(int) value;

- (OOShipGroup *) group;
- (void) setGroup:(OOShipGroup *)group;

- (OOShipGroup *) escortGroup;
- (OOShipGroup *) stationGroup; // should probably be defined in stationEntity.m

- (BOOL) hasEscorts;
- (NSEnumerator *) escortEnumerator;
- (NSArray *) escortArray;

- (uint8_t) escortCount;

// Pending escort count: number of escorts to set up "later".
- (uint8_t) pendingEscortCount;
- (void) setPendingEscortCount:(uint8_t)count;

- (ShipEntity *) proximity_alert;
- (void) setProximity_alert:(ShipEntity*) other;

- (NSString *) name;
- (NSString *) displayName;
- (void) setName:(NSString *)inName;
- (void) setDisplayName:(NSString *)inName;
- (NSString *) identFromShip:(ShipEntity*) otherShip; // name displayed to other ships

- (BOOL) hasRole:(NSString *)role;
- (OORoleSet *)roleSet;

- (NSString *)primaryRole;
- (void)setPrimaryRole:(NSString *)role;
- (BOOL)hasPrimaryRole:(NSString *)role;

- (BOOL)isPolice;		// Scan class is CLASS_POLICE
- (BOOL)isThargoid;		// Scan class is CLASS_THARGOID
- (BOOL)isTrader;		// Primary role is "trader" || isPlayer
- (BOOL)isPirate;		// Primary role is "pirate"
- (BOOL)isMissile;		// Primary role has suffix "MISSILE"
- (BOOL)isMine;			// Primary role has suffix "MINE"
- (BOOL)isWeapon;		// isMissile || isWeapon
- (BOOL)isEscort;		// Primary role is "escort" or "wingman"
- (BOOL)isShuttle;		// Primary role is "shuttle"
- (BOOL)isPirateVictim;	// Primary role is listed in pirate-victim-roles.plist
- (BOOL)isUnpiloted;	// Has unpiloted = yes in its shipdata.plist entry

- (BOOL) hasHostileTarget;

- (GLfloat) weaponRange;
- (void) setWeaponRange:(GLfloat) value;
- (void) setWeaponDataFromType:(OOWeaponType)weapon_type;
- (float) weaponRechargeRate;
- (void) setWeaponRechargeRate:(float)value;

- (GLfloat) scannerRange;
- (void) setScannerRange: (GLfloat) value;

- (Vector) reference;
- (void) setReference:(Vector) v;

- (BOOL) reportAIMessages;
- (void) setReportAIMessages:(BOOL) yn;

- (void) transitionToAegisNone;
- (PlanetEntity *) findNearestPlanet;
- (PlanetEntity *) findNearestStellarBody;		// NOTE: includes sun.
- (PlanetEntity *) findNearestPlanetExcludingMoons;
- (OOAegisStatus) checkForAegis;
- (BOOL) withinStationAegis;

- (NSArray*) crew;
- (void) setCrew: (NSArray*) crewArray;

// Fuel and capacity in tenths of light-years.
- (OOFuelQuantity) fuel;
- (void) setFuel:(OOFuelQuantity) amount;
- (OOFuelQuantity) fuelCapacity;

- (void) setRoll:(double) amount;
- (void) setPitch:(double) amount;

- (void)setThrustForDemo:(float)factor;

- (void) setBounty:(OOCreditsQuantity) amount;
- (OOCreditsQuantity) bounty;

- (int) legalStatus;

- (void) setCommodity:(OOCargoType)co_type andAmount:(OOCargoQuantity)co_amount;
- (OOCargoType) commodityType;
- (OOCargoQuantity) commodityAmount;

- (OOCargoQuantity) maxCargo;
- (OOCargoQuantity) availableCargoSpace;
- (OOCargoQuantity) cargoQuantityOnBoard;
- (OOCargoType) cargoType;
- (NSMutableArray *) cargo;
- (void) setCargo:(NSArray *) some_cargo;

- (OOCargoFlag) cargoFlag;
- (void) setCargoFlag:(OOCargoFlag) flag;

- (void) setSpeed:(double) amount;
- (double) desiredSpeed;
- (void) setDesiredSpeed:(double) amount;

- (void) increase_flight_speed:(double) delta;
- (void) decrease_flight_speed:(double) delta;
- (void) increase_flight_roll:(double) delta;
- (void) decrease_flight_roll:(double) delta;
- (void) increase_flight_pitch:(double) delta;
- (void) decrease_flight_pitch:(double) delta;
- (void) increase_flight_yaw:(double) delta;
- (void) decrease_flight_yaw:(double) delta;

- (GLfloat) flightRoll;
- (GLfloat) flightPitch;
- (GLfloat) flightYaw;
- (GLfloat) flightSpeed;
- (GLfloat) maxFlightSpeed;
- (GLfloat) speedFactor;

- (GLfloat) temperature;
- (void) setTemperature:(GLfloat) value;
- (GLfloat) heatInsulation;
- (void) setHeatInsulation:(GLfloat) value;

// the percentage of damage taken (100 is destroyed, 0 is fine)
- (int) damage;

- (void) dealEnergyDamageWithinDesiredRange;
- (void) dealMomentumWithinDesiredRange:(double)amount;

- (void) getDestroyedBy:(Entity *)whom context:(NSString *)why;
- (void) becomeExplosion;
- (void) becomeLargeExplosion:(double) factor;
- (void) becomeEnergyBlast;
Vector randomPositionInBoundingBox(BoundingBox bb);

- (Vector) positionOffsetForAlignment:(NSString*) align;
Vector positionOffsetForShipInRotationToAlignment(ShipEntity* ship, Quaternion q, NSString* align);

- (void) collectBountyFor:(ShipEntity *)other;

- (BoundingBox) findSubentityBoundingBox;

- (Vector) absolutePositionForSubentity;
- (Vector) absolutePositionForSubentityOffset:(Vector) offset;

- (Triangle) absoluteIJKForSubentity;

- (void) addSolidSubentityToCollisionRadius:(ShipEntity *)subent;

ShipEntity *doOctreesCollide(ShipEntity *prime, ShipEntity *other);

- (NSComparisonResult) compareBeaconCodeWith:(ShipEntity *)other;

- (GLfloat)laserHeatLevel;
- (GLfloat)hullHeatLevel;
- (GLfloat)entityPersonality;
- (GLint)entityPersonalityInt;

- (void)setSuppressExplosion:(BOOL)suppress;

/*-----------------------------------------

	AI piloting methods

-----------------------------------------*/

BOOL	class_masslocks(int some_class);
- (BOOL) checkTorusJumpClear;

- (void) checkScanner;
- (ShipEntity**) scannedShips;
- (int) numberOfScannedShips;

- (void) setFound_target:(Entity *) targetEntity;
- (void) setPrimaryAggressor:(Entity *) targetEntity;
- (void) addTarget:(Entity *) targetEntity;
- (void) removeTarget:(Entity *) targetEntity;
- (id) primaryTarget;
- (int) primaryTargetID;

- (void) noteLostTarget;
- (void) noteTargetDestroyed:(ShipEntity *)target;

- (OOBehaviour) behaviour;
- (void) setBehaviour:(OOBehaviour) cond;

- (void) trackOntoTarget:(double) delta_t withDForward: (GLfloat) dp;

- (double) ballTrackTarget:(double) delta_t;
- (double) ballTrackLeadingTarget:(double) delta_t;

- (GLfloat) rollToMatchUp:(Vector) up_vec rotating:(GLfloat) match_roll;

- (GLfloat) rangeToDestination;
- (double) trackDestination:(double) delta_t :(BOOL) retreat;
//- (double) trackPosition:(Vector) track_pos :(double) delta_t :(BOOL) retreat;

- (Vector) destination;
- (Vector) distance_six: (GLfloat) dist;
- (Vector) distance_twelve: (GLfloat) dist;

- (double) trackPrimaryTarget:(double) delta_t :(BOOL) retreat;
- (double) missileTrackPrimaryTarget:(double) delta_t;

//return 0.0 if there is no primary target
- (double) rangeToPrimaryTarget;
- (BOOL) onTarget:(BOOL) fwd_weapon;

- (OOTimeDelta) shotTime;
- (void) resetShotTime;

- (BOOL) fireMainWeapon:(double) range;
- (BOOL) fireAftWeapon:(double) range;
- (BOOL) fireTurretCannon:(double) range;
- (void) setLaserColor:(OOColor *) color;
- (OOColor *)laserColor;
- (BOOL) fireSubentityLaserShot: (double) range;
- (BOOL) fireDirectLaserShot;
- (BOOL) fireLaserShotInDirection: (OOViewID) direction;
- (BOOL) firePlasmaShot:(double) offset :(double) speed :(OOColor *) color;
- (BOOL) fireMissile;
- (BOOL) isMissileFlagSet;
- (void) setIsMissileFlag:(BOOL)newValue;
- (BOOL) fireECM;
- (BOOL) activateCloakingDevice;
- (void) deactivateCloakingDevice;
- (BOOL) launchEnergyBomb;
- (OOUniversalID) launchEscapeCapsule;
- (OOCargoType) dumpCargo;
- (ShipEntity *) dumpCargoItem;
- (OOCargoType) dumpItem: (ShipEntity*) jetto;

- (void) manageCollisions;
- (BOOL) collideWithShip:(ShipEntity *)other;
- (void) adjustVelocity:(Vector) xVel;
- (void) addImpactMoment:(Vector) moment fraction:(GLfloat) howmuch;
- (BOOL) canScoop:(ShipEntity *)other;
- (void) getTractoredBy:(ShipEntity *)other;
- (void) scoopIn:(ShipEntity *)other;
- (void) scoopUp:(ShipEntity *)other;
- (void) takeScrapeDamage:(double) amount from:(Entity *) ent;

- (void) takeHeatDamage:(double) amount;

- (void) enterDock:(StationEntity *)station;
- (void) leaveDock:(StationEntity *)station;

- (void) enterWormhole:(WormholeEntity *) w_hole;
- (void) enterWormhole:(WormholeEntity *) w_hole replacing:(BOOL)replacing;
- (void) enterWitchspace;
- (void) leaveWitchspace;

- (void) markAsOffender:(int)offence_value;

- (void) switchLightsOn;
- (void) switchLightsOff;

- (void) setDestination:(Vector) dest;
- (void) setEscortDestination:(Vector) dest;

- (BOOL) canAcceptEscort:(ShipEntity *)potentialEscort;
- (BOOL) acceptAsEscort:(ShipEntity *) other_ship;
- (Vector) coordinatesForEscortPosition:(int) f_pos;
- (void) deployEscorts;
- (void) dockEscorts;

- (void) setTargetToNearestStation;
- (void) setTargetToSystemStation;

- (void) landOnPlanet:(PlanetEntity *)planet;

- (void) abortDocking;

- (void) broadcastThargoidDestroyed;

- (void) broadcastHitByLaserFrom:(ShipEntity*) aggressor_ship;

- (void) sendExpandedMessage:(NSString *) message_text toShip:(ShipEntity*) other_ship;
- (void) broadcastAIMessage:(NSString *) ai_message;
// Unpiloted ships cannot broadcast messages, unless the unpilotedOverride is set to YES.
- (void) broadcastMessage:(NSString *) message_text withUnpilotedOverride:(BOOL) unpilotedOverride;
- (void) setCommsMessageColor;
- (void) receiveCommsMessage:(NSString *) message_text;
- (void) commsMessage:(NSString *)valueString withUnpilotedOverride:(BOOL)unpilotedOverride;

- (BOOL) markForFines;

- (BOOL) isMining;

- (void) spawn:(NSString *)roles_number;

- (int) checkShipsInVicinityForWitchJumpExit;

- (BOOL) trackCloseContacts;
- (void) setTrackCloseContacts:(BOOL) value;

/*
 * Changes a ship to a hulk, for example when the pilot ejects.
 * Aso unsets hulkiness for example when a new pilot gets in.
 */
- (void) setHulk:(BOOL) isNowHulk;
- (BOOL) isHulk;
- (void) claimAsSalvage;
- (void) sendCoordinatesToPilot;
- (void) pilotArrived;

- (OOScript *)script;
- (NSDictionary *)scriptInfo;

- (Entity *)entityForShaderProperties;

// *** Script events.
// For NPC ships, these call doEvent: on the ship script.
// For the player, they do that and also call doWorldScriptEvent:.
- (void) doScriptEvent:(NSString *)message;
- (void) doScriptEvent:(NSString *)message withArgument:(id)argument;
- (void) doScriptEvent:(NSString *)message withArgument:(id)argument1 andArgument:(id)argument2;
- (void) doScriptEvent:(NSString *)message withArguments:(NSArray *)arguments;

- (void) reactToAIMessage:(NSString *)message;	// Immediate message
- (void) sendAIMessage:(NSString *)message;		// Queued message
- (void) doScriptEvent:(NSString *)scriptEvent andReactToAIMessage:(NSString *)aiMessage;
- (void) doScriptEvent:(NSString *)scriptEvent withArgument:(id)argument andReactToAIMessage:(NSString *)aiMessage;

@end


// For the common case of testing whether foo is a ship, bar is a ship, bar is a subentity of foo and this relationship is represented sanely.
@interface Entity (SubEntityRelationship)

- (BOOL) isShipWithSubEntityShip:(Entity *)other;

@end


BOOL ship_canCollide (ShipEntity* ship);


NSDictionary *DefaultShipShaderMacros(void);
