on replace_chars(this_text, search_string, replacement_string)
	set AppleScript's text item delimiters to search_string
	set the item_list to every text item of this_text
	set AppleScript's text item delimiters to replacement_string
	set this_text to the item_list as string
	set AppleScript's text item delimiters to ""
	return this_text
end replace_chars

on escape_json_string(txt)
	if txt is missing value then return ""
	set s to txt as text
	set s to my replace_chars(s, "\\", "\\\\")
	set s to my replace_chars(s, "\"", "\\\"")
	set s to my replace_chars(s, return, "\\n")
	set s to my replace_chars(s, linefeed, "\\n")
	return s
end escape_json_string

on parse_media_candidate(raw_name, media_path)
	set py to "import os,re,sys,json

raw_name = sys.argv[1]
media_path = sys.argv[2]
filename_guess = os.path.basename(media_path) if media_path else ''

def clean(s):
    if not s:
        return ''

    s = os.path.basename(s)
    s = os.path.splitext(s)[0]

    s = re.sub(r'\\[.*?\\]', ' ', s)
    s = re.sub(r'\\(.*?\\)', ' ', s)

    s = s.replace('_', ' ').replace('.', ' ').replace('-', ' ')

    junk_patterns = [
        r'\\b(?:2160p|1080p|720p|480p|4k|uhd)\\b',
        r'\\b(?:bluray|brrip|webrip|web dl|webdl|hdrip|hdtv|remux)\\b',
        r'\\b(?:x264|x265|h264|h265|hevc)\\b',
        r'\\b(?:aac|ac3|ddp\\d(?:\\.\\d)?|dts|truehd|atmos)\\b',
        r'\\b(?:10bit|8bit|proper|repack|extended|unrated)\\b',
        r'\\b(?:yify|yts|tgx|galaxyrg|rarbg|evo|qxr)\\b',
        r'\\b\\d{3,4}mb\\b'
    ]

    for p in junk_patterns:
        s = re.sub(p, ' ', s, flags=re.I)

    s = re.sub(r'(?i)(?:^|\\s)1(?=\\s|$)', ' ', s)
    s = re.sub(r'\\s+', ' ', s).strip()
    return s

def parse(s):
    cleaned = clean(s)
    year = ''
    title = cleaned

    m = re.search(r'\\b(19\\d{2}|20\\d{2})\\b', cleaned)
    if m:
        year = m.group(1)
        title = cleaned[:m.start()].strip()

    return title.strip(), year, cleaned

title1, year1, clean1 = parse(raw_name)
title2, year2, clean2 = parse(filename_guess)

use_filename = bool(title2)

if use_filename:
    result = {
        'parsed_title': title2,
        'parsed_year': year2,
        'alt_title': title1,
        'alt_year': year1,
        'filename_guess': filename_guess,
        'clean_raw_name': clean1,
        'clean_filename': clean2
    }
else:
    result = {
        'parsed_title': title1,
        'parsed_year': year1,
        'alt_title': title2,
        'alt_year': year2,
        'filename_guess': filename_guess,
        'clean_raw_name': clean1,
        'clean_filename': clean2
    }

print(json.dumps(result))"
	
	try
		return do shell script "python3 -c " & quoted form of py & space & quoted form of raw_name & space & quoted form of media_path
	on error errMsg
		return "{\"parsed_title\":\"\",\"parsed_year\":\"\",\"alt_title\":\"\",\"alt_year\":\"\",\"filename_guess\":\"\",\"clean_raw_name\":\"\",\"clean_filename\":\"\",\"error\":\"" & my escape_json_string(errMsg) & "\"}"
	end try
end parse_media_candidate

on json_get_field(json_text, field_name)
	set py to "import json,sys
data=json.loads(sys.argv[1])
value=data.get(sys.argv[2], '')
print(value if value else '')"
	try
		return do shell script "python3 -c " & quoted form of py & space & quoted form of json_text & space & quoted form of field_name
	on error
		return ""
	end try
end json_get_field

on url_encode(txt)
	set py to "import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=''))"
	return do shell script "python3 -c " & quoted form of py & space & quoted form of (txt as text)
end url_encode

