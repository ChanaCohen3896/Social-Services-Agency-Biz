-- T-SQL script for SNAP eligibility calculations and reports

-- Drop existing objects if they exist
DROP VIEW IF EXISTS dbo.vw_SnapCalculation;
DROP TABLE IF EXISTS dbo.Applicants;
DROP TABLE IF EXISTS dbo.FamilySizeInfo;
GO

-- Table storing thresholds based on family size
CREATE TABLE dbo.FamilySizeInfo (
    FamilySize INT PRIMARY KEY CHECK (FamilySize BETWEEN 1 AND 17),
    GrossIncomeLimit DECIMAL(10,2) NOT NULL,
    MaxBenefitAmount DECIMAL(10,2) NOT NULL,
    StandardDeduction DECIMAL(10,2) NOT NULL
);
GO

-- Data for family size thresholds
INSERT INTO dbo.FamilySizeInfo (FamilySize, GrossIncomeLimit, MaxBenefitAmount, StandardDeduction) VALUES
    (1, 1986, 250, 177),
    (2, 2686, 459, 177),
    (3, 3386, 658, 177),
    (4, 4086, 835, 184),
    (5, 4786, 992, 215),
    (6, 5486, 119, 246),
    (7, 6186, 131, 246),
    (8, 6886, 150, 246),
    (9, 7586, 169, 246),
    (10, 8286, 188, 246),
    (11, 8986, 206, 246),
    (12, 9686, 225, 246),
    (13, 10386, 244, 246),
    (14, 11086, 263, 246),
    (15, 11786, 282, 246),
    (16, 12486, 281, 246),
    (17, 13186, 299, 246);
GO

-- Table storing applicant information
CREATE TABLE dbo.Applicants (
    ApplicantID INT IDENTITY PRIMARY KEY,
    FamilyName NVARCHAR(100) NOT NULL,
    PhoneNumber VARCHAR(20) NOT NULL,
    Address NVARCHAR(200) NOT NULL,
    FamilySize INT NOT NULL FOREIGN KEY REFERENCES dbo.FamilySizeInfo(FamilySize),
    EarnedIncome DECIMAL(10,2) NOT NULL CHECK (EarnedIncome >= 0),
    UnearnedIncome DECIMAL(10,2) NOT NULL CHECK (UnearnedIncome >= 0),
    DaycareExpense DECIMAL(10,2) NOT NULL CHECK (DaycareExpense >= 0),
    ShelterExpense DECIMAL(10,2) NOT NULL CHECK (ShelterExpense >= 0),
    UtilityExpense DECIMAL(10,2) NOT NULL CHECK (UtilityExpense >= 0),
    CONSTRAINT CK_TotalIncome CHECK (EarnedIncome + UnearnedIncome <= 25000)
);
GO

-- Sample applicant data
INSERT INTO dbo.Applicants (FamilyName, PhoneNumber, Address, FamilySize, EarnedIncome, UnearnedIncome, DaycareExpense, ShelterExpense, UtilityExpense)
VALUES
    ('Smith', '732-901-1234', '1 Happy Lane', 4, 2500, 500, 180, 900, 548),
    ('Adams', '732-942-0987', '2 Joyous Drive', 8, 5400, 1200, 360, 1750, 548),
    ('Jackson', '848-226-8765', '3 Momentous Place', 2, 1500, 1000, 0, 1000, 29),
    ('Tyler', '732-886-6543', '4 Drake Road', 3, 3000, 1200, 400, 1800, 548),
    ('Buchanan', '732-994-2345', '5 Hickory Drive', 15, 10000, 0, 810, 2250, 548),
    ('Arthur', '848-210-9843', '6 Misory Lane', 1, 9870, 0, 0, 670, 29),
    ('Wilson', '732-290-8764', '7 Smoke Lane', 3, 1500, 301, 230, 1000, 369),
    ('Hoover', '732-543-2109', '8 Justice Place', 7, 3434, 3434, 343, 1343, 548),
    ('Truman', '732-994-2210', '9 Yorktown Blvd', 5, 4500, 1200, 400, 1800, 548),
    ('Johnsohn', '732-998-7654', '10 Branchtown Road', 10, 10000, 500, 510, 1200, 548),
    ('Nixon', '732-886-4325', '11 Letsgo Place', 5, 400, 600, 300, 1150, 369),
    ('Carter', '732-990-9990', '12 Bored Town Road', 2, 2000, 500, 0, 1150, 369),
    ('Biden', '848-998-9876', '13 Icantthink Lane', 13, 9950, 100, 0, 1800, 548),
    ('Cohen', '732-765-4321', '14 Winya Place', 9, 6000, 1300, 400, 275, 369);
