/*

OOColor.m

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

#import "OOColor.h"

@implementation OOColor

- (void) setRGBA:(GLfloat)r:(GLfloat)g:(GLfloat)b:(GLfloat)a
{
	rgba[0] = r;
	rgba[1] = g;
	rgba[2] = b;
	rgba[3] = a;
}

- (void) setHSBA:(GLfloat)h:(GLfloat)s:(GLfloat)b:(GLfloat)a
{
	if (s == 0.0)
	{
		rgba[0] = rgba[1] = rgba[2] = b;
		rgba[3] = a;
		return;
	}
	GLfloat f, p, q, t;
	int i;
	while (h >= 360.0) h -= 360.0;
	while (h < 0.0) h += 360.0;
	h /= 60.0;
	i = floor(h);
	f = h - i;
	p = b * (1.0 - s);
	q = b * (1.0 - (s * f));
	t = b * (1.0 - (s * (1.0 - f)));
	switch (i)
	{
		case 0:
			rgba[0] = b;	rgba[1] = t;	rgba[2] = p;	break;
		case 1:
			rgba[0] = q;	rgba[1] = b;	rgba[2] = p;	break;
		case 2:
			rgba[0] = p;	rgba[1] = b;	rgba[2] = t;	break;
		case 3:
			rgba[0] = p;	rgba[1] = q;	rgba[2] = b;	break;
		case 4:
			rgba[0] = t;	rgba[1] = p;	rgba[2] = b;	break;
		case 5:
			rgba[0] = b;	rgba[1] = p;	rgba[2] = q;	break;
	}
	rgba[3] = a;
}

/* Create NSCalibratedRGBColorSpace colors.
*/
+ (OOColor *)colorWithCalibratedHue:(float)hue saturation:(float)saturation brightness:(float)brightness alpha:(float)alpha
{
	OOColor* result = [[OOColor alloc] init];
	[result setHSBA: 360.0 * hue : saturation : brightness : alpha];
	return [result autorelease];
}

+ (OOColor *)colorWithCalibratedRed:(float)red green:(float)green blue:(float)blue alpha:(float)alpha
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA:red:green:blue:alpha];
	return [result autorelease];
}

/* Some convenience methods to create colors in the calibrated color spaces...
*/
+ (OOColor *)colorFromString:(NSString*) colorFloatString;
{
	float set_rgba[4] = { 0.0, 0.0, 0.0, 1.0};
	OOColor* result = [[OOColor alloc] init];
	NSScanner* scanner = [NSScanner scannerWithString:colorFloatString];
	float value;
	int i = 0;
	while ((i < 4)&&[scanner scanFloat:&value])
		set_rgba[i++] = value;
	[result setRGBA: set_rgba[0] : set_rgba[1] : set_rgba[2] : set_rgba[3]];
		
	return [result autorelease];
}
+ (OOColor *)blackColor;	/* 0.0 white */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 0.0 : 0.0 : 0.0 : 1.0];
	return [result autorelease];
}
+ (OOColor *)darkGrayColor;	/* 0.333 white */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 0.333 : 0.333 : 0.333 : 1.0];
	return [result autorelease];
}
+ (OOColor *)lightGrayColor;	/* 0.667 white */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 0.667 : 0.667 : 0.667 : 1.0];
	return [result autorelease];
}
+ (OOColor *)whiteColor;	/* 1.0 white */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 1.0 : 1.0 : 1.0 : 1.0];
	return [result autorelease];
}
+ (OOColor *)grayColor;		/* 0.5 white */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 0.5 : 0.5 : 0.5 : 1.0];
	return [result autorelease];
}
+ (OOColor *)redColor;		/* 1.0, 0.0, 0.0 RGB */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 1.0 : 0.0 : 0.0 : 1.0];
	return [result autorelease];
}

