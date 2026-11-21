package kz.kunde;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import java.util.UUID;
import java.util.function.Consumer;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * TASK-055 verification: domain-owned schemas and database constraints, checked against the
 * Flyway-migrated PostgreSQL schema (docs/architecture/11-database-architecture.md:
 * schema per module, cross-schema references only to reviewed stable aggregates, no cascade
 * deletion of history). Synthetic data only; every write is rolled back.
 */
@SpringBootTest
class DomainSchemaOwnershipIntegrationTest {
    /** Namespaces owned by a domain. Adding a schema must be a reviewed change to this list. */
    private static final Set<String> DOMAIN_SCHEMAS = Set.of(
            "identity", "profile", "marketplace", "transactions", "payments", "support", "serviceability");

    /** Reviewed stable cross-schema references. A new one must be documented, then listed here. */
    private static final Set<String> REVIEWED_CROSS_SCHEMA_REFERENCES = Set.of(
            "marketplace.leisure_audit -> identity.users",
            "transactions.leisure_assignments -> identity.users",
            "transactions.leisure_assignments -> marketplace.leisure_sessions",
            "transactions.leisure_checkins -> identity.users",
            "transactions.leisure_checkins -> marketplace.leisure_sessions",
            "transactions.leisure_checkins -> marketplace.leisure_venues",
            "transactions.leisure_checkins -> marketplace.partners",
            "transactions.leisure_complaints -> identity.users",
            "transactions.leisure_complaints -> marketplace.leisure_venues",
            "transactions.health_favorites -> identity.users",
            "transactions.health_favorites -> marketplace.booking_venues",
            "transactions.health_favorites -> marketplace.booking_masters",
            "transactions.health_favorites -> marketplace.booking_services",
            "transactions.leisure_favorites -> identity.users",
            "transactions.leisure_favorites -> marketplace.leisure_events",
            "transactions.leisure_hold_lines -> marketplace.leisure_seats",
            "transactions.leisure_hold_lines -> marketplace.leisure_ticket_types",
            "transactions.leisure_holds -> identity.users",
            "transactions.leisure_holds -> marketplace.leisure_sessions",
            "transactions.leisure_order_events -> identity.users",
            "transactions.leisure_orders -> identity.users",
            "transactions.leisure_orders -> marketplace.leisure_events",
            "transactions.leisure_orders -> marketplace.leisure_sessions",
            "transactions.leisure_orders -> marketplace.leisure_venues",
            "transactions.leisure_payment_events -> identity.users",
            "transactions.leisure_payments -> identity.users",
            "transactions.leisure_reviews -> identity.users",
            "transactions.leisure_reviews -> marketplace.leisure_events",
            "transactions.leisure_reviews -> marketplace.leisure_venues",
            "transactions.leisure_tickets -> identity.users",
            "transactions.leisure_tickets -> marketplace.leisure_seats",
            "transactions.leisure_tickets -> marketplace.leisure_sessions",
            "transactions.leisure_tickets -> marketplace.leisure_ticket_types",
            "profile.consumer_profiles -> identity.users",
            "profile.consumer_addresses -> identity.users",
            "profile.consent_events -> identity.users",
            "support.cases -> identity.users",
            "support.cases -> transactions.rides",
            "support.cases -> transactions.deliveries",
            "support.case_events -> identity.users",
            "marketplace.partners -> identity.users",
            "identity.admin_role_assignments -> marketplace.partners",
            "marketplace.partner_staff -> identity.users",
            "marketplace.offering_events -> identity.users",
            "marketplace.partner_profile_events -> identity.users",
            "marketplace.partner_staff_events -> identity.users",
            "marketplace.partner_verification_events -> identity.users",
            "serviceability.zone_addresses -> profile.consumer_addresses",
            "transactions.food_orders -> identity.users",
            "marketplace.partner_catalog_events -> identity.users",
            "transactions.food_orders -> marketplace.partners",
            "transactions.food_order_events -> identity.users",
            "transactions.booking_events -> identity.users",
            "transactions.food_orders -> marketplace.food_restaurants",
            "transactions.food_order_items -> marketplace.food_dishes",
            "transactions.bookings -> identity.users",
            "transactions.ride_fare_quotes -> identity.users",
            "transactions.delivery_quotes -> identity.users",
            "transactions.delivery_quotes -> marketplace.partners",
            "transactions.deliveries -> marketplace.partners",
            "transactions.delivery_events -> identity.users",
            "transactions.delivery_couriers -> identity.users",
            "transactions.delivery_courier_reviews -> identity.users",
            "transactions.ride_drivers -> identity.users",
            "transactions.ride_fleets -> marketplace.partners",
            "transactions.ride_fleet_events -> identity.users",
            "transactions.ride_driver_review_events -> identity.users",
            "transactions.bookings -> marketplace.booking_venues",
            "transactions.bookings -> marketplace.booking_services",
            "transactions.bookings -> marketplace.booking_masters",
            "transactions.customer_vehicles -> identity.users",
            "transactions.auto_quotes -> identity.users",
            "transactions.auto_quotes -> marketplace.booking_venues",
            "transactions.auto_quotes -> marketplace.booking_services",
            "transactions.auto_quotes -> marketplace.booking_masters",
            "marketplace.booking_time_off -> identity.users",
            "marketplace.auto_admin_events -> identity.users",
            "marketplace.health_moderation_events -> identity.users",
            "transactions.auto_specialists -> identity.users",
            "transactions.auto_specialist_categories -> marketplace.auto_service_categories",
            "transactions.auto_specialist_reviews -> identity.users",
            "transactions.auto_jobs -> identity.users",
            "transactions.auto_jobs -> marketplace.auto_service_categories",
            "transactions.auto_job_events -> identity.users",
            "transactions.auto_complaints -> identity.users",
            "transactions.auto_reviews -> identity.users",
            "transactions.auto_reviews -> marketplace.booking_venues",
            "transactions.auto_payments -> identity.users",
            "transactions.auto_payment_events -> identity.users",
            "marketplace.food_favorites -> identity.users",
            "marketplace.grocery_carts -> identity.users",
            "transactions.food_courier_tasks -> identity.users",
            "marketplace.grocery_favorites -> identity.users",
            "marketplace.grocery_lists -> identity.users",
            "marketplace.grocery_product_reviews -> identity.users",
            "marketplace.grocery_product_reviews -> transactions.food_orders",
            "marketplace.food_review_complaints -> identity.users",
            "marketplace.food_reviews -> identity.users",
            "marketplace.food_reviews -> transactions.food_orders",
            "transactions.food_promo_redemptions -> identity.users",
            "transactions.food_promo_redemptions -> marketplace.food_promotions",
            "transactions.education_enrollments -> identity.users",
            "transactions.education_enrollments -> marketplace.education_cohorts",
            "transactions.education_lesson_progress -> marketplace.education_course_lessons",
            "marketplace.education_cohorts -> identity.users",
            "marketplace.education_course_events -> identity.users",
            "transactions.education_quiz_attempts -> marketplace.education_course_quizzes",
            "transactions.education_assignment_submissions -> marketplace.education_assignments");

