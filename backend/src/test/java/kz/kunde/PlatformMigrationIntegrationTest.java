package kz.kunde;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.flywaydb.core.Flyway;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class PlatformMigrationIntegrationTest {
    @Test
    void migrationPreservesErrorDatesStatelessnessAndSecurityHeaders() throws Exception {
        mockMvc.perform(post("/api/v1/protected-test"))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.timestamp").isString())
                .andExpect(jsonPath("$.code").value("AUTHENTICATION_NOT_CONFIGURED"))
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.header()
                        .string("X-Content-Type-Options", "nosniff"))
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.header()
                        .string("X-Frame-Options", "DENY"))
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.header()
                        .doesNotExist("Set-Cookie"));
    }

    @Test
    void untrustedCrossOriginPreflightCannotBypassAuthentication() throws Exception {
        mockMvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options("/api/v1/capabilities")
                .header("Origin", "https://untrusted.example.test")
                .header("Access-Control-Request-Method", "GET"))
                .andExpect(status().isForbidden());
    }

    @Autowired JdbcTemplate jdbcTemplate;
    @Autowired MockMvc mockMvc;
    @Autowired Flyway flyway;

    @Test
    void flywayCreatesOnlyTheDocumentedDomainNamespaces() {
        List<String> namespaces = jdbcTemplate.queryForList(
                "select schema_name from information_schema.schemata " +
                        "where schema_name in ('identity','profile','marketplace','transactions','payments','support') " +
                        "order by schema_name", String.class);

        assertThat(namespaces).containsExactly("identity", "marketplace", "payments", "profile", "support", "transactions");
        assertThat(jdbcTemplate.queryForObject(
                "select count(*) from flyway_schema_history where version = '1' and success", Integer.class)).isEqualTo(1);
        assertThat(jdbcTemplate.queryForObject(
                "select count(*) from flyway_schema_history where version = '2' and success", Integer.class)).isEqualTo(1);
        assertThat(jdbcTemplate.queryForObject(
                "select count(*) from information_schema.tables where table_schema = 'identity' and table_name = 'external_bindings'",
                Integer.class)).isEqualTo(1);
        assertThat(jdbcTemplate.queryForObject(
                "select count(*) from information_schema.tables where table_schema = 'profile' and table_name = 'consumer_profiles'",
                Integer.class)).isEqualTo(1);
        assertThat(flyway.migrate().migrationsExecuted).isZero();
    }

    @Test
    @org.springframework.transaction.annotation.Transactional
    void addressSchemaStartsWithoutApprovedServiceZones() {
        assertThat(jdbcTemplate.queryForObject(
                "select count(*) from flyway_schema_history where version = '3' and success", Integer.class))
                .isEqualTo(1);
        assertThat(jdbcTemplate.queryForObject(
                "select count(*) from information_schema.tables where table_schema = 'profile' and table_name = 'consumer_addresses'",
                Integer.class)).isEqualTo(1);
        assertThat(jdbcTemplate.queryForObject(
                "select count(*) from information_schema.tables where table_schema = 'serviceability' and table_name = 'zones'",
                Integer.class)).isEqualTo(1);

        java.util.UUID owner = jdbcTemplate.queryForObject(
                "insert into identity.users default values returning id", java.util.UUID.class);
        java.util.UUID address = jdbcTemplate.queryForObject("""
                insert into profile.consumer_addresses (user_id, label, formatted_address, latitude, longitude)
                values (?, 'Synthetic', 'Synthetic test address', 43.238949, 76.889709) returning id
                """, java.util.UUID.class, owner);
        assertThat(address).isNotNull();
        assertThat(jdbcTemplate.queryForObject(
                "select count(*) from serviceability.zone_addresses where address_id = ?", Integer.class, address))
                .isZero();
        java.util.UUID zone = jdbcTemplate.queryForObject(
                "insert into serviceability.zones (code) values (?) returning id",
                java.util.UUID.class, "synthetic-zone-" + owner.toString().substring(0, 8));
        assertThat(jdbcTemplate.queryForObject(
                "select enabled from serviceability.zones where id = ?", Boolean.class, zone)).isFalse();
        assertThat(jdbcTemplate.queryForObject(
                "select count(*) from serviceability.zones where enabled and id = ?", Integer.class, zone)).isZero();
    }

    @Test
    void publicCapabilitiesAreAvailableButProtectedRoutesFailClosedWithoutIssuer() throws Exception {
        mockMvc.perform(get("/api/v1/capabilities"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.marketplaceEnabled").value(false))
                .andExpect(jsonPath("$.aiEnabled").value(false));

        mockMvc.perform(post("/api/v1/protected-test"))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code").value("AUTHENTICATION_NOT_CONFIGURED"))
                .andExpect(jsonPath("$.correlationId").isNotEmpty());
    }

    @Test
    void rejectsOversizedSearchQueryWithStableValidationError() throws Exception {
        mockMvc.perform(get("/api/v1/search").param("q", "x".repeat(201)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"))
                .andExpect(jsonPath("$.correlationId").isNotEmpty());
    }

    @Test
    void offeringSearchIsPublicEmptyByDefaultAndValidatesParameters() throws Exception {
        mockMvc.perform(get("/api/v1/search/offerings").param("q", "уборка"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(0));
        mockMvc.perform(get("/api/v1/search/offerings").param("q", "x".repeat(201)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
        mockMvc.perform(get("/api/v1/search/offerings").param("q", "x").param("limit", "101"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(get("/api/v1/search/offerings").param("q", "x").param("offset", "-1"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void exposesHealthReadinessCorrelationAndOpenApi() throws Exception {
        mockMvc.perform(get("/api/v1/health").header("X-Correlation-ID", "ep001-health"))
                .andExpect(status().isOk())
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.header()
                        .string("X-Correlation-ID", "ep001-health"));
        mockMvc.perform(get("/actuator/health/readiness"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("UP"));
        mockMvc.perform(get("/actuator/health/liveness"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("UP"));
        mockMvc.perform(get("/api/v1/openapi.yaml"))
                .andExpect(status().isOk())
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.content()
                        .contentTypeCompatibleWith("application/yaml"))
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.content()
                        .string(org.hamcrest.Matchers.containsString("openapi: 3.1.0")));
    }
}
