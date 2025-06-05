local RSGCore = exports['rsg-core']:GetCoreObject()
local lootedContainers = {} 
local lootCooldown = 300000 -- 5 minutes cooldown
local playerSearchCooldowns = {} 
local searchCooldown = 5000 
local debugMode = false 
local lightVisibilityDistance = 20.0 -- Distance (in units) other players can see the light

RSGCore.Functions.CreateUseableItem('moonlight_lantern', function(source, item)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then 
        if debugMode then
            print(string.format("[DEBUG] Player not found for src=%d", src))
        end
        return 
    end
    
    if debugMode then
        print(string.format("[DEBUG] Player %d used moonlight_lantern", src))
    end
    TriggerClientEvent('rsg-moonlight:client:UseLantern', src)
end)

RegisterNetEvent('rsg-moonlight:server:SearchContainer')
AddEventHandler('rsg-moonlight:server:SearchContainer', function(containerCoords)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then 
        if debugMode then
            print(string.format("[DEBUG] Player not found for src=%d", src))
        end
        return 
    end
    
    if playerSearchCooldowns[src] and GetGameTimer() < playerSearchCooldowns[src] then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Please Wait',
            description = 'You must wait before searching another container.',
            type = 'error',
            duration = 2000
        })
        return
    end
    
    playerSearchCooldowns[src] = GetGameTimer() + searchCooldown
    
    local coordKey = string.format("%.2f,%.2f,%.2f", containerCoords.x, containerCoords.y, containerCoords.z)
    if lootedContainers[coordKey] and GetGameTimer() < lootedContainers[coordKey] then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Already Looted',
            description = 'This container has already been looted recently!',
            type = 'error',
            duration = 3000
        })
        return
    end
    
    lootedContainers[coordKey] = GetGameTimer() + lootCooldown
    
    local lootTable = {
        {item = 'dollars', amount = math.random(5, 25), chance = 60},
        {item = 'silver_ore', amount = math.random(1, 5), chance = 25},
        {item = 'copper_ore', amount = math.random(2, 8), chance = 35},
        {item = 'coal', amount = math.random(3, 10), chance = 40},
        {item = 'ammo_rifle', amount = math.random(5, 15), chance = 30},
        {item = 'ammo_pistol', amount = math.random(8, 20), chance = 35},
        {item = 'weapon_knife', amount = 1, chance = 5},
        {item = 'miracletonic', amount = math.random(1, 2), chance = 15},
    }
    
    local foundItems = {}
    for _, loot in ipairs(lootTable) do
        local roll = math.random(1, 100)
        if roll <= loot.chance then
            table.insert(foundItems, {
                item = loot.item,
                amount = loot.amount
            })
        end
    end
    
    if #foundItems > 0 then
        for _, reward in ipairs(foundItems) do
            Player.Functions.AddItem(reward.item, reward.amount)
            TriggerClientEvent('inventory:client:ItemBox', src, RSGCore.Shared.Items[reward.item], 'add', reward.amount)
        end
        
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Container Looted',
            description = 'You found ' .. #foundItems .. ' item(s) in the container!',
            type = 'success',
            duration = 4000
        })
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Empty Container',
            description = 'The container was empty or already looted.',
            type = 'inform',
            duration = 3000
        })
    end
end)

local function GetPlayersFromCoords(coords, distance)
    local players = {}
    local users = RSGCore.Functions.GetPlayers()
    for _, playerId in pairs(users) do
        local targetPed = GetPlayerPed(playerId)
        if DoesEntityExist(targetPed) then
            local targetCoords = GetEntityCoords(targetPed)
            if #(coords - targetCoords) <= distance then
                table.insert(players, playerId)
            end
        end
    end
    return players
end

RegisterNetEvent('rsg-moonlight:server:ActivateLantern')
AddEventHandler('rsg-moonlight:server:ActivateLantern', function(coords, duration)
    local src = source
    if debugMode then
        print(string.format("[DEBUG] ActivateLantern: src=%d, coords=%s, duration=%d", src, tostring(coords), duration))
    end
    
    Citizen.CreateThread(function()
        local endTime = GetGameTimer() + duration
        while GetGameTimer() < endTime do
            local ped = GetPlayerPed(src)
            if DoesEntityExist(ped) then
                local newCoords = GetEntityCoords(ped)
                local nearbyPlayers = GetPlayersFromCoords(newCoords, lightVisibilityDistance)
                if debugMode then
                    print(string.format("[DEBUG] Found %d nearby players for src=%d within %f units", #nearbyPlayers, src, lightVisibilityDistance))
                end
                for _, playerId in ipairs(nearbyPlayers) do
                    if playerId ~= src then
                        if debugMode then
                            print(string.format("[DEBUG] Sending SyncLanternOn to playerId=%d for src=%d", playerId, src))
                        end
                        TriggerClientEvent('rsg-moonlight:client:SyncLanternOn', playerId, src, newCoords, duration)
                    end
                end
            else
                if debugMode then
                    print(string.format("[DEBUG] Ped not found for src=%d", src))
                end
            end
            Wait(2000) 
        end
    end)
end)

RegisterNetEvent('rsg-moonlight:server:DeactivateLantern')
AddEventHandler('rsg-moonlight:server:DeactivateLantern', function()
    local src = source
    local ped = GetPlayerPed(src)
    local coords = DoesEntityExist(ped) and GetEntityCoords(ped) or vector3(0, 0, 0)
    local nearbyPlayers = GetPlayersFromCoords(coords, lightVisibilityDistance)
    if debugMode then
        print(string.format("[DEBUG] DeactivateLantern: src=%d, found %d nearby players within %f units", src, #nearbyPlayers, lightVisibilityDistance))
    end
    for _, playerId in ipairs(nearbyPlayers) do
        if playerId ~= src then
            if debugMode then
                print(string.format("[DEBUG] Sending SyncLanternOff to playerId=%d for src=%d", playerId, src))
            end
            TriggerClientEvent('rsg-moonlight:client:SyncLanternOff', playerId, src)
        end
    end
end)