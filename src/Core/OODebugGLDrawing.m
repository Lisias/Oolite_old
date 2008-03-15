/*

OODebugDrawing.m


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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2007 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OODebugGLDrawing.h"
#import "OOMacroOpenGL.h"

static void BeginDebugWireframe(void);
#define EndDebugWireframe() glPopAttrib()

OOINLINE void ApplyColor(OOColor *color)
{
	GLfloat				r, g, b, a;
	
	OO_ENTER_OPENGL();
	
	if (EXPECT_NOT(color == nil))  color = [OOColor lightGrayColor];
	[color getRed:&r green:&g blue:&b alpha:&a];
	glColor4f(r, g, b, a);
}


void OODebugDrawColoredBoundingBoxBetween(Vector min, Vector max, OOColor *color)
{
	OO_ENTER_OPENGL();
	BeginDebugWireframe();
	
	ApplyColor(color);
	glBegin(GL_LINE_LOOP);
		glVertex3f(min.x, min.y, min.z);
		glVertex3f(max.x, min.y, min.z);
		glVertex3f(max.x, max.y, min.z);
		glVertex3f(min.x, max.y, min.z);
		glVertex3f(min.x, max.y, max.z);
		glVertex3f(max.x, max.y, max.z);
		glVertex3f(max.x, min.y, max.z);
		glVertex3f(min.x, min.y, max.z);
	glEnd();
	glBegin(GL_LINES);
		glVertex3f(max.x, min.y, min.z);
		glVertex3f(max.x, min.y, max.z);
		glVertex3f(max.x, max.y, min.z);
		glVertex3f(max.x, max.y, max.z);
		glVertex3f(min.x, min.y, min.z);
		glVertex3f(min.x, max.y, min.z);
		glVertex3f(min.x, min.y, max.z);
		glVertex3f(min.x, max.y, max.z);
	glEnd();
	
	EndDebugWireframe();
}


void OODebugDrawColoredLine(Vector start, Vector end, OOColor *color)
{	
	OO_ENTER_OPENGL();
	BeginDebugWireframe();
	
	ApplyColor(color);
	
	float oldSize;
	glGetFloatv(GL_LINE_WIDTH, &oldSize);
	glLineWidth(1);
	
	glBegin(GL_LINES);
		glVertex3f(start.x, start.y, start.z);
		glVertex3f(end.x, end.y, end.z);
	glEnd();
	
	glLineWidth(oldSize);
	
	EndDebugWireframe();
}


void OODebugDrawBasis(Vector position, GLfloat scale)
{
	OO_ENTER_OPENGL();
	BeginDebugWireframe();
	
	glBegin(GL_LINES);
		glColor4f(1.0f, 0.0f, 0.0f, 1.0f);
		glVertex3f(position.x, position.y, position.z);
		glVertex3f(position.x + scale, position.y, position.z);
		
		glColor4f(0.0f, 1.0f, 0.0f, 1.0f);
		glVertex3f(position.x, position.y, position.z);
		glVertex3f(position.x, position.y + scale, position.z);
		
		glColor4f(0.0f, 0.0f, 1.0f, 1.0f);
		glVertex3f(position.x, position.y, position.z);
		glVertex3f(position.x, position.y, position.z + scale);
	glEnd();
	
	EndDebugWireframe();
}


void OODebugDrawPoint(Vector position, OOColor *color)
{
	OO_ENTER_OPENGL();
	BeginDebugWireframe();
	
	ApplyColor(color);
	
	float oldSize;
	glGetFloatv(GL_POINT_SIZE, &oldSize);
	glPointSize(10);
	
	glBegin(GL_POINTS);
		glVertex3f(position.x, position.y, position.z);
	glEnd();
	
	glPointSize(oldSize);
	
	EndDebugWireframe();
}


static void BeginDebugWireframe(void)
{
	OO_ENTER_OPENGL();
	
	glPushAttrib(GL_ENABLE_BIT | GL_DEPTH_BUFFER_BIT | GL_LINE_BIT | GL_CURRENT_BIT);
	
	glDisable(GL_LIGHTING);
	glDisable(GL_TEXTURE_2D);
	glDisable(GL_DEPTH_TEST);
	glDisable(GL_FOG);
	glDepthMask(GL_FALSE);
	
	glLineWidth(1.0f);
}
