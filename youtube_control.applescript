-- Fast YouTube window controls for NagBot/BTT.
-- Modes: home, open, play, surprise. Returns OK|detail or ERROR|detail.

on run argv
	set actionName to "play"
	if (count of argv) > 0 then set actionName to item 1 of argv
	if actionName is "home" then return my open_youtube_home()
	if actionName is "open" then return my open_youtube()
	if actionName is "surprise" then return my surprise_me()
	if actionName is "play_id" and (count of argv) > 1 then return my play_video_id(item 2 of argv)
	if actionName is "pause_all" then return my pause_all_youtube()
	if actionName is "play_target" and (count of argv) > 4 then
		return my play_inventory_target(item 2 of argv, item 3 of argv as integer, item 4 of argv as integer, item 5 of argv)
	end if
	return my play_youtube()
end run

on is_youtube_video(theURL)
	if theURL is missing value then return false
	set u to theURL as text
	return u contains "youtube.com/watch" or u contains "youtube.com/shorts/" or u contains "youtu.be/"
end is_youtube_video

on is_youtube_page(theURL)
	if theURL is missing value then return false
	set u to theURL as text
	return u contains "youtube.com" or u contains "youtu.be"
end is_youtube_page

on is_youtube_home(theURL)
	if theURL is missing value then return false
	set u to theURL as text
	return u is "https://www.youtube.com/" or u starts with "https://www.youtube.com/?"
end is_youtube_home

on split_pipe(theText)
	set oldDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to "|"
	set pieces to text items of theText
	set AppleScript's text item delimiters to oldDelimiters
	return pieces
end split_pipe

on inventory_path()
	return (POSIX path of (path to home folder)) & "NowPlaying/cache/browser-inventory.json"
end inventory_path

on cached_target()
	-- Prefer the atomic inventory maintained by the NowPlaying observer. It is
	-- richer than the compatibility file and updated without blocking commands.
	try
		set cacheText to do shell script "/usr/bin/jq -r 'if (.active.browser // \"\") != \"\" then [.active.browser,.active.window_index,.active.tab_index,.active.url] | join(\"|\") else empty end' " & quoted form of my inventory_path()
		set p to my split_pipe(cacheText)
		if (count of p) ≥ 4 then return {item 1 of p, item 2 of p as integer, item 3 of p as integer, item 4 of p}
	on error
	end try
	-- Compatibility during startup and on older installations.
	try
		set cacheText to do shell script "cat /tmp/nagmenu_nowplaying_tab_cache"
		set p to my split_pipe(cacheText)
		if (count of p) ≥ 4 then return {item 1 of p, item 2 of p as integer, item 3 of p as integer, item 4 of p}
	on error
	end try
	return {}
end cached_target

