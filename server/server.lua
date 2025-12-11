local RSGCore = exports['rsg-core']:GetCoreObject()

-- In-memory caches
local playerWagons        = {} -- [citizenid] = { wagon table }
local spawnedWagons      = {} -- [plate] = { src, citizenid, wagonId }
local playerActiveWagon  = {} -- [citizenid] = plate (prevents double spawn)
local playerShopLocation = {} -- [citizenid] = shop location id (which shop they're at)

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

         local shopId = row.storage_shop or 'valentine'
         local shopName = "Unknown Shop"
         for _, shop in ipairs(Config.WagonShopLocations) do
             if shop.id == shopId then
                 shopName = shop.name
                 break
             end
         end

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
            storage_shop = shopId,
            storage_shop_name = shopName,
            is_active   = row.is_active == 1 or row.is_active == true
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
     local shopId = Config.WagonShopLocations[shopLocationIndex]?.id or 'valentine'
     playerShopLocation[citizenid] = shopId
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
      local shopId = playerShopLocation[citizenid] or 'valentine'
      if playerCoords then
          local nearestIdx = GetNearestShop(playerCoords) or 1
          shopId = Config.WagonShopLocations[nearestIdx]?.id or 'valentine'
      end

      -- Insert into DB first (most important!)
      local insertId = MySQL.insert.await([[
          INSERT INTO rex_wagons (citizen_id, wagon_id, model, plate, label, price, storage, slots, description, storage_shop, stored)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
          shopId,
          true
      })

    if not insertId then
        Player.Functions.AddMoney('cash', wagonConfig.price) -- rollback
        lib.notify(src, { type = 'error', description = 'Database error, wagon purchase cancelled' })
        return
    end

    -- Find shop name
    local shopName = "Unknown Shop"
    for _, shop in ipairs(Config.WagonShopLocations) do
        if shop.id == shopId then
            shopName = shop.name
            break
        end
    end

     -- Cache the new wagon in memory
     -- Ensure player exists in cache
     if not playerWagons[citizenid] then
         playerWagons[citizenid] = {}
     end
     
     local newWagon = {
         id              = wagonConfig.id,
         label           = wagonConfig.label,
         model           = wagonConfig.model,
         plate           = plate,
         price           = wagonConfig.price,
         storage         = wagonConfig.storage,
         slots           = wagonConfig.slots,
         description     = wagonConfig.description or '',
         stored          = true,
         storage_shop    = shopId,
         storage_shop_name = shopName,
         is_active       = false
     }
     table.insert(playerWagons[citizenid], newWagon)

    -- Notify player of successful purchase
    lib.notify(src, { type = 'success', description = ('Purchased %s for $%d'):format(wagonConfig.label, wagonConfig.price) })
    TriggerClientEvent('rex-wagons:wagonPurchased', src, newWagon)

    -- Update UI
    TriggerClientEvent('rex-wagons:setShopData', src,
        Config.AvailableWagons,
        GetPlayerWagons(citizenid),
        Player.PlayerData.money.cash or 0
    )
end)

-- ====================================================================
-- Get available wagons
-- ====================================================================
RegisterNetEvent('rex-wagons:getAvailableWagons', function()
     local src = source
     TriggerClientEvent('rex-wagons:setAvailableWagons', src, Config.AvailableWagons)
end)

-- ====================================================================
-- Transfer wagon to different shop
-- ====================================================================
RegisterNetEvent('rex-wagons:transferWagon', function(plate, targetShopIndex)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local owned = GetPlayerWagons(citizenid)

    -- Find the wagon
    local wagonData = nil
    for _, w in ipairs(owned) do
        if tostring(w.plate) == tostring(plate) then
            wagonData = w
            break
        end
    end

    if not wagonData then
        lib.notify(src, { type = 'error', description = 'You do not own this wagon' })
        return
    end

    local targetShopId = Config.WagonShopLocations[targetShopIndex]?.id or 'valentine'
    local targetShop = Config.WagonShopLocations[targetShopIndex]

    -- Can't transfer to same shop
    if wagonData.storage_shop == targetShopId then
        lib.notify(src, { type = 'error', description = 'Wagon is already stored at this shop' })
        return
    end

     -- Calculate transfer cost based on non-linear distance formula: base + (distance ^ exponent) * multiplier
     local currentShopId = wagonData.storage_shop or 'valentine'
     local currentShop = nil
     for _, shop in ipairs(Config.WagonShopLocations) do
         if shop.id == currentShopId then
             currentShop = shop
             break
         end
     end

     if not currentShop then
         lib.notify(src, { type = 'error', description = 'Current shop location not found' })
         return
     end

      local basePrice = Config.WagonShop?.TransferBasePrice or 100
      local exponent = Config.WagonShop?.TransferDistanceExponent or 1.3
      local multiplier = Config.WagonShop?.TransferDistanceMultiplier or 0.01

     local distance = #(currentShop.coords - targetShop.coords)
     local transferCost = math.ceil(basePrice + (distance ^ exponent) * multiplier)

     -- Money check
     if Player.PlayerData.money.cash < transferCost then
         lib.notify(src, { type = 'error', description = ('Transfer costs $%d, you only have $%d'):format(transferCost, Player.PlayerData.money.cash) })
         return
     end

     Player.Functions.RemoveMoney('cash', transferCost)

     -- Update database
     MySQL.query.await('UPDATE rex_wagons SET storage_shop = ? WHERE plate = ?', { targetShopId, wagonData.plate })

     -- Update memory cache
     wagonData.storage_shop = targetShopId
     wagonData.storage_shop_name = targetShop.name

     lib.notify(src, { type = 'success', description = ('Wagon transferred to %s for $%d'):format(targetShop.name, transferCost) })

     -- Notify client of successful transfer so it refreshes the UI
     TriggerClientEvent('rex-wagons:transferSuccess', src)

     -- Reload shop data
     TriggerClientEvent('rex-wagons:setShopData', src,
         Config.AvailableWagons,
         GetPlayerWagons(citizenid),
         Player.PlayerData.money.cash or 0
     )
end)

-- ====================================================================
-- Get transfer options
-- ====================================================================
RegisterNetEvent('rex-wagons:getTransferData', function(plate)
      local src = source
      local Player = RSGCore.Functions.GetPlayer(src)
      if not Player then return end

      local citizenid = Player.PlayerData.citizenid
      local owned = GetPlayerWagons(citizenid)

      local wagonData = nil
      for _, w in ipairs(owned) do
          if tostring(w.plate) == tostring(plate) then
              wagonData = w
              break
          end
      end
      if not wagonData then return end

     local currentShopId = wagonData.storage_shop or 'valentine'
     local currentShop = nil
     for _, shop in ipairs(Config.WagonShopLocations) do
         if shop.id == currentShopId then
             currentShop = shop
             break
         end
     end

      local basePrice = Config.WagonShop?.TransferBasePrice or 100
      local exponent = Config.WagonShop?.TransferDistanceExponent or 1.3
      local multiplier = Config.WagonShop?.TransferDistanceMultiplier or 0.01

       local transferData = {}
       for shopIndex, shop in ipairs(Config.WagonShopLocations) do
           -- Only show shops that are different from the current shop
           if shop.id ~= currentShopId then
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

      TriggerClientEvent('rex-wagons:showTransferOptions', src, transferData)
 end)

-- ====================================================================
-- Set active wagon
-- ====================================================================
RegisterNetEvent('rex-wagons:setActiveWagon', function(plate, shopIndex)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local owned = GetPlayerWagons(citizenid)

    -- Validate wagon belongs to player
    local wagonData = nil
    for _, w in ipairs(owned) do
        if tostring(w.plate) == tostring(plate) then
            wagonData = w
            break
        end
    end

    if not wagonData then
        lib.notify(src, { type = 'error', description = 'You do not own this wagon' })
        return
    end

    -- Get fresh data from database to ensure we have the correct storage_shop
    local dbResult = MySQL.query.await('SELECT storage_shop, label FROM rex_wagons WHERE plate = ?', { plate })
    if dbResult and dbResult[1] then
        wagonData.storage_shop = dbResult[1].storage_shop
        wagonData.label = dbResult[1].label
    end

    -- Validate wagon is stored at the current shop
    local currentShopId = Config.WagonShopLocations[shopIndex]?.id or 'valentine'
    local wagonShopId = wagonData.storage_shop or 'valentine'
    
     if wagonShopId ~= currentShopId then
         local shopName = 'Unknown Shop'
         for _, shop in ipairs(Config.WagonShopLocations) do
             if shop.id == wagonShopId then
                 shopName = shop.name
                 break
             end
         end
         lib.notify(src, { type = 'error', description = ('This wagon is stored at %s'):format(shopName) })
         return
     end

     -- Clear previous active wagon
     MySQL.query.await('UPDATE rex_wagons SET is_active = FALSE WHERE citizen_id = ?', { citizenid })

     -- Set new active wagon
     MySQL.query.await('UPDATE rex_wagons SET is_active = TRUE WHERE plate = ?', { wagonData.plate })

      -- Reload wagons from database to ensure cache is up-to-date
      local dbResult = MySQL.query.await('SELECT * FROM rex_wagons WHERE citizen_id = ?', { citizenid })
      local reloadedWagons = {}
      if dbResult then
          for _, row in ipairs(dbResult) do
              local shopId = row.storage_shop or 'valentine'
              local shopName = "Unknown Shop"
              for _, shop in ipairs(Config.WagonShopLocations) do
                  if shop.id == shopId then
                      shopName = shop.name
                      break
                  end
              end
              table.insert(reloadedWagons, {
                  id          = row.wagon_id,
                  label       = row.label,
                  model       = row.model,
                  plate       = row.plate,
                  price       = row.price,
                  storage     = row.storage,
                  slots       = row.slots,
                  description = row.description or '',
                  stored      = row.stored == 1 or row.stored == true,
                  storage_shop = shopId,
                  storage_shop_name = shopName,
                  is_active   = row.is_active == 1 or row.is_active == true
              })
          end
      end
      playerWagons[citizenid] = reloadedWagons

      lib.notify(src, { type = 'success', description = ('Set %s as your active wagon'):format(wagonData.label) })
      TriggerClientEvent('rex-wagons:activeWagonSet', src, wagonData)
      TriggerEvent('ox_lib:notify', { type = 'success', title = 'Active Wagon Updated', description = wagonData.label })
      
      -- Send UI update with refreshed shop data
      TriggerClientEvent('rex-wagons:setShopData', src,
          Config.AvailableWagons,
          reloadedWagons,
          Player.PlayerData.money.cash or 0
      )
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
         local shopId = row.storage_shop or 'valentine'
         local shopName = "Unknown Shop"
         for _, shop in ipairs(Config.WagonShopLocations) do
             if shop.id == shopId then
                 shopName = shop.name
                 break
             end
         end
         
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
             storage_shop = shopId,
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
-- Spawn Owned Wagon
-- ====================================================================
RegisterNetEvent('rex-wagons:spawnWagon', function(plate, playerCoords, shopIndex)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local wagonData = nil
    
    -- Find the wagon in player's owned wagons
    local owned = GetPlayerWagons(citizenid)
    for _, w in ipairs(owned) do
        if w.plate == plate then
            wagonData = w
            break
        end
    end

    if not wagonData then
        lib.notify(src, { type = 'error', description = 'Wagon not found' })
        return
    end

    -- Validate wagon is stored at the current shop
    local currentShopId = Config.WagonShopLocations[shopIndex]?.id or 'valentine'
    local wagonShopId = wagonData.storage_shop or 'valentine'
    
    if wagonShopId ~= currentShopId then
        local shopName = 'Unknown Shop'
        for _, shop in ipairs(Config.WagonShopLocations) do
            if shop.id == wagonShopId then
                shopName = shop.name
                break
            end
        end
        lib.notify(src, { type = 'error', description = ('You must go to %s to spawn this wagon'):format(shopName) })
        return
    end

    -- Check if wagon is already spawned
    if spawnedWagons[plate] then
        lib.notify(src, { type = 'error', description = 'Your wagon is already in the world' })
        return
    end

    -- Prevent double spawn
    if playerActiveWagon[citizenid] then
        lib.notify(src, { type = 'error', description = 'You already have a wagon spawned. Return it first.' })
        return
    end

    -- If wagon is stored, unstore it first
    if wagonData.stored then
        MySQL.query.await('UPDATE rex_wagons SET stored = FALSE WHERE plate = ?', { plate })
        wagonData.stored = false
    end

    -- Register as spawned and trigger client spawn
    spawnedWagons[plate] = { src = src, citizenid = citizenid }
    playerActiveWagon[citizenid] = plate

     -- Find the shop index for the wagon's storage location
     local shopIndexForSpawn = shopIndex
     TriggerClientEvent('rex-wagons:doSpawnWagon', src, wagonData, shopIndexForSpawn)
end)

-- ====================================================================
-- Unstore Wagon
-- ====================================================================
RegisterNetEvent('rex-wagons:unstoreWagon', function(plate, playerCoords)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local wagonData = nil
    
    -- Find the wagon in player's owned wagons
    local owned = GetPlayerWagons(citizenid)
    for _, w in ipairs(owned) do
        if w.plate == plate then
            wagonData = w
            break
        end
    end

    if not wagonData then
        lib.notify(src, { type = 'error', description = 'Wagon not found' })
        return
    end

    if not wagonData.stored then
        lib.notify(src, { type = 'error', description = 'Wagon is not stored' })
        return
    end

    -- Unstore the wagon
    MySQL.query.await('UPDATE rex_wagons SET stored = FALSE WHERE plate = ?', { plate })
    wagonData.stored = false

    lib.notify(src, { type = 'success', description = 'Wagon unstored successfully' })
    TriggerClientEvent('rex-wagons:wagonUnstoredNotification', src, { plate = plate })
end)

-- ====================================================================
-- Delete/Sell Wagon
-- ====================================================================
RegisterNetEvent('rex-wagons:deleteWagon', function(plate)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local wagonData = nil
    
    -- Find the wagon in player's owned wagons
    local owned = GetPlayerWagons(citizenid)
    for _, w in ipairs(owned) do
        if w.plate == plate then
            wagonData = w
            break
        end
    end

    if not wagonData then
        lib.notify(src, { type = 'error', description = 'Wagon not found' })
        return
    end

    -- Calculate sell price (50% of purchase price)
    local sellPrice = math.ceil(wagonData.price * 0.50)

    -- Delete from database
    MySQL.query.await('DELETE FROM rex_wagons WHERE plate = ?', { plate })
    -- Delete inventory from database
    MySQL.query.await('DELETE FROM inventories WHERE identifier = ?', { 'wagon_'..plate })

    -- Remove from spawned wagons if applicable
    if spawnedWagons[plate] then
        spawnedWagons[plate] = nil
    end

     -- Give player the money
     Player.Functions.AddMoney('cash', sellPrice)

     lib.notify(src, { type = 'success', description = ('Wagon sold for $%d'):format(sellPrice) })
     TriggerClientEvent('rex-wagons:wagonDeleted', src, { plate = plate })

     -- Remove wagon from cache without clearing all wagons
     local owned = GetPlayerWagons(citizenid)
     for i = #owned, 1, -1 do
         if owned[i].plate == plate then
             table.remove(owned, i)
             break
         end
     end
end)

-- ====================================================================
-- Store Wagon
-- ====================================================================
RegisterNetEvent('rex-wagons:storeWagon', function(plate)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local wagonData = nil
    
    -- Check if wagon is spawned
    if not spawnedWagons[plate] then
        lib.notify(src, { type = 'error', description = 'Wagon is not spawned' })
        return
    end

    -- Find the wagon in player's owned wagons
    local owned = GetPlayerWagons(citizenid)
    for _, w in ipairs(owned) do
        if w.plate == plate then
            wagonData = w
            break
        end
    end

    if not wagonData then
        lib.notify(src, { type = 'error', description = 'Wagon not found' })
        return
    end

    -- Store the wagon
    MySQL.query.await('UPDATE rex_wagons SET stored = TRUE WHERE plate = ?', { plate })
    wagonData.stored = true

    -- Clean up spawned wagon tracking
    spawnedWagons[plate] = nil
    playerActiveWagon[citizenid] = nil

    -- Tell client to delete the wagon entity
    TriggerClientEvent('rex-wagons:wagonStored', src, plate)

    lib.notify(src, { type = 'success', description = 'Wagon stored successfully' })
end)

-- ====================================================================
-- Wagon Storage
-- ====================================================================
RegisterNetEvent('rex-wagons:server:openStorage', function(wagonData)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    local data = { label = 'Wagon Storage', maxweight = wagonData.storage, slots = wagonData.slots }
    exports['rsg-inventory']:OpenInventory(src, 'wagon_'..wagonData.plate, data)
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
