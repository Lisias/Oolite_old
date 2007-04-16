/*

OOBasicMaterial.m

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

#import "OOBasicMaterial.h"
#import "OOCollectionExtractors.h"
#import "OOFunctionAttributes.h"


static OOBasicMaterial *sDefaultMaterial = nil;


#define FACE		GL_FRONT_AND_BACK


@implementation OOBasicMaterial

- (id)initWithName:(NSString *)name
{
	self = [super init];
	if (EXPECT_NOT(self == nil))  return nil;
	
	materialName = [name copy];
	
	[self setDiffuseRed:1.0f green:1.0f blue:1.0f alpha:1.0f];
	[self setAmbientRed:1.0f green:1.0f blue:1.0f alpha:1.0f];
	specular[3] = 1.0;
	emission[3] = 1.0;
	smooth = YES;
	
	return self;
}


- (id)initWithName:(NSString *)name configuration:(NSDictionary *)configuration
{
	id					colorDesc = nil;
	
	self = [self initWithName:name];
	if (EXPECT_NOT(self == nil))  return nil;
	
	// Load colours from config. OOColor takes care of type checking.
	colorDesc = [configuration objectForKey:@"diffuse"];
	if (colorDesc != nil)  [self setDiffuseColor:[OOColor colorWithDescription:colorDesc]];
	colorDesc = [configuration objectForKey:@"specular"];
	if (colorDesc != nil)  [self setSpecularColor:[OOColor colorWithDescription:colorDesc]];
	colorDesc = [configuration objectForKey:@"ambient"];
	if (colorDesc != nil)  [self setAmbientColor:[OOColor colorWithDescription:colorDesc]];
	colorDesc = [configuration objectForKey:@"emission"];
	if (colorDesc != nil)  [self setEmissionColor:[OOColor colorWithDescription:colorDesc]];
	
	// ...and other attributes
	[self setShininess:[configuration intForKey:@"shininess" defaultValue:0]];
	[self setSmooth:[configuration boolForKey:@"smooth" defaultValue:NO]];
	
	return self;
}


- (void)dealloc
{
	[super willDealloc];
	[materialName release];
	
	[super dealloc];
}


- (NSString *)name
{
	return materialName;
}


- (BOOL)doApply
{
	glMaterialfv(FACE, GL_DIFFUSE, diffuse);
	glMaterialfv(FACE, GL_SPECULAR, specular);
	glMaterialfv(FACE, GL_AMBIENT, ambient);
	glMaterialfv(FACE, GL_EMISSION, emission);
	glMateriali(FACE, GL_SHININESS, shininess);
	glShadeModel(smooth ? GL_SMOOTH : GL_FLAT);
	
	return YES;
}


- (void)unapplyWithNext:(OOMaterial *)next
{
	if (![next isKindOfClass:[OOBasicMaterial class]])
	{
		if (EXPECT_NOT(sDefaultMaterial == nil))  sDefaultMaterial = [[OOBasicMaterial alloc] initWithName:@"<default material>"];
		[sDefaultMaterial doApply];
	}
}


- (OOColor *)diffuseColor
{
	return [OOColor colorWithCalibratedRed:diffuse[0]
									 green:diffuse[1]
									  blue:diffuse[2]
									 alpha:diffuse[3]];
}


- (void)setDiffuseColor:(OOColor *)color
{
	if (color != nil)
	{
		[self setDiffuseRed:[color redComponent] 
					  green:[color greenComponent]
					   blue:[color blueComponent]
					  alpha:[color alphaComponent]];
	}
}


- (void)setAmbientAndDiffuseColor:(OOColor *)color
{
	[self setAmbientColor:color];
	[self setDiffuseColor:color];
}


- (OOColor *)specularColor
{
	return [OOColor colorWithCalibratedRed:specular[0]
									 green:specular[1]
									  blue:specular[2]
									 alpha:specular[3]];
}


- (void)setSpecularColor:(OOColor *)color
{
	if (color != nil)
	{
		[self setSpecularRed:[color redComponent] 
					   green:[color greenComponent]
						blue:[color blueComponent]
					   alpha:[color alphaComponent]];
	}
}


- (OOColor *)ambientColor
{
	return [OOColor colorWithCalibratedRed:ambient[0]
									 green:ambient[1]
									  blue:ambient[2]
									 alpha:ambient[3]];
}


- (void)setAmbientColor:(OOColor *)color
{
	if (color != nil)
	{
		[self setAmbientRed:[color redComponent] 
					  green:[color greenComponent]
					   blue:[color blueComponent]
					  alpha:[color alphaComponent]];
	}
}


- (OOColor *)emmisionColor
{
	return [OOColor colorWithCalibratedRed:emission[0]
									 green:emission[1]
									  blue:emission[2]
									 alpha:emission[3]];
}


- (void)setEmissionColor:(OOColor *)color
{
	if (color != nil)
	{
		[self setEmissionRed:[color redComponent] 
					   green:[color greenComponent]
						blue:[color blueComponent]
					   alpha:[color alphaComponent]];
	}
}


- (void)getDiffuseComponents:(GLfloat[4])outComponents
{
	memcpy(outComponents, diffuse, 4 * sizeof *outComponents);
}


- (void)setDiffuseComponents:(const GLfloat[4])components
{
	memcpy(diffuse, components, 4 * sizeof *components);
}


- (void)setAmbientAndDiffuseComponents:(const GLfloat[4])components
{
	[self setAmbientComponents:components];
	[self setDiffuseComponents:components];
}


- (void)getSpecularComponents:(GLfloat[4])outComponents
{
	memcpy(outComponents, specular, 4 * sizeof *outComponents);
}


- (void)setSpecularComponents:(const GLfloat[4])components
{
	memcpy(specular, components, 4 * sizeof *components);
}


- (void)getAmbientComponents:(GLfloat[4])outComponents
{
	memcpy(outComponents, ambient, 4 * sizeof *outComponents);
}


- (void)setAmbientComponents:(const GLfloat[4])components
{
	memcpy(ambient, components, 4 * sizeof *components);
}


- (void)getEmissionComponents:(GLfloat[4])outComponents
{
	memcpy(outComponents, emission, 4 * sizeof *outComponents);
}


- (void)setEmissionComponents:(const GLfloat[4])components
{
	memcpy(emission, components, 4 * sizeof *components);
}


- (void)setDiffuseRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a
{
	diffuse[0] = r;
	diffuse[1] = g;
	diffuse[2] = b;
	diffuse[3] = a;
}


- (void)setAmbientAndDiffuseRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a
{
	[self setAmbientRed:r green:g blue:b alpha:a];
	[self setDiffuseRed:r green:g blue:b alpha:a];
}


- (void)setSpecularRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a
{
	specular[0] = r;
	specular[1] = g;
	specular[2] = b;
	specular[3] = a;
}


- (void)setAmbientRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a
{
	ambient[0] = r;
	ambient[1] = g;
	ambient[2] = b;
	ambient[3] = a;
}


- (void)setEmissionRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a
{
	emission[0] = r;
	emission[1] = g;
	emission[2] = b;
	emission[3] = a;
}



- (uint8_t)shininess
{
	return shininess;
}


- (void)setShininess:(uint8_t)value
{
	shininess = MAX(value, 128);
}


- (BOOL)smooth
{
	return smooth;
}


- (void)setSmooth:(BOOL)value
{
	smooth = value;
}

@end
