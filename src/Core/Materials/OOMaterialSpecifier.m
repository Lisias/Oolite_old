/*

OOMaterialSpecifier.m

 
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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2010 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOMaterialSpecifier.h"
#import "OOColor.h"
#import "OOCollectionExtractors.h"
#import "OOTexture.h"


NSString * const kOOMaterialDiffuseColorName				= @"diffuse_color";
NSString * const kOOMaterialDiffuseColorLegacyName			= @"diffuse";
NSString * const kOOMaterialAmbientColorName				= @"ambient_color";
NSString * const kOOMaterialAmbientColorLegacyName			= @"ambient";
NSString * const kOOMaterialSpecularColorName				= @"specular_color";
NSString * const kOOMaterialSpecularColorLegacyName			= @"specular";
NSString * const kOOMaterialEmissionColorName				= @"emission_color";
NSString * const kOOMaterialEmissionColorLegacyName			= @"emission";
NSString * const kOOMaterialIlluminationColorName			= @"illumination_color";

NSString * const kOOMaterialDiffuseMapName					= @"diffuse_map";
NSString * const kOOMaterialSpecularMapName					= @"specular_map";
NSString * const kOOMaterialNormalMapName					= @"normal_map";
NSString * const kOOMaterialNormalAndParallaxMapName		= @"normal_and_parallax_map";
NSString * const kOOMaterialEmissionMapName					= @"emission_map";
NSString * const kOOMaterialIlluminationMapName				= @"illumination_map";
NSString * const kOOMaterialEmissionAndIlluminationMapName	= @"emission_and_illumination_map";

NSString * const kOOMaterialParallaxScale					= @"parallax_scale";
NSString * const kOOMaterialParallaxBias					= @"parallax_bias";

NSString * const kOOMaterialShininess						= @"shininess";


@implementation NSDictionary (OOMateralProperties)

- (OOColor *) oo_diffuseColor
{
	OOColor * result = [OOColor colorWithDescription:[self objectForKey:kOOMaterialDiffuseColorName]];
	if (result == nil)  result = [OOColor colorWithDescription:[self objectForKey:kOOMaterialDiffuseColorLegacyName]];
	if (result == nil)  result = [OOColor whiteColor];
	return result;
}


- (OOColor *) oo_ambientColor
{
	OOColor * result = [OOColor colorWithDescription:[self objectForKey:kOOMaterialAmbientColorName]];
	if (result == nil)  result = [OOColor colorWithDescription:[self objectForKey:kOOMaterialAmbientColorLegacyName]];
	return result;
}


- (OOColor *) oo_specularColor
{
	OOColor * result = [OOColor colorWithDescription:[self objectForKey:kOOMaterialSpecularColorName]];
	if (result == nil)  result = [OOColor colorWithDescription:[self objectForKey:kOOMaterialSpecularColorLegacyName]];
	if (result == nil)
	{
		if ([self oo_floatForKey:kOOMaterialShininess] != 0)
		{
			if ([self oo_specularMapSpecifier] == nil)
			{
				// No specular map, non-zero shininess: dark specular highlight by default.
				result = [OOColor colorWithCalibratedWhite:0.2 alpha:1.0];
			}
			else
			{
				// Specular map, non-zero shininess: white by default to use unmodified specular map colour.
				result = [OOColor whiteColor];
			}
		}
		// else, zero shininess -> no specular anything.
	}
	return result;
}


- (OOColor *) oo_emissionColor
{
	OOColor * result = [OOColor colorWithDescription:[self objectForKey:kOOMaterialEmissionColorName]];
	if (result == nil)  result = [OOColor colorWithDescription:[self objectForKey:kOOMaterialEmissionColorLegacyName]];
	if ([result isBlack])  result = nil;
	return result;
}


- (OOColor *) oo_illuminationColor
{
	OOColor * result = [OOColor colorWithDescription:[self objectForKey:kOOMaterialIlluminationColorName]];
	if ([result isWhite])  result = nil;
	return result;
}


- (NSDictionary *) oo_diffuseMapSpecifierWithDefaultName:(NSString *)name
{
	return [self oo_textureSpecifierForKey:kOOMaterialDiffuseMapName defaultName:name];
}


- (NSDictionary *) oo_specularMapSpecifier
{
	// Can't use -oo_shininess for reasons of recursion.
	if ([self oo_intForKey:kOOMaterialShininess defaultValue:-1] == 0)  return nil;
	return [self oo_textureSpecifierForKey:kOOMaterialSpecularMapName defaultName:nil];
}


- (NSDictionary *) oo_normalMapSpecifier
{
	if ([self oo_normalAndParallaxMapSpecifier] != nil)  return nil;
	return [self oo_textureSpecifierForKey:kOOMaterialNormalMapName defaultName:nil];
}


- (NSDictionary *) oo_normalAndParallaxMapSpecifier
{
	return [self oo_textureSpecifierForKey:kOOMaterialNormalAndParallaxMapName defaultName:nil];
}


- (NSDictionary *) oo_emissionMapSpecifier
{
	return [self oo_textureSpecifierForKey:kOOMaterialEmissionMapName defaultName:nil];
}


- (NSDictionary *) oo_illuminationMapSpecifier
{
	return [self oo_textureSpecifierForKey:kOOMaterialIlluminationMapName defaultName:nil];
}


- (NSDictionary *) oo_emissionAndIlluminationMapSpecifier
{
	if ([self oo_emissionMapSpecifier] != nil || [self oo_illuminationMapSpecifier] != nil)  return nil;
	return [self oo_textureSpecifierForKey:kOOMaterialEmissionAndIlluminationMapName defaultName:nil];
}


- (float) oo_parallaxScale
{
	return [self oo_floatForKey:kOOMaterialParallaxScale defaultValue:0.01f];
}


- (float) oo_parallaxBias
{
	return [self oo_floatForKey:kOOMaterialParallaxBias];
}


- (int) oo_shininess
{
	int result = [self oo_intForKey:kOOMaterialShininess defaultValue:-1];
	if (result < 0)
	{
		if ([self oo_specularMapSpecifier] != nil)
		{
			result = 128;
		}
		else
		{
			result = 10;
		}
	}
	
	return result;
}

@end
