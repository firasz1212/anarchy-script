Config = {}

-- ============================================================
-- GENERAL SETTINGS
-- ============================================================
Config.Debug = false                          -- Enable debug prints in console
Config.UseTarget = true                       -- Use qb-target for interactions (false = drawtext)
Config.DefaultLocale = 'en'                   -- Default language (see shared/locales.lua)
Config.CurrencySymbol = '$'                   -- Currency symbol displayed in UI
Config.DateFormat = '%Y-%m-%d %H:%M'          -- Date format for transaction logs

-- ============================================================
-- IBAN / ACCOUNT SETTINGS
-- ============================================================
Config.IBANPrefix = 'QB'                      -- Prefix for generated IBAN numbers
Config.IBANLength = 12                        -- Total length of IBAN (including prefix)
Config.DefaultAccountType = 'personal'        -- Default account type on creation
Config.MaxAccountsPerPlayer = 5               -- Maximum accounts a player can own
Config.AllowSharedAccounts = true             -- Allow shared accounts between players
Config.MaxSharedMembers = 5                   -- Max members on a shared account

-- Account types and their settings
Config.AccountTypes = {
    ['personal'] = {
        label = 'Personal Account',
        icon = 'fa-user',
        openingBalance = 0,
        monthlyFee = 0,
        maxBalance = 10000000,
        interestRate = 0.5,                   -- 0.5% monthly interest on savings
        interestInterval = 168,               -- Interest paid every 168 hours (weekly)
        allowLoans = true,
        allowCards = true,
    },
    ['business'] = {
        label = 'Business Account',
        icon = 'fa-briefcase',
        openingBalance = 0,
        monthlyFee = 500,
        maxBalance = 50000000,
        interestRate = 1.0,
        interestInterval = 168,
        allowLoans = true,
        allowCards = true,
        requireJob = false,                   -- Require player to own a business
    },
    ['shared'] = {
        label = 'Shared Account',
        icon = 'fa-users',
        openingBalance = 0,
        monthlyFee = 100,
        maxBalance = 5000000,
        interestRate = 0.25,
        interestInterval = 168,
        allowLoans = false,
        allowCards = false,
    },
}

-- ============================================================
-- TRANSACTION SETTINGS
-- ============================================================
Config.Transactions = {
    MinDeposit = 1,                            -- Minimum deposit amount
    MaxDeposit = 1000000,                      -- Maximum single deposit
    MinWithdraw = 1,                           -- Minimum withdrawal amount
    MaxWithdraw = 500000,                      -- Maximum single withdrawal
    MinTransfer = 1,                           -- Minimum transfer amount
    MaxTransfer = 1000000,                     -- Maximum single transfer
    TransferFeePercent = 0.5,                  -- 0.5% fee on transfers
    TransferFeeMin = 5,                        -- Minimum transfer fee
    TransferFeeMax = 5000,                     -- Maximum transfer fee
    AllowScheduledTransfers = true,            -- Enable scheduled transfers
    HistoryPageSize = 20,                      -- Transactions per page in history
}

-- ============================================================
-- CARD SYSTEM
-- ============================================================
Config.Cards = {
    Enabled = true,                            -- Enable virtual card system
    MaxCardsPerAccount = 3,                    -- Max cards per account
    CardNumberLength = 16,                     -- Card number length
    CVVLength = 3,                             -- CVV length
    ExpiryMonths = 36,                         -- Card expiry in months
    DailySpendLimit = 50000,                   -- Daily spending limit per card
    AllowOnlinePurchases = true,               -- Allow virtual purchases
}

