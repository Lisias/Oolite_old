/*

ShipEntity.m


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

#define BALL_WORLD 0


#import "ShipEntity.h"
#import "ShipEntityAI.h"
#import "ShipEntityScriptMethods.h"

#import "OOMaths.h"
#import "Universe.h"
#import "OOShaderMaterial.h"
#import "OOOpenGLExtensionManager.h"

#import "ResourceManager.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"
#import "OOConstToString.h"
#import "NSScannerOOExtensions.h"
#import "OOFilteringEnumerator.h"
#import "OORoleSet.h"
#import "OOShipGroup.h"
#import "OOExcludeObjectEnumerator.h"

#import "OOCharacter.h"
#import "AI.h"
#ifdef OO_BRAIN_AI
#import "OOBrain.h"
#endif

#import "OOMesh.h"
#if BALL_WORLD
#import "OOPlanetDrawable.h"
#endif

#import "Geometry.h"
#import "Octree.h"
#import "OOColor.h"

#import "ParticleEntity.h"
#import "StationEntity.h"
#import "OOSunEntity.h"
#import "PlanetEntity.h"
#import "PlayerEntity.h"
#import "WormholeEntity.h"
#import "OOFlasherEntity.h"
#import "OOExhaustPlumeEntity.h"
#import "OOSparkEntity.h"
#import "OOECMBlastEntity.h"
#import "OOPlasmaShotEntity.h"
#import "OOFlashEffectEntity.h"

#import "PlayerEntityLegacyScriptEngine.h"
#import "PlayerEntitySound.h"
#import "GuiDisplayGen.h"
#import "HeadUpDisplay.h"
#import "OOEntityFilterPredicate.h"
#import "OOEquipmentType.h"

#import "OODebugGLDrawing.h"

#import "OOScript.h"


#define kOOLogUnconvertedNSLog @"unclassified.ShipEntity"

#define USEMASC 1


extern NSString * const kOOLogSyntaxAddShips;
static NSString * const kOOLogEntityBehaviourChanged	= @"entity.behaviour.changed";


@interface ShipEntity (Private)

- (void) drawSubEntity:(BOOL) immediate :(BOOL) translucent;

- (void)subEntityDied:(ShipEntity *)sub;
- (void)subEntityReallyDied:(ShipEntity *)sub;

#ifndef NDEBUG
- (void) drawDebugStuff;
#endif

- (void) rescaleBy:(GLfloat)factor;

- (BOOL) setUpOneSubentity:(NSDictionary *) subentDict;
- (BOOL) setUpOneFlasher:(NSDictionary *) subentDict;
- (BOOL) setUpOneStandardSubentity:(NSDictionary *) subentDict asTurret:(BOOL)asTurret;

- (Entity<OOStellarBody> *) lastAegisLock;
- (void) setLastAegisLock:(Entity<OOStellarBody> *)lastAegisLock;

- (void) addSubEntity:(Entity *) subent;

- (void) addSubentityToCollisionRadius:(Entity*) subent;

// equipment
- (NSDictionary *) eqDictionaryWithType:(OOEquipmentType *) type isDamaged:(BOOL) isDamaged;

@end


@implementation ShipEntity

- (id) init
{
	/*	-init used to set up a bunch of defaults that were different from
		those in -reinit and -setUpShipFromDictionary:. However, it seems that
		no ships are ever used which are not -setUpShipFromDictionary: (which
		is as it should be), so these different defaults were meaningless.
	*/
	return [self initWithDictionary:nil];
}


// Designated initializer
- (id) initWithDictionary:(NSDictionary *) dict
{
	if (dict == nil && ![self isKindOfClass:[PlayerEntity class]])
	{
		// Is there any reason we should allow nil dictionary here? I think not. --Ahruman 2008-04-27
		// Yes, the player ship uses -init. Any others? --Ahruman 2008-04-28
		OOLog(@"ship.sanityCheck.nilDict", @"Ship created with nil dictionary!");
	}
	
	self = [super init];
	
	isShip = YES;
	entity_personality = ranrot_rand() & 0x7FFF;
	[self setStatus:STATUS_IN_FLIGHT];
	
	zero_distance = SCANNER_MAX_RANGE2 * 2.0;
	weapon_recharge_rate = 6.0;
	shot_time = 100000.0;
	ship_temperature = 60.0;
	
	if (![self setUpShipFromDictionary:dict])
	{
		[self release];
		self = nil;
	}
	
	// Problem observed in testing -- Ahruman
	if (self != nil && !isfinite(maxFlightSpeed))
	{
		OOLog(@"ship.sanityCheck.failed", @"Ship %@ %@ infinite top speed, clamped to 300.", self, @"generated with");
		maxFlightSpeed = 300;
	}
	return self;
}


- (BOOL) setUpFromDictionary:(NSDictionary *) shipDict
{
	// Settings shared by players & NPCs.
	//
	// In order for default values to work and float values to not be junk,
	// replace nil with empty dictionary. -- Ahruman 2008-04-28
	if (shipDict == nil)  shipDict = [NSDictionary dictionary];
	
	// All like_ship references should have been resolved in -[Universe getDictionaryForShip:recursionLimit:]
	if ([shipDict objectForKey:@"like_ship"] != nil)
	{
		OOLogERR(@"ship.setUp.like_ship", @"like_ship found inside ship dictionary in -[ShipEntity setUpFromDictionary:], when it should have been resolved already. %@", @"This is an internal error, please report it.");
		return NO;
	}
	
	shipinfoDictionary = [shipDict copy];
	shipDict = shipinfoDictionary;	// TEMP: ensure no mutation
	
	// set these flags explicitly.
	haveExecutedSpawnAction = NO;
	being_fined = NO;
	isNearPlanetSurface = NO;
	suppressAegisMessages = NO;
	isMissile = NO;
	suppressExplosion = NO;
	
	// set things from dictionary from here out - default values might require adjustment -- Kaks 20091130
	maxFlightSpeed = [shipDict oo_floatForKey:@"max_flight_speed" defaultValue:160.0f];
	max_flight_roll = [shipDict oo_floatForKey:@"max_flight_roll" defaultValue:2.0f];
	max_flight_pitch = [shipDict oo_floatForKey:@"max_flight_pitch" defaultValue:1.0f];
	max_flight_yaw = [shipDict oo_floatForKey:@"max_flight_yaw" defaultValue:max_flight_pitch];	// Note by default yaw == pitch
	cruiseSpeed = maxFlightSpeed*0.8f;
	
	max_thrust = [shipDict oo_floatForKey:@"thrust" defaultValue:15.0f];
	thrust = max_thrust;
	maxEnergy = [shipDict oo_floatForKey:@"max_energy" defaultValue:200.0f];
	energy_recharge_rate = [shipDict oo_floatForKey:@"energy_recharge_rate" defaultValue:1.0f];
	
	// Each new ship should start in seemingly good operating condition, unless specifically told not to - this does not affect the ship's energy levels
	[self setThrowSparks:[shipDict oo_boolForKey:@"throw_sparks" defaultValue:NO]];
	
	forward_weapon_type = StringToWeaponType([shipDict oo_stringForKey:@"forward_weapon_type" defaultValue:@"WEAPON_NONE"]);
	aft_weapon_type = StringToWeaponType([shipDict oo_stringForKey:@"aft_weapon_type" defaultValue:@"WEAPON_NONE"]);
	[self setWeaponDataFromType:forward_weapon_type];
	
	cloaking_device_active = NO;
	military_jammer_active = NO;
	cloakPassive = [shipDict oo_boolForKey:@"cloak_passive" defaultValue:NO];
	
	missiles = [shipDict oo_intForKey:@"missiles" defaultValue:0];
	max_missiles = [shipDict oo_intForKey:@"max_missiles" defaultValue:missiles];
	if (max_missiles > SHIPENTITY_MAX_MISSILES) max_missiles = SHIPENTITY_MAX_MISSILES;
	if (missiles > max_missiles) missiles = max_missiles;
	missile_load_time = [shipDict oo_floatForKey:@"missile_load_time" defaultValue:0];
	missile_launch_time = [UNIVERSE getTime] + missile_load_time;
	
	// upgrades:
	if ([shipDict oo_fuzzyBooleanForKey:@"has_ecm"])  [self addEquipmentItem:@"EQ_ECM"];
	if ([shipDict oo_fuzzyBooleanForKey:@"has_scoop"])  [self addEquipmentItem:@"EQ_FUEL_SCOOPS"];
	if ([shipDict oo_fuzzyBooleanForKey:@"has_escape_pod"])  [self addEquipmentItem:@"EQ_ESCAPE_POD"];
	if ([shipDict oo_fuzzyBooleanForKey:@"has_energy_bomb"])  [self addEquipmentItem:@"EQ_ENERGY_BOMB"];
	if ([shipDict oo_fuzzyBooleanForKey:@"has_cloaking_device"])  [self addEquipmentItem:@"EQ_CLOAKING_DEVICE"];
	if (![UNIVERSE strict])
	{
		// These items are not available in strict mode.
		if ([shipDict oo_fuzzyBooleanForKey:@"has_fuel_injection"])  [self addEquipmentItem:@"EQ_FUEL_INJECTION"];
#if USEMASC
		if ([shipDict oo_fuzzyBooleanForKey:@"has_military_jammer"])  [self addEquipmentItem:@"EQ_MILITARY_JAMMER"];
		if ([shipDict oo_fuzzyBooleanForKey:@"has_military_scanner_filter"])  [self addEquipmentItem:@"EQ_MILITARY_SCANNER_FILTER"];
#endif
	}
	
	// can it be 'mined' for alloys?
	canFragment = [shipDict oo_fuzzyBooleanForKey:@"fragment_chance" defaultValue:0.9];
	// can subentities be destroyed separately?
	isFrangible = [shipDict oo_boolForKey:@"frangible" defaultValue:YES];
	
	max_cargo = [shipDict oo_unsignedIntForKey:@"max_cargo"];
	extra_cargo = [shipDict oo_unsignedIntForKey:@"extra_cargo" defaultValue:15];
	
	if (![UNIVERSE strict])
	{
		hyperspaceMotorSpinTime = [shipDict oo_floatForKey:@"hyperspace_motor_spin_time" defaultValue:DEFAULT_HYPERSPACE_SPIN_TIME];
	}
	else
	{
		hyperspaceMotorSpinTime = DEFAULT_HYPERSPACE_SPIN_TIME;
	}
	
	if (name !=nil) [name autorelease];
	name = [[shipDict oo_stringForKey:@"name" defaultValue:@"?"] copy];
	
	if (displayName !=nil) [displayName autorelease];
	displayName = [[shipDict oo_stringForKey:@"display_name" defaultValue:name] copy];
	
	// Load the model (must be before subentities)
	NSString *modelName = [shipDict oo_stringForKey:@"model"];
	if (modelName != nil)
	{
		OOMesh *mesh = [OOMesh meshWithName:modelName
						 materialDictionary:[shipDict oo_dictionaryForKey:@"materials"]
						  shadersDictionary:[shipDict oo_dictionaryForKey:@"shaders"]
									 smooth:[shipDict oo_boolForKey:@"smooth" defaultValue:NO]
							   shaderMacros:DefaultShipShaderMacros()
						shaderBindingTarget:self];
		if (mesh == nil)  return NO;
		[self setMesh:mesh];
	}
	
	float density = [shipDict oo_floatForKey:@"density" defaultValue:1.0f];
	if (octree)  mass = (GLfloat)(density * 20.0 * [octree volume]);
	
	OOColor *color = [OOColor brightColorWithDescription:[shipDict objectForKey:@"laser_color"]];
	if (color == nil)  color = [OOColor redColor];
	[self setLaserColor:color];
	
	[self clearSubEntities];
	[self setUpSubEntities: shipDict];
	
	// rotating subentities
	subentityRotationalVelocity = kIdentityQuaternion;
	ScanQuaternionFromString([shipDict objectForKey:@"rotational_velocity"], &subentityRotationalVelocity);

	// set weapon offsets
	[self setDefaultWeaponOffsets];
	
	ScanVectorFromString([shipDict objectForKey:@"weapon_position_forward"], &forwardWeaponOffset);
	ScanVectorFromString([shipDict objectForKey:@"weapon_position_aft"], &aftWeaponOffset);
	ScanVectorFromString([shipDict objectForKey:@"weapon_position_port"], &portWeaponOffset);
	ScanVectorFromString([shipDict objectForKey:@"weapon_position_starboard"], &starboardWeaponOffset);

	// fuel scoop destination position (where cargo gets sucked into)
	tractor_position = kZeroVector;
	ScanVectorFromString([shipDict objectForKey:@"scoop_position"], &tractor_position);
	
	// Get scriptInfo dictionary, containing arbitrary stuff scripts might be interested in.
	scriptInfo = [[shipDict oo_dictionaryForKey:@"script_info" defaultValue:nil] retain];
	
	return YES;
}


- (BOOL) setUpShipFromDictionary:(NSDictionary *) shipDict
{
	if (![self setUpFromDictionary:shipDict]) return NO;
	
	// NPC-only settings.
	//
	orientation = kIdentityQuaternion;
	rotMatrix	= kIdentityMatrix;
	v_forward	= kBasisZVector;
	v_up		= kBasisYVector;
	v_right		= kBasisXVector;
	reference	= v_forward;  // reference vector for (* turrets *)
	
	isShip = YES;

	// FIXME: give NPCs shields instead.
	if ([shipDict oo_fuzzyBooleanForKey:@"has_shield_booster"])
	{
		maxEnergy += 256.0f;
	}
	if ([shipDict oo_fuzzyBooleanForKey:@"has_shield_enhancer"])
	{
		maxEnergy += 256.0f;
		energy_recharge_rate *= 1.5;
	}
	
	// Start with full energy banks.
	energy = maxEnergy;
	
	// setWeaponDataFromType inside setUpFromDictionary should set weapon_energy from the front laser.
	// no weapon_energy? It's a missile: set weapon_energy from shipdata!
	if (weapon_energy == 0.0) weapon_energy = [shipDict oo_floatForKey:@"weapon_energy"];

	scannerRange = [shipDict oo_floatForKey:@"scanner_range" defaultValue:(float)SCANNER_MAX_RANGE];
	
	fuel = [shipDict oo_unsignedShortForKey:@"fuel"];	// Does it make sense that this defaults to 0? Should it not be 70? -- Ahruman
	fuel_accumulator = 1.0;
	
	bounty = [shipDict oo_unsignedIntForKey:@"bounty"];
	
	[shipAI autorelease];
	shipAI = [[AI alloc] init];
	[shipAI setOwner:self];
	[shipAI setStateMachine:[shipDict oo_stringForKey:@"ai_type" defaultValue:@"nullAI.plist"]];
	
	likely_cargo = [shipDict oo_unsignedIntForKey:@"likely_cargo"];
	noRocks = [shipDict oo_fuzzyBooleanForKey:@"no_boulders"];
	
	NSString *cargoString = [shipDict oo_stringForKey:@"cargo_carried"];
	if (cargoString != nil)
	{
		cargo_flag = CARGO_FLAG_FULL_UNIFORM;

		OOCargoType		c_commodity = CARGO_UNDEFINED;
		int				c_amount = 1;
		NSScanner		*scanner = [NSScanner scannerWithString:cargoString];
		if ([scanner scanInt:&c_amount])
		{
			[scanner ooliteScanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];	// skip whitespace
			c_commodity = [UNIVERSE commodityForName: [[scanner string] substringFromIndex:[scanner scanLocation]]];
		}
		else
		{
			c_amount = 1;
			c_commodity = [UNIVERSE commodityForName: [shipDict oo_stringForKey:@"cargo_carried"]];
		}

		if (c_commodity != CARGO_UNDEFINED)  [self setCommodity:c_commodity andAmount:c_amount];
	}
	
	cargoString = [shipDict oo_stringForKey:@"cargo_type"];
	if (cargoString)
	{
		cargo_type = StringToCargoType(cargoString);
		
		if (cargo != nil) [cargo autorelease];
		cargo = [[NSMutableArray alloc] initWithCapacity:max_cargo]; // alloc retains;
	}
	
	[roleSet release];
	roleSet = [[[OORoleSet roleSetWithString:[shipDict oo_stringForKey:@"roles"]] roleSetWithRemovedRole:@"player"] retain];
	[primaryRole release];
	primaryRole = nil;
	
	[self setOwner:self];
	[self setHulk:[shipDict oo_boolForKey:@"is_hulk"]];
	
	// these are the colors used for the "lollipop" of the ship. Any of the two (or both, for flash effect) can be defined
	scanner_display_color1 = [[OOColor colorWithDescription:[shipDict objectForKey:@"scanner_display_color1"]] retain];
	scanner_display_color2 = [[OOColor colorWithDescription:[shipDict objectForKey:@"scanner_display_color2"]] retain];

	// scan class settings. 'scanClass' is in common usage, but we could also have a more standard 'scan_class' key with higher precedence. Kaks 20090810 
	// let's see if scan_class is set... 
	scanClass = StringToScanClass([shipDict oo_stringForKey:@"scan_class" defaultValue:@"CLASS_NOT_SET"]);
	
	// if not, try 'scanClass'. NOTE: non-standard capitalization is documented and entrenched.
	if (scanClass == CLASS_NOT_SET)
	{
		scanClass = StringToScanClass([shipDict oo_stringForKey:@"scanClass" defaultValue:@"CLASS_NOT_SET"]);
	}
	
	// Populate the missiles here. Must come after scanClass.
	missileRole = [shipDict oo_stringForKey:@"missile_role"];
	unsigned	i;
	for (i = 0; i < missiles; i++)
	{
		missile_list[i] = [self newMissile];
		if (missile_list[i] == nil) i--;
	}
	
	// accuracy. Must come after scanClass, because we are using scanClass to determine if this is a missile.
	accuracy = [shipDict oo_floatForKey:@"accuracy" defaultValue:-100.0f];	// Out-of-range default
	if (accuracy >= -5.0f && accuracy <= 10.0f)
	{
		pitch_tolerance = 0.01 * (85.0f + accuracy);
	}
	else
	{
		pitch_tolerance = 0.01 * (80 + (randf() * 15.0f));
	}

	// If this entity is a missile, clamp its accuracy within range from 0.0 to 10.0.
	// Otherwise, just make sure that the accuracy value does not fall below 1.0.
	// Using a switch statement, in case accuracy for other scan classes need be considered in the future.
	switch (scanClass)
	{
		case CLASS_MISSILE :
			accuracy = OOClamp_0_max_f(accuracy, 10.0f);
			break;
		default :
			if (accuracy < 1.0f) accuracy = 1.0f;
			break;
	}
		
	//  escorts
	_pendingEscortCount = _maxEscortCount = [shipDict oo_unsignedIntForKey:@"escorts"];
	
	// beacons
	[self setBeaconCode:[shipDict oo_stringForKey:@"beacon"]];
	
	// contact tracking entities
	[self setTrackCloseContacts:[shipDict oo_boolForKey:@"track_contacts" defaultValue:NO]];
	
	// ship skin insulation factor (1.0 is normal)
	[self setHeatInsulation:[shipDict oo_floatForKey:@"heat_insulation" defaultValue:[self hasHeatShield] ? 2.0 : 1.0]];
	
	// crew and passengers
	NSDictionary* cdict = [[UNIVERSE characters] objectForKey:[shipDict oo_stringForKey:@"pilot"]];
	if (cdict != nil)
	{
		OOCharacter	*pilot = [OOCharacter characterWithDictionary:cdict];
		[self setCrew:[NSArray arrayWithObject:pilot]];
	}
	
	// unpiloted (like missiles asteroids etc.)
	if ((isUnpiloted = [shipDict oo_fuzzyBooleanForKey:@"unpiloted"]))  [self setCrew:nil];
	
	[self setShipScript:[shipDict oo_stringForKey:@"script"]];
	
	return YES;
}


- (BOOL) setUpSubEntities: (NSDictionary *) shipDict
{
	unsigned int	i;
	NSArray			*plumes = [shipDict oo_arrayForKey:@"exhaust"];
	
	_profileRadius = collision_radius;
	
	for (i = 0; i < [plumes count]; i++)
	{
		NSArray *definition = ScanTokensFromString([plumes oo_stringAtIndex:i]);
		OOExhaustPlumeEntity *exhaust = [OOExhaustPlumeEntity exhaustForShip:self withDefinition:definition];
		[self addSubEntity:exhaust];
	}
	
	NSArray *subs = [shipDict oo_arrayForKey:@"subentities"];
	
	for (i = 0; i < [subs count]; i++)
	{
		[self setUpOneSubentity:[subs oo_dictionaryAtIndex:i]];
	}
	
	no_draw_distance = _profileRadius * _profileRadius * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR * 2.0;
	
	return YES;
}


- (BOOL) setUpOneSubentity:(NSDictionary *) subentDict
{
	NSString			*type = nil;
	
	type = [subentDict oo_stringForKey:@"type"];
	if ([type isEqualToString:@"flasher"])
	{
		return [self setUpOneFlasher:subentDict];
	}
	else
	{
		return [self setUpOneStandardSubentity:subentDict asTurret:[type isEqualToString:@"ball_turret"]];
	}
}


- (BOOL) setUpOneFlasher:(NSDictionary *) subentDict
{
	OOFlasherEntity *flasher = [OOFlasherEntity flasherWithDictionary:subentDict];
	[flasher setPosition:[subentDict oo_vectorForKey:@"position"]];
	[self addSubEntity:flasher];
	return YES;
}


- (BOOL) setUpOneStandardSubentity:(NSDictionary *) subentDict asTurret:(BOOL)asTurret
{
	ShipEntity			*subentity = nil;
	NSString			*subentKey = nil;
	Vector				subPosition;
	Quaternion			subOrientation;
	
	subentKey = [subentDict oo_stringForKey:@"subentity_key"];
	if (subentKey == nil)  return NO;
	
	subentity = [UNIVERSE newShipWithName:subentKey];
	if (subentity == nil)  return NO;
	
	subPosition = [subentDict oo_vectorForKey:@"position"];
	subOrientation = [subentDict oo_quaternionForKey:@"orientation"];
	
	if (!asTurret && [self isStation] && [subentDict oo_boolForKey:@"is_dock"])
	{
		[(StationEntity *)self setDockingPortModel:subentity :subPosition :subOrientation];
	}
	
	[subentity setPosition:subPosition];
	[subentity setOrientation:subOrientation];
	[subentity setReference:vector_forward_from_quaternion(subOrientation)];
	
	if (asTurret)
	{
		[subentity setBehaviour:BEHAVIOUR_TRACK_AS_TURRET];
		[subentity setWeaponRechargeRate:[subentDict oo_floatForKey:@"fire_rate" defaultValue:TURRET_SHOT_FREQUENCY]];
		[subentity setStatus: STATUS_ACTIVE];
	}
	else
	{
		[subentity setStatus:STATUS_INACTIVE];
	}
	
	[self addSubEntity:subentity];
	[subentity release];
	
	return YES;
}


- (void) dealloc
{
	[self setTrackCloseContacts:NO];	// deallocs tracking dictionary
	[[self parentEntity] subEntityReallyDied:self];	// Will do nothing if we're not really a subentity
	[self clearSubEntities];
	
	[shipinfoDictionary release];
	[shipAI release];
	[cargo release];
	[name release];
	[displayName release];
	[roleSet release];
	[primaryRole release];
	[laser_color release];
	[scanner_display_color1 release];
	scanner_display_color1 = nil;
	[scanner_display_color2 release];
	scanner_display_color2 = nil;
	if (script != nil) 
	{
		[script release];
		script = nil;
	}
	
	[previousCondition release];
	
	[dockingInstructions release];
	
	[crew release];
	
	[lastRadioMessage autorelease];
	
	[octree autorelease];
	
	[self setSubEntityTakingDamage:nil];
	[self removeAllEquipment];
	
	[_group removeShip:self];
	[_group release];
	[_escortGroup removeShip:self];
	[_escortGroup release];
	
	[_lastAegisLock release];
	
	[super dealloc];
}


- (void) removeScript
{
	[script autorelease];
	script = nil;
}


- (void) clearSubEntities
{
	[subEntities makeObjectsPerformSelector:@selector(setOwner:) withObject:nil];	// Ensure backlinks are broken
	[subEntities release];
	subEntities = nil;
}


- (NSString *)descriptionComponents
{
	if (![self isSubEntity])
	{
		return [NSString stringWithFormat:@"\"%@\" %@", [self name], [super descriptionComponents]];
	}
	else
	{
		// ID, scanClass and status are of no interest for subentities.
		NSString *subtype = nil;
		if ([self behaviour] == BEHAVIOUR_TRACK_AS_TURRET)  subtype = @"(turret)";
		else  subtype = @"(subentity)";
		
		return [NSString stringWithFormat:@"\"%@\" position: %@ %@", [self name], VectorDescription([self position]), subtype];
	}
}


- (NSString *) shortDescriptionComponents
{
	return [NSString stringWithFormat:@"\"%@\"", [self name]];
}


- (OOMesh *)mesh
{
	return (OOMesh *)[self drawable];
}


- (void)setMesh:(OOMesh *)mesh
{
	if (mesh != [self mesh])
	{
		[self setDrawable:mesh];
		[octree autorelease];
		octree = [[mesh octree] retain];
	}
}


- (Vector) forwardVector
{
	return v_forward;
}


- (Vector) upVector
{
	return v_up;
}


- (Vector) rightVector
{
	return v_right;
}


- (NSArray *)subEntities
{
	return [[subEntities copy] autorelease];
}


- (unsigned) subEntityCount
{
	return [subEntities count];
}


- (BOOL) hasSubEntity:(ShipEntity *)sub
{
	return [subEntities containsObject:sub];
}

- (NSEnumerator *)subEntityEnumerator
{
	return [[self subEntities] objectEnumerator];
}


- (NSEnumerator *)shipSubEntityEnumerator
{
	return [[self subEntities] objectEnumeratorFilteredWithSelector:@selector(isShip)];
}


- (NSEnumerator *)flasherEnumerator
{
	return [[self subEntities] objectEnumeratorFilteredWithSelector:@selector(isFlasher)];
}


- (NSEnumerator *)exhaustEnumerator
{
	return [[self subEntities] objectEnumeratorFilteredWithSelector:@selector(isExhaust)];
}


- (ShipEntity *) subEntityTakingDamage
{
	ShipEntity *result = [_subEntityTakingDamage weakRefUnderlyingObject];
	
#ifndef NDEBUG
	// Sanity check - there have been problems here, see fireLaserShotInDirection:
	// -parentEntity will take care of reporting insanity.
	if ([result parentEntity] != self)  result = nil;
#endif
	
	// Clear the weakref if the subentity is dead.
	if (result == nil)  [self setSubEntityTakingDamage:nil];
	
	return result;
}


- (void) setSubEntityTakingDamage:(ShipEntity *)sub
{
#ifndef NDEBUG
	// Sanity checks: sub must be a ship subentity of self, or nil.
	if (sub != nil)
	{
		if (![self hasSubEntity:sub])
		{
			OOLog(@"ship.subentity.sanityCheck.failed.details", @"Attempt to set subentity taking damage of %@ to %@, which is not a subentity.", [self shortDescription], sub);
			sub = nil;
		}
		else if (![sub isShip])
		{
			OOLog(@"ship.subentity.sanityCheck.failed", @"Attempt to set subentity taking damage of %@ to %@, which is not a ship.", [self shortDescription], sub);
			sub = nil;
		}
	}
#endif
	
	[_subEntityTakingDamage release];
	_subEntityTakingDamage = [sub weakRetain];
}


- (OOScript *)shipScript
{
	return script;
}


- (BoundingBox)findBoundingBoxRelativeToPosition:(Vector)opv InVectors:(Vector) _i :(Vector) _j :(Vector) _k
{
	return [[self mesh] findBoundingBoxRelativeToPosition:opv
													basis:_i :_j :_k
											 selfPosition:position
												selfBasis:v_right :v_up :v_forward];
}


#ifdef OO_BRAIN_AI
// ship's brains!
- (OOBrain *)brain
{
	return brain;
}


- (void)setBrain:(OOBrain *)aBrain
{
	brain = aBrain;
}
#endif


- (Octree *) octree
{
	return octree;
}


- (float) volume
{
	return [octree volume];
}


- (GLfloat)doesHitLine:(Vector)v0: (Vector)v1;
{
	Vector u0 = vector_between(position, v0);	// relative to origin of model / octree
	Vector u1 = vector_between(position, v1);
	Vector w0 = make_vector(dot_product(u0, v_right), dot_product(u0, v_up), dot_product(u0, v_forward));	// in ijk vectors
	Vector w1 = make_vector(dot_product(u1, v_right), dot_product(u1, v_up), dot_product(u1, v_forward));
	return [octree isHitByLine:w0 :w1];
}


- (GLfloat) doesHitLine:(Vector)v0: (Vector)v1 :(ShipEntity **)hitEntity;
{
	if (hitEntity)
		hitEntity[0] = (ShipEntity*)nil;
	Vector u0 = vector_between(position, v0);	// relative to origin of model / octree
	Vector u1 = vector_between(position, v1);
	Vector w0 = make_vector(dot_product(u0, v_right), dot_product(u0, v_up), dot_product(u0, v_forward));	// in ijk vectors
	Vector w1 = make_vector(dot_product(u1, v_right), dot_product(u1, v_up), dot_product(u1, v_forward));
	GLfloat hit_distance = [octree isHitByLine:w0 :w1];
	if (hit_distance)
	{
		if (hitEntity)
			hitEntity[0] = self;
	}
	
	NSEnumerator	*subEnum = nil;
	ShipEntity		*se = nil;
	for (subEnum = [self shipSubEntityEnumerator]; (se = [subEnum nextObject]); )
	{
		Vector p0 = [se absolutePositionForSubentity];
		Triangle ijk = [se absoluteIJKForSubentity];
		u0 = vector_between(p0, v0);
		u1 = vector_between(p0, v1);
		w0 = resolveVectorInIJK(u0, ijk);
		w1 = resolveVectorInIJK(u1, ijk);
		
		GLfloat hitSub = [se->octree isHitByLine:w0 :w1];
		if (hitSub && (hit_distance == 0 || hit_distance > hitSub))
		{	
			hit_distance = hitSub;
			if (hitEntity)
			{
				*hitEntity = se;
			}
		}
	}
	
	return hit_distance;
}


- (GLfloat)doesHitLine:(Vector)v0: (Vector)v1 withPosition:(Vector)o andIJK:(Vector)i :(Vector)j :(Vector)k;
{
	Vector u0 = vector_between(o, v0);	// relative to origin of model / octree
	Vector u1 = vector_between(o, v1);
	Vector w0 = make_vector(dot_product(u0, i), dot_product(u0, j), dot_product(u0, k));	// in ijk vectors
	Vector w1 = make_vector(dot_product(u1, j), dot_product(u1, j), dot_product(u1, k));
	return [octree isHitByLine:w0 :w1];
}


- (void) wasAddedToUniverse
{
	[super wasAddedToUniverse];
	
	// if we have a universal id then we can proceed to set up any
	// stuff that happens when we get added to the UNIVERSE
	if (universalID != NO_TARGET)
	{
		// set up escorts
		if (([self status] == STATUS_IN_FLIGHT || [self status] == STATUS_LAUNCHING) && _pendingEscortCount != 0)	// just popped into existence
		{
			[self setUpEscorts];
		}
		else
		{
			/*	Earlier there was a silly log message here because I thought
				this would never happen, but wasn't entirely sure. Turns out
				it did!
				-- Ahruman 2009-09-13
			*/
			_pendingEscortCount = 0;
		}
	}

	//	Tell subentities, too
	[subEntities makeObjectsPerformSelector:@selector(wasAddedToUniverse)];
	
	[self resetExhaustPlumes];
}


- (void)wasRemovedFromUniverse
{
	[subEntities makeObjectsPerformSelector:@selector(wasRemovedFromUniverse)];
}


- (Vector)absoluteTractorPosition
{
	Vector result = position;
	result.x += v_right.x * tractor_position.x + v_up.x * tractor_position.y + v_forward.x * tractor_position.z;
	result.y += v_right.y * tractor_position.x + v_up.y * tractor_position.y + v_forward.y * tractor_position.z;
	result.z += v_right.z * tractor_position.x + v_up.z * tractor_position.y + v_forward.z * tractor_position.z;
	return result;
}


- (NSString *)beaconCode
{
	return beaconCode;
}


- (void)setBeaconCode:(NSString *)bcode
{
	if ([beaconCode length] == 0)  beaconCode = nil;
	
	if (beaconCode != bcode)
	{
		[beaconCode release];
		beaconCode = [bcode copy];
		if (beaconCode != nil)
		{
			beaconChar = [bcode cStringUsingOoliteEncodingAndRemapping][0];
		}
		else
		{
			beaconChar = '\0';
		}
	}
}


- (BOOL)isBeacon
{
	return (beaconChar != 0);
}


- (char)beaconChar
{
	return beaconChar;
}


- (int)nextBeaconID
{
	return nextBeaconID;
}


- (void)setNextBeacon:(ShipEntity *)beaconShip
{
	if (beaconShip == nil)  nextBeaconID = NO_TARGET;
	else  nextBeaconID = [beaconShip universalID];
}


- (void) setUpEscorts
{
	NSString		*defaultRole = @"escort";
	NSString		*escortRole = nil;
	NSString		*escortShipKey = nil;
	NSString		*autoAI = nil;
	NSDictionary	*autoAIMap = nil;
	NSDictionary	*escortShipDict = nil;
	AI				*escortAI = nil;
	BOOL			isSelfGroupmember = NO;
	
	// Ensure that we do not try to create escorts if we are an escort ship ourselves.
	// This could lead to circular reference memory overflows (e.g. "boa-mk2" trying to create 4 "boa-mk2"
	// escorts or the case of two ships specifying eachother as escorts) - Nikos 20090510
	if ([self isEscort])
	{
		OOLogWARN(@"shipEntity.setupEscorts.escortShipCircularReference", 
				@"Ship %@ requested escorts, when it is an escort ship itself. Avoiding possible circular reference overflow by ignoring escort setup.", self);
		return;
	}
	
	if (_pendingEscortCount == 0)  return;
	
	if ([self isPolice])  defaultRole = @"wingman";
	
	escortRole = [shipinfoDictionary oo_stringForKey:@"escort_role" defaultValue:nil];
	if (escortRole == nil)
		escortRole = [shipinfoDictionary oo_stringForKey:@"escort-role" defaultValue:defaultRole];
	if (![escortRole isEqualToString: defaultRole])
	{
		if (![[UNIVERSE newShipWithRole:escortRole] autorelease])
		{
			escortRole = defaultRole;
		}
	}
	
	escortShipKey = [shipinfoDictionary oo_stringForKey:@"escort_ship" defaultValue:nil];
	if (escortShipKey == nil)
		escortShipKey = [shipinfoDictionary oo_stringForKey:@"escort-ship"];
	
	if (escortShipKey != nil)
	{
		if (![[UNIVERSE newShipWithName:escortShipKey] autorelease])
		{
			escortShipKey = nil;
		}
	}
	
	OOShipGroup *escortGroup = [self escortGroup];
	if ([self group] == nil)
	{
		[self setGroup:escortGroup];
	}
	else
	{
		isSelfGroupmember = YES;
	}
	[escortGroup setLeader:self];
	
	while (_pendingEscortCount > 0)
	{
		Vector ex_pos = [self coordinatesForEscortPosition:_pendingEscortCount - 1];
		
		ShipEntity *escorter = nil;
		
		if (escortShipKey)
		{
			escorter = [UNIVERSE newShipWithName:escortShipKey];	// retained
		}
		else
		{
			escorter = [UNIVERSE newShipWithRole:escortRole];	// retained
		}
		
		if (escorter == nil)  break;
		
		if ([escorter crew] == nil)
		{
			[escorter setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"hunter"
				andOriginalSystem: [UNIVERSE systemSeed]]]];
		}
		
		// spread them around a little randomly
		double dd = escorter->collision_radius;
		ex_pos.x += dd * 6.0 * (randf() - 0.5);
		ex_pos.y += dd * 6.0 * (randf() - 0.5);
		ex_pos.z += dd * 6.0 * (randf() - 0.5);
		
		[escorter setPosition:ex_pos];
		[escorter setStatus:STATUS_IN_FLIGHT];
		[escorter setPrimaryRole:defaultRole];	//for mothership
		[escorter setScanClass:scanClass];		// you are the same as I
		if ([self bounty] == 0)  [escorter setBounty:0];	// Avoid dirty escorts for clean mothers
		
		[UNIVERSE addEntity:escorter];
		
		escortShipDict = [escorter shipInfoDictionary];
		autoAIMap = [ResourceManager dictionaryFromFilesNamed:@"autoAImap.plist" inFolder:@"Config" andMerge:YES];
		autoAI = [autoAIMap oo_stringForKey:defaultRole];
		if (autoAI==nil) // no 'wingman' defined in autoAImap?
		{
			autoAI = [autoAIMap oo_stringForKey:@"escort" defaultValue:@"nullAI.plist"];
		}
		if ((escortShipKey || escortRole) && [escortShipDict oo_fuzzyBooleanForKey:@"auto_ai" defaultValue:YES]) //setAITo only once!
		{
			[escorter setAITo:autoAI];
		}
		
		escortAI = [escorter getAI];
		if ([[escortAI name] isEqualToString: @"nullAI.plist"] && ![autoAI isEqualToString:@"nullAI.plist"])
		{
			[escortAI setStateMachine:autoAI];   // must happen after adding to the UNIVERSE!
		}
		
		[escorter setGroup:escortGroup];
		[escorter setOwner:self];	// make self group leader
		if(isSelfGroupmember) [[self group] addShip:escorter]; // put escorts also in leaders group when present.
		
		if([escorter heatInsulation] < [self heatInsulation]) [escorter setHeatInsulation:[self heatInsulation]]; // give escorts same protection as mother.
		if(([escorter maxFlightSpeed] < cruiseSpeed) && ([escorter maxFlightSpeed] > cruiseSpeed * 0.3)) 
				cruiseSpeed = [escorter maxFlightSpeed] * 0.99;  // adapt patrolSpeed to the slowest escort but ignore the very slow ones.

		[escortAI setState:@"FLYING_ESCORT"];	// Begin escort flight. (If the AI doesn't define FLYING_ESCORT, this has no effect.)
		[escorter doScriptEvent:@"spawnedAsEscort" withArgument:self];
		
		if (bounty)
		{
			int extra = 1 | (ranrot_rand() & 15);
			bounty += extra;	// obviously we're dodgier than we thought!
			[escorter setBounty: extra];
		}
		else
		{
			[escorter setBounty:0];
		}
		[escorter release];
		_pendingEscortCount--;
	}
}


