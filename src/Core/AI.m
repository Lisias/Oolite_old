//
//  AI.m
/*
 *
 *  Oolite
 *
 *  Created by Giles Williams on Sat Apr 03 2004.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

Copyright (c) 2004, Giles C Williams
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#import "AI.h"
#import "entities.h"
#import "ResourceManager.h"


@implementation AI

- (id) prepare
{
	aiLock = [[NSLock alloc] init];
	//
	[aiLock lock];	// protect from asynchronous access
	//
	ai_stack = [[NSMutableArray alloc] init];	// retained
	//
	pendingMessages = [[NSMutableArray alloc] init];	// retained
	//
	nextThinkTime = [[NSDate distantFuture] timeIntervalSinceNow];	// don't think for a while
	//
	thinkTimeInterval = AI_THINK_INTERVAL;
	//
	stateMachine = nil;	// no initial brain
	//
	[aiLock unlock];	// okay now we're ready...
	//
	return self;
}

- (id) init
{    
    self = [super init];
    return [self prepare];
}

- (void) dealloc
{
	[aiLock lock];	// LOCK the AI preventing reaction to messages
	//
	if (owner_desc)			[owner_desc release];
	[ai_stack removeAllObjects];	// releasing them all
	if (ai_stack)			[ai_stack release];
    if (stateMachine)		[stateMachine release];
	if (stateMachineName)	[stateMachineName release];
    if (currentState)		[currentState release];
	[pendingMessages removeAllObjects];	// releasing them all
	if (pendingMessages)	[pendingMessages release];
	//
	[aiLock unlock];
	if (aiLock)				[aiLock release];
	[super dealloc];
}

- (NSString*) description
{
	return [NSString stringWithFormat:@"<AI with stateMachine: '%@' in state: '%@'>", stateMachineName, currentState];
}

- (id) initWithStateMachine:(NSString *) smName andState:(NSString *) stateName
{    
    self = [super init];
    //
	[self prepare];
	//
	if (smName)
		[self setStateMachine:smName];
	//
	if (stateName)
		currentState = [stateName retain];
	//
    return self;
}

- (void) setOwner:(ShipEntity *)ship
{
	owner = ship;   // now we assume this is retained elsewhere!
	if (owner_desc)			[owner_desc release];
	owner_desc = [[NSString stringWithFormat:@"%@ %d", [owner name], [owner universal_id]] retain];
}

- (void) preserveCurrentStateMachine
{
	if (!stateMachine)
		return;
	
	NSMutableDictionary *pickledMachine = [NSMutableDictionary dictionaryWithCapacity:3];
	
	// use copies because the currently referenced objects might change
	[pickledMachine setObject:[NSDictionary dictionaryWithDictionary: stateMachine] forKey:@"stateMachine"];
	[pickledMachine setObject:[NSString stringWithString: currentState] forKey:@"currentState"];
	[pickledMachine setObject:[NSString stringWithString: stateMachineName] forKey:@"stateMachineName"];
	[pickledMachine setObject:[NSArray arrayWithArray: pendingMessages] forKey:@"pendingMessages"];
	
	if (!ai_stack)
		ai_stack = [[NSMutableArray alloc] initWithCapacity:8];
	
	if ([ai_stack count] > 32)
	{
		NSLog(@"***** ERROR: AI stack overflow for %@ stack:\n%@", owner, ai_stack);
		NSException *myException = [NSException
			exceptionWithName:@"OoliteException"
			reason:[NSString stringWithFormat:@"AI stack overflow for %@", owner]
			userInfo:nil];
		[myException raise];
		return;
	}
	
	[ai_stack insertObject:pickledMachine atIndex:0];	//  PUSH
}

- (void) restorePreviousStateMachine
{
	if (!ai_stack)
		return;
	if ([ai_stack count] < 1)
		return;
	NSMutableDictionary *pickledMachine = [ai_stack objectAtIndex:0];
	
	//debug
	//NSLog(@"restoring pickled ai :\n%@",[pickledMachine description]);
	
	[aiLock lock];
	if (stateMachine)   [stateMachine release];
	stateMachine = [[NSDictionary dictionaryWithDictionary:(NSDictionary *)[pickledMachine objectForKey:@"stateMachine"]] retain];
	if (currentState)   [currentState release];
	currentState = [[NSString stringWithString:(NSString *)[pickledMachine objectForKey:@"currentState"]] retain];
	if (stateMachineName)   [stateMachineName release];
	stateMachineName = [[NSString stringWithString:(NSString *)[pickledMachine objectForKey:@"stateMachineName"]] retain];
	if (pendingMessages)   [pendingMessages release];
	pendingMessages = [[NSMutableArray arrayWithArray:(NSArray *)[pickledMachine objectForKey:@"pendingMessages"]] retain];  // restore a MUTABLE array
	//NSLog(@"debug restorePreviousStateMachine");
	[aiLock unlock];
	
	[ai_stack removeObjectAtIndex:0];   //  POP
}

- (void) exitStateMachine
{
	if ([ai_stack count] > 0)
	{
		if ((owner)&&([owner reportAImessages]))   NSLog(@"Popping previous state machine for %@",self);
		[self restorePreviousStateMachine];
		[self reactToMessage:@"RESTARTED"];
	}
}

- (void) setStateMachine:(NSString *) smName
{
	//
	[aiLock lock];
	//
	NSDictionary* newSM = [ResourceManager dictionaryFromFilesNamed:smName inFolder:@"AIs" andMerge:NO];
	//
	if (newSM)
	{
		[self preserveCurrentStateMachine];
		if (stateMachine)
			[stateMachine release];	// release old state machine
		stateMachine = [newSM retain];
		nextThinkTime = 0.0;	// think at next tick
	}
	//
	[aiLock unlock];
	//
	if (currentState)		[currentState release];
	currentState = [[NSString stringWithString:@"GLOBAL"] retain];
	[self reactToMessage:@"ENTER"];
    //
    //NSLog(@"AI Loaded:\n%@",[stateMachine description]);
    //
	
	//  refresh name
	//
	if (owner_desc)			[owner_desc release];
	owner_desc = [[NSString stringWithFormat:@"%@ %d", [owner name], [owner universal_id]] retain];
	
	// refresh stateMachineName
	//
	if (stateMachineName)
		[stateMachineName release];
	stateMachineName = [smName retain];
}

- (int) ai_stack_depth
{
	return [ai_stack count];
}


- (void) setState:(NSString *) stateName
{
	if ([stateMachine objectForKey:stateName])
	{
		//if ((owner)&&([owner universal_id])&&([owner reportAImessages])) NSLog(@"AI for %@ enters state %@", owner_desc, stateName);
		//
		[self reactToMessage:@"EXIT"];
		if (currentState)		[currentState release];
		currentState = [stateName retain];
		[self reactToMessage:@"ENTER"];
	}
}

- (void) reactToMessage:(NSString *) message
{
	int i;
	NSArray* actions;
	NSDictionary* messagesForState;
	
	if (!message)
		return;
	//
	if (!owner)
		return;
	//
	if ([owner universal_id] == NO_TARGET)  // don't think until launched
		return;
	//
	if (!stateMachine)
		return;
	//
	if (![stateMachine objectForKey:currentState])
		return;

	[aiLock lock];
	//
	messagesForState = [NSDictionary dictionaryWithDictionary:[stateMachine objectForKey:currentState]];
	//
	if ((currentState)&&(![message isEqual:@"UPDATE"])&&((owner)&&([owner reportAImessages])))
		NSLog(@"AI for %@ in state '%@' receives message '%@'", owner_desc, currentState, message);
	//
	actions = [NSArray arrayWithArray:[messagesForState objectForKey:message]];
	//
	[aiLock unlock];

	if ((actions)&&([actions count] > 0))
	{
		//
		for (i = 0; i < [actions count]; i++)
			[self takeAction:[actions objectAtIndex:i]];
		//
	}
	else
	{
		if (currentState)
		{
			SEL _interpretAIMessageSel = @selector(interpretAIMessage:);
			//if ((owner)&&([owner reportAImessages])&&(![message isEqual:@"UPDATE"]))
			//   NSLog(@"AI for %@ has no response to '%@' in state '%@'", owner_desc, message, currentState);
			//if ([owner respondsToSelector:NSSelectorFromString(@"interpretAIMessage:")])
			if ([owner respondsToSelector:_interpretAIMessageSel])
				[owner performSelector:_interpretAIMessageSel withObject:message];
		}
	}
}

- (void) takeAction:(NSString *) action
{
	NSArray*	tokens = [Entity scanTokensFromString:action];
	NSString*	dataString = nil;
	NSString*   my_selector;
	SEL			_selector;
	
	if ((owner)&&([owner reportAImessages]))   NSLog(@"%@ to take action %@", owner_desc, action);
	
	if ([tokens count] < 1)
	{
		if ([owner reportAImessages])   NSLog(@"No action '%@'",action);
		return;
	}
	
	my_selector = (NSString *)[tokens objectAtIndex:0];
	
	if ([tokens count] > 1)
	{
		dataString = [[tokens subarrayWithRange:NSMakeRange(1, [tokens count] - 1)] componentsJoinedByString:@" "];
	}
	
	_selector = NSSelectorFromString(my_selector);
	
	if (!owner)
	{
		NSLog(@"***** AI %@, trying to perform %@, is orphaned (no owner)", self, my_selector);
		return;
	}
	
	if (![owner respondsToSelector:_selector])
	{
		if ([my_selector isEqual:@"setStateTo:"])
			[self setState:dataString];
		else
			NSLog(@"***** %@ does not respond to %@", owner_desc, my_selector);
	}
	else
	{
		if (dataString)
			[owner performSelector:_selector withObject:dataString];
		else
			[owner performSelector:_selector];
	}
}

- (void) think
{
	
	NSArray *ms_list = nil;
	
	if ([owner universal_id] == NO_TARGET)  // don't think until launched
		return;
	//
	
	if (!stateMachine)  // don't think until launched
		return;
	//
	
	[self reactToMessage:@"UPDATE"];

	[aiLock lock];
	if ([pendingMessages retain])
	{
		//NSLog(@"debug1");
		if ([pendingMessages count] > 0)
			ms_list = [NSArray arrayWithArray:pendingMessages];
		//NSLog(@"debug2");
		[pendingMessages removeAllObjects];
		[pendingMessages release];
	}
	[aiLock unlock];
	
	if (ms_list)
	{
		int i;
		for (i = 0; i < [ms_list count]; i++)
			[self reactToMessage:(NSString *)[ms_list objectAtIndex:i]];
	}
}

- (void) message:(NSString *) ms
{
	if ([owner universal_id] == NO_TARGET)  // don't think until launched
		return;
	//

	[pendingMessages addObject:ms];
	//[self think];
}

- (void) setNextThinkTime:(double) ntt
{
	nextThinkTime = ntt;
}

- (double) nextThinkTime
{
	if (!stateMachine)
		return [[NSDate distantFuture] timeIntervalSinceNow];

	return nextThinkTime;
}

- (void) setThinkTimeInterval:(double) tti
{
	thinkTimeInterval = tti;
}

- (double) thinkTimeInterval
{
	return thinkTimeInterval;
}

- (void) clearStack
{
	[aiLock lock];
	//
	if (ai_stack)
		[ai_stack removeAllObjects];
	//
	[aiLock unlock];
}

- (void) clearAllData
{
	[aiLock lock];
	//
	if (ai_stack)
		[ai_stack removeAllObjects];
	//
	//
	if (pendingMessages)
		[pendingMessages removeAllObjects];
	//
	//
	nextThinkTime += 36000.0;	// should dealloc in under ten hours!
	thinkTimeInterval = 36000.0;
	//
	[aiLock unlock];
}

@end
