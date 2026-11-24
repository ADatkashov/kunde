package kz.kunde;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

/**
 * TASK-054 (partial): recovery and concurrency properties of the implemented consumer journey
 * (first sign-in provisioning, support cases) against real PostgreSQL. There is no pilot
 * search/order journey yet, so this is NOT the pilot E2E suite. Synthetic identities only.
 */
@SpringBootTest(properties = {
        "app.identity.consumer-enabled=true",
        "app.security.oidc.issuer-uri=https://identity.example.test",
        "app.security.oidc.audience=kunde-api"
})
@AutoConfigureMockMvc
class ConsumerRecoveryConcurrencyIntegrationTest {
    private static final String CASES = "/api/v1/me/support/cases";
    private static final String BODY = "{\"category\":\"GENERAL\",\"message\":\"Synthetic question\"}";
    private static final int THREADS = 12;

    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;
    @MockitoBean JwtDecoder issuerJwtDecoder;

    private String auth() {
        return auth(UUID.randomUUID().toString());
    }

    private String auth(String subject) {
        String token = UUID.randomUUID().toString();
        when(issuerJwtDecoder.decode(token)).thenReturn(Jwt.withTokenValue("fixture").header("alg", "RS256")
                .issuer("https://identity.example.test").subject(subject)
                .issuedAt(Instant.now()).expiresAt(Instant.now().plusSeconds(300))
                .audience(List.of("kunde-api")).claim("typ", "Bearer")
                .claim("azp", "kunde-consumer").claim("scope", "openid kunde.consumer").build());
        return "Bearer " + token;
    }

    /** Runs the calls at the same moment and returns their HTTP statuses. */
    private List<Integer> race(List<Callable<Integer>> calls) throws Exception {
        ExecutorService pool = Executors.newFixedThreadPool(calls.size());
        try {
            CountDownLatch ready = new CountDownLatch(calls.size());
            CountDownLatch go = new CountDownLatch(1);
            List<Future<Integer>> futures = new ArrayList<>();
            for (Callable<Integer> call : calls) {
                futures.add(pool.submit(() -> {
                    ready.countDown();
                    go.await();
                    return call.call();
                }));
            }
            ready.await();
            go.countDown();
            List<Integer> statuses = new ArrayList<>();
            for (Future<Integer> future : futures) {
                statuses.add(future.get());
            }
            return statuses;
        } finally {
            pool.shutdownNow();
        }
    }

    private int openCase(String auth, String key) throws Exception {
        return http.perform(post(CASES).header("Authorization", auth).header("Idempotency-Key", key)
                .contentType(MediaType.APPLICATION_JSON).content(BODY)).andReturn().getResponse().getStatus();
    }

    private int caseCount(String subjectAuth) throws Exception {
        String body = http.perform(get(CASES).header("Authorization", subjectAuth)).andReturn()
                .getResponse().getContentAsString();
        return body.equals("[]") ? 0 : body.split("\"id\"", -1).length - 1;
    }

    @Test
    void concurrentRetriesWithOneKeyCreateExactlyOneCase() throws Exception {
        String auth = auth();
        String key = UUID.randomUUID().toString();
        List<Callable<Integer>> calls = new ArrayList<>();
        for (int i = 0; i < THREADS; i++) {
            calls.add(() -> openCase(auth, key));
        }
        List<Integer> statuses = race(calls);
        assertThat(statuses).containsOnly(200, 201);
        assertThat(statuses.stream().filter(s -> s == 201).count()).isEqualTo(1);
        assertThat(db.queryForObject(
                "select count(*) from support.cases where idempotency_key = ?", Integer.class, key)).isEqualTo(1);
    }

    @Test
    void concurrentRequestsWithDifferentKeysCannotExceedTheCaseCap() throws Exception {
        String auth = auth();
        List<Callable<Integer>> calls = new ArrayList<>();
        for (int i = 0; i < THREADS * 2; i++) {
            calls.add(() -> openCase(auth, UUID.randomUUID().toString()));
        }
        List<Integer> statuses = race(calls);
        assertThat(statuses.stream().filter(s -> s == 201).count()).isEqualTo(10);
        assertThat(statuses.stream().filter(s -> s == 409).count()).isEqualTo(THREADS * 2 - 10);
        assertThat(caseCount(auth)).isEqualTo(10);
    }

    @Test
    void concurrentEscalationRequestsRecordOneEvent() throws Exception {
        String auth = auth();
        String id = null;
        openCase(auth, UUID.randomUUID().toString());
        String listed = http.perform(get(CASES).header("Authorization", auth)).andReturn().getResponse()
                .getContentAsString();
        id = listed.replaceAll(".*\"id\":\"([0-9a-f-]{36})\".*", "$1");
        String caseId = id;
        List<Callable<Integer>> calls = new ArrayList<>();
        for (int i = 0; i < THREADS; i++) {
            calls.add(() -> http.perform(post(CASES + "/" + caseId + "/escalation").header("Authorization", auth))
                    .andReturn().getResponse().getStatus());
        }
        assertThat(race(calls)).containsOnly(200);
        assertThat(db.queryForObject("""
                select count(*) from support.case_events where case_id = ?::uuid
                and event_type = 'ESCALATION_REQUESTED'""", Integer.class, caseId)).isEqualTo(1);
    }

    @Test
    void concurrentFirstRequestsOfOneNewIdentityProvisionOneAccount() throws Exception {
        String subject = UUID.randomUUID().toString();
        String auth = auth(subject);
        List<Callable<Integer>> calls = new ArrayList<>();
        for (int i = 0; i < THREADS; i++) {
            calls.add(() -> http.perform(get("/api/v1/me").header("Authorization", auth))
                    .andReturn().getResponse().getStatus());
        }
        assertThat(race(calls)).containsOnly(200);
        assertThat(db.queryForObject("""
                select count(*) from identity.external_bindings
                where issuer = 'https://identity.example.test' and subject = ?""", Integer.class, subject))
                .isEqualTo(1);
        assertThat(db.queryForObject("""
                select count(*) from profile.consumer_profiles p
                join identity.external_bindings b on b.user_id = p.user_id
                where b.subject = ?""", Integer.class, subject)).isEqualTo(1);
    }
}
