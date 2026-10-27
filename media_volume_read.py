#!/usr/bin/env python3
"""Read routed output volume without sending keys or changing audio state."""
import math
import plistlib
from pathlib import Path
import subprocess


def cached_percent(path):
    try:
        value = Path(path).read_text().strip()
        return int(value) if value.isdigit() and 0 <= int(value) <= 100 else None
    except (OSError, ValueError):
        return None


def soundsource_percent(path):
    try:
        with Path(path).open('rb') as stream:
            models = plistlib.load(stream).get('models', [])
        output = next(model for model in models if model.get('uuid') == 'SystemOutputUUID')
        value = output.get('volume')
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return None
        if not math.isfinite(value) or not 0 <= value <= 1:
            return None
        return int(value * 100 + 0.5)
    except (OSError, ValueError, TypeError, StopIteration, plistlib.InvalidFileException):
        return None


def main():
    # SoundSource's software level is independent of the device's native 100%.
    # Its own saved model also follows changes made with the native volume keys.
    running = subprocess.run(['/usr/bin/pgrep', '-x', 'SoundSource'],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    if running:
        value = soundsource_percent(Path.home() / 'Library/Application Support/SoundSource/Models.v2.plist')
        if value is not None:
            print(value)
            return
    # Polling Core Audio from a new osascript process rebuilds SoundSource/ARK
    # taps. Fall back to the controller's cache without touching audio APIs.
    value = cached_percent(Path(__file__).resolve().parent / 'cache/soundsource-volume-percent')
    if value is not None:
        print(value)
        return
    print(0)


if __name__ == '__main__':
    main()