+ (OOColor *)greenColor;	/* 0.0, 1.0, 0.0 RGB */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 0.0 : 1.0 : 0.00 : 1.0];
	return [result autorelease];
}
+ (OOColor *)blueColor;		/* 0.0, 0.0, 1.0 RGB */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 0.0 : 0.0 : 1.0 : 1.0];
	return [result autorelease];
}
+ (OOColor *)cyanColor;		/* 0.0, 1.0, 1.0 RGB */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 0.0 : 1.0 : 1.0 : 1.0];
	return [result autorelease];
}
+ (OOColor *)yellowColor;	/* 1.0, 1.0, 0.0 RGB */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 1.0 : 1.0 : 0.0 : 1.0];
	return [result autorelease];
}
+ (OOColor *)magentaColor;	/* 1.0, 0.0, 1.0 RGB */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 1.0 : 0.0 : 1.0 : 1.0];
	return [result autorelease];
}
+ (OOColor *)orangeColor;	/* 1.0, 0.5, 0.0 RGB */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 1.0 : 0.5 : 0.0 : 1.0];
	return [result autorelease];
}
+ (OOColor *)purpleColor;	/* 0.5, 0.0, 0.5 RGB */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 0.5 : 0.0 : 0.5 : 1.0];
	return [result autorelease];
}
+ (OOColor *)brownColor;	/* 0.6, 0.4, 0.2 RGB */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 0.6 : 0.4 : 0.2 : 1.0];
	return [result autorelease];
}
+ (OOColor *)clearColor;	/* 0.0 white, 0.0 alpha */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 0.0 : 0.0 : 0.0 : 0.0];
	return [result autorelease];
}

/* Blend using the NSCalibratedRGB color space. Both colors are converted into the calibrated RGB color space, and they are blended by taking fraction of color and 1 - fraction of the receiver. The result is in the calibrated RGB color space. If the colors cannot be converted into the calibrated RGB color space the blending fails and nil is returned.
*/
- (OOColor *)blendedColorWithFraction:(float)fraction ofColor:(OOColor *)color
{
	GLfloat	rgba1[4];
	[color getRed:&rgba1[0] green:&rgba1[1] blue:&rgba1[2] alpha:&rgba1[3]];
	OOColor* result = [[OOColor alloc] init];
	float prime = 1.0f - fraction;
	[result setRGBA: prime * rgba[0] + fraction * rgba1[0] : prime * rgba[1] + fraction * rgba1[1] : prime * rgba[2] + fraction * rgba1[2] : prime * rgba[3] + fraction * rgba1[3]];
	return [result autorelease];
}

// find a point on the sea->land scale
+ (OOColor *) planetTextureColor:(float) q:(OOColor *) seaColor:(OOColor *) paleSeaColor:(OOColor *) landColor:(OOColor *) paleLandColor
{
	float hi = 0.33;
	float oh = 1.0 / hi;
	float ih = 1.0 / (1.0 - hi);
	if (q <= 0.0)
		return seaColor;
	if (q > 1.0)
		return [OOColor whiteColor];
	if (q < 0.01)
		return [paleSeaColor blendedColorWithFraction: q * 100.0 ofColor: landColor];
	if (q > hi)
		return [paleLandColor blendedColorWithFraction: (q - hi) * ih ofColor: [OOColor whiteColor]];	// snow capped peaks
	return [paleLandColor blendedColorWithFraction: (hi - q) * oh ofColor: landColor];
}

// find a point on the sea->land scale given impress and bias
+ (OOColor *) planetTextureColor:(float) q:(float) impress:(float) bias :(OOColor *) seaColor:(OOColor *) paleSeaColor:(OOColor *) landColor:(OOColor *) paleLandColor
{
	float maxq = impress + bias;
	
	float hi = 0.66667 * maxq;
	float oh = 1.0 / hi;
	float ih = 1.0 / (1.0 - hi);
	
	if (q <= 0.0)
		return seaColor;
	if (q > 1.0)
		return [OOColor whiteColor];
	if (q < 0.01)
		return [paleSeaColor blendedColorWithFraction: q * 100.0 ofColor: landColor];
	if (q > hi)
		return [paleLandColor blendedColorWithFraction: (q - hi) * ih ofColor: [OOColor whiteColor]];	// snow capped peaks
	return [paleLandColor blendedColorWithFraction: (hi - q) * oh ofColor: landColor];
}


/* Get the red, green, or blue components of NSCalibratedRGB or NSDeviceRGB colors.
*/
- (GLfloat)redComponent
{
	return rgba[0];
}

- (GLfloat)greenComponent
{
	return rgba[1];
}

- (GLfloat)blueComponent
{
	return rgba[2];
}

- (void)getRed:(GLfloat *)red green:(GLfloat *)green blue:(GLfloat *)blue alpha:(GLfloat *)alpha
{
	*red = rgba[0];
	*green = rgba[1];
	*blue = rgba[2];
	*alpha = rgba[3];
}

