-- Bring Microsoft Teams forward before sending its native mute shortcut.
-- This makes the rotary meeting control independent of whichever app was
-- active when the button was pressed.

tell application "Microsoft Teams" to activate
delay 0.25
tell application "System Events"
	keystroke "m" using {command down, shift down}
end tell

return "OK|Toggled Teams microphone"
