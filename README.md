# REX-Wagons Documentation

## Overview

**rex-wagons** is a comprehensive RSG Framework RedM resource that implements a complete wagon ownership, purchasing, and management system. Players can buy, store, retrieve, and manage wagons across multiple shop locations with a full UI interface.

**Framework:** RSG Framework  
**Dependencies:** RSG-Core, ox_lib, MySQL-async, ox_target  
**Language:** Lua

---

## Features

- **Wagon Purchasing**: Buy wagons from configured shops
- **Multi-Shop Support**: Transfer wagons between different shop locations with dynamic pricing
- **Active Wagon System**: Set a primary wagon to call with the `/callwagon` command
- **Wagon Storage**: Store wagons at shops when not in use
- **Inventory Storage**: Access wagon storage from UI
- **Blip System**: Shop locations appear on the map with custom blips
- **Server Validation**: All purchases and transactions validated server-side
- **Database Persistence**: All wagon data stored in MySQL with proper caching

---

## Installation

### 1. Database Setup
Run the SQL migration file to create the required table:

```sql
-- Located in: installation/database.sql
```

This creates the `rex_wagons` table with columns for:
- `citizen_id` (player identifier)
- `wagon_id` (config reference)
- `model`, `plate`, `label`, `price`, `storage`, `slots`
- `description`, `storage_shop`, `stored`, `is_active`

### 2. Dependency Installation
Ensure you have these resources running:
- `rsg-core`
- `ox_lib`
- `ox_target`
- MySQL-async compatible database

### 3. Resource Placement
Place the `rex-wagons` folder in your resources directory and add to `server.cfg`:

```
ensure rex-wagons
```

### 4. Configuration
Edit `/shared/config.lua` to configure:
- Available wagon models and pricing
- Shop locations and spawn points
- Transfer pricing formulas
- Max wagons per player

---

## Configuration

### Available Wagons
Define purchasable wagons in `Config.AvailableWagons`:

```lua
Config.AvailableWagons = {
    {
        id = 'wagon1',
        label = 'Supply Wagon',
        model = 'supplier_cart',
        price = 500,
        storage = true,
        slots = 50,
        description = 'A sturdy supply wagon'
    }
}
```

### Shop Locations
Configure shops in `Config.WagonShopLocations`:

```lua
Config.WagonShopLocations = {
    {
        id = 'valentine',
        name = 'Valentine Wagon Shop',
        coords = vector3(x, y, z),
        spawnpoint = vector4(x, y, z, heading),
        blipsprite = 'BLIP_WAGON',
        blipscale = 0.8,
        blipname = 'Wagon Shop',
        showblip = true
    }
}
```

### Shop Settings
Configure in `Config.WagonShop`:

```lua
Config.WagonShop = {
    MaxWagons = 10,
    TransferBasePrice = 100,
    TransferDistanceExponent = 1.3,
    TransferDistanceMultiplier = 0.01
}
```

---

## Database Schema

### rex_wagons Table

