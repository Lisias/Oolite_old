/*

OOJavaScriptEngine.m

JavaScript support for Oolite
Copyright (C) 2007-2011 David Taylor and Jens Ayton.

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

#import <jsdbgapi.h>
#import "OOJavaScriptEngine.h"
#import "OOJSEngineTimeManagement.h"
#import "OOJSScript.h"

#import "OOCollectionExtractors.h"
#import "Universe.h"
#import "OOPlanetEntity.h"
#import "NSStringOOExtensions.h"
#import "OOWeakReference.h"
#import "EntityOOJavaScriptExtensions.h"
#import "ResourceManager.h"
#import "NSNumberOOExtensions.h"
#import "OOConstToJSString.h"

#import "OOJSGlobal.h"
#import "OOJSMissionVariables.h"
#import "OOJSMission.h"
#import "OOJSVector.h"
#import "OOJSQuaternion.h"
#import "OOJSEntity.h"
#import "OOJSShip.h"
#import "OOJSStation.h"
#import "OOJSPlayer.h"
#import "OOJSPlayerShip.h"
#import "OOJSManifest.h"
#import "OOJSPlanet.h"
#import "OOJSSystem.h"
#import "OOJSOolite.h"
#import "OOJSTimer.h"
#import "OOJSClock.h"
#import "OOJSSun.h"
#import "OOJSWorldScripts.h"
#import "OOJSSound.h"
#import "OOJSSoundSource.h"
#import "OOJSSpecialFunctions.h"
#import "OOJSSystemInfo.h"
#import "OOJSEquipmentInfo.h"
#import "OOJSShipGroup.h"
#import "OOJSFrameCallbacks.h"
#import "OOJSFont.h"

#import "OOProfilingStopwatch.h"
#import "OOLoggingExtended.h"

#import <stdlib.h>


#if OO_NEW_JS
#define OOJSENGINE_JSVERSION		JSVERSION_ECMA_5
#ifdef DEBUG
#define JIT_OPTIONS					0
#else
#define JIT_OPTIONS					JSOPTION_JIT | JSOPTION_METHODJIT | JSOPTION_PROFILING
#endif
#define OOJSENGINE_CONTEXT_OPTIONS	JSOPTION_VAROBJFIX | JSOPTION_RELIMIT | JSOPTION_ANONFUNFIX | JIT_OPTIONS
#else
#define OOJSENGINE_JSVERSION		JSVERSION_1_7
#define OOJSENGINE_CONTEXT_OPTIONS	JSOPTION_VAROBJFIX | JSOPTION_NATIVE_BRANCH_CALLBACK
#endif


#define OOJS_STACK_SIZE				8192


#if !OOLITE_NATIVE_EXCEPTIONS
#warning Native exceptions apparently not available. JavaScript functions are not exception-safe.
#endif
#if defined(JS_THREADSAFE) && !OO_NEW_JS
#error Oolite and libjs must be built with JS_THREADSAFE undefined.
#endif


static OOJavaScriptEngine	*sSharedEngine = nil;
static unsigned				sErrorHandlerStackSkip = 0;

JSContext					*gOOJSMainThreadContext = NULL;


#if OOJSENGINE_MONITOR_SUPPORT

@interface OOJavaScriptEngine (OOMonitorSupportInternal)

- (void)sendMonitorError:(JSErrorReport *)errorReport
			 withMessage:(NSString *)message
			   inContext:(JSContext *)context;

- (void)sendMonitorLogMessage:(NSString *)message
			 withMessageClass:(NSString *)messageClass
					inContext:(JSContext *)context;

@end

#endif


@interface OOJavaScriptEngine (Private)

- (BOOL) lookUpStandardClassPointers;
- (void) registerStandardObjectConverters;

@end


static void ReportJSError(JSContext *context, const char *message, JSErrorReport *report);

static id JSArrayConverter(JSContext *context, JSObject *object);
static id JSStringConverter(JSContext *context, JSObject *object);
static id JSNumberConverter(JSContext *context, JSObject *object);
static id JSBooleanConverter(JSContext *context, JSObject *object);


static void ReportJSError(JSContext *context, const char *message, JSErrorReport *report)
{
	NSString			*severity = @"error";
	NSString			*messageText = nil;
	NSString			*lineBuf = nil;
	NSString			*messageClass = nil;
	NSString			*highlight = @"*****";
	NSString			*activeScript = nil;
	OOJavaScriptEngine	*jsEng = [OOJavaScriptEngine sharedEngine];
	BOOL				showLocation = [jsEng showErrorLocations];
	
	// Not OOJS_BEGIN_FULL_NATIVE() - we use JSAPI while paused.
	OOJSPauseTimeLimiter();
	
	jschar empty[1] = { 0 };
	JSErrorReport blankReport =
	{
		.filename = "<unspecified file>",
		.linebuf = "",
		.uclinebuf = empty,
		.uctokenptr = empty,
		.ucmessage = empty
	};
	if (EXPECT_NOT(report == NULL))  report = &blankReport;
	if (EXPECT_NOT(message == NULL || *message == '\0'))  message = "<unspecified error>";
	
	// Type of problem: error, warning or exception? (Strict flag wilfully ignored.)
	if (report->flags & JSREPORT_EXCEPTION) severity = @"exception";
	else if (report->flags & JSREPORT_WARNING)
	{
		severity = @"warning";
		highlight = @"-----";
	}
	
	// The error message itself
	messageText = [NSString stringWithUTF8String:message];
	
	// Get offending line, if present, and trim trailing line breaks
	lineBuf = [NSString stringWithUTF16String:report->uclinebuf];
	while ([lineBuf hasSuffix:@"\n"] || [lineBuf hasSuffix:@"\r"])  lineBuf = [lineBuf substringToIndex:[lineBuf length] - 1];
	
	// Get string for error number, for useful log message classes
	NSDictionary *errorNames = [ResourceManager dictionaryFromFilesNamed:@"javascript-errors.plist" inFolder:@"Config" andMerge:YES];
	NSString *errorNumberStr = [NSString stringWithFormat:@"%u", report->errorNumber];
	NSString *errorName = [errorNames oo_stringForKey:errorNumberStr];
	if (errorName == nil)  errorName = errorNumberStr;
	
	// Log message class
	messageClass = [NSString stringWithFormat:@"script.javaScript.%@.%@", severity, errorName];
	
	// Skip the rest if this is a warning being ignored.
	if ((report->flags & JSREPORT_WARNING) == 0 || OOLogWillDisplayMessagesInClass(messageClass))
	{
		// First line: problem description
		// avoid windows DEP exceptions!
		OOJSScript *thisScript = [[OOJSScript currentlyRunningScript] weakRetain];
		activeScript = [[thisScript weakRefUnderlyingObject] displayName];
		[thisScript release];
		
		if (activeScript == nil)  activeScript = @"<unidentified script>";
		OOLog(messageClass, @"%@ JavaScript %@ (%@): %@", highlight, severity, activeScript, messageText);
		
		if (!showLocation && sErrorHandlerStackSkip == 0 && report->filename != NULL)
		{
			// Second line: where error occured, and line if provided. (The line is only provided for compile-time errors, not run-time errors.)
			if ([lineBuf length] != 0)
			{
				OOLog(messageClass, @"      %s, line %d: %@", report->filename, report->lineno, lineBuf);
			}
			else
			{
				OOLog(messageClass, @"      %s, line %d.", report->filename, report->lineno);
			}
		}
		
#ifndef NDEBUG
		BOOL dump;
		if (report->flags & JSREPORT_WARNING)  dump = [jsEng dumpStackForWarnings];
		else  dump = [jsEng dumpStackForErrors];
		if (dump)  OOJSDumpStack(context);
#endif
		
#if OOJSENGINE_MONITOR_SUPPORT
		JSExceptionState *exState = JS_SaveExceptionState(context);
		[[OOJavaScriptEngine sharedEngine] sendMonitorError:report
												withMessage:messageText
												  inContext:context];
		JS_RestoreExceptionState(context, exState);
#endif
	}
	
	OOJSResumeTimeLimiter();
}


//===========================================================================
// JavaScript engine initialisation and shutdown
//===========================================================================

@implementation OOJavaScriptEngine

+ (OOJavaScriptEngine *)sharedEngine
{
	if (sSharedEngine == nil)  sSharedEngine = [[self alloc] init];
	
	return sSharedEngine;
}


- (void) runMissionCallback
{
	MissionRunCallback();
}


- (id) init
{
	NSAssert(sSharedEngine == nil, @"Attempt to create multiple OOJavaScriptEngines.");
	
#if OO_NEW_JS
	JS_SetCStringsAreUTF8();
#else
	// This one is causing trouble for the Linux crowd. :-/
	if (!JS_CStringsAreUTF8())
	{
		OOLog(@"script.javaScript.init.badSpiderMonkey", @"SpiderMonkey (libjs/libmozjs) must be built with the JS_C_STRINGS_ARE_UTF8 macro defined. Additionally, JS_THREADSAFE must be undefined and MOZILLA_1_8_BRANCH must be undefined.");
		exit(EXIT_FAILURE);
	}
#endif
	
	if (!(self = [super init]))  return nil;
	
	sSharedEngine = self;
	
	
#ifndef NDEBUG
	/*	Set stack trace preferences from preferences. These will be overriden
		by the debug OXP script if installed, but being able to enable traces
		without setting up the debug console could be useful for debugging
		users' problems.
	*/
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[self setDumpStackForErrors:[defaults boolForKey:@"dump-stack-for-errors"]];
	[self setDumpStackForWarnings:[defaults boolForKey:@"dump-stack-for-warnings"]];
