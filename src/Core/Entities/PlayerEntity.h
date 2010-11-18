/*

PlayerEntity.h

Entity subclass nominally representing the player's ship, but also
implementing much of the interaction, menu system etc. Breaking it up into
ten or so different classes is a perennial to-do item.

Oolite
Copyright (C) 2004-2010 Giles C Williams and contributors

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

#import <Foundation/Foundation.h>
#if WORMHOLE_SCANNER
#import "WormholeEntity.h"
#endif
#import "ShipEntity.h"
#import "OOTypes.h"

@class GuiDisplayGen, OOTrumble, MyOpenGLView, HeadUpDisplay, ShipEntity;
@class OOSound, OOSoundSource, OOSoundReferencePoint;
@class JoystickHandler, OOTexture, OOCamera;

#define SCRIPT_TIMER_INTERVAL			10.0

#define GUI_ROW_INIT(GUI) /*int n_rows = [(GUI) rows]*/
#define GUI_FIRST_ROW(GROUP) ((GUI_DEFAULT_ROWS - GUI_ROW_##GROUP##OPTIONS_END_OF_LIST) / 2)
// reposition menu
#define GUI_ROW(GROUP,ITEM) (GUI_FIRST_ROW(GROUP) - 5 + GUI_ROW_##GROUP##OPTIONS_##ITEM)

enum
{
	GUI_ROW_OPTIONS_QUICKSAVE,
	GUI_ROW_OPTIONS_SAVE,
	GUI_ROW_OPTIONS_LOAD,
	GUI_ROW_OPTIONS_BEGIN_NEW,
	GUI_ROW_OPTIONS_SPACER1,
	GUI_ROW_OPTIONS_GAMEOPTIONS,
	GUI_ROW_OPTIONS_SPACER2,
	GUI_ROW_OPTIONS_STRICT,
#if OOLITE_SDL
	GUI_ROW_OPTIONS_SPACER3,
	GUI_ROW_OPTIONS_QUIT,
#endif
	GUI_ROW_OPTIONS_END_OF_LIST,
	
	STATUS_EQUIPMENT_FIRST_ROW 			= 10,
	STATUS_EQUIPMENT_MAX_ROWS 			= 8,
	
	GUI_ROW_EQUIPMENT_START				= 3,
	GUI_MAX_ROWS_EQUIPMENT				= 12,
	GUI_ROW_EQUIPMENT_DETAIL			= GUI_ROW_EQUIPMENT_START + GUI_MAX_ROWS_EQUIPMENT + 1,
	GUI_ROW_EQUIPMENT_CASH				= 1,
	GUI_ROW_MARKET_KEY					= 1,
	GUI_ROW_MARKET_START				= 2,
	GUI_ROW_MARKET_CASH					= 20
};
#if GUI_FIRST_ROW() < 0
# error Too many items in OPTIONS list!
#endif

enum
{
	GUI_ROW_GAMEOPTIONS_AUTOSAVE,
	GUI_ROW_GAMEOPTIONS_SPACER1,
	GUI_ROW_GAMEOPTIONS_VOLUME,
#if OOLITE_MAC_OS_X
	GUI_ROW_GAMEOPTIONS_GROWL,
#endif
#if OOLITE_SPEECH_SYNTH
	GUI_ROW_GAMEOPTIONS_SPEECH,
	GUI_ROW_GAMEOPTIONS_SPEECH_LANGUAGE,
	GUI_ROW_GAMEOPTIONS_SPEECH_GENDER,
#endif
	GUI_ROW_GAMEOPTIONS_MUSIC,
	GUI_ROW_GAMEOPTIONS_SPACER2,
	GUI_ROW_GAMEOPTIONS_DISPLAY,
	GUI_ROW_GAMEOPTIONS_DISPLAYSTYLE,
	GUI_ROW_GAMEOPTIONS_DETAIL,
	GUI_ROW_GAMEOPTIONS_WIREFRAMEGRAPHICS,
#if ALLOW_PROCEDURAL_PLANETS
	GUI_ROW_GAMEOPTIONS_PROCEDURALLYTEXTUREDPLANETS,
#endif
	GUI_ROW_GAMEOPTIONS_SHADEREFFECTS,
#if OOLITE_SDL
	GUI_ROW_GAMEOPTIONS_SPACER_SDLSTICKMAPPER,
	GUI_ROW_GAMEOPTIONS_STICKMAPPER,
#endif
	GUI_ROW_GAMEOPTIONS_SPACER3,
	GUI_ROW_GAMEOPTIONS_BACK,
	
