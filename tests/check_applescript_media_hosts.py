"""Exercise the fast AppleScript host prefilter against real and lookalike URLs."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'safari_youtube_nowplaying.applescript').read_text()
start = source.index('on hostname_from_url')
end = source.index('end is_media_url', start) + len('end is_media_url')
handlers = source[start:end]

cases = {
    'https://www.youtube.com/watch?v=abc': True,
    'https://youtube.com/shorts/abc': True,
    'https://music.amazon.com/albums/abc': True,
    'https://www.primevideo.com/detail/abc': True,
    'https://www.amazon.com/dp/example': False,
    'https://www.amazon.com/dp/example?redirect=music.amazon.com': False,
    'https://youtube.com.example.test/watch?v=abc': False,
    # The homepage can host YouTube's real audible miniplayer. The browser-side
    # probe rejects muted hover previews before they can become Now Playing.
    'https://www.youtube.com/': True,
    'https://www.youtube.com/results?search_query=test': False,
}

checks = []
for url, expected in cases.items():
    value = 'true' if expected else 'false'
    checks.append(
        f'if my is_media_url("{url}") is not {value} then error "Unexpected media policy for {url}"'
    )

with tempfile.TemporaryDirectory() as temp:
    script = Path(temp) / 'media-hosts.applescript'
    script.write_text(handlers + '\n' + '\n'.join(checks) + '\nreturn "ok"\n')
    result = subprocess.run(['osascript', str(script)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == 'ok', result.stdout

print(f'Passed {len(cases)} AppleScript media-host checks.')
