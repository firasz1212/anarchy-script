local QBCore = exports['qb-core']:GetCoreObject()

-- ============================================================
-- LOAN CALLBACKS
-- ============================================================

--- Get available loan plans for a player
QBCore.Functions.CreateCallback('qb-banking:server:getLoanPlans', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then Utils.Debug('LOAN', 'getLoanPlans: Player not found') return cb({}) end

    Utils.Debug('LOAN', 'getLoanPlans called by ' .. Player.PlayerData.citizenid)
    if not Config.Loans.Enabled then Utils.Debug('LOAN', 'Loan system disabled') return cb({}) end

    local creditScore = GetCreditScore(Player.PlayerData.citizenid)
    Utils.Debug('LOAN', 'Player credit score: ' .. tostring(creditScore))
    local plans = {}

    for _, plan in ipairs(Config.Loans.Plans) do
        local planCopy = Utils.DeepCopy(plan)
        planCopy.eligible = creditScore >= plan.minCreditScore
        planCopy.playerCreditScore = creditScore
        Utils.Debug('LOAN', 'Plan ' .. plan.id .. ': eligible=' .. tostring(planCopy.eligible) .. ' (requires ' .. tostring(plan.minCreditScore) .. ')')
        plans[#plans + 1] = planCopy
    end

    Utils.Debug('LOAN', 'Returning ' .. #plans .. ' loan plans')
    cb(plans)
end)

--- Get active loans for a player
QBCore.Functions.CreateCallback('qb-banking:server:getLoans', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then Utils.Debug('LOAN', 'getLoans: Player not found') return cb({}) end
    Utils.Debug('LOAN', 'getLoans called by ' .. Player.PlayerData.citizenid)

    local loans = MySQL.query.await([[
        SELECT l.*, a.iban as account_iban
        FROM bank_loans l
        JOIN bank_accounts a ON l.account_id = a.id
        WHERE l.citizenid = ?
        ORDER BY l.created_at DESC
    ]], { Player.PlayerData.citizenid })

    Utils.Debug('LOAN', 'Returning ' .. #(loans or {}) .. ' loans for ' .. Player.PlayerData.citizenid)
    cb(loans or {})
end)

-- ============================================================
-- LOAN APPLICATION
-- ============================================================

RegisterNetEvent('qb-banking:server:applyLoan', function(planId, amount, accountId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then Utils.Debug('LOAN', 'applyLoan: Player not found') return end

    Utils.Debug('LOAN', 'Loan application: plan=' .. tostring(planId) .. ' amount=' .. tostring(amount) .. ' account=' .. tostring(accountId) .. ' by source ' .. tostring(src))
    if not Config.Loans.Enabled then
        Utils.Debug('LOAN', 'Loan system disabled')
        return TriggerClientEvent('qb-banking:client:notify', src, L('error'), 'error')
    end

    local citizenid = Player.PlayerData.citizenid

    -- Find the loan plan
    local plan = nil
    for _, p in ipairs(Config.Loans.Plans) do
        if p.id == planId then
            plan = p
            break
        end
    end

    if not plan then
        return TriggerClientEvent('qb-banking:client:notify', src, L('error'), 'error')
    end

    -- Validate amount
    amount = tonumber(amount)
    local valid, err = Utils.ValidateAmount(amount, plan.minAmount, plan.maxAmount)
    if not valid then
        return TriggerClientEvent('qb-banking:client:notify', src, L(err), 'error')
    end

    -- Check account access
    if not VerifyAccountAccess(citizenid, accountId) then
        return TriggerClientEvent('qb-banking:client:notify', src, L('account_not_found'), 'error')
    end

    -- Check credit score
    local creditScore = GetCreditScore(citizenid)
    Utils.Debug('LOAN', 'Credit score check: player=' .. tostring(creditScore) .. ' required=' .. tostring(plan.minCreditScore))
    if creditScore < plan.minCreditScore then
        Utils.Debug('LOAN', 'REJECTED: Credit score too low')
        return TriggerClientEvent('qb-banking:client:notify', src, L('credit_score_low'), 'error')
    end

    -- Check active loan limit
    local activeLoans = MySQL.scalar.await('SELECT COUNT(*) FROM bank_loans WHERE citizenid = ? AND status = ?', {
        citizenid, 'active'
    })
    Utils.Debug('LOAN', 'Active loans: ' .. tostring(activeLoans) .. '/' .. tostring(Config.Loans.MaxActiveLoans))
    if activeLoans >= Config.Loans.MaxActiveLoans then
        Utils.Debug('LOAN', 'REJECTED: Loan limit reached')
        return TriggerClientEvent('qb-banking:client:notify', src, L('loan_limit_reached'), 'error')
    end

    -- Calculate loan details
    local details = Utils.CalculateLoanDetails(plan, amount)
    Utils.Debug('LOAN', 'Loan details: principal=' .. tostring(details.principal) .. ' interest=' .. tostring(details.interest) .. ' total=' .. tostring(details.totalAmount) .. ' installments=' .. tostring(details.installments))

    -- Calculate first payment due date
    local intervalDays = math.ceil(plan.durationDays / plan.installments)
    local nextPaymentDue = os.date('%Y-%m-%d %H:%M:%S', os.time() + (intervalDays * 86400))

    -- Create loan
    local loanId = MySQL.insert.await([[
        INSERT INTO bank_loans (account_id, citizenid, plan_id, principal, interest, total_amount, installments_total, installment_amount, next_payment_due, auto_repay)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        accountId, citizenid, plan.id, details.principal, details.interest, details.totalAmount,
        details.installments, details.installmentAmount, nextPaymentDue, plan.autoRepay and 1 or 0
    })

    -- Deposit loan amount to account
    local newBalance = UpdateAccountBalance(accountId, amount, 'add')
    RecordTransaction(accountId, 'loan_deposit', amount, 0, 0, newBalance, 'Loan disbursement: ' .. plan.label, nil, nil, citizenid)
    Utils.Debug('LOAN', 'APPROVED: Loan #' .. tostring(loanId) .. ' disbursed ' .. tostring(amount) .. ' to account ' .. tostring(accountId) .. ' (newBalance=' .. tostring(newBalance) .. ')')

    TriggerClientEvent('qb-banking:client:notify', src, L('loan_approved', Utils.FormatMoney(amount)), 'success')
    TriggerClientEvent('qb-banking:client:refreshAccounts', src)

    LogToDiscord('loans', string.format('**Loan Approved** | %s received %s loan (%s plan, %s%% interest, %d installments)',
        citizenid, Utils.FormatMoney(amount), plan.label, plan.interestRate, plan.installments))
end)

-- ============================================================
-- LOAN REPAYMENT
-- ============================================================

RegisterNetEvent('qb-banking:server:repayLoan', function(loanId, amount, accountId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then Utils.Debug('LOAN', 'repayLoan: Player not found') return end

    local citizenid = Player.PlayerData.citizenid
    Utils.Debug('LOAN', 'Repay request: loan=' .. tostring(loanId) .. ' amount=' .. tostring(amount) .. ' account=' .. tostring(accountId) .. ' by ' .. citizenid)

    local loan = MySQL.single.await('SELECT * FROM bank_loans WHERE id = ? AND citizenid = ? AND status = ?', {
        loanId, citizenid, 'active'
    })
    if not loan then
        return TriggerClientEvent('qb-banking:client:notify', src, L('error'), 'error')
    end

    amount = tonumber(amount)
    local remaining = loan.total_amount + loan.late_fees - loan.amount_paid
    if amount > remaining then amount = remaining end

    if amount <= 0 then
        return TriggerClientEvent('qb-banking:client:notify', src, L('invalid_amount'), 'error')
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
    ProcessLoanPayment(loan, amount, accountId, citizenid, 'manual')

    TriggerClientEvent('qb-banking:client:notify', src, L('loan_repaid', Utils.FormatMoney(amount)), 'success')
    TriggerClientEvent('qb-banking:client:refreshAccounts', src)
end)

--- Process a loan payment
---@param loan table
---@param amount number
---@param accountId number
---@param citizenid string
---@param paymentType string 'manual' or 'auto'
function ProcessLoanPayment(loan, amount, accountId, citizenid, paymentType)
    Utils.Debug('LOAN', 'ProcessLoanPayment: loan=' .. tostring(loan.id) .. ' amount=' .. tostring(amount) .. ' type=' .. tostring(paymentType) .. ' account=' .. tostring(accountId))
    local newBalance = UpdateAccountBalance(accountId, amount, 'subtract')
    RecordTransaction(accountId, 'loan_payment', amount, 0, 0, newBalance, 'Loan payment #' .. loan.id, nil, nil, citizenid)

    local newAmountPaid = loan.amount_paid + amount
    local totalOwed = loan.total_amount + loan.late_fees
    local installmentsPaid = math.floor(newAmountPaid / loan.installment_amount)
    installmentsPaid = math.min(installmentsPaid, loan.installments_total)

    local status = 'active'
    if newAmountPaid >= totalOwed then
        status = 'paid'
        newAmountPaid = totalOwed
        Utils.Debug('LOAN', 'Loan #' .. tostring(loan.id) .. ' FULLY PAID')
    end
    Utils.Debug('LOAN', 'Payment processed: paid=' .. tostring(newAmountPaid) .. '/' .. tostring(totalOwed) .. ' installments=' .. tostring(installmentsPaid) .. '/' .. tostring(loan.installments_total) .. ' status=' .. status)

    -- Calculate next payment due
    local plan = nil
    for _, p in ipairs(Config.Loans.Plans) do
        if p.id == loan.plan_id then plan = p break end
    end

    local intervalDays = plan and math.ceil(plan.durationDays / plan.installments) or 7
    local nextDue = os.date('%Y-%m-%d %H:%M:%S', os.time() + (intervalDays * 86400))

    MySQL.update.await([[
        UPDATE bank_loans SET amount_paid = ?, installments_paid = ?, status = ?, next_payment_due = ? WHERE id = ?
    ]], { newAmountPaid, installmentsPaid, status, nextDue, loan.id })

    -- Record payment
    MySQL.insert('INSERT INTO bank_loan_payments (loan_id, amount, type) VALUES (?, ?, ?)', {
        loan.id, amount, paymentType
    })

    -- Update credit score
    local isOnTime = os.time() <= (loan.next_payment_due and os.time() or os.time())
    if isOnTime then
        UpdateCreditScore(citizenid, Config.Loans.CreditScoreChanges.LoanRepaymentOnTime, 'On-time loan payment')
    else
        UpdateCreditScore(citizenid, Config.Loans.CreditScoreChanges.LoanRepaymentLate, 'Late loan payment')
    end

    if status == 'paid' then
        LogToDiscord('loans', string.format('**Loan Paid** | %s fully repaid loan #%d', citizenid, loan.id))
    end
end

-- ============================================================
-- AUTO-REPAYMENT SYSTEM
-- ============================================================

CreateThread(function()
    while true do
        Wait(60000 * (Config.Loans.AutoRepayCheckInterval or 60))

        if not Config.Loans.Enabled then goto continue end

        -- Find loans due for payment
        local dueLoans = MySQL.query.await([[
            SELECT l.*, a.balance as account_balance
            FROM bank_loans l
            JOIN bank_accounts a ON l.account_id = a.id
            WHERE l.status = 'active' AND l.auto_repay = 1 AND l.next_payment_due <= NOW()
        ]])

        if dueLoans and #dueLoans > 0 then
            Utils.Debug('LOAN', 'Auto-repayment: Found ' .. #dueLoans .. ' loans due for payment')
            for _, loan in ipairs(dueLoans) do
                local remaining = loan.total_amount + loan.late_fees - loan.amount_paid
                local payAmount = math.min(loan.installment_amount, remaining)
                Utils.Debug('LOAN', 'Auto-repay loan #' .. tostring(loan.id) .. ': payAmount=' .. tostring(payAmount) .. ' balance=' .. tostring(loan.account_balance) .. ' remaining=' .. tostring(remaining))

                if loan.account_balance >= payAmount then
                    Utils.Debug('LOAN', 'Auto-repay: sufficient balance, processing payment')
                    ProcessLoanPayment(loan, payAmount, loan.account_id, loan.citizenid, 'auto')

                    -- Notify player if online
                    local player = QBCore.Functions.GetPlayerByCitizenId(loan.citizenid)
                    if player then
                        TriggerClientEvent('qb-banking:client:notify', player.PlayerData.source,
                            L('loan_auto_repay', Utils.FormatMoney(payAmount)), 'info')
                    end
                else
                    -- Apply late penalty
                    Utils.Debug('LOAN', 'Auto-repay: insufficient balance for loan #' .. tostring(loan.id) .. ' - applying late penalty')
                    ApplyLatePenalty(loan)
                end
            end
        end

        ::continue::
    end
end)

--- Apply late payment penalty
---@param loan table
function ApplyLatePenalty(loan)
    Utils.Debug('LOAN', 'ApplyLatePenalty: loan #' .. tostring(loan.id) .. ' citizen=' .. tostring(loan.citizenid))
    local plan = nil
    for _, p in ipairs(Config.Loans.Plans) do
        if p.id == loan.plan_id then plan = p break end
    end
    if not plan then Utils.Debug('LOAN', 'Plan not found for loan #' .. tostring(loan.id)) return end

    local penaltyAmount = loan.installment_amount * (plan.latePenaltyPercent / 100)
    penaltyAmount = Utils.Round(penaltyAmount)
    Utils.Debug('LOAN', 'Late penalty: ' .. tostring(penaltyAmount) .. ' (' .. tostring(plan.latePenaltyPercent) .. '% of ' .. tostring(loan.installment_amount) .. ')')

    MySQL.update.await('UPDATE bank_loans SET late_fees = late_fees + ? WHERE id = ?', { penaltyAmount, loan.id })

    -- Check if loan should be defaulted (more than 3x overdue)
    local totalOwed = loan.total_amount + loan.late_fees + penaltyAmount
    local overdueRatio = (totalOwed - loan.amount_paid) / loan.installment_amount
    if overdueRatio > (loan.installments_total * 1.5) then
        MySQL.update.await('UPDATE bank_loans SET status = ? WHERE id = ?', { 'defaulted', loan.id })
        UpdateCreditScore(loan.citizenid, Config.Loans.CreditScoreChanges.LoanDefault, 'Loan defaulted')

        local player = QBCore.Functions.GetPlayerByCitizenId(loan.citizenid)
        if player then
            TriggerClientEvent('qb-banking:client:notify', player.PlayerData.source, L('loan_defaulted'), 'error')
        end

        LogToDiscord('loans', string.format('**Loan Defaulted** | %s defaulted on loan #%d', loan.citizenid, loan.id))
    else
        UpdateCreditScore(loan.citizenid, Config.Loans.CreditScoreChanges.LoanRepaymentLate, 'Late loan payment penalty')

        local player = QBCore.Functions.GetPlayerByCitizenId(loan.citizenid)
        if player then
            TriggerClientEvent('qb-banking:client:notify', player.PlayerData.source, L('loan_overdue'), 'warning')
        end
    end
end

Utils.Debug('QB Banking loans module initialized')
