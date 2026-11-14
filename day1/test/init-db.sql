-- Initialize PostgreSQL database for complaints processing

CREATE TABLE IF NOT EXISTS processed_complaints (
    id SERIAL PRIMARY KEY,
    complaint_id VARCHAR(50) NOT NULL UNIQUE,
    customer_id VARCHAR(50) NOT NULL,
    message TEXT,
    severity_score INT CHECK(severity_score >= 1 AND severity_score <= 10),
    ai_category VARCHAR(20),
    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_processed_complaints_complaint_id 
    ON processed_complaints(complaint_id);

CREATE INDEX IF NOT EXISTS idx_processed_complaints_customer_id 
    ON processed_complaints(customer_id);

CREATE INDEX IF NOT EXISTS idx_processed_complaints_ai_category 
    ON processed_complaints(ai_category);

CREATE INDEX IF NOT EXISTS idx_processed_complaints_severity_score 
    ON processed_complaints(severity_score DESC);

CREATE INDEX IF NOT EXISTS idx_processed_complaints_processed_at 
    ON processed_complaints(processed_at DESC);

-- Create a view for analytics
CREATE OR REPLACE VIEW v_complaint_stats AS
SELECT 
    ai_category,
    COUNT(*) as total_complaints,
    AVG(severity_score) as avg_severity,
    MIN(severity_score) as min_severity,
    MAX(severity_score) as max_severity,
    MAX(processed_at) as latest_processed
FROM processed_complaints
GROUP BY ai_category;

GRANT SELECT, INSERT, UPDATE ON processed_complaints TO admin;
GRANT SELECT ON v_complaint_stats TO admin;
