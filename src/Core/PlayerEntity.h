//
//  PlayerEntity.h
/*
 *
 *  Oolite
 *
 *  Created by Giles Williams on Sat Apr 03 2004.
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

#import <Foundation/Foundation.h>
#import "ShipEntity.h"

#ifdef GNUSTEP
#import "SDLImage.h"
#endif

@class GuiDisplayGen, OOTrumble, MyOpenGLView, HeadUpDisplay, ShipEntity;
@class OOSound, OOMusic, OOSoundSource, OOSoundReferencePoint;

#ifdef GNUSTEP
@class JoystickHandler;
#endif

#define SCRIPT_TIMER_INTERVAL			10.0

#define GUI_SCREEN_MAIN					000
#define GUI_SCREEN_INTRO1				001
#define GUI_SCREEN_INTRO2				002
#define GUI_SCREEN_STATUS				101
#define GUI_SCREEN_MANIFEST				111
#define GUI_SCREEN_EQUIP_SHIP			102
#define GUI_SCREEN_SHIPYARD				112
#define GUI_SCREEN_LONG_RANGE_CHART		103
#define GUI_SCREEN_SHORT_RANGE_CHART	113
#define GUI_SCREEN_SYSTEM_DATA			105
#define GUI_SCREEN_MARKET				106
#define GUI_SCREEN_CONTRACTS			116
#define GUI_SCREEN_INVENTORY			107
#define GUI_SCREEN_OPTIONS				108
#define GUI_SCREEN_LOAD					118
#define GUI_SCREEN_SAVE					128
#define GUI_SCREEN_SAVE_OVERWRITE		129
#define GUI_SCREEN_STICKMAPPER			138
#define GUI_SCREEN_MISSION				201
#define GUI_SCREEN_REPORT				301

enum
{
	GUI_ROW_OPTIONS_QUICKSAVE			= 6,
	GUI_ROW_OPTIONS_SAVE,
	GUI_ROW_OPTIONS_LOAD,
	GUI_ROW_OPTIONS_BEGIN_NEW,
	GUI_ROW_OPTIONS_OPTIONS,
	GUI_ROW_OPTIONS_DISPLAY,
	
#ifndef GNUSTEP
	GUI_ROW_OPTIONS_SPEECH,
	GUI_ROW_OPTIONS_VOLUME,
	GUI_ROW_OPTIONS_GROWL,
	GUI_ROW_OPTIONS_OOTUNES,
	GUI_ROW_OPTIONS_DETAIL,
	GUI_ROW_OPTIONS_STRICT,
#else
	GUI_ROW_OPTIONS_DISPLAYSTYLE,
	GUI_ROW_OPTIONS_VOLUME,
	GUI_ROW_OPTIONS_DETAIL,
	GUI_ROW_OPTIONS_STRICT,
	GUI_ROW_OPTIONS_STICKMAPPER,
	GUI_ROW_OPTIONS_QUIT,
#endif
	
	GUI_ROW_OPTIONS_END_OF_LIST
};

enum
{
	SCOOP_STATUS_NOT_INSTALLED			= 0,
	SCOOP_STATUS_FULL_HOLD,
	SCOOP_STATUS_OKAY,
	SCOOP_STATUS_ACTIVE
};

#define GUI_ROW_EQUIPMENT_START			3
#define GUI_MAX_ROWS_EQUIPMENT			12
#define GUI_ROW_EQUIPMENT_DETAIL		GUI_ROW_EQUIPMENT_START+GUI_MAX_ROWS_EQUIPMENT+1
#define GUI_ROW_EQUIPMENT_CASH			1
#define GUI_ROW_MARKET_KEY				1
#define GUI_ROW_MARKET_START			2
#define GUI_ROW_MARKET_CASH				20

#define WEAPON_COOLING_FACTOR			6.0
#define ENERGY_RECHARGE_FACTOR			energy_recharge_rate
#define SHIELD_RECHARGE_FACTOR			(2.0 + shield_enhancer)
#define ECM_ENERGY_DRAIN_FACTOR			20.0
#define ECM_DURATION					2.5

#define ROLL_DAMPING_FACTOR				1.0
#define PITCH_DAMPING_FACTOR			1.0

#define PLAYER_MAX_FORWARD_SHIELD		(128.0 * (shield_booster + shield_enhancer))
#define PLAYER_MAX_AFT_SHIELD			(128.0 * (shield_booster + shield_enhancer))
#define PLAYER_MAX_WEAPON_TEMP			256.0
#define PLAYER_MAX_FUEL					70
#define PLAYER_MAX_MISSILES				4
#define PLAYER_STARTING_MISSILES		3
#define PLAYER_DIAL_MAX_ALTITUDE		40000.0
#define PLAYER_SUPER_ALTITUDE2			10000000000.0

#define PLAYER_MAX_TRUMBLES				24

#define	PLAYER_TARGET_MEMORY_SIZE		16

	//  ~~~~~~~~~~~~~~~~~~~~~~~~	= 40km
	
#define ALERT_CONDITION_DOCKED			0
#define ALERT_CONDITION_GREEN			1
#define ALERT_CONDITION_YELLOW			2
#define ALERT_CONDITION_RED				3

#define SHOT_RELOAD						0.25

#define HYPERSPEED_FACTOR				32.0

#define PLAYER_SHIP_DESC				@"cobra3-player"
#define PLAYER_MODEL					@"cobra3_redux.dat"

#define KEY_DOCKING_MUSIC				@"docking_music"

#define ESCAPE_SEQUENCE_TIME			10.0

#define AI_DOCKING_COMPUTER				@"dockingAI.plist"

#define MS_WITCHSPACE_SF				@"[witch-to-@-in-f-seconds]"
#define MS_GAL_WITCHSPACE_F				@"[witch-galactic-in-f-seconds]"

#define MISSILE_STATUS_SAFE				0
#define MISSILE_STATUS_ARMED			1
#define MISSILE_STATUS_TARGET_LOCKED	2

#define WEAPON_FACING_NONE				0
#define WEAPON_FACING_FORWARD			1
#define WEAPON_FACING_AFT				2
#define WEAPON_FACING_PORT				4
#define WEAPON_FACING_STARBOARD			8

#define WEAPON_OFFSET_DOWN				20

#define FORWARD_FACING_STRING			@"\tForward "
#define AFT_FACING_STRING				@"\tAft "
#define PORT_FACING_STRING				@"\tPort "
#define STARBOARD_FACING_STRING			@"\tStarboard "

#define ENERGY_UNIT_NONE				0
#define ENERGY_UNIT_NORMAL				15
#define ENERGY_UNIT_NAVAL				20

#define ALERT_FLAG_DOCKED				0x010
#define ALERT_FLAG_MASS_LOCK			0x020
#define ALERT_FLAG_YELLOW_LIMIT			0x03f
#define ALERT_FLAG_TEMP					0x040
#define ALERT_FLAG_ALT					0x080
#define ALERT_FLAG_ENERGY				0x100
#define ALERT_FLAG_HOSTILES				0x200

#define KEY_REPEAT_INTERVAL				0.20

#define OOTUNES_ON						ootunes_on

#define PLAYER_SHIP_CLOCK_START			2084004 * 86400.0

#define CONTRACTS_GOOD_KEY				@"contracts_fulfilled"
#define CONTRACTS_BAD_KEY				@"contracts_expired"
#define CONTRACTS_UNKNOWN_KEY			@"contracts_unknown"
#define PASSAGE_GOOD_KEY				@"passage_fulfilled"
#define PASSAGE_BAD_KEY					@"passage_expired"
#define PASSAGE_UNKNOWN_KEY				@"passage_unknown"

#define COMPASS_MODE_BASIC				0
#define COMPASS_MODE_PLANET				1
#define COMPASS_MODE_STATION			2
#define COMPASS_MODE_SUN				3
#define COMPASS_MODE_TARGET				4
#define COMPASS_MODE_BEACONS			6
#define COMPASS_MODE_ADVANCED_OKAY		((compass_mode >= 1)&&(compass_mode <= 10))

#define SCANNER_ZOOM_RATE_UP			2.0
#define SCANNER_ZOOM_RATE_DOWN			-8.0

#define PLAYER_INTERNAL_DAMAGE_FACTOR	31

#define PLAYER_DOCKING_AI_NAME			@"dockingAI.plist"

@interface PlayerEntity : ShipEntity
{
@public
	
	Random_Seed				system_seed;
	Random_Seed				target_system_seed;
	
	BOOL					show_info_flag;
	
@protected
	
	NSString				*ship_desc;
	int						ship_trade_in_factor;
	
	NSDictionary			*script;
	NSMutableDictionary		*mission_variables;
	NSMutableDictionary		*local_variables;
	int						missionTextRow;
	ShipEntity				*script_target;
	NSString				*missionChoice;
	
	NSString*				specialCargo;
	
	NSMutableArray*			comm_log;

#ifdef GNUSTEP
 	SDLImage				*missionBackgroundImage;
#else
	NSImage					*missionBackgroundImage;
#endif
	
	NSMutableDictionary		*extra_equipment;
	BOOL					found_equipment;
	
	NSMutableDictionary		*reputation;
	
	int						max_passengers;
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
	
	NSString				*planetSearchString;
	
	gl_matrix				playerRotMatrix;
	
	// For OO-GUI based save screen
	NSString				*commanderNameString;
	NSMutableArray			*cdrDetailArray;
	int						currentPage;
	BOOL					pollControls;
    // ...end save screen   
	
	StationEntity			*docked_station;
	
	HeadUpDisplay			*hud;
	
	BOOL					showDemoShips;
	
	BOOL					rolling, pitching, yawing;
	BOOL					using_mining_laser;
	
	BOOL					mouse_control_on;
	
	BOOL					speech_on;
	BOOL					ootunes_on;
	
	BOOL					docking_music_on;
	
	GLfloat					roll_delta, pitch_delta, yaw_delta;
	
	GLfloat					forward_shield, aft_shield;
	GLfloat					weapon_temp;
	GLfloat					forward_weapon_temp, aft_weapon_temp, port_weapon_temp, starboard_weapon_temp;
	GLfloat					weapon_energy_per_shot, weapon_heat_increment_per_shot, weapon_reload_time;
	
	int						chosen_weapon_facing;   // for purchasing weapons
	
	BOOL					game_over;
	BOOL					docked;
	BOOL					finished;
	BOOL					bomb_detonated;
	BOOL					autopilot_engaged;
	
	BOOL					afterburner_engaged;
	BOOL					afterburnerSoundLooping;
	
	BOOL					hyperspeed_engaged;
	BOOL					travelling_at_hyperspeed;
	BOOL					hyperspeed_locked;
	
	BOOL					ident_engaged;
	
	BOOL					galactic_witchjump;
	
	BOOL					ecm_in_operation;
	double					ecm_start_time;
	
	OOMusic					*themeMusic;
	OOMusic					*missionMusic;
	OOMusic					*dockingMusic;
	
	OOSound					*beepSound;
	OOSound					*boopSound;
	OOSound					*weaponSound;
	OOSound					*weaponHitSound;
	OOSound					*missileSound;
	OOSound					*damageSound;
	OOSound					*scrapeDamageSound;
	OOSound					*destructionSound;
	OOSound					*breakPatternSound;
	OOSound					*ecmSound;
	OOSound					*buySound;
	OOSound					*sellSound;
	OOSound					*warningSound;
	OOSound					*afterburner1Sound;
	OOSound					*afterburner2Sound;
	OOSound					*witchAbortSound;
	OOSound					*fuelScoopSound;
	
	OOSoundReferencePoint	*refPoint;
	OOSoundSource			*interfaceBeepSource;
	OOSoundSource			*ecmSource;
	OOSoundSource			*breakPatternSource;
	
	int						gui_screen;
	int						alert_flags;
	int						alert_condition;
	int						missile_status;
	int						active_missile;
	
	int						current_cargo;
	
	NSPoint					cursor_coordinates;
	double					witchspaceCountdown;
	
	// player commander data
	NSString*				player_name;
	NSPoint					galaxy_coordinates;
	
	Random_Seed				galaxy_seed;
	
	int						credits;	
	int						galaxy_number;
	int						forward_weapon;
	int						aft_weapon;
	int						port_weapon;
	int						starboard_weapon;
	
	NSMutableArray			*shipCommodityData;
	
	BOOL					has_energy_unit;
	int						energy_unit;
	int						shield_booster, shield_enhancer;
	BOOL					has_docking_computer;
	BOOL					has_galactic_hyperdrive;
	
	int						max_missiles;		// int				- no. of missile pylons
	ShipEntity*				missile_entity[SHIPENTITY_MAX_MISSILES];	// holds the actual missile entities or equivalents
	
	int						legal_status;
	int						market_rnd;
	int						ship_kills;
	BOOL					saved;
	
	int						compass_mode;
	
	GLfloat					fuel_leak_rate;
	
	// keys!
	int						key_roll_left;
	int						key_roll_right;
	int						key_yaw_left;
	int						key_yaw_right;
	int						key_pitch_forward;
	int						key_pitch_back;
	int						key_increase_speed;
	int						key_decrease_speed;
	
	int						key_inject_fuel;
	
	int						key_fire_lasers;
	int						key_target_missile;
	int						key_untarget_missile;
	int						key_launch_missile;
	int						key_ecm;
	int						key_launch_escapepod;
	int						key_energy_bomb;
	int						key_galactic_hyperspace;
	int						key_hyperspace;
	int						key_jumpdrive;
	int						key_dump_cargo;
	int						key_rotate_cargo;
	int						key_autopilot;
	int						key_autopilot_target;
	int						key_autodock;
	int						key_snapshot;
	int						key_docking_music;
	int						key_scanner_zoom;
	int						key_scanner_unzoom;
	
	int						key_map_dump;
	int						key_map_home;
	int						key_map_info;
	
	int						key_pausebutton;
	int						key_show_fps;
	int						key_mouse_control;
	
	int						key_emergency_hyperdrive;
	
	int						key_next_missile;
	int						key_ident_system;
	
	int						key_comms_log;
	
	int						key_next_compass_mode;
	
	int						key_cloaking_device;
	
	int						key_contract_info;
	
	int						key_next_target;
	int						key_previous_target;
	
	int						key_custom_view;
	
	// save-file
	NSString				*save_path;
	
	// position of viewports
	Vector					forwardViewOffset, aftViewOffset, portViewOffset, starboardViewOffset;
	
	// DEBUG
	ParticleEntity			*drawDebugParticle;
	int						debugShipID;
	
	// trumbles
	int						n_trumbles;
	OOTrumble				*trumble[PLAYER_MAX_TRUMBLES];
	
	// smart zoom
	GLfloat					scanner_zoom_rate;
	
	// smart target lst reports
	BOOL					suppressTargetLost;
	
	// smart fuelscoops
	BOOL					scoopsActive;
	
	// target memory
	int						target_memory[PLAYER_TARGET_MEMORY_SIZE];
	int						target_memory_index;
	
	/* GILES custom viewpoints */
	
	// custom view points
	NSMutableArray*			custom_views;
	Quaternion				customViewQuaternion;
	GLfloat					customViewMatrix[16];
	Vector					customViewOffset, customViewForwardVector, customViewUpVector, customViewRightVector;
	NSString*				customViewDescription;
	
	int						currentWeaponFacing;	// decoupled from view direction
	
	// docking reports
	NSMutableString*		dockingReport;
	
	/* -- */

