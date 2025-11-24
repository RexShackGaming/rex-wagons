fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'

name 'rex-wagons'
author 'RexShackGaming'
description 'Advanced wagon shop for RSG Framework'
version '2.0.2'
url 'https://discord.gg/YUV7ebzkqs'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/server.lua',
    'server/versionchecker.lua'
}

client_scripts {
    'client/client.lua',
    'client/npcs.lua'
}

dependencies {
    'ox_lib',
    'oxmysql',
    'rsg-core',
    'ox_target',
}

files {
  'locales/*.json',
  'html/index.html',
  'html/style.css',
  'html/script.js',
  'html/images/*'
}

ui_page 'html/index.html'

lua54 'yes'
