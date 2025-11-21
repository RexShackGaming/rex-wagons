local RSGCore = exports['rsg-core']:GetCoreObject()
local NUIOpen = false
local NUIClosingTime = 0
local spawnedWagons = {} -- { entity, netId, plate, model }
local SpawnedWagonShopBilps = {}
local currentActiveWagon = nil
local lastCallTime = 0 -- Cooldown for calling wagon
lib.locale()

-- ====================================================================
-- blips
-- ====================================================================
Citizen.CreateThread(function()
    for _,v in pairs(Config.WagonShopLocations) do
        if v.showblip == true then
            local WagonShopBlip = BlipAddForCoords(1664425300, v.coords)
            SetBlipSprite(WagonShopBlip, joaat(v.blipsprite), true)
            SetBlipScale(WagonShopBlip, v.blipscale)
            SetBlipName(WagonShopBlip, v.blipname)
            table.insert(SpawnedWagonShopBilps, WagonShopBlip)
        end
    end
end)

local currentShopIndex = nil

-- ====================================================================
-- Open Wagon Shop
-- ====================================================================
RegisterNetEvent('rex-wagons:openShop', function(shopIndex)
    if NUIOpen or GetGameTimer() - NUIClosingTime < 500 then return end
    NUIOpen = true
    SetNuiFocus(true, true)
    currentShopIndex = shopIndex
    TriggerServerEvent('rex-wagons:setShopLocation', shopIndex)
    SendNUIMessage({ type = 'openShop' })
    TriggerServerEvent('rex-wagons:getShopData')
end)

-- ====================================================================
-- Receive shop data
-- ====================================================================
RegisterNetEvent('rex-wagons:setShopData', function(availableWagons, playerWagons, cash)
    SendNUIMessage({ type = 'setWagons', wagons = availableWagons })
    SendNUIMessage({ type = 'setOwnedWagons', wagons = playerWagons })
    SendNUIMessage({ type = 'setPlayerCash', cash = cash })
end)

-- ====================================================================
-- NUI Callbacks
-- ====================================================================
RegisterNUICallback('closeShop', function(_, cb)
    CloseShopNUI()
    cb('ok')
end)

RegisterNUICallback('purchaseWagon', function(data, cb)
    local playerCoords = GetEntityCoords(PlayerPedId())
    TriggerServerEvent('rex-wagons:purchaseWagon', data.wagonId, playerCoords)
    cb('ok')
end)

local isSpawningWagon = false

RegisterNUICallback('spawnWagon', function(data, cb)
    if isSpawningWagon then cb('ok') return end
    isSpawningWagon = true
    local playerCoords = GetEntityCoords(PlayerPedId())
    TriggerServerEvent('rex-wagons:spawnWagon', data.wagonId, playerCoords, currentShopIndex)
    SetTimeout(2000, function()
        isSpawningWagon = false
        if NUIOpen then CloseShopNUI() end
    end)
    cb('ok')
end)

RegisterNUICallback('unstoreWagon', function(data, cb)
    if isSpawningWagon then cb('ok') return end
    isSpawningWagon = true
    local playerCoords = GetEntityCoords(PlayerPedId())
    TriggerServerEvent('rex-wagons:unstoreWagon', data.wagonId, playerCoords)
    SetTimeout(2000, function()
        isSpawningWagon = false
        if NUIOpen then CloseShopNUI() end
    end)
    cb('ok')
end)

RegisterNUICallback('deleteWagonConfirm', function(data, cb)
    local sellPrice = math.ceil(data.price * 0.50)
    local alert = lib.alertDialog({
        header = locale('sell_header') or 'Sell Wagon',
        content = locale('sell_confirm'):format(sellPrice) or ('Are you sure you want to sell this wagon for $%d?'):format(sellPrice),
        centered = true,
        cancel = true
    })
    if alert == 'confirm' then
        TriggerServerEvent('rex-wagons:deleteWagon', data.wagonId)
    end
    cb('ok')
end)

