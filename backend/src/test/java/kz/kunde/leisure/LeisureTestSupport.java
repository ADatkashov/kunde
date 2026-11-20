package kz.kunde.leisure;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.util.UUID;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

/** Shared HTTP helpers for Leisure integration tests. */
final class LeisureTestSupport {
    final MockMvc http;
    final JdbcTemplate db;

    LeisureTestSupport(MockMvc http, JdbcTemplate db) {
        this.http = http;
        this.db = db;
    }

    ResultActions send(String method, String path, String token, String json, String key) throws Exception {
        var request = switch (method) {
            case "GET" -> get(path);
            case "PATCH" -> patch(path);
            case "PUT" -> put(path);
            case "DELETE" -> delete(path);
            default -> post(path);
        };
        request.contentType(MediaType.APPLICATION_JSON);
        if (json != null) { request.content(json); }
        if (token != null) { request.header("Authorization", "Bearer " + token); }
        if (key != null) { request.header("Idempotency-Key", key); }
        return http.perform(request);
    }

    String body(ResultActions r) throws Exception { return r.andReturn().getResponse().getContentAsString(); }

    String loginBody(String phone) throws Exception {
        send("POST", "/api/v1/auth/otp/request", null, "{\"phone\":\"" + phone + "\"}", null).andExpect(status().isAccepted());
        return body(send("POST", "/api/v1/auth/otp/verify", null, "{\"phone\":\"" + phone + "\",\"code\":\"123456\"}", null).andExpect(status().isOk()));
    }

    String login(String phone) throws Exception { return JsonPath.read(loginBody(phone), "$.accessToken"); }

    static UUID subject(String loginBody) throws Exception {
        return UUID.fromString(com.nimbusds.jwt.SignedJWT.parse((String) JsonPath.read(loginBody, "$.accessToken")).getJWTClaimsSet().getSubject());
    }

    String refreshed(String loginBody) throws Exception {
        return JsonPath.read(body(send("POST", "/api/v1/auth/token/refresh", null, "{\"refreshToken\":\"" + JsonPath.read(loginBody, "$.refreshToken") + "\"}", null)
                .andExpect(status().isOk())), "$.accessToken");
    }

    UUID event(String title) { return db.queryForObject("select id from marketplace.leisure_events where title like ? limit 1", UUID.class, title + "%"); }

    UUID firstSession(UUID event) {
        return db.queryForObject("select id from marketplace.leisure_sessions where event_id = ? and status = 'SCHEDULED' and starts_at > now() + interval '3 hours' order by starts_at limit 1", UUID.class, event);
    }

    UUID ticketType(UUID event, String name) {
        return db.queryForObject("select id from marketplace.leisure_ticket_types where event_id = ? and name = ?", UUID.class, event, name);
    }

    UUID seat(UUID session, String row, int n) {
        return db.queryForObject("select id from marketplace.leisure_seats where session_id = ? and row_label = ? and seat_number = ?", UUID.class, session, row, n);
    }
}