| Column | Type | Description |
|--------|------|-------------|
| `id` | INT | Auto-increment primary key |
| `citizen_id` | VARCHAR(255) | Player's citizen ID |
| `wagon_id` | VARCHAR(50) | Wagon config ID |
| `model` | VARCHAR(50) | Vehicle model hash |
| `plate` | VARCHAR(20) | Unique wagon plate (W######) |
| `label` | VARCHAR(255) | Wagon display name |
| `price` | INT | Purchase price |
| `storage` | BOOLEAN | Whether wagon has storage |
| `slots` | INT | Storage slot count |
| `description` | TEXT | Wagon description |
| `storage_shop` | VARCHAR(50) | Shop ID where stored |
| `stored` | BOOLEAN | Whether currently stored |
| `is_active` | BOOLEAN | Whether this is active wagon |

---

## Server Events

### Registration Events
Events called by client and handled on server.

#### `rex-wagons:getShopData`
**Purpose:** Retrieve available and owned wagons for a player  
**Called by:** Client  
**Returns:** Sends `rex-wagons:setShopData` with wagons and cash

#### `rex-wagons:purchaseWagon`
**Purpose:** Purchase a wagon  
**Parameters:**
- `wagonId` (string) - Wagon config ID
- `playerCoords` (vector3) - Player position

**Validation:**
- Player must be a valid RSG Core player
- Wagon config must exist
- Player must own less than max wagons
- Player must have sufficient cash
- Generates unique plate starting with 'W'

**Side Effects:**
- Deducts money from player
- Inserts wagon into database
- Caches wagon in memory
- Stores at nearest shop to player's current location

#### `rex-wagons:setActiveWagon`
**Purpose:** Set a wagon as the active (call-able) wagon  
**Parameters:**
- `plate` (string) - Wagon plate
- `shopIndex` (int) - Shop location index

**Validation:**
- Wagon must be owned by player
- Wagon must be stored at current shop location
- Clears previous active wagon

#### `rex-wagons:spawnWagon`
**Purpose:** Spawn a wagon at a shop location  
**Parameters:**
- `plate` (string) - Wagon plate
- `playerCoords` (vector3) - Player position
- `shopIndex` (int) - Shop index

**Validation:**
- Wagon must exist and be owned
- Wagon must be stored at shop
- Cannot spawn if already spawned elsewhere
- Cannot spawn if player has active wagon

#### `rex-wagons:transferWagon`
**Purpose:** Move wagon to different shop (for a fee)  
**Parameters:**
- `plate` (string) - Wagon plate
- `targetShopIndex` (int) - Destination shop

**Pricing:** `cost = basePrice + (distance ^ exponent) * multiplier`

#### `rex-wagons:getTransferData`
**Purpose:** Get available shops and transfer costs for a wagon  
**Parameters:**
- `plate` (string) - Wagon plate

**Returns:** Sends `rex-wagons:showTransferOptions` with shop data

#### `rex-wagons:storeWagon`
**Purpose:** Store an active wagon at its shop  
**Parameters:**
- `plate` (string) - Wagon plate

**Validation:**
- Wagon must be spawned
- Removes from spawned tracking

#### `rex-wagons:deleteWagon` / Sell Wagon
**Purpose:** Sell a wagon to the shop  
**Parameters:**
- `plate` (string) - Wagon plate

**Reward:** 50% of purchase price (rounded up)

#### `rex-wagons:unstoreWagon`
**Purpose:** Mark wagon as unstored (inventory access)  
**Parameters:**
- `plate` (string) - Wagon plate

#### `rex-wagons:callWagonFailedServer`
**Purpose:** Notify server that wagon spawn failed  
**Called by:** Client
**Effect:** Cleans up server-side tracking

---

## Client Events

### Receiving Events
Events sent to client from server.

#### `rex-wagons:setShopData`
**Sent:** After player requests shop data  
**Parameters:**
- `availableWagons` (table) - Available wagons to purchase
- `playerWagons` (table) - Player's owned wagons
- `cash` (int) - Player's cash

#### `rex-wagons:doSpawnWagon`
**Sent:** When server approves wagon spawn  
**Parameters:**
- `wagonData` (table) - Wagon info
- `shopLocationIndex` (int) - Shop index

**Client Behavior:**
- Loads model asynchronously
- Validates spawn point is clear
- Creates vehicle entity
- Adds ox_target interactions (storage, store)
- Creates blip labeled "My Wagon"

#### `rex-wagons:spawnWagonNearPlayer`
**Sent:** For `/callwagon` command  
**Parameters:**
- `wagonData` (table) - Wagon info

**Client Behavior:**
- Finds safe spawn point around player (8 directions)
- Falls back to front of player
- Handles model loading with timeout
- Creates interactive wagon entity

#### `rex-wagons:wagonStored`
**Sent:** When wagon is successfully stored  
**Parameters:**
- `plate` (string) - Wagon plate

**Client Behavior:**
- Deletes wagon entity
- Updates UI
- Notifies player

#### `rex-wagons:wagonDeleted`
**Sent:** When wagon is sold  
**Parameters:**
- `plate` (string) - Wagon plate

#### `rex-wagons:activeWagonSet`
**Sent:** When active wagon is set  
**Parameters:**
- `wagonData` (table) - Wagon info

#### `rex-wagons:transferSuccess`
**Sent:** When wagon transfer completes  
**Effect:** Refreshes UI and shop data

#### `rex-wagons:updateActiveWagon`
**Sent:** On player join with active wagon info  
**Sent:** On player load to restore active wagon state

#### `rex-wagons:showTransferOptions`
**Sent:** When transfer data is requested  
**Parameters:**
- `transferData` (table) - Array of shop options with costs

---

## Console Commands

### `/callwagon`
**Usage:** `/callwagon`  
**Purpose:** Spawn active wagon near player  
**Requirements:**
- Player must have active wagon set
- Wagon cannot already be spawned
- Player cannot have another wagon spawned

**Behavior:**
- Checks memory cache first, loads from DB if needed
- Unstores wagon if marked as stored
- Spawns within configurable radius around player
- Finds clear spawn point or fails gracefully

**Cooldown:** Implicit (one wagon per player at a time)

---

## Memory Caches

The server maintains three in-memory caches for performance:

### `playerWagons`
```lua
playerWagons[citizenid] = {
    { id, label, model, plate, price, storage, slots, 
      description, stored, storage_shop, storage_shop_name, is_active }
}
```
- Loaded on resource start from database
- Updated on purchase
- Reloaded after active wagon set
- Used for all wagon lookups

### `spawnedWagons`
```lua
spawnedWagons[plate] = { src, citizenid }
```
- Tracks which wagons are currently spawned
- Prevents double spawning
- Cleared on wagon store/delete

### `playerActiveWagon`
```lua
playerActiveWagon[citizenid] = plate
```
- Maps player to their active (spawned) wagon
- Prevents multiple active wagons
- Cleared on wagon store

---

## Workflow Examples

### Purchasing a Wagon
1. Player opens shop UI
2. Client requests shop data via `rex-wagons:getShopData`
3. Server sends available and owned wagons
4. Player selects wagon and clicks purchase
5. Client sends `rex-wagons:purchaseWagon` with player coords
6. Server validates:
   - Wagon config exists
   - Player owns < max wagons
   - Player has enough cash
7. Server deducts cash, inserts into DB, caches in memory
8. Server sends `rex-wagons:wagonPurchased` notification
9. UI updates to show new wagon in "My Wagons" tab

### Calling a Wagon
1. Player types `/callwagon`
2. Server checks if active wagon exists (cache + DB)
3. Server marks wagon as unstored
4. Server sends `rex-wagons:spawnWagonNearPlayer`
5. Client finds safe spawn point around player
6. Client loads model and creates entity
7. Client creates blip and ox_target interactions
8. Player can access storage or store wagon

### Transferring a Wagon
1. Player selects wagon and clicks transfer
2. Client requests transfer data via `rex-wagons:getTransferData`
3. Server calculates costs for all shops
4. Server sends `rex-wagons:showTransferOptions`
5. Player selects destination shop
6. Client sends `rex-wagons:transferWagon` with target shop
7. Server validates ownership and location
8. Server calculates transfer cost
9. Server deducts cost and updates `storage_shop`
10. Server sends `rex-wagons:transferSuccess`
11. UI refreshes to show new storage location

---

## Error Handling

### Server-Side Validation
- All client input is validated
- Database errors trigger automatic refunds (e.g., purchase fail)
- Player validity checked before all operations
- Wagon ownership verified for all interactions

### Client-Side Failures
- Model loading has 10-second timeout
- Spawn point validation prevents blocking
- Failed spawns trigger server cleanup via `rex-wagons:callWagonFailedServer`
- Entity existence checks prevent crashes

### User Notifications
Uses `lib.notify` for:
- Success messages (green)
- Error messages (red)
- Warnings (yellow)

Example responses:
```lua
lib.notify({ type = 'success', description = 'Wagon purchased!' })
lib.notify({ type = 'error', description = 'Not enough cash' })
```

---

## NUI Callbacks

### From UI to Client

#### `closeShop`
Closes the wagon shop UI

#### `purchaseWagon`
Triggers purchase with selected wagon

#### `spawnWagon`
Spawns selected owned wagon at current shop

#### `unstoreWagon`
Marks wagon as unstored (for inventory)

#### `deleteWagonConfirm`
Shows confirmation dialog and sells wagon

#### `setActiveWagon`
Sets selected wagon as active

#### `getTransferData`
Requests transfer options for wagon

#### `transferWagon`
Transfers wagon to selected shop

#### `notifySuccess` / `notifyError`
Display notifications to player

---

## Localization

The resource uses ox_lib localization via `lib.locale()`.

Locale keys used:
- `sell_header` - Sell wagon dialog title
- `sell_confirm` - Sell wagon confirmation message

Edit `/locales/en.json` to customize messages.

---

## Advanced Concepts

### Distance-Based Transfer Pricing
Transfer cost uses a non-linear formula:
```
cost = basePrice + (distance ^ exponent) * multiplier
```

Default values:
- `basePrice = 100`
- `exponent = 1.3` (increases cost non-linearly)
- `multiplier = 0.01`

Example: 500 unit distance = 100 + (500^1.3) * 0.01 = ~$1,845

### Spawn Point Finding Algorithm
When calling wagon:
1. Tries 8 directions around player (360° / 8)
2. Uses ground check at each point
3. Validates no peds/objects within radius
4. Falls back to front of player if no clear point
5. Fails gracefully with notification

### Safe Mode Mechanics
- `isSpawningWagon` flag prevents rapid spam
- 2-second timeout after spawn attempt
- Double-spawn protection via `playerActiveWagon`
- NUI focus lock prevents command spam

---

## Troubleshooting

### Wagons Not Appearing in Shop
- Check database connection
- Verify MySQL resource is running
- Check citizen_id format in database
- Verify RSG-Core player load completes

### Spawn Failures
- Ensure spawn points are accessible (not inside buildings)
- Check ground Z coordinate accuracy
- Verify wagon model exists and is registered
- Check for entity count limits

### Transfer Costs Not Updating
- Verify shop coords in config
- Check TransferDistanceExponent and Multiplier
- Ensure shops have unique IDs

### UI Not Opening
- Verify ox_lib is running
- Check browser console for JS errors
- Ensure NUI file paths are correct
- Verify SetNuiFocus calls

---

## Performance Notes

- All database queries use async/await (non-blocking)
- Caches reduce DB hits significantly
- Wagon loading done once per resource start
- Model loading uses RequestModel (async)
- Blips created once on client spawn
- Target interactions added per-entity

---

## Compatibility

- **RSG Framework**: Required
- **RedM Server**: 1.0+
- **MySQL**: 5.7+ (async library required)
- **ox_lib**: Required for UI/notifications
- **ox_target**: Required for wagon interactions

---

## Support & Issues

For bug reports or feature requests, refer to the resource repository documentation.

Key maintainers: REX Development Team

---

**Last Updated:** 2024  
**Version:** 1.0  
**Framework:** RSG Standalone
