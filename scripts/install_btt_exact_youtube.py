#!/usr/bin/env python3
"""Install only the exact-video BTT actions used by queue handoffs."""

from __future__ import annotations

from install_btt_fast_paths import (
    NEW_TRIGGERS,
    SHELL_ACTION_CONFIG,
    add_trigger,
    load_local_triggers,
    update_trigger,
)


EXACT_TRIGGER_NAMES = ("mac_youtube_play_cached", "mac_youtube_play_selected")


def main() -> int:
    triggers = load_local_triggers()
    by_name = {item.get("BTTTriggerName"): item for item in triggers}
    for name in EXACT_TRIGGER_NAMES:
        command = NEW_TRIGGERS[name]
        trigger = by_name.get(name)
        if trigger:
            actions = trigger.get("BTTActionsToExecute") or []
            if not actions:
                raise SystemExit(f"Named trigger has no action: {name}")
            update_trigger(
                actions[0]["BTTUUID"],
                {
                    "BTTPredefinedActionType": 206,
                    "BTTPredefinedActionName": "Execute Shell Script  or  Task",
                    "BTTShellTaskActionScript": command,
                    "BTTShellTaskActionConfig": SHELL_ACTION_CONFIG,
                },
            )
            print(f"Updated {name}")
            continue
        add_trigger(
            {
                "BTTTriggerType": 643,
                "BTTTriggerClass": "BTTTriggerTypeOtherTriggers",
                "BTTTriggerName": name,
                "BTTEnabled2": 1,
                "BTTActionsToExecute": [
                    {
                        "BTTPredefinedActionType": 206,
                        "BTTPredefinedActionName": "Execute Shell Script  or  Task",
                        "BTTShellTaskActionScript": command,
                        "BTTShellTaskActionConfig": SHELL_ACTION_CONFIG,
                    }
                ],
            }
        )
        print(f"Created {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
