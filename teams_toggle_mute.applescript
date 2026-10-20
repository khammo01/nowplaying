-- Toggle the microphone through SoundSource's global Command-Shift-M shortcut.
-- Do not activate Teams or disturb the user's frontmost window.

tell application "System Events"
	keystroke "m" using {command down, shift down}
end tell

return "OK|Toggled microphone with the global SoundSource shortcut"
