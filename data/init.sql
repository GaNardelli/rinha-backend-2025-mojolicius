CREATE TABLE IF NOT EXISTS payments (
  correlation_id TEXT PRIMARY KEY,
  amount DECIMAL(12, 2) NOT NULL,
  requested_at TIMESTAMP WITH TIME ZONE NOT NULL,
  processor TEXT CHECK (processor IN ('default', 'fallback')) NOT NULL
);
CREATE INDEX idx_payments_requested_at ON payments(requested_at);
CREATE INDEX idx_processor ON payments(processor);