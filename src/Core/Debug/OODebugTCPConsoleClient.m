/*

OODebugTCPConsoleClient.m


Oolite Debug OXP

Copyright (C) 2009 Jens Ayton

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

#ifndef OO_EXCLUDE_DEBUG_SUPPORT


#import "OODebugTCPConsoleClient.h"
#import "OODebugTCPConsoleProtocol.h"
#import "OODebugMonitor.h"
#import "OOFunctionAttributes.h"
#import "OOLogging.h"
#import <stdint.h>

#if OOLITE_WINDOWS
#import <winsock2.h>
#else
#import <arpa/inet.h>	// For htonl
#endif

#import "OOCollectionExtractors.h"
#import "OOTCPStreamDecoder.h"


#ifdef OO_LOG_DEBUG_PROTOCOL_PACKETS
static void LogSendPacket(NSDictionary *packet);
#else
#define LogSendPacket(packet) do {} while (0)
#endif


static void DecoderPacket(void *cbInfo, OOALStringRef packetType, OOALDictionaryRef packet);
static void DecoderError(void *cbInfo, OOALStringRef errorDesc);


OOINLINE BOOL StatusIsSendable(OOTCPClientConnectionStatus status)
{
	return status == kOOTCPClientStartedConnectionStage1 || status == kOOTCPClientStartedConnectionStage2 || status == kOOTCPClientConnected;
}


@interface OODebugTCPConsoleClient (OOPrivate)

- (void) closeConnection;

- (BOOL) sendBytes:(const void *)bytes count:(size_t)count;
- (void) sendDictionary:(NSDictionary *)dictionary;

- (void) sendPacket:(NSString *)packetType
	 withParameters:(NSDictionary *)parameters;

- (void) sendPacket:(NSString *)packetType
		  withValue:(id)value
	   forParameter:(NSString *)paramKey;

- (void) readData;
- (void) dispatchPacket:(NSDictionary *)packet ofType:(NSString *)packetType;

- (void) handleApproveConnectionPacket:(NSDictionary *)packet;
- (void) handleRejectConnectionPacket:(NSDictionary *)packet;
- (void) handleCloseConnectionPacket:(NSDictionary *)packet;
- (void) handleNoteConfigurationChangePacket:(NSDictionary *)packet;
- (void) handlePerformCommandPacket:(NSDictionary *)packet;
- (void) handleRequestConfigurationValuePacket:(NSDictionary *)packet;
- (void) handlePingPacket:(NSDictionary *)packet;
- (void) handlePongPacket:(NSDictionary *)packet;

- (void) disconnectFromServerWithMessage:(NSString *)message;
- (void) breakConnectionWithMessage:(NSString *)message;
- (void) breakConnectionWithBadStream:(NSStream *)stream;

@end


@implementation OODebugTCPConsoleClient

- (id) init
{
	return [self initWithAddress:nil port:0];
}


- (id) initWithAddress:(NSString *)address port:(uint16_t)port
{
	BOOL					OK = NO;
	NSDictionary			*parameters = nil;
	
	if (address == nil)  address = @"127.0.0.1";
	if (port == 0)  port = kOOTCPConsolePort;
	
	self = [super init];
	if (self != nil)
	{
		_host = [NSHost hostWithName:address];
		if (_host != nil)
		{
			[_host retain];
			[NSStream getStreamsToHost:_host
								  port:port
						   inputStream:&_inStream
						  outputStream:&_outStream];
		}
		
		if (_inStream != nil && _outStream != nil)
		{
			[_inStream retain];
			[_outStream retain];
			[_inStream setDelegate:self];
			[_outStream setDelegate:self];
			[_inStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
			[_outStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
			[_inStream open];
			[_outStream open];
			
			// Need to wait for the streams to reach open status before we can send packets
			// TODO: Might be neater to use the handleEvent callback to flag this.. - Micha 20090425
			NSRunLoop * myRunLoop = [NSRunLoop currentRunLoop];
			NSDate * timeOut = [NSDate dateWithTimeIntervalSinceNow:3]; // Wait up to 3 seconds
			while( _host != nil && ([_inStream streamStatus] < 2 || [_outStream streamStatus] < 2) &&
					[myRunLoop runMode:NSDefaultRunLoopMode beforeDate:timeOut] )
				; // Wait

			_decoder = OOTCPStreamDecoderCreate(DecoderPacket, DecoderError, NULL, self);
		}
		
		if (_decoder != NULL)
		{
			OK = YES;
			_status = kOOTCPClientStartedConnectionStage1;
			
			
			// Attempt to connect
			parameters = [NSDictionary dictionaryWithObjectsAndKeys:
							[NSNumber numberWithUnsignedInt:kOOTCPProtocolVersion_1_1_0], kOOTCPProtocolVersion,
							[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"], kOOTCPOoliteVersion,
							nil];
			[self sendPacket:kOOTCPPacket_RequestConnection
			   withParameters:parameters];
			
			if (_status == kOOTCPClientStartedConnectionStage1)  _status = kOOTCPClientStartedConnectionStage2;
			else  OK = NO;	// Connection failed.
		}
		
		if (!OK)
		{
			OOLog(@"debugTCP.connect.failed", @"Failed to connect to debug console at %@:%i.", address, port);
			[self release];
			self = nil;
		}
	}
	
	return self;
}


- (void) dealloc
{
	if (StatusIsSendable(_status))
	{
		[self disconnectFromServerWithMessage:@"TCP console bridge unexpectedly released while active."];
	}
	if (_monitor)
	{
		[_monitor disconnectDebugger:self message:@"TCP console bridge unexpectedly released while active."];
	}
	
	
	[self closeConnection];
	
	OOTCPStreamDecoderDestroy(_decoder);
	_decoder = NULL;
	
	[super dealloc];
}


- (BOOL)connectDebugMonitor:(in OODebugMonitor *)debugMonitor
			   errorMessage:(out NSString **)message
{
	if (_status == kOOTCPClientConnectionRefused)
	{
		if (message != NULL)  *message = @"Connection refused.";
		return NO;
	}
	if (_status == kOOTCPClientDisconnected)
	{
		if (message != NULL)  *message = @"Cannot reconnect after disconnecting.";
		return NO;
	}
	
	_monitor = debugMonitor;
	
	return YES;
}


- (void)disconnectDebugMonitor:(in OODebugMonitor *)debugMonitor
					   message:(in NSString *)message
{
	[self disconnectFromServerWithMessage:message];
	_monitor = nil;
}


- (oneway void)debugMonitor:(in OODebugMonitor *)debugMonitor
			jsConsoleOutput:(in NSString *)output
				   colorKey:(in NSString *)colorKey
			  emphasisRange:(in NSRange)emphasisRange
{
	NSMutableDictionary			*parameters = nil;
	NSArray						*range = nil;
	
	parameters = [NSMutableDictionary dictionaryWithCapacity:3];
	[parameters setObject:output forKey:kOOTCPMessage];
	[parameters setObject:colorKey ? colorKey : (NSString *)@"general" forKey:kOOTCPColorKey];
	if (emphasisRange.length != 0)
	{
		range = [NSArray arrayWithObjects:
						[NSNumber numberWithUnsignedInt:emphasisRange.location],
						[NSNumber numberWithUnsignedInt:emphasisRange.length],
						nil];
		[parameters setObject:range forKey:kOOTCPEmphasisRanges];
	}
	
	[self sendPacket:kOOTCPPacket_ConsoleOutput
	   withParameters:parameters];
}


- (oneway void)debugMonitorClearConsole:(in OODebugMonitor *)debugMonitor
{
	[self sendPacket:kOOTCPPacket_ClearConsole
	   withParameters:nil];
}


- (oneway void)debugMonitorShowConsole:(in OODebugMonitor *)debugMonitor;
{
	[self sendPacket:kOOTCPPacket_ShowConsole
	   withParameters:nil];
}


- (oneway void)debugMonitor:(in OODebugMonitor *)debugMonitor
		  noteConfiguration:(in NSDictionary *)configuration
{
	[self sendPacket:kOOTCPPacket_NoteConfiguration
			withValue:configuration
		 forParameter:kOOTCPConfiguration];
}


- (oneway void)debugMonitor:(in OODebugMonitor *)debugMonitor
noteChangedConfigrationValue:(in id)newValue
					 forKey:(in NSString *)key
{
	if (newValue != nil)
	{
		[self sendPacket:kOOTCPPacket_NoteConfiguration
				withValue:[NSDictionary dictionaryWithObject:newValue forKey:key]
			 forParameter:kOOTCPConfiguration];
	}
	else
	{
		[self sendPacket:kOOTCPPacket_NoteConfiguration
				withValue:[NSArray arrayWithObject:key]
			 forParameter:kOOTCPRemovedConfigurationKeys];
	}
}


- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
	if (_status > kOOTCPClientConnected)  return;
	
	if (stream == _inStream && eventCode == NSStreamEventHasBytesAvailable)
	{
		[self readData];
	}
	else if (eventCode == NSStreamEventErrorOccurred)
	{
		[self breakConnectionWithBadStream:stream];
	}
	else if (eventCode == NSStreamEventErrorOccurred)
	{
		[self breakConnectionWithMessage:[NSString stringWithFormat:
		   @"Console closed the connection."]];
	}
}

@end


@implementation OODebugTCPConsoleClient (OOPrivate)

- (void) closeConnection
{
	[_inStream close];
	[_inStream setDelegate:nil];
	[_inStream release];
	_inStream = nil;
	
	[_outStream close];
	[_outStream setDelegate:nil];
	[_outStream release];
	_outStream = nil;
	
	[_host release];
	_host = nil;
}


- (BOOL) sendBytes:(const void *)bytes count:(size_t)count
{
	int						written;
	
	if (bytes == NULL || count == 0)  return YES;
	if (!StatusIsSendable(_status) || _outStream == nil)  return NO;
	
	do
	{
		written = [_outStream write:bytes maxLength:count];
		if (written < 1)  return NO;
		
		count -= written;
		bytes += written;
	}
	while (count > 0);
	
	return YES;
}


- (void) sendDictionary:(NSDictionary *)dictionary
{
	NSData					*data = nil;
	NSString				*errorDesc = nil;
	size_t					count;
	const uint8_t			*bytes = NULL;
	uint32_t				header;
	
	if (dictionary == nil || !StatusIsSendable(_status))  return;
	
	data = [NSPropertyListSerialization dataFromPropertyList:dictionary
													  format:NSPropertyListXMLFormat_v1_0
											errorDescription:&errorDesc];
	
	if (data == nil)
	{
		OOLog(@"debugTCP.conversionFailure", @"Could not convert dictionary to data for transmission to debug console: %@", errorDesc ? errorDesc : (NSString *)@"unknown error.");
#if OOLITE_RELEASE_PLIST_ERROR_STRINGS
		[errorDesc autorelease];
#endif
		return;
	}
	
	LogSendPacket(dictionary);
	
	count = [data length];
	if (count == 0)  return;
	header = htonl(count);
	
	bytes = [data bytes];
	if (![self sendBytes:&header count:sizeof header] || ![self sendBytes:bytes count:count])
	{
		[self breakConnectionWithBadStream:_outStream];
	}
}


- (void) sendPacket:(NSString *)packetType
	 withParameters:(NSDictionary *)parameters
{
	NSMutableDictionary		*dict = nil;
	
	if (packetType == nil)  return;
	
	if (parameters != nil)
	{
		dict = [parameters mutableCopy];
		[dict setObject:packetType forKey:kOOTCPPacketType];
	}
	else
	{
		dict = [[NSDictionary alloc] initWithObjectsAndKeys:packetType, kOOTCPPacketType, nil];
	}
	
	[self sendDictionary:dict];
	[dict release];
}


- (void) sendPacket:(NSString *)packetType
		  withValue:(id)value
	   forParameter:(NSString *)paramKey
{
	if (packetType == nil)  return;
	if (paramKey == nil)  value = nil;
	
	[self sendDictionary:[NSDictionary dictionaryWithObjectsAndKeys:
		packetType, kOOTCPPacketType,
		value, paramKey,
		nil]];
}


- (void) readData
{
	enum { kBufferSize = 16 << 10 };
	
	uint8_t							buffer[kBufferSize];
	int								length;
	NSData							*data;
	
	length = [_inStream read:buffer maxLength:kBufferSize];
	while( length > 0 )
	{
		/* This test is superfluous after the rewrite to fix Bug#014643
		 * TODO: Put the BadStream test back into the code
		if (length < 1)
		{
			// Under GNUstep, but not OS X (currently), -hasBytesAvailable will return YES when the buffer is in fact empty.
			if ([_inStream streamStatus] == NSStreamStatusReading) break;
			
			[self breakConnectionWithBadStream:_inStream];
			return;
		}
		*/
		
		data = [NSData dataWithBytesNoCopy:buffer length:length freeWhenDone:NO];
		OOTCPStreamDecoderReceiveData(_decoder, data);
		length = [_inStream read:buffer maxLength:kBufferSize];
	}
}