on pause_competing_media()
	-- Starting a selected YouTube video is an intentional source switch. The
	-- inventory observer records tabs that were playing at its last sample, but
	-- Safari can resume a selected tab after a long idle before that state is
	-- visible in the cache. Pause every browser window's live selected YouTube
	-- tab first, then cover any other playing tabs recorded by the inventory.
	-- This remains fast because JavaScript runs on at most one live tab per
	-- window instead of every tab in a large browser session.
	set pauseJS to "(() => {let count=0;const player=document.getElementById('movie_player');try{if(player&&typeof player.getPlayerState==='function'&&player.getPlayerState()===1&&typeof player.pauseVideo==='function'){player.pauseVideo();count++;}}catch(e){}for(const media of document.querySelectorAll('video,audio')){try{if(!media.paused&&!media.ended){media.pause();count++;}if(media.webkitDisplayingFullscreen&&typeof media.webkitExitFullscreen==='function')media.webkitExitFullscreen();}catch(e){}}try{if(document.fullscreenElement&&document.exitFullscreen)document.exitFullscreen().catch(()=>{});else if(document.webkitFullscreenElement&&document.webkitExitFullscreen)document.webkitExitFullscreen();}catch(e){}return String(count);})()"
	if application "Safari" is running then
		tell application "Safari"
			repeat with candidateWindow in windows
				try
					set candidateTab to current tab of candidateWindow
					if my is_youtube_video(URL of candidateTab) then do JavaScript pauseJS in candidateTab
				on error
				end try
			end repeat
		end tell
	end if
	if application "Google Chrome" is running then
		tell application "Google Chrome"
			repeat with candidateWindow in windows
				try
					set candidateTab to active tab of candidateWindow
					if my is_youtube_video(URL of candidateTab) then execute candidateTab javascript pauseJS
				on error
				end try
			end repeat
		end tell
	end if
	set playingTargets to ""
	try
		set query to "/usr/bin/jq -r '.tabs[] | select((.media_metadata.playing // false)==true) | [.browser,(.window_index|tostring),(.tab_index|tostring),.url] | join(\"|\")' " & quoted form of my inventory_path()
		set playingTargets to do shell script query
	on error
	end try
	if playingTargets is not "" then
		repeat with targetLine in paragraphs of playingTargets
			try
				set fields to my split_pipe(targetLine as text)
				if (count of fields) ≥ 4 then
					set browserName to item 1 of fields
					set windowIndex to item 2 of fields as integer
					set tabIndex to item 3 of fields as integer
					set expectedURL to item 4 of fields
					if browserName is "Safari" and application "Safari" is running then
						tell application "Safari"
							set candidateTab to tab tabIndex of window windowIndex
							if (URL of candidateTab as text) is expectedURL then do JavaScript pauseJS in candidateTab
						end tell
					else if browserName is "Google Chrome" and application "Google Chrome" is running then
						tell application "Google Chrome"
							set candidateTab to tab tabIndex of window windowIndex
							if (URL of candidateTab as text) is expectedURL then execute candidateTab javascript pauseJS
						end tell
					end if
				end if
			on error
				-- A moved/closed source tab is already no longer competing.
			end try
		end repeat
	end if
	try
		tell application "Music" to if player state is playing then pause
	end try
	if application "VLC" is running then
		tell application "VLC"
			try
				if playing then pause
			end try
		end tell
	end if
end pause_competing_media

on pause_all_youtube()
	set pauseJS to "(() => {let count=0;const player=document.getElementById('movie_player');try{if(player&&typeof player.getPlayerState==='function'&&player.getPlayerState()===1&&typeof player.pauseVideo==='function'){player.pauseVideo();count++;}}catch(e){}for(const media of document.querySelectorAll('video,audio')){try{if(!media.paused&&!media.ended){media.pause();count++;}}catch(e){}}return String(count);})()"
	set pausedCount to 0
	if application "Safari" is running then
		tell application "Safari"
			repeat with candidateWindow in windows
				repeat with candidateTab in tabs of candidateWindow
					try
						if my is_youtube_video(URL of candidateTab) then
							set resultText to do JavaScript pauseJS in candidateTab
							set pausedCount to pausedCount + (resultText as integer)
						end if
					on error
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
						if my is_youtube_video(URL of candidateTab) then
							set resultText to execute candidateTab javascript pauseJS
							set pausedCount to pausedCount + (resultText as integer)
						end if
					on error
					end try
				end repeat
			end repeat
		end tell
	end if
	return "OK|paused:" & pausedCount
end pause_all_youtube

on play_inventory_target(browserName, windowIndex, tabIndex, videoID)
	if (length of videoID) is not 11 then return "ERROR|Invalid YouTube video ID"
	if browserName is "Chrome" then set browserName to "Google Chrome"
	try
		if browserName is "Safari" and application "Safari" is running then
			tell application "Safari"
				set liveURL to URL of tab tabIndex of window windowIndex as text
			end tell
			if my url_video_id(liveURL) is videoID then return my play_target(browserName, windowIndex, tabIndex, liveURL)
		else if browserName is "Google Chrome" and application "Google Chrome" is running then
			tell application "Google Chrome"
				set liveURL to URL of tab tabIndex of window windowIndex as text
			end tell
			if my url_video_id(liveURL) is videoID then return my play_target(browserName, windowIndex, tabIndex, liveURL)
		end if
	on error
	end try
	-- Window and tab indexes can move between detection and a controller tap.
	-- Preserve the user's selection by relocating the same stable video ID.
	return my play_video_id(videoID)
