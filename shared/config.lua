Config = {}

---------------------------------
-- general settings
---------------------------------
Config.CheckSpawnDistance = 3.0 -- check the spawn area for ped & objects

---------------------------------
-- wagon shop settings
---------------------------------
Config.WagonShop = {
    MaxWagons = 10, -- Max wagons a player can own
    -- Non-linear transfer pricing: cost = base + (distance ^ exponent) * multiplier
    TransferBasePrice = 100, -- Base price for any wagon transfer
    TransferDistanceExponent = 1.3, -- Exponent for non-linear scaling (1.3 = steeper curve)
    TransferDistanceMultiplier = 0.01, -- Multiplier for distance calculation
    SellPercentage = 0.50, -- Percentage of original price when selling (0.50 = 50%)
}

---------------------------------
-- call wagon settings
---------------------------------
Config.CallWagon = {
    SpawnDistanceFromPlayer = 5, -- Distance to spawn wagon from player (meters)
    SpawnSearchRadius = 5, -- Radius to search for clear spawn space (meters)
}

---------------------------------
-- performance settings
---------------------------------
Config.Performance = {
    -- NPC Management
    NpcDistanceCheck = 3000, -- How often to check NPC distances (ms)
    NpcCoordsUpdate = 2000,  -- How often to update player coords for NPCs (ms)
    NpcSpawnDistance = 20.0, -- Distance to spawn/despawn NPCs
    NpcFadeSpeed = 40,       -- Fade animation speed (ms between steps)
}

---------------------------------
-- wagon categories
---------------------------------
Config.WagonCategories = {
    { id = 'carts',        label = 'Carts',          color = '#8B4513' },
    { id = 'wagons',       label = 'Wagons',         color = '#CD853F' },
    { id = 'stagecoaches', label = 'Stagecoaches',   color = '#DAA520' },
    { id = 'buggies',      label = 'Buggies',        color = '#D2691E' },
    { id = 'industrial',   label = 'Industrial',     color = '#A0522D' },
    { id = 'specialty',    label = 'Specialty',      color = '#8B0000' },
}

