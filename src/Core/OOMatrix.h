/*

OOMatrix.h

Mathematical framework for Oolite.

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


#ifndef INCLUDED_OOMATHS_h
	#error Do not include OOMatrix.h directly; include OOMaths.h.
#else

/* Deprecated legacy representations */
typedef GLfloat	gl_matrix[16];


typedef struct OOMatrix
{
	GLfloat				m[4][4];
} OOMatrix;


extern const OOMatrix	kIdentityMatrix;		/* {1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1} */
extern const OOMatrix	kZeroMatrix;			/* {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0} */


/* Matrix construction and standard primitive matrices */
OOINLINE OOMatrix OOMatrixConstruct(GLfloat aa, GLfloat ab, GLfloat ac, GLfloat ad,
									GLfloat ba, GLfloat bb, GLfloat bc, GLfloat bd,
									GLfloat ca, GLfloat cb, GLfloat cc, GLfloat cd,
									GLfloat da, GLfloat db, GLfloat dc, GLfloat dd) INLINE_CONST_FUNC;

OOINLINE OOMatrix OOMatrixFromOrientationAndPosition(Quaternion orientation, Vector position) INLINE_CONST_FUNC;

OOINLINE OOMatrix OOMatrixFromBasisVectorsAndPosition(Vector i, Vector j, Vector k, Vector position) INLINE_CONST_FUNC;
OOINLINE OOMatrix OOMatrixFromBasisVectors(Vector i, Vector j, Vector k) INLINE_CONST_FUNC;

OOINLINE OOMatrix OOMatrixForRotationX(GLfloat angle) INLINE_CONST_FUNC;
OOINLINE OOMatrix OOMatrixForRotationY(GLfloat angle) INLINE_CONST_FUNC;
OOINLINE OOMatrix OOMatrixForRotationZ(GLfloat angle) INLINE_CONST_FUNC;
OOMatrix OOMatrixForRotation(Vector axis, GLfloat angle) CONST_FUNC;
OOMatrix OOMatrixForQuaternionRotation(Quaternion orientation);

OOINLINE OOMatrix OOMatrixForTranslation(Vector v) INLINE_CONST_FUNC;
OOINLINE OOMatrix OOMatrixForTranslationComponents(GLfloat dx, GLfloat dy, GLfloat dz) INLINE_CONST_FUNC;


/* Matrix transformations */
OOINLINE OOMatrix OOMatrixTranslate(OOMatrix m, Vector offset) INLINE_CONST_FUNC;
OOINLINE OOMatrix OOMatrixTranslateComponents(OOMatrix m, GLfloat dx, GLfloat dy, GLfloat dz) INLINE_CONST_FUNC;

OOINLINE OOMatrix OOMatrixRotateX(OOMatrix m, GLfloat angle) INLINE_CONST_FUNC;
OOINLINE OOMatrix OOMatrixRotateY(OOMatrix m, GLfloat angle) INLINE_CONST_FUNC;
OOINLINE OOMatrix OOMatrixRotateZ(OOMatrix m, GLfloat angle) INLINE_CONST_FUNC;
OOINLINE OOMatrix OOMatrixRotate(OOMatrix m, Vector axis, GLfloat angle) INLINE_CONST_FUNC;
OOINLINE OOMatrix OOMatrixRotateQuaternion(OOMatrix m, Quaternion quat) INLINE_CONST_FUNC;


/* Matrix multiplication */
OOMatrix OOMatrixMultiply(OOMatrix a, OOMatrix b) CONST_FUNC;
Vector OOVectorMultiplyMatrix(Vector v, OOMatrix m) CONST_FUNC;


/* Orthogonalizion - avoidance of distortions due to numerical inaccuracy. */
OOMatrix OOMatrixOrthogonalize(OOMatrix m) CONST_FUNC;


/*	OpenGL conveniences. Need to be macros to work with OOMacroOpenGL. */
#define OOMatrixValuesForOpenGL(M) (&(M).m[0][0])
#define GLMultOOMatrix(M) do { OOMatrix m_ = M; glMultMatrixf(OOMatrixValuesForOpenGL(m_)); } while (0)
#define GLLoadOOMatrix(M) do { OOMatrix m_ = M; glLoadMatrixf(OOMatrixValuesForOpenGL(m_)); } while (0)
#define GLMultTransposeOOMatrix(M) do { OOMatrix m_ = M; glMultTransposeMatrixf(OOMatrixValuesForOpenGL(m_)); } while (0)
#define GLLoadTransposeOOMatrix(M) do { OOMatrix m_ = M; glLoadTransposeMatrixf(OOMatrixValuesForOpenGL(m_)); } while (0)

OOINLINE OOMatrix OOMatrixLoadGLMatrix(unsigned long /* GLenum */ matrixID) ALWAYS_INLINE_FUNC;


/* Conversion to/from legacy representations */
OOINLINE OOMatrix OOMatrixFromGLMatrix(gl_matrix m) NONNULL_FUNC;

#ifdef __OBJC__
NSString *OOMatrixDescription(OOMatrix matrix);		// @"{{#, #, #, #}, {#, #, #, #}, {#, #, #, #}, {#, #, #, #}}"
#endif



/*** Only inline definitions beyond this point ***/

OOINLINE OOMatrix OOMatrixConstruct(GLfloat aa, GLfloat ab, GLfloat ac, GLfloat ad,
									GLfloat ba, GLfloat bb, GLfloat bc, GLfloat bd,
									GLfloat ca, GLfloat cb, GLfloat cc, GLfloat cd,
									GLfloat da, GLfloat db, GLfloat dc, GLfloat dd)
{
	OOMatrix r =
	{{
		{ aa, ab, ac, ad },
		{ ba, bb, bc, bd },
		{ ca, cb, cc, cd },
		{ da, db, dc, dd }
	}};
	return r;
}

