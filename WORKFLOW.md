# BG3 Inventory Rework — Technical Workflow Reference

## Overview

A custom BG3 mod that adds a unified inventory panel showing all party members' items with **full native BG3 tooltips** (description, damage, AC, comparison panel, passives). This is the first known BG3 mod to achieve fully-functional native item tooltips in a custom UI panel.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Server (Lua)                                            │
│  BootstrapServer.lua → DataStore.lua → NetHandlers.lua   │
│  Collects items via Ext.Entity from all party members    │
│  Sends data to client via NetMessage                     │
└────────────────────────┬─────────────────────────────────┘
                         │ Net: InvRework_FullInventory
┌────────────────────────▼─────────────────────────────────┐
│  Client (Lua)                                            │
│  BootstrapClient.lua → InventoryPanelVM.lua              │
│  InventoryUI.lua → NetHandlers.lua                       │
│                                                          │
│  Grabs native VMInventorySlot objects from Noesis VM     │
│  Populates XAML panel via custom ViewModel                │
└────────────────────────┬─────────────────────────────────┘
                         │ DataContext binding
┌────────────────────────▼─────────────────────────────────┐
│  XAML (Noesis 3.1.6 / WPF-like)                          │
│  InventoryPanel.xaml                                     │
│  ListBox + ListBoxItem ControlTemplate + LSEntityObject  │
│  Direct LSTooltip (no ToolTip wrapper)                   │
└──────────────────────────────────────────────────────────┘
```

## File Locations

**Canonical source (git repo + junction, edits go here):**
```
C:\Users\BogdanMichon\Documents\BaldursGateInventory\Mod\
├── GUI\Pages\
│   ├── InventoryPanel.xaml                ← Unified inventory XAML
│   └── ArmoryPanel.xaml                   ← Armory panel XAML
├── ScriptExtender\Lua\Client\
│   ├── InventoryPanelVM.lua               ← Inventory ViewModel + NativeSlots + INVRW_SlotWrapper type
│   ├── ArmoryPanelVM.lua                  ← Armory ViewModel + equipped slots + equip action
│   ├── InventoryUI.lua                    ← F10 toggle, panel registration
│   └── NetHandlers.lua                    ← Client net message handlers
├── ScriptExtender\Lua\Server\
│   ├── InventoryCollector.lua             ← Item collection + equipped detection (Osi + inventory container)
│   ├── ItemMover.lua                      ← Equip/move actions via Osi.Equip
│   ├── DataStore.lua                      ← Data storage + query
│   └── NetHandlers.lua                    ← Server net message handlers
└── ScriptExtender\Lua\
    ├── BootstrapClient.lua
    └── BootstrapServer.lua
```

**Steam mod path (junction → Mod\, do not edit here directly):**
```
C:\Program Files (x86)\Steam\steamapps\common\Baldurs Gate 3\Data\Mods\BG3InventoryRework\
```

**Unpacked vanilla game XAML (read-only reference):**
```
C:\Users\BogdanMichon\Documents\BG3Unpacked\Game\Game\
├── Mods\MainUI\GUI\Pages\Container.xaml   ← Native inventory (reference pattern)
└── Public\Game\GUI\Library\
    ├── DataTemplates.xaml                  ← BaseInvContainerItemStyle
    ├── Tooltips.xaml                       ← ItemsTooltip, CompareTooltipTemplate
    └── Theme\DefaultTheme.Styles.xaml      ← LSTooltipStyle, NoPinTooltipTemplate
```

## Key Breakthrough: Native Tooltips in Custom Panels

### The Problem
BG3's C++ engine lazily populates `VMTooltipItem` fields (TechnicalDescription, Damages, ArmorSection) only under specific conditions. Using `ItemsControl` + `DataTemplate` or wrapping `LSTooltip` in a `<ToolTip>` element gives partial data (name, icon, passives) but description/stats text stays empty.

### The Solution
Replicate the **exact native Container.xaml hierarchy**:

```
Border (ls:TooltipExtender.Owner = SelectedChar)
  └── ListBox (ItemsSource = NativeSlots collection)
       └── ListBoxItem (ControlTemplate)
            └── ls:LSEntityObject
                  ├── DataContext = "{Binding Object}"        ← VMItem
                  ├── EntityRef = "{Binding EntityHandle}"    ← from VMItem
                  └── ToolTip
                       └── ls:LSTooltip (DIRECT, no wrapper)
                            └── Content = "{Binding DataContext.Object,
                                  RelativeSource=TemplatedParent}"
