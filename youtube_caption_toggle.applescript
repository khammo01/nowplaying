-- Compatibility entry point retained for existing BetterTouchTool actions.
-- The shared command handler keeps every YouTube control on the same exact tab.

set handlerPath to (POSIX path of (path to home folder)) & "NowPlaying/youtube_target_command.applescript"
return do shell script "/usr/bin/osascript " & quoted form of handlerPath & " captions"
