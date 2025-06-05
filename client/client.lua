local RSGCore = exports['rsg-core']:GetCoreObject()


local CONFIG = {
    lanternDuration = 60000, -- 60 seconds
    lightRadius = 5.0,
    objectCheckInterval = 2000,
    searchCooldown = 5000,
    maxMarkers = 3,
    textScale = 0.35,
    textFont = 6,
    spriteName = "feeds",
    spriteDict = "toast_bg",
    updatePositionThreshold = 1.0,
    debugMode = false,
    lightVisibilityDistance = 20.0 -- Distance other players can see the light
}


local state = {
    hasLanternActive = false,
    lanternEndTime = 0,
    highlightObjects = {},
    cachedObjects = {},
    lastObjectCheck = 0,
    lastSearchTime = 0,
    lastPlayerPosition = nil,
    syncedLanterns = {}
}


CreateThread(function()
    RequestStreamedTextureDict(CONFIG.spriteName)
    while not HasStreamedTextureDictLoaded(CONFIG.spriteName) do
        Wait(100)
    end
end)


local function DrawText3D(x, y, z, text)
    local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(x, y, z)
    if not onScreen then return end

    local textLength = string.len(text) / 160
    SetTextScale(CONFIG.textScale, CONFIG.textScale)
    SetTextFontForCurrentCommand(CONFIG.textFont)
    SetTextColor(255, 0, 0, 215)
    SetTextCentre(1)
    
    DrawSprite(CONFIG.spriteName, CONFIG.spriteDict, screenX, screenY + 0.0150, 0.015 + textLength, 0.032, 0.1, 0, 0, 0, 190, 0)
    DisplayText(CreateVarString(10, "LITERAL_STRING", text), screenX, screenY)
end


local function GetNearbyObjects(coords, radius)
    local objects = {}
    local objectTypes = {
        GetHashKey("p_crate01x"),
        GetHashKey("p_chest01x"),
        GetHashKey("p_barrel01x"),
        GetHashKey("p_strongbox01x"),
        GetHashKey("p_lockbox01x")
    }
    
    for _, hash in ipairs(objectTypes) do
        local obj = GetClosestObjectOfType(coords.x, coords.y, coords.z, radius, hash, false, false, false)
        if obj ~= 0 and DoesEntityExist(obj) then
            objects[obj] = true
        end
    end
    
    return objects
end


local function SearchContainer(container)
    if GetGameTimer() - state.lastSearchTime < CONFIG.searchCooldown then
        lib.notify({
            title = 'Please Wait',
            description = 'You must wait before searching another container.',
            type = 'error',
            duration = 2000
        })
        return
    end

    local playerPed = PlayerPedId()
    LocalPlayer.state:set('inv_busy', true, true)
    
    TaskStartScenarioInPlace(playerPed, GetHashKey('WORLD_HUMAN_CROUCH_INSPECT'), -1, true, false, false, false)
    
    lib.progressBar({
        duration = 3000,
        label = 'Searching Container...',
        useWhileDead = false,
        canCancel = false,
        disable = { move = true, combat = true }
    })

    state.lastSearchTime = GetGameTimer()
    TriggerServerEvent('rsg-moonlight:server:SearchContainer', GetEntityCoords(container))
    
    ClearPedTasks(playerPed)
    LocalPlayer.state:set('inv_busy', false, true)
end