```

**Critical requirements:**
1. Must use `ListBox` with `ItemContainerStyle` (NOT `ItemsControl` + `ItemTemplate`)
2. `ListBoxItem` must have a `ControlTemplate` containing `ls:LSEntityObject`
3. `LSTooltip` must be direct (NO `<ToolTip>` wrapper element)
4. Must feed raw `VMInventorySlot` objects from the game's own Noesis VM
5. Parent `Border` needs `ls:TooltipExtender.Owner` for character context

### What Doesn't Work (tried and failed)
- `ItemsControl` + `DataTemplate` → partial tooltip (no description/stats)
- `<ToolTip Style="{x:Null}"><ls:LSTooltip/></ToolTip>` → partial tooltip
- Bare `LSTooltip` as ToolTip value without ListBox context → empty border
- `Template="{StaticResource NoPinTooltipTemplate}"` → empty border
- Setting `TooltipExtender.Owner` / `TooltipExtender.Content` on LSTooltip → kills comparison panel

## Data Flow: How NativeSlots Gets Populated

### 1. Finding the Overlay Widget
```lua
local root = Ext.UI.GetRoot()
local contentRoot = root:Find("ContentRoot")
-- Scan children[0..30] for widget named "Overlay"
local overlay = children[i]  -- where Name == "Overlay"
local dc = overlay.DataContext
local cp = dc.CurrentPlayer
```

### 2. Collecting VMInventorySlot Objects

**Per character, `char.Inventories` contains:**
- `Inventories[1]` = bag inventory (same as `char.Inventory`)
- `Inventories[2]` = equipped items

**Important:** Only use `Inventories` (plural), NOT `Inventory`. Using both causes duplicates since `Inventory == Inventories[1]`.

### 3. Finding Party Characters

**Primary path:** `dc.Data.PartyCharacters` (flat list)
- Used by native `PartyPanel.xaml`
- Contains all party member character VMs

**Fallback path:** `dc.Data.Players[i].PartyGroups[j].Characters` (hierarchical)
- Used by native `PlayerPortraits.xaml`
- Grouped by player, then by party group

**Deduplication:** Compare `tostring(char.Inventories)` pointers to skip SelectedCharacter (already added first).

**Note:** `cp.Characters`, `cp.PartyCharacters`, `cp.Party` are all nil — these don't exist on CurrentPlayer. Party characters are only accessible via `dc.Data.PartyCharacters`.

### 4. Other Noesis VM Paths (documented for reference)
```
dc.Data.Players                              ← LSPlayerList
dc.Data.Players[i].PartyGroups[j].Characters ← per-group characters
dc.Data.PartyCharacters                      ← flat party character list
cp.SelectedCharacter                         ← currently selected char
cp.SelectedCharacter.Inventory               ← same as Inventories[1]
cp.SelectedCharacter.Inventories[1]          ← bag inventory
cp.SelectedCharacter.Inventories[2]          ← equipped items
cp.ContainerInventoryList                    ← empty unless native inventory is open
cp.PartyInventory                            ← merged party inventory (untested)
```

## ViewModel Types

```lua
-- Panel-level ViewModel
INVRW_InventoryPanelVM = {
    PanelVisible   : Bool
    StatusText     : String
    Items          : Collection   -- INVRW_InventoryItem (legacy, used by ItemCardTemplate)
    EquipSlots     : Collection   -- INVRW_EquipSlot
    NativeSlots    : Collection   -- Raw VMInventorySlot objects (used by ListBox)
    ToggleCommand  : Command
    RefreshCommand : Command
    SelectedChar   : Object       -- SelectedCharacter VM for TooltipExtender.Owner
}