#ifdef GNUSTEP
  // Keeping track of joysticks
  int						numSticks;
  JoystickHandler			*stickHandler;
  BOOL						keyboardRollPitchOverride;
  
  // For PlayerEntity (StickMapper)
  int						selFunctionIdx;
  BOOL						waitingForStickCallback;
  NSArray					*stickFunctions; 
#endif
}

- (void) init_keys;
- (void) warnAboutHostiles;

- (void) unloadCargoPods;
- (void) loadCargoPods;

- (int)			random_factor;
- (Random_Seed) galaxy_seed;
- (NSPoint)		galaxy_coordinates;
- (NSPoint)		cursor_coordinates;

- (Random_Seed) system_seed;
- (void) setSystem_seed:(Random_Seed) s_seed;
- (Random_Seed) target_system_seed;

- (NSDictionary *) commanderDataDictionary;
- (void) setCommanderDataFromDictionary:(NSDictionary *) dict;

- (void) set_up;

- (void) doBookkeeping:(double) delta_t;

- (BOOL) massLocked;
- (BOOL) atHyperspeed;
- (Vector) velocityVector;

- (NSString *) ship_desc;

- (StationEntity *) docked_station;

- (HeadUpDisplay *) hud;

- (void) setShowDemoShips:(BOOL) value;
- (BOOL) showDemoShips;

