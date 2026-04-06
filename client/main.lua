local QBCore = exports['qb-core']:GetCoreObject()
local PlayerData = QBCore.Functions.GetPlayerData()
local isUIOpen = false
local currentMode = 'bank' -- 'bank' or 'atm'

-- ============================================================
-- PLAYER DATA UPDATES
-- ============================================================

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    PlayerData = {}
    CloseUI()
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
    PlayerData.job = JobInfo
end)

-- ============================================================
-- NUI OPEN / CLOSE
-- ============================================================

--- Open the banking UI
---@param mode string 'bank' or 'atm'
function OpenUI(mode)
    if isUIOpen then return end
    isUIOpen = true
    currentMode = mode or 'bank'

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        mode = currentMode,
        playerName = (PlayerData.charinfo and PlayerData.charinfo.firstname or 'Player') .. ' ' ..
                     (PlayerData.charinfo and PlayerData.charinfo.lastname or ''),
        job = PlayerData.job and PlayerData.job.name or 'unemployed',
    })

    -- Play open sound
    if Config.Notifications.SoundEnabled then
        SendNUIMessage({ action = 'playSound', sound = 'open', volume = Config.Notifications.SoundVolume })
    end
end

--- Close the banking UI
function CloseUI()
    if not isUIOpen then return end
    isUIOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

-- ============================================================
-- NUI CALLBACKS (from UI to client/server)
-- ============================================================

RegisterNUICallback('close', function(_, cb)
    CloseUI()
    cb('ok')
end)

RegisterNUICallback('getAccounts', function(_, cb)
    QBCore.Functions.TriggerCallback('qb-banking:server:getAccounts', function(accounts)
        cb(accounts)
    end)
end)

RegisterNUICallback('getDashboard', function(data, cb)
    QBCore.Functions.TriggerCallback('qb-banking:server:getDashboard', function(dashboard)
        cb(dashboard)
    end, data.accountId)
end)

RegisterNUICallback('getTransactions', function(data, cb)
    QBCore.Functions.TriggerCallback('qb-banking:server:getTransactions', function(result)
        cb(result)
    end, data.accountId, data.page, data.filters)
end)

RegisterNUICallback('deposit', function(data, cb)
    TriggerServerEvent('qb-banking:server:deposit', data.accountId, data.amount)
    cb('ok')
end)

RegisterNUICallback('withdraw', function(data, cb)
    TriggerServerEvent('qb-banking:server:withdraw', data.accountId, data.amount)
    cb('ok')
end)

RegisterNUICallback('transfer', function(data, cb)
    TriggerServerEvent('qb-banking:server:transfer', data.fromAccountId, data.toIban, data.amount, data.description)
    cb('ok')
end)

RegisterNUICallback('scheduleTransfer', function(data, cb)
    TriggerServerEvent('qb-banking:server:scheduleTransfer', data.fromAccountId, data.toIban, data.amount, data.description, data.frequency, data.executeDate)
    cb('ok')
end)

RegisterNUICallback('createAccount', function(data, cb)
    TriggerServerEvent('qb-banking:server:createAccount', data.accountType, data.accountName)
    cb('ok')
end)

RegisterNUICallback('closeAccount', function(data, cb)
    TriggerServerEvent('qb-banking:server:closeAccount', data.accountId)
    cb('ok')
end)

-- Shared Account
RegisterNUICallback('addSharedMember', function(data, cb)
    TriggerServerEvent('qb-banking:server:addSharedMember', data.accountId, data.citizenId, data.role)
    cb('ok')
end)

RegisterNUICallback('removeSharedMember', function(data, cb)
    TriggerServerEvent('qb-banking:server:removeSharedMember', data.accountId, data.citizenId)
    cb('ok')
end)

-- Loans
RegisterNUICallback('getLoanPlans', function(_, cb)
    QBCore.Functions.TriggerCallback('qb-banking:server:getLoanPlans', function(plans)
        cb(plans)
    end)
end)

RegisterNUICallback('getLoans', function(_, cb)
    QBCore.Functions.TriggerCallback('qb-banking:server:getLoans', function(loans)
        cb(loans)
    end)
end)

RegisterNUICallback('applyLoan', function(data, cb)
    TriggerServerEvent('qb-banking:server:applyLoan', data.planId, data.amount, data.accountId)
    cb('ok')
end)

