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

    /** Synthetic APPROVED partner; call inside the rolled-back transaction. */
    private java.util.UUID partner(String status) {
        var user = jdbc.queryForObject("insert into identity.users default values returning id", java.util.UUID.class);
        return jdbc.queryForObject("""
                insert into marketplace.partners (display_name, verification_status, created_by_user_id)
                values ('Synthetic Partner', ?, ?) returning id""", java.util.UUID.class, status, user);
    }

    @Test
    void doesNotAdvertiseUnapprovedOrDemoCategories() {
        assertThat(controller.categories()).isEmpty();
        assertThat(controller.search("food")).isEmpty();
        assertThat(controller.search("")).isEmpty();
        assertThat(controller.searchOfferings("food", 50, 0)).isEmpty();
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

    @Test
    void offeringsAreVisibleOnlyWhenOfferingAndCategoryArePublished() {
        new TransactionTemplate(transactionManager).executeWithoutResult(status -> {
            status.setRollbackOnly();
            partner("APPROVED");
            var pub = jdbc.queryForObject("""
                    insert into marketplace.categories (code, name_ru, name_kk, status, published_at)
                    values ('o-pub', 'К', 'К', 'PUBLISHED', now()) returning id""", java.util.UUID.class);
            var draft = jdbc.queryForObject("""
                    insert into marketplace.categories (code, name_ru, name_kk) values ('o-draft', 'Ч', 'Ч') returning id""",
                    java.util.UUID.class);
            jdbc.update("""
                    insert into marketplace.offerings (category_id, kind, name_ru, name_kk, status, published_at, partner_id) values
                    (?, 'SERVICE', 'Опубликовано', 'Жарияланды', 'PUBLISHED', now(), (select id from marketplace.partners)),
                    (?, 'SERVICE', 'Черновик', 'Қара', 'DRAFT', null, (select id from marketplace.partners)),
                    (?, 'PRODUCT', 'Приостановлено', 'Тоқтатылды', 'SUSPENDED', null, (select id from marketplace.partners)),
                    (?, 'SERVICE', 'В черновой категории', 'Қара санат', 'PUBLISHED', now(), (select id from marketplace.partners))""",
                    pub, pub, pub, draft);
            assertThat(controller.offerings(pub, 50, 0)).extracting(Offering::nameRu).containsExactly("Опубликовано");
            assertThat(controller.offerings(draft, 50, 0)).isEmpty();
            var shown = controller.offerings(pub, 50, 0).get(0);
            assertThat(controller.offering(java.util.UUID.fromString(shown.id())).nameRu()).isEqualTo("Опубликовано");
            assertThat(controller.offerings(pub, 1, 1)).isEmpty();
            var hidden = jdbc.queryForObject("select id from marketplace.offerings where name_ru = 'Черновик'", java.util.UUID.class);
            var inDraftCategory = jdbc.queryForObject("select id from marketplace.offerings where name_ru = 'В черновой категории'", java.util.UUID.class);
            for (var id : java.util.List.of(hidden, inDraftCategory, java.util.UUID.randomUUID())) {
                org.assertj.core.api.Assertions.assertThatThrownBy(() -> controller.offering(id))
                        .isInstanceOf(kz.kunde.platform.ApiException.class)
                        .hasFieldOrPropertyWithValue("code", "OFFERING_NOT_FOUND");
            }
            assertThat(controller.offerings(java.util.UUID.randomUUID(), 50, 0)).isEmpty();
        });
    }

    @Test
    void offeringSearchIsPublishedOnlyRankedPaginatedAndWildcardSafe() {
        new TransactionTemplate(transactionManager).executeWithoutResult(status -> {
            status.setRollbackOnly();
            partner("APPROVED");
            var pub = jdbc.queryForObject("""
                    insert into marketplace.categories (code, name_ru, name_kk, status, published_at)
                    values ('os-pub', 'К', 'К', 'PUBLISHED', now()) returning id""", java.util.UUID.class);
            var draft = jdbc.queryForObject("""
                    insert into marketplace.categories (code, name_ru, name_kk) values ('os-draft', 'Ч', 'Ч') returning id""",
                    java.util.UUID.class);
            jdbc.update("""
                    insert into marketplace.offerings (category_id, kind, name_ru, name_kk, name_en, status, published_at, partner_id) values
                    (?, 'SERVICE', 'Генеральная уборка', 'Бас тазалау', null, 'PUBLISHED', now() - interval '3 minute', (select id from marketplace.partners)),
                    (?, 'SERVICE', 'Уборка квартиры', 'Пәтер', null, 'PUBLISHED', now() - interval '2 minute', (select id from marketplace.partners)),
                    (?, 'SERVICE', 'Уборка', 'Тазалау', 'Cleaning', 'PUBLISHED', now() - interval '1 minute', (select id from marketplace.partners)),
                    (?, 'SERVICE', 'Уборка черновик', 'Қара', null, 'DRAFT', null, (select id from marketplace.partners)),
                    (?, 'PRODUCT', 'Уборка приостановлена', 'Тоқтатылды', null, 'SUSPENDED', null, (select id from marketplace.partners)),
                    (?, 'SERVICE', 'Уборка в черновой категории', 'Қара санат', null, 'PUBLISHED', now(), (select id from marketplace.partners)),
                    (?, 'PRODUCT', '100% чистота', 'Тазалық', null, 'PUBLISHED', now(), (select id from marketplace.partners))""",
                    pub, pub, pub, pub, pub, draft, pub);
            assertThat(controller.searchOfferings("уборка", 50, 0)).extracting(Offering::nameRu)
                    .containsExactly("Уборка", "Уборка квартиры", "Генеральная уборка");
            assertThat(controller.searchOfferings(" CLEANING ", 50, 0)).extracting(Offering::nameRu)
                    .containsExactly("Уборка");
            assertThat(controller.searchOfferings("уборка", 1, 1)).extracting(Offering::nameRu)
                    .containsExactly("Уборка квартиры");
            assertThat(controller.searchOfferings("%", 50, 0)).extracting(Offering::nameRu)
                    .containsExactly("100% чистота");
            assertThat(controller.searchOfferings("_", 50, 0)).isEmpty();
            assertThat(controller.searchOfferings("   ", 50, 0)).isEmpty();
            assertThat(controller.searchOfferings("черновик", 50, 0)).isEmpty();
        });
    }

    @Test
    void offeringsRequireAnApprovedPartnerAndExposeItsIdentity() {
        new TransactionTemplate(transactionManager).executeWithoutResult(status -> {
            status.setRollbackOnly();
            var cat = jdbc.queryForObject("""
                    insert into marketplace.categories (code, name_ru, name_kk, status, published_at)
                    values ('p-pub', 'К', 'К', 'PUBLISHED', now()) returning id""", java.util.UUID.class);
            var approved = partner("APPROVED");
            var pending = partner("PENDING_REVIEW");
            var suspended = partner("SUSPENDED");
            for (var row : java.util.List.of(new Object[] {"Одобренный", approved}, new Object[] {"Ожидает", pending},
                    new Object[] {"Приостановленный", suspended})) {
                jdbc.update("""
                        insert into marketplace.offerings (category_id, kind, name_ru, name_kk, status, published_at, partner_id)
                        values (?, 'SERVICE', ?, 'Қ', 'PUBLISHED', now(), ?)""", cat, row[0], row[1]);
            }
            var shown = controller.offerings(cat, 50, 0);
            assertThat(shown).extracting(Offering::nameRu).containsExactly("Одобренный");
            assertThat(shown.get(0).partnerId()).isEqualTo(approved.toString());
            assertThat(shown.get(0).partnerName()).isEqualTo("Synthetic Partner");
            assertThat(controller.searchOfferings("Ожидает", 50, 0)).isEmpty();
            assertThat(controller.searchOfferings("Одобренный", 50, 0)).hasSize(1);
            // Losing approval hides the offering again without touching its own status.
            jdbc.update("update marketplace.partners set verification_status = 'SUSPENDED' where id = ?", approved);
            assertThat(controller.offerings(cat, 50, 0)).isEmpty();
        });
    }

    @Test
    void databaseRejectsPublishedOfferingWithoutPartner() {
        new TransactionTemplate(transactionManager).executeWithoutResult(status -> {
            status.setRollbackOnly();
            var cat = jdbc.queryForObject("""
                    insert into marketplace.categories (code, name_ru, name_kk) values ('np-cat', 'К', 'К') returning id""",
                    java.util.UUID.class);
            org.assertj.core.api.Assertions.assertThatThrownBy(() -> jdbc.update("""
                    insert into marketplace.offerings (category_id, kind, name_ru, name_kk, status, published_at)
                    values (?, 'SERVICE', 'Без партнёра', 'Қ', 'PUBLISHED', now())""", cat))
                    .hasMessageContaining("offerings_published_has_partner");
        });
    }
}
