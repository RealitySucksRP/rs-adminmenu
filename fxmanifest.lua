fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'RealitySucksRP'
description 'RS Admin Menu - cinematic server owner / developer command center'
version '0.15.7'

ui_page 'web/index.html'

dependency '/onesync'

shared_scripts {
    'config.lua',
    'shared/lua_console.lua'
}

client_scripts {
    'client/main.lua',
    'client/quick_menu.lua',
    'client/powers.lua',
    'client/pranks.lua',
    'client/advanced.lua',
    'client/player_actions.lua',
    'client/punishments.lua',
    'client/world_control.lua',
    'client/disaster_meteors.lua',
    'client/disaster_funnel.lua',
    'client/disaster_impacts.lua',
    'client/disaster_stuntcars.lua',
    'client/disaster_debris.lua',
    'client/disaster_physical_props.lua',
    'client/disaster_cows.lua',
    'client/spectate.lua',
    'client/noclip.lua',
    'client/vehicle_lab.lua',
    'client/entity_laser.lua',
    'client/devtools.lua',
    'client/pathways.lua'
}

server_scripts {
    'server_config.lua',
    'server/framework.lua',
    'server/bridge.lua',
    'server/main.lua',
    'server/player_lifecycle.lua',
    'server/advanced.lua',
    'server/economy_transfers.lua',
    'server/staff_groups.lua',
    'server/punishments.lua',
    'server/player_actions.lua',
    'server/operations.lua',
    'server/devtools.lua',
    'server/pathways.lua'
}

files {
    'web/index.html',
    'web/style.css',
    'web/readable.css',
    'web/ui.css',
    'web/app.js',
    'web/assets/map.webp',
    'web/assets/*',
    'web/assets/**/*',
    'locales/*.json',
    'water/*.xml',
    'install/*.lua'
}