#endif
	
	assert(sizeof(jschar) == sizeof(unichar));
	
	// set up global JS variables, including global and custom objects
	
	// initialize the JS run time, and return result in runtime
	runtime = JS_NewRuntime(8L * 1024L * 1024L);
	
	// if runtime creation failed, end the program here
	if (runtime == NULL)
	{
		OOLog(@"script.javaScript.init.error", @"***** FATAL ERROR: failed to create JavaScript runtime.");
		exit(1);
	}
	
	// OOJSTimeManagementInit() must be called before any context is created!
	OOJSTimeManagementInit(self, runtime);
	
	// create a context and associate it with the JS run time
	gOOJSMainThreadContext = JS_NewContext(runtime, OOJS_STACK_SIZE);
	
	// if context creation failed, end the program here
	if (gOOJSMainThreadContext == NULL)
	{
		OOLog(@"script.javaScript.init.error", @"***** FATAL ERROR: failed to create JavaScript context.");
		exit(1);
	}
	
	JS_BeginRequest(gOOJSMainThreadContext);
	
	JS_SetOptions(gOOJSMainThreadContext, OOJSENGINE_CONTEXT_OPTIONS);
	JS_SetVersion(gOOJSMainThreadContext, OOJSENGINE_JSVERSION);
	
#if JS_GC_ZEAL
	uint8_t gcZeal = [[NSUserDefaults standardUserDefaults]  oo_unsignedCharForKey:@"js-gc-zeal"];
	if (gcZeal > 0)
	{
		// Useful js-gc-zeal values are 0 (off), 1 and 2.
		OOLog(@"script.javaScript.debug.gcZeal", @"Setting JavaScript garbage collector zeal to %u.", gcZeal);
		JS_SetGCZeal(gOOJSMainThreadContext, gcZeal);
	}
#endif
	
	JS_SetErrorReporter(gOOJSMainThreadContext, ReportJSError);
	
	// Create the global object.
	CreateOOJSGlobal(gOOJSMainThreadContext, &globalObject);

	// Initialize the built-in JS objects and the global object.
	JS_InitStandardClasses(gOOJSMainThreadContext, globalObject);
	if (![self lookUpStandardClassPointers])
	{
		OOLog(@"script.javaScript.init.error", @"***** FATAL ERROR: failed to look up standard JavaScript classes.");
		exit(1);
	}
	[self registerStandardObjectConverters];
	
	SetUpOOJSGlobal(gOOJSMainThreadContext, globalObject);
	OOConstToJSStringInit(gOOJSMainThreadContext);
	
	// Initialize Oolite classes.
	InitOOJSMissionVariables(gOOJSMainThreadContext, globalObject);
	InitOOJSMission(gOOJSMainThreadContext, globalObject);
	InitOOJSOolite(gOOJSMainThreadContext, globalObject);
	InitOOJSVector(gOOJSMainThreadContext, globalObject);
	InitOOJSQuaternion(gOOJSMainThreadContext, globalObject);
	InitOOJSSystem(gOOJSMainThreadContext, globalObject);
	InitOOJSEntity(gOOJSMainThreadContext, globalObject);
	InitOOJSShip(gOOJSMainThreadContext, globalObject);
	InitOOJSStation(gOOJSMainThreadContext, globalObject);
	InitOOJSPlayer(gOOJSMainThreadContext, globalObject);
	InitOOJSPlayerShip(gOOJSMainThreadContext, globalObject);
	InitOOJSManifest(gOOJSMainThreadContext, globalObject);
	InitOOJSSun(gOOJSMainThreadContext, globalObject);
	InitOOJSPlanet(gOOJSMainThreadContext, globalObject);
	InitOOJSScript(gOOJSMainThreadContext, globalObject);
	InitOOJSTimer(gOOJSMainThreadContext, globalObject);
	InitOOJSClock(gOOJSMainThreadContext, globalObject);
	InitOOJSWorldScripts(gOOJSMainThreadContext, globalObject);
	InitOOJSSound(gOOJSMainThreadContext, globalObject);
	InitOOJSSoundSource(gOOJSMainThreadContext, globalObject);
	InitOOJSSpecialFunctions(gOOJSMainThreadContext, globalObject);
	InitOOJSSystemInfo(gOOJSMainThreadContext, globalObject);
	InitOOJSEquipmentInfo(gOOJSMainThreadContext, globalObject);
	InitOOJSShipGroup(gOOJSMainThreadContext, globalObject);
	InitOOJSFrameCallbacks(gOOJSMainThreadContext, globalObject);
	InitOOJSFont(gOOJSMainThreadContext, globalObject);
	
	// Run prefix scripts.
	[OOJSScript jsScriptFromFileNamed:@"oolite-global-prefix.js"
						   properties:[NSDictionary dictionaryWithObject:JSSpecialFunctionsObjectWrapper(gOOJSMainThreadContext)
																  forKey:@"special"]];
	
	JS_EndRequest(gOOJSMainThreadContext);
	
	OOLog(@"script.javaScript.init.success", @"Set up JavaScript context.");
	
	return self;
}


- (void) dealloc
{
	sSharedEngine = nil;
	
	JS_DestroyContext(gOOJSMainThreadContext);
	JS_DestroyRuntime(runtime);
	
	[super dealloc];
}


- (JSObject *) globalObject
{
	return globalObject;
}


- (BOOL) callJSFunction:(jsval)function
			  forObject:(JSObject *)jsThis
				   argc:(uintN)argc
				   argv:(jsval *)argv
				 result:(jsval *)outResult
{
	JSContext					*context = NULL;
	BOOL						result;
	
	NSParameterAssert(OOJSValueIsFunction(context, function));
	
	context = OOJSAcquireContext();
	
	OOJSStartTimeLimiter();
	result = JS_CallFunctionValue(context, jsThis, function, argc, argv, outResult);
	OOJSStopTimeLimiter();
	
	JS_ReportPendingException(context);
	OOJSRelinquishContext(context);
	
	return result;
}


- (void) removeGCObjectRoot:(JSObject **)rootPtr
{
	JSContext *context = OOJSAcquireContext();
	JS_RemoveObjectRoot(context, rootPtr);
	OOJSRelinquishContext(context);
}


- (void) removeGCValueRoot:(jsval *)rootPtr
{
	JSContext *context = OOJSAcquireContext();
	JS_RemoveValueRoot(context, rootPtr);
	OOJSRelinquishContext(context);
}


- (void) garbageCollectionOpportunity
{
	JSContext *context = OOJSAcquireContext();
#ifndef NDEBUG
	JS_GC(context);
#else
	JS_MaybeGC(context);
#endif
	OOJSRelinquishContext(context);
}


- (BOOL) showErrorLocations
{
	return _showErrorLocations;
}


- (void) setShowErrorLocations:(BOOL)value
{
	_showErrorLocations = !!value;
}


- (JSClass *) objectClass
{
	return _objectClass;
}


- (JSClass *) stringClass
{
	return _stringClass;
}


- (JSClass *) arrayClass
{
	return _arrayClass;
}


- (JSClass *) numberClass
{
	return _numberClass;
}


- (JSClass *) booleanClass
{
	return _booleanClass;
}


- (BOOL) lookUpStandardClassPointers
{
	JSObject				*templateObject = NULL;
	
	templateObject = JS_NewObject(gOOJSMainThreadContext, NULL, NULL, NULL);
	if (EXPECT_NOT(templateObject == NULL))  return NO;
	_objectClass = OOJSGetClass(gOOJSMainThreadContext, templateObject);
	
	if (EXPECT_NOT(!JS_ValueToObject(gOOJSMainThreadContext, JS_GetEmptyStringValue(gOOJSMainThreadContext), &templateObject)))  return NO;
	_stringClass = OOJSGetClass(gOOJSMainThreadContext, templateObject);
	
	templateObject = JS_NewArrayObject(gOOJSMainThreadContext, 0, NULL);
	if (EXPECT_NOT(templateObject == NULL))  return NO;
	_arrayClass = OOJSGetClass(gOOJSMainThreadContext, templateObject);
	
	if (EXPECT_NOT(!JS_ValueToObject(gOOJSMainThreadContext, INT_TO_JSVAL(0), &templateObject)))  return NO;
	_numberClass = OOJSGetClass(gOOJSMainThreadContext, templateObject);
	
	if (EXPECT_NOT(!JS_ValueToObject(gOOJSMainThreadContext, JSVAL_FALSE, &templateObject)))  return NO;
	_booleanClass = OOJSGetClass(gOOJSMainThreadContext, templateObject);
	
	return YES;
}


