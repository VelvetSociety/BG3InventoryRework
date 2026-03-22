--- Enumerates all party member inventories and sends data to clients.
-- @module InventoryCollector

local InventoryCollector = {}

--- Collect all items from all party members.
-- @return array of item tables
function InventoryCollector.CollectAll()
    local allItems = {}

    -- Try multiple methods to get party members
    local partyMembers = nil

    local ok, result = pcall(function() return Osi.DB_IsPlayer:Get(nil) end)
    if ok and result then
        partyMembers = result
    end

    if not partyMembers then
        local ok2, result2 = pcall(function() return Osi.DB_PartyMembers:Get(nil) end)
        if ok2 and result2 then
            partyMembers = result2
        end
    end

    if not partyMembers then
        _P("[BG3InventoryRework] No party members found via Osiris DB")
        return allItems
    end

    for _, tuple in pairs(partyMembers) do
        local charUUID = tuple[1]
        local ok3, err = pcall(function()
            local charEntity = Ext.Entity.Get(charUUID)
            if charEntity then
                local charItems = InventoryCollector.CollectFromCharacter(charUUID, charEntity)
                for _, item in ipairs(charItems) do
                    allItems[#allItems + 1] = item
                end
            end
        end)
        if not ok3 then
            _P("[BG3InventoryRework] Error collecting from " .. tostring(charUUID) .. ": " .. tostring(err))
        end
    end

    -- Mark actually-equipped items using Osi.GetEquippedItem
    InventoryCollector._markEquippedItems(allItems, partyMembers)

    _P("[BG3InventoryRework] Collected " .. #allItems .. " items from " .. #partyMembers .. " characters")
    return allItems
end

--- Collect items from a single character's inventory, recursing into bag items.
-- @param charUUID string
-- @param charEntity Entity
-- @return array of item tables
function InventoryCollector.CollectFromCharacter(charUUID, charEntity)
    local result = {}

    local inventoryOwner = charEntity.InventoryOwner
    if not inventoryOwner or not inventoryOwner.Inventories then
        return result
    end

    local charName = InventoryCollector._getCharacterName(charEntity) or charUUID

    -- Recursive helper: collect all items from a container entity.
    -- Recurses into bag items (Backpack, Keychain, Pouch, etc.) up to depth limit.
    local function collectFromContainer(containerEntity, depth)
        if depth > 4 then return end
        pcall(function()
            local container = containerEntity.InventoryContainer
            if not container or not container.Items then return end
            for _, slotData in pairs(container.Items) do
                pcall(function()
                    local itemEntity = slotData.Item or slotData
                    if not itemEntity then return end

                    local itemData = InventoryCollector._extractItemData(itemEntity, charUUID, charName)
                    if itemData then
                        result[#result + 1] = itemData
                    end

                    -- If this item is itself a container (bag), recurse into it
                    pcall(function()
                        if itemEntity.InventoryContainer then
                            collectFromContainer(itemEntity, depth + 1)
                        end
                    end)
                end)
            end
        end)
    end

    for _, invEntity in ipairs(inventoryOwner.Inventories) do
        collectFromContainer(invEntity, 0)
    end

    return result
end

--- Mark items as equipped by querying Osi.GetEquippedItem for each character+slot.
-- This replaces the broken InventoryMember.EquipmentSlot check which is always >= 0.
function InventoryCollector._markEquippedItems(allItems, partyMembers)
    -- Build a UUID → item lookup
    local byUUID = {}
    for _, item in ipairs(allItems) do
        if item.UUID then byUUID[item.UUID] = item end
    end

    local EQUIP_SLOTS = {
        "Helmet", "Breast", "Cloak", "MeleeMainHand", "MeleeOffHand",
        "RangedMainHand", "RangedOffHand", "Gloves", "Boots",
        "Amulet", "Ring", "Ring2", "Underwear", "VanityBody", "VanityBoots",
    }

    -- Method 1: Osi.GetEquippedItem (works for armor/vanity slots)
    for _, tuple in pairs(partyMembers) do
        local charUUID = tuple[1]
        for _, slotName in ipairs(EQUIP_SLOTS) do
            pcall(function()
                local equippedUUID = Osi.GetEquippedItem(charUUID, slotName)
                if equippedUUID and byUUID[equippedUUID] then
                    byUUID[equippedUUID].Equipped = true
                end
            end)
        end
    end

    -- Method 2: Equipment inventory container (catches weapon slots that Osi misses)
    -- The 2nd inventory (index 2) on each character is the equipment container.
    for _, tuple in pairs(partyMembers) do
        local charUUID = tuple[1]
        pcall(function()
            local charEntity = Ext.Entity.Get(charUUID)
            if not charEntity or not charEntity.InventoryOwner then return end
            local inventories = charEntity.InventoryOwner.Inventories
            if not inventories then return end
            -- Equipment container is typically at index 2 (1-based)
            for invIdx = 2, #inventories do
                pcall(function()
                    local inv = inventories[invIdx]
                    if not inv or not inv.InventoryContainer then return end
                    local container = inv.InventoryContainer
                    if not container or not container.Items then return end
                    for _, slotData in pairs(container.Items) do
                        pcall(function()
                            local itemEntity = slotData.Item or slotData
                            if not itemEntity or not itemEntity.Uuid then return end
                            local uuid = itemEntity.Uuid.EntityUuid
                            if uuid and byUUID[uuid] then
                                byUUID[uuid].Equipped = true
                            end
                        end)
                    end
                end)
            end
        end)
    end
end

--- Extract relevant data from an item entity.
function InventoryCollector._extractItemData(itemEntity, ownerUUID, ownerName)
    local ok, itemData = pcall(function()
        if not itemEntity then return nil end

        -- Get UUID
        local uuid = nil
        if itemEntity.Uuid then
            uuid = itemEntity.Uuid.EntityUuid
        end
        if not uuid then return nil end

        local item = {
            UUID = uuid,
            Name = "",
            Type = "Misc",
            Rarity = "Common",
            Weight = 0,
            Value = 0,
            OwnerUUID = ownerUUID,
            OwnerName = ownerName,
            Icon = "",
            StackSize = 1,
            Slot = "",
            Equipped = false,
            Enchantments = {},
        }

        -- Name
        if itemEntity.DisplayName and itemEntity.DisplayName.Name then
            local nameHandle = itemEntity.DisplayName.Name.Handle
            if nameHandle then
                local handle = nameHandle.Handle or nameHandle
                local translated = Ext.Loca.GetTranslatedString(handle)
                if translated then
                    item.Name = translated
                end
            end
        end

        -- Rarity
        if itemEntity.Value and itemEntity.Value.Rarity then
            local rarityMap = {[0]="Common", [1]="Uncommon", [2]="Rare", [3]="VeryRare", [4]="Legendary"}
            item.Rarity = rarityMap[itemEntity.Value.Rarity] or "Common"
        end

        -- Value
        if itemEntity.Value and itemEntity.Value.Value then
            item.Value = itemEntity.Value.Value
        end

        -- Weight
        if itemEntity.Data and itemEntity.Data.Weight then
            item.Weight = itemEntity.Data.Weight
        end

        -- Stack size
        if itemEntity.InventoryStack and itemEntity.InventoryStack.Amount then
            item.StackSize = itemEntity.InventoryStack.Amount
        end

        -- Icon
        if itemEntity.Icon and itemEntity.Icon.Icon then
            item.Icon = itemEntity.Icon.Icon
        end

        -- Equipment slot
        if itemEntity.Equipable and itemEntity.Equipable.Slot then
            item.Slot = tostring(itemEntity.Equipable.Slot)
        end

        -- Note: Equipped flag is set later by _markEquippedItems() using Osi.GetEquippedItem
        -- (InventoryMember.EquipmentSlot is a container index, always >= 0, NOT an equipped indicator)

        -- Description (from DisplayName component or template)
        pcall(function()
            if itemEntity.DisplayName and itemEntity.DisplayName.Description then
                local descHandle = itemEntity.DisplayName.Description.Handle
                if descHandle then
                    local handle = descHandle.Handle or descHandle
                    local translated = Ext.Loca.GetTranslatedString(handle)
                    if translated and translated ~= "" then
                        item.Description = translated
                    end
                end
            end
        end)

        -- Fallback: try getting description from root template
        if not item.Description or item.Description == "" then
            pcall(function()
                if itemEntity.OriginalTemplate then
                    local tmplId = itemEntity.OriginalTemplate.OriginalTemplate
                    if tmplId then
                        local tmpl = Ext.Template.GetRootTemplate(tmplId)
                        if tmpl and tmpl.Description then
                            local descHandle = tmpl.Description.Handle
                            if descHandle then
                                local handle = descHandle.Handle or descHandle
                                local translated = Ext.Loca.GetTranslatedString(handle)
                                if translated and translated ~= "" then
                                    item.Description = translated
                                end
                            end
                        end
                    end
                end
            end)
        end

        item.Description = item.Description or ""

        -- Item type classification
        item.Type = InventoryCollector._classifyItemType(itemEntity)

        -- Stats (damage, armor class, passives, boosts)
        pcall(function()
            local statsId = nil
            if itemEntity.Data then
                pcall(function() statsId = itemEntity.Data.StatsId end)
            end
            if not statsId and itemEntity.ServerItem then
                pcall(function() statsId = itemEntity.ServerItem.StatsId end)
            end

            if statsId and statsId ~= "" then
                local stat = Ext.Stats.Get(statsId)
                if stat then
                    -- Weapon damage (confirmed attribute names from DIAG V3)
                    if item.Type == "Weapon" then
                        pcall(function()
                            local parts = {}
                            local dmg = stat.Damage
                            if dmg and dmg ~= "" then
                                parts[#parts+1] = tostring(dmg)
                            end
                            local dmgType = stat["Damage Type"]
                            if dmgType and dmgType ~= "" then
                                parts[#parts+1] = tostring(dmgType)
                            end
                            if #parts > 0 then
                                item.DamageStr = table.concat(parts, " ")
                            end
                        end)
                    end

                    -- Armor class (confirmed attribute name from DIAG V3)
                    if item.Type == "Armor" then
                        pcall(function()
                            local ac = stat.ArmorClass
                            if ac and tostring(ac) ~= "" and tostring(ac) ~= "0" then
                                item.ArmorClass = tostring(ac)
                            end
                        end)
                    end

                    -- Passives on equip (special effects)
                    pcall(function()
                        local passives = stat.PassivesOnEquip
                        if passives and passives ~= "" then
                            local descs = {}
                            for passiveName in tostring(passives):gmatch("[^;]+") do
                                passiveName = passiveName:match("^%s*(.-)%s*$")
                                pcall(function()
                                    local passiveStat = Ext.Stats.Get(passiveName)
                                    if passiveStat then
                                        local descHandle = nil
                                        pcall(function() descHandle = passiveStat.Description end)
                                        if descHandle and tostring(descHandle) ~= "" then
                                            local translated = Ext.Loca.GetTranslatedString(tostring(descHandle))
                                            if translated and translated ~= "" then
                                                descs[#descs+1] = translated
                                            end
                                        end
                                    end
                                end)
                            end
                            if #descs > 0 then
                                item.SpecialEffects = table.concat(descs, "\n")
                            end
                        end
                    end)

                    -- BoostsOnEquipMainHand confirmed in DIAG V3 but contains spell unlock strings,
                    -- not human-readable text — skip for now
                end
            end
        end)

        return item
    end)

    if ok then
        return itemData
    else
        return nil
    end
end

--- Classify an item into a broad type category.
function InventoryCollector._classifyItemType(itemEntity)
    local function has(comp)
        local ok, val = pcall(function() return itemEntity[comp] end)
        return ok and val
    end
    if has("Weapon") then return "Weapon" end
    if has("Armor") then return "Armor" end
    if has("InventoryContainer") then return "Container" end
    if has("Boostable") then return "Consumable" end
    if has("SpellBook") then return "Scroll" end
    if has("BookAction") then return "Book" end
    return "Misc"
end

--- Get display name of a character entity.
function InventoryCollector._getCharacterName(charEntity)
    local ok, name = pcall(function()
        if charEntity.DisplayName and charEntity.DisplayName.Name then
            local nameHandle = charEntity.DisplayName.Name.Handle
            if nameHandle then
                local handle = nameHandle.Handle or nameHandle
                return Ext.Loca.GetTranslatedString(handle)
            end
        end
        return nil
    end)
    return ok and name or nil
end

--- Send full inventory to a specific client.
-- userId is a numeric peer ID; use BroadcastMessage instead since
-- PostMessageToClient expects a character GUID.
function InventoryCollector.SendToClient(userId)
    local allItems = InventoryCollector.CollectAll()
    local json = Ext.Json.Stringify(allItems)
    -- BroadcastMessage works for single-player and avoids the GUID issue
    Ext.ServerNet.BroadcastMessage("InvRework_FullInventory", json)
end

--- Send full inventory to all clients.
function InventoryCollector.BroadcastToAll()
    local allItems = InventoryCollector.CollectAll()
    local json = Ext.Json.Stringify(allItems)
    Ext.ServerNet.BroadcastMessage("InvRework_FullInventory", json)
end

-- Export
Mods = Mods or {}
Mods.BG3InventoryRework = Mods.BG3InventoryRework or {}
Mods.BG3InventoryRework.InventoryCollector = InventoryCollector

return InventoryCollector
