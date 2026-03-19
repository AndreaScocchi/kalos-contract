-- Add notification categories for practice and journal features
-- NOTE: ALTER TYPE ... ADD VALUE cannot run inside a transaction block,
-- so this migration must be run outside of a transaction.

ALTER TYPE notification_category ADD VALUE IF NOT EXISTS 'practice_reminder';   -- Promemoria pratica quotidiana
ALTER TYPE notification_category ADD VALUE IF NOT EXISTS 'practice_resume';     -- Riprendi pratica iniziata
ALTER TYPE notification_category ADD VALUE IF NOT EXISTS 'journal_reminder';    -- Promemoria diario settimanale
