-- Scoped administrator permission for the Groceries Control Center (does not grant the Food or Delivery centers).
ALTER TABLE identity.admin_grants DROP CONSTRAINT admin_grants_permission_check;
ALTER TABLE identity.admin_grants ADD CONSTRAINT admin_grants_permission_check CHECK (permission IN
    ('PARTNER_VERIFICATION', 'ADMIN_GRANTS', 'RIDE_VERIFICATION', 'RIDE_OPERATIONS', 'DELIVERY_OPERATIONS', 'AUTO_OPERATIONS',
     'LEISURE_OPERATIONS', 'HEALTH_OPERATIONS', 'FOOD_OPERATIONS', 'GROCERIES_OPERATIONS'));
