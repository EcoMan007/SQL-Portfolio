USE AdventureWorksDW2019;

;WITH MonthEnds AS
(
    -- Select last 5 years of month end dates
    SELECT DISTINCT
        MonthYear = FORMAT(FullDateAlternateKey, 'MMM-yyyy'),
        LastDayOfMonth = EOMONTH(FullDateAlternateKey),
        FirstDayOfMonth = DATEFROMPARTS(CalendarYear, MonthNumberOfYear, 1)
    FROM dbo.DimDate
    WHERE FullDateAlternateKey > DATEADD(YEAR, -5, GETDATE())
      AND FullDateAlternateKey < GETDATE()
),
MonthEndsCustomers AS
(
    -- Cross join each customer with each month end
    SELECT 
        m.MonthYear,
        m.LastDayOfMonth,
        m.FirstDayOfMonth,
        c.CustomerKey
    FROM MonthEnds m
    CROSS JOIN dbo.DimCustomer c
),
CustomerHistory AS
(
    -- Simulate a credit limit history using FactSalesQuota
    SELECT 
        e.EmployeeKey AS CustomerKey,   -- stand-in for PartnerFinanceCustomerNo
        e.SalesQuotaDate AS EffectiveDate,
        MonthYear = FORMAT(e.SalesQuotaDate, 'MMM-yyyy'),
        CreditLimit = e.SalesAmountQuota,   -- pretend this is credit limit
        Ranks = DENSE_RANK() OVER (
            PARTITION BY e.EmployeeKey, FORMAT(e.SalesQuotaDate,'MM-yyyy')
            ORDER BY MAX(e.SalesQuotaDate) DESC
        )
    FROM dbo.FactSalesQuota e
    GROUP BY e.EmployeeKey, e.SalesQuotaDate, e.SalesAmountQuota
),
tblInterim AS
(
    SELECT
        c.CustomerKey,
        c.LastDayOfMonth,
        c.MonthYear,
        [CreditLimitAtME] = h.CreditLimit,
        h.EffectiveDate,
        RowNo = ROW_NUMBER() OVER (PARTITION BY c.CustomerKey ORDER BY c.LastDayOfMonth)
    FROM MonthEndsCustomers c
    LEFT JOIN CustomerHistory h
      ON h.CustomerKey = c.CustomerKey
     AND h.MonthYear = c.MonthYear
     AND h.Ranks = 1
)
SELECT
    CustomerKey,
    MonthYear,
    CreditLimitAtME = ISNULL(ISNULL(ti.CreditLimitAtME, x.CreditLimitAtME), 0),
    ti.LastDayOfMonth
FROM tblInterim ti
OUTER APPLY
(
    -- Find most recent prior credit limit > 10
    SELECT TOP 1 
        i.CreditLimitAtME,
        DenseRank = DENSE_RANK() OVER (
            PARTITION BY i.CustomerKey ORDER BY i.LastDayOfMonth DESC
        )
    FROM tblInterim i
    WHERE i.CustomerKey = ti.CustomerKey
      AND i.CreditLimitAtME > 10
      AND i.LastDayOfMonth < ti.LastDayOfMonth
) x
WHERE ti.LastDayOfMonth <= EOMONTH(GETDATE())
ORDER BY CustomerKey, ti.LastDayOfMonth;
