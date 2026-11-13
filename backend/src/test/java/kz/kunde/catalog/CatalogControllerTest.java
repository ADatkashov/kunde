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

    @Test
    void searchMatchesPublishedOnlyRanksAndTreatsWildcardsLiterally() {
        new TransactionTemplate(transactionManager).executeWithoutResult(status -> {
            status.setRollbackOnly();
            jdbc.update("""
                    insert into marketplace.categories (code, name_ru, name_kk, name_en, status, sort_order, published_at) values
                    ('s-sub', 'Большая уборка', 'Үлкен тазалау', null, 'PUBLISHED', 0, now()),
                    ('s-pre', 'Уборка квартир', 'Пәтер', null, 'PUBLISHED', 5, now()),
                    ('s-exact', 'Уборка', 'Тазалау', 'Cleaning', 'PUBLISHED', 9, now()),
                    ('s-draft', 'Уборка черновик', 'Қара', null, 'DRAFT', 0, null),
                    ('s-pct', '100% скидка', 'Жеңілдік', null, 'PUBLISHED', 0, now())""");
            assertThat(controller.search("уборка")).extracting(Category::nameRu)
                    .containsExactly("Уборка", "Уборка квартир", "Большая уборка");
            assertThat(controller.search("  CLEANING ")).extracting(Category::nameRu).containsExactly("Уборка");
            assertThat(controller.search("%")).extracting(Category::nameRu).containsExactly("100% скидка");
            assertThat(controller.search("_")).isEmpty();
            assertThat(controller.search("   ")).isEmpty();
        });
    }
}
