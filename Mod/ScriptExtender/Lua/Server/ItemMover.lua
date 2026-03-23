--- Handles moving and equipping items between characters (server-side).
-- @module ItemMover

local ItemMover = {}

--- Move an item to a target character's inventory.
-- @param itemUUID string
-- @param targetCharUUID string
-- @return success boolean, message string
function ItemMover.MoveItem(itemUUID, targetCharUUID)
    if not itemUUID or not targetCharUUID then
        return false, "Missing item or target UUID"
    end

    -- Verify item exists
    local itemEntity = Ext.Entity.Get(itemUUID)
    if not itemEntity then
        return false, "Item not found: " .. itemUUID
    end

    -- Try multiple methods to move item
    local ok, err = pcall(function()
        -- Osi.MagicPocketsMoveTo(source, object, destination, showNotification, clearOriginalOwner)
        Osi.MagicPocketsMoveTo(itemUUID, itemUUID, targetCharUUID, 0, 0)
    end)

    if not ok then
        -- Fallback: try ToInventory
        ok, err = pcall(function()
            Osi.ToInventory(itemUUID, targetCharUUID, 1, 0, 0)
        end)
    end

    if not ok then
        return false, "Move failed: " .. tostring(err)
    end

    return true, "Item moved successfully"
end

--- Equip an item on a target character.
-- If the item is on another character or in another inventory, it is moved first.
-- @param itemUUID string
-- @param targetCharUUID string
-- @param targetSlot string|nil  optional slot ID to vacate before equipping
-- @return success boolean, message string
function ItemMover.EquipItem(itemUUID, targetCharUUID, targetSlot)
    if not itemUUID or not targetCharUUID then
        return false, "Missing item or target UUID"
    end

    -- Verify item exists
    local itemEntity = Ext.Entity.Get(itemUUID)
    if not itemEntity then
        return false, "Item not found: " .. itemUUID
    end

    -- Container slot indices for fallback when Osi.GetEquippedItem returns nil (weapons)
    local containerIdxMap = {
        MeleeMainHand  = 3,
        MeleeOffHand   = 4,
        RangedMainHand = 5,
        RangedOffHand  = 6,
        Ring           = 9,
        Ring2          = 10,
    }

    -- Helper: get UUID of the item currently in a given equipment slot.
    -- Osi.GetEquippedItem works for armor/shields; container index fallback for weapons.
    local function getSlotOccupant(osiSlotName)
        local occupantUUID = nil
        pcall(function()
            occupantUUID = Osi.GetEquippedItem(targetCharUUID, osiSlotName)
        end)
        if not occupantUUID then
            pcall(function()
                local cIdx = containerIdxMap[osiSlotName]
                if not cIdx then return end
                local charEntity = Ext.Entity.Get(targetCharUUID)
                if not charEntity or not charEntity.InventoryOwner then return end
                local inventories = charEntity.InventoryOwner.Inventories
                if not inventories then return end
                for invIdx = 2, #inventories do
                    pcall(function()
                        local inv = inventories[invIdx]
                        if not inv or not inv.InventoryContainer then return end
                        local items = inv.InventoryContainer.Items
                        if not items then return end
                        local slotData = items[cIdx]
                        if not slotData then return end
                        local ie = slotData.Item or slotData
                        if ie and ie.Uuid then occupantUUID = ie.Uuid.EntityUuid end
                    end)
                end
            end)
        end
        return occupantUUID
    end

    -- Helper: move a slot's occupant to inventory
    local function vacateSlot(osiSlotName)
        local uid = getSlotOccupant(osiSlotName)
        if uid and uid ~= itemUUID then
            _P("[BG3InventoryRework] Vacating " .. osiSlotName .. ": " .. tostring(uid))
            pcall(function() Osi.ToInventory(uid, targetCharUUID, 1, 0, 0) end)
        end
        return uid
    end

    -- Step 1: If the item is on ANOTHER character, move it to target first.
    pcall(function()
        local currentOwner = nil
        pcall(function() currentOwner = Osi.GetOwner(itemUUID) end)
        if currentOwner and currentOwner ~= targetCharUUID then
            pcall(function() Osi.ToInventory(itemUUID, targetCharUUID, 1, 0, 0) end)
        end
    end)

    -- Step 2 + 3: Equip with slot-targeting logic.
    -- Osi.Equip has NO slot parameter — a MeleeMainHand weapon ALWAYS goes to MainHand.
    -- For OffHand/Ring2 we skip Osi.Equip and directly swap the item into the equipment
    -- container at the correct slot index, then Osi.Equip the displaced occupant's original
    -- main-hand weapon back. This is the only reliable way to target a specific slot.

    if targetSlot == "MeleeOffHand" or targetSlot == "RangedOffHand" or targetSlot == "Ring2" then
        -- Determine which slot pair we're working with
        local primarySlot
        if targetSlot == "MeleeOffHand" then primarySlot = "MeleeMainHand"
        elseif targetSlot == "RangedOffHand" then primarySlot = "RangedMainHand"
        else primarySlot = "Ring" end
        local secondarySlot = targetSlot  -- MeleeOffHand, RangedOffHand, or Ring2

        -- Get current occupants
        local primaryUUID = getSlotOccupant(primarySlot)
        local secondaryOccupant = vacateSlot(secondarySlot)  -- remove shield/old off-hand/ring2

        -- Strategy: clear both slots, equip the PRIMARY weapon first so it takes the
        -- primary slot, then equip the NEW weapon — with the primary slot occupied,
        -- Osi.Equip should place it in the secondary slot (OffHand / Ring2).
        if primaryUUID and primaryUUID ~= itemUUID then
            -- Temporarily remove the primary weapon
            _P("[BG3InventoryRework] Temporarily removing " .. primarySlot .. ": " .. tostring(primaryUUID))
            pcall(function() Osi.ToInventory(primaryUUID, targetCharUUID, 1, 0, 0) end)

            -- Re-equip primary weapon → goes to empty MainHand/Ring
            _P("[BG3InventoryRework] Re-equipping primary to " .. primarySlot)
            pcall(function() Osi.Equip(targetCharUUID, primaryUUID, 1, 0, 0) end)

            -- Now equip NEW weapon — primary slot is occupied, should go to secondary
            _P("[BG3InventoryRework] Equipping new item with " .. primarySlot .. " occupied")
            local ok1, err1 = pcall(function() Osi.Equip(targetCharUUID, itemUUID, 1, 0, 0) end)
            if not ok1 then return false, "Equip failed: " .. tostring(err1) end
        else
            -- No primary occupant — just equip normally (will go to primary slot, best we can do)
            local ok1, err1 = pcall(function() Osi.Equip(targetCharUUID, itemUUID, 1, 0, 0) end)
            if not ok1 then return false, "Equip failed: " .. tostring(err1) end
        end

        return true, "Item equipped to " .. targetSlot

    else
        -- Standard case: vacate the target slot and equip normally
        if targetSlot and targetSlot ~= "" then
            vacateSlot(targetSlot)
        end

        local ok, err = pcall(function()
            Osi.Equip(targetCharUUID, itemUUID, 1, 0, 0)
        end)

        if not ok then
            return false, "Equip failed: " .. tostring(err)
        end

        return true, "Item equipped successfully"
    end
