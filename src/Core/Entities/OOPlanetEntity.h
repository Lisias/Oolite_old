/*

OOPlanetEntity.h

Entity subclass representing a planet.

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

#import "Entity.h"

// For some declarations that'll eventually migrate here
#import "PlanetEntity.h"


@class OOPlanetDrawable, ShipEntity;


@interface OOPlanetEntity: Entity <OOPlanet>
{
@private
	OOPlanetDrawable		*_planetDrawable;
	OOPlanetDrawable		*_atmosphereDrawable;
	
	BOOL					_miniature;
	
	Vector					_rotationAxis;
	float					_rotationalVelocity;
	
	unsigned				_shuttlesOnGround;
	OOTimeDelta				_lastLaunchTime;
	OOTimeDelta				_shuttleLaunchInterval;
	
	NSDictionary			*_materialParameters;
}

- (id) initAsMainPlanetForSystemSeed:(Random_Seed)seed;

- (id) initFromDictionary:(NSDictionary *)dict withAtmosphere:(BOOL)atmosphere andSeed:(Random_Seed)seed;

- (id) miniatureVersion;

- (void) launchShuttle;
- (void) welcomeShuttle:(ShipEntity *)shuttle;

- (BOOL) hasAtmosphere;

// FIXME: need material model.
- (NSString *) textureFileName;
- (void) setTextureFileName:(NSString *)textureName;

- (BOOL) setUpPlanetFromTexture:(NSString *)fileName;

@end
