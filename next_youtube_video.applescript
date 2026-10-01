-- Close the playing/last-played YouTube tab, then select the next queued video.
-- Window IDs survive front-window reordering; tab indexes are adjusted after close.
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
 set {sourceWindow, sourceTab, sourceURL} to item sourcePosition of candidates
 -- Verify identity immediately before closing; never use a stale front window.
 if URL of tab sourceTab of window id sourceWindow is not sourceURL then return "Source changed; skipped"
 close tab sourceTab of window id sourceWindow
 if (count of candidates) < 2 then return my open_youtube_home()
 set {targetWindow, targetTab, targetURL} to my next_destination(candidates, sourcePosition)
 if URL of tab targetTab of window id targetWindow is not targetURL then return "Destination changed; skipped"
 set current tab of window id targetWindow to tab targetTab of window id targetWindow
 set index of window id targetWindow to 1
 activate
 do JavaScript "(() => {const v=document.querySelector('video'); if(v){if(document.activeElement)document.activeElement.blur(); v.setAttribute('tabindex','-1'); v.focus(); if(v.ended)v.currentTime=0; v.play().catch(()=>{});}})()" in tab targetTab of window id targetWindow
 -- Wait for this destination to play before sending the fullscreen shortcut.
 repeat 20 times
  delay 0.25
  if URL of current tab of front window is not targetURL or id of front window is not targetWindow then return "Selection changed; skipped fullscreen"
  set playbackState to do JavaScript "(() => {const v=document.querySelector('video'); return v&&!v.paused&&!v.ended ? (document.fullscreenElement||v.webkitDisplayingFullscreen?'fullscreen':'playing') : 'waiting';})()" in current tab of front window
  if playbackState = "fullscreen" then return "Advanced to next YouTube video"
  if playbackState = "playing" then
   tell application "System Events"
    if frontmost of application process "Safari" then keystroke "f"
   end tell
   return "Advanced to next YouTube video"
  end if
 end repeat
 return "Selected next YouTube video; playback did not start"
end tell

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

on next_destination(candidates, sourcePosition)
 set {sourceWindow, sourceTab, sourceURL} to item sourcePosition of candidates
 set nextPosition to sourcePosition + 1
 if nextPosition > (count of candidates) then set nextPosition to 1
 set {targetWindow, targetTab, targetURL} to item nextPosition of candidates
 if targetWindow = sourceWindow and targetTab > sourceTab then set targetTab to targetTab - 1
 return {targetWindow, targetTab, targetURL}
end next_destination