    @Autowired JdbcTemplate jdbc;
    @Autowired PlatformTransactionManager transactionManager;
    @Autowired Flyway flyway;

    @Test
    void applicationTablesExistOnlyInDocumentedDomainSchemas() {
        List<String> offenders = jdbc.queryForList("""
                select table_schema || '.' || table_name from information_schema.tables
                where table_type = 'BASE TABLE'
                  and table_schema not in ('pg_catalog', 'information_schema')
                order by 1
                """, String.class).stream()
                .filter(name -> !name.equals("public.flyway_schema_history"))
                .filter(name -> !DOMAIN_SCHEMAS.contains(name.substring(0, name.indexOf('.'))))
                .toList();

        assertThat(offenders).as("tables outside domain-owned schemas").isEmpty();
    }

    @Test
    void everyDomainTableHasAPrimaryKey() {
        List<String> withoutKey = jdbc.queryForList("""
                select t.table_schema || '.' || t.table_name
                from information_schema.tables t
                where t.table_type = 'BASE TABLE' and t.table_schema = any (?)
                  and not exists (
                    select 1 from information_schema.table_constraints c
                    where c.table_schema = t.table_schema and c.table_name = t.table_name
                      and c.constraint_type = 'PRIMARY KEY')
                order by 1
                """, String.class, (Object) DOMAIN_SCHEMAS.toArray(String[]::new));

        assertThat(withoutKey).as("domain tables without a primary key").isEmpty();
    }

    @Test
    void crossSchemaForeignKeysAreExactlyTheReviewedStableReferences() {
        Set<String> actual = new TreeSet<>(jdbc.queryForList("""
                select src_ns.nspname || '.' || src.relname || ' -> ' || dst_ns.nspname || '.' || dst.relname
                from pg_constraint con
                join pg_class src on src.oid = con.conrelid
                join pg_namespace src_ns on src_ns.oid = src.relnamespace
                join pg_class dst on dst.oid = con.confrelid
                join pg_namespace dst_ns on dst_ns.oid = dst.relnamespace
                where con.contype = 'f' and src.relnamespace <> dst.relnamespace
                """, String.class));

        assertThat(actual).containsExactlyInAnyOrderElementsOf(REVIEWED_CROSS_SCHEMA_REFERENCES);
    }

