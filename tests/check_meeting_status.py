"""Meeting status follows HA, bounds polling, and exposes failed reads honestly."""
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
source = (root / 'NowPlaying.sh').read_text()
functions = source[source.index('read_meeting_state() {'):source.index('ensure_nagbot_computer_agent() {')]
program = '''
set -eu
BEARER_TOKEN=test-only
HA_BASE_URL=https://ha.invalid
meeting_state=unknown
last_meeting_check_epoch=0
TEST_NOW=100
RESPONSE='{"state":"on"}'
calls=0
epoch_now() { printf '%s' "$TEST_NOW"; }
curl() {
    # HTTP reads only: meeting awareness must never send a playback command.
    [[ "$*" != *'/api/services/'* && "$*" != *' -d '* ]] || exit 5
    [[ "${!#}" == 'https://ha.invalid/api/states/input_boolean.in_a_work_meeting' ]] || exit 6
    printf '%s' "$RESPONSE"
}
'''+functions+'''
read_meeting_state
[[ "$meeting_state" == on ]]
[[ "$(meeting_status_label)" == 'In A Meeting' ]]
TEST_NOW=110
RESPONSE='{"state":"off"}'
read_meeting_state
[[ "$meeting_state" == on && "$last_meeting_check_epoch" == 100 ]]
TEST_NOW=131
read_meeting_state
[[ "$meeting_state" == off ]]
[[ "$(meeting_status_label)" == 'Not In A Meeting' ]]
TEST_NOW=162
RESPONSE=''
read_meeting_state
[[ "$meeting_state" == unknown ]]
[[ "$(meeting_status_label)" == 'Meeting status unavailable' ]]
TEST_NOW=193
RESPONSE='{"state":"unavailable"}'
read_meeting_state
[[ "$meeting_state" == unknown ]]
media_status=Idle
meeting_state=on
[[ "$(display_media_status)" == 'In a Meeting' ]]
[[ "$media_status" == Idle ]]
meeting_state=off
[[ "$(display_media_status)" == Idle ]]
meeting_state=unknown
[[ "$(display_media_status)" == Idle ]]
meeting_state=on
for media_status in Music YouTube Playing Video Paused; do
    [[ "$(display_media_status)" == "$media_status" ]]
done
'''
subprocess.run(['bash', '-c', program], env=dict(os.environ), check=True)
print('Passed meeting polling, idle display override and playback-state preservation checks.')