- (void) registerStandardObjectConverters
{
	OOJSRegisterObjectConverter([self objectClass], (OOJSClassConverterCallback)OOJSDictionaryFromJSObject);
	OOJSRegisterObjectConverter([self stringClass], JSStringConverter);
	OOJSRegisterObjectConverter([self arrayClass], JSArrayConverter);
	OOJSRegisterObjectConverter([self numberClass], JSNumberConverter);
	OOJSRegisterObjectConverter([self booleanClass], JSBooleanConverter);
}


#ifndef NDEBUG
static JSTrapStatus DebuggerHook(JSContext *context, JSScript *script, jsbytecode *pc, jsval *rval, void *closure)
{
	OOJSPauseTimeLimiter();
	
	OOLog(@"script.javaScript.debugger", @"debugger invoked during %@:", [[OOJSScript currentlyRunningScript] displayName]);
	OOJSDumpStack(context);
	
	OOJSResumeTimeLimiter();
	
	return JSTRAP_CONTINUE;
}


- (BOOL) dumpStackForErrors
{
	return _dumpStackForErrors;
}


- (void) setDumpStackForErrors:(BOOL)value
{
	_dumpStackForErrors = !!value;
}


- (BOOL) dumpStackForWarnings
{
	return _dumpStackForWarnings;
}


- (void) setDumpStackForWarnings:(BOOL)value
{
	_dumpStackForWarnings = !!value;
}


- (void) enableDebuggerStatement
{
	JS_SetDebuggerHandler(runtime, DebuggerHook, self);
}
#endif

@end


#if OOJSENGINE_MONITOR_SUPPORT

@implementation OOJavaScriptEngine (OOMonitorSupport)

- (void)setMonitor:(id<OOJavaScriptEngineMonitor>)inMonitor
{
	[monitor autorelease];
	monitor = [inMonitor retain];
}

@end


@implementation OOJavaScriptEngine (OOMonitorSupportInternal)

- (void)sendMonitorError:(JSErrorReport *)errorReport
			 withMessage:(NSString *)message
			   inContext:(JSContext *)theContext
{
	if ([monitor respondsToSelector:@selector(jsEngine:context:error:stackSkip:showingLocation:withMessage:)])
	{
		[monitor jsEngine:self context:theContext error:errorReport stackSkip:sErrorHandlerStackSkip showingLocation:[self showErrorLocations] withMessage:message];
	}
}


- (void)sendMonitorLogMessage:(NSString *)message
			 withMessageClass:(NSString *)messageClass
					inContext:(JSContext *)theContext
{
	if ([monitor respondsToSelector:@selector(jsEngine:context:logMessage:ofClass:)])
	{
		[monitor jsEngine:self context:theContext logMessage:message ofClass:messageClass];
	}
}

@end

#endif


#ifndef NDEBUG

static void DumpVariable(JSContext *context, JSPropertyDesc *prop)
{
	NSString *name = OOStringFromJSValueEvenIfNull(context, prop->id);
	NSString *value = OOJSDebugDescribe(context, prop->value);
	
	enum
	{
		kInterestingFlags = ~(JSPD_ENUMERATE | JSPD_PERMANENT | JSPD_VARIABLE | JSPD_ARGUMENT)
	};
	
	NSString *flagStr = @"";
	if ((prop->flags & kInterestingFlags) != 0)
	{
		NSMutableArray *flags = [NSMutableArray array];
		if (prop->flags & JSPD_READONLY)  [flags addObject:@"read-only"];
		if (prop->flags & JSPD_ALIAS)  [flags addObject:[NSString stringWithFormat:@"alias (%@)", OOJSDebugDescribe(context, prop->alias)]];
		if (prop->flags & JSPD_EXCEPTION)  [flags addObject:@"exception"];
		if (prop->flags & JSPD_ERROR)  [flags addObject:@"error"];
		
		flagStr = [NSString stringWithFormat:@" [%@]", [flags componentsJoinedByString:@", "]];
	}
	
	OOLog(@"script.javaScript.stackTrace", @"    %@: %@%@", name, value, flagStr);
}


void OOJSDumpStack(JSContext *context)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	NS_DURING
		JSStackFrame	*frame = NULL;
		unsigned		idx = 0;
		unsigned		skip = sErrorHandlerStackSkip;
		
		while (JS_FrameIterator(context, &frame) != NULL)
		{
			JSScript			*script = JS_GetFrameScript(context, frame);
			NSString			*desc = nil;
			JSPropertyDescArray	properties = { 0 , NULL };
			BOOL				gotProperties = NO;
			
			idx++;
			
#if OO_NEW_JS
			if (!JS_IsScriptFrame(context, frame))
			{
				continue;
			}
#endif
			
			if (skip != 0)
			{
				skip--;
				continue;
			}
			
			if (script != NULL)
			{
				NSString	*location = OOJSDescribeLocation(context, frame);
				JSObject	*scope = JS_GetFrameScopeChain(context, frame);
				
				if (scope != NULL)  gotProperties = JS_GetPropertyDescArray(context, scope, &properties);
				
				NSString *funcDesc = nil;
				JSFunction *function = JS_GetFrameFunction(context, frame);
				if (function != NULL)
				{
					JSString *funcName = JS_GetFunctionId(function);
					if (funcName != NULL)
					{
						funcDesc = OOStringFromJSString(context, funcName);
						if (!JS_IsConstructorFrame(context, frame))
						{
							funcDesc = [funcDesc stringByAppendingString:@"()"];
						}
						else
						{
							funcDesc = [NSString stringWithFormat:@"new %@()", funcDesc];
						}
						
					}
					else
					{
						funcDesc = @"<anonymous function>";
					}
				}
				else
				{
					funcDesc = @"<not a function frame>";
				}
				
				desc = [NSString stringWithFormat:@"(%@) %@", location, funcDesc];
			}
			else if (JS_IsDebuggerFrame(context, frame))
			{
				desc = @"<debugger frame>";
			}
			else
			{
				desc = @"<Oolite native>";
			}
			
			OOLog(@"script.javaScript.stackTrace", @"%2u %@", idx - 1, desc);
			
			if (gotProperties)
			{
				jsval this;
				if (JS_GetFrameThis(context, frame, &this))
				{
					static BOOL haveThis = NO;
					static jsval thisAtom;
					if (EXPECT_NOT(!haveThis))
					{
						thisAtom = STRING_TO_JSVAL(JS_InternString(context, "this"));
						haveThis = YES;
					}
					JSPropertyDesc thisDesc = { .id = thisAtom, .value = this };
					DumpVariable(context, &thisDesc);
				}
				
				// Dump arguments.
				unsigned i;
				for (i = 0; i < properties.length; i++)
				{
					JSPropertyDesc *prop = &properties.array[i];
					if (prop->flags & JSPD_ARGUMENT)  DumpVariable(context, prop);
				}
				
				// Dump locals.
				for (i = 0; i < properties.length; i++)
				{
					JSPropertyDesc *prop = &properties.array[i];
					if (prop->flags & JSPD_VARIABLE)  DumpVariable(context, prop);
				}
				
				// Dump anything else.
				for (i = 0; i < properties.length; i++)
				{
					JSPropertyDesc *prop = &properties.array[i];
					if (!(prop->flags & (JSPD_ARGUMENT | JSPD_VARIABLE)))  DumpVariable(context, prop);
				}
				
				JS_PutPropertyDescArray(context, &properties);
			}
		}
	NS_HANDLER
		OOLog(kOOLogException, @"Exception during JavaScript stack trace: %@:%@", [localException name], [localException reason]);
	NS_ENDHANDLER
	
	[pool release];
}


static const char *sConsoleScriptName;	// Lifetime is lifetime of script object, which is forever.
static OOUInteger sConsoleEvalLineNo;


static void GetLocationNameAndLine(JSContext *context, JSStackFrame *stackFrame, const char **name, OOUInteger *line)
{
	NSCParameterAssert(context != NULL && stackFrame != NULL && name != NULL && line != NULL);
	
	*name = NULL;
	*line = 0;
	
	JSScript *script = JS_GetFrameScript(context, stackFrame);
	if (script != NULL)
	{
		*name = JS_GetScriptFilename(context, script);
		if (name != NULL)
		{
			jsbytecode *PC = JS_GetFramePC(context, stackFrame);
			*line = JS_PCToLineNumber(context, script, PC);
		}
	}
	else if (JS_IsDebuggerFrame(context, stackFrame))
	{
		*name = "<debugger frame>";
	}
}


