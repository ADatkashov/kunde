-- Beauty masters can sign in to KUNDE Executor: a master is linked to a user once, with an invite code the salon hands out.
-- «Online» only controls whether the master receives NEW bookings; confirmed bookings are never touched.
ALTER TABLE marketplace.booking_masters
    ADD COLUMN user_id uuid UNIQUE REFERENCES identity.users(id),
    ADD COLUMN invite_code varchar(24) COLLATE "C" UNIQUE CHECK (invite_code IS NULL OR invite_code ~ '^[A-Z0-9-]{6,24}$'),
    ADD COLUMN online boolean NOT NULL DEFAULT true;

-- Beauty analytics for platform administrators.
ALTER TABLE identity.admin_grants DROP CONSTRAINT admin_grants_permission_check;
ALTER TABLE identity.admin_grants ADD CONSTRAINT admin_grants_permission_check CHECK (permission IN
    ('PARTNER_VERIFICATION', 'ADMIN_GRANTS', 'RIDE_VERIFICATION', 'RIDE_OPERATIONS', 'DELIVERY_OPERATIONS',
     'AUTO_OPERATIONS', 'LEISURE_OPERATIONS', 'HEALTH_OPERATIONS', 'FOOD_OPERATIONS', 'EDUCATION_OPERATIONS',
     'GROCERIES_OPERATIONS', 'EVENTS_OPERATIONS', 'HOME_SERVICES_CATALOG', 'BEAUTY_OPERATIONS'));
