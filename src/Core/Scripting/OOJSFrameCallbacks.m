/*

OOJSFrameCallbacks.m


Copyright (C) 2011 Jens Ayton

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

#import "OOJSFrameCallbacks.h"
#import "OOCollectionExtractors.h"


/*
	By default, tracking IDs are scrambled to discourage people from trying to
	be clever or making assumptions about them. If DEBUG_FCB_SIMPLE_TRACKING_IDS
	is non-zero, tracking IDs starting from 1 and rising monotonously are used
	instead. Additionally, the next ID is reset to 1 when all frame callbacks
	are removed.
*/
#ifndef DEBUG_FCB_SIMPLE_TRACKING_IDS
#define DEBUG_FCB_SIMPLE_TRACKING_IDS	0
#endif

#ifndef DEBUG_FCB_VERBOSE_LOGGING
#define DEBUG_FCB_VERBOSE_LOGGING		0
#endif



#if defined (NDEBUG) && DEBUG_FCB_SIMPLE_TRACKING_IDS
#error Deployment builds may not be built with DEBUG_FCB_SIMPLE_TRACKING_IDS.
#endif

#if DEBUG_FCB_VERBOSE_LOGGING
#define FCBLog					OOLog
#define FCBLogIndentIf			OOLogIndentIf
#define FCBLogOutdentIf			OOLogOutdentIf
#else
#define FCBLog(...)				do {} while (0)
#define FCBLogIndentIf(key)		do {} while (0)
#define FCBLogOutdentIf(key)	do {} while (0)
#endif


enum
{
	kMinCount					= 16,
	
#if DEBUG_FCB_SIMPLE_TRACKING_IDS
	kIDScrambleMask				= 0
#else
	kIDScrambleMask				= 0x2315EB16	// Just a random number.
#endif
};


typedef struct
{
	jsval					callback;
	uint32					trackingID;
	uint32					_padding;
} CallbackEntry;


static CallbackEntry	*sCallbacks;
static OOUInteger		sCount;			// Number of slots in use.
static OOUInteger		sSpace;			// Number of slots allocated.
static OOUInteger		sHighWaterMark;	// Number of slots which are GC roots.
static NSMutableArray	*sDeferredOps;	// Deferred adds/removes while running.
static uint32			sNextID;
static BOOL				sRunning;


// Methods
static JSBool GlobalAddFrameCallback(OOJS_NATIVE_ARGS);
static JSBool GlobalRemoveFrameCallback(OOJS_NATIVE_ARGS);
static JSBool GlobalIsValidFrameCallback(OOJS_NATIVE_ARGS);


// Internals
static BOOL AddCallback(JSContext *context, jsval callback, uint32 trackingID, NSString **errorString);
static BOOL GrowCallbackList(JSContext *context, NSString **errorString);

OOINLINE void IncrementTrackingID(void);

static BOOL GetIndexForTrackingID(uint32 trackingID, OOUInteger *outIndex);

static BOOL RemoveCallbackWithTrackingID(JSContext *context, uint32 trackingID);
static void RemoveCallbackAtIndex(JSContext *context, OOUInteger index);

static void QueueDeferredOperation(NSString *opType, uint32 trackingID, OOJSValue *value);
static void RunDeferredOperations(JSContext *context);


// MARK: Public

void InitOOJSFrameCallbacks(JSContext *context, JSObject *global)
{
	JS_DefineFunction(context, global, "addFrameCallback", GlobalAddFrameCallback, 1, 0);
	JS_DefineFunction(context, global, "removeFrameCallback", GlobalRemoveFrameCallback, 1, 0);
	JS_DefineFunction(context, global, "isValidFrameCallback", GlobalIsValidFrameCallback, 1, 0);
	
#if DEBUG_FCB_SIMPLE_TRACKING_IDS
	sNextID = 1;
#else
	// Set randomish initial ID to catch bad habits.
	sNextID =  [[NSDate date] timeIntervalSinceReferenceDate];
#endif
}


