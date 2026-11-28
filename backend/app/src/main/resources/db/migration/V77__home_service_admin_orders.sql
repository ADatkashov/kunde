-- Home Services H8: operations over orders for platform staff. A separate grant from catalogue moderation (HOME_SERVICES_CATALOG),
-- so that scoped RBAC can give "orders" and "catalogue" to different people. Staff actions are recorded as ADMIN in the booking
-- history and in an append-only audit owned by Home Services. The audit references orders, masters and staff by id without
-- foreign keys (Constitution §5: no new constraints across table owners; the controller checks them under the order lock).
ALTER TABLE identity.admin_grants DROP CONSTRAINT admin_grants_permission_check;
ALTER TABLE identity.admin_grants ADD CONSTRAINT admin_grants_permission_check CHECK (permission IN
    ('PARTNER_VERIFICATION', 'ADMIN_GRANTS', 'RIDE_VERIFICATION', 'RIDE_OPERATIONS', 'DELIVERY_OPERATIONS',
     'AUTO_OPERATIONS', 'LEISURE_OPERATIONS', 'HEALTH_OPERATIONS', 'FOOD_OPERATIONS', 'EDUCATION_OPERATIONS',
     'GROCERIES_OPERATIONS', 'EVENTS_OPERATIONS', 'HOME_SERVICES_CATALOG', 'BEAUTY_OPERATIONS', 'HOME_SERVICES_OPERATIONS'));

ALTER TABLE transactions.booking_events DROP CONSTRAINT booking_events_actor_type_check;
ALTER TABLE transactions.booking_events ADD CONSTRAINT booking_events_actor_type_check
    CHECK (actor_type IN ('CUSTOMER', 'PARTNER', 'SYSTEM', 'ADMIN'));
ALTER TABLE transactions.bookings DROP CONSTRAINT bookings_cancelled_by_check;
ALTER TABLE transactions.bookings ADD CONSTRAINT bookings_cancelled_by_check
    CHECK (cancelled_by IN ('CUSTOMER', 'PARTNER', 'SYSTEM', 'ADMIN'));

CREATE TABLE marketplace.home_service_admin_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    booking_id uuid NOT NULL,
    admin_user_id uuid NOT NULL,
    action varchar(12) COLLATE "C" NOT NULL CHECK (action IN ('CANCEL', 'REASSIGN')),
    reason varchar(200) NOT NULL CHECK (length(btrim(reason)) > 0),
    from_master_id uuid,
    to_master_id uuid,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT home_service_admin_events_reassign CHECK ((action = 'REASSIGN') = (to_master_id IS NOT NULL))
);
CREATE INDEX home_service_admin_events_booking_idx ON marketplace.home_service_admin_events (booking_id, id);

CREATE TRIGGER home_service_admin_events_immutable
    BEFORE UPDATE OR DELETE ON marketplace.home_service_admin_events
    FOR EACH ROW EXECUTE FUNCTION transactions.reject_food_event_mutation();
