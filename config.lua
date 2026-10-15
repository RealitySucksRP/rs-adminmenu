Config = {}

Config.Command = 'rsadmin'
Config.Keybind = 'F7'
Config.ReportCommand = 'report'
Config.Framework = 'qbox' -- auto | qbox | qbcore | esx | standalone

-- Qbox-first: current Qbox recommends ACE permissions.
Config.Ace = {
    open = 'rsadmin.open',
    owner = 'rsadmin.owner',
    moderate = 'rsadmin.moderate',
    players = 'rsadmin.players',
    vehicles = 'rsadmin.vehicles',
    weapons = 'rsadmin.weapons',
    world = 'rsadmin.world',
    developer = 'rsadmin.developer',
    reports = 'rsadmin.reports',
    server = 'rsadmin.server',
    inventory = 'rsadmin.inventory',
    garage = 'rsadmin.garage',
    pranks = 'rsadmin.pranks',
    spectate = 'rsadmin.spectate',
    economy = 'rsadmin.economy',
    staff = 'rsadmin.staff',
    builder = 'rsadmin.builder',
    security = 'rsadmin.security',
    logs = 'rsadmin.logs',
    punishments = 'rsadmin.punishments',
    pathways = 'rsadmin.pathways'
}

Config.FrameworkPermissionFallback = true
Config.ProtectOwnerFromControl = true -- lower staff cannot freeze/kill/bring/spectate/prank owner-level players
Config.DefaultGarage = 'pillboxgarage'
Config.MaxGiveItemAmount = 5000
Config.AdminVehiclePlate = 'RSADMIN'
Config.AdminVehicleDefaults = { 'superd', 'everon3', 'raptor', 'champion', 'zentorno', 'polbuffalo6' }
Config.PrankMaxSeconds = 30
Config.OwnerIdentifiers = {
    -- 'license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
}

Config.Security = {
    windowMs = 4000,
    maxRequests = 50,
    maxString = 512,
    maxRpcDepth = 10,
    maxRpcFields = 2048,
    maxRpcStringBytes = 16384,
    maxRpcTotalBytes = 65536,
    rejectedAuditIntervalMs = 10000,
    maxReports = 1000,
    auditLimit = 700,
    banDefaultMinutes = 0, -- 0 = permanent
    maxEntityDistance = 300.0,
}

Config.PrivateLab = {
    baseBucket = 700000,
    strict = true,
    disablePopulation = true
}

Config.ProtectedResources = {
    ['rs-adminmenu'] = true,
    ['sessionmanager'] = true,
    ['mapmanager'] = true,
    ['spawnmanager'] = true,
}

Config.WeatherTypes = {
    'EXTRASUNNY','CLEAR','CLOUDS','OVERCAST','RAIN','THUNDER','CLEARING','SMOG','FOGGY','XMAS','SNOWLIGHT','BLIZZARD','HALLOWEEN'
}

Config.Weapons = {
    {label='Pistol', name='WEAPON_PISTOL', ammo=250},
    {label='Combat Pistol', name='WEAPON_COMBATPISTOL', ammo=250},
    {label='AP Pistol', name='WEAPON_APPISTOL', ammo=400},
    {label='Heavy Pistol', name='WEAPON_HEAVYPISTOL', ammo=250},
    {label='SMG', name='WEAPON_SMG', ammo=600},
    {label='Micro SMG', name='WEAPON_MICROSMG', ammo=600},
    {label='Assault SMG', name='WEAPON_ASSAULTSMG', ammo=600},
    {label='Carbine Rifle', name='WEAPON_CARBINERIFLE', ammo=900},
    {label='Carbine Rifle Mk II', name='WEAPON_CARBINERIFLE_MK2', ammo=900},
    {label='Assault Rifle', name='WEAPON_ASSAULTRIFLE', ammo=900},
    {label='Special Carbine', name='WEAPON_SPECIALCARBINE', ammo=900},
    {label='Pump Shotgun', name='WEAPON_PUMPSHOTGUN', ammo=250},
    {label='Combat Shotgun', name='WEAPON_COMBATSHOTGUN', ammo=250},
    {label='Heavy Sniper', name='WEAPON_HEAVYSNIPER', ammo=120},
    {label='Heavy Sniper Mk II', name='WEAPON_HEAVYSNIPER_MK2', ammo=120},
    {label='Grenade Launcher', name='WEAPON_GRENADELAUNCHER', ammo=40},
    {label='RPG', name='WEAPON_RPG', ammo=20},
    {label='Railgun', name='WEAPON_RAILGUN', ammo=20},
    {label='Stun Gun', name='WEAPON_STUNGUN', ammo=20},
    {label='Knife', name='WEAPON_KNIFE', ammo=1},
    {label='Bat', name='WEAPON_BAT', ammo=1},
    {label='Parachute', name='GADGET_PARACHUTE', ammo=1},
}

