tell application "Safari"
	set bestWindow to missing value
	set bestTab to missing value
	set bestCount to 0

	repeat with w in windows
		set youtubeCount to 0
		set firstYoutubeTab to missing value
		repeat with t in tabs of w
			try
				set tabURL to URL of t
				if tabURL contains "youtube.com" or tabURL contains "youtu.be" then
					set youtubeCount to youtubeCount + 1
					if firstYoutubeTab is missing value then set firstYoutubeTab to t
				end if
			end try
		end repeat

		if youtubeCount > bestCount then
			set bestCount to youtubeCount
			set bestWindow to w
			set bestTab to firstYoutubeTab
		end if
	end repeat

	if bestCount > 0 then
		set current tab of bestWindow to bestTab
		set index of bestWindow to 1
		activate
	else
		make new document with properties {URL:"https://www.youtube.com/"}
		activate
	end if
end tell
