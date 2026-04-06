local QBCore = exports['qb-core']:GetCoreObject()

-- ============================================================
-- ADMIN PERMISSION CHECK
-- ============================================================

--- Check if a player has admin permissions
---@param src number
---@return boolean
local function IsAdmin(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then Utils.Debug('ADMIN', 'IsAdmin: Player not found for source ' .. tostring(src)) return false end

    -- Check whitelist
    for _, cid in ipairs(Config.Admin.Whitelist) do
        if cid == Player.PlayerData.citizenid then
            Utils.Debug('ADMIN', 'IsAdmin: ' .. Player.PlayerData.citizenid .. ' authorized via whitelist')
            return true
        end
    end

    -- Check QBCore permissions
    local hasPermission = QBCore.Functions.HasPermission(src, Config.Admin.PermissionLevel)
    Utils.Debug('ADMIN', 'IsAdmin: ' .. Player.PlayerData.citizenid .. ' permission check (' .. Config.Admin.PermissionLevel .. '): ' .. tostring(hasPermission))
    return hasPermission
end

--- Log admin action
---@param adminCitizenId string
---@param action string
---@param targetCitizenId string|nil
---@param targetAccountId number|nil
---@param details table|nil
local function LogAdminAction(adminCitizenId, action, targetCitizenId, targetAccountId, details)
    Utils.Debug('ADMIN', 'LogAdminAction: admin=' .. tostring(adminCitizenId) .. ' action=' .. tostring(action) .. ' target=' .. tostring(targetCitizenId) .. ' account=' .. tostring(targetAccountId))
    if details then Utils.DebugTable('Admin action details', details) end
    MySQL.insert('INSERT INTO bank_admin_logs (admin_citizenid, action, target_citizenid, target_account_id, details) VALUES (?, ?, ?, ?, ?)', {
        adminCitizenId, action, targetCitizenId, targetAccountId, details and json.encode(details) or nil
    })
    LogToDiscord('admin', string.format('**Admin Action** | Admin: %s | Action: %s | Target: %s',
        adminCitizenId, action, targetCitizenId or 'N/A'))
end

-- ============================================================
-- ADMIN CALLBACKS
-- ============================================================

--- Get admin overview data
QBCore.Functions.CreateCallback('qb-banking:server:admin:getOverview', function(source, cb)
    Utils.Debug('ADMIN', 'getOverview called by source ' .. tostring(source))
    if not IsAdmin(source) then Utils.Debug('ADMIN', 'getOverview: Not admin') return cb(nil) end

    local totalAccounts = MySQL.scalar.await('SELECT COUNT(*) FROM bank_accounts WHERE is_closed = 0')
    local totalBalance = MySQL.scalar.await('SELECT COALESCE(SUM(balance), 0) FROM bank_accounts WHERE is_closed = 0')
    local activeLoans = MySQL.scalar.await('SELECT COUNT(*) FROM bank_loans WHERE status = ?', { 'active' })
    local totalLoanValue = MySQL.scalar.await('SELECT COALESCE(SUM(total_amount - amount_paid), 0) FROM bank_loans WHERE status = ?', { 'active' })
    local pendingInvoices = MySQL.scalar.await('SELECT COUNT(*) FROM bank_invoices WHERE status IN (?, ?)', { 'pending', 'overdue' })
    local todayTransactions = MySQL.scalar.await('SELECT COUNT(*) FROM bank_transactions WHERE DATE(created_at) = CURDATE()')
    local todayVolume = MySQL.scalar.await('SELECT COALESCE(SUM(amount), 0) FROM bank_transactions WHERE DATE(created_at) = CURDATE()')
    local totalTaxCollected = MySQL.scalar.await('SELECT COALESCE(SUM(amount), 0) FROM bank_tax_records')

    Utils.Debug('ADMIN', 'Overview: accounts=' .. tostring(totalAccounts) .. ' balance=' .. tostring(totalBalance) .. ' loans=' .. tostring(activeLoans) .. ' invoices=' .. tostring(pendingInvoices) .. ' txToday=' .. tostring(todayTransactions))
    cb({
        totalAccounts = totalAccounts or 0,
        totalBalance = totalBalance or 0,
        activeLoans = activeLoans or 0,
        totalLoanValue = totalLoanValue or 0,
        pendingInvoices = pendingInvoices or 0,
        todayTransactions = todayTransactions or 0,
        todayVolume = todayVolume or 0,
        totalTaxCollected = totalTaxCollected or 0,
    })
end)

--- Search accounts (admin)
QBCore.Functions.CreateCallback('qb-banking:server:admin:searchAccounts', function(source, cb, searchQuery)
    Utils.Debug('ADMIN', 'searchAccounts: query="' .. tostring(searchQuery) .. '" by source ' .. tostring(source))
    if not IsAdmin(source) then return cb({}) end

    local accounts = MySQL.query.await([[
        SELECT a.*, COUNT(t.id) as transaction_count
        FROM bank_accounts a
        LEFT JOIN bank_transactions t ON a.id = t.account_id
        WHERE a.iban LIKE ? OR a.owner_citizenid LIKE ? OR a.account_name LIKE ?
        GROUP BY a.id
        ORDER BY a.created_at DESC
        LIMIT 50
    ]], {
        '%' .. searchQuery .. '%',
        '%' .. searchQuery .. '%',
        '%' .. searchQuery .. '%',
    })

    Utils.Debug('ADMIN', 'searchAccounts: returning ' .. #(accounts or {}) .. ' results')
    cb(accounts or {})
end)

--- Get admin logs
QBCore.Functions.CreateCallback('qb-banking:server:admin:getLogs', function(source, cb, page)
    Utils.Debug('ADMIN', 'getLogs: page=' .. tostring(page) .. ' by source ' .. tostring(source))
    if not IsAdmin(source) then return cb({}) end

    local limit = 25
    local offset = ((page or 1) - 1) * limit

    local logs = MySQL.query.await([[
        SELECT * FROM bank_admin_logs ORDER BY created_at DESC LIMIT ? OFFSET ?
    ]], { limit, offset })

    local total = MySQL.scalar.await('SELECT COUNT(*) FROM bank_admin_logs')

    cb({
        logs = logs or {},
        total = total or 0,
        page = page or 1,
    })
end)

-- ============================================================
-- ADMIN COMMANDS
-- ============================================================

--- Set account balance
RegisterNetEvent('qb-banking:server:admin:setBalance', function(accountId, amount)
    local src = source
    Utils.Debug('ADMIN', 'setBalance request: account=' .. tostring(accountId) .. ' amount=' .. tostring(amount) .. ' by source ' .. tostring(src))
    if not IsAdmin(src) then
        Utils.Debug('ADMIN', 'setBalance: Not admin')
        return TriggerClientEvent('qb-banking:client:notify', src, L('admin_no_permission'), 'error')
    end

    local Player = QBCore.Functions.GetPlayer(src)
    amount = tonumber(amount)
    if not amount or amount < 0 then Utils.Debug('ADMIN', 'setBalance: Invalid amount') return end

    local account = MySQL.single.await('SELECT * FROM bank_accounts WHERE id = ?', { accountId })
    if not account then Utils.Debug('ADMIN', 'setBalance: Account not found') return end

    Utils.Debug('ADMIN', 'setBalance: ' .. tostring(account.iban) .. ' old=' .. tostring(account.balance) .. ' new=' .. tostring(amount))
    MySQL.update.await('UPDATE bank_accounts SET balance = ? WHERE id = ?', { amount, accountId })
    RecordTransaction(accountId, 'admin_adjust', amount, 0, 0, amount,
        'Admin balance adjustment', nil, nil, Player.PlayerData.citizenid)

    LogAdminAction(Player.PlayerData.citizenid, 'set_balance', account.owner_citizenid, accountId,
        { old_balance = account.balance, new_balance = amount })

    TriggerClientEvent('qb-banking:client:notify', src,
        L('admin_balance_set', Utils.FormatMoney(amount), account.iban), 'success')
end)

--- Freeze / Unfreeze account
RegisterNetEvent('qb-banking:server:admin:toggleFreeze', function(accountId)
    local src = source
    Utils.Debug('ADMIN', 'toggleFreeze request: account=' .. tostring(accountId) .. ' by source ' .. tostring(src))
    if not IsAdmin(src) then
        return TriggerClientEvent('qb-banking:client:notify', src, L('admin_no_permission'), 'error')
    end

    local Player = QBCore.Functions.GetPlayer(src)
    local account = MySQL.single.await('SELECT * FROM bank_accounts WHERE id = ?', { accountId })
    if not account then Utils.Debug('ADMIN', 'toggleFreeze: Account not found') return end

    local newState = account.is_frozen == 1 and 0 or 1
    Utils.Debug('ADMIN', 'toggleFreeze: account ' .. tostring(account.iban) .. ' frozen: ' .. tostring(account.is_frozen) .. ' -> ' .. tostring(newState))
    MySQL.update.await('UPDATE bank_accounts SET is_frozen = ? WHERE id = ?', { newState, accountId })

    LogAdminAction(Player.PlayerData.citizenid, newState == 1 and 'freeze_account' or 'unfreeze_account',
        account.owner_citizenid, accountId)

    TriggerClientEvent('qb-banking:client:notify', src, L('success'), 'success')
end)

--- Clear a loan (admin override)
RegisterNetEvent('qb-banking:server:admin:clearLoan', function(loanId)
    local src = source
    Utils.Debug('ADMIN', 'clearLoan request: loan=' .. tostring(loanId) .. ' by source ' .. tostring(src))
    if not IsAdmin(src) then
        return TriggerClientEvent('qb-banking:client:notify', src, L('admin_no_permission'), 'error')
    end

    local Player = QBCore.Functions.GetPlayer(src)
    local loan = MySQL.single.await('SELECT * FROM bank_loans WHERE id = ?', { loanId })
    if not loan then Utils.Debug('ADMIN', 'clearLoan: Loan not found') return end
    Utils.Debug('ADMIN', 'clearLoan: Clearing loan #' .. tostring(loanId) .. ' for ' .. tostring(loan.citizenid) .. ' amount=' .. tostring(loan.total_amount))

    MySQL.update.await('UPDATE bank_loans SET status = ?, amount_paid = total_amount + late_fees WHERE id = ?', {
        'paid', loanId
    })

    LogAdminAction(Player.PlayerData.citizenid, 'clear_loan', loan.citizenid, nil,
        { loan_id = loanId, amount = loan.total_amount })

    TriggerClientEvent('qb-banking:client:notify', src, L('admin_loan_cleared', loan.citizenid), 'success')
end)

--- Adjust credit score
RegisterNetEvent('qb-banking:server:admin:setCreditScore', function(targetCitizenId, newScore)
    local src = source
    Utils.Debug('ADMIN', 'setCreditScore request: target=' .. tostring(targetCitizenId) .. ' score=' .. tostring(newScore) .. ' by source ' .. tostring(src))
    if not IsAdmin(src) then
        return TriggerClientEvent('qb-banking:client:notify', src, L('admin_no_permission'), 'error')
    end

    local Player = QBCore.Functions.GetPlayer(src)
    newScore = tonumber(newScore)
    if not newScore then Utils.Debug('ADMIN', 'setCreditScore: Invalid score') return end
    newScore = math.max(0, math.min(Config.Loans.MaxCreditScore, newScore))
    Utils.Debug('ADMIN', 'setCreditScore: Setting ' .. tostring(targetCitizenId) .. ' score to ' .. tostring(newScore))

    MySQL.update.await('UPDATE bank_credit_scores SET score = ? WHERE citizenid = ?', { newScore, targetCitizenId })
    ServerCache.creditScores[targetCitizenId] = newScore

    LogAdminAction(Player.PlayerData.citizenid, 'set_credit_score', targetCitizenId, nil,
        { new_score = newScore })

    TriggerClientEvent('qb-banking:client:notify', src, L('success'), 'success')
end)

--- Cancel invoice (admin)
RegisterNetEvent('qb-banking:server:admin:cancelInvoice', function(invoiceId)
    local src = source
    Utils.Debug('ADMIN', 'cancelInvoice request: invoice=' .. tostring(invoiceId) .. ' by source ' .. tostring(src))
    if not IsAdmin(src) then
        return TriggerClientEvent('qb-banking:client:notify', src, L('admin_no_permission'), 'error')
    end

    local Player = QBCore.Functions.GetPlayer(src)
    local invoice = MySQL.single.await('SELECT * FROM bank_invoices WHERE id = ?', { invoiceId })
    if not invoice then Utils.Debug('ADMIN', 'cancelInvoice: Invoice not found') return end
    Utils.Debug('ADMIN', 'cancelInvoice: Cancelling invoice #' .. tostring(invoiceId) .. ' amount=' .. tostring(invoice.amount))

    MySQL.update.await('UPDATE bank_invoices SET status = ? WHERE id = ?', { 'cancelled', invoiceId })

    LogAdminAction(Player.PlayerData.citizenid, 'cancel_invoice', invoice.to_citizenid, nil,
        { invoice_id = invoiceId, amount = invoice.amount })

    TriggerClientEvent('qb-banking:client:notify', src, L('success'), 'success')
end)

-- ============================================================
-- CHAT COMMANDS
-- ============================================================

QBCore.Commands.Add('bankadmin', 'Open bank admin panel', {}, false, function(source)
    Utils.Debug('ADMIN', '/bankadmin command by source ' .. tostring(source))
    if not IsAdmin(source) then
        return TriggerClientEvent('qb-banking:client:notify', source, L('admin_no_permission'), 'error')
    end
    TriggerClientEvent('qb-banking:client:openAdmin', source)
end, Config.Admin.PermissionLevel)

QBCore.Commands.Add('setbalance', 'Set a bank account balance', {
    { name = 'iban', help = 'Account IBAN' },
    { name = 'amount', help = 'New balance amount' },
}, false, function(source, args)
    Utils.Debug('ADMIN', '/setbalance command: iban=' .. tostring(args[1]) .. ' amount=' .. tostring(args[2]))
    if not IsAdmin(source) then
        return TriggerClientEvent('qb-banking:client:notify', source, L('admin_no_permission'), 'error')
    end

    local iban = args[1]
    local amount = tonumber(args[2])
    if not iban or not amount then Utils.Debug('ADMIN', '/setbalance: Missing args') return end

    local account = MySQL.single.await('SELECT * FROM bank_accounts WHERE iban = ?', { iban })
    if not account then
        return TriggerClientEvent('qb-banking:client:notify', source, L('account_not_found'), 'error')
    end

    TriggerEvent('qb-banking:server:admin:setBalance', account.id, amount)
end, Config.Admin.PermissionLevel)

QBCore.Commands.Add('clearloan', 'Clear a player loan', {
    { name = 'loanId', help = 'Loan ID' },
}, false, function(source, args)
    Utils.Debug('ADMIN', '/clearloan command: loanId=' .. tostring(args[1]))
    if not IsAdmin(source) then
        return TriggerClientEvent('qb-banking:client:notify', source, L('admin_no_permission'), 'error')
    end

    local loanId = tonumber(args[1])
    if not loanId then Utils.Debug('ADMIN', '/clearloan: Missing loanId') return end

    TriggerEvent('qb-banking:server:admin:clearLoan', loanId)
end, Config.Admin.PermissionLevel)

QBCore.Commands.Add('setcredit', 'Set a player credit score', {
    { name = 'citizenid', help = 'Citizen ID' },
    { name = 'score', help = 'New credit score' },
}, false, function(source, args)
    Utils.Debug('ADMIN', '/setcredit command: citizenid=' .. tostring(args[1]) .. ' score=' .. tostring(args[2]))
    if not IsAdmin(source) then
        return TriggerClientEvent('qb-banking:client:notify', source, L('admin_no_permission'), 'error')
    end

    local citizenid = args[1]
    local score = tonumber(args[2])
    if not citizenid or not score then Utils.Debug('ADMIN', '/setcredit: Missing args') return end

    TriggerEvent('qb-banking:server:admin:setCreditScore', citizenid, score)
end, Config.Admin.PermissionLevel)

Utils.Debug('QB Banking admin module initialized')
