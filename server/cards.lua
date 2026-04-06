local QBCore = exports['qb-core']:GetCoreObject()

-- ============================================================
-- CARD CALLBACKS
-- ============================================================

--- Get cards for a player
QBCore.Functions.CreateCallback('qb-banking:server:getCards', function(source, cb, accountId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb({}) end

    if not Config.Cards.Enabled then return cb({}) end

    if not VerifyAccountAccess(Player.PlayerData.citizenid, accountId) then
        return cb({})
    end

    local cards = MySQL.query.await([[
        SELECT id, account_id, card_number, holder_name, expiry_date, daily_limit, daily_spent, is_blocked, is_active, created_at
        FROM bank_cards
        WHERE account_id = ? AND is_active = 1
    ]], { accountId })

    -- Mask card numbers for display (show last 4 digits)
    if cards then
        for _, card in ipairs(cards) do
            card.masked_number = string.rep('*', #card.card_number - 4) .. string.sub(card.card_number, -4)
        end
    end

    cb(cards or {})
end)

-- ============================================================
-- CREATE CARD
-- ============================================================

RegisterNetEvent('qb-banking:server:createCard', function(accountId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if not Config.Cards.Enabled then return end

    local citizenid = Player.PlayerData.citizenid
    if not VerifyAccountAccess(citizenid, accountId) then
        return TriggerClientEvent('qb-banking:client:notify', src, L('account_not_found'), 'error')
    end

    -- Check account type allows cards
    local account = MySQL.single.await('SELECT * FROM bank_accounts WHERE id = ?', { accountId })
    if not account then return end

    local typeConfig = Config.AccountTypes[account.account_type]
    if typeConfig and not typeConfig.allowCards then
        return TriggerClientEvent('qb-banking:client:notify', src, L('error'), 'error')
    end

    -- Check card limit
    local cardCount = MySQL.scalar.await('SELECT COUNT(*) FROM bank_cards WHERE account_id = ? AND is_active = 1', { accountId })
    if cardCount >= Config.Cards.MaxCardsPerAccount then
        return TriggerClientEvent('qb-banking:client:notify', src, L('card_limit_reached'), 'error')
    end

    -- Generate card details
    local cardNumber = GenerateUniqueCardNumber()
    local cvv = Utils.GenerateCVV()
    local expiryDate = os.date('%Y-%m-%d', os.time() + (Config.Cards.ExpiryMonths * 30 * 86400))
    local holderName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname

    MySQL.insert.await([[
        INSERT INTO bank_cards (account_id, card_number, cvv, holder_name, expiry_date, daily_limit)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], {
        accountId, cardNumber, cvv, holderName, expiryDate, Config.Cards.DailySpendLimit
    })

    TriggerClientEvent('qb-banking:client:notify', src, L('card_created'), 'success')
    TriggerClientEvent('qb-banking:client:refreshAccounts', src)

    LogToDiscord('transactions', string.format('**Card Created** | %s created card for account #%d',
        citizenid, accountId))
end)

-- ============================================================
-- BLOCK / UNBLOCK CARD
-- ============================================================

RegisterNetEvent('qb-banking:server:toggleCardBlock', function(cardId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local card = MySQL.single.await([[
        SELECT c.*, a.owner_citizenid
        FROM bank_cards c
        JOIN bank_accounts a ON c.account_id = a.id
        WHERE c.id = ?
    ]], { cardId })

    if not card then return end
    if not VerifyAccountAccess(Player.PlayerData.citizenid, card.account_id) then return end

    local newState = card.is_blocked == 1 and 0 or 1
    MySQL.update.await('UPDATE bank_cards SET is_blocked = ? WHERE id = ?', { newState, cardId })

    if newState == 1 then
        TriggerClientEvent('qb-banking:client:notify', src, L('card_blocked'), 'warning')
    else
        TriggerClientEvent('qb-banking:client:notify', src, L('success'), 'success')
    end
end)

-- ============================================================
-- DAILY LIMIT RESET
-- ============================================================

CreateThread(function()
    while true do
        Wait(60000 * 60) -- Check every hour

        if not Config.Cards.Enabled then goto continue end

        -- Reset daily spending for cards where 24h has passed
        MySQL.update.await([[
            UPDATE bank_cards
            SET daily_spent = 0, daily_reset = NOW()
            WHERE daily_reset <= DATE_SUB(NOW(), INTERVAL 24 HOUR) AND is_active = 1
        ]])

        ::continue::
    end
end)

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

--- Generate unique card number
---@return string
function GenerateUniqueCardNumber()
    local cardNumber
    local exists = true
    while exists do
        cardNumber = Utils.GenerateCardNumber()
        local count = MySQL.scalar.await('SELECT COUNT(*) FROM bank_cards WHERE card_number = ?', { cardNumber })
        exists = count > 0
    end
    return cardNumber
end

Utils.Debug('QB Banking cards module initialized')
