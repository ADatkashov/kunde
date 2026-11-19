ALTER TABLE identity.admin_grants DROP CONSTRAINT admin_grants_permission_check;
ALTER TABLE identity.admin_grants ADD CONSTRAINT admin_grants_permission_check
    CHECK (permission IN ('PARTNER_VERIFICATION', 'ADMIN_GRANTS', 'RIDE_VERIFICATION', 'RIDE_OPERATIONS'));

ALTER TABLE transactions.rides ADD CONSTRAINT rides_owner_id_unique UNIQUE (user_id, id);
ALTER TABLE support.cases ADD COLUMN ride_id uuid;
ALTER TABLE support.cases ADD CONSTRAINT support_case_owned_ride
    FOREIGN KEY (owner_user_id, ride_id) REFERENCES transactions.rides (user_id, id);
ALTER TABLE support.cases DROP CONSTRAINT cases_status_check;
ALTER TABLE support.cases ADD CONSTRAINT cases_status_check
    CHECK (status IN ('OPEN', 'ESCALATION_REQUESTED', 'RESOLVED'));
CREATE INDEX support_cases_ride_queue ON support.cases (created_at DESC, id) WHERE ride_id IS NOT NULL;

ALTER TABLE support.case_events ADD COLUMN actor_user_id uuid REFERENCES identity.users(id);
ALTER TABLE support.case_events DROP CONSTRAINT case_events_event_type_check;
ALTER TABLE support.case_events ADD CONSTRAINT case_events_event_type_check
    CHECK (event_type IN ('CREATED', 'ESCALATION_REQUESTED', 'RESOLVED'));
ALTER TABLE support.case_events ADD CONSTRAINT case_events_resolution_actor
    CHECK (event_type <> 'RESOLVED' OR actor_user_id IS NOT NULL);
