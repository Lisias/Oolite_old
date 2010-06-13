/*

oolite-default-ship-script.js

Standard ship script; handles legacy foo_actions.


Oolite
Copyright © 2004-2009 Giles C Williams and contributors

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


/*jslint bitwise: true, undef: true, undef: true, eqeqeq: true, newcap: true*/


this.name			= "oolite-default-ship-script";
this.author			= "Jens Ayton";
this.copyright		= "© 2007–2009 the Oolite team.";
this.description	= "Standard script for ships.";
this.version		= "1.74.1";


// launch_actions handled on shipSpawned().
if (this.legacy_launchActions !== undefined)
{
	this.shipSpawned = function ()
	{
		/*	IMPORTANT: runLegacyScriptActions() is a private function. It may
			be removed, renamed or have its semantics changed at any time in
			the future. Do not use it in your own scripts.
		*/
		this.ship.runLegacyScriptActions(this.ship, this.legacy_launchActions);
		
		// These can only be used once; keeping them around after that is pointless.
		delete this.shipSpawned;
		delete this.legacy_launchActions;
	};
}


// death_actions handled on shipDied().
if (this.legacy_deathActions !== undefined)
{
	this.shipDied = function ()
	{
		/*	IMPORTANT: runLegacyScriptActions() is a private function. It may
			be removed, renamed or have its semantics changed at any time in
			the future. Do not use it in your own scripts.
		*/
		this.ship.runLegacyScriptActions(this.ship, this.legacy_deathActions);
	};
}


// script_actions handled on otherShipDocked() and shipWasScooped().
if (this.legacy_scriptActions !== undefined)
{
	/*	legacy script_actions should be called for stations when the player
		docks, and for cargo pods when they are is scooped. No sane vessel can
		be scooped _and_ docked with. Non-sane vessels are certified insane.
	*/
	this.otherShipDocked = function (docker)
	{
		if (docker.isPlayer)
		{
			/*	IMPORTANT: runLegacyScriptActions() is a private function. It
				may be removed, renamed or have its semantics changed at any
				time in the future. Do not use it in your own scripts.
			*/
			this.ship.runLegacyScriptActions(docker, this.legacy_scriptActions);
		}
	};
	this.shipWasScooped = function (scooper)
	{
		/*	IMPORTANT: runLegacyScriptActions() is a private function. It may
			be removed, renamed or have its semantics changed at any time in
			the future. Do not use it in your own scripts.
		*/
		
		// Note "backwards" call, allowing awardEquipment: and similar to affect the scooper rather than the scoopee.
		scooper.runLegacyScriptActions(scooper, this.legacy_scriptActions);
	};
}


// setup_actions handled on script initialization.
if (this.legacy_setupActions !== undefined)
{
	/*	IMPORTANT: runLegacyScriptActions() is a private function. It may be
		removed, renamed or have its semantics changed at any time in the
		future. Do not use it in your own scripts.
	*/
	this.ship.runLegacyScriptActions(this.ship, this.legacy_setupActions);
	delete this.legacy_setupActions;
}
