/* ============================================================
   QB Banking - Lightweight Canvas Chart Library
   No external dependencies required
   ============================================================ */

const ChartLib = {
    /**
     * Draw a bar chart on a canvas element
     * @param {string} canvasId - Canvas element ID
     * @param {object} data - Chart data { labels: [], datasets: [{ label, data, color }] }
     * @param {object} options - Chart options
     */
    barChart: function(canvasId, data, options = {}) {
        const canvas = document.getElementById(canvasId);
        if (!canvas) return;

        const ctx = canvas.getContext('2d');
        const dpr = window.devicePixelRatio || 1;
        const rect = canvas.parentElement.getBoundingClientRect();

        canvas.width = rect.width * dpr;
        canvas.height = (options.height || 250) * dpr;
        canvas.style.width = rect.width + 'px';
        canvas.style.height = (options.height || 250) + 'px';
        ctx.scale(dpr, dpr);

        const width = rect.width;
        const height = options.height || 250;
        const padding = { top: 30, right: 20, bottom: 40, left: 70 };
        const chartWidth = width - padding.left - padding.right;
        const chartHeight = height - padding.top - padding.bottom;

        // Clear canvas
        ctx.clearRect(0, 0, width, height);

        if (!data.labels || data.labels.length === 0) {
            ctx.fillStyle = '#9ca3af';
            ctx.font = '14px Inter, sans-serif';
            ctx.textAlign = 'center';
            ctx.fillText('No data available', width / 2, height / 2);
            return;
        }

        // Calculate max value
        let maxVal = 0;
        data.datasets.forEach(ds => {
            ds.data.forEach(v => { if (v > maxVal) maxVal = v; });
        });
        maxVal = maxVal * 1.1 || 100;

        // Draw grid lines
        const gridLines = 5;
        ctx.strokeStyle = this.getThemeColor('border');
        ctx.lineWidth = 0.5;
        ctx.font = '11px Inter, sans-serif';
        ctx.fillStyle = this.getThemeColor('textSecondary');
        ctx.textAlign = 'right';

        for (let i = 0; i <= gridLines; i++) {
            const y = padding.top + (chartHeight / gridLines) * i;
            const value = maxVal - (maxVal / gridLines) * i;

            ctx.beginPath();
            ctx.moveTo(padding.left, y);
            ctx.lineTo(width - padding.right, y);
            ctx.stroke();

            ctx.fillText(this.formatNumber(value), padding.left - 8, y + 4);
        }

        // Draw bars
        const groupWidth = chartWidth / data.labels.length;
        const barWidth = Math.min(groupWidth * 0.3, 30);
        const barGap = 4;

        data.datasets.forEach((ds, dsIndex) => {
            ds.data.forEach((value, i) => {
                const barHeight = (value / maxVal) * chartHeight;
                const x = padding.left + groupWidth * i + (groupWidth / 2) - ((data.datasets.length * (barWidth + barGap)) / 2) + dsIndex * (barWidth + barGap);
                const y = padding.top + chartHeight - barHeight;

                // Draw bar with rounded top
                ctx.fillStyle = ds.color || '#3b82f6';
                ctx.beginPath();
                const radius = Math.min(4, barWidth / 2);
                ctx.moveTo(x, y + radius);
                ctx.arcTo(x, y, x + barWidth, y, radius);
                ctx.arcTo(x + barWidth, y, x + barWidth, y + barHeight, radius);
                ctx.lineTo(x + barWidth, padding.top + chartHeight);
                ctx.lineTo(x, padding.top + chartHeight);
                ctx.closePath();
                ctx.fill();
            });
        });

        // Draw x-axis labels
        ctx.fillStyle = this.getThemeColor('textSecondary');
        ctx.font = '11px Inter, sans-serif';
        ctx.textAlign = 'center';

        data.labels.forEach((label, i) => {
            const x = padding.left + groupWidth * i + groupWidth / 2;
            ctx.fillText(label, x, height - 10);
        });

        // Draw legend
        if (data.datasets.length > 1) {
            let legendX = padding.left;
            const legendY = 12;

            data.datasets.forEach((ds) => {
                ctx.fillStyle = ds.color || '#3b82f6';
                ctx.fillRect(legendX, legendY - 6, 12, 12);
                ctx.fillStyle = this.getThemeColor('textPrimary');
                ctx.font = '11px Inter, sans-serif';
                ctx.textAlign = 'left';
                ctx.fillText(ds.label || '', legendX + 16, legendY + 4);
                legendX += ctx.measureText(ds.label || '').width + 36;
            });
        }
    },

    /**
     * Format large numbers for axis labels
     */
    formatNumber: function(num) {
        if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
        if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
        return Math.round(num).toString();
    },

    /**
     * Get theme-aware colors
     */
    getThemeColor: function(type) {
        const isDark = document.documentElement.classList.contains('dark');
        const colors = {
            textPrimary: isDark ? '#e5e7eb' : '#1a1d23',
            textSecondary: isDark ? '#9ca3af' : '#6b7280',
            border: isDark ? '#2d3139' : '#e5e7eb',
            bg: isDark ? '#1a1d26' : '#ffffff',
        };
        return colors[type] || colors.textPrimary;
    },

    /**
     * Draw a donut chart
     */
    donutChart: function(canvasId, data, options = {}) {
        const canvas = document.getElementById(canvasId);
        if (!canvas) return;

        const ctx = canvas.getContext('2d');
        const dpr = window.devicePixelRatio || 1;
        const size = options.size || 150;

        canvas.width = size * dpr;
        canvas.height = size * dpr;
        canvas.style.width = size + 'px';
        canvas.style.height = size + 'px';
        ctx.scale(dpr, dpr);

        const centerX = size / 2;
        const centerY = size / 2;
        const radius = (size / 2) - 10;
        const lineWidth = options.lineWidth || 20;

        ctx.clearRect(0, 0, size, size);

        const total = data.reduce((sum, item) => sum + item.value, 0);
        if (total === 0) {
            ctx.beginPath();
            ctx.arc(centerX, centerY, radius, 0, Math.PI * 2);
            ctx.strokeStyle = this.getThemeColor('border');
            ctx.lineWidth = lineWidth;
            ctx.stroke();
            return;
        }

        let startAngle = -Math.PI / 2;

        data.forEach(item => {
            const sliceAngle = (item.value / total) * Math.PI * 2;
            ctx.beginPath();
            ctx.arc(centerX, centerY, radius, startAngle, startAngle + sliceAngle);
            ctx.strokeStyle = item.color;
            ctx.lineWidth = lineWidth;
            ctx.lineCap = 'round';
            ctx.stroke();
            startAngle += sliceAngle;
        });

        // Center text
        if (options.centerText) {
            ctx.fillStyle = this.getThemeColor('textPrimary');
            ctx.font = 'bold 18px Inter, sans-serif';
            ctx.textAlign = 'center';
            ctx.textBaseline = 'middle';
            ctx.fillText(options.centerText, centerX, centerY);
        }
    }
};
