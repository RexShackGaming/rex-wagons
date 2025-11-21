local RSGCore = exports['rsg-core']:GetCoreObject()
local lastPlayerCoords = vector3(0, 0, 0)
local coordsUpdateTimer = 0
local lastDistanceCheck = 0
local coordsUpdateInterval = Config.Performance and Config.Performance.NpcCoordsUpdate or 2000
local distanceCheckInterval = Config.Performance and Config.Performance.NpcDistanceCheck or 3000
local spawnedPeds = {}
local modelCache = {}
local fadeSteps = {}
local shopOpen = false
lib.locale()

-- pre-calculate fade steps
CreateThread(function()
    for i = 0, 255, 51 do
        fadeSteps[#fadeSteps + 1] = i
    end
end)

CreateThread(function()
    while true do
        local currentTime = GetGameTimer()
        
        -- update player coordinates less frequently
        if currentTime - coordsUpdateTimer > coordsUpdateInterval then
            lastPlayerCoords = GetEntityCoords(PlayerPedId())
            coordsUpdateTimer = currentTime
        end
        
        -- check distances less frequently for better performance
        if currentTime - lastDistanceCheck > distanceCheckInterval then
            for k, v in pairs(Config.WagonShopLocations) do
                local distance = #(lastPlayerCoords - v.npccoords.xyz)
                local spawnDistance = Config.Performance and Config.Performance.NpcSpawnDistance or Config.DistanceSpawn or 20.0
                
                -- spawn NPC if player is close and NPC doesn't exist
                if distance < spawnDistance and not spawnedPeds[k] then
                    CreateThread(function()
                        local spawnedPed = NearPed(v.npcmodel, v.npccoords, v.scenario)
                        if spawnedPed then
                            spawnedPeds[k] = { spawnedPed = spawnedPed }
                            if Config.Debug then
                                print('[rex-wagons] Spawned NPC at ' .. v.name)
                            end
                        end
                    end)
                end
                
                -- despawn NPC if player is far and NPC exists
                if distance >= spawnDistance and spawnedPeds[k] then
                    CreateThread(function()
                        local pedData = spawnedPeds[k]
                        if pedData and DoesEntityExist(pedData.spawnedPed) then
                            if Config.FadeIn then
                                -- optimized fade out
                                for i = 255, 0, -51 do
                                    SetEntityAlpha(pedData.spawnedPed, i, false)
                                    Wait(30) -- reduced wait time for smoother fade
                                end
                            end
                            DeletePed(pedData.spawnedPed)
                            if Config.Debug then
                                print('[rex-butcher] Despawned NPC at ' .. v.name)
                            end
                        end
                        spawnedPeds[k] = nil
                    end)
                end
            end
            lastDistanceCheck = currentTime
        end
        Wait(1000)
    end
end)

function NearPed(npcmodel, npccoords, scenario)
    -- check if model is already cached/loaded
    if not modelCache[npcmodel] then
        RequestModel(npcmodel)
        local timeout = 0
        while not HasModelLoaded(npcmodel) and timeout < 100 do -- Add timeout to prevent infinite loop
            Wait(50)
            timeout = timeout + 1
        end
        
        if not HasModelLoaded(npcmodel) then
            print('[rex-wagons] Failed to load model: ' .. tostring(npcmodel))
            return nil
        end
        
        modelCache[npcmodel] = true
    end
    
    local spawnedPed = CreatePed(npcmodel, npccoords.x, npccoords.y, npccoords.z - 1.0, npccoords.w, false, false, 0, 0)
    
    if not DoesEntityExist(spawnedPed) then
        print('[rex-wagons] Failed to create ped with model: ' .. tostring(npcmodel))
        return nil
    end
    
    -- batch set entity properties for better performance
    SetEntityAlpha(spawnedPed, Config.FadeIn and 0 or 255, false)
    SetRandomOutfitVariation(spawnedPed, true)
    SetEntityCanBeDamaged(spawnedPed, false)
    SetEntityInvincible(spawnedPed, true)
    FreezeEntityPosition(spawnedPed, true)
    SetBlockingOfNonTemporaryEvents(spawnedPed, true)
    SetPedCanBeTargetted(spawnedPed, false)
    SetPedFleeAttributes(spawnedPed, 0, false)
    TaskStartScenarioInPlace(spawnedPed, scenario, 0, true)

    -- Optimized fade in with pre-calculated steps
    if Config.FadeIn then
        CreateThread(function() -- Don't block the main function
            for _, alpha in ipairs(fadeSteps) do
                if DoesEntityExist(spawnedPed) then
                    SetEntityAlpha(spawnedPed, alpha, false)
                    Wait(Config.Performance and Config.Performance.NpcFadeSpeed or 40)
                else
                    break
                end
            end
        end)
    end
    
    -- add target interaction if enabled
	CreateThread(function()
		exports.ox_target:addLocalEntity(spawnedPed, {
			{
				name = 'npc_wagons_shop',
				icon = 'fas fa-shop',
				label = 'Open Wagon Shop',
				onSelect = function()
					TriggerEvent('rex-wagons:openShop')
				end,
				distance = 3.0
			},
		})
	end)
    
    return spawnedPed
end

-- Listen for ESC key to close shop
Citizen.CreateThread(function()
    while true do
        Wait(0)
        if shopOpen then
            if IsDisabledControlJustReleased(0, 27) then -- ESC key
                CloseShop()
            end
        else
            Wait(100)
        end
    end
end)

-- Function to close shop
function CloseShop()
    shopOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({type = 'setVisible', visible = false})
end

-- NUI callback when close button is clicked
RegisterNUICallback('close', function(data, cb)
    CloseShop()
    cb('ok')
end)

-- cleanup
AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for k,v in pairs(spawnedPeds) do
        DeletePed(spawnedPeds[k].spawnedPed)
        spawnedPeds[k] = nil
    end
    if shopOpen then
        SetNuiFocus(false, false)
    end
end)
