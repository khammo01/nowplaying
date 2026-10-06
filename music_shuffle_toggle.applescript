-- Music's `shuffle enabled` property can report state while silently ignoring
-- writes. Press the native mini-player Shuffle control instead.
tell application "System Events"
	tell process "Music"
		set mainSplit to first UI element of window "Music" whose role is "AXSplitGroup"
		set mainGroups to every UI element of mainSplit whose role is "AXGroup"
		set miniWrapper to first UI element of item 2 of mainGroups whose role is "AXGroup"
		set miniPlayer to first UI element of miniWrapper whose role is "AXGroup"
		perform action "AXPress" of first button of miniPlayer
	end tell
end tell