- (NSDictionary *)shipInfoDictionary
{
	return shipinfoDictionary;
}


- (void) setDefaultWeaponOffsets
{
	forwardWeaponOffset = kZeroVector;
	aftWeaponOffset = kZeroVector;
	portWeaponOffset = kZeroVector;
	starboardWeaponOffset = kZeroVector;
}


- (BOOL)isFrangible
{
	return isFrangible;
}


- (OOScanClass) scanClass
{
	if (cloaking_device_active)
		return CLASS_NO_DRAW;
	else
		return scanClass;
}

//////////////////////////////////////////////

BOOL ship_canCollide (ShipEntity* ship)
{
	int		s_status =		[ship status];
	int		s_scan_class =	ship->scanClass;
	if ((s_status == STATUS_COCKPIT_DISPLAY)||(s_status == STATUS_DEAD)||(s_status == STATUS_BEING_SCOOPED))
		return NO;
	if ((s_scan_class == CLASS_MISSILE) && ([ship shotTime] < 0.25)) // not yet fused
		return NO;
	return YES;
}


- (BOOL) canCollide
{
	return ship_canCollide(self);
}

ShipEntity* doOctreesCollide(ShipEntity* prime, ShipEntity* other)
{
	// octree check
	Octree		*prime_octree = prime->octree;
	Octree		*other_octree = other->octree;
	
	Vector		prime_position = [prime absolutePositionForSubentity];
	Triangle	prime_ijk = [prime absoluteIJKForSubentity];
	Vector		other_position = [other absolutePositionForSubentity];
	Triangle	other_ijk = [other absoluteIJKForSubentity];

	Vector		relative_position_of_other = resolveVectorInIJK(vector_between(prime_position, other_position), prime_ijk);
	Triangle	relative_ijk_of_other;
	relative_ijk_of_other.v[0] = resolveVectorInIJK(other_ijk.v[0], prime_ijk);
	relative_ijk_of_other.v[1] = resolveVectorInIJK(other_ijk.v[1], prime_ijk);
	relative_ijk_of_other.v[2] = resolveVectorInIJK(other_ijk.v[2], prime_ijk);
	
	// check hull octree against other hull octree
	if ([prime_octree isHitByOctree:other_octree
						 withOrigin:relative_position_of_other
							 andIJK:relative_ijk_of_other])
	{
		return other;
	}
	
	// check prime subentities against the other's hull
	NSArray* prime_subs = prime->subEntities;
	if (prime_subs)
	{
		int i;
		int n_subs = [prime_subs count];
		for (i = 0; i < n_subs; i++)
		{
			Entity* se = [prime_subs objectAtIndex:i];
			if ([se isShip] && [se canCollide] && doOctreesCollide((ShipEntity*)se, other))
				return other;
		}
	}

	// check prime hull against the other's subentities
	NSArray* other_subs = other->subEntities;
	if (other_subs)
	{
		int i;
		int n_subs = [other_subs count];
		for (i = 0; i < n_subs; i++)
		{
			Entity* se = [other_subs objectAtIndex:i];
			if ([se isShip] && [se canCollide] && doOctreesCollide(prime, (ShipEntity*)se))
				return (ShipEntity*)se;
		}
	}
	
	// check prime subenties against the other's subentities
	if ((prime_subs)&&(other_subs))
	{
		int i;
		int n_osubs = [other_subs count];
		for (i = 0; i < n_osubs; i++)
		{
			Entity* oe = [other_subs objectAtIndex:i];
			if ([oe isShip] && [oe canCollide])
			{
				int j;
				int n_psubs = [prime_subs count];
				for (j = 0; j <  n_psubs; j++)
				{
					Entity* pe = [prime_subs objectAtIndex:j];
					if ([pe isShip] && [pe canCollide] && doOctreesCollide((ShipEntity*)pe, (ShipEntity*)oe))
						return (ShipEntity*)oe;
				}
			}
		}
	}

	// fall through => no collision
	return nil;
}


- (BOOL) checkCloseCollisionWith:(Entity *)other
{
	if (other == nil)  return NO;
	if ([collidingEntities containsObject:other])  return NO;	// we know about this already!
	
	ShipEntity *otherShip = nil;
	if ([other isShip])  otherShip = (ShipEntity *)other;
	
	if ([self canScoop:otherShip])  return YES;	// quick test - could this improve scooping for small ships? I think so!
	
	if (otherShip != nil && trackCloseContacts)
	{
		// in update we check if close contacts have gone out of touch range (origin within our collision_radius)
		// here we check if something has come within that range
		Vector			otherPos = [otherShip position];
		OOUniversalID	otherID = [otherShip universalID];
		NSString		*other_key = [NSString stringWithFormat:@"%d", otherID];
		
		if (![closeContactsInfo objectForKey:other_key] &&
			distance2(position, otherPos) < collision_radius * collision_radius)
		{
			// calculate position with respect to our own position and orientation
			Vector	dpos = vector_between(position, otherPos);
			Vector  rpos = make_vector(dot_product(dpos, v_right), dot_product(dpos, v_up), dot_product(dpos, v_forward));
			[closeContactsInfo setObject:[NSString stringWithFormat:@"%f %f %f", rpos.x, rpos.y, rpos.z] forKey: other_key];
			
			// send AI a message about the touch
			OOUniversalID	temp_id = primaryTarget;
			primaryTarget = otherID;
			[self doScriptEvent:@"shipCloseContact" withArgument:otherShip andReactToAIMessage:@"CLOSE CONTACT"];
			primaryTarget = temp_id;
		}
	}
	
	if (zero_distance > CLOSE_COLLISION_CHECK_MAX_RANGE2)	// don't work too hard on entities that are far from the player
		return YES;
	
	if (otherShip != nil)
	{
		// check hull octree versus other hull octree
		collider = doOctreesCollide(self, otherShip);
		return (collider != nil);
	}
	
	// default at this stage is to say YES they've collided!
	collider = other;
	return YES;
}


- (BoundingBox)findSubentityBoundingBox
{
	return [[self mesh] findSubentityBoundingBoxWithPosition:position rotMatrix:rotMatrix];
}


- (Triangle) absoluteIJKForSubentity
{
	Triangle	result = {{ kBasisXVector, kBasisYVector, kBasisZVector, kZeroVector }};
	Entity		*last = nil;
	Entity		*father = self;
	OOMatrix	r_mat;
	
	while ((father)&&(father != last) && (father != NO_TARGET))
	{
		r_mat = [father drawRotationMatrix];
		result.v[0] = OOVectorMultiplyMatrix(result.v[0], r_mat);
		result.v[1] = OOVectorMultiplyMatrix(result.v[1], r_mat);
		result.v[2] = OOVectorMultiplyMatrix(result.v[2], r_mat);
		
		last = father;
		if (![last isSubEntity]) break;
		father = [father owner];
	}
	return result;
}


- (void) addSubentityToCollisionRadius:(Entity*)subent
{
	if (!subent)  return;
	
	double distance = magnitude([subent position]) + [subent findCollisionRadius];
	if ([subent isKindOfClass:[ShipEntity class]])	// Solid subentity
	{
		if (distance > collision_radius)
		{
			collision_radius = distance;
		}
		
		mass += 20.0 * [(ShipEntity *)subent volume];
	}
	if (distance > _profileRadius)
	{
		_profileRadius = distance;
	}
}


- (BOOL) validForAddToUniverse
{
	if (shipinfoDictionary == nil)
	{
		OOLog(@"shipEntity.notDict", @"Ship %@ was not set up from dictionary.", self);
		return NO;
	}
	return YES;
}


- (void) update:(OOTimeDelta)delta_t
{
	if (shipinfoDictionary == nil)
	{
		OOLog(@"shipEntity.notDict", @"Ship %@ was not set up from dictionary.", self);
		[UNIVERSE removeEntity:self];
		return;
	}
	
	if (!isfinite(maxFlightSpeed))
	{
		OOLog(@"ship.sanityCheck.failed", @"Ship %@ %@ infinite top speed, clamped to 300.", self, @"had");
		maxFlightSpeed = 300;
	}
	
	//
	// deal with collisions
	//
	[self manageCollisions];
	
	//
	// reset any inadvertant legal mishaps
	//
	if (scanClass == CLASS_POLICE)
	{
		if (bounty > 0)
			bounty = 0;
		ShipEntity* target = [UNIVERSE entityForUniversalID:primaryTarget];
		if ((target)&&(target->scanClass == CLASS_POLICE))
		{
			[self noteLostTarget];
		}
	}
	
	if (trackCloseContacts)
	{
		// in checkCloseCollisionWith: we check if some thing has come within touch range (origin within our collision_radius)
		// here we check if it has gone outside that range
		NSEnumerator			*contactEnum = nil;
		NSString				*other_key = nil;
		
		for (contactEnum = [closeContactsInfo keyEnumerator]; (other_key = [contactEnum nextObject]); )
		{
			ShipEntity* other = [UNIVERSE entityForUniversalID:[other_key intValue]];
			if ((other != nil) && (other->isShip))
			{
				if (distance2(position, other->position) > collision_radius * collision_radius)	// moved beyond our sphere!
				{
					// calculate position with respect to our own position and orientation
					Vector	dpos = vector_between(position, other->position);
					Vector  pos1 = make_vector(dot_product(dpos, v_right), dot_product(dpos, v_up), dot_product(dpos, v_forward));
					Vector	pos0 = {0, 0, 0};
					ScanVectorFromString([closeContactsInfo objectForKey: other_key], &pos0);
					// send AI messages about the contact
					int	temp_id = primaryTarget;
					primaryTarget = other->universalID;
					if ((pos0.x < 0.0)&&(pos1.x > 0.0))
					{
						[self doScriptEvent:@"shipTraversePositiveX" withArgument:other andReactToAIMessage:@"POSITIVE X TRAVERSE"];
					}
					if ((pos0.x > 0.0)&&(pos1.x < 0.0))
					{
						[self doScriptEvent:@"shipTraverseNegativeX" withArgument:other andReactToAIMessage:@"NEGATIVE X TRAVERSE"];
					}
					if ((pos0.y < 0.0)&&(pos1.y > 0.0))
					{
						[self doScriptEvent:@"shipTraversePositiveY" withArgument:other andReactToAIMessage:@"POSITIVE Y TRAVERSE"];
					}
					if ((pos0.y > 0.0)&&(pos1.y < 0.0))
					{
						[self doScriptEvent:@"shipTraverseNegativeY" withArgument:other andReactToAIMessage:@"NEGATIVE Y TRAVERSE"];
					}
					if ((pos0.z < 0.0)&&(pos1.z > 0.0))
					{
						[self doScriptEvent:@"shipTraversePositiveZ" withArgument:other andReactToAIMessage:@"POSITIVE Z TRAVERSE"];
					}
					if ((pos0.z > 0.0)&&(pos1.z < 0.0))
					{
						[self doScriptEvent:@"shipTraverseNegativeZ" withArgument:other andReactToAIMessage:@"NEGATIVE Z TRAVERSE"];
					}
					primaryTarget = temp_id;
					[closeContactsInfo removeObjectForKey: other_key];
				}
			}
			else
			{
				[closeContactsInfo removeObjectForKey: other_key];
			}
		}
	}
	
	// think!
#ifdef OO_BRAIN_AI
	[brain update:delta_t];
#endif
	
	// super update
	[super update:delta_t];
	
#ifndef NDEBUG
	// DEBUGGING
	if (reportAIMessages && (debugLastBehaviour != behaviour))
	{
		OOLog(kOOLogEntityBehaviourChanged, @"%@ behaviour is now %@", self, BehaviourToString(behaviour));
		debugLastBehaviour = behaviour;
	}
#endif

	// update time between shots
	shot_time += delta_t;

	// handle radio message effects
	if (messageTime > 0.0)
	{
		messageTime -= delta_t;
		if (messageTime < 0.0)
			messageTime = 0.0;
	}

	// temperature factors
	double external_temp = 0.0;
	OOSunEntity *sun = [UNIVERSE sun];
	if (sun != nil)
	{
		// set the ambient temperature here
		double  sun_zd = magnitude2(vector_between(position, [sun position]));	// square of distance
		double  sun_cr = sun->collision_radius;
		double	alt1 = sun_cr * sun_cr / sun_zd;
		external_temp = SUN_TEMPERATURE * alt1;
		if ([sun goneNova])  external_temp *= 100;
	}

	// work on the ship temperature
	//
	float heatThreshold = [self heatInsulation] * 100.0f;
	if (external_temp > heatThreshold &&  external_temp > ship_temperature)
		ship_temperature += (external_temp - ship_temperature) * delta_t * SHIP_INSULATION_FACTOR / [self heatInsulation];
	else
	{
		if (ship_temperature > SHIP_MIN_CABIN_TEMP)
			ship_temperature += (external_temp - heatThreshold - ship_temperature) * delta_t * SHIP_COOLING_FACTOR / [self heatInsulation];
	}

	if (ship_temperature > SHIP_MAX_CABIN_TEMP)
		[self takeHeatDamage: delta_t * ship_temperature];

	// are we burning due to low energy
	if ((energy < maxEnergy * 0.20)&&(energy_recharge_rate > 0.0))	// prevents asteroid etc. from burning
		throw_sparks = YES;
	
	// burning effects
	if (throw_sparks)
	{
		next_spark_time -= delta_t;
		if (next_spark_time < 0.0)
		{
			[self throwSparks];
			throw_sparks = NO;	// until triggered again
		}
	}
	
	// cloaking device
	if ([self hasCloakingDevice])
	{
		if (cloaking_device_active)
		{
			energy -= delta_t * CLOAKING_DEVICE_ENERGY_RATE;
			if (energy < CLOAKING_DEVICE_MIN_ENERGY)
				[self deactivateCloakingDevice];
		}
		else
		{
			if (energy < maxEnergy)
			{
				energy += delta_t * CLOAKING_DEVICE_ENERGY_RATE;
				if (energy > maxEnergy)
				{
					energy = maxEnergy;
					[shipAI message:@"ENERGY_FULL"];
				}
			}
		}
	}

	// military_jammer
	if ([self hasMilitaryJammer])
	{
		if (military_jammer_active)
		{
			energy -= delta_t * MILITARY_JAMMER_ENERGY_RATE;
			if (energy < MILITARY_JAMMER_MIN_ENERGY)
				military_jammer_active = NO;
		}
		else
		{
			if (energy > 1.5 * MILITARY_JAMMER_MIN_ENERGY)
				military_jammer_active = YES;
		}
	}

	// check outside factors
	//
	aegis_status = [self checkForAegis];   // is a station or something nearby??

	//scripting
	if (!haveExecutedSpawnAction && script != nil && [self status] == STATUS_IN_FLIGHT)
	{
		[[PlayerEntity sharedPlayer] setScriptTarget:self];
		[self doScriptEvent:@"shipSpawned"];
		haveExecutedSpawnAction = YES;
	}

	// behaviours according to status and behaviour
	//
	if ([self status] == STATUS_LAUNCHING)
	{
		if ([UNIVERSE getTime] > launch_time + LAUNCH_DELAY)		// move for while before thinking
		{
			StationEntity *stationLaunchedFrom = [UNIVERSE nearestEntityMatchingPredicate:IsStationPredicate parameter:NULL relativeToEntity:self];
			[self setStatus:STATUS_IN_FLIGHT];
			[self doScriptEvent:@"shipLaunchedFromStation" withArgument:stationLaunchedFrom];
			[shipAI reactToMessage: @"LAUNCHED OKAY"];
		}
		else
		{
			// ignore behaviour just keep moving...
			[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
			[self applyThrust:delta_t];
			if (energy < maxEnergy)
			{
				energy += energy_recharge_rate * delta_t;
				if (energy > maxEnergy)
				{
					energy = maxEnergy;
					[self doScriptEvent:@"shipEnergyBecameFull"];
					[shipAI message:@"ENERGY_FULL"];
				}
			}
			
			NSEnumerator	*subEnum = nil;
			ShipEntity		*se = nil;
			for (subEnum = [self subEntityEnumerator]; (se = [subEnum nextObject]); )
			{
				[se update:delta_t];
			}
			return;
		}
	}
	//
	// double check scooped behaviour
	//
	if ([self status] == STATUS_BEING_SCOOPED)
	{
		//if we are being tractored, but we have no owner, then we have a problem
		if (behaviour != BEHAVIOUR_TRACTORED  || [self owner] == nil || [self owner] == self || [self owner] == NO_TARGET)
		{
			// escaped tractor beam
			[self setStatus:STATUS_IN_FLIGHT];	// should correct 'uncollidable objects' bug
			behaviour = BEHAVIOUR_IDLE;
			frustration = 0.0;
			[self setOwner:self];
			[shipAI exitStateMachineWithMessage:nil];  // Escapepods and others should continue their old AI here.
		}
	}
	
	if ([self status] == STATUS_COCKPIT_DISPLAY)
	{
		[self applyRoll: delta_t * flightRoll andClimb: delta_t * flightPitch];
		GLfloat range2 = 0.1 * distance2(position, destination) / (collision_radius * collision_radius);
		if ((range2 > 1.0)||(velocity.z > 0.0))	range2 = 1.0;
		position = vector_add(position, vector_multiply_scalar(velocity, range2 * delta_t));
	}
	else
	{
		ShipEntity *target = [UNIVERSE entityForUniversalID:primaryTarget];
		
		if (target == nil || [target scanClass] == CLASS_NO_DRAW || ![target isShip] || [target isCloaked])
		{
			 // It's no longer a parrot, it has ceased to be, it has joined the choir invisible...
			if (primaryTarget != NO_TARGET)
			{
				if ([target isShip] && [target isCloaked])
				{
					[self doScriptEvent:@"shipTargetCloaked" andReactToAIMessage:@"TARGET_CLOAKED"];
				}
				[self noteLostTarget];
			}
		}

		switch (behaviour)
		{
			case BEHAVIOUR_TUMBLE :
				[self behaviour_tumble: delta_t];
				break;

			case BEHAVIOUR_STOP_STILL :
			case BEHAVIOUR_STATION_KEEPING :
				[self behaviour_stop_still: delta_t];
				break;

			case BEHAVIOUR_IDLE :
				[self behaviour_idle: delta_t];
				break;

			case BEHAVIOUR_TRACTORED :
				[self behaviour_tractored: delta_t];
				break;

			case BEHAVIOUR_TRACK_TARGET :
				[self behaviour_track_target: delta_t];
				break;

			case BEHAVIOUR_INTERCEPT_TARGET :
			case BEHAVIOUR_COLLECT_TARGET :
				[self behaviour_intercept_target: delta_t];
				break;

			case BEHAVIOUR_ATTACK_TARGET :
				[self behaviour_attack_target: delta_t];
				break;

			case BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX :
			case BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE :
				[self behaviour_fly_to_target_six: delta_t];
				break;

			case BEHAVIOUR_ATTACK_MINING_TARGET :
				[self behaviour_attack_mining_target: delta_t];
				break;

			case BEHAVIOUR_ATTACK_FLY_TO_TARGET :
				[self behaviour_attack_fly_to_target: delta_t];
				break;

			case BEHAVIOUR_ATTACK_FLY_FROM_TARGET :
				[self behaviour_attack_fly_from_target: delta_t];
				break;

			case BEHAVIOUR_RUNNING_DEFENSE :
				[self behaviour_running_defense: delta_t];
				break;

			case BEHAVIOUR_FLEE_TARGET :
				[self behaviour_flee_target: delta_t];
				break;

			case BEHAVIOUR_FLY_RANGE_FROM_DESTINATION :
				[self behaviour_fly_range_from_destination: delta_t];
				break;

			case BEHAVIOUR_FACE_DESTINATION :
				[self behaviour_face_destination: delta_t];
				break;

			case BEHAVIOUR_FORMATION_FORM_UP :
				[self behaviour_formation_form_up: delta_t];
				break;

			case BEHAVIOUR_FLY_TO_DESTINATION :
				[self behaviour_fly_to_destination: delta_t];
				break;

			case BEHAVIOUR_FLY_FROM_DESTINATION :
			case BEHAVIOUR_FORMATION_BREAK :
				[self behaviour_fly_from_destination: delta_t];
				break;

			case BEHAVIOUR_AVOID_COLLISION :
				[self behaviour_avoid_collision: delta_t];
				break;

			case BEHAVIOUR_TRACK_AS_TURRET :
				[self behaviour_track_as_turret: delta_t];
				break;

			case BEHAVIOUR_FLY_THRU_NAVPOINTS :
				[self behaviour_fly_thru_navpoints: delta_t];
				break;

			case BEHAVIOUR_ENERGY_BOMB_COUNTDOWN:
				// Do nothing
				break;
		}
		
		// manage energy
		if (energy < maxEnergy)
		{
			energy += energy_recharge_rate * delta_t;
			if (energy > maxEnergy)
			{
				energy = maxEnergy;
				[shipAI message:@"ENERGY_FULL"];
			}
		}
		
		// update destination position for escorts
		if ([self hasEscorts])
		{
			NSEnumerator			*escortEnum = nil;
			ShipEntity				*escort = nil;
			unsigned				i = 0;
			
			// Note: works on escortArray rather than escortEnumerator because escorts may be mutated.
			for (escortEnum = [[self escortArray] objectEnumerator]; (escort = [escortEnum nextObject]); )
			{
				[escort setEscortDestination:[self coordinatesForEscortPosition:i++]];
			}
		}
		if ([self escortGroup] != nil) 
		{
			ShipEntity *leader = [[self escortGroup] leader];
			if (leader != nil && ([leader scanClass] != [self scanClass])) {
				OOLog(@"ship.sanityCheck.failed", @"Ship %@ escorting %@ with wrong scanclass!", self, leader);
				[[self escortGroup] removeShip:self];
				[[self escortGroup] release];
			}
		}
	}
	
	// subentity rotation
	if (!quaternion_equal(subentityRotationalVelocity, kIdentityQuaternion) &&
		!quaternion_equal(subentityRotationalVelocity, kZeroQuaternion))
	{
		Quaternion qf = subentityRotationalVelocity;
		qf.w *= (1.0 - delta_t);
		qf.x *= delta_t;
		qf.y *= delta_t;
		qf.z *= delta_t;
		orientation = quaternion_multiply(qf, orientation);
	}
	
	//	reset totalBoundingBox
	totalBoundingBox = boundingBox;
	
	// update subentities
	NSEnumerator	*subEnum = nil;
	ShipEntity		*se = nil;
	for (subEnum = [self subEntityEnumerator]; (se = [subEnum nextObject]); )
	{
		[se update:delta_t];
		if ([se isShip])
		{
			BoundingBox sebb = [se findSubentityBoundingBox];
			bounding_box_add_vector(&totalBoundingBox, sebb.max);
			bounding_box_add_vector(&totalBoundingBox, sebb.min);
		}
	}
	
}


// override Entity version...
//
- (double) speed
{
	return sqrt(velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z + flightSpeed * flightSpeed);
}



- (void)respondToAttackFrom:(Entity *)from becauseOf:(Entity *)other
{
	Entity				*source = nil;
	
	if ([other isKindOfClass:[ShipEntity class]])
	{
		source = other;
		
		ShipEntity *hunter = (ShipEntity *)other;
		//if we are in the same group, then we have to be careful about how we handle things
		if ([self isPolice] && [hunter isPolice]) 
		{
			//police never get into a fight with each other
			return;
		}
		
		OOShipGroup *group = [self group];
		
		if (group != nil && group == [hunter group]) 
		{
			//we are in the same group, do we forgive you?
			//criminals are less likely to forgive
			if (randf() < (0.8 - (bounty/100))) 
			{
				//it was an honest mistake, lets get on with it
				return;
			}
			
			ShipEntity *groupLeader = [group leader];
			if (hunter == groupLeader)
			{
				//oops we were attacked by our leader, desert him
				[self setGroup:nil];
			}
			else 
			{
				//evict them from our group
				[hunter setGroup:nil];
				
				[groupLeader setFound_target:other];
				[groupLeader setPrimaryAggressor:hunter];
				[groupLeader respondToAttackFrom:from becauseOf:other];
			}
		}
	}
	else
	{
		source = from;
	}	
	[self doScriptEvent:@"shipBeingAttacked" withArgument:source andReactToAIMessage:@"ATTACKED"];
}


// Equipment

- (BOOL) hasOneEquipmentItem:(NSString *)itemKey includeWeapons:(BOOL)includeWeapons
{
	if ([self hasOneEquipmentItem:itemKey includeMissiles:includeWeapons])  return YES;
	if (includeWeapons)
	{
		// Check for primary weapon
		OOWeaponType weaponType = EquipmentStringToWeaponTypeStrict(itemKey);
		if (weaponType != WEAPON_NONE)
		{
			if ([self hasPrimaryWeapon:weaponType])  return YES;
		}
	}
	
	return NO;
}


- (BOOL) hasOneEquipmentItem:(NSString *)itemKey includeMissiles:(BOOL)includeMissiles
{
	if ([_equipment containsObject:itemKey])  return YES;
	
	if (includeMissiles && missiles > 0)
	{
		unsigned i;
		for (i = 0; i < missiles; i++)
		{
			if ([[missile_list[i] identifier] isEqualTo:itemKey])  return YES;
		}
	}
	
	return NO;
}


- (BOOL) hasPrimaryWeapon:(OOWeaponType)weaponType
{
	NSEnumerator				*subEntEnum = nil;
	ShipEntity					*subEntity = nil;
	
	if (forward_weapon_type == weaponType || aft_weapon_type == weaponType)  return YES;
	
	for (subEntEnum = [self shipSubEntityEnumerator]; (subEntity = [subEntEnum nextObject]); )
	{
		if ([subEntity hasPrimaryWeapon:weaponType])  return YES;
	}
	
	return NO;
}


- (BOOL) hasEquipmentItem:(id)equipmentKeys includeWeapons:(BOOL)includeWeapons
{
	// this function is also used internally to find out if an equipped item is undamaged.
	NSEnumerator				*keyEnum = nil;
	id							key = nil;
	
	if (!includeWeapons && _equipment == nil)  return NO;
	
	// Make sure it's an array or set, using a single-object set if it's a string.
	if ([equipmentKeys isKindOfClass:[NSString class]])  equipmentKeys = [NSArray arrayWithObject:equipmentKeys];
	else if (![equipmentKeys isKindOfClass:[NSArray class]] && ![equipmentKeys isKindOfClass:[NSSet class]])  return NO;
	
	for (keyEnum = [equipmentKeys objectEnumerator]; (key = [keyEnum nextObject]); )
	{
		if ([self hasOneEquipmentItem:key includeWeapons:includeWeapons])  return YES;
	}
	
	return NO;
}


- (BOOL) hasEquipmentItem:(id)equipmentKeys
{
	return [self hasEquipmentItem:equipmentKeys includeWeapons:NO];
}


- (BOOL) hasAllEquipment:(id)equipmentKeys includeWeapons:(BOOL)includeWeapons
{
	NSEnumerator				*keyEnum = nil;
	id							key = nil;
	
	if (_equipment == nil)  return NO;
	
	// Make sure it's an array or set, using a single-object set if it's a string.
	if ([equipmentKeys isKindOfClass:[NSString class]])  equipmentKeys = [NSArray arrayWithObject:equipmentKeys];
	else if (![equipmentKeys isKindOfClass:[NSArray class]] && ![equipmentKeys isKindOfClass:[NSSet class]])  return NO;
	
	for (keyEnum = [equipmentKeys objectEnumerator]; (key = [keyEnum nextObject]); )
	{
		if (![self hasOneEquipmentItem:key includeWeapons:includeWeapons])  return NO;
	}
	
	return YES;
}


- (BOOL) hasAllEquipment:(id)equipmentKeys
{
	return [self hasAllEquipment:equipmentKeys includeWeapons:NO];
}


- (BOOL) canAddEquipment:(NSString *)equipmentKey
{	
	if ([equipmentKey hasSuffix:@"_DAMAGED"])
	{
		equipmentKey = [equipmentKey substringToIndex:[equipmentKey length] - [@"_DAMAGED" length]];
	}
	
	if ([equipmentKey hasSuffix:@"MISSILE"]||[equipmentKey hasSuffix:@"MINE"]||([self isThargoid] && [equipmentKey isEqualToString:@"thargon"]))
	{
		if (missiles >= max_missiles) return NO;
	}
	
	if ([self hasEquipmentItem:equipmentKey])  return NO;
	if (![self equipmentValidToAdd:equipmentKey])  return NO;
	
	return YES;
}


- (OOEquipmentType *) weaponTypeForFacing:(int) facing
{
	OOWeaponType 			weapon_type = WEAPON_NONE;
	
	switch (facing)
	{
		case WEAPON_FACING_FORWARD:
			weapon_type = forward_weapon_type;
			break;
		case WEAPON_FACING_AFT:
			weapon_type = aft_weapon_type;
			break;
		// any other value is not a facing for NPC ships...
		default:
			break;
	}

	return [OOEquipmentType equipmentTypeWithIdentifier:WeaponTypeToEquipmentString(weapon_type)];
}


- (NSArray *) missilesList
{
	NSMutableArray		*miss = [NSMutableArray arrayWithCapacity:missiles];
	unsigned			i;

	for (i = 0; i < missiles; i++)
	{
		[miss addObject:missile_list[i]];
	}
	return [[miss copy] autorelease];
}


- (NSArray *) passengerListForScripting
{
	return [NSArray array];
}


- (NSArray *) contractListForScripting
{
	return [NSArray array];
}


- (NSDictionary *) eqDictionaryWithType:(OOEquipmentType *) type isDamaged:(BOOL) isDamaged
{
	return [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:type, [NSNumber numberWithBool:isDamaged], nil]
									   forKeys:[NSArray arrayWithObjects:@"type", @"isDamaged", nil]];
}


- (NSArray *) equipmentListForScripting
{
	NSArray				*eqTypes = [OOEquipmentType allEquipmentTypes];
	NSMutableArray		*quip = [NSMutableArray arrayWithCapacity:[eqTypes count]];
	NSEnumerator		*eqTypeEnum = nil;
	OOEquipmentType		*eqType = nil;
	BOOL				isDamaged;
	
	for (eqTypeEnum = [eqTypes objectEnumerator]; (eqType = [eqTypeEnum nextObject]); )
	{
		/*
		// comprehensive list, but at odds with the rest of the api - Kaks
		if ([self hasEquipmentItem:[eqType identifier]])
		{
			[quip addObject:[self eqDictionaryWithType:eqType isDamaged:NO]];
		}
		else if (![UNIVERSE strict]) // Check for damaged version
		{
			if ([self hasEquipmentItem:[[eqType identifier] stringByAppendingString:@"_DAMAGED"]])
			{
				[quip addObject:[self eqDictionaryWithType:eqType isDamaged:YES]];
			}
		}
		*/
		// less comprehensive list, but consistent with the rest of the API - Kaks
		isDamaged = ![UNIVERSE strict] && [self hasEquipmentItem:[[eqType identifier] stringByAppendingString:@"_DAMAGED"]];
		if ([self hasEquipmentItem:[eqType identifier]] || isDamaged)
		{
			[quip addObject:eqType];
		}
	}
	
	// Passengers - not supported for NPCs, but it's here for genericity.
	if ([self passengerCapacity] > 0)
	{
		eqType = [OOEquipmentType equipmentTypeWithIdentifier:@"EQ_PASSENGER_BERTH"];
		//[quip addObject:[self eqDictionaryWithType:eqType isDamaged:NO]];
		[quip addObject:eqType];
	}
	
	return [[quip copy] autorelease];
}


- (BOOL) equipmentValidToAdd:(NSString *)equipmentKey
{
	OOEquipmentType			*eqType = nil;
	
	if ([equipmentKey hasSuffix:@"_DAMAGED"])
	{
		equipmentKey = [equipmentKey substringToIndex:[equipmentKey length] - [@"_DAMAGED" length]];
	}
	
	eqType = [OOEquipmentType equipmentTypeWithIdentifier:equipmentKey];
	if (eqType == nil)  return NO;
	
	if ([eqType requiresEmptyPylon] && [self missileCount] >= [self missileCapacity])  return NO;
	if ([eqType  requiresMountedPylon] && [self missileCount] == 0)  return NO;
	if ([self availableCargoSpace] < [eqType requiredCargoSpace])  return NO;
	if ([eqType requiresEquipment] != nil && ![self hasAllEquipment:[eqType requiresEquipment] includeWeapons:YES])  return NO;
	if ([eqType requiresAnyEquipment] != nil && ![self hasEquipmentItem:[eqType requiresAnyEquipment] includeWeapons:YES])  return NO;
	if ([eqType incompatibleEquipment] != nil && [self hasEquipmentItem:[eqType incompatibleEquipment] includeWeapons:YES])  return NO;
	if ([eqType requiresCleanLegalRecord] && [self legalStatus] != 0)  return NO;
	if ([eqType requiresNonCleanLegalRecord] && [self legalStatus] == 0)  return NO;
	if ([eqType requiresFreePassengerBerth] && [self passengerCount] >= [self passengerCapacity])  return NO;
	if ([eqType requiresFullFuel] && [self fuel] < [self fuelCapacity])  return NO;
	if ([eqType requiresNonFullFuel] && [self fuel] >= [self fuelCapacity])  return NO;
	
	return YES;
}


- (BOOL) addEquipmentItem:(NSString *)equipmentKey
{
	return [self addEquipmentItem:equipmentKey withValidation:YES];
}


- (BOOL) addEquipmentItem:(NSString *)equipmentKey withValidation:(BOOL)validateAddition
{
	OOEquipmentType			*eqType = nil;
	
	// canAddEquipment always checks if the undamaged version is equipped.
	if (validateAddition == YES && ![self canAddEquipment:equipmentKey])  return NO;
	
	// special cases
	
	if ([equipmentKey hasSuffix:@"MISSILE"]||[equipmentKey hasSuffix:@"MINE"]||([self isThargoid] && [equipmentKey isEqualToString:@"thargon"]))
	{
		if (missiles >= max_missiles) return NO;
		
		missile_list[missiles] = [OOEquipmentType equipmentTypeWithIdentifier:equipmentKey];
		missiles++;
		return YES;
	}
	
	// don't add any thargons to non-thargoid ships.
	if([equipmentKey isEqualToString:@"thargon"]) return NO;
	
	// we can theoretically add a damaged weapon, but not a working one.
	if([equipmentKey hasPrefix:@"EQ_WEAPON"] && ![equipmentKey hasSuffix:@"_DAMAGED"])
	{
		return NO;
	}
	
	// end special cases

	if ([equipmentKey hasSuffix:@"_DAMAGED"])
	{
		eqType = [OOEquipmentType equipmentTypeWithIdentifier:[equipmentKey substringToIndex:[equipmentKey length] - [@"_DAMAGED" length]]];
	}
	else
	{
		eqType = [OOEquipmentType equipmentTypeWithIdentifier:equipmentKey];
	}
	
	// does this equipment actually exist?
	if (eqType == nil)  return NO;
	
	if (_equipment == nil)  _equipment = [[NSMutableSet alloc] init];
	
	if ([equipmentKey isEqual:@"EQ_CARGO_BAY"])
	{
		max_cargo += extra_cargo;
	}
	
	// add the equipment
	[_equipment addObject:equipmentKey];
	return YES;
}


- (NSEnumerator *) equipmentEnumerator
{
	return [_equipment objectEnumerator];
}


- (unsigned) equipmentCount
{
	return [_equipment count];
}


- (void) removeEquipmentItem:(NSString *)equipmentKey
{
	NSString *equipmentTypeCheckKey = equipmentKey;
	
	// determine the equipment type and make sure it works also in the case of damaged equipment
	if ([equipmentKey hasSuffix:@"_DAMAGED"])
	{
		equipmentTypeCheckKey = [equipmentKey substringToIndex:[equipmentKey length] - [@"_DAMAGED" length]];
	}
	OOEquipmentType *eqType = [OOEquipmentType equipmentTypeWithIdentifier:equipmentTypeCheckKey];
	if (eqType == nil)  return;
	
	if ([eqType isMissileOrMine] || ([self isThargoid] && [equipmentTypeCheckKey isEqualToString:@"thargon"]))
	{
		[self removeExternalStore:eqType];
	}
	else
	{
		if ([equipmentKey isEqual:@"EQ_CARGO_BAY"] && [_equipment containsObject:equipmentKey])
		{
			max_cargo -= extra_cargo;
		}
		
		[_equipment removeObject:equipmentKey];
		if (![equipmentKey hasSuffix:@"_DAMAGED"])
		{
			[_equipment removeObject:[equipmentKey stringByAppendingString:@"_DAMAGED"]];
		}
		if ([_equipment count] == 0)  [self removeAllEquipment];
		if (isPlayer)
		{
			if([equipmentKey isEqualToString:@"EQ_ADVANCED_COMPASS"]) [(PlayerEntity*)self setCompassMode:COMPASS_MODE_BASIC];
		}
	}
}


