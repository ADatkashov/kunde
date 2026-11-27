package kz.kunde.partner;

import java.util.UUID;
import kz.kunde.auth.PhoneAuthProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.annotation.Order;
import org.springframework.core.env.Environment;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Safe, repeatable DEV seed of synthetic partners for the Partner Operations pilot. Runs only with
 * {@code app.partner-ops.seed-demo=true} in a dev/local/test environment. It creates two APPROVED synthetic partners whose
 * owners are the synthetic numbers {@value #PARTNER_PHONE} and {@value #OTHER_PHONE} (DEV OTP allowlist), links the first one
 * to the synthetic restaurant {@code partner-kitchen-demo} and venues {@code partner-salon-demo} and {@code home-clean-demo} (Home Services), and leaves the second one
 * without assets (used to verify that a partner cannot touch another partner's data). No real person or business is represented.
 */
@Component
@Order(100)
@ConditionalOnProperty(name = "app.partner-ops.seed-demo", havingValue = "true")
public class PartnerOpsDemoSeeder implements ApplicationRunner {
    public static final String PARTNER_PHONE = "+77000000002";
    public static final String OTHER_PHONE = "+77000000003";
    private static final Logger log = LoggerFactory.getLogger(PartnerOpsDemoSeeder.class);

    private final JdbcTemplate db;
    private final PhoneAuthProperties auth;

    public PartnerOpsDemoSeeder(JdbcTemplate db, PhoneAuthProperties auth, Environment env) {
        String environment = env.getProperty("app.environment", "production");
        if (!java.util.Set.of("dev", "local", "test").contains(environment)) {
            throw new IllegalStateException("The partner demo seed is forbidden outside dev/local/test");
        }
        this.db = db;
        this.auth = auth;
    }

    @Override
    public void run(ApplicationArguments args) {
        UUID demo = seed();
        log.info("Partner demo seed done (partner {})", demo);
    }

    @Transactional
    public UUID seed() {
        UUID first = partner(PARTNER_PHONE, "Демо-партнёр KUNDE (синтетика)");
        partner(OTHER_PHONE, "Демо-партнёр Б (синтетика)");
        db.update("update marketplace.food_restaurants set partner_id = ? where slug = 'partner-kitchen-demo' and partner_id is null", first);
        db.update("update marketplace.food_restaurants set partner_id = ? where slug = 'partner-flowers-demo' and is_synthetic and partner_id is null", first);
        db.update("update marketplace.booking_venues set partner_id = ? where slug = 'partner-salon-demo' and partner_id is null", first);
        db.update("update marketplace.booking_venues set partner_id = ? where slug = 'home-clean-demo' and partner_id is null", first);
        return first;
    }

    private UUID partner(String phone, String name) {
        UUID user = db.query("select user_id from identity.phone_identities where phone_e164 = ?",
                rs -> rs.next() ? rs.getObject(1, UUID.class) : null, phone);
        if (user == null) {
            user = db.queryForObject("insert into identity.users default values returning id", UUID.class);
            db.update("insert into identity.phone_identities (user_id, phone_e164) values (?, ?)", user, phone);
            db.update("insert into identity.external_bindings (issuer, subject, user_id) values (?, ?, ?)", auth.issuer(), user.toString(), user);
            db.update("insert into profile.consumer_profiles (user_id) values (?)", user);
            db.update("insert into identity.account_events (user_id, event_type) values (?, 'PROVISIONED')", user);
        }
        UUID existing = db.query("select id from marketplace.partners where created_by_user_id = ? and display_name = ?",
                rs -> rs.next() ? rs.getObject(1, UUID.class) : null, user, name);
        if (existing != null) { return existing; }
        UUID partner = db.queryForObject("""
                insert into marketplace.partners (display_name, verification_status, created_by_user_id)
                values (?, 'APPROVED', ?) returning id
                """, UUID.class, name, user);
        db.update("""
                insert into marketplace.partner_verification_events (partner_id, decision, from_status, to_status, actor_user_id)
                values (?, 'SUBMIT', null, 'PENDING_REVIEW', ?)
                """, partner, user);
        db.update("""
                insert into marketplace.partner_verification_events (partner_id, decision, from_status, to_status, actor_user_id, reason)
                values (?, 'APPROVE', 'PENDING_REVIEW', 'APPROVED', ?, 'Synthetic DEV seed')
                """, partner, user);
        db.update("insert into marketplace.partner_staff (partner_id, user_id, role, granted_by_user_id) values (?, ?, 'OWNER', ?)", partner, user, user);
        db.update("insert into marketplace.partner_staff_events (partner_id, subject_user_id, actor_user_id, event_type, role) values (?, ?, ?, 'GRANTED', 'OWNER')",
                partner, user, user);
        return partner;
    }
}