on omdb_lookup_once(movie_title, movie_year)
	if movie_title is "" then return "{\"Response\":\"False\",\"Error\":\"Empty title\"}"
	
	set omdb_api_key to system attribute "OMDB_API_KEY"
	if omdb_api_key is "" then return "{\"Response\":\"False\",\"Error\":\"OMDB_API_KEY not configured\"}"
	set baseURL to "https://www.omdbapi.com/?apikey=" & omdb_api_key & "&t=" & my url_encode(movie_title)
	
	set queryURL to baseURL
	if movie_year is not "" then
		set queryURL to queryURL & "&y=" & my url_encode(movie_year)
	end if
	
	return do shell script "curl -s " & quoted form of queryURL
end omdb_lookup_once

on omdb_lookup(movie_title, movie_year, alt_title, alt_year)
	set resultJSON to my omdb_lookup_once(movie_title, movie_year)
	if resultJSON does not contain "\"Response\":\"False\"" then return resultJSON
	
	set resultJSON to my omdb_lookup_once(movie_title, "")
	if resultJSON does not contain "\"Response\":\"False\"" then return resultJSON
	
	if alt_title is not "" and alt_title is not movie_title then
		set resultJSON to my omdb_lookup_once(alt_title, alt_year)
		if resultJSON does not contain "\"Response\":\"False\"" then return resultJSON
		
		set resultJSON to my omdb_lookup_once(alt_title, "")
		if resultJSON does not contain "\"Response\":\"False\"" then return resultJSON
	end if
	
	return resultJSON
end omdb_lookup

on probe_vlc()
	set out_playing to "false"
	set out_path to ""
	set out_name to ""
	set out_duration to ""
	set out_time to ""
	
	try
		tell application "VLC"
			if it is not running then
				return "{\"playing\":\"false\",\"raw_name\":\"\",\"media_path\":\"\",\"duration\":\"\",\"position\":\"\",\"probe_error\":\"VLC not running\"}"
			end if
			
			try
				set out_playing to («class AAPL» as text)
			end try
			
			try
				set out_path to («class AAPA») as text
			end try
			
			try
				set out_name to («class AANA») as text
			end try
			
			try
				set out_duration to («class AADU») as text
			end try
			
			try
				set out_time to («class AACT») as text
			end try
		end tell
	on error errMsg
		return "{\"playing\":\"false\",\"raw_name\":\"\",\"media_path\":\"\",\"duration\":\"\",\"position\":\"\",\"probe_error\":\"" & my escape_json_string(errMsg) & "\"}"
	end try
	
	if out_name is "" and out_path is "" then
		return "{\"playing\":\"false\",\"raw_name\":\"\",\"media_path\":\"\",\"duration\":\"\",\"position\":\"\",\"probe_error\":\"No media loaded\"}"
	end if
	
	return "{\"playing\":\"" & my escape_json_string(out_playing) & "\",\"raw_name\":\"" & my escape_json_string(out_name) & "\",\"media_path\":\"" & my escape_json_string(out_path) & "\",\"duration\":\"" & my escape_json_string(out_duration) & "\",\"position\":\"" & my escape_json_string(out_time) & "\",\"probe_error\":\"\"}"
end probe_vlc

set vlc_probe_json to my probe_vlc()

set vlc_playing to my json_get_field(vlc_probe_json, "playing")
set vlc_raw_name to my json_get_field(vlc_probe_json, "raw_name")
set vlc_media_path to my json_get_field(vlc_probe_json, "media_path")
set vlc_duration to my json_get_field(vlc_probe_json, "duration")
set vlc_position to my json_get_field(vlc_probe_json, "position")
set probe_error to my json_get_field(vlc_probe_json, "probe_error")