	GUI_ROW_GAMEOPTIONS_END_OF_LIST
};
#if GUI_FIRST_ROW() < 0
# error Too many items in GAMEOPTIONS list!
#endif


typedef enum
{
	// Exposed to shaders.
	SCOOP_STATUS_NOT_INSTALLED			= 0,
	SCOOP_STATUS_FULL_HOLD,
	SCOOP_STATUS_OKAY,
	SCOOP_STATUS_ACTIVE
} OOFuelScoopStatus;


enum
{
	ALERT_FLAG_DOCKED				= 0x010,
	ALERT_FLAG_MASS_LOCK			= 0x020,
	ALERT_FLAG_YELLOW_LIMIT			= 0x03f,
	ALERT_FLAG_TEMP					= 0x040,
	ALERT_FLAG_ALT					= 0x080,
	ALERT_FLAG_ENERGY				= 0x100,
	ALERT_FLAG_HOSTILES				= 0x200
};
typedef uint16_t OOAlertFlags;


typedef enum
{
	// Exposed to shaders.
	MISSILE_STATUS_SAFE,
	MISSILE_STATUS_ARMED,
	MISSILE_STATUS_TARGET_LOCKED
} OOMissileStatus;


#define WEAPON_COOLING_FACTOR			6.0f
#define ENERGY_RECHARGE_FACTOR			energy_recharge_rate
#define ECM_ENERGY_DRAIN_FACTOR			20.0f
#define ECM_DURATION					2.5f

#define ROLL_DAMPING_FACTOR				1.0f
#define PITCH_DAMPING_FACTOR			1.0f
#define YAW_DAMPING_FACTOR			1.0f

#define PLAYER_MAX_WEAPON_TEMP			256.0f
#define PLAYER_MAX_FUEL					70
#define PLAYER_MAX_MISSILES				16
#define PLAYER_STARTING_MAX_MISSILES	4
#define PLAYER_STARTING_MISSILES		3
#define PLAYER_DIAL_MAX_ALTITUDE		40000.0
#define PLAYER_SUPER_ALTITUDE2			10000000000.0

#define PLAYER_MAX_TRUMBLES				24

#define	PLAYER_TARGET_MEMORY_SIZE		16

	//  ~~~~~~~~~~~~~~~~~~~~~~~~	= 40km

#define SHOT_RELOAD						0.25

#define HYPERSPEED_FACTOR				32.0

#define PLAYER_SHIP_DESC				@"cobra3-player"

#define ESCAPE_SEQUENCE_TIME			10.0

#define MS_WITCHSPACE_SF				@"[witch-to-@-in-f-seconds]"
#define MS_GAL_WITCHSPACE_F				@"[witch-galactic-in-f-seconds]"

#define WEAPON_OFFSET_DOWN				20

#define FORWARD_FACING_STRING			DESC(@"forward-facing-string")
#define AFT_FACING_STRING				DESC(@"aft-facing-string")
#define PORT_FACING_STRING				DESC(@"port-facing-string")
#define STARBOARD_FACING_STRING			DESC(@"starboard-facing-string")

#define KEY_REPEAT_INTERVAL				0.20

#define PLAYER_SHIP_CLOCK_START			(2084004 * 86400.0)

#define CONTRACTS_GOOD_KEY				@"contracts_fulfilled"
#define CONTRACTS_BAD_KEY				@"contracts_expired"
#define CONTRACTS_UNKNOWN_KEY			@"contracts_unknown"
#define PASSAGE_GOOD_KEY				@"passage_fulfilled"
#define PASSAGE_BAD_KEY					@"passage_expired"
#define PASSAGE_UNKNOWN_KEY				@"passage_unknown"


