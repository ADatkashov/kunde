CREATE TABLE identity.admin_roles (
    code text PRIMARY KEY
);

CREATE TABLE identity.admin_role_permissions (
    role_code text NOT NULL REFERENCES identity.admin_roles(code),
    permission text NOT NULL CHECK (permission IN (
        'PARTNER_VERIFICATION', 'RIDE_VERIFICATION', 'RIDE_OPERATIONS', 'DELIVERY_OPERATIONS', 'AUTO_OPERATIONS'
    )),
    PRIMARY KEY (role_code, permission)
);

CREATE TABLE identity.admin_role_assignments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES identity.users(id),
    role_code text NOT NULL REFERENCES identity.admin_roles(code),
    product_code text CHECK (product_code IN ('FOOD', 'GROCERY', 'FLOWERS', 'HOME_SERVICES', 'BEAUTY', 'RIDES', 'DELIVERY', 'AUTO')),
    region_code text CHECK (region_code ~ '^[A-Z0-9_-]{1,40}$'),
    organization_id uuid REFERENCES marketplace.partners(id),
    resource_id uuid,
    assigned_by uuid NOT NULL REFERENCES identity.users(id),
    assigned_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz CHECK (expires_at > assigned_at),
    revoked_at timestamptz CHECK (revoked_at >= assigned_at),
    revoked_by uuid REFERENCES identity.users(id),
    CHECK (resource_id IS NULL OR product_code IS NOT NULL),
    CHECK ((revoked_at IS NULL) = (revoked_by IS NULL))
);

CREATE INDEX admin_role_assignments_active_user_idx
    ON identity.admin_role_assignments(user_id) WHERE revoked_at IS NULL;

-- Canonical effective grants are evaluated at statement time and retain their assignment boundaries.
CREATE VIEW identity.effective_admin_permissions AS
SELECT g.user_id, g.permission::text, NULL::text AS product_code, NULL::text AS region_code,
       NULL::uuid AS organization_id, NULL::uuid AS resource_id
FROM identity.admin_grants g JOIN identity.users u ON u.id = g.user_id
WHERE g.revoked_at IS NULL AND u.status = 'ACTIVE'
UNION ALL
SELECT a.user_id, p.permission, a.product_code, a.region_code, a.organization_id, a.resource_id
FROM identity.admin_role_assignments a
JOIN identity.admin_role_permissions p ON p.role_code = a.role_code
JOIN identity.users u ON u.id = a.user_id
WHERE a.revoked_at IS NULL AND (a.expires_at IS NULL OR a.expires_at > statement_timestamp())
    AND u.status = 'ACTIVE';
