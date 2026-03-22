# BG3 Inventory Rework — Progress Log

## What We Built

A working BG3 mod that adds a **unified inventory panel** merging all party character inventories into a single UI. The panel is fully functional with real BG3 styling, toggled via F10.

## Architecture

```
Server Lua (InventoryCollector.lua)
  │  Collects items from all party characters via Osiris DB
  │  Extracts: UUID, Name, Type, Rarity, Weight, Value, Owner, Icon, Slot,
  │            Description, DamageStr, ArmorClass, SpecialEffects
  │  Uses Ext.Stats.Get() for weapon/armor stats and passive descriptions
  │  Sends JSON via net channel "InvRework_FullInventory"
  ▼
Client Lua (DataStore.lua)
  │  Receives & indexes items by UUID, Owner, Type, Rarity
  ▼
Client Lua (InventoryPanelVM.lua)
  │  ViewModel bridge: registers SE types, creates VM, sets as widget DataContext
  │  Populates Items + EquipSlots collections from DataStore
  │  Formats Weight (grams→kg) and Value (gold pieces)
  ▼
XAML (InventoryPanel.xaml)
     NoesisGUI panel injected into ContentRoot, data-bound to the VM
     Uses real BG3 textures for native look & feel
```

## What Works (as of 2026-03-16)

- **F10 toggle** — shows/hides the inventory panel
- **Draggable panel** — 1300x920 panel using `MouseDragElementBehavior`
- **Real BG3 styling** — uses actual game textures:
  - `container_background.png` (nine-slice panel border)
  - `slot_inventory.png` (item slot backgrounds)
  - `container_closeBtn_d/h.png` (close button with hover state)
  - `container_roundBtn_d/h.png` (round buttons with hover state)
  - `invSlot_selector.png` (slot hover glow)
  - `TT_full_bg.png` (tooltip nine-slice background)
- **Item grid** — 96x96 icon cells in a WrapPanel with scroll
- **Hover glow** — slot selector highlight on mouse-over
- **Polished custom tooltips** — BG3-styled nine-slice tooltip showing:
  - Rarity-coloured item name (grey/green/blue/purple/orange)
  - Item type + rarity text
  - Weapon damage (e.g., "1d12 Slashing") — in progress, needs stat attribute name fix
  - Armor class (e.g., "AC 15") — in progress, needs stat attribute name fix
  - Divider line
  - Item description (translated from loca handles)
  - Special effects / passives (translated, green text)
  - Weight (kg) + Value (gold pieces)
  - Owner name
  - "EQUIPPED" badge (green, only shown when equipped)
  - Transparent ToolTip chrome (no ugly double border)
- **Equipment slots row** — shows 12 equip slots with equipped item names
- **Status bar** — "Showing X / Y items" with Refresh button
- **Close button** — hides panel
- **Refresh button** — re-fetches inventory from server
- **24 items collected** from 2 party characters successfully
- **2-8ms dispatch times** per operation

## Native Tooltip Investigation (Closed)

We thoroughly investigated using BG3's native tooltips (`ls:LSEntityObject` + `ls:LSTooltip`) in our custom panel. After 5 rounds of probing:

1. **Game VM access works** — All ContentRoot widgets share a `DCWidget` DataContext with `.CurrentPlayer.SelectedCharacter.Inventory.Slots` (8 slots)
2. **VMGameObject storage works** — `Object`-typed property on custom VMs can store game VMGameObject references
3. **UUID bridge is impossible** — Game VM `.Object.Name` values are Larian's internal resource handles (h-g format), NOT entity UUIDs or template UUIDs. `Ext.Entity.Get()` returns nil for them. No bridge exists between the SE entity system and the Noesis VM layer.
4. **Limited coverage** — Only 8 inventory slots accessible (current page), no full inventory collection
5. **52 ECS components examined** — None bridge to Noesis VM objects

**Conclusion:** Native tooltips require VMGameObject references that can only be obtained from the game's own inventory widget, but those objects use internal IDs with no mapping to SE entity UUIDs. Custom tooltips are the only viable path.

## Key Technical Lessons Learned

### 1. Lua Proxy Expiry (Critical!)
SE creates **temporary Lua userdata proxies** for Noesis C++ objects. These expire between calls. You CANNOT cache widget or VM references — they go nil.

**Solution:** `GetVM()` calls `FindWidget()` every time to get fresh proxies, then reads `.DataContext`. Only cache simple booleans like `isBound = true`.

### 2. Widget Discovery
The XAML panel appears at `ContentRoot.Children[~20]` with `Name="InventoryPanel"` after ~10s. We scan Children in a loop to find it. Timer-based retry at 8s, 10s, 12s, 15s, 20s, 30s.

### 3. DataContext Keeps VM Alive
Even though the Lua proxy expires, Noesis keeps the actual VM object alive as long as it's set as the widget's DataContext. We re-acquire it via `widget.DataContext` each time.