RegisterNUICallback('getTransferData', function(data, cb)
    TriggerServerEvent('rex-wagons:getTransferData', data.wagonId)
    cb('ok')
end)

RegisterNUICallback('transferWagon', function(data, cb)
    TriggerServerEvent('rex-wagons:transferWagon', data.wagonId, data.targetShopIndex)
    cb('ok')
end)

RegisterNUICallback('notifySuccess', function(data, cb)
    lib.notify({ type = 'success', description = data.message })
    cb('ok')
end)

RegisterNUICallback('notifyError', function(data, cb)
    lib.notify({ type = 'error', description = data.message })
    cb('ok')
end)

RegisterNUICallback('setActiveWagon', function(data, cb)
    if data and data.wagonId then
        TriggerServerEvent('rex-wagons:setActiveWagon', data.wagonId, currentShopIndex)
    end
    cb('ok')
end)

-- ====================================================================
-- Purchase success → keep open and show My Wagons tab
-- ====================================================================
RegisterNetEvent('rex-wagons:purchaseSuccess', function()
    if NUIOpen then
        SendNUIMessage({ type = 'purchaseSuccess' })
    end
end)

-- ====================================================================
-- Check if spawn point is clear
-- ====================================================================
local function isSpawnPointClear(spawnPos, checkRadius)
    checkRadius = checkRadius or Config.CheckSpawnDistance

    for _, ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and not IsEntityDead(ped) then
            if #(spawnPos - GetEntityCoords(ped)) < checkRadius then
                return false
            end
        end
    end

    for _, obj in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(obj) and #(spawnPos - GetEntityCoords(obj)) < checkRadius then
            return false
        end
    end

    return true
end

-- ====================================================================
-- Actually spawn the wagon (called from server)
-- ====================================================================
RegisterNetEvent('rex-wagons:doSpawnWagon', function(wagonData, shopLocationIndex)
    local shopLocation = Config.WagonShopLocations[shopLocationIndex or 1]
    if not shopLocation or not shopLocation.spawnpoint then
        return lib.notify({ title = 'Error', description = 'Shop spawn point not configured.', type = 'error' })
    end

    local spawnPoint = shopLocation.spawnpoint
    local spawnPos = vec3(spawnPoint.x, spawnPoint.y, spawnPoint.z)
    local heading = spawnPoint.w or 0.0

    if not isSpawnPointClear(spawnPos) then
        return lib.notify({
            title = 'Spawn Point Blocked',
            description = 'Another player or object is blocking the spawn point. Please wait or try another location.',
            type = 'error'
        })
    end

    local modelHash = type(wagonData.model) == 'string' and GetHashKey(wagonData.model) or wagonData.model
    if not HasModelLoaded(modelHash) then
        RequestModel(modelHash)
        local timeout = 0
        while not HasModelLoaded(modelHash) and timeout < 10000 do
            Wait(50)
            timeout = timeout + 50
        end
    end

    if not HasModelLoaded(modelHash) then
        SetModelAsNoLongerNeeded(modelHash)
        return lib.notify({ title = 'Error', description = 'Failed to load wagon model.', type = 'error' })
    end

    local vehicle = CreateVehicle(modelHash, spawnPos.x, spawnPos.y, spawnPos.z, heading, true, false)
    SetVehicleOnGroundProperly(vehicle)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetModelAsNoLongerNeeded(modelHash)

    table.insert(spawnedWagons, {
        entity = vehicle,
        netId = NetworkGetNetworkIdFromEntity(vehicle),
        plate = wagonData.plate,
        model = wagonData.model
    })

    exports.ox_target:addLocalEntity(vehicle, {
        { name = 'storage_wagon', icon = 'fas fa-warehouse', label = 'Wagon Storage', distance = 2.5, onSelect = function()
            TriggerServerEvent('rex-wagons:server:openStorage', wagonData)
        end },
        { name = 'store_wagon', icon = 'fas fa-warehouse', label = 'Store Wagon', distance = 2.5, onSelect = function()
            TriggerServerEvent('rex-wagons:storeWagon', wagonData.plate)
        end },
    })

    CloseShopNUI()
    SendNUIMessage({ type = 'wagonSpawned', plate = wagonData.plate, label = wagonData.label })
    lib.notify({
        type = 'success',
        title = 'Wagon Spawned',
        description = ('%s has been spawned!'):format(wagonData.label),
        duration = 6000
    })
end)

