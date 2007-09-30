/*

oolite-trumbles.js

Script for random offers of trumbles.

Oolite
Copyright © 2007 Giles C Williams and contributors

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


this.name			= "oolite-trumbles";
this.author			= "Jens Ayton";
this.copyright		= "© 2007 the Oolite team.";
this.description	= "Random offers of trumbles.";
this.version		= "1.69.2";


this.log = function(message)
{
	// Uncomment next line for diagnostics.
//	LogWithClass("js.trumbles", message);
}


this.startUp = this.reset = function()
{
	/*	For simplicity, ensure that missionVariables.trumbles is never
		undefined when running the rest of the script. If it could be
		undefined, it would be necessary to test for undefinedness before
		doing any tests on the value, like so:
			if (missionVariables.trumbles && missionVariables.trumbles == "FOO")
	*/
	if (!missionVariables.trumbles)
	{
		missionVariables.trumbles = "";
		this.log("missionVariables.trumbles was undefined, set it to empty string.");
	}
	else
	{
		this.log("Reset with missionVariables.trumbles = " + missionVariables.trumbles);
	}
}


this.didDock = function()
{
	/*	In the pre-JavaScript implementation, the mission variable was set to
		OFFER_MADE while the mission screen was shown. If the player lanched
		in that state, the offer would never be made again -- unless some
		other script used the mission choice keys "YES" or "NO". This
		implementation uses unique choice keys and doesn't change the mission
		variable, which should be more reliable in all cases.
	*/
	if (missionVariables.trumbles == "OFFER_MADE")  missionVariables.trumbles = "BUY_ME"
	
	if (player.dockedStation.isMainStation &&
		missionVariables.trumbles == "" &&
		!missionVariables.novacount &&		// Hmm. Why is this here? (Ported from legacy script)
		player.credits > 6553.5)
	{
		this.log("Time to start selling trumbles.")
		missionVariables.trumbles = "BUY_ME"
	}
	
	if (missionVariables.trumbles == "BUY_ME")
	{
		this.log("Trumbles are on the market.")
		// 20% chance of trumble being offered, if no other script got this dock session first.
		if (guiScreen == "GUI_SCREEN_STATUS"
			&& Math.random() < 0.2)
		{
			this.log("Offering trumble.")
			
			let message =
			"Commander " + player.name + ",\n\n" +
			"You look like someone who could use a Trumble on your " + player.shipDescription + "!\n\n" +
			"This is yours for only 30 credits."
			
			// Show a mission screen.
			mission.clearMissionScreen()
			mission.setBackgroundImage("trumblebox.png")
			mission.showMissionScreen()
			mission.addMessageText(message)
			mission.setChoicesKey("oolite_trumble_offer_yesno")
		}
		else
		{
			this.log("Not offering trumble. GUI screen is " + guiScreen)
		}
	}
	else
	{
		this.log("Not offering trumble. mission_trumbles is " + missionVariables.trumbles)
	}
}


this.missionScreenEnded = function()
{
	if (missionVariables.trumbles == "BUY_ME")
	{
		this.log("Trumble mission screen closed.")
		
		if (mission.choice == "OOLITE_TRUMBLE_YES")
		{
			this.log("Trumble bought.")
			mission.clearMissionScreen()
			missionVariables.trumbles = "TRUMBLE_BOUGHT"
			player.credits -= 30
			player.awardEquipment("EQ_TRUMBLE")
		}
		else if (mission.choice == "OOLITE_TRUMBLE_NO")
		{
			this.log("Trumble rejected.")
			mission.clearMissionScreen()
			missionVariables.trumbles = "NOT_NOW"
		}
	}
	else
	{
		this.log("Non-trumble mission screen closed.")
	}
}


this.willExitWitchSpace = function()
{
	// If player has rejected a trumble offer, reset trumble mission with 2% probability per jump.
	if (missionVariables.trumbles == "NOT_NOW" && Math.random < 0.02)
	{
		this.log("Resetting trumble buyability.")
		missionVariables.trumbles = "BUY_ME"
	}
}
