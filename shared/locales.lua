Locales = {}

Locales['en'] = {
    -- General
    ['bank_name'] = 'QB Banking',
    ['welcome'] = 'Welcome to QB Banking',
    ['loading'] = 'Loading...',
    ['confirm'] = 'Confirm',
    ['cancel'] = 'Cancel',
    ['close'] = 'Close',
    ['success'] = 'Success',
    ['error'] = 'Error',
    ['warning'] = 'Warning',
    ['info'] = 'Information',
    ['yes'] = 'Yes',
    ['no'] = 'No',

    -- Accounts
    ['account_personal'] = 'Personal Account',
    ['account_business'] = 'Business Account',
    ['account_shared'] = 'Shared Account',
    ['account_created'] = 'Account created successfully',
    ['account_closed'] = 'Account closed successfully',
    ['account_not_found'] = 'Account not found',
    ['account_limit_reached'] = 'Maximum account limit reached',
    ['account_insufficient_funds'] = 'Insufficient funds',
    ['account_balance'] = 'Balance',

    -- Transactions
    ['deposit_success'] = 'Successfully deposited %s',
    ['withdraw_success'] = 'Successfully withdrew %s',
    ['transfer_success'] = 'Successfully transferred %s to %s',
    ['transfer_fee'] = 'Transfer fee: %s',
    ['deposit_failed'] = 'Deposit failed',
    ['withdraw_failed'] = 'Withdrawal failed',
    ['transfer_failed'] = 'Transfer failed',
    ['invalid_amount'] = 'Invalid amount',
    ['amount_too_low'] = 'Amount is below minimum',
    ['amount_too_high'] = 'Amount exceeds maximum',
    ['recipient_not_found'] = 'Recipient account not found',

    -- Loans
    ['loan_approved'] = 'Loan approved: %s',
    ['loan_denied'] = 'Loan application denied',
    ['loan_repaid'] = 'Loan payment of %s processed',
    ['loan_overdue'] = 'You have an overdue loan payment!',
    ['loan_defaulted'] = 'Loan has been defaulted',
    ['loan_limit_reached'] = 'Maximum active loans reached',
    ['credit_score_low'] = 'Credit score too low for this loan',
    ['loan_auto_repay'] = 'Auto-repayment: %s deducted',

    -- Billing
    ['invoice_sent'] = 'Invoice sent to %s',
    ['invoice_received'] = 'You received an invoice for %s',
    ['invoice_paid'] = 'Invoice paid: %s',
    ['invoice_partial'] = 'Partial payment of %s applied',
    ['invoice_overdue'] = 'You have overdue invoices!',
    ['invoice_reminder'] = 'Payment reminder: Invoice #%s is due',
    ['invoice_not_authorized'] = 'You are not authorized to send invoices',

    -- Taxes
    ['tax_collected'] = 'Tax collected: %s (%s)',
    ['tax_income'] = 'Income Tax',
    ['tax_transaction'] = 'Transaction Tax',
    ['tax_business'] = 'Business Tax',
    ['tax_exempt'] = 'Tax exempt',

    -- Cards
    ['card_created'] = 'New card created',
    ['card_blocked'] = 'Card has been blocked',
    ['card_limit_reached'] = 'Maximum card limit reached',
    ['card_expired'] = 'Card has expired',
    ['card_daily_limit'] = 'Daily spending limit reached',

    -- Admin
    ['admin_balance_set'] = 'Balance set to %s for account %s',
    ['admin_loan_cleared'] = 'Loan cleared for %s',
    ['admin_no_permission'] = 'You do not have permission',

    -- ATM / Bank
    ['atm_interact'] = 'Press [E] to use ATM',
    ['bank_interact'] = 'Press [E] to access Bank',
    ['bank_open'] = 'Bank',
    ['atm_open'] = 'ATM',

    -- Notifications
    ['notification_title'] = 'QB Banking',
}

-- Function to get locale string
function GetLocaleString(key, ...)
    local locale = Config.DefaultLocale or 'en'
    local str = Locales[locale] and Locales[locale][key] or Locales['en'][key] or key
    if ... then
        return string.format(str, ...)
    end
    return str
end

-- Shorthand
function L(key, ...)
    return GetLocaleString(key, ...)
end
