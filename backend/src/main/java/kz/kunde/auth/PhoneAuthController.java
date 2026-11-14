package kz.kunde.auth;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/auth")
@ConditionalOnProperty(name = "app.auth.phone.enabled", havingValue = "true")
public class PhoneAuthController {
    private final PhoneAuthService auth;

    public PhoneAuthController(PhoneAuthService auth) {
        this.auth = auth;
    }

    /** Same 202 body for every well-formed number: registration status is never disclosed. */
    @PostMapping("/otp/request")
    ResponseEntity<PhoneAuthService.OtpChallenge> request(@Valid @RequestBody PhoneRequest body) {
        return ResponseEntity.status(HttpStatus.ACCEPTED).cacheControl(CacheControl.noStore())
                .body(auth.requestOtp(body.phone()));
    }

    @PostMapping("/otp/verify")
    ResponseEntity<TokenResponse> verify(@Valid @RequestBody VerifyRequest body) {
        return tokens(auth.verifyOtp(body.phone(), body.code()));
    }

    @PostMapping("/token/refresh")
    ResponseEntity<TokenResponse> refresh(@Valid @RequestBody RefreshRequest body) {
        return tokens(auth.refresh(body.refreshToken()));
    }

    @PostMapping("/logout")
    ResponseEntity<Void> logout(@Valid @RequestBody RefreshRequest body) {
        auth.logout(body.refreshToken());
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    private static ResponseEntity<TokenResponse> tokens(PhoneAuthService.Tokens tokens) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(new TokenResponse(tokens.accessToken(),
                tokens.refreshToken(), "Bearer", tokens.expiresIn(), tokens.refreshExpiresIn()));
    }

    public record PhoneRequest(@NotBlank @Size(max = 32) String phone) {}
    public record VerifyRequest(@NotBlank @Size(max = 32) String phone, @NotBlank @Pattern(regexp = "[0-9]{6}") String code) {}
    public record RefreshRequest(@NotBlank @Size(max = 128) String refreshToken) {}
    public record TokenResponse(String accessToken, String refreshToken, String tokenType, int expiresIn,
            int refreshExpiresIn) {}
}
