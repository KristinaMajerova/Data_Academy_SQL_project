-- PRIMARY TABLE : 
		
-- dokaz ze region_code = NULL - priemerná hodnota krajov: 
	
SELECT *, date_from, category_code, avg(value) 
FROM czechia_price cp
GROUP BY date_from, category_code 
ORDER BY region_code;

CREATE OR REPLACE TABLE t_kristina_majerova_project_SQL_primary_final AS
SELECT * 
from (
	SELECT base1.*, cpc.name AS price_cat_name
	FROM ( 
		SELECT year(date_from) AS price_year, round(avg(value),2) AS avg_price, category_code 
		FROM czechia_price cp
			WHERE region_code IS NULL
			GROUP by year(date_from), category_code
			) base1
		LEFT JOIN czechia_price_category cpc 
			ON cpc.code = base1.category_code
		ORDER BY base1.price_year
		) groceries
JOIN 
	(SELECT base2.*, cpib.name AS industry_branch_name
	FROM (
		SELECT cp.payroll_year, cp.industry_branch_code, round(avg(cp.value),2) AS avg_payroll
			FROM czechia_payroll cp 
				WHERE cp.calculation_code = 200 
				AND cp.value_type_code = 5958 
				AND cp.industry_branch_code IS NOT NULL 
			GROUP BY cp.industry_branch_code, cp.payroll_year
			) base2
		LEFT JOIN czechia_payroll_industry_branch cpib 
		ON base2.industry_branch_code = cpib.code
		) payroll
ON groceries.price_year = payroll.payroll_year;

-- CREATE SECONDARY TABLE FINAL

CREATE OR REPLACE TABLE t_kristina_majerova_project_SQL_secondary_final AS
SELECT country, `year`, GDP, population, 
    round(GDP/population,2) AS GDP_per_capita, 
    round(lead(GDP/population,-1)OVER (ORDER BY `year`),2) AS GDP_per_capita_prew,
    round(((GDP/population/lead(GDP/population,-1)OVER (ORDER BY `year`)-1)*100),2) AS growth_gdp_per_capita
    FROM economies e
    WHERE country = 'Czech Republic' AND YEAR >= 2005
    ORDER BY `year`;


-- OTAZKA 1
-- Rostou v průběhu let mzdy ve všech odvětvích, nebo v některých klesají?

SELECT payroll_year, industry_branch_name, growth_avg_payroll
FROM (
    SELECT *, 
        lag(avg_payroll,1) OVER (PARTITION BY industry_branch_name ORDER BY payroll_year) AS avg_payroll_lag,
        round(avg_payroll/lag(avg_payroll,1) OVER (PARTITION BY industry_branch_name ORDER BY payroll_year)*100-100,2) AS growth_avg_payroll
    FROM (
        SELECT payroll_year, avg_payroll, industry_branch_name
        FROM t_kristina_majerova_project_sql_primary_final
        ) base
    ) base2
WHERE growth_avg_payroll < 0
ORDER BY industry_branch_name;


-- OTAZKA 2
-- Kolik je možné si koupit litrů mléka a kilogramů chleba za první a poslední srovnatelné období v dostupných datech cen a mezd?

SELECT *, round(t2.avg_payroll/t1.avg_price, 2) AS purchasing_power
FROM (
    SELECT price_year, price_cat_name, avg(avg_price) AS avg_price
        FROM t_kristina_majerova_project_sql_primary_final
        WHERE price_cat_name IN ('Mléko polotučné pasterované','Chléb konzumní kmínový') 
        AND price_year IN (
                (SELECT DISTINCT min(price_year)
                FROM t_kristina_majerova_project_sql_primary_final),
                (SELECT DISTINCT max(price_year)
                FROM t_kristina_majerova_project_sql_primary_final))
    GROUP BY price_year, price_cat_name
    ) t1
JOIN (
    SELECT price_year, round(avg(avg_payroll),2) AS avg_payroll
        FROM t_kristina_majerova_project_sql_primary_final
    GROUP BY price_year
    ) t2
ON t1.price_year=t2.price_year;

-- Var 2  - riešenie po jednotlivých odvetviach 

SELECT *, round(t2.avg_payroll/t1.avg_price, 2) AS purchasing_power
FROM (
    SELECT price_year, price_cat_name, avg(avg_price) AS avg_price
        FROM t_kristina_majerova_project_sql_primary_final
        WHERE price_cat_name IN ('Mléko polotučné pasterované','Chléb konzumní kmínový') 
        AND price_year IN (
                (SELECT DISTINCT min(price_year)
                FROM t_kristina_majerova_project_sql_primary_final),
                (SELECT DISTINCT max(price_year)
                FROM t_kristina_majerova_project_sql_primary_final))
    GROUP BY price_year, price_cat_name
    ) t1
JOIN (
    SELECT price_year, industry_branch_name, round(avg(avg_payroll),2) AS avg_payroll
        FROM t_kristina_majerova_project_sql_primary_final
    GROUP BY price_year, industry_branch_name
    ) t2
ON t1.price_year=t2.price_year;


-- OTAZKA 3
-- Která kategorie potravin zdražuje nejpomaleji (je u ní nejnižší percentuální meziroční nárůst)?
 
-- riešenie s použitím 
 
 SELECT avg(growth_avg_price), price_cat_name
FROM(
    SELECT *, 
        lag(avg_price,1) OVER (PARTITION BY price_cat_name ORDER BY price_year) AS avg_price_lag,
        round(avg_price/lag(avg_price,1) OVER (PARTITION BY price_cat_name ORDER BY price_year)*100-100,2) AS growth_avg_price
    FROM(
        SELECT price_year, avg(avg_price) AS avg_price, price_cat_name 
        FROM t_kristina_majerova_project_sql_primary_final
        GROUP BY price_cat_name, price_year
        )base
    )base2
 GROUP BY price_cat_name
 ORDER BY (avg(growth_avg_price));
 
