-- Send a command to the exact YouTube video selected by NowPlaying.
--
-- Usage:
--   osascript youtube_target_command.applescript captions
--   osascript youtube_target_command.applescript fullscreen
--   osascript youtube_target_command.applescript slower
--   osascript youtube_target_command.applescript faster
--   osascript youtube_target_command.applescript playpause
--   osascript youtube_target_command.applescript seek_relative 10

on split_pipe(theText)
	set oldDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to "|"
	set theParts to text items of theText
	set AppleScript's text item delimiters to oldDelimiters
	return theParts
end split_pipe

on is_youtube_video(theURL)
	if theURL is missing value then return false
	set theURL to theURL as text
	return (theURL contains "youtube.com/watch") or (theURL contains "youtube.com/shorts/") or (theURL contains "youtu.be/")
end is_youtube_video

on inventory_path()
	return (POSIX path of (path to home folder)) & "NowPlaying/cache/browser-inventory.json"
end inventory_path

on read_cached_target()
	try
		set cacheText to do shell script "/usr/bin/jq -r 'if (.active.browser // \"\") != \"\" then [.active.browser,.active.window_index,.active.tab_index,.active.url] | join(\"|\") else empty end' " & quoted form of my inventory_path()
		set cacheParts to my split_pipe(cacheText)
		if (count of cacheParts) ≥ 4 then return {item 1 of cacheParts, (item 2 of cacheParts as integer), (item 3 of cacheParts as integer), item 4 of cacheParts}
	on error
	end try
	-- Legacy cache remains a startup fallback while the observer warms up.
	try
		set cacheText to do shell script "cat /tmp/nagmenu_nowplaying_tab_cache"
		set cacheParts to my split_pipe(cacheText)
		if (count of cacheParts) < 4 then return {}
		return {item 1 of cacheParts, (item 2 of cacheParts as integer), (item 3 of cacheParts as integer), item 4 of cacheParts}
	on error
		return {}
	end try
end read_cached_target

on resolve_safari_target(windowIndex, tabIndex, expectedURL)
	tell application "Safari"
		try
			set candidateWindow to window windowIndex
			set candidateTab to tab tabIndex of candidateWindow
			if URL of candidateTab is expectedURL and my is_youtube_video(URL of candidateTab) then return {candidateWindow, candidateTab}
		end try
		-- Tab indexes are volatile. The URL is the stable identity.
		repeat with candidateWindow in windows
			repeat with candidateTab in tabs of candidateWindow
				try
					if URL of candidateTab is expectedURL and my is_youtube_video(URL of candidateTab) then return {candidateWindow, candidateTab}
				end try
			end repeat
		end repeat
	end tell
	return {}
end resolve_safari_target

on resolve_chrome_target(windowIndex, tabIndex, expectedURL)
	tell application "Google Chrome"
		try
			set candidateWindow to window windowIndex
			set candidateTab to tab tabIndex of candidateWindow
			if URL of candidateTab is expectedURL and my is_youtube_video(URL of candidateTab) then return {candidateWindow, candidateTab}
		end try
		repeat with candidateWindow in windows
			repeat with candidateTab in tabs of candidateWindow
				try
					if URL of candidateTab is expectedURL and my is_youtube_video(URL of candidateTab) then return {candidateWindow, candidateTab}
				end try
			end repeat
		end repeat
	end tell
	return {}
end resolve_chrome_target

on resolve_cached_target()
	set targetParts to my read_cached_target()
	if (count of targetParts) < 4 then return {}
	set browserName to item 1 of targetParts
	set windowIndex to item 2 of targetParts
	set tabIndex to item 3 of targetParts
	set expectedURL to item 4 of targetParts
	if expectedURL is "" then return {}
	if browserName is "Safari" and application "Safari" is running then
		set resolvedTarget to my resolve_safari_target(windowIndex, tabIndex, expectedURL)
	else if browserName is "Google Chrome" and application "Google Chrome" is running then
		set resolvedTarget to my resolve_chrome_target(windowIndex, tabIndex, expectedURL)
	else
		return {}
	end if
	if (count of resolvedTarget) < 2 then return {}
	return {browserName, item 1 of resolvedTarget, item 2 of resolvedTarget}
end resolve_cached_target

