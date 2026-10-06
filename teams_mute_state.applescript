-- Read Teams' actual microphone button state from its accessibility tree.
-- "Unmute mic" means the microphone is currently muted; "Mute mic" means
-- it is currently live. BetterTouchTool runs this with its Accessibility
-- permission and stores the result for Home Assistant / the rotary controller.

on run
	set muteState to "unknown"
	try
		tell application "System Events"
			if not (exists process "Microsoft Teams") then return my saveState("unavailable")
			tell process "Microsoft Teams"
				my saveState("checking")
				with timeout of 6 seconds
					repeat with teamsWindow in windows
						set windowName to ""
						try
							set windowName to name of teamsWindow as text
						end try
						-- The main Calendar window contains thousands of Outlook
						-- accessibility nodes and never owns the in-call controls.
						if windowName does not start with "Calendar |" then
							set windowItems to entire contents of teamsWindow
							repeat with itemRef in windowItems
								try
									if role of itemRef is "AXButton" then
										set itemName to name of itemRef as text
										if itemName is "Unmute mic" then return my saveState("muted")
										if itemName is "Mute mic" then return my saveState("unmuted")
									end if
								on error
									-- Ignore transient Chromium accessibility nodes.
								end try
							end repeat
						end if
					end repeat
				end timeout
			end tell
		end tell
	on error
		return my saveState("unknown")
	end try
	return my saveState("unavailable")
end run

on saveState(muteState)
	try
		tell application "BetterTouchTool" to set_string_variable "teams_mute_state" to muteState
	end try
	return muteState
end saveState
