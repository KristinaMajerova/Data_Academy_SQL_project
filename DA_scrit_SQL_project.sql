-- PRIMARY TABLE : 
		
-- dokaz ze region_code = NULL - priemerná hodnota krajov: 
	
SELECT *, avg(value) 
FROM czechia_price cp
GROUP BY date_from , category_code 
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
		) potraviny
JOIN 
	(SELECT base2.*, cpib.name AS industry_branch_name
	FROM (
		SELECT cp.payroll_year , cp.industry_branch_code , round(avg(cp.value),2) AS avg_payroll
			FROM czechia_payroll cp 
				WHERE cp.calculation_code = 200 
				AND cp.value_type_code = 5958 
				AND cp.industry_branch_code IS NOT NULL 
			GROUP BY cp.industry_branch_code , cp.payroll_year
			) base2
		LEFT JOIN czechia_payroll_industry_branch cpib 
		ON base2.industry_branch_code = cpib.code
		) mzdy
ON potraviny.price_year = mzdy.payroll_year;


-- CREATE SECONDARY TABLE FINAL

CREATE OR REPLACE TABLE t_kristina_majerova_project_SQL_secondary_final as
SELECT country, `year`, GDP, population , 
    round(GDP/population,2) AS GDP_per_capita, 
    round(lead(GDP/population,-1)OVER (ORDER BY `year`),2) AS GDP_per_capita_prew,
    round(((GDP/population/lead(GDP/population,-1)OVER (ORDER BY `year`)-1)*100),2) as rast_gdp_per_capita
    FROM economies e
    WHERE country = 'Czech Republic' AND YEAR >= 2005
    ORDER BY `year` ;


-- OTAZKA 1
-- Rostou v průběhu let mzdy ve všech odvětvích, nebo v některých klesají?


SELECT payroll_year, industry_branch_name, rast_avg_payroll
FROM (
    SELECT *, 
        lag(avg_payroll,1) OVER (PARTITION BY industry_branch_name ORDER BY payroll_year) AS avg_payroll_lag,
        round(avg_payroll/lag(avg_payroll,1) OVER (PARTITION BY industry_branch_name ORDER BY payroll_year)*100-100,2) AS rast_avg_payroll
    FROM (
        SELECT payroll_year, avg_payroll, industry_branch_name
        FROM t_kristina_majerova_project_sql_primary_final
        GROUP BY industry_branch_name, price_year
        ) base
    ) base2
WHERE rast_avg_payroll < 0
ORDER BY industry_branch_name;

-- OTAZKA 2
-- Kolik je možné si koupit litrů mléka a kilogramů chleba za první a poslední srovnatelné období v dostupných datech cen a mezd?

SELECT *, round(t2.avg_payroll/t1.avg_price, 2) AS kupyschopnost
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
    SELECT price_year , round(avg(avg_payroll),2) AS avg_payroll
        FROM t_kristina_majerova_project_sql_primary_final
    GROUP BY price_year
    ) t2
ON t1.price_year=t2.price_year;

-- Var 2  - riešenie po jednotlivých odvetviach 

SELECT *, round(t2.avg_payroll/t1.avg_price, 2) AS kupyschopnost
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
    SELECT price_year, industry_branch_name , round(avg(avg_payroll),2) AS avg_payroll
        FROM t_kristina_majerova_project_sql_primary_final
    GROUP BY price_year, industry_branch_name
    ) t2
ON t1.price_year=t2.price_year;


-- OTAZKA 3
-- Která kategorie potravin zdražuje nejpomaleji (je u ní nejnižší percentuální meziroční nárůst)?
 
-- riešenie s použitím 
 
 SELECT avg(rast_avg_price), price_cat_name
from(
    SELECT *, 
        lag(avg_price,1) OVER (PARTITION BY price_cat_name ORDER BY price_year) AS avg_price_lag,
        round(avg_price/lag(avg_price,1) OVER (PARTITION BY price_cat_name ORDER BY price_year)*100-100,2) AS rast_avg_price
    from(
        SELECT price_year, avg(avg_price) AS avg_price, price_cat_name 
        FROM t_kristina_majerova_project_sql_primary_final
        GROUP BY price_cat_name , price_year
        )base
    )base2
 GROUP BY price_cat_name
 ORDER BY (avg(rast_avg_price));
 
