"""Exercise next-video detection and tab-index adjustment without browser actions."""
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'next_youtube_video.applescript').read_text()
control_source = (ROOT / 'youtube_control.applescript').read_text()
wrapper = (ROOT / 'youtube_action_with_feedback.sh').read_text()
assert 'cache/next-youtube.lock' in wrapper, 'Next action must prevent overlapping workers'
assert 'find_playing_youtube_tab' in source, 'Next action must adopt Safari autoplay handoff'
assert source.index('find_playing_youtube_tab()') < source.index('v.play().catch'), 'Autoplay handoff must be checked before requesting play'
assert "player.pauseVideo()" in control_source, 'Queued launches must explicitly pause YouTube players'
assert "media.webkitExitFullscreen()" in control_source, 'Queued launches must exit native video fullscreen'
play_video_id = control_source[control_source.index('on play_video_id('):control_source.index('end play_video_id')]
assert 'repeat with wi from 1 to count of windows' in play_video_id, 'Queued launches must recover from stale cached window indices'
assert 'liveURL contains videoID' in play_video_id, 'Queued launches must relocate the requested video by its stable ID'
play_target = control_source[control_source.index('on play_target('):control_source.index('end play_target')]
assert play_target.index('my pause_competing_media()') < play_target.index('set current tab of w to t'), 'Competing media must pause before selecting a queued Safari tab'
assert play_target.index('my pause_competing_media()') < play_target.index('set active tab index of w to index of t'), 'Competing media must pause before selecting a queued Chrome tab'
assignment = source.split('set probeJS to ', 1)[1].split('\n\n', 1)[0]
probe = '\n'.join(json.loads(c) for c in re.findall(r'"(?:\\.|[^"\\])*"', assignment))
completion_assignment = source.split('set completionProbeJS to ', 1)[1].split('\n\n', 1)[0]
completion_probe = '\n'.join(json.loads(c) for c in re.findall(r'"(?:\\.|[^"\\])*"', completion_assignment))
cases = r'''
var location={hostname:'www.youtube.com',pathname:'/watch',href:'https://www.youtube.com/watch?v=a'};
var window={}, videos=[];
var document={querySelectorAll:()=>videos};
let checks=0;
function expect(value){const actual=eval(probe);if(actual!==value)throw Error(actual+' != '+value);checks++;}
expect('1|0');
videos=[{paused:true,ended:false,currentTime:42,readyState:4}];expect('2|0');
window.__nagmenuPlayback={url:location.href,at:1234};expect('2|1234');
videos[0].ended=true;expect('2|1234');
videos[0].paused=false;videos[0].ended=false;expect('3|1234');
location.href+='new';expect('3|0'); // SPA navigation must invalidate history.
location.hostname='youtube.com.evil.example';expect('0|0');
location.hostname='www.youtube.com';location.pathname='/';expect('0|0');
location.pathname='/shorts/abc';expect('3|0');
console.log('Passed '+checks+' next-video probe checks.');
'''
completion_cases = r'''
{
var location={hostname:'www.youtube.com',pathname:'/watch',href:'https://www.youtube.com/watch?v=a'};
var playerEnded=false;
var video={paused:true,ended:false,currentTime:98,duration:100};
var document={querySelectorAll:()=>[video],querySelector:(value)=>value==='video'?video:(playerEnded?{}:null)};
let checks=0;
function expect(value){const actual=eval(completionProbe);if(actual!==value)throw Error(actual+' != '+value);checks++;}
expect(false);
video.currentTime=99.91;expect(true);
video.currentTime=98;video.ended=true;expect(true);
video.ended=false;playerEnded=true;expect(true);
location.pathname='/';expect(false);
console.log('Passed '+checks+' completed-video checks.');
}
'''
helpers = source[source.index('on prefer_candidate('):]
harness = '''
on run
 if not prefer_candidate(3, 0, false, 2, 100, true) then error "Playing must beat paused"
 if not prefer_candidate(2, 200, false, 2, 100, true) then error "Most recent pause wins"
 if prefer_candidate(2, 100, true, 2, 200, false) then error "Selected must not beat recency"
 if not prefer_candidate(2, 100, true, 2, 100, false) then error "Selected breaks ties"
 if prefer_candidate(1, 0, true, 2, 0, false) then error "Untouched must not beat watched"
 set entries to {{101, 2, "a"}, {101, 4, "b"}, {202, 1, "c"}}
 if next_destination(entries, 1) is not {101, 3, "b"} then error "Same window index shift"
 if next_destination(entries, 2) is not {202, 1, "c"} then error "Other window stable"
 if next_destination(entries, 3) is not {101, 2, "a"} then error "Wraparound"
 return "Passed 8 next-video selection checks."
end run
'''
with tempfile.TemporaryDirectory() as temp:
    js = Path(temp) / 'next.js'
    js.write_text('const probe='+json.dumps(probe)+';\nconst completionProbe='+json.dumps(completion_probe)+';\n'+cases+completion_cases)
    subprocess.run(['osascript', '-l', 'JavaScript', str(js)], check=True)
    applescript = Path(temp) / 'selection.applescript'
    applescript.write_text(helpers+harness)
    subprocess.run(['osascript', str(applescript)], check=True)
