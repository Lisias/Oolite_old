/*

OOTypes.h

Various simple types that don't require us to pull in the associated class
headers.

Oolite
Copyright (C) 2004-2011 Giles C Williams and contributors

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

#include "OOFunctionAttributes.h"
#include "OOCocoa.h"


typedef enum
{
	OPTIMIZED_BY_NONE,
	OPTIMIZED_BY_JUMPS,
	OPTIMIZED_BY_TIME
} OORouteType;


#define ENTRY(label, value) label,

typedef enum
{
	#include "OOViewID.tbl"
		
	kOOViewIDDefault = VIEW_NONE
} OOViewID;

#undef ENTRY


typedef enum
{
	AEGIS_NONE,
	AEGIS_CLOSE_TO_ANY_PLANET,
	AEGIS_CLOSE_TO_MAIN_PLANET,
	AEGIS_IN_DOCKING_RANGE
} OOAegisStatus;


typedef enum
{
	CARGO_UNDEFINED					= -2,	// FIXME: it's unclear whether there's a useful distinction between CARGO_UNDEFINED (previously NSNotFound) and CARGO_NOT_CARGO.
	CARGO_NOT_CARGO					= -1,
	CARGO_SLAVES					= 3,
	CARGO_ALLOY						= 9,
	CARGO_MINERALS					= 12,
	CARGO_THARGOID					= 16,
	CARGO_RANDOM					= 100,
	CARGO_SCRIPTED_ITEM				= 200,
	CARGO_CHARACTER					= 300
} OOCargoType;


typedef enum
{
	COMMODITY_UNDEFINED		= -1,
	COMMODITY_FOOD,		//	=  0 
	COMMODITY_TEXTILES,
	COMMODITY_RADIOACTIVES,
	COMMODITY_SLAVES,
	COMMODITY_LIQUOR_WINES,
	COMMODITY_LUXURIES,
	COMMODITY_NARCOTICS,
	COMMODITY_COMPUTERS,
	COMMODITY_MACHINERY,
	COMMODITY_ALLOYS,
	COMMODITY_FIREARMS,
	COMMODITY_FURS,
	COMMODITY_MINERALS,
	COMMODITY_GOLD,
	COMMODITY_PLATINUM,
	COMMODITY_GEM_STONES,
	COMMODITY_ALIEN_ITEMS
} OOCommodityType;


typedef enum
{
	CARGO_FLAG_NONE					= 400,
	CARGO_FLAG_FULL_PLENTIFUL		= 501,
	CARGO_FLAG_FULL_SCARCE			= 502,
	CARGO_FLAG_PIRATE				= 505,
	CARGO_FLAG_FULL_UNIFORM			= 510,
	CARGO_FLAG_CANISTERS			= 600,
	CARGO_FLAG_FULL_PASSENGERS		= 700
} OOCargoFlag;


typedef enum
{
	UNITS_TONS,
	UNITS_KILOGRAMS,
	UNITS_GRAMS
} OOMassUnit;


typedef enum
{
	ENERGY_UNIT_NONE,
	ENERGY_UNIT_NORMAL_DAMAGED,
	ENERGY_UNIT_NAVAL_DAMAGED,
	OLD_ENERGY_UNIT_NORMAL			=15,
	OLD_ENERGY_UNIT_NAVAL			= 20,
	ENERGY_UNIT_NORMAL				= 8,
	ENERGY_UNIT_NAVAL				= 16
} OOEnergyUnitType;


#define ENTRY(label, value) label = value,

typedef enum
{
	#include "OOCompassMode.tbl"
} OOCompassMode;

enum
{
	kOOCompassModeDefault		= COMPASS_MODE_BASIC
};

#undef ENTRY


#if DOCKING_CLEARANCE_ENABLED
typedef enum
{
	DOCKING_CLEARANCE_STATUS_NONE,
	DOCKING_CLEARANCE_STATUS_NOT_REQUIRED,
	DOCKING_CLEARANCE_STATUS_REQUESTED,
	DOCKING_CLEARANCE_STATUS_GRANTED,
	DOCKING_CLEARANCE_STATUS_TIMING_OUT,
} OODockingClearanceStatus;
#endif


typedef uint32_t	OOCargoQuantity;
typedef int32_t		OOCargoQuantityDelta;

typedef uint16_t	OOFuelQuantity;


typedef uint64_t	OOCreditsQuantity;


typedef uint16_t	OOKeyCode;


typedef uint16_t	OOUniversalID;		// Valid IDs range from 100 to 1000.

enum
{
	UNIVERSE_MAX_ENTITIES	= 2048,
	NO_TARGET				= 0,
	MIN_ENTITY_UID			= 100,
	MAX_ENTITY_UID			= MIN_ENTITY_UID + UNIVERSE_MAX_ENTITIES + 1
};


enum
{
	kOOVariableTechLevel	= 99
};


typedef uint8_t		OOGalaxyID;			// 0..7
typedef int16_t		OOSystemID;			// 0..255, -1 for interstellar space (?)


enum
{
	kOOMaximumGalaxyID		= 7,
	kOOMaximumSystemID		= 255,
	kOOMinimumSystemID		= -1
};


typedef double OOTimeAbsolute;
typedef double OOTimeDelta;
