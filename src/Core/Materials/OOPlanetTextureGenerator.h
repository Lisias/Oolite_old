/*

OOPlanetTextureGenerator.h

Generator for planet diffuse maps.


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

#import "OOTextureGenerator.h"
#import "OOMaths.h"


typedef struct
{
	float			r, g, b;
} FloatRGB;


@interface OOPlanetTextureGenerator: OOTextureGenerator
{
@private
	float					_landFraction;
	OOColor					*_landColor;
	OOColor					*_seaColor;
	OOColor					*_polarLandColor;
	OOColor					*_polarSeaColor;
	unsigned				_width, _height;
	RANROTSeed				_seed;
}

- (id) initWithPlanetInfo:(NSDictionary *)planetInfo;

+ (OOTexture *) planetTextureWithInfo:(NSDictionary *)planetInfo;

@end