-- Dynamic vehicle mod slots. Counts are read from the actual vehicle, so addon cars work too.
Config.VehicleModSlots = {
    [0]='Spoiler',[1]='Front Bumper',[2]='Rear Bumper',[3]='Side Skirt',[4]='Exhaust',[5]='Frame',
    [6]='Grille',[7]='Hood',[8]='Left Fender',[9]='Right Fender',[10]='Roof',[11]='Engine',
    [12]='Brakes',[13]='Transmission',[14]='Horns',[15]='Suspension',[16]='Armor',[23]='Front Wheels',
    [24]='Rear Wheels',[25]='Plate Holder',[26]='Vanity Plates',[27]='Trim Design',[28]='Ornaments',
    [29]='Dashboard',[30]='Dials',[31]='Door Speakers',[32]='Seats',[33]='Steering Wheel',[34]='Shifter',
    [35]='Plaques',[36]='Speakers',[37]='Trunk',[38]='Hydraulics',[39]='Engine Block',[40]='Air Filter',
    [41]='Struts',[42]='Arch Cover',[43]='Aerials',[44]='Trim',[45]='Tank',[46]='Windows',[48]='Livery',[49]='Lightbar'
}

Config.WheelTypes = {
    [0]='Sport',[1]='Muscle',[2]='Lowrider',[3]='SUV',[4]='Offroad',[5]='Tuner',[6]='Bike',
    [7]='High End',[8]="Benny's Original",[9]="Benny's Bespoke",[10]='Open Wheel',[11]='Street',[12]='Track'
}


-- v0.7 integrated administration ------------------------------------------------
Config.RpcTimeoutMs = 12000
Config.Language = 'en'
Config.Languages = { en='English', es='Español', pt='Português', fr='Français', de='Deutsch' }

Config.Jail = {
    enabled = true,
    defaultMinutes = 10,
    maxMinutes = 1440,
    cells = {
        {x=459.61,y=-997.89,z=24.91,w=90.0},
        {x=459.58,y=-1001.28,z=24.91,w=90.0},
        {x=460.03,y=-994.53,z=24.91,w=90.0},
    },
    release = {x=426.00,y=-980.45,z=30.70,w=90.0},
    leashRadius = 35.0,
    stripInventory = false,
}

Config.Economy = {
    accounts = { cash=true, bank=true, crypto=true },
    maxAdminAdjustment = 5000000,
    maxPlayerTransfer = 500000,
    dailyPlayerTransferLimit = 1500000,
    highValueThreshold = 100000,
    extremeValueThreshold = 500000,
    requireReasonAbove = 100000,
    webhookAbove = 100000,
    maxTransactions = 2000,
}

Config.Stats = {
    updateSeconds = 60,
    maxSessionHistoryPerPlayer = 90,
    maxActivityRows = 2500,
}

Config.StaffChat = { command='achat', maxHistory=100, maxMessage=500 }
Config.StaffRoles = {
    owner = { label='Owner', rank=100, color='#ff3f8f', position='Server Owner', wildcard=true },
    admin = { label='Admin', rank=80, color='#268cff', position='Administrator', permissions={ 'open','moderate','players','vehicles','weapons','world','developer','reports','server','inventory','garage','pranks','spectate','economy','staff','builder','security','logs','punishments','pathways' } },
    moderator = { label='Moderator', rank=50, color='#20d4e8', position='Moderator', permissions={ 'open','moderate','players','reports','spectate','pranks','punishments','logs' } },
    trial = { label='Trial Moderator', rank=20, color='#44d98a', position='Trial Moderator', permissions={ 'open','players','reports','spectate' } },
}

