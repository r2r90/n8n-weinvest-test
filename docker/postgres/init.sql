CREATE TABLE IF NOT EXISTS leads (
  id SERIAL PRIMARY KEY,
  lead_id VARCHAR(100) UNIQUE NOT NULL,
  first_name VARCHAR(100),
  last_name VARCHAR(100),
  email VARCHAR(255),
  city VARCHAR(100),
  project_type VARCHAR(100),
  budget INTEGER,
  priority VARCHAR(50),
  source VARCHAR(100),
  received_at TIMESTAMP,
  email_sent BOOLEAN DEFAULT FALSE,
  email_sent_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);