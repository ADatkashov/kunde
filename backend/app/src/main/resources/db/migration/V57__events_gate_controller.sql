-- Events: a gate controller (GATE) is an executor assigned by the organiser to a session; he scans QR tickets of that session only.
ALTER TABLE transactions.leisure_assignments DROP CONSTRAINT IF EXISTS leisure_assignments_role_check;
ALTER TABLE transactions.leisure_assignments ADD CONSTRAINT leisure_assignments_role_check
    CHECK (role IN ('GUIDE', 'HOST', 'INSTRUCTOR', 'ANIMATOR', 'ORGANIZER', 'GATE'));
ALTER TABLE transactions.leisure_checkins DROP CONSTRAINT IF EXISTS leisure_checkins_result_check;
ALTER TABLE transactions.leisure_checkins ADD CONSTRAINT leisure_checkins_result_check
    CHECK (result IN ('ADMITTED', 'DUPLICATE', 'INVALID', 'WRONG_ORGANIZATION', 'WRONG_SESSION', 'CANCELLED', 'NOT_CONFIRMED', 'EXPIRED', 'TOO_EARLY', 'ACCESS_DENIED'));