#define SCANNER_ZOOM_RATE_UP			2.0
#define SCANNER_ZOOM_RATE_DOWN			-8.0

#define PLAYER_INTERNAL_DAMAGE_FACTOR	31

#define PLAYER_DOCKING_AI_NAME			@"oolite-player-AI.plist"

@interface PlayerEntity: ShipEntity
{
@public
	
	Random_Seed				system_seed;
	Random_Seed				target_system_seed;
	
@protected
	
	Random_Seed				found_system_seed;
	int						ship_trade_in_factor;
	
	NSDictionary			*worldScripts;
	NSMutableDictionary		*mission_variables;
	NSMutableDictionary		*localVariables;
	int						missionTextRow;
	NSString				*missionChoice;
	BOOL					_missionWithCallback;
	
	NSString				*specialCargo;
	
	NSMutableArray			*commLog;

	NSMutableArray			*eqScripts;
	
	NSString				*missionBackgroundTexture;
	NSString				*missionForegroundTexture;
	NSString				*tempTexture;
	
	BOOL					found_equipment;
	
	NSMutableDictionary		*reputation;
	
	unsigned				max_passengers;
	NSMutableArray			*passengers;
	NSMutableDictionary		*passenger_record;
	
	NSMutableArray			*contracts;
	NSMutableDictionary		*contract_record;
	
	NSMutableDictionary		*shipyard_record;
	
	NSMutableArray			*missionDestinations;

	double					script_time;
	double					script_time_check;
	double					script_time_interval;
	NSString				*lastTextKey;
	
	double					ship_clock;
	double					ship_clock_adjust;
	
	double					fps_check_time;
	int						fps_counter;
	double					last_fps_check_time;
	
	NSString				*planetSearchString;
	
	OOMatrix				playerRotMatrix;
	
	// For OO-GUI based save screen
	NSString				*commanderNameString;
	NSMutableArray			*cdrDetailArray;
	int						currentPage;
	BOOL					pollControls;
// ...end save screen   

	StationEntity			*dockedStation;
#if DOCKING_CLEARANCE_ENABLED
/* Used by the DOCKING_CLEARANCE code to implement docking at non-main
 * stations. Could possibly overload use of 'dockedStation' instead
 * but that needs futher investigation to ensure it doesn't break anything. */
	StationEntity			*targetDockStation; 
#endif
	
	HeadUpDisplay			*hud;
	
	GLfloat					roll_delta, pitch_delta, yaw_delta;
	GLfloat					launchRoll;
	
	GLfloat					forward_shield, aft_shield;
	GLfloat					weapon_temp;
	GLfloat					forward_weapon_temp, aft_weapon_temp, port_weapon_temp, starboard_weapon_temp;
	OOTimeDelta				forward_shot_time, aft_shot_time, port_shot_time, starboard_shot_time;
	GLfloat					weapon_energy_use, weapon_shot_temperature, weapon_reload_time;
	
	int						chosen_weapon_facing;   // for purchasing weapons
	
	double					ecm_start_time;
	
	OOSoundReferencePoint	*refPoint;
	
	OOGUIScreenID			gui_screen;
	OOAlertFlags			alertFlags;
	OOAlertCondition		alertCondition;
	OOAlertCondition		lastScriptAlertCondition;
	OOMissileStatus			missile_status;
	unsigned				activeMissile;
	unsigned				primedEquipment;
	
	OOCargoQuantity			current_cargo;
	
	NSPoint					cursor_coordinates;
	float					witchspaceCountdown;
	
	// player commander data
	NSString				*player_name;
	NSPoint					galaxy_coordinates;
	
	Random_Seed				galaxy_seed;
	
	OOCreditsQuantity		credits;	
	OOGalaxyID				galaxy_number;
	/*
	OOWeaponType			forward_weapon;		// Is there a reason for having both this and forward_weapon_type? -- ahruman
	OOWeaponType			aft_weapon;			// ditto 	- No good reason, and it could lead to some inconsistent state. Fixed. -- kaks
	*/
	OOWeaponType			port_weapon_type;
	OOWeaponType			starboard_weapon_type;
	
	NSMutableArray			*shipCommodityData;
	