void OOJSFrameCallbacksInvoke(OOTimeDelta delta)
{
	NSCAssert1(!sRunning, @"%s cannot be called while frame callbacks are running.", __PRETTY_FUNCTION__);
	
	if (sCount != 0)
	{
		OOJavaScriptEngine	*jsEng = [OOJavaScriptEngine sharedEngine];
		JSContext			*context = [jsEng acquireContext];
		jsval				deltaVal, result;
		OOUInteger			i;
		
		JS_BeginRequest(context);
		
		if (EXPECT_NOT(!JS_NewDoubleValue(context, delta, &deltaVal)))  return;
		
		// Block mutations.
		sRunning = YES;
		
		/*
			The watchdog timer only fires once per second in deployment builds,
			but in testrelease builds at least we can keep them on a short leash.
		*/
		OOJSStartTimeLimiterWithTimeLimit(0.1);
		
		for (i = 0; i < sCount; i++)
		{
			JS_CallFunctionValue(context, NULL, sCallbacks[i].callback, 1, &deltaVal, &result);
		}
		
		OOJSStopTimeLimiter();
		sRunning = NO;
		
		if (EXPECT_NOT(sDeferredOps != NULL))
		{
			RunDeferredOperations(context);
			DESTROY(sDeferredOps);
		}
		
		JS_EndRequest(context);
		[jsEng releaseContext:context];
	}
}


void OOJSFrameCallbacksRemoveAll(void)
{
	NSCAssert1(!sRunning, @"%s cannot be called while frame callbacks are running.", __PRETTY_FUNCTION__);
	
	if (sCount != 0)
	{
		OOJavaScriptEngine	*jsEng = [OOJavaScriptEngine sharedEngine];
		JSContext			*context = [jsEng acquireContext];
		JS_BeginRequest(context);
		
		while (sCount != 0)  RemoveCallbackAtIndex(context, sCount - 1);
		
		JS_EndRequest(context);
		[jsEng releaseContext:context];
	}
}


// MARK: Methods

// addFrameCallback(callback : Function) : Number
static JSBool GlobalAddFrameCallback(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	// Get callback argument and verify that it's a function.
	jsval callback = OOJS_ARG(0);
	if (EXPECT_NOT(!JSVAL_IS_OBJECT(callback) || !JS_ObjectIsFunction(context, JSVAL_TO_OBJECT(callback))))
	{
		OOJSReportBadArguments(context, nil, @"addFrameCallback", 1, OOJS_ARGV, nil, @"function");
		return NO;
	}
	
	// Assign a tracking ID.
	uint32 trackingID = sNextID ^ kIDScrambleMask;
	IncrementTrackingID();
	
	if (EXPECT(!sRunning))
	{
		// Add to list immediately.
		NSString *errorString = nil;
		if (EXPECT_NOT(!AddCallback(context, callback, trackingID, &errorString)))
		{
			OOJSReportError(context, @"%@", errorString);
			return NO;
		}
	}
	else
	{
		// Defer mutations during callback invocation.
		FCBLog(@"script.frameCallback.debug.add.deferred", @"Deferring addition of frame callback with tracking ID %u.", trackingID);
		QueueDeferredOperation(@"add", trackingID, [OOJSValue valueWithJSValue:callback inContext:context]);
	}
	
	OOJS_RETURN_INT(trackingID);
	
	OOJS_NATIVE_EXIT
}


