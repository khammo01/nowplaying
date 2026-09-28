"""Exercise the actual JavaScript embedded in both Safari detection paths."""
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'safari_youtube_nowplaying.applescript').read_text()
expressions = []
for name in ('probeJS', 'js'):
    start = source.index('set ' + name + ' to ')
    end = source.index('\n\t\t\n', start)
    chunks = re.findall(r'"(?:\\.|[^"\\])*"', source[start:end])
    expressions.append('\n'.join(json.loads(c) for c in chunks))
with tempfile.TemporaryDirectory() as temp:
    script = Path(temp) / 'playback.js'
    script.write_text('const expressions=' + json.dumps(expressions) + ';\n' +
                      (ROOT / 'tests/playback_cases.js').read_text())
    subprocess.run(['osascript', '-l', 'JavaScript', str(script)], check=True)