Config.Widgets = {
    default = { 'onlinePlayers','onlineStaff','openReports','serverEconomy','highValueTransfers','recentActions','worldStatus','longestSessions' },
    available = { 'onlinePlayers','onlineStaff','openReports','serverEconomy','highValueTransfers','recentActions','worldStatus','longestSessions','richestPlayers','vehicleCount','activeBans','activeJails','onDutyStaff','sessionStats','recentKicks','activityTrend','activityHeatmap' }
}

Config.VehicleImages = {
    cfxBase = 'https://docs.fivem.net/vehicles/',
    localBase = 'assets/vehicles/',
    fallback = 'assets/concepts/assets-library.png',
}
Config.ItemImages = { localBase='assets/items/', fallback='assets/concepts/assets-library.png' }

Config.VehicleCleanup = {
    maxRadius=500.0,
    ownerOnlyGlobal=true,
    allowScheduling=true,
    maxScheduledMinutes=120,
    warningSeconds={300,60,30,10},
}

Config.Builder = {
    maxPersistent = 500,
    maxDistanceFromStaff = 500.0,
    propAlpha = 255,
    pedAlpha = 255,
}

Config.Pranks = Config.Pranks or {}
Config.Pranks.Animations = {
    {key='dance1',label='Nightclub Dance',dict='anim@amb@nightclub@mini@dance@dance_solo@male@var_a@',clip='high_center',flag=1,duration=10000},
    {key='dance2',label='Dance Loop',dict='rcmnigel1bnmt_1b',clip='dance_loop_tyler',flag=1,duration=10000},
    {key='thumbsup',label='Thumbs Up',dict='anim@mp_player_intcelebrationmale@thumbs_up',clip='thumbs_up',flag=48,duration=5000},
    {key='salute',label='Salute',dict='anim@mp_player_intcelebrationmale@salute',clip='salute',flag=48,duration=5000},
    {key='facepalm',label='Face Palm',dict='anim@mp_player_intcelebrationmale@face_palm',clip='face_palm',flag=48,duration=5000},
    {key='jazzhands',label='Jazz Hands',dict='anim@mp_player_intcelebrationmale@jazz_hands',clip='jazz_hands',flag=48,duration=6000},
    {key='airguitar',label='Air Guitar',dict='anim@mp_player_intcelebrationmale@air_guitar',clip='air_guitar',flag=48,duration=7000},
    {key='slowclap',label='Slow Clap',dict='anim@mp_player_intcelebrationmale@slow_clap',clip='slow_clap',flag=48,duration=7000},
    {key='crybaby',label='Cry Baby',dict='anim@mp_player_intcelebrationmale@cry_baby',clip='cry_baby',flag=48,duration=6000},
    {key='mindblown',label='Mind Blown',dict='anim@mp_player_intcelebrationmale@mind_blown',clip='mind_blown',flag=48,duration=6000},
    {key='peace',label='Peace',dict='anim@mp_player_intcelebrationmale@peace',clip='peace',flag=48,duration=5000},
    {key='fingerkiss',label='Finger Kiss',dict='anim@mp_player_intcelebrationmale@finger_kiss',clip='finger_kiss',flag=48,duration=5000},
    {key='cheer',label='Cheer',dict='amb@world_human_cheering@male_a',clip='base',flag=49,duration=7000},
    {key='impatient',label='Impatient',dict='amb@world_human_stand_impatient@male@no_sign@base',clip='base',flag=49,duration=7000},
    {key='pushups',label='Push Ups',dict='amb@world_human_push_ups@male@base',clip='base',flag=1,duration=10000},
    {key='situps',label='Sit Ups',dict='amb@world_human_sit_ups@male@base',clip='base',flag=1,duration=10000},
    {key='yoga',label='Yoga Pose',dict='missfam5_yoga',clip='a2_pose',flag=1,duration=10000},
    {key='mechanic',label='Mechanic Work',dict='mini@repair',clip='fixing_a_ped',flag=49,duration=8000},
    {key='surrender',label='Surrender',dict='random@arrests@busted',clip='idle_a',flag=49,duration=10000},
    {key='celebrate',label='Celebrate',dict='anim@mp_player_intcelebrationmale@raise_the_roof',clip='raise_the_roof',flag=48,duration=7000},
}
Config.Pranks.CustomAnimations = {
    -- {key='my_anim',label='My Animation',dict='anim@dict',clip='clip',flag=49,duration=5000}
}

