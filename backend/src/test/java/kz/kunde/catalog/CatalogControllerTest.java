package kz.kunde.catalog;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

@SpringBootTest
class CatalogControllerTest {
    @Autowired CatalogController controller;
    @Autowired JdbcTemplate jdbc;
    @Autowired PlatformTransactionManager transactionManager;

    @Test
    void doesNotAdvertiseUnapprovedOrDemoCategories() {
        assertThat(controller.categories()).isEmpty();
        assertThat(controller.search("food")).isEmpty();
        assertThat(controller.search("")).isEmpty();
    }

    @Test
    void returnsOnlyPublishedCategoriesInOrder() {
        new TransactionTemplate(transactionManager).executeWithoutResult(status -> {
            status.setRollbackOnly();
            jdbc.update("""
                    insert into marketplace.categories (code, name_ru, name_kk, status, sort_order, published_at) values
                    ('t-b', 'Б', 'Б', 'PUBLISHED', 2, now()), ('t-a', 'А', 'А', 'PUBLISHED', 1, now()),
                    ('t-d', 'Д', 'Д', 'DRAFT', 0, null), ('t-r', 'Р', 'Р', 'RETIRED', 0, null)""");
            assertThat(controller.categories()).extracting(Category::nameRu).containsExactly("А", "Б");
        });
    }
}