	ShipEntity				*missile_entity[PLAYER_MAX_MISSILES];	// holds the actual missile entities or equivalents
	OOUniversalID			_dockTarget;	// used by the escape pod code
	
	int						legalStatus;
	int						market_rnd;
	unsigned				ship_kills;
	
	OOCompassMode			compassMode;
	Entity 					*compassTarget;
	
	GLfloat					fuel_leak_rate;
	
	// keys!
	OOKeyCode				key_roll_left;
	OOKeyCode				key_roll_right;
	OOKeyCode				key_pitch_forward;
	OOKeyCode				key_pitch_back;
	OOKeyCode				key_yaw_left;
	OOKeyCode				key_yaw_right;
	
	OOKeyCode				key_increase_speed;
	OOKeyCode				key_decrease_speed;
	OOKeyCode				key_inject_fuel;
	
	OOKeyCode				key_fire_lasers;
	OOKeyCode				key_launch_missile;
	OOKeyCode				key_next_missile;
	OOKeyCode				key_ecm;
	
	OOKeyCode				key_prime_equipment;
	OOKeyCode				key_activate_equipment;
	
	OOKeyCode				key_target_missile;
	OOKeyCode				key_untarget_missile;
#if TARGET_INCOMING_MISSILES
	OOKeyCode				key_target_incoming_missile;
#endif
	OOKeyCode				key_ident_system;
	
	OOKeyCode				key_scanner_zoom;
	OOKeyCode				key_scanner_unzoom;
	
	OOKeyCode				key_launch_escapepod;
	OOKeyCode				key_energy_bomb;
	
	OOKeyCode				key_galactic_hyperspace;
	OOKeyCode				key_hyperspace;
	OOKeyCode				key_jumpdrive;
	
	OOKeyCode				key_dump_cargo;
	OOKeyCode				key_rotate_cargo;
	
	OOKeyCode				key_autopilot;
	OOKeyCode				key_autopilot_target;
	OOKeyCode				key_autodock;
	
	OOKeyCode				key_snapshot;
	OOKeyCode				key_docking_music;
	
	OOKeyCode				key_advanced_nav_array;
	OOKeyCode				key_map_home;
	OOKeyCode				key_map_info;
	
	OOKeyCode				key_pausebutton;
	OOKeyCode				key_show_fps;
	OOKeyCode				key_mouse_control;
	
	OOKeyCode				key_comms_log;
	OOKeyCode				key_next_compass_mode;
	
	OOKeyCode				key_cloaking_device;
	
	OOKeyCode				key_contract_info;
	
	OOKeyCode				key_next_target;
	OOKeyCode				key_previous_target;
	
	OOKeyCode				key_custom_view;
	
#if DOCKING_CLEARANCE_ENABLED
	OOKeyCode				key_docking_clearance_request;
#endif
	
#ifndef NDEBUG
	OOKeyCode				key_dump_target_state;
#endif

	OOKeyCode				key_weapons_online_toggle;
	
	// save-file
	NSString				*save_path;
	
	// position of viewports
	Vector					forwardViewOffset, aftViewOffset, portViewOffset, starboardViewOffset;
	Vector					_sysInfoLight;
	
	// trumbles
	OOUInteger				trumbleCount;
	OOTrumble				*trumble[PLAYER_MAX_TRUMBLES];
	
	// smart zoom
	GLfloat					scanner_zoom_rate;
	
	// target memory
	int						target_memory[PLAYER_TARGET_MEMORY_SIZE];
	int						target_memory_index;
	
	// custom view points
	Quaternion				customViewQuaternion;
	OOMatrix				customViewMatrix;
	Vector					customViewOffset, customViewForwardVector, customViewUpVector, customViewRightVector;
	NSString				*customViewDescription;
	
	OOViewID				currentWeaponFacing;	// decoupled from view direction
	
	// docking reports
	NSMutableString			*dockingReport;
	
	// Woo, flags.
	unsigned				suppressTargetLost: 1,		// smart target lst reports
							scoopsActive: 1,			// smart fuelscoops
	
							scoopOverride: 1, //scripted to just be on, ignoring normal rules
							game_over: 1,
							finished: 1,
							bomb_detonated: 1,
							autopilot_engaged: 1,
	