### 4. Command Handlers Work Differently
XAML button commands work because Noesis calls the closure directly (it's alive in SE's callback registry). The proxy expiry only affects Lua-side cached references.

### 5. Visibility Enum Must Be Strings
SE bridge requires `widget.Visibility = "Visible"` / `"Collapsed"` — NOT integers (0, 1). Using integers causes enum parse errors.

### 6. XAML Namespace URIs Must Use http://
Using `https://` in XAML namespace URIs crashes the game. Always use `http://`.

### 7. CC-Context Resources Don't Work in HUD
Resources like `{StaticResource PanelHeaderText}` and `{StaticResource BoolToVisibleConverter}` are only available in Character Creation context, not the HUD. Using them crashes the game on load.

### 8. Canvas Click-Through
A Canvas without a Background is naturally click-transparent. Do NOT add `IsHitTestVisible="False"` — it blocks ALL descendant hit tests including buttons.

### 9. DataTemplate.Triggers Only Supports DataTrigger
WPF DataTemplate.Triggers only supports `DataTrigger`, not `Trigger`. For `IsMouseOver`, wrap content in a Button with a ControlTemplate (which supports `Trigger`).

### 10. Type Registration Warnings Are Harmless
"Registering type 'String' when it already exists" warnings from SE are safe to ignore.

### 11. Game VM Internal IDs Are Opaque
The game's Noesis VM layer uses internal resource handles in `h...g...` format (e.g., `ha248915ag9249g4fafg8924g12bb3e56c426`). These are NOT entity UUIDs, NOT template UUIDs, and cannot be looked up via `Ext.Entity.Get()` or `Ext.Template.GetRootTemplate()`. The ECS entity system and Noesis VM layer are completely separate.

## What's Working (as of 2026-03-17)

### Item Icons — SOLVED
- `pack://application:,,,/Core;component/Assets/ControllerUIIcons/items_png/<IconName>.DDS`
- Atlas name from `itemEntity.Icon.Icon` (e.g. `Item_CONT_GEN_AlchemyPouch`) maps directly to a DDS file at that path
- Icons now render correctly in item cards

### Item Stats — SOLVED (DIAG V3)
- DIAG V3 dump confirmed correct BG3 stat attribute names
- Stats pipeline working in `InventoryCollector.lua`

### Native Tooltips — IN PROGRESS
- `GetGameVMItems()` in `InventoryPanelVM.lua` grabs VMItem objects from the game's Noesis VM
- Only covers items in the **currently selected character's inventory** (the game VM only exposes the active character's 8 paged slots)
- Matched items stored in `vmItem.GameItem`, flag `vmItem.HasGameItem = true`
- `<ls:LSTooltip Content="{Binding GameItem}"/>` bound in XAML
- **Partial rendering confirmed**: LSTooltip shows correct rarity border + item icon
- **Missing**: tooltip text (item name, description, stats) does not appear
- **Fixed (2026-03-17)**: Removed extra `<ToolTip>` wrapper chrome that was creating a double-tooltip (rarity square outside, native tooltip inside) — LSTooltip now set directly as `Button.ToolTip`
- **Next**: Investigate why LSTooltip renders border/icon but not text — check if additional properties (TooltipType, ItemHandle, etc.) are needed on the bound VMItem object

## What's Not Working Yet

### Native Tooltip Text
- LSTooltip renders but shows no text (name, description, stats)
- Need F9/PROBE V2 output to see what properties `slot.Object` has beyond `EntityUUID`
- Possible: LSTooltip needs a `TooltipType` hint or different property binding

## Next Steps

1. **Run game** — test LSTooltip without the wrapper chrome, see if text appears
2. **F9 probe** — capture PROBE V2 output to inspect VMItem properties on `slot.Object`
3. **Fallback plan** — if text still missing, may need to restore custom tooltip for unmatched items and only use LSTooltip for matched ones

## File Locations

| File | Path |
|------|------|
| XAML Panel | `Baldurs Gate 3\Data\Mods\BG3InventoryRework\GUI\Pages\InventoryPanel.xaml` |
| Client VM | `...\ScriptExtender\Lua\Client\InventoryPanelVM.lua` |
| Client DataStore | `...\ScriptExtender\Lua\Client\DataStore.lua` |
| Client Init | `...\ScriptExtender\Lua\Client\ClientBoot.lua` |
| Server Collector | `...\ScriptExtender\Lua\Server\InventoryCollector.lua` |
| Server Init | `...\ScriptExtender\Lua\Server\ServerBoot.lua` |
| Filter Engine | `...\ScriptExtender\Lua\Client\FilterEngine.lua` |
| State Machine | `...\Data\Public\BG3InventoryRework\GUI\StateMachines\InventoryPanel_StateMachine.xml` |
| Widget Layout | `...\Data\Public\BG3InventoryRework\GUI\InventoryPanel_Layout.xaml` |
