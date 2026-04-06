Utils = {}

--- Generate a random IBAN number
---@return string
function Utils.GenerateIBAN()
    local prefix = Config.IBANPrefix or 'QB'
    local length = (Config.IBANLength or 12) - #prefix
    local iban = prefix
    for i = 1, length do
        iban = iban .. tostring(math.random(0, 9))
    end
    return iban
end

--- Generate a random card number
---@return string
function Utils.GenerateCardNumber()
    local length = Config.Cards.CardNumberLength or 16
    local number = ''
    for i = 1, length do
        number = number .. tostring(math.random(0, 9))
    end
    return number
end

--- Generate a random CVV
---@return string
function Utils.GenerateCVV()
    local length = Config.Cards.CVVLength or 3
    local cvv = ''
    for i = 1, length do
        cvv = cvv .. tostring(math.random(0, 9))
    end
    return cvv
end

--- Format currency amount
---@param amount number
---@return string
function Utils.FormatMoney(amount)
    local symbol = Config.CurrencySymbol or '$'
    local formatted = string.format('%.2f', amount)
    -- Add thousand separators
    local k
    while true do
        formatted, k = string.gsub(formatted, '^(-?%d+)(%d%d%d)', '%1,%2')
        if k == 0 then break end
    end
    return symbol .. formatted
end

--- Format date from timestamp
---@param timestamp number
---@return string
function Utils.FormatDate(timestamp)
    local format = Config.DateFormat or '%Y-%m-%d %H:%M'
    return os.date(format, timestamp)
end

--- Calculate transfer fee
---@param amount number
---@return number
function Utils.CalculateTransferFee(amount)
    local fee = amount * (Config.Transactions.TransferFeePercent / 100)
    fee = math.max(fee, Config.Transactions.TransferFeeMin or 0)
    fee = math.min(fee, Config.Transactions.TransferFeeMax or math.huge)
    return math.floor(fee * 100) / 100
end

--- Calculate income tax based on brackets
---@param income number
---@return number
function Utils.CalculateIncomeTax(income)
    if not Config.Taxes.Enabled or not Config.Taxes.IncomeTax.Enabled then
        return 0
    end
    local totalTax = 0
    local remaining = income
    local brackets = Config.Taxes.IncomeTax.Brackets
    for _, bracket in ipairs(brackets) do
        if remaining <= 0 then break end
        local taxableInBracket = math.min(remaining, bracket.max - bracket.min + 1)
        if income > bracket.min then
            totalTax = totalTax + (taxableInBracket * bracket.rate / 100)
            remaining = remaining - taxableInBracket
        end
    end
    return math.floor(totalTax * 100) / 100
end

--- Calculate transaction tax
---@param amount number
---@return number
function Utils.CalculateTransactionTax(amount)
    if not Config.Taxes.Enabled or not Config.Taxes.TransactionTax.Enabled then
        return 0
    end
    if amount < (Config.Taxes.TransactionTax.MinAmount or 0) then
        return 0
    end
    return math.floor(amount * Config.Taxes.TransactionTax.Rate / 100 * 100) / 100
end

--- Check if a job is tax exempt
---@param job string
---@return boolean
function Utils.IsJobTaxExempt(job)
    if not Config.Taxes.TransactionTax.ExemptJobs then return false end
    for _, exemptJob in ipairs(Config.Taxes.TransactionTax.ExemptJobs) do
        if exemptJob == job then
            return true
        end
    end
    return false
end

--- Calculate loan repayment details
---@param plan table
---@param amount number
---@return table
function Utils.CalculateLoanDetails(plan, amount)
    local totalInterest = amount * (plan.interestRate / 100)
    local totalAmount = amount + totalInterest
    local installmentAmount = math.ceil(totalAmount / plan.installments * 100) / 100
    return {
        principal = amount,
        interest = totalInterest,
        totalAmount = totalAmount,
        installments = plan.installments,
        installmentAmount = installmentAmount,
        durationDays = plan.durationDays,
    }
end

--- Validate amount within bounds
---@param amount number
---@param min number
---@param max number
---@return boolean, string|nil
function Utils.ValidateAmount(amount, min, max)
    if type(amount) ~= 'number' or amount ~= amount then
        return false, 'invalid_amount'
    end
    if amount < (min or 0) then
        return false, 'amount_too_low'
    end
    if amount > (max or math.huge) then
        return false, 'amount_too_high'
    end
    return true, nil
end

--- Round to 2 decimal places
---@param num number
---@return number
function Utils.Round(num)
    return math.floor(num * 100 + 0.5) / 100
end

--- Deep copy a table
---@param orig table
---@return table
function Utils.DeepCopy(orig)
    local copy = {}
    for k, v in pairs(orig) do
        if type(v) == 'table' then
            copy[k] = Utils.DeepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

--- Debug print helper with category support
---@param category string|nil Optional category tag (e.g. 'DEPOSIT', 'LOAN', 'ADMIN')
---@param ... any
function Utils.Debug(category, ...)
    if Config.Debug then
        local timestamp = os.date('%H:%M:%S')
        if select('#', ...) == 0 then
            -- Single argument call (backward compatible): treat category as the message
            print(string.format('[QB-Banking %s]', timestamp), category)
        else
            print(string.format('[QB-Banking %s][%s]', timestamp, tostring(category)), ...)
        end
    end
end

--- Debug print for data tables (pretty-print)
---@param label string
---@param tbl table
function Utils.DebugTable(label, tbl)
    if Config.Debug then
        local timestamp = os.date('%H:%M:%S')
        print(string.format('[QB-Banking %s][TABLE] %s:', timestamp, label))
        if type(tbl) == 'table' then
            for k, v in pairs(tbl) do
                print(string.format('  %s = %s (%s)', tostring(k), tostring(v), type(v)))
            end
        else
            print('  (not a table: ' .. type(tbl) .. ') = ' .. tostring(tbl))
        end
    end
end
