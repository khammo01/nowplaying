on escape_json(s)
	if s is missing value then return ""
	set s to s as string
	set s to my replace_chars(s, "\\", "\\\\")
	set s to my replace_chars(s, "\"", "\\\"")
	set s to my replace_chars(s, return, "")
	set s to my replace_chars(s, linefeed, "")
	return s
end escape_json


on replace_chars(this_text, search_string, replacement_string)
	set oldTID to AppleScript's text item delimiters
	set AppleScript's text item delimiters to search_string
	set item_list to every text item of this_text
	set AppleScript's text item delimiters to replacement_string
	set this_text to item_list as string
	set AppleScript's text item delimiters to oldTID
	return this_text
end replace_chars


on split_pipe(s)
	set oldTID to AppleScript's text item delimiters
	set AppleScript's text item delimiters to "|"
	set parts to text items of s
	set AppleScript's text item delimiters to oldTID
	return parts
end split_pipe


on read_nowplaying_cache()
	set cacheFile to "/tmp/nagmenu_nowplaying_tab_cache"

	try
		set cacheData to do shell script "cat " & quoted form of cacheFile
		if cacheData is "" then return {}
		return my split_pipe(cacheData)
	on error
		return {}
	end try
end read_nowplaying_cache


on write_nowplaying_cache(browserName, windowIndex, tabIndex)
	set cacheFile to "/tmp/nagmenu_nowplaying_tab_cache"
	set cacheData to browserName & "|" & windowIndex & "|" & tabIndex

	try
		do shell script "printf %s " & quoted form of cacheData & " > " & quoted form of cacheFile
	end try
end write_nowplaying_cache


on clear_nowplaying_cache()
	try
		do shell script "rm -f /tmp/nagmenu_nowplaying_tab_cache"
	end try
end clear_nowplaying_cache


