# QB Banking - Advanced QBCore Banking System

A fully featured, production-ready banking system for FiveM QBCore servers. Includes banking, loans, billing, taxes, virtual cards, and a modern NUI dashboard.

## Features

### Banking System
- **Multiple Account Types**: Personal, Business, and Shared accounts
- **IBAN System**: Unique IBAN numbers for all accounts
- **Deposit & Withdraw**: Full cash deposit/withdrawal with configurable limits
- **Transfers**: Instant and scheduled transfers with fee calculation
- **Transaction History**: Filterable, searchable history with pagination
- **Virtual Cards**: Create/manage virtual debit cards with daily limits

### Loan System
- **Configurable Plans**: Micro, Personal, Business, and Mortgage loans
- **Credit Score System**: Dynamic scoring (0-850) affecting loan eligibility
- **Auto-Repayment**: Automatic payment deduction from linked accounts
- **Late Penalties**: Configurable penalty rates and grace periods
- **Loan Default**: Automatic default detection with credit score impact

### Billing & Invoices
- **Send/Receive Invoices**: Between players and job-authorized roles
- **Categories**: Service, Fine, Medical, Repair, Legal, Tax, Other
- **Partial Payments**: Pay invoices in installments
- **Auto-Reminders**: Automatic reminders for unpaid invoices
- **Overdue Penalties**: Configurable penalty on overdue invoices
- **Job Integration**: Police, Ambulance, Mechanic, Lawyer, Real Estate

### Tax System
- **Income Tax**: Progressive tax brackets on paychecks
- **Transaction Tax**: Percentage tax on transfers above threshold
- **Business Tax**: Periodic tax on business account revenue
- **Tax Records**: Full tax history and reporting
- **Exempt Jobs**: Configurable tax-exempt roles
- **Auto-Collection**: Automatic tax deduction

### Admin Tools
- **Admin Panel**: Full NUI-based admin dashboard
- **Balance Management**: Set/adjust any account balance
- **Account Freeze**: Freeze/unfreeze accounts
- **Loan Management**: Clear/override loans
- **Credit Score Override**: Manually adjust credit scores
- **Invoice Cancellation**: Cancel any invoice
- **Audit Logs**: Full admin action logging
- **Discord Webhooks**: Log all actions to Discord
- **Chat Commands**: `/bankadmin`, `/setbalance`, `/clearloan`, `/setcredit`

### UI/UX
- **Modern Dashboard**: Charts, stats, clean layout
- **Dark/Light Mode**: Toggle between themes
- **Smooth Animations**: Slide-in, fade, hover effects
- **Responsive Design**: Works on all screen sizes
- **Toast Notifications**: Non-intrusive notification system
- **Sound Effects**: Optional audio feedback (add .ogg files to `html/assets/sounds/`)

## Requirements

- [QBCore Framework](https://github.com/qbcore-framework/qb-core)
- [oxmysql](https://github.com/overextended/oxmysql)
- [qb-target](https://github.com/qbcore-framework/qb-target) (optional, for interaction zones)

## Installation

1. **Download** the resource and place it in your `resources` folder as `qb-banking`

2. **Import SQL**: Run the SQL file to create database tables:
   ```sql
   source sql/install.sql
   ```
   Or import `sql/install.sql` via phpMyAdmin/HeidiSQL

3. **Configure**: Edit `config.lua` to customize:
   - Account types and limits
   - Loan plans and interest rates
   - Tax brackets and rates
   - Billing rules and authorized jobs
   - Bank/ATM locations
   - Admin permissions
   - Discord webhook URL

4. **Add to server.cfg**:
   ```
   ensure qb-banking
   ```

5. **Restart** your server

## Configuration Highlights

### Loan Plans
```lua
Config.Loans.Plans = {
    {
        id = 'personal',
        label = 'Personal Loan',
        minAmount = 5000,
        maxAmount = 100000,
        interestRate = 8.0,        -- 8% interest
        durationDays = 30,
        minCreditScore = 500,
        installments = 4,          -- 4 weekly payments
        latePenaltyPercent = 3.0,
        autoRepay = true,
    },
}
```

### Tax Brackets (Progressive)
```lua
Config.Taxes.IncomeTax.Brackets = {
    { min = 0, max = 5000, rate = 0 },          -- 0% on first $5,000
    { min = 5001, max = 20000, rate = 5.0 },     -- 5% on $5,001-$20,000
    { min = 20001, max = 50000, rate = 10.0 },    -- 10%
    { min = 50001, max = 100000, rate = 15.0 },   -- 15%
    { min = 100001, max = math.huge, rate = 20.0 },-- 20%
}
```

### Authorized Billing Jobs
```lua
Config.Billing.AuthorizedJobs = {
    ['police'] = { maxAmount = 50000, categories = { 'fine', 'legal' } },
    ['ambulance'] = { maxAmount = 25000, categories = { 'medical', 'service' } },
    ['mechanic'] = { maxAmount = 15000, categories = { 'repair', 'service' } },
}
```

## File Structure
```
qb-banking/
├── fxmanifest.lua          -- Resource manifest
├── config.lua              -- All configuration options
├── shared/
│   ├── locales.lua         -- Multi-language support
│   └── utils.lua           -- Utility functions
├── server/
│   ├── main.lua            -- Core server logic, deposits, withdrawals, transfers
│   ├── loans.lua           -- Loan system, credit scores, auto-repayment
│   ├── billing.lua         -- Invoice system, reminders, overdue processing
│   ├── taxes.lua           -- Tax calculation, collection, records
│   ├── cards.lua           -- Virtual card management
│   └── admin.lua           -- Admin commands, logs, balance management
├── client/
│   ├── main.lua            -- NUI callbacks, bank/ATM interactions
│   └── notifications.lua   -- Notification system
├── html/
│   ├── index.html          -- Main UI page
│   ├── css/style.css       -- Modern stylesheet with dark/light themes
│   ├── js/app.js           -- UI application controller
│   ├── js/charts.js        -- Lightweight canvas chart library
│   └── assets/sounds/      -- Sound effect files (.ogg)
├── sql/
│   └── install.sql         -- Database schema
└── README.md
```

## Exports

### Server Exports
```lua
-- Apply income tax on a paycheck amount
exports['qb-banking']:ApplyIncomeTax(citizenid, amount)
```

## Security
- All financial operations validated server-side
- Account access verification on every request
- Admin permission checks on all admin endpoints
- No client-side money manipulation possible
- SQL injection protection via parameterized queries

## Performance
- Server-side caching for accounts and credit scores
- Efficient async database queries (oxmysql)
- Minimal client-side loops (only active near bank/ATM)
- Batched database operations where possible
- Configurable cache timeouts

## Discord Webhook Logging
Set your webhook URL in `config.lua`:
```lua
Config.Admin.DiscordWebhook = 'https://discord.com/api/webhooks/YOUR_WEBHOOK_URL'
```
Logs: Transactions, Loans, Billing, Taxes, Admin Actions

## Localization
Add new languages in `shared/locales.lua`:
```lua
Locales['fr'] = {
    ['bank_name'] = 'QB Banque',
    -- ...
}
```
Set `Config.DefaultLocale = 'fr'` in config.

## License
Free to use and modify for your FiveM server.
