local RSGCore = exports['rsg-core']:GetCoreObject()

-- In-memory caches
local playerWagons        = {} -- [citizenid] = { wagon table }
local spawnedWagons      = {} -- [plate] = { src, citizenid, wagonId }
local playerActiveWagon  = {} -- [citizenid] = plate (prevents double spawn)
local playerShopLocation = {} -- [citizenid] = shop location index (which shop they're at)

-- ====================================================================
-- Database: Load all owned wagons on resource start
-- ====================================================================
local function LoadAllWagons()
    local result = MySQL.query.await('SELECT * FROM rex_wagons')
    if not result or not next(result) then
        print("^2[rex-wagons] No wagons found in database.^7")
        return
    end

    playerWagons = {}
    for _, row in ipairs(result) do
        local cid = row.citizen_id
        playerWagons[cid] = playerWagons[cid] or {}

        local shopIndex = row.storage_shop or 1
        local shopName = Config.WagonShopLocations[shopIndex]?.name or "Unknown Shop"

        table.insert(playerWagons[cid], {
            id          = row.wagon_id,
            label       = row.label,
            model       = row.model,
            plate       = row.plate,
            price       = row.price,
            storage     = row.storage,
            slots       = row.slots,
            description = row.description or '',
            stored      = row.stored == 1 or row.stored == true,
            storage_shop = shopIndex,
            storage_shop_name = shopName
        })
    end

    -- Fixed count
    local playerCount = 0
    for _ in pairs(playerWagons) do playerCount = playerCount + 1 end

    print(("^2[rex-wagons] Loaded %d owned wagons for %d players.^7"):format(#result, playerCount))
end

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    LoadAllWagons()
end)

-- ====================================================================
-- Helper: Get player's owned wagons
-- ====================================================================
local function GetPlayerWagons(citizenid)
    return playerWagons[citizenid] or {}
end

-- ====================================================================
-- Helper: Get nearest shop to player based on coords
-- ====================================================================
local function GetNearestShop(playerCoords)
    local nearestIdx, nearestDist = nil, math.huge
    for i, shop in ipairs(Config.WagonShopLocations) do
        local shopCoords = type(shop.coords) == 'table' and vector3(shop.coords.x, shop.coords.y, shop.coords.z) or shop.coords
        local dist = #(playerCoords - shopCoords)
        if dist < nearestDist then
            nearestDist = dist
            nearestIdx = i
        end
    end
    return nearestIdx, nearestDist
end

-- ====================================================================
-- Track which shop location player is at
-- ====================================================================
RegisterNetEvent('rex-wagons:setShopLocation', function(shopLocationIndex)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    playerShopLocation[citizenid] = shopLocationIndex
end)

-- ====================================================================
-- Send shop data to client
-- ====================================================================
RegisterNetEvent('rex-wagons:getShopData', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local cash = Player.PlayerData.money.cash or 0

    TriggerClientEvent('rex-wagons:setShopData', src,
        Config.AvailableWagons,
        GetPlayerWagons(citizenid),
        cash
    )
end)

-- ====================================================================
-- Purchase wagon
-- ====================================================================
RegisterNetEvent('rex-wagons:purchaseWagon', function(wagonId, playerCoords)
     local src = source
     local Player = RSGCore.Functions.GetPlayer(src)
     if not Player then return end

     local citizenid = Player.PlayerData.citizenid

     -- Find wagon config
     local wagonConfig = nil
     for _, w in ipairs(Config.AvailableWagons) do
         if w.id == wagonId then wagonConfig = w break end
     end
     if not wagonConfig then
         lib.notify(src, { type = 'error', description = 'Invalid wagon selected' })
         return
     end

     -- Max wagons check
     if #GetPlayerWagons(citizenid) >= (Config.WagonShop?.MaxWagons or 10) then
         lib.notify(src, { type = 'error', description = 'You already own the maximum number of wagons' })
         return
     end

     -- Money check
     if not Player.Functions.RemoveMoney('cash', wagonConfig.price) then
         lib.notify(src, { type = 'error', description = 'Not enough cash' })
         return
     end

     -- Generate unique plate
     local plate
     repeat
         plate = ('W%s'):format(math.random(100000, 999999))
     until not spawnedWagons[plate] and MySQL.scalar.await('SELECT 1 FROM rex_wagons WHERE plate = ?', { plate }) == nil

     -- Get the shop location they're at to store with the wagon (use coords for accuracy)
     local shopLocationIndex = 1
     if playerCoords then
         shopLocationIndex = GetNearestShop(playerCoords) or 1
     else
         shopLocationIndex = playerShopLocation[citizenid] or 1
     end

    -- Insert into DB first (most important!)
    local insertId = MySQL.insert.await([[
        INSERT INTO rex_wagons (citizen_id, wagon_id, model, plate, label, price, storage, slots, description, storage_shop)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        citizenid,
        wagonConfig.id,
        wagonConfig.model,
        plate,
        wagonConfig.label,
        wagonConfig.price,
        wagonConfig.storage,
        wagonConfig.slots,
        wagonConfig.description or '',
        shopLocationIndex
    })

    if not insertId then
        Player.Functions.AddMoney('cash', wagonConfig.price) -- rollback
        lib.notify(src, { type = 'error', description = 'Database error – purchase cancelled' })
        return
    end

     -- now safe to add to memory
     playerWagons[citizenid] = playerWagons[citizenid] or {}
     local shopName = Config.WagonShopLocations[shopLocationIndex]?.name or "Unknown Shop"
     table.insert(playerWagons[citizenid], {
         id          = wagonConfig.id,
         label       = wagonConfig.label,
         model       = wagonConfig.model,
         plate       = plate,
         price       = wagonConfig.price,
         storage     = wagonConfig.storage,
         slots       = wagonConfig.slots,
         description = wagonConfig.description or '',
         stored      = false,
         storage_shop = shopLocationIndex,
         storage_shop_name = shopName
     })

    lib.notify(src, { type = 'success', description = ('Purchased %s for $%d'):format(wagonConfig.label, wagonConfig.price) })
    TriggerClientEvent('rex-wagons:purchaseSuccess', src)
end)

-- ====================================================================
-- Spawn wagon
-- ====================================================================
RegisterNetEvent('rex-wagons:spawnWagon', function(wagonId, playerCoords)
     local src = source
     local Player = RSGCore.Functions.GetPlayer(src)
     if not Player then return end

     local citizenid = Player.PlayerData.citizenid

     -- Prevent double spawn
     if playerActiveWagon[citizenid] then
         lib.notify(src, { type = 'error', description = 'You already have a wagon spawned. Return it first.' })
         return
     end

     local owned = GetPlayerWagons(citizenid)
     local wagonData = nil
     for _, w in ipairs(owned) do
         if w.id == wagonId then
             wagonData = w
             break
         end
     end

     if not wagonData then
         lib.notify(src, { type = 'error', description = 'You do not own this wagon' })
         return
     end

     -- Prevent same wagon being spawned twice globally
     if spawnedWagons[wagonData.plate] then
         lib.notify(src, { type = 'error', description = 'This wagon is already in the world' })
         return
     end

     -- Use the wagon's stored shop location
     local storedShopIndex = wagonData.storage_shop or 1
     local storedShop = Config.WagonShopLocations[storedShopIndex]
     if not storedShop then
         lib.notify(src, { type = 'error', description = 'Shop location not found' })
         return
     end

     -- Find nearest shop to player and check if it matches wagon's stored location
     if playerCoords then
         local nearestIdx, nearestDist = GetNearestShop(playerCoords)
         local spawnRadius = Config.WagonShop?.SpawnRadius or 10.0
         
         if nearestDist > spawnRadius then
             lib.notify(src, { type = 'error', description = 'You are not at a wagon shop' })
             return
         end
         
         if nearestIdx ~= storedShopIndex then
             lib.notify(src, { type = 'error', description = ('This wagon is stored at %s. Go there to spawn it.'):format(storedShop.name) })
             return
         end
     end

     -- All checks passed → register as spawned
     spawnedWagons[wagonData.plate] = { src = src, citizenid = citizenid }
     playerActiveWagon[citizenid] = wagonData.plate

     TriggerClientEvent('rex-wagons:doSpawnWagon', src, wagonData, storedShopIndex)
end)

-- ====================================================================
-- Sell wagon
-- ====================================================================
RegisterNetEvent('rex-wagons:deleteWagon', function(wagonId)
     local src = source
     local Player = RSGCore.Functions.GetPlayer(src)
     if not Player then return end

     local citizenid = Player.PlayerData.citizenid
     local owned = GetPlayerWagons(citizenid)

     local wagon = nil
     local index = nil
     for i, w in ipairs(owned) do
         if w.id == wagonId then
             wagon = w
             index = i
             break
         end
     end

     if not wagon then
         lib.notify(src, { type = 'error', description = 'Wagon not found' })
         return
     end

     -- If it's currently spawned → clean up
     if spawnedWagons[wagon.plate] then
         TriggerClientEvent('rex-wagons:forceCleanup', spawnedWagons[wagon.plate].src or src, wagon.plate)
         spawnedWagons[wagon.plate] = nil
     end
     if playerActiveWagon[citizenid] == wagon.plate then
         playerActiveWagon[citizenid] = nil
     end

     -- Calculate sell price based on config percentage
     local sellPercentage = Config.WagonShop.SellPercentage or 0.50
     local sellPrice = math.ceil(wagon.price * sellPercentage)

     -- Add money to player
     Player.Functions.AddMoney('cash', sellPrice)

      -- Remove inventory from stash table
      local stashId = 'wagon_storage_' .. wagon.plate
      MySQL.query.await('DELETE FROM inventories WHERE identifier = ?', { stashId })

      -- Remove from DB
      MySQL.query.await('DELETE FROM rex_wagons WHERE citizen_id = ? AND plate = ?', { citizenid, wagon.plate })

      -- Remove from memory
      table.remove(owned, index)

     lib.notify(src, { type = 'success', description = ('Sold %s for $%d'):format(wagon.label, sellPrice) })
     TriggerClientEvent('rex-wagons:wagonDeleted', src, wagon.plate)
end)

-- ====================================================================
-- Player disconnect cleanup
-- ====================================================================
AddEventHandler('playerDropped', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local activePlate = playerActiveWagon[citizenid]

    if activePlate and spawnedWagons[activePlate] then
        TriggerClientEvent('rex-wagons:forceCleanup', spawnedWagons[activePlate].src or -1, activePlate)
        spawnedWagons[activePlate] = nil
    end

    playerActiveWagon[citizenid] = nil
end)

-- ====================================================================
-- Resource stop cleanup
-- ====================================================================
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end

    for plate, data in pairs(spawnedWagons) do
        if data.src and GetPlayerName(data.src) then
            TriggerClientEvent('rex-wagons:forceCleanup', data.src, plate)
        end
    end

    spawnedWagons = {}
    playerActiveWagon = {}
    print("^2[rex-wagons] Server-side cleanup complete.^7")
end)

-- ====================================================================
-- Store wagon (put it away but keep ownership)
-- ====================================================================
RegisterNetEvent('rex-wagons:storeWagon', function(plate)
     local src = source
     local Player = RSGCore.Functions.GetPlayer(src)
     if not Player then return end

     local citizenid = Player.PlayerData.citizenid

     -- Check if wagon is spawned and belongs to player
     if not spawnedWagons[plate] or spawnedWagons[plate].citizenid ~= citizenid then
         lib.notify(src, { type = 'error', description = 'This wagon does not belong to you' })
         return
     end

     -- Update DB to mark as stored
     MySQL.query.await('UPDATE rex_wagons SET stored = TRUE WHERE plate = ?', { plate })

     -- Clean up from world
     TriggerClientEvent('rex-wagons:forceCleanup', src, plate)
     spawnedWagons[plate] = nil
     playerActiveWagon[citizenid] = nil

     -- Update memory cache
     local owned = GetPlayerWagons(citizenid)
     for _, w in ipairs(owned) do
         if w.plate == plate then
             w.stored = true
             break
         end
     end

     lib.notify(src, { type = 'success', description = 'Wagon stored successfully' })
     TriggerClientEvent('rex-wagons:wagonStored', src, plate)
end)

-- ====================================================================
-- Unstore wagon (retrieve from storage)
-- ====================================================================
RegisterNetEvent('rex-wagons:unstoreWagon', function(wagonId, playerCoords)
     local src = source
     local Player = RSGCore.Functions.GetPlayer(src)
     if not Player then return end

     local citizenid = Player.PlayerData.citizenid

     -- Prevent double spawn
     if playerActiveWagon[citizenid] then
         lib.notify(src, { type = 'error', description = 'You already have a wagon spawned. Return it first.' })
         return
     end

     local owned = GetPlayerWagons(citizenid)
     local wagonData = nil
     for _, w in ipairs(owned) do
         if w.id == wagonId then
             wagonData = w
             break
         end
     end

     if not wagonData then
         lib.notify(src, { type = 'error', description = 'You do not own this wagon' })
         return
     end

     if not wagonData.stored then
          lib.notify(src, { type = 'error', description = 'This wagon is not stored' })
          return
      end

      -- Prevent same wagon being spawned twice globally
      if spawnedWagons[wagonData.plate] then
          lib.notify(src, { type = 'error', description = 'This wagon is already in the world' })
          return
      end

     -- Use the wagon's stored shop location
     local storedShopIndex = wagonData.storage_shop or 1
     local storedShop = Config.WagonShopLocations[storedShopIndex]
     if not storedShop then
         lib.notify(src, { type = 'error', description = 'Shop location not found' })
         return
     end

     -- Find nearest shop to player and check if it matches wagon's stored location
     if playerCoords then
         local nearestIdx, nearestDist = GetNearestShop(playerCoords)
         local spawnRadius = Config.WagonShop?.SpawnRadius or 10.0
         
         if nearestDist > spawnRadius then
             lib.notify(src, { type = 'error', description = 'You are not at a wagon shop' })
             return
         end
         
         if nearestIdx ~= storedShopIndex then
             lib.notify(src, { type = 'error', description = ('This wagon is stored at %s. Go there to retrieve it.'):format(storedShop.name) })
             return
         end
     end

    -- Update DB to mark as unstored
    MySQL.query.await('UPDATE rex_wagons SET stored = FALSE WHERE plate = ?', { wagonData.plate })

     -- Update memory cache
     wagonData.stored = false

     -- Register as spawned
     spawnedWagons[wagonData.plate] = { src = src, citizenid = citizenid }
     playerActiveWagon[citizenid] = wagonData.plate

     lib.notify(src, { type = 'success', description = ('Retrieved %s from storage'):format(wagonData.label) })
     TriggerClientEvent('rex-wagons:doSpawnWagon', src, wagonData, storedShopIndex)
end)

-- Optional: utility function for other resources
exports('GetPlayerWagons', GetPlayerWagons)

-- wagon storage
RegisterNetEvent('rex-wagons:server:openStorage', function(wagonData)
     local src = source
     local stashId = 'wagon_storage_' .. wagonData.plate
     local maxWeight = wagonData.storage
     local slots = wagonData.slots
     local inventoryData = { label = 'Wagon Storage', maxweight = maxWeight, slots = slots }
     exports['rsg-inventory']:OpenInventory(src, stashId, inventoryData)
end)

-- ====================================================================
-- Transfer wagon to another shop
-- ====================================================================
RegisterNetEvent('rex-wagons:transferWagon', function(wagonId, targetShopIndex)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local cash = Player.PlayerData.money.cash or 0

    -- Validate target shop exists
    if not Config.WagonShopLocations[targetShopIndex] then
        lib.notify(src, { type = 'error', description = 'Invalid destination shop' })
        return
    end

    -- Find the wagon
    local owned = GetPlayerWagons(citizenid)
    local wagonData = nil
    for _, w in ipairs(owned) do
        if w.id == wagonId then
            wagonData = w
            break
        end
    end

    if not wagonData then
        lib.notify(src, { type = 'error', description = 'Wagon not found' })
        return
    end

    -- Can't transfer to same shop
    local currentShopIndex = wagonData.storage_shop
    if currentShopIndex == targetShopIndex then
        lib.notify(src, { type = 'error', description = 'Wagon is already stored at this shop' })
        return
    end

     -- Calculate transfer cost based on non-linear distance formula: base + (distance ^ exponent) * multiplier
     local currentShop = Config.WagonShopLocations[currentShopIndex]
     local targetShop = Config.WagonShopLocations[targetShopIndex]
     
     local distance = #(currentShop.coords - targetShop.coords)
     local basePrice = Config.WagonShop.TransferBasePrice or 100
     local exponent = Config.WagonShop.TransferDistanceExponent or 1.3
     local multiplier = Config.WagonShop.TransferDistanceMultiplier or 0.01
     local transferCost = math.ceil(basePrice + (distance ^ exponent) * multiplier)

    -- Check if player has enough money
    if cash < transferCost then
        lib.notify(src, { type = 'error', description = ('Insufficient funds. Cost: $%d, You have: $%d'):format(transferCost, cash) })
        return
    end

    -- If wagon is spawned, can't transfer
    if spawnedWagons[wagonData.plate] then
        lib.notify(src, { type = 'error', description = 'Wagon must be stored before transferring' })
        return
    end

    -- Deduct money
    if not Player.Functions.RemoveMoney('cash', transferCost) then
        lib.notify(src, { type = 'error', description = 'Payment failed' })
        return
    end

     -- Update database
     MySQL.query.await('UPDATE rex_wagons SET storage_shop = ? WHERE plate = ?', { targetShopIndex, wagonData.plate })

     -- Update memory cache
     wagonData.storage_shop = targetShopIndex
     wagonData.storage_shop_name = targetShop.name

     lib.notify(src, { type = 'success', description = ('Wagon transferred to %s for $%d'):format(targetShop.name, transferCost) })
     TriggerClientEvent('rex-wagons:transferSuccess', src, wagonId)
end)

-- ====================================================================
-- Get transfer data (shops and costs)
-- ====================================================================
RegisterNetEvent('rex-wagons:getTransferData', function(wagonId)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid

    -- Find the wagon
    local owned = GetPlayerWagons(citizenid)
    local wagonData = nil
    for _, w in ipairs(owned) do
        if w.id == wagonId then
            wagonData = w
            break
        end
    end

    if not wagonData then return end

    local currentShopIndex = wagonData.storage_shop
    local currentShop = Config.WagonShopLocations[currentShopIndex]
    local transferData = {}

     -- Build list of available destination shops with costs using non-linear formula
     local basePrice = Config.WagonShop.TransferBasePrice or 100
     local exponent = Config.WagonShop.TransferDistanceExponent or 1.3
     local multiplier = Config.WagonShop.TransferDistanceMultiplier or 0.01
     
     for shopIndex, shop in ipairs(Config.WagonShopLocations) do
         if shopIndex ~= currentShopIndex then
             local distance = #(currentShop.coords - shop.coords)
             local cost = math.ceil(basePrice + (distance ^ exponent) * multiplier)

             table.insert(transferData, {
                 shopIndex = shopIndex,
                 name = shop.name,
                 distance = math.floor(distance),
                 cost = cost
             })
         end
     end

      TriggerClientEvent('rex-wagons:receiveTransferData', src, transferData)
end)

-- ====================================================================
-- Set active wagon
-- ====================================================================
RegisterNetEvent('rex-wagons:setActiveWagon', function(wagonId)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local owned = GetPlayerWagons(citizenid)

    -- Validate wagon belongs to player
    local wagonData = nil
    for _, w in ipairs(owned) do
        if w.id == wagonId then
            wagonData = w
            break
        end
    end

    if not wagonData then
        lib.notify(src, { type = 'error', description = 'You do not own this wagon' })
        return
    end

    -- Clear previous active wagon
    MySQL.query.await('UPDATE rex_wagons SET is_active = FALSE WHERE citizen_id = ?', { citizenid })

    -- Set new active wagon
    MySQL.query.await('UPDATE rex_wagons SET is_active = TRUE WHERE plate = ?', { wagonData.plate })

    -- Update memory cache
    for _, w in ipairs(owned) do
        w.is_active = (w.plate == wagonData.plate)
    end

    lib.notify(src, { type = 'success', description = ('Set %s as your active wagon'):format(wagonData.label) })
    TriggerClientEvent('rex-wagons:activeWagonSet', src, wagonData)
end)

-- ====================================================================
-- Get active wagon
-- ====================================================================
local function GetPlayerActiveWagon(citizenid)
     local owned = GetPlayerWagons(citizenid)
     for _, w in ipairs(owned) do
         if w.is_active then
             return w
         end
     end
     return nil
end

-- ====================================================================
-- Retrieve active wagon from database on first call
-- ====================================================================
local function LoadActiveWagonFromDB(citizenid)
     local result = MySQL.query.await('SELECT * FROM rex_wagons WHERE citizen_id = ? AND is_active = TRUE LIMIT 1', { citizenid })
     if result and result[1] then
         local row = result[1]
         local shopIndex = row.storage_shop or 1
         local shopName = Config.WagonShopLocations[shopIndex]?.name or "Unknown Shop"
         
         return {
             id          = row.wagon_id,
             label       = row.label,
             model       = row.model,
             plate       = row.plate,
             price       = row.price,
             storage     = row.storage,
             slots       = row.slots,
             description = row.description or '',
             stored      = row.stored == 1 or row.stored == true,
             storage_shop = shopIndex,
             storage_shop_name = shopName,
             is_active   = true
         }
     end
     return nil
end

-- ====================================================================
-- Call wagon command
-- ====================================================================
RegisterCommand('callwagon', function(source, args, rawCommand)
     local src = source
     local Player = RSGCore.Functions.GetPlayer(src)
     if not Player then return end
 
     local citizenid = Player.PlayerData.citizenid
     
     -- Try memory cache first, if not found load from DB
     local activeWagon = GetPlayerActiveWagon(citizenid)
     if not activeWagon then
         activeWagon = LoadActiveWagonFromDB(citizenid)
     end
 
     -- Check if player has an active wagon set
     if not activeWagon then
         lib.notify(src, { type = 'error', description = 'You have no active wagon set. Select one from the wagon shop.' })
         return
     end
 
     -- Check if wagon is already spawned in the world
     if spawnedWagons[activeWagon.plate] then
         lib.notify(src, { type = 'error', description = 'Your wagon is already in the world' })
         return
     end
 
     -- Prevent double spawn
     if playerActiveWagon[citizenid] then
         lib.notify(src, { type = 'error', description = 'You already have a wagon spawned. Return it first.' })
         return
     end
     
     -- If wagon is stored, unstore it first
     if activeWagon.stored then
         MySQL.query.await('UPDATE rex_wagons SET stored = FALSE WHERE plate = ?', { activeWagon.plate })
         activeWagon.stored = false
         
         -- Update memory cache
         local owned = GetPlayerWagons(citizenid)
         for _, w in ipairs(owned) do
             if w.plate == activeWagon.plate then
                 w.stored = false
                 break
             end
         end
     end
 
     -- Register as spawned and trigger client spawn
     spawnedWagons[activeWagon.plate] = { src = src, citizenid = citizenid }
     playerActiveWagon[citizenid] = activeWagon.plate
 
     TriggerClientEvent('rex-wagons:spawnWagonNearPlayer', src, activeWagon)
end, false)

-- ====================================================================
-- Handle call wagon failure
-- ====================================================================
RegisterNetEvent('rex-wagons:callWagonFailedServer', function(plate)
     local src = source
     local Player = RSGCore.Functions.GetPlayer(src)
     if not Player then return end

     local citizenid = Player.PlayerData.citizenid
     
     -- Clean up from spawned wagons and active wagon tracking
     if spawnedWagons[plate] then
         spawnedWagons[plate] = nil
     end
     if playerActiveWagon[citizenid] == plate then
         playerActiveWagon[citizenid] = nil
     end

     lib.notify(src, { type = 'error', description = 'Failed to spawn wagon. Please try again.' })
end)

-- ====================================================================
-- Load active wagon status on player load
-- ====================================================================
AddEventHandler('playerJoining', function()
    local src = source
    Wait(100) -- Small delay for player to fully load
    local Player = RSGCore.Functions.GetPlayer(src)
    if Player then
        local citizenid = Player.PlayerData.citizenid
        local activeWagon = GetPlayerActiveWagon(citizenid)
        if activeWagon then
            TriggerClientEvent('rex-wagons:updateActiveWagon', src, activeWagon)
        end
    end
end)