-- Per-item ViewModel (legacy — kept for ItemCardTemplate fallback)
INVRW_InventoryItem = {
    Name, ItemType, Rarity, OwnerName, UUID, Icon : String
    Weight, Value, Description, DamageStr, ArmorClass, SpecialEffects : String
    IsEquipped, HasGameItem : Bool
    GameItem, GameItemBrush, GameItemOwner, GameItemEntityHandle : Object
}

-- Equipment slot display
INVRW_EquipSlot = {
    SlotLabel : String
    ItemName  : String
    IsEmpty   : Bool
}
```

## Noesis/SE Gotchas

1. **Never cache Noesis proxies** — SE Lua proxies for Noesis objects expire between calls. Always re-find widgets and re-acquire DataContext fresh each time.

2. **XAML namespaces must use `http://`** — Using `https://` in namespace URIs crashes the game.

3. **pcall everything** — Noesis property access can throw at any time. Wrap every access in pcall.

4. **`return` inside pcall doesn't exit parent function** — `pcall(function() ... return end)` only exits the anonymous function. Use a flag variable for control flow.

5. **Inventory == Inventories[1]** — They're the same object. Only use `Inventories` to avoid duplicates.

6. **ToolTip wrapper vs direct LSTooltip** — The `<ToolTip>` wrapper element creates a standard WPF popup that the game engine doesn't fully own. Direct `LSTooltip` as ToolTip value requires the ListBox/ListBoxItem/ControlTemplate context to work.

7. **PlacementTarget bindings don't work in Noesis** — Unlike WPF, you can't bind to `PlacementTarget.(attached property)` to cross the tooltip popup boundary.

## Keybinds

- **F10** — Toggle inventory panel (also tries to bind VM on first press)
- **F11** — Toggle Armory panel
- **F9** — Debug probe (ShortDescription/Icon deep-dive)
- **T** — Pin/focus tooltip (native game binding via `UIPinTooltip` event) — allows hovering LSTag elements for nested tooltips

## Testing Workflow

1. Edit files in `C:\Users\BogdanMichon\Documents\BaldursGateInventory\Mod\` (the git repo)
2. In-game: open SE console, run `reset` to reload Lua (or restart game for XAML changes)
3. Press F10 (inventory) or F11 (armory) to open panel
4. Hover items to test tooltips
5. Check SE console for `[BG3InventoryRework]` log lines
6. Commit when stable: `git add Mod/path/to/file && git commit -m "..."`

> The Steam mod path is a directory junction pointing to `Mod/` — no copy step needed.

## Tooltip Pinning

To enable tooltip pinning (press T to focus, hover LSTag for nested tooltips):

1. Set `CanBePinned="True"` on the `ls:LSTooltip` element
2. Add `<ls:LSInputBinding Style="{DynamicResource PinTooltipBindingStyle}"/>` inside the panel's Grid — this bridges the `UIPinTooltip` input event to the engine's `PinTooltipCommand`

The key mapping (T) is handled by the C++ engine, not XAML. The `LSInputBinding` just connects the event.

## Armory Panel

### Overview
The Armory panel (F12) is a dedicated equipment management view with a **left panel** showing equipped slots and a **right panel** showing filterable items for each slot. Click an equipped slot on the left to filter the right side to compatible items, then click an item to equip it.

### Files
```
GUI\Pages\ArmoryPanel.xaml              ← Armory XAML
ScriptExtender\Lua\Client\ArmoryPanelVM.lua  ← Armory ViewModel
ScriptExtender\Lua\Server\ItemMover.lua      ← Equip action (server-side Osi.Equip)
ScriptExtender\Lua\Server\InventoryCollector.lua ← Item collection + equipped detection
```

### Equipped Detection (IMPORTANT)

`InventoryMember.EquipmentSlot` is **NOT** an equipped indicator — it's a container slot index and is always >= 0 for all items. Using it marks every item as "equipped".

**Correct approach (two methods combined):**
1. `Osi.GetEquippedItem(charUUID, slotName)` — works for armor, vanity, and accessory slots but **returns nil for weapon slots** (MeleeMainHand, MeleeOffHand, RangedMainHand, RangedOffHand). Root cause unknown.
2. Equipment inventory container — `InventoryOwner.Inventories[2]` is the equipment container for each character. All items in it are equipped. This catches the weapon slots that Osi misses.

Both methods run in `InventoryCollector._markEquippedItems()`.

### Equipped Slot Icons

Equipped slot icons use `ItemIcon` string property (a `pack://` URI built from DataStore `item.Icon`) instead of `NativeObject.Icon` (which is a stale Noesis ImageBrush proxy). The `LSEntityObject` remains for native tooltip binding only — it has no visual children.

