-- Lightweight browser inventory for the NowPlaying cache. YouTube video tabs
-- also expose their already-loaded channel and duration so small controllers
-- can render useful queue cards without downloading artwork.

on escape_json(valueText)
	set s to valueText as text
	set s to my replace_text("\\", "\\\\", s)
	set s to my replace_text("\"", "\\\"", s)
	set s to my replace_text(return, "\\r", s)
	set s to my replace_text(linefeed, "\\n", s)
	set s to my replace_text(tab, "\\t", s)
	return s
end escape_json

on replace_text(findText, replacementText, sourceText)
	set oldDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to findText
	set pieces to text items of sourceText
	set AppleScript's text item delimiters to replacementText
	set joined to pieces as text
	set AppleScript's text item delimiters to oldDelimiters
	return joined
end replace_text

on is_youtube_page(theURL)
	if theURL is missing value then return false
	set u to theURL as text
	return u contains "youtube.com" or u contains "youtu.be"
end is_youtube_page

on is_youtube_video(theURL)
	if theURL is missing value then return false
	set u to theURL as text
	return u contains "youtube.com/watch" or u contains "youtube.com/shorts/" or u contains "youtu.be/"
end is_youtube_video

on is_media_page(theURL)
	if theURL is missing value then return false
	set u to theURL as text
	if u contains "home-assistant" or u contains "homeassistant" or u contains ":8123" then return false
	set mediaHosts to {"youtube.com", "youtu.be", "netflix.com", "hulu.com", "disneyplus.com", "max.com", "hbomax.com", "primevideo.com", "tv.apple.com", "peacocktv.com", "paramountplus.com", "twitch.tv", "vimeo.com", "dailymotion.com", "crunchyroll.com", "tubi.tv", "pluto.tv", "spotify.com", "music.apple.com", "music.amazon.com", "soundcloud.com", "pandora.com", "tidal.com", "deezer.com", "bandcamp.com", "app.plex.tv"}
	repeat with mediaHost in mediaHosts
		if u contains (mediaHost as text) then return true
	end repeat
	return false
end is_media_page

on tab_json(browserName, windowID, windowIndex, tabIndex, tabURL, tabTitle, selectedTab, mediaMetadata)
	set youtubePage to my is_youtube_page(tabURL)
	set youtubeVideo to my is_youtube_video(tabURL)
	set mediaPage to my is_media_page(tabURL)
	if not youtubePage and not mediaPage then return ""
	return "{\"browser\":\"" & browserName & "\",\"window_id\":" & windowID & ",\"window_index\":" & windowIndex & ",\"tab_index\":" & tabIndex & ",\"url\":\"" & my escape_json(tabURL) & "\",\"title\":\"" & my escape_json(tabTitle) & "\",\"selected\":" & selectedTab & ",\"is_youtube_page\":" & youtubePage & ",\"is_youtube_video\":" & youtubeVideo & ",\"is_media_page\":" & mediaPage & ",\"media_metadata\":" & mediaMetadata & "}"
end tab_json

set youtubeMetadataScript to "(()=>{const d=window.ytInitialPlayerResponse?.videoDetails||{};const v=document.querySelector('video');const a=(document.querySelector('#owner #channel-name a,ytd-channel-name a,#channel-name a')?.textContent||d.author||'').trim();const n=Number(v?.duration||d.lengthSeconds||0);return JSON.stringify({author:a,duration_sec:Number.isFinite(n)?Math.round(n):0})})()"

set entries to {}

if application "Safari" is running then
	tell application "Safari"
		repeat with wi from 1 to count of windows
			set w to window wi
			set wid to id of w
			set selectedIndex to 0
			try
				set selectedURL to URL of current tab of w
				repeat with candidateIndex from 1 to count of tabs of w
					if URL of tab candidateIndex of w is selectedURL then
						set selectedIndex to candidateIndex
						exit repeat
					end if
				end repeat
			end try
			repeat with ti from 1 to count of tabs of w
				try
					set t to tab ti of w
					set mediaMetadata to "{}"
					if my is_youtube_video(URL of t) then
						try
							set mediaMetadata to do JavaScript youtubeMetadataScript in t
						end try
					end if
					set rowJSON to my tab_json("Safari", wid, wi, ti, URL of t, name of t, ti is selectedIndex, mediaMetadata)
					if rowJSON is not "" then set end of entries to rowJSON
				end try
			end repeat
		end repeat
	end tell
end if

if application "Google Chrome" is running then
	tell application "Google Chrome"
		repeat with wi from 1 to count of windows
			set w to window wi
			set wid to id of w
			set selectedIndex to active tab index of w
			repeat with ti from 1 to count of tabs of w
				try
					set t to tab ti of w
					set mediaMetadata to "{}"
					if my is_youtube_video(URL of t) then
						try
							set mediaMetadata to execute t javascript youtubeMetadataScript
						end try
					end if
					set rowJSON to my tab_json("Google Chrome", wid, wi, ti, URL of t, title of t, ti is selectedIndex, mediaMetadata)
					if rowJSON is not "" then set end of entries to rowJSON
				end try
			end repeat
		end repeat
	end tell
end if

set oldDelimiters to AppleScript's text item delimiters
set AppleScript's text item delimiters to ","
set payload to entries as text
set AppleScript's text item delimiters to oldDelimiters
return "[" & payload & "]"
