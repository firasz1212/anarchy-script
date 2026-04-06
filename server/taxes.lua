local QBCore = exports['qb-core']:GetCoreObject()

-- ============================================================
-- TAX CALLBACKS
-- ============================================================

--- Get tax records for a player
QBCore.Functions.CreateCallback('qb-banking:server:getTaxRecords', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb({}) end

    if not Config.Taxes.Enabled then return cb({}) end

    local records = MySQL.query.await([[
        SELECT * FROM bank_tax_records WHERE citizenid = ? ORDER BY created_at DESC LIMIT 50
    ]], { Player.PlayerData.citizenid })

    -- Calculate tax summary
    local summary = MySQL.query.await([[
        SELECT
            tax_type,
            COALESCE(SUM(amount), 0) as total_paid,
            COUNT(*) as count
        FROM bank_tax_records
        WHERE citizenid = ?
        GROUP BY tax_type
    ]], { Player.PlayerData.citizenid })

    cb({
        records = records or {},
        summary = summary or {},
        taxConfig = {
            incomeTax = Config.Taxes.IncomeTax,
            transactionTax = Config.Taxes.TransactionTax,
            businessTax = Config.Taxes.BusinessTax,
        },
    })
end)

-- ============================================================
-- INCOME TAX (Applied on job paychecks)
-- ============================================================

--- Hook into QBCore paycheck to apply income tax
RegisterNetEvent('qb-banking:server:onDeposit', function(citizenid, amount)
    -- This is triggered on deposits; income tax specifically on paychecks
    -- We track large deposits for credit score
    if amount >= 10000 then
        UpdateCreditScore(citizenid, Config.Loans.CreditScoreChanges.LargeDeposit, 'Large deposit')
    end
end)

--- Apply income tax on paycheck
---@param citizenid string
---@param amount number
---@return number taxAmount
function ApplyIncomeTax(citizenid, amount)
    if not Config.Taxes.Enabled or not Config.Taxes.IncomeTax.Enabled then
        return 0
    end

    local player = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if player and Utils.IsJobTaxExempt(player.PlayerData.job.name) then
        return 0
    end

    local tax = Utils.CalculateIncomeTax(amount)
    if tax <= 0 then return 0 end

    -- Record tax
    RecordTax(citizenid, nil, 'income', tax, amount, 0, 'Income tax on paycheck')

    -- Deduct from primary account
    local account = MySQL.single.await([[
        SELECT id, balance FROM bank_accounts
        WHERE owner_citizenid = ? AND account_type = 'personal' AND is_closed = 0
        ORDER BY id ASC LIMIT 1
    ]], { citizenid })

    if account and account.balance >= tax then
        local newBalance = UpdateAccountBalance(account.id, tax, 'subtract')
        RecordTransaction(account.id, 'tax_deduction', tax, 0, 0, newBalance, 'Income tax', nil, nil, 'system')

        if player then
            TriggerClientEvent('qb-banking:client:notify', player.PlayerData.source,
                L('tax_collected', Utils.FormatMoney(tax), L('tax_income')), 'info')
        end
    end

    LogToDiscord('taxes', string.format('**Income Tax** | %s: %s tax on %s income',
        citizenid, Utils.FormatMoney(tax), Utils.FormatMoney(amount)))

    return tax
end

-- Export for other resources to call
exports('ApplyIncomeTax', ApplyIncomeTax)

-- ============================================================
-- BUSINESS TAX (Periodic collection on business accounts)
-- ============================================================

CreateThread(function()
    while true do
        Wait(60000 * 60) -- Check every hour

        if not Config.Taxes.Enabled or not Config.Taxes.BusinessTax.Enabled then goto continue end
        if not Config.Taxes.AutoCollect then goto continue end

        -- Get all business accounts with revenue above minimum
        local businessAccounts = MySQL.query.await([[
            SELECT
                a.id, a.owner_citizenid, a.balance,
                COALESCE(SUM(CASE WHEN t.type IN ('deposit', 'transfer_in', 'invoice_income') THEN t.amount ELSE 0 END), 0) as period_revenue
            FROM bank_accounts a
            LEFT JOIN bank_transactions t ON a.id = t.account_id
                AND t.created_at >= DATE_SUB(NOW(), INTERVAL ? HOUR)
            WHERE a.account_type = 'business' AND a.is_closed = 0
            GROUP BY a.id
            HAVING period_revenue >= ?
        ]], { Config.Taxes.BusinessTax.CollectionInterval, Config.Taxes.BusinessTax.MinRevenue })

        if businessAccounts then
            for _, account in ipairs(businessAccounts) do
                local tax = Utils.Round(account.period_revenue * Config.Taxes.BusinessTax.Rate / 100)
                if tax > 0 and account.balance >= tax then
                    local newBalance = UpdateAccountBalance(account.id, tax, 'subtract')
                    RecordTransaction(account.id, 'tax_deduction', tax, 0, 0, newBalance,
                        'Business tax', nil, nil, 'system')
                    RecordTax(account.owner_citizenid, account.id, 'business', tax,
                        account.period_revenue, Config.Taxes.BusinessTax.Rate, 'Periodic business tax')

                    local player = QBCore.Functions.GetPlayerByCitizenId(account.owner_citizenid)
                    if player then
                        TriggerClientEvent('qb-banking:client:notify', player.PlayerData.source,
                            L('tax_collected', Utils.FormatMoney(tax), L('tax_business')), 'info')
                    end

                    LogToDiscord('taxes', string.format('**Business Tax** | Account #%d: %s tax on %s revenue',
                        account.id, Utils.FormatMoney(tax), Utils.FormatMoney(account.period_revenue)))
                end
            end
        end

        ::continue::
    end
end)

-- ============================================================
-- TAX CLEANUP
-- ============================================================

CreateThread(function()
    while true do
        Wait(60000 * 60 * 24) -- Run once a day

        if Config.Taxes.TaxLogRetentionDays > 0 then
            MySQL.query.await('DELETE FROM bank_tax_records WHERE created_at < DATE_SUB(NOW(), INTERVAL ? DAY)', {
                Config.Taxes.TaxLogRetentionDays
            })
            Utils.Debug('Cleaned up old tax records')
        end
    end
end)

Utils.Debug('QB Banking taxes module initialized')
