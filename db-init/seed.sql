-- Seed data: 9 customers (3 per tier) with at least 2 risk factors each.
-- All INSERTs use ON CONFLICT DO NOTHING for idempotency.

-- ============================================================
-- LOW tier customers
-- ============================================================

INSERT INTO customers (customer_id, name, tier)
VALUES ('CUST001', 'Alice Marchetti', 'LOW')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST001', 'STABLE_INCOME', 'Customer has maintained stable salaried employment with the same employer for over seven years.')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST001', 'LOW_DEBT_RATIO', 'Total outstanding debt is less than 10% of annual income, well within acceptable thresholds.')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST001', 'CONSISTENT_PAYMENTS', 'No missed or late payments recorded in the past five years across all credit accounts.')
ON CONFLICT DO NOTHING;

-- ---

INSERT INTO customers (customer_id, name, tier)
VALUES ('CUST002', 'Bernard Okafor', 'LOW')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST002', 'STRONG_CREDIT_HISTORY', 'Credit file spans twelve years with no defaults, collections, or adverse judgements.')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST002', 'MINIMAL_OUTSTANDING_DEBT', 'Only one active credit facility with a low utilisation rate below 15%.')
ON CONFLICT DO NOTHING;

-- ---

INSERT INTO customers (customer_id, name, tier)
VALUES ('CUST003', 'Clara Nguyen', 'LOW')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST003', 'LONG_EMPLOYMENT_TENURE', 'Customer has been continuously employed in the same sector for over ten years with documented income growth.')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST003', 'DIVERSIFIED_ASSETS', 'Customer holds diversified savings and investment accounts that provide a substantial financial buffer.')
ON CONFLICT DO NOTHING;

-- ============================================================
-- MEDIUM tier customers
-- ============================================================

INSERT INTO customers (customer_id, name, tier)
VALUES ('CUST004', 'David Ferreira', 'MEDIUM')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST004', 'MODERATE_DEBT_RATIO', 'Outstanding debt is approximately 40% of annual income, within acceptable bounds but warranting monitoring.')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST004', 'OCCASIONAL_LATE_PAYMENT', 'Two late payments recorded in the past three years, both subsequently resolved within 30 days.')
ON CONFLICT DO NOTHING;

-- ---

INSERT INTO customers (customer_id, name, tier)
VALUES ('CUST005', 'Elena Vasquez', 'MEDIUM')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST005', 'SHORT_CREDIT_HISTORY', 'Credit file is less than three years old, providing insufficient history for a low-risk assessment.')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST005', 'VARIABLE_INCOME', 'Customer is self-employed with income that varies by more than 25% between fiscal years.')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST005', 'MODERATE_CREDIT_UTILISATION', 'Credit card utilisation is consistently between 40% and 55%, indicating moderate reliance on revolving credit.')
ON CONFLICT DO NOTHING;

-- ---

INSERT INTO customers (customer_id, name, tier)
VALUES ('CUST006', 'Frank Delacroix', 'MEDIUM')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST006', 'RECENT_CREDIT_INQUIRY', 'Three hard credit enquiries recorded in the past six months, suggesting active credit-seeking behaviour.')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST006', 'PARTIAL_EMPLOYMENT_GAP', 'Customer had an eight-month period of unemployment two years ago with no documented income during that time.')
ON CONFLICT DO NOTHING;

-- ============================================================
-- HIGH tier customers
-- ============================================================

INSERT INTO customers (customer_id, name, tier)
VALUES ('CUST007', 'Grace Adeyemi', 'HIGH')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST007', 'HIGH_DEBT_RATIO', 'Total outstanding debt exceeds 90% of annual income, indicating severe over-leveraging.')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST007', 'MISSED_PAYMENTS', 'Five missed payments recorded across two accounts in the past twelve months, with two accounts currently past due.')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST007', 'LOW_CREDIT_SCORE', 'Credit score falls in the lowest risk band, reflecting a sustained pattern of adverse credit events.')
ON CONFLICT DO NOTHING;

-- ---

INSERT INTO customers (customer_id, name, tier)
VALUES ('CUST008', 'Haruto Kimura', 'HIGH')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST008', 'DEBT_COLLECTION_HISTORY', 'Two accounts were referred to external debt collection agencies within the past two years.')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST008', 'MULTIPLE_DEFAULTS', 'Customer has defaulted on three separate credit agreements, all within the past four years.')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST008', 'HIGH_CREDIT_UTILISATION', 'All active credit facilities are at or above 90% utilisation, leaving no available credit buffer.')
ON CONFLICT DO NOTHING;

-- ---

INSERT INTO customers (customer_id, name, tier)
VALUES ('CUST009', 'Ingrid Sorensen', 'HIGH')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST009', 'BANKRUPTCY_HISTORY', 'Customer filed for personal bankruptcy three years ago; discharge was granted but adverse markers remain active.')
ON CONFLICT DO NOTHING;

INSERT INTO risk_factors (customer_id, factor_code, factor_description)
VALUES ('CUST009', 'NO_VERIFIABLE_INCOME', 'No verifiable income source has been documented in the past eighteen months despite multiple requests.')
ON CONFLICT DO NOTHING;