- (void) dispatchPacket:(NSDictionary *)packet ofType:(NSString *)packetType
{
	if (packet == nil || packetType == nil)  return;
	
#define PACKET_CASE(x) else if ([packetType isEqualToString:kOOTCPPacket_##x])  { [self handle##x##Packet:packet]; }
	
	if (0) {}
	PACKET_CASE(ApproveConnection)
	PACKET_CASE(RejectConnection)
	PACKET_CASE(CloseConnection)
	PACKET_CASE(NoteConfigurationChange)
	PACKET_CASE(PerformCommand)
	PACKET_CASE(RequestConfigurationValue)
	PACKET_CASE(Ping)
	PACKET_CASE(Pong)
	else
	{
		OOLog(@"debugTCP.protocolError.unknownPacketType", @"Unhandled packet type %@.", packetType);
	}
}


- (void) handleApproveConnectionPacket:(NSDictionary *)packet
{
	NSMutableString			*connectedMessage = nil;
	NSString				*consoleIdentity = nil;
	NSString				*hostName = nil;
	
	if (_status == kOOTCPClientStartedConnectionStage2)
	{
		_status = kOOTCPClientConnected;
		
		// Build "Connected..." message with two optional parts, console identity and host name.
		connectedMessage = [NSMutableString stringWithString:@"Connected to external debug console"];
		
		consoleIdentity = [packet stringForKey:kOOTCPConsoleIdentity];
		if (consoleIdentity != nil)  [connectedMessage appendFormat:@" \"%@\"", consoleIdentity];
		
		hostName = [_host name];
		if ([hostName length] != 0 &&
			![hostName isEqual:@"localhost"] &&
			![hostName isEqual:@"127.0.0.1"] &&
			![hostName isEqual:@"::1"])
		{
			[connectedMessage appendFormat:@" at %@", hostName];
		}
		
		OOLog(@"debugTCP.connected", @"%@.", connectedMessage);
	}
	else
	{
		OOLog(@"debugTCP.protocolError.outOfOrder", @"Got %@ packet from debug console in wrong context.", kOOTCPPacket_ApproveConnection);
	}	
}


