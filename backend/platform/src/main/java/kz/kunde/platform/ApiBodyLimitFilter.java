package kz.kunde.platform;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ReadListener;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletInputStream;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletRequestWrapper;
import jakarta.servlet.http.HttpServletResponse;
import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/** Bounds bodies before the current synchronous JSON API can parse or act on them. */
@Component
public class ApiBodyLimitFilter extends OncePerRequestFilter {
    private final ApiSecurityErrorWriter errors;
    private final Counter denied;
    private final int maxBytes;

    public ApiBodyLimitFilter(ApiSecurityErrorWriter errors, MeterRegistry metrics,
            @Value("${app.security.max-body-bytes:65536}") int maxBytes) {
        if (maxBytes < 1 || maxBytes > 1048576) {
            throw new IllegalArgumentException("API body limit must be between 1 and 1048576 bytes");
        }
        this.errors = errors;
        this.denied = metrics.counter("kunde.api.body_limit.denied");
        this.maxBytes = maxBytes;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getServletPath();
        return !(path.equals("/api/v1") || path.startsWith("/api/v1/"));
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
            FilterChain chain) throws ServletException, IOException {
        if (request.getContentLengthLong() > maxBytes) {
            reject(request, response);
            return;
        }
        // Count actual bytes even when Content-Length is absent or understates the stream.
        byte[] body = request.getInputStream().readNBytes(maxBytes + 1);
        if (body.length > maxBytes) {
            reject(request, response);
            return;
        }
        chain.doFilter(new BufferedBodyRequest(request, body), response);
    }

    private void reject(HttpServletRequest request, HttpServletResponse response) throws IOException {
        denied.increment();
        response.setHeader("Cache-Control", "no-store");
        errors.write(request, response, HttpStatus.PAYLOAD_TOO_LARGE,
                "PAYLOAD_TOO_LARGE", "API request body exceeds the configured byte limit");
    }

    private static final class BufferedBodyRequest extends HttpServletRequestWrapper {
        private final ServletInputStream input;
        private boolean inputRequested;
        private BufferedReader reader;

        private BufferedBodyRequest(HttpServletRequest request, byte[] body) {
            super(request);
            var bytes = new ByteArrayInputStream(body);
            input = new ServletInputStream() {
                @Override public int read() { return bytes.read(); }
                @Override public int read(byte[] target, int offset, int length) {
                    return bytes.read(target, offset, length);
                }
                @Override public boolean isFinished() { return bytes.available() == 0; }
                @Override public boolean isReady() { return true; }
                @Override public void setReadListener(ReadListener listener) {
                    throw new IllegalStateException("Only synchronous API body reads are supported");
                }
            };
        }

        @Override
        public ServletInputStream getInputStream() {
            if (reader != null) throw new IllegalStateException("getReader() was already called");
            inputRequested = true;
            return input;
        }

        @Override
        public BufferedReader getReader() {
            if (inputRequested) throw new IllegalStateException("getInputStream() was already called");
            if (reader == null) {
                Charset encoding = getCharacterEncoding() == null ? StandardCharsets.ISO_8859_1
                        : Charset.forName(getCharacterEncoding());
                reader = new BufferedReader(new InputStreamReader(input, encoding));
            }
            return reader;
        }
    }
}