- (BOOL) removeExternalStore:(OOEquipmentType *)eqType
{
	NSString	*identifier = [eqType identifier];
	unsigned	i;
	
	for (i = 0; i < missiles; i++)
	{
		if ([[missile_list[i] identifier] isEqualTo:identifier])
		{
			// now 'delete' [i] by compacting the array
			while ( ++i < missiles ) missile_list[i - 1] = missile_list[i];
			
			missiles--;
			return YES;
		}
	}
	return NO;
}


- (OOEquipmentType *) newMissile
{
	ShipEntity			*missile = nil;
	OOEquipmentType		*missileType = nil;
	BOOL 				isMissileType = NO;
	id 					value;
	double				chance = randf();
	
	if ([self isThargoid])
	{
		if (missileRole != nil)	missile = [UNIVERSE newShipWithRole:missileRole];	// retained
		else missile =  [UNIVERSE newShipWithRole:@"thargon"];	// retained
		missileType = [OOEquipmentType equipmentTypeWithIdentifier:[missile primaryRole]];
		return missileType;
	}
	
	// random role 10% of the cases, if a missile role is defined.
	if (chance < 0.9f && missileRole != nil)  missile = [UNIVERSE newShipWithRole:missileRole];	// retained
	if (missile == nil)	// no actual role defined?
	{
		// random role 20% of the cases. (the 10% above is included here)
		if (chance > 0.8f) missile = [UNIVERSE newShipWithRole:@"missile"];	// retained
		// otherwise use the standard role.
		else missile = [UNIVERSE newShipWithRole:@"EQ_MISSILE"];	// retained
	}
	
	NSEnumerator *enumerator = [[[missile roleSet] roles] objectEnumerator];

	while ((value = [enumerator nextObject])) {
		missileType = [OOEquipmentType equipmentTypeWithIdentifier:(NSString *)value];
		// ensure that we have a missile or mine
		isMissileType = (missileType != nil && [missileType isMissileOrMine]);
		if (isMissileType) break;
	}
	[missile release];

	return (isMissileType ? missileType : nil);
}


- (void) removeAllEquipment
{
	[_equipment release];
	_equipment = nil;
}


- (int) removeMissiles
{
	missiles = 0;
	return 0;
}


- (unsigned) passengerCount
{
	return 0;
}


- (unsigned) passengerCapacity
{
	return 0;
}


- (unsigned) missileCount
{
	return missiles;
}


- (unsigned) missileCapacity
{
	return max_missiles;
}


- (unsigned) extraCargo
{
	return extra_cargo;
}


- (BOOL) hasScoop
{
	return [self hasEquipmentItem:@"EQ_FUEL_SCOOPS"];
}


- (BOOL) hasECM
{
	return [self hasEquipmentItem:@"EQ_ECM"];
}


- (BOOL) hasCloakingDevice
{
	return [self hasEquipmentItem:@"EQ_CLOAKING_DEVICE"];
}


- (BOOL) hasMilitaryScannerFilter
{
#if USEMASC
	return [self hasEquipmentItem:@"EQ_MILITARY_SCANNER_FILTER"];
#else
	return NO;
#endif
}


- (BOOL) hasMilitaryJammer
{
#if USEMASC
	return [self hasEquipmentItem:@"EQ_MILITARY_JAMMER"];
#else
	return NO;
#endif
}


- (BOOL) hasExpandedCargoBay
{
	return [self hasEquipmentItem:@"EQ_CARGO_BAY"];
}


- (BOOL) hasShieldBooster
{
	return [self hasEquipmentItem:@"EQ_SHIELD_BOOSTER"];
}


- (BOOL) hasMilitaryShieldEnhancer
{
	return [self hasEquipmentItem:@"EQ_NAVAL_SHIELD_BOOSTER"];
}


- (BOOL) hasHeatShield
{
	return [self hasEquipmentItem:@"EQ_HEAT_SHIELD"];
}


- (BOOL) hasFuelInjection
{
	return [self hasEquipmentItem:@"EQ_FUEL_INJECTION"];
}


- (BOOL) hasEnergyBomb
{
	return [self hasEquipmentItem:@"EQ_ENERGY_BOMB"];
}


- (BOOL) hasEscapePod
{
	return [self hasEquipmentItem:@"EQ_ESCAPE_POD"];
}


- (BOOL) hasDockingComputer
{
	return [self hasEquipmentItem:@"EQ_DOCK_COMP"];
}


- (BOOL) hasGalacticHyperdrive
{
	return [self hasEquipmentItem:@"EQ_GAL_DRIVE"];
}


- (float) shieldBoostFactor
{
	float boostFactor = 1.0f;
	if ([self hasShieldBooster])  boostFactor += 1.0f;
	if ([self hasMilitaryShieldEnhancer])  boostFactor += 1.0f;
	
	return boostFactor;
}


- (float) maxForwardShieldLevel
{
	return BASELINE_SHIELD_LEVEL * [self shieldBoostFactor];
}


- (float) maxAftShieldLevel
{
	return BASELINE_SHIELD_LEVEL * [self shieldBoostFactor];
}


- (float) shieldRechargeRate
{
	return [self hasMilitaryShieldEnhancer] ? 3.0f : 2.0f;
}


- (float) afterburnerFactor
{
	return 7.0f;
}


- (float) maxThrust
{
	return max_thrust;
}


- (float) thrust
{
	return thrust;
}