- (GLfloat) dial_roll;
- (GLfloat) dial_pitch;
- (GLfloat) dial_speed;
- (GLfloat) dial_hyper_speed;

- (GLfloat) dial_forward_shield;
- (GLfloat) dial_aft_shield;

- (GLfloat) dial_energy;
- (GLfloat) dial_max_energy;

- (GLfloat) dial_fuel;
- (GLfloat) dial_hyper_range;

- (GLfloat) dial_ship_temperature;
- (GLfloat) dial_weapon_temp;
- (GLfloat) dial_altitude;

- (int) dial_missiles;
- (int) calc_missiles;
- (int) dial_missile_status;

- (int) dial_fuelscoops_status;

- (NSString*) dial_clock;
- (NSString*) dial_clock_adjusted;
- (NSString*) dial_fpsinfo;
- (NSString*) dial_objinfo;

- (NSMutableArray*) comm_log;

- (int) compass_mode;
- (void) setCompass_mode:(int) value;
- (void) setNextCompassMode;

- (int) active_missile;
- (void) setActive_missile: (int) value;
- (int) dial_max_missiles;
- (BOOL) dial_ident_engaged;
- (NSString *) dial_target_name;
- (ShipEntity *) missile_for_station: (int) value;
- (void) sort_missiles;
- (void) safe_all_missiles;
- (void) select_next_missile;
- (void) tidyMissilePylons;

