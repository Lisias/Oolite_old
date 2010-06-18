/*

PlayerEntityControls.m

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

#import "PlayerEntityControls.h"
#import "PlayerEntityContracts.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "PlayerEntityScriptMethods.h"
#import "PlayerEntitySound.h"
#import "PlayerEntityLoadSave.h"
#import "PlayerEntityStickMapper.h"

#import "ShipEntityAI.h"
#import "StationEntity.h"
#import "Universe.h"
#import "OOSunEntity.h"
#import "OOPlanetEntity.h"
#import "GameController.h"
#import "AI.h"
#import "MyOpenGLView.h"
#import "OOSound.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"
#import "ResourceManager.h"
#import "HeadUpDisplay.h"
#import "OOConstToString.h"
#import "OOLoggingExtended.h"
#import "OOMusicController.h"
#import "OOTexture.h"
#import "OODebugFlags.h"

#import "JoystickHandler.h"

#if OOLITE_MAC_OS_X
#import "Groolite.h"
#endif


static BOOL				jump_pressed;
static BOOL				hyperspace_pressed;
static BOOL				galhyperspace_pressed;
static BOOL				pause_pressed;
static BOOL				compass_mode_pressed;
static BOOL				next_target_pressed;
static BOOL				previous_target_pressed;
static BOOL				next_missile_pressed;
static BOOL				fire_missile_pressed;
static BOOL				target_missile_pressed;
#if TARGET_INCOMING_MISSILES
static BOOL				target_incoming_missile_pressed;
#endif
static BOOL				ident_pressed;
static BOOL				safety_pressed;
static BOOL				cloak_pressed;
static BOOL				rotateCargo_pressed;
static BOOL				autopilot_key_pressed;
static BOOL				fast_autopilot_key_pressed;
static BOOL				target_autopilot_key_pressed;
#if DOCKING_CLEARANCE_ENABLED
static BOOL				docking_clearance_request_key_pressed;
#endif
#ifndef NDEBUG
static BOOL				dump_target_state_pressed;
#endif
static BOOL				hide_hud_pressed;
static BOOL				f_key_pressed;
static BOOL				m_key_pressed;
static BOOL				taking_snapshot;
static BOOL				pling_pressed;
static BOOL				cursor_moving;
static BOOL				disc_operation_in_progress;
static BOOL				switching_resolution;
static BOOL				wait_for_key_up;
static BOOL				upDownKeyPressed;
static BOOL				leftRightKeyPressed;
static BOOL				musicModeKeyPressed;
static BOOL				volumeControlPressed;
static BOOL				shaderSelectKeyPressed;
static BOOL				selectPressed;
static BOOL				queryPressed;
static BOOL				spacePressed;
static BOOL				switching_chart_screens;
static BOOL				switching_status_screens;
static BOOL				switching_market_screens;
static BOOL				switching_equipship_screens;
static BOOL				zoom_pressed;
static BOOL				customView_pressed;

static unsigned			searchStringLength;
static double			timeLastKeyPress;
static OOGUIRow			oldSelection;
static int				saved_view_direction;
static double			saved_script_time;
static int				saved_gui_screen;
static int 				pressedArrow = 0;
static BOOL			mouse_x_axis_map_to_yaw = NO;
static NSTimeInterval	time_last_frame;


@interface PlayerEntity (OOControlsPrivate)

- (void) pollFlightControls:(double) delta_t;
- (void) pollFlightArrowKeyControls:(double) delta_t;
- (void) pollGuiArrowKeyControls:(double) delta_t;
- (void) handleGameOptionsScreenKeys;
- (void) pollApplicationControls;
- (void) pollViewControls;
- (void) pollGuiScreenControls;
- (void) pollGuiScreenControlsWithFKeyAlias:(BOOL)fKeyAlias;
- (void) handleUndockControl;
- (void) pollGameOverControls:(double) delta_t;
- (void) pollAutopilotControls:(double) delta_t;
- (void) pollDockedControls:(double) delta_t;
- (void) pollDemoControls:(double) delta_t;
- (void) handleMissionCallback;
- (void) switchToThisView:(OOViewID) viewDirection;

@end


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
	
#if OOLITE_WINDOWS
	// override windows keyboard autoselect
	[[UNIVERSE gameView] setKeyboardTo:[kdic oo_stringForKey:@"windows_keymap" defaultValue:@"auto"]];
#endif

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
			else continue;
			
			[kdic setObject:[NSNumber numberWithUnsignedChar:keychar] forKey:key];
		}
	}
	
	// set default keys.
#define LOAD_KEY_SETTING(name, default)	name = [kdic oo_unsignedShortForKey:@#name defaultValue:default]
	
	LOAD_KEY_SETTING(key_roll_left,				gvArrowKeyLeft		);
	LOAD_KEY_SETTING(key_roll_right,			gvArrowKeyRight		);
	LOAD_KEY_SETTING(key_pitch_forward,			gvArrowKeyUp		);
	LOAD_KEY_SETTING(key_pitch_back,			gvArrowKeyDown		);
	LOAD_KEY_SETTING(key_yaw_left,				','			);
	LOAD_KEY_SETTING(key_yaw_right,				'.'			);
	
	LOAD_KEY_SETTING(key_increase_speed,			'w'			);
	LOAD_KEY_SETTING(key_decrease_speed,			's'			);
	LOAD_KEY_SETTING(key_inject_fuel,			'i'			);
	
	LOAD_KEY_SETTING(key_fire_lasers,			'a'			);
	LOAD_KEY_SETTING(key_launch_missile,			'm'			);
	LOAD_KEY_SETTING(key_next_missile,			'y'			);
	LOAD_KEY_SETTING(key_ecm,				'e'			);
	
	LOAD_KEY_SETTING(key_target_missile,			't'			);
	LOAD_KEY_SETTING(key_untarget_missile,			'u'			);
#if TARGET_INCOMING_MISSILES
	LOAD_KEY_SETTING(key_target_incoming_missile,		'T'			);
#endif
	LOAD_KEY_SETTING(key_ident_system,			'r'			);
	
	LOAD_KEY_SETTING(key_scanner_zoom,			'z'			);
	LOAD_KEY_SETTING(key_scanner_unzoom,			'Z'			);
	
	LOAD_KEY_SETTING(key_launch_escapepod,			27	/* esc */	);
	LOAD_KEY_SETTING(key_energy_bomb,			'\t'			);
	
	LOAD_KEY_SETTING(key_galactic_hyperspace,		'g'			);
	LOAD_KEY_SETTING(key_hyperspace,			'h'			);
	LOAD_KEY_SETTING(key_jumpdrive,				'j'			);
	
	LOAD_KEY_SETTING(key_dump_cargo,			'd'			);
	LOAD_KEY_SETTING(key_rotate_cargo,			'R'			);
	
	LOAD_KEY_SETTING(key_autopilot,				'c'			);
	LOAD_KEY_SETTING(key_autopilot_target,			'C'			);
	LOAD_KEY_SETTING(key_autodock,				'D'			);
#if DOCKING_CLEARANCE_ENABLED
	LOAD_KEY_SETTING(key_docking_clearance_request, 	'L'			);
#endif
	
	LOAD_KEY_SETTING(key_snapshot,				'*'			);
	LOAD_KEY_SETTING(key_docking_music,			's'			);
	
	LOAD_KEY_SETTING(key_advanced_nav_array,		'^'			);
	LOAD_KEY_SETTING(key_map_home,				gvHomeKey		);
	LOAD_KEY_SETTING(key_map_info,				'i'			);
	
	LOAD_KEY_SETTING(key_pausebutton,			'p'			);
	LOAD_KEY_SETTING(key_show_fps,				'F'			);
	LOAD_KEY_SETTING(key_mouse_control,			'M'			);
	
	LOAD_KEY_SETTING(key_comms_log,				'`'			);
	LOAD_KEY_SETTING(key_next_compass_mode,			'\\'			);
	
	LOAD_KEY_SETTING(key_cloaking_device,			'0'			);
	
	LOAD_KEY_SETTING(key_contract_info,			'\?'			);
	
	LOAD_KEY_SETTING(key_next_target,			'+'			);
	LOAD_KEY_SETTING(key_previous_target,			'-'			);
	
	LOAD_KEY_SETTING(key_custom_view,			'v'			);
	
#ifndef NDEBUG
	LOAD_KEY_SETTING(key_dump_target_state,			'H'			);
#endif
	
	if (key_yaw_left == key_roll_left && key_yaw_left == ',')  key_yaw_left = 0;
	if (key_yaw_right == key_roll_right && key_yaw_right == '.')  key_yaw_right = 0;
	
	// other keys are SET and cannot be varied
	
	// Enable polling
	pollControls=YES;
}


- (void) pollControls:(double)delta_t
{
	MyOpenGLView  *gameView = [UNIVERSE gameView];
	NSString * volatile	exceptionContext = @"setup";
	
	NS_DURING
		if (gameView)
		{
			// poll the gameView keyboard things
			exceptionContext = @"pollApplicationControls";
			[self pollApplicationControls]; // quit command-f etc.
			switch ([self status])
			{
				case STATUS_WITCHSPACE_COUNTDOWN:
				case STATUS_IN_FLIGHT:
					exceptionContext = @"pollFlightControls";
					[self pollFlightControls:delta_t];
					break;
					
				case STATUS_DEAD:
					exceptionContext = @"pollGameOverControls";
					[self pollGameOverControls:delta_t];
					break;
					
				case STATUS_AUTOPILOT_ENGAGED:
					exceptionContext = @"pollAutopilotControls";
					[self pollAutopilotControls:delta_t];
					break;
					
				case STATUS_DOCKED:
					exceptionContext = @"pollDockedControls";
					[self pollDockedControls:delta_t];
					break;
					
				case STATUS_START_GAME:
					exceptionContext = @"pollDemoControls";
					[self pollDemoControls:delta_t];
					break;
					
				default:
					break;
			}
		}
	NS_HANDLER
		// TEMP extra exception checking
		OOLog(kOOLogException, @"***** Exception checking controls [%@]: %@ : %@", exceptionContext, [localException name], [localException reason]);
	NS_ENDHANDLER
}

