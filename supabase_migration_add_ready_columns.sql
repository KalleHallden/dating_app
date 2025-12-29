-- Migration: Clean up old columns and add ready tracking columns
-- Purpose: Track when each user has landed on the call page to prevent
--          Agora from connecting before both users are present

-- Remove old columns if they exist (from previous failed attempt)
ALTER TABLE calls
DROP COLUMN IF EXISTS caller_joined,
DROP COLUMN IF EXISTS called_joined;

-- Add new ready tracking columns
ALTER TABLE calls
ADD COLUMN IF NOT EXISTS caller_ready BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS called_ready BOOLEAN DEFAULT FALSE;

-- Create an index for faster ready status queries
CREATE INDEX IF NOT EXISTS idx_calls_ready_status
ON calls(caller_ready, called_ready);

-- Add comments to document the purpose of these columns
COMMENT ON COLUMN calls.caller_ready IS 'Tracks if the caller has landed on the call page';
COMMENT ON COLUMN calls.called_ready IS 'Tracks if the called user has landed on the call page';