    @Test
    void foreignKeysNeverCascadeOrNullifyHistory() {
        List<String> offenders = jdbc.queryForList("""
                select con.conname from pg_constraint con
                join pg_class rel on rel.oid = con.conrelid
                join pg_namespace ns on ns.oid = rel.relnamespace
                where con.contype = 'f' and ns.nspname = any (?)
                  and (con.confdeltype not in ('a', 'r') or con.confupdtype not in ('a', 'r'))
                """, String.class, (Object) DOMAIN_SCHEMAS.toArray(String[]::new));

        assertThat(offenders).as("foreign keys with cascading or nullifying actions").isEmpty();
    }

    @Test
    void flywayHistoryIsSuccessfulContiguousAndFullyApplied() {
        assertThat(jdbc.queryForObject("select count(*) from flyway_schema_history where not success", Integer.class))
                .isZero();
        List<Integer> versions = jdbc.queryForList(
                "select version::int from flyway_schema_history where version is not null order by installed_rank",
                Integer.class);
        assertThat(versions).isNotEmpty();
        for (int index = 0; index < versions.size(); index++) {
            assertThat(versions.get(index)).as("version at position %d", index).isEqualTo(index + 1);
        }
        assertThat(flyway.info().pending()).isEmpty();
        flyway.validate();
    }

    @Test
    void checkConstraintsRejectInvalidRowsAndAcceptValidControls() {
        // Each pair: a valid control proves the statement shape is fine, the invalid one proves the constraint.
        assertAccepted(owner -> jdbc.update("update identity.users set status = 'RESTRICTED' where id = ?", owner));
        assertRejected(owner -> jdbc.update("update identity.users set status = 'BOGUS' where id = ?", owner));

        assertAccepted(owner -> jdbc.update(
                "insert into identity.external_bindings (issuer, subject, user_id) values ('https://issuer.test', 's', ?)", owner));
        assertRejected(owner -> jdbc.update(
                "insert into identity.external_bindings (issuer, subject, user_id) values ('', 's', ?)", owner));

        assertAccepted(owner -> jdbc.update(
                "insert into profile.consumer_profiles (user_id, preferred_language) values (?, 'kk')", owner));
        assertRejected(owner -> jdbc.update(
                "insert into profile.consumer_profiles (user_id, preferred_language) values (?, 'de')", owner));
        assertRejected(owner -> jdbc.update(
                "insert into profile.consumer_profiles (user_id, version) values (?, -1)", owner));

        assertAccepted(owner -> insertAddress(owner, "Home", "43.238949"));
        assertRejected(owner -> insertAddress(owner, "Home", "91"));
        assertRejected(owner -> insertAddress(owner, "   ", "43.238949"));

        assertAccepted(owner -> jdbc.update("insert into serviceability.zones (code) values ('synthetic-zone')"));
        assertRejected(owner -> jdbc.update("insert into serviceability.zones (code) values ('Bad Code')"));

        assertAccepted(owner -> insertPolicy("a".repeat(64)));
        assertRejected(owner -> insertPolicy("not-a-sha"));

        assertAccepted(owner -> jdbc.update(
                "insert into profile.consent_events (user_id, policy_id, action) values (?, ?, 'GRANTED')",
                owner, insertPolicy("b".repeat(64))));
        assertRejected(owner -> jdbc.update(
                "insert into profile.consent_events (user_id, policy_id, action) values (?, ?, 'DELETED')",
                owner, insertPolicy("c".repeat(64))));
    }

    @Test
    void supportCaseConstraintsRejectInvalidRowsAndDuplicateKeys() {
        assertAccepted(owner -> insertCase(owner, "GENERAL", "Synthetic", "k".repeat(16)));
        assertRejected(owner -> insertCase(owner, "ORDER", "Synthetic", "k".repeat(16)));
        assertRejected(owner -> insertCase(owner, "GENERAL", "   ", "k".repeat(16)));
        assertRejected(owner -> insertCase(owner, "GENERAL", "x".repeat(2001), "k".repeat(16)));
        assertRejected(owner -> insertCase(owner, "GENERAL", "Synthetic", "short"));
        assertRejected(owner -> {
            insertCase(owner, "GENERAL", "Synthetic", "d".repeat(16));
            insertCase(owner, "GENERAL", "Synthetic", "d".repeat(16));
        });
        assertRejected(owner -> jdbc.update(
                "insert into support.case_events (case_id, event_type) values (?, 'CREATED')", UUID.randomUUID()));
    }

    private void insertCase(UUID owner, String category, String message, String key) {
        jdbc.update("""
                insert into support.cases (owner_user_id, category, message, idempotency_key, request_sha256)
                values (?, ?, ?, ?, ?)""", owner, category, message, key, "a".repeat(64));
    }

