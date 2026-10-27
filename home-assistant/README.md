# NowPlaying page synopsis

Browser metadata extraction remains restricted to the existing media-host whitelist.
YouTube keeps its dedicated player, canonical identity, description and summary logic.
Other allowed sites can provide JSON-LD VideoObject/Course/Article data, description
sections, learning objectives and the active lecture title. Extraction is bounded;
whole-page navigation, unrelated profile text and generic page body text are not used.

## Home Assistant configuration

Copy `nowplaying_synopsis.jinja` into `/config/custom_templates/`, then reload custom
templates. Replace the existing `nowplaying_generate_ai_synopsis` automation using
`nowplaying-synopsis-automation.json` rather than adding a duplicate automation.
The definition uses the existing `ai_task.openai_ai_task` entity.

Import `synopsis_key` in consumers of `sensor.now_playing_ai_synopsis_cache`:

```jinja
{% from 'nowplaying_synopsis.jinja' import synopsis_key %}
{% set a = states.sensor.now_playing_metadata.attributes %}
{% set entries = state_attr('sensor.now_playing_ai_synopsis_cache', 'entries') | default({}, true) %}
{{ entries.get(synopsis_key(a), {}).get('synopsis') | default(a.summary | default(a.description, true) | default('No synopsis metadata is available.', true), true) }}
```

In the incoming media template's `display_synopsis` attribute, use
`synopsis_key(trigger.event.data)` for its cache lookup and fall back to the supplied
summary/description instead of an indefinite generating message. In the cache sensor's
`now_playing_ai_synopsis_ready` event handler, retain `source_hash` alongside synopsis,
basis_kind and generated_at. Existing events without source_hash can default to `''`.
The automation regenerates when the source metadata changes and stores each response
under the captured item identity, so a completed response cannot replace a newer item.

YouTube IDs keep their existing cache keys. Other pages use a URL hash. Udemy course
lecture paths identify individual lessons; learning-path query parameters and fragments
are ignored. No non-YouTube page ID is inserted into the playback video_id field.

For the dashboard's Binge counter, check the actual URL host, since the historical
`media_type: youtube` value also represents other browser video:

```jinja
{% if a.url | default('', true) | lower | regex_match('^https?://([a-z0-9-]+\\.)*(youtube\\.com|youtu\\.be)([:/]|$)') %}
  Binge {{ states('input_number.video_binge_current_score') | int }} / {{ states('input_number.video_binge_high_score') | int }}
{% endif %}
```

The Mac terminal follows the same URL-host rule. Generic video speed remains visible.