OOINLINE OOMatrix OOMatrixFromOrientationAndPosition(Quaternion orientation, Vector position)
{
	OOMatrix m = OOMatrixForQuaternionRotation(orientation);
	return OOMatrixTranslate(m, position);
}


OOINLINE OOMatrix OOMatrixFromBasisVectorsAndPosition(Vector i, Vector j, Vector k, Vector p)
{
	return OOMatrixConstruct
	(
		i.x,	i.y,	i.z,	0.0f,
		j.x,	j.y,	j.z,	0.0f,
		k.x,	k.y,	k.z,	0.0f,
		p.x,	p.y,	p.z,	1.0f
	);
}


OOINLINE OOMatrix OOMatrixFromBasisVectors(Vector i, Vector j, Vector k)
{
	return OOMatrixFromBasisVectorsAndPosition(i, j, k, kZeroVector);
}


/* Standard primitive transformation matrices: */
OOMatrix OOMatrixForRotationX(GLfloat angle)
{
	GLfloat			s, c;
	
	s = sinf(angle);
	c = cosf(angle);
	
	return OOMatrixConstruct
	(
		1,  0,  0,  0,
		0,  c,  s,  0,
		0, -s,  c,  0,
		0,  0,  0,  1
	);
}


OOMatrix OOMatrixForRotationY(GLfloat angle)
{
	GLfloat			s, c;
	
	s = sinf(angle);
	c = cosf(angle);
	
	return OOMatrixConstruct
	(
		c,  0, -s,  0,
		0,  1,  0,  0,
		s,  0,  c,  0,
		0,  0,  0,  1
	);
}


OOMatrix OOMatrixForRotationZ(GLfloat angle)
{
	GLfloat			s, c;
	
	s = sinf(angle);
	c = cosf(angle);
	
	return OOMatrixConstruct
	(
	    c,  s,  0,  0,
	   -s,  c,  0,  0,
	    0,  0,  1,  0,
		0,  0,  0,  1
	);
}
OOINLINE OOMatrix OOMatrixForTranslationComponents(GLfloat dx, GLfloat dy, GLfloat dz)
{
	return OOMatrixConstruct
	(
	    1,  0,  0,  0,
	    0,  1,  0,  0,
	    0,  0,  1,  0,
	   dx, dy, dz,  1
	);
}


OOINLINE OOMatrix OOMatrixForTranslation(Vector v)
{
	return OOMatrixForTranslationComponents(v.x, v.y, v.z);
}


OOINLINE OOMatrix OOMatrixTranslateComponents(OOMatrix m, GLfloat dx, GLfloat dy, GLfloat dz)
{
	m.m[3][0] += dx;
	m.m[3][1] += dy;
	m.m[3][2] += dz;
	return m;
}


OOINLINE OOMatrix OOMatrixTranslate(OOMatrix m, Vector offset)
{
	return OOMatrixTranslateComponents(m, offset.x, offset.y, offset.z);
}


OOINLINE OOMatrix OOMatrixRotateX(OOMatrix m, GLfloat angle)
{
	return OOMatrixMultiply(m, OOMatrixForRotationX(angle));
}


OOINLINE OOMatrix OOMatrixRotateY(OOMatrix m, GLfloat angle)
{
	return OOMatrixMultiply(m, OOMatrixForRotationY(angle));
}


OOINLINE OOMatrix OOMatrixRotateZ(OOMatrix m, GLfloat angle)
{
	return OOMatrixMultiply(m, OOMatrixForRotationZ(angle));
}


OOINLINE OOMatrix OOMatrixRotate(OOMatrix m, Vector axis, GLfloat angle)
{
	return OOMatrixMultiply(m, OOMatrixForRotation(axis, angle));
}


OOINLINE OOMatrix OOMatrixRotateQuaternion(OOMatrix m, Quaternion quat)
{
	return OOMatrixMultiply(m, OOMatrixForQuaternionRotation(quat));
}

OOINLINE OOMatrix OOMatrixFromGLMatrix(gl_matrix m)
{
	assert(m != NULL);
	
	OOMatrix r;
	memcpy(&r.m[0][0], m, sizeof (GLfloat) * 16);
	return r;
}

OOINLINE OOMatrix OOMatrixLoadGLMatrix(unsigned long /* GLenum */ matrixID)
{
	OOMatrix m;
	glGetFloatv(matrixID, OOMatrixValuesForOpenGL(m));
	return m;
}







/***** Deprecated legacy stuff beyond this point, do not use *****/


/* Set matrix to identity matrix */
OOINLINE void OOCopyGLMatrix(gl_matrix dst, const gl_matrix src) ALWAYS_INLINE_FUNC NONNULL_FUNC;


/* Multiply vector by OpenGL matrix */
void mult_vector_gl_matrix(Vector *outVector, const gl_matrix glmat) NONNULL_FUNC;

/* Build an OpenGL matrix from vectors */
void vectors_into_gl_matrix(Vector forward, Vector right, Vector up, gl_matrix outGLMatrix) NONNULL_FUNC;



/*** Only inline definitions beyond this point ***/
OOINLINE void OOCopyGLMatrix(gl_matrix dst, const gl_matrix src)
{
	memcpy(dst, src, sizeof dst);
}


#endif	/* INCLUDED_OOMATHS_h */
