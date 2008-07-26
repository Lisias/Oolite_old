/*

DustEntity.m

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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

#import "DustEntity.h"

#import "OOMaths.h"
#import "Universe.h"
#import "MyOpenGLView.h"
#import "OOGraphicsResetManager.h"

#import "PlayerEntity.h"


// Declare protocol conformance
@interface DustEntity (OOGraphicsResetClient) <OOGraphicsResetClient>
@end


@implementation DustEntity

- (id) init
{
    int vi;
	
    ranrot_srand([[NSDate date] timeIntervalSince1970]);	// seed randomiser by time
    
    self = [super init];
	
	for (vi = 0; vi < DUST_N_PARTICLES; vi++)
	{
		vertices[vi].x = (ranrot_rand() % DUST_SCALE) - DUST_SCALE / 2;
		vertices[vi].y = (ranrot_rand() % DUST_SCALE) - DUST_SCALE / 2;
		vertices[vi].z = (ranrot_rand() % DUST_SCALE) - DUST_SCALE / 2;
	}
	
	dust_color = [[OOColor colorWithCalibratedRed:0.5 green:1.0 blue:1.0 alpha:1.0] retain];
    displayListName = 0;
    status = STATUS_ACTIVE;
	
	[[OOGraphicsResetManager sharedManager] registerClient:self];
    
    return self;
}


- (void) dealloc
{
	[dust_color release];
	[[OOGraphicsResetManager sharedManager] unregisterClient:self];
	glDeleteLists(displayListName, 1);
	
	[super dealloc];
}


- (void) setDustColor:(OOColor *) color
{
	if (dust_color) [dust_color release];
	dust_color = [color retain];
	[dust_color getGLRed:&color_fv[0] green:&color_fv[1] blue:&color_fv[2] alpha:&color_fv[3]];
}


- (OOColor *) dust_color
{
	return dust_color;
}


- (BOOL) canCollide
{
	return NO;
}


- (void) update:(OOTimeDelta) delta_t
{
	PlayerEntity* player = [PlayerEntity sharedPlayer];
	if (!player)  return;	//	DON'T UPDATE
	
	zero_distance = 0.0;
			
	Vector offset = player->position;
	GLfloat  half_scale = DUST_SCALE * 0.50;
	int vi;
	for (vi = 0; vi < DUST_N_PARTICLES; vi++)
	{
		while (vertices[vi].x - offset.x < -half_scale)
			vertices[vi].x += DUST_SCALE;
		while (vertices[vi].x - offset.x > half_scale)
			vertices[vi].x -= DUST_SCALE;
		
		while (vertices[vi].y - offset.y < -half_scale)
			vertices[vi].y += DUST_SCALE;
		while (vertices[vi].y - offset.y > half_scale)
			vertices[vi].y -= DUST_SCALE;
		
		while (vertices[vi].z - offset.z < -half_scale)
			vertices[vi].z += DUST_SCALE;
		while (vertices[vi].z - offset.z > half_scale)
			vertices[vi].z -= DUST_SCALE;
	}
						
}


- (void) drawEntity:(BOOL) immediate :(BOOL) translucent
{
	PlayerEntity* player = [PlayerEntity sharedPlayer];
	if (!player)  return;	//	DON'T DRAW
	//
    int ct;
	int vi;

    GLfloat *fogcolor = [UNIVERSE skyClearColor];
	int  dust_size = floor([[UNIVERSE gameView] viewSize].width / 480.0);
	if (dust_size < 1.0)
		dust_size = 1.0;
	int  line_size = dust_size / 2;
	if (line_size < 1.0)
		line_size = 1.0;
	GLfloat  half_scale = DUST_SCALE * 0.50;
	GLfloat  quarter_scale = DUST_SCALE * 0.25;
	
	if ([UNIVERSE breakPatternHide])	return;	// DON'T DRAW

	BOOL	warp_stars = [player atHyperspeed];
	Vector  warp_vector = vector_multiply_scalar([player velocityVector], 1.0f / HYPERSPEED_FACTOR);
		
	if (translucent)
	{
		glEnable(GL_FOG);
		glFogi(GL_FOG_MODE, GL_LINEAR);
		glFogfv(GL_FOG_COLOR, fogcolor);
		glHint(GL_FOG_HINT, GL_NICEST);
		glFogf(GL_FOG_START, quarter_scale);
		glFogf(GL_FOG_END, half_scale);
		//
		// disapply lighting and texture
		glDisable(GL_TEXTURE_2D);
		//
		if (player->isSunlit)
			glColor4fv(color_fv);
		else
			glColor4fv(UNIVERSE->stars_ambient);
		//
		ct = 0;
		
		GLenum dustMode;
		
		if (!warp_stars)
		{
			glEnable(GL_POINT_SMOOTH);
			glPointSize(dust_size);
			dustMode = GL_POINTS;
		}
		else
		{
			glEnable(GL_LINE_SMOOTH);
			glLineWidth(line_size);
			dustMode = GL_LINES;
		}
		
		glBegin(dustMode);
		
		for (vi = 0; vi < DUST_N_PARTICLES; vi++)
		{
			GLVertexOOVector(vertices[vi]);
			if (warp_stars)  GLVertexOOVector(vector_subtract(vertices[vi], warp_vector));
		}
		glEnd();
		// reapply normal conditions
		glDisable(GL_FOG);
	}
	
	CheckOpenGLErrors(@"DustEntity after drawing %@", self);
}


- (void)resetGraphicsState
{
	if (displayListName != 0)
	{
		glDeleteLists(displayListName, 1);
		displayListName = 0;
	}
}

@end