- (void) handleRejectConnectionPacket:(NSDictionary *)packet
{
	NSString				*message = nil;
	
	if (_status == kOOTCPClientStartedConnectionStage2)
	{
		_status = kOOTCPClientConnectionRefused;
	}
	else
	{
		OOLog(@"debugTCP.protocolError.outOfOrder", @"Got %@ packet from debug console in wrong context.", kOOTCPPacket_RejectConnection);
	}
	
	message = [packet stringForKey:kOOTCPMessage];
	if (message == nil)  message = @"Console refused connection.";
	[self breakConnectionWithMessage:message];
}


- (void) handleCloseConnectionPacket:(NSDictionary *)packet
{
	NSString				*message = nil;
	
	if (!StatusIsSendable(_status))
	{
		OOLog(@"debugTCP.protocolError.outOfOrder", @"Got %@ packet from debug console in wrong context.", kOOTCPPacket_CloseConnection);
	}
	message = [packet stringForKey:kOOTCPMessage];
	if (message == nil)  message = @"Console closed connection.";
	[self breakConnectionWithMessage:message];
}


- (void) handleNoteConfigurationChangePacket:(NSDictionary *)packet
{
	NSDictionary			*configuration = nil;
	NSArray					*removed = nil;
	NSEnumerator			*keyEnum = nil;
	NSString				*key = nil;
	id						value = nil;
	
	if (_monitor == nil)  return;
	
	configuration = [packet dictionaryForKey:kOOTCPConfiguration];
	if (configuration != nil)
	{
		for (keyEnum = [configuration keyEnumerator]; (key = [keyEnum nextObject]); )
		{
			value = [configuration objectForKey:key];
			[_monitor setConfigurationValue:value forKey:key];
		}
	}
	
	removed = [configuration arrayForKey:kOOTCPRemovedConfigurationKeys];
	for (keyEnum = [removed objectEnumerator]; (key = [keyEnum nextObject]); )
	{
		[_monitor setConfigurationValue:nil forKey:key];
	}
}