- (void) clearAlert_flags;
- (void) setAlert_flag:(int) flag :(BOOL) value;
- (int) alert_condition;

- (BOOL) mountMissile: (ShipEntity *)missile;

- (BOOL) fireEnergyBomb;
- (BOOL) launchMine:(ShipEntity*) mine;

- (BOOL) fireMainWeapon;
- (int) weaponForView:(int) view;

- (void) rotateCargo;

- (void) enterGalacticWitchspace;
- (void) enterWormhole:(WormholeEntity*) w_hole;

- (void) interpretAIMessage:(NSString *)ms;

- (void) takeInternalDamage;
- (NSDictionary*) damageInformation;
- (void) getDestroyed;

- (void) loseTargetStatus;

- (void) docked;

- (void) quicksavePlayer;
- (void) savePlayer;
- (void) loadPlayer;
- (void) loadPlayerFromFile:(NSString *)fileToOpen;
- (void) changePlayerName;

- (void) setGuiToStatusScreen;
- (int) getRatingFromKills: (int)shipKills;
- (NSArray *) equipmentList;
- (NSArray *) cargoList;
- (void) setGuiToSystemDataScreen;
- (NSArray *) markedDestinations;
- (void) setGuiToLongRangeChartScreen;
- (void) starChartDump;
- (void) setGuiToShortRangeChartScreen;
- (void) setGuiToLoadSaveScreen;
- (void) setGuiToEquipShipScreen:(int) skip :(int) itemForSelectFacing;
- (void) showInformationForSelectedUpgrade;
- (void) calculateCurrentCargo;
- (void) setGuiToMarketScreen;

