-- The dashboard action means "start shuffled playback now", not merely change
-- the hidden Up Next ordering. Starting the Library as the shuffled context
-- also escapes radio-station URL tracks, which forcibly disable shuffle.
tell application "Music"
	if not running then launch
	set shuffle mode to songs
	set shuffle enabled to true
	play library playlist 1
	return "shuffled-library-playing"
end tell