// DJS + aegidian: Moved from the big switch/case block in pollGuiArrowKeyControls
- (BOOL) handleGUIUpDownArrowKeys
{
	MyOpenGLView	*gameView = [UNIVERSE gameView];
	GuiDisplayGen	*gui = [UNIVERSE gui];
	BOOL			result = NO;
	BOOL			arrow_up = [gameView isDown:gvArrowKeyUp];
	BOOL			arrow_down = [gameView isDown:gvArrowKeyDown];
	BOOL			mouse_click = [gameView isDown:gvMouseLeftButton];
	
	if (arrow_down)
	{
		if ((!upDownKeyPressed) || (script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
		{
			if ([gui setNextRow: +1])
			{
				result = YES;
			}
			else
			{
				if ([gui setFirstSelectableRow])  result = YES;
			}
			
			if (result && [gui selectableRange].length > 1)  [self playMenuNavigationDown];
			else  [self playMenuNavigationNot];
			
			timeLastKeyPress = script_time;
		}
	}
	
	if (arrow_up)
	{
		if ((!upDownKeyPressed) || (script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
		{
			if ([gui setNextRow: -1])
			{
				result = YES;
			}
			else
			{
				if ([gui setLastSelectableRow])  result = YES;
			}
			
			if (result && [gui selectableRange].length > 1)  [self playMenuNavigationUp];
			else  [self playMenuNavigationNot];

			timeLastKeyPress = script_time;
		}
	}
	
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
	
	upDownKeyPressed = (arrow_up || arrow_down || mouse_click);
	
	return result;
}


- (void) targetNewSystem:(int) direction
{
	target_system_seed = [[UNIVERSE gui] targetNextFoundSystem:direction];
	cursor_coordinates.x = target_system_seed.d;
	cursor_coordinates.y = target_system_seed.b;
	found_system_seed = target_system_seed;
	[[UNIVERSE gameView] resetTypedString];
	if (planetSearchString) [planetSearchString release];
	planetSearchString = nil;
	cursor_moving = YES;
}

@end


@implementation PlayerEntity (OOControlsPrivate)

- (void) pollApplicationControls
{
	if (!pollControls) return;
	
	NSString * volatile	exceptionContext = @"setup";
	
	// does fullscreen / quit / snapshot
	MyOpenGLView  *gameView = [UNIVERSE gameView];
	
	NS_DURING
		//  command-key controls
		if ([[gameView gameController] inFullScreenMode])
		{
			exceptionContext = @"command key controls";
			if ([gameView isCommandFDown])
			{
				[[gameView gameController] exitFullScreenMode];
				if (mouse_control_on)
				{
					[UNIVERSE addMessage:DESC(@"mouse-off") forCount:3.0];
					mouse_control_on = NO;
				}
			}
			
			if ([gameView isCommandQDown])
			{
				[[gameView gameController] pauseFullScreenModeToPerform:@selector(exitApp) onTarget:[gameView gameController]];
			}
		}
		
	#if OOLITE_WINDOWS
		if ( ([gameView isDown:'Q']) )
		{
			exceptionContext = @"windows - Q";
			[[gameView gameController] exitApp];
			exit(0); // Force it
		}
	#endif
		
		// handle pressing Q or [esc] in error-handling mode
		if ([self status] == STATUS_HANDLING_ERROR)
		{
			exceptionContext = @"error handling mode";
			if ([gameView isDown:113]||[gameView isDown:81]||[gameView isDown:27])   // 'q' | 'Q' | esc
			{
				[[gameView gameController] exitApp];
			}
		}
		
		//  snapshot
		if ([gameView isDown:key_snapshot])   //  '*' key
		{
			exceptionContext = @"snapshot";
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
		
		// FPS display
		if ([gameView isDown:key_show_fps])   //  'F' key
		{
			exceptionContext = @"toggle FPS";
			if (!f_key_pressed)  [UNIVERSE setDisplayFPS:![UNIVERSE displayFPS]];
			f_key_pressed = YES;
		}
		else
		{
			f_key_pressed = NO;
		}
		
		// Mouse control
		BOOL allowMouseControl;
	#if OO_DEBUG
		allowMouseControl = YES;
	#else
		allowMouseControl = [[gameView gameController] inFullScreenMode] ||
					[[NSUserDefaults standardUserDefaults] boolForKey:@"mouse-control-in-windowed-mode"];
	#endif
		
		if (allowMouseControl)
		{
			exceptionContext = @"mouse control";
			if ([gameView isDown:key_mouse_control])   //  'M' key
			{
				if (!m_key_pressed)
				{
					mouse_control_on = !mouse_control_on;
					if (mouse_control_on)
					{
						[UNIVERSE addMessage:DESC(@"mouse-on") forCount:3.0];
						/*	Ensure the keyboard pitch override (intended to lock
						 out the joystick if the player runs to the keyboard)
						 is reset */
						keyboardRollPitchOverride = NO;
						keyboardYawOverride = NO;
						mouse_x_axis_map_to_yaw = [gameView isCtrlDown];
					}
					else
					{
						[UNIVERSE addMessage:DESC(@"mouse-off") forCount:3.0];
					}
				}
				m_key_pressed = YES;
			}
			else
			{
				m_key_pressed = NO;
			}
		}
		else
		{
			if (mouse_control_on)
			{
				mouse_control_on = NO;
				[UNIVERSE addMessage:DESC(@"mouse-off") forCount:3.0];
			}
		}
		
		// HUD toggle
		if ([gameView isDown:'o'] && [[gameView gameController] gameIsPaused])// 'o' key while paused
		{
			exceptionContext = @"toggle HUD";
			if (!hide_hud_pressed)
			{
				HeadUpDisplay *theHUD = [self hud];
				[theHUD setHidden:![theHUD isHidden]];
			}
			hide_hud_pressed = YES;
		}
		else
		{
			hide_hud_pressed = NO;
		}
	NS_HANDLER
		// TEMP extra exception checking
		OOLog(kOOLogException, @"***** Exception in pollApplicationControls [%@]: %@ : %@", exceptionContext, [localException name], [localException reason]);
	NS_ENDHANDLER
}


- (void) pollFlightControls:(double)delta_t
{
	MyOpenGLView  *gameView = [UNIVERSE gameView];
	NSString * volatile	exceptionContext = @"setup";
	
	NS_DURING
		exceptionContext = @"joystick handling";
		// DJS: TODO: Sort where SDL keeps its stuff.
		if(!stickHandler)
		{
			stickHandler=[gameView getStickHandler];
		}
		const BOOL *joyButtonState = [stickHandler getAllButtonStates];
		
		BOOL paused = [[gameView gameController] gameIsPaused];
		double speed_delta = 5.0 * thrust;
		
		if (!paused && gui_screen == GUI_SCREEN_MISSION)
		{
			exceptionContext = @"mission screen";
			OOViewID view = VIEW_NONE;
			
			NSPoint			virtualView = NSZeroPoint;
			double			view_threshold = 0.5;
			
			if ([stickHandler getNumSticks])
			{
				virtualView = [stickHandler getViewAxis];
				if (virtualView.y == STICK_AXISUNASSIGNED)
					virtualView.y = 0.0;
				if (virtualView.x == STICK_AXISUNASSIGNED)
					virtualView.x = 0.0;
				if (fabs(virtualView.y) >= fabs(virtualView.x))
					virtualView.x = 0.0; // forward/aft takes precedence
				else
					virtualView.y = 0.0;
			}
		
			if (([gameView isDown:gvFunctionKey1])||([gameView isDown:gvNumberKey1])||(virtualView.y < -view_threshold)||joyButtonState[BUTTON_VIEWFORWARD])
			{
				view = VIEW_FORWARD;
			}
			if (([gameView isDown:gvFunctionKey2])||([gameView isDown:gvNumberKey2])||(virtualView.y > view_threshold)||joyButtonState[BUTTON_VIEWAFT])
			{
				view = VIEW_AFT;
			}
			if (([gameView isDown:gvFunctionKey3])||([gameView isDown:gvNumberKey3])||(virtualView.x < -view_threshold)||joyButtonState[BUTTON_VIEWPORT])
			{
				view = VIEW_PORT;
			}
			if (([gameView isDown:gvFunctionKey4])||([gameView isDown:gvNumberKey4])||(virtualView.x > view_threshold)||joyButtonState[BUTTON_VIEWSTARBOARD])
			{
				view = VIEW_STARBOARD;
			}
			if (view == VIEW_NONE)
			{
				// still in mission screen, process the input.
				[self pollDemoControls: delta_t];
			}
			else
			{
				[[UNIVERSE gui] clearBackground];
				[self switchToThisView:view];
				if (_missionWithCallback)
				{
					[self doMissionCallback];
				}
				// notify older scripts, but do not trigger missionScreenOpportunity.
				[self doWorldEventUntilMissionScreen:@"missionScreenEnded"];
			}
		}
		else if (!paused)
		{
			exceptionContext = @"arrow keys";
			// arrow keys
			if ([UNIVERSE displayGUI])
				[self pollGuiArrowKeyControls:delta_t];
			else
				[self pollFlightArrowKeyControls:delta_t];
			
			//  view keys
			[self pollViewControls];
			
			if (![UNIVERSE displayCursor])
			{
				exceptionContext = @"afterburner";
				if ((joyButtonState[BUTTON_FUELINJECT] || [gameView isDown:key_inject_fuel]) &&
					[self hasFuelInjection] &&
					!hyperspeed_engaged)
				{
					if (fuel > 0 && !afterburner_engaged)
					{
						[UNIVERSE addMessage:DESC(@"fuel-inject-on") forCount:1.5];
						afterburner_engaged = YES;
						[self startAfterburnerSound];
					}
					else
					{
						if (fuel <= 0.0)
							[UNIVERSE addMessage:DESC(@"fuel-out") forCount:1.5];
					}
					afterburner_engaged = (fuel > 0);
				}
				else
					afterburner_engaged = NO;
				
				if ((!afterburner_engaged)&&(afterburnerSoundLooping))
					[self stopAfterburnerSound];
				
			exceptionContext = @"thrust";
	#if OOLITE_HAVE_JOYSTICK
				// DJS: Thrust can be an axis or a button. Axis takes precidence.
				double reqSpeed=[stickHandler getAxisState: AXIS_THRUST];
				if(reqSpeed == STICK_AXISUNASSIGNED || [stickHandler getNumSticks] == 0)
				{
					// DJS: original keyboard code
					if (([gameView isDown:key_increase_speed] || joyButtonState[BUTTON_INCTHRUST])&&(flightSpeed < maxFlightSpeed)&&(!afterburner_engaged))
					{
						flightSpeed += speed_delta * delta_t;
					}
					
					// ** tgape ** - decrease obviously means no hyperspeed
					if (([gameView isDown:key_decrease_speed] || joyButtonState[BUTTON_DECTHRUST])&&(!afterburner_engaged))
					{
						flightSpeed -= speed_delta * delta_t;
						
						// ** tgape ** - decrease obviously means no hyperspeed
						hyperspeed_engaged = NO;
					}
				} // DJS: STICK_NOFUNCTION else...a joystick axis is assigned to thrust.
				else
				{
					if (flightSpeed < maxFlightSpeed * reqSpeed)
					{
						flightSpeed += speed_delta * delta_t;
					}
					if (flightSpeed > maxFlightSpeed * reqSpeed)
					{
						flightSpeed -= speed_delta * delta_t;
					}
				} // DJS: end joystick thrust axis
	#else
				if (([gameView isDown:key_increase_speed])&&(flightSpeed < maxFlightSpeed)&&(!afterburner_engaged))
				{
					flightSpeed += speed_delta * delta_t;
				}
				
				if (([gameView isDown:key_decrease_speed])&&(!afterburner_engaged))
				{
					flightSpeed -= speed_delta * delta_t;
					// ** tgape ** - decrease obviously means no hyperspeed
					hyperspeed_engaged = NO;
				}
	#endif
				if (!afterburner_engaged && ![self atHyperspeed] && !hyperspeed_engaged)
				{
					flightSpeed = OOClamp_0_max_f(flightSpeed, maxFlightSpeed);
				}
				
				exceptionContext = @"hyperspeed";
				//  hyperspeed controls
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
								[self playJumpMassLocked];
								[UNIVERSE addMessage:DESC(@"jump-mass-locked") forCount:1.5];
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
				
				exceptionContext = @"shoot";
				//  shoot 'a'
				if ((([gameView isDown:key_fire_lasers])||((mouse_control_on)&&([gameView isDown:gvMouseLeftButton]))||joyButtonState[BUTTON_FIRE])&&(shot_time > weapon_reload_time))
					
				{
					if ([self fireMainWeapon])
					{
						[self playLaserHit:target_laser_hit != NO_TARGET];
					}
				}
				
				exceptionContext = @"missile fire";
				//  shoot 'm'   // launch missile
				if ([gameView isDown:key_launch_missile] || joyButtonState[BUTTON_LAUNCHMISSILE])
				{
					// launch here
					if (!fire_missile_pressed)
					{
						[self fireMissile];
						fire_missile_pressed = YES;
					}
				}
				else  fire_missile_pressed = NO;
				
				exceptionContext = @"next missile";
				//  shoot 'y'   // next missile
				if ([gameView isDown:key_next_missile] || joyButtonState[BUTTON_CYCLEMISSILE])
				{
					if ((!ident_engaged)&&(!next_missile_pressed))
					{
						[self playNextMissileSelected];
						[self selectNextMissile];
					}
					next_missile_pressed = YES;
				}
				else  next_missile_pressed = NO;
				
				exceptionContext = @"next target";
				//	'+' // next target
				if ([gameView isDown:key_next_target])
				{
					if ((!next_target_pressed)&&([self hasEquipmentItem:@"EQ_TARGET_MEMORY"]))
					{
						[self moveTargetMemoryBy:+1];
					}
					next_target_pressed = YES;
				}
				else  next_target_pressed = NO;
				
				exceptionContext = @"previous target";
				//	'-' // previous target
				if ([gameView isDown:key_previous_target])
				{
					if ((!previous_target_pressed)&&([self hasEquipmentItem:@"EQ_TARGET_MEMORY"]))
					{
						[self moveTargetMemoryBy:-1];
					}
					previous_target_pressed = YES;
				}
				else  previous_target_pressed = NO;
				
				exceptionContext = @"ident R";
				//  shoot 'r'   // switch on ident system
				if ([gameView isDown:key_ident_system] || joyButtonState[BUTTON_ID])
				{
					// ident 'on' here
					if (!ident_pressed)
					{
						// Clear current target if we're already in Ident mode
						if (ident_engaged)
						{
							if (primaryTarget != NO_TARGET) [self noteLostTarget];
							primaryTarget = NO_TARGET;
						}
						[self safeAllMissiles];
						ident_engaged = YES;
						if ([self primaryTargetID] == NO_TARGET)
						{
							[self playIdentOn];
							[UNIVERSE addMessage:DESC(@"ident-on") forCount:2.0];
						}
						else
						{
							[self playIdentLockedOn];
							[self printIdentLockedOnForMissile:NO];
						}
					}
					ident_pressed = YES;
				}
				else  ident_pressed = NO;
	#if TARGET_INCOMING_MISSILES
				// target nearest incoming missile 'T' - useful for quickly giving a missile target to turrets
				if ([gameView isDown:key_target_incoming_missile] || joyButtonState[BUTTON_TARGETINCOMINGMISSILE])
				{
					if (!target_incoming_missile_pressed)
					{
						[self targetNearestIncomingMissile];
					}
					target_incoming_missile_pressed = YES;
				}
				else  target_incoming_missile_pressed = NO;
	#endif
				
				exceptionContext = @"missile T";
				//  shoot 't'   // switch on missile targeting
				if (([gameView isDown:key_target_missile] || joyButtonState[BUTTON_ARMMISSILE])&&(missile_entity[activeMissile]))
				{
					// targeting 'on' here
					if (!target_missile_pressed)
					{
						// Clear current target if we're already in Missile Targeting mode
						if (missile_status != MISSILE_STATUS_SAFE)
						{
							primaryTarget = NO_TARGET;
						}

						// Arm missile and check for missile lock
						missile_status = MISSILE_STATUS_ARMED;
						if ([missile_entity[activeMissile] isMissile])
						{
							if ([[self primaryTarget] isShip])
							{
								missile_status = MISSILE_STATUS_TARGET_LOCKED;
								[missile_entity[activeMissile] addTarget:[self primaryTarget]];
								[self printIdentLockedOnForMissile:YES];
								[self playMissileLockedOn];
							}
							else
							{
								[self removeTarget:nil];
								[missile_entity[activeMissile] removeTarget:nil];
								[UNIVERSE addMessage:[NSString stringWithFormat:DESC(@"@-armed"), [missile_entity[activeMissile] name]] forCount:2.0];
								[self playMissileArmed];
							}
						}
						else if ([missile_entity[activeMissile] isMine])
						{
							[UNIVERSE addMessage:[NSString stringWithFormat:DESC(@"@-armed"), [missile_entity[activeMissile] name]] forCount:2.0];
							[self playMineArmed];
						}
						ident_engaged = NO;
					}
					target_missile_pressed = YES;
				}
				else  target_missile_pressed = NO;
				
				exceptionContext = @"missile U";
				//  shoot 'u'   // disarm missile targeting
				if ([gameView isDown:key_untarget_missile] || joyButtonState[BUTTON_UNARM])
				{
					if (!safety_pressed)
					{
						//targeting off in both cases!
						if (primaryTarget != NO_TARGET) [self noteLostTarget];
						primaryTarget = NO_TARGET;
						[self safeAllMissiles];
						if (!ident_engaged)
						{
							[UNIVERSE addMessage:DESC(@"missile-safe") forCount:2.0];
							[self playMissileSafe];
						}
						else
						{
							[UNIVERSE addMessage:DESC(@"ident-off") forCount:2.0];
							[self playIdentOff];
						}
						ident_engaged = NO;
					}
					safety_pressed = YES;
				}
				else  safety_pressed = NO;
				
				exceptionContext = @"ECM";
				//  shoot 'e'   // ECM
				if (([gameView isDown:key_ecm] || joyButtonState[BUTTON_ECM]) && [self hasECM])
				{
					if (!ecm_in_operation)
					{
						if ([self fireECM])
						{
							[self playFiredECMSound];
							[UNIVERSE addMessage:DESC(@"ecm-on") forCount:3.0];
						}
					}
				}
				
				exceptionContext = @"energy bomb";
				//  shoot 'tab'   // Energy bomb
				if (([gameView isDown:key_energy_bomb] || joyButtonState[BUTTON_ENERGYBOMB]) && [self hasEnergyBomb])
				{
					// original energy bomb routine
					[self fireEnergyBomb];
					[self removeEquipmentItem:@"EQ_ENERGY_BOMB"];
				}
				
				exceptionContext = @"escape pod";
				//  shoot 'escape'   // Escape pod launch
				if (([gameView isDown:key_launch_escapepod] || joyButtonState[BUTTON_ESCAPE]) && [self hasEscapePod] && [UNIVERSE station] != nil)
					
				{
					found_target = [self launchEscapeCapsule];
				}
				
				exceptionContext = @"dump cargo";
				//  shoot 'd'   // Dump Cargo
				if (([gameView isDown:key_dump_cargo] || joyButtonState[BUTTON_JETTISON]) && [cargo count] > 0)
				{
					[self dumpCargo];
				}
				
				exceptionContext = @"rotate cargo";
				//  shoot 'R'   // Rotate Cargo
				if ([gameView isDown:key_rotate_cargo])
				{
					if ((!rotateCargo_pressed)&&([cargo count] > 0))
						[self rotateCargo];
					rotateCargo_pressed = YES;
				}
				else
					rotateCargo_pressed = NO;
				
				exceptionContext = @"autopilot C";
				// autopilot 'c'
				if ([gameView isDown:key_autopilot] || joyButtonState[BUTTON_DOCKCPU])   // look for the 'c' key
				{
					if ([self hasDockingComputer] && !autopilot_key_pressed)   // look for the 'c' key
					{
						BOOL isUsingDockingAI = [[shipAI name] isEqual: PLAYER_DOCKING_AI_NAME];
						BOOL isOkayToUseAutopilot = YES;
						
						if (isUsingDockingAI)
						{
							if ([self checkForAegis] != AEGIS_IN_DOCKING_RANGE)
							{
								isOkayToUseAutopilot = NO;
								[self playAutopilotOutOfRange];
								[UNIVERSE addMessage:DESC(@"autopilot-out-of-range") forCount:4.5];
							}
						}
						
						if (isOkayToUseAutopilot)
						{
							[self engageAutopilotToStation:[UNIVERSE station]];
							[UNIVERSE addMessage:DESC(@"autopilot-on") forCount:4.5];
						}
					}
					autopilot_key_pressed = YES;
				}
				else
					autopilot_key_pressed = NO;
				
				exceptionContext = @"autopilot shift-C";
				// autopilot 'C' - dock with target
				if ([gameView isDown:key_autopilot_target])   // look for the 'C' key
				{
					if ([self hasDockingComputer] && (!target_autopilot_key_pressed))
					{
						StationEntity* primeTarget = [self primaryTarget];
						BOOL primeTargetIsHostile = [self hasHostileTarget];
						if (primeTarget != nil && [primeTarget isStation] && 
							!primeTargetIsHostile)
						{
							[self engageAutopilotToStation:primeTarget];
							[UNIVERSE addMessage:DESC(@"autopilot-on") forCount:4.5];
						}
						else
						{
							[self playAutopilotCannotDockWithTarget];
							if (primeTargetIsHostile && [primeTarget isStation])
							{
								[UNIVERSE addMessage:DESC(@"autopilot-target-docking-instructions-denied") forCount:4.5];
							}
							else
							{
								[UNIVERSE addMessage:DESC(@"autopilot-cannot-dock-with-target") forCount:4.5];
							}
						}
					}
					target_autopilot_key_pressed = YES;
				}
				else
					target_autopilot_key_pressed = NO;
				
				exceptionContext = @"autopilot shift-D";
				// autopilot 'D'
				if ([gameView isDown:key_autodock] || joyButtonState[BUTTON_DOCKCPUFAST])   // look for the 'D' key
				{
					if ([self hasDockingComputer] && (!fast_autopilot_key_pressed))   // look for the 'D' key
					{
						if ([self checkForAegis] == AEGIS_IN_DOCKING_RANGE)
						{
							StationEntity *the_station = [UNIVERSE station];
							if (the_station)
							{
								if (legalStatus > 50)
								{
									[self setStatus:STATUS_AUTOPILOT_ENGAGED];
									[self interpretAIMessage:@"DOCKING_REFUSED"];
								}
								else
								{
									if (legalStatus > 0)
									{
										// there's a slight chance you'll be fined for your past offences when autodocking
										int fine_chance = ranrot_rand() & 0x03ff;	//	0..1023
										int government = 1 + [[UNIVERSE currentSystemData] oo_intForKey:KEY_GOVERNMENT];	// 1..8
										if ([UNIVERSE inInterstellarSpace])  government = 2;	// equivalent to Feudal. I'm assuming any station in interstellar space is military. -- Ahruman 2008-05-29
										fine_chance /= government;
										if (fine_chance < legalStatus)
										{
											[self markForFines];
										}
									}
	#if DOCKING_CLEARANCE_ENABLED
									[self setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_GRANTED];
	#endif
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
							[self playAutopilotOutOfRange];
							[UNIVERSE addMessage:DESC(@"autopilot-out-of-range") forCount:4.5];
						}
					}
					fast_autopilot_key_pressed = YES;
				}
				else
					fast_autopilot_key_pressed = NO;
				
	#if DOCKING_CLEARANCE_ENABLED
				exceptionContext = @"docking clearance request";
				// docking clearance request 'L', not available in strict mode
				if ([gameView isDown:key_docking_clearance_request] && ![UNIVERSE strict])
				{
					if (!docking_clearance_request_key_pressed)
					{
						Entity *primeTarget = [self primaryTarget];
						if ((primeTarget)&&(primeTarget->isStation)&&[primeTarget isKindOfClass:[StationEntity class]])
						{
							NSString *stationDockingClearanceStatus = [(StationEntity*)primeTarget acceptDockingClearanceRequestFrom:self];
							if (stationDockingClearanceStatus != nil)
							{
								[self doScriptEvent:@"playerRequestedDockingClearance" withArgument:stationDockingClearanceStatus];
							}
						}
					}
					docking_clearance_request_key_pressed = YES;
				}
				else
					docking_clearance_request_key_pressed = NO;
	#endif
				
				exceptionContext = @"hyperspace";
				// hyperspace 'h'
				if (([gameView isDown:key_hyperspace]) || joyButtonState[BUTTON_HYPERDRIVE])   // look for the 'h' key
				{
					if (!hyperspace_pressed)
					{
						float			dx = target_system_seed.d - galaxy_coordinates.x;
						float			dy = target_system_seed.b - galaxy_coordinates.y;
						double		distance = distanceBetweenPlanetPositions(target_system_seed.d,target_system_seed.b,galaxy_coordinates.x,galaxy_coordinates.y);
						BOOL		jumpOK = YES;
						
						if ((dx == 0) && (dy == 0) && equal_seeds(target_system_seed, system_seed))
						{
							[self playHyperspaceNoTarget];
							[UNIVERSE clearPreviousMessage];
							[UNIVERSE addMessage:DESC(@"witch-no-target") forCount:3.0];
							jumpOK = NO;
						}
						
						if (distance > 7)
						{
							[self playHyperspaceNoFuel];
							[UNIVERSE clearPreviousMessage];
							[UNIVERSE addMessage:DESC(@"witch-too-far") forCount:3.0];
							jumpOK = NO;
						}
						else if ((10.0 * distance > fuel)||(fuel == 0))
						{
							[self playHyperspaceNoFuel];
							[UNIVERSE clearPreviousMessage];
							[UNIVERSE addMessage:DESC(@"witch-no-fuel") forCount:3.0];
							jumpOK = NO;
						}
						
						if ([self status] == STATUS_WITCHSPACE_COUNTDOWN)
						{
							// abort!
							jumpOK = NO;
							galactic_witchjump = NO;
							[self setStatus:STATUS_IN_FLIGHT];
							[self playHyperspaceAborted];
							// say it!
							[UNIVERSE clearPreviousMessage];
							[UNIVERSE addMessage:DESC(@"witch-user-abort") forCount:3.0];
							
							[self doScriptEvent:@"playerCancelledJumpCountdown"];
						}
						
						if (jumpOK)
						{
							galactic_witchjump = NO;
							witchspaceCountdown = hyperspaceMotorSpinTime;
							[self setStatus:STATUS_WITCHSPACE_COUNTDOWN];
							[self playStandardHyperspace];
							// say it!
							[UNIVERSE clearPreviousMessage];
							[UNIVERSE addMessage:[NSString stringWithFormat:DESC(@"witch-to-@-in-f-seconds"), [UNIVERSE getSystemName:target_system_seed], witchspaceCountdown] forCount:1.0];
							[self doScriptEvent:@"playerStartedJumpCountdown"
								  withArguments:[NSArray arrayWithObjects:@"standard", [NSNumber numberWithFloat:witchspaceCountdown], nil]];
							[UNIVERSE preloadPlanetTexturesForSystem:target_system_seed];
						}
					}
					hyperspace_pressed = YES;
				}
				else
					hyperspace_pressed = NO;
				
				exceptionContext = @"galactic hyperspace";
				// Galactic hyperspace 'g'
				if (([gameView isDown:key_galactic_hyperspace] || joyButtonState[BUTTON_GALACTICDRIVE]) &&
					([self hasEquipmentItem:@"EQ_GAL_DRIVE"]))// look for the 'g' key
				{
					if (!galhyperspace_pressed)
					{
						BOOL	jumpOK = YES;
						
						if ([self status] == STATUS_WITCHSPACE_COUNTDOWN)
						{
							// abort!
							jumpOK = NO;
							galactic_witchjump = NO;
							[self setStatus:STATUS_IN_FLIGHT];
							[self playHyperspaceAborted];
							// say it!
							[UNIVERSE clearPreviousMessage];
							[UNIVERSE addMessage:DESC(@"witch-user-abort") forCount:3.0];
							
							[self doScriptEvent:@"playerCancelledJumpCountdown"];
						}
						
						if (jumpOK)
						{
							galactic_witchjump = YES;
							witchspaceCountdown = hyperspaceMotorSpinTime;
							[self setStatus:STATUS_WITCHSPACE_COUNTDOWN];
							[self playGalacticHyperspace];
							// say it!
							[UNIVERSE addMessage:[NSString stringWithFormat:DESC(@"witch-galactic-in-f-seconds"), witchspaceCountdown] forCount:1.0];
							// FIXME: how to preload target system for hyperspace jump?
							
							[self doScriptEvent:@"playerStartedJumpCountdown"
								  withArguments:[NSArray arrayWithObjects:@"galactic", [NSNumber numberWithFloat:witchspaceCountdown], nil]];
						}
					}
					galhyperspace_pressed = YES;
				}
				else
					galhyperspace_pressed = NO;
				
				exceptionContext = @"cloaking device";
				//  shoot '0'   // Cloaking Device
				if (([gameView isDown:key_cloaking_device] || joyButtonState[BUTTON_CLOAK]) && [self hasCloakingDevice])
				{
					if (!cloak_pressed)
					{
						if (!cloaking_device_active)
						{
							if ([self activateCloakingDevice])
							{
								[UNIVERSE addMessage:DESC(@"cloak-on") forCount:2];
								[self playCloakingDeviceOn];
							}
							else
							{
								[UNIVERSE addMessage:DESC(@"cloak-low-juice") forCount:3];
								[self playCloakingDeviceInsufficientEnergy];
							}
						}
						else
						{
							[self deactivateCloakingDevice];
							[UNIVERSE addMessage:DESC(@"cloak-off") forCount:2];
							[self playCloakingDeviceOff];
						}
					}
					cloak_pressed = YES;
				}
				else
					cloak_pressed = NO;
				
			}
			
	#ifndef NDEBUG
			exceptionContext = @"dump target state";
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
			
			//  text displays
			exceptionContext = @"pollGuiScreenControls";
			[self pollGuiScreenControls];
		}
		else
		{
			// game is paused
			
			// check options menu request
			exceptionContext = @"options menu";
			if ((([gameView isDown:gvFunctionKey2])||([gameView isDown:gvNumberKey2]))&&(gui_screen != GUI_SCREEN_OPTIONS))
			{
				[gameView clearKeys];
				[self setGuiToLoadSaveScreen];
			}
			
			if (gui_screen == GUI_SCREEN_OPTIONS || gui_screen == GUI_SCREEN_GAMEOPTIONS || gui_screen == GUI_SCREEN_STICKMAPPER)
			{
				if ([UNIVERSE pauseMessageVisible]) [[UNIVERSE message_gui] leaveLastLine];
				else [[UNIVERSE message_gui] clear];
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
			
			exceptionContext = @"debug keys";
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
			
	#endif
			
			if ([gameView isDown:'s'])// look for the 's' key
			{
				OOLogSetDisplayMessagesInClass(@"$shaderDebugOn", YES);
				[UNIVERSE addMessage:@"Shader debug ON" forCount:3];
			}

			if (([gameView isDown:gvArrowKeyLeft] || [gameView isDown:gvArrowKeyRight]) && gui_screen != GUI_SCREEN_GAMEOPTIONS)
			{
				if (!leftRightKeyPressed)
				{
					float newTimeAccelerationFactor = [gameView isDown:gvArrowKeyLeft] ? 
							OOMax_f([UNIVERSE timeAccelerationFactor] / 2.0f, TIME_ACCELERATION_FACTOR_MIN) :
							OOMin_f([UNIVERSE timeAccelerationFactor] * 2.0f, TIME_ACCELERATION_FACTOR_MAX);
					[UNIVERSE setTimeAccelerationFactor:newTimeAccelerationFactor];
				}
				leftRightKeyPressed = YES;
			}
			else
				leftRightKeyPressed = NO;
					
			
			if ([gameView isDown:'n'])// look for the 'n' key
			{
	#ifndef NDEBUG
				gDebugFlags = 0;
				[UNIVERSE addMessage:@"All debug flags OFF" forCount:3];
	#else
				[UNIVERSE addMessage:@"Shader debug OFF" forCount:3];
	#endif	// NDEBUG
				OOLogSetDisplayMessagesInClass(@"$shaderDebugOn", NO);
			}
		}
		
		exceptionContext = @"pause";
		// Pause game 'p'
		if ([gameView isDown:key_pausebutton] && gui_screen != GUI_SCREEN_LONG_RANGE_CHART)// look for the 'p' key
		{
			if (!pause_pressed)
			{
				if (paused)
				{
					script_time = saved_script_time;
					// Reset to correct GUI screen, if we are unpausing from one.
					// Don't set gui_screen here, use setGuis - they also switch backgrounds.
					// No gui switching events will be triggered while still paused.
					switch (saved_gui_screen)
					{
						case GUI_SCREEN_STATUS:
							[self setGuiToStatusScreen];
							break;
						case GUI_SCREEN_SHORT_RANGE_CHART:
							[self setGuiToShortRangeChartScreen];
							break;
						case GUI_SCREEN_MANIFEST:
							[self setGuiToManifestScreen];
							break;
						case GUI_SCREEN_MARKET:
							[self setGuiToMarketScreen];
							break;
						case GUI_SCREEN_SYSTEM_DATA:
							// Do not reset planet rotation if we are already in the system info screen!
							if (gui_screen != GUI_SCREEN_SYSTEM_DATA)
								[self setGuiToSystemDataScreen];
							break;
						default:
							gui_screen = saved_gui_screen;	// make sure we're back to the right screen
							break;
					}
					[gameView allowStringInput:NO];
					[UNIVERSE setDisplayCursor:NO];
					[UNIVERSE clearPreviousMessage];
					[UNIVERSE setViewDirection:saved_view_direction];
					// make sure the light comes from the right direction after resuming from pause!
					if (saved_gui_screen == GUI_SCREEN_SYSTEM_DATA) [UNIVERSE setMainLightPosition:_sysInfoLight];
					[[UNIVERSE gui] setForegroundTextureKey:@"overlay"];
					[[gameView gameController] unpause_game];
				}
				else
				{
					saved_view_direction = [UNIVERSE viewDirection];
					saved_script_time = script_time;
					saved_gui_screen = gui_screen;
					[UNIVERSE sleepytime:nil];	// pause handler
				}
			}
			pause_pressed = YES;
		}
		else
		{
			pause_pressed = NO;
		}
	NS_HANDLER
		// TEMP extra exception checking
		OOLog(kOOLogException, @"***** Exception in pollFlightControls [%@]: %@ : %@", exceptionContext, [localException name], [localException reason]);
	NS_ENDHANDLER
}


- (void) pollGuiArrowKeyControls:(double) delta_t
{
	MyOpenGLView	*gameView = [UNIVERSE gameView];
	BOOL			moving = NO;
	double			cursor_speed = 10.0;
	NSString		*commanderFile;
	GameController  *controller = [UNIVERSE gameController];
	GuiDisplayGen	*gui = [UNIVERSE gui];
	GUI_ROW_INIT(gui);
	
	// deal with string inputs as necessary
	if (gui_screen == GUI_SCREEN_LONG_RANGE_CHART)
	{
		[gameView setStringInput: gvStringInputAlpha];
	}
	else if (gui_screen == GUI_SCREEN_SAVE)
	{
		[gameView setStringInput: gvStringInputAll];
	}
	else
	{
		[gameView allowStringInput: NO];
	}
	
	switch (gui_screen)
	{
		case GUI_SCREEN_LONG_RANGE_CHART:
			if ([gameView isDown:key_advanced_nav_array])   //  '^' key
			{
				if (!pling_pressed)
				{
					if ([self hasEquipmentItem:@"EQ_ADVANCED_NAVIGATIONAL_ARRAY"])  [gui setShowAdvancedNavArray:YES];
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
			
			if ([[gameView typedString] length] > 0)
			{
				planetSearchString = [[[gameView typedString] lowercaseString] retain];
				NSPoint search_coords = [UNIVERSE findSystemCoordinatesWithPrefix:planetSearchString];
				if ((search_coords.x >= 0.0)&&(search_coords.y >= 0.0))
				{
					// always reset the found system index at the beginning of a new search
					if ([planetSearchString length] == 1) [[UNIVERSE gui] targetNextFoundSystem:0];
					found_system_seed = [UNIVERSE findSystemAtCoords:search_coords withGalaxySeed:galaxy_seed];
					moving = YES;
					cursor_coordinates = search_coords;
				}
				else
				{
					found_system_seed = kNilRandomSeed;
					[gameView resetTypedString];
					if (planetSearchString) [planetSearchString release];
					planetSearchString = nil;
				}
			}
			else
			{
				if ([gameView isDown:gvDeleteKey]) // did we just delete the string ?
				{
					found_system_seed = kNilRandomSeed;
					[UNIVERSE findSystemCoordinatesWithPrefix:@""];
				}
				if (planetSearchString) [planetSearchString release];
				planetSearchString = nil;
			}
			
			moving |= (searchStringLength != [[gameView typedString] length]);
			searchStringLength = [[gameView typedString] length];
			
		case GUI_SCREEN_SHORT_RANGE_CHART:
			
			show_info_flag = ([gameView isDown:key_map_info] && ![UNIVERSE strict]);
			
			// If we have entered this screen with the injectors key pressed, make sure
			// that injectors switch off when we release it - Nikos.
			if (afterburner_engaged && ![gameView isDown:key_inject_fuel])
			{
				afterburner_engaged = NO;
			}
			
			if ([self status] != STATUS_WITCHSPACE_COUNTDOWN)
			{
				if ([gameView isDown:gvMouseLeftButton])
				{
					NSPoint maus = [gameView virtualJoystickPosition];
					if (gui_screen == GUI_SCREEN_SHORT_RANGE_CHART)
					{
						double		vadjust = 51;
						double		hscale = MAIN_GUI_PIXEL_WIDTH / 64.0;
						double		vscale = MAIN_GUI_PIXEL_HEIGHT / 128.0;
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
				}
				if ([gameView isDown:key_map_home])
				{
					[gameView resetTypedString];
					cursor_coordinates = galaxy_coordinates;
					found_system_seed = kNilRandomSeed;
					[UNIVERSE findSystemCoordinatesWithPrefix:@""];
					moving = YES;
				}
				
				BOOL nextSystem = [gameView isShiftDown] && gui_screen == GUI_SCREEN_LONG_RANGE_CHART;
				
				if ([gameView isDown:gvArrowKeyLeft])
				{
					if (nextSystem && pressedArrow != gvArrowKeyLeft)
					{
						[self targetNewSystem:-1];
						pressedArrow = gvArrowKeyLeft;
					}
					else if (!nextSystem)
					{
						[gameView resetTypedString];
						cursor_coordinates.x -= cursor_speed*delta_t;
						if (cursor_coordinates.x < 0.0) cursor_coordinates.x = 0.0;
						moving = YES;
					}
				}
				else
					pressedArrow =  pressedArrow == gvArrowKeyLeft ? 0 : pressedArrow;
				
				if ([gameView isDown:gvArrowKeyRight])
				{
					if (nextSystem && pressedArrow != gvArrowKeyRight)
					{
						[self targetNewSystem:+1];
						pressedArrow = gvArrowKeyRight;
					}
					else if (!nextSystem)
					{
						[gameView resetTypedString];
						cursor_coordinates.x += cursor_speed*delta_t;
						if (cursor_coordinates.x > 256.0) cursor_coordinates.x = 256.0;
						moving = YES;
					}
				}
				else
					pressedArrow =  pressedArrow == gvArrowKeyRight ? 0 : pressedArrow;
				
				if ([gameView isDown:gvArrowKeyDown])
				{
					if (nextSystem && pressedArrow != gvArrowKeyDown)
					{
						[self targetNewSystem:+1];
						pressedArrow = gvArrowKeyDown;
					}
					else if (!nextSystem)
					{
						[gameView resetTypedString];
						cursor_coordinates.y += cursor_speed*delta_t*2.0;
						if (cursor_coordinates.y > 256.0) cursor_coordinates.y = 256.0;
						moving = YES;
					}
				}
				else
					pressedArrow =  pressedArrow == gvArrowKeyDown ? 0 : pressedArrow;
				
				if ([gameView isDown:gvArrowKeyUp])
				{
					if (nextSystem && pressedArrow != gvArrowKeyUp)
					{
						[self targetNewSystem:-1];
						pressedArrow = gvArrowKeyUp;
					}	
					else if (!nextSystem)
					{
						[gameView resetTypedString];
						cursor_coordinates.y -= cursor_speed*delta_t*2.0;
						if (cursor_coordinates.y < 0.0) cursor_coordinates.y = 0.0;
						moving = YES;
					}
				}
				else
					pressedArrow =  pressedArrow == gvArrowKeyUp ? 0 : pressedArrow;
				
				if ((cursor_moving)&&(!moving))
				{
					// if found with a search string, don't recalculate! Required for overlapping systems, like Divees & Tezabi in galaxy 5
					if (cursor_coordinates.x != found_system_seed.d && cursor_coordinates.y != found_system_seed.b)
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
			
		case GUI_SCREEN_SYSTEM_DATA:
			if ([self status] == STATUS_DOCKED && [gameView isDown:key_contract_info] && ![UNIVERSE strict])  // '?' toggle between maps/info and contract screen
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
			commanderFile = [self commanderSelector];
			if(commanderFile)
			{
				[self loadPlayerFromFile:commanderFile];
			}
			break;
		case GUI_SCREEN_SAVE:
			[self pollGuiScreenControlsWithFKeyAlias:NO];
			if ([gameView isDown:gvFunctionKey1])  [self handleUndockControl];
			if (gui_screen == GUI_SCREEN_SAVE)
			{
				[self saveCommanderInputHandler];
			}
			else pollControls = YES;
			break;
			
		case GUI_SCREEN_SAVE_OVERWRITE:
			[self overwriteCommanderInputHandler];
			break;
			
#if OOLITE_HAVE_JOYSTICK
		case GUI_SCREEN_STICKMAPPER:
			[self stickMapperInputHandler: gui view: gameView];

			leftRightKeyPressed = [gameView isDown:gvArrowKeyRight]|[gameView isDown:gvArrowKeyLeft];
			if (leftRightKeyPressed)
			{
				NSString* key = [gui keyForRow: [gui selectedRow]];
				if ([gameView isDown:gvArrowKeyRight])
				{
					key = [gui keyForRow: GUI_ROW_FUNCEND];
				}
				if ([gameView isDown:gvArrowKeyLeft])
				{
					key = [gui keyForRow: GUI_ROW_FUNCSTART];
				}
				int from_function = [[[key componentsSeparatedByString:@":"] objectAtIndex: 1] intValue];
				if (from_function < 0)  from_function = 0;
				
				[self setGuiToStickMapperScreen:from_function];
				if ([[UNIVERSE gui] selectedRow] < 0)
					[[UNIVERSE gui] setSelectedRow: GUI_ROW_FUNCSTART];
				if (from_function == 0)
					[[UNIVERSE gui] setSelectedRow: GUI_ROW_FUNCSTART + MAX_ROWS_FUNCTIONS - 1];
			}
			break;
#endif
			
		case GUI_SCREEN_GAMEOPTIONS:
			[self handleGameOptionsScreenKeys];
			break;
			
		case GUI_SCREEN_OPTIONS:
			[self handleGUIUpDownArrowKeys];
			int guiSelectedRow = [gui selectedRow];
			BOOL selectKeyPress = ([gameView isDown:13]||[gameView isDown:gvMouseDoubleClick]);
			
			if (selectKeyPress)   // 'enter'
			{
				if ((guiSelectedRow == GUI_ROW(,QUICKSAVE))&&(!disc_operation_in_progress))
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
				if ((guiSelectedRow == GUI_ROW(,SAVE))&&(!disc_operation_in_progress))
				{
					disc_operation_in_progress = YES;
					[self savePlayer];
				}
				if ((guiSelectedRow == GUI_ROW(,LOAD))&&(!disc_operation_in_progress))
				{
					disc_operation_in_progress = YES;
					if (![self loadPlayer])
					{
						disc_operation_in_progress = NO;
						[self setGuiToStatusScreen];
					}
				}
				
				
				if ((guiSelectedRow == GUI_ROW(,BEGIN_NEW))&&(!disc_operation_in_progress))
				{
					disc_operation_in_progress = YES;
					[UNIVERSE reinitAndShowDemo:YES];
				}
				
				if ([gameView isDown:gvMouseDoubleClick])
					[gameView clearMouse];
			}
			else
			{
				disc_operation_in_progress = NO;
			}
			
#if OOLITE_SDL
			// quit only appears in GNUstep as users aren't
			// used to Cmd-Q equivs. Same goes for window
			// vs fullscreen.
			if ((guiSelectedRow == GUI_ROW(,QUIT)) && selectKeyPress)
			{
				[[gameView gameController] exitApp];
			}
#endif
			
			if ((guiSelectedRow == GUI_ROW(,GAMEOPTIONS)) && selectKeyPress)
			{
				[gameView clearKeys];
				[self setGuiToGameOptionsScreen];
			}
			
			/*	TODO: Investigate why this has to be handled last (if the
			 quit item and this are swapped, the game crashes if
			 strict mode is selected with SIGSEGV in the ObjC runtime
			 system. The stack trace shows it crashes when it hits
			 the if statement, trying to send the message to one of
			 the things contained.) */
			if ((guiSelectedRow == GUI_ROW(,STRICT))&& selectKeyPress)
			{
				[UNIVERSE setStrict:![UNIVERSE strict]];
			}
			
			break;
			
		case GUI_SCREEN_EQUIP_SHIP:
			if ([self handleGUIUpDownArrowKeys])
			{
				NSString		*itemText = [gui selectedRowText];
				OOWeaponType		weaponType = WEAPON_UNDEFINED;
				
				if ([itemText isEqual:FORWARD_FACING_STRING]) weaponType = forward_weapon_type;
				if ([itemText isEqual:AFT_FACING_STRING]) weaponType = aft_weapon_type;
				if ([itemText isEqual:PORT_FACING_STRING]) weaponType = port_weapon_type;
				if ([itemText isEqual:STARBOARD_FACING_STRING]) weaponType = starboard_weapon_type;
				
				if (weaponType != WEAPON_UNDEFINED)
				{
					BOOL		sameAs = EquipmentStringToWeaponTypeSloppy([gui selectedRowKey]) == weaponType;
					// override showInformation _completely_ with itemText
					if (weaponType == WEAPON_NONE)  itemText = DESC(@"no-weapon-enter-to-install");
					else
					{
						NSString *weaponName = [UNIVERSE descriptionForArrayKey:@"weapon_name" index:weaponType];
						if (sameAs)  itemText = [NSString stringWithFormat:DESC(@"weapon-installed-@"), weaponName];
						else  itemText = [NSString stringWithFormat:DESC(@"weapon-@-enter-to-replace"), weaponName];
					}
					
					[self showInformationForSelectedUpgradeWithFormatString:itemText];
				}
				else
					[self showInformationForSelectedUpgrade];
			}
			
			if ([gameView isDown:gvArrowKeyLeft])
			{
				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if ([[gui keyForRow:GUI_ROW_EQUIPMENT_START] hasPrefix:@"More:"])
					{
						[self playMenuPagePrevious];
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
						[self playMenuPageNext];
						[gui setSelectedRow:GUI_ROW_EQUIPMENT_START + GUI_MAX_ROWS_EQUIPMENT - 1];
						[self buySelectedItem];
					}
					timeLastKeyPress = script_time;
				}
			}
			leftRightKeyPressed = [gameView isDown:gvArrowKeyRight]|[gameView isDown:gvArrowKeyLeft];
			
			if ([gameView isDown:13] || [gameView isDown:gvMouseDoubleClick])   // 'enter'
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
			break;
			
		case GUI_SCREEN_MARKET:
			if ([self status] == STATUS_DOCKED)
			{
				[self handleGUIUpDownArrowKeys];
				
				if (([gameView isDown:gvArrowKeyRight])||([gameView isDown:gvArrowKeyLeft])||([gameView isDown:13]||[gameView isDown:gvMouseDoubleClick]))
				{
					if ([gameView isDown:gvArrowKeyRight])   // -->
					{
						if (!wait_for_key_up)
						{
							int item = [(NSString *)[gui selectedRowKey] intValue];
							if ([self tryBuyingCommodity:item all:[gameView isShiftDown]])
							{
								[self playBuyCommodity];
								[self setGuiToMarketScreen];
							}
							else
							{
								[self playCantBuyCommodity];
							}
							wait_for_key_up = YES;
						}
					}
					if ([gameView isDown:gvArrowKeyLeft])   // <--
					{
						if (!wait_for_key_up)
						{
							int item = [(NSString *)[gui selectedRowKey] intValue];
							if ([self trySellingCommodity:item all:[gameView isShiftDown]])
							{
								[self playSellCommodity];
								[self setGuiToMarketScreen];
							}
							else
							{
								[self playCantSellCommodity];
							}
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
							int yours =		[[shipCommodityData oo_arrayAtIndex:item] oo_intAtIndex:1];
							if ([gameView isShiftDown] && [self tryBuyingCommodity:item all:YES])	// buy as much as possible (with Shift)
							{
								[self playBuyCommodity];
								[self setGuiToMarketScreen];
							}
							else if ((yours > 0) && [self trySellingCommodity:item all:YES])	// sell all you can
							{
								[self playSellCommodity];
								[self setGuiToMarketScreen];
							}
							else if ([self tryBuyingCommodity:item all:YES])			// buy as much as possible
							{
								[self playBuyCommodity];
								[self setGuiToMarketScreen];
							}
							else
							{
								[self playCantBuyCommodity];
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
			
		case GUI_SCREEN_CONTRACTS:
			if ([self status] == STATUS_DOCKED)
			{
				if ([self handleGUIUpDownArrowKeys])
					[self setGuiToContractsScreen];
				
				if ([self status] == STATUS_DOCKED && ([gameView isDown:13] || [gameView isDown:gvMouseDoubleClick]))   // 'enter' | doubleclick
				{
					if ([gameView isDown:gvMouseDoubleClick])
						[gameView clearMouse];
					if (!selectPressed)
					{
						if ([self pickFromGuiContractsScreen])
						{
							[self playBuyCommodity];
							[self setGuiToContractsScreen];
						}
						else
						{
							[self playCantBuyCommodity];
						}
					}
					selectPressed = YES;
				}
				else
				{
					selectPressed = NO;
				}
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
			
		case GUI_SCREEN_REPORT:
			if ([gameView isDown:32])	// spacebar
			{
				if (!spacePressed)
				{
					BOOL reportEnded = ([dockingReport length] == 0);
					[self playDismissedReportScreen];
					[self setGuiToStatusScreen];
					if(reportEnded)
					{
						[self doScriptEvent:@"reportScreenEnded"];  // last report given. Screen is now free for missionscreens.
						[self doWorldEventUntilMissionScreen:@"missionScreenOpportunity"];
					}
				}
				spacePressed = YES;
			}
			else
				spacePressed = NO;
			break;
		case GUI_SCREEN_STATUS:
			[self handleGUIUpDownArrowKeys];
			if ([gameView isDown:gvArrowKeyLeft])
			{

				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if ([[gui keyForRow:STATUS_EQUIPMENT_FIRST_ROW] isEqual:GUI_KEY_OK])
					{
						[gui setSelectedRow:STATUS_EQUIPMENT_FIRST_ROW];
						[self playMenuPagePrevious];
						[gui setStatusPage:-1];
						[self setGuiToStatusScreen];
					}
					timeLastKeyPress = script_time;
				}
			}
			if ([gameView isDown:gvArrowKeyRight])
			{

				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if ([[gui keyForRow:STATUS_EQUIPMENT_FIRST_ROW + STATUS_EQUIPMENT_MAX_ROWS] isEqual:GUI_KEY_OK])
					{
						[gui setSelectedRow:STATUS_EQUIPMENT_FIRST_ROW + STATUS_EQUIPMENT_MAX_ROWS];
						[self playMenuPageNext];
						[gui setStatusPage:+1];
						[self setGuiToStatusScreen];
					}
					timeLastKeyPress = script_time;
				}
			}
			leftRightKeyPressed = [gameView isDown:gvArrowKeyRight]|[gameView isDown:gvArrowKeyLeft];
			
			if ([gameView isDown:13] || [gameView isDown:gvMouseDoubleClick])   // 'enter'
			{
				if ([gameView isDown:gvMouseDoubleClick])
				{
					selectPressed = NO;
					[gameView clearMouse];
				}
				if ((!selectPressed)&&([gui selectedRow] > -1))
				{
					[gui setStatusPage:([gui selectedRow] == STATUS_EQUIPMENT_FIRST_ROW ? -1 : +1)];
					[self setGuiToStatusScreen];

					selectPressed = YES;
				}
			}
			else
			{
				selectPressed = NO;
			}

			break;
		case GUI_SCREEN_SHIPYARD:
			if ([self handleGUIUpDownArrowKeys])
			{
				[self showShipyardInfoForSelection];
			}
			
			if ([gameView isDown:gvArrowKeyLeft])
			{
				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if ([[gui keyForRow:GUI_ROW_SHIPYARD_START] hasPrefix:@"More:"])
					{
						[self playMenuPagePrevious];
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
						[self playMenuPageNext];
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
						if (money != credits)	// money == credits means we skipped to another page, don't do anything
						{
							[UNIVERSE removeDemoShips];
							[self setGuiToStatusScreen];
							[self playBuyShip];
							[self doScriptEvent:@"playerBoughtNewShip" withArgument:self]; // some equipment.oxp might want to know everything has changed.
						}
					}
					else
					{
						[self playCantBuyShip];
					}
				}
				selectPressed = YES;
			}
			else
			{
				selectPressed = NO;
			}
			break;
			
		default:
			break;
	}
	
	// damp any rotations we entered with
	if (flightRoll > 0.0)
	{
		if (flightRoll > delta_t)		[self decrease_flight_roll:delta_t];
		else	flightRoll = 0.0;
	}
	if (flightRoll < 0.0)
	{
		if (flightRoll < -delta_t)		[self increase_flight_roll:delta_t];
		else	flightRoll = 0.0;
	}
	if (flightPitch > 0.0)
	{
		if (flightPitch > delta_t)		[self decrease_flight_pitch:delta_t];
		else	flightPitch = 0.0;
	}
	if (flightPitch < 0.0)
	{
		if (flightPitch < -delta_t)		[self increase_flight_pitch:delta_t];
		else	flightPitch = 0.0;
	}
	if (flightYaw > 0.0) 
	{ 
		if (flightYaw > delta_t)		[self decrease_flight_yaw:delta_t]; 
		else	flightYaw = 0.0; 
	} 
	if (flightYaw < 0.0) 
	{ 
		if (flightYaw < -delta_t)		[self increase_flight_yaw:delta_t]; 
		else	flightYaw = 0.0; 
	} 
}


- (void) handleGameOptionsScreenKeys
{
	GameController		*controller = [UNIVERSE gameController];
	NSArray				*modes = [controller displayModes];
	MyOpenGLView		*gameView = [UNIVERSE gameView];
	GuiDisplayGen		*gui = [UNIVERSE gui];
	GUI_ROW_INIT(gui);
	
	[self handleGUIUpDownArrowKeys];
	int guiSelectedRow = [gui selectedRow];
	BOOL selectKeyPress = ([gameView isDown:13]||[gameView isDown:gvMouseDoubleClick]);
	if ([gameView isDown:gvMouseDoubleClick])
		[gameView clearMouse];
		
	
#if OOLITE_HAVE_JOYSTICK
	if ((guiSelectedRow == GUI_ROW(GAME,STICKMAPPER)) && selectKeyPress)
	{
		selFunctionIdx = 0;
		[self setGuiToStickMapperScreen: 0];
	}
#endif

	if (!switching_resolution &&
		guiSelectedRow == GUI_ROW(GAME,DISPLAY) &&
		([gameView isDown:gvArrowKeyRight] || [gameView isDown:gvArrowKeyLeft]))
	{
		int			direction = ([gameView isDown:gvArrowKeyRight]) ? 1 : -1;
		OOInteger	displayModeIndex = [controller indexOfCurrentDisplayMode];
		if (displayModeIndex == NSNotFound)
		{
			OOLogWARN(@"graphics.mode.notFound", @"couldn't find current fullscreen setting, switching to default.");
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
		int modeWidth = [mode oo_intForKey:kOODisplayWidth];
		int modeHeight = [mode oo_intForKey:kOODisplayHeight];
		int modeRefresh = [mode oo_intForKey:kOODisplayRefreshRate];
		[controller setDisplayWidth:modeWidth Height:modeHeight Refresh:modeRefresh];

		NSString *displayModeString = [self screenModeStringForWidth:modeWidth height:modeHeight refreshRate:modeRefresh];
		
		[self playChangedOption];
		[gui setText:displayModeString	forRow:GUI_ROW(GAME,DISPLAY)  align:GUI_ALIGN_CENTER];
		switching_resolution = YES;
#if OOLITE_HAVE_APPKIT
		if ([controller inFullScreenMode]) [controller changeFullScreenResolution]; // changes fullscreen mode immediately
#elif OOLITE_SDL
		/*	TODO: The gameView for the SDL game currently holds and
		 sets the actual screen resolution (controller just stores
		 it). This probably ought to change. */
		[gameView setScreenSize: displayModeIndex]; // changes fullscreen mode immediately
#endif
	}
	if (switching_resolution && ![gameView isDown:gvArrowKeyRight] && ![gameView isDown:gvArrowKeyLeft] && !selectKeyPress)
	{
		switching_resolution = NO;
	}
	
#if OOLITE_SPEECH_SYNTH
	if ((guiSelectedRow == GUI_ROW(GAME,SPEECH))&&(([gameView isDown:gvArrowKeyRight])||([gameView isDown:gvArrowKeyLeft])))
	{
		if ([gameView isDown:gvArrowKeyRight] != isSpeechOn)
			[self playChangedOption];
		isSpeechOn = [gameView isDown:gvArrowKeyRight];
		NSString *message = DESC(isSpeechOn ? @"gameoptions-spoken-messages-yes" : @"gameoptions-spoken-messages-no");
		[gui setText:message	forRow:GUI_ROW(GAME,SPEECH)  align:GUI_ALIGN_CENTER];
		if (isSpeechOn)
		{
			[UNIVERSE stopSpeaking];
			[UNIVERSE startSpeakingString:message];
		}
	}
#if OOLITE_ESPEAK
	if (guiSelectedRow == GUI_ROW(GAME,SPEECH_LANGUAGE))
	{
		if ([gameView isDown:gvArrowKeyRight] || [gameView isDown:gvArrowKeyLeft])
		{
			if (!leftRightKeyPressed && script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL)
			{
				[self playChangedOption];
				if ([gameView isDown:gvArrowKeyRight])
					voice_no = [UNIVERSE nextVoice: voice_no];
				else
					voice_no = [UNIVERSE prevVoice: voice_no];
				[UNIVERSE setVoice: voice_no withGenderM:voice_gender_m];
				NSString *message = [NSString stringWithFormat:DESC(@"gameoptions-voice-@"), [UNIVERSE voiceName: voice_no]];
				[gui setText:message forRow:GUI_ROW(GAME,SPEECH_LANGUAGE) align:GUI_ALIGN_CENTER];
				if (isSpeechOn)
				{
					[UNIVERSE stopSpeaking];
					[UNIVERSE startSpeakingString:[UNIVERSE voiceName: voice_no]];
				}
			}
			leftRightKeyPressed = YES;
		}
		else
			leftRightKeyPressed = NO;
	}

	if (guiSelectedRow == GUI_ROW(GAME,SPEECH_GENDER))
	{
		if ([gameView isDown:gvArrowKeyRight] || [gameView isDown:gvArrowKeyLeft])
		{
			if (!leftRightKeyPressed && script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL)
			{
				[self playChangedOption];
				BOOL m = [gameView isDown:gvArrowKeyRight];
				if (m != voice_gender_m)
				{
					voice_gender_m = m;
					[UNIVERSE setVoice:voice_no withGenderM:voice_gender_m];
					NSString *message = [NSString stringWithFormat:DESC(voice_gender_m ? @"gameoptions-voice-M" : @"gameoptions-voice-F")];
					[gui setText:message forRow:GUI_ROW(GAME,SPEECH_GENDER) align:GUI_ALIGN_CENTER];
					if (isSpeechOn)
					{
						[UNIVERSE stopSpeaking];
						[UNIVERSE startSpeakingString:[UNIVERSE voiceName: voice_no]];
					}
				}
			}
			leftRightKeyPressed = YES;
		}
		else
			leftRightKeyPressed = NO;
	}
#endif
#endif
	
	if ((guiSelectedRow == GUI_ROW(GAME,MUSIC))&&(([gameView isDown:gvArrowKeyRight])||([gameView isDown:gvArrowKeyLeft])))
	{
		if (!musicModeKeyPressed)
		{
			OOMusicController	*musicController = [OOMusicController sharedController];
			int					initialMode = [musicController mode];
			int					mode = initialMode;
			
			if ([gameView isDown:gvArrowKeyRight])  mode++;
			if ([gameView isDown:gvArrowKeyLeft])  mode--;
			
			[musicController setMode:MAX(mode, 0)];
			
			if ((int)[musicController mode] != initialMode)
			{
				[self playChangedOption];
				NSString *message = [NSString stringWithFormat:DESC(@"gameoptions-music-mode-@"), [UNIVERSE descriptionForArrayKey:@"music-mode" index:mode]];
				[gui setText:message forRow:GUI_ROW(GAME,MUSIC)  align:GUI_ALIGN_CENTER];
			}
		}
		musicModeKeyPressed = YES;
	}
	else  musicModeKeyPressed = NO;
	
	if ((guiSelectedRow == GUI_ROW(GAME,AUTOSAVE))&&(([gameView isDown:gvArrowKeyRight])||([gameView isDown:gvArrowKeyLeft])))
	{
		if ([gameView isDown:gvArrowKeyRight] != [UNIVERSE autoSave])
			[self playChangedOption];
		[UNIVERSE setAutoSave:[gameView isDown:gvArrowKeyRight]];
		if ([UNIVERSE autoSave])
		{
			// if just enabled, we want to autosave immediately
			[UNIVERSE setAutoSaveNow:YES];
			[gui setText:DESC(@"gameoptions-autosave-yes")	forRow:GUI_ROW(GAME,AUTOSAVE)  align:GUI_ALIGN_CENTER];
		}
		else
		{
			[UNIVERSE setAutoSaveNow:NO];
			[gui setText:DESC(@"gameoptions-autosave-no")	forRow:GUI_ROW(GAME,AUTOSAVE)  align:GUI_ALIGN_CENTER];
		}
	}

	if ((guiSelectedRow == GUI_ROW(GAME,VOLUME))
		&&(([gameView isDown:gvArrowKeyRight])||([gameView isDown:gvArrowKeyLeft]))
		&&[OOSound respondsToSelector:@selector(masterVolume)])
	{
		if ((!volumeControlPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
		{
			BOOL rightKeyDown = [gameView isDown:gvArrowKeyRight];
			BOOL leftKeyDown = [gameView isDown:gvArrowKeyLeft];
			int volume = 100 * [OOSound masterVolume];
			volume += (((rightKeyDown && (volume < 100)) ? 5 : 0) - ((leftKeyDown && (volume > 0)) ? 5 : 0));
			if (volume > 100) volume = 100;
			if (volume < 0) volume = 0;
			[OOSound setMasterVolume: 0.01 * volume];
			[self playChangedOption];
			if (volume > 0)
			{
				NSString* soundVolumeWordDesc = DESC(@"gameoptions-sound-volume");
				NSString* v1_string = @"|||||||||||||||||||||||||";
				NSString* v0_string = @".........................";
				v1_string = [v1_string substringToIndex:volume / 5];
				v0_string = [v0_string substringToIndex:20 - volume / 5];
				[gui setText:[NSString stringWithFormat:@"%@%@%@ ", soundVolumeWordDesc, v1_string, v0_string]	forRow:GUI_ROW(GAME,VOLUME)  align:GUI_ALIGN_CENTER];
			}
			else
				[gui setText:DESC(@"gameoptions-sound-volume-mute")	forRow:GUI_ROW(GAME,VOLUME)  align:GUI_ALIGN_CENTER];
			timeLastKeyPress = script_time;
		}
		volumeControlPressed = YES;
	}
	else
		volumeControlPressed = NO;
	
#if OOLITE_MAC_OS_X
	if ((guiSelectedRow == GUI_ROW(GAME,GROWL))&&([gameView isDown:gvArrowKeyRight]||[gameView isDown:gvArrowKeyLeft]))
	{
		if ([Groolite isEnabled] && (!leftRightKeyPressed || script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
		{
			NSUserDefaults* prefs = [NSUserDefaults standardUserDefaults];
			BOOL rightKeyDown = [gameView isDown:gvArrowKeyRight];
			BOOL leftKeyDown = [gameView isDown:gvArrowKeyLeft];
			int growl_min_priority = 3;
			if ([prefs objectForKey:@"groolite-min-priority"])
				growl_min_priority = [prefs integerForKey:@"groolite-min-priority"];
			int new_priority = growl_min_priority;
			if (rightKeyDown)
				new_priority--;
			if (leftKeyDown)
				new_priority++;
			if (new_priority < kGroolitePriorityMinimum)	// sanity check values -2 .. 3
				new_priority = kGroolitePriorityMinimum;
			if (new_priority > kGroolitePriorityMaximum)
				new_priority = kGroolitePriorityMaximum;
			if (new_priority != growl_min_priority)
			{
				growl_min_priority = new_priority;
				NSString* growl_priority_desc = [Groolite priorityDescription:growl_min_priority];
				[gui setText:[NSString stringWithFormat:DESC(@"gameoptions-show-growl-messages-@"), growl_priority_desc]
					  forRow:GUI_ROW(GAME,GROWL) align:GUI_ALIGN_CENTER];
				[self playChangedOption];
				[prefs setInteger:growl_min_priority forKey:@"groolite-min-priority"];
			}
			timeLastKeyPress = script_time;
		}
		leftRightKeyPressed = YES;
	}
	else
		leftRightKeyPressed = NO;
#endif
	
	if ((guiSelectedRow == GUI_ROW(GAME,WIREFRAMEGRAPHICS))&&(([gameView isDown:gvArrowKeyRight])||([gameView isDown:gvArrowKeyLeft])))
	{
		if ([gameView isDown:gvArrowKeyRight] != [UNIVERSE wireframeGraphics])
			[self playChangedOption];
		[UNIVERSE setWireframeGraphics:[gameView isDown:gvArrowKeyRight]];
		if ([UNIVERSE wireframeGraphics])
			[gui setText:DESC(@"gameoptions-wireframe-graphics-yes")  forRow:GUI_ROW(GAME,WIREFRAMEGRAPHICS)  align:GUI_ALIGN_CENTER];
		else
			[gui setText:DESC(@"gameoptions-wireframe-graphics-no")  forRow:GUI_ROW(GAME,WIREFRAMEGRAPHICS)  align:GUI_ALIGN_CENTER];
	}
	
#if ALLOW_PROCEDURAL_PLANETS
	if ((guiSelectedRow == GUI_ROW(GAME,PROCEDURALLYTEXTUREDPLANETS))&&(([gameView isDown:gvArrowKeyRight])||([gameView isDown:gvArrowKeyLeft])))
	{
		if ([gameView isDown:gvArrowKeyRight] != [UNIVERSE doProcedurallyTexturedPlanets])
		{
			[UNIVERSE setDoProcedurallyTexturedPlanets:[gameView isDown:gvArrowKeyRight]];
			[self playChangedOption];
			if ([UNIVERSE planet])
			{
				[UNIVERSE setUpPlanet];
			}
		}
		if ([UNIVERSE doProcedurallyTexturedPlanets])
			[gui setText:DESC(@"gameoptions-procedurally-textured-planets-yes")  forRow:GUI_ROW(GAME,PROCEDURALLYTEXTUREDPLANETS)  align:GUI_ALIGN_CENTER];
		else
			[gui setText:DESC(@"gameoptions-procedurally-textured-planets-no")  forRow:GUI_ROW(GAME,PROCEDURALLYTEXTUREDPLANETS)  align:GUI_ALIGN_CENTER];
	}
#endif
	
	if ((guiSelectedRow == GUI_ROW(GAME,DETAIL))&&(([gameView isDown:gvArrowKeyRight])||([gameView isDown:gvArrowKeyLeft])))
	{
		if ([gameView isDown:gvArrowKeyRight] != [UNIVERSE reducedDetail])
			[self playChangedOption];
		[UNIVERSE setReducedDetail:[gameView isDown:gvArrowKeyRight]];
		if ([UNIVERSE reducedDetail])
			[gui setText:DESC(@"gameoptions-reduced-detail-yes")	forRow:GUI_ROW(GAME,DETAIL)  align:GUI_ALIGN_CENTER];
		else
			[gui setText:DESC(@"gameoptions-reduced-detail-no")	forRow:GUI_ROW(GAME,DETAIL)  align:GUI_ALIGN_CENTER];
	}
	
	
	if (guiSelectedRow == GUI_ROW(GAME,SHADEREFFECTS) && ([gameView isDown:gvArrowKeyRight] || [gameView isDown:gvArrowKeyLeft]))
	{
		if (!shaderSelectKeyPressed || (script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
		{
			int direction = ([gameView isDown:gvArrowKeyRight]) ? 1 : -1;
			OOShaderSetting shaderEffects = [UNIVERSE shaderEffectsLevel] + direction;
			[UNIVERSE setShaderEffectsLevel:shaderEffects];
			shaderEffects = [UNIVERSE shaderEffectsLevel];
			
			[gui setText:[NSString stringWithFormat:DESC(@"gameoptions-shaderfx-@"), ShaderSettingToDisplayString(shaderEffects)]
				  forRow:GUI_ROW(GAME,SHADEREFFECTS)
				   align:GUI_ALIGN_CENTER];
			timeLastKeyPress = script_time;
		}
		shaderSelectKeyPressed = YES;
	}
	else shaderSelectKeyPressed = NO;
	
#if OOLITE_SDL
	if ((guiSelectedRow == GUI_ROW(GAME,DISPLAYSTYLE)) && selectKeyPress)
	{
		[gameView toggleScreenMode];
		// redraw GUI
		[self setGuiToGameOptionsScreen];
	}
#endif

	if ((guiSelectedRow == GUI_ROW(GAME,BACK)) && selectKeyPress)
	{
		[gameView clearKeys];
		[self setGuiToLoadSaveScreen];
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


- (void) pollViewControls
{
	if(!pollControls)
		return;
	
	MyOpenGLView	*gameView = [UNIVERSE gameView];
	
	NSPoint			virtualView = NSZeroPoint;
	double			view_threshold = 0.5;

	if (!stickHandler)
	{
		stickHandler = [gameView getStickHandler];
	}

	if ([stickHandler getNumSticks])
	{
		virtualView = [stickHandler getViewAxis];
		if (virtualView.y == STICK_AXISUNASSIGNED)
			virtualView.y = 0.0;
		if (virtualView.x == STICK_AXISUNASSIGNED)
			virtualView.x = 0.0;
		if (fabs(virtualView.y) >= fabs(virtualView.x))
			virtualView.x = 0.0; // forward/aft takes precedence
		else
			virtualView.y = 0.0;
	}

	const BOOL *joyButtonState = [stickHandler getAllButtonStates];

	//  view keys
	if (([gameView isDown:gvFunctionKey1])||([gameView isDown:gvNumberKey1])||(virtualView.y < -view_threshold)||joyButtonState[BUTTON_VIEWFORWARD] || ((([gameView isDown:key_hyperspace] && gui_screen != GUI_SCREEN_LONG_RANGE_CHART) || joyButtonState[BUTTON_HYPERDRIVE]) && [UNIVERSE displayGUI]))
	{
		[self switchToThisView:VIEW_FORWARD];
	}
	if (([gameView isDown:gvFunctionKey2])||([gameView isDown:gvNumberKey2])||(virtualView.y > view_threshold)||joyButtonState[BUTTON_VIEWAFT])
	{
		[self switchToThisView:VIEW_AFT];
	}
	if (([gameView isDown:gvFunctionKey3])||([gameView isDown:gvNumberKey3])||(virtualView.x < -view_threshold)||joyButtonState[BUTTON_VIEWPORT])
	{
		[self switchToThisView:VIEW_PORT];
	}
	if (([gameView isDown:gvFunctionKey4])||([gameView isDown:gvNumberKey4])||(virtualView.x > view_threshold)||joyButtonState[BUTTON_VIEWSTARBOARD])
	{
		[self switchToThisView:VIEW_STARBOARD];
	}
	
	if ([gameView isDown:key_custom_view])
	{
		if (!customView_pressed && [_customViews count] != 0 && ![UNIVERSE displayCursor])
		{
			if ([UNIVERSE viewDirection] == VIEW_CUSTOM)	// already in custom view mode
			{
				// rotate the custom views
				_customViewIndex = (_customViewIndex + 1) % [_customViews count];
			}
			
			[self setCustomViewDataFromDictionary:[_customViews oo_dictionaryAtIndex:_customViewIndex]];
			
			if ([UNIVERSE displayGUI])
				[self switchToMainView];
			[UNIVERSE setViewDirection:VIEW_CUSTOM];
		}
		customView_pressed = YES;
	}
	else
		customView_pressed = NO;
	
	// Zoom scanner 'z'
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
	
	// Unzoom scanner 'Z'
	if ([gameView isDown:key_scanner_unzoom] && ([gameView allowingStringInput] == gvStringInputNo)) // look for the 'Z' key
	{
		if ((!scanner_zoom_rate)&&([hud scanner_zoom] > 1.0))
			scanner_zoom_rate = SCANNER_ZOOM_RATE_DOWN;
	}
	
	// Compass mode '\'
	if ([gameView isDown:key_next_compass_mode]) // look for the '\' key
	{
		if ((!compass_mode_pressed)&&(compassMode != COMPASS_MODE_BASIC))
			[self setNextCompassMode];
		compass_mode_pressed = YES;
	}
	else
	{
		compass_mode_pressed = NO;
	}
	
	//  show comms log '`'
	if ([gameView isDown:key_comms_log])
	{
		[UNIVERSE showCommsLog: 1.5];
		[hud refreshLastTransmitter];
	}
}


- (void) pollFlightArrowKeyControls:(double)delta_t
{
	MyOpenGLView	*gameView = [UNIVERSE gameView];
	NSPoint			virtualStick = NSZeroPoint;
	double			reqYaw = 0.0;
	double			deadzone;
	
	// TODO: Rework who owns the stick.
	if(!stickHandler)
	{
		stickHandler=[gameView getStickHandler];
	}
	numSticks=[stickHandler getNumSticks];
	deadzone = STICK_DEADZONE / [stickHandler getSensitivity];
	
	/*	DJS: Handle inputs on the joy roll/pitch axis.
	 Mouse control on takes precidence over joysticks.
	 We have to assume the player has a reason for switching mouse
	 control on if they have a joystick - let them do it. */
	if(mouse_control_on)
	{
		virtualStick=[gameView virtualJoystickPosition];
		double sensitivity = 2.0;
		virtualStick.x *= sensitivity;
		virtualStick.y *= sensitivity;
		reqYaw = virtualStick.x;
	}
	else if(numSticks)
	{
		virtualStick=[stickHandler getRollPitchAxis];
		if((virtualStick.x == STICK_AXISUNASSIGNED ||
		   virtualStick.y == STICK_AXISUNASSIGNED) ||
		   (fabs(virtualStick.x) < deadzone &&
		    fabs(virtualStick.y) < deadzone))
		{
			// Not assigned or deadzoned - set to zero.
			virtualStick.x=0;
			virtualStick.y=0;
		}
		else if(virtualStick.x != 0 ||
				virtualStick.y != 0)
		{
			// cancel keyboard override, stick has been waggled
			keyboardRollPitchOverride=NO;
		}
		// handle yaw separately from pitch/roll
		reqYaw = [stickHandler getAxisState: AXIS_YAW];
		if((reqYaw == STICK_AXISUNASSIGNED) || fabs(reqYaw) < deadzone)
		{
			// Not assigned or deadzoned - set to zero.
			reqYaw=0;
		}
		else if(reqYaw != 0)
		{
			// cancel keyboard override, stick has been waggled
			keyboardYawOverride=NO;
		}
	}
	
	double roll_dampner = ROLL_DAMPING_FACTOR * delta_t;
	double pitch_dampner = PITCH_DAMPING_FACTOR * delta_t;
	double yaw_dampner = YAW_DAMPING_FACTOR * delta_t;
	
	rolling = NO;
	// if we have yaw on the mouse x-axis, then allow using the keyboard roll keys
	if (!mouse_control_on || (mouse_control_on && mouse_x_axis_map_to_yaw))
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
	if(((mouse_control_on && !mouse_x_axis_map_to_yaw) || numSticks) && !keyboardRollPitchOverride)
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
		rolling = (fabs(virtualStick.x) >= deadzone);
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
	// we don't care about pitch keyboard overrides when mouse control is on, only when using joystick
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
	if(mouse_control_on || (numSticks && !keyboardRollPitchOverride))
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
		pitching = (fabs(virtualStick.y) >= deadzone);
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
		// if we have roll on the mouse x-axis, then allow using the keyboard yaw keys
		if (!mouse_control_on || (mouse_control_on && !mouse_x_axis_map_to_yaw))
		{
			if ([gameView isDown:key_yaw_left])
			{
				keyboardYawOverride=YES;
				if (flightYaw < 0.0)  flightYaw = 0.0;
				[self increase_flight_yaw:delta_t*yaw_delta];
				yawing = YES;
			}
			else if ([gameView isDown:key_yaw_right])
			{
				keyboardYawOverride=YES;
				if (flightYaw > 0.0)  flightYaw = 0.0;
				[self decrease_flight_yaw:delta_t*yaw_delta];
				yawing = YES;
			}
		}
		if(((mouse_control_on && mouse_x_axis_map_to_yaw) || numSticks) && !keyboardYawOverride)
		{
			// I think yaw is handled backwards in the code,
			// which is why the negative sign is here.
			double stick_yaw = max_flight_yaw * (-reqYaw);
			if (flightYaw < stick_yaw)
			{
				[self increase_flight_yaw:delta_t*yaw_delta];
				if (flightYaw > stick_yaw)
					flightYaw = stick_yaw;
			}
			if (flightYaw > stick_yaw)
			{
				[self decrease_flight_yaw:delta_t*yaw_delta];
				if (flightYaw < stick_yaw)
					flightYaw = stick_yaw;
			}
			yawing = (fabs(reqYaw) >= deadzone);
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


- (void) pollGuiScreenControls
{
	[self pollGuiScreenControlsWithFKeyAlias:YES];
}


- (void) pollGuiScreenControlsWithFKeyAlias:(BOOL)fKeyAlias
{
	if(!pollControls && fKeyAlias)	// Still OK to run, if we don't use number keys.
		return;
	
	GuiDisplayGen	*gui = [UNIVERSE gui];
	MyOpenGLView	*gameView = [UNIVERSE gameView];
	BOOL			docked_okay = ([self status] == STATUS_DOCKED);
	
	//  text displays
	if (([gameView isDown:gvFunctionKey5])||(fKeyAlias && [gameView isDown:gvNumberKey5]))
	{
		if (!switching_status_screens)
		{
			switching_status_screens = YES;
			if ((gui_screen == GUI_SCREEN_STATUS)&&(![UNIVERSE strict]))
			{
				[self doScriptEvent:@"guiScreenWillChange" withArgument:GUIScreenIDToString(GUI_SCREEN_MANIFEST) andArgument:GUIScreenIDToString(gui_screen)];
				[self setGuiToManifestScreen];
			}
			else
				[self setGuiToStatusScreen];
			[self checkScript];
		}
	}
	else
	{
		switching_status_screens = NO;
	}
	
	if (([gameView isDown:gvFunctionKey6])||(fKeyAlias && [gameView isDown:gvNumberKey6]))
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
	
	if (([gameView isDown:gvFunctionKey7])||(fKeyAlias &&[gameView isDown:gvNumberKey7]))
	{
		if (gui_screen != GUI_SCREEN_SYSTEM_DATA)
		{
			[self setGuiToSystemDataScreen];
		}
	}
	
	
	if (docked_okay)
	{	
		if ((([gameView isDown:gvFunctionKey2])||(fKeyAlias && [gameView isDown:gvNumberKey2]))&&(gui_screen != GUI_SCREEN_OPTIONS))
		{
			[gameView clearKeys];
			[self setGuiToLoadSaveScreen];
		}
		
		if (([gameView isDown:gvFunctionKey3])||(fKeyAlias && [gameView isDown:gvNumberKey3]))
		{
			if (!switching_equipship_screens)
			{
				if (!dockedStation)  dockedStation = [UNIVERSE station];
				OOGUIScreenID oldScreen = gui_screen;
				
				if ((gui_screen == GUI_SCREEN_EQUIP_SHIP)&&[dockedStation hasShipyard])
				{
					[gameView clearKeys];
					[self doScriptEvent:@"guiScreenWillChange" withArgument:GUIScreenIDToString(GUI_SCREEN_SHIPYARD) andArgument:GUIScreenIDToString(oldScreen)];
					[self setGuiToShipyardScreen:0];
					[gui setSelectedRow:GUI_ROW_SHIPYARD_START];
					[self showShipyardInfoForSelection];
				}
				else
				{
					[gameView clearKeys];
					[self doScriptEvent:@"guiScreenWillChange" withArgument:GUIScreenIDToString(GUI_SCREEN_EQUIP_SHIP) andArgument:GUIScreenIDToString(oldScreen)];
					[self setGuiToEquipShipScreen:0];
					[gui setSelectedRow:GUI_ROW_EQUIPMENT_START];
				}
				
				[self noteGuiChangeFrom:oldScreen to:gui_screen]; 
			}
			switching_equipship_screens = YES;
		}
		else
		{
			switching_equipship_screens = NO;
		}
		
		if (([gameView isDown:gvFunctionKey8])||(fKeyAlias && [gameView isDown:gvNumberKey8]))
		{
			if (!switching_market_screens)
			{
				if ((gui_screen == GUI_SCREEN_MARKET)&&(dockedStation == [UNIVERSE station])&&(![UNIVERSE strict]))
				{
					[gameView clearKeys];
					[self setGuiToContractsScreen];
					[gui setSelectedRow:GUI_ROW_PASSENGERS_START];
				}
				else
				{
					[gameView clearKeys];
					[self doScriptEvent:@"guiScreenWillChange" withArgument:GUIScreenIDToString(GUI_SCREEN_MARKET) andArgument:GUIScreenIDToString(gui_screen)];
					[self setGuiToMarketScreen];
					[gui setSelectedRow:GUI_ROW_MARKET_START];
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
		if (([gameView isDown:gvFunctionKey8])||(fKeyAlias && [gameView isDown:gvNumberKey8]))
		{
			if (!switching_market_screens)
			{
				[self doScriptEvent:@"guiScreenWillChange" withArgument:GUIScreenIDToString(GUI_SCREEN_MARKET) andArgument:GUIScreenIDToString(gui_screen)];
				[self setGuiToMarketScreen];
				[gui setSelectedRow:GUI_ROW_MARKET_START];
			}
			switching_market_screens = YES;
		}
		else
		{
			switching_market_screens = NO;
		}
	}
}


- (void) pollGameOverControls:(double)delta_t
{
	MyOpenGLView  *gameView = [UNIVERSE gameView];
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

- (void) pollAutopilotControls:(double)delta_t
{
	// controls polled while the autopilot is active
	
	MyOpenGLView  *gameView = [UNIVERSE gameView];
	
	//  view keys
	[self pollViewControls];
	
	//  text displays
	[self pollGuiScreenControls];
	
	if ([UNIVERSE displayGUI])
		[self pollGuiArrowKeyControls:delta_t];
	
	if ([gameView isDown:key_autopilot])   // look for the 'c' key
	{
		if (([self hasDockingComputer]) && (!autopilot_key_pressed))   // look for the 'c' key
		{
			[self disengageAutopilot];
			[UNIVERSE addMessage:DESC(@"autopilot-off") forCount:4.5];
		}
		autopilot_key_pressed = YES;
	}
	else
		autopilot_key_pressed = NO;
	
	if (([gameView isDown:key_docking_music]))   // look for the 's' key
	{
		if (!toggling_music)
		{
			[[OOMusicController sharedController] toggleDockingMusic];
		}
		toggling_music = YES;
	}
	else
	{
		toggling_music = NO;
	}
}


- (void) pollDockedControls:(double)delta_t
{
	MyOpenGLView			*gameView = [UNIVERSE gameView];
	GameController			*gameController = [gameView gameController];
	NSString * volatile		exceptionContext = @"setup";
	
	NS_DURING
		// Pause game, 'p' key
		exceptionContext = @"pause key";
		if ([gameView isDown:key_pausebutton] && (gui_screen != GUI_SCREEN_LONG_RANGE_CHART &&
				gui_screen != GUI_SCREEN_MISSION && gui_screen != GUI_SCREEN_REPORT &&
				gui_screen != GUI_SCREEN_SAVE) )
		{
			if (!pause_pressed)
			{
				if ([gameController gameIsPaused])
				{
					script_time = saved_script_time;
					[gameView allowStringInput:NO];
					[UNIVERSE setDisplayCursor:NO];
					if ([UNIVERSE pauseMessageVisible])
					{
						[UNIVERSE clearPreviousMessage];	// remove the 'paused' message.
					}
					[[UNIVERSE gui] setForegroundTextureKey:@"docked_overlay"];
					[gameController unpause_game];
				}
				else
				{
					saved_script_time = script_time;
					[[UNIVERSE message_gui] clear];
					
					[UNIVERSE sleepytime:nil];	// 'paused' handler
				}
			}
			pause_pressed = YES;
		}
		else
		{
			pause_pressed = NO;
		}
		
		if ([gameController gameIsPaused]) NS_VOIDRETURN; //return;	// TEMP
		
		if(pollControls)
		{
			exceptionContext = @"undock";
			if ([gameView isDown:gvFunctionKey1] || [gameView isDown:gvNumberKey1])   // look for the f1 key
			{
				[self handleUndockControl];
			}
		}
		
		//  text displays
		// mission screens
		exceptionContext = @"GUI keys";
		if (gui_screen == GUI_SCREEN_MISSION)
			[self pollDemoControls: delta_t];
		else
			[self pollGuiScreenControls];	// don't switch away from mission screens
		
		[self pollGuiArrowKeyControls:delta_t];
	NS_HANDLER
		// TEMP extra exception checking
		OOLog(kOOLogException, @"***** Exception in pollDockedControls [%@]: %@ : %@", exceptionContext, [localException name], [localException reason]);
	NS_ENDHANDLER
}

- (void) handleUndockControl
{
	// FIXME: should this not be in leaveDock:? (Note: leaveDock: is also called from script method launchFromStation and -[StationEntity becomeExplosion]) -- Ahruman 20080308
	[UNIVERSE setUpUniverseFromStation]; // player pre-launch
	if (!dockedStation)  dockedStation = [UNIVERSE station];
	
	if (dockedStation == [UNIVERSE station] && [UNIVERSE autoSaveNow] && !([[UNIVERSE sun] goneNova] || [[UNIVERSE sun] willGoNova])) [self autosavePlayer];
	// autosave at the second launch after load / restart
	if ([UNIVERSE autoSave]) [UNIVERSE setAutoSaveNow:YES];
	[self leaveDock:dockedStation];
}

- (void) pollDemoControls:(double)delta_t
{
	MyOpenGLView	*gameView = [UNIVERSE gameView];
	GuiDisplayGen	*gui = [UNIVERSE gui];
	
	switch (gui_screen)
	{
		case GUI_SCREEN_INTRO1:
			if(0) {}	// Dummy statement so compiler does not complain.
			
			// In order to support multiple languages, the Y/N response cannot be hardcoded. We get the keys
			// corresponding to Yes/No from descriptions.plist and if they are not found there, we set them
			// by default to [yY] and [nN] respectively. 
			id valueYes = [[[UNIVERSE descriptions] oo_stringForKey:@"load-previous-commander-yes" defaultValue:@"y"] lowercaseString];
			id valueNo = [[[UNIVERSE descriptions] oo_stringForKey:@"load-previous-commander-no" defaultValue:@"n"] lowercaseString];
			unsigned char charYes, charNo;
			
			charYes = [valueYes characterAtIndex: 0] & 0x00ff;	// Use lower byte of unichar.
			charNo = [valueNo characterAtIndex: 0] & 0x00ff;	// Use lower byte of unichar.
			
			if (!disc_operation_in_progress)
			{
				if (([gameView isDown:charYes]) || ([gameView isDown:charYes - 32]))
				{
					[[OOMusicController sharedController] stopThemeMusic];
					disc_operation_in_progress = YES;
					[self setStatus:STATUS_DOCKED];
					[UNIVERSE removeDemoShips];
					[gui clearBackground];
					if (![self loadPlayer])
					{
						[self setGuiToIntroFirstGo:NO];
						[UNIVERSE selectIntro2Next];
					}
				}
			}
			if (([gameView isDown:charNo]) || ([gameView isDown:charNo - 32]))
			{
				[self setGuiToIntroFirstGo:NO];
				[UNIVERSE selectIntro2Next];
			}
			
			break;
			
		case GUI_SCREEN_INTRO2:
			if ([gameView isDown:' '])	//  '<space>'
			{
				[self setStatus: STATUS_DOCKED];
				[UNIVERSE removeDemoShips];
				[gui clearBackground];
				[[OOMusicController sharedController] stopThemeMusic];
				[[UNIVERSE gameView] supressKeysUntilKeyUp]; // to prevent a missionscreen on the first page from reacting on this keypress.
				[self setGuiToStatusScreen];
				[self doWorldEventUntilMissionScreen:@"missionScreenOpportunity"];	// trigger missionScreenOpportunity immediately after (re)start
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
			
		case GUI_SCREEN_MISSION:
			if ([[gui keyForRow:21] isEqual:@"spacebar"])
			{
				if ([gameView isDown:32])	//  '<space>'
				{
					if (!spacePressed)
					{
						[self setStatus:STATUS_DOCKED];
						[[OOMusicController sharedController] stopMissionMusic];
						
						[self handleMissionCallback];
						
					}
					spacePressed = YES;
				}
				else
					spacePressed = NO;
			}
			else
			{
				int guiSelectedRow = [gui selectedRow];
				if ([gameView isDown:gvArrowKeyDown])
				{
					if ((!upDownKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
					{
						if ([gui setSelectedRow:guiSelectedRow + 1])
						{
							[self playMenuNavigationDown];
						}
						else
						{
							[self playMenuNavigationNot];
						}
						timeLastKeyPress = script_time;
					}
				}
				if ([gameView isDown:gvArrowKeyUp])
				{
					if ((!upDownKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
					{
						if ([gui setSelectedRow:guiSelectedRow - 1])
						{
							[self playMenuNavigationUp];
						}
						else
						{
							[self playMenuNavigationNot];
						}
						timeLastKeyPress = script_time;
					}
				}
				upDownKeyPressed = (([gameView isDown:gvArrowKeyUp])||([gameView isDown:gvArrowKeyDown]));
				
				if ([gameView isDown:13])	//  '<enter/return>'
				{
					if (!selectPressed)
					{
						[self setMissionChoice:[gui selectedRowKey]];
						[[OOMusicController sharedController] stopMissionMusic];
						[self playDismissedMissionScreen];
						
						[self handleMissionCallback];
						
						[self checkScript];
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
}


- (void) handleMissionCallback
{
	[UNIVERSE removeDemoShips];
	[[UNIVERSE gui] clearBackground];
	
	[self setGuiToStatusScreen]; // need this to find out if we call a new mission screen inside callback.
	
	if ([self status] != STATUS_DOCKED) [self switchToThisView:VIEW_FORWARD];
	
	if (_missionWithCallback)
	{
		[self doMissionCallback];
	}
	
	if ([self status] != STATUS_DOCKED)	// did we launch inside callback? / are we in flight?
	{
		[self doWorldEventUntilMissionScreen:@"missionScreenEnded"];	// no opportunity events.
	}
	else
	{
		if (gui_screen != GUI_SCREEN_MISSION) // did we call a new mission screen inside callback?
		{
			[self setGuiToStatusScreen];	// if not, update status screen with callback changes, if any.
			[self endMissionScreenAndNoteOpportunity];	// missionScreenEnded, plus opportunity events.
		}
	}

}


- (void) switchToThisView:(OOViewID) viewDirection
{
	if ([UNIVERSE displayGUI]) [self switchToMainView];
	[UNIVERSE setViewDirection:viewDirection];
	currentWeaponFacing = viewDirection;
}

@end
