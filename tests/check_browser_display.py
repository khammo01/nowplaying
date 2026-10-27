"""Only actual YouTube URLs show Binge; generic video controls stay visible."""
from pathlib import Path
import subprocess
r=Path(__file__).resolve().parents[1];s=(r/'NowPlaying.sh').read_text()
helper=s[s.index('is_youtube_playback_url() {'):s.index('ensure_nagbot_computer_agent() {')]
render=s[s.index('emit_cli() {'):s.index('# Initialization',s.index('emit_cli() {'))]
prefix='''set -u
nodebug() { :; }
print_title_lines() { :; }
print_description_lines() { :; }
cecho() { :; }
nowplaying_updated_relative() { printf 'just now'; }
meeting_status_label() { printf 'Not In A Meeting'; }
display_media_status() { printf 'YouTube'; }
last_polled_time=12:00:00
last_ha_update_time_local=12:00:00
music_playing=false
youtube_playing=true
track=Training
description=Context
last_known_description=''
artist=Instructor
playlist_name=''
playback_speed=1.0
youtube_video_count=3
high_score=5
currentTimehms=01:00
duration_hms=05:00
progress_bar_full=''
next_check_interval=5
'''
for host,expected in [('www.youtube.com',True),('music.youtube.com',True),('youtu.be',True),('1111systems.udemy.com',False),('youtube.com.evil.test',False),('notyoutube.com',False)]:
 out=subprocess.check_output(['bash','-c',prefix+helper+render+'\nurl="https://'+host+'/watch?v=abc"\nemit_cli\n'],text=True)
 assert ('Video Binge:' in out)==expected,(host,out)
 assert 'Speed:' in out,(host,out)
print('Passed YouTube-only Binge and generic-video speed display checks.')
