package kz.kunde.catalog;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class CatalogControllerTest {
    private final CatalogController controller = new CatalogController();

    @Test
    void doesNotAdvertiseUnapprovedOrDemoCategories() {
        assertThat(controller.categories()).isEmpty();
        assertThat(controller.search("food")).isEmpty();
        assertThat(controller.search("")).isEmpty();
    }
}