-- These can be expanded by the server owner without editing UI code.
Config.Ace.economy = Config.Ace.economy or 'rsadmin.economy'
Config.Ace.staff = Config.Ace.staff or 'rsadmin.staff'
Config.Ace.builder = Config.Ace.builder or 'rsadmin.builder'


Config.World = {
    defaults = { weather='CLEAR',hour=12,minute=0,blackout=false,rain=0.0,wind=0.0,windDirection=0.0,traffic=1.0,parked=1.0,randomVehicles=1.0,peds=1.0,scenarios=1.0 },
    reassertMs = 2500,
}
Config.Disasters = {
    maxSeconds = 120,
    allowDamage = false,
    requireOwnerForGlobalDangerous = true,
    dangerous = { tsunami=true,meteor=true,tornado=true,firestorm=true,emp=true },
    tsunami = { floodFile='water/wavyflood.xml', highWaterFile='water/wavywater.xml', riseDelayMs=8000, highWaterDelayMs=12000 },
}


-- v0.8 control-center expansion -------------------------------------------------
Config.PlayerSearch = {
    allowEndpointSearch = true, -- requires security permission
    minQueryLength = 1,
    maxResults = 128,
    refreshMs = 2000,
}

Config.LiveMap = {
    defaultMode = 'perspective', -- flat | perspective
    refreshMs = 2000,
    showLabels = true,
}

Config.Punishments = {
    maxWarningsPerPlayer = 200,
    maxNotesPerPlayer = 300,
    maxCommunityService = 1000,
    communityServiceDefault = 20,
    communityServiceCoords = {x=170.18,y=-990.91,z=30.09,w=162.0},
    communityServiceOffsets = {{4.0,0.0},{-4.0,2.0},{2.0,5.0},{-2.5,-4.0},{5.5,-2.0}},
    communityServiceRadius = 2.25,
    watchlistMaxNote = 500,
}

Config.StaffGroups = {
    allowCustomGroups = true,
    maxGroups = 32,
    ownerKey = 'owner',
    reserved = { owner=true },
}

Config.Logs = {
    pageSize = 50,
    maxPageSize = 100,
    categories = {
        all=true, players=true, moderation=true, economy=true, items=true, vehicles=true,
        world=true, disasters=true, staff=true, server=true, security=true, builder=true,
    }
}

Config.PlayerActions = {
    setPedAllowed = true,
    handcuffIndependent = true,
    slapForce = 6.0,
}

Config.World.advanced = {
    freezeTime = false,
    timeScale = 1.0,
    fog = 0.0,
    snow = false,
    waveIntensity = 0.0,
    dispatch = true,
    ambientEvents = true,
    policeActivity = 1.0,
}


-- v0.9 live-operations expansion ----------------------------------------------
Config.Duty = {
    enabled = true,
    defaultOn = false,
    command = 'aduty',
    maxLogRows = 2500,
    webhook = true,
}

Config.StaffChat.channels = {
    {key='staff', label='Staff', color='#20a9ff', permission='open'},
    {key='management', label='Management', color='#ff3f8f', permission='staff'},
    {key='moderation', label='Moderation', color='#20d4e8', permission='moderate'},
}
Config.StaffChat.allowCustomChannels = true
Config.StaffChat.maxChannels = 16
Config.StaffChat.maxChannelHistory = 120

Config.Dock = {
    enabled = true,
    interactKey = 'LMENU', -- hold Left Alt to interact while docked
}

Config.QuickMenu = {
    command = 'fadminmenu',
    keybind = 'F10',
    defaultMode = 'radial', -- radial | list
    defaultActions = {'players','gotoWaypoint','noclip','heal','reports','staffChat','vehicleRepair','world'},
    allowedActions = {
        players=true,gotoWaypoint=true,noclip=true,heal=true,reports=true,staffChat=true,
        vehicleRepair=true,world=true,bring=true,spectate=true,vehicleSpawn=true,logs=true
    }
}