- (void) setGuiToIntro1Screen;
- (void) setGuiToIntro2Screen;

- (int) gui_screen;

- (void) buySelectedItem;
- (BOOL) tryBuyingItem:(int) index;
- (BOOL) marketFlooded:(int) index;
- (BOOL) tryBuyingCommodity:(int) index;
- (BOOL) trySellingCommodity:(int) index;

- (BOOL) speech_on;

- (BOOL) has_extra_equipment:(NSString *) eq_key;
- (void) add_extra_equipment:(NSString *) eq_key;
- (void) remove_extra_equipment:(NSString *) eq_key;
- (void) set_extra_equipment_from_flags;
- (void) set_flags_from_extra_equipment;

- (void) loopAfterburnerSound;
- (void) stopAfterburnerSound;

- (void) setScript_target:(ShipEntity *)ship;
- (ShipEntity*) script_target;
 
- (void) getFined;

- (void) setDefaultViewOffsets;
- (Vector) weaponViewOffset;

- (void) setUpTrumbles;
- (void) addTrumble:(OOTrumble*) papaTrumble;
- (void) removeTrumble:(OOTrumble*) deadTrumble;
- (OOTrumble**) trumbleArray;
- (int) n_trumbles;
// loading and saving n_trummbles
- (NSObject*) trumbleValue;
- (void) setTrumbleValueFrom:(NSObject*) trumbleValue;

- (void) munge_checksum_with_NSString:(NSString*) str;

- (NSString *)screenModeStringForWidth:(unsigned)inWidth height:(unsigned)inHeight refreshRate:(float)inRate;

- (void) suppressTargetLost;

- (void) setScoopsActive;

- (void) clearTargetMemory;
- (BOOL) selectNextTargetFromMemory;
- (BOOL) selectPreviousTargetFromMemory;

- (void) applyYaw:(GLfloat) yaw;

/* GILES custom viewpoints */

// custom view points
- (Quaternion)	customViewQuaternion;
- (GLfloat*)	customViewMatrix;
- (Vector)		customViewOffset;
- (Vector)		customViewForwardVector;
- (Vector)		customViewUpVector;
- (Vector)		customViewRightVector;
- (NSString*)	customViewDescription;
- (void)		setCustomViewDataFromDictionary:(NSDictionary*) viewDict;

/* -- */


@end
