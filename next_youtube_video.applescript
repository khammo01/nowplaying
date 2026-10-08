-- Close the playing/last-played YouTube tab, then select the next queued video.
-- Window IDs survive front-window reordering; tab indexes are adjusted after close.
set completedResult to my try_frontmost_completed_advance()
if completedResult is not "" then return completedResult

set cachedResult to my try_cached_advance()
if cachedResult is not "" then return cachedResult

set probeJS to "(() => {" & linefeed & ¬
	" const host=location.hostname.toLowerCase();" & linefeed & ¬
	" if(!/(^|\\.)youtube\\.com$/.test(host) || !/^\\/(watch|shorts)(\\/|$)/.test(location.pathname)) return '0|0';" & linefeed & ¬
	" const videos=Array.from(document.querySelectorAll('video'));" & linefeed & ¬
	" const playing=videos.some(v=>!v.paused&&!v.ended&&v.readyState>=2);" & linefeed & ¬
	" const watched=videos.some(v=>v.currentTime>0||v.ended);" & linefeed & ¬
	" const last=window.__nagmenuPlayback;" & linefeed & ¬
	" return (playing?3:watched?2:1)+'|'+(last&&last.url===location.href?last.at:0);" & linefeed & ¬
	"})()"

if application "Safari" is not running then return my open_youtube_home()
set candidates to {}
set sourcePosition to 0
set bestRank to 0
set bestTime to 0
set bestSelected to false

tell application "Safari"
 repeat with w in windows
  set wid to id of w
  repeat with ti from 1 to count of tabs of w
   try
    set t to tab ti of w
    set tabURL to URL of t
    set raw to do JavaScript probeJS in t
    set oldDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to "|"
    set fields to text items of raw
    set AppleScript's text item delimiters to oldDelimiters
    set rankValue to item 1 of fields as integer
    set lastTime to item 2 of fields as real
    if rankValue > 0 then
     set selectedTab to (index of current tab of w = ti)
     -- An untouched background video is a destination, not a source.
     set end of candidates to {wid, ti, tabURL}
     if rankValue > 1 or selectedTab then
      if my prefer_candidate(rankValue, lastTime, selectedTab, bestRank, bestTime, bestSelected) then
       set bestRank to rankValue
       set bestTime to lastTime
       set bestSelected to selectedTab
       set sourcePosition to count of candidates
      end if
     end if
    end if
   end try
  end repeat
 end repeat
 if (count of candidates) = 0 then return my open_youtube_home()
 if sourcePosition = 0 then return "No current YouTube video found"
end tell
return my advance_queue(candidates, sourcePosition)

-- A finished video is commonly absent from the active-player cache. Prefer the
-- selected tab in Safari's front window when its player is ended or effectively
-- at 100%, close that exact tab, and advance through the live YouTube queue.
on try_frontmost_completed_advance()
 if application "Safari" is not running then return ""
 set completionProbeJS to "(() => {" & linefeed & ¬
	" const host=location.hostname.toLowerCase();" & linefeed & ¬
	" if(!/(^|\\.)youtube\\.com$/.test(host) || !/^\\/(watch|shorts)(\\/|$)/.test(location.pathname)) return false;" & linefeed & ¬
	" const v=Array.from(document.querySelectorAll('video')).find(x=>Number.isFinite(x.duration)&&x.duration>0) || document.querySelector('video');" & linefeed & ¬
	" if(!v) return !!document.querySelector('.html5-video-player.ended-mode');" & linefeed & ¬
	" const remaining=Number.isFinite(v.duration)?v.duration-v.currentTime:Infinity;" & linefeed & ¬
	" return !!(v.ended || remaining<=1.5 || (v.duration>0&&v.currentTime/v.duration>=0.999) || document.querySelector('.html5-video-player.ended-mode'));" & linefeed & ¬
	"})()"

 tell application "Safari"
  if (count of windows) = 0 then return ""
  set sourceWindow to id of front window
  set sourceTab to index of current tab of front window
  set sourceURL to URL of current tab of front window
  try
   if not (do JavaScript completionProbeJS in current tab of front window) then return ""
  on error
   return ""
  end try

  set candidates to {}
  set sourcePosition to 0
  repeat with w in windows
   set wid to id of w
   repeat with ti from 1 to count of tabs of w
    try
     set tabURL to URL of tab ti of w
     if my is_youtube_video_url(tabURL) then
      set end of candidates to {wid, ti, tabURL}
      if wid = sourceWindow and ti = sourceTab then set sourcePosition to count of candidates
     end if
    end try
   end repeat
  end repeat
  if sourcePosition = 0 then return ""
 end tell
 return my advance_queue(candidates, sourcePosition)
end try_frontmost_completed_advance