NSString *OOJSDescribeLocation(JSContext *context, JSStackFrame *stackFrame)
{
	NSCParameterAssert(context != NULL && stackFrame != NULL);
	
	const char	*fileName;
	OOUInteger	lineNo;
	GetLocationNameAndLine(context, stackFrame, &fileName, &lineNo);
	if (fileName == NULL)  return NO;
	
	// If this stops working, we probably need to switch to strcmp().
	if (fileName == sConsoleScriptName && lineNo >= sConsoleEvalLineNo)  return @"<console input>";
	
	// Objectify it.
	NSString	*fileNameObj = [NSString stringWithUTF8String:fileName];
	if (fileNameObj == nil)  fileNameObj = [NSString stringWithCString:fileName encoding:NSISOLatin1StringEncoding];
	if (fileNameObj == nil)  return nil;
	
	NSString	*shortFileName = [fileNameObj lastPathComponent];
	if (![[shortFileName lowercaseString] isEqualToString:@"script.js"])  fileNameObj = shortFileName;
	
	return [NSString stringWithFormat:@"%@:%u", fileNameObj, lineNo];
}


void OOJSMarkConsoleEvalLocation(JSContext *context, JSStackFrame *stackFrame)
{
	GetLocationNameAndLine(context, stackFrame, &sConsoleScriptName, &sConsoleEvalLineNo);
}
#endif


#if OO_NEW_JS
void OOJSInitPropIDCachePRIVATE(const char *name, jsid *idCache, BOOL *inited)
{
	NSCParameterAssert(name != NULL && idCache != NULL && inited != NULL && !*inited);
	
	JSContext *context = OOJSAcquireContext();
	
	JSString *string = JS_InternString(context, name);
	if (EXPECT_NOT(string == NULL))
	{
		[NSException raise:NSGenericException format:@"Failed to initialize JS ID cache for \"%s\".", name];
	}
	
	*idCache = INTERNED_STRING_TO_JSID(string);
	*inited = YES;
	
	OOJSRelinquishContext(context);
}


OOJSPropID OOJSPropIDFromString(NSString *string)
{
	if (EXPECT_NOT(string == nil))  return JSID_VOID;
	
	JSContext *context = OOJSAcquireContext();
	
	enum { kStackBufSize = 1024 };
	unichar stackBuf[kStackBufSize];
	unichar *buffer;
	size_t length = [string length];
	if (length < kStackBufSize)
	{
		buffer = stackBuf;
	}
	else
	{
		buffer = malloc(sizeof (unichar) * length);
		if (EXPECT_NOT(buffer == NULL))  return JSID_VOID;
	}
	[string getCharacters:buffer];
	
	JSString *jsString = JS_InternUCStringN(context, buffer, length);
	if (EXPECT_NOT(jsString == NULL))  return JSID_VOID;
	
	if (EXPECT_NOT(buffer != stackBuf))  free(buffer);
	
	OOJSRelinquishContext(context);
	
	return INTERNED_STRING_TO_JSID(jsString);
}


NSString *OOStringFromJSPropID(OOJSPropID propID)
{
	JSContext *context = OOJSAcquireContext();
	
	jsval		value;
	NSString	*result = nil;
	if (JS_IdToValue(context, propID, &value))
	{
		result = OOStringFromJSString(context, JS_ValueToString(context, value));
	}
	
	OOJSRelinquishContext(context);
	
	return result;
}
#else
OOJSPropID OOJSPropIDFromString(NSString *string)
{
	if (EXPECT_NOT(string == nil))  return NULL;
	
	return [string UTF8String];
}


NSString *OOStringFromJSPropID(OOJSPropID propID)
{
	return [NSString stringWithUTF8String:propID];
}
#endif


static NSString *CallerPrefix(NSString *scriptClass, NSString *function)
{
	if (function == nil)  return @"";
	if (scriptClass == nil)  return [function stringByAppendingString:@": "];
	return  [NSString stringWithFormat:@"%@.%@: ", scriptClass, function];
}


void OOJSReportError(JSContext *context, NSString *format, ...)
{
	va_list					args;
	
	va_start(args, format);
	OOJSReportErrorWithArguments(context, format, args);
	va_end(args);
}


void OOJSReportErrorForCaller(JSContext *context, NSString *scriptClass, NSString *function, NSString *format, ...)
{
	va_list					args;
	NSString				*msg = nil;
	
	NS_DURING
		va_start(args, format);
		msg = [[NSString alloc] initWithFormat:format arguments:args];
		va_end(args);
		
		OOJSReportError(context, @"%@%@", CallerPrefix(scriptClass, function), msg);
	NS_HANDLER
		// Squash any secondary errors during error handling.
	NS_ENDHANDLER
	[msg release];
}


void OOJSReportErrorWithArguments(JSContext *context, NSString *format, va_list args)
{
	NSString				*msg = nil;
	
	NSCParameterAssert(JS_IsInRequest(context));
	
	NS_DURING
		msg = [[NSString alloc] initWithFormat:format arguments:args];
		JS_ReportError(context, "%s", [msg UTF8String]);
	NS_HANDLER
		// Squash any secondary errors during error handling.
	NS_ENDHANDLER
	[msg release];
}


#if OOLITE_NATIVE_EXCEPTIONS

void OOJSReportWrappedException(JSContext *context, id exception)
{
	if (!JS_IsExceptionPending(context))
	{
		if ([exception isKindOfClass:[NSException class]])  OOJSReportError(context, @"Native exception: %@", [exception reason]);
		else  OOJSReportError(context, @"Unidentified native exception");
	}
	// Else, let the pending exception propagate.
}

#endif


#ifndef NDEBUG

void OOJSUnreachable(const char *function, const char *file, unsigned line)
{
	OOLog(@"fatal.unreachable", @"Supposedly unreachable statement reached in %s (%@:%u) -- terminating.", function, OOLogAbbreviatedFileName(file), line);
	abort();
}

#endif


void OOJSReportWarning(JSContext *context, NSString *format, ...)
{
	va_list					args;
	
	va_start(args, format);
	OOJSReportWarningWithArguments(context, format, args);
	va_end(args);
}


void OOJSReportWarningForCaller(JSContext *context, NSString *scriptClass, NSString *function, NSString *format, ...)
{
	va_list					args;
	NSString				*msg = nil;
	
	NS_DURING
		va_start(args, format);
		msg = [[NSString alloc] initWithFormat:format arguments:args];
		va_end(args);
		
		OOJSReportWarning(context, @"%@%@", CallerPrefix(scriptClass, function), msg);
	NS_HANDLER
	// Squash any secondary errors during error handling.
	NS_ENDHANDLER
	[msg release];
}


void OOJSReportWarningWithArguments(JSContext *context, NSString *format, va_list args)
{
	NSString				*msg = nil;
	
	NS_DURING
		msg = [[NSString alloc] initWithFormat:format arguments:args];
		JS_ReportWarning(context, "%s", [msg UTF8String]);
	NS_HANDLER
	// Squash any secondary errors during error handling.
	NS_ENDHANDLER
	[msg release];
}


void OOJSReportBadPropertySelector(JSContext *context, JSObject *thisObj, jsid propID, JSPropertySpec *propertySpec)
{
	NSString	*propName = OOStringFromJSPropertyIDAndSpec(context, propID, propertySpec);
	const char	*className = OOJSGetClass(context, thisObj)->name;
	
	OOJSReportError(context, @"Invalid property identifier %@ for instance of %s.", propName, className);
}


void OOJSReportBadPropertyValue(JSContext *context, JSObject *thisObj, jsid propID, JSPropertySpec *propertySpec, jsval value)
{
	NSString	*propName = OOStringFromJSPropertyIDAndSpec(context, propID, propertySpec);
	const char	*className = OOJSGetClass(context, thisObj)->name;
	NSString	*valueDesc = OOJSDebugDescribe(context, value);
	
	OOJSReportError(context, @"Cannot set property %@ of instance of %s to invalid value %@.", propName, className, valueDesc);
}


void OOJSReportBadArguments(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, NSString *message, NSString *expectedArgsDescription)
{
	NS_DURING
		if (message == nil)  message = @"Invalid arguments";
		message = [NSString stringWithFormat:@"%@ %@", message, [NSString stringWithJavaScriptParameters:argv count:argc inContext:context]];
		if (expectedArgsDescription != nil)  message = [NSString stringWithFormat:@"%@ -- expected %@", message, expectedArgsDescription];
		
		OOJSReportErrorForCaller(context, scriptClass, function, @"%@.", message);
	NS_HANDLER
	// Squash any secondary errors during error handling.
	NS_ENDHANDLER
}


void OOJSSetWarningOrErrorStackSkip(unsigned skip)
{
	sErrorHandlerStackSkip = skip;
}


BOOL OOJSArgumentListGetNumber(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, double *outNumber, uintN *outConsumed)
{
	if (OOJSArgumentListGetNumberNoError(context, argc, argv, outNumber, outConsumed))
	{
		return YES;
	}
	else
	{
		OOJSReportBadArguments(context, scriptClass, function, argc, argv,
									   @"Expected number, got", NULL);
		return NO;
	}
}