end play_inventory_target

on play_target(browserName, windowIndex, tabIndex, expectedURL)
	set playJS to "(() => {const v=[...document.querySelectorAll('video')].find(x=>x.readyState>=2)||document.querySelector('video');if(!v)return 'ERROR|Video is not ready';if(v.ended)v.currentTime=0;v.play().catch(()=>{});return 'OK|'+(document.title||'YouTube');})()"
	try
		-- Pause the source while its fullscreen/tab context is still intact. Doing
		-- this after selecting the destination can leave the old Safari fullscreen
		-- player running behind the newly selected video.
		my pause_competing_media()
		if browserName is "Safari" then
			tell application "Safari"
				set w to window windowIndex
				set t to tab tabIndex of w
				if expectedURL is not "" and URL of t is not expectedURL then
					repeat with candidateWindow in windows
						repeat with candidateTab in tabs of candidateWindow
							if URL of candidateTab is expectedURL then set {w, t} to {candidateWindow, candidateTab}
						end repeat
					end repeat
				end if
				if expectedURL is not "" and URL of t is not expectedURL then return "ERROR|The saved YouTube tab moved"
				if not my is_youtube_video(URL of t) then return "ERROR|The saved YouTube tab is gone"
				set current tab of w to t
				set index of w to 1
				activate
				return do JavaScript playJS in t
			end tell
		else if browserName is "Google Chrome" then
			tell application "Google Chrome"
				set w to window windowIndex
				set t to tab tabIndex of w
				if expectedURL is not "" and URL of t is not expectedURL then
					repeat with candidateWindow in windows
						repeat with candidateTab in tabs of candidateWindow
							if URL of candidateTab is expectedURL then set {w, t} to {candidateWindow, candidateTab}
						end repeat
					end repeat
				end if
				if expectedURL is not "" and URL of t is not expectedURL then return "ERROR|The saved YouTube tab moved"
				if not my is_youtube_video(URL of t) then return "ERROR|The saved YouTube tab is gone"
				set active tab index of w to index of t
				set index of w to 1
				activate
				return execute t javascript playJS
			end tell
		end if
	on error errorText
		return "ERROR|" & errorText
	end try
	return "ERROR|No supported browser"
end play_target

on play_youtube()
	-- The NowPlaying cache is the cheapest and most accurate last-played target.
	set cached to my cached_target()
	if (count of cached) is 4 then
		set cachedResult to my play_target(item 1 of cached, item 2 of cached, item 3 of cached, item 4 of cached)
		if cachedResult starts with "OK|" then return cachedResult
	end if

	-- Fall back to the most recently active YouTube tab. If no tab has playback
	-- history, select the first tab in the window containing the largest queue.
	set probeJS to "(() => {const v=document.querySelector('video');const last=window.__nagmenuPlayback;const rank=v?(!v.paused&&!v.ended?3:(v.currentTime>0||v.ended?2:1)):1;return rank+'|'+(last&&last.url===location.href?Number(last.at)||0:0);})()"
	set bestBrowser to ""
	set bestWindow to 0
	set bestTab to 0
	set bestRank to 0
	set bestTime to 0
	set queueBrowser to ""
	set queueWindow to 0
	set queueTab to 0
	set queueCount to 0

	if application "Safari" is running then
		tell application "Safari"
			repeat with wi from 1 to count of windows
				set thisCount to 0
				set firstTab to 0
				repeat with ti from 1 to count of tabs of window wi
					try
						set t to tab ti of window wi
						if my is_youtube_video(URL of t) then
							set thisCount to thisCount + 1
							if firstTab is 0 then set firstTab to ti
							set fields to my split_pipe(do JavaScript probeJS in t)
							set r to item 1 of fields as integer
							set stamp to item 2 of fields as real
							if r > bestRank or (r = bestRank and stamp > bestTime) then
								set {bestBrowser, bestWindow, bestTab, bestRank, bestTime} to {"Safari", wi, ti, r, stamp}
							end if
						end if
					end try
				end repeat
				if thisCount > queueCount then set {queueBrowser, queueWindow, queueTab, queueCount} to {"Safari", wi, firstTab, thisCount}
			end repeat
		end tell
	end if

	if application "Google Chrome" is running then
		tell application "Google Chrome"
			repeat with wi from 1 to count of windows
				set thisCount to 0
				set firstTab to 0
				repeat with ti from 1 to count of tabs of window wi
					try
						set t to tab ti of window wi
						if my is_youtube_video(URL of t) then
							set thisCount to thisCount + 1
							if firstTab is 0 then set firstTab to ti
							set fields to my split_pipe(execute t javascript probeJS)
							set r to item 1 of fields as integer
							set stamp to item 2 of fields as real
							if r > bestRank or (r = bestRank and stamp > bestTime) then
								set {bestBrowser, bestWindow, bestTab, bestRank, bestTime} to {"Google Chrome", wi, ti, r, stamp}
							end if
						end if
					end try
				end repeat
				if thisCount > queueCount then set {queueBrowser, queueWindow, queueTab, queueCount} to {"Google Chrome", wi, firstTab, thisCount}
			end repeat
		end tell
	end if

	if bestRank > 1 then return my play_target(bestBrowser, bestWindow, bestTab, "")
	if queueCount > 0 then return my play_target(queueBrowser, queueWindow, queueTab, "")
	return "ERROR|No YouTube video tabs are open"
