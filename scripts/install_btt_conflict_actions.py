#!/usr/bin/env python3
"""Install only the exact actions used by the multi-video conflict chooser."""

from install_btt_fast_paths import (
    NEW_TRIGGERS,
    add_trigger,
    load_local_triggers,
    update_trigger,
)

NAMES = ("mac_youtube_resolve_conflict", "mac_youtube_pause_all")


def main() -> int:
    triggers = load_local_triggers()
    by_name = {item.get("BTTTriggerName"): item for item in triggers}
    for name in NAMES:
        command = NEW_TRIGGERS[name]
        current = by_name.get(name)
        if current:
            actions = current.get("BTTActionsToExecute") or []
            if not actions:
                raise SystemExit(f"Named trigger has no action: {name}")
            update_trigger(
                actions[0]["BTTUUID"],
                {
                    "BTTActionCategory": 0,
                    "BTTPredefinedActionType": 206,
                    "BTTShellTaskActionScript": command,
                },
            )
        else:
            add_trigger(
                {
                    "BTTTriggerType": 643,
                    "BTTTriggerClass": "BTTTriggerTypeOtherTriggers",
                    "BTTTriggerName": name,
                    "BTTActionsToExecute": [
                        {
                            "BTTActionCategory": 0,
                            "BTTPredefinedActionType": 206,
                            "BTTShellTaskActionScript": command,
                        }
                    ],
                }
            )
        print(f"updated {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