- (void) handlePerformCommandPacket:(NSDictionary *)packet
{
	NSString				*message = nil;
	
	message = [packet stringForKey:kOOTCPMessage];
	if (message != nil)  [_monitor performJSConsoleCommand:message];
}


- (void) handleRequestConfigurationValuePacket:(NSDictionary *)packet
{
	NSString				*key = nil;
	id						value = nil;
	
	key = [packet stringForKey:kOOTCPConfigurationKey];
	if (key != nil)
	{
		value = [_monitor configurationValueForKey:key];
		[self debugMonitor:_monitor
 noteChangedConfigrationValue:value
					forKey:key];
	}
}


- (void) handlePingPacket:(NSDictionary *)packet
{
	id						message = nil;
	
	message = [packet objectForKey:kOOTCPMessage];
	[self sendPacket:kOOTCPPacket_Pong
			withValue:message
		 forParameter:kOOTCPMessage];
}


- (void) handlePongPacket:(NSDictionary *)packet
{
	// Do nothing; we don't currently send pings.
}


- (void) disconnectFromServerWithMessage:(NSString *)message
{
	if (StatusIsSendable(_status))
	{
		[self sendPacket:kOOTCPPacket_CloseConnection
				withValue:message
			 forParameter:kOOTCPMessage];
	}
	[self closeConnection];
	
	_status = kOOTCPClientDisconnected;
}


