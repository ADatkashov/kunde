-- Events & Tickets has its own administrator permission: EVENTS_OPERATIONS manages the Events control center (event moderation, ticket
-- orders, refunds, categories of Events); LEISURE_OPERATIONS keeps Leisure. Venues, complaints, reviews and the audit journal are shared and
-- open to either permission. Grants are checked in the database on every request (revocation is immediate).
ALTER TABLE identity.admin_grants DROP CONSTRAINT admin_grants_permission_check;
ALTER TABLE identity.admin_grants ADD CONSTRAINT admin_grants_permission_check CHECK (permission IN
    ('PARTNER_VERIFICATION', 'ADMIN_GRANTS', 'RIDE_VERIFICATION', 'RIDE_OPERATIONS', 'DELIVERY_OPERATIONS', 'AUTO_OPERATIONS', 'LEISURE_OPERATIONS', 'HEALTH_OPERATIONS',
     'FOOD_OPERATIONS', 'EVENTS_OPERATIONS'));