-- ====================================================================
-- Close NUI safely
-- ====================================================================
function CloseShopNUI()
    if not NUIOpen then return end
    NUIOpen = false
    NUIClosingTime = GetGameTimer()
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'closeShop' })
end

-- ====================================================================
-- Cleanup events
-- ====================================================================
RegisterNetEvent('rex-wagons:wagonDeleted', function(plate)
    for i = #spawnedWagons, 1, -1 do
        local wagon = spawnedWagons[i]
        if wagon.plate == plate and DoesEntityExist(wagon.entity) then
            DeleteEntity(wagon.entity)
            table.remove(spawnedWagons, i)
        end
    end
    SendNUIMessage({ type = 'wagonDeleted', plate = plate })
end)

RegisterNetEvent('rex-wagons:forceCleanup', function(plate)
    for i = #spawnedWagons, 1, -1 do
        local wagon = spawnedWagons[i]
        if wagon.plate == plate and DoesEntityExist(wagon.entity) then
            DeleteEntity(wagon.entity)
            table.remove(spawnedWagons, i)
        end
    end
end)

RegisterNetEvent('rex-wagons:wagonStored', function(plate)
    for i = #spawnedWagons, 1, -1 do
        local wagon = spawnedWagons[i]
        if wagon.plate == plate and DoesEntityExist(wagon.entity) then
            DeleteEntity(wagon.entity)
            table.remove(spawnedWagons, i)
        end
    end
    SendNUIMessage({ type = 'wagonStored', plate = plate })
    lib.notify({
        type = 'success',
        title = 'Wagon Stored',
        description = 'Your wagon has been stored and can be retrieved from the wagon shop.',
        duration = 5000
    })
end)