```lua
-- In ArmoryPanelVM.lua PopulateEquippedSlots():
local iconName = equipped.Icon or "Item_Unknown"
wrapper.ItemIcon = "pack://application:,,,/Core;component/Assets/ControllerUIIcons/items_png/" .. iconName .. ".DDS"
```

```xml
<!-- In ArmoryPanel.xaml EquippedSlotStyle: -->
<!-- LSEntityObject for tooltip only (no Rectangle inside) -->
<ls:LSEntityObject x:Name="ItemEntity" ... />
<!-- Separate Image for icon display -->
<Image x:Name="ItemIcon" Source="{Binding ItemIcon}" ... />
```

### Equip Action

- Client sends `InvRework_EquipItem` net message with `{itemUUID, targetCharUUID}`
- Server calls `Osi.Equip(char, item, 1, 0, 0)` — 4th param `0` suppresses "Item Received" notification
- Client uses `_equipBusy` flag (800ms lockout) to prevent rapid clicks from crashing the game

### ViewModel Types

```lua
INVRW_SlotWrapper = {
    NativeSlot   : Object   -- VMInventorySlot for native tooltip
    NativeObject : Object   -- VMItem (the .Object of the slot)
    NativeHandle : Object   -- EntityHandle for LSEntityObject.EntityRef
    Rarity       : String   -- "Common", "Uncommon", "Rare", "VeryRare", "Legendary"
    StackSize    : Int32
    ShowStack    : Bool
    SlotIcon     : String   -- Per-slot silhouette icon (empty) or EQ_blank (equipped)
    HasItem      : Bool     -- Controls visibility of LSEntityObject + ItemIcon
    ItemIcon     : String   -- pack:// URI for item icon (from DataStore)
}

INVRW_ArmoryPanelVM = {
    PanelVisible, StatusText, SelectedChar, CharacterName,
    ActiveSlotLabel, SelectedIndex, EquippedSlotIndex,
    EquipSelectedCommand, EquippedSlotClickCommand,
    ToggleCommand, RefreshCommand,
    EquippedSlots : Collection,    -- INVRW_SlotWrapper (left panel)
    FilteredItems : Collection,    -- INVRW_SlotWrapper (right panel)
    SlotActive_* : String,         -- "True"/"False" per slot chip
    SelectSlot_* : Command         -- Per slot chip
}
```

### Equipment Slot IDs
These are the `Equipable.Slot` values from the entity system, used as keys in both DataStore and the Armory filter:
```
Helmet, Breast, Cloak, MeleeMainHand, MeleeOffHand,
RangedMainHand, RangedOffHand, Gloves, Boots,
Amulet, Ring, Ring2, Underwear, VanityBody, VanityBoots
```
Note: Both Ring slots use `Slot="Ring"` in `Equipable.Slot` — the Ring vs Ring2 distinction comes from the equipment slot index, not the Equipable component.

## Current State (2026-03-21)

**Unified Inventory (F10):**
- Full native tooltips working (description, damage, AC, passives, comparison panel)
- Tooltip pinning works (T key) — nested LSTag tooltips accessible
- All party members' items displayed (bag + equipped)
- No duplicates
- Equipment slots row showing slot labels + item names
- Panel draggable, close button, refresh button
- Status bar showing item count