end

--- Use an item (consumable, scroll, etc.).
-- @param itemUUID string
-- @param charUUID string - character who uses it
-- @return success boolean, message string
function ItemMover.UseItem(itemUUID, charUUID)
    if not itemUUID or not charUUID then
        return false, "Missing item or character UUID"
    end

    -- BG3 Osi.Use requires 3 params: (character, item, consumeType)
    -- Try multiple signatures since Osi naming varies by BG3 version
    local ok, err
    ok, err = pcall(function() Osi.Use(charUUID, itemUUID, "") end)
    if not ok then
        ok, err = pcall(function() Osi.RequestUse(charUUID, itemUUID) end)
    end
    if not ok then
        ok, err = pcall(function() Osi.CharacterUseItem(charUUID, itemUUID, "") end)
    end
    if not ok then
        -- Last resort: try ApplyStatus for consumables or just report
        return false, "Use failed (no matching Osi function): " .. tostring(err)
    end

    return true, "Item used"
end

--- Drop an item on the ground near a character.
-- @param itemUUID string
-- @param charUUID string - character who drops it
-- @return success boolean, message string
function ItemMover.DropItem(itemUUID, charUUID)
    if not itemUUID then
        return false, "Missing item UUID"
    end

    -- Osi.Drop takes just the item UUID (1 param) — drops from current owner
    local ok, err
    ok, err = pcall(function() Osi.Drop(itemUUID) end)
    if not ok then
        ok, err = pcall(function() Osi.ItemDrop(itemUUID) end)
    end
    if not ok then
        -- Fallback: move item to ground at character's position
        ok, err = pcall(function()
            if charUUID then
                local x, y, z = Osi.GetPosition(charUUID)
                if x then
                    Osi.ItemMoveToPosition(itemUUID, x, y, z)
                end
            end
        end)
    end

    if not ok then
        return false, "Drop failed: " .. tostring(err)
    end

    return true, "Item dropped"
end

--- Send an item to the camp chest.
-- @param itemUUID string
-- @return success boolean, message string
function ItemMover.SendToCamp(itemUUID)
    if not itemUUID then
        return false, "Missing item UUID"
    end

    -- Try various Osi camp chest functions
    local ok, err
    ok, err = pcall(function() Osi.SendToCampChest(itemUUID) end)
    if not ok then
        ok, err = pcall(function() Osi.SendToCampChest(itemUUID, 1) end)
    end
    if not ok then
        -- Fallback: find camp chest entity and move item to it
        ok, err = pcall(function()
            -- YOURTREASURE_YOURTREASURE is the camp supply chest template
            local chestUUID = Osi.GetClosestAlivePlayer(itemUUID)
            Osi.MagicPocketsMoveTo(itemUUID, itemUUID, "YOURTREASURE_YOURTREASURE", 0, 0)
        end)
    end

    if not ok then
        return false, "Send to camp failed: " .. tostring(err)
    end

    return true, "Item sent to camp"
end

-- Export
Mods = Mods or {}
Mods.BG3InventoryRework = Mods.BG3InventoryRework or {}
Mods.BG3InventoryRework.ItemMover = ItemMover

return ItemMover