-- ====================================================================
-- Spawn wagon near player at safe distance
-- ====================================================================
RegisterNetEvent('rex-wagons:spawnWagonNearPlayer', function(wagonData)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local spawnDistance = Config.CallWagon.SpawnDistanceFromPlayer or 50.0
    local attempts = 0
    local maxAttempts = 8
    local spawnPos = nil

    -- Try 8 directions around the player to find a clear spot
    for attempt = 1, maxAttempts do
        local angle = (attempt - 1) * (360 / maxAttempts)
        local offsetX = math.cos(math.rad(angle)) * spawnDistance
        local offsetY = math.sin(math.rad(angle)) * spawnDistance
        local checkPos = playerCoords + vec3(offsetX, offsetY, 100.0)

        local found, groundZ = GetGroundZAndNormalFor_3dCoord(checkPos.x, checkPos.y, checkPos.z)
        if found then
            local testPos = vec3(checkPos.x, checkPos.y, groundZ)
            if isSpawnPointClear(testPos, Config.CheckSpawnDistance or 3.0) then
                spawnPos = testPos
                break
            end
        end
        Wait(0)
    end

    -- Fallback: try in front of player
    if not spawnPos then
        local heading = GetEntityHeading(playerPed)
        local forward = vec3(math.cos(math.rad(heading)), math.sin(math.rad(heading)), 0.0) * spawnDistance
        local fallback = playerCoords + forward + vec3(0, 0, 100.0)
        local found, groundZ = GetGroundZAndNormalFor_3dCoord(fallback.x, fallback.y, fallback.z)
        if found then
            spawnPos = vec3(fallback.x, fallback.y, groundZ)
        end
    end

    if not spawnPos then
        lib.notify({ type = 'error', description = 'Could not find a clear space to spawn your wagon.', duration = 5000 })
        TriggerServerEvent('rex-wagons:callWagonFailedServer', wagonData.plate)
        return
    end

    local modelHash = type(wagonData.model) == 'string' and GetHashKey(wagonData.model) or wagonData.model
    RequestModel(modelHash)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 10000 do Wait(50) timeout = timeout + 50 end

    if not HasModelLoaded(modelHash) then
        SetModelAsNoLongerNeeded(modelHash)
        lib.notify({ type = 'error', description = 'Failed to load wagon model.', duration = 5000 })
        TriggerServerEvent('rex-wagons:callWagonFailedServer', wagonData.plate)
        return
    end

    -- Calculate heading toward player
    local dx = playerCoords.x - spawnPos.x
    local dy = playerCoords.y - spawnPos.y
    local heading = math.deg(math.atan2(dy, dx))

    local vehicle = CreateVehicle(modelHash, spawnPos.x, spawnPos.y, spawnPos.z, heading, true, false)
    SetVehicleOnGroundProperly(vehicle)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetModelAsNoLongerNeeded(modelHash)
	wagonblip = Citizen.InvokeNative(0x23F74C2FDA6E7C61, -1230993421, vehicle)
	Citizen.InvokeNative(0x9CB1A1623062F402, wagonblip, 'My Wagon')

    table.insert(spawnedWagons, {
        entity = vehicle,
        netId = NetworkGetNetworkIdFromEntity(vehicle),
        plate = wagonData.plate,
        model = wagonData.model
    })

    exports.ox_target:addLocalEntity(vehicle, {
        { name = 'storage_wagon', icon = 'fas fa-warehouse', label = 'Wagon Storage', distance = 2.5, onSelect = function()
            TriggerServerEvent('rex-wagons:server:openStorage', wagonData)
        end },
        { name = 'store_wagon', icon = 'fas fa-warehouse', label = 'Store Wagon', distance = 2.5, onSelect = function()
            TriggerServerEvent('rex-wagons:storeWagon', wagonData.plate)
        end },
    })

    lib.notify({
        type = 'success',
        title = 'Wagon Spawned',
        description = ('%s has been spawned nearby!'):format(wagonData.label),
        duration = 5000
    })
end)

-- ====================================================================
-- Transfer & active wagon events
-- ====================================================================
RegisterNetEvent('rex-wagons:showTransferOptions', function(transferData)
    SendNUIMessage({ type = 'showTransferOptions', transferData = transferData })
end)

RegisterNetEvent('rex-wagons:receiveTransferData', function(transferData)
    SendNUIMessage({ type = 'receiveTransferData', transferData = transferData })
end)

RegisterNetEvent('rex-wagons:transferSuccess', function()
     SendNUIMessage({ type = 'transferSuccess' })
     if NUIOpen then TriggerServerEvent('rex-wagons:getShopData') end
end)

RegisterNetEvent('rex-wagons:updateActiveWagon', function(data) currentActiveWagon = data end)
RegisterNetEvent('rex-wagons:activeWagonSet', function(data) currentActiveWagon = data end)

RegisterNetEvent('rex-wagons:sendUIMessage', function(data)
    SendNUIMessage(data)
end)

-- ====================================================================
-- Resource stop cleanup
-- ====================================================================
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for i = #spawnedWagons, 1, -1 do
        if DoesEntityExist(spawnedWagons[i].entity) then
            DeleteEntity(spawnedWagons[i].entity)
        end
    end
    spawnedWagons = {}
end)

-- ====================================================================
-- ESC to close
-- ====================================================================
CreateThread(function()
    while true do
        Wait(0)
        if NUIOpen and IsControlJustReleased(0, 0x4CC0E2FE) then -- ESC
            CloseShopNUI()
        end
    end
end)