							afterburner_engaged: 1,
							afterburnerSoundLooping: 1,
	
							hyperspeed_engaged: 1,
							travelling_at_hyperspeed: 1,
							hyperspeed_locked: 1,
							
							scripted_misjump: 1,
	
							ident_engaged: 1,
	
							galactic_witchjump: 1,
	
							ecm_in_operation: 1,
	
							show_info_flag: 1,
	
							showDemoShips: 1,
	
							rolling, pitching, yawing: 1,
							using_mining_laser: 1,
	
							mouse_control_on: 1,
	
							isSpeechOn: 1,
	
							keyboardRollOverride: 1,   // Handle keyboard roll...
							keyboardPitchOverride: 1,  // ...and pitch override separately - (fix for BUG #17490)  
							keyboardYawOverride: 1,
							waitingForStickCallback: 1,
							
							weapons_online: 1,
							
							launchingMissile: 1,
							replacingMissile: 1;
#if OOLITE_ESPEAK
	unsigned int			voice_no;
	BOOL					voice_gender_m;
#endif

	// Note: joystick stuff does nothing under OS X.
	// Keeping track of joysticks
	int						numSticks;
	JoystickHandler			*stickHandler;
  
	// For PlayerEntity (StickMapper)
	int						selFunctionIdx;
	NSArray					*stickFunctions; 
	
	OOGalacticHyperspaceBehaviour galacticHyperspaceBehaviour;
	NSPoint					galacticHyperspaceFixedCoords;
	
@private
	NSArray					*_customViews;
	OOUInteger				_customViewIndex;
	
#if DOCKING_CLEARANCE_ENABLED
	OODockingClearanceStatus dockingClearanceStatus;
#endif
#if WORMHOLE_SCANNER
	NSMutableArray *scannedWormholes;
#endif
}

+ (PlayerEntity *)sharedPlayer;
- (void) deferredInit;

- (void) setUp;
- (void)completeSetUp;

- (NSString *) captainName;

- (BOOL) isDocked;

- (void) warnAboutHostiles;

- (void) unloadCargoPods;
- (void) loadCargoPods;
- (void) unloadAllCargoPodsForType:(OOCommodityType)type fromArray:(NSMutableArray *) manifest;
- (void) unloadCargoPodsForType:(OOCommodityType)type amount:(OOCargoQuantity) quantity;
- (void) loadCargoPodsForType:(OOCommodityType)type fromArray:(NSMutableArray *) manifest;
- (void) loadCargoPodsForType:(OOCargoType)type amount:(OOCargoQuantity) quantity;
- (NSMutableArray *) shipCommodityData;

- (OOCreditsQuantity) deciCredits;

- (int) random_factor;
- (Random_Seed) galaxy_seed;
- (NSPoint) galaxy_coordinates;
- (NSPoint) cursor_coordinates;

- (Random_Seed) system_seed;
- (void) setSystem_seed:(Random_Seed) s_seed;
- (Random_Seed) target_system_seed;
- (void) setTargetSystemSeed:(Random_Seed) s_seed;

- (NSDictionary *) commanderDataDictionary;
- (BOOL)setCommanderDataFromDictionary:(NSDictionary *) dict;

- (void) doBookkeeping:(double) delta_t;

- (BOOL) massLocked;
- (BOOL) atHyperspeed;

- (void) setDockedAtMainStation;
- (StationEntity *) dockedStation;

- (BOOL) engageAutopilotToStation:(StationEntity *)stationForDocking;
- (void) disengageAutopilot;

- (void) resetAutopilotAI;

#if DOCKING_CLEARANCE_ENABLED
- (void) setTargetDockStationTo:(StationEntity *) value;
- (StationEntity *) getTargetDockStation;
#endif

- (HeadUpDisplay *) hud;
- (BOOL) switchHudTo:(NSString *)hudFileName;
- (void) resetHud;

- (void) setShowDemoShips:(BOOL) value;
- (BOOL) showDemoShips;

- (GLfloat) forwardShieldLevel;
- (GLfloat) aftShieldLevel;
- (GLfloat) baseMass;

