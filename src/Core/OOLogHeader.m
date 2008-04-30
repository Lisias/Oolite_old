/*

OOLogHeader.m


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

Copyright (C) 2007-2008 Jens Ayton

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

#import "OOLogHeader.h"
#import "OOCPUInfo.h"
#import "OOLogging.h"


static NSString *AdditionalLogHeaderInfo(void);


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
	
	#ifdef OO_DEBUG
		#define RELEASE_VARIANT_STRING " debug"
	#elif !defined (NDEBUG)
		#define RELEASE_VARIANT_STRING " test release"
	#else
		#define RELEASE_VARIANT_STRING ""
	#endif
	
	// systemString: NSString with system type and possibly version.
	#if OOLITE_MAC_OS_X
		NSString *systemString = [NSString stringWithFormat:@OS_TYPE_STRING " %@", [[NSProcessInfo processInfo] operatingSystemVersionString]];
	#else
		#define systemString @OS_TYPE_STRING
	#endif
	
	NSString *versionString = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
	if (versionString == nil)  versionString = @"<unknown version>";
	
	NSMutableString *miscString = [NSMutableString stringWithFormat:@"Opening log for Oolite version %@ (" CPU_TYPE_STRING RELEASE_VARIANT_STRING ") under %@ at %@.\n", versionString, systemString, [NSDate date]];
	
	[miscString appendString:AdditionalLogHeaderInfo()];
	
	#if OOLITE_ALTIVEC
		if (OOAltiVecAvailable())
		{
			[miscString appendString:@" Altivec acceleration available."];
		}
		else
		{
			[miscString appendString:@" Altivec acceleration not available."];
		}
	#endif
	
	[miscString appendString:@"\nNote that the contents of the log file can be adjusted by editing logcontrol.plist."];
	
	OOLog(@"log.header", @"%@\n", miscString);
}


// System-specific stuff to append to log header.
#if OOLITE_MAC_OS_X
#import <sys/sysctl.h>

static NSString *GetSysCtlString(const char *name);
static unsigned long long GetSysCtlInt(const char *name);
static NSString *GetCPUDescription(void);

static NSString *AdditionalLogHeaderInfo(void)
{
	unsigned long			sysPhysMem;
	NSString				*sysModel = nil;
	
	sysModel = GetSysCtlString("hw.model");
	Gestalt(gestaltPhysicalRAMSizeInMegabytes, (long *)&sysPhysMem);
	
	return [NSString stringWithFormat:@"Machine type: %@, %u MiB memory, %@.", sysModel, sysPhysMem, GetCPUDescription()];
}


static NSString *GetCPUDescription(void)
{
	unsigned long long	sysCPUType, sysCPUSubType,
	sysCPUFrequency, sysCPUCount;
	NSString			*typeStr = nil, *subTypeStr = nil;
	
	sysCPUType = GetSysCtlInt("hw.cputype");
	sysCPUSubType = GetSysCtlInt("hw.cpusubtype");
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
		}
			break;
			
		case CPU_TYPE_I386:
			typeStr = @"x86";
			// Currently all x86 CPUs seem to report subtype CPU_SUBTYPE_486, which isn't very useful.
			if (sysCPUSubType == CPU_SUBTYPE_486)  subTypeStr = @"";
			break;
	}
	
	if (typeStr == nil)  typeStr = [NSString stringWithFormat:@"%u", sysCPUType];
	if (subTypeStr == nil)  subTypeStr = [NSString stringWithFormat:@":%u", sysCPUSubType];
	
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
	return [NSString stringWithFormat:@"%u processors detected.", OOCPUCount()];
}
#endif