end play_youtube

on play_video_id(videoID)
	if videoID is "" then return "ERROR|Missing YouTube video ID"
	set cachedResult to ""
	try
		set query to "/usr/bin/jq -r --arg id " & quoted form of videoID & " '.tabs[] | select(.is_youtube_video==true and (.url | contains($id))) | [.browser,.window_index,.tab_index,.url] | join(\"|\")' " & quoted form of my inventory_path() & " | /usr/bin/head -n 1"
		set cacheText to do shell script query
		set p to my split_pipe(cacheText)
		if (count of p) ≥ 4 then
			set cachedResult to my play_target(item 1 of p, item 2 of p as integer, item 3 of p as integer, item 4 of p)
			if cachedResult starts with "OK|" then return cachedResult
		end if
	on error
	end try

	-- Window and tab indices are only hints. Safari can renumber them whenever a
	-- tab or window closes, while the queue still contains a perfectly valid
	-- video ID. Recover against the live browser before rejecting the press.
	if application "Safari" is running then
		tell application "Safari"
			repeat with wi from 1 to count of windows
				repeat with ti from 1 to count of tabs of window wi
					try
						set liveURL to URL of tab ti of window wi as text
						if my is_youtube_video(liveURL) and liveURL contains videoID then return my play_target("Safari", wi, ti, liveURL)
					end try
				end repeat
			end repeat
		end tell
	end if
	if application "Google Chrome" is running then
		tell application "Google Chrome"
			repeat with wi from 1 to count of windows
				repeat with ti from 1 to count of tabs of window wi
					try
						set liveURL to URL of tab ti of window wi as text
						if my is_youtube_video(liveURL) and liveURL contains videoID then return my play_target("Google Chrome", wi, ti, liveURL)
					end try
				end repeat
			end repeat
		end tell
	end if
	if cachedResult starts with "ERROR|" then return cachedResult
	return "ERROR|That queued video is no longer open"
end play_video_id

