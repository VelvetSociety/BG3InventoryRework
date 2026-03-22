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
-- Osi.Equip will move the item automatically if needed.
-- @param itemUUID string
-- @param targetCharUUID string
-- @return success boolean, message string
function ItemMover.EquipItem(itemUUID, targetCharUUID)
    if not itemUUID or not targetCharUUID then
        return false, "Missing item or target UUID"
    end

    -- Verify item exists
    local itemEntity = Ext.Entity.Get(itemUUID)
    if not itemEntity then
        return false, "Item not found: " .. itemUUID
    end

    -- Osi.Equip(character, item, addToMainInventoryOnFail, showNotification, clearOriginalOwner)
    local ok, err = pcall(function()
        Osi.Equip(targetCharUUID, itemUUID, 1, 0, 0)
    end)

    if not ok then
        return false, "Equip failed: " .. tostring(err)
    end

    return true, "Item equipped successfully"
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
