/*

PlayerEntityControls.h

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

#import "PlayerEntityControls.h"
#import "PlayerEntityContracts.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "PlayerEntitySound.h"
#import "PlayerEntityLoadSave.h"
#import "PlayerEntityStickMapper.h"

#import "ShipEntityAI.h"
#import "StationEntity.h"
#import "Universe.h"
#import "GameController.h"
#import "AI.h"
#import "MyOpenGLView.h"
#import "OOSound.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"
#import "ResourceManager.h"
#import "HeadUpDisplay.h"
#import "OOConstToString.h"

#import "JoystickHandler.h"

#if OOLITE_MAC_OS_X
#import "Groolite.h"
#endif


static NSString * const kOOLogFlightTrainingBeacons		= @"beacon.list.flightTraining";


@implementation PlayerEntity (Controls)

- (void) initControls
{
	NSMutableDictionary	*kdic = [NSMutableDictionary dictionaryWithDictionary:[ResourceManager dictionaryFromFilesNamed:@"keyconfig.plist" inFolder:@"Config" mergeMode:MERGE_BASIC cache:NO]];
	
	// pre-process kdic - replace any strings with an integer representing the ASCII value of the first character
	
	unsigned		i;
	NSArray			*keys = nil;
	id				key = nil, value = nil;
	int				iValue;
	unsigned char	keychar;
	NSString		*keystring = nil;
	
	keys = [kdic allKeys];
	for (i = 0; i < [keys count]; i++)
	{
		key = [keys objectAtIndex:i];
		value = [kdic objectForKey: key];
		iValue = [value intValue];
		
		//	for '0' '1' '2' '3' '4' '5' '6' '7' '8' '9' - we want to interpret those as strings - not numbers
		//	alphabetical characters and symbols will return an intValue of 0.
		
		if ([value isKindOfClass:[NSString class]] && (iValue < 10))
		{
			keystring = value;
			if ([keystring length] == 1 || (iValue == 0 && [keystring length] != 0))
			{
				keychar = [keystring characterAtIndex: 0] & 0x00ff; // uses lower byte of unichar
			}
			else if (iValue <= 0xFF)  keychar = iValue;
			
			[kdic setObject:[NSNumber numberWithUnsignedChar:keychar] forKey:key];
		}
	}
	
	// set default keys.
	#define LOAD_KEY_SETTING(name, default)	name = [kdic unsignedShortForKey:@#name defaultValue:default]
	
	LOAD_KEY_SETTING(key_roll_left,				gvArrowKeyLeft		);
	LOAD_KEY_SETTING(key_roll_right,			gvArrowKeyRight		);
	LOAD_KEY_SETTING(key_pitch_forward,			gvArrowKeyUp		);
	LOAD_KEY_SETTING(key_pitch_back,			gvArrowKeyDown		);
	LOAD_KEY_SETTING(key_yaw_left,				','					);
	LOAD_KEY_SETTING(key_yaw_right,				'.'					);
	
	LOAD_KEY_SETTING(key_increase_speed,		'w'					);
	LOAD_KEY_SETTING(key_decrease_speed,		's'					);
	LOAD_KEY_SETTING(key_inject_fuel,			'i'					);
	
	LOAD_KEY_SETTING(key_fire_lasers,			'a'					);
	LOAD_KEY_SETTING(key_launch_missile,		'm'					);
	LOAD_KEY_SETTING(key_next_missile,			'y'					);
	LOAD_KEY_SETTING(key_ecm,					'e'					);
	
	LOAD_KEY_SETTING(key_target_missile,		't'					);
	LOAD_KEY_SETTING(key_untarget_missile,		'u'					);
	LOAD_KEY_SETTING(key_ident_system,			'r'					);
	
	LOAD_KEY_SETTING(key_scanner_zoom,			'z'					);
	LOAD_KEY_SETTING(key_scanner_unzoom,		'Z'					);
	
	LOAD_KEY_SETTING(key_launch_escapepod,		27	/* esc */		);
	LOAD_KEY_SETTING(key_energy_bomb,			'\t'				);
	
	LOAD_KEY_SETTING(key_galactic_hyperspace,	'g'					);
	LOAD_KEY_SETTING(key_hyperspace,			'h'					);
	LOAD_KEY_SETTING(key_jumpdrive,				'j'					);
	
	LOAD_KEY_SETTING(key_dump_cargo,			'd'					);
	LOAD_KEY_SETTING(key_rotate_cargo,			'R'					);
	
	LOAD_KEY_SETTING(key_autopilot,				'c'					);
	LOAD_KEY_SETTING(key_autopilot_target,		'C'					);
	LOAD_KEY_SETTING(key_autodock,				'D'					);
	
	LOAD_KEY_SETTING(key_snapshot,				'*'					);
	LOAD_KEY_SETTING(key_docking_music,			's'					);
	
	LOAD_KEY_SETTING(key_advanced_nav_array,	'^'					);
	LOAD_KEY_SETTING(key_map_home,				gvHomeKey			);
	LOAD_KEY_SETTING(key_map_info,				'i'					);
	
	LOAD_KEY_SETTING(key_pausebutton,			'p'					);
	LOAD_KEY_SETTING(key_show_fps,				'F'					);
	LOAD_KEY_SETTING(key_mouse_control,			'M'					);
	
	LOAD_KEY_SETTING(key_comms_log,				'`'					);
	LOAD_KEY_SETTING(key_next_compass_mode,		'\\'				);
	
	LOAD_KEY_SETTING(key_cloaking_device,		'0'					);
	
	LOAD_KEY_SETTING(key_contract_info,			'\?'				);
	
	LOAD_KEY_SETTING(key_next_target,			'+'					);
	LOAD_KEY_SETTING(key_previous_target,		'-'					);
	
	LOAD_KEY_SETTING(key_custom_view,			'v'					);
	
#ifndef NDEBUG
	LOAD_KEY_SETTING(key_dump_target_state,		'H'					);
#endif
	
	// other keys are SET and cannot be varied
	
	// Enable polling
	pollControls=YES;
}


- (void) pollControls:(double) delta_t
{
	MyOpenGLView  *gameView = (MyOpenGLView *)[UNIVERSE gameView];

	if (gameView)
	{
		// poll the gameView keyboard things
		[self pollApplicationControls]; // quit command-f etc.
		switch (status)
		{
			case	STATUS_WITCHSPACE_COUNTDOWN :
			case	STATUS_IN_FLIGHT :
				[self pollFlightControls:delta_t];
				break;

			case	STATUS_DEAD :
				[self pollGameOverControls:delta_t];
				break;

			case	STATUS_AUTOPILOT_ENGAGED :
				[self pollAutopilotControls:delta_t];
				break;

			case	STATUS_DOCKED :
				[self pollDockedControls:delta_t];
				break;

			case	STATUS_START_GAME :
				[self pollDemoControls:delta_t];
				break;

			case	STATUS_ESCAPE_SEQUENCE :
			case	STATUS_HANDLING_ERROR :
			default :
				break;
		}

		// handle docking music generically
		if (status == STATUS_AUTOPILOT_ENGAGED)
		{
			if (docking_music_on)
			{
				if (![dockingMusic isPlaying])
					[dockingMusic play];
			}
			else
			{
				if ([dockingMusic isPlaying])
					[dockingMusic stop];
			}
		}
		else
		{
			if ([dockingMusic isPlaying])
				[dockingMusic stop];
		}

	}
}

//static BOOL fuel_inject_pressed;
static BOOL jump_pressed;
static BOOL hyperspace_pressed;
static BOOL galhyperspace_pressed;
static BOOL pause_pressed;
static BOOL compass_mode_pressed;
static BOOL next_target_pressed;
static BOOL previous_target_pressed;
static BOOL next_missile_pressed;
static BOOL fire_missile_pressed;
static BOOL target_missile_pressed;
static BOOL ident_pressed;
static BOOL safety_pressed;
static BOOL cloak_pressed;
static BOOL rotateCargo_pressed;
static BOOL autopilot_key_pressed;
static BOOL fast_autopilot_key_pressed;
static BOOL target_autopilot_key_pressed;

#ifndef NDEBUG
static BOOL dump_target_state_pressed;
#endif