-- OTAZKA 4
-- Existuje rok, ve kterém byl meziroční nárůst cen potravin výrazně vyšší než růst mezd (větší než 10 %)? 
 
-- relativny % rastu za predpokladu ze v oboch obdobiach bol rast
 
SELECT *, round((price.rast_avg_price-payroll.rast_avg_payroll)/payroll.rast_avg_payroll*100,2) AS perc_pomer_rastu
FROM 
    (SELECT *, 
        lag(avg_payroll,1) OVER (ORDER BY payroll_year) AS avg_payroll_lag,
        round(avg_payroll/lag(avg_payroll,1) OVER (ORDER BY payroll_year)*100-100,2) AS rast_avg_payroll
        FROM (
            SELECT payroll_year, round(avg(avg_payroll),2)AS avg_payroll
            FROM t_kristina_majerova_project_sql_primary_final
            GROUP BY payroll_year
            ) t1
        )payroll
LEFT join
    (SELECT *, 
        lag(avg_price,1) OVER (ORDER BY price_year) AS avg_price_lag,
        round(avg_price/lag(avg_price,1) OVER (ORDER BY price_year)*100-100,2) AS rast_avg_price
        from( 
            SELECT price_year, round(avg(avg_price),2) AS avg_price
            FROM t_kristina_majerova_project_sql_primary_final
            GROUP BY price_year
            )t2
        )price 
ON payroll.payroll_year=price.price_year
WHERE round((price.rast_avg_price-payroll.rast_avg_payroll)/payroll.rast_avg_payroll*100,2) > 10
;


-- Otázka 5
-- Má výška HDP vliv na změny ve mzdách a cenách potravin? Neboli, pokud HDP vzroste výrazněji v jednom roce, projeví se to na cenách potravin či mzdách ve stejném nebo násdujícím roce výraznějším růstem?

CREATE OR replaceVIEW v_kristina_majerova_project_sql_primary_final2 as
SELECT payroll.payroll_year, payroll.rast_avg_payroll, price.rast_avg_price, tkmpssf.rast_gdp_per_capita
FROM 
    (SELECT *, 
        lag(avg_payroll,1) OVER (ORDER BY payroll_year) AS avg_payroll_lag,
        round(avg_payroll/lag(avg_payroll,1) OVER (ORDER BY payroll_year)*100-100,2) AS rast_avg_payroll
        FROM (
            SELECT payroll_year, round(avg(avg_payroll),2)AS avg_payroll
            FROM t_kristina_majerova_project_sql_primary_final
            GROUP BY payroll_year
            ) t1
        )payroll
LEFT join
    (SELECT *, 
        lag(avg_price,1) OVER (ORDER BY price_year) AS avg_price_lag,
        round(avg_price/lag(avg_price,1) OVER (ORDER BY price_year)*100-100,2) AS rast_avg_price
        from( 
            SELECT price_year, round(avg(avg_price),2) AS avg_price
            FROM t_kristina_majerova_project_sql_primary_final
            GROUP BY price_year
            )t2
        )price 
ON payroll.payroll_year=price.price_year
LEFT JOIN t_kristina_majerova_project_sql_secondary_final tkmpssf 
ON payroll.payroll_year=tkmpssf.YEAR;

-- porovnanie rastu HDP a rastu miezd, cien v aktuálnom roku : 

SELECT *, 
rast_avg_price/rast_gdp_per_capita, 
rast_avg_payroll/rast_gdp_per_capita
FROM v_kristina_majerova_project_sql_primary_final2
ORDER BY rast_gdp_per_capita DESC ;

-- porovnanie rastu HDP a rastu miezd, cien v nasledujúcom roku :

SELECT payroll_year, rast_avg_price, rast_avg_payroll,
lag(rast_gdp_per_capita)OVER(ORDER BY payroll_year) AS lag_rast_gdp,
rast_avg_price/lag(rast_gdp_per_capita)OVER(ORDER BY payroll_year), 
rast_avg_payroll/lag(rast_gdp_per_capita)OVER(ORDER BY payroll_year)
FROM v_kristina_majerova_project_sql_primary_final2
ORDER BY lag(rast_gdp_per_capita)OVER(ORDER BY payroll_year) DESC ;