GO

-- View calculating benefit eligibility with intermediate steps
CREATE VIEW dbo.vw_SnapCalculation AS
SELECT
    a.ApplicantID,
    a.FamilyName,
    a.Address,
    a.FamilySize,
    a.EarnedIncome,
    a.UnearnedIncome,
    a.DaycareExpense,
    a.ShelterExpense,
    a.UtilityExpense,
    fs.GrossIncomeLimit,
    fs.MaxBenefitAmount,
    fs.StandardDeduction,
    tot.TotalIncome,
    gross.GrossIncome,
    nibs.NetIncomeBeforeShelter,
    su.ShelterAndUtilities,
    ex.ExcessShelter,
    aft.NetIncomeAfterShelter,
    thirty.ThirtyPercentNetIncome,
    benefit.BenefitAmount,
    CASE WHEN tot.TotalIncome <= fs.GrossIncomeLimit AND benefit.BenefitAmount > 0 THEN 1 ELSE 0 END AS IsEligible
FROM dbo.Applicants a
JOIN dbo.FamilySizeInfo fs ON a.FamilySize = fs.FamilySize
CROSS APPLY (SELECT a.EarnedIncome + a.UnearnedIncome AS TotalIncome) tot
CROSS APPLY (SELECT CAST(0.8 * a.EarnedIncome + a.UnearnedIncome AS DECIMAL(10,2)) AS GrossIncome) gross
CROSS APPLY (
    SELECT CASE WHEN gross.GrossIncome - fs.StandardDeduction - a.DaycareExpense < 0 THEN 0
                ELSE CAST(gross.GrossIncome - fs.StandardDeduction - a.DaycareExpense AS DECIMAL(10,2)) END AS NetIncomeBeforeShelter
) nibs
CROSS APPLY (SELECT a.ShelterExpense + a.UtilityExpense AS ShelterAndUtilities) su
CROSS APPLY (
     SELECT CASE WHEN su.ShelterAndUtilities > 0.5 * nibs.NetIncomeBeforeShelter
                 THEN su.ShelterAndUtilities - 0.5 * nibs.NetIncomeBeforeShelter ELSE 0 END AS ExcessShelter
) ex
CROSS APPLY (
     SELECT CASE WHEN nibs.NetIncomeBeforeShelter - ex.ExcessShelter < 0 THEN 0
                 ELSE CAST(nibs.NetIncomeBeforeShelter - ex.ExcessShelter AS DECIMAL(10,2)) END AS NetIncomeAfterShelter
) aft
CROSS APPLY (SELECT CAST(0.3 * aft.NetIncomeAfterShelter AS DECIMAL(10,2)) AS ThirtyPercentNetIncome) thirty
CROSS APPLY (
     SELECT CASE WHEN fs.MaxBenefitAmount - thirty.ThirtyPercentNetIncome < 0 THEN 0
                 ELSE CAST(fs.MaxBenefitAmount - thirty.ThirtyPercentNetIncome AS DECIMAL(10,2)) END AS BenefitAmount
) benefit;
GO

-- Reports

-- 1) List of eligible families with benefit amount
SELECT FamilyName, Address, BenefitAmount
FROM dbo.vw_SnapCalculation
WHERE IsEligible = 1;

-- 2) List of ineligible families with benefit amount
SELECT FamilyName, Address, BenefitAmount
FROM dbo.vw_SnapCalculation
WHERE IsEligible = 0;

-- 3) Count of applicants under income limit but not eligible for benefits
SELECT COUNT(*) AS CountUnderLimitNotEligible
FROM dbo.vw_SnapCalculation
WHERE TotalIncome <= GrossIncomeLimit AND BenefitAmount = 0;

-- 4) Count of applicants whose unearned income is greater than earned income
SELECT COUNT(*) AS UnearnedGreaterThanEarned
FROM dbo.vw_SnapCalculation
WHERE UnearnedIncome > EarnedIncome;

-- 5) Eligible families with real benefit, max benefit and extra Covid benefit
SELECT FamilyName, Address, BenefitAmount AS RealBenefitAmount,
       MaxBenefitAmount,
       MaxBenefitAmount - BenefitAmount AS ExtraCovidBenefit
FROM dbo.vw_SnapCalculation
WHERE IsEligible = 1;
GO