BOOL OOJSArgumentListGetNumberNoError(JSContext *context, uintN argc, jsval *argv, double *outNumber, uintN *outConsumed)
{
	OOJS_PROFILE_ENTER
	
	double					value;
	
	NSCParameterAssert(context != NULL && (argv != NULL || argc == 0) && outNumber != NULL);
	
	// Get value, if possible.
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[0], &value) || isnan(value)))
	{
		if (outConsumed != NULL)  *outConsumed = 0;
		return NO;
	}
	
	// Success.
	*outNumber = value;
	if (outConsumed != NULL)  *outConsumed = 1;
	return YES;
	
	OOJS_PROFILE_EXIT
}


static JSObject *JSArrayFromNSArray(JSContext *context, NSArray *array)
{
	OOJS_PROFILE_ENTER
	
	JSObject				*result = NULL;
	unsigned				i;
	unsigned				count;
	jsval					value;
	
	if (array == nil)  return NULL;
	
	NS_DURING
		result = JS_NewArrayObject(context, 0, NULL);
		if (result != NULL)
		{
			count = [array count];
			for (i = 0; i != count; ++i)
			{
				value = [[array objectAtIndex:i] oo_jsValueInContext:context];
				BOOL OK = JS_SetElement(context, result, i, &value);
				
				if (EXPECT_NOT(!OK))
				{
					result = NULL;
					break;
				}
			}
		}
	NS_HANDLER
		result = NULL;
	NS_ENDHANDLER
	
	return (JSObject *)result;
	
	OOJS_PROFILE_EXIT
}


static BOOL JSNewNSArrayValue(JSContext *context, NSArray *array, jsval *value)
{
	OOJS_PROFILE_ENTER
	
	JSObject				*object = NULL;
	BOOL					OK = YES;
	
	if (value == NULL)  return NO;
	
	// NOTE: should be called within a local root scope or have *value be a set root for GC reasons.
	if (!JS_EnterLocalRootScope(context))  return NO;
	
	object = JSArrayFromNSArray(context, array);
	if (object == NULL)
	{
		*value = JSVAL_VOID;
		OK = NO;
	}
	else
	{
		*value = OBJECT_TO_JSVAL(object);
	}
	
	JS_LeaveLocalRootScopeWithResult(context, *value);
	return OK;
	
	OOJS_PROFILE_EXIT
}


/*	Convert an NSDictionary to a JavaScript Object.
	Only properties whose keys are either strings or non-negative NSNumbers,
	and	whose values have a non-void JS representation, are converted.
*/
static JSObject *JSObjectFromNSDictionary(JSContext *context, NSDictionary *dictionary)
{
	OOJS_PROFILE_ENTER
	
	JSObject				*result = NULL;
	BOOL					OK = YES;
	NSEnumerator			*keyEnum = nil;
	id						key = nil;
	jsval					value;
	jsint					index;
	
	if (dictionary == nil)  return NULL;
	
	NS_DURING
		result = JS_NewObject(context, NULL, NULL, NULL);	// create object of class Object
		if (result != NULL)
		{
			for (keyEnum = [dictionary keyEnumerator]; (key = [keyEnum nextObject]); )
			{
				if ([key isKindOfClass:[NSString class]] && [key length] != 0)
				{
					value = [[dictionary objectForKey:key] oo_jsValueInContext:context];
					if (!JSVAL_IS_VOID(value))
					{
						OK = JS_SetPropertyById(context, result, OOJSPropIDFromString(key), &value);
						if (EXPECT_NOT(!OK))  break;
					}
				}
				else if ([key isKindOfClass:[NSNumber class]])
				{
					index = [key intValue];
					if (0 < index)
					{
						value = [[dictionary objectForKey:key] oo_jsValueInContext:context];
						if (!JSVAL_IS_VOID(value))
						{
							OK = JS_SetElement(context, (JSObject *)result, index, &value);
							if (EXPECT_NOT(!OK))  break;
						}
					}
				}
				
				if (EXPECT_NOT(!OK))  break;
			}
		}
	NS_HANDLER
		OK = NO;
	NS_ENDHANDLER
	
	if (EXPECT_NOT(!OK))
	{
		result = NULL;
	}
	
	return (JSObject *)result;
	
	OOJS_PROFILE_EXIT
}


static BOOL JSNewNSDictionaryValue(JSContext *context, NSDictionary *dictionary, jsval *value)
{
	OOJS_PROFILE_ENTER
	
	JSObject				*object = NULL;
	BOOL					OK = YES;
	
	if (value == NULL)  return NO;
	
	// NOTE: should be called within a local root scope or have *value be a set root for GC reasons.
	if (!JS_EnterLocalRootScope(context))  return NO;
	
	object = JSObjectFromNSDictionary(context, dictionary);
	if (object == NULL)
	{
		*value = JSVAL_VOID;
		OK = NO;
	}
	else
	{
		*value = OBJECT_TO_JSVAL(object);
	}
	
	JS_LeaveLocalRootScopeWithResult(context, *value);
	return OK;
	
	OOJS_PROFILE_EXIT
}


@implementation NSObject (OOJavaScriptConversion)

- (jsval) oo_jsValueInContext:(JSContext *)context
{
	return JSVAL_VOID;
}


- (NSString *) oo_jsClassName
{
	return nil;
}


- (NSString *) oo_jsDescription
{
	return [self oo_jsDescriptionWithClassName:[self oo_jsClassName]];
}


- (NSString *) oo_jsDescriptionWithClassName:(NSString *)className
{
	OOJS_PROFILE_ENTER
	
	NSString				*components = nil;
	NSString				*description = nil;
	
	components = [self descriptionComponents];
	if (className == nil)  className = [[self class] description];
	
	if (components != nil)
	{
		description = [NSString stringWithFormat:@"[%@ %@]", className, components];
	}
	else
	{
		description = [NSString stringWithFormat:@"[object %@]", className];
	}
	
	return description;
	
	OOJS_PROFILE_EXIT
}


- (void) oo_clearJSSelf:(JSObject *)selfVal
{
	
}

@end


@implementation OOJSValue

+ (id) valueWithJSValue:(jsval)value inContext:(JSContext *)context
{
	OOJS_PROFILE_ENTER
	
	return [[[self alloc] initWithJSValue:value inContext:context] autorelease];
	
	OOJS_PROFILE_EXIT
}


+ (id) valueWithJSObject:(JSObject *)object inContext:(JSContext *)context
{
	OOJS_PROFILE_ENTER
	
	return [[[self alloc] initWithJSObject:object inContext:context] autorelease];
	
	OOJS_PROFILE_EXIT
}


- (id) initWithJSValue:(jsval)value inContext:(JSContext *)context
{
	OOJS_PROFILE_ENTER
	
	self = [super init];
	if (self != nil)
	{
		BOOL tempCtxt = NO;
		if (context == NULL)
		{
			context = OOJSAcquireContext();
			tempCtxt = YES;
		}
		
		_val = value;
		JS_AddNamedValueRoot(context, &_val, "OOJSValue");
		
		if (tempCtxt)  OOJSRelinquishContext(context);
	}
	return self;
	
	OOJS_PROFILE_EXIT
}


- (id) initWithJSObject:(JSObject *)object inContext:(JSContext *)context
{
	return [self initWithJSValue:OBJECT_TO_JSVAL(object) inContext:context];
}


- (void) dealloc
{
	JSContext *context = OOJSAcquireContext();
	JS_RemoveValueRoot(context, &_val);
	OOJSRelinquishContext(context);
	
	[super dealloc];
}


- (jsval) oo_jsValueInContext:(JSContext *)context
{
	return _val;
}

@end


void OOJSStrLiteralCachePRIVATE(const char *string, jsval *strCache, BOOL *inited)
{
	NSCParameterAssert(string != NULL && strCache != NULL && inited != NULL && !*inited);
	
	JSContext *context = OOJSAcquireContext();
	
	JSString *jsString = JS_InternString(context, string);
	if (EXPECT_NOT(string == NULL))
	{
		[NSException raise:NSGenericException format:@"Failed to initialize JavaScript string literal cache for \"%@\".", [[NSString stringWithUTF8String:string] escapedForJavaScriptLiteral]];
	}
	
	*strCache = STRING_TO_JSVAL(jsString);
	*inited = YES;
	
	OOJSRelinquishContext(context);
}


NSString *OOStringFromJSString(JSContext *context, JSString *string)
{
	OOJS_PROFILE_ENTER
	
	if (EXPECT_NOT(string == NULL))  return nil;
	
	size_t length;
	const jschar *chars = JS_GetStringCharsAndLength(context, string, &length);
	
	if (EXPECT(chars != NULL))
	{
		return [NSString stringWithCharacters:chars length:length];
	}
	else
	{
		return nil;
	}

	OOJS_PROFILE_EXIT
}


NSString *OOStringFromJSValueEvenIfNull(JSContext *context, jsval value)
{
	OOJS_PROFILE_ENTER
	
	NSCParameterAssert(context != NULL && JS_IsInRequest(context));
	
	JSString *string = JS_ValueToString(context, value);	// Calls the value's toString method if needed.
	return OOStringFromJSString(context, string);
	
	OOJS_PROFILE_EXIT
}