static int				saved_view_direction;
static double			saved_script_time;
static NSTimeInterval	time_last_frame;
- (void) pollFlightControls:(double) delta_t
{
	MyOpenGLView  *gameView = (MyOpenGLView *)[UNIVERSE gameView];

	// DJS: TODO: Sort where SDL keeps its stuff.
	if(!stickHandler)
	{
		stickHandler=[gameView getStickHandler];
	}
	const BOOL *joyButtonState=[stickHandler getAllButtonStates];
	
    BOOL paused = [[gameView gameController] gameIsPaused];
	double speed_delta = 5.0 * thrust;
	
	if (!paused)
	{
		//
		// arrow keys
		//
		if ([UNIVERSE displayGUI])
			[self pollGuiArrowKeyControls:delta_t];
		else
			[self pollFlightArrowKeyControls:delta_t];
		//
		//  view keys
		//
		[self pollViewControls];

		//if (![gameView allowingStringInput])
		if (![UNIVERSE displayCursor])
		{
			if ((joyButtonState[BUTTON_FUELINJECT] || [gameView isDown:key_inject_fuel])&&(has_fuel_injection)&&(!hyperspeed_engaged))
			{
				if ((fuel > 0)&&(!afterburner_engaged))
				{
					[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[fuel-inject-on]") forCount:1.5];
					afterburner_engaged = YES;
					if (!afterburnerSoundLooping)
						[self loopAfterburnerSound];
				}
				else
				{
					if (fuel <= 0.0)
						[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[fuel-out]") forCount:1.5];
				}
				afterburner_engaged = (fuel > 0);
			}
			else
				afterburner_engaged = NO;

			if ((!afterburner_engaged)&&(afterburnerSoundLooping))
				[self stopAfterburnerSound];
			//

#if OOLITE_HAVE_JOYSTICK
		 // DJS: Thrust can be an axis or a button. Axis takes precidence.
         double reqSpeed=[stickHandler getAxisState: AXIS_THRUST];
         if(reqSpeed == STICK_AXISUNASSIGNED || [stickHandler getNumSticks] == 0)
         {
            // DJS: original keyboard code
            if (([gameView isDown:key_increase_speed] || joyButtonState[BUTTON_INCTHRUST])&&(flightSpeed < maxFlightSpeed)&&(!afterburner_engaged))
            {
               if (flightSpeed < maxFlightSpeed)
                  flightSpeed += speed_delta * delta_t;
               if (flightSpeed > maxFlightSpeed)
                  flightSpeed = maxFlightSpeed;
            }
            // if (([gameView isDown:key_decrease_speed])&&(!hyperspeed_engaged)&&(!afterburner_engaged))
            // ** tgape ** - decrease obviously means no hyperspeed
            if (([gameView isDown:key_decrease_speed] || joyButtonState[BUTTON_DECTHRUST])&&(!afterburner_engaged))
            {
               if (flightSpeed > 0.0)
                  flightSpeed -= speed_delta * delta_t;
               if (flightSpeed < 0.0)
                  flightSpeed = 0.0;
               // ** tgape ** - decrease obviously means no hyperspeed
               hyperspeed_engaged = NO;
            }
         } // DJS: STICK_NOFUNCTION else...a joystick axis is assigned to thrust.
         else
         {
            if(flightSpeed < maxFlightSpeed * reqSpeed)
            {
               flightSpeed += speed_delta * delta_t;
            }
            if(flightSpeed > maxFlightSpeed * reqSpeed)
            {
               flightSpeed -= speed_delta * delta_t;
            }
         } // DJS: end joystick thrust axis
#else
		 if (([gameView isDown:key_increase_speed])&&(flightSpeed < maxFlightSpeed)&&(!afterburner_engaged))
		 {
			 if (flightSpeed < maxFlightSpeed)
				 flightSpeed += speed_delta * delta_t;
			 if (flightSpeed > maxFlightSpeed)
				 flightSpeed = maxFlightSpeed;
		 }
		 // ** tgape ** - decrease obviously means no hyperspeed
		 if (([gameView isDown:key_decrease_speed])&&(!afterburner_engaged))
		 {
			 if (flightSpeed > 0.0)
				 flightSpeed -= speed_delta * delta_t;
			 if (flightSpeed < 0.0)
				 flightSpeed = 0.0;
			 // ** tgape ** - decrease obviously means no hyperspeed
			 hyperspeed_engaged = NO;
		 }
#endif

			//
			//  hyperspeed controls
			//

			if ([gameView isDown:key_jumpdrive] || joyButtonState[BUTTON_HYPERSPEED])		// 'j'
			{
				if (!jump_pressed)
				{
					if (!hyperspeed_engaged)
					{
						hyperspeed_locked = [self massLocked];
						hyperspeed_engaged = !hyperspeed_locked;
						if (hyperspeed_locked)
						{
							if (![UNIVERSE playCustomSound:@"[jump-mass-locked]"])
								[self boop];
							[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[jump-mass-locked]") forCount:1.5];
						}
					}
					else
					{
						hyperspeed_engaged = NO;
					}
				}
				jump_pressed = YES;
			}
			else
			{
				jump_pressed = NO;
			}
			//
			//  shoot 'a'
			//
			if ((([gameView isDown:key_fire_lasers])||((mouse_control_on)&&([gameView isDown:gvMouseLeftButton]))||joyButtonState[BUTTON_FIRE])&&(shot_time > weapon_reload_time))

			{
				if ([self fireMainWeapon])
				{
					if (target_laser_hit != NO_TARGET)
					{
						if (weaponHitSound)
						{
							if ([weaponHitSound isPlaying])
								[weaponHitSound stop];
							[weaponHitSound play];
						}
					}
					else
					{
						if (weaponSound)
						{
							if ([weaponSound isPlaying])  [weaponSound stop];
							[weaponSound play];
						}
					}
				}
			}
			//
			//  shoot 'm'   // launch missile
			//
			if ([gameView isDown:key_launch_missile] || joyButtonState[BUTTON_LAUNCHMISSILE])
			{
				// launch here
				if (!fire_missile_pressed)
				{
					BOOL missile_noise = [missile_entity[activeMissile] isMissile];
					if ([self fireMissile])
					{
						if (missile_noise)  [missileSound play];
					}
				}
				fire_missile_pressed = YES;
			}
			else
				fire_missile_pressed = NO;
			//
			//  shoot 'y'   // next missile
			//
			if ([gameView isDown:key_next_missile] || joyButtonState[BUTTON_CYCLEMISSILE])
			{
				if ((!ident_engaged)&&(!next_missile_pressed)&&([self hasExtraEquipment:@"EQ_MULTI_TARGET"]))
				{
					[[UNIVERSE gui] click];
					[self selectNextMissile];
				}
				next_missile_pressed = YES;
			}
			else
				next_missile_pressed = NO;
			//
			//	'+' // next target
			//
			if ([gameView isDown:key_next_target])
			{
				if ((!next_target_pressed)&&([self hasExtraEquipment:@"EQ_TARGET_MEMORY"]))
				{
					if ([self selectNextTargetFromMemory])
						[[UNIVERSE gui] click];
					else
					{
						if (![UNIVERSE playCustomSound:@"[no-target-in-memory]"])
							[self boop];
					}
				}
				next_target_pressed = YES;
			}
			else
				next_target_pressed = NO;
			//
			//	'-' // previous target
			//
			if ([gameView isDown:key_previous_target])
			{
				if ((!previous_target_pressed)&&([self hasExtraEquipment:@"EQ_TARGET_MEMORY"]))
				{
					if ([self selectPreviousTargetFromMemory])
						[[UNIVERSE gui] click];
					else
					{
						if (![UNIVERSE playCustomSound:@"[no-target-in-memory]"])
							[self boop];
					}
				}
				previous_target_pressed = YES;
			}
			else
				previous_target_pressed = NO;
			//
			//  shoot 'r'   // switch on ident system
			//
			if ([gameView isDown:key_ident_system] || joyButtonState[BUTTON_ID])
			{
				// ident 'on' here
				if (!ident_pressed)
				{
					missile_status = MISSILE_STATUS_ARMED;
					primaryTarget = NO_TARGET;
					ident_engaged = YES;
					if (![UNIVERSE playCustomSound:@"[ident-on]"])
						[self beep];
					[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[ident-on]") forCount:2.0];
				}
				ident_pressed = YES;
			}
			else
				ident_pressed = NO;
			//
			//  shoot 't'   // switch on missile targetting
			//
			if (([gameView isDown:key_target_missile] || joyButtonState[BUTTON_ARMMISSILE])&&(missile_entity[activeMissile]))
			{
				// targetting 'on' here
				if (!target_missile_pressed)
				{
					missile_status = MISSILE_STATUS_ARMED;
					if ((ident_engaged) && ([self primaryTarget]))
					{
						if ([missile_entity[activeMissile] isMissile])
						{
							missile_status = MISSILE_STATUS_TARGET_LOCKED;
							[missile_entity[activeMissile] addTarget:[self primaryTarget]];
							[UNIVERSE addMessage:[NSString stringWithFormat:ExpandDescriptionForCurrentSystem(@"[missile-locked-onto-@]"), [(ShipEntity *)[self primaryTarget] identFromShip: self]] forCount:4.5];
							if (![UNIVERSE playCustomSound:@"[missile-locked-on]"])
								[self beep];
						}
					}
					else
					{
						primaryTarget = NO_TARGET;
						if ([missile_entity[activeMissile] isMissile])
						{
							if (missile_entity[activeMissile])
								[missile_entity[activeMissile] removeTarget:nil];
							[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[missile-armed]") forCount:2.0];
							if (![UNIVERSE playCustomSound:@"[missile-armed]"])
								[self beep];
						}
					}
					if ([missile_entity[activeMissile] isMine])
					{
						[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[mine-armed]") forCount:4.5];
						if (![UNIVERSE playCustomSound:@"[mine-armed]"])
							[self beep];
					}
					ident_engaged = NO;
				}
				target_missile_pressed = YES;
			}
			else
				target_missile_pressed = NO;
			//
			//  shoot 'u'   // disarm missile targetting
			//
			if ([gameView isDown:key_untarget_missile] || joyButtonState[BUTTON_UNARM])
			{
				if (!safety_pressed)
				{
					if (!ident_engaged)
					{
						// targetting 'off' here
						missile_status = MISSILE_STATUS_SAFE;
						primaryTarget = NO_TARGET;
						[self safeAllMissiles];
						if (![UNIVERSE playCustomSound:@"[missile-safe]"])
							[self boop];
						[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[missile-safe]") forCount:2.0];
					}
					else
					{
						// targetting 'back on' here
						primaryTarget = [missile_entity[activeMissile] primaryTargetID];
						missile_status = (primaryTarget != NO_TARGET)? MISSILE_STATUS_TARGET_LOCKED : MISSILE_STATUS_SAFE;
						if (![UNIVERSE playCustomSound:@"[ident-off]"])
							[self boop];
						[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[ident-off]") forCount:2.0];
					}
					ident_engaged = NO;
				}
				safety_pressed = YES;
			}
			else
				safety_pressed = NO;
			//
			//  shoot 'e'   // ECM
			//
			if (([gameView isDown:key_ecm] || joyButtonState[BUTTON_ECM])&&(has_ecm))
			{
				if (!ecm_in_operation)
				{
					if ([self fireECM])
					{
						[self playECMSound];
						[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[ecm-on]") forCount:3.0];
					}
				}
			}
			//
			//  shoot 'tab'   // Energy bomb
			//
			if (([gameView isDown:key_energy_bomb] || joyButtonState[BUTTON_ENERGYBOMB])&&(has_energy_bomb))
			{
				// original energy bomb routine
				[self fireEnergyBomb];
				[self removeExtraEquipment:@"EQ_ENERGY_BOMB"];
			}
			//
			//  shoot 'escape'   // Escape pod launch
			//
			if (([gameView isDown:key_launch_escapepod] || joyButtonState[BUTTON_ESCAPE])&&(has_escape_pod)&&([UNIVERSE station]))

			{
				found_target = [self launchEscapeCapsule];
			}
			//
			//  shoot 'd'   // Dump Cargo
			//
			if (([gameView isDown:key_dump_cargo] || joyButtonState[BUTTON_JETTISON])&&([cargo count] > 0))
			{
				if ([self dumpCargo] != CARGO_NOT_CARGO)
				{
					if (![UNIVERSE playCustomSound:@"[cargo-jettisoned]"])
						[self beep];
				}
			}
			//
			//  shoot 'R'   // Rotate Cargo
			//
			if ([gameView isDown:key_rotate_cargo])
			{
				if ((!rotateCargo_pressed)&&([cargo count] > 0))
					[self rotateCargo];
				rotateCargo_pressed = YES;
			}
			else
				rotateCargo_pressed = NO;
			//
			// autopilot 'c'
			//
			if ([gameView isDown:key_autopilot] || joyButtonState[BUTTON_DOCKCPU])   // look for the 'c' key
			{
				if (has_docking_computer && (!autopilot_key_pressed))   // look for the 'c' key
				{
					BOOL isUsingDockingAI = [[shipAI name] isEqual: PLAYER_DOCKING_AI_NAME];
					BOOL isOkayToUseAutopilot = YES;
					//
					if (isUsingDockingAI)
					{
						if ([self checkForAegis] != AEGIS_IN_DOCKING_RANGE)
						{
							isOkayToUseAutopilot = NO;
							if (![UNIVERSE playCustomSound:@"[autopilot-out-of-range]"])
								[self boop];
							[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[autopilot-out-of-range]") forCount:4.5];
						}
					}
					//
					if (isOkayToUseAutopilot)
					{
						primaryTarget = NO_TARGET;
						targetStation = NO_TARGET;
						autopilot_engaged = YES;
						ident_engaged = NO;
						[self safeAllMissiles];
						velocity = kZeroVector;
						status = STATUS_AUTOPILOT_ENGAGED;
						[shipAI setState:@"GLOBAL"];	// reboot the AI
						if (![UNIVERSE playCustomSound:@"[autopilot-on]"])
							[self beep];
						[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[autopilot-on]") forCount:4.5];
						[self doScriptEvent:@"didStartAutoPilot"];
						//
						if (ootunes_on)
						{
							// ootunes - play docking music
							[[UNIVERSE gameController] playiTunesPlaylist:@"Oolite-Docking"];
							docking_music_on = NO;
						}
						//
						if (afterburner_engaged)
						{
							afterburner_engaged = NO;
							if (afterburnerSoundLooping)
								[self stopAfterburnerSound];
						}
					}
					//
				}
				autopilot_key_pressed = YES;
			}
			else
				autopilot_key_pressed = NO;
			//
			// autopilot 'C' - dock with target
			//
			if ([gameView isDown:key_autopilot_target])   // look for the 'C' key
			{
				if (has_docking_computer && (!target_autopilot_key_pressed))
				{
					Entity* primeTarget = [self primaryTarget];
					if ((primeTarget)&&(primeTarget->isStation)&&[primeTarget isKindOfClass:[StationEntity class]])
					{
						targetStation = primaryTarget;
						primaryTarget = NO_TARGET;
						autopilot_engaged = YES;
						ident_engaged = NO;
						[self safeAllMissiles];
						velocity = kZeroVector;
						status = STATUS_AUTOPILOT_ENGAGED;
						[shipAI setState:@"GLOBAL"];	// restart the AI
						if (![UNIVERSE playCustomSound:@"[autopilot-on]"])
							[self beep];
						[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[autopilot-on]") forCount:4.5];
						[self doScriptEvent:@"didStartAutoPilot"];
						//
						if (ootunes_on)
						{
							// ootunes - play docking music
							[[UNIVERSE gameController] playiTunesPlaylist:@"Oolite-Docking"];
							docking_music_on = NO;
						}
						//
						if (afterburner_engaged)
						{
							afterburner_engaged = NO;
							if (afterburnerSoundLooping)
								[self stopAfterburnerSound];
						}
					}
					else
					{
						if (![UNIVERSE playCustomSound:@"[autopilot-cannot-dock-with-target]"])
							[self boop];
						[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"Target is not capable of autopilot-docking") forCount:4.5];
					}
				}
				target_autopilot_key_pressed = YES;
			}
			else
				target_autopilot_key_pressed = NO;
			//
			// autopilot 'D'
			//
			if ([gameView isDown:key_autodock] || joyButtonState[BUTTON_DOCKCPUFAST])   // look for the 'D' key
			{
				if (has_docking_computer && (!fast_autopilot_key_pressed))   // look for the 'D' key
				{
					if ([self checkForAegis] == AEGIS_IN_DOCKING_RANGE)
					{
						StationEntity *the_station = [UNIVERSE station];
						if (the_station)
						{
							if (legalStatus > 50)
							{
								status = STATUS_AUTOPILOT_ENGAGED;
								[self interpretAIMessage:@"DOCKING_REFUSED"];
							}
							else
							{
								if (legalStatus > 0)
								{
									// there's a slight chance you'll be fined for your past offences when autodocking
									//
									int fine_chance = ranrot_rand() & 0x03ff;	//	0..1023
									int government = 1 + [(NSNumber *)[[UNIVERSE currentSystemData] objectForKey:KEY_GOVERNMENT] intValue];	// 1..8
									fine_chance /= government;
									if (fine_chance < legalStatus)
										[self markForFines];
								}
								ship_clock_adjust = 1200.0;			// 20 minutes penalty to enter dock
								ident_engaged = NO;
								[self safeAllMissiles];
								[UNIVERSE setViewDirection:VIEW_FORWARD];
								[self enterDock:the_station];
							}
						}
					}
					else
					{
						if (![UNIVERSE playCustomSound:@"[autopilot-out-of-range]"])
							[self boop];
						[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[autopilot-out-of-range]") forCount:4.5];
					}
				}
				fast_autopilot_key_pressed = YES;
			}
			else
				fast_autopilot_key_pressed = NO;
			//
			// hyperspace 'h'
			//
			if ([gameView isDown:key_hyperspace] || joyButtonState[BUTTON_HYPERDRIVE])   // look for the 'h' key
			{
				if (!hyperspace_pressed)
				{
					float			dx = target_system_seed.d - galaxy_coordinates.x;
					float			dy = target_system_seed.b - galaxy_coordinates.y;
					double		distance = distanceBetweenPlanetPositions(target_system_seed.d,target_system_seed.b,galaxy_coordinates.x,galaxy_coordinates.y);
					BOOL		jumpOK = YES;

					if ((dx == 0) && (dy == 0) && equal_seeds(target_system_seed, system_seed))
					{
						if (![UNIVERSE playCustomSound:@"[witch-no-target]"])
							[self boop];
						[UNIVERSE clearPreviousMessage];
						[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[witch-no-target]") forCount:3.0];
						jumpOK = NO;
					}

					if ((10.0 * distance > fuel)||(fuel == 0))
					{
						if (![UNIVERSE playCustomSound:@"[witch-no-fuel]"])
							[self boop];
						[UNIVERSE clearPreviousMessage];
						[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[witch-no-fuel]") forCount:3.0];
						jumpOK = NO;
					}

					if (status == STATUS_WITCHSPACE_COUNTDOWN)
					{
						// abort!
						if (galactic_witchjump)
							[UNIVERSE stopCustomSound:@"[galactic-hyperspace-countdown-begun]"];
						else
							[UNIVERSE stopCustomSound:@"[hyperspace-countdown-begun]"];
						jumpOK = NO;
						galactic_witchjump = NO;
						status = STATUS_IN_FLIGHT;
						if (![UNIVERSE playCustomSound:@"[hyperspace-countdown-aborted]"])
							[self boop];
						// say it!
						[UNIVERSE clearPreviousMessage];
						[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[witch-user-abort]") forCount:3.0];
						
						[self doScriptEvent:@"didCancelJumpCountDown"];
					}

					if (jumpOK)
					{
						galactic_witchjump = NO;
						witchspaceCountdown = 15.0;
						status = STATUS_WITCHSPACE_COUNTDOWN;
						if (![UNIVERSE playCustomSound:@"[hyperspace-countdown-begun]"])
							[self beep];
						// say it!
						[UNIVERSE clearPreviousMessage];
						[UNIVERSE addMessage:[NSString stringWithFormat:ExpandDescriptionForCurrentSystem(@"[witch-to-@-in-f-seconds]"), [UNIVERSE getSystemName:target_system_seed], witchspaceCountdown] forCount:1.0];
						
						[self doScriptEvent:@"didBeginJumpCountDown" withArgument:@"standard"];
					}
				}
				hyperspace_pressed = YES;
			}
			else
				hyperspace_pressed = NO;
			//
			// Galactic hyperspace 'g'
			//
			if (([gameView isDown:key_galactic_hyperspace] || joyButtonState[BUTTON_GALACTICDRIVE])&&(has_galactic_hyperdrive))// look for the 'g' key
			{
				if (!galhyperspace_pressed)
				{
					BOOL	jumpOK = YES;

					if (status == STATUS_WITCHSPACE_COUNTDOWN)
					{
						// abort!
						if (galactic_witchjump)
							[UNIVERSE stopCustomSound:@"[galactic-hyperspace-countdown-begun]"];
						else
							[UNIVERSE stopCustomSound:@"[hyperspace-countdown-begun]"];
						jumpOK = NO;
						galactic_witchjump = NO;
						status = STATUS_IN_FLIGHT;
						if (![UNIVERSE playCustomSound:@"[hyperspace-countdown-aborted]"])
							[self boop];
						// say it!
						[UNIVERSE clearPreviousMessage];
						[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[witch-user-abort]") forCount:3.0];
						
						[self doScriptEvent:@"didCancelJumpCountDown"];
					}

					if (jumpOK)
					{
						galactic_witchjump = YES;
						witchspaceCountdown = 15.0;
						status = STATUS_WITCHSPACE_COUNTDOWN;
						if (![UNIVERSE playCustomSound:@"[galactic-hyperspace-countdown-begun]"])
							if (![UNIVERSE playCustomSound:@"[hyperspace-countdown-begun]"])
								[self beep];
						// say it!
						[UNIVERSE addMessage:[NSString stringWithFormat:ExpandDescriptionForCurrentSystem(@"[witch-galactic-in-f-seconds]"), witchspaceCountdown] forCount:1.0];
						
						[self doScriptEvent:@"didBeginJumpCountDown" withArgument:@"galactic"];
					}
				}
				galhyperspace_pressed = YES;
			}
			else
				galhyperspace_pressed = NO;
					//
			//  shoot '0'   // Cloaking Device
			//
			if (([gameView isDown:key_cloaking_device] || joyButtonState[BUTTON_CLOAK]) && has_cloaking_device)
			{
				if (!cloak_pressed)
				{
					if (!cloaking_device_active)
					{
						if ([self activateCloakingDevice])
							[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[cloak-on]") forCount:2];
						else
							[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[cloak-low-juice]") forCount:3];
					}
					else
					{
						[self deactivateCloakingDevice];
						[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[cloak-off]") forCount:2];
					}
					//
					if (cloaking_device_active)
					{
						if (![UNIVERSE playCustomSound:@"[cloaking-device-on]"])
							[self beep];
					}
					else
					{
						if (![UNIVERSE playCustomSound:@"[cloaking-device-off]"])
							[self boop];
					}
				}
				cloak_pressed = YES;
			}
			else
				cloak_pressed = NO;

		}
		
#ifndef NDEBUG
		if ([gameView isDown:key_dump_target_state])
		{
			if (!dump_target_state_pressed)
			{
				dump_target_state_pressed = YES;
				id target = [self primaryTarget];
				if (target == nil)	target = self;
				[target dumpState];
			}
		}
		else  dump_target_state_pressed = NO;
#endif

		//
		//  text displays
		//
		[self pollGuiScreenControls];
	}
	else
	{
		// game is paused

		// check options menu request
		if ((([gameView isDown:gvFunctionKey2])||([gameView isDown:gvNumberKey2]))&&(gui_screen != GUI_SCREEN_OPTIONS))
		{
			[gameView clearKeys];
			[self setGuiToLoadSaveScreen];
		}
		
		if (gui_screen == GUI_SCREEN_OPTIONS || gui_screen == GUI_SCREEN_GAMEOPTIONS || gui_screen == GUI_SCREEN_STICKMAPPER)
		{
			NSTimeInterval	time_this_frame = [NSDate timeIntervalSinceReferenceDate];
			OOTimeDelta		time_delta;
			if (![[GameController sharedController] gameIsPaused])
			{
				time_delta = time_this_frame - time_last_frame;
				time_last_frame = time_this_frame;
				time_delta = OOClamp_0_max_d(time_delta, MINIMUM_GAME_TICK);
			}
			else
			{
				time_delta = 0.0;
			}
			
			script_time += time_delta;
			[self pollGuiArrowKeyControls:time_delta];
		}

#ifndef NDEBUG
		// look for debugging keys
		if ([gameView isDown:48])// look for the '0' key
		{
			if (!cloak_pressed)
			{
				[UNIVERSE obj_dump];	// dump objects
				gDebugFlags = 0;
				[UNIVERSE addMessage:@"Entity List dumped. Debugging OFF" forCount:3];
			}
			cloak_pressed = YES;
		}
		else
			cloak_pressed = NO;
		
		// look for debugging keys
		if ([gameView isDown:'d'])// look for the 'd' key
		{
			gDebugFlags = DEBUG_ALL;
			[UNIVERSE addMessage:@"Full debug ON" forCount:3];
		}
		
		if ([gameView isDown:'b'])// look for the 'b' key
		{
			gDebugFlags |= DEBUG_COLLISIONS;
			[UNIVERSE addMessage:@"Collision debug ON" forCount:3];
		}
		
		if ([gameView isDown:'x'])// look for the 'x' key
		{
			gDebugFlags |= DEBUG_BOUNDING_BOXES;
			[UNIVERSE addMessage:@"Bounding box debug ON" forCount:3];
		}
		
		if ([gameView isDown:'c'])// look for the 'c' key
		{
			gDebugFlags |= DEBUG_OCTREE;
			[UNIVERSE addMessage:@"Octree debug ON" forCount:3];
		}
		
#if 0		
		// Disabled - Wireframe graphics has been implemented as game option.
		if ([gameView isDown:'w'])
		{
			gDebugFlags |= DEBUG_WIREFRAME_GRAPHICS;
			[UNIVERSE addMessage:@"Wireframe graphics ON" forCount:3];
		}
#endif

#endif
#ifdef ALLOW_PROCEDURAL_PLANETS
		if ([gameView isDown:'t'])// look for the 't' key
		{
			[UNIVERSE setDoProcedurallyTexturedPlanets: YES];
			[UNIVERSE addMessage:@"Procedural Textures On" forCount:3];
		}
#endif
		
		if ([gameView isDown:'s'])// look for the 's' key
		{
			OOLogSetDisplayMessagesInClass(@"$shaderDebugOn", YES);
			[UNIVERSE addMessage:@"Shader debug ON" forCount:3];
		}
		
		if ([gameView isDown:'n'])// look for the 'n' key
		{
#ifndef NDEBUG
			gDebugFlags = 0;
			[UNIVERSE addMessage:@"All debug flags OFF" forCount:3];
#else
			[UNIVERSE addMessage:@"Procedural textures OFF" forCount:3];
#endif
			OOLogSetDisplayMessagesInClass(@"$shaderDebugOn", NO);
#ifdef ALLOW_PROCEDURAL_PLANETS
			[UNIVERSE setDoProcedurallyTexturedPlanets: NO];
#endif	// ALLOW_PROCEDURAL_PLANETS
		}
	}
	//
	// Pause game 'p'
	//
	if ([gameView isDown:key_pausebutton])// look for the 'p' key
	{
		if (!pause_pressed)
		{
			if (paused)
			{
				script_time = saved_script_time;
				gui_screen = GUI_SCREEN_MAIN;
				[gameView allowStringInput:NO];
				[UNIVERSE setDisplayCursor:NO];
				[UNIVERSE clearPreviousMessage];
				[UNIVERSE setViewDirection:saved_view_direction];
				[[gameView gameController] unpause_game];
			}
			else
			{
				saved_view_direction = [UNIVERSE viewDirection];
				saved_script_time = script_time;
				[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[game-paused]") forCount:1.0];
				[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[game-paused-options]") forCount:1.0];
				[[gameView gameController] pause_game];
			}
		}
		pause_pressed = YES;
	}
	else
	{
		pause_pressed = NO;
	}
	//
	//
	//
}

static  BOOL	f_key_pressed;
static  BOOL	m_key_pressed;
static  BOOL	taking_snapshot;
- (void) pollApplicationControls
{
   if(!pollControls)
      return;

	// does fullscreen / quit / snapshot
	//
	MyOpenGLView  *gameView = (MyOpenGLView *)[UNIVERSE gameView];
	//
	//  command-key controls
	//
	if (([gameView isCommandDown])&&([[gameView gameController] inFullScreenMode]))
	{
		if (([gameView isCommandDown])&&([gameView isDown:102]))   //  command f
		{
			[[gameView gameController] exitFullScreenMode];
			if (mouse_control_on)
				[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[mouse-off]") forCount:3.0];
			mouse_control_on = NO;
		}
		//
		if (([gameView isCommandDown])&&([gameView isDown:113]))   //  command q
		{
			[[gameView gameController] pauseFullScreenModeToPerform:@selector(exitApp) onTarget:[gameView gameController]];
		}
	}

#if OOLITE_WINDOWS
	if ( ([gameView isDown:'Q']) )
	{
		  [[gameView gameController] exitApp];
		  exit(0); // Force it
	}
#endif

	//
	// handle pressing Q or [esc] in error-handling mode
	//
	if (status == STATUS_HANDLING_ERROR)
	{
		if ([gameView isDown:113]||[gameView isDown:81]||[gameView isDown:27])   // 'q' | 'Q' | esc
		{
			[[gameView gameController] exitApp];
		}
	}

#ifndef NDEBUG
	//
	// dread debugging keypress of fear
	//
	if ([gameView isDown: 64])   // '@'
	{
		OOLog(@"debug.atKey", @"%@ status==%@ guiscreen==%@", self, [self status_string], [self gui_screen_string]);
	}
#endif

	//
	//  snapshot
	//
	if ([gameView isDown:key_snapshot])   //  '*' key
	{
		if (!taking_snapshot)
		{
			taking_snapshot = YES;
			[gameView snapShot];
		}
	}
	else
	{
		taking_snapshot = NO;
	}
	//
	// FPS display
	//
	if ([gameView isDown:key_show_fps])   //  'F' key
	{
		if (!f_key_pressed)
			[UNIVERSE setDisplayFPS:![UNIVERSE displayFPS]];
		f_key_pressed = YES;
	}
	else
	{
		f_key_pressed = NO;
	}
	//
	// Mouse control
	//
	BOOL allowMouseControl;
#if OO_DEBUG
	allowMouseControl = YES;
#else
	allowMouseControl = [[gameView gameController] inFullScreenMode];
#endif
	if (allowMouseControl)
	{
		if ([gameView isDown:key_mouse_control])   //  'M' key
		{
			if (!m_key_pressed)
			{
				mouse_control_on = !mouse_control_on;
				if (mouse_control_on)
				{
					[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[mouse-on]") forCount:3.0];
					// ensure the keyboard pitch override (intended to lock out the joystick if the
					// player runs to the keyboard) is reset
					keyboardRollPitchOverride = NO;
				}
				else
					[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[mouse-off]") forCount:3.0];
			}
			m_key_pressed = YES;
		}
		else
		{
			m_key_pressed = NO;
		}
	}
}


- (void) pollFlightArrowKeyControls:(double) delta_t
{
	MyOpenGLView	*gameView = [UNIVERSE gameView];
	NSPoint			virtualStick = NSZeroPoint;
	#define			kDeadZone 0.02
	
	// TODO: Rework who owns the stick.
	if(!stickHandler)
	{
		stickHandler=[gameView getStickHandler];
	}
	numSticks=[stickHandler getNumSticks];
	
	// DJS: Handle inputs on the joy roll/pitch axis.
	// Mouse control on takes precidence over joysticks.
	// We have to assume the player has a reason for switching mouse
	// control on if they have a joystick - let them do it.
	if(mouse_control_on)
	{
		virtualStick=[gameView virtualJoystickPosition];
		double sensitivity = 2.0;
		virtualStick.x *= sensitivity;
		virtualStick.y *= sensitivity;
	}
	else if(numSticks)
	{
		virtualStick=[stickHandler getRollPitchAxis];
		if(virtualStick.x == STICK_AXISUNASSIGNED ||
		   virtualStick.y == STICK_AXISUNASSIGNED)
		{
			// Not assigned - set to zero.
			virtualStick.x=0;
			virtualStick.y=0;
		}
		else if(virtualStick.x != 0 ||
				virtualStick.y != 0)
		{
			// cancel keyboard override, stick has been waggled
			keyboardRollPitchOverride=NO;
		}
	}
	
	double roll_dampner = ROLL_DAMPING_FACTOR * delta_t;
	double pitch_dampner = PITCH_DAMPING_FACTOR * delta_t;
	double yaw_dampner = PITCH_DAMPING_FACTOR * delta_t;
	
	rolling = NO;
	if (!mouse_control_on )
	{
		if ([gameView isDown:key_roll_left])
		{
			keyboardRollPitchOverride=YES;
			if (flightRoll > 0.0)  flightRoll = 0.0;
			[self decrease_flight_roll:delta_t*roll_delta];
			rolling = YES;
		}
		if ([gameView isDown:key_roll_right])
		{
			keyboardRollPitchOverride=YES;
			if (flightRoll < 0.0)  flightRoll = 0.0;
			[self increase_flight_roll:delta_t*roll_delta];
			rolling = YES;
		}
	}
	if((mouse_control_on || numSticks) && !keyboardRollPitchOverride)
	{
		double stick_roll = max_flight_roll * virtualStick.x;
		if (flightRoll < stick_roll)
		{
			[self increase_flight_roll:delta_t*roll_delta];
			if (flightRoll > stick_roll)
				flightRoll = stick_roll;
		}
		if (flightRoll > stick_roll)
		{
			[self decrease_flight_roll:delta_t*roll_delta];
			if (flightRoll < stick_roll)
				flightRoll = stick_roll;
		}
		rolling = (abs(virtualStick.x) > kDeadZone);
	}
	if (!rolling)
	{
		if (flightRoll > 0.0)
		{
			if (flightRoll > roll_dampner)	[self decrease_flight_roll:roll_dampner];
			else	flightRoll = 0.0;
		}
		if (flightRoll < 0.0)
		{
			if (flightRoll < -roll_dampner)   [self increase_flight_roll:roll_dampner];
			else	flightRoll = 0.0;
		}
	}
	
	pitching = NO;
	if (!mouse_control_on)
	{
		if ([gameView isDown:key_pitch_back])
		{
			keyboardRollPitchOverride=YES;
			if (flightPitch < 0.0)  flightPitch = 0.0;
			[self increase_flight_pitch:delta_t*pitch_delta];
			pitching = YES;
		}
		if ([gameView isDown:key_pitch_forward])
		{
			keyboardRollPitchOverride=YES;
			if (flightPitch > 0.0)  flightPitch = 0.0;
			[self decrease_flight_pitch:delta_t*pitch_delta];
			pitching = YES;
		}
	}
	if((mouse_control_on || numSticks) && !keyboardRollPitchOverride)
	{
		double stick_pitch = max_flight_pitch * virtualStick.y;
		if (flightPitch < stick_pitch)
		{
			[self increase_flight_pitch:delta_t*roll_delta];
			if (flightPitch > stick_pitch)
				flightPitch = stick_pitch;
		}
		if (flightPitch > stick_pitch)
		{
			[self decrease_flight_pitch:delta_t*roll_delta];
			if (flightPitch < stick_pitch)
				flightPitch = stick_pitch;
		}
		pitching = (abs(virtualStick.x) > kDeadZone);
	}
	if (!pitching)
	{
		if (flightPitch > 0.0)
		{
			if (flightPitch > pitch_dampner)	[self decrease_flight_pitch:pitch_dampner];
			else	flightPitch = 0.0;
		}
		if (flightPitch < 0.0)
		{
			if (flightPitch < -pitch_dampner)	[self increase_flight_pitch:pitch_dampner];
			else	flightPitch = 0.0;
		}
	}
	
	if (![UNIVERSE strict])
	{
		yawing = NO;
		if ([gameView isDown:key_yaw_left])
		{
			if (flightYaw < 0.0)  flightYaw = 0.0;
			[self increase_flight_yaw:delta_t*yaw_delta];
			yawing = YES;
		}
		else if ([gameView isDown:key_yaw_right])
		{
			if (flightYaw > 0.0)  flightYaw = 0.0;
			[self decrease_flight_yaw:delta_t*yaw_delta];
			yawing = YES;
		}
		if (!yawing)
		{
			if (flightYaw > 0.0)
			{
				if (flightYaw > yaw_dampner)	[self decrease_flight_yaw:yaw_dampner];
				else	flightYaw = 0.0;
			}
			if (flightYaw < 0.0)
			{
				if (flightYaw < -yaw_dampner)   [self increase_flight_yaw:yaw_dampner];
				else	flightYaw = 0.0;
			}
		}
	}
}


static BOOL			pling_pressed;
static BOOL			cursor_moving;
static BOOL			disc_operation_in_progress;
static BOOL			switching_resolution;
static BOOL			wait_for_key_up;
static unsigned		searchStringLength;
static double		timeLastKeyPress;
static BOOL			upDownKeyPressed;
static BOOL			leftRightKeyPressed;
static BOOL			enterSelectKeyPressed;
static BOOL			volumeControlPressed;
static BOOL			shaderSelectKeyPressed;
static OOGUIRow		oldSelection;
static BOOL			selectPressed;
static BOOL			queryPressed;
static BOOL			spacePressed;

// DJS + aegidian : Moved from the big switch/case block in pollGuiArrowKeyControls
- (BOOL) handleGUIUpDownArrowKeys
         : (GuiDisplayGen *)gui
         : (MyOpenGLView *)gameView
{
	BOOL result = NO;
	BOOL arrow_up = [gameView isDown:gvArrowKeyUp];
	BOOL arrow_down = [gameView isDown:gvArrowKeyDown];
	BOOL mouse_click = [gameView isDown:gvMouseLeftButton];
	//
	if (arrow_down)
	{
		if ((!upDownKeyPressed) || (script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
		{
		   if ([gui setNextRow: +1])
			{
				[gui click];
				result = YES;
			}
			timeLastKeyPress = script_time;
		}
	}
	//
	if (arrow_up)
	{
		if ((!upDownKeyPressed) || (script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
		{
			if ([gui setNextRow: -1])
			{
				[gui click];
				result = YES;
			}
			timeLastKeyPress = script_time;
		}
	}
	//
	if (mouse_click)
	{
		if (!upDownKeyPressed)
		{
			int click_row = 0;
			if (UNIVERSE)
				click_row = UNIVERSE->cursor_row;
			if ([gui setSelectedRow:click_row])
			{
				result = YES;
			}
		}
	}
	//
	upDownKeyPressed = (arrow_up || arrow_down || mouse_click);
	//
	return result;
}

- (void) pollGuiArrowKeyControls:(double) delta_t
{
	MyOpenGLView*	gameView = (MyOpenGLView *)[UNIVERSE gameView];
	BOOL			moving = NO;
	double			cursor_speed = 10.0;
	GuiDisplayGen*  gui = [UNIVERSE gui];
	NSString*		commanderFile;

	// deal with string inputs as necessary
	if (gui_screen == GUI_SCREEN_LONG_RANGE_CHART)
		[gameView setStringInput: gvStringInputAlpha];
	else if (gui_screen == GUI_SCREEN_SAVE)
		[gameView setStringInput: gvStringInputAll];
	else
		[gameView allowStringInput: NO];

	switch (gui_screen)
	{
		case	GUI_SCREEN_LONG_RANGE_CHART :
			if ([gameView isDown:key_advanced_nav_array])   //  '^' key
			{
				if (!pling_pressed)
				{
					if ([self hasExtraEquipment:@"EQ_ADVANCED_NAVIGATIONAL_ARRAY"])  [gui setShowAdvancedNavArray:YES];
					pling_pressed = YES;
				}
			}
			else
			{
				if (pling_pressed)
				{
					[gui setShowAdvancedNavArray:NO];
					pling_pressed = NO;
				}
			}
			if ([[gameView typedString] length])
			{
				planetSearchString = [gameView typedString];
				NSPoint search_coords = [UNIVERSE findSystemCoordinatesWithPrefix:planetSearchString withGalaxySeed:galaxy_seed];
				if ((search_coords.x >= 0.0)&&(search_coords.y >= 0.0))
				{
					moving = ((cursor_coordinates.x != search_coords.x)||(cursor_coordinates.y != search_coords.y));
					cursor_coordinates = search_coords;
				}
				else
				{
					[gameView resetTypedString];
				}
			}
			else
			{
				planetSearchString = nil;
			}
			//
			moving |= (searchStringLength != [[gameView typedString] length]);
			searchStringLength = [[gameView typedString] length];
			//
		case	GUI_SCREEN_SHORT_RANGE_CHART :
			//
			show_info_flag = ([gameView isDown:key_map_info] && ![UNIVERSE strict]);
			//
			if (status != STATUS_WITCHSPACE_COUNTDOWN)
			{
				if ([gameView isDown:gvMouseLeftButton])
				{
					NSPoint maus = [gameView virtualJoystickPosition];
					if (gui_screen == GUI_SCREEN_SHORT_RANGE_CHART)
					{
						double		vadjust = 51;
						double		hscale = 4.0 * MAIN_GUI_PIXEL_WIDTH / 256.0;
						double		vscale = 4.0 * MAIN_GUI_PIXEL_HEIGHT / 512.0;
						cursor_coordinates.x = galaxy_coordinates.x + (maus.x * MAIN_GUI_PIXEL_WIDTH) / hscale;
						cursor_coordinates.y = galaxy_coordinates.y + (maus.y * MAIN_GUI_PIXEL_HEIGHT + vadjust) / vscale;
					}
					if (gui_screen == GUI_SCREEN_LONG_RANGE_CHART)
					{
						double		vadjust = 211;
						double		hadjust = MAIN_GUI_PIXEL_WIDTH / 2.0;
						double		hscale = MAIN_GUI_PIXEL_WIDTH / 256.0;
						double		vscale = MAIN_GUI_PIXEL_HEIGHT / 512.0;
						cursor_coordinates.x = (maus.x * MAIN_GUI_PIXEL_WIDTH + hadjust)/ hscale;
						cursor_coordinates.y = (maus.y * MAIN_GUI_PIXEL_HEIGHT + vadjust) / vscale;
					}
					[gameView resetTypedString];
					moving = YES;
				}
				if ([gameView isDown:gvMouseDoubleClick])
				{
					[gameView clearMouse];
					[self setGuiToSystemDataScreen];
					[self checkScript];
				}
				if ([gameView isDown:key_map_home])
				{
					[gameView resetTypedString];
					cursor_coordinates = galaxy_coordinates;
					moving = YES;
				}
				if ([gameView isDown:gvArrowKeyLeft])
				{
					[gameView resetTypedString];
					cursor_coordinates.x -= cursor_speed*delta_t;
					if (cursor_coordinates.x < 0.0) cursor_coordinates.x = 0.0;
					moving = YES;
				}
				if ([gameView isDown:gvArrowKeyRight])
				{
					[gameView resetTypedString];
					cursor_coordinates.x += cursor_speed*delta_t;
					if (cursor_coordinates.x > 256.0) cursor_coordinates.x = 256.0;
					moving = YES;
				}
				if ([gameView isDown:gvArrowKeyDown])
				{
					[gameView resetTypedString];
					cursor_coordinates.y += cursor_speed*delta_t*2.0;
					if (cursor_coordinates.y > 256.0) cursor_coordinates.y = 256.0;
					moving = YES;
				}
				if ([gameView isDown:gvArrowKeyUp])
					{
					[gameView resetTypedString];
					cursor_coordinates.y -= cursor_speed*delta_t*2.0;
					if (cursor_coordinates.y < 0.0) cursor_coordinates.y = 0.0;
					moving = YES;
				}
				if ((cursor_moving)&&(!moving))
				{
					target_system_seed = [UNIVERSE findSystemAtCoords:cursor_coordinates withGalaxySeed:galaxy_seed];
					cursor_coordinates.x = target_system_seed.d;
					cursor_coordinates.y = target_system_seed.b;
					if (gui_screen == GUI_SCREEN_LONG_RANGE_CHART) [self setGuiToLongRangeChartScreen];
					if (gui_screen == GUI_SCREEN_SHORT_RANGE_CHART) [self setGuiToShortRangeChartScreen];
				}
				cursor_moving = moving;
				if ((cursor_moving)&&(gui_screen == GUI_SCREEN_LONG_RANGE_CHART)) [self setGuiToLongRangeChartScreen]; // update graphics
				if ((cursor_moving)&&(gui_screen == GUI_SCREEN_SHORT_RANGE_CHART)) [self setGuiToShortRangeChartScreen]; // update graphics
			}
			//
		case	GUI_SCREEN_SYSTEM_DATA :
			//
			if ((status == STATUS_DOCKED)&&([gameView isDown:key_contract_info]))  // '?' toggle between maps/info and contract screen
			{
				if (!queryPressed)
				{
					[self setGuiToContractsScreen];
					if ((oldSelection >= (int)[gui selectableRange].location)&&(oldSelection < (int)[gui selectableRange].location + (int)[gui selectableRange].length))
						[gui setSelectedRow:oldSelection];
					[self setGuiToContractsScreen];
				}
				queryPressed = YES;
			}
			else
				queryPressed = NO;
			break;

      // DJS: Farm off load/save screen options to LoadSave.m
			case GUI_SCREEN_LOAD:
				commanderFile = [self commanderSelector: gui :gameView];
				if(commanderFile)
				{
					[self loadPlayerFromFile:commanderFile];
					[self setGuiToStatusScreen];
				}
				break;
			case GUI_SCREEN_SAVE:
				[self saveCommanderInputHandler: gui :gameView];
				break;
			case GUI_SCREEN_SAVE_OVERWRITE:
				[self overwriteCommanderInputHandler: gui :gameView];
				break;

#if OOLITE_HAVE_JOYSTICK
		case GUI_SCREEN_STICKMAPPER:
			[self stickMapperInputHandler: gui view: gameView];
			break;
#endif


		case	GUI_SCREEN_GAMEOPTIONS:
			{
				int wireframe_row =	GUI_ROW_GAMEOPTIONS_WIREFRAMEGRAPHICS;
				int detail_row =	GUI_ROW_GAMEOPTIONS_DETAIL;
				int shaderfx_row = 	GUI_ROW_GAMEOPTIONS_SHADEREFFECTS;
				int back_row = GUI_ROW_GAMEOPTIONS_BACK;
#if OOLITE_SDL
				int display_style_row = GUI_ROW_GAMEOPTIONS_DISPLAYSTYLE;
				int stickmap_row = GUI_ROW_GAMEOPTIONS_STICKMAPPER;
#endif
#if OOLITE_MAC_OS_X
				// Macintosh only
				int ootunes_row =	GUI_ROW_GAMEOPTIONS_OOTUNES;
				int speech_row =	GUI_ROW_GAMEOPTIONS_SPEECH;
				int growl_row =		GUI_ROW_GAMEOPTIONS_GROWL;
#endif
				int volume_row = GUI_ROW_GAMEOPTIONS_VOLUME;
				int display_row =   GUI_ROW_GAMEOPTIONS_DISPLAY;

				GameController  *controller = [UNIVERSE gameController];
				NSArray *modes = [controller displayModes];

				[self handleGUIUpDownArrowKeys: gui :gameView];
				BOOL selectKeyPress = ([gameView isDown:13]||[gameView isDown:gvMouseDoubleClick]);
				if ([gameView isDown:gvMouseDoubleClick])
					[gameView clearMouse];
				
#if OOLITE_HAVE_JOYSTICK
				if (([gui selectedRow] == stickmap_row) && selectKeyPress)
				{
					[self setGuiToStickMapperScreen];
				}
#endif

				if (([gui selectedRow] == display_row)&&(([gameView isDown:gvArrowKeyRight])||([gameView isDown:gvArrowKeyLeft]))&&(!switching_resolution))
				{
					int direction = ([gameView isDown:gvArrowKeyRight]) ? 1 : -1;
					int displayModeIndex = [controller indexOfCurrentDisplayMode];
					if (displayModeIndex == NSNotFound)
					{
						OOLog(@"graphics.mode.notFound", @"***** couldn't find current display mode switching to basic 640x480");
						displayModeIndex = 0;
					}
					else
					{
						displayModeIndex = displayModeIndex + direction;
						int count = [modes count];
						if (displayModeIndex < 0)
							displayModeIndex = count - 1;
						if (displayModeIndex >= count)
							displayModeIndex = 0;
					}
					NSDictionary	*mode = [modes objectAtIndex:displayModeIndex];
					int modeWidth = [mode intForKey:kOODisplayWidth];
					int modeHeight = [mode intForKey:kOODisplayHeight];
					int modeRefresh = [mode intForKey:kOODisplayRefreshRate];
					[controller setDisplayWidth:modeWidth Height:modeHeight Refresh:modeRefresh];
#if OOLITE_SDL
					// TODO: The gameView for the SDL game currently holds and
					// sets the actual screen resolution (controller just stores
					// it). This probably ought to change.
					[gameView setScreenSize: displayModeIndex];
#endif
					NSString *displayModeString = [self screenModeStringForWidth:modeWidth height:modeHeight refreshRate:modeRefresh];

					[gui click];
					{
						GuiDisplayGen* gui = [UNIVERSE gui];
						int display_row =   GUI_ROW_GAMEOPTIONS_DISPLAY;
						[gui setText:displayModeString	forRow:display_row  align:GUI_ALIGN_CENTER];
					}
					switching_resolution = YES;
				}
				if ((![gameView isDown:gvArrowKeyRight])&&(![gameView isDown:gvArrowKeyLeft])&&(!selectKeyPress))
					switching_resolution = NO;

#if OOLITE_MAC_OS_X
				if (([gui selectedRow] == speech_row)&&(([gameView isDown:gvArrowKeyRight])||([gameView isDown:gvArrowKeyLeft])))
				{
					GuiDisplayGen* gui = [UNIVERSE gui];
					if ([gameView isDown:gvArrowKeyRight] != isSpeechOn)
						[gui click];
					isSpeechOn = [gameView isDown:gvArrowKeyRight];
					if (isSpeechOn)
						[gui setText:@" Spoken Messages: YES "	forRow:speech_row  align:GUI_ALIGN_CENTER];
					else
						[gui setText:@" Spoken Messages: NO "	forRow:speech_row  align:GUI_ALIGN_CENTER];
				}


				if (([gui selectedRow] == ootunes_row)&&(([gameView isDown:gvArrowKeyRight])||([gameView isDown:gvArrowKeyLeft])))
				{
					GuiDisplayGen* gui = [UNIVERSE gui];
					if ([gameView isDown:gvArrowKeyRight] != ootunes_on)
						[gui click];
					ootunes_on = [gameView isDown:gvArrowKeyRight];
					if (ootunes_on)
						[gui setText:@" iTunes Integration: YES "	forRow:ootunes_row  align:GUI_ALIGN_CENTER];
					else
						[gui setText:@" iTunes Integration: NO "	forRow:ootunes_row  align:GUI_ALIGN_CENTER];
				}
#endif
				if (([gui selectedRow] == volume_row)
					&&(([gameView isDown:gvArrowKeyRight])||([gameView isDown:gvArrowKeyLeft]))
					&&[OOSound respondsToSelector:@selector(masterVolume)])
				{
					if ((!volumeControlPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
					{
						BOOL rightKeyDown = [gameView isDown:gvArrowKeyRight];
						BOOL leftKeyDown = [gameView isDown:gvArrowKeyLeft];
						GuiDisplayGen* gui = [UNIVERSE gui];
						int volume = 100 * [OOSound masterVolume];
						volume += (((rightKeyDown && (volume < 100)) ? 5 : 0) - ((leftKeyDown && (volume > 0)) ? 5 : 0));
						if (volume > 100) volume = 100;
						if (volume < 0) volume = 0;
						[OOSound setMasterVolume: 0.01 * volume];
						[gui click];
						if (volume > 0)
						{
							NSString* v1_string = @"|||||||||||||||||||||||||";
							NSString* v0_string = @".........................";
							v1_string = [v1_string substringToIndex:volume / 5];
							v0_string = [v0_string substringToIndex:20 - volume / 5];
							[gui setText:[NSString stringWithFormat:@" Sound Volume: %@%@ ", v1_string, v0_string]	forRow:volume_row  align:GUI_ALIGN_CENTER];
						}
						else
							[gui setText:@" Sound Volume: MUTE "	forRow:volume_row  align:GUI_ALIGN_CENTER];
						timeLastKeyPress = script_time;
					}
					volumeControlPressed = YES;
				}
				else
					volumeControlPressed = NO;

#if OOLITE_MAC_OS_X
				if (([gui selectedRow] == growl_row)&&([gameView isDown:gvArrowKeyRight]||[gameView isDown:gvArrowKeyLeft]))
				{
					if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
					{
						NSUserDefaults* prefs = [NSUserDefaults standardUserDefaults];
						BOOL rightKeyDown = [gameView isDown:gvArrowKeyRight];
						BOOL leftKeyDown = [gameView isDown:gvArrowKeyLeft];
						GuiDisplayGen* gui = [UNIVERSE gui];
						int growl_min_priority = 3;
						if ([prefs objectForKey:@"groolite-min-priority"])
							growl_min_priority = [prefs integerForKey:@"groolite-min-priority"];
						int new_priority = growl_min_priority;
						if (rightKeyDown)
							new_priority--;
						if (leftKeyDown)
							new_priority++;
						if (new_priority < -2)	// sanity check values -2 .. 3
							new_priority = -2;
						if (new_priority > 3)
							new_priority = 3;
						if (new_priority != growl_min_priority)
						{
							growl_min_priority = new_priority;
							NSString* growl_priority_desc = [Groolite priorityDescription:growl_min_priority];
							[gui setText:[NSString stringWithFormat:@" Show Growl Messages: %@ ", growl_priority_desc] forRow:growl_row align:GUI_ALIGN_CENTER];
							[gui click];
							[prefs setInteger:growl_min_priority forKey:@"groolite-min-priority"];
						}
						timeLastKeyPress = script_time;
					}
					leftRightKeyPressed = YES;
				}
				else
					leftRightKeyPressed = NO;
#endif

				if (([gui selectedRow] == wireframe_row)&&(([gameView isDown:gvArrowKeyRight])||([gameView isDown:gvArrowKeyLeft])))
				{
					GuiDisplayGen* gui = [UNIVERSE gui];
					if ([gameView isDown:gvArrowKeyRight] != [UNIVERSE wireframeGraphics])
						[gui click];
					[UNIVERSE setWireframeGraphics:[gameView isDown:gvArrowKeyRight]];
					if ([UNIVERSE wireframeGraphics])
						[gui setText:@" Wireframe Graphics: YES "  forRow:wireframe_row  align:GUI_ALIGN_CENTER];
					else
						[gui setText:@" Wireframe Graphics: NO "  forRow:wireframe_row  align:GUI_ALIGN_CENTER];
				}
				
				if (([gui selectedRow] == detail_row)&&(([gameView isDown:gvArrowKeyRight])||([gameView isDown:gvArrowKeyLeft])))
				{
					GuiDisplayGen* gui = [UNIVERSE gui];
					if ([gameView isDown:gvArrowKeyRight] != [UNIVERSE reducedDetail])
						[gui click];
					[UNIVERSE setReducedDetail:[gameView isDown:gvArrowKeyRight]];
					if ([UNIVERSE reducedDetail])
						[gui setText:@" Reduced Detail: YES "	forRow:detail_row  align:GUI_ALIGN_CENTER];
					else
						[gui setText:@" Reduced Detail: NO "	forRow:detail_row  align:GUI_ALIGN_CENTER];
				}
				
				
				if ([gui selectedRow] == shaderfx_row && ([gameView isDown:gvArrowKeyRight] || [gameView isDown:gvArrowKeyLeft]))
				{
					if (!shaderSelectKeyPressed || (script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
					{
						int direction = ([gameView isDown:gvArrowKeyRight]) ? 1 : -1;
						int shaderEffects = [UNIVERSE shaderEffectsLevel];
						shaderEffects = shaderEffects + direction;
						if (shaderEffects < SHADERS_MIN)
							shaderEffects = SHADERS_MIN;
						if (shaderEffects > SHADERS_MAX)
							shaderEffects = SHADERS_MAX;
						[UNIVERSE setShaderEffectsLevel:shaderEffects];
						[gui setText:[NSString stringWithFormat:@" Shader Effects: %@ ", ShaderSettingToDisplayString(shaderEffects)]
							  forRow:shaderfx_row
							   align:GUI_ALIGN_CENTER];
						timeLastKeyPress = script_time;
					}
					shaderSelectKeyPressed = YES;
				}
				else shaderSelectKeyPressed = NO;

				if (([gui selectedRow] == back_row) && selectKeyPress)
				{
					[gameView clearKeys];
					[self setGuiToLoadSaveScreen];
				}
            			
#if OOLITE_SDL
				if (([gui selectedRow] == display_style_row) && selectKeyPress)
				{
					[gameView toggleScreenMode];
					// redraw GUI
					[self setGuiToGameOptionsScreen];
				}
#endif
			}
			break;



		case	GUI_SCREEN_OPTIONS :
			{
				int quicksave_row =		GUI_ROW_OPTIONS_QUICKSAVE;
				int save_row =			GUI_ROW_OPTIONS_SAVE;
				int load_row =			GUI_ROW_OPTIONS_LOAD;
				int begin_new_row =	GUI_ROW_OPTIONS_BEGIN_NEW;
				int gameoptions_row = 	GUI_ROW_OPTIONS_GAMEOPTIONS;
				int strict_row =	GUI_ROW_OPTIONS_STRICT;
#if OOLITE_SDL
				// quit only appears in GNUstep as users aren't
				// used to Cmd-Q equivs. Same goes for window
				// vs fullscreen.
				int quit_row = GUI_ROW_OPTIONS_QUIT;
#endif

				GameController  *controller = [UNIVERSE gameController];

				[self handleGUIUpDownArrowKeys: gui :gameView];
				BOOL selectKeyPress = ([gameView isDown:13]||[gameView isDown:gvMouseDoubleClick]);
				if ([gameView isDown:gvMouseDoubleClick])
					[gameView clearMouse];

				if (selectKeyPress)   // 'enter'
				{
					if (([gui selectedRow] == quicksave_row)&&(!disc_operation_in_progress))
					{
						NS_DURING
							disc_operation_in_progress = YES;
							[self quicksavePlayer];
						NS_HANDLER
							OOLog(kOOLogException, @"\n\n***** Handling localException: %@ : %@ *****\n\n",[localException name], [localException reason]);
							if ([[localException name] isEqual:@"GameNotSavedException"])	// try saving game instead
							{
								OOLog(kOOLogException, @"\n\n***** Trying a normal save instead *****\n\n");
								if ([controller inFullScreenMode])
									[controller pauseFullScreenModeToPerform:@selector(savePlayer) onTarget:self];
								else
									[self savePlayer];
							}
							else
							{
								[localException raise];
							}
						NS_ENDHANDLER
					}
					if (([gui selectedRow] == save_row)&&(!disc_operation_in_progress))
					{
						disc_operation_in_progress = YES;
						[self savePlayer];
					}
					if (([gui selectedRow] == load_row)&&(!disc_operation_in_progress))
					{
						disc_operation_in_progress = YES;
						[self loadPlayer];
					}

					
					if (([gui selectedRow] == begin_new_row)&&(!disc_operation_in_progress))
					{
						disc_operation_in_progress = YES;
						[UNIVERSE reinit];
					}
				}
				else
				{
					disc_operation_in_progress = NO;
				}

#if OOLITE_SDL
            			// SDL-only menu quit item
            			if (([gui selectedRow] == quit_row) && selectKeyPress)
            			{
					[[gameView gameController] exitApp];
            			}
#endif

	    			if (([gui selectedRow] == gameoptions_row) && selectKeyPress)
	    			{
	    				[gameView clearKeys];
	    				[self setGuiToGameOptionsScreen];
	    			}
	    
            			// TODO: Investigate why this has to be handled last (if the
            			// quit item and this are swapped, the game crashes if
            			// strict mode is selected with SIGSEGV in the ObjC runtime
            			// system. The stack trace shows it crashes when it hits
            			// the if statement, trying to send the message to one of
            			// the things contained.
				if (([gui selectedRow] == strict_row)&& selectKeyPress)
				{
					[UNIVERSE setStrict:![UNIVERSE strict]];
				}

			}
			break;

		case	GUI_SCREEN_EQUIP_SHIP :
			{
				//
				if ([self handleGUIUpDownArrowKeys:gui :gameView])
				{
					[self showInformationForSelectedUpgrade];
				}
				//
				if ([gameView isDown:gvArrowKeyLeft])
				{
					if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
					{
						if ([[gui keyForRow:GUI_ROW_EQUIPMENT_START] hasPrefix:@"More:"])
						{
							[gui click];
							[gui setSelectedRow:GUI_ROW_EQUIPMENT_START];
							[self buySelectedItem];
						}
						timeLastKeyPress = script_time;
					}
				}
				if ([gameView isDown:gvArrowKeyRight])
				{
					if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
					{
						if ([[gui keyForRow:GUI_ROW_EQUIPMENT_START + GUI_MAX_ROWS_EQUIPMENT - 1] hasPrefix:@"More:"])
						{
							[gui click];
							[gui setSelectedRow:GUI_ROW_EQUIPMENT_START + GUI_MAX_ROWS_EQUIPMENT - 1];
							[self buySelectedItem];
						}
						timeLastKeyPress = script_time;
					}
				}
				leftRightKeyPressed = [gameView isDown:gvArrowKeyRight]|[gameView isDown:gvArrowKeyLeft];

				if ([gameView isDown:13]||[gameView isDown:gvMouseDoubleClick])   // 'enter'
				{
					if ([gameView isDown:gvMouseDoubleClick])
					{
						selectPressed = NO;
						[gameView clearMouse];
					}
					if ((!selectPressed)&&([gui selectedRow] > -1))
					{
						[self buySelectedItem];
						selectPressed = YES;
					}
				}
				else
				{
					selectPressed = NO;
				}
			}
			break;

		case	GUI_SCREEN_MARKET :
			if (status == STATUS_DOCKED)
			{
				//
				[self handleGUIUpDownArrowKeys:gui :gameView];
				//
				if (([gameView isDown:gvArrowKeyRight])||([gameView isDown:gvArrowKeyLeft])||([gameView isDown:13]||[gameView isDown:gvMouseDoubleClick]))
				{
					if ([gameView isDown:gvArrowKeyRight])   // -->
					{
						if (!wait_for_key_up)
						{
							int item = [(NSString *)[gui selectedRowKey] intValue];
							if ([self tryBuyingCommodity:item])
								[self setGuiToMarketScreen];
							else
								[self boop];
							wait_for_key_up = YES;
						}
					}
					if ([gameView isDown:gvArrowKeyLeft])   // <--
					{
						if (!wait_for_key_up)
						{
							int item = [(NSString *)[gui selectedRowKey] intValue];
							if ([self trySellingCommodity:item])
								[self setGuiToMarketScreen];
							else
								[self boop];
							wait_for_key_up = YES;
						}
					}
					if ([gameView isDown:13]||[gameView isDown:gvMouseDoubleClick])   // 'enter'
					{
						if ([gameView isDown:gvMouseDoubleClick])
						{
							wait_for_key_up = NO;
							[gameView clearMouse];
						}
						if (!wait_for_key_up)
						{
							int item = [(NSString *)[gui selectedRowKey] intValue];
							int yours =		[(NSNumber *)[(NSArray *)[shipCommodityData objectAtIndex:item] objectAtIndex:1] intValue];
							if ((yours > 0)&&(![self marketFlooded:item]))  // sell all you can
							{
								int i;
								for (i = 0; i < yours; i++)
									[self trySellingCommodity:item];
								[self playInterfaceBeep:kInterfaceBeep_Sell];
								[self setGuiToMarketScreen];
							}
							else			// buy as much as possible
							{
								int amount_bought = 0;
								while ([self tryBuyingCommodity:item])
									amount_bought++;
								[self setGuiToMarketScreen];
								if (amount_bought == 0)
								{
									[self boop];
								}
								else
								{
									[self playInterfaceBeep:kInterfaceBeep_Buy];
								}
							}
							wait_for_key_up = YES;
						}
					}
				}
				else
				{
					wait_for_key_up = NO;
				}
			}
			break;

		case	GUI_SCREEN_CONTRACTS :
			if (status == STATUS_DOCKED)
			{
				//
				if ([self handleGUIUpDownArrowKeys:gui :gameView])
					[self setGuiToContractsScreen];
				//
				if ((status == STATUS_DOCKED)&&([gameView isDown:13]||[gameView isDown:gvMouseDoubleClick]))   // 'enter' | doubleclick
				{
					if ([gameView isDown:gvMouseDoubleClick])
						[gameView clearMouse];
					if (!selectPressed)
					{
						if ([self pickFromGuiContractsScreen])
						{
							[self playInterfaceBeep:kInterfaceBeep_Buy];
							[self setGuiToContractsScreen];
						}
						else
						{
							[self boop];
						}
					}
					selectPressed = YES;
				}
				else
				{
					selectPressed = NO;
				}
				//
				if ([gameView isDown:key_contract_info])   // '?' toggle between contracts screen and map
				{
					if (!queryPressed)
					{
						oldSelection = [gui selectedRow];
						[self highlightSystemFromGuiContractsScreen];
					}
					queryPressed = YES;
				}
				else
					queryPressed = NO;
			}
			break;

		case	GUI_SCREEN_REPORT :
			if ([gameView isDown:32])	// spacebar
			{
				if (!spacePressed)
				{
					[gui click];
					[self setGuiToStatusScreen];
				}
				spacePressed = YES;
			}
			else
				spacePressed = NO;
			break;

		case	GUI_SCREEN_SHIPYARD :
			{
				GuiDisplayGen* gui = [UNIVERSE gui];
				//
				if ([self handleGUIUpDownArrowKeys:gui :gameView])
				{
					[self showShipyardInfoForSelection];
				}
				//
				if ([gameView isDown:gvArrowKeyLeft])
				{
					if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
					{
						if ([[gui keyForRow:GUI_ROW_SHIPYARD_START] hasPrefix:@"More:"])
						{
							[gui click];
							[gui setSelectedRow:GUI_ROW_SHIPYARD_START];
							[self buySelectedShip];
						}
						timeLastKeyPress = script_time;
					}
				}
				if ([gameView isDown:gvArrowKeyRight])
				{
					if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
					{
						if ([[gui keyForRow:GUI_ROW_SHIPYARD_START + MAX_ROWS_SHIPS_FOR_SALE - 1] hasPrefix:@"More:"])
						{
							[gui click];
							[gui setSelectedRow:GUI_ROW_SHIPYARD_START + MAX_ROWS_SHIPS_FOR_SALE - 1];
							[self buySelectedShip];
						}
						timeLastKeyPress = script_time;
					}
				}
				leftRightKeyPressed = [gameView isDown:gvArrowKeyRight]|[gameView isDown:gvArrowKeyLeft];

				if ([gameView isDown:13])   // 'enter' NOT double-click
				{
					if (!selectPressed)
					{
						// try to buy the ship!
						OOCreditsQuantity money = credits;
						if ([self buySelectedShip])
						{
							if (money == credits)	// we just skipped to another page
							{
								[[UNIVERSE gui] click];
							}
							else
							{
								[UNIVERSE removeDemoShips];
								[self setGuiToStatusScreen];
								[self playInterfaceBeep: kInterfaceBeep_Buy];
							}
						}
						else
						{
							[self boop];
						}
					}
					selectPressed = YES;
				}
				else
				{
					selectPressed = NO;
				}
			}
			break;
		
		default:
			break;
	}

	//
	// damp any rotations we entered with
	//
	if (flightRoll > 0.0)
	{
		if (flightRoll > delta_t)	[self decrease_flight_roll:delta_t];
		else	flightRoll = 0.0;
	}
	if (flightRoll < 0.0)
	{
		if (flightRoll < -delta_t)   [self increase_flight_roll:delta_t];
		else	flightRoll = 0.0;
	}
	if (flightPitch > 0.0)
	{
		if (flightPitch > delta_t)	[self decrease_flight_pitch:delta_t];
		else	flightPitch = 0.0;
	}
	if (flightPitch < 0.0)
	{
		if (flightPitch < -delta_t)	[self increase_flight_pitch:delta_t];
		else	flightPitch = 0.0;
	}
}

- (void) switchToMainView
{
	gui_screen = GUI_SCREEN_MAIN;
	if (showDemoShips)
	{
		[self setShowDemoShips: NO];
		[UNIVERSE removeDemoShips];
	}
	[(MyOpenGLView *)[UNIVERSE gameView] allowStringInput:NO];
	[UNIVERSE setDisplayCursor:NO];
}

static BOOL zoom_pressed;
	/* GILES custom viewpoints */
static BOOL customView_pressed;
	/* -- */

- (void) pollViewControls
{
   if(!pollControls)
      return;

	MyOpenGLView  *gameView = (MyOpenGLView *)[UNIVERSE gameView];
	//
	//  view keys
	//
	if (([gameView isDown:gvFunctionKey1])||([gameView isDown:gvNumberKey1]))
	{
		if ([UNIVERSE displayGUI])
			[self switchToMainView];
		[UNIVERSE setViewDirection:VIEW_FORWARD];
		currentWeaponFacing = VIEW_FORWARD;
	}
	if (([gameView isDown:gvFunctionKey2])||([gameView isDown:gvNumberKey2]))
	{
		if ([UNIVERSE displayGUI])
			[self switchToMainView];
		[UNIVERSE setViewDirection:VIEW_AFT];
		currentWeaponFacing = VIEW_AFT;
	}
	if (([gameView isDown:gvFunctionKey3])||([gameView isDown:gvNumberKey3]))
	{
		if ([UNIVERSE displayGUI])
			[self switchToMainView];
		[UNIVERSE setViewDirection:VIEW_PORT];
		currentWeaponFacing = VIEW_PORT;
	}
	if (([gameView isDown:gvFunctionKey4])||([gameView isDown:gvNumberKey4]))
	{
		if ([UNIVERSE displayGUI])
			[self switchToMainView];
		[UNIVERSE setViewDirection:VIEW_STARBOARD];
		currentWeaponFacing = VIEW_STARBOARD;
	}

	/* GILES custom viewpoints */

	if ([gameView isDown:key_custom_view])
	{
		if ((!customView_pressed)&&(custom_views)&&(![UNIVERSE displayCursor]))
		{
			if ([UNIVERSE viewDirection] == VIEW_CUSTOM)	// already in custom view mode
			{
				// rotate the custom views
				[custom_views addObject:[custom_views objectAtIndex:0]];
				[custom_views removeObjectAtIndex:0];
			}

			[self setCustomViewDataFromDictionary:(NSDictionary*)[custom_views objectAtIndex:0]];

			if ([UNIVERSE displayGUI])
				[self switchToMainView];
			[UNIVERSE setViewDirection:VIEW_CUSTOM];
		}
		customView_pressed = YES;
	}
	else
		customView_pressed = NO;

	/* -- */
	//
	// Zoom scanner 'z'
	//
	if ([gameView isDown:key_scanner_zoom] && ([gameView allowingStringInput] == gvStringInputNo)) // look for the 'z' key
	{
		if (!scanner_zoom_rate)
		{
			if ([hud scanner_zoom] < 5.0)
			{
				if (([hud scanner_zoom] > 1.0)||(!zoom_pressed))
					scanner_zoom_rate = SCANNER_ZOOM_RATE_UP;
			}
			else
			{
				if (!zoom_pressed)	// must release and re-press zoom to zoom back down..
					scanner_zoom_rate = SCANNER_ZOOM_RATE_DOWN;
			}
		}
		zoom_pressed = YES;
	}
	else
		zoom_pressed = NO;
	//
	// Unzoom scanner 'Z'
	//
	if ([gameView isDown:key_scanner_unzoom] && ([gameView allowingStringInput] == gvStringInputNo)) // look for the 'Z' key
	{
		if ((!scanner_zoom_rate)&&([hud scanner_zoom] > 1.0))
			scanner_zoom_rate = SCANNER_ZOOM_RATE_DOWN;
	}
	//
	// Compass mode '/'
	//
	if ([gameView isDown:key_next_compass_mode]) // look for the '/' key
	{
		if ((!compass_mode_pressed)&&(compassMode != COMPASS_MODE_BASIC))
			[self setNextCompassMode];
		compass_mode_pressed = YES;
	}
	else
	{
		compass_mode_pressed = NO;
	}
	//
	//  show comms log '`'
	//
	if ([gameView isDown:key_comms_log])
	{
		[UNIVERSE showCommsLog: 1.5];
		[hud refreshLastTransmitter];
	}
}

static BOOL switching_chart_screens;
static BOOL switching_status_screens;
static BOOL switching_market_screens;
static BOOL switching_equipship_screens;
- (void) pollGuiScreenControls
{
   if(!pollControls)
      return;

	MyOpenGLView  *gameView = (MyOpenGLView *)[UNIVERSE gameView];
	BOOL docked_okay = (status == STATUS_DOCKED);// || ((status == STATUS_COCKPIT_DISPLAY) && (gui_screen == GUI_SCREEN_SHIPYARD));
	//
	//  text displays
	//
	if (([gameView isDown:gvFunctionKey5])||([gameView isDown:gvNumberKey5]))
	{
		if (!switching_status_screens)
		{
			switching_status_screens = YES;
			if ((gui_screen == GUI_SCREEN_STATUS)&&(![UNIVERSE strict]))
				[self setGuiToManifestScreen];
			else
				[self setGuiToStatusScreen];
			[self checkScript];
		}
	}
	else
	{
		switching_status_screens = NO;
	}

	if (([gameView isDown:gvFunctionKey6])||([gameView isDown:gvNumberKey6]))
	{
		if  (!switching_chart_screens)
		{
			switching_chart_screens = YES;
			if (gui_screen == GUI_SCREEN_SHORT_RANGE_CHART)
				[self setGuiToLongRangeChartScreen];
			else
				[self setGuiToShortRangeChartScreen];
		}
	}
	else
	{
		switching_chart_screens = NO;
	}

	if (([gameView isDown:gvFunctionKey7])||([gameView isDown:gvNumberKey7]))
	{
		if (gui_screen != GUI_SCREEN_SYSTEM_DATA)
		{
			[self setGuiToSystemDataScreen];
			[self checkScript];
		}
	}


	if (docked_okay)
	{
		if ((([gameView isDown:gvFunctionKey2])||([gameView isDown:gvNumberKey2]))&&(gui_screen != GUI_SCREEN_OPTIONS))
		{
			[gameView clearKeys];
			[self setGuiToLoadSaveScreen];
		}
		//
		if (([gameView isDown:gvFunctionKey3])||([gameView isDown:gvNumberKey3]))
		{
			if (!switching_equipship_screens)
			{
				if (!dockedStation)
					dockedStation = [UNIVERSE station];
				if ((gui_screen == GUI_SCREEN_EQUIP_SHIP)&&[dockedStation hasShipyard])
				{
					[gameView clearKeys];
					[self setGuiToShipyardScreen:0];
					[[UNIVERSE gui] setSelectedRow:GUI_ROW_SHIPYARD_START];
					[self showShipyardInfoForSelection];
				}
				else
				{
					[gameView clearKeys];
					[self setGuiToEquipShipScreen:0:-1];
					[[UNIVERSE gui] setSelectedRow:GUI_ROW_EQUIPMENT_START];
				}
			}
			switching_equipship_screens = YES;
		}
		else
		{
			switching_equipship_screens = NO;
		}
		//
		if (([gameView isDown:gvFunctionKey8])||([gameView isDown:gvNumberKey8]))
		{
			if (!switching_market_screens)
			{
				if ((gui_screen == GUI_SCREEN_MARKET)&&(dockedStation == [UNIVERSE station])&&(![UNIVERSE strict]))
				{
					[gameView clearKeys];
					[self setGuiToContractsScreen];
					[[UNIVERSE gui] setSelectedRow:GUI_ROW_PASSENGERS_START];
				}
				else
				{
					[gameView clearKeys];
					[self setGuiToMarketScreen];
					[[UNIVERSE gui] setSelectedRow:GUI_ROW_MARKET_START];
				}
			}
			switching_market_screens = YES;
		}
		else
		{
			switching_market_screens = NO;
		}
	}
	else
	{
		if (([gameView isDown:gvFunctionKey8])||([gameView isDown:gvNumberKey8]))
		{
			if (!switching_market_screens)
			{
				[self setGuiToMarketScreen];
				[[UNIVERSE gui] setSelectedRow:GUI_ROW_MARKET_START];
			}
			switching_market_screens = YES;
		}
		else
		{
			switching_market_screens = NO;
		}
	}
}

- (void) pollGameOverControls:(double) delta_t
{
	MyOpenGLView  *gameView = (MyOpenGLView *)[UNIVERSE gameView];
	if ([gameView isDown:32])   // look for the spacebar
	{
		if (!spacePressed)
		{
			[UNIVERSE displayMessage:@"" forCount:1.0];
			shot_time = 31.0;	// force restart
		}
		spacePressed = YES;
	}
	else
		spacePressed = NO;
}

static BOOL toggling_music;
- (void) pollAutopilotControls:(double) delta_t
{
	//
	// controls polled while the autopilot is active
	//

	MyOpenGLView  *gameView = (MyOpenGLView *)[UNIVERSE gameView];
	//
	//  view keys
	//
	[self pollViewControls];
	//
	//  text displays
	//
	[self pollGuiScreenControls];
	//
	if ([UNIVERSE displayGUI])
		[self pollGuiArrowKeyControls:delta_t];
	//
	//
	if ([gameView isDown:key_autopilot])   // look for the 'c' key
	{
		if (has_docking_computer && (!autopilot_key_pressed))   // look for the 'c' key
		{
			[self abortDocking];			// let the station know that you are no longer on approach
			behaviour = BEHAVIOUR_IDLE;
			frustration = 0.0;
			autopilot_engaged = NO;
			primaryTarget = NO_TARGET;
			status = STATUS_IN_FLIGHT;
			if (![UNIVERSE playCustomSound:@"[autopilot-off]"])
				[self beep];
			[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[autopilot-off]") forCount:4.5];
			[self doScriptEvent:@"didAbortAutoPilot"];
			//
			if (ootunes_on)
			{
				// ootunes - play inflight music
				[[UNIVERSE gameController] playiTunesPlaylist:@"Oolite-Inflight"];
				docking_music_on = NO;
			}
		}
		autopilot_key_pressed = YES;
	}
	else
		autopilot_key_pressed = NO;
	//
	if (([gameView isDown:key_docking_music])&&(!ootunes_on))   // look for the 's' key
	{
		if (!toggling_music)
		{
			docking_music_on = !docking_music_on;
			// set defaults..
			[[NSUserDefaults standardUserDefaults]  setBool:docking_music_on forKey:KEY_DOCKING_MUSIC];
		}
		toggling_music = YES;
	}
	else
	{
		toggling_music = NO;
	}
	//

}

- (void) pollDockedControls:(double) delta_t
{
	if(pollControls)
	{
		MyOpenGLView  *gameView = (MyOpenGLView *)[UNIVERSE gameView];
		if (([gameView isDown:gvFunctionKey1])||([gameView isDown:gvNumberKey1]))   // look for the f1 key
		{
			// ensure we've not left keyboard entry on
			[gameView allowStringInput: NO];

			[UNIVERSE setUpUniverseFromStation]; // launch!
			if (!dockedStation)
				dockedStation = [UNIVERSE station];
			[self leaveDock:dockedStation];
			[UNIVERSE setDisplayCursor:NO];
			[self doScriptEvent:@"willLaunch"];
			[self playBreakPattern];
		}
	}
	//
	//  text displays
	//
	// mission screens
	if (gui_screen == GUI_SCREEN_MISSION)
		[self pollDemoControls: delta_t];
	else
		[self pollGuiScreenControls];	// don't switch away from mission screens
	//
	[self pollGuiArrowKeyControls:delta_t];
	//
}

- (void) pollDemoControls:(double) delta_t
{
	MyOpenGLView*	gameView = (MyOpenGLView *)[UNIVERSE gameView];
	GuiDisplayGen*	gui = [UNIVERSE gui];

	switch (gui_screen)
	{
		case	GUI_SCREEN_INTRO1 :
			if (!disc_operation_in_progress)
			{
				if (([gameView isDown:121])||([gameView isDown:89]))	//  'yY'
				{
					if (themeMusic)
					{
						[themeMusic stop];
					}
					disc_operation_in_progress = YES;
					[self setStatus:STATUS_DOCKED];
					[UNIVERSE removeDemoShips];
					[gui clearBackground];
					[self loadPlayer];
				}
			}
			if (([gameView isDown:110])||([gameView isDown:78]))	//  'nN'
			{
				[self setGuiToIntro2Screen];
			}

			break;

		case	GUI_SCREEN_INTRO2 :
			if ([gameView isDown:32])	//  '<space>'
			{
				[self setStatus: STATUS_DOCKED];
				[UNIVERSE removeDemoShips];
				[gui clearBackground];
				[self setGuiToStatusScreen];
				if (themeMusic)
				{
					[themeMusic stop];
				}
			}
			if ([gameView isDown:gvArrowKeyLeft])	//  '<--'
			{
				if (!upDownKeyPressed)
					[UNIVERSE selectIntro2Previous];
			}
			if ([gameView isDown:gvArrowKeyRight])	//  '-->'
			{
				if (!upDownKeyPressed)
					[UNIVERSE selectIntro2Next];
			}
			upDownKeyPressed = (([gameView isDown:gvArrowKeyLeft])||([gameView isDown:gvArrowKeyRight]));
			break;

		case	GUI_SCREEN_MISSION :
			if ([[gui keyForRow:21] isEqual:@"spacebar"])
			{
				if ([gameView isDown:32])	//  '<space>'
				{
					if (!spacePressed)
					{
						[self setStatus:STATUS_DOCKED];
						[UNIVERSE removeDemoShips];
						[gui clearBackground];
						[self setGuiToStatusScreen];
						[missionMusic stop];
						
						[self doScriptEvent:@"missionScreenEnded"];
					}
					spacePressed = YES;
				}
				else
					spacePressed = NO;
			}
			else
			{
				if ([gameView isDown:gvArrowKeyDown])
				{
					if ((!upDownKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
					{
						if ([gui setSelectedRow:[gui selectedRow] + 1])
						{
							[gui click];
						}
						timeLastKeyPress = script_time;
					}
				}
				if ([gameView isDown:gvArrowKeyUp])
				{
					if ((!upDownKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
					{
						if ([gui setSelectedRow:[gui selectedRow] - 1])
						{
							[gui click];
						}
						timeLastKeyPress = script_time;
					}
				}
				upDownKeyPressed = (([gameView isDown:gvArrowKeyUp])||([gameView isDown:gvArrowKeyDown]));
				//
				if ([gameView isDown:13])	//  '<enter/return>'
				{
					if (!enterSelectKeyPressed)
					{
						if (missionChoice)
							[missionChoice release];
						missionChoice = [[NSString stringWithString:[gui selectedRowKey]] retain];
						//
						[UNIVERSE removeDemoShips];
						[gui clearBackground];
						[self setGuiToStatusScreen];
						[missionMusic stop];
						[missionMusic release];
						missionMusic = nil;
						
						[self doScriptEvent:@"missionScreenEnded"];
						[self checkScript];
					}
					enterSelectKeyPressed = YES;
				}
				else
					enterSelectKeyPressed = NO;
			}
			break;
		
		default:
			break;
	}

}

@end
