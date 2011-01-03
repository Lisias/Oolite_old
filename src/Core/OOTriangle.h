/*

OOTriangle.h

Mathematical framework for Oolite.

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


#ifndef INCLUDED_OOMATHS_h
	#error Do not include OOTriangle.h directly; include OOMaths.h.
#else


typedef struct
{
	Vector		v[4];	// three vertices + normal
} Triangle;


/* Calculate normal for triangle, storing it in v[3] */
OOINLINE Vector calculateNormalForTriangle(Triangle *ioTriangle) NONNULL_FUNC;

/* Generate a triangle from three vertices. Also calculates normal. */
OOINLINE Triangle make_triangle(Vector v0, Vector v1, Vector v2) CONST_FUNC;

/* resolve vector in arbitrary ijk vectors */
OOINLINE Vector resolveVectorInIJK(Vector v0, Triangle ijk);


/*** Only inline definitions beyond this point ***/

OOINLINE Triangle make_triangle(Vector v0, Vector v1, Vector v2)
{
	Triangle result;
	result.v[0] = v0;
	result.v[1] = v1;
	result.v[2] = v2;
	calculateNormalForTriangle(&result);
	return result;
}


OOINLINE Vector calculateNormalForTriangle(Triangle *tri)
{
	Vector v01 = vector_subtract(tri->v[1], tri->v[0]);
	Vector v12 = vector_subtract(tri->v[2], tri->v[1]);
	tri->v[3] = cross_product(v01, v12);
	return tri->v[3];
}


OOINLINE Vector resolveVectorInIJK(Vector v0, Triangle ijk)
{
	Vector result;
	result.x = dot_product(v0, ijk.v[0]);
	result.y = dot_product(v0, ijk.v[1]);
	result.z = dot_product(v0, ijk.v[2]);
	return result;
}


#endif	/* INCLUDED_OOMATHS_h */