if vlc_raw_name is "" and vlc_media_path is "" then
	return "{\"playing\":\"" & my escape_json_string(vlc_playing) & "\",\"raw_name\":\"\",\"filename_guess\":\"\",\"clean_raw_name\":\"\",\"clean_filename\":\"\",\"parsed_title\":\"\",\"parsed_year\":\"\",\"alt_title\":\"\",\"alt_year\":\"\",\"parse_error\":\"\",\"media_path\":\"\",\"duration\":\"\",\"position\":\"\",\"title\":\"\",\"year\":\"\",\"director\":\"\",\"writer\":\"\",\"actors\":\"\",\"genre\":\"\",\"description\":\"\",\"imdbID\":\"\",\"imdbRating\":\"\",\"poster\":\"\",\"omdb_response\":\"False\",\"omdb_error\":\"" & my escape_json_string(probe_error) & "\",\"omdb\":{\"Response\":\"False\",\"Error\":\"" & my escape_json_string(probe_error) & "\"}}"
end if

set parse_json to my parse_media_candidate(vlc_raw_name, vlc_media_path)

set parsed_title to my json_get_field(parse_json, "parsed_title")
set parsed_year to my json_get_field(parse_json, "parsed_year")
set alt_title to my json_get_field(parse_json, "alt_title")
set alt_year to my json_get_field(parse_json, "alt_year")
set filename_guess to my json_get_field(parse_json, "filename_guess")
set clean_raw_name to my json_get_field(parse_json, "clean_raw_name")
set clean_filename to my json_get_field(parse_json, "clean_filename")
set parse_error to my json_get_field(parse_json, "error")

set omdb_json to my omdb_lookup(parsed_title, parsed_year, alt_title, alt_year)

set omdb_title to my json_get_field(omdb_json, "Title")
set omdb_year to my json_get_field(omdb_json, "Year")
set omdb_director to my json_get_field(omdb_json, "Director")
set omdb_writer to my json_get_field(omdb_json, "Writer")
set omdb_actors to my json_get_field(omdb_json, "Actors")
set omdb_description to my json_get_field(omdb_json, "Plot")
set omdb_genre to my json_get_field(omdb_json, "Genre")
set omdb_imdbID to my json_get_field(omdb_json, "imdbID")
set omdb_imdbRating to my json_get_field(omdb_json, "imdbRating")
set omdb_poster to my json_get_field(omdb_json, "Poster")
set omdb_response to my json_get_field(omdb_json, "Response")
set omdb_error to my json_get_field(omdb_json, "Error")

if omdb_title is "" then set omdb_title to parsed_title
if omdb_year is "" then set omdb_year to parsed_year
if omdb_description is "" then set omdb_description to parsed_title

return "{\"playing\":\"" & my escape_json_string(vlc_playing) & "\",\"raw_name\":\"" & my escape_json_string(vlc_raw_name) & "\",\"filename_guess\":\"" & my escape_json_string(filename_guess) & "\",\"clean_raw_name\":\"" & my escape_json_string(clean_raw_name) & "\",\"clean_filename\":\"" & my escape_json_string(clean_filename) & "\",\"parsed_title\":\"" & my escape_json_string(parsed_title) & "\",\"parsed_year\":\"" & my escape_json_string(parsed_year) & "\",\"alt_title\":\"" & my escape_json_string(alt_title) & "\",\"alt_year\":\"" & my escape_json_string(alt_year) & "\",\"parse_error\":\"" & my escape_json_string(parse_error) & "\",\"media_path\":\"" & my escape_json_string(vlc_media_path) & "\",\"duration\":\"" & my escape_json_string(vlc_duration) & "\",\"position\":\"" & my escape_json_string(vlc_position) & "\",\"title\":\"" & my escape_json_string(omdb_title) & "\",\"year\":\"" & my escape_json_string(omdb_year) & "\",\"director\":\"" & my escape_json_string(omdb_director) & "\",\"writer\":\"" & my escape_json_string(omdb_writer) & "\",\"actors\":\"" & my escape_json_string(omdb_actors) & "\",\"genre\":\"" & my escape_json_string(omdb_genre) & "\",\"description\":\"" & my escape_json_string(omdb_description) & "\",\"imdbID\":\"" & my escape_json_string(omdb_imdbID) & "\",\"imdbRating\":\"" & my escape_json_string(omdb_imdbRating) & "\",\"poster\":\"" & my escape_json_string(omdb_poster) & "\",\"omdb_response\":\"" & my escape_json_string(omdb_response) & "\",\"omdb_error\":\"" & my escape_json_string(omdb_error) & "\",\"omdb\":" & omdb_json & "}"