-- ============================================================
-- LOAN SYSTEM
-- ============================================================
Config.Loans = {
    Enabled = true,                            -- Enable loan system
    MaxActiveLoans = 3,                        -- Max active loans per player
    MinCreditScore = 300,                      -- Min credit score to apply
    DefaultCreditScore = 650,                  -- Starting credit score
    MaxCreditScore = 850,                      -- Maximum credit score

    -- Credit score adjustments
    CreditScoreChanges = {
        LoanRepaymentOnTime = 15,              -- Score increase for on-time payment
        LoanRepaymentLate = -25,               -- Score decrease for late payment
        LoanDefault = -100,                    -- Score decrease for defaulting
        InvoicePaidOnTime = 5,                 -- Score increase for paying invoices
        InvoicePaidLate = -10,                 -- Score decrease for late invoice
        LargeDeposit = 2,                      -- Score increase for large deposits
    },

    -- Loan plans (fully configurable)
    Plans = {
        {
            id = 'micro',
            label = 'Micro Loan',
            description = 'Small short-term loan for quick needs',
            minAmount = 1000,
            maxAmount = 25000,
            interestRate = 5.0,                -- 5% total interest
            durationDays = 7,                  -- 7 days to repay
            minCreditScore = 300,
            installments = 1,                  -- Single payment
            latePenaltyPercent = 2.0,          -- 2% penalty per late period
            latePenaltyInterval = 24,          -- Penalty applied every 24 hours late
            autoRepay = true,                  -- Auto-deduct from account
            requireCollateral = false,
        },
        {
            id = 'personal',
            label = 'Personal Loan',
            description = 'Standard personal loan with monthly payments',
            minAmount = 5000,
            maxAmount = 100000,
            interestRate = 8.0,
            durationDays = 30,
            minCreditScore = 500,
            installments = 4,                  -- 4 weekly payments
            latePenaltyPercent = 3.0,
            latePenaltyInterval = 24,
            autoRepay = true,
            requireCollateral = false,
        },
        {
            id = 'business',
            label = 'Business Loan',
            description = 'Large loan for business investments',
            minAmount = 50000,
            maxAmount = 500000,
            interestRate = 6.0,
            durationDays = 90,
            minCreditScore = 650,
            installments = 12,                 -- 12 weekly payments
            latePenaltyPercent = 2.5,
            latePenaltyInterval = 48,
            autoRepay = true,
            requireCollateral = true,
        },
        {
            id = 'mortgage',
            label = 'Mortgage',
            description = 'Long-term loan for property purchases',
            minAmount = 100000,
            maxAmount = 2000000,
            interestRate = 4.5,
            durationDays = 180,
            minCreditScore = 700,
            installments = 24,
            latePenaltyPercent = 1.5,
            latePenaltyInterval = 48,
            autoRepay = true,
            requireCollateral = true,
        },
    },

    -- Auto-repayment settings
    AutoRepayCheckInterval = 60,               -- Check every 60 minutes (in-game)
    GracePeriodHours = 24,                     -- Hours grace period before penalty
}

-- ============================================================
-- BILLING / INVOICE SYSTEM
-- ============================================================
Config.Billing = {
    Enabled = true,
    MaxUnpaidInvoices = 10,                    -- Max unpaid invoices before penalty
    AllowPartialPayments = true,               -- Allow paying part of an invoice
    MinPartialPayment = 100,                   -- Minimum partial payment
    AutoReminderHours = 48,                    -- Send reminder after X hours
    OverdueAfterHours = 168,                   -- Invoice overdue after 7 days
    OverduePenaltyPercent = 5.0,               -- 5% penalty on overdue invoices

    -- Invoice categories
    Categories = {
        { id = 'service', label = 'Service', icon = 'fa-wrench' },
        { id = 'fine', label = 'Fine', icon = 'fa-gavel' },
        { id = 'medical', label = 'Medical', icon = 'fa-hospital' },
        { id = 'repair', label = 'Repair', icon = 'fa-car' },
        { id = 'legal', label = 'Legal Fee', icon = 'fa-balance-scale' },
        { id = 'tax', label = 'Tax Bill', icon = 'fa-file-invoice-dollar' },
        { id = 'other', label = 'Other', icon = 'fa-file-alt' },
    },

    -- Jobs that can send invoices
    AuthorizedJobs = {
        ['police'] = { maxAmount = 50000, categories = { 'fine', 'legal' } },
        ['ambulance'] = { maxAmount = 25000, categories = { 'medical', 'service' } },
        ['mechanic'] = { maxAmount = 15000, categories = { 'repair', 'service' } },
        ['lawyer'] = { maxAmount = 30000, categories = { 'legal', 'service' } },
        ['realestate'] = { maxAmount = 100000, categories = { 'service', 'other' } },
    },
}

