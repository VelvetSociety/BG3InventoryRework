--- Server-side network message handlers.
-- @module Server.NetHandlers

local InventoryCollector = Mods.BG3InventoryRework.InventoryCollector
local ItemMover = Mods.BG3InventoryRework.ItemMover

--- Handle refresh request from client.
Ext.RegisterNetListener("InvRework_RequestRefresh", function(channel, payload, userId)
    _P("[BG3InventoryRework] Refresh requested by user " .. tostring(userId))
    local ok, err = pcall(InventoryCollector.SendToClient, userId)
    if not ok then
        _P("[BG3InventoryRework] Error sending inventory: " .. tostring(err))
    end
end)

--- Handle move item request from client.
Ext.RegisterNetListener("InvRework_MoveItem", function(channel, payload, userId)
    local ok, data = pcall(Ext.Json.Parse, payload)
    if not ok or not data or not data.itemUUID or not data.targetCharUUID then
        Ext.ServerNet.BroadcastMessage("InvRework_ActionResult",
            Ext.Json.Stringify({ success = false, message = "Invalid move request" }))
        return
    end

    local success, message = ItemMover.MoveItem(data.itemUUID, data.targetCharUUID)
    Ext.ServerNet.BroadcastMessage("InvRework_ActionResult",
        Ext.Json.Stringify({ success = success, message = message }))

    if success then
        pcall(InventoryCollector.BroadcastToAll)
    end
end)

--- Handle equip item request from client.
Ext.RegisterNetListener("InvRework_EquipItem", function(channel, payload, userId)
    local ok, data = pcall(Ext.Json.Parse, payload)
    if not ok or not data or not data.itemUUID or not data.targetCharUUID then
        Ext.ServerNet.BroadcastMessage("InvRework_ActionResult",
            Ext.Json.Stringify({ success = false, message = "Invalid equip request" }))
        return
    end

    local success, message = ItemMover.EquipItem(data.itemUUID, data.targetCharUUID)
    Ext.ServerNet.BroadcastMessage("InvRework_ActionResult",
        Ext.Json.Stringify({ success = success, message = message }))

    if success then
        pcall(InventoryCollector.BroadcastToAll)
    end
end)

--- Handle use item request from client.
Ext.RegisterNetListener("InvRework_UseItem", function(channel, payload, userId)
    local ok, data = pcall(Ext.Json.Parse, payload)
    if not ok or not data or not data.itemUUID then
        Ext.ServerNet.BroadcastMessage("InvRework_ActionResult",
            Ext.Json.Stringify({ success = false, message = "Invalid use request" }))
        return
    end

    local charUUID = data.charUUID
    if not charUUID then
        _P("[BG3InventoryRework] UseItem: no charUUID, trying to find owner")
        pcall(function()
            charUUID = Osi.GetOwner(data.itemUUID)
        end)
    end

    local success, message = ItemMover.UseItem(data.itemUUID, charUUID)
    _P("[BG3InventoryRework] UseItem result: " .. tostring(success) .. " - " .. tostring(message))
    Ext.ServerNet.BroadcastMessage("InvRework_ActionResult",
        Ext.Json.Stringify({ success = success, message = message }))

    if success then
        pcall(InventoryCollector.BroadcastToAll)
    end
end)

--- Handle drop item request from client.
Ext.RegisterNetListener("InvRework_DropItem", function(channel, payload, userId)
    local ok, data = pcall(Ext.Json.Parse, payload)
    if not ok or not data or not data.itemUUID then
        Ext.ServerNet.BroadcastMessage("InvRework_ActionResult",
            Ext.Json.Stringify({ success = false, message = "Invalid drop request" }))
        return
    end

    local charUUID = data.charUUID
    if not charUUID then
        pcall(function()
            charUUID = Osi.GetOwner(data.itemUUID)
        end)
    end

    local success, message = ItemMover.DropItem(data.itemUUID, charUUID)
    _P("[BG3InventoryRework] DropItem result: " .. tostring(success) .. " - " .. tostring(message))
    Ext.ServerNet.BroadcastMessage("InvRework_ActionResult",
        Ext.Json.Stringify({ success = success, message = message }))

    if success then
        pcall(InventoryCollector.BroadcastToAll)
    end
end)

--- Handle send to camp request from client.
Ext.RegisterNetListener("InvRework_SendToCamp", function(channel, payload, userId)
    local ok, data = pcall(Ext.Json.Parse, payload)
    if not ok or not data or not data.itemUUID then
        Ext.ServerNet.BroadcastMessage("InvRework_ActionResult",
            Ext.Json.Stringify({ success = false, message = "Invalid send to camp request" }))
        return
    end

    local success, message = ItemMover.SendToCamp(data.itemUUID)
    _P("[BG3InventoryRework] SendToCamp result: " .. tostring(success) .. " - " .. tostring(message))
    Ext.ServerNet.BroadcastMessage("InvRework_ActionResult",
        Ext.Json.Stringify({ success = success, message = message }))

    if success then
        pcall(InventoryCollector.BroadcastToAll)
    end
end)

--- Throttled inventory change listener.
local pendingBroadcast = false

local function ScheduleBroadcast()
    if pendingBroadcast then return end
    pendingBroadcast = true
    Ext.Timer.WaitFor(500, function()
        pendingBroadcast = false
        pcall(InventoryCollector.BroadcastToAll)
    end)
end

Ext.Osiris.RegisterListener("TemplateAddedTo", 4, "after", function(template, item, inventory, addType)
    ScheduleBroadcast()
end)

Ext.Osiris.RegisterListener("TemplateRemovedFrom", 4, "after", function(template, item, inventory, removeType)
    ScheduleBroadcast()
end)

Ext.Osiris.RegisterListener("DroppedBy", 2, "after", function(item, character)
    ScheduleBroadcast()
end)

Ext.Osiris.RegisterListener("Unequipped", 3, "after", function(item, character, slot)
    ScheduleBroadcast()
end)

Ext.Osiris.RegisterListener("Equipped", 3, "after", function(item, character, slot)
    ScheduleBroadcast()
end)
