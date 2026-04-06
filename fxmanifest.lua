fx_version 'cerulean'
game 'gta5'

name 'qb-banking'
description 'Advanced QBCore Banking System with Loans, Billing, Taxes & Admin Tools'
author 'QB Banking'
version '1.0.0'

lua54 'yes'

shared_scripts {
    '@qb-core/shared/locale.lua',
    'config.lua',
    'shared/*.lua',
}

client_scripts {
    'client/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/app.js',
    'html/js/charts.js',
    'html/assets/sounds/*.ogg',
}

dependencies {
    'qb-core',
    'oxmysql',
}