**Armory (F11):**
- Equipped slots left panel with correct icons (DataStore-based, no Noesis proxy staleness)
- Equipped detection working via Osi + inventory container fallback
- Click-to-filter: clicking equipped slot filters right panel to compatible items
- Click-to-equip: clicking item in right panel equips it (800ms lockout prevents crashes)
- Native tooltips on both equipped slots and item grid
- Character auto-detection via OwnerName vote counting
- Rarity frames on both panels
- No "Item Received" notification spam

## Dev Tools

### Overview

Three tools accelerate the mod iteration loop:

| Tool | File | Purpose |
|---|---|---|
| XAML + Lua linter | `Tools/lint.py` | Catches crashes and anti-patterns before game launch |
| SE console commands | `Client/DevCommands.lua` | In-game state inspection and VM reload |
| Log watcher | `Tools/watch_log.py` | Real-time filtered tail of SE output |

The pre-commit hook (`.git/hooks/pre-commit`) runs the linter automatically on every `git commit`.

---

### Tool 1 — XAML + Lua Linter (`Tools/lint.py`)

Runs in < 1 second. Exit code 0 = clean; non-zero = errors found.

```bash
python Tools/lint.py                          # lint all Mod/ files
python Tools/lint.py Mod/GUI/Pages/Foo.xaml   # lint specific file(s)
```

**XAML rules:**

| Severity | Rule |
|---|---|
| ERROR | `https://` in xmlns URIs (crashes game — must be `http://`) |
| ERROR | `<ToolTip>` wrapping `ls:LSTooltip` (wrong hierarchy) |
| WARN | `ItemsControl` in same file as `ls:LSTooltip` (prefer ListBox) |
| WARN | `DataTrigger` on `Tag` property (use `Trigger Property="Tag"`) |
| WARN | Horizontal `StackPanel` with `Width="*"` Grid columns (use WrapPanel) |
| WARN | Unknown `pack://` assembly names |

**Lua rules:**

| Severity | Rule |
|---|---|
| ERROR | `https://` in any string literal |
| ERROR | Net message name mismatch (client sends with no server listener, or server broadcasts with no client listener) |
| WARN | bare `return` inside `pcall(function()` |
| WARN | `.Inventory` usage (not `.Inventories`) |

---

### Tool 2 — SE Console Commands (`Client/DevCommands.lua`)

Type in the SE console (F11 dev console):

| Command | What it does |
|---|---|
| `!invrw_reload` | Re-runs `Init + TryBind + OnDataUpdated` on both VMs — faster than full `reset` |
| `!invrw_dump` | Prints DataStore summary: total items, owners, type breakdown, rarity breakdown |
| `!invrw_open inventory` | Toggles the Inventory panel |
| `!invrw_open armory` | Toggles the Armory panel |
| `!invrw_status` | Prints binding state of both VMs + live VM property values |

---

### Tool 3 — Log Watcher (`Tools/watch_log.py`)

Start once per session. Tails `gold.*.log` in BG3's `bin\` folder, filters to mod output, writes `Tools/last_session.log` (overwritten each run).

```bash
python Tools/watch_log.py                          # filter [BG3InventoryRework]
python Tools/watch_log.py --filter "[Armory]"      # only armory subsystem
python Tools/watch_log.py --filter "[Inventory]"   # only inventory subsystem
python Tools/watch_log.py --filter ""              # all SE output
```

`Tools/last_session.log` is gitignored. Claude Code reads it to diagnose issues without copy-paste.

---

### Revised Iteration Workflows

**Lua changes:**
1. Edit `Mod/ScriptExtender/Lua/**/*.lua`
2. `python Tools/watch_log.py` running in a terminal
3. SE console: `reset` or `!invrw_reload` (VM-only changes)
4. Check terminal / ask Claude (reads `last_session.log`)
5. `!invrw_dump` / `!invrw_status` to inspect in-game state

**XAML changes:**
1. Edit `Mod/GUI/**/*.xaml`
2. `python Tools/lint.py` — fix any errors *before* launching
3. Launch BG3, check `last_session.log`, test, kill, repeat

**Committing:**
1. `git add ...` + `git commit` — pre-commit hook runs linter automatically
2. Errors block the commit; warnings pass through