- (void) breakConnectionWithMessage:(NSString *)message
{
	[self closeConnection];
	
	if (_status != kOOTCPClientConnectionRefused)  _status = kOOTCPClientDisconnected;
	
	if ([message length] > 0)
	{
		OOLog(@"debugTCP.disconnect", @"Debug console disconnected with message %@", message);
	}
	else
	{
		OOLog(@"debugTCP.disconnect", @"Debug console disconnected.");	
	}
	
#if 0
	// Disconnecting causes crashiness for reasons I don't understand, and isn't very important anyway.
	[_monitor disconnectDebugger:self message:message];
	_monitor = nil;
#endif
}


- (void) breakConnectionWithBadStream:(NSStream *)stream
{
	NSString				*errorDesc = nil;
	NSError					*error = nil;
	
	error = [stream streamError];
	errorDesc = [error localizedDescription];
	if (errorDesc == nil)  errorDesc = [error description];
	if (errorDesc == nil)  errorDesc = @"unknown error.";
	[self breakConnectionWithMessage:[NSString stringWithFormat:
	   @"Lost connection to remote debug console. outStream status: %i, inStream status: %i. Stream error: %@",
		[_outStream streamStatus], [_inStream streamStatus], errorDesc]];
}

@end


static void DecoderPacket(void *cbInfo, OOALStringRef packetType, OOALDictionaryRef packet)
{
	[(OODebugTCPConsoleClient *)cbInfo dispatchPacket:packet ofType:packetType];
}


static void DecoderError(void *cbInfo, OOALStringRef errorDesc)
{
	[(OODebugTCPConsoleClient *)cbInfo breakConnectionWithMessage:errorDesc];
}


#ifdef OO_LOG_DEBUG_PROTOCOL_PACKETS
void LogOOTCPStreamDecoderPacket(NSDictionary *packet)
{
	NSData					*data = nil;
	NSString				*xml = nil;
	
	data = [NSPropertyListSerialization dataFromPropertyList:packet format:NSPropertyListXMLFormat_v1_0 errorDescription:NULL];
	xml = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	OOLog(@"debugTCP.receive", @"Received packet:\n%@", xml);
}


static void LogSendPacket(NSDictionary *packet)
{
	NSData					*data = nil;
	NSString				*xml = nil;
	
	data = [NSPropertyListSerialization dataFromPropertyList:packet format:NSPropertyListXMLFormat_v1_0 errorDescription:NULL];
	xml = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	OOLog(@"debugTCP.send", @"Sent packet:\n%@", xml);
}
#endif

#endif /* OO_EXCLUDE_DEBUG_SUPPORT */