-- OTAZKA 4
-- Existuje rok, ve kterém byl meziroční nárůst cen potravin výrazně vyšší než růst mezd (větší než 10 %)? 
 
-- riešenie cez odčítania hodnôt percentuálneho rastu miezd od rastu cien v jednotlivých rokoch 
 

SELECT payroll.payroll_year, price.growth_avg_price, payroll.growth_avg_payroll, price.growth_avg_price-payroll.growth_avg_payroll AS perc_growth_diff
FROM 
    (SELECT *, 
        lag(avg_payroll,1) OVER (ORDER BY payroll_year) AS growth_payroll_lag,
        round(avg_payroll/lag(avg_payroll,1) OVER (ORDER BY payroll_year)*100-100,2) AS growth_avg_payroll
        FROM (
            SELECT payroll_year, round(avg(avg_payroll),2)AS avg_payroll
            FROM t_kristina_majerova_project_sql_primary_final
            GROUP BY payroll_year
            ) t1
        )payroll
LEFT JOIN
    (SELECT *, 
        lag(avg_price,1) OVER (ORDER BY price_year) AS avg_price_lag,
        round(avg_price/lag(avg_price,1) OVER (ORDER BY price_year)*100-100,2) AS growth_avg_price
        FROM( 
            SELECT price_year, round(avg(avg_price),2) AS avg_price
            FROM t_kristina_majerova_project_sql_primary_final
            GROUP BY price_year
            )t2
        )price 
ON payroll.payroll_year=price.price_year
WHERE price.growth_avg_price-payroll.growth_avg_payroll > 10;

-- zobrazenie rozdielov v jednotlivých rokoch zostupne: 

SELECT 
    payroll.payroll_year, 
    price.growth_avg_price, 
    payroll.growth_avg_payroll, 
    price.growth_avg_price-payroll.growth_avg_payroll AS perc_growth_diff
FROM 
    (SELECT *, 
        lag(avg_payroll,1) OVER (ORDER BY payroll_year) AS growth_payroll_lag,
        round(avg_payroll/lag(avg_payroll,1) OVER (ORDER BY payroll_year)*100-100,2) AS growth_avg_payroll
        FROM (
            SELECT payroll_year, round(avg(avg_payroll),2)AS avg_payroll
            FROM t_kristina_majerova_project_sql_primary_final
            GROUP BY payroll_year
            ) t1
        )payroll
LEFT JOIN
    (SELECT *, 
        lag(avg_price,1) OVER (ORDER BY price_year) AS avg_price_lag,
        round(avg_price/lag(avg_price,1) OVER (ORDER BY price_year)*100-100,2) AS growth_avg_price
        FROM( 
            SELECT price_year, round(avg(avg_price),2) AS avg_price
            FROM t_kristina_majerova_project_sql_primary_final
            GROUP BY price_year
            )t2
        )price 
ON payroll.payroll_year=price.price_year
ORDER BY perc_growth_diff DESC; 


-- Otázka 5
-- Má výška HDP vliv na změny ve mzdách a cenách potravin? Neboli, pokud HDP vzroste výrazněji v jednom roce, projeví se to na cenách potravin či mzdách ve stejném nebo násdujícím roce výraznějším růstem?

CREATE OR REPLACE VIEW v_kristina_majerova_project_sql_primary_final2 AS
SELECT payroll.payroll_year, payroll.growth_avg_payroll, price.growth_avg_price, tkmpssf.growth_gdp_per_capita
FROM 
    (SELECT *, 
        lag(avg_payroll,1) OVER (ORDER BY payroll_year) AS avg_payroll_lag,
        round(avg_payroll/lag(avg_payroll,1) OVER (ORDER BY payroll_year)*100-100,2) AS growth_avg_payroll
        FROM (
            SELECT payroll_year, round(avg(avg_payroll),2)AS avg_payroll
            FROM t_kristina_majerova_project_sql_primary_final
            GROUP BY payroll_year
            ) t1
        )payroll
LEFT JOIN 
    (SELECT *, 
        lag(avg_price,1) OVER (ORDER BY price_year) AS avg_price_lag,
        round(avg_price/lag(avg_price,1) OVER (ORDER BY price_year)*100-100,2) AS growth_avg_price
        FROM( 
            SELECT price_year, round(avg(avg_price),2) AS avg_price
            FROM t_kristina_majerova_project_sql_primary_final
            GROUP BY price_year
            )t2
        )price 
ON payroll.payroll_year=price.price_year
LEFT JOIN t_kristina_majerova_project_sql_secondary_final tkmpssf 
ON payroll.payroll_year=tkmpssf.`year`;

-- porovnanie rastu HDP a rastu miezd, cien v aktuálnom roku : 

SELECT *, 
growth_avg_price/growth_gdp_per_capita, 
growth_avg_payroll/growth_gdp_per_capita
FROM v_kristina_majerova_project_sql_primary_final2
ORDER BY growth_gdp_per_capita DESC ;

-- porovnanie rastu HDP a rastu miezd, cien v nasledujúcom roku :

SELECT 
    payroll_year, 
    growth_avg_price, 
    growth_avg_payroll,
    lag(growth_gdp_per_capita)OVER(ORDER BY payroll_year) AS lag_growth_gdp,
    growth_avg_price/lag(growth_gdp_per_capita)OVER(ORDER BY payroll_year), 
    growth_avg_payroll/lag(growth_gdp_per_capita)OVER(ORDER BY payroll_year)
FROM v_kristina_majerova_project_sql_primary_final2
ORDER BY lag(growth_gdp_per_capita)OVER(ORDER BY payroll_year) DESC ;