- (void) setForwardShieldLevel:(GLfloat)level;
- (void) setAftShieldLevel:(GLfloat)level;

- (BOOL) isMouseControlOn;

- (GLfloat) dialRoll;
- (GLfloat) dialPitch;
- (GLfloat) dialYaw;
- (GLfloat) dialSpeed;
- (GLfloat) dialHyperSpeed;

- (void) currentWeaponStats;

- (GLfloat) dialForwardShield;
- (GLfloat) dialAftShield;

- (GLfloat) dialEnergy;
- (GLfloat) dialMaxEnergy;

- (GLfloat) dialFuel;
- (GLfloat) dialHyperRange;

- (GLfloat) dialAltitude;

- (unsigned) countMissiles;
- (OOMissileStatus) dialMissileStatus;

- (OOFuelScoopStatus) dialFuelScoopStatus;

- (float)fuelLeakRate;

- (double) clockTime;		// Note that this is not an OOTimeAbsolute
- (double) clockTimeAdjusted;	// Note that this is not an OOTimeAbsolute
- (BOOL) clockAdjusting;
- (void) addToAdjustTime:(double) seconds ;

- (NSString *) dial_clock;
- (NSString *) dial_clock_adjusted;
- (NSString *) dial_fpsinfo;
- (NSString *) dial_objinfo;

- (NSMutableArray *) commLog;

- (Entity *) compassTarget;
- (void) setCompassTarget:(Entity *)value;

- (OOCompassMode) compassMode;
- (void) setCompassMode:(OOCompassMode)value;
- (void) setNextCompassMode;

- (unsigned) activeMissile;
- (void) setActiveMissile:(unsigned)value;
- (unsigned) dialMaxMissiles;
- (BOOL) dialIdentEngaged;
- (NSString *) specialCargo;
- (NSString *) dialTargetName;
- (ShipEntity *) missileForPylon:(unsigned)value;
- (void) safeAllMissiles;
- (void) selectNextMissile;
- (void) tidyMissilePylons;
- (BOOL) removeFromPylon:(unsigned) pylon;
- (BOOL) assignToActivePylon:(NSString *)identifierKey;

- (void) clearAlertFlags;
- (int) alertFlags;
- (void) setAlertFlag:(int)flag to:(BOOL)value;
- (OOAlertCondition) alertCondition;

- (BOOL) mountMissile:(ShipEntity *)missile;
- (BOOL) mountMissileWithRole:(NSString *)role;

- (OOEnergyUnitType) installedEnergyUnitType;
- (OOEnergyUnitType) energyUnitType;

- (BOOL) fireEnergyBomb;
- (ShipEntity *) launchMine:(ShipEntity *)mine;

- (BOOL) weaponsOnline;
- (void) setWeaponsOnline:(BOOL)newValue;

- (BOOL) fireMainWeapon;
- (OOWeaponType) weaponForView:(OOViewID)view;

- (void) rotateCargo;

- (void) enterGalacticWitchspace;

- (BOOL) takeInternalDamage;

- (void) loseTargetStatus;

- (void) docked;

- (void) setGuiToStatusScreen;
- (NSArray *) equipmentList;	// Each entry is an array with a string followed by a boolean indicating availability (NO = damaged).
- (NSArray *) cargoList;
- (NSArray *) cargoListForScripting;
- (void) setGuiToSystemDataScreen;
- (NSArray *) markedDestinations;
- (void) setGuiToLongRangeChartScreen;
- (void) setGuiToShortRangeChartScreen;
- (void) setGuiToLoadSaveScreen;
- (void) setGuiToGameOptionsScreen;
- (void) setGuiToEquipShipScreen:(int)skip selectingFacingFor:(NSString *)eqKeyForSelectFacing;
- (void) setGuiToEquipShipScreen:(int)skip;
- (void) highlightEquipShipScreenKey:(NSString *)key;
- (void) showInformationForSelectedUpgrade;
- (void) showInformationForSelectedUpgradeWithFormatString:(NSString *)extraString;
- (BOOL) changePassengerBerths:(int) addRemove;
- (OOCargoQuantity) cargoQuantityForType:(OOCommodityType)type;
- (OOCargoQuantity) setCargoQuantityForType:(OOCommodityType)type amount:(OOCargoQuantity)amount;
- (void) calculateCurrentCargo;
- (void) setGuiToMarketScreen;

