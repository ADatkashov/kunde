package kz.kunde.platform;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.mock.web.MockFilterChain;

class RequestCorrelationFilterTest {
    private final RequestCorrelationFilter filter = new RequestCorrelationFilter();

    @Test
    void preservesSafeCallerCorrelationId() throws Exception {
        var request = new MockHttpServletRequest();
        request.addHeader(RequestCorrelationFilter.HEADER, "mobile-req_123");
        var response = new MockHttpServletResponse();

        filter.doFilter(request, response, new MockFilterChain());

        assertThat(response.getHeader(RequestCorrelationFilter.HEADER)).isEqualTo("mobile-req_123");
    }

    @Test
    void replacesUnsafeCallerValueAndAlwaysReturnsAnIdentifier() throws Exception {
        var request = new MockHttpServletRequest();
        request.addHeader(RequestCorrelationFilter.HEADER, "secret\r\nInjected: yes");
        var response = new MockHttpServletResponse();

        filter.doFilter(request, response, new MockFilterChain());

        assertThat(response.getHeader(RequestCorrelationFilter.HEADER)).matches(
                "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}");
    }

    @Test
    void exposesIdToTheChainAndClearsMdcEvenWhenTheChainFails() throws Exception {
        var request = new MockHttpServletRequest();
        request.addHeader(RequestCorrelationFilter.HEADER, "mdc-check");
        var response = new MockHttpServletResponse();
        String[] seen = new String[1];

        org.assertj.core.api.Assertions.assertThatThrownBy(() -> filter.doFilter(request, response,
                (req, res) -> {
                    seen[0] = org.slf4j.MDC.get(RequestCorrelationFilter.MDC_KEY);
                    throw new jakarta.servlet.ServletException("synthetic failure");
                })).isInstanceOf(jakarta.servlet.ServletException.class);

        assertThat(seen[0]).isEqualTo("mdc-check");
        assertThat(org.slf4j.MDC.get(RequestCorrelationFilter.MDC_KEY)).isNull();
    }
}