NSString *OOStringFromJSValue(JSContext *context, jsval value)
{
	OOJS_PROFILE_ENTER
	
	if (EXPECT(!JSVAL_IS_NULL(value) && !JSVAL_IS_VOID(value)))
	{
		return OOStringFromJSValueEvenIfNull(context, value);
	}
	return nil;
	
	OOJS_PROFILE_EXIT
}


#if OO_NEW_JS
NSString *OOStringFromJSPropertyIDAndSpec(JSContext *context, jsid propID, JSPropertySpec *propertySpec)
#else
NSString *OOStringFromJSPropertyIDAndSpec(JSContext *context, jsval propID, JSPropertySpec *propertySpec)
#endif
{
	if (JSID_IS_STRING(propID))
	{
		return OOStringFromJSString(context, JSID_TO_STRING(propID));
	}
	else if (JSID_IS_INT(propID) && propertySpec != NULL)
	{
		int tinyid = JSID_TO_INT(propID);
		
		while (propertySpec->name != NULL)
		{
			if (propertySpec->tinyid == tinyid)  return [NSString stringWithUTF8String:propertySpec->name];
			propertySpec++;
		}
	}
	
	jsval value;
#if OO_NEW_JS
	if (!JS_IdToValue(context, propID, &value))  return @"unknown";
#else
	value = propID;
#endif
	
	return OOStringFromJSString(context, JS_ValueToString(context, value));
}


NSString *OOJSDebugDescribe(JSContext *context, jsval value)
{
	OOJS_PROFILE_ENTER
	
	NSCParameterAssert(context != NULL && JS_IsInRequest(context));
	
	if (OOJSValueIsFunction(context, value))
	{
		JSString *name = JS_GetFunctionId(JS_ValueToFunction(context, value));
		if (name != NULL)  return [NSString stringWithFormat:@"function %@", OOStringFromJSString(context, name)];
		else  return @"function";
	}
	
	NSString *result;
	if (JSVAL_IS_STRING(value))
	{
		enum { kMaxLength = 200 };
		
		JSString *string = JSVAL_TO_STRING(value);
		size_t length;
		const jschar *chars = JS_GetStringCharsAndLength(context, string, &length);
		
		result = [NSString stringWithCharacters:chars length:MIN(length, (size_t)kMaxLength)];
		result = [NSString stringWithFormat:@"\"%@%@\"", [result escapedForJavaScriptLiteral], (length > kMaxLength) ? @"..." : @""];
	}
	else
	{
		result = OOStringFromJSValueEvenIfNull(context, value);
	}
	
	return result;
	
	OOJS_PROFILE_EXIT
}


@implementation NSString (OOJavaScriptExtensions)

+ (id) stringOrNilWithJavaScriptValue:(jsval)value inContext:(JSContext *)context
{
	return OOStringFromJSValue(context, value);
}


+ (id) stringWithJavaScriptValue:(jsval)value inContext:(JSContext *)context
{
	return OOStringFromJSValueEvenIfNull(context, value);
}


+ (id) stringWithJavaScriptParameters:(jsval *)params count:(uintN)count inContext:(JSContext *)context
{
	OOJS_PROFILE_ENTER
	
	if (params == NULL && count != 0) return nil;
	
	uintN					i;
	jsval					val;
	NSMutableString			*result = [NSMutableString stringWithString:@"("];
	NSString				*valString = nil;
	
	for (i = 0; i < count; ++i)
	{
		if (i != 0)  [result appendString:@", "];
		
		val = params[i];
		valString = [self stringWithJavaScriptValue:val inContext:context];
		if (JSVAL_IS_STRING(val))
		{
			[result appendFormat:@"\"%@\"", valString];
		}
		else if (OOJSValueIsArray(context, val))
		{
			[result appendFormat:@"[%@]", valString];
		}
		else
		{
			[result appendString:valString]; //crash if valString is nil
		}
	}
	
	[result appendString:@")"];
	return result;
	
	OOJS_PROFILE_EXIT
}


- (jsval) oo_jsValueInContext:(JSContext *)context
{
	OOJS_PROFILE_ENTER
	
	size_t					length = [self length];
	unichar					*buffer = NULL;
	JSString				*string = NULL;
	
	if (length == 0)
	{
		jsval result = JS_GetEmptyStringValue(context);
		return result;
	}
	else
	{
		buffer = malloc(length * sizeof *buffer);
		if (buffer == NULL) return JSVAL_VOID;
		
		[self getCharacters:buffer];
		
		string = JS_NewUCStringCopyN(context, buffer, length);
		
		free(buffer);
		return STRING_TO_JSVAL(string);
	}
	
	OOJS_PROFILE_EXIT_JSVAL
}


+ (id) concatenationOfStringsFromJavaScriptValues:(jsval *)values count:(size_t)count separator:(NSString *)separator inContext:(JSContext *)context
{
	OOJS_PROFILE_ENTER
	
	size_t					i;
	NSMutableString			*result = nil;
	NSString				*element = nil;
	
	if (count < 1) return nil;
	if (values == NULL) return NULL;
	
	for (i = 0; i != count; ++i)
	{
		element = [NSString stringWithJavaScriptValue:values[i] inContext:context];
		if (result == nil)  result = [[element mutableCopy] autorelease];
		else
		{
			if (separator != nil)  [result appendString:separator];
			[result appendString:element];
		}
	}
	
	return result;
	
	OOJS_PROFILE_EXIT
}


- (NSString *)escapedForJavaScriptLiteral
{
	OOJS_PROFILE_ENTER
	
	NSMutableString			*result = nil;
	unsigned				i, length;
	unichar					c;
	NSAutoreleasePool		*pool = nil;
	
	length = [self length];
	result = [NSMutableString stringWithCapacity:[self length]];
	
	// Not hugely efficient.
	pool = [[NSAutoreleasePool alloc] init];
	for (i = 0; i != length; ++i)
	{
		c = [self characterAtIndex:i];
		switch (c)
		{
			case '\\':
				[result appendString:@"\\\\"];
				break;
				
			case '\b':
				[result appendString:@"\\b"];
				break;
				
			case '\f':
				[result appendString:@"\\f"];
				break;
				
			case '\n':
				[result appendString:@"\\n"];
				break;
				
			case '\r':
				[result appendString:@"\\r"];
				break;
				
			case '\t':
				[result appendString:@"\\t"];
				break;
				
			case '\v':
				[result appendString:@"\\v"];
				break;
				
			case '\'':
				[result appendString:@"\\\'"];
				break;
				
			case '\"':
				[result appendString:@"\\\""];
				break;
			
			default:
				[result appendString:[NSString stringWithCharacters:&c length:1]];
		}
	}
	[pool release];
	return result;
	
	OOJS_PROFILE_EXIT
}


- (NSString *) oo_jsClassName
{
	return @"String";
}

@end


@implementation NSArray (OOJavaScriptConversion)

- (jsval)oo_jsValueInContext:(JSContext *)context
{
	jsval value = JSVAL_VOID;
	JSNewNSArrayValue(context, self, &value);
	return value;
}

@end


@implementation NSDictionary (OOJavaScriptConversion)

- (jsval)oo_jsValueInContext:(JSContext *)context
{
	jsval value = JSVAL_VOID;
	JSNewNSDictionaryValue(context, self, &value);
	return value;
}

@end


@implementation NSNumber (OOJavaScriptConversion)

- (jsval)oo_jsValueInContext:(JSContext *)context
{
	OOJS_PROFILE_ENTER
	
	jsval					result;
	BOOL					isFloat = NO;
	long long				longLongValue;
	
#if 0
	/*	Under GNUstep, it is not possible to distinguish between boolean
		NSNumbers and integer NSNumbers - there is no such distinction.
		It is better to convert booleans to integers than vice versa.
	*/
	if ([self oo_isBoolean])
	{
		if ([self boolValue])  result = JSVAL_TRUE;
		else  result = JSVAL_FALSE;
	}
	else
#endif
	{
		isFloat = [self oo_isFloatingPointNumber];
		if (!isFloat)
		{
			longLongValue = [self longLongValue];
			if (longLongValue < (long long)JSVAL_INT_MIN || (long long)JSVAL_INT_MAX < longLongValue)
			{
				// values outside JSVAL_INT range are returned as doubles.
				isFloat = YES;
			}
		}
		
		if (isFloat)
		{
			if (!JS_NewDoubleValue(context, [self doubleValue], &result)) result = JSVAL_VOID;
		}
		else
		{
			result = INT_TO_JSVAL(longLongValue);
		}
	}
	
	return result;
	
	OOJS_PROFILE_EXIT_JSVAL
}


- (NSString *) oo_jsClassName
{
	return @"Number";
}

@end


@implementation NSNull (OOJavaScriptConversion)

- (jsval)oo_jsValueInContext:(JSContext *)context
{
	return JSVAL_NULL;
}

@end


