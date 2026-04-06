local QBCore = exports['qb-core']:GetCoreObject()

-- Server-side cache
ServerCache = {
    accounts = {},
    creditScores = {},
    lastCleanup = os.time(),
}

-- ============================================================
-- PLAYER LOAD / UNLOAD
-- ============================================================

--- Initialize player bank account on login
RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid

    -- Check if player has a personal account, create one if not
    local accounts = MySQL.query.await('SELECT * FROM bank_accounts WHERE owner_citizenid = ? AND is_closed = 0', { citizenid })

    if not accounts or #accounts == 0 then
        -- Create default personal account
        local iban = GenerateUniqueIBAN()
        MySQL.insert.await('INSERT INTO bank_accounts (iban, owner_citizenid, account_type, account_name, balance) VALUES (?, ?, ?, ?, ?)', {
            iban, citizenid, 'personal', 'Personal Account', Player.PlayerData.money.bank or 0
        })
        Utils.Debug('Created personal account for ' .. citizenid .. ' with IBAN: ' .. iban)
    end

    -- Ensure credit score exists
    local creditScore = MySQL.scalar.await('SELECT score FROM bank_credit_scores WHERE citizenid = ?', { citizenid })
    if not creditScore then
        MySQL.insert.await('INSERT INTO bank_credit_scores (citizenid, score) VALUES (?, ?)', {
            citizenid, Config.Loans.DefaultCreditScore
        })
    end

    -- Cache player data
    CachePlayerAccounts(citizenid)

    -- Send initial data to client
    TriggerClientEvent('qb-banking:client:init', src, {
        accounts = GetPlayerAccounts(citizenid),
        creditScore = GetCreditScore(citizenid),
    })
end)

