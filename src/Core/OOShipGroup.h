/*
OOShipGroup.h

A weak-referencing, mutable set of ships. Not thread safe.


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

*/

#import "OOCocoa.h"
#import "OOWeakReference.h"

@class ShipEntity;


@interface OOShipGroup: OOWeakRefObject
#if OOLITE_FAST_ENUMERATION
<NSFastEnumeration>
#endif
{
@private
	OOUInteger				_count, _capacity;
	unsigned long			_updateCount;
	OOWeakReference			**_members;
	OOWeakReference			*_leader;
	NSString				*_name;
	
	struct JSObject			*_jsSelf;
}

- (id) init;
- (id) initWithName:(NSString *)name;
+ (id) groupWithName:(NSString *)name;
+ (id) groupWithName:(NSString *)name leader:(ShipEntity *)leader;

- (NSString *) name;
- (void) setName:(NSString *)name;

- (ShipEntity *) leader;
- (void) setLeader:(ShipEntity *)leader;

- (NSEnumerator *) objectEnumerator;
- (NSSet *) members;
- (NSArray *) memberArray;	// arbitrary order

- (BOOL) containsShip:(ShipEntity *)ship;
- (void) addShip:(ShipEntity *)ship;
- (void) removeShip:(ShipEntity *)ship;

- (OOUInteger) count;		// NOTE: this is O(n).
- (BOOL) isEmpty;

@end
