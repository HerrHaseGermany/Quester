## Changelog

### 0.5.3

- Automatically clear the inventory lock when space is actually freed and resume open quest dialogues.
- Unchanged inventory events and rearranged item stacks do not trigger new attempts.
- Failed retries pause automation again; closed dialogues are not reopened.

### 0.5.2

- Stop automation on inventory or quest log errors and repeated actions without confirmed success.
- Discard pending actions; the error lock persists across dialogue changes.
- Use `/quester resume` to manually resume after resolving the error.

### 0.5.1

- Right-click the handle to collapse or expand target icons; the handle remains visible.
- Save the collapsed state and defer changes during combat until combat ends.

### 0.5.0

- Automatically turn in quests, including selecting completed quests and collecting rewards with at most one choice.
- Accept and turn in quests after the dialogue loads; discard outdated actions when it closes.
- Add `/quester auto on/off` and `/quester turnin`; select trivial quests by default.
- Multiple reward choices and monetary costs require manual input; Shift pauses both functions.

### 0.4.2

- Add a compact target bar with a dark WoW background and a subtle gold border.
- Replace the Unicode character unsupported by the client with a graphical handle.

### 0.4.1

- Fix tooltip errors when hovering over target icons: the text helper returns only the text, without the replacement count.
- Add a regression test that runs the tooltip OnEnter and OnLeave handlers.

### 0.4.0

- Learn NPC names for collection and kill objectives from structured Forever tooltips.
- Match quest IDs and unfinished objective text unambiguously; exclude completed or ambiguous objectives.
- Store mappings by NPC ID, client build and language; prefer actual names over text detection.
- Add regression tests for the reported Rascally Rodents / Stolen Book / Kobold Worker case.

### 0.3.1

- Add `/quester inspect` to display copyable NPC, tooltip, quest log and map diagnostics.
- Mark unavailable modern APIs and provide tooltip and quest log fallbacks for older clients.
- Open the diagnostic window only on explicit command, preserving target detection behavior.

### 0.3.0

- Replace the large quest window with compact, clickable target icons; show details in tooltips.
- Normalize English plurals through specific noun mappings, including Kobold Workers → Kobold Worker.
- Use protected target buttons and defer layout and target changes during combat.
- Make raw troubleshooting data available through `/quester debug`.

### 0.2.0

- Add a movable quest window with original text, enemy names, detection status and a macro preview.
- Add a global target macro and migrate the old character copy after successful creation.
- Extend detection to numbered placeholders, color codes and simple progress counters.
- Keep the window current during combat and while macro updates are disabled.

### 0.1.1

- Prefer C_QuestLog for quest log queries; retain older global APIs as fallbacks.
- Add a regression test for clients without global quest log functions.

### 0.1.0

- Automatically accept quests, with a Shift pause and optional selection of trivial quests.
- Add a character macro for unfinished enemy objectives, updated when quests change.
- Defer changes during combat, handle macro slot limits and save settings.