JSBool OOJSUnconstructableConstruct(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	JSFunction *function = JS_ValueToFunction(context, JS_CALLEE(context, vp));
	NSString *name = OOStringFromJSString(context, JS_GetFunctionId(function));
	
	OOJSReportError(context, @"%@ cannot be used as a constructor.", name);
	return NO;
	
	OOJS_NATIVE_EXIT
}


void OOJSObjectWrapperFinalize(JSContext *context, JSObject *this)
{
	OOJS_PROFILE_ENTER
	
	id object = JS_GetPrivate(context, this);
	if (object != nil)
	{
		[[object weakRefUnderlyingObject] oo_clearJSSelf:this];
		[object release];
		JS_SetPrivate(context, this, nil);
	}
	
	OOJS_PROFILE_EXIT_VOID
}


JSBool OOJSObjectWrapperToString(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	id						object = nil;
	NSString				*description = nil;
	JSClass					*jsClass = NULL;
	
	object = OOJSNativeObjectFromJSObject(context, OOJS_THIS);
	if (object != nil)
	{
		description = [object oo_jsDescription];
		if (description == nil)  description = [object description];
	}
	if (description == nil)
	{
		jsClass = OOJSGetClass(context, OOJS_THIS);
		if (jsClass != NULL)
		{
			description = [NSString stringWithFormat:@"[object %@]", [NSString stringWithUTF8String:jsClass->name]];
		}
	}
	if (description == nil)  description = @"[object]";
	
	OOJS_RETURN_OBJECT(description);
	
	OOJS_NATIVE_EXIT
}


BOOL JSFunctionPredicate(Entity *entity, void *parameter)
{
	OOJS_PROFILE_ENTER
	
	JSFunctionPredicateParameter	*param = parameter;
	jsval							args[1];
	jsval							rval = JSVAL_VOID;
	JSBool							result = NO;
	
	NSCParameterAssert(entity != NULL && param != NULL);
	NSCParameterAssert(param->context != NULL && JS_IsInRequest(param->context));
	NSCParameterAssert(OOJSValueIsFunction(param->context, param->function));
	
	if (EXPECT_NOT(param->errorFlag))  return NO;
	
	args[0] = [entity oo_jsValueInContext:param->context];
	
	OOJSStartTimeLimiter();
	OOJSResumeTimeLimiter();
	BOOL success = JS_CallFunctionValue(param->context, param->jsThis, param->function, 1, args, &rval);
	OOJSPauseTimeLimiter();
	OOJSStopTimeLimiter();
	
	if (success)
	{
		if (!JS_ValueToBoolean(param->context, rval, &result))  result = NO;
		if (JS_IsExceptionPending(param->context))
		{
			JS_ReportPendingException(param->context);
			param->errorFlag = YES;
		}
	}
	else
	{
		param->errorFlag = YES;
	}
	
	return result;
	
	OOJS_PROFILE_EXIT
}


BOOL JSEntityIsJavaScriptVisiblePredicate(Entity *entity, void *parameter)
{
	OOJS_PROFILE_ENTER
	
	return [entity isVisibleToScripts];
	
	OOJS_PROFILE_EXIT
}


BOOL JSEntityIsJavaScriptSearchablePredicate(Entity *entity, void *parameter)
{
	OOJS_PROFILE_ENTER
	
	if (![entity isVisibleToScripts])  return NO;
	if ([entity isShip])
	{
		if ([entity isSubEntity])  return NO;
		if ([entity status] == STATUS_COCKPIT_DISPLAY)  return NO;	// Demo ship
		return YES;
	}
	else if ([entity isPlanet])
	{
		switch ([(OOPlanetEntity *)entity planetType])
		{
			case STELLAR_TYPE_MOON:
			case STELLAR_TYPE_NORMAL_PLANET:
			case STELLAR_TYPE_SUN:
				return YES;
				
#if !NEW_PLANETS
			case STELLAR_TYPE_ATMOSPHERE:
#endif
			case STELLAR_TYPE_MINIATURE:
				return NO;
		}
	}
	
	return YES;	// would happen if we added a new script-visible class
	
	OOJS_PROFILE_EXIT
}


static NSMapTable *sRegisteredSubClasses;

void OOJSRegisterSubclass(JSClass *subclass, JSClass *superclass)
{
	NSCParameterAssert(subclass != NULL && superclass != NULL);
	
	if (sRegisteredSubClasses == NULL)
	{
		sRegisteredSubClasses = NSCreateMapTable(NSNonOwnedPointerMapKeyCallBacks, NSNonOwnedPointerMapValueCallBacks, 0);
	}
	
	NSCAssert(NSMapGet(sRegisteredSubClasses, subclass) == NULL, @"A JS class cannot be registered as a subclass of multiple classes.");
	
	NSMapInsertKnownAbsent(sRegisteredSubClasses, subclass, superclass);
}


BOOL OOJSIsSubclass(JSClass *putativeSubclass, JSClass *superclass)
{
	NSCParameterAssert(putativeSubclass != NULL && superclass != NULL);
	NSCAssert(sRegisteredSubClasses != NULL, @"OOJSIsSubclass() called before any subclasses registered (disallowed for hot path efficiency).");
	
	do
	{
		if (putativeSubclass == superclass)  return YES;
		
		putativeSubclass = NSMapGet(sRegisteredSubClasses, putativeSubclass);
	}
	while (putativeSubclass != NULL);
	
	return NO;
}


BOOL OOJSObjectGetterImplPRIVATE(JSContext *context, JSObject *object, JSClass *requiredJSClass,
#ifndef NDEBUG
	Class requiredObjCClass, const char *name,
#endif
	id *outObject)
{
#ifndef NDEBUG
	OOJS_PROFILE_ENTER_NAMED(name)
	NSCParameterAssert(requiredObjCClass != Nil);
	NSCParameterAssert(context != NULL && object != NULL && requiredJSClass != NULL && outObject != NULL);
#else
	OOJS_PROFILE_ENTER
#endif
	
	/*
		Ensure it's a valid type of JS object. This is absolutely necessary,
		because if we don't check it we'll crash trying to get the private
		field of something that isn't an ObjC object wrapper - for example,
		Ship.setAI.call(new Vector3D, "") is valid JavaScript.
		
		Alternatively, we could abuse JSCLASS_PRIVATE_IS_NSISUPPORTS as a
		flag for ObjC object wrappers (SpiderMonkey only uses it internally
		in a debug function we don't use), but we'd still need to do an
		Objective-C class test, and I don't think that's any faster.
		TODO: profile.
	*/
	JSClass *actualClass = OOJSGetClass(context, object);
	if (EXPECT_NOT(!OOJSIsSubclass(actualClass, requiredJSClass)))
	{
		OOJSReportError(context, @"Native method expected %s, got %@.", requiredJSClass->name, OOStringFromJSValue(context, OBJECT_TO_JSVAL(object)));
		return NO;
	}
	NSCAssert(actualClass->flags & JSCLASS_HAS_PRIVATE, @"Native object accessor requires JS class with private storage.");
	
	// Get the underlying object.
	*outObject = [(id)JS_GetPrivate(context, object) weakRefUnderlyingObject];
	
#ifndef NDEBUG
	// Double-check that the underlying object is of the expected ObjC class.
	if (EXPECT_NOT(*outObject != nil && ![*outObject isKindOfClass:requiredObjCClass]))
	{
		OOJSReportError(context, @"Native method expected %@ from %s and got correct JS type but incorrect native object %@", requiredObjCClass, requiredJSClass->name, *outObject);
		return NO;
	}
#endif
	
	return YES;
	
	OOJS_PROFILE_EXIT
}


NSDictionary *OOJSDictionaryFromJSValue(JSContext *context, jsval value)
{
	OOJS_PROFILE_ENTER
	
	JSObject *object = NULL;
	if (EXPECT_NOT(!JS_ValueToObject(context, value, &object) || object == NULL))
	{
		return nil;
	}
	return OOJSDictionaryFromJSObject(context, object);
	
	OOJS_PROFILE_EXIT
}


