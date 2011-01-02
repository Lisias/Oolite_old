/*

OOLogHeader.m


Copyright (C) 2007-2010 Jens Ayton and contributors

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

#import "OOLogHeader.h"
#import "OOCPUInfo.h"
#import "OOLogging.h"
#import "OOOXPVerifier.h"
#import "Universe.h"
#import "OOStellarBody.h"
#import "OOJavaScriptEngine.h"


static NSString *AdditionalLogHeaderInfo(void);

NSString *OOPlatformDescription(void);


void OOPrintLogHeader(void)
{
	// Bunch of string literal macros which are assembled into a CPU info string.
	#if defined (__ppc__)
		#define CPU_TYPE_STRING "PPC-32"
	#elif defined (__ppc64__)
		#define CPU_TYPE_STRING "PPC-64"
	#elif defined (__i386__)
		#define CPU_TYPE_STRING "x86-32"
	#elif defined (__x86_64__)
		#define CPU_TYPE_STRING "x86-64"
	#else
		#if OOLITE_BIG_ENDIAN
			#define CPU_TYPE_STRING "<unknown big-endian architecture>"
		#elif OOLITE_LITTLE_ENDIAN
			#define CPU_TYPE_STRING "<unknown little-endian architecture>"
		#else
			#define CPU_TYPE_STRING "<unknown architecture with unknown byte order>"
		#endif
	#endif
	
	#if OOLITE_MAC_OS_X
		#define OS_TYPE_STRING "Mac OS X"
	#elif OOLITE_WINDOWS
		#define OS_TYPE_STRING "Windows"
	#elif OOLITE_LINUX
		#define OS_TYPE_STRING "Linux"	// Hmm, what about other unices?
	#elif OOLITE_SDL
		#define OS_TYPE_STRING "unknown SDL system"
	#elif OOLITE_HAVE_APPKIT
		#define OS_TYPE_STRING "unknown AppKit system"
	#else
		#define OS_TYPE_STRING "unknown system"
	#endif
	
	#if OO_DEBUG
		#define RELEASE_VARIANT_STRING " debug"
	#elif !defined (NDEBUG)
		#define RELEASE_VARIANT_STRING " test release"
	#else
		#define RELEASE_VARIANT_STRING ""
	#endif
	
	NSArray *featureStrings = [NSArray arrayWithObjects:
	// User features
	#if OO_SHADERS

		@"GLSL shaders",
	#endif
	
	#if NEW_PLANETS
		@"new planets",
	#elif ALLOW_PROCEDURAL_PLANETS
		@"procedural planet textures",
	#endif
	
	#if DOCKING_CLEARANCE_ENABLED
		@"docking clearance",
	#endif
	
	#if WORMHOLE_SCANNER
		@"wormhole scanner",
	#endif
	
	#if TARGET_INCOMING_MISSILES
		@"target incoming missiles",
	#endif
	
	#if OOLITE_MAC_OS_X || defined(HAVE_LIBESPEAK)
		@"spoken messages",
	#endif
	
	#if MASS_DEPENDENT_FUEL_PRICES
		@"mass/fuel pricing",
	#endif
	
	// Debug features
	#if OO_CHECK_GL_HEAVY
		@"heavy OpenGL error checking",
	#endif
	
	#ifndef OO_EXCLUDE_DEBUG_SUPPORT
		@"JavaScript console support",
		#if OOLITE_MAC_OS_X
			// Under Mac OS X, Debug.oxp adds more than console support.
			@"Debug plug-in support",
		#endif
	#endif
	
	#if OO_OXP_VERIFIER_ENABLED
		@"OXP verifier",
	#endif
	
	#if OO_LOCALIZATION_TOOLS
		@"localization tools",
	#endif
	
	#if DEBUG_GRAPHVIZ
		@"debug GraphViz support",
	#endif
	
	#if OOJS_PROFILE
		@"JavaScript profiling",
	#endif
	
	#if !OO_NEW_JS
		@"OUTDATED JAVASCRIPT ENGINE",
	#endif
	
		nil];
	
	// systemString: NSString with system type and possibly version.
	#if OOLITE_MAC_OS_X
		NSString *systemString = [NSString stringWithFormat:@OS_TYPE_STRING " %@", [[NSProcessInfo processInfo] operatingSystemVersionString]];
	#else
		#define systemString @OS_TYPE_STRING
	#endif
	
	NSString *versionString = nil;
	#if (defined (SNAPSHOT_BUILD) && defined (OOLITE_SNAPSHOT_VERSION))
		versionString = @"development version " OOLITE_SNAPSHOT_VERSION;
	#else
		versionString = [NSString stringWithFormat:@"version %@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]];
	#endif
	if (versionString == nil)  versionString = @"<unknown version>";
	
	NSMutableString *miscString = [NSMutableString stringWithFormat:@"Opening log for Oolite %@ (" CPU_TYPE_STRING RELEASE_VARIANT_STRING ") under %@ at %@.\n", versionString, systemString, [NSDate date]];
	
	[miscString appendString:AdditionalLogHeaderInfo()];
	
	NSString *featureDesc = [featureStrings componentsJoinedByString:@", "];
	if ([featureDesc length] == 0)  featureDesc = @"none";
	[miscString appendFormat:@"\nOolite options: %@.\n", featureDesc];
	
	[miscString appendString:@"\nNote that the contents of the log file can be adjusted by editing logcontrol.plist."];
	
	OOLog(@"log.header", @"%@\n", miscString);
}


NSString *OOPlatformDescription(void)
{
	#if OOLITE_MAC_OS_X
		NSString *systemString = [NSString stringWithFormat:@OS_TYPE_STRING " %@", [[NSProcessInfo processInfo] operatingSystemVersionString]];
	#else
		#define systemString @OS_TYPE_STRING
	#endif
	
	return [NSString stringWithFormat:@"%@ ("CPU_TYPE_STRING RELEASE_VARIANT_STRING")", systemString];
}


// System-specific stuff to append to log header.
#if OOLITE_MAC_OS_X
#import <sys/sysctl.h>


#ifndef CPUFAMILY_INTEL_6_13
// Copied from OS X 10.5 SDK
#define CPUFAMILY_INTEL_6_13	0xaa33392b
#define CPUFAMILY_INTEL_6_14	0x73d67300  /* "Intel Core Solo" and "Intel Core Duo" (32-bit Pentium-M with SSE3) */
#define CPUFAMILY_INTEL_6_15	0x426f69ef  /* "Intel Core 2 Duo" */
#define CPUFAMILY_INTEL_6_23	0x78ea4fbc  /* Penryn */
#define CPUFAMILY_INTEL_6_26	0x6b5a4cd2