---------------------------------
-- available wagons
---------------------------------
Config.AvailableWagons = {
    -- CARTS
    { id = 'wagon_cart05', label = 'General Purpose Cart', model = 'cart05', price = 100, storage = 50000,   slots = 2, category = 'carts', description = 'Versatile cart used for multiple purposes.' },
    { id = 'wagon_cart02', label = 'Merchant\'s Cart',     model = 'cart02', price = 125, storage = 70000,   slots = 3, category = 'carts', description = 'Used by merchants to carry goods and wares.' },
    { id = 'wagon_cart08', label = 'Vendor Cart',          model = 'cart08', price = 150, storage = 90000,   slots = 4, category = 'carts', description = 'Used by traveling vendors for on-the-road sales.' },
    { id = 'wagon_cart01', label = 'Small Wooden Cart',    model = 'cart01', price = 150, storage = 90000,   slots = 4, category = 'carts', description = 'A small wooden cart suitable for light loads.' },
    { id = 'wagon_cart03', label = 'Trade Cart',           model = 'cart03', price = 200, storage = 100000,  slots = 5, category = 'carts', description = 'A sturdy cart for everyday trade and hauling.' },
    { id = 'wagon_cart04', label = 'Farmer\'s Cart',       model = 'cart04', price = 200, storage = 100000,  slots = 5, category = 'carts', description = 'Traditional farmer\'s cart for produce and supplies.' },
    { id = 'wagon_cart07', label = 'Supply Cart',          model = 'cart07', price = 260, storage = 120000,  slots = 6, category = 'carts', description = 'Cart for moving general supplies and equipment.' },
    { id = 'wagon_cart06', label = 'Delivery Cart',        model = 'cart06', price = 300, storage = 150000,  slots = 8, category = 'carts', description = 'Designed for making deliveries between towns.' },

    -- WAGONS
    { id = 'wagon_wagonprison01x',    label = 'Prison Transport Wagon', model = 'wagonprison01x',    price = 1000, storage = 100000, slots = 5,  category = 'wagons', description = 'Reinforced wagon for prisoner transport.' },
    { id = 'wagon_wagonarmoured01x',  label = 'Armored Security Wagon', model = 'wagonarmoured01x',  price = 1200, storage = 200000, slots = 10, category = 'wagons', description = 'Heavily armored for secure cargo transport.' },
    { id = 'wagon_wagoncircus01x',    label = 'Circus Cage Wagon',      model = 'wagoncircus01x',    price = 450,  storage = 200000, slots = 10, category = 'wagons', description = 'Used to transport circus animals in cages.' },
    { id = 'wagon_wagoncircus02x',    label = 'Circus Living Wagon',    model = 'wagoncircus02x',    price = 500,  storage = 200000, slots = 10, category = 'wagons', description = 'Living quarters on wheels for circus performers.' },
    { id = 'wagon_wagon02x',          label = 'Basic Two-Horse Wagon',  model = 'wagon02x',          price = 900,  storage = 400000, slots = 20, category = 'wagons', description = 'A basic two-horse wagon for general freight.' },
    { id = 'wagon_wagon06x',          label = 'Transport Wagon',        model = 'wagon06x',          price = 900,  storage = 400000, slots = 20, category = 'wagons', description = 'Multipurpose wagon for carrying people or goods.' },
    { id = 'wagon_wagondairy01x',     label = 'Milk/Dairy Wagon',       model = 'wagondairy01x',     price = 900,  storage = 400000, slots = 20, category = 'wagons', description = 'Used for carrying milk and dairy goods.' },
    { id = 'wagon_wagondoc01x',       label = 'Traveling Doctor Wagon', model = 'wagondoc01x',       price = 900,  storage = 400000, slots = 20, category = 'wagons', description = 'Equipped for medical supplies and travel.' },
    { id = 'wagon_wagonwork01x',      label = 'Work Wagon',             model = 'wagonwork01x',      price = 1200, storage = 400000, slots = 20, category = 'wagons', description = 'Used for hauling tools and workers\' equipment.' },
    { id = 'wagon_wagontraveller01x', label = 'Gypsy/Traveler Wagon',   model = 'wagontraveller01x', price = 1500, storage = 450000, slots = 25, category = 'wagons', description = 'Stylish traveler wagon with good capacity.' },
    { id = 'wagon_wagon03x',          label = 'Medium Freight Wagon',   model = 'wagon03x',          price = 1900, storage = 650000, slots = 30, category = 'wagons', description = 'Medium-sized freight wagon with good capacity.' },
    { id = 'wagon_wagon04x',          label = 'Large Cargo Wagon',      model = 'wagon04x',          price = 2000, storage = 750000, slots = 45, category = 'wagons', description = 'Large wagon for hauling heavier loads.' },
    { id = 'wagon_wagon05x',          label = 'Heavy Duty Wagon',       model = 'wagon05x',          price = 2500, storage = 850000, slots = 50, category = 'wagons', description = 'Built for long distance and rugged terrain.' },

    -- STAGECOACHES
    { id = 'wagon_stagecoach001x', label = 'Valentine Stagecoach',     model = 'stagecoach001x', price = 700, storage = 200000, slots = 10, category = 'stagecoaches', description = 'Stagecoach servicing the Valentine region.' },
    { id = 'wagon_stagecoach005x', label = 'Strawberry Stagecoach',    model = 'stagecoach005x', price = 700, storage = 200000, slots = 10, category = 'stagecoaches', description = 'Passenger coach operating around Strawberry.' },
    { id = 'wagon_stagecoach002x', label = 'Emerald Ranch Stagecoach', model = 'stagecoach002x', price = 750, storage = 300000, slots = 15, category = 'stagecoaches', description = 'Stagecoach running routes around Emerald Ranch.' },
    { id = 'wagon_stagecoach003x', label = 'Rhodes Stagecoach',        model = 'stagecoach003x', price = 750, storage = 300000, slots = 15, category = 'stagecoaches', description = 'Passenger coach operating out of Rhodes.' },
    { id = 'wagon_stagecoach004x', label = 'Saint Denis Stagecoach',   model = 'stagecoach004x', price = 900, storage = 400000, slots = 20, category = 'stagecoaches', description = 'Luxury coach in the Saint Denis area.' },
    { id = 'wagon_stagecoach006x', label = 'Fancy Stagecoach',         model = 'stagecoach006x', price = 950, storage = 400000, slots = 20, category = 'stagecoaches', description = 'Elegant and ornate stagecoach for VIPs.' },

    -- BUGGIES
    { id = 'wagon_buggy01', label = 'Basic Buggy',     model = 'buggy01', price = 400, storage = 100000, slots = 5, category = 'buggies', description = 'Simple one-horse buggy for personal use.' },
    { id = 'wagon_buggy02', label = 'Fancy Buggy',     model = 'buggy02', price = 600, storage = 100000, slots = 5, category = 'buggies', description = 'Stylish buggy for wealthier riders.' },
    { id = 'wagon_buggy03', label = 'Doctor\'s Buggy', model = 'buggy03', price = 650, storage = 100000, slots = 5, category = 'buggies', description = 'Medical buggy for rural house calls.' },

    -- INDUSTRIAL WAGONS
    { id = 'wagon_oilwagon01x',     label = 'Oil Tank Wagon',    model = 'oilwagon01x',     price = 900, storage = 400000, slots = 20, category = 'industrial', description = 'Carries barrels of crude oil safely.' },
    { id = 'wagon_oilwagon02x',     label = 'Kerosene Wagon',    model = 'oilwagon02x',     price = 900, storage = 400000, slots = 20, category = 'industrial', description = 'Used for refined kerosene transport.' },
    { id = 'wagon_armysupplywagon', label = 'Army Supply Wagon', model = 'armysupplywagon', price = 950, storage = 450000, slots = 25, category = 'industrial', description = 'Military supply wagon for missions and logistics.' },
    { id = 'wagon_logwagon',        label = 'Log Hauler',        model = 'logwagon',        price = 950, storage = 450000, slots = 25, category = 'industrial', description = 'Hauls long logs for sawmills and lumberyards.' },

    -- SPECIALTY WAGONS
    { id = 'wagon_huntercart01', label = 'Legendary Hunting Wagon',  model = 'huntercart01', price = 1200, storage = 450000, slots = 25, category = 'specialty', description = 'Special wagon for hunting and transporting trophies.' },
    { id = 'wagon_utilliwag',    label = 'Utility Wagon',            model = 'utilliwag',    price = 750,  storage = 100000, slots = 5, category = 'specialty', description = 'Reliable wagon for multiple work purposes.' }

}

---------------------------------
-- prompt locations
---------------------------------
Config.WagonShopLocations = {

    {   --valentine
        name = 'Valentine Wagons',
        coords = vector3(-360.72, 782.02, 116.21),
        npcmodel = 's_m_m_valdealer_01',
        npccoords = vec4(-360.72, 782.02, 116.21, 281.40),
        scenario = 'WORLD_HUMAN_CLIPBOARD',
        showblip = true,
        blipscale = 0.2,
        blipsprite = 'blip_ambient_wagon',
        blipname = 'Valentine Wagons',
        spawnpoint = vec4(-355.75, 786.42, 116.12, 250.29),
    },
    {   --saint denis
        name = 'Saint Denis Wagons',
        coords = vector3(2518.84, -1466.61, 46.27),
        npcmodel = 's_m_m_valdealer_01',
        npccoords = vec4(2518.84, -1466.61, 46.27, 181.68),
        scenario = 'WORLD_HUMAN_CLIPBOARD',
        showblip = true,
        blipscale = 0.2,
        blipsprite = 'blip_ambient_wagon',
        blipname = 'Saint Denis Wagons',
        spawnpoint = vec4(2507.51, -1471.01, 46.29, 99.80),
    },

}