on open_youtube()
	set bestBrowser to ""
	set bestWindow to 0
	set bestTab to 0
	set bestCount to 0
	if application "Safari" is running then
		tell application "Safari"
			repeat with wi from 1 to count of windows
				set c to 0
				set firstTab to 0
				repeat with ti from 1 to count of tabs of window wi
					if my is_youtube_page(URL of tab ti of window wi) then
						set c to c + 1
						if firstTab is 0 then set firstTab to ti
					end if
				end repeat
				if c > bestCount then set {bestBrowser, bestWindow, bestTab, bestCount} to {"Safari", wi, firstTab, c}
			end repeat
		end tell
	end if
	if application "Google Chrome" is running then
		tell application "Google Chrome"
			repeat with wi from 1 to count of windows
				set c to 0
				set firstTab to 0
				repeat with ti from 1 to count of tabs of window wi
					if my is_youtube_page(URL of tab ti of window wi) then
						set c to c + 1
						if firstTab is 0 then set firstTab to ti
					end if
				end repeat
				if c > bestCount then set {bestBrowser, bestWindow, bestTab, bestCount} to {"Google Chrome", wi, firstTab, c}
			end repeat
		end tell
	end if
	if bestCount > 0 then
		if bestBrowser is "Safari" then
			tell application "Safari"
				set current tab of window bestWindow to tab bestTab of window bestWindow
				set index of window bestWindow to 1
				activate
			end tell
		else
			tell application "Google Chrome"
				set active tab index of window bestWindow to bestTab
				set index of window bestWindow to 1
				activate
			end tell
		end if
		return "OK|Opened the largest YouTube window"
	end if
	tell application "Safari"
		make new document with properties {URL:"https://www.youtube.com/"}
		activate
	end tell
	return "OK|Opened YouTube"
end open_youtube

on open_youtube_home()
	if application "Safari" is running then
		tell application "Safari"
			repeat with wi from 1 to count of windows
				repeat with ti from 1 to count of tabs of window wi
					if my is_youtube_home(URL of tab ti of window wi) then
						set current tab of window wi to tab ti of window wi
						set index of window wi to 1
						activate
						return "OK|Opened YouTube Home"
					end if
				end repeat
			end repeat
		end tell
	end if
	if application "Google Chrome" is running then
		tell application "Google Chrome"
			repeat with wi from 1 to count of windows
				repeat with ti from 1 to count of tabs of window wi
					if my is_youtube_home(URL of tab ti of window wi) then
						set active tab index of window wi to ti
						set index of window wi to 1
						activate
						return "OK|Opened YouTube Home"
					end if
				end repeat
			end repeat
		end tell
	end if
	tell application "Safari"
		make new document with properties {URL:"https://www.youtube.com/"}
		activate
	end tell
	return "OK|Opened YouTube Home"
end open_youtube_home

on surprise_me()
	set targetWindow to 0
	set targetTab to 0
	if application "Safari" is running then
		tell application "Safari"
			repeat with wi from 1 to count of windows
				repeat with ti from 1 to count of tabs of window wi
					if my is_youtube_home(URL of tab ti of window wi) then
						set {targetWindow, targetTab} to {wi, ti}
						exit repeat
					end if
				end repeat
				if targetWindow > 0 then exit repeat
			end repeat
			if targetWindow is 0 then
				make new document with properties {URL:"https://www.youtube.com/"}
				set {targetWindow, targetTab} to {1, 1}
			end if
			set w to window targetWindow
			set t to tab targetTab of w
			set current tab of w to t
			set index of w to 1
			activate
			set recommendationJS to "(() => {const selectors=['a.ytLockupViewModelContentImage[href*=\"/watch\"]','ytd-rich-item-renderer:not([is-ad]) a[href*=\"/watch\"]','ytd-rich-item-renderer a[href*=\"/watch\"]','a[href*=\"/watch\"]'];for(const s of selectors){const a=[...document.querySelectorAll(s)].find(x=>x.href&&!x.closest('ytd-ad-slot-renderer,ytm-promoted-sparkles-web-renderer')&&!x.href.includes('/watch?list='));if(a)return a.href;}return '';})()"
			repeat 24 times
				try
					set destination to do JavaScript recommendationJS in t
					if destination is not "" then
						set URL of t to destination
						my pause_competing_media()
						repeat 24 times
							delay 0.25
							set playResult to do JavaScript "(() => {const v=document.querySelector('video');if(!v)return '';v.play().catch(()=>{});return 'OK|'+(document.title||'YouTube surprise');})()" in t
							if playResult starts with "OK|" then return playResult
						end repeat
						return "ERROR|The surprise video did not become ready"
					end if
				end try
				delay 0.25
			end repeat
		end tell
	end if
	return "ERROR|No YouTube recommendation was available"
end surprise_me
