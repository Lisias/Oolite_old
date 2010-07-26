/*

oolite-constrictor-hunt-mission.js

Script for Constrictor hunt mission.


Oolite
Copyright © 2004-2010 Giles C Williams and contributors

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


/*jslint bitwise: true, undef: true, eqeqeq: true, immed: true, newcap: true*/
/*global missionVariables, player*/


this.name			= "oolite-constrictor";
this.author			= "Eric Walch";
this.copyright		= "© 2008-2010 the Oolite team.";
this.version		= "1.74.3";


this.legalPoints = 0;

this.shipSpawned = function ()
{
	this.legalPoints = this.ship.bounty;
	this.ship.bounty = 0;
	if (player.score > 512) this.ship.awardEquipment("EQ_SHIELD_BOOSTER"); // Player is Dangerous
	if (player.score > 2560) this.ship.awardEquipment("EQ_SHIELD_ENHANCER"); // Player is Deadly
	this.ship.energy = this.ship.maxEnergy; // start with all energy banks full.
};


this.shipDied = function (killer)
{
    if(killer.isPlayer)
	{
		missionVariables.conhunt = "CONSTRICTOR_DESTROYED";
	}
};


this.checkDistance = function ()
{
	if (player.ship.position.distanceTo(this.ship) < 50000)
	{
		if(this.legalPoints > 0)
		{
			this.ship.bounty = this.legalPoints;
			this.legalPoints = 0;
		}
	}
	else
	{
		if(this.legalPoints === 0)
		{
			this.legalPoints = this.ship.bounty;
			this.ship.bounty = 0;
		}
	}
};