// removeFrameCallback(trackingID : Number)
static JSBool GlobalRemoveFrameCallback(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	// Get tracking ID argument.
	uint32 trackingID;
	if (EXPECT_NOT(!JS_ValueToECMAUint32(context, OOJS_ARG(0), &trackingID)))
	{
		OOJSReportBadArguments(context, nil, @"removeFrameCallback", 1, OOJS_ARGV, nil, @"frame callback tracking ID");
		return NO;
	}
	
	if (EXPECT(!sRunning))
	{
		// Remove it.
		if (EXPECT_NOT(!RemoveCallbackWithTrackingID(context, trackingID)))
		{
			OOJSReportWarning(context, @"removeFrameCallback(): invalid tracking ID.");
		}
	}
	else
	{
		// Defer mutations during callback invocation.
		FCBLog(@"script.frameCallback.debug.remove.deferred", @"Deferring removal of frame callback with tracking ID %u.", trackingID);
		QueueDeferredOperation(@"remove", trackingID, nil);
	}
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// isValidFrameCallback(trackingID : Number)
static JSBool GlobalIsValidFrameCallback(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	// Get tracking ID argument.
	uint32 trackingID;
	if (EXPECT_NOT(!JS_ValueToECMAUint32(context, OOJS_ARG(0), &trackingID)))
	{
		OOJS_RETURN_BOOL(NO);
	}
	
	OOUInteger index;
	OOJS_RETURN_BOOL(GetIndexForTrackingID(trackingID, &index));
	
	OOJS_NATIVE_EXIT
}


// MARK: Internals

static BOOL AddCallback(JSContext *context, jsval callback, uint32 trackingID, NSString **errorString)
{
	NSCParameterAssert(context != NULL && JS_IsInRequest(context));
	NSCParameterAssert(errorString != NULL);
	NSCAssert1(!sRunning, @"%s cannot be called while frame callbacks are running.", __PRETTY_FUNCTION__);
	
	if (EXPECT_NOT(sCount == sSpace))
	{
		if (!GrowCallbackList(context, errorString))  return NO;
	}
	
	FCBLog(@"script.frameCallback.debug.add", @"Adding frame callback with tracking ID %u.", trackingID);
	
	sCallbacks[sCount].callback = callback;
	if (sCount >= sHighWaterMark)
	{
		// If we haven't used this slot before, root it.
		
		if (EXPECT_NOT(!OOJSAddGCValueRoot(context, &sCallbacks[sCount].callback, "frame callback")))
		{
			*errorString = @"Failed to add GC root for frame callback.";
			return NO;
		}
	}
	
	sCallbacks[sCount].trackingID = trackingID;
	sCount++;
	
	return YES;
}


static BOOL GrowCallbackList(JSContext *context, NSString **errorString)
{
	NSCParameterAssert(context != NULL && JS_IsInRequest(context));
	NSCParameterAssert(errorString != NULL);
	
	OOUInteger newSpace = MAX(sSpace * 2, (OOUInteger)kMinCount);
	
	CallbackEntry *newCallbacks = calloc(sizeof (CallbackEntry), newSpace);
	if (newCallbacks == NULL)  return NO;
	
	CallbackEntry *oldCallbacks = sCallbacks;
	
	// Root and copy occupied slots.
	OOUInteger newHighWaterMark = sCount;
	OOUInteger i;
	for (i = 0; i < newHighWaterMark; i++)
	{
		if (EXPECT_NOT(!OOJSAddGCValueRoot(context, &newCallbacks[i].callback, "frame callback")))
		{
			// If we can't root them all, we fail; unroot all entries to date, free the buffer and return NO.
			OOUInteger j;
			for (j = 0; i < i; j++)
			{
				JS_RemoveValueRoot(context, &newCallbacks[j].callback);
			}
			free(newCallbacks);
			
			*errorString = @"Failed to add GC root for frame callback.";
			return NO;
		}
		newCallbacks[i] = oldCallbacks[i];
	}
	
	// Unroot old array's slots.
	for (i = 0; i < sHighWaterMark; i++)
	{
		JS_RemoveValueRoot(context, &oldCallbacks[i].callback);
	}
	
	// We only rooted the occupied slots, so reset high water mark.
	sHighWaterMark = newHighWaterMark;
	
	// Replace array.
	sCallbacks = newCallbacks;
	free(oldCallbacks);
	sSpace = newSpace;
	
	return YES;
}


OOINLINE void IncrementTrackingID(void)
{
#if DEBUG_FCB_SIMPLE_TRACKING_IDS
	sNextID++;
#else
	/*	Increment by a large prime number to produce a non-obvious sequence
		which still uses all 2^32 values.
	*/
	sNextID += 992699;
#endif
}


static BOOL GetIndexForTrackingID(uint32 trackingID, OOUInteger *outIndex)
{
	NSCParameterAssert(outIndex != 0);
	
	/*	It is assumed that few frame callbacks will be active at once, so a
		linear search is reasonable. If they become unexpectedly popular, we
		can switch to a sorted list or a separate lookup table without changing
		the API.
	*/
	OOUInteger i;
	for (i = 0; i < sCount; i++)
	{
		if (sCallbacks[i].trackingID == trackingID)
		{
			*outIndex = i;
			return YES;
		}
	}
	
	return NO;
}


static BOOL RemoveCallbackWithTrackingID(JSContext *context, uint32 trackingID)
{
	NSCParameterAssert(context != NULL && JS_IsInRequest(context));
	NSCAssert1(!sRunning, @"%s cannot be called while frame callbacks are running.", __PRETTY_FUNCTION__);
	
	OOUInteger index;
	if (GetIndexForTrackingID(trackingID, &index))
	{
		RemoveCallbackAtIndex(context, index);
		return YES;
	}
	
	return NO;
}


static void RemoveCallbackAtIndex(JSContext *context, OOUInteger index)
{
	NSCParameterAssert(context != NULL && JS_IsInRequest(context));
	NSCParameterAssert(index < sCount && sCallbacks != NULL);
	NSCAssert1(!sRunning, @"%s cannot be called while frame callbacks are running.", __PRETTY_FUNCTION__);
	
	FCBLog(@"script.frameCallback.debug.remove", @"Removing frame callback with tracking ID %u.", sCallbacks[index].trackingID);
	
	// Overwrite entry to be removed with last entry, and decrement count.
	sCount--;
	sCallbacks[index] = sCallbacks[sCount];
	sCallbacks[sCount].callback = JSVAL_NULL;
	
#if DEBUG_FCB_SIMPLE_TRACKING_IDS
	if (sCount == 0)
	{
		OOLog(@"script.frameCallback.debug.reset", @"All frame callbacks removed, resetting next ID to 1.");
		sNextID = 1;
	}
#endif
}


static void QueueDeferredOperation(NSString *opType, uint32 trackingID, OOJSValue *value)
{
	NSCAssert1(sRunning, @"%s can only be called while frame callbacks are running.", __PRETTY_FUNCTION__);
	
	if (sDeferredOps == nil)  sDeferredOps = [[NSMutableArray alloc] init];
	[sDeferredOps addObject:[NSDictionary dictionaryWithObjectsAndKeys:
							 opType, @"operation",
							 [NSNumber numberWithInt:trackingID], @"trackingID",
							 value, @"value",
							 nil]];
}


static void RunDeferredOperations(JSContext *context)
{
	NSDictionary		*operation = nil;
	NSEnumerator		*operationEnum = nil;
	
	FCBLog(@"script.frameCallback.debug.run-deferred", @"Running %lu deferred frame callback operations.", (long)[sDeferredOps count]);
	FCBLogIndentIf(@"script.frameCallback.debug.run-deferred");
	
	for (operationEnum = [sDeferredOps objectEnumerator]; (operation = [operationEnum nextObject]); )
	{
		NSString	*opType = [operation objectForKey:@"operation"];
		uint32		trackingID = [operation oo_intForKey:@"trackingID"];
		
		if ([opType isEqualToString:@"add"])
		{
			OOJSValue	*callbackObj = [operation objectForKey:@"value"];
			NSString	*errorString = nil;
			
			if (!AddCallback(context, [callbackObj oo_jsValueInContext:context], trackingID, &errorString))
			{
				OOLogWARN(@"script.frameCallback.deferredAdd.failed", @"Deferred frame callback insertion failed: %@", errorString);
			}
		}
		else if ([opType isEqualToString:@"remove"])
		{
			RemoveCallbackWithTrackingID(context, trackingID);
		}
	}
	
	FCBLogOutdentIf(@"script.frameCallback.debug.run-deferred");
}