RegisterNUICallback('repayLoan', function(data, cb)
    TriggerServerEvent('qb-banking:server:repayLoan', data.loanId, data.amount, data.accountId)
    cb('ok')
end)

-- Billing
RegisterNUICallback('getInvoices', function(data, cb)
    QBCore.Functions.TriggerCallback('qb-banking:server:getInvoices', function(invoices)
        cb(invoices)
    end, data.filter)
end)

RegisterNUICallback('sendInvoice', function(data, cb)
    TriggerServerEvent('qb-banking:server:sendInvoice', data.targetCitizenId, data.amount, data.category, data.description)
    cb('ok')
end)

RegisterNUICallback('payInvoice', function(data, cb)
    TriggerServerEvent('qb-banking:server:payInvoice', data.invoiceId, data.accountId, data.amount)
    cb('ok')
end)

-- Taxes
RegisterNUICallback('getTaxRecords', function(_, cb)
    QBCore.Functions.TriggerCallback('qb-banking:server:getTaxRecords', function(records)
        cb(records)
    end)
end)

-- Cards
RegisterNUICallback('getCards', function(data, cb)
    QBCore.Functions.TriggerCallback('qb-banking:server:getCards', function(cards)
        cb(cards)
    end, data.accountId)
end)

RegisterNUICallback('createCard', function(data, cb)
    TriggerServerEvent('qb-banking:server:createCard', data.accountId)
    cb('ok')
end)

RegisterNUICallback('toggleCardBlock', function(data, cb)
    TriggerServerEvent('qb-banking:server:toggleCardBlock', data.cardId)
    cb('ok')
end)

-- Admin
RegisterNUICallback('admin:getOverview', function(_, cb)
    QBCore.Functions.TriggerCallback('qb-banking:server:admin:getOverview', function(data)
        cb(data)
    end)
end)

RegisterNUICallback('admin:searchAccounts', function(data, cb)
    QBCore.Functions.TriggerCallback('qb-banking:server:admin:searchAccounts', function(accounts)
        cb(accounts)
    end, data.query)
end)

RegisterNUICallback('admin:getLogs', function(data, cb)
    QBCore.Functions.TriggerCallback('qb-banking:server:admin:getLogs', function(logs)
        cb(logs)
    end, data.page)
end)

RegisterNUICallback('admin:setBalance', function(data, cb)
    TriggerServerEvent('qb-banking:server:admin:setBalance', data.accountId, data.amount)
    cb('ok')
end)

RegisterNUICallback('admin:toggleFreeze', function(data, cb)
    TriggerServerEvent('qb-banking:server:admin:toggleFreeze', data.accountId)
    cb('ok')
end)

RegisterNUICallback('admin:clearLoan', function(data, cb)
    TriggerServerEvent('qb-banking:server:admin:clearLoan', data.loanId)
    cb('ok')
end)

RegisterNUICallback('admin:setCreditScore', function(data, cb)
    TriggerServerEvent('qb-banking:server:admin:setCreditScore', data.citizenId, data.score)
    cb('ok')
end)

RegisterNUICallback('admin:cancelInvoice', function(data, cb)
    TriggerServerEvent('qb-banking:server:admin:cancelInvoice', data.invoiceId)
    cb('ok')
end)

-- ============================================================
-- SERVER EVENT HANDLERS
-- ============================================================

