local QBCore = exports['qb-core']:GetCoreObject()

-- ============================================================
-- NOTIFICATION SYSTEM
-- ============================================================

--- Display a notification to the player
---@param message string
---@param type string 'success', 'error', 'warning', 'info'
RegisterNetEvent('qb-banking:client:notify', function(message, type)
    local notifType = type or 'info'
    Utils.Debug('NOTIFY', 'Notification: type=' .. tostring(notifType) .. ' system=' .. tostring(Config.Notifications.System) .. ' msg=' .. tostring(message))

    if Config.Notifications.System == 'qb' then
        -- QBCore native notification
        QBCore.Functions.Notify(message, notifType, Config.Notifications.Duration)
    elseif Config.Notifications.System == 'okok' then
        -- okokNotify
        exports['okokNotify']:Alert(L('notification_title'), message, Config.Notifications.Duration, notifType)
    else
        -- Custom / NUI notification
        SendNUIMessage({
            action = 'notification',
            message = message,
            type = notifType,
            duration = Config.Notifications.Duration,
        })
    end

    -- Play notification sound
    Utils.Debug('NOTIFY', 'Sound enabled: ' .. tostring(Config.Notifications.SoundEnabled))
    if Config.Notifications.SoundEnabled then
        SendNUIMessage({
            action = 'playSound',
            sound = notifType,
            volume = Config.Notifications.SoundVolume,
        })
    end
end)

Utils.Debug('QB Banking notifications module initialized')
