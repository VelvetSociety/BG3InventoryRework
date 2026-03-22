# BG3 Inventory Rework Mod — UI Upgrade Plan

## Current Status

Phase 1-2 are **complete and working in-game**:
- Mod loads via BG3SE + BG3 Mod Manager
- Inventory collection works (25 items from 2 characters)
- ImGui windows render with text tables (F11 = Unified Inventory, F12 = Armory)
- Equip/move actions work via `Osi.Equip` / `BroadcastMessage`
- Hot reload via `reset` in SE console

## Goal

Make the UI **look like the base game** — grid of square item icons, right-click context menus, proper game art style.

---

## The Problem

BG3SE's ImGui Lua API does **not** expose `AddImage` / `AddImageButton`, so we **cannot display game item icons** in ImGui. The current text table is functional but doesn't match BG3's visual style.

---

## Two Approaches

### Option A: Enhanced ImGui (incremental, limited fidelity)

Improve current ImGui with a grid of colored square buttons.

**What's possible:**
- Grid layout using `AddTable` with N columns (e.g. 8 across)
- Each cell = `AddButton` sized as a square, labeled with item type abbreviation
- Rarity indicated by label prefix: `[C]`, `[U]`, `[R]`, `[VR]`, `[L]`
- Tooltip on hover: full item name, type, rarity, value, weight, owner
- Right-click popup menus via `AddPopup`: Move to [char], Equip on [char]
- Left-click: select item, show details in a side panel

**Visual mockup:**
```
[Search: ___________] [Type: ▼] [Rarity: ▼]
Showing 25 / 25 items

[WPN] [WPN] [ARM] [ARM] [CON] [CON] [SCR] [MSC]
[WPN] [ARM] [ARM] [CON] [MSC] [MSC] [MSC] [MSC]
...
```

**Tooltip content per item:**
```
Spear of Night
Type: Weapon | Rarity: Very Rare
Value: 960 | Weight: 1.8
Owner: Shadowheart
Slot: Main Hand
```

**Pros:**
- Fast to implement (1 session)
- Keeps current working backend code unchanged
- Hot-reloadable via SE console

**Cons:**
- Cannot show actual item icons — just colored text buttons
- Will always look like an overlay, not native game UI
- No drag-and-drop

---

### Option B: Native XAML / NoesisGUI (full game-matching UI)

Replace ImGui with NoesisGUI XAML — the same framework BG3 uses for all its UI.

**What's possible:**
- Full access to game item icons, textures, tooltips, rarity borders
- Right-click menus, drag-and-drop — all native
- Matches the game's art style exactly
- Use `ModType="Extend"` to inject panels alongside existing HUD
- Data binding from Lua to XAML

**Files to create:**
```
Public/BG3InventoryRework/GUI/
├── StateMachines/
│   ├── Keyboard.xaml      — Extend PlayerHUD with toggle events
│   └── Controller.xaml    — Controller input support
├── Pages/
│   ├── UnifiedInventory.xaml  — Merged inventory grid
│   └── ArmoryPanel.xaml       — Equipment paperdoll + item list
└── Resources/
    └── Resources.xaml     — Rarity colors, slot sizes, fonts
```

**Pros:**
- Looks and feels like the real game
- Proper icon grid with actual item art
- Native right-click menus, tooltips, drag-and-drop
- Controller support built-in

**Cons:**
- Significant implementation effort
- Requires XAML/WPF knowledge + NoesisGUI specifics
- More fragile across game patches
- Harder to debug than ImGui

**Research needed before starting:**
- BG3 XAML modding patterns (StateMachine extension, panel injection)
- NoesisGUI data binding from Lua
- How to reference item icon texture atlases (DDS files: 380x380, 144x144, 64x64 variants)
- Existing XAML mods as reference (ImpUI, Better Inventory UI source code)

---

## Recommended Path

**Do Option A first** (enhance ImGui grid) → validates all UX decisions with fast iteration.

**Then Option B** (XAML native) → production-quality UI once gameplay logic is fully stable.

Backend files stay unchanged for both options:
- `DataStore.lua`, `FilterEngine.lua`, `NetHandlers.lua` (client + server)
- `InventoryCollector.lua`, `ItemMover.lua`

---

## Files to modify for Option A

| File | Change |
|---|---|
| `Client/InventoryUI.lua` | Replace text table → grid of buttons with tooltips + right-click popups |
| `Client/ArmoryUI.lua` | Same grid treatment for equippable items list |

## Verification for Option A

1. `reset` in SE console to hot-reload
2. F11 → Unified Inventory shows grid of item buttons
3. Hover over button → tooltip shows item details
4. Right-click → popup with Move/Equip options
5. F12 → Armory shows equipment slots + grid of equippable items
6. Equip action still works through the grid