RegisterNetEvent('qb-banking:client:init', function(data)
    -- Initial data received from server on player load
    Utils.Debug('Banking initialized with ' .. #data.accounts .. ' accounts, credit score: ' .. data.creditScore)
end)

RegisterNetEvent('qb-banking:client:refreshAccounts', function()
    if isUIOpen then
        SendNUIMessage({ action = 'refreshAccounts' })
    end
end)

RegisterNetEvent('qb-banking:client:openAdmin', function()
    if isUIOpen then CloseUI() end
    isUIOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openAdmin' })
end)

-- ============================================================
-- BANK NPC & BLIP SETUP
-- ============================================================

CreateThread(function()
    for _, bank in ipairs(Config.BankLocations) do
        -- Create blip
        local blip = AddBlipForCoord(bank.coords.x, bank.coords.y, bank.coords.z)
        SetBlipSprite(blip, bank.blip.sprite)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, bank.blip.scale)
        SetBlipColour(blip, bank.blip.color)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(bank.name .. ' Bank')
        EndTextCommandSetBlipName(blip)

        -- Spawn NPC
        if bank.npcModel then
            local model = GetHashKey(bank.npcModel)
            RequestModel(model)
            local timeout = 0
            while not HasModelLoaded(model) and timeout < 5000 do
                Wait(10)
                timeout = timeout + 10
            end

            if HasModelLoaded(model) then
                local ped = CreatePed(0, model, bank.coords.x, bank.coords.y, bank.coords.z - 1.0, bank.heading, false, true)
                SetEntityHeading(ped, bank.heading)
                FreezeEntityPosition(ped, true)
                SetEntityInvincible(ped, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
            end
        end

        -- Interaction zone
        if Config.UseTarget then
            -- qb-target integration
            exports['qb-target']:AddBoxZone('bank_' .. bank.name, bank.coords, 2.0, 2.0, {
                name = 'bank_' .. bank.name,
                heading = bank.heading,
                debugPoly = Config.Debug,
                minZ = bank.coords.z - 1.0,
                maxZ = bank.coords.z + 2.0,
            }, {
                options = {
                    {
                        type = 'client',
                        icon = 'fas fa-university',
                        label = L('bank_open'),
                        action = function()
                            OpenUI('bank')
                        end,
                    },
                },
                distance = 2.5,
            })
        end
    end
end)

-- DrawText interaction (fallback when not using qb-target)
if not Config.UseTarget then
    CreateThread(function()
        while true do
            local sleep = 1000
            local playerCoords = GetEntityCoords(PlayerPedId())

            for _, bank in ipairs(Config.BankLocations) do
                local dist = #(playerCoords - bank.coords)
                if dist < 3.0 then
                    sleep = 0
                    DrawText3D(bank.coords.x, bank.coords.y, bank.coords.z + 0.5, L('bank_interact'))

                    if IsControlJustReleased(0, 38) then -- E key
                        OpenUI('bank')
                    end
                end
            end

            Wait(sleep)
        end
    end)
end

-- ============================================================
-- ATM INTERACTION
-- ============================================================

if Config.ATM.Enabled then
    if Config.UseTarget then
        -- Add target to ATM models
        CreateThread(function()
            for _, model in ipairs(Config.ATM.ATMModels) do
                exports['qb-target']:AddTargetModel(GetHashKey(model), {
                    options = {
                        {
                            type = 'client',
                            icon = 'fas fa-credit-card',
                            label = L('atm_open'),
                            action = function()
                                OpenUI('atm')
                            end,
                        },
                    },
                    distance = 1.5,
                })
            end
        end)
    else
        CreateThread(function()
            while true do
                local sleep = 1000
                local playerCoords = GetEntityCoords(PlayerPedId())
                local closestATM = nil
                local closestDist = math.huge

                -- Check nearby ATM objects
                for _, model in ipairs(Config.ATM.ATMModels) do
                    local hash = GetHashKey(model)
                    local atm = GetClosestObjectOfType(playerCoords.x, playerCoords.y, playerCoords.z, 2.0, hash, false, false, false)
                    if atm ~= 0 then
                        local atmCoords = GetEntityCoords(atm)
                        local dist = #(playerCoords - atmCoords)
                        if dist < closestDist then
                            closestDist = dist
                            closestATM = atmCoords
                        end
                    end
                end

                if closestATM and closestDist < 1.5 then
                    sleep = 0
                    DrawText3D(closestATM.x, closestATM.y, closestATM.z + 0.5, L('atm_interact'))

                    if IsControlJustReleased(0, 38) then
                        OpenUI('atm')
                    end
                end

                Wait(sleep)
            end
        end)
    end
end

-- ============================================================
-- ESC KEY HANDLER
-- ============================================================

CreateThread(function()
    while true do
        Wait(0)
        if isUIOpen and IsControlJustReleased(0, 322) then -- ESC
            CloseUI()
        end
    end
end)

-- ============================================================
-- HELPER: 3D TEXT
-- ============================================================

function DrawText3D(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0)
    local factor = (string.len(text)) / 370
    DrawRect(0.0, 0.0 + 0.0125, 0.017 + factor, 0.03, 0, 0, 0, 75)
    ClearDrawOrigin()
end

Utils.Debug('QB Banking client initialized')
