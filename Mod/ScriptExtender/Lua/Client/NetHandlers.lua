--- Client-side network message handlers.
-- @module Client.NetHandlers

local DataStore = Mods.BG3InventoryRework.DataStore

--- Receive full inventory from server.
Ext.RegisterNetListener("InvRework_FullInventory", function(channel, payload)
    local ok, items = pcall(Ext.Json.Parse, payload)
    if ok and items then
        DataStore.LoadFullInventory(items)
        _P("[BG3InventoryRework] Inventory loaded: " .. DataStore.GetItemCount() .. " items")

        -- Notify UI to refresh
        if Mods.BG3InventoryRework.InventoryUI then
            pcall(Mods.BG3InventoryRework.InventoryUI.RefreshTable)
        end
        if Mods.BG3InventoryRework.ArmoryUI then
            pcall(Mods.BG3InventoryRework.ArmoryUI.OnDataUpdated)
        end
        if Mods.BG3InventoryRework.InventoryPanelVM then
            pcall(Mods.BG3InventoryRework.InventoryPanelVM.OnDataUpdated)
        end
        if Mods.BG3InventoryRework.ArmoryPanelVM then
            pcall(Mods.BG3InventoryRework.ArmoryPanelVM.OnDataUpdated)
        end
    else
        _P("[BG3InventoryRework] Failed to parse inventory data")
    end
end)

--- Receive action result from server.
Ext.RegisterNetListener("InvRework_ActionResult", function(channel, payload)
    local ok, result = pcall(Ext.Json.Parse, payload)
    if ok and result then
        if result.success then
            _P("[BG3InventoryRework] Action OK: " .. (result.message or ""))
        else
            _P("[BG3InventoryRework] Action failed: " .. (result.message or "unknown error"))
        end
    end
end)

--- Request a full inventory refresh from server.
function Mods.BG3InventoryRework.RequestRefresh()
    Ext.ClientNet.PostMessageToServer("InvRework_RequestRefresh", "")
end

--- Request moving an item to a character.
function Mods.BG3InventoryRework.RequestMoveItem(itemUUID, targetCharUUID)
    Ext.ClientNet.PostMessageToServer("InvRework_MoveItem",
        Ext.Json.Stringify({ itemUUID = itemUUID, targetCharUUID = targetCharUUID }))
end

--- Request equipping an item on a character.
function Mods.BG3InventoryRework.RequestEquipItem(itemUUID, targetCharUUID)
    Ext.ClientNet.PostMessageToServer("InvRework_EquipItem",
        Ext.Json.Stringify({ itemUUID = itemUUID, targetCharUUID = targetCharUUID }))
end
