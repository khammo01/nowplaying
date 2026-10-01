# Safari next-video shortcut

In **Tab to Next Youtube Video Safari**, replace the Run AppleScript action with:

```applescript
on run {input, parameters}
    return do shell script "/usr/bin/osascript " & quoted form of ((POSIX path of (path to home folder)) & "NowPlaying/next_youtube_video.applescript")
end run
```

Remove the separate BetterTouchTool action that sends `f` to Safari. The script
sends it only after selecting a different YouTube tab and verifying playback.
Keep the sound actions if desired. This wrapper reads the source from the local
checkout on each invocation; update the checkout on each Mac before installing
or syncing the shortcut wrapper there.

The source is chosen from actual video tabs: playing first, then paused/ended
with playback progress, then a selected untouched video. NowPlaying records the
last observed playback time in the page so paused candidates can be ordered by
recency. Without that history, selected tabs break ties, followed by Safari's
window/tab order. The transient timestamp is invalidated when the URL changes.

Only the chosen tab is closed (Safari closes its window if that was its last
tab). The next YouTube video in window/tab order is selected, wrapping around.
Unrelated tabs are skipped. With no next video, the source is closed and the
YouTube home page opens without sending a fullscreen key. The home page also
opens when no YouTube video tabs exist or Safari is not running. If playback is blocked or focus changes, fullscreen
is skipped. This requires the existing Safari JavaScript and System Events
Automation permissions.

`./scripts/check.sh` compiles the script and tests playback classification,
selection priority, index adjustment, and wraparound without closing live tabs.