Config.MapVehicles = {
    maxResults = 220,
    refreshMs = 2500,
    includeEmpty = true,
    ownerLookup = true,
}

Config.Resources = {
    allowStart = true,
    allowStop = true,
    allowRestart = true,
    ownerOnlyStartStop = true,
    deny = {
        ['rs-adminmenu']=true,['qbx_core']=true,['qb-core']=true,['es_extended']=true,
        ['oxmysql']=true,['ox_inventory']=true,['qb-inventory']=true,['ps-inventory']=true,
        ['pma-voice']=true,['qbx_vehiclekeys']=true,
    }
}
for key,value in pairs(Config.ProtectedResources or {}) do
    local name = type(key)=='string' and key or value
    if type(name)=='string' and name~='' then Config.Resources.deny[name]=true end
end

Config.Bridges = {
    inventory = {'ox_inventory','qb-inventory','ps-inventory'},
    housing = {'qbx_properties','qb-houses','ps-housing','qs-housing','bcs_housing'},
    target = {'ox_target','qb-target','interact'},
    clothing = {'illenium-appearance','fivem-appearance','qb-clothing'},
    screenshots = {'screenshot-basic'},
    sounds = {'interact-sound','xsound'},
    vehicleKeys = {'qbx_vehiclekeys','qb-vehiclekeys','Renewed-Vehiclekeys'},
    garage = {'qbx_garages','qb-garages','jg-advancedgarages'},
}

Config.Settings = {
    showServerTime = true,
    staffChatNotifications = true,
    reportNotifications = true,
    disasterNotifications = true,
}

-- Optional custom adapter hooks. Keep nil unless your provider has a custom API.
-- Example server-side property hook:
-- Config.BridgeHooks.properties = function(source)
--     return exports['my-housing']:GetPlayerProperties(source)
-- end
Config.BridgeHooks = Config.BridgeHooks or {
    properties = nil,
}


Config.Maintenance = {
    tsunamiEvacuation = true,
    minCountdownSeconds = 15,
    maxCountdownSeconds = 900,
    tsunamiLeadSeconds = 30,
    allowDisconnectAtEnd = true,
    keepStaffConnected = true,
    disconnectMessage = 'Server evacuation complete. Please reconnect after maintenance.',
}