    @Test
    void catalogSchemaIsUnpublishedByDefaultAndRejectsInvalidRows() {
        // Only the D-01 Food Ordering category exists, and only as an unpublished DRAFT (V7).
        assertThat(jdbc.queryForList("select code from marketplace.categories", String.class)).containsExactly("food-ordering");
        assertThat(jdbc.queryForObject(
                "select count(*) from marketplace.categories where status <> 'DRAFT' or published_at is not null", Integer.class)).isZero();
        assertThat(jdbc.queryForObject("select count(*) from marketplace.offerings", Integer.class)).isZero();
        // ADR-014: migrations must never seed partners (no demo restaurants in the public DEV catalog).
        assertThat(jdbc.queryForObject("select count(*) from marketplace.partners", Integer.class)).isZero();

        assertAccepted(owner -> insertCategory("home"));
        assertThat(jdbc.queryForObject("""
                select column_default from information_schema.columns
                where table_schema = 'marketplace' and table_name = 'categories' and column_name = 'status'
                """, String.class)).contains("DRAFT");
        assertRejected(owner -> insertCategory("Bad Code"));
        assertRejected(owner -> jdbc.update(
                "insert into marketplace.categories (code, name_ru, name_kk, status) values ('x', 'р', 'қ', 'LIVE')"));
        assertRejected(owner -> jdbc.update(
                "insert into marketplace.categories (code, name_ru, name_kk, status) values ('x', 'р', 'қ', 'PUBLISHED')"));
        assertAccepted(owner -> jdbc.update("""
                insert into marketplace.categories (code, name_ru, name_kk, status, published_at)
                values ('x', 'р', 'қ', 'PUBLISHED', now())"""));
        assertRejected(owner -> jdbc.update("""
                insert into marketplace.categories (code, name_ru, name_kk) values ('x', '  ', 'қ')"""));
        assertRejected(owner -> {
            insertCategory("dup");
            insertCategory("dup");
        });
        assertRejected(owner -> {
            UUID id = insertCategory("self");
            jdbc.update("update marketplace.categories set parent_id = id where id = ?", id);
        });

        assertAccepted(owner -> insertOffering(insertCategory("c1"), "SERVICE"));
        assertRejected(owner -> insertOffering(insertCategory("c2"), "VOUCHER"));
        assertRejected(owner -> insertOffering(UUID.randomUUID(), "SERVICE"));
        assertRejected(owner -> {
            UUID category = insertCategory("c3");
            insertOffering(category, "PRODUCT");
            jdbc.update("delete from marketplace.categories where id = ?", category);
        });
    }

    private UUID insertCategory(String code) {
        return jdbc.queryForObject("""
                insert into marketplace.categories (code, name_ru, name_kk) values (?, 'Синтетика', 'Синтетика')
                returning id""", UUID.class, code);
    }

    private void insertOffering(UUID category, String kind) {
        jdbc.update("""
                insert into marketplace.offerings (category_id, kind, name_ru, name_kk)
                values (?, ?, 'Синтетика', 'Синтетика')""", category, kind);
    }

    @Test
    void referencesRejectOrphansAndDeletingAReferencedUser() {
        assertRejected(owner -> jdbc.update(
                "insert into profile.consumer_profiles (user_id) values (?)", UUID.randomUUID()));
        assertRejected(owner -> {
            jdbc.update("insert into profile.consumer_profiles (user_id) values (?)", owner);
            jdbc.update("delete from identity.users where id = ?", owner);
        });
    }

    private UUID insertPolicy(String sha256) {
        return jdbc.queryForObject("""
                insert into profile.consent_policies (purpose, policy_version, document_sha256, locale)
                values ('synthetic_purpose', 'v-' || gen_random_uuid(), ?, 'en') returning id
                """, UUID.class, sha256);
    }

    private void insertAddress(UUID owner, String label, String latitude) {
        jdbc.update("""
                insert into profile.consumer_addresses (user_id, label, formatted_address, latitude, longitude)
                values (?, ?, 'Synthetic address', ?::numeric, 76.889709)
                """, owner, label, latitude);
    }

    /** Runs the statement against a fresh synthetic user and requires the constraint to reject it. */
    private void assertRejected(Consumer<UUID> statement) {
        assertThatThrownBy(() -> inRollbackOnlyTransaction(statement))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    private void assertAccepted(Consumer<UUID> statement) {
        inRollbackOnlyTransaction(statement);
    }

    private void inRollbackOnlyTransaction(Consumer<UUID> statement) {
        new TransactionTemplate(transactionManager).executeWithoutResult(status -> {
            status.setRollbackOnly();
            UUID owner = jdbc.queryForObject("insert into identity.users default values returning id", UUID.class);
            statement.accept(owner);
        });
    }
}
