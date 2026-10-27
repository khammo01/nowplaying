#!/usr/bin/env python3
"""Routed volume must not be replaced by a fixed device level or malformed data."""
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import contextlib
import io
from types import SimpleNamespace
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('volume',Path(__file__).resolve().parents[1]/'media_volume_read.py')
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder)/'models.plist'
 def check(models,expected):
  p.write_bytes(plistlib.dumps({'models':models}));assert mod.soundsource_percent(p)==expected
 check([{'uuid':'SystemInputUUID','volume':1.0},{'uuid':'SystemOutputUUID','volume':.3125}],31)
 check([{'uuid':'SystemOutputUUID','volume':.25}],25)
 check([{'uuid':'SystemOutputUUID','volume':0}],0)
 check([{'uuid':'SystemOutputUUID','volume':1}],100)
 check([{'uuid':'SystemInputUUID','volume':.5}],None)
 for v in [True,-.1,1.1,'31',float('nan')]:check([{'uuid':'SystemOutputUUID','volume':v}],None)
 p.write_bytes(b'incomplete');assert mod.soundsource_percent(p) is None
 p.unlink();assert mod.soundsource_percent(p) is None
 cache=Path(folder)/'cache';cache.mkdir()
 cached=cache/'soundsource-volume-percent'
 for value,expected in [('63',63),('0',0),('100',100),('101',None),('-1',None),('bad',None)]:
  cached.write_text(value);assert mod.cached_percent(cached)==expected
 def no_audio_queries(argv,**kwargs):
  assert argv==['/usr/bin/pgrep','-x','SoundSource'],argv
  return SimpleNamespace(returncode=1)
 with patch.object(mod,'__file__',str(Path(folder)/'media_volume_read.py')),patch.object(mod.subprocess,'run',side_effect=no_audio_queries):
  for value,expected in [('63',63),('bad',0),(None,0)]:
   if value is None:cached.unlink()
   else:cached.write_text(value)
   output=io.StringIO()
   with contextlib.redirect_stdout(output):mod.main()
   assert output.getvalue().strip()==str(expected),output.getvalue()
print('Passed routed-volume identity, cache fallback and no-Core-Audio-query checks.')
