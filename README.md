Quester

Lightweight quest helper for WoW Forever client 1.60.1.

First Use

1. Restart WoW if the addon does not yet appear in the addon list; otherwise use /reload.
2. Enable Quester in the addon list.
3. Under /macro → General Macros, drag the global QuesterTarget macro onto your action bar.
4. The compact bar displays one 30-pixel icon for each detected enemy target. Left-click an icon to target that enemy; its name and quest progress are shown in the tooltip. Drag the handle on the left to reposition the bar, and right-click the handle to collapse or expand it. The handle remains visible while collapsed, and the state is saved. /quester hide hides the entire bar; /quester shows it again.
5. For collection quests, target a suitable enemy or mouse over it. If its tooltip contains an open quest objective that can be matched unambiguously, the actual NPC name appears as a target icon and in the macro.
6. Talk to a quest giver: available quests are selected and accepted automatically. Hold Shift to keep quest acceptance manual.

The macro is updated whenever quest data changes. During combat, updates are delayed until combat ends. Each click searches open enemy objectives in quest log order and stops at the first existing living target. The previous target selection is cleared first. The macro does not start an attack.

Commands

Command	Effect
/quester or /quester show	Show target icons
/quester hide	Hide target icons
/quester inspect	Open a copyable diagnostic report for the targeted NPC
/quester debug	Print original objective text and detected names in chat
/quester status	Show help, settings, and the number of omitted targets
/quester auto on / /quester auto off	Explicitly enable/disable automatic quest acceptance and turn-in
/quester resume	Clear the error lock; then talk to the quest giver again
/quester turnin	Toggle automatic quest turn-in only
/quester auto	Toggle automatic quest acceptance and turn-in together
/quester macro	Toggle macro updates; the existing macro remains in place
/quester trivial	Also select grey/trivial quests in the selection window
/quester update	Request a macro update

Quest acceptance, quest turn-in, selection of grey quests, and macro updates are enabled by default. Previously saved explicit settings are preserved. Settings and the macro are stored account-wide. The macro is populated with the objectives of the currently logged-in character. The name QuesterTarget is reserved for this addon. An old character-specific copy is removed only after the global macro has been created successfully. Afterwards, drag the global macro onto the action bar once again. If the global macro storage is full, the old copy is retained.

Limitations of the First Version

* Enemy names are taken from localized Blizzard text for open kill objectives, including numbered placeholders and simple progress counters such as Forest Wolf: 0/8. Common English plural forms are normalized using a limited mapping, for example Kobold Workers to Kobold Worker. Other NPC names remain unchanged. For collection and kill objectives, unambiguous NPC tooltip mappings are preferred. Without such an observation, collection objectives remain unknown. World objects are not targetable enemies. /quester debug displays the objective text when needed; no external quest database is required.
* Entries provided by the quest log API are taken into account. Collapsed categories may hide objectives depending on the client. If objectives are missing, expand the categories and run /quester update.
* The macro is limited to 255 bytes. Excess targets are omitted; /quester status shows how many. Individual icons can still target enemies beyond this limit. Completed objectives free up space again.
* One free global macro slot is required. Execution always happens through your own key press or click.
* Grey quests are also selected by default; /quester trivial toggles this behavior. If you manually open the details of a grey quest, automatic acceptance will also apply; holding Shift pauses it.
* Quests ready for turn-in are opened and completed at the NPC. If there is no choice of reward, or exactly one selectable reward, it is collected automatically. If there are multiple selectable rewards or a monetary cost, manual selection or confirmation is preserved. Holding Shift pauses both acceptance and turn-in.

In-Game Testing

Open a quest giver with multiple quests, test the Shift interruption, accept an enemy quest, and test the macro. After progress, completion, or abandonment, the macro text should update accordingly. During combat, the text must remain unchanged and update once combat ends. /console scriptErrors 1 enables Lua error messages.

API reference: Blizzard QuestLog documentation and GossipInfo documentation, mirrored from Blizzard’s UI source code.

The icons use protected WoW action buttons. During combat, existing icons remain clickable; changes to targets, position, or visibility are applied only afterwards. The macro and icons use the same name detection logic. If there are no enemy objectives, only the small handle remains visible. The symbols are numbered target icons, not NPC portraits.

Diagnostics for Collection Quest Enemies

After /reload, target a possible loot enemy for an open collection quest and run /quester inspect. Copy the highlighted report with Ctrl+C or Cmd+C. The diagnostic window opens only through this command; Escape closes it.

The report contains the client build, language, NPC name and NPC ID, raw tooltip lines including unknown beta fields, quest log objectives, and available quest map data. Missing or failing APIs are marked accordingly. If no modern tooltip API is available, a separate tooltip is used for reading the data. If objective text has not yet loaded, briefly mouse over the NPC and try again.

The diagnostic snapshot remains in memory only until the next reload. Automatic tooltip detection runs independently of the diagnostic window.

Learned Quest Targets

Quester monitors target changes and mouseover units. In the Forever Tooltip, a quest heading (type 17, quest ID) links the following objective lines (type 8) to a quest. A mapping is stored only if exactly one open collection or kill objective from that active quest matches the tooltip text after removing the progress counter. The NPC must be attackable; its actual name and NPC ID are used.

Mappings are stored account-wide in QuesterDB.learnedTargets, separated by client build and language. Multiple NPC types can be associated with a single objective. Completed or abandoned quests no longer provide active macro targets, but the mapping remains stored for future acceptance or for other characters. New beta builds are learned again from scratch.

Quester learns the quest association displayed by the game, not drop chances or a complete loot table. Unknown NPC types are recognized only after an encounter. Missing, conflicting, or inaccessible tooltip data does not create a mapping. The macro and protected icons are updated during combat only after combat ends.

If quest acceptance or turn-in was disabled, use /quester auto on, then talk to the NPC again. /quester debug additionally displays the most recent automation action. Dialogue actions are delayed briefly and discarded if the quest window is closed or the active quest changes.

Protection Against Failed Quest Loops

If the client reports a full inventory, full quest log, or an item limit after an automatic action, Quester pauses quest acceptance and turn-in. In addition, the same action for the same quest will not be repeated without confirmed success. Cancelling discards pending actions and prints a single notification in chat.

Once the inventory has actually been relieved — through more free slots or fewer items — or space has been freed in the quest log, the lock is removed automatically. If the quest dialogue is still open, processing continues automatically; if it has been closed, simply talk to the NPC again. Inventory events that do not change available space, and merely rearranging item stacks, do not trigger another attempt. If the action fails again, Quester pauses until space is freed again. During combat, continuation is delayed until combat ends. /quester resume remains available as an optional manual reset.