on resolve_playing_fallback()
	set playingProbe to "(() => { const v=document.querySelector('video'); return !!(v && !v.paused && !v.ended && v.readyState >= 2); })()"
	if application "Safari" is running then
		tell application "Safari"
			repeat with candidateWindow in windows
				repeat with candidateTab in tabs of candidateWindow
					try
						if my is_youtube_video(URL of candidateTab) and (do JavaScript playingProbe in candidateTab) then return {"Safari", candidateWindow, candidateTab}
					end try
				end repeat
			end repeat
		end tell
	end if
	if application "Google Chrome" is running then
		tell application "Google Chrome"
			repeat with candidateWindow in windows
				repeat with candidateTab in tabs of candidateWindow
					try
						if my is_youtube_video(URL of candidateTab) and (execute candidateTab javascript playingProbe) then return {"Google Chrome", candidateWindow, candidateTab}
					end try
				end repeat
			end repeat
		end tell
	end if
	return {}
end resolve_playing_fallback

on select_target(targetParts)
	set browserName to item 1 of targetParts
	set targetWindow to item 2 of targetParts
	set targetTab to item 3 of targetParts
	if browserName is "Safari" then
		tell application "Safari"
			set current tab of targetWindow to targetTab
			set index of targetWindow to 1
			activate
		end tell
	else
		tell application "Google Chrome"
			set active tab index of targetWindow to index of targetTab
			set index of targetWindow to 1
			activate
		end tell
	end if
end select_target

on javascript_on_target(targetParts, javascriptText)
	set browserName to item 1 of targetParts
	set targetTab to item 3 of targetParts
	if browserName is "Safari" then
		tell application "Safari" to return do JavaScript javascriptText in targetTab
	else
		tell application "Google Chrome" to return execute targetTab javascript javascriptText
	end if
end javascript_on_target

on run argv
	if (count of argv) < 1 then error "Missing YouTube command"
	set commandName to item 1 of argv
	set targetParts to my resolve_cached_target()
	if (count of targetParts) < 3 then set targetParts to my resolve_playing_fallback()
	if (count of targetParts) < 3 then return "No current YouTube video found"

	if commandName is "seek_relative" then
		if (count of argv) < 2 then error "Missing seek distance"
		set seekDistance to (item 2 of argv) as real
		set seekJS to "(() => { const v=document.querySelector('video'); if(!v) return 'no-video'; const next=Math.max(0,Math.min(Number.isFinite(v.duration)?v.duration:Infinity,v.currentTime+(" & seekDistance & "))); v.currentTime=next; return String(next); })()"
		return my javascript_on_target(targetParts, seekJS)
	end if

	-- Change speed on the resolved video element itself. YouTube's keyboard
	-- shortcuts are focus-sensitive in fullscreen, while playbackRate is not.
	if commandName is "slower" or commandName is "faster" then
		if commandName is "slower" then
			set speedDelta to -0.25
		else
			set speedDelta to 0.25
		end if
		set speedJS to "(() => { const v=document.querySelector('video'); if(!v) return 'no-video'; const next=Math.max(0.25,Math.min(2,Math.round((v.playbackRate+(" & speedDelta & "))*4)/4)); v.defaultPlaybackRate=next; v.playbackRate=next; v.dispatchEvent(new Event('ratechange')); return String(next); })()"
		return my javascript_on_target(targetParts, speedJS)
	end if

	-- Click YouTube's own captions control on the resolved tab. Activating the
	-- browser and typing "c" first exits the macOS fullscreen space while the
	-- video itself remains fullscreen, so the shortcut reaches the wrong view.
	-- This preserves fullscreen and still uses YouTube's native caption track.
	if commandName is "captions" then
		set captionsJS to "(() => { const button=document.querySelector('.ytp-subtitles-button'); if(!button) return 'no-caption-button'; button.click(); const player=document.getElementById('movie_player'); if(player && typeof player.isSubtitlesOn==='function') return player.isSubtitlesOn() ? 'captions:on' : 'captions:off'; return button.getAttribute('aria-pressed')==='true' ? 'captions:on' : 'captions:off'; })()"
		return my javascript_on_target(targetParts, captionsJS)
	end if

	set previousApp to ""
	try
		tell application "System Events" to set previousApp to name of first application process whose frontmost is true
	end try
	my select_target(targetParts)
	delay 0.08

	if commandName is "fullscreen" then
		tell application "System Events" to keystroke "f"
	else if commandName is "playpause" then
		tell application "System Events" to keystroke "k"
	else
		error "Unknown YouTube command: " & commandName
	end if

	delay 0.08
	-- Keep a newly-entered fullscreen video visible. For the other commands,
	-- give focus back to the dashboard/app that issued the command.
	if commandName is not "fullscreen" and previousApp is not "" and previousApp is not "Safari" and previousApp is not "Google Chrome" then
		try
			tell application "System Events" to set frontmost of process previousApp to true
		end try
	end if
	return "YouTube " & commandName & " sent"
end run