- (void) setGuiToIntroFirstGo:(BOOL)justCobra;

- (void) noteGuiChangeFrom:(OOGUIScreenID)fromScreen to:(OOGUIScreenID)toScreen;

- (OOGUIScreenID) guiScreen;

- (void) buySelectedItem;
- (BOOL) marketFlooded:(int) index;
- (BOOL) tryBuyingCommodity:(int) index all:(BOOL) all;
- (BOOL) trySellingCommodity:(int) index all:(BOOL) all;

- (BOOL) isSpeechOn;

- (void) addEquipmentFromCollection:(id)equipment;	// equipment may be an array, a set, a dictionary whose values are all YES, or a string.
 
- (void) getFined;
- (void) reduceTradeInFactorBy:(int)value;

- (void) setDefaultViewOffsets;
- (void) setDefaultCustomViews;
- (Vector) weaponViewOffset;

- (void) setUpTrumbles;
- (void) addTrumble:(OOTrumble*) papaTrumble;
- (void) removeTrumble:(OOTrumble*) deadTrumble;
- (OOTrumble**)trumbleArray;
- (OOUInteger) trumbleCount;
// loading and saving trumbleCount
- (id)trumbleValue;
- (void) setTrumbleValueFrom:(NSObject*) trumbleValue;

- (void) mungChecksumWithNSString:(NSString *)str;

- (NSString *)screenModeStringForWidth:(unsigned)inWidth height:(unsigned)inHeight refreshRate:(float)inRate;

- (void) suppressTargetLost;

- (void) setScoopsActive;

- (void) clearTargetMemory;
- (BOOL) moveTargetMemoryBy:(int)delta;

- (void) printIdentLockedOnForMissile:(BOOL)missile;

- (void) applyYaw:(GLfloat) yaw;

/* GILES custom viewpoints */

// custom view points
- (Quaternion)customViewQuaternion;
- (OOMatrix)customViewMatrix;
- (Vector)customViewOffset;
- (Vector)customViewForwardVector;
- (Vector)customViewUpVector;
- (Vector)customViewRightVector;
- (NSString *)customViewDescription;
- (void)setCustomViewDataFromDictionary:(NSDictionary*) viewDict;
- (Vector) viewpointPosition;
- (Vector) viewpointOffset;

#if 0
- (OOCamera *) currentCamera;
#endif

- (NSArray *) worldScriptNames;
- (NSDictionary *) worldScriptsByName;

// *** World script events.
// In general, script events should be sent through doScriptEvent:..., which
// will forward to the world scripts.
- (void) doWorldScriptEvent:(NSString *)message withArguments:(NSArray *)arguments timeLimit:(OOTimeDelta)limit;
- (BOOL) doWorldEventUntilMissionScreen:(NSString *)message;

- (BOOL)showInfoFlag;

- (void) setGalacticHyperspaceBehaviour:(OOGalacticHyperspaceBehaviour) galacticHyperspaceBehaviour;
- (OOGalacticHyperspaceBehaviour) galacticHyperspaceBehaviour;
- (void) setGalacticHyperspaceFixedCoordsX:(unsigned char)x y:(unsigned char)y;
- (NSPoint) galacticHyperspaceFixedCoords;

- (BOOL) scriptedMisjump;
- (void) setScriptedMisjump:(BOOL)newValue;

- (BOOL) scoopOverride;
- (void) setScoopOverride:(BOOL)newValue;
- (void) setDockTarget:(ShipEntity *)entity;

#if DOCKING_CLEARANCE_ENABLED
- (BOOL) clearedToDock;
- (void) setDockingClearanceStatus:(OODockingClearanceStatus) newValue;
- (OODockingClearanceStatus) getDockingClearanceStatus;
- (void) penaltyForUnauthorizedDocking;
#endif

#if WORMHOLE_SCANNER
- (NSArray *) scannedWormholes;
#endif

@end