RegisterNetEvent('rsg-moonlight:client:UseLantern')
AddEventHandler('rsg-moonlight:client:UseLantern', function()
    local currentHour = GetClockHours()
    if currentHour < 20 and currentHour >= 5 then
        lib.notify({
            title = 'Moonlight Lantern',
            description = 'The Moonlight Lantern only works at night (8 PM - 5 AM)!',
            type = 'error',
            duration = 4000
        })
        return
    end

    if state.hasLanternActive then
        lib.notify({
            title = 'Moonlight Lantern',
            description = 'The Moonlight Lantern is already active!',
            type = 'error',
            duration = 3000
        })
        return
    end

    state.hasLanternActive = true
    state.lanternEndTime = GetGameTimer() + CONFIG.lanternDuration
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    
    TriggerServerEvent('rsg-moonlight:server:ActivateLantern', playerCoords, CONFIG.lanternDuration)
    
    lib.notify({
        title = 'Moonlight Lantern',
        description = 'You activated the Moonlight Lantern! Hidden secrets are revealed for 60 seconds!',
        type = 'success',
        duration = 5000
    })

   
    CreateThread(function()
        while state.hasLanternActive and GetGameTimer() < state.lanternEndTime do
            local coords = GetEntityCoords(playerPed)
            DrawLightWithRange(coords.x, coords.y, coords.z + 1.0, 0, 0, 255, CONFIG.lightRadius, 1.0)
            Wait(0)
        end
        if CONFIG.debugMode then
            print("[DEBUG] Local lantern light thread ended")
        end
        TriggerServerEvent('rsg-moonlight:server:DeactivateLantern')
    end)

   
    CreateThread(function()
        while state.hasLanternActive and GetGameTimer() < state.lanternEndTime do
            local loopStart = CONFIG.debugMode and GetGameTimer() or nil
            local playerCoords = GetEntityCoords(playerPed)
            
            
            if not state.lastPlayerPosition or #(playerCoords - state.lastPlayerPosition) > CONFIG.updatePositionThreshold or GetGameTimer() - state.lastObjectCheck > CONFIG.objectCheckInterval then
                state.cachedObjects = GetNearbyObjects(playerCoords, CONFIG.lightRadius)
                state.lastPlayerPosition = playerCoords
                state.lastObjectCheck = GetGameTimer()
                
                for obj in pairs(state.highlightObjects) do
                    if not DoesEntityExist(obj) then
                        state.highlightObjects[obj] = nil
                    end
                end
            end

            local markerCount = 0
            for obj in pairs(state.cachedObjects) do
                if DoesEntityExist(obj) and markerCount < CONFIG.maxMarkers then
                    local objCoords = GetEntityCoords(obj)
                    if not state.highlightObjects[obj] then
                        DrawMarker(2, objCoords.x, objCoords.y, objCoords.z + 2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            0.5, 0.5, 0.5, 255, 255, 0, 200, true, true, 2, false, nil, nil, false)
                        state.highlightObjects[obj] = true
                        markerCount = markerCount + 1
                    end

                    if #(playerCoords - objCoords) <= 3.0 then
                        DrawText3D(objCoords.x, objCoords.y, objCoords.z + 2.2, "[J] Search Container")
                        if IsControlJustPressed(0, 0xF3830D8E) then
                            SearchContainer(obj)
                        end
                    end
                end
            end

            Wait(next(state.cachedObjects) and 0 or 500)
            
            if CONFIG.debugMode and loopStart then
                local elapsed = GetGameTimer() - loopStart
                if elapsed > 10 then
                    print(string.format("[DEBUG] Object loop took %dms", elapsed))
                end
            end
        end

       
        state.hasLanternActive = false
        state.highlightObjects = {}
        state.cachedObjects = {}
        state.lastPlayerPosition = nil
        lib.hideTextUI()
        lib.notify({
            title = 'Moonlight Lantern',
            description = 'The Moonlight Lantern\'s glow has faded.',
            type = 'inform',
            duration = 3000
        })
    end)
end)


RegisterNetEvent('rsg-moonlight:client:SyncLanternOn')
AddEventHandler('rsg-moonlight:client:SyncLanternOn', function(serverId, coords, duration)
    if CONFIG.debugMode then
        print(string.format("[DEBUG] SyncLanternOn: serverId=%d, coords=%s, duration=%d", serverId, tostring(coords), duration))
    end

    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    if #(playerCoords - coords) > CONFIG.lightVisibilityDistance then
        if CONFIG.debugMode then
            print(string.format("[DEBUG] Player too far from lantern (serverId=%d), distance=%f", serverId, #(playerCoords - coords)))
        end
        return
    end

    state.syncedLanterns[serverId] = {
        endTime = GetGameTimer() + duration,
        coords = coords
    }

    CreateThread(function()
        while state.syncedLanterns[serverId] and GetGameTimer() < state.syncedLanterns[serverId].endTime do
            local targetPed = GetPlayerPed(GetPlayerFromServerId(serverId))
            local drawCoords = targetPed ~= 0 and DoesEntityExist(targetPed) and GetEntityCoords(targetPed) or state.syncedLanterns[serverId].coords
            local playerCoords = GetEntityCoords(PlayerPedId())
            if #(playerCoords - drawCoords) <= CONFIG.lightVisibilityDistance then
                DrawLightWithRange(drawCoords.x, drawCoords.y, drawCoords.z + 1.0, 0, 0, 255, CONFIG.lightRadius, 1.0)
            end
            Wait(0)
        end
        state.syncedLanterns[serverId] = nil
        if CONFIG.debugMode then
            print(string.format("[DEBUG] Stopped drawing light for serverId=%d", serverId))
        end
    end)
end)


RegisterNetEvent('rsg-moonlight:client:SyncLanternOff')
AddEventHandler('rsg-moonlight:client:SyncLanternOff', function(serverId)
    if CONFIG.debugMode then
        print(string.format("[DEBUG] SyncLanternOff: serverId=%d", serverId))
    end
    state.syncedLanterns[serverId] = nil
end)