-- ============================================================
-- TAX SYSTEM
-- ============================================================
Config.Taxes = {
    Enabled = true,

    -- Income Tax (applied to job paychecks)
    IncomeTax = {
        Enabled = true,
        -- Progressive tax brackets
        Brackets = {
            { min = 0, max = 5000, rate = 0 },            -- 0% on first $5,000
            { min = 5001, max = 20000, rate = 5.0 },      -- 5% on $5,001-$20,000
            { min = 20001, max = 50000, rate = 10.0 },     -- 10% on $20,001-$50,000
            { min = 50001, max = 100000, rate = 15.0 },    -- 15% on $50,001-$100,000
            { min = 100001, max = math.huge, rate = 20.0 }, -- 20% on $100,001+
        },
    },

    -- Transaction Tax (applied to transfers)
    TransactionTax = {
        Enabled = true,
        Rate = 1.0,                            -- 1% tax on transfers
        MinAmount = 1000,                      -- Only tax transfers above $1,000
        ExemptJobs = { 'police', 'ambulance' }, -- Exempt jobs
    },

    -- Business Tax (applied to business account income)
    BusinessTax = {
        Enabled = true,
        Rate = 8.0,                            -- 8% business tax
        CollectionInterval = 168,              -- Collect every 168 hours (weekly)
        MinRevenue = 10000,                    -- Only tax if revenue exceeds this
    },

    -- Tax collection settings
    AutoCollect = true,                        -- Automatically collect taxes
    CollectionDay = 1,                         -- Day of week (1=Monday) for collection
    TaxLogRetentionDays = 90,                  -- Keep tax logs for 90 days
}

-- ============================================================
-- ATM SYSTEM
-- ============================================================
Config.ATM = {
    Enabled = true,
    WithdrawOnly = false,                      -- If true, ATMs only allow withdrawals
    MaxWithdraw = 50000,                       -- Max ATM withdrawal
    UseBuiltinLocations = true,                -- Use built-in ATM prop detection
    CustomLocations = {},                      -- Add custom ATM locations here
    ATMModels = {                              -- ATM prop models
        'prop_atm_01',
        'prop_atm_02',
        'prop_atm_03',
        'prop_fleeca_atm',
    },
}

-- ============================================================
-- BANK LOCATIONS
-- ============================================================
Config.BankLocations = {
    {
        name = 'Legion Square',
        coords = vector3(149.47, -1040.39, 29.37),
        heading = 340.0,
        blip = { sprite = 108, color = 2, scale = 0.8 },
        npcModel = 'ig_bankman',
    },
    {
        name = 'Alta Street',
        coords = vector3(314.19, -278.65, 54.16),
        heading = 340.0,
        blip = { sprite = 108, color = 2, scale = 0.8 },
        npcModel = 'ig_bankman',
    },
    {
        name = 'Burton',
        coords = vector3(-351.23, -49.26, 49.04),
        heading = 340.0,
        blip = { sprite = 108, color = 2, scale = 0.8 },
        npcModel = 'ig_bankman',
    },
    {
        name = 'Del Perro',
        coords = vector3(-1212.98, -330.37, 37.79),
        heading = 27.0,
        blip = { sprite = 108, color = 2, scale = 0.8 },
        npcModel = 'ig_bankman',
    },
    {
        name = 'Great Ocean Highway',
        coords = vector3(-2962.58, 482.63, 15.7),
        heading = 87.0,
        blip = { sprite = 108, color = 2, scale = 0.8 },
        npcModel = 'ig_bankman',
    },
    {
        name = 'Paleto Bay',
        coords = vector3(-112.22, 6469.29, 31.63),
        heading = 132.0,
        blip = { sprite = 108, color = 2, scale = 0.8 },
        npcModel = 'ig_bankman',
    },
}

-- ============================================================
-- ADMIN SETTINGS
-- ============================================================
Config.Admin = {
    -- Permission level required for admin commands (QBCore permission)
    PermissionLevel = 'admin',
    -- Players with these citizen IDs always have admin access
    Whitelist = {},
    -- Discord webhook for logging (leave empty to disable)
    DiscordWebhook = '',
    DiscordBotName = 'QB Banking',
    DiscordBotAvatar = '',
    -- Log types to send to Discord
    LogTypes = {
        transactions = true,
        loans = true,
        billing = true,
        taxes = true,
        admin = true,
    },
}

-- ============================================================
-- NOTIFICATION SETTINGS
-- ============================================================
Config.Notifications = {
    System = 'qb',                             -- 'qb' for QBCore, 'okok' for okokNotify, 'custom'
    Duration = 5000,                           -- Default notification duration (ms)
    SoundEnabled = true,                       -- Play sound with notifications
    SoundVolume = 0.3,                         -- Sound volume (0.0 - 1.0)
}

-- ============================================================
-- PERFORMANCE SETTINGS
-- ============================================================
Config.Performance = {
    CacheTimeout = 300,                        -- Cache expiry in seconds
    MaxQueryBatch = 50,                        -- Max DB queries per batch
    UIUpdateInterval = 1000,                   -- UI refresh interval (ms)
    UseResourceKvp = true,                     -- Use KVP for client-side caching
}
