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
				with timeout of 8 seconds
					repeat with teamsWindow in windows
						set windowName to ""
						try
							set windowName to name of teamsWindow as text
						end try
						-- The main Calendar window contains thousands of Outlook
						-- accessibility nodes and never owns the in-call controls.
						if windowName does not start with "Calendar |" then
							-- Walk directly to the compact meeting-controls branch.
							-- Scanning the full Chromium window takes several seconds
							-- longer and caused the controller to read an interim value.
							set p1 to UI element 1 of teamsWindow
							set p2 to UI element 1 of p1
							set p3 to UI element 2 of p2
							set p4 to UI element 2 of p3
							set p5 to UI element 2 of p4
							set p6 to UI element 1 of p5
							set p7 to UI element 1 of p6
							set p8 to UI element 1 of p7
							set p9 to UI element 2 of p8
							set p10 to UI element 1 of p9
							set p11 to UI element 1 of p10
							set p12 to UI element 1 of p11
							set meetingRoot to UI element 1 of p12
							set controlItems to entire contents of UI element 3 of meetingRoot
							repeat with itemRef in controlItems
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