with timeout of 12 seconds

	-- ============================================================
	-- WHICH BROWSER IS FRONTMOST?
	-- ============================================================

	set frontApp to ""

	try
		tell application "System Events"
			set frontApp to name of first application process whose frontmost is true
		end tell
	end try


	set safariRunning to false
	set chromeRunning to false

	try
		set safariRunning to application "Safari" is running
	end try

	try
		set chromeRunning to application "Google Chrome" is running
	end try


	-- ============================================================
	-- TAB PLAYBACK PROBE
	-- ============================================================

	set probeJS to "(() => {" & linefeed & ¬
		"try {" & linefeed & ¬
		" const host=(location.hostname||'').toLowerCase();" & linefeed & ¬
		" // Only dedicated media hosts may suppress voice notifications." & linefeed & ¬
		" // Keep this policy identical in the probe and metadata paths." & linefeed & ¬
		" const mediaHosts=[" & linefeed & ¬
		"   'youtube.com','youtu.be','netflix.com','hulu.com','disneyplus.com'," & linefeed & ¬
		"   'max.com','hbomax.com','primevideo.com','tv.apple.com'," & linefeed & ¬
		"   'peacocktv.com','paramountplus.com','twitch.tv','vimeo.com'," & linefeed & ¬
		"   'dailymotion.com','crunchyroll.com','tubi.tv','pluto.tv'," & linefeed & ¬
		"   'spotify.com','music.apple.com','music.amazon.com'," & linefeed & ¬
		"   'soundcloud.com','pandora.com','tidal.com','deezer.com'," & linefeed & ¬
		"   'bandcamp.com','app.plex.tv'" & linefeed & ¬
		" ];" & linefeed & ¬
		" const blockedSite=!mediaHosts.some(domain=>host===domain||host.endsWith('.'+domain));" & linefeed & ¬
		"" & linefeed & ¬
		" if(blockedSite)" & linefeed & ¬
		"   return '0|0|0|0|0|0|0|0|null';" & linefeed & ¬
		"" & linefeed & ¬
		" const isYT=" & linefeed & ¬
		"   /(^|\\.)youtube\\.com$/.test(host)||" & linefeed & ¬
		"   /(^|\\.)youtu\\.be$/.test(host);" & linefeed & ¬
		"" & linefeed & ¬
		" if(isYT && Array.from(document.querySelectorAll('video')).some(v=>!v.paused&&!v.ended&&v.readyState>=2))" & linefeed & ¬
		"   window.__nagmenuPlayback={url:location.href,at:Date.now()};" & linefeed & ¬
		" const ytHomepage=" & linefeed & ¬
		"   /(^|\\.)youtube\\.com$/.test(host)&&" & linefeed & ¬
		"   location.pathname==='/';" & linefeed & ¬
		"" & linefeed & ¬
		" const docs=[];" & linefeed & ¬
		" const seen=new Set();" & linefeed & ¬
		"" & linefeed & ¬
		" function collectDocs(d){" & linefeed & ¬
		"   if(!d||seen.has(d))return;" & linefeed & ¬
		"   seen.add(d);" & linefeed & ¬
		"   docs.push(d);" & linefeed & ¬
		"" & linefeed & ¬
		"   let frames=[];" & linefeed & ¬
		"   try {frames=[...d.querySelectorAll('iframe,frame')];} catch(e) {}" & linefeed & ¬
		"" & linefeed & ¬
		"   for(const f of frames){" & linefeed & ¬
		"     try {" & linefeed & ¬
		"       if(f.contentDocument)collectDocs(f.contentDocument);" & linefeed & ¬
		"     } catch(e) {}" & linefeed & ¬
		"   }" & linefeed & ¬
		" }" & linefeed & ¬
		"" & linefeed & ¬
		" collectDocs(document);" & linefeed & ¬
		"" & linefeed & ¬
		" const allMedia=[];" & linefeed & ¬
		" for(const d of docs){" & linefeed & ¬
		"   try {allMedia.push(...d.querySelectorAll('video,audio'));} catch(e) {}" & linefeed & ¬
		" }" & linefeed & ¬
		"" & linefeed & ¬
		" const media=allMedia;" & linefeed & ¬
		"" & linefeed & ¬
		" const htmlPlaying=media.some(m=>" & linefeed & ¬
		"   !m.paused&&" & linefeed & ¬
		"   !m.ended&&" & linefeed & ¬
		"   m.readyState>=2" & linefeed & ¬
		" );" & linefeed & ¬
		"" & linefeed & ¬
		" const mp=isYT" & linefeed & ¬
		"   ? document.getElementById('movie_player')" & linefeed & ¬
		"   : null;" & linefeed & ¬
		"" & linefeed & ¬
		" const ps=" & linefeed & ¬
		"   (mp&&typeof mp.getPlayerState==='function')" & linefeed & ¬
		"     ? mp.getPlayerState()" & linefeed & ¬
		"     : null;" & linefeed & ¬
		"" & linefeed & ¬
		" const ms=navigator.mediaSession||null;" & linefeed & ¬
		" const msPlaying=!!ms&&ms.playbackState==='playing';" & linefeed & ¬
		"" & linefeed & ¬
		" const playing=" & linefeed & ¬
		"   ytHomepage" & linefeed & ¬
		"     ? false" & linefeed & ¬
		"     : isYT" & linefeed & ¬
		"       ? ((ps===1)||htmlPlaying)" & linefeed & ¬
		"       : (htmlPlaying||msPlaying);" & linefeed & ¬
		"" & linefeed & ¬
		" let fullscreen=false;" & linefeed & ¬
		" let pip=false;" & linefeed & ¬
		"" & linefeed & ¬
		" for(const d of docs){" & linefeed & ¬
		"   try {" & linefeed & ¬
		"     if(d.fullscreenElement||d.webkitFullscreenElement)" & linefeed & ¬
		"       fullscreen=true;" & linefeed & ¬
		"     if(d.pictureInPictureElement||d.webkitPictureInPictureElement)" & linefeed & ¬
		"       pip=true;" & linefeed & ¬
		"   } catch(e) {}" & linefeed & ¬
		" }" & linefeed & ¬
		"" & linefeed & ¬
		" if(media.some(m=>" & linefeed & ¬
		"   m.webkitDisplayingFullscreen||" & linefeed & ¬
		"   m.webkitPresentationMode==='fullscreen'" & linefeed & ¬
		" )) fullscreen=true;" & linefeed & ¬
		"" & linefeed & ¬
		" if(media.some(m=>" & linefeed & ¬
		"   m.webkitPresentationMode==='picture-in-picture'" & linefeed & ¬
		" )) pip=true;" & linefeed & ¬
		"" & linefeed & ¬
		" const focused=document.hasFocus();" & linefeed & ¬
		" const visible=document.visibilityState==='visible';" & linefeed & ¬
		"" & linefeed & ¬
		" let score=0;" & linefeed & ¬
		"" & linefeed & ¬
		" if(playing){" & linefeed & ¬
		"   if(fullscreen&&((ps===1)||htmlPlaying))" & linefeed & ¬
		"     score=1200;" & linefeed & ¬
		"   else if(pip&&((ps===1)||htmlPlaying))" & linefeed & ¬
		"     score=1100;" & linefeed & ¬
		"   else if((ps===1)||htmlPlaying){" & linefeed & ¬
		"     if(focused)score=700;" & linefeed & ¬
		"     else if(visible)score=500;" & linefeed & ¬
		"     else score=300;" & linefeed & ¬
		"   }" & linefeed & ¬
		"   else if(msPlaying){" & linefeed & ¬
		"     if(focused)score=160;" & linefeed & ¬
		"     else if(visible)score=120;" & linefeed & ¬
		"     else score=80;" & linefeed & ¬
		"   }" & linefeed & ¬
		" }" & linefeed & ¬
		"" & linefeed & ¬
		" return [" & linefeed & ¬
		"   score," & linefeed & ¬
		"   playing?1:0," & linefeed & ¬
		"   fullscreen?1:0," & linefeed & ¬
		"   pip?1:0," & linefeed & ¬
		"   focused?1:0," & linefeed & ¬
		"   visible?1:0," & linefeed & ¬
		"   htmlPlaying?1:0," & linefeed & ¬
		"   msPlaying?1:0," & linefeed & ¬
		"   ps===null?'null':ps" & linefeed & ¬
		" ].join('|');" & linefeed & ¬
		"" & linefeed & ¬
		"} catch(e){" & linefeed & ¬
		" return '0|0|0|0|0|0|0|0|null';" & linefeed & ¬
		"}" & linefeed & ¬
		"})()"


	-- ============================================================
	-- GLOBAL WINNER
	-- ============================================================

	set selectedBrowser to ""
	set selectedWindowIndex to 0
	set selectedTabIndex to 0
	set selectedScore to 0


	-- ============================================================
	-- FAST PATH 1: PREVIOUS WINNER
	-- ============================================================

	set cachedParts to my read_nowplaying_cache()

	if (count of cachedParts) ≥ 3 then

		try
			set cachedBrowser to item 1 of cachedParts
			set cachedWindowIndex to item 2 of cachedParts as integer
			set cachedTabIndex to item 3 of cachedParts as integer
		on error
			set cachedBrowser to ""
			set cachedWindowIndex to 0
			set cachedTabIndex to 0
		end try


		if cachedBrowser is "Safari" and safariRunning then

			try
				tell application "Safari"

					if cachedWindowIndex ≤ (count of windows) then

						set cachedWindow to window cachedWindowIndex

						if cachedTabIndex ≤ (count of tabs of cachedWindow) then

							set cachedTab to tab cachedTabIndex of cachedWindow
							set cachedURL to ""

							try
								set cachedURL to URL of cachedTab
							end try

							if cachedURL starts with "http://" or cachedURL starts with "https://" then

								set probeResult to do JavaScript probeJS in cachedTab
								set probeParts to my split_pipe(probeResult)

								try
									set candidateScore to item 1 of probeParts as integer
								on error
									set candidateScore to 0
								end try

								if candidateScore > 0 then

									if frontApp is "Safari" then
										set candidateScore to candidateScore + 2
									end if

									set selectedScore to candidateScore
									set selectedBrowser to "Safari"
									set selectedWindowIndex to cachedWindowIndex
									set selectedTabIndex to cachedTabIndex

								end if

							end if

						end if

					end if

				end tell
			end try

		end if


		if selectedBrowser is "" and cachedBrowser is "Google Chrome" and chromeRunning then

			try
				tell application "Google Chrome"

					if cachedWindowIndex ≤ (count of windows) then

						set cachedWindow to window cachedWindowIndex

						if cachedTabIndex ≤ (count of tabs of cachedWindow) then

							set cachedTab to tab cachedTabIndex of cachedWindow
							set cachedURL to ""

							try
								set cachedURL to URL of cachedTab
							end try

							if cachedURL starts with "http://" or cachedURL starts with "https://" then

								set probeResult to execute cachedTab javascript probeJS
								set probeParts to my split_pipe(probeResult)

								try
									set candidateScore to item 1 of probeParts as integer
								on error
									set candidateScore to 0
								end try

								if candidateScore > 0 then

									if frontApp is "Google Chrome" then
										set candidateScore to candidateScore + 2
									end if

									set selectedScore to candidateScore
									set selectedBrowser to "Google Chrome"
									set selectedWindowIndex to cachedWindowIndex
									set selectedTabIndex to cachedTabIndex

								end if

							end if

						end if

					end if

				end tell
			end try

		end if

	end if


	-- ============================================================
	-- FAST PATH 2: CURRENT TAB OF FRONTMOST BROWSER
	-- ============================================================

	if selectedBrowser is "" then

		if frontApp is "Safari" and safariRunning then

			try
				tell application "Safari"

					if (count of windows) > 0 then

						set w to front window
						set currentTab to current tab of w
						set currentURL to ""

						try
							set currentURL to URL of currentTab
						end try

						if currentURL starts with "http://" or currentURL starts with "https://" then

							set probeResult to do JavaScript probeJS in currentTab
							set probeParts to my split_pipe(probeResult)

							try
								set candidateScore to item 1 of probeParts as integer
							on error
								set candidateScore to 0
							end try

							if candidateScore > 0 then

								set candidateScore to candidateScore + 2
								set currentTabIndex to 0
								set tabCount to count of tabs of w

								repeat with ti from 1 to tabCount
									try
										if URL of tab ti of w is currentURL then
											set currentTabIndex to ti
											exit repeat
										end if
									end try
								end repeat

								if currentTabIndex > 0 then
									set selectedScore to candidateScore
									set selectedBrowser to "Safari"
									set selectedWindowIndex to 1
									set selectedTabIndex to currentTabIndex
								end if

							end if

						end if

					end if

				end tell
			end try

		end if


		if selectedBrowser is "" and frontApp is "Google Chrome" and chromeRunning then

			try
				tell application "Google Chrome"

					if (count of windows) > 0 then

						set w to front window
						set currentTabIndex to active tab index of w
						set currentTab to tab currentTabIndex of w
						set currentURL to ""

						try
							set currentURL to URL of currentTab
						end try

						if currentURL starts with "http://" or currentURL starts with "https://" then

							set probeResult to execute currentTab javascript probeJS
							set probeParts to my split_pipe(probeResult)

							try
								set candidateScore to item 1 of probeParts as integer
							on error
								set candidateScore to 0
							end try

							if candidateScore > 0 then
								set candidateScore to candidateScore + 2

								set selectedScore to candidateScore
								set selectedBrowser to "Google Chrome"
								set selectedWindowIndex to 1
								set selectedTabIndex to currentTabIndex
							end if

						end if

					end if

				end tell
			end try

		end if

	end if


	-- ============================================================
	-- SLOW PATH: SAFARI DISCOVERY
	-- ============================================================

	if selectedBrowser is "" and safariRunning then

		try
			tell application "Safari"

				set windowCount to count of windows

				repeat with wi from 1 to windowCount

					try
						set w to window wi
						set tabCount to count of tabs of w

						repeat with ti from 1 to tabCount

							try
								set t to tab ti of w
								set candidateURL to ""

								try
									set candidateURL to URL of t
								end try

								if candidateURL starts with "http://" or candidateURL starts with "https://" then

									set probeResult to ""

									try
										set probeResult to do JavaScript probeJS in t
									end try

									if probeResult is not missing value and probeResult is not "" then

										set probeParts to my split_pipe(probeResult)

										try
											set candidateScore to item 1 of probeParts as integer
										on error
											set candidateScore to 0
										end try

										if candidateScore > 0 and frontApp is "Safari" then
											set candidateScore to candidateScore + 2
										end if

										if candidateScore > selectedScore then
											set selectedScore to candidateScore
											set selectedBrowser to "Safari"
											set selectedWindowIndex to wi
											set selectedTabIndex to ti
										end if

									end if

								end if

							end try

						end repeat

					end try

				end repeat

			end tell

		end try

	end if


	-- ============================================================
	-- SLOW PATH: CHROME DISCOVERY
	-- ============================================================

	if selectedBrowser is "" and chromeRunning then

		try
			tell application "Google Chrome"

				set windowCount to count of windows

				repeat with wi from 1 to windowCount

					try
						set w to window wi
						set tabCount to count of tabs of w

						repeat with ti from 1 to tabCount

							try
								set t to tab ti of w
								set candidateURL to ""

								try
									set candidateURL to URL of t
								end try

								if candidateURL starts with "http://" or candidateURL starts with "https://" then

									set probeResult to ""

									try
										set probeResult to execute t javascript probeJS
									end try

									if probeResult is not missing value and probeResult is not "" then

										set probeParts to my split_pipe(probeResult)

										try
											set candidateScore to item 1 of probeParts as integer
										on error
											set candidateScore to 0
										end try

										if candidateScore > 0 and frontApp is "Google Chrome" then
											set candidateScore to candidateScore + 2
										end if

										if candidateScore > selectedScore then
											set selectedScore to candidateScore
											set selectedBrowser to "Google Chrome"
											set selectedWindowIndex to wi
											set selectedTabIndex to ti
										end if

									end if

								end if

							end try

						end repeat

					end try

				end repeat

			end tell

		end try

	end if


	if selectedScore > 0 and selectedBrowser is not "" then
		my write_nowplaying_cache(selectedBrowser, selectedWindowIndex, selectedTabIndex)
	else
		my clear_nowplaying_cache()
	end if


	-- ============================================================
	-- FALLBACK WHEN NOTHING IS PLAYING
	-- ============================================================

	if selectedBrowser is "" then

		if frontApp is "Google Chrome" and chromeRunning then

			try
				tell application "Google Chrome"
					if (count of windows) > 0 then
						set selectedBrowser to "Google Chrome"
						set selectedWindowIndex to 1
						set selectedTabIndex to active tab index of front window
					end if
				end tell
			end try

		else if frontApp is "Safari" and safariRunning then

			try
				tell application "Safari"
					if (count of windows) > 0 then
						set selectedBrowser to "Safari"
						set selectedWindowIndex to 1

						set currentURL to ""

						try
							set currentURL to URL of current tab of front window
						end try

						set tabCount to count of tabs of front window

						repeat with ti from 1 to tabCount
							try
								if URL of tab ti of front window is currentURL then
									set selectedTabIndex to ti
									exit repeat
								end if
							end try
						end repeat

						if selectedTabIndex = 0 then set selectedTabIndex to 1
					end if
				end tell
			end try

		else if safariRunning then

			try
				tell application "Safari"
					if (count of windows) > 0 then
						set selectedBrowser to "Safari"
						set selectedWindowIndex to 1

						set currentURL to ""

						try
							set currentURL to URL of current tab of front window
						end try

						set tabCount to count of tabs of front window

						repeat with ti from 1 to tabCount
							try
								if URL of tab ti of front window is currentURL then
									set selectedTabIndex to ti
									exit repeat
								end if
							end try
						end repeat

						if selectedTabIndex = 0 then set selectedTabIndex to 1
					end if
				end tell
			end try

		else if chromeRunning then

			try
				tell application "Google Chrome"
					if (count of windows) > 0 then
						set selectedBrowser to "Google Chrome"
						set selectedWindowIndex to 1
						set selectedTabIndex to active tab index of front window
					end if
				end tell
			end try

		end if

	end if


	if selectedBrowser is "" or selectedWindowIndex = 0 or selectedTabIndex = 0 then
		return "{\"playing\":false}"
	end if


	-- ============================================================
	-- FULL MEDIA METADATA
	--
	-- SHORTS AUTHORITATIVE SOURCES:
	--
	-- video_id:
	--     current URL
	--
	-- title/channel/artwork:
	--     MediaSession
	--
	-- currentTime/duration/playbackRate:
	--     actual visible playing HTML video
	--
	-- description:
	--     current DOM/current matching player data only
	--
	-- ytInitialPlayerResponse and generic page meta are NOT trusted
	-- for Shorts unless explicitly tied to current video.
	-- ============================================================

	set js to "(() => {" & linefeed & ¬
		"try {" & linefeed & ¬
		" const url=location.href||'';" & linefeed & ¬
		" const host=(location.hostname||'').toLowerCase();" & linefeed & ¬
		"" & linefeed & ¬
		" const emptyResult=()=>JSON.stringify({" & linefeed & ¬
		"   playing:false," & linefeed & ¬
		"   url," & linefeed & ¬
		"   video_id:''," & linefeed & ¬
		"   title:''," & linefeed & ¬
		"   channel:''," & linefeed & ¬
		"   description:''," & linefeed & ¬
		"   currentTime:0," & linefeed & ¬
		"   duration:0," & linefeed & ¬
		"   playbackRate:1," & linefeed & ¬
		"   thumbnail:''," & linefeed & ¬
		"   fullscreenish:false," & linefeed & ¬
		"   playerState:null," & linefeed & ¬
		"   youtubePlayingMode:false," & linefeed & ¬
		"   youtubePausedMode:false," & linefeed & ¬
		"   mediaSessionPlaying:false," & linefeed & ¬
		"   isShorts:false" & linefeed & ¬
		" });" & linefeed & ¬
		"" & linefeed & ¬
		" // Only dedicated media hosts may suppress voice notifications." & linefeed & ¬
		" // Keep this policy identical in the probe and metadata paths." & linefeed & ¬
		" const mediaHosts=[" & linefeed & ¬
		"   'youtube.com','youtu.be','netflix.com','hulu.com','disneyplus.com'," & linefeed & ¬
		"   'max.com','hbomax.com','primevideo.com','tv.apple.com'," & linefeed & ¬
		"   'peacocktv.com','paramountplus.com','twitch.tv','vimeo.com'," & linefeed & ¬
		"   'dailymotion.com','crunchyroll.com','tubi.tv','pluto.tv'," & linefeed & ¬
		"   'spotify.com','music.apple.com','music.amazon.com'," & linefeed & ¬
		"   'soundcloud.com','pandora.com','tidal.com','deezer.com'," & linefeed & ¬
		"   'bandcamp.com','app.plex.tv'" & linefeed & ¬
		" ];" & linefeed & ¬
		" const blockedSite=!mediaHosts.some(domain=>host===domain||host.endsWith('.'+domain));" & linefeed & ¬
		"" & linefeed & ¬
		" if(blockedSite)return emptyResult();" & linefeed & ¬
		"" & linefeed & ¬
		" const isYoutube=" & linefeed & ¬
		"   /(^|\\.)youtube\\.com$/.test(host)||" & linefeed & ¬
		"   /(^|\\.)youtu\\.be$/.test(host);" & linefeed & ¬
		"" & linefeed & ¬
		" const isYoutubeHomepage=" & linefeed & ¬
		"   /(^|\\.)youtube\\.com$/.test(host)&&" & linefeed & ¬
		"   location.pathname==='/';" & linefeed & ¬
		"" & linefeed & ¬
		" if(isYoutubeHomepage)return emptyResult();" & linefeed & ¬
		"" & linefeed & ¬
		" const isShorts=" & linefeed & ¬
		"   isYoutube&&location.pathname.startsWith('/shorts/');" & linefeed & ¬
		"" & linefeed & ¬
		" const finite=n=>" & linefeed & ¬
		"   typeof n==='number'&&Number.isFinite(n);" & linefeed & ¬
		"" & linefeed & ¬
		" const docs=[];" & linefeed & ¬
		" const seen=new Set();" & linefeed & ¬
		"" & linefeed & ¬
		" function collectDocs(d){" & linefeed & ¬
		"   if(!d||seen.has(d))return;" & linefeed & ¬
		"   seen.add(d);" & linefeed & ¬
		"   docs.push(d);" & linefeed & ¬
		"" & linefeed & ¬
		"   let frames=[];" & linefeed & ¬
		"   try {frames=[...d.querySelectorAll('iframe,frame')];} catch(e) {}" & linefeed & ¬
		"" & linefeed & ¬
		"   for(const f of frames){" & linefeed & ¬
		"     try {" & linefeed & ¬
		"       if(f.contentDocument)collectDocs(f.contentDocument);" & linefeed & ¬
		"     } catch(e) {}" & linefeed & ¬
		"   }" & linefeed & ¬
		" }" & linefeed & ¬
		"" & linefeed & ¬
		" collectDocs(document);" & linefeed & ¬
		"" & linefeed & ¬
		" const allMedia=[];" & linefeed & ¬
		"" & linefeed & ¬
		" for(const d of docs){" & linefeed & ¬
		"   try {allMedia.push(...d.querySelectorAll('video,audio'));} catch(e) {}" & linefeed & ¬
		" }" & linefeed & ¬
		"" & linefeed & ¬
		" const media=allMedia;" & linefeed & ¬
		"" & linefeed & ¬
		" const text=s=>{" & linefeed & ¬
		"   for(const d of docs){" & linefeed & ¬
		"     try {" & linefeed & ¬
		"       const v=d.querySelector(s)?.textContent?.trim();" & linefeed & ¬
		"       if(v)return v;" & linefeed & ¬
		"     } catch(e) {}" & linefeed & ¬
		"   }" & linefeed & ¬
		"   return '';" & linefeed & ¬
		" };" & linefeed & ¬
		"" & linefeed & ¬
		" const visibleText=s=>{" & linefeed & ¬
		"   for(const d of docs){" & linefeed & ¬
		"     let nodes=[];" & linefeed & ¬
		"     try {nodes=[...d.querySelectorAll(s)];} catch(e) {}" & linefeed & ¬
		"" & linefeed & ¬
		"     for(const n of nodes){" & linefeed & ¬
		"       try {" & linefeed & ¬
		"         const r=n.getBoundingClientRect();" & linefeed & ¬
		"         if(" & linefeed & ¬
		"           r.width>0&&r.height>0&&" & linefeed & ¬
		"           r.bottom>0&&r.right>0&&" & linefeed & ¬
		"           r.top<innerHeight&&r.left<innerWidth" & linefeed & ¬
		"         ){" & linefeed & ¬
		"           const v=(n.textContent||'').trim();" & linefeed & ¬
		"           if(v)return v;" & linefeed & ¬
		"         }" & linefeed & ¬
		"       } catch(e) {}" & linefeed & ¬
		"     }" & linefeed & ¬
		"   }" & linefeed & ¬
		"   return '';" & linefeed & ¬
		" };" & linefeed & ¬
		"" & linefeed & ¬
		" const meta=(s,a='content')=>{" & linefeed & ¬
		"   for(const d of docs){" & linefeed & ¬
		"     try {" & linefeed & ¬
		"       const v=d.querySelector(s)?.getAttribute(a)||'';" & linefeed & ¬
		"       if(v)return v;" & linefeed & ¬
		"     } catch(e) {}" & linefeed & ¬
		"   }" & linefeed & ¬
		"   return '';" & linefeed & ¬
		" };" & linefeed & ¬
		"" & linefeed & ¬
		" const parseVideoId=u=>{" & linefeed & ¬
		"   try {" & linefeed & ¬
		"     const x=new URL(u,location.origin);" & linefeed & ¬
		"" & linefeed & ¬
		"     if(x.hostname==='youtu.be')" & linefeed & ¬
		"       return x.pathname.replace(/^\\/+/, '').split(/[?#&]/)[0]||'';" & linefeed & ¬
		"" & linefeed & ¬
		"     if(x.pathname.startsWith('/shorts/'))" & linefeed & ¬
		"       return (x.pathname.split('/')[2]||'').split(/[?#&]/)[0];" & linefeed & ¬
		"" & linefeed & ¬
		"     if(x.pathname==='/watch')" & linefeed & ¬
		"       return x.searchParams.get('v')||'';" & linefeed & ¬
		"" & linefeed & ¬
		"     if(x.pathname.startsWith('/embed/'))" & linefeed & ¬
		"       return (x.pathname.split('/')[2]||'').split(/[?#&]/)[0];" & linefeed & ¬
		"" & linefeed & ¬
		"     return '';" & linefeed & ¬
		"   } catch(e) {" & linefeed & ¬
		"     return '';" & linefeed & ¬
		"   }" & linefeed & ¬
		" };" & linefeed & ¬
		"" & linefeed & ¬
		" const urlVideoId=parseVideoId(url);" & linefeed & ¬
		"" & linefeed & ¬
		" const mp=isYoutube" & linefeed & ¬
		"   ? document.getElementById('movie_player')" & linefeed & ¬
		"   : null;" & linefeed & ¬
		"" & linefeed & ¬
		" const playerState=" & linefeed & ¬
		"   (mp&&typeof mp.getPlayerState==='function')" & linefeed & ¬
		"     ? mp.getPlayerState()" & linefeed & ¬
		"     : null;" & linefeed & ¬
		"" & linefeed & ¬
		" const playingMedia=media.filter(m=>" & linefeed & ¬
		"   !m.paused&&" & linefeed & ¬
		"   !m.ended&&" & linefeed & ¬
		"   m.readyState>=2" & linefeed & ¬
		" );" & linefeed & ¬
		"" & linefeed & ¬
		" const visiblePlayingMedia=playingMedia.find(m=>{" & linefeed & ¬
		"   try {" & linefeed & ¬
		"     const r=m.getBoundingClientRect();" & linefeed & ¬
		"     return " & linefeed & ¬
		"       r.width>0&&r.height>0&&" & linefeed & ¬
		"       r.bottom>0&&r.right>0&&" & linefeed & ¬
		"       r.top<innerHeight&&r.left<innerWidth;" & linefeed & ¬
		"   } catch(e) {" & linefeed & ¬
		"     return false;" & linefeed & ¬
		"   }" & linefeed & ¬
		" })||null;" & linefeed & ¬
		"" & linefeed & ¬
		" const activeMedia=" & linefeed & ¬
		"   visiblePlayingMedia||playingMedia[0]||null;" & linefeed & ¬
		"" & linefeed & ¬
		" const usableMedia=" & linefeed & ¬
		"   activeMedia||" & linefeed & ¬
		"   media.find(m=>m.readyState>0)||" & linefeed & ¬
		"   media[0]||null;" & linefeed & ¬
		"" & linefeed & ¬
		" const ms=navigator.mediaSession||null;" & linefeed & ¬
		" const mediaSessionPlaying=!!ms&&ms.playbackState==='playing';" & linefeed & ¬
		" const msMeta=ms?.metadata||null;" & linefeed & ¬
		"" & linefeed & ¬
		" let vhs=null;" & linefeed & ¬
		" let vhsState=null;" & linefeed & ¬
		"" & linefeed & ¬
		" try {" & linefeed & ¬
		"   const V=window.VHS||window.__VHS__;" & linefeed & ¬
		"" & linefeed & ¬
		"   if(V&&V.instances){" & linefeed & ¬
		"     const instances=" & linefeed & ¬
		"       Array.isArray(V.instances)" & linefeed & ¬
		"         ? V.instances" & linefeed & ¬
		"         : Object.values(V.instances);" & linefeed & ¬
		"" & linefeed & ¬
		"     vhs=instances.find(Boolean)||null;" & linefeed & ¬
		"" & linefeed & ¬
		"     if(vhs?.store&&typeof vhs.store.getState==='function')" & linefeed & ¬
		"       vhsState=vhs.store.getState();" & linefeed & ¬
		"   }" & linefeed & ¬
		" } catch(e) {}" & linefeed & ¬
		"" & linefeed & ¬
		" const vd=" & linefeed & ¬
		"   (mp&&typeof mp.getVideoData==='function')" & linefeed & ¬
		"     ? (mp.getVideoData()||{})" & linefeed & ¬
		"     : {};" & linefeed & ¬
		"" & linefeed & ¬
		" const playerVDId=vd.video_id||vd.videoId||'';" & linefeed & ¬
		"" & linefeed & ¬
		" const initialVD=" & linefeed & ¬
		"   window?.ytInitialPlayerResponse?.videoDetails||{};" & linefeed & ¬
		"" & linefeed & ¬
		" const initialVideoId=initialVD.videoId||'';" & linefeed & ¬
		"" & linefeed & ¬
		" const playerDataMatchesCurrent=" & linefeed & ¬
		"   !!urlVideoId&&!!playerVDId&&playerVDId===urlVideoId;" & linefeed & ¬
		"" & linefeed & ¬
		" const initialDataMatchesCurrent=" & linefeed & ¬
		"   !!urlVideoId&&!!initialVideoId&&initialVideoId===urlVideoId;" & linefeed & ¬
		"" & linefeed & ¬
		" const video_id=isShorts" & linefeed & ¬
		"   ? urlVideoId" & linefeed & ¬
		"   : (" & linefeed & ¬
		"       playerVDId||" & linefeed & ¬
		"       vhsState?.player?.media?.id||" & linefeed & ¬
		"       urlVideoId||" & linefeed & ¬
		"       ''" & linefeed & ¬
		"     );" & linefeed & ¬
		"" & linefeed & ¬
		" const shortVisibleTitle=" & linefeed & ¬
		"   visibleText('ytd-reel-video-renderer #title')||" & linefeed & ¬
		"   visibleText('ytd-reel-video-renderer h2')||" & linefeed & ¬
		"   '';" & linefeed & ¬
		"" & linefeed & ¬
		" const title=isShorts" & linefeed & ¬
		"   ? (" & linefeed & ¬
		"       msMeta?.title||" & linefeed & ¬
		"       shortVisibleTitle||" & linefeed & ¬
		"       (playerDataMatchesCurrent?vd.title:'')||" & linefeed & ¬
		"       (initialDataMatchesCurrent?initialVD.title:'')||" & linefeed & ¬
		"       (document.title||'')" & linefeed & ¬
		"         .replace(/\\s*-\\s*YouTube\\s*$/,'')" & linefeed & ¬
		"         .trim()" & linefeed & ¬
		"     )" & linefeed & ¬
		"   : (" & linefeed & ¬
		"       vd.title||" & linefeed & ¬
		"       msMeta?.title||" & linefeed & ¬
		"       vhsState?.player?.media?.headline||" & linefeed & ¬
		"       meta('meta[name=\"title\"]')||" & linefeed & ¬
		"       meta('meta[property=\"og:title\"]')||" & linefeed & ¬
		"       text('h1.ytd-watch-metadata')||" & linefeed & ¬
		"       text('h1')||" & linefeed & ¬
		"       (document.title||'')" & linefeed & ¬
		"         .replace(/\\s*-\\s*YouTube\\s*$/,'')" & linefeed & ¬
		"         .trim()" & linefeed & ¬
		"     );" & linefeed & ¬
		"" & linefeed & ¬
		" const initialDataChannel=" & linefeed & ¬
		"   window?.ytInitialData?.metadata?.channelMetadataRenderer?.title||" & linefeed & ¬
		"   window?.ytInitialData?.contents" & linefeed & ¬
		"     ?.twoColumnWatchNextResults" & linefeed & ¬
		"     ?.results" & linefeed & ¬
		"     ?.results" & linefeed & ¬
		"     ?.contents" & linefeed & ¬
		"     ?.find(x=>x.videoSecondaryInfoRenderer)" & linefeed & ¬
		"     ?.videoSecondaryInfoRenderer" & linefeed & ¬
		"     ?.owner" & linefeed & ¬
		"     ?.videoOwnerRenderer" & linefeed & ¬
		"     ?.title" & linefeed & ¬
		"     ?.runs?.[0]?.text||" & linefeed & ¬
		"   '';" & linefeed & ¬
		"" & linefeed & ¬
		" const shortVisibleChannel=" & linefeed & ¬
		"   visibleText('ytd-reel-video-renderer #channel-name')||" & linefeed & ¬
		"   visibleText('ytd-reel-video-renderer a[href^=\"/@\"]')||" & linefeed & ¬
		"   visibleText('a[href^=\"/@\"]')||" & linefeed & ¬
		"   '';" & linefeed & ¬
		"" & linefeed & ¬
		" let channel=isShorts" & linefeed & ¬
		"   ? (" & linefeed & ¬
		"       msMeta?.artist||" & linefeed & ¬
		"       shortVisibleChannel||" & linefeed & ¬
		"       (playerDataMatchesCurrent?(vd.author||vd.channelName||''):'')||" & linefeed & ¬
		"       (initialDataMatchesCurrent?(initialVD.author||''):'')||" & linefeed & ¬
		"       ''" & linefeed & ¬
		"     )" & linefeed & ¬
		"   : (" & linefeed & ¬
		"       vd.author||" & linefeed & ¬
		"       vd.channelName||" & linefeed & ¬
		"       msMeta?.artist||" & linefeed & ¬
		"       initialVD.author||" & linefeed & ¬
		"       initialDataChannel||" & linefeed & ¬
		"       meta('meta[name=\"author\"]')||" & linefeed & ¬
		"       meta('meta[property=\"og:site_name\"]')||" & linefeed & ¬
		"       text('#channel-name a')||" & linefeed & ¬
		"       text('ytd-channel-name a')||" & linefeed & ¬
		"       text('a[href^=\"/@\"]')||" & linefeed & ¬
		"       ''" & linefeed & ¬
		"     );" & linefeed & ¬
		"" & linefeed & ¬
		" if(!channel){" & linefeed & ¬
		"   if(host==='nytimes.com'||host.endsWith('.nytimes.com'))" & linefeed & ¬
		"     channel='The New York Times';" & linefeed & ¬
		"   else channel=host||'';" & linefeed & ¬
		" }" & linefeed & ¬
		"" & linefeed & ¬
		" const rawDomDesc=" & linefeed & ¬
		"   text('#description-inline-expander yt-attributed-string')||" & linefeed & ¬
		"   text('#description-inline-expander-inline-content')||" & linefeed & ¬
		"   text('#description yt-attributed-string')||" & linefeed & ¬
		"   '';" & linefeed & ¬
		"" & linefeed & ¬
		" const normalizedRawDesc=rawDomDesc.replace(/\\s+/g,' ').trim();" & linefeed & ¬
		" const directAiSummary=" & linefeed & ¬
		"   text('#video-summary #content')||" & linefeed & ¬
		"   text('#video-summary .videoSummaryContentViewModelParagraphContainer')||" & linefeed & ¬
		"   text('#video-summary video-summary-content-view-model')||" & linefeed & ¬
		"   '';" & linefeed & ¬
		" const aiSummaryMarker='AI-generated video summary';" & linefeed & ¬
		" const embeddedSummaryStart=normalizedRawDesc.indexOf('Summary');" & linefeed & ¬
		" const embeddedSummaryEnd=normalizedRawDesc.indexOf(aiSummaryMarker);" & linefeed & ¬
		" const embeddedAiSummary=(embeddedSummaryStart>=0&&embeddedSummaryEnd>embeddedSummaryStart)" & linefeed & ¬
		"   ? normalizedRawDesc.slice(embeddedSummaryStart+'Summary'.length,embeddedSummaryEnd).trim()" & linefeed & ¬
		"   : '';" & linefeed & ¬
		" const pageMetadataMatchesCurrent=" & linefeed & ¬
		"   !isYoutube||!urlVideoId||initialDataMatchesCurrent;" & linefeed & ¬
		" const aiSummary=(pageMetadataMatchesCurrent?(directAiSummary||embeddedAiSummary):'')" & linefeed & ¬
		"   .replace(/\\s+/g,' ')" & linefeed & ¬
		"   .trim();" & linefeed & ¬
		"" & linefeed & ¬
		" const domDesc=rawDomDesc" & linefeed & ¬
		"   .split('…more')[0]" & linefeed & ¬
		"   .split('...more')[0]" & linefeed & ¬
		"   .split('AI-generated video summary')[0]" & linefeed & ¬
		"   .split('Transcript')[0]" & linefeed & ¬
		"   .split('Show transcript')[0]" & linefeed & ¬
		"   .split('Ask questions')[0]" & linefeed & ¬
		"   .replace(/\\s+/g,' ')" & linefeed & ¬
		"   .trim();" & linefeed & ¬
		"" & linefeed & ¬
		" const shortRawDesc=" & linefeed & ¬
		"   visibleText('ytd-reel-video-renderer #description')||" & linefeed & ¬
		"   visibleText('ytd-reel-video-renderer #description-text')||" & linefeed & ¬
		"   visibleText('ytd-reel-video-renderer yt-attributed-string')||" & linefeed & ¬
		"   '';" & linefeed & ¬
		"" & linefeed & ¬
		" const shortDomDesc=shortRawDesc" & linefeed & ¬
		"   .replace(/\\s+/g,' ')" & linefeed & ¬
		"   .trim();" & linefeed & ¬
		"" & linefeed & ¬
		" const literalDescription=isShorts" & linefeed & ¬
		"   ? (" & linefeed & ¬
		"       shortDomDesc||" & linefeed & ¬
		"       (playerDataMatchesCurrent?(vd.shortDescription||''):'')||" & linefeed & ¬
		"       (initialDataMatchesCurrent?(initialVD.shortDescription||''):'')||" & linefeed & ¬
		"       title||" & linefeed & ¬
		"       ''" & linefeed & ¬
		"     )" & linefeed & ¬
		"   : (" & linefeed & ¬
		"       (playerDataMatchesCurrent?(vd.shortDescription||''):'')||" & linefeed & ¬
		"       (initialDataMatchesCurrent?(initialVD.shortDescription||''):'')||" & linefeed & ¬
		"       (pageMetadataMatchesCurrent?domDesc:'')||" & linefeed & ¬
		"       (!isYoutube?meta('meta[name=\"description\"]'):'')||" & linefeed & ¬
		"       (!isYoutube?meta('meta[property=\"og:description\"]'):'')||" & linefeed & ¬
		"       ''" & linefeed & ¬
		"     );" & linefeed & ¬
		" const sanitizeDescription=value=>(value||'')" & linefeed & ¬
		"   .split(/\\n+/)" & linefeed & ¬
		"   .map(line=>line.trim())" & linefeed & ¬
		"   .filter(line=>{" & linefeed & ¬
		"     if(!line)return false;" & linefeed & ¬
		"     if(/https?:\\/\\//i.test(line))return true;" & linefeed & ¬
		"     if(/^#{1,}\\S/.test(line))return false;" & linefeed & ¬
		"     if((line.match(/(^|\\s)#[A-Za-z0-9_]+/g)||[]).length>=3)return false;" & linefeed & ¬
		"     if(/^(subscribe|follow (me|us)|connect with|socials?|merch|sponsor|use code|support (me|us)|business inquiries?)\\b/i.test(line))return false;" & linefeed & ¬
		"     return true;" & linefeed & ¬
		"   })" & linefeed & ¬
		"   .join(' ')" & linefeed & ¬
		"   .replace(/\\s+/g,' ')" & linefeed & ¬
		"   .trim();" & linefeed & ¬
		" const summary=aiSummary;" & linefeed & ¬
		" const description=sanitizeDescription(literalDescription);" & linefeed & ¬
		"" & linefeed & ¬
		" let currentTime=0;" & linefeed & ¬
		"" & linefeed & ¬
		" if(isShorts&&activeMedia&&finite(activeMedia.currentTime)){" & linefeed & ¬
		"   currentTime=Math.floor(activeMedia.currentTime);" & linefeed & ¬
		" }" & linefeed & ¬
		" else if(isYoutube&&mp&&typeof mp.getCurrentTime==='function'){" & linefeed & ¬
		"   try {" & linefeed & ¬
		"     const n=mp.getCurrentTime();" & linefeed & ¬
		"     if(finite(n))currentTime=Math.floor(n);" & linefeed & ¬
		"   } catch(e) {}" & linefeed & ¬
		" }" & linefeed & ¬
		" else if(activeMedia&&finite(activeMedia.currentTime)){" & linefeed & ¬
		"   currentTime=Math.floor(activeMedia.currentTime);" & linefeed & ¬
		" }" & linefeed & ¬
		" else if(vhs&&typeof vhs.getCurrentTime==='function'){" & linefeed & ¬
		"   try {" & linefeed & ¬
		"     const n=vhs.getCurrentTime();" & linefeed & ¬
		"     if(finite(n)&&n>0)currentTime=Math.floor(n);" & linefeed & ¬
		"   } catch(e) {}" & linefeed & ¬
		" }" & linefeed & ¬
		"" & linefeed & ¬
		" let duration=0;" & linefeed & ¬
		"" & linefeed & ¬
		" if(isShorts&&activeMedia&&finite(activeMedia.duration)){" & linefeed & ¬
		"   duration=Math.floor(activeMedia.duration);" & linefeed & ¬
		" }" & linefeed & ¬
		" else if(isYoutube&&mp&&typeof mp.getDuration==='function'){" & linefeed & ¬
		"   try {" & linefeed & ¬
		"     const n=mp.getDuration();" & linefeed & ¬
		"     if(finite(n))duration=Math.floor(n);" & linefeed & ¬
		"   } catch(e) {}" & linefeed & ¬
		" }" & linefeed & ¬
		" else if(activeMedia&&finite(activeMedia.duration)){" & linefeed & ¬
		"   duration=Math.floor(activeMedia.duration);" & linefeed & ¬
		" }" & linefeed & ¬
		"" & linefeed & ¬
		" if(!duration&&vhs&&typeof vhs.getDuration==='function'){" & linefeed & ¬
		"   try {" & linefeed & ¬
		"     const n=vhs.getDuration();" & linefeed & ¬
		"     if(finite(n))duration=Math.floor(n);" & linefeed & ¬
		"   } catch(e) {}" & linefeed & ¬
		" }" & linefeed & ¬
		"" & linefeed & ¬
		" if(!duration&&finite(vhsState?.player?.media?.duration))" & linefeed & ¬
		"   duration=Math.floor(vhsState.player.media.duration);" & linefeed & ¬
		"" & linefeed & ¬
		" if(!duration&&finite(usableMedia?.duration))" & linefeed & ¬
		"   duration=Math.floor(usableMedia.duration);" & linefeed & ¬
		"" & linefeed & ¬
		" let playbackRate=1;" & linefeed & ¬
		"" & linefeed & ¬
		" if(isShorts&&activeMedia&&finite(activeMedia.playbackRate)){" & linefeed & ¬
		"   playbackRate=activeMedia.playbackRate;" & linefeed & ¬
		" }" & linefeed & ¬
		" else if(isYoutube&&mp&&typeof mp.getPlaybackRate==='function'){" & linefeed & ¬
		"   try {" & linefeed & ¬
		"     const n=mp.getPlaybackRate();" & linefeed & ¬
		"     if(finite(n))playbackRate=n;" & linefeed & ¬
		"   } catch(e) {}" & linefeed & ¬
		" }" & linefeed & ¬
		" else if(activeMedia&&finite(activeMedia.playbackRate)){" & linefeed & ¬
		"   playbackRate=activeMedia.playbackRate;" & linefeed & ¬
		" }" & linefeed & ¬
		" else if(usableMedia&&finite(usableMedia.playbackRate)){" & linefeed & ¬
		"   playbackRate=usableMedia.playbackRate;" & linefeed & ¬
		" }" & linefeed & ¬
		"" & linefeed & ¬
		" let thumbnail='';" & linefeed & ¬
		"" & linefeed & ¬
		" if(isShorts){" & linefeed & ¬
		"   thumbnail=" & linefeed & ¬
		"     msMeta?.artwork?.slice(-1)?.[0]?.src||" & linefeed & ¬
		"     (video_id" & linefeed & ¬
		"       ? `https://img.youtube.com/vi/${video_id}/maxresdefault.jpg`" & linefeed & ¬
		"       : '');" & linefeed & ¬
		" }" & linefeed & ¬
		" else if(isYoutube&&video_id){" & linefeed & ¬
		"   thumbnail=`https://img.youtube.com/vi/${video_id}/maxresdefault.jpg`;" & linefeed & ¬
		" }" & linefeed & ¬
		" else {" & linefeed & ¬
		"   thumbnail=" & linefeed & ¬
		"     msMeta?.artwork?.slice(-1)?.[0]?.src||" & linefeed & ¬
		"     meta('meta[property=\"og:image\"]')||" & linefeed & ¬
		"     meta('meta[name=\"twitter:image\"]')||" & linefeed & ¬
		"     vhsState?.player?.media?.posterUrl||" & linefeed & ¬
		"     usableMedia?.poster||" & linefeed & ¬
		"     '';" & linefeed & ¬
		" }" & linefeed & ¬
		"" & linefeed & ¬
		" let nativeFullscreen=false;" & linefeed & ¬
		" let domFullscreen=false;" & linefeed & ¬
		"" & linefeed & ¬
		" nativeFullscreen=media.some(m=>" & linefeed & ¬
		"   m.webkitDisplayingFullscreen||" & linefeed & ¬
		"   m.webkitPresentationMode==='fullscreen'" & linefeed & ¬
		" );" & linefeed & ¬
		"" & linefeed & ¬
		" for(const d of docs){" & linefeed & ¬
		"   try {" & linefeed & ¬
		"     if(d.fullscreenElement||d.webkitFullscreenElement){" & linefeed & ¬
		"       domFullscreen=true;" & linefeed & ¬
		"       break;" & linefeed & ¬
		"     }" & linefeed & ¬
		"   } catch(e) {}" & linefeed & ¬
		" }" & linefeed & ¬
		"" & linefeed & ¬
		" const fullscreenish=nativeFullscreen||domFullscreen;" & linefeed & ¬
		"" & linefeed & ¬
		" const html5Playing=media.some(m=>" & linefeed & ¬
		"   !m.paused&&" & linefeed & ¬
		"   !m.ended&&" & linefeed & ¬
		"   m.readyState>=2" & linefeed & ¬
		" );" & linefeed & ¬
		"" & linefeed & ¬
		" const youtubeActuallyPlaying=playerState===1;" & linefeed & ¬
		"" & linefeed & ¬
		" const playing=isYoutube" & linefeed & ¬
		"     ? (youtubeActuallyPlaying||html5Playing)" & linefeed & ¬
		"     : (html5Playing||mediaSessionPlaying);" & linefeed & ¬
		"" & linefeed & ¬
		" const playerClasses=mp?.className||'';" & linefeed & ¬
		"" & linefeed & ¬
		" const compatiblePlayerState=" & linefeed & ¬
		"   isYoutube?playerState:(playing?1:2);" & linefeed & ¬
		"" & linefeed & ¬
		" const compatiblePlayingMode=isYoutube" & linefeed & ¬
		"   ? /\\bplaying-mode\\b/.test(playerClasses)" & linefeed & ¬
		"   : playing;" & linefeed & ¬
		"" & linefeed & ¬
		" const compatiblePausedMode=isYoutube" & linefeed & ¬
		"   ? /\\bpaused-mode\\b/.test(playerClasses)" & linefeed & ¬
		"   : !playing;" & linefeed & ¬
		"" & linefeed & ¬
		" return JSON.stringify({" & linefeed & ¬
		"   playing," & linefeed & ¬
		"   url," & linefeed & ¬
		"   video_id," & linefeed & ¬
		"   title," & linefeed & ¬
		"   channel," & linefeed & ¬
		"   summary," & linefeed & ¬
		"   description," & linefeed & ¬
		"   currentTime," & linefeed & ¬
		"   duration," & linefeed & ¬
		"   playbackRate," & linefeed & ¬
		"   thumbnail," & linefeed & ¬
		"   fullscreenish," & linefeed & ¬
		"   playerState:compatiblePlayerState," & linefeed & ¬
		"   youtubePlayingMode:compatiblePlayingMode," & linefeed & ¬
		"   youtubePausedMode:compatiblePausedMode," & linefeed & ¬
		"   mediaSessionPlaying," & linefeed & ¬
		"   isShorts" & linefeed & ¬
		" });" & linefeed & ¬
		"" & linefeed & ¬
		"} catch(e) {" & linefeed & ¬
		" return JSON.stringify({" & linefeed & ¬
		"   playing:false," & linefeed & ¬
		"   error:String(e)," & linefeed & ¬
		"   url:location.href||''" & linefeed & ¬
		" });" & linefeed & ¬
		"}" & linefeed & ¬
		"})()"


	-- ============================================================
	-- EXECUTE FULL METADATA AGAINST WINNING TAB
	-- ============================================================

	set raw to ""
	set theURL to ""


	if selectedBrowser is "Safari" then

		try
			tell application "Safari"

				set targetTab to tab selectedTabIndex of window selectedWindowIndex

				try
					set theURL to URL of targetTab
				end try

				try
					set raw to do JavaScript js in targetTab
				on error errMsg number errNum
					return "{\"playing\":false,\"error\":\"" & my escape_json(errMsg) & "\",\"error_number\":" & errNum & ",\"url\":\"" & my escape_json(theURL) & "\"}"
				end try

			end tell

		on error errMsg number errNum
			return "{\"playing\":false,\"error\":\"" & my escape_json(errMsg) & "\",\"error_number\":" & errNum & ",\"url\":\"" & my escape_json(theURL) & "\"}"
		end try


	else if selectedBrowser is "Google Chrome" then

		try
			tell application "Google Chrome"

				set targetTab to tab selectedTabIndex of window selectedWindowIndex

				try
					set theURL to URL of targetTab
				end try

				try
					set raw to execute targetTab javascript js
				on error errMsg number errNum

					set chromeError to errMsg

					if chromeError contains "JavaScript through AppleScript is turned off" then
						set chromeError to "Google Chrome JavaScript from Apple Events is disabled. Enable View > Developer > Allow JavaScript from Apple Events."
					end if

					return "{\"playing\":false,\"error\":\"" & my escape_json(chromeError) & "\",\"error_number\":" & errNum & ",\"url\":\"" & my escape_json(theURL) & "\"}"
				end try

			end tell

		on error errMsg number errNum
			return "{\"playing\":false,\"error\":\"" & my escape_json(errMsg) & "\",\"error_number\":" & errNum & ",\"url\":\"" & my escape_json(theURL) & "\"}"
		end try

	end if


	if raw is missing value or raw is "" then
		return "{\"playing\":false,\"error\":\"Browser returned missing value\",\"url\":\"" & my escape_json(theURL) & "\"}"
	end if


	return raw

end timeout
