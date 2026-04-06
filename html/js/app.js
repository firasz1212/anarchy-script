/* ============================================================
   QB Banking - Main Application Controller
   ============================================================ */

const App = {
    isOpen: false,
    mode: 'bank',
    currentPage: 'dashboard',
    selectedAccount: null,
    accounts: [],
    playerName: 'Player',
    playerJob: 'unemployed',
    isDarkMode: false,
    transactionPage: 1,

    // ============================================================
    // INITIALIZATION
    // ============================================================

    init: function() {
        this.setupEventListeners();
        this.loadThemePreference();
    },

    setupEventListeners: function() {
        // NUI message listener
        window.addEventListener('message', (event) => {
            this.handleMessage(event.data);
        });

        // Keyboard events
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && this.isOpen) {
                this.close();
            }
        });

        // Navigation
        document.querySelectorAll('.nav-item').forEach(item => {
            item.addEventListener('click', (e) => {
                e.preventDefault();
                const page = item.dataset.page;
                this.navigateTo(page);
            });
        });

        // Tab switching
        document.querySelectorAll('.tab').forEach(tab => {
            tab.addEventListener('click', () => {
                const tabId = tab.dataset.tab;
                tab.parentElement.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
                tab.classList.add('active');
                document.querySelectorAll('.tab-content').forEach(tc => tc.classList.remove('active'));
                const tabContent = document.getElementById('tab-' + tabId);
                if (tabContent) tabContent.classList.add('active');
            });
        });

        // Account selector
        document.getElementById('accountSelect').addEventListener('change', (e) => {
            const accountId = parseInt(e.target.value);
            if (accountId) {
                this.selectedAccount = this.accounts.find(a => a.id === accountId);
                this.onAccountChanged();
            }
        });

        // Theme toggle
        document.getElementById('themeToggle').addEventListener('click', () => {
            this.toggleTheme();
        });

        // Close button
        document.getElementById('closeBtn').addEventListener('click', () => {
            this.close();
        });

        // Transfer amount change for fee preview
        document.getElementById('transferAmount').addEventListener('input', (e) => {
            this.updateTransferFeePreview(parseFloat(e.target.value) || 0);
        });
    },

    // ============================================================
    // NUI MESSAGE HANDLER
    // ============================================================

    handleMessage: function(data) {
        switch (data.action) {
            case 'open':
                this.open(data);
                break;
            case 'close':
                this.hide();
                break;
            case 'openAdmin':
                this.openAdmin();
                break;
            case 'refreshAccounts':
                this.refreshAccounts();
                break;
            case 'notification':
                this.showToast(data.message, data.type, data.duration);
                break;
            case 'playSound':
                this.playSound(data.sound, data.volume);
                break;
        }
    },

    // ============================================================
    // OPEN / CLOSE
    // ============================================================

    open: function(data) {
        this.isOpen = true;
        this.mode = data.mode || 'bank';
        this.playerName = data.playerName || 'Player';
        this.playerJob = data.job || 'unemployed';

        document.getElementById('app').classList.remove('hidden');
        document.getElementById('playerName').textContent = this.playerName;

        // Hide admin nav for non-admin
        // Load accounts
        this.loadAccounts();
    },

    openAdmin: function() {
        this.isOpen = true;
        document.getElementById('app').classList.remove('hidden');
        this.navigateTo('admin');
        this.loadAdminData();
    },

    close: function() {
        this.isOpen = false;
        this.hide();
        this.fetchNUI('close', {});
    },

    hide: function() {
        const app = document.getElementById('app');
        app.style.animation = 'slideOut 0.3s ease';
        setTimeout(() => {
            app.classList.add('hidden');
            app.style.animation = '';
        }, 280);
    },

    // ============================================================
    // NAVIGATION
    // ============================================================

    navigateTo: function(page) {
        this.currentPage = page;

        // Update nav
        document.querySelectorAll('.nav-item').forEach(item => {
            item.classList.toggle('active', item.dataset.page === page);
        });

        // Show page
        document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
        const pageEl = document.getElementById('page-' + page);
        if (pageEl) pageEl.classList.add('active');

        // Load page data
        this.loadPageData(page);
    },

    loadPageData: function(page) {
        if (!this.selectedAccount && page !== 'accounts' && page !== 'admin') {
            return;
        }

        switch (page) {
            case 'dashboard':
                this.loadDashboard();
                break;
            case 'transactions':
                this.loadTransactions(1);
                break;
            case 'cards':
                this.loadCards();
                break;
            case 'loans':
                this.loadLoans();
                break;
            case 'billing':
                this.loadInvoices();
                break;
            case 'taxes':
                this.loadTaxRecords();
                break;
            case 'accounts':
                this.renderAccounts();
                break;
            case 'admin':
                this.loadAdminData();
                break;
        }
    },

    // ============================================================
    // ACCOUNTS
    // ============================================================

    loadAccounts: function() {
        this.fetchNUI('getAccounts', {}).then(accounts => {
            this.accounts = accounts || [];
            this.renderAccountSelector();
            this.renderAccounts();

            if (this.accounts.length > 0 && !this.selectedAccount) {
                this.selectedAccount = this.accounts[0];
                document.getElementById('accountSelect').value = this.selectedAccount.id;
                this.onAccountChanged();
            }
        });
    },

    refreshAccounts: function() {
        this.fetchNUI('getAccounts', {}).then(accounts => {
            this.accounts = accounts || [];
            this.renderAccountSelector();

            if (this.selectedAccount) {
                const updated = this.accounts.find(a => a.id === this.selectedAccount.id);
                if (updated) {
                    this.selectedAccount = updated;
                }
            }

            this.loadPageData(this.currentPage);
        });
    },

    renderAccountSelector: function() {
        const select = document.getElementById('accountSelect');
        const currentVal = select.value;
        select.innerHTML = '<option value="">Select Account</option>';

        this.accounts.forEach(acc => {
            const option = document.createElement('option');
            option.value = acc.id;
            option.textContent = `${acc.account_name || acc.account_type} (${acc.iban})`;
            select.appendChild(option);
        });

        if (currentVal) select.value = currentVal;
    },

    renderAccounts: function() {
        const container = document.getElementById('accountsList');
        if (!container) return;

        if (this.accounts.length === 0) {
            container.innerHTML = '<div class="empty-state-box"><i class="fas fa-wallet"></i><p>No accounts found</p></div>';
            return;
        }

        container.innerHTML = this.accounts.map(acc => `
            <div class="account-card">
                <div class="account-card-header">
                    <div class="account-type-icon">
                        <i class="fas ${this.getAccountIcon(acc.account_type)}"></i>
                    </div>
                    <span class="badge badge-${acc.is_frozen ? 'danger' : 'success'}">
                        ${acc.is_frozen ? 'Frozen' : 'Active'}
                    </span>
                </div>
                <div class="account-card-balance">${this.formatMoney(acc.balance)}</div>
                <div class="account-card-iban">${acc.iban}</div>
                <div class="account-card-footer">
                    <span style="font-size:12px;color:var(--text-secondary)">
                        ${(acc.account_name || acc.account_type).toUpperCase()} ${acc.access_role === 'owner' ? '' : '(Shared)'}
                    </span>
                    ${acc.access_role === 'owner' && acc.account_type !== 'personal' ? `
                        <button class="btn btn-danger btn-sm" onclick="App.closeAccountPrompt(${acc.id})">
                            <i class="fas fa-times"></i> Close
                        </button>
                    ` : ''}
                </div>
            </div>
        `).join('');
    },

    onAccountChanged: function() {
        this.loadPageData(this.currentPage);
    },

    getAccountIcon: function(type) {
        const icons = { personal: 'fa-user', business: 'fa-briefcase', shared: 'fa-users' };
        return icons[type] || 'fa-wallet';
    },

    // ============================================================
    // DASHBOARD
    // ============================================================

    loadDashboard: function() {
        if (!this.selectedAccount) return;

        this.fetchNUI('getDashboard', { accountId: this.selectedAccount.id }).then(data => {
            if (!data) return;

            document.getElementById('dashBalance').textContent = this.formatMoney(data.balance);

            const stats = data.weekStats || {};
            const income = parseFloat(stats.total_deposits || 0) + parseFloat(stats.total_received || 0);
            const expenses = parseFloat(stats.total_withdrawals || 0) + parseFloat(stats.total_sent || 0);

            document.getElementById('dashIncome').textContent = this.formatMoney(income);
            document.getElementById('dashExpenses').textContent = this.formatMoney(expenses);
            document.getElementById('dashLoans').textContent = data.activeLoans || 0;

            // Credit score
            const score = data.creditScore || 0;
            document.getElementById('creditScoreBadge').textContent = 'Credit Score: ' + score;
            document.getElementById('creditScoreBadge').className = 'badge badge-' + this.getCreditScoreColor(score);

            // Chart
            this.renderWeeklyChart(data.dailyData || []);
        });
    },

    renderWeeklyChart: function(dailyData) {
        const labels = [];
        const incomeData = [];
        const expenseData = [];

        // Fill 7 days
        for (let i = 6; i >= 0; i--) {
            const date = new Date();
            date.setDate(date.getDate() - i);
            const dateStr = date.toISOString().split('T')[0];
            const dayLabel = date.toLocaleDateString('en-US', { weekday: 'short' });
            labels.push(dayLabel);

            const dayData = dailyData.find(d => d.date === dateStr);
            incomeData.push(dayData ? parseFloat(dayData.income) : 0);
            expenseData.push(dayData ? parseFloat(dayData.expenses) : 0);
        }

        ChartLib.barChart('weeklyChart', {
            labels: labels,
            datasets: [
                { label: 'Income', data: incomeData, color: '#10b981' },
                { label: 'Expenses', data: expenseData, color: '#ef4444' },
            ]
        }, { height: 250 });
    },

    getCreditScoreColor: function(score) {
        if (score >= 700) return 'success';
        if (score >= 500) return 'warning';
        return 'danger';
    },

    // ============================================================
    // TRANSACTIONS
    // ============================================================

    loadTransactions: function(page) {
        if (!this.selectedAccount) return;
        this.transactionPage = page || 1;

        const filters = {
            type: document.getElementById('filterType').value,
            dateFrom: document.getElementById('filterDateFrom').value,
            dateTo: document.getElementById('filterDateTo').value,
            search: document.getElementById('filterSearch').value,
        };

        this.fetchNUI('getTransactions', {
            accountId: this.selectedAccount.id,
            page: this.transactionPage,
            filters: filters,
        }).then(result => {
            if (!result) return;
            this.renderTransactions(result.transactions || []);
            this.renderPagination(result.total, result.page, result.pageSize);
        });
    },

    renderTransactions: function(transactions) {
        const tbody = document.getElementById('transactionList');

        if (transactions.length === 0) {
            tbody.innerHTML = '<tr><td colspan="6" class="empty-state">No transactions found</td></tr>';
            return;
        }

        tbody.innerHTML = transactions.map(tx => {
            const isIncome = ['deposit', 'transfer_in', 'loan_deposit', 'invoice_income'].includes(tx.type);
            return `
                <tr>
                    <td>${this.formatDate(tx.created_at)}</td>
                    <td><span class="tx-type tx-${tx.type}">${this.formatTxType(tx.type)}</span></td>
                    <td class="${isIncome ? 'amount-positive' : 'amount-negative'}">
                        ${isIncome ? '+' : '-'}${this.formatMoney(tx.amount)}
                    </td>
                    <td>${tx.fee > 0 ? this.formatMoney(tx.fee) : '-'}</td>
                    <td>${this.formatMoney(tx.balance_after)}</td>
                    <td>${tx.description || '-'}</td>
                </tr>
            `;
        }).join('');
    },

    renderPagination: function(total, currentPage, pageSize) {
        const container = document.getElementById('transactionPagination');
        const totalPages = Math.ceil(total / pageSize);

        if (totalPages <= 1) {
            container.innerHTML = '';
            return;
        }

        let html = '';
        html += `<button ${currentPage <= 1 ? 'disabled' : ''} onclick="App.loadTransactions(${currentPage - 1})"><i class="fas fa-chevron-left"></i></button>`;

        for (let i = 1; i <= totalPages; i++) {
            if (i === 1 || i === totalPages || (i >= currentPage - 2 && i <= currentPage + 2)) {
                html += `<button class="${i === currentPage ? 'active' : ''}" onclick="App.loadTransactions(${i})">${i}</button>`;
            } else if (i === currentPage - 3 || i === currentPage + 3) {
                html += '<button disabled>...</button>';
            }
        }

        html += `<button ${currentPage >= totalPages ? 'disabled' : ''} onclick="App.loadTransactions(${currentPage + 1})"><i class="fas fa-chevron-right"></i></button>`;
        container.innerHTML = html;
    },

    formatTxType: function(type) {
        const types = {
            deposit: 'Deposit',
            withdraw: 'Withdraw',
            transfer_in: 'Received',
            transfer_out: 'Sent',
            loan_deposit: 'Loan',
            loan_payment: 'Loan Pay',
            invoice_payment: 'Invoice',
            invoice_income: 'Invoice In',
            tax_deduction: 'Tax',
            admin_adjust: 'Admin',
        };
        return types[type] || type;
    },

    // ============================================================
    // QUICK ACTIONS (Deposit / Withdraw)
    // ============================================================

    quickDeposit: function() {
        if (!this.selectedAccount) return this.showToast('Please select an account first', 'warning');

        this.showModal('Deposit Money', `
            <div class="form-group">
                <label>Amount ($)</label>
                <input type="number" id="quickDepositAmount" placeholder="0.00" min="1" class="form-input" autofocus>
            </div>
        `, [
            { label: 'Cancel', class: 'btn-secondary', action: () => this.closeModal() },
            { label: 'Deposit', class: 'btn-success', icon: 'fa-plus', action: () => {
                const amount = parseFloat(document.getElementById('quickDepositAmount').value);
                if (!amount || amount <= 0) return this.showToast('Enter a valid amount', 'error');
                this.fetchNUI('deposit', { accountId: this.selectedAccount.id, amount: amount });
                this.closeModal();
            }},
        ]);
    },

    quickWithdraw: function() {
        if (!this.selectedAccount) return this.showToast('Please select an account first', 'warning');

        this.showModal('Withdraw Money', `
            <div class="form-group">
                <label>Amount ($)</label>
                <input type="number" id="quickWithdrawAmount" placeholder="0.00" min="1" class="form-input" autofocus>
            </div>
            <p style="font-size:12px;color:var(--text-secondary)">Available: ${this.formatMoney(this.selectedAccount.balance)}</p>
        `, [
            { label: 'Cancel', class: 'btn-secondary', action: () => this.closeModal() },
            { label: 'Withdraw', class: 'btn-danger', icon: 'fa-minus', action: () => {
                const amount = parseFloat(document.getElementById('quickWithdrawAmount').value);
                if (!amount || amount <= 0) return this.showToast('Enter a valid amount', 'error');
                this.fetchNUI('withdraw', { accountId: this.selectedAccount.id, amount: amount });
                this.closeModal();
            }},
        ]);
    },

    // ============================================================
    // TRANSFERS
    // ============================================================

    submitTransfer: function() {
        if (!this.selectedAccount) return this.showToast('Please select an account first', 'warning');

        const iban = document.getElementById('transferIban').value.trim();
        const amount = parseFloat(document.getElementById('transferAmount').value);
        const desc = document.getElementById('transferDesc').value.trim();

        if (!iban) return this.showToast('Enter recipient IBAN', 'error');
        if (!amount || amount <= 0) return this.showToast('Enter a valid amount', 'error');

        this.fetchNUI('transfer', {
            fromAccountId: this.selectedAccount.id,
            toIban: iban,
            amount: amount,
            description: desc,
        });

        // Clear form
        document.getElementById('transferIban').value = '';
        document.getElementById('transferAmount').value = '';
        document.getElementById('transferDesc').value = '';
        document.getElementById('transferFeePreview').textContent = '';
    },

    submitScheduledTransfer: function() {
        if (!this.selectedAccount) return this.showToast('Please select an account first', 'warning');

        const iban = document.getElementById('schedIban').value.trim();
        const amount = parseFloat(document.getElementById('schedAmount').value);
        const frequency = document.getElementById('schedFrequency').value;
        const date = document.getElementById('schedDate').value;
        const desc = document.getElementById('schedDesc').value.trim();

        if (!iban) return this.showToast('Enter recipient IBAN', 'error');
        if (!amount || amount <= 0) return this.showToast('Enter a valid amount', 'error');
        if (!date) return this.showToast('Select execution date', 'error');

        this.fetchNUI('scheduleTransfer', {
            fromAccountId: this.selectedAccount.id,
            toIban: iban,
            amount: amount,
            description: desc,
            frequency: frequency,
            executeDate: date,
        });

        this.showToast('Transfer scheduled!', 'success');
    },

    updateTransferFeePreview: function(amount) {
        const preview = document.getElementById('transferFeePreview');
        if (amount <= 0) {
            preview.textContent = '';
            return;
        }
        const feePercent = 0.5;
        const fee = Math.max(5, Math.min(5000, amount * feePercent / 100));
        preview.textContent = `Transfer fee: ${this.formatMoney(fee)} | Total deducted: ${this.formatMoney(amount + fee)}`;
    },

    // ============================================================
    // CARDS
    // ============================================================

    loadCards: function() {
        if (!this.selectedAccount) return;

        this.fetchNUI('getCards', { accountId: this.selectedAccount.id }).then(cards => {
            const container = document.getElementById('cardsList');

            if (!cards || cards.length === 0) {
                container.innerHTML = '<div class="empty-state-box"><i class="fas fa-credit-card"></i><p>No cards yet. Create your first virtual card!</p></div>';
                return;
            }

            container.innerHTML = cards.map(card => `
                <div class="virtual-card ${card.is_blocked ? 'blocked' : ''}">
                    <div class="card-chip"></div>
                    <div class="card-number">${card.masked_number.replace(/(.{4})/g, '$1 ').trim()}</div>
                    <div class="card-details">
                        <div>
                            <div class="card-holder">Card Holder</div>
                            <div class="card-holder-name">${card.holder_name}</div>
                        </div>
                        <div class="card-expiry">
                            <div class="card-expiry-label">Expires</div>
                            <div class="card-expiry-value">${this.formatCardExpiry(card.expiry_date)}</div>
                        </div>
                    </div>
                    <div class="card-actions">
                        <button class="btn btn-sm ${card.is_blocked ? 'btn-success' : 'btn-danger'}"
                                onclick="App.toggleCardBlock(${card.id})">
                            <i class="fas fa-${card.is_blocked ? 'unlock' : 'lock'}"></i>
                            ${card.is_blocked ? 'Unblock' : 'Block'}
                        </button>
                    </div>
                </div>
            `).join('');
        });
    },

    createCard: function() {
        if (!this.selectedAccount) return this.showToast('Please select an account first', 'warning');
        this.fetchNUI('createCard', { accountId: this.selectedAccount.id });
        setTimeout(() => this.loadCards(), 500);
    },

    toggleCardBlock: function(cardId) {
        this.fetchNUI('toggleCardBlock', { cardId: cardId });
        setTimeout(() => this.loadCards(), 500);
    },

    formatCardExpiry: function(date) {
        if (!date) return '--/--';
        const d = new Date(date);
        return (d.getMonth() + 1).toString().padStart(2, '0') + '/' + d.getFullYear().toString().slice(-2);
    },

    // ============================================================
    // LOANS
    // ============================================================

    loadLoans: function() {
        this.fetchNUI('getLoanPlans', {}).then(plans => {
            this.renderLoanPlans(plans || []);
        });

        this.fetchNUI('getLoans', {}).then(loans => {
            this.renderActiveLoans(loans || []);
        });

        // Update credit score display
        if (this.selectedAccount) {
            this.fetchNUI('getDashboard', { accountId: this.selectedAccount.id }).then(data => {
                if (!data) return;
                const score = data.creditScore || 0;
                document.getElementById('creditScoreValue').textContent = score;
                document.getElementById('creditScoreFill').style.width = ((score / 850) * 100) + '%';

                const circle = document.getElementById('creditScoreCircle');
                circle.style.borderColor = score >= 700 ? '#10b981' : score >= 500 ? '#f59e0b' : '#ef4444';
            });
        }
    },

    renderLoanPlans: function(plans) {
        const container = document.getElementById('loanPlansList');

        if (plans.length === 0) {
            container.innerHTML = '<div class="empty-state-box"><i class="fas fa-hand-holding-usd"></i><p>No loan plans available</p></div>';
            return;
        }

        container.innerHTML = plans.map(plan => `
            <div class="loan-plan-card ${plan.eligible ? '' : 'ineligible'}">
                <div class="loan-plan-header">
                    <h4>${plan.label}</h4>
                    <span class="badge ${plan.eligible ? 'badge-success' : 'badge-danger'}">
                        ${plan.eligible ? 'Eligible' : 'Not Eligible'}
                    </span>
                </div>
                <div class="loan-plan-body">
                    <p>${plan.description}</p>
                    <div class="loan-detail">
                        <span class="loan-detail-label">Amount Range</span>
                        <span class="loan-detail-value">${this.formatMoney(plan.minAmount)} - ${this.formatMoney(plan.maxAmount)}</span>
                    </div>
                    <div class="loan-detail">
                        <span class="loan-detail-label">Interest Rate</span>
                        <span class="loan-detail-value">${plan.interestRate}%</span>
                    </div>
                    <div class="loan-detail">
                        <span class="loan-detail-label">Duration</span>
                        <span class="loan-detail-value">${plan.durationDays} days</span>
                    </div>
                    <div class="loan-detail">
                        <span class="loan-detail-label">Installments</span>
                        <span class="loan-detail-value">${plan.installments}</span>
                    </div>
                    <div class="loan-detail">
                        <span class="loan-detail-label">Min Credit Score</span>
                        <span class="loan-detail-value">${plan.minCreditScore}</span>
                    </div>
                </div>
                ${plan.eligible ? `
                    <button class="btn btn-primary btn-block" onclick="App.applyForLoan('${plan.id}', ${plan.minAmount}, ${plan.maxAmount})">
                        <i class="fas fa-hand-holding-usd"></i> Apply Now
                    </button>
                ` : `
                    <button class="btn btn-secondary btn-block" disabled>
                        Credit score too low (need ${plan.minCreditScore})
                    </button>
                `}
            </div>
        `).join('');
    },

    renderActiveLoans: function(loans) {
        const container = document.getElementById('activeLoansList');

        const activeLoans = loans.filter(l => l.status === 'active');
        if (activeLoans.length === 0) {
            container.innerHTML = '<div class="empty-state-box"><i class="fas fa-hand-holding-usd"></i><p>No active loans</p></div>';
            return;
        }

        container.innerHTML = activeLoans.map(loan => {
            const progress = (parseFloat(loan.amount_paid) / (parseFloat(loan.total_amount) + parseFloat(loan.late_fees))) * 100;
            const remaining = parseFloat(loan.total_amount) + parseFloat(loan.late_fees) - parseFloat(loan.amount_paid);

            return `
                <div class="active-loan-item">
                    <div class="loan-header">
                        <h4>${loan.plan_id.charAt(0).toUpperCase() + loan.plan_id.slice(1)} Loan #${loan.id}</h4>
                        <span class="badge badge-${loan.status === 'active' ? 'primary' : 'danger'}">${loan.status}</span>
                    </div>
                    <div class="loan-progress">
                        <div class="loan-progress-bar">
                            <div class="loan-progress-fill" style="width: ${Math.min(100, progress)}%"></div>
                        </div>
                        <div class="loan-progress-text">
                            <span>Paid: ${this.formatMoney(loan.amount_paid)}</span>
                            <span>Remaining: ${this.formatMoney(remaining)}</span>
                        </div>
                    </div>
                    <div class="loan-details-grid">
                        <div class="loan-detail-box">
                            <div class="label">Principal</div>
                            <div class="value">${this.formatMoney(loan.principal)}</div>
                        </div>
                        <div class="loan-detail-box">
                            <div class="label">Interest</div>
                            <div class="value">${this.formatMoney(loan.interest)}</div>
                        </div>
                        <div class="loan-detail-box">
                            <div class="label">Late Fees</div>
                            <div class="value">${this.formatMoney(loan.late_fees)}</div>
                        </div>
                    </div>
                    <div style="display:flex;gap:8px">
                        <button class="btn btn-success btn-block" onclick="App.repayLoanPrompt(${loan.id}, ${remaining})">
                            <i class="fas fa-money-bill-wave"></i> Make Payment
                        </button>
                    </div>
                </div>
            `;
        }).join('');
    },

    applyForLoan: function(planId, minAmount, maxAmount) {
        if (!this.selectedAccount) return this.showToast('Please select an account first', 'warning');

        this.showModal('Apply for Loan', `
            <div class="form-group">
                <label>Loan Amount ($)</label>
                <input type="number" id="loanAmount" placeholder="${minAmount}" min="${minAmount}" max="${maxAmount}" class="form-input" autofocus>
                <p style="font-size:12px;color:var(--text-secondary);margin-top:4px">Range: ${this.formatMoney(minAmount)} - ${this.formatMoney(maxAmount)}</p>
            </div>
        `, [
            { label: 'Cancel', class: 'btn-secondary', action: () => this.closeModal() },
            { label: 'Apply', class: 'btn-primary', icon: 'fa-paper-plane', action: () => {
                const amount = parseFloat(document.getElementById('loanAmount').value);
                if (!amount || amount < minAmount || amount > maxAmount) {
                    return this.showToast('Enter a valid amount within range', 'error');
                }
                this.fetchNUI('applyLoan', {
                    planId: planId,
                    amount: amount,
                    accountId: this.selectedAccount.id,
                });
                this.closeModal();
                setTimeout(() => this.loadLoans(), 500);
            }},
        ]);
    },

    repayLoanPrompt: function(loanId, maxAmount) {
        if (!this.selectedAccount) return this.showToast('Please select an account first', 'warning');

        this.showModal('Repay Loan', `
            <div class="form-group">
                <label>Payment Amount ($)</label>
                <input type="number" id="repayAmount" placeholder="${maxAmount.toFixed(2)}" max="${maxAmount}" class="form-input" autofocus>
                <p style="font-size:12px;color:var(--text-secondary);margin-top:4px">Remaining: ${this.formatMoney(maxAmount)}</p>
            </div>
        `, [
            { label: 'Cancel', class: 'btn-secondary', action: () => this.closeModal() },
            { label: 'Pay', class: 'btn-success', icon: 'fa-money-bill-wave', action: () => {
                const amount = parseFloat(document.getElementById('repayAmount').value) || maxAmount;
                this.fetchNUI('repayLoan', {
                    loanId: loanId,
                    amount: amount,
                    accountId: this.selectedAccount.id,
                });
                this.closeModal();
                setTimeout(() => this.loadLoans(), 500);
            }},
        ]);
    },

    // ============================================================
    // BILLING
    // ============================================================

    loadInvoices: function() {
        this.fetchNUI('getInvoices', {}).then(data => {
            if (!data) return;
            this.renderInvoices(data.received || [], 'receivedInvoices', true);
            this.renderInvoices(data.sent || [], 'sentInvoices', false);
        });
    },

    renderInvoices: function(invoices, containerId, showPayButton) {
        const container = document.getElementById(containerId);

        if (invoices.length === 0) {
            container.innerHTML = '<div class="empty-state-box"><i class="fas fa-file-invoice"></i><p>No invoices</p></div>';
            return;
        }

        container.innerHTML = invoices.map(inv => {
            const remaining = parseFloat(inv.amount) - parseFloat(inv.amount_paid);
            const statusBadge = this.getInvoiceStatusBadge(inv.status);

            return `
                <div class="invoice-item">
                    <div class="invoice-icon">
                        <i class="fas fa-file-invoice-dollar"></i>
                    </div>
                    <div class="invoice-details">
                        <div class="invoice-title">${inv.invoice_number} - ${inv.category}</div>
                        <div class="invoice-meta">
                            ${inv.description || 'No description'} | ${this.formatDate(inv.created_at)}
                            ${inv.from_job ? ' | Job: ' + inv.from_job : ''}
                        </div>
                    </div>
                    <div class="invoice-amount">
                        ${this.formatMoney(inv.amount)}
                        ${inv.amount_paid > 0 ? `<br><span style="font-size:11px;color:var(--text-secondary)">Paid: ${this.formatMoney(inv.amount_paid)}</span>` : ''}
                    </div>
                    <span class="badge ${statusBadge.class}">${statusBadge.label}</span>
                    ${showPayButton && (inv.status === 'pending' || inv.status === 'overdue') ? `
                        <div class="invoice-actions">
                            <button class="btn btn-success btn-sm" onclick="App.payInvoicePrompt(${inv.id}, ${remaining})">
                                <i class="fas fa-money-bill-wave"></i> Pay
                            </button>
                        </div>
                    ` : ''}
                </div>
            `;
        }).join('');
    },

    getInvoiceStatusBadge: function(status) {
        const badges = {
            pending: { class: 'badge-warning', label: 'Pending' },
            partial: { class: 'badge-info', label: 'Partial' },
            paid: { class: 'badge-success', label: 'Paid' },
            overdue: { class: 'badge-danger', label: 'Overdue' },
            cancelled: { class: 'badge-secondary', label: 'Cancelled' },
        };
        return badges[status] || { class: 'badge-info', label: status };
    },

    showSendInvoice: function() {
        this.showModal('Send Invoice', `
            <div class="form-group">
                <label>Recipient Citizen ID</label>
                <input type="text" id="invoiceCitizenId" placeholder="Citizen ID" class="form-input">
            </div>
            <div class="form-group">
                <label>Amount ($)</label>
                <input type="number" id="invoiceAmount" placeholder="0.00" min="1" class="form-input">
            </div>
            <div class="form-group">
                <label>Category</label>
                <select id="invoiceCategory" class="form-input">
                    <option value="service">Service</option>
                    <option value="fine">Fine</option>
                    <option value="medical">Medical</option>
                    <option value="repair">Repair</option>
                    <option value="legal">Legal Fee</option>
                    <option value="other">Other</option>
                </select>
            </div>
            <div class="form-group">
                <label>Description</label>
                <input type="text" id="invoiceDesc" placeholder="Description..." class="form-input">
            </div>
        `, [
            { label: 'Cancel', class: 'btn-secondary', action: () => this.closeModal() },
            { label: 'Send Invoice', class: 'btn-primary', icon: 'fa-paper-plane', action: () => {
                const citizenId = document.getElementById('invoiceCitizenId').value.trim();
                const amount = parseFloat(document.getElementById('invoiceAmount').value);
                const category = document.getElementById('invoiceCategory').value;
                const desc = document.getElementById('invoiceDesc').value.trim();

                if (!citizenId) return this.showToast('Enter recipient citizen ID', 'error');
                if (!amount || amount <= 0) return this.showToast('Enter a valid amount', 'error');

                this.fetchNUI('sendInvoice', {
                    targetCitizenId: citizenId,
                    amount: amount,
                    category: category,
                    description: desc,
                });
                this.closeModal();
            }},
        ]);
    },

    payInvoicePrompt: function(invoiceId, remaining) {
        if (!this.selectedAccount) return this.showToast('Please select an account first', 'warning');

        this.showModal('Pay Invoice', `
            <div class="form-group">
                <label>Payment Amount ($)</label>
                <input type="number" id="invoicePayAmount" placeholder="${remaining.toFixed(2)}" max="${remaining}" class="form-input" autofocus>
                <p style="font-size:12px;color:var(--text-secondary);margin-top:4px">Remaining: ${this.formatMoney(remaining)}</p>
            </div>
        `, [
            { label: 'Cancel', class: 'btn-secondary', action: () => this.closeModal() },
            { label: 'Pay', class: 'btn-success', icon: 'fa-money-bill-wave', action: () => {
                const amount = parseFloat(document.getElementById('invoicePayAmount').value) || remaining;
                this.fetchNUI('payInvoice', {
                    invoiceId: invoiceId,
                    accountId: this.selectedAccount.id,
                    amount: amount,
                });
                this.closeModal();
                setTimeout(() => this.loadInvoices(), 500);
            }},
        ]);
    },

    // ============================================================
    // TAXES
    // ============================================================

    loadTaxRecords: function() {
        this.fetchNUI('getTaxRecords', {}).then(data => {
            if (!data) return;

            // Render summary
            const summary = data.summary || [];
            const summaryContainer = document.getElementById('taxSummary');
            summaryContainer.innerHTML = summary.map(s => `
                <div class="stat-card danger">
                    <div class="stat-icon"><i class="fas fa-receipt"></i></div>
                    <div class="stat-info">
                        <span class="stat-label">${s.tax_type} Tax</span>
                        <span class="stat-value">${this.formatMoney(s.total_paid)}</span>
                    </div>
                </div>
            `).join('');

            // Render records
            const tbody = document.getElementById('taxRecordsList');
            const records = data.records || [];

            if (records.length === 0) {
                tbody.innerHTML = '<tr><td colspan="6" class="empty-state">No tax records</td></tr>';
                return;
            }

            tbody.innerHTML = records.map(r => `
                <tr>
                    <td>${this.formatDate(r.created_at)}</td>
                    <td><span class="badge badge-danger">${r.tax_type}</span></td>
                    <td>${this.formatMoney(r.taxable_amount)}</td>
                    <td>${r.rate}%</td>
                    <td class="amount-negative">${this.formatMoney(r.amount)}</td>
                    <td>${r.description || '-'}</td>
                </tr>
            `).join('');
        });
    },

    // ============================================================
    // ACCOUNT MANAGEMENT
    // ============================================================

    showCreateAccount: function() {
        this.showModal('Create New Account', `
            <div class="form-group">
                <label>Account Type</label>
                <select id="newAccountType" class="form-input">
                    <option value="personal">Personal Account</option>
                    <option value="business">Business Account</option>
                    <option value="shared">Shared Account</option>
                </select>
            </div>
            <div class="form-group">
                <label>Account Name (optional)</label>
                <input type="text" id="newAccountName" placeholder="My Account" class="form-input">
            </div>
        `, [
            { label: 'Cancel', class: 'btn-secondary', action: () => this.closeModal() },
            { label: 'Create Account', class: 'btn-primary', icon: 'fa-plus', action: () => {
                const type = document.getElementById('newAccountType').value;
                const name = document.getElementById('newAccountName').value.trim();
                this.fetchNUI('createAccount', { accountType: type, accountName: name || null });
                this.closeModal();
                setTimeout(() => this.loadAccounts(), 500);
            }},
        ]);
    },

    closeAccountPrompt: function(accountId) {
        this.showModal('Close Account', `
            <p style="color:var(--text-secondary)">Are you sure you want to close this account? Any remaining balance will be returned as cash.</p>
        `, [
            { label: 'Cancel', class: 'btn-secondary', action: () => this.closeModal() },
            { label: 'Close Account', class: 'btn-danger', icon: 'fa-times', action: () => {
                this.fetchNUI('closeAccount', { accountId: accountId });
                this.closeModal();
                setTimeout(() => this.loadAccounts(), 500);
            }},
        ]);
    },

    // ============================================================
    // ADMIN
    // ============================================================

    loadAdminData: function() {
        this.fetchNUI('admin:getOverview', {}).then(data => {
            if (!data) return;

            const container = document.getElementById('adminStats');
            container.innerHTML = `
                <div class="stat-card primary">
                    <div class="stat-icon"><i class="fas fa-wallet"></i></div>
                    <div class="stat-info">
                        <span class="stat-label">Total Accounts</span>
                        <span class="stat-value">${data.totalAccounts}</span>
                    </div>
                </div>
                <div class="stat-card success">
                    <div class="stat-icon"><i class="fas fa-coins"></i></div>
                    <div class="stat-info">
                        <span class="stat-label">Total Balance</span>
                        <span class="stat-value">${this.formatMoney(data.totalBalance)}</span>
                    </div>
                </div>
                <div class="stat-card warning">
                    <div class="stat-icon"><i class="fas fa-hand-holding-usd"></i></div>
                    <div class="stat-info">
                        <span class="stat-label">Active Loans</span>
                        <span class="stat-value">${data.activeLoans}</span>
                    </div>
                </div>
                <div class="stat-card danger">
                    <div class="stat-icon"><i class="fas fa-receipt"></i></div>
                    <div class="stat-info">
                        <span class="stat-label">Tax Collected</span>
                        <span class="stat-value">${this.formatMoney(data.totalTaxCollected)}</span>
                    </div>
                </div>
            `;
        });

        this.fetchNUI('admin:getLogs', { page: 1 }).then(data => {
            if (!data) return;
            this.renderAdminLogs(data.logs || []);
        });
    },

    adminSearch: function() {
        const query = document.getElementById('adminSearch').value.trim();
        if (!query) return;

        this.fetchNUI('admin:searchAccounts', { query: query }).then(accounts => {
            const container = document.getElementById('adminSearchResults');

            if (!accounts || accounts.length === 0) {
                container.innerHTML = '<p style="color:var(--text-secondary);padding:16px">No results found</p>';
                return;
            }

            container.innerHTML = accounts.map(acc => `
                <div class="admin-account-row">
                    <div class="admin-account-info">
                        <strong>${acc.iban}</strong>
                        <span>${acc.owner_citizenid} | ${acc.account_type} | ${this.formatMoney(acc.balance)}</span>
                    </div>
                    <div class="admin-account-actions">
                        <button class="btn btn-sm btn-primary" onclick="App.adminSetBalance(${acc.id}, ${acc.balance})">
                            <i class="fas fa-edit"></i> Set Balance
                        </button>
                        <button class="btn btn-sm ${acc.is_frozen ? 'btn-success' : 'btn-warning'}" onclick="App.adminToggleFreeze(${acc.id})">
                            <i class="fas fa-${acc.is_frozen ? 'unlock' : 'lock'}"></i> ${acc.is_frozen ? 'Unfreeze' : 'Freeze'}
                        </button>
                    </div>
                </div>
            `).join('');
        });
    },

    renderAdminLogs: function(logs) {
        const tbody = document.getElementById('adminLogsList');

        if (logs.length === 0) {
            tbody.innerHTML = '<tr><td colspan="5" class="empty-state">No logs</td></tr>';
            return;
        }

        tbody.innerHTML = logs.map(log => `
            <tr>
                <td>${this.formatDate(log.created_at)}</td>
                <td>${log.admin_citizenid}</td>
                <td><span class="badge badge-info">${log.action}</span></td>
                <td>${log.target_citizenid || '-'}</td>
                <td>${log.details ? JSON.stringify(JSON.parse(log.details)).substring(0, 50) : '-'}</td>
            </tr>
        `).join('');
    },

    adminSetBalance: function(accountId, currentBalance) {
        this.showModal('Set Account Balance', `
            <div class="form-group">
                <label>New Balance ($)</label>
                <input type="number" id="adminNewBalance" value="${currentBalance}" class="form-input" autofocus>
            </div>
        `, [
            { label: 'Cancel', class: 'btn-secondary', action: () => this.closeModal() },
            { label: 'Set Balance', class: 'btn-primary', action: () => {
                const amount = parseFloat(document.getElementById('adminNewBalance').value);
                if (isNaN(amount) || amount < 0) return this.showToast('Enter a valid amount', 'error');
                this.fetchNUI('admin:setBalance', { accountId: accountId, amount: amount });
                this.closeModal();
            }},
        ]);
    },

    adminToggleFreeze: function(accountId) {
        this.fetchNUI('admin:toggleFreeze', { accountId: accountId });
        setTimeout(() => this.adminSearch(), 500);
    },

    // ============================================================
    // MODAL SYSTEM
    // ============================================================

    showModal: function(title, bodyHtml, buttons) {
        document.getElementById('modalTitle').textContent = title;
        document.getElementById('modalBody').innerHTML = bodyHtml;

        const footer = document.getElementById('modalFooter');
        footer.innerHTML = '';

        if (buttons) {
            buttons.forEach(btn => {
                const button = document.createElement('button');
                button.className = 'btn ' + (btn.class || 'btn-primary');
                button.innerHTML = (btn.icon ? `<i class="fas ${btn.icon}"></i> ` : '') + btn.label;
                button.addEventListener('click', btn.action);
                footer.appendChild(button);
            });
        }

        document.getElementById('modalOverlay').classList.remove('hidden');
    },

    closeModal: function() {
        document.getElementById('modalOverlay').classList.add('hidden');
    },

    // ============================================================
    // TOAST NOTIFICATIONS
    // ============================================================

    showToast: function(message, type, duration) {
        const container = document.getElementById('toastContainer');
        const toast = document.createElement('div');
        toast.className = 'toast toast-' + (type || 'info');

        const icons = {
            success: 'fa-check-circle',
            error: 'fa-exclamation-circle',
            warning: 'fa-exclamation-triangle',
            info: 'fa-info-circle',
        };

        toast.innerHTML = `
            <i class="fas ${icons[type] || icons.info}"></i>
            <span class="toast-message">${message}</span>
        `;

        container.appendChild(toast);

        setTimeout(() => {
            toast.style.animation = 'toastOut 0.3s ease forwards';
            setTimeout(() => toast.remove(), 300);
        }, duration || 5000);
    },

    // ============================================================
    // THEME
    // ============================================================

    toggleTheme: function() {
        this.isDarkMode = !this.isDarkMode;
        document.documentElement.classList.toggle('dark', this.isDarkMode);

        const icon = document.querySelector('#themeToggle i');
        icon.className = this.isDarkMode ? 'fas fa-sun' : 'fas fa-moon';

        localStorage.setItem('qb-banking-theme', this.isDarkMode ? 'dark' : 'light');
    },

    loadThemePreference: function() {
        const savedTheme = localStorage.getItem('qb-banking-theme');
        if (savedTheme === 'dark') {
            this.isDarkMode = true;
            document.documentElement.classList.add('dark');
            const icon = document.querySelector('#themeToggle i');
            if (icon) icon.className = 'fas fa-sun';
        }
    },

    // ============================================================
    // SOUND SYSTEM
    // ============================================================

    playSound: function(sound, volume) {
        // Sound effects would be loaded from assets/sounds/
        // For now this is a stub - add .ogg files to assets/sounds/ to enable
        try {
            const audio = new Audio('assets/sounds/' + sound + '.ogg');
            audio.volume = volume || 0.3;
            audio.play().catch(() => {});
        } catch (e) {
            // Silent fail if sound not found
        }
    },

    // ============================================================
    // UTILITY FUNCTIONS
    // ============================================================

    formatMoney: function(amount) {
        amount = parseFloat(amount) || 0;
        return '$' + amount.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    },

    formatDate: function(dateStr) {
        if (!dateStr) return '--';
        const d = new Date(dateStr);
        if (isNaN(d.getTime())) return dateStr;
        return d.toLocaleDateString('en-US', {
            year: 'numeric',
            month: 'short',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit',
        });
    },

    /**
     * Send NUI callback to client
     */
    fetchNUI: function(event, data) {
        return fetch('https://qb-banking/' + event, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data || {}),
        })
        .then(res => res.json())
        .catch(err => {
            console.error('NUI Fetch error:', err);
            return null;
        });
    },
};

// Initialize on DOM ready
document.addEventListener('DOMContentLoaded', () => {
    App.init();
});