-- v0.10 RS Pathways -----------------------------------------------------------
-- Entire progression/certification system can be disabled here.
Config.Pathways = {
    Enabled = true,
    Command = 'pathway',
    ValidationSeconds = 5,
    ProviderValidationSeconds = 15, -- inventory/money/owned-vehicle checks
    ProgressSaveSeconds = 30, -- timer progress checkpoint; completions save immediately

    -- Player-facing tracking is display-only. The server remains authoritative.
    Tracking = {
        InventoryItem = true,
        Notifications = true,
        GPS = true,
        ChatCommand = true,
        MiniHUD = false,
    },

    GuideItem = {
        Enabled = true,
        ItemName = 'citizen_guide',
        GiveOnAssignment = true,
        UpdateMetadata = true, -- live metadata refresh is supported natively by ox_inventory
        RemoveOnCompletion = false,
    },

    GPS = {
        Enabled = true,
        AutoRouteNextLocation = false,
        AllowPlayerRoute = true,
        ShowObjectiveBlip = true,
    },

    MiniHUD = {
        Enabled = false,
        DefaultVisible = false,
    },

    -- Optional job certification gates for staff job assignment in rs-adminmenu.
    -- Leave a job out to allow normal assignment without Pathways certification.
    JobRequirements = {
        police = 'police',
        ambulance = 'ems',
        ems = 'ems',
    },

    Tracks = {
        citizen = {
            Label = 'Citizen Orientation',
            Description = 'Learn the city, core services and basic server systems before full citizenship.',
            Enabled = true,
            AutoAssign = false, -- set true to automatically assign new players
            ForcedDefault = false,
            Ordered = true,
            RequiredPoints = 80,
            GuideItem = 'citizen_guide',
            Tracking = { InventoryItem=true, Notifications=true, GPS=true },
            Rewards = { bank = 500 },
            Steps = {
                { key='city_hall', label='Visit City Hall', type='location', points=10, required=true, x=-545.34, y=-204.02, z=38.22, radius=35.0, seconds=3 },
                { key='inventory', label='Open Your Inventory', type='event', event='inventory_open', points=5, required=true },
                { key='bank', label='Open / Register Bank Services', type='event', event='bank_account_opened', points=10, required=true },
                { key='clothing', label='Visit Clothing / Appearance', type='event', event='clothing_opened', points=5, required=false },
                { key='garage', label='Visit a Garage', type='event', event='garage_opened', points=5, required=true },
                { key='retrieve_vehicle', label='Retrieve a Vehicle', type='event', event='vehicle_retrieved', points=10, required=true },
                { key='refuel', label='Refuel a Vehicle', type='event', event='vehicle_refueled', points=5, required=false },
                { key='social', label='Spend 10 Minutes Around Other Citizens', type='interaction_time', points=10, required=true, seconds=600, radius=5.0, uniquePlayers=1 },
                { key='hospital', label='Visit Pillbox Medical', type='location', points=5, required=false, x=307.22, y=-595.31, z=43.28, radius=45.0, seconds=3 },
                { key='police_visit', label='Visit Mission Row Police Department', type='location', points=5, required=false, x=425.13, y=-979.56, z=30.71, radius=45.0, seconds=3 },
                { key='emote', label='Use an Emote / Animation', type='event', event='emote_used', points=5, required=false },
                { key='store_vehicle', label='Store a Vehicle', type='event', event='vehicle_stored', points=10, required=true },
            }
        },

        police = {
            Label = 'Police Academy',
            Description = 'Structured police orientation and academy certification.',
            Enabled = true,
            AutoAssign = false,
            ForcedDefault = false,
            Ordered = true,
            RequiredPoints = 100,
            Requires = {'citizen'},
            Tracking = { InventoryItem=true, Notifications=true, GPS=true },
            GuideItem = 'police_guide',
            Rewards = {},
            Steps = {
                { key='mrpd', label='Report to Mission Row PD', type='location', points=10, required=true, x=425.13, y=-979.56, z=30.71, radius=45.0, seconds=3 },
                { key='duty', label='Complete Duty Setup', type='event', event='police_duty', points=10, required=true },
                { key='radio', label='Radio Orientation', type='event', event='police_radio', points=10, required=true },
                { key='armory', label='Armory Orientation', type='event', event='police_armory', points=10, required=true },
                { key='patrol', label='Patrol Vehicle Checkout', type='event', event='police_vehicle', points=15, required=true },
                { key='cuff', label='Cuff / Escort Training', type='event', event='police_cuff_training', points=15, required=true },
                { key='report', label='Complete a Training Report', type='event', event='police_report', points=15, required=true },
                { key='supervisor', label='Supervisor Approval', type='event', event='police_supervisor_approved', points=15, required=true },
            }
        },

        ems = {
            Label = 'EMS Orientation',
            Description = 'Hospital, ambulance, treatment and reporting orientation for EMS staff.',
            Enabled = true,
            AutoAssign = false,
            ForcedDefault = false,
            Ordered = true,
            RequiredPoints = 100,
            Requires = {'citizen'},
            Tracking = { InventoryItem=true, Notifications=true, GPS=true },
            GuideItem = 'ems_guide',
            Rewards = {},
            Steps = {
                { key='hospital', label='Report to Pillbox Medical', type='location', points=10, required=true, x=307.22, y=-595.31, z=43.28, radius=45.0, seconds=3 },
                { key='duty', label='Complete EMS Duty Setup', type='event', event='ems_duty', points=10, required=true },
                { key='uniform', label='Uniform Orientation', type='event', event='ems_uniform', points=10, required=true },
                { key='radio', label='Radio Orientation', type='event', event='ems_radio', points=10, required=true },
                { key='ambulance', label='Ambulance Checkout', type='event', event='ems_vehicle', points=15, required=true },
                { key='treatment', label='Treatment Demonstration', type='event', event='ems_treatment', points=15, required=true },
                { key='transport', label='Patient Transport Demonstration', type='event', event='ems_transport', points=15, required=true },
                { key='report', label='Complete an Incident Report', type='event', event='ems_report', points=15, required=true },
            }
        },
    }
}
