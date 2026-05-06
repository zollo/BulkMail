# BulkMail

Bulk mail sending for World of Warcraft, made really easy.

BulkMail lets you automatically send items to alts based on configurable rules (item ID, item type, PeriodicTable sets, and global exclusions). Open the mailbox, and matching items are queued for sending automatically. A compact QTip window shows the queue and lets you manage it on the fly.

Originally written by **hyperactiveChipmunk**. Maintained by **NeoTron**.

---

## Module Structure

The addon is organized into focused source files, loaded in order from `BulkMail2.toc`:

| File | Responsibility |
|---|---|
| `Core.lua` | Addon object creation, library handle declarations, C_Container / AddOns API compat shims, named color constants, shared state initialization, and small utility functions (`color`, `linkToId`, `_QTipClose`, `_addIndentedCell`) used by multiple modules. |
| `TablePool.lua` | Lightweight memory pool (`new`, `del`, `newHash`, `newSet`, `deepDel`) that recycles Lua tables to reduce GC pressure. |
| `Compat.lua` | One-shot migration helpers (`_convertBulkMail2DB`, `_convertAce2ToAce3Realm`) that upgrade old BulkMail 2 / Ace2 saved variables. Called once during `OnInitialize` then discarded. |
| `RulesCache.lua` | Builds and queries `rulesCache` — the flattened item→destination lookup derived from `autoSendRules`. Exposes `_rulesCacheBuild` and `_rulesCacheDest`. |
| `SendQueue.lua` | Manages the per-session send cache (`sendCache`). Contains bag iteration, item mailability checks, send-cost updates, and `organizeSendCache`. All send-cache functions are exposed on `mod` for cross-module use. |
| `Send.lua` | Public sending methods: `mod:Send`, `mod:StopBulkSend`, `mod:QuickSend`, `mod:AddDestination`, `mod:RemoveDestination`. |
| `Hooks.lua` | All `SecureHook` / `RawHookScript` method implementations — container frame clicks, tab switches, name edit-box changes, and the Send button handler. |
| `Events.lua` | `MAIL_SHOW`, `MAIL_CLOSED`, `MAIL_SEND_SUCCESS`, `SECURE_TRANSFER_CANCEL`, `MAIL_FAILED`, `PLAYER_INTERACTION_MANAGER_FRAME_HIDE`, `CheckMailFrameChanged`, plus `OnEnable` / `OnDisable`. |
| `GUI_SendQueue.lua` | The floating send-queue QTip window (`ShowSendQueueGUI`, `HideSendQueueGUI`, `RefreshSendQueueGUI`) and the inline recipient edit bar (`_createOrAttachRecipientBar`). |
| `GUI_EditRules.lua` | The AutoSend Rules editor QTip window (`OpenEditTooltipGUI`, `RefreshEditTooltipGUI`), rule-list rendering, and the Ace3/PT31/Inventory dropdown menus for adding new rules. |
| `Config.lua` | `OnInitialize` (AceDB setup, options table, LDB data object, PT31 LoD loading), `OptReg`, `OpenConfigMenu`, `ToggleConfigDialog`, and `StaticPopupDialogs` definitions. |

---

## Usage

- **Open the mailbox** — BulkMail auto-fills the send queue based on your rules.
- **Alt-Right-Click** an item in your bags to add/remove it from the queue.
- **Alt-Left-Click** an item to bulk-add/remove all stacks of that item.
- **Ctrl-Shift-Left-Click** to quick-send a single item immediately.
- Click the **Edit Destinations** button (or `/bm autosend edit`) to manage rules.
- The **recipient bar** below the queue lets you type or auto-complete the destination.

## Slash Commands

```
/bulkmail   (or /bm)
```

---

## Version History

- **v9.x** — Multi-file module restructure; bug fixes; C_Container compat; TSM integration; recipient bar with auto-complete.
- **v8.x** — Dragonflight bag API compat (C_Container).
- **v7.x** — Legion update.
- **v4.x** — Full Ace3 rewrite (AceDB-3.0, LibQTip-1.0, LibDropdown-1.0).
- **v3.x** — Wrath of the Lich King (Ace2).
- **v2.x** — Burning Crusade (Ace2, original BulkMail 2 codebase by hyperactiveChipmunk).