#define CPUFAMILY_INTEL_YONAH	CPUFAMILY_INTEL_6_14
#define CPUFAMILY_INTEL_MEROM	CPUFAMILY_INTEL_6_15
#define CPUFAMILY_INTEL_PENRYN	CPUFAMILY_INTEL_6_23
#define CPUFAMILY_INTEL_NEHALEM	CPUFAMILY_INTEL_6_26

#define CPUFAMILY_INTEL_CORE	CPUFAMILY_INTEL_6_14
#define CPUFAMILY_INTEL_CORE2	CPUFAMILY_INTEL_6_15
#endif

#ifndef CPUFAMILY_INTEL_WESTMERE
// Copied from OS X 10.6 SDK
#define CPUFAMILY_INTEL_WESTMERE	0x573b5eec
#endif

#ifndef CPU_TYPE_ARM
#define CPU_TYPE_ARM			((cpu_type_t) 12)
#define CPU_SUBTYPE_ARM_ALL		((cpu_subtype_t) 0)
#define CPU_SUBTYPE_ARM_V4T		((cpu_subtype_t) 5)
#define CPU_SUBTYPE_ARM_V6		((cpu_subtype_t) 6)
#define CPUFAMILY_ARM_9			0xe73283ae
#define CPUFAMILY_ARM_11		0x8ff620d8
#endif
#ifndef CPUFAMILY_ARM_XSCALE
// From 10.6 SDK
#define CPUFAMILY_ARM_XSCALE 0x53b005f5
#define CPUFAMILY_ARM_13     0x0cc90e64
#endif


static NSString *GetSysCtlString(const char *name);
static unsigned long long GetSysCtlInt(const char *name);
static NSString *GetCPUDescription(void);

static NSString *AdditionalLogHeaderInfo(void)
{
	NSString				*sysModel = nil;
	unsigned long long		sysPhysMem;
	
	sysModel = GetSysCtlString("hw.model");
	sysPhysMem = GetSysCtlInt("hw.memsize");
	
	return [NSString stringWithFormat:@"Machine type: %@, %llu MiB memory, %@.", sysModel, sysPhysMem >> 20, GetCPUDescription()];
}