-- Fast path: NowPlaying already records the exact browser, tab index, and URL.
-- Resolve that stable URL, enumerate only YouTube URLs (no per-tab JavaScript),
-- then advance. The full probe below remains as recovery for a stale cache.
on try_cached_advance()
 try
	set inventoryPath to (POSIX path of (path to home folder)) & "NowPlaying/cache/browser-inventory.json"
  -- Reject an old inventory. URL validation protects identity, while this age
  -- bound prevents a newly opened queue from being omitted for too long.
  set expectedURL to do shell script "/usr/bin/jq -r 'select((now-(.updated_at//0)) < 120) | select(.active.browser==\"Safari\") | .active.url // empty' " & quoted form of inventoryPath
  if expectedURL does not contain "youtube.com/watch" and expectedURL does not contain "youtube.com/shorts/" then return ""
  set queueText to do shell script "/usr/bin/jq -r '.tabs[] | select(.browser==\"Safari\" and .is_youtube_video==true) | [.window_id,.tab_index,.url] | @tsv' " & quoted form of inventoryPath
  if queueText is "" then return ""
 on error
  return ""
 end try

 tell application "Safari"
  if not running then return ""
  set candidates to {}
  set sourcePosition to 0
  set oldDelimiters to AppleScript's text item delimiters
  set AppleScript's text item delimiters to linefeed
  set queueLines to text items of queueText
  set AppleScript's text item delimiters to oldDelimiters
  repeat with queueLine in queueLines
   set AppleScript's text item delimiters to tab
   set queueFields to text items of (queueLine as text)
   set AppleScript's text item delimiters to oldDelimiters
   if (count of queueFields) ≥ 3 then
    try
     set wid to item 1 of queueFields as integer
     set ti to item 2 of queueFields as integer
     set tabURL to item 3 of queueFields
     -- Validate every cached identity before it can become a source or target.
     if URL of tab ti of window id wid is tabURL then
      set end of candidates to {wid, ti, tabURL}
      if tabURL is expectedURL and sourcePosition is 0 then set sourcePosition to count of candidates
     end if
    end try
   end if
  end repeat
  if sourcePosition is 0 then return ""
 end tell
 return my advance_queue(candidates, sourcePosition)
end try_cached_advance

on advance_queue(candidates, sourcePosition)
 tell application "Safari"
  set {sourceWindow, sourceTab, sourceURL} to item sourcePosition of candidates
  if URL of tab sourceTab of window id sourceWindow is not sourceURL then return "Source changed; skipped"
  close tab sourceTab of window id sourceWindow
  if (count of candidates) < 2 then return my open_youtube_home()
  set {targetWindow, targetTab, targetURL} to my next_destination(candidates, sourcePosition)
  if URL of tab targetTab of window id targetWindow is not targetURL then return "Destination changed; skipped"
  set current tab of window id targetWindow to tab targetTab of window id targetWindow
  set index of window id targetWindow to 1
  activate
  do JavaScript "(() => {const v=document.querySelector('video');if(v){if(document.activeElement)document.activeElement.blur();v.setAttribute('tabindex','-1');v.focus();if(v.ended)v.currentTime=0;v.play().catch(()=>{});}})()" in tab targetTab of window id targetWindow
  repeat 30 times
   delay 0.1
   if URL of current tab of front window is not targetURL or id of front window is not targetWindow then return "Selection changed; skipped fullscreen"
   set playbackState to do JavaScript "(() => {const v=document.querySelector('video');return v&&!v.paused&&!v.ended?(document.fullscreenElement||v.webkitDisplayingFullscreen?'fullscreen':'playing'):'waiting';})()" in current tab of front window
   if playbackState is "fullscreen" then return "Advanced to next YouTube video"
   if playbackState is "playing" then
    tell application "System Events"
     if frontmost of application process "Safari" then keystroke "f"
    end tell
    return "Advanced to next YouTube video"
   end if
  end repeat
  return "Selected next YouTube video; playback did not start"
 end tell
end advance_queue

-- No queued video remains: open the home page without toggling fullscreen.
on open_youtube_home()
 tell application "Safari"
  make new document with properties {URL:"https://www.youtube.com/"}
  activate
 end tell
 return "Opened YouTube home page"
end open_youtube_home

-- Pure selection helpers are exercised without controlling a browser.
on prefer_candidate(rankValue, lastTime, selectedTab, bestRank, bestTime, bestSelected)
 return rankValue > bestRank or (rankValue = bestRank and lastTime > bestTime) or (rankValue = bestRank and lastTime = bestTime and selectedTab and not bestSelected)
end prefer_candidate

on is_youtube_video_url(tabURL)
 return tabURL starts with "https://www.youtube.com/watch" or tabURL starts with "https://www.youtube.com/shorts/" or tabURL starts with "https://youtube.com/watch" or tabURL starts with "https://youtube.com/shorts/" or tabURL starts with "https://m.youtube.com/watch" or tabURL starts with "https://m.youtube.com/shorts/"
end is_youtube_video_url

on next_destination(candidates, sourcePosition)
 set {sourceWindow, sourceTab, sourceURL} to item sourcePosition of candidates
 set nextPosition to sourcePosition + 1
 if nextPosition > (count of candidates) then set nextPosition to 1
 set {targetWindow, targetTab, targetURL} to item nextPosition of candidates
 if targetWindow = sourceWindow and targetTab > sourceTab then set targetTab to targetTab - 1
 return {targetWindow, targetTab, targetURL}
end next_destination
