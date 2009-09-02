#ifndef INCLUDED_OOFUNCTIONATTRIBUTES_h
#define INCLUDED_OOFUNCTIONATTRIBUTES_h


#ifndef GCC_ATTR
	#ifdef __GNUC__
		#define GCC_ATTR(x)	__attribute__(x)
	#else
		#define GCC_ATTR(x)
	#endif
#endif


// Clang feature testing extension.
#ifndef __has_feature
	#define __has_feature(x) (0)
#endif



#define OOINLINE			static inline


#if !OO_DEBUG
#define ALWAYS_INLINE_FUNC	GCC_ATTR((always_inline))	// Force inlining of function
#else
#define ALWAYS_INLINE_FUNC								// Don't force inlining of function (because gdb is silly)
#endif

#define PURE_FUNC			GCC_ATTR((pure))			// result dependent only on params and globals
#define CONST_FUNC			GCC_ATTR((const))			// pure + no pointer dereferences or globals
#define NONNULL_FUNC		GCC_ATTR((nonnull))			// Pointer parameters may not be NULL
#define DEPRECATED_FUNC		GCC_ATTR((deprecated))		// Warn if this function is used
#define NO_RETURN_FUNC		GCC_ATTR((noreturn))		// Function can never return

#define INLINE_PURE_FUNC	ALWAYS_INLINE_FUNC PURE_FUNC
#define INLINE_CONST_FUNC	ALWAYS_INLINE_FUNC CONST_FUNC


#ifdef __GNUC__
	#define EXPECT(x)		__builtin_expect((x), 1)
	#define EXPECT_NOT(x)	__builtin_expect((x), 0)
#else
	#define EXPECT(x)		(x)
	#define EXPECT_NOT(x)	(x)
#endif


// OO_RETURNS_RETAINED: indicates the caller of a method owns a reference to the return value.
#if __has_feature(attribute_ns_returns_retained)
	#define OO_RETURNS_RETAINED __attribute__((ns_returns_retained))
#else
	#define OO_RETURNS_RETAINED
#endif


#endif	/* INCLUDED_OOFUNCTIONATTRIBUTES_h */