/* Get the components of NSCalibratedRGB or NSDeviceRGB colors as hue, saturation, or brightness.
*/
- (float)hueComponent
{
	GLfloat maxrgb = (rgba[0] > rgba[1])? ((rgba[0] > rgba[2])? rgba[0]:rgba[2]):((rgba[1] > rgba[2])? rgba[1]:rgba[2]);
	GLfloat minrgb = (rgba[0] < rgba[1])? ((rgba[0] < rgba[2])? rgba[0]:rgba[2]):((rgba[1] < rgba[2])? rgba[1]:rgba[2]);
	if (maxrgb == minrgb)
		return 0.0;
	GLfloat delta = maxrgb - minrgb;
	GLfloat hue = 0.0;
	if (rgba[0] == maxrgb)
		hue = (rgba[1] - rgba[2]) / delta;
	else if (rgba[1] == maxrgb)
		hue = 2.0 + (rgba[2] - rgba[0]) / delta;
	else if (rgba[2] == maxrgb)
		hue = 4.0 + (rgba[0] - rgba[1]) / delta;
	hue *= 60.0;
	while (hue < 0.0) hue += 360.0;
	return hue;
}

- (float)saturationComponent
{
	GLfloat maxrgb = (rgba[0] > rgba[1])? ((rgba[0] > rgba[2])? rgba[0]:rgba[2]):((rgba[1] > rgba[2])? rgba[1]:rgba[2]);
	GLfloat minrgb = (rgba[0] < rgba[1])? ((rgba[0] < rgba[2])? rgba[0]:rgba[2]):((rgba[1] < rgba[2])? rgba[1]:rgba[2]);
	GLfloat brightness = 0.5 * (maxrgb + minrgb);
	if (maxrgb == minrgb)
		return 0.0;
	GLfloat delta = maxrgb - minrgb;
	return (brightness <= 0.5)? (delta / (maxrgb + minrgb)) : (delta / (2.0 - (maxrgb + minrgb)));
}

- (float)brightnessComponent
{
	GLfloat maxrgb = (rgba[0] > rgba[1])? ((rgba[0] > rgba[2])? rgba[0]:rgba[2]):((rgba[1] > rgba[2])? rgba[1]:rgba[2]);
	GLfloat minrgb = (rgba[0] < rgba[1])? ((rgba[0] < rgba[2])? rgba[0]:rgba[2]):((rgba[1] < rgba[2])? rgba[1]:rgba[2]);
	return 0.5 * (maxrgb + minrgb);
}

- (void)getHue:(float *)hue saturation:(float *)saturation brightness:(float *)brightness alpha:(float *)alpha
{
	*alpha = rgba[3];
	GLfloat maxrgb = (rgba[0] > rgba[1])? ((rgba[0] > rgba[2])? rgba[0]:rgba[2]):((rgba[1] > rgba[2])? rgba[1]:rgba[2]);
	GLfloat minrgb = (rgba[0] < rgba[1])? ((rgba[0] < rgba[2])? rgba[0]:rgba[2]):((rgba[1] < rgba[2])? rgba[1]:rgba[2]);
	*brightness = 0.5 * (maxrgb + minrgb);
	if (maxrgb == minrgb)
	{
		*saturation = 0.0;
		*hue = 0.0;
		return;
	}
	GLfloat delta = maxrgb - minrgb;
	*saturation = (*brightness <= 0.5)? (delta / (maxrgb + minrgb)) : (delta / (2.0 - (maxrgb + minrgb)));
	if (rgba[0] == maxrgb)
		*hue = (rgba[1] - rgba[2]) / delta;
	else if (rgba[1] == maxrgb)
		*hue = 2.0 + (rgba[2] - rgba[0]) / delta;
	else if (rgba[2] == maxrgb)
		*hue = 4.0 + (rgba[0] - rgba[1]) / delta;
	*hue *= 60.0;
	while (*hue < 0.0) *hue += 360.0;
}


/* Get the alpha component. For colors which do not have alpha components, this will return 1.0 (opaque).
*/
- (float)alphaComponent
{
	return rgba[3];
}

- (GLfloat *) RGBA;
{
	return rgba;
}


#ifndef GNUSTEP

- (NSColor *)asNSColor
{
	return [NSColor colorWithCalibratedRed:rgba[0] green:rgba[1] blue:rgba[2] alpha:rgba[3]];
}


- (void)set
{
	[[self asNSColor] set];
}


- (void)setFill
{
	[[self asNSColor] setFill];
}


- (void)setStroke
{
	[[self asNSColor] setStroke];
}

#endif

@end
