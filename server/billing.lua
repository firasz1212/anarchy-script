local QBCore = exports['qb-core']:GetCoreObject()

-- ============================================================
-- INVOICE CALLBACKS
-- ============================================================

--- Get invoices for a player (sent and received)
QBCore.Functions.CreateCallback('qb-banking:server:getInvoices', function(source, cb, filter)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then Utils.Debug('BILLING', 'getInvoices: Player not found') return cb({}) end

    Utils.Debug('BILLING', 'getInvoices called by ' .. Player.PlayerData.citizenid .. ' filter=' .. tostring(filter))
    if not Config.Billing.Enabled then Utils.Debug('BILLING', 'Billing system disabled') return cb({}) end

    local citizenid = Player.PlayerData.citizenid

    local received = MySQL.query.await([[
        SELECT * FROM bank_invoices WHERE to_citizenid = ? ORDER BY created_at DESC LIMIT 50
    ]], { citizenid })

    local sent = MySQL.query.await([[
        SELECT * FROM bank_invoices WHERE from_citizenid = ? ORDER BY created_at DESC LIMIT 50
    ]], { citizenid })

    Utils.Debug('BILLING', 'Returning invoices: received=' .. #(received or {}) .. ' sent=' .. #(sent or {}))
    cb({
        received = received or {},
        sent = sent or {},
        categories = Config.Billing.Categories,
    })
end)

-- ============================================================
-- SEND INVOICE
-- ============================================================

RegisterNetEvent('qb-banking:server:sendInvoice', function(targetCitizenId, amount, category, description)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then Utils.Debug('BILLING', 'sendInvoice: Player not found') return end

    Utils.Debug('BILLING', 'Send invoice: target=' .. tostring(targetCitizenId) .. ' amount=' .. tostring(amount) .. ' category=' .. tostring(category))
    if not Config.Billing.Enabled then Utils.Debug('BILLING', 'Billing system disabled') return end

    local citizenid = Player.PlayerData.citizenid
    local jobName = Player.PlayerData.job.name
    Utils.Debug('BILLING', 'Sender job: ' .. tostring(jobName))
    amount = tonumber(amount)

    -- Validate the sender is authorized
    local isAuthorized = false
    local maxAmount = math.huge

    Utils.Debug('BILLING', 'Checking authorization for job: ' .. tostring(jobName))
    if Config.Billing.AuthorizedJobs[jobName] then
        local jobConfig = Config.Billing.AuthorizedJobs[jobName]
        isAuthorized = true
        maxAmount = jobConfig.maxAmount

        -- Check if category is allowed for this job
        local categoryAllowed = false
        for _, cat in ipairs(jobConfig.categories) do
            if cat == category then
                categoryAllowed = true
                break
            end
        end
        if not categoryAllowed then
            return TriggerClientEvent('qb-banking:client:notify', src, L('invoice_not_authorized'), 'error')
        end
    end

    -- Allow player-to-player invoices (no job required) with a general limit
    if not isAuthorized then
        maxAmount = 100000 -- Default max for non-job invoices
    end

    local valid, err = Utils.ValidateAmount(amount, 1, maxAmount)
    if not valid then
        return TriggerClientEvent('qb-banking:client:notify', src, L(err), 'error')
    end

    -- Generate invoice number
    local invoiceNumber = 'INV-' .. os.time() .. '-' .. math.random(1000, 9999)
    Utils.Debug('BILLING', 'Invoice created: ' .. invoiceNumber .. ' from=' .. citizenid .. ' to=' .. tostring(targetCitizenId) .. ' amount=' .. tostring(amount))

    -- Calculate due date
    local dueDate = os.date('%Y-%m-%d %H:%M:%S', os.time() + (Config.Billing.OverdueAfterHours * 3600))

    MySQL.insert.await([[
        INSERT INTO bank_invoices (invoice_number, from_citizenid, from_job, to_citizenid, amount, category, description, due_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        invoiceNumber, citizenid, jobName, targetCitizenId, amount, category or 'other',
        description or '', dueDate
    })

    TriggerClientEvent('qb-banking:client:notify', src, L('invoice_sent', targetCitizenId), 'success')

    -- Notify recipient if online
    local targetPlayer = QBCore.Functions.GetPlayerByCitizenId(targetCitizenId)
    if targetPlayer then
        TriggerClientEvent('qb-banking:client:notify', targetPlayer.PlayerData.source,
            L('invoice_received', Utils.FormatMoney(amount)), 'info')
    end

    LogToDiscord('billing', string.format('**Invoice Sent** | %s sent %s invoice to %s (Category: %s)',
        citizenid, Utils.FormatMoney(amount), targetCitizenId, category))
end)

-- ============================================================
-- PAY INVOICE
-- ============================================================

RegisterNetEvent('qb-banking:server:payInvoice', function(invoiceId, accountId, amount)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then Utils.Debug('BILLING', 'payInvoice: Player not found') return end

    local citizenid = Player.PlayerData.citizenid
    Utils.Debug('BILLING', 'Pay invoice: id=' .. tostring(invoiceId) .. ' account=' .. tostring(accountId) .. ' amount=' .. tostring(amount) .. ' by ' .. citizenid)

    local invoice = MySQL.single.await('SELECT * FROM bank_invoices WHERE id = ? AND to_citizenid = ? AND status IN (?, ?)', {
        invoiceId, citizenid, 'pending', 'overdue'
    })

    if not invoice then
        return TriggerClientEvent('qb-banking:client:notify', src, L('error'), 'error')
    end

    amount = tonumber(amount)
    local remaining = invoice.amount - invoice.amount_paid

    Utils.Debug('BILLING', 'Invoice remaining: ' .. tostring(remaining) .. ' (total=' .. tostring(invoice.amount) .. ' paid=' .. tostring(invoice.amount_paid) .. ')')
    -- Handle partial payments
    if Config.Billing.AllowPartialPayments and amount < remaining then
        if amount < Config.Billing.MinPartialPayment then
            return TriggerClientEvent('qb-banking:client:notify', src, L('amount_too_low'), 'error')
        end
    else
        amount = remaining
    end

    -- Check account balance
    if not VerifyAccountAccess(citizenid, accountId) then
        return TriggerClientEvent('qb-banking:client:notify', src, L('account_not_found'), 'error')
    end

    local account = MySQL.single.await('SELECT balance FROM bank_accounts WHERE id = ?', { accountId })
    if not account or account.balance < amount then
        return TriggerClientEvent('qb-banking:client:notify', src, L('account_insufficient_funds'), 'error')
    end

    -- Process payment
    Utils.Debug('BILLING', 'Processing invoice payment: ' .. tostring(amount) .. ' from account ' .. tostring(accountId))
    local newBalance = UpdateAccountBalance(accountId, amount, 'subtract')
    RecordTransaction(accountId, 'invoice_payment', amount, 0, 0, newBalance,
        'Invoice #' .. invoice.invoice_number, nil, nil, citizenid)

    local newAmountPaid = invoice.amount_paid + amount
    local status = newAmountPaid >= invoice.amount and 'paid' or 'partial'
    Utils.Debug('BILLING', 'Invoice payment: newAmountPaid=' .. tostring(newAmountPaid) .. ' status=' .. status)

    MySQL.update.await('UPDATE bank_invoices SET amount_paid = ?, status = ? WHERE id = ?', {
        newAmountPaid, status, invoiceId
    })

    -- Credit the sender's primary account
    local senderAccount = MySQL.single.await([[
        SELECT id FROM bank_accounts WHERE owner_citizenid = ? AND account_type = 'personal' AND is_closed = 0 LIMIT 1
    ]], { invoice.from_citizenid })

    if senderAccount then
        local senderBalance = UpdateAccountBalance(senderAccount.id, amount, 'add')
        RecordTransaction(senderAccount.id, 'invoice_income', amount, 0, 0, senderBalance,
            'Invoice #' .. invoice.invoice_number .. ' payment', nil, nil, citizenid)
    end

    -- Update credit score
    local isOverdue = invoice.status == 'overdue'
    if isOverdue then
        UpdateCreditScore(citizenid, Config.Loans.CreditScoreChanges.InvoicePaidLate, 'Late invoice payment')
    else
        UpdateCreditScore(citizenid, Config.Loans.CreditScoreChanges.InvoicePaidOnTime, 'On-time invoice payment')
    end

    if status == 'paid' then
        TriggerClientEvent('qb-banking:client:notify', src, L('invoice_paid', Utils.FormatMoney(amount)), 'success')
    else
        TriggerClientEvent('qb-banking:client:notify', src, L('invoice_partial', Utils.FormatMoney(amount)), 'info')
    end

    TriggerClientEvent('qb-banking:client:refreshAccounts', src)

    LogToDiscord('billing', string.format('**Invoice Paid** | %s paid %s on invoice #%s (Status: %s)',
        citizenid, Utils.FormatMoney(amount), invoice.invoice_number, status))
end)

-- ============================================================
-- INVOICE REMINDERS & OVERDUE PROCESSING
-- ============================================================

CreateThread(function()
    while true do
        Wait(60000 * 30) -- Check every 30 minutes

        if not Config.Billing.Enabled then goto continue end

        Utils.Debug('BILLING', 'Running invoice reminder & overdue check')
        -- Send reminders for pending invoices
        local remindableInvoices = MySQL.query.await([[
            SELECT * FROM bank_invoices
            WHERE status = 'pending'
            AND reminder_sent = 0
            AND created_at <= DATE_SUB(NOW(), INTERVAL ? HOUR)
        ]], { Config.Billing.AutoReminderHours })

        if remindableInvoices and #remindableInvoices > 0 then
            Utils.Debug('BILLING', 'Sending reminders for ' .. #remindableInvoices .. ' invoices')
            for _, invoice in ipairs(remindableInvoices) do
                -- Mark reminder sent
                MySQL.update.await('UPDATE bank_invoices SET reminder_sent = 1 WHERE id = ?', { invoice.id })

                -- Notify player if online
                local player = QBCore.Functions.GetPlayerByCitizenId(invoice.to_citizenid)
                if player then
                    TriggerClientEvent('qb-banking:client:notify', player.PlayerData.source,
                        L('invoice_reminder', invoice.invoice_number), 'warning')
                end
            end
        end

        -- Mark overdue invoices
        local overdueInvoices = MySQL.query.await([[
            SELECT * FROM bank_invoices
            WHERE status = 'pending'
            AND due_date <= NOW()
        ]])

        if overdueInvoices and #overdueInvoices > 0 then
            Utils.Debug('BILLING', 'Marking ' .. #overdueInvoices .. ' invoices as overdue')
            for _, invoice in ipairs(overdueInvoices) do
                local penaltyAmount = 0
                if not invoice.penalty_applied or invoice.penalty_applied == 0 then
                    penaltyAmount = invoice.amount * (Config.Billing.OverduePenaltyPercent / 100)
                    penaltyAmount = Utils.Round(penaltyAmount)
                end

                MySQL.update.await([[
                    UPDATE bank_invoices
                    SET status = 'overdue', amount = amount + ?, penalty_applied = 1
                    WHERE id = ?
                ]], { penaltyAmount, invoice.id })

                local player = QBCore.Functions.GetPlayerByCitizenId(invoice.to_citizenid)
                if player then
                    TriggerClientEvent('qb-banking:client:notify', player.PlayerData.source, L('invoice_overdue'), 'error')
                end
            end
        end

        ::continue::
    end
end)

Utils.Debug('QB Banking billing module initialized')
