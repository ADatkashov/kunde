-- Flowers & Gifts (ADR-026): runtime switch for the new domain (off by default, see FlowersSettings). No data tables yet.
ALTER TABLE identity.feature_toggles DROP CONSTRAINT feature_toggles_feature_check;
ALTER TABLE identity.feature_toggles ADD CONSTRAINT feature_toggles_feature_check
    CHECK (feature IN ('AUTO', 'RIDES', 'DELIVERY', 'LEISURE', 'HEALTH', 'EDUCATION', 'GROCERIES', 'EVENTS', 'HOME_SERVICES', 'BEAUTY', 'FLOWERS'));

ALTER TABLE identity.feature_toggle_events DROP CONSTRAINT feature_toggle_events_feature_check;
ALTER TABLE identity.feature_toggle_events ADD CONSTRAINT feature_toggle_events_feature_check
    CHECK (feature IN ('AUTO', 'RIDES', 'DELIVERY', 'LEISURE', 'HEALTH', 'EDUCATION', 'GROCERIES', 'EVENTS', 'HOME_SERVICES', 'BEAUTY', 'FLOWERS'));
