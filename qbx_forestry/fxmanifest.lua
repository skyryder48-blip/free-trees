fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbx_forestry'
description 'Forestry & Lumber Production for Qbox Framework'
version '1.0.0'
author 'QBX Forestry Project'

shared_scripts {
    '@ox_lib/init.lua',
    'config/shared.lua',
    'shared/*.lua',
}

client_scripts {
    'config/client.lua',
    'client/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config/server.lua',
    'server/*.lua',
}

dependencies {
    'qbx_core',
    'ox_lib',
    'ox_target',
    'ox_inventory',
    'oxmysql',
}
