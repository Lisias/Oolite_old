/*

oolite-global-prefix.js

This script is run before any other JavaScript script. It is used to implement
parts of the Oolite JavaScript environment in JavaScript.

Do not override this script! Its functionality is likely to change between
Oolite versions, and functionality may move between the Oolite application and
this script.

“special” is an object provided to the script (as a property) that allows
access to functions otherwise internal to Oolite. Currently, this means the
special.jsWarning() function, which writes a warning to the log and, if
applicable, the debug console.


Oolite
Copyright © 2004-2011 Giles C Williams and contributors

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


// NOTE: for jslint to work, you must comment out the use of __proto__.
/*jslint white: true, undef: true, eqeqeq: true, bitwise: false, regexp: true, newcap: true, immed: true */
/*global Entity, global, mission, player, Quaternion, Ship, special, system, Vector3D, SystemInfo, expandMissionText*/


"use strict";


this.name			= "oolite-global-prefix";
this.author			= "Jens Ayton";
this.copyright		= "© 2009-2011 the Oolite team.";
this.version		= "1.75";


/**** Built-in in ECMAScript 5, to be removed when Linux builds transition ****/

/*
	Object.defineProperty: subset of ECMAScript 5 standard. In particular, the
	configurable, enumerable and writable properties are not supported.
*/
if (typeof Object.defineProperty !== "function")
{
	Object.defineProperty = function (object, property, descriptor)
	{
		if (descriptor.value !== undefined)
		{
			object[property] = descriptor.value;
		}
		else
		{
			if (descriptor.get !== undefined)
			{
				object.__defineGetter__(property, descriptor.get);
			}
			if (descriptor.set !== undefined)
			{
				object.__defineSetter__(property, descriptor.set);
			}
		}
	}
}


//	Object.getPrototypeOf(): ECMAScript 5th Edition eqivalent to __proto__ extension.
if (typeof Object.getPrototypeOf !== "function")
{
	Object.getPrototypeOf = function (object)
	{
		return object.__proto__;
	};
}

/*	string.trim(): remove leading and trailing whitespace.
	Implementation by Steve Leviathan, see:
	http://blog.stevenlevithan.com/archives/faster-trim-javascript
	Note: as of ECMAScript 5th Edition, this will be a core language method.
*/
if (typeof String.prototype.trim !== "function")
{
	String.prototype.trim = function String_trim()
	{
		var	str = this.replace(/^\s\s*/, ''),
			 ws = /\s/,
			  i = str.length;
		while (ws.test(str.charAt(--i))) {}
		return str.slice(0, i + 1);
	};
}

// Array.isArray(object): true if object is an array.
if (typeof Array.isArray !== "function")
{
	Array.isArray = function Array_isArray(object)
	{
		return object && object.constructor === [].constructor;
	}
}


// Utility to define non-enumerable, non-configurable, permanent methods, to match the behaviour of native methods.
this.defineMethod = function(object, name, implementation)
{
	Object.defineProperty(object, name, { value: implementation, writable: false, configurable: false, enumerable: false });
}


/**** Miscellaneous utilities for public consumption ****
	  Note that these are documented as part of the scripting interface.
	  The fact that they’re currently in JavaScript is an implementation
	  detail and subject to change.
*/

// Ship.spawnOne(): like spawn(role, 1), but returns the ship rather than an array.
this.defineMethod(Ship.prototype, "spawnOne", function (role)
{
	var result = this.spawn(role, 1);
	return result ? result[0] : null;
});


// mission.addMessageTextKey(): load mission text from mission.plist and append to mission screen or info screen.
this.defineMethod(Mission.prototype, "addMessageTextKey", function (textKey)
{
	this.addMessageText((textKey ? expandMissionText(textKey) : null));
});


/*	SystemInfo.systemsInRange(): return SystemInfos for all systems within a
	certain distance.
*/
this.defineMethod(SystemInfo, "systemsInRange", function (range)
{
	if (range === undefined)
	{
		range = 7;
	}
	
	// Default to using the current system.
	var thisSystem = system.info;
	
	// If called on an instance instead of the SystemInfo constructor, use that system instead.
	if (this !== SystemInfo)
	{
		if (this.systemID !== undefined && this.distanceToSystem !== undefined)
		{
			thisSystem = this;
		}
		else
		{
			special.jsWarning("systemsInRange() called in the wrong context. Returning empty array.");
			return [];
		}
	}
	
	return SystemInfo.filteredSystems(this, function (other)
	{
		return (other.systemID !== thisSystem.systemID) && (thisSystem.distanceToSystem(other) <= range);
	});
});


/*	system.scrambledPseudoRandomNumber(salt : Number (integer)) : Number
	
	This function converts system.pseudoRandomNumber to an effectively
	arbitrary different value that is also stable per system. Every combination
	of system and salt produces a different number.
	
	This should generally be used in preference to system.pseudoRandomNumber,
	because multiple OXPs using system.pseudoRandomNumber to make the same kind
	of decision will cause unwanted clustering. For example, if three different
	OXPs add a station to a system when system.pseudoRandomNumber <= 0.25,
	their stations will always appear in the same system. If they instead use
	system.scrambledPseudoRandomNumber() with different salt values, there will
	be no obvious correlation between the different stations’ distributions.
*/
this.defineMethod(System.prototype, "scrambledPseudoRandomNumber", function (salt)
{
	// Convert from float in [0..1) with 24 bits of precision to integer.
	var n = Math.floor(this.pseudoRandomNumber * 16777216.0);
	
	// Add salt to enable generation of different sequences.
	n += salt;
	
	// Scramble with basic LCG psuedo-random number generator.
	n = (214013 * n + 2531011) & 0xFFFFFFFF;
	n = (214013 * n + 2531011) & 0xFFFFFFFF;
	n = (214013 * n + 2531011) & 0xFFFFFFFF;
	
	// Convert from (effectively) 32-bit signed integer to float in [0..1).
	return n / 4294967296.0 + 0.5;
});


/*	soundSource.playSound(sound : SoundExpression [, count : Number])
	
	Load a sound and play it.
*/
this.defineMethod(SoundSource.prototype, "playSound", function (sound, count)
{
	this.sound = sound;
	this.play(count);
});


delete this.defineMethod;


/**** Backwards-compatibility functions. These will be removed before next stable. ****/

// Define a read-only property that is an alias for another property.
this.defineCompatibilityGetter = function (constructorName, oldName, newName)
{
	var getter = function ()
	{
		special.jsWarning(constructorName + "." + oldName + " is deprecated, use " + constructorName + "." + newName + " instead.");
		return this[newName];
	};
	
	Object.defineProperty(global[constructorName].prototype, oldName, { get: getter });
};


this.defineCompatibilityGetterAndSetter = function (constructorName, oldName, newName)
{
	var getter = function ()
	{
		special.jsWarning(constructorName + "." + oldName + " is deprecated, use " + constructorName + "." + newName + " instead.");
		return this[newName];
	};
	var setter = function (value)
	{
		special.jsWarning(constructorName + "." + oldName + " is deprecated, use " + constructorName + "." + newName + " instead.");
		this[newName] = value;
	};
	
	Object.defineProperty(global[constructorName].prototype, oldName, { get: getter, set: setter });
};


this.defineCompatibilityGetter("Ship", "roleProbabilities", "roleWeights");
