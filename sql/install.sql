-- ============================================================
-- QB Banking System - Database Schema
-- Run this SQL file to install all required tables
-- ============================================================

-- Bank Accounts
CREATE TABLE IF NOT EXISTS `bank_accounts` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `iban` VARCHAR(20) NOT NULL UNIQUE,
    `owner_citizenid` VARCHAR(50) NOT NULL,
    `account_type` VARCHAR(20) NOT NULL DEFAULT 'personal',
    `account_name` VARCHAR(100) DEFAULT NULL,
    `balance` DECIMAL(16,2) NOT NULL DEFAULT 0.00,
    `is_frozen` TINYINT(1) NOT NULL DEFAULT 0,
    `is_closed` TINYINT(1) NOT NULL DEFAULT 0,
    `metadata` JSON DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_owner` (`owner_citizenid`),
    INDEX `idx_type` (`account_type`),
    INDEX `idx_iban` (`iban`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Shared Account Members
CREATE TABLE IF NOT EXISTS `bank_account_members` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `account_id` INT NOT NULL,
    `citizenid` VARCHAR(50) NOT NULL,
    `role` VARCHAR(20) NOT NULL DEFAULT 'member',
    `permissions` JSON DEFAULT NULL,
    `added_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (`account_id`) REFERENCES `bank_accounts`(`id`) ON DELETE CASCADE,
    UNIQUE KEY `unique_member` (`account_id`, `citizenid`),
    INDEX `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Transaction History
CREATE TABLE IF NOT EXISTS `bank_transactions` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `account_id` INT NOT NULL,
    `type` VARCHAR(20) NOT NULL,
    `amount` DECIMAL(16,2) NOT NULL,
    `fee` DECIMAL(16,2) DEFAULT 0.00,
    `tax` DECIMAL(16,2) DEFAULT 0.00,
    `balance_after` DECIMAL(16,2) NOT NULL,
    `description` VARCHAR(255) DEFAULT NULL,
    `from_iban` VARCHAR(20) DEFAULT NULL,
    `to_iban` VARCHAR(20) DEFAULT NULL,
    `initiated_by` VARCHAR(50) DEFAULT NULL,
    `metadata` JSON DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_account` (`account_id`),
    INDEX `idx_type` (`type`),
    INDEX `idx_date` (`created_at`),
    INDEX `idx_from_iban` (`from_iban`),
    INDEX `idx_to_iban` (`to_iban`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Scheduled Transfers
CREATE TABLE IF NOT EXISTS `bank_scheduled_transfers` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `from_account_id` INT NOT NULL,
    `to_iban` VARCHAR(20) NOT NULL,
    `amount` DECIMAL(16,2) NOT NULL,
    `description` VARCHAR(255) DEFAULT NULL,
    `frequency` VARCHAR(20) NOT NULL DEFAULT 'once',
    `next_execution` TIMESTAMP NOT NULL,
    `last_executed` TIMESTAMP NULL DEFAULT NULL,
    `is_active` TINYINT(1) NOT NULL DEFAULT 1,
    `created_by` VARCHAR(50) NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (`from_account_id`) REFERENCES `bank_accounts`(`id`) ON DELETE CASCADE,
    INDEX `idx_next_exec` (`next_execution`),
    INDEX `idx_active` (`is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Virtual Cards
CREATE TABLE IF NOT EXISTS `bank_cards` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `account_id` INT NOT NULL,
    `card_number` VARCHAR(20) NOT NULL UNIQUE,
    `cvv` VARCHAR(5) NOT NULL,
    `pin_hash` VARCHAR(255) DEFAULT NULL,
    `holder_name` VARCHAR(100) NOT NULL,
    `expiry_date` DATE NOT NULL,
    `daily_limit` DECIMAL(16,2) NOT NULL DEFAULT 50000.00,
    `daily_spent` DECIMAL(16,2) NOT NULL DEFAULT 0.00,
    `daily_reset` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `is_blocked` TINYINT(1) NOT NULL DEFAULT 0,
    `is_active` TINYINT(1) NOT NULL DEFAULT 1,
    `metadata` JSON DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (`account_id`) REFERENCES `bank_accounts`(`id`) ON DELETE CASCADE,
    INDEX `idx_account` (`account_id`),
    INDEX `idx_card_number` (`card_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Credit Scores
CREATE TABLE IF NOT EXISTS `bank_credit_scores` (
    `citizenid` VARCHAR(50) PRIMARY KEY,
    `score` INT NOT NULL DEFAULT 650,
    `last_updated` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `history` JSON DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Loans
CREATE TABLE IF NOT EXISTS `bank_loans` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `account_id` INT NOT NULL,
    `citizenid` VARCHAR(50) NOT NULL,
    `plan_id` VARCHAR(50) NOT NULL,
    `principal` DECIMAL(16,2) NOT NULL,
    `interest` DECIMAL(16,2) NOT NULL,
    `total_amount` DECIMAL(16,2) NOT NULL,
    `amount_paid` DECIMAL(16,2) NOT NULL DEFAULT 0.00,
    `installments_total` INT NOT NULL,
    `installments_paid` INT NOT NULL DEFAULT 0,
    `installment_amount` DECIMAL(16,2) NOT NULL,
    `next_payment_due` TIMESTAMP NOT NULL,
    `status` VARCHAR(20) NOT NULL DEFAULT 'active',
    `late_fees` DECIMAL(16,2) NOT NULL DEFAULT 0.00,
    `auto_repay` TINYINT(1) NOT NULL DEFAULT 1,
    `metadata` JSON DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (`account_id`) REFERENCES `bank_accounts`(`id`) ON DELETE CASCADE,
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_status` (`status`),
    INDEX `idx_next_payment` (`next_payment_due`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Loan Payment History
CREATE TABLE IF NOT EXISTS `bank_loan_payments` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `loan_id` INT NOT NULL,
    `amount` DECIMAL(16,2) NOT NULL,
    `type` VARCHAR(20) NOT NULL DEFAULT 'manual',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (`loan_id`) REFERENCES `bank_loans`(`id`) ON DELETE CASCADE,
    INDEX `idx_loan` (`loan_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Invoices / Bills
CREATE TABLE IF NOT EXISTS `bank_invoices` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `invoice_number` VARCHAR(20) NOT NULL UNIQUE,
    `from_citizenid` VARCHAR(50) NOT NULL,
    `from_job` VARCHAR(50) DEFAULT NULL,
    `to_citizenid` VARCHAR(50) NOT NULL,
    `to_account_id` INT DEFAULT NULL,
    `amount` DECIMAL(16,2) NOT NULL,
    `amount_paid` DECIMAL(16,2) NOT NULL DEFAULT 0.00,
    `category` VARCHAR(50) NOT NULL DEFAULT 'other',
    `description` VARCHAR(255) DEFAULT NULL,
    `status` VARCHAR(20) NOT NULL DEFAULT 'pending',
    `due_date` TIMESTAMP NULL DEFAULT NULL,
    `penalty_applied` TINYINT(1) NOT NULL DEFAULT 0,
    `reminder_sent` TINYINT(1) NOT NULL DEFAULT 0,
    `metadata` JSON DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX `idx_from` (`from_citizenid`),
    INDEX `idx_to` (`to_citizenid`),
    INDEX `idx_status` (`status`),
    INDEX `idx_due_date` (`due_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tax Records
CREATE TABLE IF NOT EXISTS `bank_tax_records` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `account_id` INT DEFAULT NULL,
    `tax_type` VARCHAR(20) NOT NULL,
    `amount` DECIMAL(16,2) NOT NULL,
    `taxable_amount` DECIMAL(16,2) NOT NULL,
    `rate` DECIMAL(5,2) NOT NULL,
    `description` VARCHAR(255) DEFAULT NULL,
    `period_start` TIMESTAMP NULL DEFAULT NULL,
    `period_end` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_type` (`tax_type`),
    INDEX `idx_date` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Admin Audit Log
CREATE TABLE IF NOT EXISTS `bank_admin_logs` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `admin_citizenid` VARCHAR(50) NOT NULL,
    `action` VARCHAR(50) NOT NULL,
    `target_citizenid` VARCHAR(50) DEFAULT NULL,
    `target_account_id` INT DEFAULT NULL,
    `details` JSON DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_admin` (`admin_citizenid`),
    INDEX `idx_action` (`action`),
    INDEX `idx_date` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