static NSString *GetCPUDescription(void)
{
	unsigned long long	sysCPUType, sysCPUSubType, sysCPUFamily,
						sysCPUFrequency, sysCPUCount;
	NSString			*typeStr = nil, *subTypeStr = nil;
	
	sysCPUType = GetSysCtlInt("hw.cputype");
	sysCPUSubType = GetSysCtlInt("hw.cpusubtype");
	sysCPUFamily = GetSysCtlInt("hw.cpufamily");
	sysCPUFrequency = GetSysCtlInt("hw.cpufrequency");
	sysCPUCount = GetSysCtlInt("hw.logicalcpu");
	
	/*	Note: CPU_TYPE_STRING tells us the build architecture. This gets the
		physical CPU type. They may differ, for instance, when running under
		Rosetta. The code is written for flexibility, although ruling out
		x86 code running on PPC would be entirely reasonable.
	*/
	switch (sysCPUType)
	{
		case CPU_TYPE_POWERPC:
			typeStr = @"PowerPC";
			switch (sysCPUSubType)
			{
				case CPU_SUBTYPE_POWERPC_750:
					subTypeStr = @" G3 (750)";
					break;
					
				case CPU_SUBTYPE_POWERPC_7400:
					subTypeStr = @" G4 (7400)";
					break;
					
				case CPU_SUBTYPE_POWERPC_7450:
					subTypeStr = @" G4 (7450)";
					break;
					
				case CPU_SUBTYPE_POWERPC_970:
					subTypeStr = @" G5 (970)";
					break;
				
				default:
					subTypeStr = [NSString stringWithFormat:@":%u", sysCPUSubType];
			}
			break;
			
		case CPU_TYPE_I386:
			typeStr = @"x86";
			switch (sysCPUFamily)
			{
				case CPUFAMILY_INTEL_6_13:
					subTypeStr = @" (Intel 6:13)";
					break;
					
				case CPUFAMILY_INTEL_YONAH:
					subTypeStr = @" (Core/Yonah)";
					break;
					
				case CPUFAMILY_INTEL_MEROM:
					subTypeStr = @" (Core 2/Merom)";
					break;
					
				case CPUFAMILY_INTEL_PENRYN:
					subTypeStr = @" (Penryn)";
					break;
					
				case CPUFAMILY_INTEL_NEHALEM:
					subTypeStr = @" (Nehalem)";
					break;
					
				case CPUFAMILY_INTEL_WESTMERE:
					subTypeStr = @" (Westmere)";
					break;
					
				default:
					subTypeStr = [NSString stringWithFormat:@" (family %x)", sysCPUFamily];
			}
			break;
		
		case CPU_TYPE_ARM:
			typeStr = @"ARM";
			switch (sysCPUSubType)
			{
				case CPU_SUBTYPE_ARM_V4T:
					subTypeStr = @" v4T";
					break;
					
				case CPU_SUBTYPE_ARM_V6:
					subTypeStr = @"v6";		// No space
					break;
			}
			if (subTypeStr == nil)
			{
				switch (sysCPUFamily)
				{
					case CPUFAMILY_ARM_9:
						subTypeStr = @"9";	// No space
						break;
						
					case CPUFAMILY_ARM_11:
						subTypeStr = @"11";	// No space
						break;
						
					case CPUFAMILY_ARM_XSCALE:
						subTypeStr = @" XScale";
						break;
						
					case CPUFAMILY_ARM_13:
						subTypeStr = @"13";	// No such thing?
						break;
					
					default:
						subTypeStr = [NSString stringWithFormat:@" (family %u)", sysCPUFamily];
				}
			}
	}
	
	if (typeStr == nil)  typeStr = [NSString stringWithFormat:@"%u", sysCPUType];
	
	return [NSString stringWithFormat:@"%llu x %@%@ @ %llu MHz", sysCPUCount, typeStr, subTypeStr, (sysCPUFrequency + 500000) / 1000000];
}


static NSString *GetSysCtlString(const char *name)
{
	char					*buffer = NULL;
	size_t					size = 0;
	
	// Get size
	sysctlbyname(name, NULL, &size, NULL, 0);
	if (size == 0)  return nil;
	
	buffer = alloca(size);
	if (sysctlbyname(name, buffer, &size, NULL, 0) != 0)  return nil;
	return [NSString stringWithUTF8String:buffer];
}


static unsigned long long GetSysCtlInt(const char *name)
{
	unsigned long long		llresult = 0;
	unsigned int			intresult = 0;
	size_t					size;
	
	size = sizeof llresult;
	if (sysctlbyname(name, &llresult, &size, NULL, 0) != 0)  return 0;
	if (size == sizeof llresult)  return llresult;
	
	size = sizeof intresult;
	if (sysctlbyname(name, &intresult, &size, NULL, 0) != 0)  return 0;
	if (size == sizeof intresult)  return intresult;
	
	return 0;
}

#else
static NSString *AdditionalLogHeaderInfo(void)
{
	unsigned cpuCount = OOCPUCount();
	return [NSString stringWithFormat:@"%u processor%@ detected.", cpuCount, cpuCount != 1 ? @"s" : @""];
}
#endif
