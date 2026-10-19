-- Start Apple Music's Genius Shuffle, which builds playback from related library tracks.
tell application "Music"
	if not running then launch
	activate
end tell

delay 0.15

tell application "System Events"
	tell process "Music"
		if exists menu item "Genius Shuffle" of menu "Controls" of menu bar 1 then
			click menu item "Genius Shuffle" of menu "Controls" of menu bar 1
		else
			keystroke space using option down
		end if
	end tell
end tell
return "genius-shuffle-started"
