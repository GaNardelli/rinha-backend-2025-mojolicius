CREATE TABLE IF NOT EXISTS payments (
  correlation_id TEXT PRIMARY KEY,
  amount FLOAT,
  requested_at TIMESTAMP,
  processor TEXT
);