NSDictionary *OOJSDictionaryFromJSObject(JSContext *context, JSObject *object)
{
	OOJS_PROFILE_ENTER
	
	JSIdArray					*ids = NULL;
	jsint						i;
	NSMutableDictionary			*result = nil;
	jsval						value = JSVAL_VOID;
	id							objKey = nil;
	id							objValue = nil;
	
	ids = JS_Enumerate(context, object);
	if (EXPECT_NOT(ids == NULL))
	{
		return nil;
	}
	
	result = [NSMutableDictionary dictionaryWithCapacity:ids->length];
	for (i = 0; i != ids->length; ++i)
	{
		jsid thisID = ids->vector[i];
		
#if OO_NEW_JS
		if (JSID_IS_STRING(thisID))
		{
			objKey = OOStringFromJSString(context, JSID_TO_STRING(thisID));
		}
		else if (JSID_IS_INT(thisID))
		{
			objKey = [NSNumber numberWithInt:JSID_TO_INT(thisID)];
		}
		else
		{
			objKey = nil;
		}
		
		value = JSVAL_VOID;
		if (objKey != nil && !JS_LookupPropertyById(context, object, thisID, &value))  value = JSVAL_VOID;
#else
		jsval propKey = value = JSVAL_VOID;
		objKey = nil;
		
		if (JS_IdToValue(context, thisID, &propKey))
		{
			// Properties with string keys.
			if (JSVAL_IS_STRING(propKey))
			{
				JSString *stringKey = JSVAL_TO_STRING(propKey);
				if (JS_LookupProperty(context, object, JS_GetStringBytes(stringKey), &value))
				{
					objKey = OOStringFromJSString(context, stringKey);
				}
			}
			
			// Properties with int keys.
			else if (JSVAL_IS_INT(propKey))
			{
				jsint intKey = JSVAL_TO_INT(propKey);
				if (JS_GetElement(context, object, intKey, &value))
				{
					objKey = [NSNumber numberWithInt:intKey];
				}
			}
		}
#endif
		
		if (objKey != nil && !JSVAL_IS_VOID(value))
		{
			objValue = OOJSNativeObjectFromJSValue(context, value);
			if (objValue != nil)
			{
				[result setObject:objValue forKey:objKey];
			}
		}
	}
	
	JS_DestroyIdArray(context, ids);
	return result;
	
	OOJS_PROFILE_EXIT
}


NSDictionary *OOJSDictionaryFromStringTable(JSContext *context, jsval tableValue)
{
	OOJS_PROFILE_ENTER
	
	JSObject					*tableObject = NULL;
	JSIdArray					*ids;
	jsint						i;
	NSMutableDictionary			*result = nil;
	jsval						value = JSVAL_VOID;
	id							objKey = nil;
	id							objValue = nil;
	
	if (EXPECT_NOT(!JS_ValueToObject(context, tableValue, &tableObject)))
	{
		return nil;
	}
	
	ids = JS_Enumerate(context, tableObject);
	if (EXPECT_NOT(ids == NULL))
	{
		return nil;
	}
	
	result = [NSMutableDictionary dictionaryWithCapacity:ids->length];
	for (i = 0; i != ids->length; ++i)
	{
		jsid thisID = ids->vector[i];
		
#if OO_NEW_JS
		if (JSID_IS_STRING(thisID))
		{
			objKey = OOStringFromJSString(context, JSID_TO_STRING(thisID));
		}
		else
		{
			objKey = nil;
		}
		
		value = JSVAL_VOID;
		if (objKey != nil && !JS_LookupPropertyById(context, tableObject, thisID, &value))  value = JSVAL_VOID;
#else
		jsval propKey = value = JSVAL_VOID;
		objKey = nil;
		
		if (JS_IdToValue(context, thisID, &propKey))
		{
			// Properties with string keys.
			if (JSVAL_IS_STRING(propKey))
			{
				JSString *stringKey = JSVAL_TO_STRING(propKey);
				if (JS_LookupProperty(context, tableObject, JS_GetStringBytes(stringKey), &value))
				{
					objKey = OOStringFromJSString(context, stringKey);
				}
			}
		}
#endif
		
		if (objKey != nil && !JSVAL_IS_VOID(value))
		{
			// Note: we want nulls and undefines included, so not OOStringFromJSValue().
			objValue = [NSString stringWithJavaScriptValue:value inContext:context];
			
			if (objValue != nil)
			{
				[result setObject:objValue forKey:objKey];
			}
		}
	}
	
	JS_DestroyIdArray(context, ids);
	return result;
	
	OOJS_PROFILE_EXIT
}


static NSMutableDictionary *sObjectConverters;


id OOJSNativeObjectFromJSValue(JSContext *context, jsval value)
{
	OOJS_PROFILE_ENTER
	
	if (JSVAL_IS_NULL(value) || JSVAL_IS_VOID(value))  return nil;
	
	if (JSVAL_IS_INT(value))
	{
		return [NSNumber numberWithInt:JSVAL_TO_INT(value)];
	}
	if (JSVAL_IS_DOUBLE(value))
	{
		return [NSNumber numberWithDouble:JSVAL_TO_DOUBLE(value)];
	}
	if (JSVAL_IS_BOOLEAN(value))
	{
		return [NSNumber numberWithBool:JSVAL_TO_BOOLEAN(value)];
	}
	if (JSVAL_IS_STRING(value))
	{
		return OOStringFromJSValue(context, value);
	}
	if (JSVAL_IS_OBJECT(value))
	{
		return OOJSNativeObjectFromJSObject(context, JSVAL_TO_OBJECT(value));
	}
	return nil;
	
	OOJS_PROFILE_EXIT
}


id OOJSNativeObjectFromJSObject(JSContext *context, JSObject *tableObject)
{
	OOJS_PROFILE_ENTER
	
	NSValue					*wrappedClass = nil;
	NSValue					*wrappedConverter = nil;
	OOJSClassConverterCallback converter = NULL;
	JSClass					*class = NULL;
	
	if (tableObject == NULL)  return nil;
	
	class = OOJSGetClass(context, tableObject);
	wrappedClass = [NSValue valueWithPointer:class];
	if (wrappedClass != nil)  wrappedConverter = [sObjectConverters objectForKey:wrappedClass];
	if (wrappedConverter != nil)
	{
		converter = [wrappedConverter pointerValue];
		return converter(context, tableObject);
	}
	return nil;
	
	OOJS_PROFILE_EXIT
}


id OOJSNativeObjectOfClassFromJSValue(JSContext *context, jsval value, Class requiredClass)
{
	id result = OOJSNativeObjectFromJSValue(context, value);
	if (![result isKindOfClass:requiredClass])  result = nil;
	return result;
}


id OOJSNativeObjectOfClassFromJSObject(JSContext *context, JSObject *object, Class requiredClass)
{
	id result = OOJSNativeObjectFromJSObject(context, object);
	if (![result isKindOfClass:requiredClass])  result = nil;
	return result;
}


id OOJSBasicPrivateObjectConverter(JSContext *context, JSObject *object)
{
	id						result;
	
	/*	This will do the right thing - for non-OOWeakReferences,
		weakRefUnderlyingObject returns the object itself. For nil, of course,
		it returns nil.
	*/
	result = JS_GetPrivate(context, object);
	return [result weakRefUnderlyingObject];
}


void OOJSRegisterObjectConverter(JSClass *theClass, OOJSClassConverterCallback converter)
{
	NSValue					*wrappedClass = nil;
	NSValue					*wrappedConverter = nil;
	
	if (theClass == NULL)  return;
	if (sObjectConverters == nil)  sObjectConverters = [[NSMutableDictionary alloc] init];
	
	wrappedClass = [NSValue valueWithPointer:theClass];
	if (converter != NULL)
	{
		wrappedConverter = [NSValue valueWithPointer:converter];
		[sObjectConverters setObject:wrappedConverter forKey:wrappedClass];
	}
	else
	{
		[sObjectConverters removeObjectForKey:wrappedClass];
	}
}


static id JSArrayConverter(JSContext *context, JSObject *array)
{
	jsuint						i, count;
	id							*values = NULL;
	jsval						value = JSVAL_VOID;
	id							object = nil;
	NSArray						*result = nil;
	
	// Convert a JS array to an NSArray by calling OOJSNativeObjectFromJSValue() on all its elements.
	if (!JS_IsArrayObject(context, array)) return nil;
	if (!JS_GetArrayLength(context, array, &count)) return nil;
	
	if (count == 0)  return [NSArray array];
	
	values = calloc(count, sizeof *values);
	if (values == NULL)  return nil;
	
	for (i = 0; i != count; ++i)
	{
		value = JSVAL_VOID;
		if (!JS_GetElement(context, array, i, &value))  value = JSVAL_VOID;
		
		object = OOJSNativeObjectFromJSValue(context, value);
		if (object == nil)  object = [NSNull null];
		values[i] = object;
	}
	
	result = [NSArray arrayWithObjects:values count:count];
	free(values);
	return result;
}


static id JSStringConverter(JSContext *context, JSObject *object)
{
	return [NSString stringOrNilWithJavaScriptValue:OBJECT_TO_JSVAL(object) inContext:context];
}


static id JSNumberConverter(JSContext *context, JSObject *object)
{
	jsdouble value;
	if (JS_ValueToNumber(context, OBJECT_TO_JSVAL(object), &value))
	{
		return [NSNumber numberWithDouble:value];
	}
	return nil;
}


static id JSBooleanConverter(JSContext *context, JSObject *object)
{
	/*	Fun With JavaScript: Boolean(false) is a truthy value, since it's a
		non-null object. JS_ValueToBoolean() therefore reports true.
		However, Boolean objects are transformed to numbers sanely, so this
		works.
	*/
	jsdouble value;
	if (JS_ValueToNumber(context, OBJECT_TO_JSVAL(object), &value))
	{
		return [NSNumber numberWithBool:(value != 0)];
	}
	return nil;
}