////////////////
//            //
// behaviours //
//            //
- (void) behaviour_stop_still:(double) delta_t
{
	double		damping = 0.5 * delta_t;
	// damp roll
	if (flightRoll < 0)
		flightRoll += (flightRoll < -damping) ? damping : -flightRoll;
	if (flightRoll > 0)
		flightRoll -= (flightRoll > damping) ? damping : flightRoll;
	// damp pitch
	if (flightPitch < 0)
		flightPitch += (flightPitch < -damping) ? damping : -flightPitch;
	if (flightPitch > 0)
		flightPitch -= (flightPitch > damping) ? damping : flightPitch;
	[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
	[self applyThrust:delta_t];
}


- (void) behaviour_idle:(double) delta_t
{
	double		damping = 0.5 * delta_t;
	if ((!isStation)&&(scanClass != CLASS_BUOY))
	{
		// damp roll
		if (flightRoll < 0)
			flightRoll += (flightRoll < -damping) ? damping : -flightRoll;
		if (flightRoll > 0)
			flightRoll -= (flightRoll > damping) ? damping : flightRoll;
	}
	if (scanClass != CLASS_BUOY)
	{
		// damp pitch
		if (flightPitch < 0)
			flightPitch += (flightPitch < -damping) ? damping : -flightPitch;
		if (flightPitch > 0)
			flightPitch -= (flightPitch > damping) ? damping : flightPitch;
	}
	[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
	[self applyThrust:delta_t];
}


- (void) behaviour_tumble:(double) delta_t
{
	[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
	[self applyThrust:delta_t];
}


- (void) behaviour_tractored:(double) delta_t
{
	desired_range = collision_radius * 2.0;
	ShipEntity* hauler = (ShipEntity*)[self owner];
	if ((hauler)&&([hauler isShip]))
	{
		destination = [hauler absoluteTractorPosition];
		double  distance = [self rangeToDestination];
		if (distance < desired_range)
		{
			behaviour = BEHAVIOUR_TUMBLE;
			[self setStatus:STATUS_IN_FLIGHT];
			[hauler scoopUp:self];
			return;
		}
		GLfloat tf = TRACTOR_FORCE / mass;
		// adjust for difference in velocity (spring rule)
		Vector dv = vector_between([self velocity], [hauler velocity]);
		GLfloat moment = delta_t * 0.25 * tf;
		velocity.x += moment * dv.x;
		velocity.y += moment * dv.y;
		velocity.z += moment * dv.z;
		// acceleration = force / mass
		// force proportional to distance (spring rule)
		Vector dp = vector_between(position, destination);
		moment = delta_t * 0.5 * tf;
		velocity.x += moment * dp.x;
		velocity.y += moment * dp.y;
		velocity.z += moment * dp.z;
		// force inversely proportional to distance
		GLfloat d2 = magnitude2(dp);
		moment = (d2 > 0.0)? delta_t * 5.0 * tf / d2 : 0.0;
		if (d2 > 0.0)
		{
			velocity.x += moment * dp.x;
			velocity.y += moment * dp.y;
			velocity.z += moment * dp.z;
		}
		//
		if ([self status] == STATUS_BEING_SCOOPED)
		{
			BOOL lost_contact = (distance > hauler->collision_radius + collision_radius + 250.0f);	// 250m range for tractor beam
			if ([hauler isPlayer])
			{
				switch ([(PlayerEntity*)hauler dialFuelScoopStatus])
				{
					case SCOOP_STATUS_NOT_INSTALLED :
					case SCOOP_STATUS_FULL_HOLD :
						lost_contact = YES;	// don't draw
						break;
				}
			}
			//
			if (lost_contact)	// 250m range for tractor beam
			{
				// escaped tractor beam
				[self setStatus:STATUS_IN_FLIGHT];
				behaviour = BEHAVIOUR_IDLE;
				frustration = 0.0;
				[self setOwner:self];
				[shipAI exitStateMachineWithMessage:nil];	// exit nullAI.plist
			}
			else if ([hauler isPlayer])
			{
				[(PlayerEntity*)hauler setScoopsActive];
			}
		}
	}
	[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
	desired_speed = 0.0;
	thrust = 25.0;	// used to damp velocity (must be less than hauler thrust)
	[self applyThrust:delta_t];
	thrust = 0.0;	// must reset thrust now
}


- (void) behaviour_track_target:(double) delta_t
{
	if (primaryTarget == NO_TARGET)
	{
		behaviour = BEHAVIOUR_IDLE;
		frustration = 0.0;
		[self noteLostTarget];
		return;
	}
	[self trackPrimaryTarget:delta_t:NO];
	if ((proximity_alert != NO_TARGET)&&(proximity_alert != primaryTarget))
	{
		[self avoidCollision];
	}
	[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
	[self applyThrust:delta_t];
}


- (void) behaviour_intercept_target:(double) delta_t
{
	double  range = [self rangeToPrimaryTarget];
	if (behaviour == BEHAVIOUR_INTERCEPT_TARGET)
	{
		desired_speed = maxFlightSpeed;
		if (range < desired_range)
		{
			[shipAI reactToMessage:@"DESIRED_RANGE_ACHIEVED"];
		}
		desired_speed = maxFlightSpeed * [self trackPrimaryTarget:delta_t:NO];
	}
	else
	{
		// = BEHAVIOUR_COLLECT_TARGET
		ShipEntity*	target = [self primaryTarget];
		double target_speed = [target speed];
		double eta = range / (flightSpeed - target_speed);
		double last_success_factor = success_factor;
		double last_distance = last_success_factor;
		double  distance = [self rangeToDestination];
		success_factor = distance;
		//
		double slowdownTime = 96.0 / thrust;	// more thrust implies better slowing
		double minTurnSpeedFactor = 0.005 * max_flight_pitch * max_flight_roll;	// faster turning implies higher speeds

		if ((eta < slowdownTime)&&(flightSpeed > maxFlightSpeed * minTurnSpeedFactor))
			desired_speed = flightSpeed * 0.75;   // cut speed by 50% to a minimum minTurnSpeedFactor of speed
		else
			desired_speed = maxFlightSpeed;

		if (desired_speed < target_speed)
		{
			desired_speed += target_speed;
			if (target_speed > maxFlightSpeed)
			{
				behaviour = BEHAVIOUR_IDLE;
				frustration = 0.0;
				[self noteLostTarget];
				return;
			}
		}
		//
		if (target)	// check introduced to stop crash at next line
		{
			destination = target->position;
			desired_range = 0.5 * target->collision_radius;
			[self trackDestination: delta_t : NO];
		}
		else
		{
			behaviour = BEHAVIOUR_IDLE;
			frustration = 0.0;
			[self noteLostTarget];
		}
		//
		if (distance < last_distance)	// improvement
		{
			frustration -= delta_t;
			if (frustration < 0.0)
				frustration = 0.0;
		}
		else
		{
			frustration += delta_t;
			if (frustration > 10.0)	// 10s of frustration
			{
				[shipAI reactToMessage:@"FRUSTRATED"];
				frustration -= 5.0;	//repeat after another five seconds' frustration
			}
		}
	}
	if ((proximity_alert != NO_TARGET)&&(proximity_alert != primaryTarget))
		[self avoidCollision];
	[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
	[self applyThrust:delta_t];
}


- (void) behaviour_attack_target:(double) delta_t
{
	BOOL	canBurn = [self hasFuelInjection] && (fuel > MIN_FUEL);
	float	max_available_speed = maxFlightSpeed;
	double  range = [self rangeToPrimaryTarget];
	if (canBurn) max_available_speed *= [self afterburnerFactor];
	
	[self activateCloakingDevice];
	
	desired_speed = max_available_speed;
	if (range < 0.035 * weaponRange)
		behaviour = BEHAVIOUR_ATTACK_FLY_FROM_TARGET;
	else
		if (universalID & 1)	// 50% of ships are smart S.M.R.T. smart!
		{
			if (randf() < 0.75)
				behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX;
			else
				behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE;
		}
		else
		{
			behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET;
		}
	frustration = 0.0;	// behaviour changed, so reset frustration
	[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
	[self applyThrust:delta_t];
}


- (void) behaviour_fly_to_target_six:(double) delta_t
{
	BOOL	canBurn = [self hasFuelInjection] && (fuel > MIN_FUEL);
	float	max_available_speed = maxFlightSpeed;
	double  range = [self rangeToPrimaryTarget];
	if (canBurn) max_available_speed *= [self afterburnerFactor];
	
	// deal with collisions and lost targets
	if (proximity_alert != NO_TARGET)
	{
		[self avoidCollision];
	}
	if (range > SCANNER_MAX_RANGE || primaryTarget == NO_TARGET)
	{
		behaviour = BEHAVIOUR_IDLE;
		frustration = 0.0;
		[self noteLostTarget];
		return;
	}

	// control speed
	BOOL isUsingAfterburner = canBurn && (flightSpeed > maxFlightSpeed);
	double	slow_down_range = weaponRange * COMBAT_WEAPON_RANGE_FACTOR * ((isUsingAfterburner)? 3.0 * [self afterburnerFactor] : 1.0);
	ShipEntity*	target = [UNIVERSE entityForUniversalID:primaryTarget];
	double target_speed = [target speed];
		double last_success_factor = success_factor; // EW
	double distance = [self rangeToDestination];
		success_factor = distance; // EW
		
	if (range < slow_down_range)
	{
		desired_speed = OOMax_d(target_speed, 0.4 * maxFlightSpeed);
		
		// avoid head-on collision
		if ((range < 0.5 * distance)&&(behaviour == BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX))
			behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE;
	}
	else
		desired_speed = max_available_speed; // use afterburner to approach


	// if within 0.75km of the target's six or twelve then vector in attack
	if (distance < 750.0)
	{
		behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET;
		frustration = 0.0;
		desired_speed = OOMax_d(target_speed, 0.4 * maxFlightSpeed);   // within the weapon's range don't use afterburner
	}

	// target-six
	if (behaviour == BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX)
	{
		// head for a point weapon-range * 0.5 to the six of the target
		//
		destination = [target distance_six:0.5 * weaponRange];
	}
	// target-twelve
	if (behaviour == BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE)
	{
		// head for a point 1.25km above the target
		//
		destination = [target distance_twelve:1250];
	}

	double confidenceFactor = [self trackDestination:delta_t :NO];
	
	if(success_factor > last_success_factor || confidenceFactor < 0.85) frustration += delta_t;  // EW
	else if(frustration > 0.0) frustration -= delta_t;
	if(frustration > 10)  // EW
	{
		frustration = 0.0;
		if (randf() < 0.4) 
		{
			behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET;
		}
		else
		{
			if (randf() < 0.5)
				behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX;
			else
				behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE;
		}
	}

	// use weaponry
	int missile_chance = 0;
	int rhs = 3.2 / delta_t;
	if (rhs)	missile_chance = 1 + (ranrot_rand() % rhs);

	double hurt_factor = 16 * pow(energy/maxEnergy, 4.0);
	if (missiles > missile_chance * hurt_factor)
	{
		[self fireMissile];
	}
	[self activateCloakingDevice];
	[self fireMainWeapon:range];
	[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
	[self applyThrust:delta_t];
}


- (void) behaviour_attack_mining_target:(double) delta_t
{
	double  range = [self rangeToPrimaryTarget];
	if (primaryTarget == NO_TARGET || range > SCANNER_MAX_RANGE) 
	{
		behaviour = BEHAVIOUR_IDLE;
		frustration = 0.0;
		[self noteLostTarget];
		desired_speed = maxFlightSpeed * 0.375;
		return;
	}
	else if ((range < 650) || (proximity_alert != NO_TARGET))
	{
		if (proximity_alert == NO_TARGET)
		{
			desired_speed = range * maxFlightSpeed / (650.0 * 16.0);
		}
		else
		{
			[self avoidCollision];
		}
	}
	else
	{
		//we have a target, its within scanner range, and outside 650
		desired_speed = maxFlightSpeed * 0.375;
	}

	[self trackPrimaryTarget:delta_t:NO];
	[self fireMainWeapon:range];
	[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
	[self applyThrust:delta_t];
}


- (void) behaviour_attack_fly_to_target:(double) delta_t
{
	BOOL	canBurn = [self hasFuelInjection] && (fuel > MIN_FUEL);
	float	max_available_speed = maxFlightSpeed;
	double  range = [self rangeToPrimaryTarget];
	if (canBurn) max_available_speed *= [self afterburnerFactor];
	if (primaryTarget == NO_TARGET)
	{
		behaviour = BEHAVIOUR_IDLE;
		frustration = 0.0;
		[self noteLostTarget];
		return;
	}
	if ((range < COMBAT_IN_RANGE_FACTOR * weaponRange)||(proximity_alert != NO_TARGET))
	{
		if (proximity_alert == NO_TARGET)
		{
			if (aft_weapon_type == WEAPON_NONE)
			{
				jink.x = (ranrot_rand() % 256) - 128.0;
				jink.y = (ranrot_rand() % 256) - 128.0;
				jink.z = 1000.0;
				behaviour = BEHAVIOUR_ATTACK_FLY_FROM_TARGET;
				frustration = 0.0;
				desired_speed = max_available_speed;
			}
			else
			{
				// entering running defense mode
				jink = kZeroVector;
				behaviour = BEHAVIOUR_RUNNING_DEFENSE;
				frustration = 0.0;
				desired_speed = maxFlightSpeed;
			}
		}
		else
		{
			[self avoidCollision];
		}
	}
	else
	{
		if (range > SCANNER_MAX_RANGE)
		{
			behaviour = BEHAVIOUR_IDLE;
			frustration = 0.0;
			[self noteLostTarget];
			return;
		}
	}

	// control speed
	//
	BOOL isUsingAfterburner = canBurn && (flightSpeed > maxFlightSpeed);
	double slow_down_range = weaponRange * COMBAT_WEAPON_RANGE_FACTOR * ((isUsingAfterburner)? 3.0 * [self afterburnerFactor] : 1.0);
	ShipEntity*	target = [UNIVERSE entityForUniversalID:primaryTarget];
	double target_speed = [target speed];
	if (range <= slow_down_range)
		desired_speed = OOMax_d(target_speed, 0.25 * maxFlightSpeed);   // within the weapon's range match speed
	else
		desired_speed = max_available_speed; // use afterburner to approach

	double last_success_factor = success_factor;
	success_factor = [self trackPrimaryTarget:delta_t:NO];	// do the actual piloting
	if ((success_factor > 0.999)||(success_factor > last_success_factor))
	{
		frustration -= delta_t;
		if (frustration < 0.0)
			frustration = 0.0;
	}
	else
	{
		frustration += delta_t;
		if (frustration > 3.0)	// 3s of frustration
		{
			[shipAI reactToMessage:@"FRUSTRATED"];
			// THIS IS HERE AS A TEST ONLY
			// BREAK OFF
			jink.x = (ranrot_rand() % 256) - 128.0;
			jink.y = (ranrot_rand() % 256) - 128.0;
			jink.z = 1000.0;
			behaviour = BEHAVIOUR_ATTACK_FLY_FROM_TARGET;
			frustration = 0.0;
			desired_speed = maxFlightSpeed;
		}
	}

	int missile_chance = 0;
	int rhs = 3.2 / delta_t;
	if (rhs)	missile_chance = 1 + (ranrot_rand() % rhs);

	double hurt_factor = 16 * pow(energy/maxEnergy, 4.0);
	if (missiles > missile_chance * hurt_factor)
	{
		[self fireMissile];
	}
	[self activateCloakingDevice];
	[self fireMainWeapon:range];
	[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
	[self applyThrust:delta_t];
}


- (void) behaviour_attack_fly_from_target:(double) delta_t
{
	double  range = [self rangeToPrimaryTarget];
	if (primaryTarget == NO_TARGET)
	{
		behaviour = BEHAVIOUR_IDLE;
		frustration = 0.0;
		[self noteLostTarget];
		return;
	}
	if (range > COMBAT_OUT_RANGE_FACTOR * weaponRange + 15.0 * jink.x)
	{
		jink.x = 0.0;
		jink.y = 0.0;
		jink.z = 0.0;
		behaviour = BEHAVIOUR_ATTACK_TARGET;
		frustration = 0.0;
	}
	[self trackPrimaryTarget:delta_t:YES];

	int missile_chance = 0;
	int rhs = 3.2 / delta_t;
	if (rhs) missile_chance = 1 + (ranrot_rand() % rhs);

	double hurt_factor = 16 * pow(energy/maxEnergy, 4.0);
	if (missiles > missile_chance * hurt_factor)
	{
		[self fireMissile];
	}
	[self activateCloakingDevice];
	[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
	[self applyThrust:delta_t];
}


- (void) behaviour_running_defense:(double) delta_t
{
	double  range = [self rangeToPrimaryTarget];
	if (range > weaponRange || range > 0.8 * scannerRange || range == 0)
	{
		jink.x = 0.0;
		jink.y = 0.0;
		jink.z = 0.0;
		behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET;
		frustration = 0.0;
	}
	[self trackPrimaryTarget:delta_t:YES];
	[self fireAftWeapon:range];
	[self activateCloakingDevice];
	[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
	[self applyThrust:delta_t];
}


- (void) behaviour_flee_target:(double) delta_t
{
	BOOL	canBurn = [self hasFuelInjection] && (fuel > MIN_FUEL);
	float	max_available_speed = maxFlightSpeed;
	double  range = [self rangeToPrimaryTarget];
	if (canBurn) max_available_speed *= [self afterburnerFactor];
	
	if (range > desired_range || range == 0)
		[shipAI message:@"REACHED_SAFETY"];
	else
		desired_speed = max_available_speed;
	[self trackPrimaryTarget:delta_t:YES];

	int missile_chance = 0;
	int rhs = 3.2 / delta_t;
	if (rhs)	missile_chance = 1 + (ranrot_rand() % rhs);

	if (([self hasEnergyBomb]) && (range < 10000.0) && canBurn)
	{
		float	qbomb_chance = 0.01 * delta_t;
		if (randf() < qbomb_chance)
		{
			[self launchEnergyBomb];
		}
	}

	double hurt_factor = 16 * pow(energy/maxEnergy, 4.0);
	if (([(ShipEntity *)[self primaryTarget] primaryTarget] == self)&&(missiles > missile_chance * hurt_factor))
		[self fireMissile];
	[self activateCloakingDevice];
	[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
	[self applyThrust:delta_t];
}


- (void) behaviour_fly_range_from_destination:(double) delta_t
{
	double distance = [self rangeToDestination];
	if (distance < desired_range)
	{
		behaviour = BEHAVIOUR_FLY_FROM_DESTINATION;
		desired_speed = maxFlightSpeed;  // Not all AI define speed when flying away. Start with max speed to stay compatible with such AI's.
	}
	else
	{
		behaviour = BEHAVIOUR_FLY_TO_DESTINATION;
	}
	if (proximity_alert != NO_TARGET)
	{
		[self avoidCollision];
	}
	frustration = 0.0;
	[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
	[self applyThrust:delta_t];
}


- (void) behaviour_face_destination:(double) delta_t
{
	double max_cos = 0.995;
	double distance = [self rangeToDestination];
	double old_pitch = flightPitch;
	desired_speed = 0.0;
	if (desired_range > 1.0 && distance > desired_range)
		max_cos = sqrt(1 - 0.90 * desired_range*desired_range/(distance * distance));   // Head for a point within 95% of desired_range (must match the value in trackDestination)
	else
		max_cos = 0.995;	// 0.995 - cos(5 degrees) is close enough
	double confidenceFactor = [self trackDestination:delta_t:NO];
	if (confidenceFactor >= max_cos)
	{
		// desired facing achieved
		[shipAI message:@"FACING_DESTINATION"];
		frustration = 0.0;
		if(docking_match_rotation)  // IDLE stops rotating while docking
		{
			behaviour = BEHAVIOUR_FLY_TO_DESTINATION;
		}
		else
		{
			behaviour = BEHAVIOUR_IDLE;
		}
	}

	if(flightSpeed == 0) frustration += delta_t;
	if (frustration > 15.0 / max_flight_pitch)	// allow more time for slow ships.
	{
		frustration = 0.0;
		[shipAI reactToMessage:@"FRUSTRATED"];
		if(flightPitch == old_pitch) flightPitch = 0.5 * max_flight_pitch; // hack to get out of frustration.
	}	
	
	/* 2009-7-18 Eric: the condition check below is intended to eliminate the flippering between two positions for fast turning ships
	   during low FPS conditions. This flippering is particular frustrating on slow computers during docking. But with my current computer I can't
	   induce those low FPS conditions so I can't properly test if it helps.
	   I did try with the TAF time acceleration that also generated larger frame jumps and than it seemed to help.
	*/
	if(flightSpeed == 0 && frustration > 5 && confidenceFactor > 0.5 && ((flightPitch > 0 && old_pitch < 0) || (flightPitch < 0 && old_pitch > 0)))
	{
		flightPitch += 0.5 * old_pitch; // damping with last pitch value.
	}
	
	if ((proximity_alert != NO_TARGET)&&(proximity_alert != primaryTarget))
		[self avoidCollision];
	[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
	[self applyThrust:delta_t];
}


- (void) behaviour_formation_form_up:(double) delta_t
{
	// destination for each escort is set in update() from owner.
	ShipEntity* leadShip = [self owner];
	double distance = [self rangeToDestination];
	double eta = (distance - desired_range) / flightSpeed;
	if(eta < 0) eta = 0;
	if ((eta < 5.0)&&(leadShip)&&(leadShip->isShip))
		desired_speed = [leadShip flightSpeed] * (1 + eta * 0.05); // EW: This code works better, specialy at low speeds.
		// desired_speed = [leadShip flightSpeed] * 1.25; // EW Original code, escorts always fly 25% to fast or drop speed 50% later on.
		// this speed dropping does not work well at low speeds leading to escorts "waggling".
	else
		desired_speed = maxFlightSpeed;

	double last_distance = success_factor;
	success_factor = distance;

	// do the actual piloting!!
	[self trackDestination:delta_t: NO];

	eta = eta / 0.51;	// 2% safety margin assuming an average of half current speed
	GLfloat slowdownTime = (thrust > 0.0)? flightSpeed / thrust : 4.0;
	GLfloat minTurnSpeedFactor = 0.05 * max_flight_pitch * max_flight_roll;	// faster turning implies higher speeds

	if ((eta < slowdownTime)&&(flightSpeed > maxFlightSpeed * minTurnSpeedFactor))
		desired_speed = flightSpeed * 0.50;   // cut speed by 50% to a minimum minTurnSpeedFactor of speed
		
	if (distance < last_distance)	// improvement
	{
		frustration -= 0.25 * delta_t;
		if (frustration < 0.0)
			frustration = 0.0;
	}
	else
	{
		frustration += delta_t;
		if (frustration > 15.0)
		{
			if (!leadShip) [shipAI reactToMessage:@"FRUSTRATED"]; // escorts never reach their destination when following leader.
			else if (distance > 0.5 * scannerRange) 
			{
				flightPitch = max_flight_pitch; // hack to get out of frustration.
			}
			frustration = 0;
		}
	}
	if ((proximity_alert != NO_TARGET)&&(proximity_alert != primaryTarget))
		[self avoidCollision];
	[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
	[self applyThrust:delta_t];
}


- (void) behaviour_fly_to_destination:(double) delta_t
{
	double distance = [self rangeToDestination];
	if (distance < desired_range)// + collision_radius)
	{
		// desired range achieved
		[shipAI message:@"DESIRED_RANGE_ACHIEVED"];
		if(!docking_match_rotation) // IDLE stops rotating while docking
		{
			behaviour = BEHAVIOUR_IDLE;
			desired_speed = 0.0;
		}
		frustration = 0.0;
	}
	else
	{
		double last_distance = success_factor;
		success_factor = distance;

		// do the actual piloting!!
		double confidenceFactor = [self trackDestination:delta_t: NO];
		if(confidenceFactor < 0.2) confidenceFactor = 0.2;  // don't allow small or negative values.
		
		/*	2009-07-19 Eric: Estimated Time of Arrival (eta) should also take the "angle to target" into account (confidenceFactor = cos(angle to target))
			and should not fuss about that last meter and use "distance + 1" instead of just "distance".
			trackDestination already did pitch regulation, use confidence here only for cutting down to high speeds.
			This should prevent ships crawling to their destination when they try to pull up close to their destination.
			
			To prevent ships circling around their target without reaching destination I added a limitation based on turnrate,
			speed and distance to target. Formula based on satelite orbit:
					orbitspeed = turnrate (rad/sec) * radius (m)   or   flightSpeed = max_flight_pitch * 2 Pi * distance
			Speed must be significant lower when not flying in direction of target (low confidenceFactor) or it can never approach its destination 
			and the ships runs the risk flying in circles around the target. (exclude active escorts)
		*/
		GLfloat eta = ((distance + 1) - desired_range) / (0.51 * flightSpeed * confidenceFactor);	// 2% safety margin assuming an average of half current speed
		GLfloat slowdownTime = (thrust > 0.0)? flightSpeed / thrust : 4.0;
		GLfloat minTurnSpeedFactor = 0.05 * max_flight_pitch * max_flight_roll;	// faster turning implies higher speeds

		if (((eta < slowdownTime)&&(flightSpeed > maxFlightSpeed * minTurnSpeedFactor)) || (flightSpeed > max_flight_pitch * 5 * confidenceFactor * distance))
			desired_speed = flightSpeed * 0.50;   // cut speed by 50% to a minimum minTurnSpeedFactor of speed
			
		if (distance < last_distance)	// improvement
		{
			frustration -= 0.25 * delta_t;
			if (frustration < 0.0)
				frustration = 0.0;
		}
		else
		{
			frustration += delta_t;
			if ((frustration > slowdownTime * 10.0 && slowdownTime > 0)||(frustration > 15.0))	// 10x slowdownTime or 15s of frustration
			{
				[shipAI reactToMessage:@"FRUSTRATED"];
				frustration -= slowdownTime * 5.0;	//repeat after another five units of frustration
			}
		}
	}
	if ((proximity_alert != NO_TARGET)&&(proximity_alert != primaryTarget))
		[self avoidCollision];
	[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
	[self applyThrust:delta_t];
}


- (void) behaviour_fly_from_destination:(double) delta_t
{
	double distance = [self rangeToDestination];
	if (distance > desired_range)
	{
		// desired range achieved
		[shipAI message:@"DESIRED_RANGE_ACHIEVED"];
		behaviour = BEHAVIOUR_IDLE;
		frustration = 0.0;
		desired_speed = 0.0;
	}

	[self trackDestination:delta_t:YES];
	if ((proximity_alert != NO_TARGET)&&(proximity_alert != primaryTarget))
		[self avoidCollision];
	[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
	[self applyThrust:delta_t];
}


- (void) behaviour_avoid_collision:(double) delta_t
{
	double distance = [self rangeToDestination];
	if (distance > desired_range)
	{
		[self resumePostProximityAlert];
	}
	else
	{
		ShipEntity* prox_ship = [self proximity_alert];
		if (prox_ship)
		{
			desired_range = prox_ship->collision_radius * PROXIMITY_AVOID_DISTANCE_FACTOR;
			destination = prox_ship->position;
		}
		double dq = [self trackDestination:delta_t:YES];
		if (dq >= 0)
			dq = 0.5 * dq + 0.5;
		else
			dq = 0.0;
		desired_speed = maxFlightSpeed * dq;
	}
	[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
	[self applyThrust:delta_t];
}


- (void) behaviour_track_as_turret:(double) delta_t
{
	double aim = [self ballTrackLeadingTarget:delta_t];
	ShipEntity *turret_owner = (ShipEntity *)[self owner];
	ShipEntity *turret_target = (ShipEntity *)[turret_owner primaryTarget];
	
	if (turret_owner && turret_target && [turret_owner hasHostileTarget])
	{
		Vector p = vector_subtract([turret_target position], [turret_owner position]);
		double cr = [turret_owner collisionRadius];
		
		if (aim > .95)
		{
			[self fireTurretCannon:magnitude(p) - cr];
		}
	}
}


- (void) behaviour_fly_thru_navpoints:(double) delta_t
{
	int navpoint_plus_index = (next_navpoint_index + 1) % number_of_navpoints;
	Vector d1 = navpoints[next_navpoint_index];		// head for this one
	Vector d2 = navpoints[navpoint_plus_index];	// but be facing this one
	
	Vector rel = vector_between(d1, position);	// vector from d1 to position 
	Vector ref = vector_between(d2, d1);		// vector from d2 to d1
	ref = vector_normal(ref);
	
	Vector xp = make_vector(ref.y * rel.z - ref.z * rel.y, ref.z * rel.x - ref.x * rel.z, ref.x * rel.y - ref.y * rel.x);	
	
	GLfloat v0 = 0.0;
	
	GLfloat	r0 = dot_product(rel, ref);	// proportion of rel in direction ref
	
	// if r0 is negative then we're the wrong side of things
	
	GLfloat	r1 = magnitude(xp);	// distance of position from line
	
	BOOL in_cone = (r0 > 0.5 * r1);
	
	if (!in_cone)	// are we in the approach cone ?
		r1 = 25.0 * flightSpeed;	// aim a few km out!
	else
		r1 *= 2.0;
	
	GLfloat dist2 = magnitude2(rel);
	
	if (dist2 < desired_range * desired_range)
	{
		// desired range achieved
		[self doScriptEvent:@"shipReachedNavPoint" andReactToAIMessage:@"NAVPOINT_REACHED"];
		if (navpoint_plus_index == 0)
		{
			[self doScriptEvent:@"shipReachedEndPoint" andReactToAIMessage:@"ENDPOINT_REACHED"];
			behaviour = BEHAVIOUR_IDLE;
		}
		next_navpoint_index = navpoint_plus_index;	// loop as required
	}
	else
	{
		double last_success_factor = success_factor;
		double last_dist2 = last_success_factor;
		success_factor = dist2;

		// set destination spline point from r1 and ref
		destination = make_vector(d1.x + r1 * ref.x, d1.y + r1 * ref.y, d1.z + r1 * ref.z);

		// do the actual piloting!!
		//
		// aim to within 1m
		GLfloat temp = desired_range;
		if (in_cone)
			desired_range = 1.0;
		else
			desired_range = 100.0;
		v0 = [self trackDestination:delta_t: NO];
		desired_range = temp;
		
		if (dist2 < last_dist2)	// improvement
		{
			frustration -= 0.25 * delta_t;
			if (frustration < 0.0)
				frustration = 0.0;
		}
		else
		{
			frustration += delta_t;
			if (frustration > 15.0)	// 15s of frustration
			{
				[shipAI reactToMessage:@"FRUSTRATED"];
				frustration -= 15.0;	//repeat after another 15s of frustration
			}
		}
	}
	
	[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
	GLfloat temp = desired_speed;
	desired_speed *= v0 * v0;
	[self applyThrust:delta_t];
	desired_speed = temp;
}


#if BALL_WORLD
- (void)drawEntity2:(BOOL)immediate :(BOOL)translucent
{
	if (no_draw_distance < zero_distance)
	{
		// Don't draw.
		return;
	}
	
	if ([UNIVERSE wireframeGraphics])  GLDebugWireframeModeOn();
	
	OOPlanetDrawable *ball = [OOPlanetDrawable planetWithTextureName:@"oolite-planet-temp.png" radius:[[self mesh] collisionRadius] eccentricity:0];
	
	if (translucent)  [ball renderTranslucentParts];
	else  [ball renderOpaqueParts];
	
	if ([UNIVERSE wireframeGraphics])  GLDebugWireframeModeOff();
}
#endif


- (void)drawEntity:(BOOL)immediate :(BOOL)translucent
{
	NSEnumerator				*subEntityEnum = nil;
	ShipEntity					*subEntity = nil;
	
	if ((no_draw_distance < zero_distance) ||	// Done redundantly to skip subentities
		(cloaking_device_active && randf() > 0.10))
	{
		// Don't draw.
		return;
	}
	
	// Draw self.
#if BALL_WORLD
	[self drawEntity2:immediate :translucent];
#else
	[super drawEntity:immediate :translucent];
#endif

#ifndef NDEBUG
	// Draw bounding boxes if we have to before going for the subentities.
	// TODO: the translucent flag here makes very little sense. Something's wrong with the matrices.
	if (translucent)  [self drawDebugStuff];
	else if (gDebugFlags & DEBUG_BOUNDING_BOXES && ![self isSubEntity])
	{
		OODebugDrawBoundingBox([self boundingBox]);
		OODebugDrawColoredBoundingBox(totalBoundingBox, [OOColor purpleColor]);
	}
#endif
	
	// Draw subentities.
	if (!immediate)	// TODO: is this relevant any longer?
	{
		for (subEntityEnum = [self subEntityEnumerator]; (subEntity = [subEntityEnum nextObject]); )
		{
			[subEntity setOwner:self]; // refresh ownership
			[subEntity drawSubEntity:immediate :translucent];
		}
	}
}


#ifndef NDEBUG
- (void) drawDebugStuff
{
	
	if (reportAIMessages)
	{
		OODebugDrawPoint(destination, [OOColor blueColor]);
		OODebugDrawColoredLine([self position], destination, [OOColor colorWithCalibratedWhite:0.15 alpha:1.0]);
		
		Entity *pTarget = [self primaryTarget];
		if (pTarget != nil)
		{
			OODebugDrawPoint([pTarget position], [OOColor redColor]);
			OODebugDrawColoredLine([self position], [pTarget position], [OOColor colorWithCalibratedRed:0.2 green:0.0 blue:0.0 alpha:1.0]);
		}
		
		Entity *sTarget = [UNIVERSE entityForUniversalID:targetStation];
		if (sTarget != pTarget && [sTarget isStation])
		{
			OODebugDrawPoint([sTarget position], [OOColor cyanColor]);
		}
		
		Entity *fTarget = [UNIVERSE entityForUniversalID:found_target];
		if (fTarget != nil && fTarget != pTarget && fTarget != sTarget)
		{
			OODebugDrawPoint([fTarget position], [OOColor magentaColor]);
		}
	}
}
#endif


- (void) drawSubEntity:(BOOL) immediate :(BOOL) translucent
{
	Entity* my_owner = [self owner];
	if (my_owner)
	{
		// this test provides an opportunity to do simple LoD culling
		zero_distance = [my_owner zeroDistance];
		if (zero_distance > no_draw_distance)
		{
			return; // TOO FAR AWAY
		}
	}
	
	if ([self status] == STATUS_ACTIVE)
	{
		Vector abspos = position;  // STATUS_ACTIVE means it is in control of it's own orientation
		Entity		*last = nil;
		Entity		*father = my_owner;
		OOMatrix	r_mat;
		
		while ((father)&&(father != last)  &&father != NO_TARGET)
		{
			r_mat = [father drawRotationMatrix];
			abspos = vector_add(OOVectorMultiplyMatrix(abspos, r_mat), [father position]);
			last = father;
			if (![last isSubEntity]) break;
				father = [father owner];
		}
		
		GLLoadOOMatrix([UNIVERSE viewMatrix]);
		OOGL(glPopMatrix());
		OOGL(glPushMatrix());
		GLTranslateOOVector(abspos);
		GLMultOOMatrix(rotMatrix);
		
		[self drawEntity:immediate :translucent];
	}
	else
	{
		OOGL(glPushMatrix());
		
		GLTranslateOOVector(position);
		GLMultOOMatrix(rotMatrix);
		
		[self drawEntity:immediate :translucent];
		
		OOGL(glPopMatrix());
	}
	
#ifndef NDEBUG
	if (gDebugFlags & DEBUG_BOUNDING_BOXES)
	{
		OODebugDrawBoundingBox([self boundingBox]);
	}
#endif
		
}


static GLfloat cargo_color[4] =		{ 0.9, 0.9, 0.9, 1.0};	// gray
static GLfloat hostile_color[4] =	{ 1.0, 0.25, 0.0, 1.0};	// red/orange
static GLfloat neutral_color[4] =	{ 1.0, 1.0, 0.0, 1.0};	// yellow
static GLfloat friendly_color[4] =	{ 0.0, 1.0, 0.0, 1.0};	// green
static GLfloat missile_color[4] =	{ 0.0, 1.0, 1.0, 1.0};	// cyan
static GLfloat police_color1[4] =	{ 0.5, 0.0, 1.0, 1.0};	// purpley-blue
static GLfloat police_color2[4] =	{ 1.0, 0.0, 0.5, 1.0};	// purpley-red
static GLfloat jammed_color[4] =	{ 0.0, 0.0, 0.0, 0.0};	// clear black
static GLfloat mascem_color1[4] =	{ 0.3, 0.3, 0.3, 1.0};	// dark gray
static GLfloat mascem_color2[4] =	{ 0.4, 0.1, 0.4, 1.0};	// purple
static GLfloat scripted_color[4] = 	{ 0.0, 0.0, 0.0, 0.0};	// to be defined by script

- (GLfloat *) scannerDisplayColorForShip:(ShipEntity*)otherShip :(BOOL)isHostile :(BOOL)flash :(OOColor *)scannerDisplayColor1 :(OOColor *)scannerDisplayColor2
{
	// if there are any scripted scanner display colors for the ship, use them
	if (scannerDisplayColor1 || scannerDisplayColor2)
	{
		if (scannerDisplayColor1 && !scannerDisplayColor2)
		{
			[scannerDisplayColor1 getGLRed:&scripted_color[0] green:&scripted_color[1] blue:&scripted_color[2] alpha:&scripted_color[3]];
		}
		
		if (!scannerDisplayColor1 && scannerDisplayColor2)
		{
			[scannerDisplayColor2 getGLRed:&scripted_color[0] green:&scripted_color[1] blue:&scripted_color[2] alpha:&scripted_color[3]];
		}
		
		if (scannerDisplayColor1 && scannerDisplayColor2)
		{
			if (flash)
				[scannerDisplayColor1 getGLRed:&scripted_color[0] green:&scripted_color[1] blue:&scripted_color[2] alpha:&scripted_color[3]];
			else
				[scannerDisplayColor2 getGLRed:&scripted_color[0] green:&scripted_color[1] blue:&scripted_color[2] alpha:&scripted_color[3]];
		}
		
		return scripted_color;
	}

	// no scripted scanner display colors defined, proceed as per standard
	if ([self isJammingScanning])
	{
		if (![otherShip hasMilitaryScannerFilter])
			return jammed_color;
		else
		{
			if (flash)
				return mascem_color1;
			else
			{
				if (isHostile)
					return hostile_color;
				else
					return mascem_color2;
			}
		}
	}

	switch (scanClass)
	{
		case CLASS_ROCK :
		case CLASS_CARGO :
			return cargo_color;
		case CLASS_THARGOID :
			if (flash)
				return hostile_color;
			else
				return friendly_color;
		case CLASS_MISSILE :
			return missile_color;
		case CLASS_STATION :
			return friendly_color;
		case CLASS_BUOY :
			if (flash)
				return friendly_color;
			else
				return neutral_color;
		case CLASS_POLICE :
		case CLASS_MILITARY :
			if ((isHostile)&&(flash))
				return police_color2;
			else
				return police_color1;
		case CLASS_MINE :
			if (flash)
				return neutral_color;
			else
				return hostile_color;
		default :
			if (isHostile)
				return hostile_color;
	}
	return neutral_color;
}


- (void)setScannerDisplayColor1:(OOColor *)color1
{
	[scanner_display_color1 release];
	scanner_display_color1 = nil;
	if (color1)
	{
		scanner_display_color1 = [color1 retain];
	}
}


- (void)setScannerDisplayColor2:(OOColor *)color2
{
	[scanner_display_color2 release];
	scanner_display_color2 = nil;
	if (color2)
	{
		scanner_display_color2 = [color2 retain];
	}
}


- (OOColor *)scannerDisplayColor1
{
	return [[scanner_display_color1 retain] autorelease];
}


- (OOColor *)scannerDisplayColor2
{
	return [[scanner_display_color2 retain] autorelease];
}


- (BOOL)isCloaked
{
	return cloaking_device_active;
}


- (void)setCloaked:(BOOL)cloak
{
	if (cloak)  [self activateCloakingDevice];
	else  [self deactivateCloakingDevice];
}


- (BOOL) isJammingScanning
{
	return ([self hasMilitaryJammer] && military_jammer_active);
}


- (void) addSubEntity:(Entity *)sub
{
	if (sub == nil)  return;
	
	if (subEntities == nil)  subEntities = [[NSMutableArray alloc] init];
	sub->isSubEntity = YES;
	// Order matters - need consistent state in setOwner:. -- Ahruman 2008-04-20
	[subEntities addObject:sub];
	[sub setOwner:self];
	
	[self addSubentityToCollisionRadius:sub];
}


- (void) setOwner:(Entity *)who_owns_entity
{
	[super setOwner:who_owns_entity];
	
	/*	Reset shader binding target so that bind-to-super works.
		This is necessary since we don't know about the owner in
		setUpShipFromDictionary:, when the mesh is initially set up.
		-- Ahruman 2008-04-19
	*/
	OODrawable *drawable_ = [self drawable];
	if (isSubEntity)
	{
		[drawable_ setBindingTarget:self];
	}
}


- (void) applyThrust:(double) delta_t
{
	GLfloat dt_thrust = thrust * delta_t;
	BOOL	canBurn = [self hasFuelInjection] && (fuel > MIN_FUEL);
	BOOL	isUsingAfterburner = (canBurn && (flightSpeed > maxFlightSpeed) && (desired_speed >= flightSpeed));
	float	max_available_speed = maxFlightSpeed;
	if (canBurn) max_available_speed *= [self afterburnerFactor];
	
	position = vector_add(position, vector_multiply_scalar(velocity, delta_t));
	
	if (thrust)
	{
		GLfloat velmag = magnitude(velocity);
		if (velmag)
		{
			GLfloat vscale = fmaxf((velmag - dt_thrust) / velmag, 0.0f);
			scale_vector(&velocity, vscale);
		}
	}

	if (behaviour == BEHAVIOUR_TUMBLE)  return;

	// check for speed
	if (desired_speed > max_available_speed)
		desired_speed = max_available_speed;

	if (flightSpeed > desired_speed)
	{
		[self decrease_flight_speed: dt_thrust];
		if (flightSpeed < desired_speed)   flightSpeed = desired_speed;
	}
	if (flightSpeed < desired_speed)
	{
		[self increase_flight_speed: dt_thrust];
		if (flightSpeed > desired_speed)   flightSpeed = desired_speed;
	}
	[self moveForward: delta_t*flightSpeed];

	// burn fuel at the appropriate rate
	if (isUsingAfterburner) // no fuelconsumption on slowdown
	{
		fuel_accumulator -= delta_t * AFTERBURNER_NPC_BURNRATE;
		while (fuel_accumulator < 0.0)
		{
			fuel--;
			fuel_accumulator += 1.0;
		}
	}
}


- (void) orientationChanged
{
	[super orientationChanged];
	
	v_forward   = vector_forward_from_quaternion(orientation);
	v_up		= vector_up_from_quaternion(orientation);
	v_right		= vector_right_from_quaternion(orientation);
}


- (void) applyRoll:(GLfloat) roll1 andClimb:(GLfloat) climb1
{
	Quaternion q1 = kIdentityQuaternion;

	if (!roll1 && !climb1 && !hasRotated)  return;

	if (roll1)  quaternion_rotate_about_z(&q1, -roll1);
	if (climb1)  quaternion_rotate_about_x(&q1, -climb1);

	orientation = quaternion_multiply(q1, orientation);
	[self orientationChanged];
}


- (void) avoidCollision
{
	if (scanClass == CLASS_MISSILE)
		return;						// missiles are SUPPOSED to collide!
	
	ShipEntity* prox_ship = [self proximity_alert];

	if (prox_ship)
	{
		if (previousCondition)
		{
			[previousCondition release];
			previousCondition = nil;
		}

		previousCondition = [[NSMutableDictionary dictionaryWithCapacity:5] retain];
		
		[previousCondition oo_setInteger:behaviour forKey:@"behaviour"];
		[previousCondition oo_setInteger:primaryTarget forKey:@"primaryTarget"];
		[previousCondition oo_setFloat:desired_range forKey:@"desired_range"];
		[previousCondition oo_setFloat:desired_speed forKey:@"desired_speed"];
		[previousCondition oo_setVector:destination forKey:@"destination"];
		
		destination = [prox_ship position];
		destination = OOVectorInterpolate(position, [prox_ship position], 0.5);		// point between us and them
		
		desired_range = prox_ship->collision_radius * PROXIMITY_AVOID_DISTANCE_FACTOR;
		
		behaviour = BEHAVIOUR_AVOID_COLLISION;
	}
}


- (void) resumePostProximityAlert
{
	if (!previousCondition)  return;
	
	behaviour =		[previousCondition oo_intForKey:@"behaviour"];
	primaryTarget =	[previousCondition oo_intForKey:@"primaryTarget"];
	desired_range =	[previousCondition oo_floatForKey:@"desired_range"];
	desired_speed =	[previousCondition oo_floatForKey:@"desired_speed"];
	destination =	[previousCondition oo_vectorForKey:@"destination"];
	
	[previousCondition release];
	previousCondition = nil;
	frustration = 0.0;
	
	proximity_alert = NO_TARGET;
	
	//[shipAI message:@"RESTART_DOCKING"];	// if docking, start over, other AIs will ignore this message
}


- (double) messageTime
{
	return messageTime;
}


- (void) setMessageTime:(double) value
{
	messageTime = value;
}


- (OOShipGroup *) group
{
	return _group;
}


- (void) setGroup:(OOShipGroup *)group
{
	if (group != _group)
	{
		if (_escortGroup != _group) 
		{
			if (self == [_group leader])  [_group setLeader:nil];
			[_group removeShip:self];
		}
		[_group release];
		[group addShip:self];
		_group = [group retain];
	}
}


- (OOShipGroup *) escortGroup
{
	if (_escortGroup == nil)
	{
		_escortGroup = [[OOShipGroup alloc] initWithName:@"escort group"];
		[_escortGroup setLeader:self];
	}
	
	return _escortGroup;
}


#ifndef NDEBUG
- (OOShipGroup *) rawEscortGroup
{
	return _escortGroup;
}
#endif


- (OOShipGroup *) stationGroup
{
	if (_group == nil)
	{
		_group = [[OOShipGroup alloc] initWithName:@"station group"];
		[_group setLeader:self];
	}
	
	return _group;
}


- (BOOL) hasEscorts
{
	if (_escortGroup == nil)  return NO;
	return [_escortGroup count] > 1;	// If only one memeber, it's self.
}


- (NSEnumerator *) escortEnumerator
{
	if (_escortGroup == nil)  return [[NSArray array] objectEnumerator];
	return [[_escortGroup objectEnumerator] ooExcludingObject:self];
}


- (NSArray *) escortArray
{
	if (_escortGroup == nil)  return [NSArray array];
	return [[self escortEnumerator] allObjects];
}


- (uint8_t) escortCount
{
	if (_escortGroup == nil)  return 0;
	return [_escortGroup count] - 1;
}


- (uint8_t) pendingEscortCount
{
	return _pendingEscortCount;
}


- (void) setPendingEscortCount:(uint8_t)count
{
	_pendingEscortCount = count;
}


- (ShipEntity*) proximity_alert
{
	return [UNIVERSE entityForUniversalID:proximity_alert];
}


- (void) setProximity_alert:(ShipEntity*) other
{
	if (!other)
	{
		proximity_alert = NO_TARGET;
		return;
	}

	if (isStation || (other->isStation)) // don't be alarmed close to stations -- is this sensible? we dont mind crashing into carriers?
		return;

	if ((scanClass == CLASS_CARGO)||(scanClass == CLASS_BUOY)||(scanClass == CLASS_MISSILE)||(scanClass == CLASS_ROCK))	// rocks and stuff don't get alarmed easily
		return;

	// check vectors
	Vector vdiff = vector_between(position, other->position);
	GLfloat d_forward = dot_product(vdiff, v_forward);
	GLfloat d_up = dot_product(vdiff, v_up);
	GLfloat d_right = dot_product(vdiff, v_right);
	if ((d_forward > 0.0)&&(flightSpeed > 0.0))	// it's ahead of us and we're moving forward
		d_forward *= 0.25 * maxFlightSpeed / flightSpeed;	// extend the collision zone forward up to 400%
	double d2 = d_forward * d_forward + d_up * d_up + d_right * d_right;
	double cr2 = collision_radius * 2.0 + other->collision_radius;	cr2 *= cr2;	// check with twice the combined radius

	if (d2 > cr2) // we're okay
		return;

	if (behaviour == BEHAVIOUR_AVOID_COLLISION)	//	already avoiding something
	{
		ShipEntity* prox = [UNIVERSE entityForUniversalID:proximity_alert];
		if ((prox)&&(prox != other))
		{
			// check which subtends the greatest angle
			GLfloat sa_prox = prox->collision_radius * prox->collision_radius / distance2(position, prox->position);
			GLfloat sa_other = other->collision_radius *  other->collision_radius / distance2(position, other->position);
			if (sa_prox < sa_other)  return;
		}
	}
	proximity_alert = [other universalID];
}


- (NSString *) name
{
	return name;
}


- (NSString *) displayName
{
	if (displayName == nil)  return name;
	return displayName;
}


- (void) setName:(NSString *)inName
{
	[name release];
	name = [inName copy];
}


- (void) setDisplayName:(NSString *)inName
{
	[displayName release];
	displayName = [inName copy];
}


- (NSString *) identFromShip:(ShipEntity*) otherShip
{
	if ([self isJammingScanning] && ![otherShip hasMilitaryScannerFilter])
	{
		return DESC(@"unknown-target");
	}
	return displayName;
}


- (BOOL) hasRole:(NSString *)role
{
	return [roleSet hasRole:role] || [role isEqual:primaryRole];
}


- (OORoleSet *)roleSet
{
	if (roleSet == nil)  roleSet = [[OORoleSet alloc] initWithRoleString:primaryRole];
	return [roleSet roleSetWithAddedRoleIfNotSet:primaryRole probability:1.0];
}


- (NSString *)primaryRole
{
	if (primaryRole == nil)
	{
		primaryRole = [roleSet anyRole];
		if (primaryRole == nil)  primaryRole = @"trader";
		[primaryRole retain];
		OOLog(@"ship.noPrimaryRole", @"%@ had no primary role, randomly selected \"%@\".", [self name], primaryRole);
	}
	
	return primaryRole;
}


// Exposed to AI.
- (void)setPrimaryRole:(NSString *)role
{
	if (![role isEqual:primaryRole])
	{
		[primaryRole release];
		primaryRole = [role copy];
	}
}


- (BOOL)hasPrimaryRole:(NSString *)role
{
	return [[self primaryRole] isEqual:role];
}


- (BOOL)isPolice
{
	//bounty hunters have a police role, but are not police, so we must test by scan class, not by role
	return [self scanClass] == CLASS_POLICE;
}

- (BOOL)isThargoid
{
	return [self scanClass] == CLASS_THARGOID;
}


- (BOOL)isTrader
{
	return isPlayer || [self hasPrimaryRole:@"trader"];
}


- (BOOL)isPirate
{
	return [self hasPrimaryRole:@"pirate"];
}


- (BOOL)isMissile
{
	return ([[self primaryRole] hasSuffix:@"MISSILE"] || [self hasPrimaryRole:@"missile"]);
}


- (BOOL)isMine
{
	return [[self primaryRole] hasSuffix:@"MINE"];
}


- (BOOL)isWeapon
{
	return [self isMissile] || [self isMine];
}


- (BOOL)isEscort
{
	return [self hasPrimaryRole:@"escort"] || [self hasPrimaryRole:@"wingman"];
}


- (BOOL)isShuttle
{
	return [self hasPrimaryRole:@"shuttle"];
}


- (BOOL)isPirateVictim
{
	return [UNIVERSE roleIsPirateVictim:[self primaryRole]];
}


- (BOOL)isUnpiloted
{
	return isUnpiloted;
}


// Exposed to shaders.
- (BOOL) hasHostileTarget
{
	if (primaryTarget == NO_TARGET)
		return NO;
	if ([self isMissile])
		return YES;	// missiles are always fired against a hostile target
	if ((behaviour == BEHAVIOUR_AVOID_COLLISION)&&(previousCondition))
	{
		int old_behaviour = [previousCondition oo_intForKey:@"behaviour"];
		return IsBehaviourHostile(old_behaviour);
	}
	return IsBehaviourHostile(behaviour);
}


- (GLfloat) weaponRange
{
	return weaponRange;
}


- (void) setWeaponRange: (GLfloat) value
{
	weaponRange = value;
}


- (void) setWeaponDataFromType: (OOWeaponType) weapon_type
{
	switch (weapon_type)
	{
		case WEAPON_PLASMA_CANNON:
			weapon_energy =			6.0;
			weapon_recharge_rate =	0.25;
			weaponRange =			5000;
			break;
		case WEAPON_PULSE_LASER:
			weapon_energy =			15.0;
			weapon_recharge_rate =	0.33;
			weaponRange =			12500;
			break;
		case WEAPON_BEAM_LASER:
			weapon_energy =			15.0;
			weapon_recharge_rate =	0.25;
			weaponRange =			15000;
			break;
		case WEAPON_MINING_LASER:
			weapon_energy =			50.0;
			weapon_recharge_rate =	0.5;
			weaponRange =			12500;
			break;
		case WEAPON_THARGOID_LASER:		// omni directional lasers FRIGHTENING!
			weapon_energy =			12.5;
			weapon_recharge_rate =	0.5;
			weaponRange =			17500;
			break;
		case WEAPON_MILITARY_LASER:
			weapon_energy =			23.0;
			weapon_recharge_rate =	0.20;
			weaponRange =			30000;
			break;
		case WEAPON_NONE:
		case WEAPON_UNDEFINED:
			weapon_energy =			0.0;	// indicating no weapon!
			weapon_recharge_rate =	0.20;	// maximum rate
			weaponRange =			32000;
			break;
	}
}


- (float) weaponRechargeRate
{
	return weapon_recharge_rate;
}


- (void) setWeaponRechargeRate:(float)value
{
	weapon_recharge_rate = value;
}


- (GLfloat) scannerRange
{
	return scannerRange;
}


- (void) setScannerRange: (GLfloat) value
{
	scannerRange = value;
}


- (Vector) reference
{
	return reference;
}


- (void) setReference:(Vector) v
{
	reference = v;
}


- (BOOL) reportAIMessages
{
	return reportAIMessages;
}


- (void) setReportAIMessages:(BOOL) yn
{
	reportAIMessages = yn;
}


- (void) transitionToAegisNone
{
	if (!suppressAegisMessages && aegis_status != AEGIS_NONE)
	{
		Entity<OOStellarBody> *lastAegisLock = [self lastAegisLock];
		if (lastAegisLock != nil)
		{
			[self doScriptEvent:@"shipExitedPlanetaryVicinity" withArgument:lastAegisLock];
			
			if (lastAegisLock == [UNIVERSE sun])
			{
				[shipAI message:@"AWAY_FROM_SUN"];
			}
			else
			{
				[shipAI message:@"AWAY_FROM_PLANET"];
			}
			[self setLastAegisLock:nil];
		}

		if (aegis_status != AEGIS_CLOSE_TO_ANY_PLANET)
		{
			[shipAI message:@"AEGIS_NONE"];
		}
	}
	aegis_status = AEGIS_NONE;
}


static float SurfaceDistanceSqaredV(Vector reference, Entity<OOStellarBody> *stellar)
{
	float centerDistance = magnitude2(vector_subtract([stellar position], reference));
	float r = [(PlanetEntity *)stellar radius];
	
	/*	1.35: empirical value used to help determine proximity when non-nested
		planets are close to each other
	*/
	return centerDistance - 1.35 * r * r;
}


static float SurfaceDistanceSqared(Entity *reference, Entity<OOStellarBody> *stellar)
{
	return SurfaceDistanceSqaredV([reference position], stellar);
}


NSComparisonResult ComparePlanetsBySurfaceDistance(id i1, id i2, void* context)
{
	Vector p = [(ShipEntity*) context position];
	PlanetEntity* e1 = i1;
	PlanetEntity* e2 = i2;
	
#if OBSOLETE
	//fx: empirical value used to help determine proximity when non-nested planets are close to each other
	float fx=1.35;
	float r;
	
	float p1 = magnitude2(vector_subtract([e1 position], p));
	float p2 = magnitude2(vector_subtract([e2 position], p));
	r = [e1 radius];
	p1 -= fx*r*r;
	r = [e2 radius];
	p2 -= fx*r*r;
#else
	float p1 = SurfaceDistanceSqaredV(p, e1);
	float p2 = SurfaceDistanceSqaredV(p, e2);
#endif
	
	if (p1 < p2) return NSOrderedAscending;
	if (p1 > p2) return NSOrderedDescending;
	
	return NSOrderedSame;
}


- (PlanetEntity *) findNearestPlanet
{
	PlanetEntity		*result = nil;
	NSArray				*planets = nil;
	
	planets = [UNIVERSE planets];
	if ([planets count] == 0)  return nil;
	
	planets = [planets sortedArrayUsingFunction:ComparePlanetsBySurfaceDistance context:self];
	result = [planets objectAtIndex:0];
	
	// ignore miniature planets when determining nearest planet - Nikos 20090313
	if ([result planetType] == PLANET_TYPE_MINIATURE)
	{
		if ([UNIVERSE sun])	// if we are not in witchspace give us the next in the list, else nothing
		{
			result = [planets objectAtIndex:1];
		}
		else
		{
			result = nil;
		}
	}
	
	return result;
}


- (Entity<OOStellarBody> *) findNearestStellarBody
{
	Entity<OOStellarBody> *match = [self findNearestPlanet];
	OOSunEntity *sun = [UNIVERSE sun];
	
	if (sun != nil)
	{
		if (match == nil ||
			SurfaceDistanceSqared(self, sun) < SurfaceDistanceSqared(self, match))
		{
			match = sun;
		}
	}
	
	return match;
}


- (PlanetEntity *) findNearestPlanetExcludingMoons
{
	PlanetEntity		*result = nil;
	PlanetEntity		*planet = nil;
	NSArray				*bodies = nil;
	NSArray				*planets = nil;
	unsigned			i;
	
	bodies = [UNIVERSE planets];
	planets = [NSMutableArray arrayWithCapacity:[bodies count]];

	for (i=0; i < [bodies count]; i++)
	{
		planet = [bodies objectAtIndex:i];
		if([planet planetType] == PLANET_TYPE_GREEN)
					planets = [planets arrayByAddingObject:planet];
	}
	
	if ([planets count] == 0)  return nil;
	
	planets = [planets sortedArrayUsingFunction:ComparePlanetsBySurfaceDistance context:self];
	result = [planets objectAtIndex:0];
		
	return result;
}


- (OOAegisStatus) checkForAegis
{
	Entity<OOStellarBody>	*nearest = [self findNearestStellarBody];
	BOOL					sunGoneNova = [[UNIVERSE sun] goneNova];
	
	if (nearest == nil)
	{
		if (aegis_status != AEGIS_NONE)
		{
			// Planet disappeared!
			[self transitionToAegisNone];
		}
		return AEGIS_NONE;
	}

	// check planet
	float			cr = [nearest radius];
	float			cr2 = cr * cr;
	OOAegisStatus	result = AEGIS_NONE;
	float			d2;
	
	d2 = magnitude2(vector_subtract([nearest position], [self position]));
	
	// check if nearing surface
	BOOL wasNearPlanetSurface = isNearPlanetSurface;
	isNearPlanetSurface = (d2 - cr2) < (250000.0f + 1000.0f * cr); //less than 500m from the surface: (a+b)*(a+b) = a*a+b*b +2*a*b
	if (!suppressAegisMessages)
	{
		if (!wasNearPlanetSurface && isNearPlanetSurface)
		{
			[self doScriptEvent:@"shipApproachingPlanetSurface" withArgument:nearest];
			[shipAI reactToMessage:@"APPROACHING_SURFACE"];
		}
		if (wasNearPlanetSurface && !isNearPlanetSurface)
		{
			[self doScriptEvent:@"shipLeavingPlanetSurface" withArgument:nearest];
			[shipAI reactToMessage:@"LEAVING_SURFACE"];
		}
	}
	
	if (d2 < cr2 * 9.0f) //to  3x radius of any planet/moon
	{
		result = AEGIS_CLOSE_TO_ANY_PLANET;
	}
	
	if (!sunGoneNova)
	{
		d2 = magnitude2(vector_subtract([[UNIVERSE planet] position], [self position]));
		cr2 = [[UNIVERSE planet] radius];
		cr2 *= cr2;
		if (d2 < cr2 * 9.0f) // to 3x radius of main planet
		{
			result = AEGIS_CLOSE_TO_MAIN_PLANET;
		}
	}
	
	// check station
	StationEntity	*the_station = [UNIVERSE station];
	if (the_station)
	{
		d2 = magnitude2(vector_subtract([the_station position], [self position]));
		if (d2 < SCANNER_MAX_RANGE2 * 4.0f) // double scanner range
		{
			result = AEGIS_IN_DOCKING_RANGE;
		}
	}

	/*	Rewrote aegis stuff and tested it against redux.oxp that adds multiple planets and moons.
		Made sure AI scripts can differentiate between MAIN and NON-MAIN planets so they can decide
		if they can dock at the systemStation or just any station.
		Added sun detection so route2Patrol can turn before they heat up in the sun.
		-- Eric 2009-07-11
	*/
	if (!suppressAegisMessages)
	{
		// script/AI messages on change in status
		// approaching..
		if ((aegis_status == AEGIS_NONE || aegis_status == AEGIS_CLOSE_TO_ANY_PLANET)&&(result == AEGIS_CLOSE_TO_MAIN_PLANET))
		{
			if(aegis_status == AEGIS_CLOSE_TO_ANY_PLANET)
			{
				[self doScriptEvent:@"shipExitedPlanetaryVicinity" withArgument:[self lastAegisLock]];
				[shipAI message:@"AWAY_FROM_PLANET"];        // fires for all planets and moons.
			}
			[self doScriptEvent:@"shipEnteredPlanetaryVicinity" withArgument:[UNIVERSE planet]];
			[self setLastAegisLock:(Entity<OOStellarBody> *)[UNIVERSE planet]];		// NEW_PLANETS temp compile fix
			[shipAI message:@"CLOSE_TO_PLANET"];             // fires for all planets and moons.
			[shipAI message:@"AEGIS_CLOSE_TO_PLANET"];	     // fires only for main planets, keep for compatibility with pre-1.72 AI plists.
			[shipAI message:@"AEGIS_CLOSE_TO_MAIN_PLANET"];  // fires only for main planet.
		}
		if ((aegis_status == AEGIS_NONE || aegis_status == AEGIS_CLOSE_TO_MAIN_PLANET)&&(result == AEGIS_CLOSE_TO_ANY_PLANET))
		{
			if(aegis_status == AEGIS_CLOSE_TO_MAIN_PLANET)
			{
				[self doScriptEvent:@"shipExitedPlanetaryVicinity" withArgument:[UNIVERSE planet]];
				[shipAI message:@"AWAY_FROM_PLANET"];
			}
			[self doScriptEvent:@"shipEnteredPlanetaryVicinity" withArgument:nearest];
			[self setLastAegisLock:nearest];
			if([nearest isSun])
			{
				[shipAI message:@"CLOSE_TO_SUN"];
			}
			else
			{
				[shipAI message:@"CLOSE_TO_PLANET"];
				if ([nearest planetType] == PLANET_TYPE_MOON)
				{
					[shipAI message:@"CLOSE_TO_MOON"];
				}
				else
				{
					[shipAI message:@"CLOSE_TO_SECONDARY_PLANET"];
				}
			}
		}
		if ((aegis_status != AEGIS_IN_DOCKING_RANGE)&&(result == AEGIS_IN_DOCKING_RANGE))
		{
			[self doScriptEvent:@"shipEnteredStationAegis" withArgument:the_station];
			[shipAI message:@"AEGIS_IN_DOCKING_RANGE"];
			
			if([self lastAegisLock] == nil && !sunGoneNova) // With small main planets the station aegis can come before planet aegis
			{
				[self doScriptEvent:@"shipEnteredPlanetaryVicinity" withArgument:[UNIVERSE planet]];
				[self setLastAegisLock:(Entity<OOStellarBody> *)[UNIVERSE planet]];	// NEW_PLANETS temp compile fix
			}
		}
		// leaving..
		if ((aegis_status == AEGIS_IN_DOCKING_RANGE)&&(result != AEGIS_IN_DOCKING_RANGE))
		{
			[self doScriptEvent:@"shipExitedStationAegis" withArgument:the_station];
			[shipAI message:@"AEGIS_LEAVING_DOCKING_RANGE"];
		}
		if ((aegis_status != AEGIS_NONE)&&(result == AEGIS_NONE))
		{
			if([self lastAegisLock] == nil && !sunGoneNova)
			{
				[self setLastAegisLock:(Entity<OOStellarBody> *)[UNIVERSE planet]];  // in case of a first launch.	// NEW_PLANETS temp compile fix
			}
			[self transitionToAegisNone];
		}
	}

	aegis_status = result;	// put this here
	return result;
}


- (BOOL) withinStationAegis
{
	return aegis_status == AEGIS_IN_DOCKING_RANGE;
}


- (Entity<OOStellarBody> *) lastAegisLock
{
	Entity<OOStellarBody> *stellar = [_lastAegisLock weakRefUnderlyingObject];
	if (stellar == nil)
	{
		[_lastAegisLock release];
		_lastAegisLock = nil;
	}
	
	return stellar;
}


- (void) setLastAegisLock:(Entity<OOStellarBody> *)lastAegisLock
{
	[_lastAegisLock release];
	_lastAegisLock = [lastAegisLock weakRetain];
}


- (void) setStatus:(OOEntityStatus) stat
{
	[super setStatus:stat];
	if (stat == STATUS_LAUNCHING)
	{
		launch_time = [UNIVERSE getTime];
	}
}


- (NSArray*) crew
{
	return crew;
}


- (void) setCrew: (NSArray*) crewArray
{
	if (isUnpiloted) 
	{
		//unpiloted ships cannot have crew
		return;
	}
	//do not set to hulk here when crew is nill (or 0).  Some things like missiles have no crew.
	if (crew != nil) [crew autorelease];
	crew = [crewArray copy];
}


- (void) setStateMachine:(NSString *) ai_desc
{
	[shipAI setStateMachine: ai_desc];
}


- (void) setAI:(AI *) ai
{
	[ai retain];
	if (shipAI)
	{
		[shipAI clearAllData];
		[shipAI autorelease];
	}
	shipAI = ai;
}


- (AI *) getAI
{
	return shipAI;
}


- (void) setShipScript:(NSString *)script_name
{
	NSMutableDictionary		*properties = nil;
	NSArray					*actions = nil;
	
	properties = [NSMutableDictionary dictionary];
	[properties setObject:self forKey:@"ship"];
	
	[script autorelease];
	script = [OOScript nonLegacyScriptFromFileNamed:script_name properties:properties];
	
	if (script == nil)
	{
		actions = [shipinfoDictionary oo_arrayForKey:@"launch_actions"];
		if (actions)  [properties setObject:actions forKey:@"legacy_launchActions"];	
		actions = [shipinfoDictionary oo_arrayForKey:@"script_actions"];
		if (actions)  [properties setObject:actions forKey:@"legacy_scriptActions"];
		actions = [shipinfoDictionary oo_arrayForKey:@"death_actions"];
		if (actions)  [properties setObject:actions forKey:@"legacy_deathActions"];
		actions = [shipinfoDictionary oo_arrayForKey:@"setup_actions"];
		if (actions)  [properties setObject:actions forKey:@"legacy_setupActions"];
		
		script = [OOScript nonLegacyScriptFromFileNamed:@"oolite-default-ship-script.js"
											 properties:properties];
	}
	[script retain];
}


- (double)frustration
{
	return frustration;
}


- (OOFuelQuantity) fuel
{
	return fuel;
}


- (void) setFuel:(OOFuelQuantity) amount
{
	if (amount > [self fuelCapacity])  amount = [self fuelCapacity];
	
	fuel = amount;
}


- (OOFuelQuantity) fuelCapacity
{
	// FIXME: shipdata.plist can allow greater fuel quantities (without extending hyperspace range). Need some consistency here.
	return PLAYER_MAX_FUEL;
}


- (void) setRoll:(double) amount
{
	flightRoll = amount * M_PI / 2.0;
}


- (void) setPitch:(double) amount
{
	flightPitch = amount * M_PI / 2.0;
}


- (void) setThrust:(double) amount
{
	thrust = amount;
}


- (void) setThrustForDemo:(float) factor
{
	flightSpeed = factor * maxFlightSpeed;
}


- (void) setBounty:(OOCreditsQuantity) amount
{
	bounty = amount;
}


- (OOCreditsQuantity) bounty
{
	return bounty;
}


- (int) legalStatus
{
	if (scanClass == CLASS_THARGOID)
		return 5 * collision_radius;
	if (scanClass == CLASS_ROCK)
		return 0;
	return bounty;
}


- (void) setCommodity:(OOCargoType)co_type andAmount:(OOCargoQuantity)co_amount
{
	if (co_type != CARGO_UNDEFINED)
	{
		commodity_type = co_type;
		commodity_amount = co_amount;
	}
}


- (OOCargoType) commodityType
{
	return commodity_type;
}


- (OOCargoQuantity) commodityAmount
{
	return commodity_amount;
}


- (OOCargoQuantity) maxCargo
{
	return max_cargo;
}


- (OOCargoQuantity) availableCargoSpace
{
	return [self maxCargo] - [self cargoQuantityOnBoard];
}


- (OOCargoQuantity) cargoQuantityOnBoard
{
	OOCargoQuantity		cargoQtyOnBoard = 0;
	int i;
	
	if ([self isPlayer] && ([(PlayerEntity*)self specialCargo] != nil))
	{
		return [self maxCargo];
	}	
	
	if ([self isPlayer]) // always use this method to avoid inconsistencies  - Kaks 20091002
	{
		/*
	  	  The cargo array is nil when the player ship is docked, due to action in unloadCargopods. For
	  	  this reason, we must use a slightly more complex method to determine the quantity of cargo
	  	  carried in this case - Nikos 20090830
		  
		  Optimised this method, to compensate for increased usage - Kaks 20091002
		*/
		PlayerEntity*	player = [PlayerEntity sharedPlayer];
		NSArray* manifest = [NSArray arrayWithArray:[player shipCommodityData]];
		OOMassUnit			commodityUnits = UNITS_TONS;
		OOCargoQuantity		quantity = 0;
		for (i = [manifest count] - 1; i >= 0 ; i--)
		{
			NSArray*	commodityInfo = [NSArray arrayWithArray:(NSArray *)[manifest objectAtIndex:i]];
			quantity = [commodityInfo oo_intAtIndex:MARKET_QUANTITY];
			// manifest contains entries for all 17 commodities, whether their quantity is 0 or more.
			commodityUnits = [UNIVERSE unitsForCommodity:i];
			if (commodityUnits != UNITS_TONS)
			{
				if (commodityUnits == UNITS_KILOGRAMS) quantity = (quantity + 500) / 1000;
				else quantity = (quantity + 500000) / 1000000;	// grams
			}
			cargoQtyOnBoard += quantity;
		}
		cargoQtyOnBoard += [[self cargo] count];
	}
	else	// NPCs only method
	{
		cargoQtyOnBoard = [[self cargo] count];
	}
	
	return cargoQtyOnBoard;
}



- (OOCargoType) cargoType
{
	return cargo_type;
}


- (NSMutableArray*) cargo
{
	return cargo;
}


- (void) setCargo:(NSArray *) some_cargo
{
	[cargo removeAllObjects];
	[cargo addObjectsFromArray:some_cargo];
}


- (OOCargoFlag) cargoFlag
{
	return cargo_flag;
}


- (void) setCargoFlag:(OOCargoFlag) flag
{
	cargo_flag = flag;
}


- (void) setSpeed:(double) amount
{
	flightSpeed = amount;
}


- (void) setDesiredSpeed:(double) amount
{
	desired_speed = amount;
}


- (double) desiredSpeed
{
	return desired_speed;
}


- (void) increase_flight_speed:(double) delta
{
	double factor = 1.0;
	if (desired_speed > maxFlightSpeed && [self hasFuelInjection] && fuel > MIN_FUEL) factor = [self afterburnerFactor];

	if (flightSpeed < maxFlightSpeed * factor)
		flightSpeed += delta * factor;
	else
		flightSpeed = maxFlightSpeed * factor;
}


- (void) decrease_flight_speed:(double) delta
{
	double factor = 1.0;
	if (flightSpeed > maxFlightSpeed) factor = [self afterburnerFactor] / 2;

	if (flightSpeed > factor * delta)
		flightSpeed -= factor * delta;  // Player uses here: flightSpeed -= 5 * HYPERSPEED_FACTOR * delta (= 160 * delta);
	else
		flightSpeed = 0;
}


- (void) increase_flight_roll:(double) delta
{
	if (flightRoll < max_flight_roll)
		flightRoll += delta;
	if (flightRoll > max_flight_roll)
		flightRoll = max_flight_roll;
}


- (void) decrease_flight_roll:(double) delta
{
	if (flightRoll > -max_flight_roll)
		flightRoll -= delta;
	if (flightRoll < -max_flight_roll)
		flightRoll = -max_flight_roll;
}


- (void) increase_flight_pitch:(double) delta
{
	if (flightPitch < max_flight_pitch)
		flightPitch += delta;
	if (flightPitch > max_flight_pitch)
		flightPitch = max_flight_pitch;
}


- (void) decrease_flight_pitch:(double) delta
{
	if (flightPitch > -max_flight_pitch)
		flightPitch -= delta;
	if (flightPitch < -max_flight_pitch)
		flightPitch = -max_flight_pitch;
}


- (void) increase_flight_yaw:(double) delta
{
	if (flightYaw < max_flight_yaw)
		flightYaw += delta;
	if (flightYaw > max_flight_yaw)
		flightYaw = max_flight_yaw;
}


- (void) decrease_flight_yaw:(double) delta
{
	if (flightYaw > -max_flight_yaw)
		flightYaw -= delta;
	if (flightYaw < -max_flight_yaw)
		flightYaw = -max_flight_yaw;
}


- (GLfloat) flightRoll
{
	return flightRoll;
}


- (GLfloat) flightPitch
{
	return flightPitch;
}


- (GLfloat) flightYaw
{
	return flightYaw;
}


- (GLfloat) flightSpeed
{
	return flightSpeed;
}


- (GLfloat) maxFlightSpeed
{
	return maxFlightSpeed;
}


- (GLfloat) speedFactor
{
	if (maxFlightSpeed <= 0.0)  return 0.0;
	return flightSpeed / maxFlightSpeed;
}


- (GLfloat) temperature
{
	return ship_temperature;
}


- (void) setTemperature:(GLfloat) value
{
	ship_temperature = value;
}


- (GLfloat) heatInsulation
{
	return _heatInsulation;
}


- (void) setHeatInsulation:(GLfloat) value
{
	_heatInsulation = value;
}


- (int) damage
{
	return (int)(100 - (100 * energy / maxEnergy));
}


// Exposed to AI
- (void) dealEnergyDamageWithinDesiredRange
{
	NSArray* targets = [UNIVERSE getEntitiesWithinRange:desired_range ofEntity:self];
	if ([targets count] > 0)
	{
		unsigned i;
		for (i = 0; i < [targets count]; i++)
		{
			Entity *e2 = [targets objectAtIndex:i];
			Vector p2 = vector_subtract([e2 position], position);
			double ecr = [e2 collisionRadius];
			double d2 = magnitude2(p2) - ecr * ecr;
			double damage = weapon_energy*desired_range/d2;
			[e2 takeEnergyDamage:damage from:self becauseOf:[self owner]];
		}
	}
}


- (void) dealMomentumWithinDesiredRange:(double)amount
{
	NSArray* targets = [UNIVERSE getEntitiesWithinRange:desired_range ofEntity:self];
	if ([targets count] > 0)
	{
		unsigned i;
		for (i = 0; i < [targets count]; i++)
		{
			ShipEntity *e2 = (ShipEntity*)[targets objectAtIndex:i];
			if ([e2 isShip])
			{
				Vector p2 = vector_subtract([e2 position], position);
				double ecr = [e2 collisionRadius];
				double d2 = magnitude2(p2) - ecr * ecr;
				while (d2 <= 0.0)
				{
					p2 = OOVectorRandomSpatial(1.0);
					d2 = magnitude2(p2);
				}
				double moment = amount*desired_range/d2;
				[e2 addImpactMoment:vector_normal(p2) fraction:moment];
			}
		}
	}
}


- (BOOL) isHulk
{
	return isHulk;
}

- (void) setHulk:(BOOL)isNowHulk
{
	isHulk = isNowHulk;
}

- (void) getDestroyedBy:(Entity *)whom context:(NSString *)context
{
	if (whom == nil)  whom = (id)[NSNull null];
	
	// Is this safe to do here? The script actions will be executed before the status has been set to
	// STATUS_DEAD, which is the opposite of what was happening inside becomeExplosion - Nikos.
	if (script != nil)
	{
		[[PlayerEntity sharedPlayer] setScriptTarget:self];
		[self doScriptEvent:@"shipDied" withArguments:[NSArray arrayWithObjects:whom, context, nil]];
	}
	
	[self becomeExplosion];
}


- (void) rescaleBy:(GLfloat)factor
{
	// rescale mesh (and collision detection stuff)
	[self setMesh:[[self mesh] meshRescaledBy:factor]];
	
	// rescale positions of subentities
	NSEnumerator	*subEnum = nil;
	Entity			*se = nil;
	for (subEnum = [self subEntityEnumerator]; (se = [subEnum nextObject]); )
	{
		se->position = vector_multiply_scalar([se position], factor);
		
		// rescale ship subentities
		if ([se isShip])  [(ShipEntity*)se rescaleBy:factor];
		
		// rescale particle subentities
		if ([se isParticle])
		{
			ParticleEntity* pe = (ParticleEntity*)se;
			NSSize sz = [pe size];
			sz.width *= factor;
			sz.height *= factor;
			[pe setSize: sz];
		}
	}
	
	// rescale mass
	mass *= factor * factor * factor;
}


- (void) becomeExplosion
{
	OOCargoQuantity cargo_to_go;
	
	// check if we're destroying a subentity
	ShipEntity *parent = [self parentEntity];
	if (parent != nil)
	{
		ShipEntity* this_ship = [self retain];
		Vector this_pos = [self absolutePositionForSubentity];
		
		// remove this ship from its parent's subentity list
		[parent subEntityDied:self];
		[UNIVERSE addEntity:this_ship];
		[this_ship setPosition:this_pos];
		[this_ship release];
	}
	
	Vector xposition = position;
	Entity *fragment = nil;
	int i;
	Vector v;
	Quaternion q;
	int speed_low = 200;
	int n_alloys = floor(sqrtf(sqrtf(mass / 25000.0)));

	if ([self status] == STATUS_DEAD)
	{
		[UNIVERSE removeEntity:self];
		return;
	}
	[self setStatus:STATUS_DEAD];
	
	if ([self isThargoid])  [self broadcastThargoidDestroyed];
	
	if (!suppressExplosion)
	{
		if ((mass > 500000.0f)&&(randf() < 0.25f)) // big!
		{
			// draw an expanding ring
			ParticleEntity *ring = [[ParticleEntity alloc] initHyperringFromShip:self]; // retained
			Vector ring_vel = [self velocity];
			ring_vel.x *= 0.25;	ring_vel.y *= 0.25;	ring_vel.z *= 0.25;	// quarter velocity
			[ring setVelocity:ring_vel];
			[UNIVERSE addEntity:ring];
			[ring release];
		}
		
		// several parts to the explosion:
		// 1. fast sparks
		fragment = [[ParticleEntity alloc] initFragburstSize:collision_radius fromPosition:xposition];
		[UNIVERSE addEntity:fragment];
		[fragment release];
		// 2. slow clouds
		fragment = [[ParticleEntity alloc] initBurst2Size:collision_radius fromPosition:xposition];
		[UNIVERSE addEntity:fragment];
		[fragment release];
		// 3. flash
		fragment = [[OOFlashEffectEntity alloc] initExplosionFlashWithPosition:position size:collision_radius];
		[UNIVERSE addEntity:fragment];
		[fragment release];

		BOOL add_more_explosion = YES;
		if (UNIVERSE)
		{
			add_more_explosion &= (UNIVERSE->n_entities < 0.95 * UNIVERSE_MAX_ENTITIES);	// 
			add_more_explosion &= ([UNIVERSE getTimeDelta] < 0.125);						// FPS > 8
		}
		// quick - check if UNIVERSE is nearing limit for entities - if it is don't add to it!
		//
		if (add_more_explosion)
		{
			// we need to throw out cargo at this point.
			NSArray *jetsam = nil;  // this will contain the stuff to get thrown out
			unsigned cargo_chance = 10;
			if ([[name lowercaseString] rangeOfString:@"medical"].location != NSNotFound)
			{
				cargo_to_go = max_cargo * cargo_chance / 100;
				while (cargo_to_go > 15)
					cargo_to_go = ranrot_rand() % cargo_to_go;
				[self setCargo:[UNIVERSE getContainersOfDrugs:cargo_to_go]];
				cargo_chance = 100;  //  chance of any given piece of cargo surviving decompression
				cargo_flag = CARGO_FLAG_CANISTERS;
			}
			
			cargo_to_go = max_cargo * cargo_chance / 100;
			while (cargo_to_go > 15)
				cargo_to_go = ranrot_rand() % cargo_to_go;
			cargo_chance = 100;  //  chance of any given piece of cargo surviving decompression
			switch (cargo_flag)
			{
				case CARGO_FLAG_NONE:
				case CARGO_FLAG_FULL_PASSENGERS:
					break;
				
				case CARGO_FLAG_FULL_UNIFORM :
					{
						NSString* commodity_name = [shipinfoDictionary oo_stringForKey:@"cargo_carried"];
						jetsam = [UNIVERSE getContainersOfCommodity:commodity_name :cargo_to_go];
					}
					break;
				
				case CARGO_FLAG_FULL_PLENTIFUL :
					jetsam = [UNIVERSE getContainersOfGoods:cargo_to_go scarce:NO];
					break;
				
				case CARGO_FLAG_PIRATE :
					cargo_to_go = likely_cargo;
					while (cargo_to_go > 15)
						cargo_to_go = ranrot_rand() % cargo_to_go;
					cargo_chance = 65;	// 35% chance of spoilage
					jetsam = [UNIVERSE getContainersOfGoods:cargo_to_go scarce:YES];
					break;
				
				case CARGO_FLAG_FULL_SCARCE :
					jetsam = [UNIVERSE getContainersOfGoods:cargo_to_go scarce:YES];
					break;
				
				case CARGO_FLAG_CANISTERS:
					jetsam = [NSArray arrayWithArray:cargo];   // what the ship is carrying
					[cargo removeAllObjects];   // dispense with it!
					break;
			}

			//  Throw out cargo
			if (jetsam)
			{
				int n_jetsam = [jetsam count];
				//NSDictionary *containerShipDict = nil;
				//
				for (i = 0; i < n_jetsam; i++)
				{
					if (Ranrot() % 100 < cargo_chance)  //  chance of any given piece of cargo surviving decompression
					{
						ShipEntity* container = [jetsam objectAtIndex:i];
						AI *containerAI = nil;
						Vector  rpos = xposition;
						Vector	rrand = randomPositionInBoundingBox(boundingBox);
						rpos.x += rrand.x;	rpos.y += rrand.y;	rpos.z += rrand.z;
						rpos.x += (ranrot_rand() % 7) - 3;
						rpos.y += (ranrot_rand() % 7) - 3;
						rpos.z += (ranrot_rand() % 7) - 3;
						[container setPosition:rpos];
						v.x = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
						v.y = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
						v.z = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
						[container setVelocity:v];
						quaternion_set_random(&q);
						[container setOrientation:q];
						[container setStatus:STATUS_IN_FLIGHT];
						[container setScanClass: CLASS_CARGO];
						[UNIVERSE addEntity:container];
						containerAI = [container getAI];
						if ([containerAI hasSuspendedStateMachines]) // check if new or recycled cargo.
						{
							[containerAI exitStateMachineWithMessage:nil];
							[container setThrust:[container maxThrust]]; // restore old value. Was set to zero on previous scooping.
							[container setOwner:container];
						}
						else 
						{
							[containerAI setState:@"GLOBAL"];
						}
					}
				}
			}

			//  Throw out rocks and alloys to be scooped up
			if ([self hasRole:@"asteroid"])
			{
				if (!noRocks && (being_mined || randf() < 0.20))
				{
					int n_rocks = 2 + (Ranrot() % (likely_cargo + 1));
					
					for (i = 0; i < n_rocks; i++)
					{
						ShipEntity* rock = [UNIVERSE newShipWithRole:@"boulder"];   // retain count = 1
						if (rock)
						{
							Vector  rpos = xposition;
							int  r_speed = 20.0 * [rock maxFlightSpeed];
							int cr = 3 * rock->collision_radius;
							rpos.x += (ranrot_rand() % cr) - cr/2;
							rpos.y += (ranrot_rand() % cr) - cr/2;
							rpos.z += (ranrot_rand() % cr) - cr/2;
							[rock setPosition:rpos];
							v.x = 0.1 *((ranrot_rand() % r_speed) - r_speed / 2);
							v.y = 0.1 *((ranrot_rand() % r_speed) - r_speed / 2);
							v.z = 0.1 *((ranrot_rand() % r_speed) - r_speed / 2);
							[rock setVelocity:v];
							quaternion_set_random(&q);
							[rock setOrientation:q];
							[rock setStatus:STATUS_IN_FLIGHT];
							[rock setScanClass: CLASS_ROCK];
							[UNIVERSE addEntity:rock];
							[[rock getAI] setState:@"GLOBAL"];
							[rock release];
						}
					}
				}
				[UNIVERSE removeEntity:self];
				return; // don't do anything more
			}

			if ([self hasRole:@"boulder"])
			{
				if ((being_mined)||(ranrot_rand() % 100 < 20))
				{
					int n_rocks = 2 + (ranrot_rand() % 5);
					//
					for (i = 0; i < n_rocks; i++)
					{
						ShipEntity* rock = [UNIVERSE newShipWithRole:@"splinter"];   // retain count = 1
						if (rock)
						{
							Vector  rpos = xposition;
							int  r_speed = 20.0 * [rock maxFlightSpeed];
							int cr = 3 * rock->collision_radius;
							rpos.x += (ranrot_rand() % cr) - cr/2;
							rpos.y += (ranrot_rand() % cr) - cr/2;
							rpos.z += (ranrot_rand() % cr) - cr/2;
							[rock setPosition:rpos];
							v.x = 0.1 *((ranrot_rand() % r_speed) - r_speed / 2);
							v.y = 0.1 *((ranrot_rand() % r_speed) - r_speed / 2);
							v.z = 0.1 *((ranrot_rand() % r_speed) - r_speed / 2);
							[rock setBounty: 0];
							[rock setCommodity:[UNIVERSE commodityForName:@"Minerals"] andAmount: 1];
							[rock setVelocity:v];
							quaternion_set_random(&q);
							[rock setOrientation:q];
							[rock setStatus:STATUS_IN_FLIGHT];
							[rock setScanClass: CLASS_CARGO];
							[UNIVERSE addEntity:rock];
							[[rock getAI] setState:@"GLOBAL"];
							[rock release];
						}
					}
				}
				[UNIVERSE removeEntity:self];
				return; // don't do anything more
			}

			// throw out burning chunks of wreckage
			//
			if (n_alloys && canFragment)
			{
				int n_wreckage = (n_alloys < 3)? n_alloys : 3;
				
				// quick - check if UNIVERSE is nearing limit for entities - if it is don't make wreckage
				//
				add_more_explosion &= (UNIVERSE->n_entities < 0.50 * UNIVERSE_MAX_ENTITIES);
				if (!add_more_explosion)
					n_wreckage = 0;
				//
				////
				
				for (i = 0; i < n_wreckage; i++)
				{
					ShipEntity* wreck = [UNIVERSE newShipWithRole:@"wreckage"];   // retain count = 1
					if (wreck)
					{
						GLfloat expected_mass = 0.1f * mass * (0.75 + 0.5 * randf());
						GLfloat wreck_mass = [wreck mass];
						GLfloat scale_factor = powf(expected_mass / wreck_mass, 0.33333333f);	// cube root of volume ratio
						[wreck rescaleBy: scale_factor];
						
						Vector r1 = randomFullNodeFrom([octree octreeDetails], kZeroVector);
						Vector rpos = make_vector (v_right.x * r1.x + v_up.x * r1.y + v_forward.x * r1.z,
													v_right.y * r1.x + v_up.y * r1.y + v_forward.y * r1.z,
													v_right.z * r1.x + v_up.z * r1.y + v_forward.z * r1.z);
						rpos.x += xposition.x;
						rpos.y += xposition.y;
						rpos.z += xposition.z;
						[wreck setPosition:rpos];
						
						[wreck setVelocity:[self velocity]];

						quaternion_set_random(&q);
						[wreck setOrientation:q];
						
						[wreck setTemperature: 1000.0];		// take 1000e heat damage per second
						[wreck setHeatInsulation: 1.0e7];	// very large! so it won't cool down
						[wreck setEnergy: 750.0 * randf() + 250.0 * i + 100.0];	// burn for 0.25s -> 1.25s
						
						[wreck setStatus:STATUS_IN_FLIGHT];
						[UNIVERSE addEntity:wreck];
						[wreck performTumble];
						[wreck rescaleBy: 1.0/scale_factor];
						[wreck release];
					}
				}
				n_alloys = ranrot_rand() % n_alloys;
			}

			// Throw out scrap metal
			//
			for (i = 0; i < n_alloys; i++)
			{
				ShipEntity* plate = [UNIVERSE newShipWithRole:@"alloy"];   // retain count = 1
				if (plate)
				{
					Vector  rpos = xposition;
					Vector	rrand = randomPositionInBoundingBox(boundingBox);
					rpos.x += rrand.x;	rpos.y += rrand.y;	rpos.z += rrand.z;
					rpos.x += (ranrot_rand() % 7) - 3;
					rpos.y += (ranrot_rand() % 7) - 3;
					rpos.z += (ranrot_rand() % 7) - 3;
					[plate setPosition:rpos];
					v.x = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
					v.y = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
					v.z = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
					[plate setVelocity:v];
					quaternion_set_random(&q);
					[plate setOrientation:q];
					[plate setScanClass: CLASS_CARGO];
					[plate setCommodity:[UNIVERSE commodityForName:@"Alloys"] andAmount:1];
					[UNIVERSE addEntity:plate];
					[plate setStatus:STATUS_IN_FLIGHT];
					[plate setTemperature:[self temperature] * EJECTA_TEMP_FACTOR];
					[[plate getAI] setState:@"GLOBAL"];
					[plate release];
				}
			}
		}
	}
	
	NSEnumerator	*subEnum = nil;
	ShipEntity		*se = nil;
	for (subEnum = [self shipSubEntityEnumerator]; (se = [subEnum nextObject]); )
	{
		[se setSuppressExplosion:suppressExplosion];
		[se setPosition:[se absolutePositionForSubentity]];
		[UNIVERSE addEntity:se];
		[se becomeExplosion];
	}
	[self clearSubEntities];

	// momentum from explosions
	desired_range = collision_radius * 2.5;
	[self dealMomentumWithinDesiredRange: 0.125 * mass];
	
	if (self != [PlayerEntity sharedPlayer])	// was if !isPlayer - but I think this may cause ghosts (Who's "I"? -- Ahruman)
	{
		if (isPlayer)
		{
#ifndef NDEBUG
			OOLog(@"becomeExplosion.suspectedGhost.confirm", @"Ship spotted with isPlayer set when not actually the player.");
#endif
			isPlayer = NO;
		}
		[UNIVERSE removeEntity:self];
	}
}


// Exposed to AI
- (void) becomeEnergyBlast
{
	ParticleEntity* blast = [[ParticleEntity alloc] initEnergyMineFromShip:self];
	[UNIVERSE addEntity:blast];
	[blast setOwner: [self owner]];
	[blast release];
	[UNIVERSE removeEntity:self];
}


- (void)subEntityDied:(ShipEntity *)sub
{
	if ([self subEntityTakingDamage] == sub)  [self setSubEntityTakingDamage:nil];
	
	[sub setOwner:nil];
	[subEntities removeObject:sub];
}


- (void)subEntityReallyDied:(ShipEntity *)sub
{
	if ([self subEntityTakingDamage] == sub)  [self setSubEntityTakingDamage:nil];
	
	if ([self hasSubEntity:sub])
	{
		OOLogERR(@"shipEntity.bug.subEntityRetainUnderflow", @"Subentity of %@ died while still in subentity list! This is bad. Leaking subentity list to avoid crash. %@", self, @"This is an internal error, please report it.");
		
		// Leak subentity list.
		subEntities = nil;
	}
}


Vector randomPositionInBoundingBox(BoundingBox bb)
{
	Vector result;
	result.x = bb.min.x + randf() * (bb.max.x - bb.min.x);
	result.y = bb.min.y + randf() * (bb.max.y - bb.min.y);
	result.z = bb.min.z + randf() * (bb.max.z - bb.min.z);
	return result;
}


- (Vector) positionOffsetForAlignment:(NSString*) align
{
	NSString* padAlign = [NSString stringWithFormat:@"%@---", align];
	Vector result = kZeroVector;
	switch ([padAlign characterAtIndex:0])
	{
		case (unichar)'c':
		case (unichar)'C':
			result.x = 0.5 * (boundingBox.min.x + boundingBox.max.x);
			break;
		case (unichar)'M':
			result.x = boundingBox.max.x;
			break;
		case (unichar)'m':
			result.x = boundingBox.min.x;
			break;
	}
	switch ([padAlign characterAtIndex:1])
	{
		case (unichar)'c':
		case (unichar)'C':
			result.y = 0.5 * (boundingBox.min.y + boundingBox.max.y);
			break;
		case (unichar)'M':
			result.y = boundingBox.max.y;
			break;
		case (unichar)'m':
			result.y = boundingBox.min.y;
			break;
	}
	switch ([padAlign characterAtIndex:2])
	{
		case (unichar)'c':
		case (unichar)'C':
			result.z = 0.5 * (boundingBox.min.z + boundingBox.max.z);
			break;
		case (unichar)'M':
			result.z = boundingBox.max.z;
			break;
		case (unichar)'m':
			result.z = boundingBox.min.z;
			break;
	}
	return result;
}


Vector positionOffsetForShipInRotationToAlignment(ShipEntity* ship, Quaternion q, NSString* align)
{
	NSString* padAlign = [NSString stringWithFormat:@"%@---", align];
	Vector i = vector_right_from_quaternion(q);
	Vector j = vector_up_from_quaternion(q);
	Vector k = vector_forward_from_quaternion(q);
	BoundingBox arbb = [ship findBoundingBoxRelativeToPosition: make_vector(0,0,0) InVectors: i : j : k];
	Vector result = kZeroVector;
	switch ([padAlign characterAtIndex:0])
	{
		case (unichar)'c':
		case (unichar)'C':
			result.x = 0.5 * (arbb.min.x + arbb.max.x);
			break;
		case (unichar)'M':
			result.x = arbb.max.x;
			break;
		case (unichar)'m':
			result.x = arbb.min.x;
			break;
	}
	switch ([padAlign characterAtIndex:1])
	{
		case (unichar)'c':
		case (unichar)'C':
			result.y = 0.5 * (arbb.min.y + arbb.max.y);
			break;
		case (unichar)'M':
			result.y = arbb.max.y;
			break;
		case (unichar)'m':
			result.y = arbb.min.y;
			break;
	}
	switch ([padAlign characterAtIndex:2])
	{
		case (unichar)'c':
		case (unichar)'C':
			result.z = 0.5 * (arbb.min.z + arbb.max.z);
			break;
		case (unichar)'M':
			result.z = arbb.max.z;
			break;
		case (unichar)'m':
			result.z = arbb.min.z;
			break;
	}
	return result;
}


- (void) becomeLargeExplosion:(double) factor
{
	Vector xposition = position;
	ParticleEntity  *fragment;
	OOCargoQuantity n_cargo = (ranrot_rand() % (likely_cargo + 1));
	OOCargoQuantity cargo_to_go;

	if ([self status] == STATUS_DEAD)  return;
	[self setStatus:STATUS_DEAD];
	
	//scripting
	if (script != nil)
	{
		[[PlayerEntity sharedPlayer] setScriptTarget:self];
		[self doScriptEvent:@"shipDied"];	// FIXME: params missing
	}

	// two parts to the explosion:
	// 1. fast sparks
	float how_many = factor;
	while (how_many > 0.5f)
	{
		fragment = [[ParticleEntity alloc] initFragburstSize: collision_radius fromPosition:xposition];
		[UNIVERSE addEntity:fragment];
		[fragment release];
		how_many -= 1.0f;
	}
	// 2. slow clouds
	how_many = factor;
	while (how_many > 0.5f)
	{
		fragment = [[ParticleEntity alloc] initBurst2Size: collision_radius fromPosition:xposition];
		[UNIVERSE addEntity:fragment];
		[fragment release];
		how_many -= 1.0f;
	}


	// we need to throw out cargo at this point.
	unsigned cargo_chance = 10;
	if ([[name lowercaseString] rangeOfString:@"medical"].location != NSNotFound)
	{
		cargo_to_go = max_cargo * cargo_chance / 100;
		while (cargo_to_go > 15)
			cargo_to_go = ranrot_rand() % cargo_to_go;
		[self setCargo:[UNIVERSE getContainersOfDrugs:cargo_to_go]];
		cargo_chance = 100;  //  chance of any given piece of cargo surviving decompression
		cargo_flag = CARGO_FLAG_CANISTERS;
	}
	if (cargo_flag == CARGO_FLAG_FULL_PLENTIFUL)
	{
		cargo_to_go = max_cargo / 10;
		while (cargo_to_go > 15)
			cargo_to_go = ranrot_rand() % cargo_to_go;
		[self setCargo:[UNIVERSE getContainersOfGoods:cargo_to_go scarce:NO]];
		cargo_chance = 100;
	}
	if (cargo_flag == CARGO_FLAG_FULL_SCARCE)
	{
		cargo_to_go = max_cargo / 10;
		while (cargo_to_go > 15)
			cargo_to_go = ranrot_rand() % cargo_to_go;
		[self setCargo:[UNIVERSE getContainersOfGoods:cargo_to_go scarce:NO]];
		cargo_chance = 100;
	}
	while ([cargo count] > 0)
	{
		if (Ranrot() % 100 < cargo_chance)  //  10% chance of any given piece of cargo surviving decompression
		{
			ShipEntity* container = [[cargo objectAtIndex:0] retain];
			Vector  rpos = xposition;
			Vector	rrand = randomPositionInBoundingBox(boundingBox);
			rpos.x += rrand.x;	rpos.y += rrand.y;	rpos.z += rrand.z;
			rpos.x += (ranrot_rand() % 7) - 3;
			rpos.y += (ranrot_rand() % 7) - 3;
			rpos.z += (ranrot_rand() % 7) - 3;
			[container setPosition:rpos];
			[container setScanClass: CLASS_CARGO];
			[UNIVERSE addEntity:container];
			[[container getAI] setState:@"GLOBAL"];
			[container setStatus:STATUS_IN_FLIGHT];
			[container release];
			if (n_cargo > 0)
				n_cargo--;  // count down extra cargo
		}
		[cargo removeObjectAtIndex:0];
	}
	
	NSEnumerator	*subEnum = nil;
	ShipEntity		*se = nil;
	for (subEnum = [self shipSubEntityEnumerator]; (se = [subEnum nextObject]); )
	{
		[se setSuppressExplosion:suppressExplosion];
		[se setPosition:[se absolutePositionForSubentity]];
		[UNIVERSE addEntity:se];
		[se becomeExplosion];
	}
	[self clearSubEntities];
	
	if (!isPlayer)  [UNIVERSE removeEntity:self];
}


- (void) collectBountyFor:(ShipEntity *)other
{
	if ([self isPirate])  bounty += [other bounty];
}


- (NSComparisonResult) compareBeaconCodeWith:(ShipEntity*) other
{
	return [[self beaconCode] compare:[other beaconCode] options: NSCaseInsensitiveSearch];
}


- (GLfloat)laserHeatLevel
{
	float result = (weapon_recharge_rate - [self shotTime]) / weapon_recharge_rate;
	return OOClamp_0_1_f(result);
}


- (GLfloat)hullHeatLevel
{
	return ship_temperature / (GLfloat)SHIP_MAX_CABIN_TEMP;
}


- (GLfloat)entityPersonality
{
	return entity_personality / (float)0x7FFF;
}


- (GLint)entityPersonalityInt
{
	return entity_personality;
}


- (void)setSuppressExplosion:(BOOL)suppress
{
	suppressExplosion = !!suppress;
}


- (void) resetExhaustPlumes
{
	NSEnumerator *exEnum = nil;
	OOExhaustPlumeEntity *exEnt = nil;
	
	for (exEnum = [self exhaustEnumerator]; (exEnt = [exEnum nextObject]); )
	{
		[exEnt resetPlume];
	}
}


/*-----------------------------------------

	AI piloting methods

-----------------------------------------*/

BOOL class_masslocks(int some_class)
{
	switch (some_class)
	{
		case CLASS_BUOY:
		case CLASS_ROCK:
		case CLASS_CARGO:
		case CLASS_MINE:
		case CLASS_NO_DRAW:
			return NO;
		
		case CLASS_THARGOID:
		case CLASS_MISSILE:
		case CLASS_STATION:
		case CLASS_POLICE:
		case CLASS_MILITARY:
		case CLASS_WORMHOLE:
			return YES;
	}
	return NO;
}


- (BOOL) checkTorusJumpClear
{
	Entity* scan;
	//
	scan = z_previous;	while ((scan)&&(!class_masslocks(scan->scanClass)))	scan = scan->z_previous;	// skip non-mass-locking
	while ((scan)&&(scan->position.z > position.z - scannerRange))
	{
		if (class_masslocks(scan->scanClass) && (distance2(position, scan->position) < SCANNER_MAX_RANGE2))
			return NO;
		scan = scan->z_previous;	while ((scan)&&(!class_masslocks(scan->scanClass)))	scan = scan->z_previous;
	}
	scan = z_next;	while ((scan)&&(!class_masslocks(scan->scanClass)))	scan = scan->z_next;	// skip non-mass-locking
	while ((scan)&&(scan->position.z < position.z + scannerRange))
	{
		if (class_masslocks(scan->scanClass) && (distance2(position, scan->position) < SCANNER_MAX_RANGE2))
			return NO;
		scan = scan->z_previous;	while ((scan)&&(!class_masslocks(scan->scanClass)))	scan = scan->z_previous;
	}
	return YES;
}


- (void) checkScanner
{
	Entity* scan;
	n_scanned_ships = 0;
	//
	scan = z_previous;	while ((scan)&&(scan->isShip == NO))	scan = scan->z_previous;	// skip non-ships
	while ((scan)&&(scan->position.z > position.z - scannerRange)&&(n_scanned_ships < MAX_SCAN_NUMBER))
	{
		if (scan->isShip)
		{
			distance2_scanned_ships[n_scanned_ships] = distance2(position, scan->position);
			if (distance2_scanned_ships[n_scanned_ships] < SCANNER_MAX_RANGE2)
				scanned_ships[n_scanned_ships++] = (ShipEntity*)scan;
		}
		scan = scan->z_previous;	while ((scan)&&(scan->isShip == NO))	scan = scan->z_previous;
	}
	//
	scan = z_next;	while ((scan)&&(scan->isShip == NO))	scan = scan->z_next;	// skip non-ships
	while ((scan)&&(scan->position.z < position.z + scannerRange)&&(n_scanned_ships < MAX_SCAN_NUMBER))
	{
		if (scan->isShip)
		{
			distance2_scanned_ships[n_scanned_ships] = distance2(position, scan->position);
			if (distance2_scanned_ships[n_scanned_ships] < SCANNER_MAX_RANGE2)
				scanned_ships[n_scanned_ships++] = (ShipEntity*)scan;
		}
		scan = scan->z_next;	while ((scan)&&(scan->isShip == NO))	scan = scan->z_next;	// skip non-ships
	}
	//
	scanned_ships[n_scanned_ships] = nil;	// terminate array
}


- (ShipEntity**) scannedShips
{
	scanned_ships[n_scanned_ships] = nil;	// terminate array
	return scanned_ships;
}


- (int) numberOfScannedShips
{
	return n_scanned_ships;
}


- (void) setFound_target:(Entity *) targetEntity
{
	if (targetEntity)
		found_target = [targetEntity universalID];
}


- (void) setPrimaryAggressor:(Entity *) targetEntity
{
	if (targetEntity)
		primaryAggressor = [targetEntity universalID];
}


- (void) addTarget:(Entity *) targetEntity
{
	if (targetEntity == self)  return;
	if (targetEntity != nil)  primaryTarget = [targetEntity universalID];
	
	[[self shipSubEntityEnumerator] makeObjectsPerformSelector:@selector(addTarget:) withObject:targetEntity];
}


- (void) removeTarget:(Entity *) targetEntity
{
	if(targetEntity != nil) [self noteLostTarget];
	else primaryTarget = NO_TARGET; 
	// targetEntity == nil is currently only true for mounted player missiles. 
	// we don't want to send lostTarget messages while the missile is mounted.
	
	[[self shipSubEntityEnumerator] makeObjectsPerformSelector:@selector(removeTarget:) withObject:targetEntity];
}


- (id) primaryTarget
{
	return [UNIVERSE entityForUniversalID:primaryTarget];
}


- (int) primaryTargetID
{
	return primaryTarget;
}


- (void) noteLostTarget
{
	if (primaryTarget != NO_TARGET)
	{
		ShipEntity* target = [UNIVERSE entityForUniversalID:primaryTarget];
		primaryTarget = NO_TARGET;
		[self doScriptEvent:@"shipLostTarget" withArgument:(target && target->isShip) ? (id)target : nil];
		[shipAI reactToMessage:@"TARGET_LOST"];
	}
	else
	{
		[self doScriptEvent:@"shipLostTarget" withArgument:nil];
		[shipAI message:@"TARGET_LOST"]; // this often triggers on witchspace jumps, so make it a message.
	}
}


- (void) noteTargetDestroyed:(ShipEntity *)target
{
	[self collectBountyFor:(ShipEntity *)target];
	if ([self primaryTarget] == target)
	{
		[self removeTarget:target];
		[self doScriptEvent:@"shipDestroyedTarget" withArgument:target];
		[shipAI message:@"TARGET_DESTROYED"];
	}
}


- (OOBehaviour) behaviour
{
	return behaviour;
}


- (void) setBehaviour:(OOBehaviour) cond
{
	if (cond != behaviour)
	{
		frustration = 0.0;	// change is a GOOD thing
		behaviour = cond;
	}
}


- (Vector) destination
{
	return destination;
}

- (Vector) coordinates
{
	return coordinates;
}

- (void) setCoordinate:(Vector) coord // The name "setCoordinates" is already used by AI scripting.
{
	coordinates = coord;
}

- (Vector) distance_six: (GLfloat) dist
{
	Vector six = position;
	six.x -= dist * v_forward.x;	six.y -= dist * v_forward.y;	six.z -= dist * v_forward.z;
	return six;
}


- (Vector) distance_twelve: (GLfloat) dist
{
	Vector twelve = position;
	twelve.x += dist * v_up.x;	twelve.y += dist * v_up.y;	twelve.z += dist * v_up.z;
	return twelve;
}


- (double) ballTrackTarget:(double) delta_t
{
	Vector		vector_to_target;
	Vector		axis_to_track_by;
	Vector		my_position = position;  // position relative to parent
	Vector		my_aim = vector_forward_from_quaternion(orientation);
	Vector		my_ref = reference;
	double		aim_cos, ref_cos;
	
	Entity		*target = [self primaryTarget];
	
	Entity		*last = nil;
	Entity		*father = [self parentEntity];
	OOMatrix	r_mat;
	
	while ((father)&&(father != last) && father != NO_TARGET)
	{
		r_mat = [father drawRotationMatrix];
		my_position = vector_add(OOVectorMultiplyMatrix(my_position, r_mat), [father position]);
		my_ref = OOVectorMultiplyMatrix(my_ref, r_mat);
		last = father;
		if (![last isSubEntity]) break;
		father = [father owner];
	}

	if (target)
	{
		vector_to_target = vector_subtract([target position], my_position);
		vector_to_target = vector_normal_or_fallback(vector_to_target, kBasisZVector);
		
		// do the tracking!
		aim_cos = dot_product(vector_to_target, my_aim);
		ref_cos = dot_product(vector_to_target, my_ref);
	}
	else
	{
		aim_cos = 0.0;
		ref_cos = -1.0;
	}

	if (ref_cos > TURRET_MINIMUM_COS)  // target is forward of self
	{
		axis_to_track_by = cross_product(vector_to_target, my_aim);
	}
	else
	{
		aim_cos = 0.0;
		axis_to_track_by = cross_product(my_ref, my_aim);	//	return to center
	}
	
	quaternion_rotate_about_axis(&orientation, axis_to_track_by, thrust * delta_t);
	[self orientationChanged];
	
	[self setStatus:STATUS_ACTIVE];
	
	return aim_cos;
}


- (void) trackOntoTarget:(double) delta_t withDForward: (GLfloat) dp
{
	Vector vector_to_target;
	Quaternion q_minarc;
	//
	Entity* target = [self primaryTarget];
	//
	if (!target)
		return;

	vector_to_target = target->position;
	vector_to_target.x -= position.x;	vector_to_target.y -= position.y;	vector_to_target.z -= position.z;
	//
	GLfloat range2 =		magnitude2(vector_to_target);
	GLfloat	targetRadius =	0.75 * target->collision_radius;
	GLfloat	max_cos =		sqrt(1 - targetRadius*targetRadius/range2);
	
	if (dp > max_cos)
		return;	// ON TARGET!
	
	if (vector_to_target.x||vector_to_target.y||vector_to_target.z)
		vector_to_target = vector_normal(vector_to_target);
	else
		vector_to_target.z = 1.0;
	
	q_minarc = quaternion_rotation_between(v_forward, vector_to_target);
	
	orientation = quaternion_multiply(q_minarc, orientation);
	[self orientationChanged];
	
	flightRoll = 0.0;
	flightPitch = 0.0;
}


- (double) ballTrackLeadingTarget:(double) delta_t
{
	Vector		vector_to_target;
	Vector		axis_to_track_by;
	Vector		my_position = position;  // position relative to parent
	Vector		my_aim = vector_forward_from_quaternion(orientation);
	Vector		my_ref = reference;
	double		aim_cos, ref_cos;
	Entity		*target = [self primaryTarget];
	Vector		leading = [target velocity];
	Entity		*last = nil;
	Entity		*father = [self parentEntity];
	OOMatrix	r_mat;
	
	while ((father)&&(father != last) && (father != NO_TARGET))
	{
		r_mat = [father drawRotationMatrix];
		my_position = vector_add(OOVectorMultiplyMatrix(my_position, r_mat), [father position]);
		my_ref = OOVectorMultiplyMatrix(my_ref, r_mat);
		last = father;
		if (![last isSubEntity]) break;
		father = [father owner];
	}

	if (target)
	{
		vector_to_target = vector_subtract([target position], my_position);
		float lead = magnitude(vector_to_target) / TURRET_SHOT_SPEED;
		
		vector_to_target = vector_add(vector_to_target, vector_multiply_scalar(leading, lead));
		vector_to_target = vector_normal_or_fallback(vector_to_target, kBasisZVector);
		
		// do the tracking!
		aim_cos = dot_product(vector_to_target, my_aim);
		ref_cos = dot_product(vector_to_target, my_ref);
	}
	else
	{
		aim_cos = 0.0;
		ref_cos = -1.0;
	}
	
	if (ref_cos > TURRET_MINIMUM_COS)  // target is forward of self
	{
		axis_to_track_by = cross_product(vector_to_target, my_aim);
	}
	else
	{
		aim_cos = 0.0;
		axis_to_track_by = cross_product(my_ref, my_aim);	//	return to center
	}
	
	quaternion_rotate_about_axis(&orientation, axis_to_track_by, thrust * delta_t);
	[self orientationChanged];
	
	[self setStatus:STATUS_ACTIVE];
	
	return aim_cos;
}


- (double) trackPrimaryTarget:(double) delta_t :(BOOL) retreat
{
	Entity*	target = [self primaryTarget];

	if (!target)   // leave now!
	{
		behaviour = BEHAVIOUR_IDLE;
		frustration = 0.0;
		[self noteLostTarget];	// NOTE: was AI message: rather than reactToMessage:
		return 0.0;
	}

	if (scanClass == CLASS_MISSILE)
		return [self missileTrackPrimaryTarget: delta_t];

	GLfloat  d_forward, d_up, d_right;
	
	Vector  relPos = vector_subtract(target->position, position);
	double	range2 = magnitude2(relPos);

	if (range2 > SCANNER_MAX_RANGE2)
	{
		behaviour = BEHAVIOUR_IDLE;
		frustration = 0.0;
		[self noteLostTarget];	// NOTE: was AI message: rather than reactToMessage:
		return 0.0;
	}

	//jink if retreating
	if (retreat && (range2 > 250000.0))	// don't jink if closer than 500m - just RUN
	{
		Vector vx, vy, vz;
		if (target->isShip)
		{
			ShipEntity* targetShip = (ShipEntity*)target;
			vx = targetShip->v_right;
			vy = targetShip->v_up;
			vz = targetShip->v_forward;
		}
		else
		{
			Quaternion q = target->orientation;
			vx = vector_right_from_quaternion(q);
			vy = vector_up_from_quaternion(q);
			vz = vector_forward_from_quaternion(q);
		}
		relPos.x += jink.x * vx.x + jink.y * vy.x + jink.z * vz.x;
		relPos.y += jink.x * vx.y + jink.y * vy.y + jink.z * vz.y;
		relPos.z += jink.x * vx.z + jink.y * vy.z + jink.z * vz.z;
	}

	if (!vector_equal(relPos, kZeroVector))  relPos = vector_normal(relPos);
	else  relPos.z = 1.0;

	double	targetRadius = 0.75 * target->collision_radius;

	double	max_cos = sqrt(1 - targetRadius*targetRadius/range2);

	double  rate2 = 4.0 * delta_t;
	double  rate1 = 2.0 * delta_t;

	double stick_roll = 0.0;	//desired roll and pitch
	double stick_pitch = 0.0;

	double reverse = (retreat)? -1.0: 1.0;

	double min_d = 0.004;

	d_right		=   dot_product(relPos, v_right);
	d_up		=   dot_product(relPos, v_up);
	d_forward   =   dot_product(relPos, v_forward);	// == cos of angle between v_forward and vector to target

	if (d_forward * reverse > max_cos)	// on_target!
		return d_forward;

	// begin rule-of-thumb manoeuvres
	stick_pitch = 0.0;
	stick_roll = 0.0;


	if ((reverse * d_forward < -0.5) && !pitching_over) // we're going the wrong way!
		pitching_over = YES;

	if (pitching_over)
	{
		if (reverse * d_up > 0) // pitch up
			stick_pitch = -max_flight_pitch;
		else
			stick_pitch = max_flight_pitch;
		pitching_over = (reverse * d_forward < 0.707);
	}

	// check if we are flying toward the destination..
	if ((d_forward < max_cos)||(retreat))	// not on course so we must adjust controls..
	{
		if (d_forward < -max_cos)  // hack to avoid just flying away from the destination
		{
			d_up = min_d * 2.0;
		}

		if (d_up > min_d)
		{
			int factor = sqrt(fabs(d_right) / fabs(min_d));
			if (factor > 8)
				factor = 8;
			if (d_right > min_d)
				stick_roll = - max_flight_roll * reverse * 0.125 * factor;
			if (d_right < -min_d)
				stick_roll = + max_flight_roll * reverse * 0.125 * factor;
		}
		if (d_up < -min_d)
		{
			int factor = sqrt(fabs(d_right) / fabs(min_d));
			if (factor > 8)
				factor = 8;
			if (d_right > min_d)
				stick_roll = + max_flight_roll * reverse * 0.125 * factor;
			if (d_right < -min_d)
				stick_roll = - max_flight_roll * reverse * 0.125 * factor;
		}

		if (stick_roll == 0.0)
		{
			int factor = sqrt(fabs(d_up) / fabs(min_d));
			if (factor > 8)
				factor = 8;
			if (d_up > min_d)
				stick_pitch = - max_flight_pitch * reverse * 0.125 * factor;
			if (d_up < -min_d)
				stick_pitch = + max_flight_pitch * reverse * 0.125 * factor;
		}
	}

	// end rule-of-thumb manoeuvres

	// apply 'quick-stop' to roll and pitch adjustments
	if (((stick_roll > 0.0)&&(flightRoll < 0.0))||((stick_roll < 0.0)&&(flightRoll > 0.0)))
		rate1 *= 4.0;	// much faster correction
	if (((stick_pitch > 0.0)&&(flightPitch < 0.0))||((stick_pitch < 0.0)&&(flightPitch > 0.0)))
		rate2 *= 4.0;	// much faster correction

	// apply stick movement limits
	if (flightRoll < stick_roll - rate1)
		stick_roll = flightRoll + rate1;
	if (flightRoll > stick_roll + rate1)
		stick_roll = flightRoll - rate1;
	if (flightPitch < stick_pitch - rate2)
		stick_pitch = flightPitch + rate2;
	if (flightPitch > stick_pitch + rate2)
		stick_pitch = flightPitch - rate2;

	// apply stick to attitude control
	flightRoll = stick_roll;
	flightPitch = stick_pitch;

	if (retreat)
		d_forward *= d_forward;	// make positive AND decrease granularity

	if (d_forward < 0.0)
		return 0.0;

	if ((!flightRoll)&&(!flightPitch))	// no correction
		return 1.0;

	return d_forward;
}


- (double) missileTrackPrimaryTarget:(double) delta_t
{
	Vector  relPos;
	GLfloat  d_forward, d_up, d_right;
	Entity  *target = [self primaryTarget];

	if (!target)   // leave now!
		return 0.0;

	double  damping = 0.5 * delta_t;
	double  rate2 = 4.0 * delta_t;
	double  rate1 = 2.0 * delta_t;

	double stick_roll = 0.0;	//desired roll and pitch
	double stick_pitch = 0.0;

	relPos = vector_subtract(target->position, position);
	
	
	// Adjust missile course by taking into account target's velocity and missile
	// accuracy. Modification on original code contributed by Cmdr James.

	float missileSpeed = (float)[self speed];

	// Avoid getting ourselves in a divide by zero situation by setting a missileSpeed
	// low threshold. Arbitrarily chosen 0.01, since it seems to work quite well.
	// Missile accuracy is already clamped within the 0.0 to 10.0 range at initialization,
	// but doing these calculations every frame when accuracy equals 0.0 just wastes cycles.
	if (missileSpeed > 0.01f && accuracy > 0.0f)
	{
		Vector leading = [target velocity]; 
		float lead = magnitude(relPos) / missileSpeed; 
		
		// Adjust where we are going to take into account target's velocity.
		// Use accuracy value to determine how well missile will track target.
		relPos.x += (lead * leading.x * (accuracy / 10.0f)); 
		relPos.y += (lead * leading.y * (accuracy / 10.0f)); 
		relPos.z += (lead * leading.z * (accuracy / 10.0f)); 
	}

	if (!vector_equal(relPos, kZeroVector))  relPos = vector_normal(relPos);
	else  relPos.z = 1.0;

	d_right		=   dot_product(relPos, v_right);		// = cosine of angle between angle to target and v_right
	d_up		=   dot_product(relPos, v_up);		// = cosine of angle between angle to target and v_up
	d_forward   =   dot_product(relPos, v_forward);	// = cosine of angle between angle to target and v_forward

	// begin rule-of-thumb manoeuvres

	stick_roll = 0.0;

	if (pitching_over)
		pitching_over = (stick_pitch != 0.0);

	if ((d_forward < -pitch_tolerance) && (!pitching_over))
	{
		pitching_over = YES;
		if (d_up >= 0)
			stick_pitch = -max_flight_pitch;
		if (d_up < 0)
			stick_pitch = max_flight_pitch;
	}

	if (pitching_over)
	{
		pitching_over = (d_forward < 0.5);
	}
	else
	{
		stick_pitch = -max_flight_pitch * d_up;
		stick_roll = -max_flight_roll * d_right;
	}

	// end rule-of-thumb manoeuvres

	// apply damping
	if (flightRoll < 0)
		flightRoll += (flightRoll < -damping) ? damping : -flightRoll;
	if (flightRoll > 0)
		flightRoll -= (flightRoll > damping) ? damping : flightRoll;
	if (flightPitch < 0)
		flightPitch += (flightPitch < -damping) ? damping : -flightPitch;
	if (flightPitch > 0)
		flightPitch -= (flightPitch > damping) ? damping : flightPitch;

	// apply stick movement limits
	if (flightRoll + rate1 < stick_roll)
		stick_roll = flightRoll + rate1;
	if (flightRoll - rate1 > stick_roll)
		stick_roll = flightRoll - rate1;
	if (flightPitch + rate2 < stick_pitch)
		stick_pitch = flightPitch + rate2;
	if (flightPitch - rate2 > stick_pitch)
		stick_pitch = flightPitch - rate2;

	// apply stick to attitude
	flightRoll = stick_roll;
	flightPitch = stick_pitch;

	//
	//  return target confidence 0.0 .. 1.0
	//
	if (d_forward < 0.0)
		return 0.0;
	return d_forward;
}


- (double) trackDestination:(double) delta_t :(BOOL) retreat
{
	Vector  relPos;
	GLfloat  d_forward, d_up, d_right;

	BOOL	we_are_docking = (nil != dockingInstructions);

	double  rate2 = 4.0 * delta_t;
	double  rate1 = 2.0 * delta_t;

	double stick_roll = 0.0;	//desired roll and pitch
	double stick_pitch = 0.0;

	double reverse = 1.0;

	double min_d = 0.004;
	double max_cos = 0.995;  // was 0.85; should match default value of max_cos in behaviour_fly_to_destination!

	if (retreat)
		reverse = -reverse;

	if (isPlayer)
		reverse = -reverse;

	relPos = vector_subtract(destination, position);
	double range2 = magnitude2(relPos);
	double desired_range2 = desired_range*desired_range;
	
	/*	2009-7-18 Eric: We need to aim well inide the desired_range sphere round the target and not at the surface of the sphere. 
		Because of the framerate most ships normally overshoot the target and they end up flying clearly on a path
		through the sphere. Those ships give no problems, but ships with a very low turnrate will aim close to the surface and will than
		have large trouble with reaching their destination. When those ships enter the slowdown range, they have almost no speed vector
		in the direction of the target. I now used 95% of desired_range to aim at, but a smaller value might even be better. 
	*/
	if (range2 > desired_range2) max_cos = sqrt(1 - 0.90 * desired_range2/range2);  // Head for a point within 95% of desired_range.

	if (!vector_equal(relPos, kZeroVector))  relPos = vector_normal(relPos);
	else  relPos.z = 1.0;

	d_right		=   dot_product(relPos, v_right);
	d_up		=   dot_product(relPos, v_up);
	d_forward   =   dot_product(relPos, v_forward);	// == cos of angle between v_forward and vector to target

	// begin rule-of-thumb manoeuvres
	stick_pitch = 0.0;
	stick_roll = 0.0;
	
	// check if we are flying toward the destination..
	if ((d_forward < max_cos)||(retreat))	// not on course so we must adjust controls..
	{

		if (d_forward <= -max_cos)  // hack to avoid just flying away from the destination
		{
			d_up = min_d * 2.0;
		}

		if (d_up > min_d)
		{
			int factor = sqrt(fabs(d_right) / fabs(min_d));
			if (factor > 8)
				factor = 8;
			if (d_right > min_d)
				stick_roll = - max_flight_roll * reverse * 0.125 * factor;  //roll_roll * reverse;
			if (d_right < -min_d)
				stick_roll = + max_flight_roll * reverse * 0.125 * factor; //roll_roll * reverse;
		}
		if (d_up < -min_d)
		{
			int factor = sqrt(fabs(d_right) / fabs(min_d));
			if (factor > 8)
				factor = 8;
			if (d_right > min_d)
				stick_roll = + max_flight_roll * reverse * 0.125 * factor;  //roll_roll * reverse;
			if (d_right < -min_d)
				stick_roll = - max_flight_roll * reverse * 0.125 * factor; //roll_roll * reverse;
		}

		if (stick_roll == 0.0)
		{
			int factor = sqrt(fabs(d_up) / fabs(min_d));
			if (factor > 8)
				factor = 8;
			if (d_up > min_d)
				stick_pitch = - max_flight_pitch * reverse * 0.125 * factor;  //pitch_pitch * reverse;
			if (d_up < -min_d)
				stick_pitch = + max_flight_pitch * reverse * 0.125 * factor;  //pitch_pitch * reverse;
		}
	}

	if (we_are_docking && docking_match_rotation && (d_forward > max_cos))
	{
		/* we are docking and need to consider the rotation/orientation of the docking port */
		StationEntity* station_for_docking = (StationEntity*)[UNIVERSE entityForUniversalID:targetStation];

		if ((station_for_docking)&&(station_for_docking->isStation))
		{
			stick_roll = [self rollToMatchUp:[station_for_docking portUpVectorForShipsBoundingBox: boundingBox] rotating:[station_for_docking flightRoll]];
		}
	}

	// end rule-of-thumb manoeuvres

	// apply 'quick-stop' to roll and pitch adjustments
	if (((stick_roll > 0.0)&&(flightRoll < 0.0))||((stick_roll < 0.0)&&(flightRoll > 0.0)))
		rate1 *= 4.0;	// much faster correction
	if (((stick_pitch > 0.0)&&(flightPitch < 0.0))||((stick_pitch < 0.0)&&(flightPitch > 0.0)))
		rate2 *= 4.0;	// much faster correction

	// apply stick movement limits
	if (flightRoll < stick_roll - rate1)
		stick_roll = flightRoll + rate1;
	if (flightRoll > stick_roll + rate1)
		stick_roll = flightRoll - rate1;
	if (flightPitch < stick_pitch - rate2)
		stick_pitch = flightPitch + rate2;
	if (flightPitch > stick_pitch + rate2)
		stick_pitch = flightPitch - rate2;
	
	// apply stick to attitude control
	flightRoll = stick_roll;
	flightPitch = stick_pitch;

	if (retreat)
		d_forward *= d_forward;	// make positive AND decrease granularity

	if (d_forward < 0.0)
		return 0.0;

	if ((!flightRoll)&&(!flightPitch))	// no correction
		return 1.0;

	return d_forward;
}


- (GLfloat) rollToMatchUp:(Vector) up_vec rotating:(GLfloat) match_roll;
{
	GLfloat cosTheta = dot_product(up_vec, v_up);	// == cos of angle between up vectors
	GLfloat sinTheta = dot_product(up_vec, v_right);

	if (!isPlayer)
	{
		match_roll = -match_roll;	// make necessary corrections for a different viewpoint
		sinTheta = -sinTheta;
	}

	if (cosTheta < 0.0f)
	{
		cosTheta = -cosTheta;
		sinTheta = -sinTheta;
	}

	if (sinTheta > 0.0f)
	{
		// increase roll rate
		return cosTheta * cosTheta * match_roll + sinTheta * sinTheta * max_flight_roll;
	}
	else
	{
		// decrease roll rate
		return cosTheta * cosTheta * match_roll - sinTheta * sinTheta * max_flight_roll;
	}
}


- (GLfloat) rangeToDestination
{
	return sqrtf(distance2(position, destination));
}


- (double) rangeToPrimaryTarget
{
	double dist;
	Vector delta;
	Entity  *target = [self primaryTarget];
	if (target == nil)   // leave now!
		return 0.0;
	delta = target->position;
	delta.x -= position.x;
	delta.y -= position.y;
	delta.z -= position.z;
	dist = sqrt(delta.x*delta.x + delta.y*delta.y + delta.z*delta.z);
	dist -= target->collision_radius;
	dist -= collision_radius;
	return dist;
}


- (BOOL) onTarget:(BOOL) fwd_weapon
{
	GLfloat d2, radius, dq, astq;
	Vector rel_pos, urp;
	int weapon_type = (fwd_weapon)? forward_weapon_type : aft_weapon_type;
	if (weapon_type == WEAPON_THARGOID_LASER)
	{
		return (randf() < 0.05);	// one in twenty shots on target
	}
	
	Entity  *target = [self primaryTarget];
	if (target == nil)  return NO;
	if ([target status] == STATUS_DEAD)  return NO;
	
	if (isSunlit && (target->isSunlit == NO) && (randf() < 0.75))
		return NO;	// 3/4 of the time you can't see from a lit place into a darker place
	radius = target->collision_radius;
	rel_pos = target->position;
	rel_pos.x -= position.x;
	rel_pos.y -= position.y;
	rel_pos.z -= position.z;
	d2 = magnitude2(rel_pos);
	if (d2)
		urp = vector_normal(rel_pos);
	else
		urp = make_vector(0, 0, 1);
	dq = dot_product(urp, v_forward);				// cosine of angle between v_forward and unit relative position
	if (((fwd_weapon)&&(dq < 0.0)) || ((!fwd_weapon)&&(dq > 0.0)))
		return NO;

	astq = sqrt(1.0 - radius * radius / d2);	// cosine of half angle subtended by target

	return (fabs(dq) >= astq);
}


- (BOOL) fireMainWeapon:(double) range
{
	//
	// set the values for the forward weapon
	//
	[self setWeaponDataFromType:forward_weapon_type];
	weapon_energy = OOClamp_0_max_f([shipinfoDictionary oo_floatForKey:@"weapon_energy" defaultValue:weapon_energy],50.0);
	
	if ([self shotTime] < weapon_recharge_rate)
		return NO;
	
	if (range > randf() * weaponRange * accuracy)
		return NO;
	if (range > weaponRange)
		return NO;
	if (![self onTarget:YES])
		return NO;
		
	//

	BOOL fired = NO;
	switch (forward_weapon_type)
	{
		case WEAPON_PLASMA_CANNON :
			[self firePlasmaShotAtOffset:0.0 speed:NPC_PLASMA_SPEED color:[OOColor yellowColor]];
			fired = YES;
			break;
		
		case WEAPON_PULSE_LASER :
		case WEAPON_BEAM_LASER :
		case WEAPON_MINING_LASER :
		case WEAPON_MILITARY_LASER :
			[self fireLaserShotInDirection: VIEW_FORWARD];
			fired = YES;
			break;
		
		case WEAPON_THARGOID_LASER :
			[self fireDirectLaserShot];
			fired = YES;
			break;
		
		case WEAPON_NONE:
		case WEAPON_UNDEFINED:
			// Do nothing
			break;
	}

	//can we fire lasers from our subentities?
	NSEnumerator	*subEnum = nil;
	ShipEntity		*se = nil;
	for (subEnum = [self shipSubEntityEnumerator]; (se = [subEnum nextObject]); )
	{
		if ([se fireSubentityLaserShot:range])  fired = YES;
	}
	
	if (fired && cloaking_device_active && cloakPassive)
	{
		[self deactivateCloakingDevice];
	}
	
	return fired;
}


- (BOOL) fireAftWeapon:(double) range
{
	BOOL result = YES;
	//
	// save the existing weapon values
	//
	double weapon_energy1 = weapon_energy;
	double weapon_recharge_rate1 = weapon_recharge_rate;
	double weapon_range1 = weaponRange;
	//
	// set new values from aft_weapon_type
	//
	[self setWeaponDataFromType:aft_weapon_type];

	if ([self shotTime] < weapon_recharge_rate)
		return NO;
	if (![self onTarget:NO])
		return NO;
	if (range > randf() * weaponRange)
		return NO;

	if (result)
	{
		switch (aft_weapon_type)
		{
			case WEAPON_PULSE_LASER :
			case WEAPON_BEAM_LASER :
			case WEAPON_MINING_LASER :
			case WEAPON_MILITARY_LASER :
				[self fireLaserShotInDirection:VIEW_AFT];
				break;
			case WEAPON_THARGOID_LASER :
				[self fireDirectLaserShot];
				return YES;
				break;
			
			case WEAPON_PLASMA_CANNON:	// FIXME: NPCs can't have rear plasma cannons, for no obvious reason.
			case WEAPON_UNDEFINED:
			case WEAPON_NONE:
				// do nothing
				break;
		}
	}
	
	// restore previous values
	weapon_energy = weapon_energy1;
	weapon_recharge_rate = weapon_recharge_rate1;
	weaponRange = weapon_range1;
	//
	return result;
}


- (OOTimeDelta) shotTime
{
	return shot_time;
}


- (void) resetShotTime
{
	shot_time = 0.0;
}


- (BOOL) fireTurretCannon:(double) range
{
	if ([self shotTime] < weapon_recharge_rate)
		return NO;
	if (range > TURRET_SHOT_RANGE * 1.01) // 1% more than max range - open up just slightly early
		return NO;
	
	Vector		origin = position;
	Entity		*last = nil;
	Entity		*father = [self parentEntity];
	OOMatrix	r_mat;
	Vector		vel;
	
	while ((father)&&(father != last) && (father != NO_TARGET))
	{
		r_mat = [father drawRotationMatrix];
		origin = vector_add(OOVectorMultiplyMatrix(origin, r_mat), [father position]);
		last = father;
		if (![last isSubEntity]) break;
		father = [father owner];
	}
	
	vel = vector_forward_from_quaternion(orientation);		// Facing
	origin = vector_add(origin, vector_multiply_scalar(vel, collision_radius + 0.5));	// Start just outside collision sphere
	vel = vector_multiply_scalar(vel, TURRET_SHOT_SPEED);	// Shot velocity
	
	OOPlasmaShotEntity *shot = [[OOPlasmaShotEntity alloc] initWithPosition:origin
																   velocity:vel
																	 energy:weapon_energy
																   duration:TURRET_SHOT_DURATION
																	  color:laser_color];
	
	[shot autorelease];
	[UNIVERSE addEntity:shot];
	[shot setOwner:[self rootShipEntity]];	// has to be done AFTER adding shot to the UNIVERSE
	
	[self resetShotTime];
	return YES;
}


- (void) setLaserColor:(OOColor *) color
{
	if (color)
	{
		[laser_color release];
		laser_color = [color retain];
	}
}


- (OOColor *)laserColor
{
	return [[laser_color retain] autorelease];
}


- (BOOL) fireSubentityLaserShot: (double) range
{
	ParticleEntity  *shot;
	int				direction = VIEW_FORWARD;
	GLfloat			hit_at_range;
	target_laser_hit = NO_TARGET;

	if (forward_weapon_type == WEAPON_NONE)
		return NO;
	[self setWeaponDataFromType:forward_weapon_type];

	ShipEntity* parent = (ShipEntity*)[self owner];

	if ([self shotTime] < weapon_recharge_rate)
		return NO;

	if (range > weaponRange)
		return NO;

	hit_at_range = weaponRange;
	target_laser_hit = [UNIVERSE getFirstEntityHitByLaserFromEntity:self inView:direction offset: make_vector(0,0,0) rangeFound: &hit_at_range];

	shot = [[ParticleEntity alloc] initLaserFromShip:self view:direction offset:kZeroVector];
	[shot setColor:laser_color];
	[shot setScanClass: CLASS_NO_DRAW];
	ShipEntity *victim = [UNIVERSE entityForUniversalID:target_laser_hit];
	if ([victim isShip])
	{
		ShipEntity *subent = [victim subEntityTakingDamage];
		if (subent && [victim isFrangible])
		{
			// do 1% bleed-through damage...
			[victim takeEnergyDamage: 0.01 * weapon_energy from:subent becauseOf: parent];
			victim = subent;
		}

		if (hit_at_range < weaponRange)
		{
			[victim takeEnergyDamage:weapon_energy from:self becauseOf: parent];	// a very palpable hit

			[shot setCollisionRadius: hit_at_range];
			Vector vd = vector_forward_from_quaternion([shot orientation]);
			Vector flash_pos = vector_add([shot position], vector_multiply_scalar(vd, hit_at_range));
			OOFlashEffectEntity *laserFlash = [[OOFlashEffectEntity alloc] initLaserFlashWithPosition:flash_pos color:laser_color];
			[laserFlash setVelocity:[victim velocity]];
			[UNIVERSE addEntity:laserFlash];
			[laserFlash release];
		}
	}
	[UNIVERSE addEntity:shot];
	[shot release];
	
	[self resetShotTime];

	return YES;
}


- (BOOL) fireDirectLaserShot
{
	GLfloat			hit_at_range;
	Entity*	my_target = [self primaryTarget];
	if (!my_target)
		return NO;
	ParticleEntity*	shot;
	double			range_limit2 = weaponRange*weaponRange;
	Vector			r_pos = my_target->position;
	r_pos.x -= position.x;	r_pos.y -= position.y;	r_pos.z -= position.z;
	if (r_pos.x||r_pos.y||r_pos.z)
		r_pos = vector_normal(r_pos);
	else
		r_pos.z = 1.0;

	Quaternion		q_laser = quaternion_rotation_between(r_pos, make_vector(0.0f,0.0f,1.0f));
	q_laser.x += 0.01 * (randf() - 0.5);	// randomise aim a little (+/- 0.005)
	q_laser.y += 0.01 * (randf() - 0.5);
	q_laser.z += 0.01 * (randf() - 0.5);
	quaternion_normalize(&q_laser);

	Quaternion q_save = orientation;	// save rotation
	orientation = q_laser;			// face in direction of laser
	target_laser_hit = [UNIVERSE getFirstEntityHitByLaserFromEntity:self inView:VIEW_FORWARD offset: make_vector(0,0,0) rangeFound: &hit_at_range];
	orientation = q_save;			// restore rotation

	Vector  vel = make_vector(v_forward.x * flightSpeed, v_forward.y * flightSpeed, v_forward.z * flightSpeed);

	// do special effects laser line
	shot = [[ParticleEntity alloc] initLaserFromShip:self view:VIEW_FORWARD offset:kZeroVector];
	[shot setColor:laser_color];
	[shot setScanClass: CLASS_NO_DRAW];
	[shot setPosition: position];
	[shot setOrientation: q_laser];
	[shot setVelocity: vel];
	ShipEntity *victim = [UNIVERSE entityForUniversalID:target_laser_hit];
	if ([victim isShip])
	{
		ShipEntity *subent = [victim subEntityTakingDamage];
		if (subent != nil && [victim isFrangible])
		{
			// do 1% bleed-through damage...
			[victim takeEnergyDamage: 0.01 * weapon_energy from:subent becauseOf:self];
			victim = subent;
		}

		if (hit_at_range * hit_at_range < range_limit2)
		{
			[victim takeEnergyDamage:weapon_energy from:self becauseOf:self];	// a very palpable hit

			[shot setCollisionRadius: hit_at_range];
			Vector vd = vector_forward_from_quaternion([shot orientation]);
			Vector flash_pos = vector_add([shot position], vector_multiply_scalar(vd, hit_at_range));
			OOFlashEffectEntity *laserFlash = [[OOFlashEffectEntity alloc] initLaserFlashWithPosition:flash_pos color:laser_color];
			[laserFlash setVelocity:[victim velocity]];
			[UNIVERSE addEntity:laserFlash];
			[laserFlash release];
		}
	}
	[UNIVERSE addEntity:shot];
	[shot release];
	
	[self resetShotTime];

	// random laser over-heating for AI ships
	if ((!isPlayer)&&((ranrot_rand() & 255) < weapon_energy)&&(![self isMining]))
	{
		shot_time -= (randf() * weapon_energy);
	}

	return YES;
}


- (BOOL) fireLaserShotInDirection: (OOViewID) direction
{
	ParticleEntity  *shot;
	double			range_limit2 = weaponRange*weaponRange;
	GLfloat			hit_at_range;
	Vector  vel;
	target_laser_hit = NO_TARGET;

	vel.x = v_forward.x * flightSpeed;
	vel.y = v_forward.y * flightSpeed;
	vel.z = v_forward.z * flightSpeed;

	Vector	laserPortOffset;

	switch(direction)
	{
		case VIEW_AFT:
			laserPortOffset = aftWeaponOffset;
			break;
		case VIEW_PORT:
			laserPortOffset = portWeaponOffset;
			break;
		case VIEW_STARBOARD:
			laserPortOffset = starboardWeaponOffset;
			break;
		default:
			laserPortOffset = forwardWeaponOffset;
	}

	target_laser_hit = [UNIVERSE getFirstEntityHitByLaserFromEntity:self inView:direction offset:laserPortOffset rangeFound: &hit_at_range];
	
	shot = [[ParticleEntity alloc] initLaserFromShip:self view:direction offset:laserPortOffset];	// alloc retains!

	[shot setColor:laser_color];
	[shot setScanClass: CLASS_NO_DRAW];
	[shot setVelocity: vel];
	ShipEntity *victim = [UNIVERSE entityForUniversalID:target_laser_hit];
	if ([victim isShip])
	{
		/*	CRASH in [victim->sub_entities containsObject:subent] here (1.69, OS X/x86).
			Analysis: Crash is in _freedHandler called from CFEqual, indicating either a dead
			object in victim->sub_entities or dead victim->subentity_taking_damage. I suspect
			the latter. Probable solution: dying subentities must cause parent to clean up
			properly. This was probably obscured by the entity recycling scheme in the past.
			Fix: made subentity_taking_damage a weak reference accessed via a method.
			-- Ahruman 20070706, 20080304
		*/
		ShipEntity *subent = [victim subEntityTakingDamage];
		if (subent != nil && [victim isFrangible])
		{
			// do 1% bleed-through damage...
			[victim takeEnergyDamage: 0.01 * weapon_energy from:subent becauseOf:self];
			victim = subent;
		}

		if (hit_at_range * hit_at_range < range_limit2)
		{
			[victim takeEnergyDamage:weapon_energy from:self becauseOf:self];	// a very palpable hit

			[shot setCollisionRadius:hit_at_range];
			Vector vd = vector_forward_from_quaternion([shot orientation]);
			Vector flash_pos = vector_add([shot position], vector_multiply_scalar(vd, hit_at_range));
			OOFlashEffectEntity *laserFlash = [[OOFlashEffectEntity alloc] initLaserFlashWithPosition:flash_pos color:laser_color];
			[laserFlash setVelocity:[victim velocity]];
			[UNIVERSE addEntity:laserFlash];
			[laserFlash release];
		}
	}
	[UNIVERSE addEntity:shot];
	[shot release]; //release
	
	[self resetShotTime];

	// random laser over-heating for AI ships
	if ((!isPlayer)&&((ranrot_rand() & 255) < weapon_energy)&&(![self isMining]))
	{
		shot_time -= (randf() * weapon_energy);
	}

	return YES;
}

- (void) throwSparks
{
	OOSparkEntity *spark = nil;
	Vector  vel;
	Vector  origin = position;

	GLfloat lr	= randf() * (boundingBox.max.x - boundingBox.min.x) + boundingBox.min.x;
	GLfloat ud	= randf() * (boundingBox.max.y - boundingBox.min.y) + boundingBox.min.y;
	GLfloat fb	= randf() * boundingBox.max.z + boundingBox.min.z;	// rear section only

	origin.x += fb * v_forward.x;
	origin.y += fb * v_forward.y;
	origin.z += fb * v_forward.z;

	origin.x += ud * v_up.x;
	origin.y += ud * v_up.y;
	origin.z += ud * v_up.z;

	origin.x += lr * v_right.x;
	origin.y += lr * v_right.y;
	origin.z += lr * v_right.z;

	float	w = boundingBox.max.x - boundingBox.min.x;
	float	h = boundingBox.max.y - boundingBox.min.y;
	float	m = (w < h) ? 0.25 * w: 0.25 * h;

	float	sz = m * (1 + randf() + randf());	// half minimum dimension on average

	vel = make_vector(2.0 * (origin.x - position.x), 2.0 * (origin.y - position.y), 2.0 * (origin.z - position.z));
	
	OOColor *color = [OOColor colorWithCalibratedHue:0.08 + 0.17 * randf() saturation:1.0 brightness:1.0 alpha:1.0];
	
	spark = [[OOSparkEntity alloc] initWithPosition:origin
										   velocity:vel
										   duration:2.0 + 3.0 * randf()
											   size:sz
											  color:color];
	
	[spark setOwner:self];
	[UNIVERSE addEntity:spark];
	[spark release];

	next_spark_time = randf();
}


- (BOOL) firePlasmaShotAtOffset:(double)offset speed:(double)speed color:(OOColor *)color
{
	Vector  vel, rt;
	Vector  origin = position;
	double  start = collision_radius + 0.5;

	speed += flightSpeed;

	if (++shot_counter % 2)
		offset = -offset;

	vel = v_forward;
	rt = v_right;

	if (isPlayer)					// player can fire into multiple views!
	{
		switch ([UNIVERSE viewDirection])
		{
			case VIEW_AFT :
				vel = vector_flip(v_forward);
				rt = vector_flip(v_right);
				break;
			case VIEW_STARBOARD :
				vel = v_right;
				rt = vector_flip(v_forward);
				break;
			case VIEW_PORT :
				vel = vector_flip(v_right);
				rt = v_forward;
				break;
			
			default:
				break;
		}
	}
	
	origin = vector_add(origin, vector_multiply_scalar(vel, start));
	origin = vector_add(origin, vector_multiply_scalar(rt, offset));
	
	vel = vector_multiply_scalar(vel, speed);
	
	OOPlasmaShotEntity *shot = [[OOPlasmaShotEntity alloc] initWithPosition:origin
																   velocity:vel
																	 energy:weapon_energy
																   duration:MAIN_PLASMA_DURATION
																	  color:color];
	
	[UNIVERSE addEntity:shot];
	[shot setOwner:[self rootShipEntity]];
	[shot release];
	
	[self resetShotTime];
	
	return YES;
}


- (ShipEntity *) fireMissile
{
	return [self fireMissileWithIdentifier:nil andTarget:[self primaryTarget]];
}


- (ShipEntity *) fireMissileWithIdentifier:(NSString *) identifier andTarget:(Entity *) target
{
	ShipEntity		*missile = nil;
	ShipEntity		*target_ship = nil;
	
	Vector			vel;
	Vector			origin = position;
	Vector			start, v_eject;
	
	if ([UNIVERSE getTime] < missile_launch_time) return nil;

	// default launching position
	start.x = 0.0f;						// in the middle
	start.y = boundingBox.min.y - 4.0f;	// 4m below bounding box
	start.z = boundingBox.max.z + 1.0f;	// 1m ahead of bounding box
	// custom launching position
	ScanVectorFromString([shipinfoDictionary objectForKey:@"missile_launch_position"], &start);
	
	double  throw_speed = 250.0f;
	Quaternion q1 = orientation;
	if (isPlayer) q1.w = -q1.w;   // player view is reversed!
	
	if	((missiles <= 0)||(target == nil)||(target->scanClass == CLASS_NO_DRAW))	// no missile lock!
		return nil;
	
	if ([target isShip])
	{
		target_ship = (ShipEntity*)target;
		if ([target_ship isCloaked])  return nil;
		if (![self hasMilitaryScannerFilter] && [target_ship isJammingScanning]) return nil;
	}
	
	unsigned i;
	if (identifier == nil)
	{
		// use a random missile from the list
		i = floor(randf()*(double)missiles);
		identifier = [missile_list[i] identifier];
		missile = [UNIVERSE newShipWithRole:identifier];
		if (missile == nil)	// invalid missile role.
		{
			// remove that invalid missile role from the missiles list.
			while ( ++i < missiles ) missile_list[i - 1] = missile_list[i];
			missiles--;
		}
	}
	else
		missile = [UNIVERSE newShipWithRole:identifier];
	
	if (missile == nil)	return nil;
	
	// By definition, the player will always have the specified missile.
	// What if the NPC didn't actually have the specified missile to begin with?
	if (!isPlayer && ![self removeExternalStore:[OOEquipmentType equipmentTypeWithIdentifier:identifier]])
	{
		[missile release];
		return nil;
	}
	
	double mcr = missile->collision_radius;
	v_eject = vector_normal(start);
	vel = kZeroVector;	// starting velocity
	
	// check if start is within bounding box...
	while (	(start.x > boundingBox.min.x - mcr)&&(start.x < boundingBox.max.x + mcr)&&
			(start.y > boundingBox.min.y - mcr)&&(start.y < boundingBox.max.y + mcr)&&
			(start.z > boundingBox.min.z - mcr)&&(start.z < boundingBox.max.z + mcr) )
	{
		start = vector_add(start, vector_multiply_scalar(v_eject, mcr));
		
		// Kept different vel calculations for player & NPCs. Is there an acutal reason for that difference? - Kaks 20091204
		if (!isPlayer) vel = vector_add(vel, vector_multiply_scalar(v_eject, 10.0f * mcr)); // throw it outward a bit harder
	}
	
	// Kept different vel calculations for player & NPCs. Is there an acutal reason for that difference? - Kaks 20091204
	if (isPlayer) vel = vector_multiply_scalar(v_forward, flightSpeed + throw_speed);
	else vel = vector_add(vel, vector_multiply_scalar(v_forward, flightSpeed + throw_speed));
	

	origin.x = position.x + v_right.x * start.x + v_up.x * start.y + v_forward.x * start.z;
	origin.y = position.y + v_right.y * start.x + v_up.y * start.y + v_forward.y * start.z;
	origin.z = position.z + v_right.z * start.x + v_up.z * start.y + v_forward.z * start.z;
	
	if (isPlayer) [missile setScanClass: CLASS_MISSILE];
	
// special cases
	
	//We don't want real missiles in a group. Missiles could become escorts when the group is also used as escortGroup.
	if ([missile scanClass] == CLASS_THARGOID) 
	{
		if([self group] == nil) [self setGroup:[OOShipGroup groupWithName:@"thargoid group"]];
		[missile setGroup:[self group]];
	}
	
	// is this a submunition?
	if (![self isMissileFlagSet])  [missile setOwner:self];
	else  [missile setOwner:[self owner]];
	
// end special cases
	
	[missile setPosition:origin];
	[missile addTarget:target];	
	[missile setOrientation:q1];
	[missile setStatus:STATUS_IN_FLIGHT];  // necessary to get it going!
	[missile setIsMissileFlag:YES];
	[missile setVelocity:vel];
	[missile setSpeed:150.0f];
	[missile setDistanceTravelled:0.0f];
	[missile resetShotTime];
	missile_launch_time = [UNIVERSE getTime] + missile_load_time; // set minimum launchtime for the next missile.
	
	[UNIVERSE addEntity:missile];
	[missile release]; //release
	
	// missile lives on after UNIVERSE addEntity
	if ([missile scanClass] == CLASS_MISSILE && [target isShip])
	{
		[self doScriptEvent:@"shipFiredMissile" withArgument:missile andArgument:target_ship];
		[target_ship setPrimaryAggressor:self];
		[target_ship doScriptEvent:@"shipAttackedWithMissile" withArgument:missile andArgument:self];
		[target_ship reactToAIMessage:@"INCOMING_MISSILE"];
	}
	
	if (cloaking_device_active && cloakPassive)
	{
		[self deactivateCloakingDevice];
	}
	
	return missile;
}


- (BOOL) isMissileFlagSet
{
	return isMissile; // were we created using fireMissile? (for tracking submunitions)
}


- (void) setIsMissileFlag:(BOOL)newValue
{
	isMissile = !!newValue; // set the isMissile flag, used for tracking submunitions
}


// Exposed to AI
- (BOOL) fireECM
{
	if (![self hasECM])  return NO;
	
	OOECMBlastEntity *ecmDevice = [[OOECMBlastEntity alloc] initFromShip:self];
	[UNIVERSE addEntity:ecmDevice];
	[ecmDevice release];
	return YES;
}


- (BOOL) activateCloakingDevice
{
	if (![self hasCloakingDevice])  return NO;
	
	if (!cloaking_device_active)  cloaking_device_active = (energy > CLOAKING_DEVICE_START_ENERGY * maxEnergy);
	return cloaking_device_active;
}


- (void) deactivateCloakingDevice
{
	cloaking_device_active = NO;
}


- (BOOL) launchEnergyBomb
{
	if (![self hasEnergyBomb])  return NO;
	[self setSpeed: maxFlightSpeed + 300];
	ShipEntity*	bomb = [UNIVERSE newShipWithRole:@"energy-bomb"];
	if (bomb == nil)  return NO;
	
	[self removeEquipmentItem:@"EQ_ENERGY_BOMB"];
	
	double  start = collision_radius + bomb->collision_radius;
	Quaternion  random_direction;
	Vector  vel;
	Vector  rpos;
	double random_roll =	randf() - 0.5;  //  -0.5 to +0.5
	double random_pitch = 	randf() - 0.5;  //  -0.5 to +0.5
	quaternion_set_random(&random_direction);
	
	rpos = vector_subtract([self position], vector_multiply_scalar(v_forward, start));
	
	double  eject_speed = -800.0;
	vel = vector_multiply_scalar(v_forward, [self flightSpeed] + eject_speed);
	eject_speed *= 0.5 * (randf() - 0.5);   //  -0.25x .. +0.25x
	vel = vector_add(vel, vector_multiply_scalar(v_up, eject_speed));
	eject_speed *= 0.5 * (randf() - 0.5);   //  -0.0625x .. +0.0625x
	vel = vector_add(vel, vector_multiply_scalar(v_right, eject_speed));
	
	[bomb setPosition:rpos];
	[bomb setOrientation:random_direction];
	[bomb setRoll:random_roll];
	[bomb setPitch:random_pitch];
	[bomb setVelocity:vel];
	[bomb setScanClass:CLASS_MINE];	// TODO should be CLASS_ENERGY_BOMB
	[bomb setStatus:STATUS_IN_FLIGHT];
	[bomb setEnergy:5.0];	// 5 second countdown
	[bomb setBehaviour:BEHAVIOUR_ENERGY_BOMB_COUNTDOWN];
	[bomb setOwner:self];
	[UNIVERSE addEntity:bomb];
	[[bomb getAI] setState:@"GLOBAL"];
	[bomb release];
	
	if (self != [PlayerEntity sharedPlayer])	// get the heck out of here
	{
		[self addTarget:bomb];
		[self setBehaviour:BEHAVIOUR_FLEE_TARGET];
		frustration = 0.0;
	}
	return YES;
}


- (OOUniversalID)launchEscapeCapsule
{
	OOUniversalID		result = NO_TARGET;
	ShipEntity			*mainPod = nil, *pod = nil;
	unsigned			n_pods;
	
	/*	BUG: player can't launch escape pod in interstellar space (because
		there is no standard place for ressurection), but NPCs can.
		FIX: don't let NPCs do it either. Submitted by Cmdr James.
		-- Ahruman 20070822
	*/
	if ([UNIVERSE station] == nil)  return NO_TARGET;
	
	// check number of pods aboard -- require at least one.
	n_pods = [shipinfoDictionary oo_unsignedIntForKey:@"has_escape_pod"];
	
	pod = [UNIVERSE newShipWithRole:[shipinfoDictionary oo_stringForKey:@"escape_pod_model" defaultValue:@"escape-capsule"]];
	mainPod = pod;
	
	if (pod)
	{
		[pod setOwner:self];
		[pod setScanClass: CLASS_CARGO];
		[pod setCommodity:[UNIVERSE commodityForName:@"Slaves"] andAmount:1];
		if (crew)	// transfer crew
		{
			// make sure crew inherit any legalStatus
			unsigned i;
			for (i = 0; i < [crew count]; i++)
			{
				OOCharacter *ch = (OOCharacter*)[crew objectAtIndex:i];
				[ch setLegalStatus: [self legalStatus] | [ch legalStatus]];
			}
			[pod setCrew:crew];
			[self setCrew:nil];
			[self setHulk:YES]; //CmdrJames experiment with fixing ejection behaviour
		}
		[[pod getAI] setStateMachine:@"homeAI.plist"];
		[self dumpItem:pod];
		[[pod getAI] setState:@"GLOBAL"];
		[pod release]; //release
		result = [pod universalID];
	}
	// launch other pods (passengers)
	unsigned i;
	for (i = 1; i < n_pods; i++)
	{
		pod = [UNIVERSE newShipWithRole:@"escape-capsule"];
		if (pod)
		{
			Random_Seed orig = [UNIVERSE systemSeedForSystemNumber:gen_rnd_number()];
			[pod setOwner:self];
			[pod setScanClass: CLASS_CARGO];
			[pod setCommodity:[UNIVERSE commodityForName:@"Slaves"] andAmount:1];
			[pod setCrew:[NSArray arrayWithObject:[OOCharacter randomCharacterWithRole:@"passenger" andOriginalSystem:orig]]];
			[[pod getAI] setStateMachine:@"homeAI.plist"];
			[self dumpItem:pod];
			[[pod getAI] setState:@"GLOBAL"];
			[pod release]; //release
		}
	}
	
	[self doScriptEvent:@"shipLaunchedEscapePod" withArgument:mainPod];
	
	return result;
}


// This is a documented AI method; do not change semantics. (Note: AIs don't have access to the return value.)
- (OOCargoType) dumpCargo
{
	ShipEntity *jetto = [self dumpCargoItem];
	if (jetto != nil)  return [jetto commodityType];
	else  return CARGO_NOT_CARGO;
}


- (ShipEntity *) dumpCargoItem
{
	ShipEntity				*jetto = nil;
	
	if (([cargo count] > 0)&&([UNIVERSE getTime] - cargo_dump_time > 0.5))  // space them 0.5s or 10m apart
	{
		jetto = [[[cargo objectAtIndex:0] retain] autorelease];
		if (jetto != nil)
		{
			[self dumpItem:jetto];
			[cargo removeObjectAtIndex:0];
			[[UNIVERSE findShipsMatchingPredicate:YESPredicate
									   parameter:nil
										 inRange:SCANNER_MAX_RANGE2
										ofEntity:self]
					makeObjectsPerformSelector:@selector(sendAIMessage:) withObject:@"CARGO_DUMPED"];
		}
	}
	
	return jetto;
}


- (OOCargoType) dumpItem: (ShipEntity*) jetto
{
	if (!jetto)
		return 0;
	int		result = [jetto cargoType];
	AI		*jettoAI = nil;
	Vector	start;

	double  eject_speed = 20.0;
	double  eject_reaction = -eject_speed * [jetto mass] / [self mass];
	double	jcr = jetto->collision_radius;

	Quaternion  random_direction;
	Vector  vel, v_eject;
	Vector  rpos = position;
	double random_roll =	((ranrot_rand() % 1024) - 512.0)/1024.0;  //  -0.5 to +0.5
	double random_pitch =   ((ranrot_rand() % 1024) - 512.0)/1024.0;  //  -0.5 to +0.5
	quaternion_set_random(&random_direction);

	// default launching position
	start.x = 0.0;						// in the middle
	start.y = 0.0;						//
	start.z = boundingBox.min.z - jcr;	// 1m behind of bounding box

	// custom launching position
	ScanVectorFromString([shipinfoDictionary objectForKey:@"aft_eject_position"], &start);

	v_eject = vector_normal(start);

	// check if start is within bounding box...
	while (	(start.x > boundingBox.min.x - jcr)&&(start.x < boundingBox.max.x + jcr)&&
			(start.y > boundingBox.min.y - jcr)&&(start.y < boundingBox.max.y + jcr)&&
			(start.z > boundingBox.min.z - jcr)&&(start.z < boundingBox.max.z + jcr))
	{
		start = vector_add(start, vector_multiply_scalar(v_eject, jcr));
	}

	v_eject = make_vector(	v_right.x * start.x +	v_up.x * start.y +	v_forward.x * start.z,
							v_right.y * start.x +	v_up.y * start.y +	v_forward.y * start.z,
							v_right.z * start.x +	v_up.z * start.y +	v_forward.z * start.z);
	
	rpos = vector_add(rpos, v_eject);
	v_eject = vector_normal(v_eject);
	
	v_eject.x += (randf() - randf())/eject_speed;
	v_eject.y += (randf() - randf())/eject_speed;
	v_eject.z += (randf() - randf())/eject_speed;
	
	vel = vector_add(vector_multiply_scalar(v_forward, flightSpeed), vector_multiply_scalar(v_eject, eject_speed));
	velocity = vector_add(velocity, vector_multiply_scalar(v_eject, eject_reaction));
	
	[jetto setPosition:rpos];
	[jetto setOrientation:random_direction];
	[jetto setRoll:random_roll];
	[jetto setPitch:random_pitch];
	[jetto setVelocity:vel];
	[jetto setScanClass: CLASS_CARGO];
	[jetto setStatus: STATUS_IN_FLIGHT];
	[jetto setTemperature:[self temperature] * EJECTA_TEMP_FACTOR];
	[UNIVERSE addEntity:jetto];

	jettoAI = [jetto getAI];
	if ([jettoAI hasSuspendedStateMachines]) // check if this was previos scooped cargo.
	{
		[jetto setThrust:[jetto maxThrust]]; // restore old thrust.
		[jetto setOwner:jetto];
		[jettoAI exitStateMachineWithMessage:nil]; // exit nullAI.
	}
	else 
	{
		[jettoAI setState:@"GLOBAL"];
	}
	cargo_dump_time = [UNIVERSE getTime];
	return result;
}


- (void) manageCollisions
{
	// deal with collisions
	//
	Entity*		ent;
	ShipEntity* other_ship;

	while ([collidingEntities count] > 0)
	{
		ent = [(Entity *)[collidingEntities objectAtIndex:0] retain];
		[collidingEntities removeObjectAtIndex:0];
		if (ent)
		{
			if ([ent isShip])
			{
				other_ship = (ShipEntity *)ent;
				[self collideWithShip:other_ship];
			}
			else if ([ent isStellarObject])
			{
				[self getDestroyedBy:ent context:[ent isSun] ? @"hit a sun" : @"hit a planet"];
				if (self == [PlayerEntity sharedPlayer]) [self retain];
			}
			else if ([ent isWormhole])
			{
				WormholeEntity* whole = (WormholeEntity*)ent;
				if (isPlayer)
				{
					[(PlayerEntity*)self enterWormhole: whole];
					return;
				}
				else
				{
					[whole suckInShip: self];
				}
			}
			[ent release];
		}
	}
}


- (BOOL) collideWithShip:(ShipEntity *)other
{
	Vector  loc;
	double  dam1, dam2;
	
	if (!other)
		return NO;
	
	ShipEntity* otherParent = [other parentEntity];
	BOOL otherIsStation = other == [UNIVERSE station];
	// calculate line of centers using centres
	loc = vector_normal_or_zbasis(vector_subtract([other absolutePositionForSubentity], position));
	
	if ([self canScoop:other])
	{
		[self scoopIn:other];
		return NO;
	}
	if ([other canScoop:self])
	{
		[other scoopIn:self];
		return NO;
	}
	if (universalID == NO_TARGET)
		return NO;
	if (other->universalID == NO_TARGET)
		return NO;

	// find velocity along line of centers
	//
	// momentum = mass x velocity
	// ke = mass x velocity x velocity
	//
	GLfloat m1 = mass;			// mass of self
	GLfloat m2 = [other mass];	// mass of other

	// starting velocities:
	Vector	v, vel1b =	[self velocity];
	
	if (otherParent != nil)
	{
		// Subentity
		/*	TODO: if the subentity is rotating (subentityRotationalVelocity is
			not 1 0 0 0) we should calculate the tangential velocity from the
			other's position relative to our absolute position and add that in.
		*/
		v = [otherParent velocity];
	}
	else
	{
		v = [other velocity];
	}

	v = vector_subtract(vel1b, v);
	
	GLfloat	v2b = dot_product(v, loc);			// velocity of other along loc before collision
	
	GLfloat v1a = sqrt(v2b * v2b * m2 / m1);	// velocity of self along loc after elastic collision
	if (v2b < 0.0f)	v1a = -v1a;					// in same direction as v2b
	
	// are they moving apart at over 1m/s already?
	if (v2b < 0.0f)
	{
		if (v2b < -1.0f)  return NO;
		else
		{
			position = vector_subtract(position, loc);	// adjust self position
			v = kZeroVector;	// go for the 1m/s solution
		}
	}

	// convert change in velocity into damage energy (KE)
	dam1 = m2 * v2b * v2b / 50000000;
	dam2 = m1 * v2b * v2b / 50000000;
	
	// calculate adjustments to velocity after collision
	Vector vel1a = vector_multiply_scalar(loc, -v1a);
	Vector vel2a = vector_multiply_scalar(loc, v2b);

	if (magnitude2(v) <= 0.1)	// virtually no relative velocity - we must provide at least 1m/s to avoid conjoined objects
	{
		vel1a = vector_multiply_scalar(loc, -1);
		vel2a = loc;
	}

	// apply change in velocity
	if (otherParent != nil)
	{
		[otherParent adjustVelocity:vel2a];	// move the otherParent not the subentity
	}
	else
	{
		[other adjustVelocity:vel2a];
	}
	
	[self adjustVelocity:vel1a];
	
	BOOL selfDestroyed = (dam1 > energy);
	BOOL otherDestroyed = (dam2 > [other energy]) && !otherIsStation;
	
	if (dam1 > 0.05)
	{
		[self takeScrapeDamage: dam1 from:other];
		if (selfDestroyed)	// inelastic! - take xplosion velocity damage instead
		{
			vel2a = vector_multiply_scalar(vel2a, -1);
			[other adjustVelocity:vel2a];
		}
	}
	
	if (dam2 > 0.05)
	{
		if (otherParent != nil && ![otherParent isFrangible])
		{
			[otherParent takeScrapeDamage: dam2 from:self];
		}
		else
		{
			[other	takeScrapeDamage: dam2 from:self];
		}
		
		if (otherDestroyed)	// inelastic! - take explosion velocity damage instead
		{
			vel1a = vector_multiply_scalar(vel1a, -1);
			[self adjustVelocity:vel1a];
		}
	}
	
	if (!selfDestroyed && !otherDestroyed)
	{
		float t = 10.0 * [UNIVERSE getTimeDelta];	// 10 ticks
		
		Vector pos1a = vector_add([self position], vector_multiply_scalar(loc, t * v1a));
		[self setPosition:pos1a];
		
		if (!otherIsStation)
		{
			Vector pos2a = vector_add([other position], vector_multiply_scalar(loc, t * v2b));
			[other setPosition:pos2a];
		}
	}
	
	// remove self from other's collision list
	[[other collisionArray] removeObject:self];
	
	[self doScriptEvent:@"shipCollided" withArgument:other andReactToAIMessage:@"COLLISION"];
	
	return YES;
}


- (Vector) velocity	// overrides Entity velocity
{
	return vector_add(velocity, vector_multiply_scalar(v_forward, flightSpeed));
}


- (void) adjustVelocity:(Vector) xVel
{
	velocity = vector_add(velocity, xVel);
}


- (void) addImpactMoment:(Vector) moment fraction:(GLfloat) howmuch
{
	velocity = vector_add(velocity, vector_multiply_scalar(moment, howmuch / mass));
}


- (BOOL) canScoop:(ShipEntity*)other
{
	if (other == nil)							return NO;
	if (![self hasScoop])						return NO;
	if ([cargo count] >= max_cargo)				return NO;
	if (scanClass == CLASS_CARGO)				return NO;  // we have no power so we can't scoop
	if ([other scanClass] != CLASS_CARGO)		return NO;
	if ([other cargoType] == CARGO_NOT_CARGO)	return NO;
	
	if ([other isStation])						return NO;

	Vector  loc = vector_between(position, [other position]);
	
	if (dot_product(v_forward, loc) < 0.0f)  return NO;  // Must be in front of us
	if ([self isPlayer] && dot_product(v_up, loc) > 0.0f)  return NO;  // player has to scoop on underside, give more flexibility to NPCs
	
	return YES;
}


- (void) getTractoredBy:(ShipEntity *)other
{
	if([self status] == STATUS_BEING_SCOOPED) return; // both cargo and ship call this. Act only once.
	desired_speed = 0.0;
	[self setAITo:@"nullAI.plist"];	// prevent AI from changing status or behaviour.
	behaviour = BEHAVIOUR_TRACTORED;
	[self setStatus:STATUS_BEING_SCOOPED];
	[self addTarget:other];
	[self setOwner:other];
	[self checkScanner];
	unsigned i;
	for (i = 0; i < n_scanned_ships ; i++)
	{
		ShipEntity *scooper = (ShipEntity *)scanned_ships[i];
		// very specific. might break if the AI convention changes.
		// if (other != scoopers && (id) self == [scoopers primaryTarget] && [[[scoopers getAI] state] isEqualToString: @"COLLECT_STUFF"])
		// more generic, if other ships are trying to shoot the scooped item, they'll lose it too.
		if (other != scooper && (id) self == [scooper primaryTarget])
		{
			[scooper noteLostTarget];
		}
	}
}


- (void) scoopIn:(ShipEntity *)other
{
	[other getTractoredBy:self];
}


- (void) suppressTargetLost
{
	
}


- (void) scoopUp:(ShipEntity *)other
{
	if (other == nil)  return;
	
	OOCargoType		co_type;
	OOCargoQuantity	co_amount;
	
	// don't even think of trying to scoop if the cargo hold is already full
	if (max_cargo && [cargo count] >= max_cargo)
	{
		[other setStatus:STATUS_IN_FLIGHT];
		return;
	}
	
	switch ([other cargoType])
	{
		case CARGO_RANDOM:
			co_type = [other commodityType];
			co_amount = [other commodityAmount];
			break;
		
		case CARGO_SLAVES:
			co_amount = 1;
			co_type = [UNIVERSE commodityForName:@"Slaves"];
			break;
		
		case CARGO_ALLOY:
			co_amount = 1;
			co_type = [UNIVERSE commodityForName:@"Alloys"];
			break;
		
		case CARGO_MINERALS:
			co_amount = 1;
			co_type = [UNIVERSE commodityForName:@"Minerals"];
			break;
		
		case CARGO_THARGOID:
			co_amount = 1;
			co_type = [UNIVERSE commodityForName:@"Alien Items"];
			break;
		
		case CARGO_SCRIPTED_ITEM:
			{
				//scripting
				PlayerEntity *player = [PlayerEntity sharedPlayer];
				[player setScriptTarget:self];
				[other doScriptEvent:@"shipWasScooped" withArgument:self];
				[self doScriptEvent:@"shipScoopedOther" withArgument:other];
				
				if (isPlayer)
				{
					NSString* scoopedMS = [NSString stringWithFormat:DESC(@"@-scooped"), [other displayName]];
					[UNIVERSE clearPreviousMessage];
					[UNIVERSE addMessage:scoopedMS forCount:4];
				}
			}
		
		default :
			co_amount = 0;
			co_type = 0;
			break;
	}
	
	/*	Bug: docking failed due to NSRangeException while looking for element
		NSNotFound of cargo mainfest in -[PlayerEntity unloadCargoPods].
		Analysis: bad cargo pods being generated due to
		-[Universe commodityForName:] looking in wrong place for names.
		Fix 1: fix -[Universe commodityForName:].
		Fix 2: catch NSNotFound here and substitute random cargo type.
		-- Ahruman 20070714
	*/
	if (co_type == CARGO_UNDEFINED)
	{
		co_type = [UNIVERSE getRandomCommodity];
		co_amount = [UNIVERSE getRandomAmountOfCommodity:co_type];
	}
	
	if (co_amount > 0)
	{
		[other setCommodity:co_type andAmount:co_amount];   // belt and braces setting this!
		cargo_flag = CARGO_FLAG_CANISTERS;
		
		if (isPlayer)
		{
			[UNIVERSE clearPreviousMessage];
			if ([other crew])
			{
				unsigned i;
				for (i = 0; i < [[other crew] count]; i++)
				{
					OOCharacter *rescuee = [[other crew] objectAtIndex:i];
					if ([rescuee legalStatus])
					{
						[UNIVERSE addMessage: [NSString stringWithFormat:DESC(@"scoop-captured-@"), [rescuee name]] forCount: 4.5];
					}
					else if ([rescuee insuranceCredits])
					{
						[UNIVERSE addMessage: [NSString stringWithFormat:DESC(@"scoop-rescued-@"), [rescuee name]] forCount: 4.5];
					}
					else
					{
						[UNIVERSE addMessage: DESC(@"scoop-got-slave") forCount: 4.5];
					}
					[(PlayerEntity *)self playEscapePodScooped];
				}
			}
			else
			{
				[UNIVERSE addMessage:[UNIVERSE describeCommodity:co_type amount:co_amount] forCount:4.5];
			}
		}
		[cargo insertObject: other atIndex: 0];	// places most recently scooped object at eject position
		[other setStatus:STATUS_IN_HOLD];
		[other setBehaviour:BEHAVIOUR_TUMBLE];
		[shipAI message:@"CARGO_SCOOPED"];
		if (max_cargo && [cargo count] >= max_cargo)  [shipAI message:@"HOLD_FULL"];
	}
	[[other collisionArray] removeObject:self];			// so it can't be scooped twice!
	[self suppressTargetLost];
	[UNIVERSE removeEntity:other];
}


- (void) takeEnergyDamage:(double)amount from:(Entity *)ent becauseOf:(Entity *)other
{
	if ([self status] == STATUS_DEAD)  return;
	if (amount <= 0.0)  return;
	
	// If it's an energy mine...
	BOOL energyMine = ([ent isParticle] && [ent scanClass] == CLASS_MINE);
	if (energyMine)
	{
		switch (scanClass)
		{
			case CLASS_WORMHOLE :
			case CLASS_ROCK :
			case CLASS_CARGO :
			case CLASS_BUOY :
				// does not normally cascade
				if ((fuel > MIN_FUEL) || isStation) 
				{
					//we have fuel onboard so we can still go pop, or we are a station which can
				}
				else break;
			case CLASS_STATION :
			case CLASS_MINE :
			case CLASS_PLAYER :
			case CLASS_POLICE :
			case CLASS_MILITARY :
			case CLASS_THARGOID :
			case CLASS_MISSILE :
			case CLASS_NOT_SET :
			case CLASS_NO_DRAW :
			case CLASS_NEUTRAL :
			case CLASS_TARGET :
				// ...start a chain reaction, if we're dying and have a non-trivial amount of energy.
				if (energy < amount && energy > 10)
				{
					ParticleEntity *chainReaction = [[ParticleEntity alloc] initEnergyMineFromShip:self];
					[UNIVERSE addEntity:chainReaction];
					[chainReaction setOwner:[ent owner]];
					[chainReaction release];
				}				
				break;
			//no default thanks, we want the compiler to tell us if we missed a case.
		}
	}
	
	energy -= amount;
	being_mined = NO;
	ShipEntity *hunter = nil;
	
	if ([other isShip] && [self owner] != other) // our owner could be the same entity as the one responsible for our taking damage in the case of submunitions
	{
		hunter = (ShipEntity *)other;
		if ([hunter isCloaked])
		{
			[self doScriptEvent:@"shipBeingAttackedByCloaked" andReactToAIMessage:@"ATTACKED_BY_CLOAKED"];
			
			// lose it!
			other = nil;
			hunter = nil;
		}
	}
	
	// if the other entity is a ship note it as an aggressor
	if (hunter != nil)
	{
		BOOL iAmTheLaw = [self isPolice];
		BOOL uAreTheLaw = [hunter isPolice];
		
		last_escort_target = NO_TARGET;	// we're being attacked, escorts can scramble!
		
		primaryAggressor = [hunter universalID];
		found_target = primaryAggressor;

		// firing on an innocent ship is an offence
		[self broadcastHitByLaserFrom: hunter];

		// tell ourselves we've been attacked
		if (energy > 0)
		{
			[self respondToAttackFrom:ent becauseOf:other];
		}

		// tell our group we've been attacked
		OOShipGroup *group = [self group];
		if (group != nil && group != [hunter group] && !(iAmTheLaw || uAreTheLaw))
		{
			if ([self isTrader] || [self isEscort])
			{
				ShipEntity *groupLeader = [group leader];
				[groupLeader setFound_target:hunter];
				[groupLeader setPrimaryAggressor:hunter];
				[groupLeader respondToAttackFrom:ent becauseOf:hunter];
				//unsetting group leader for carriers can break stuff
			}
			if ([self isPirate])
			{
				NSEnumerator		*groupEnum = nil;
				ShipEntity			*otherPirate = nil;
				
				for (groupEnum = [group objectEnumerator]; (otherPirate = [groupEnum nextObject]); )
				{
					if (randf() < 0.5)	// 50% chance they'll help
					{
						[otherPirate setFound_target:hunter];
						[otherPirate setPrimaryAggressor:hunter];
						[otherPirate respondToAttackFrom:ent becauseOf:hunter];
					}
				}
			}
			else if (iAmTheLaw)
			{
				NSEnumerator		*groupEnum = nil;
				ShipEntity			*otherPolice = nil;
				
				for (groupEnum = [group objectEnumerator]; (otherPolice = [groupEnum nextObject]); )
				{
					[otherPolice setFound_target:hunter];
					[otherPolice setPrimaryAggressor:hunter];
					[otherPolice respondToAttackFrom:ent becauseOf:hunter];
				}
			}
		}

		// if I'm a copper and you're not, then mark the other as an offender!
		if (iAmTheLaw && !uAreTheLaw)
		{
			[hunter markAsOffender:64];
		}

		if ([hunter group] == group || (iAmTheLaw && uAreTheLaw))
		{
			// avoid shooting each other
			if ([hunter behaviour] == BEHAVIOUR_ATTACK_FLY_TO_TARGET)	// avoid me please!
			{
				[hunter setBehaviour:BEHAVIOUR_ATTACK_FLY_FROM_TARGET];
				[hunter setDesiredSpeed:[hunter maxFlightSpeed]];
			}
		}

		if ((other)&&(other->isShip))
			being_mined = [(ShipEntity *)other isMining];
	}
	// die if I'm out of energy
	if (energy <= 0.0)
	{
		if (hunter != nil)  [hunter noteTargetDestroyed:self];
		[self getDestroyedBy:other context:suppressExplosion ? @"removed" : (energyMine ? @"cascade weapon" : @"energy damage")];
	}
	else
	{
		// warn if I'm low on energy
		if (energy < maxEnergy * 0.25)
		{
			[self doScriptEvent:@"shipEnergyIsLow" andReactToAIMessage:@"ENERGY_LOW"];
		}
		if (energy < maxEnergy *0.125 && [self hasEscapePod] && (ranrot_rand() & 3) == 0)  // 25% chance he gets to an escape pod
		{
			[self abandonShip];
		}
	}
}


- (void) abandonShip
{
	if ([self isPlayer] && [(PlayerEntity *)self isDocked])
	{
		OOLog(@"ShipEntity.abandonShip.failed", @"Player cannot abandon ship while docked.");
		return;
	}
	
	if (![self hasEscapePod])
	{
		OOLog(@"ShipEntity.abandonShip.failed", @"Ship abandonment was requested for %@, but this ship does not carry escape pod(s).", self);
		return;
	}
		
	if ([self launchEscapeCapsule] != NO_TARGET)	// -launchEscapeCapsule takes care of everyhing for the player
	{
		if (![self isPlayer])
		{
			[self removeEquipmentItem:@"EQ_ESCAPE_POD"];
			[shipAI setStateMachine:@"nullAI.plist"];
			[shipAI setState:@"GLOBAL"];
			behaviour = BEHAVIOUR_IDLE;
			frustration = 0.0;
			[self setScanClass: CLASS_CARGO];			// we're unmanned now!
			thrust = thrust * 0.5;
			desired_speed = 0.0;
			//maxFlightSpeed = 0.0;
			[self setHulk:YES];

			if ([self hasEscorts])
			{
				OOShipGroup			*escortGroup = [self escortGroup];
				NSEnumerator		*escortEnum = nil;
				ShipEntity			*escort = nil;
				// Note: works on escortArray rather than escortEnumerator because escorts may be mutated.
				for (escortEnum = [[self escortArray] objectEnumerator]; (escort = [escortEnum nextObject]); )
				{
					// act individually now!
					if ([escort group] == escortGroup)  [escort setGroup:nil];
					if ([escort owner] == self)  [escort setOwner:nil];
				}
				
				// We now have no escorts.
				[_escortGroup release];
				_escortGroup = nil;
			}
		}
	}
	else
	{
		OOLog(@"ShipEntity.abandonShip.notPossible", @"Ship %@ cannot be abandoned at this time.", self);
	}
}


- (void) takeScrapeDamage:(double) amount from:(Entity *) ent
{
	if ([self status] == STATUS_DEAD)  return;

	if ([self status] == STATUS_LAUNCHING)			// no collisions during launches please
		return;
	if ([ent status] == STATUS_LAUNCHING)			// no collisions during launches please
		return;
	
	energy -= amount;
	// oops we hit too hard!!!
	if (energy <= 0.0)
	{
		being_mined = YES;  // same as using a mining laser
		if ([ent isShip])
		{
			[(ShipEntity *)ent noteTargetDestroyed:self];
		}
		[self getDestroyedBy:ent context:@"scrape damage"];
	}
	else
	{
		// warn if I'm low on energy
		if (energy < maxEnergy * 0.25)
		{
			[self doScriptEvent:@"shipEnergyIsLow" andReactToAIMessage:@"ENERGY_LOW"];
		}
	}
}


- (void) takeHeatDamage:(double) amount
{
	if ([self status] == STATUS_DEAD)					// it's too late for this one!
		return;

	if (amount < 0.0)
		return;

	energy -= amount;

	throw_sparks = YES;

	// oops we're burning up!
	if (energy <= 0.0)
		[self getDestroyedBy:nil context:@"heat damage"];
	else
	{
		// warn if I'm low on energy
		if (energy < maxEnergy * 0.25)
		{
			[self doScriptEvent:@"shipEnergyIsLow" andReactToAIMessage:@"ENERGY_LOW"];
		}
	}
}


- (void) enterDock:(StationEntity *)station
{
	// throw these away now we're docked...
	if (dockingInstructions != nil)
	{
		[dockingInstructions autorelease];
		dockingInstructions = nil;
	}
	
	[self doScriptEvent:@"shipWillDockWithStation" withArgument:station];
	[self doScriptEvent:@"shipDockedWithStation" withArgument:station];
	[shipAI message:@"DOCKED"];
	[station noteDockedShip:self];
	[UNIVERSE removeEntity:self];
}


- (void) leaveDock:(StationEntity *)station
{
	if (station == nil)  return;
	
	Vector stat_f = vector_forward_from_quaternion([station orientation]);
	[self setPosition:vector_add([station position], vector_multiply_scalar(stat_f, 500.0f))];
	
	[self setOrientation:[station orientation]];
	flightRoll = [station flightRoll];
	flightPitch = 0.0;
	flightSpeed = maxFlightSpeed * 0.5;
	
	[self setStatus:STATUS_LAUNCHING];
	
	[self doScriptEvent:@"shipWillLaunchFromStation" withArgument:station];
	[shipAI message:@"LAUNCHED"];
	[UNIVERSE addEntity:self];
}


- (void) enterWormhole:(WormholeEntity *) w_hole
{
	[self enterWormhole:w_hole replacing:YES];
}


- (void) enterWormhole:(WormholeEntity *) w_hole replacing:(BOOL)replacing
{
	if (replacing && ![[UNIVERSE sun] willGoNova] && [UNIVERSE sun] != nil)
	{
		/*	Add a new ship to maintain quantities of standard ships, unless
			there's a nova in the works, the AI asked us not to, or we're in
			interstellar space.
		*/
		[UNIVERSE witchspaceShipWithPrimaryRole:[self primaryRole]];
	}

	[w_hole suckInShip: self];	// removes ship from universe
}


- (void) enterWitchspace
{
	// witchspace entry effects here
	ParticleEntity *ring1 = [[ParticleEntity alloc] initHyperringFromShip:self]; // retained
	[UNIVERSE addEntity:ring1];
	[ring1 release];
	ParticleEntity *ring2 = [[ParticleEntity alloc] initHyperringFromShip:self]; // retained
	[ring2 setSize:NSMakeSize([ring2 size].width * -2.5 ,[ring2 size].height * -2.0 )]; // shrinking!
	[UNIVERSE addEntity:ring2];
	[ring2 release];

	[shipAI message:@"ENTERED_WITCHSPACE"];

	if (![[UNIVERSE sun] willGoNova])				// if the sun's not going nova
		[UNIVERSE witchspaceShipWithPrimaryRole:[self primaryRole]];	// then add a new ship like this one leaving!
	
	[UNIVERSE removeEntity:self];
}

int w_space_seed = 1234567;
- (void) leaveWitchspace
{
	Vector		pos = [UNIVERSE getWitchspaceExitPosition];
	Quaternion  q_rtn = [UNIVERSE getWitchspaceExitRotation];
	
	// try to ensure healthy random numbers
	//
	ranrot_srand(w_space_seed);
	w_space_seed = ranrot_rand();
	
	position = pos;
	double		d1 = SCANNER_MAX_RANGE * (randf() - randf());
	if (abs(d1) < 500.0)	// no closer than 500m
		d1 += ((d1 > 0.0)? 500.0: -500.0);
	Quaternion	q1 = q_rtn;
	quaternion_set_random(&q1);
	Vector		v1 = vector_forward_from_quaternion(q1);
	position.x += v1.x * d1; // randomise exit position
	position.y += v1.y * d1;
	position.z += v1.z * d1;
	orientation = q_rtn;
	flightRoll = 0.0;
	flightPitch = 0.0;
	flightSpeed = maxFlightSpeed * 0.25;
	[self setStatus:STATUS_LAUNCHING];
	[shipAI message:@"EXITED_WITCHSPACE"];
	[UNIVERSE addEntity:self];

	// witchspace exit effects here
	ParticleEntity *ring1 = [[ParticleEntity alloc] initHyperringFromShip:self]; // retained
	[UNIVERSE addEntity:ring1];
	[ring1 release];
	ParticleEntity *ring2 = [[ParticleEntity alloc] initHyperringFromShip:self]; // retained
	[ring2 setSize:NSMakeSize([ring2 size].width * -2.5 ,[ring2 size].height * -2.0 )]; // shrinking!
	[UNIVERSE addEntity:ring2];
	[ring2 release];
}


- (void) markAsOffender:(int)offence_value
{
	if (scanClass != CLASS_POLICE)  bounty |= offence_value;
}


// Exposed to AI
- (void) switchLightsOn
{
	NSEnumerator	*subEnum = nil;
	OOFlasherEntity	*se = nil;
	ShipEntity		*sub = nil;
	
	for (subEnum = [self flasherEnumerator]; (se = [subEnum nextObject]); )
	{
		[se setActive:YES];
	}
	for (subEnum = [self shipSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		[sub switchLightsOn];
	}
}

// Exposed to AI
- (void) switchLightsOff
{
	NSEnumerator	*subEnum = nil;
	OOFlasherEntity	*se = nil;
	ShipEntity		*sub = nil;
	
	for (subEnum = [self flasherEnumerator]; (se = [subEnum nextObject]); )
	{
		[se setActive:NO];
	}
	for (subEnum = [self shipSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		[sub switchLightsOff];
	}
}


- (void) setDestination:(Vector) dest
{
	destination = dest;
	frustration = 0.0;	// new destination => no frustration!
}


- (void) setEscortDestination:(Vector) dest
{
	destination = dest; // don't reset frustration for escorts.
}


- (BOOL) canAcceptEscort:(ShipEntity *)potentialEscort
{
	//this condition has to be checked first! 
	if (![self isEscort] && ([self hasRole:@"police"] || [self hasRole:@"interceptor"]))
	{
		return [potentialEscort hasRole:@"wingman"];
	}
	if ([self bounty] == 0 && [potentialEscort bounty] != 0) // clean mothers can only accept clean escorts
	{
		return NO;
	}
	if (![self isEscort])
	{
		return [potentialEscort hasRole:@"escort"];
	}
	return NO;
}
	

- (BOOL) acceptAsEscort:(ShipEntity *) other_ship
{
	// can't pair with self
	if (self == other_ship)  return NO;

	//increased stack depth at which it can accept escorts to avoid rejections at this stage.
	//doesn't seem to have any adverse effect for now. - Kaks.
	if ([shipAI stackDepth] > 3)
	{
		OOLog(@"ship.escort.reject", @"%@ rejecting escort %@ because AI stack depth is %u.",self, other_ship, [shipAI stackDepth]);
		return NO;
	}
	
	if ([self canAcceptEscort:other_ship])
	{
		OOShipGroup *escortGroup = [self escortGroup];
		
		if ([escortGroup containsShip:other_ship])  return YES;
		
		// check total number acceptable
		unsigned maxEscorts = _maxEscortCount;
		unsigned escortCount = [escortGroup count] - 1;
		
		//however the system's patrols don't have escorts inside their dictionary 
		if (maxEscorts == 0 && ([self hasRole:@"police"] || [self hasRole:@"interceptor"] || [self hasRole:@"hunter"]))
		{
			maxEscorts = MAX_ESCORTS;
		}
		else if (maxEscorts > MAX_ESCORTS)
		{
			maxEscorts = MAX_ESCORTS;
		}
		
		if (escortCount < maxEscorts)
		{
			[escortGroup addShip:other_ship];
			[other_ship setGroup:escortGroup];
			if ([self group] == nil)
			{
				[self setGroup:escortGroup];
			}
			else if ([self group] != escortGroup) [[self group] addShip:other_ship];
			
			if(([other_ship maxFlightSpeed] < cruiseSpeed) && ([other_ship maxFlightSpeed] > cruiseSpeed * 0.3)) 
					cruiseSpeed = [other_ship maxFlightSpeed] * 0.99;

			OOLog(@"ship.escort.accept", @"Accepting existing escort %@.", other_ship);
			
			[self doScriptEvent:@"shipAcceptedEscort" withArgument:other_ship];
			[other_ship doScriptEvent:@"escortAccepted" withArgument:self];
			return YES;
		}
		else if (maxEscorts > 0)
		{
			OOLog(@"ship.escort.reject", @" %@ already got max escorts(%d). Escort rejected: %@.",self, escortCount, other_ship);
		}
	}
	return NO;
}


- (Vector) coordinatesForEscortPosition:(int) f_pos
{
	int f_hi = 1 + (f_pos >> 2);
	int f_lo = f_pos & 3;

	int fp = f_lo * 3;
	int escort_positions[12] = {	-2,0,-1,   2,0,-1,  -3,0,-3,	3,0,-3  }; // V-shape escort pattern
	// int escort_positions[12] = {	-2,0,+2,   2,0,+2,  -3,0,-3,	3,0,-3  }; // X-shape escort pattern
	Vector pos = position;
	double spacing = collision_radius * ESCORT_SPACING_FACTOR;
	double xx = f_hi * spacing * escort_positions[fp++];
	double yy = f_hi * spacing * escort_positions[fp++];
	double zz = f_hi * spacing * escort_positions[fp];
	pos.x += v_right.x * xx;	pos.y += v_right.y * xx;	pos.z += v_right.z * xx;
	pos.x += v_up.x * yy;		pos.y += v_up.y * yy;		pos.z += v_up.z * yy;
	pos.x += v_forward.x * zz;	pos.y += v_forward.y * zz;	pos.z += v_forward.z * zz;

	return pos;
}


// Exposed to AI
- (void) deployEscorts
{
	NSEnumerator	*escortEnum = nil;
	ShipEntity		*escort = nil;
	ShipEntity		*target = nil;
	NSMutableSet	*idleEscorts = nil;
	unsigned		deployCount;
	
	if ([self primaryTarget] == nil || _escortGroup == nil)  return;
	
	OOShipGroup *escortGroup = [self escortGroup];
	unsigned escortCount = [escortGroup count] - 1;  // escorts minus leader.
	if (escortCount == 0)  return;
	
	if ([self group] == nil)  [self setGroup:escortGroup];
	
	if (primaryTarget == last_escort_target)
	{
		// already deployed escorts onto this target!
		return;
	}
	
	last_escort_target = primaryTarget;
	
	// Find idle escorts
	idleEscorts = [NSMutableSet set];
	for (escortEnum = [self escortEnumerator]; (escort = [escortEnum nextObject]); )
	{
		if (![[[escort getAI] name] isEqualToString:@"interceptAI.plist"])
		{
			[idleEscorts addObject:escort];
		}
	}
	
	escortCount = [idleEscorts count];
	if (escortCount == 0)  return;
	
	deployCount = ranrot_rand() % escortCount + 1;
	
	// Deply deployCount idle escorts.
	target = [self primaryTarget];
	for (escortEnum = [idleEscorts objectEnumerator]; (escort = [escortEnum nextObject]); )
	{
		[escort addTarget:target];
		[escort setStateMachine:@"interceptAI.plist"];
		[escort doScriptEvent:@"escortAttack" withArgument:target];
		
		if (--deployCount == 0)  break;
	}
}


// Exposed to AI
- (void) dockEscorts
{
	if (![self hasEscorts])  return;
	
	OOShipGroup			*escortGroup = [self escortGroup];
	NSEnumerator		*escortEnum = nil;
	ShipEntity			*escort = nil;
	ShipEntity			*target = [self primaryTarget];
	unsigned			i = 0;
	// Note: works on escortArray rather than escortEnumerator because escorts may be mutated.
	for (escortEnum = [[self escortArray] objectEnumerator]; (escort = [escortEnum nextObject]); )
	{
		float		delay = i++ * 3.0 + 1.5;		// send them off at three second intervals
		AI			*ai = [escort getAI];
		
		// act individually now!
		if ([escort group] == escortGroup)  [escort setGroup:nil];
		if ([escort owner] == self)  [escort setOwner:nil];
		if(target && [target isStation]) [escort addTarget:target];
		
		[ai setStateMachine:@"dockingAI.plist" afterDelay:delay];
		[ai setState:@"ABORT" afterDelay:delay + 0.25];
		[escort doScriptEvent:@"escortDock" withArgument:[NSNumber numberWithFloat:delay]];
	}
	
	// We now have no escorts.
	[_escortGroup release];
	_escortGroup = nil;
}


// Exosed to AI
- (void) setTargetToNearestStation
{
	// check if the groupID (parent ship) points to a station...
	Entity* mother = [[self group] leader];
	if ([mother isStation])
	{
		primaryTarget = [mother universalID];
		targetStation = primaryTarget;
		return;	// head for mother!
	}

	/*- selects the nearest station it can find -*/
	if (!UNIVERSE)
		return;
	int			ent_count =		UNIVERSE->n_entities;
	Entity**	uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	Entity*		my_entities[ent_count];
	int i;
	int station_count = 0;
	for (i = 0; i < ent_count; i++)
		if (uni_entities[i]->isStation)
			my_entities[station_count++] = [uni_entities[i] retain];		//	retained
	//
	StationEntity* station =  nil;
	double nearest2 = SCANNER_MAX_RANGE2 * 1000000.0; // 1000x scanner range (25600 km), squared.
	for (i = 0; i < station_count; i++)
	{
		StationEntity* thing = (StationEntity*)my_entities[i];
		double range2 = distance2(position, thing->position);
		if (range2 < nearest2)
		{
			station = (StationEntity *)thing;
			nearest2 = range2;
		}
	}
	for (i = 0; i < station_count; i++)
		[my_entities[i] release];		//	released
	//
	if (station)
	{
		primaryTarget = [station universalID];
		targetStation = primaryTarget;
	}
	else
	{
		[shipAI message:@"NO_STATION_FOUND"];
	}
}


// Exosed to AI
- (void) setTargetToSystemStation
{
	StationEntity* system_station = [UNIVERSE station];
	
	if (!system_station)
	{
		[shipAI message:@"NOTHING_FOUND"];
		[shipAI message:@"NO_STATION_FOUND"];
		primaryTarget = NO_TARGET;
		targetStation = NO_TARGET;
		return;
	}
	
	if (!system_station->isStation)
	{
		[shipAI message:@"NOTHING_FOUND"];
		[shipAI message:@"NO_STATION_FOUND"];
		primaryTarget = NO_TARGET;
		targetStation = NO_TARGET;
		return;
	}
	
	primaryTarget = [system_station universalID];
	targetStation = primaryTarget;
	return;
}


- (void) landOnPlanet:(PlanetEntity *)planet
{
	if (planet)
	{
		[planet welcomeShuttle:self];   // 10km from the surface
	}
	[shipAI message:@"LANDED_ON_PLANET"];
	
#ifndef NDEBUG
	if ([self reportAIMessages])
	{
		OOLog(@"planet.collide.shuttleLanded", @"DEBUG: %@ landed on planet %@", self, planet);
	}
#endif
	
	[UNIVERSE removeEntity:self];
}


// Exposed to AI
- (void) abortDocking
{
	[[UNIVERSE findEntitiesMatchingPredicate:IsStationPredicate
								   parameter:nil
									 inRange:-1
									ofEntity:nil]
			makeObjectsPerformSelector:@selector(abortDockingForShip:) withObject:self];
}


- (void) broadcastThargoidDestroyed
{
	[[UNIVERSE findShipsMatchingPredicate:HasRolePredicate
							   parameter:@"tharglet"
								 inRange:SCANNER_MAX_RANGE2
								ofEntity:self]
			makeObjectsPerformSelector:@selector(sendAIMessage:) withObject:@"THARGOID_DESTROYED"];
}


static BOOL AuthorityPredicate(Entity *entity, void *parameter)
{
	ShipEntity			*victim = parameter;
	
	// Select main station, if victim is in aegis
	if (entity == [UNIVERSE station] && [victim withinStationAegis])
	{
		return YES;
	}
	
	// Select police units in scanner range
	if ([entity scanClass] == CLASS_POLICE &&
		distance2([victim position], [entity position]) < SCANNER_MAX_RANGE2)
	{
		return YES;
	}
	
	// Reject others
	return NO;
}


- (void) broadcastHitByLaserFrom:(ShipEntity *) aggressor_ship
{
	/*-- If you're clean, locates all police and stations in range and tells them OFFENCE_COMMITTED --*/
	if (!UNIVERSE)  return;
	if ([self bounty])  return;
	if (!aggressor_ship)  return;
	
	if (	(scanClass == CLASS_NEUTRAL)||
			(scanClass == CLASS_STATION)||
			(scanClass == CLASS_BUOY)||
			(scanClass == CLASS_POLICE)||
			(scanClass == CLASS_MILITARY)||
			(scanClass == CLASS_PLAYER))	// only for active ships...
	{
		NSArray			*authorities = nil;
		NSEnumerator	*authEnum = nil;
		ShipEntity		*auth = nil;
		
		authorities = [UNIVERSE findShipsMatchingPredicate:AuthorityPredicate
												 parameter:self
												   inRange:-1
												  ofEntity:nil];
		authEnum = [authorities objectEnumerator];
		while ((auth = [authEnum nextObject]))
		{
			[auth setFound_target:aggressor_ship];
			[auth doScriptEvent:@"offenceCommittedNearby" withArgument:aggressor_ship andArgument:self];
			[auth reactToAIMessage:@"OFFENCE_COMMITTED"];
		}
	}
}


- (void) sendExpandedMessage:(NSString *) message_text toShip:(ShipEntity*) other_ship
{
	if (!other_ship)
		return;
	if (!crew)
		return;	// nobody to send the signal
	if ((lastRadioMessage) && (messageTime > 0.0) && [message_text isEqual:lastRadioMessage])
		return;	// don't send the same message too often
	[lastRadioMessage autorelease];
	lastRadioMessage = [message_text retain];
	Vector delta = other_ship->position;
	delta.x -= position.x;  delta.y -= position.y;  delta.z -= position.z;
	double d2 = delta.x*delta.x + delta.y*delta.y + delta.z*delta.z;
	if (d2 > scannerRange * scannerRange)
		return;					// out of comms range
	if (!other_ship)
		return;
	NSMutableString *localExpandedMessage = [NSMutableString stringWithString:message_text];
	[localExpandedMessage	replaceOccurrencesOfString:@"[self:name]"
							withString:[self displayName]
							options:NSLiteralSearch range:NSMakeRange(0, [localExpandedMessage length])];
	[localExpandedMessage	replaceOccurrencesOfString:@"[target:name]"
							withString:[other_ship identFromShip: self]
							options:NSLiteralSearch range:NSMakeRange(0, [localExpandedMessage length])];
	Random_Seed very_random_seed;
	very_random_seed.a = rand() & 255;
	very_random_seed.b = rand() & 255;
	very_random_seed.c = rand() & 255;
	very_random_seed.d = rand() & 255;
	very_random_seed.e = rand() & 255;
	very_random_seed.f = rand() & 255;
	seed_RNG_only_for_planet_description(very_random_seed);
	NSString* expandedMessage = ExpandDescriptionForCurrentSystem(localExpandedMessage);
	[self setCommsMessageColor];
	[other_ship receiveCommsMessage:[NSString stringWithFormat:@"%@:\n %@", displayName, expandedMessage]];
	if (other_ship->isPlayer)
		messageTime = 6.0;
	[UNIVERSE resetCommsLogColor];
}


- (void) broadcastAIMessage:(NSString *) ai_message
{
	NSString* expandedMessage = ExpandDescriptionForCurrentSystem(ai_message);

	[self checkScanner];
	unsigned i;
	for (i = 0; i < n_scanned_ships ; i++)
	{
		ShipEntity* ship = scanned_ships[i];
		[[ship getAI] message: expandedMessage];
	}
}


- (void) broadcastMessage:(NSString *) message_text withUnpilotedOverride:(BOOL) unpilotedOverride
{
	NSString* expandedMessage = [NSString stringWithFormat:@"%@:\n %@", displayName, ExpandDescriptionForCurrentSystem(message_text)];

	if (!crew && !unpilotedOverride)
		return;	// nobody to send the signal and no override for unpiloted craft is set

	[self setCommsMessageColor];
	[self checkScanner];
	unsigned i;
	for (i = 0; i < n_scanned_ships ; i++)
	{
		ShipEntity* ship = scanned_ships[i];
		[ship receiveCommsMessage: expandedMessage];
		if ([ship isPlayer])
			messageTime = 6.0;
	}
	[UNIVERSE resetCommsLogColor];
}


- (void) setCommsMessageColor
{
	float hue = 0.0625 * (universalID & 15);
	[[UNIVERSE comm_log_gui] setTextColor:[OOColor colorWithCalibratedHue:hue saturation:0.375 brightness:1.0 alpha:1.0]];
	if (scanClass == CLASS_THARGOID)
		[[UNIVERSE comm_log_gui] setTextColor:[OOColor greenColor]];
	if (scanClass == CLASS_POLICE)
		[[UNIVERSE comm_log_gui] setTextColor:[OOColor cyanColor]];
}


- (void) receiveCommsMessage:(NSString *) message_text
{
	// ignore messages for now
}


- (void) commsMessage:(NSString *)valueString withUnpilotedOverride:(BOOL)unpilotedOverride
{
	Random_Seed very_random_seed;
	very_random_seed.a = rand() & 255;
	very_random_seed.b = rand() & 255;
	very_random_seed.c = rand() & 255;
	very_random_seed.d = rand() & 255;
	very_random_seed.e = rand() & 255;
	very_random_seed.f = rand() & 255;
	seed_RNG_only_for_planet_description(very_random_seed);
	
	[self broadcastMessage:valueString withUnpilotedOverride:unpilotedOverride];
}


- (BOOL) markForFines
{
	if (being_fined)
		return NO;	// can't mark twice
	being_fined = ([self legalStatus] > 0);
	return being_fined;
}


- (BOOL) isMining
{
	return ((behaviour == BEHAVIOUR_ATTACK_MINING_TARGET)&&(forward_weapon_type == WEAPON_MINING_LASER));
}


- (void) interpretAIMessage:(NSString *)ms
{
	if ([ms hasPrefix:AIMS_AGGRESSOR_SWITCHED_TARGET])
	{
		// if I'm under attack send a thank-you message to the rescuer
		//
		NSArray* tokens = ScanTokensFromString(ms);
		int switcher_id = [(NSString*)[tokens objectAtIndex:1] intValue];
		Entity* switcher = [UNIVERSE entityForUniversalID:switcher_id];
		int rescuer_id = [(NSString*)[tokens objectAtIndex:2] intValue];
		Entity* rescuer = [UNIVERSE entityForUniversalID:rescuer_id];
		if ((switcher_id == primaryAggressor)&&(switcher_id == primaryTarget)&&(switcher)&&(rescuer)&&(rescuer->isShip)&&(thanked_ship_id != rescuer_id)&&(scanClass != CLASS_THARGOID))
		{
			if (scanClass == CLASS_POLICE)
				[self sendExpandedMessage:@"[police-thanks-for-assist]" toShip:(ShipEntity*)rescuer];
			else
				[self sendExpandedMessage:@"[thanks-for-assist]" toShip:(ShipEntity*)rescuer];
			thanked_ship_id = rescuer_id;
			[(ShipEntity*)switcher setBounty:[(ShipEntity*)switcher bounty] + 5 + (ranrot_rand() & 15)];	// reward
		}
	}
}


- (BoundingBox) findBoundingBoxRelativeTo:(Entity *)other InVectors:(Vector) _i :(Vector) _j :(Vector) _k
{
	Vector  opv = other ? other->position : position;
	return [self findBoundingBoxRelativeToPosition:opv InVectors:_i :_j :_k];
}


// Exposed to AI and legacy scripts.
- (void) spawn:(NSString *)roles_number
{
	NSArray		*tokens = ScanTokensFromString(roles_number);
	NSString	*roleString = nil;
	NSString	*numberString = nil;
	OOUInteger	number;
	
	if ([tokens count] != 2)
	{
		OOLog(kOOLogSyntaxAddShips, @"***** Could not spawn: '%@' (must be two tokens, role and number)",roles_number);
		return;
	}
	
	roleString = [tokens oo_stringAtIndex:0];
	numberString = [tokens oo_stringAtIndex:1];
	
	number = [numberString intValue];
	
	[self spawnShipsWithRole:roleString count:number];
}


- (int) checkShipsInVicinityForWitchJumpExit
{
	// checks if there are any large masses close by
	// since we want to place the space station at least 10km away
	// the formula we'll use is K x m / d2 < 1.0
	// (m = mass, d2 = distance squared)
	// coriolis station is mass 455,223,200
	// 10km is 10,000m,
	// 10km squared is 100,000,000
	// therefore K is 0.22 (approx)

	int result = NO_TARGET;

	GLfloat k = 0.1;

	int			ent_count =		UNIVERSE->n_entities;
	Entity**	uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	ShipEntity*	my_entities[ent_count];
	int i;

	int ship_count = 0;
	for (i = 0; i < ent_count; i++)
		if ((uni_entities[i]->isShip)&&(uni_entities[i] != self))
			my_entities[ship_count++] = (ShipEntity*)[uni_entities[i] retain];		//	retained
	//
	for (i = 0; (i < ship_count)&&(result == NO_TARGET) ; i++)
	{
		ShipEntity* ship = my_entities[i];
		Vector delta = vector_between(position, ship->position);
		GLfloat d2 = magnitude2(delta);
		if ((k * [ship mass] > d2)&&(d2 < SCANNER_MAX_RANGE2))	// if you go off scanner from a blocker - it ceases to block
			result = [ship universalID];
	}
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release];	//		released

	return result;
}


- (BOOL) trackCloseContacts
{
	return trackCloseContacts;
}


- (void) setTrackCloseContacts:(BOOL) value
{
	if (value == trackCloseContacts)  return;
	
	trackCloseContacts = value;
	[closeContactsInfo release];
	
	if (trackCloseContacts)
	{
		closeContactsInfo = [[NSMutableDictionary alloc] init];
	}
	else
	{
		closeContactsInfo = nil;
	}
}


- (void) claimAsSalvage
{
	// Create a bouy and beacon where the hulk is.
	// Get the main GalCop station to launch a pilot boat to deliver a pilot to the hulk.
	OOLog(@"claimAsSalvage.called", @"claimAsSalvage called on %@ %@", [self name], [self roleSet]);
	
	// Not an abandoned hulk, so don't allow the salvage
	if (![self isHulk])
	{
		OOLog(@"claimAsSalvage.failed.notHulk", @"claimAsSalvage failed because not a hulk");
		return;
	}

	// Set target to main station, and return now if it can't be found
	[self setTargetToSystemStation];
	if (primaryTarget == NO_TARGET)
	{
		OOLog(@"claimAsSalvage.failed.noStation", @"claimAsSalvage failed because did not find a station");
		return;
	}

	// Get the station to launch a pilot boat to bring a pilot out to the hulk (use a viper for now)
	StationEntity *station = (StationEntity *)[UNIVERSE entityForUniversalID:primaryTarget];
	OOLog(@"claimAsSalvage.requestingPilot", @"claimAsSalvage asking station to launch a pilot boat");
	[station launchShipWithRole:@"pilot"];
	[self setReportAIMessages:YES];
	OOLog(@"claimAsSalvage.success", @"claimAsSalvage setting own state machine to capturedShipAI.plist");
	[self setStateMachine:@"capturedShipAI.plist"];
}


- (void) sendCoordinatesToPilot
{
	Entity		*scan;
	ShipEntity	*scanShip, *pilot;
	
	n_scanned_ships = 0;
	scan = z_previous;
	OOLog(@"ship.pilotage", @"searching for pilot boat");
	while (scan &&(scan->isShip == NO))
	{
		scan = scan->z_previous;	// skip non-ships
	}

	pilot = nil;
	while (scan)
	{
		if (scan->isShip)
		{
			scanShip = (ShipEntity *)scan;
			
			if ([self hasRole:@"pilot"] == YES)
			{
				if ([scanShip primaryTargetID] == NO_TARGET)
				{
					OOLog(@"ship.pilotage", @"found pilot boat with no target, will use this one");
					pilot = scanShip;
					[pilot setPrimaryRole:@"pilot"];
					break;
				}
			}
		}
		scan = scan->z_previous;
		while (scan && (scan->isShip == NO))
		{
			scan = scan->z_previous;
		}
	}

	if (pilot != nil)
	{
		OOLog(@"ship.pilotage", @"becoming pilot target and setting AI");
		[pilot setReportAIMessages:YES];
		[pilot addTarget:self];
		[pilot setStateMachine:@"pilotAI.plist"];
		[self reactToAIMessage:@"FOUND_PILOT"];
	}
}


- (void) pilotArrived
{
	[self setHulk:NO];
	[self reactToAIMessage:@"PILOT_ARRIVED"];
}


#ifndef NDEBUG
- (void)dumpSelfState
{
	NSMutableArray		*flags = nil;
	NSString			*flagsString = nil;
	
	[super dumpSelfState];
	
	OOLog(@"dumpState.shipEntity", @"Name: %@", name);
	OOLog(@"dumpState.shipEntity", @"Display Name: %@", displayName);
	OOLog(@"dumpState.shipEntity", @"Roles: %@", [self roleSet]);
	OOLog(@"dumpState.shipEntity", @"Primary role: %@", primaryRole);
	OOLog(@"dumpState.shipEntity", @"Script: %@", script);
	OOLog(@"dumpState.shipEntity", @"Subentity count: %u", [self subEntityCount]);
	OOLog(@"dumpState.shipEntity", @"Behaviour: %@", BehaviourToString(behaviour));
	if (primaryTarget != NO_TARGET)  OOLog(@"dumpState.shipEntity", @"Target: %@", [self primaryTarget]);
	OOLog(@"dumpState.shipEntity", @"Destination: %@", VectorDescription(destination));
	OOLog(@"dumpState.shipEntity", @"Other destination: %@", VectorDescription(coordinates));
	OOLog(@"dumpState.shipEntity", @"Waypoint count: %u", number_of_navpoints);
	OOLog(@"dumpState.shipEntity", @"Desired speed: %g", desired_speed);
	OOLog(@"dumpState.shipEntity", @"Thrust: %g", thrust);
	if ([self escortCount] != 0)  OOLog(@"dumpState.shipEntity", @"Escort count: %u", [self escortCount]);
	OOLog(@"dumpState.shipEntity", @"Fuel: %i", fuel);
	OOLog(@"dumpState.shipEntity", @"Fuel accumulator: %g", fuel_accumulator);
	OOLog(@"dumpState.shipEntity", @"Missile count: %u", missiles);
	
#ifdef OO_BRAIN_AI
	if (brain != nil && OOLogWillDisplayMessagesInClass(@"dumpState.shipEntity.brain"))
	{
		OOLog(@"dumpState.shipEntity.brain", @"Brain:");
		OOLogPushIndent();
		OOLogIndent();
		NS_DURING
			[brain dumpState];
		NS_HANDLER
		NS_ENDHANDLER
		OOLogPopIndent();
	}
#endif
	
	if (shipAI != nil && OOLogWillDisplayMessagesInClass(@"dumpState.shipEntity.ai"))
	{
		OOLog(@"dumpState.shipEntity.ai", @"AI:");
		OOLogPushIndent();
		OOLogIndent();
		NS_DURING
			[shipAI dumpState];
		NS_HANDLER
		NS_ENDHANDLER
		OOLogPopIndent();
	}
	OOLog(@"dumpState.shipEntity", @"Frustration: %g", frustration);
	OOLog(@"dumpState.shipEntity", @"Success factor: %g", success_factor);
	OOLog(@"dumpState.shipEntity", @"Shots fired: %u", shot_counter);
	OOLog(@"dumpState.shipEntity", @"Time since shot: %g", [self shotTime]);
	OOLog(@"dumpState.shipEntity", @"Spawn time: %g (%g seconds ago)", [self spawnTime], [self timeElapsedSinceSpawn]);
	if (beaconChar != '\0')
	{
		OOLog(@"dumpState.shipEntity", @"Beacon character: '%c'", beaconChar);
	}
	OOLog(@"dumpState.shipEntity", @"Hull temperature: %g", ship_temperature);
	OOLog(@"dumpState.shipEntity", @"Heat insulation: %g", [self heatInsulation]);
	
	flags = [NSMutableArray array];
	#define ADD_FLAG_IF_SET(x)		if (x) { [flags addObject:@#x]; }
	ADD_FLAG_IF_SET(military_jammer_active);
	ADD_FLAG_IF_SET(docking_match_rotation);
	ADD_FLAG_IF_SET(pitching_over);
	ADD_FLAG_IF_SET(reportAIMessages);
	ADD_FLAG_IF_SET(being_mined);
	ADD_FLAG_IF_SET(being_fined);
	ADD_FLAG_IF_SET(isHulk);
	ADD_FLAG_IF_SET(trackCloseContacts);
	ADD_FLAG_IF_SET(isNearPlanetSurface);
	ADD_FLAG_IF_SET(isFrangible);
	ADD_FLAG_IF_SET(cloaking_device_active);
	ADD_FLAG_IF_SET(canFragment);
	ADD_FLAG_IF_SET(proximity_alert);
	flagsString = [flags count] ? [flags componentsJoinedByString:@", "] : (NSString *)@"none";
	OOLog(@"dumpState.shipEntity", @"Flags: %@", flagsString);
}
#endif


- (OOScript *)script
{
	return script;
}


- (NSDictionary *)scriptInfo
{
	return (scriptInfo != nil) ? scriptInfo : (NSDictionary *)[NSDictionary dictionary];
}


- (Entity *)entityForShaderProperties
{
	return [self rootShipEntity];
}


// *** Script event dispatch.
// For ease of overriding, these all go through doScriptEvent:withArguments:.
- (void) doScriptEvent:(NSString *)message
{
	[self doScriptEvent:message withArguments:nil];
}


- (void) doScriptEvent:(NSString *)message withArgument:(id)argument
{
	NSArray				*arguments = nil;
	
	if (argument == nil)
		[self doScriptEvent:message];
	else
	{
		arguments = [NSArray arrayWithObject:argument];
		[self doScriptEvent:message withArguments:arguments];
	}
}


- (void) doScriptEvent:(NSString *)message
		  withArgument:(id)argument1
		   andArgument:(id)argument2
{
	NSArray				*arguments = nil;
	
	if (argument1 == nil)  argument1 = [NSNull null];
	if (argument2 == nil)  argument2 = [NSNull null];
	arguments = [NSArray arrayWithObjects:argument1, argument2, nil];
	
	NS_DURING
		[self doScriptEvent:message withArguments:arguments];
	NS_HANDLER
		OOLog(kOOLogException, @"***** Exception while performing script event %@ for %@: %@ : %@", message, [self shortDescription], [localException name], [localException reason]);
	NS_ENDHANDLER
}


- (void) doScriptEvent:(NSString *)message withArguments:(NSArray *)arguments
{
	[script doEvent:message withArguments:arguments];
}


- (void) reactToAIMessage:(NSString *)message
{
	[shipAI reactToMessage:message];
}


- (void) sendAIMessage:(NSString *)message
{
	[shipAI message:message];	
}


- (void) doScriptEvent:(NSString *)scriptEvent andReactToAIMessage:(NSString *)aiMessage
{
	[self doScriptEvent:scriptEvent];
	[self reactToAIMessage:aiMessage];
}


- (void) doScriptEvent:(NSString *)scriptEvent withArgument:(id)argument andReactToAIMessage:(NSString *)aiMessage
{
	[self doScriptEvent:scriptEvent withArgument:argument];
	[self reactToAIMessage:aiMessage];
}


// Exposed to AI and scripts.
- (void) doNothing
{
	
}

@end


@implementation Entity (SubEntityRelationship)

- (BOOL) isShipWithSubEntityShip:(Entity *)other
{
	return NO;
}

@end


@implementation ShipEntity (SubEntityRelationship)

- (BOOL) isShipWithSubEntityShip:(Entity *)other
{
	assert ([self isShip]);
	
	if (![other isShip])  return NO;
	if (![other isSubEntity])  return NO;
	if ([other owner] != self)  return NO;
	
#ifndef NDEBUG
	// Sanity check; this should always be true.
	if (![self hasSubEntity:(ShipEntity *)other])
	{
		OOLogERR(@"ship.subentity.sanityCheck.failed", @"%@ thinks it's a subentity of %@, but the supposed parent does not agree. %@", [other shortDescription], [self shortDescription], @"This is an internal error, please report it.");
		[other setOwner:nil];
		return NO;
	}
#endif
	
	return YES;
}

@end


NSDictionary *DefaultShipShaderMacros(void)
{
	static NSDictionary		*macros = nil;
	NSDictionary			*materialDefaults = nil;
	
	if (macros == nil)
	{
		materialDefaults = [ResourceManager dictionaryFromFilesNamed:@"material-defaults.plist" inFolder:@"Config" andMerge:YES];
		macros = [[materialDefaults oo_dictionaryForKey:@"ship-prefix-macros" defaultValue:[NSDictionary dictionary]] retain];
	}
	
	return macros;
}


BOOL OOUniformBindingPermitted(NSString *propertyName, id bindingTarget)
{
	static NSSet			*entityWhitelist = nil;
	static NSSet			*shipWhitelist = nil;
	static NSSet			*playerShipWhitelist = nil;
	
	if (entityWhitelist == nil)
	{
		NSDictionary *wlDict = [ResourceManager whitelistDictionary];
		entityWhitelist = [[NSSet alloc] initWithArray:[wlDict oo_arrayForKey:@"shader_entity_binding_methods"]];
		shipWhitelist = [[NSSet alloc] initWithArray:[wlDict oo_arrayForKey:@"shader_ship_binding_methods"]];
		playerShipWhitelist = [[NSSet alloc] initWithArray:[wlDict oo_arrayForKey:@"shader_player_ship_binding_methods"]];
	}
	
	if ([bindingTarget isKindOfClass:[Entity class]])
	{
		if ([entityWhitelist containsObject:propertyName])  return YES;
	}
	if ([bindingTarget isKindOfClass:[ShipEntity class]])
	{
		if ([shipWhitelist containsObject:propertyName])  return YES;
	}
	if ([bindingTarget isKindOfClass:[PlayerEntity class]])
	{
		if ([playerShipWhitelist containsObject:propertyName])  return YES;
	}
	
	return NO;
}