RegisterNetEvent('QBCore:Server:OnPlayerUnload', function(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local citizenid = Player.PlayerData.citizenid
    -- Clear cache
    ServerCache.accounts[citizenid] = nil
    ServerCache.creditScores[citizenid] = nil
end)

-- ============================================================
-- NUI CALLBACK HANDLERS
-- ============================================================

--- Get all accounts for a player
QBCore.Functions.CreateCallback('qb-banking:server:getAccounts', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb({}) end
    local accounts = GetPlayerAccounts(Player.PlayerData.citizenid)
    cb(accounts)
end)

--- Get transaction history
QBCore.Functions.CreateCallback('qb-banking:server:getTransactions', function(source, cb, accountId, page, filters)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb({}) end

    if not VerifyAccountAccess(Player.PlayerData.citizenid, accountId) then
        return cb({})
    end

    local limit = Config.Transactions.HistoryPageSize
    local offset = ((page or 1) - 1) * limit
    local query = 'SELECT * FROM bank_transactions WHERE account_id = ?'
    local params = { accountId }

    if filters then
        if filters.type and filters.type ~= '' then
            query = query .. ' AND type = ?'
            params[#params + 1] = filters.type
        end
        if filters.dateFrom and filters.dateFrom ~= '' then
            query = query .. ' AND created_at >= ?'
            params[#params + 1] = filters.dateFrom
        end
        if filters.dateTo and filters.dateTo ~= '' then
            query = query .. ' AND created_at <= ?'
            params[#params + 1] = filters.dateTo
        end
        if filters.search and filters.search ~= '' then
            query = query .. ' AND (description LIKE ? OR from_iban LIKE ? OR to_iban LIKE ?)'
            local searchPattern = '%' .. filters.search .. '%'
            params[#params + 1] = searchPattern
            params[#params + 1] = searchPattern
            params[#params + 1] = searchPattern
        end
    end

    -- Get total count
    local countQuery = query:gsub('SELECT %*', 'SELECT COUNT(*) as total')
    local countResult = MySQL.scalar.await(countQuery, params)

    query = query .. ' ORDER BY created_at DESC LIMIT ? OFFSET ?'
    params[#params + 1] = limit
    params[#params + 1] = offset

    local transactions = MySQL.query.await(query, params)
    cb({
        transactions = transactions or {},
        total = countResult or 0,
        page = page or 1,
        pageSize = limit,
    })
end)

--- Get dashboard stats
QBCore.Functions.CreateCallback('qb-banking:server:getDashboard', function(source, cb, accountId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb({}) end

    if not VerifyAccountAccess(Player.PlayerData.citizenid, accountId) then
        return cb({})
    end

    -- Get account balance
    local account = MySQL.single.await('SELECT * FROM bank_accounts WHERE id = ?', { accountId })
    if not account then return cb({}) end

    -- Get recent transactions summary
    local weekAgo = os.time() - (7 * 24 * 60 * 60)
    local weekStats = MySQL.query.await([[
        SELECT
            COALESCE(SUM(CASE WHEN type = 'deposit' THEN amount ELSE 0 END), 0) as total_deposits,
            COALESCE(SUM(CASE WHEN type = 'withdraw' THEN amount ELSE 0 END), 0) as total_withdrawals,
            COALESCE(SUM(CASE WHEN type = 'transfer_out' THEN amount ELSE 0 END), 0) as total_sent,
            COALESCE(SUM(CASE WHEN type = 'transfer_in' THEN amount ELSE 0 END), 0) as total_received,
            COUNT(*) as transaction_count
        FROM bank_transactions
        WHERE account_id = ? AND created_at >= FROM_UNIXTIME(?)
    ]], { accountId, weekAgo })

    -- Get daily transaction data for chart (last 7 days)
    local dailyData = MySQL.query.await([[
        SELECT
            DATE(created_at) as date,
            COALESCE(SUM(CASE WHEN type IN ('deposit', 'transfer_in') THEN amount ELSE 0 END), 0) as income,
            COALESCE(SUM(CASE WHEN type IN ('withdraw', 'transfer_out') THEN amount ELSE 0 END), 0) as expenses
        FROM bank_transactions
        WHERE account_id = ? AND created_at >= FROM_UNIXTIME(?)
        GROUP BY DATE(created_at)
        ORDER BY DATE(created_at) ASC
    ]], { accountId, weekAgo })

    -- Get active loans count
    local activeLoans = MySQL.scalar.await('SELECT COUNT(*) FROM bank_loans WHERE citizenid = ? AND status = ?', {
        Player.PlayerData.citizenid, 'active'
    })

    -- Get unpaid invoices count
    local unpaidInvoices = MySQL.scalar.await('SELECT COUNT(*) FROM bank_invoices WHERE to_citizenid = ? AND status IN (?, ?)', {
        Player.PlayerData.citizenid, 'pending', 'overdue'
    })

    cb({
        balance = account.balance,
        accountType = account.account_type,
        iban = account.iban,
        weekStats = weekStats and weekStats[1] or {},
        dailyData = dailyData or {},
        activeLoans = activeLoans or 0,
        unpaidInvoices = unpaidInvoices or 0,
        creditScore = GetCreditScore(Player.PlayerData.citizenid),
    })
end)

-- ============================================================
-- DEPOSIT
-- ============================================================

RegisterNetEvent('qb-banking:server:deposit', function(accountId, amount)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    amount = tonumber(amount)
    local valid, err = Utils.ValidateAmount(amount, Config.Transactions.MinDeposit, Config.Transactions.MaxDeposit)
    if not valid then
        return TriggerClientEvent('qb-banking:client:notify', src, L(err), 'error')
    end

    if not VerifyAccountAccess(Player.PlayerData.citizenid, accountId) then
        return TriggerClientEvent('qb-banking:client:notify', src, L('account_not_found'), 'error')
    end

    -- Check if player has enough cash
    local cash = Player.PlayerData.money.cash
    if cash < amount then
        return TriggerClientEvent('qb-banking:client:notify', src, L('account_insufficient_funds'), 'error')
    end

    -- Process deposit
    Player.Functions.RemoveMoney('cash', amount, 'bank-deposit')

    local newBalance = UpdateAccountBalance(accountId, amount, 'add')
    RecordTransaction(accountId, 'deposit', amount, 0, 0, newBalance, 'Cash deposit', nil, nil, Player.PlayerData.citizenid)

    -- Trigger tax event if applicable
    TriggerEvent('qb-banking:server:onDeposit', Player.PlayerData.citizenid, amount)

    TriggerClientEvent('qb-banking:client:notify', src, L('deposit_success', Utils.FormatMoney(amount)), 'success')
    TriggerClientEvent('qb-banking:client:refreshAccounts', src)

    LogToDiscord('transactions', string.format('**Deposit** | %s deposited %s into account #%d',
        Player.PlayerData.citizenid, Utils.FormatMoney(amount), accountId))
end)

-- ============================================================
-- WITHDRAW
-- ============================================================

RegisterNetEvent('qb-banking:server:withdraw', function(accountId, amount)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    amount = tonumber(amount)
    local valid, err = Utils.ValidateAmount(amount, Config.Transactions.MinWithdraw, Config.Transactions.MaxWithdraw)
    if not valid then
        return TriggerClientEvent('qb-banking:client:notify', src, L(err), 'error')
    end

    if not VerifyAccountAccess(Player.PlayerData.citizenid, accountId) then
        return TriggerClientEvent('qb-banking:client:notify', src, L('account_not_found'), 'error')
    end

    local account = MySQL.single.await('SELECT balance FROM bank_accounts WHERE id = ?', { accountId })
    if not account or account.balance < amount then
        return TriggerClientEvent('qb-banking:client:notify', src, L('account_insufficient_funds'), 'error')
    end

    -- Process withdrawal
    local newBalance = UpdateAccountBalance(accountId, amount, 'subtract')
    Player.Functions.AddMoney('cash', amount, 'bank-withdrawal')

    RecordTransaction(accountId, 'withdraw', amount, 0, 0, newBalance, 'Cash withdrawal', nil, nil, Player.PlayerData.citizenid)

    TriggerClientEvent('qb-banking:client:notify', src, L('withdraw_success', Utils.FormatMoney(amount)), 'success')
    TriggerClientEvent('qb-banking:client:refreshAccounts', src)

    LogToDiscord('transactions', string.format('**Withdrawal** | %s withdrew %s from account #%d',
        Player.PlayerData.citizenid, Utils.FormatMoney(amount), accountId))
end)

-- ============================================================
-- TRANSFER
-- ============================================================

RegisterNetEvent('qb-banking:server:transfer', function(fromAccountId, toIban, amount, description)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    amount = tonumber(amount)
    local valid, err = Utils.ValidateAmount(amount, Config.Transactions.MinTransfer, Config.Transactions.MaxTransfer)
    if not valid then
        return TriggerClientEvent('qb-banking:client:notify', src, L(err), 'error')
    end

    if not VerifyAccountAccess(Player.PlayerData.citizenid, fromAccountId) then
        return TriggerClientEvent('qb-banking:client:notify', src, L('account_not_found'), 'error')
    end

    -- Verify recipient exists
    local toAccount = MySQL.single.await('SELECT * FROM bank_accounts WHERE iban = ? AND is_closed = 0', { toIban })
    if not toAccount then
        return TriggerClientEvent('qb-banking:client:notify', src, L('recipient_not_found'), 'error')
    end

    -- Calculate fees and taxes
    local fee = Utils.CalculateTransferFee(amount)
    local tax = 0
    if not Utils.IsJobTaxExempt(Player.PlayerData.job.name) then
        tax = Utils.CalculateTransactionTax(amount)
    end
    local totalDeduction = amount + fee + tax

    -- Check balance
    local fromAccount = MySQL.single.await('SELECT * FROM bank_accounts WHERE id = ?', { fromAccountId })
    if not fromAccount or fromAccount.balance < totalDeduction then
        return TriggerClientEvent('qb-banking:client:notify', src, L('account_insufficient_funds'), 'error')
    end

    -- Process transfer
    local fromBalance = UpdateAccountBalance(fromAccountId, totalDeduction, 'subtract')
    local toBalance = UpdateAccountBalance(toAccount.id, amount, 'add')

    local desc = description or 'Transfer'
    RecordTransaction(fromAccountId, 'transfer_out', amount, fee, tax, fromBalance, desc, fromAccount.iban, toIban, Player.PlayerData.citizenid)
    RecordTransaction(toAccount.id, 'transfer_in', amount, 0, 0, toBalance, desc, fromAccount.iban, toIban, Player.PlayerData.citizenid)

    -- Record tax if applicable
    if tax > 0 then
        RecordTax(Player.PlayerData.citizenid, fromAccountId, 'transaction', tax, amount, Config.Taxes.TransactionTax.Rate, 'Transaction tax on transfer')
    end

    TriggerClientEvent('qb-banking:client:notify', src, L('transfer_success', Utils.FormatMoney(amount), toIban), 'success')
    if fee > 0 then
        TriggerClientEvent('qb-banking:client:notify', src, L('transfer_fee', Utils.FormatMoney(fee)), 'info')
    end
    TriggerClientEvent('qb-banking:client:refreshAccounts', src)

    -- Notify recipient if online
    local recipientPlayer = QBCore.Functions.GetPlayerByCitizenId(toAccount.owner_citizenid)
    if recipientPlayer then
        TriggerClientEvent('qb-banking:client:notify', recipientPlayer.PlayerData.source,
            L('transfer_success', Utils.FormatMoney(amount), 'your account'), 'success')
        TriggerClientEvent('qb-banking:client:refreshAccounts', recipientPlayer.PlayerData.source)
    end

    LogToDiscord('transactions', string.format('**Transfer** | %s sent %s from %s to %s (Fee: %s, Tax: %s)',
        Player.PlayerData.citizenid, Utils.FormatMoney(amount), fromAccount.iban, toIban,
        Utils.FormatMoney(fee), Utils.FormatMoney(tax)))
end)

-- ============================================================
-- ACCOUNT MANAGEMENT
-- ============================================================

RegisterNetEvent('qb-banking:server:createAccount', function(accountType, accountName)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid

    -- Validate account type
    if not Config.AccountTypes[accountType] then
        return TriggerClientEvent('qb-banking:client:notify', src, L('error'), 'error')
    end

    -- Check account limit
    local accountCount = MySQL.scalar.await('SELECT COUNT(*) FROM bank_accounts WHERE owner_citizenid = ? AND is_closed = 0', { citizenid })
    if accountCount >= Config.MaxAccountsPerPlayer then
        return TriggerClientEvent('qb-banking:client:notify', src, L('account_limit_reached'), 'error')
    end

    -- Generate unique IBAN
    local iban = GenerateUniqueIBAN()
    local typeConfig = Config.AccountTypes[accountType]

    MySQL.insert.await('INSERT INTO bank_accounts (iban, owner_citizenid, account_type, account_name, balance) VALUES (?, ?, ?, ?, ?)', {
        iban, citizenid, accountType, accountName or typeConfig.label, typeConfig.openingBalance or 0
    })

    CachePlayerAccounts(citizenid)
    TriggerClientEvent('qb-banking:client:notify', src, L('account_created'), 'success')
    TriggerClientEvent('qb-banking:client:refreshAccounts', src)

    LogToDiscord('transactions', string.format('**Account Created** | %s created a %s account (IBAN: %s)',
        citizenid, accountType, iban))
end)

RegisterNetEvent('qb-banking:server:closeAccount', function(accountId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local account = MySQL.single.await('SELECT * FROM bank_accounts WHERE id = ? AND owner_citizenid = ?', { accountId, citizenid })

    if not account then
        return TriggerClientEvent('qb-banking:client:notify', src, L('account_not_found'), 'error')
    end

    -- Transfer remaining balance to cash
    if account.balance > 0 then
        Player.Functions.AddMoney('cash', account.balance, 'account-closure')
    end

    MySQL.update.await('UPDATE bank_accounts SET is_closed = 1, balance = 0 WHERE id = ?', { accountId })
    CachePlayerAccounts(citizenid)

    TriggerClientEvent('qb-banking:client:notify', src, L('account_closed'), 'success')
    TriggerClientEvent('qb-banking:client:refreshAccounts', src)
end)

-- ============================================================
-- SHARED ACCOUNT MANAGEMENT
-- ============================================================

RegisterNetEvent('qb-banking:server:addSharedMember', function(accountId, targetCitizenId, role)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if not Config.AllowSharedAccounts then return end

    local account = MySQL.single.await('SELECT * FROM bank_accounts WHERE id = ? AND owner_citizenid = ? AND account_type = ?', {
        accountId, Player.PlayerData.citizenid, 'shared'
    })
    if not account then
        return TriggerClientEvent('qb-banking:client:notify', src, L('account_not_found'), 'error')
    end

    local memberCount = MySQL.scalar.await('SELECT COUNT(*) FROM bank_account_members WHERE account_id = ?', { accountId })
    if memberCount >= Config.MaxSharedMembers then
        return TriggerClientEvent('qb-banking:client:notify', src, L('account_limit_reached'), 'error')
    end

    MySQL.insert.await('INSERT IGNORE INTO bank_account_members (account_id, citizenid, role) VALUES (?, ?, ?)', {
        accountId, targetCitizenId, role or 'member'
    })

    TriggerClientEvent('qb-banking:client:notify', src, L('success'), 'success')
end)

RegisterNetEvent('qb-banking:server:removeSharedMember', function(accountId, targetCitizenId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local account = MySQL.single.await('SELECT * FROM bank_accounts WHERE id = ? AND owner_citizenid = ?', {
        accountId, Player.PlayerData.citizenid
    })
    if not account then
        return TriggerClientEvent('qb-banking:client:notify', src, L('account_not_found'), 'error')
    end

    MySQL.query.await('DELETE FROM bank_account_members WHERE account_id = ? AND citizenid = ?', {
        accountId, targetCitizenId
    })

    TriggerClientEvent('qb-banking:client:notify', src, L('success'), 'success')
end)

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

--- Generate a unique IBAN that doesn't exist in database
---@return string
function GenerateUniqueIBAN()
    local iban
    local exists = true
    while exists do
        iban = Utils.GenerateIBAN()
        local count = MySQL.scalar.await('SELECT COUNT(*) FROM bank_accounts WHERE iban = ?', { iban })
        exists = count > 0
    end
    return iban
end

--- Update account balance (add or subtract)
---@param accountId number
---@param amount number
---@param operation string 'add' or 'subtract'
---@return number newBalance
function UpdateAccountBalance(accountId, amount, operation)
    if operation == 'add' then
        MySQL.update.await('UPDATE bank_accounts SET balance = balance + ? WHERE id = ?', { amount, accountId })
    else
        MySQL.update.await('UPDATE bank_accounts SET balance = balance - ? WHERE id = ?', { amount, accountId })
    end
    local newBalance = MySQL.scalar.await('SELECT balance FROM bank_accounts WHERE id = ?', { accountId })
    return newBalance or 0
end

--- Record a transaction in the database
function RecordTransaction(accountId, txType, amount, fee, tax, balanceAfter, description, fromIban, toIban, initiatedBy)
    MySQL.insert('INSERT INTO bank_transactions (account_id, type, amount, fee, tax, balance_after, description, from_iban, to_iban, initiated_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
        accountId, txType, amount, fee or 0, tax or 0, balanceAfter, description, fromIban, toIban, initiatedBy
    })
end

--- Record a tax entry
function RecordTax(citizenid, accountId, taxType, amount, taxableAmount, rate, description)
    MySQL.insert('INSERT INTO bank_tax_records (citizenid, account_id, tax_type, amount, taxable_amount, rate, description) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        citizenid, accountId, taxType, amount, taxableAmount, rate, description
    })
end

--- Check if player has access to an account
---@param citizenid string
---@param accountId number
---@return boolean
function VerifyAccountAccess(citizenid, accountId)
    -- Check if owner
    local isOwner = MySQL.scalar.await('SELECT COUNT(*) FROM bank_accounts WHERE id = ? AND owner_citizenid = ? AND is_closed = 0', {
        accountId, citizenid
    })
    if isOwner > 0 then return true end

    -- Check if shared member
    local isMember = MySQL.scalar.await('SELECT COUNT(*) FROM bank_account_members WHERE account_id = ? AND citizenid = ?', {
        accountId, citizenid
    })
    return isMember > 0
end

--- Get all accounts for a player (including shared)
---@param citizenid string
---@return table
function GetPlayerAccounts(citizenid)
    if ServerCache.accounts[citizenid] then
        return ServerCache.accounts[citizenid]
    end
    return CachePlayerAccounts(citizenid)
end

--- Cache player accounts
---@param citizenid string
---@return table
function CachePlayerAccounts(citizenid)
    local owned = MySQL.query.await([[
        SELECT a.*, 'owner' as access_role
        FROM bank_accounts a
        WHERE a.owner_citizenid = ? AND a.is_closed = 0
    ]], { citizenid })

    local shared = MySQL.query.await([[
        SELECT a.*, m.role as access_role
        FROM bank_accounts a
        JOIN bank_account_members m ON a.id = m.account_id
        WHERE m.citizenid = ? AND a.is_closed = 0
    ]], { citizenid })

    local accounts = owned or {}
    if shared then
        for _, acc in ipairs(shared) do
            accounts[#accounts + 1] = acc
        end
    end

    ServerCache.accounts[citizenid] = accounts
    return accounts
end

--- Get credit score for a citizen
---@param citizenid string
---@return number
function GetCreditScore(citizenid)
    if ServerCache.creditScores[citizenid] then
        return ServerCache.creditScores[citizenid]
    end
    local score = MySQL.scalar.await('SELECT score FROM bank_credit_scores WHERE citizenid = ?', { citizenid })
    score = score or Config.Loans.DefaultCreditScore
    ServerCache.creditScores[citizenid] = score
    return score
end

--- Update credit score
---@param citizenid string
---@param change number (positive or negative)
---@param reason string
function UpdateCreditScore(citizenid, change, reason)
    local current = GetCreditScore(citizenid)
    local newScore = math.max(0, math.min(Config.Loans.MaxCreditScore, current + change))

    MySQL.update.await('UPDATE bank_credit_scores SET score = ?, history = JSON_ARRAY_APPEND(COALESCE(history, JSON_ARRAY()), \'$\', JSON_OBJECT(\'change\', ?, \'reason\', ?, \'score\', ?, \'timestamp\', UNIX_TIMESTAMP())) WHERE citizenid = ?', {
        newScore, change, reason, newScore, citizenid
    })

    ServerCache.creditScores[citizenid] = newScore
    Utils.Debug('Credit score updated for ' .. citizenid .. ': ' .. current .. ' -> ' .. newScore .. ' (' .. reason .. ')')
end

--- Send Discord webhook log
---@param logType string
---@param message string
function LogToDiscord(logType, message)
    if not Config.Admin.DiscordWebhook or Config.Admin.DiscordWebhook == '' then return end
    if not Config.Admin.LogTypes[logType] then return end

    PerformHttpRequest(Config.Admin.DiscordWebhook, function(err, text, headers) end, 'POST',
        json.encode({
            username = Config.Admin.DiscordBotName,
            avatar_url = Config.Admin.DiscordBotAvatar,
            embeds = {{
                title = 'QB Banking - ' .. logType:upper(),
                description = message,
                color = 3447003,
                footer = { text = os.date(Config.DateFormat) },
            }}
        }),
        { ['Content-Type'] = 'application/json' }
    )
end

-- ============================================================
-- SCHEDULED TRANSFER PROCESSING
-- ============================================================

CreateThread(function()
    while true do
        Wait(60000 * 5) -- Check every 5 minutes

        if Config.Transactions.AllowScheduledTransfers then
            local pending = MySQL.query.await([[
                SELECT st.*, a.owner_citizenid, a.iban as from_iban
                FROM bank_scheduled_transfers st
                JOIN bank_accounts a ON st.from_account_id = a.id
                WHERE st.is_active = 1 AND st.next_execution <= NOW()
            ]])

            if pending then
                for _, transfer in ipairs(pending) do
                    ProcessScheduledTransfer(transfer)
                end
            end
        end
    end
end)

--- Process a scheduled transfer
---@param transfer table
function ProcessScheduledTransfer(transfer)
    local toAccount = MySQL.single.await('SELECT * FROM bank_accounts WHERE iban = ? AND is_closed = 0', { transfer.to_iban })
    if not toAccount then
        MySQL.update.await('UPDATE bank_scheduled_transfers SET is_active = 0 WHERE id = ?', { transfer.id })
        return
    end

    local fromAccount = MySQL.single.await('SELECT * FROM bank_accounts WHERE id = ?', { transfer.from_account_id })
    if not fromAccount or fromAccount.balance < transfer.amount then
        -- Insufficient funds, skip this cycle
        return
    end

    local fee = Utils.CalculateTransferFee(transfer.amount)
    local totalDeduction = transfer.amount + fee

    if fromAccount.balance < totalDeduction then return end

    local fromBalance = UpdateAccountBalance(transfer.from_account_id, totalDeduction, 'subtract')
    local toBalance = UpdateAccountBalance(toAccount.id, transfer.amount, 'add')

    RecordTransaction(transfer.from_account_id, 'transfer_out', transfer.amount, fee, 0, fromBalance,
        'Scheduled: ' .. (transfer.description or 'Transfer'), fromAccount.iban, transfer.to_iban, transfer.created_by)
    RecordTransaction(toAccount.id, 'transfer_in', transfer.amount, 0, 0, toBalance,
        'Scheduled: ' .. (transfer.description or 'Transfer'), fromAccount.iban, transfer.to_iban, transfer.created_by)

    -- Update or deactivate
    if transfer.frequency == 'once' then
        MySQL.update.await('UPDATE bank_scheduled_transfers SET is_active = 0, last_executed = NOW() WHERE id = ?', { transfer.id })
    else
        local interval = transfer.frequency == 'daily' and 1 or (transfer.frequency == 'weekly' and 7 or 30)
        MySQL.update.await('UPDATE bank_scheduled_transfers SET last_executed = NOW(), next_execution = DATE_ADD(NOW(), INTERVAL ? DAY) WHERE id = ?', {
            interval, transfer.id
        })
    end
end

--- Create scheduled transfer
RegisterNetEvent('qb-banking:server:scheduleTransfer', function(fromAccountId, toIban, amount, description, frequency, executeDate)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if not Config.Transactions.AllowScheduledTransfers then return end

    amount = tonumber(amount)
    local valid, err = Utils.ValidateAmount(amount, Config.Transactions.MinTransfer, Config.Transactions.MaxTransfer)
    if not valid then
        return TriggerClientEvent('qb-banking:client:notify', src, L(err), 'error')
    end

    if not VerifyAccountAccess(Player.PlayerData.citizenid, fromAccountId) then
        return TriggerClientEvent('qb-banking:client:notify', src, L('account_not_found'), 'error')
    end

    MySQL.insert.await('INSERT INTO bank_scheduled_transfers (from_account_id, to_iban, amount, description, frequency, next_execution, created_by) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        fromAccountId, toIban, amount, description or '', frequency or 'once', executeDate, Player.PlayerData.citizenid
    })

    TriggerClientEvent('qb-banking:client:notify', src, L('success'), 'success')
end)

Utils.Debug('QB Banking server initialized')
