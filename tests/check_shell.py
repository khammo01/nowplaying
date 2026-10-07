"""Run one real orchestration cycle with fake sensors and network commands."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
for playing in (False, True):
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        shutil.copy2(ROOT / 'NowPlaying.sh', root / 'NowPlaying.sh')
        (root / 'config.local.sh').write_text('''HA_SERVER=unused.invalid
HA_API_URL=https://ha.invalid/webhook/test
HA_BASE_URL=https://ha.invalid
HA_AUDIO_ENTITY=input_boolean.test_mac
BEARER_TOKEN=test-only
OMDB_API_KEY=test-only
''')
        mock = root / 'bin'
        mock.mkdir()
        cache = root / 'cache'
        cache.mkdir()
        (cache / 'browser-inventory.json').write_text(json.dumps({
            'tabs': [
                {'is_youtube_video': True, 'title': 'Current - YouTube',
                 'url': 'https://www.youtube.com/watch?v=active123'},
                {'is_youtube_video': True, 'title': 'Queued video - YouTube',
                 'url': 'https://www.youtube.com/watch?v=queued456'},
            ]
        }))
        commands = {
            'sleep': '#!/bin/bash\nkill -TERM "$PPID"\n',
            'osascript': '#!/bin/bash\ncase "${1:-}" in\n*safari*) echo \'{"playing":' + str(playing).lower() + ',"title":"Test video","duration":60,"currentTime":2,"video_id":"active123","url":"https://www.youtube.com/watch?v=active123"}\';;\n*) echo \'{"playing":false}\';;\nesac\n',
            'pmset': '#!/bin/bash\nexit 0\n',
            'ps': '#!/bin/bash\necho "2.5 coreaudiod"\n',
            'scp': '#!/bin/bash\nexit 0\n',
            'ssh': '#!/bin/bash\nexit 0\n',
            'curl': '#!/usr/bin/python3\nimport json,os,sys\nwith open(os.environ["MOCK_REQUESTS"],"a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\nprint("200",end="")\n',
        }
        for name, content in commands.items():
            p = mock / name
            p.write_text(content)
            p.chmod(0o755)
        env = dict(os.environ, PATH=str(mock) + ':' + os.environ['PATH'],
                   MOCK_REQUESTS=str(root / 'requests.jsonl'), TERM='dumb')
        env.pop('NOWPLAYING_CONFIG', None)
        result = subprocess.run(['bash', str(root / 'NowPlaying.sh')], env=env,
                                capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, result.stderr
        assert not result.stderr, result.stderr
        requests = [json.loads(line) for line in (root / 'requests.jsonl').read_text().splitlines()]
        service = next(r for r in requests if '/api/services/' in r[-1])
        assert service[-1] == 'https://ha.invalid/api/services/input_boolean/turn_' + ('on' if playing else 'off')
        assert json.loads(service[service.index('-d') + 1]) == {'entity_id': 'input_boolean.test_mac'}
        webhook = next(r for r in requests if r[-1] == 'https://ha.invalid/webhook/test')
        payload = json.loads(webhook[webhook.index('-d') + 1])
        assert payload['youtube_playing'] == playing, payload
        queue_ids = [item['video_id'] for item in payload['youtube_queue']]
        assert 'queued456' in queue_ids, payload['youtube_queue']
        assert ('active123' not in queue_ids) == playing, payload['youtube_queue']
        queued = next(item for item in payload['youtube_queue'] if item['video_id'] == 'queued456')
        assert queued['author'] == 'YouTube', queued
        assert queued['duration_sec'] == 0, queued
print('Passed idle/playing orchestration checks with isolated config and mocked network.')
