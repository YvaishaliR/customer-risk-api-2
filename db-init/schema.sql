-- customers: one row per customer, holds the assigned risk tier.
CREATE TABLE IF NOT EXISTS customers (
    customer_id  VARCHAR(20)  PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    tier         VARCHAR(10)  NOT NULL CHECK (tier IN ('LOW', 'MEDIUM', 'HIGH')),
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- risk_factors: one or more contributing factors per customer that explain the tier.
CREATE TABLE IF NOT EXISTS risk_factors (
    id                 SERIAL       PRIMARY KEY,
    customer_id        VARCHAR(20)  NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    factor_code        VARCHAR(50)  NOT NULL,
    factor_description TEXT         NOT NULL,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (customer_id, factor_code)
);

CREATE INDEX IF NOT EXISTS idx_risk_factors_customer_id ON risk_factors (customer_id);
