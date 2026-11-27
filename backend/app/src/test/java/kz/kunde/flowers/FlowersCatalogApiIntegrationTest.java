package kz.kunde.flowers;

import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.everyItem;
import static org.hamcrest.Matchers.is;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

@Transactional
@SpringBootTest(properties = {
        "app.environment=test",
        "app.identity.consumer-enabled=true",
        "app.flowers.enabled=true",
        "app.security.rate-limit.requests=100000"
})
@AutoConfigureMockMvc
class FlowersCatalogApiIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate db;

    @BeforeEach
    void seed() {
        db.update("delete from marketplace.flowers_products");
        db.update("delete from marketplace.flowers_shops");
        new FlowersDemoSeeder(db).seed();
    }

    @Test
    void capabilityIsOnAndCategoriesComeInDisplayOrder() throws Exception {
        http.perform(get("/api/v1/capabilities")).andExpect(jsonPath("$.flowersEnabled").value(true));
        http.perform(get("/api/v1/flowers/categories"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(8)))
                .andExpect(jsonPath("$[0].code").value("BOUQUETS"))
                .andExpect(jsonPath("$[7].code").value("OTHER"));
        http.perform(get("/api/v1/flowers/categories").param("featured", "true"))
                .andExpect(jsonPath("$", hasSize(7)))
                .andExpect(jsonPath("$[*].featured", everyItem(is(true))));
    }

    @Test
    void shopsCanBeFilteredByCategoryAndSearchedAndHideUnapprovedPartners() throws Exception {
        http.perform(get("/api/v1/flowers/shops")).andExpect(status().isOk()).andExpect(jsonPath("$", hasSize(4)));
        http.perform(get("/api/v1/flowers/shops").param("category", "SWEETS"))
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].slug").value("flowers-demo-gifts"));
        http.perform(get("/api/v1/flowers/shops").param("q", "ПИОН"))
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].slug").value("flowers-demo-roses"));
        http.perform(get("/api/v1/flowers/shops").param("q", "100%")).andExpect(jsonPath("$", hasSize(0)));
        // a real (non-synthetic) shop with no approved partner is never public
        db.update("insert into marketplace.flowers_shops (slug, name, is_synthetic) values ('hidden-real', 'Скрытый', false)");
        http.perform(get("/api/v1/flowers/shops")).andExpect(jsonPath("$", hasSize(4)));
        http.perform(get("/api/v1/flowers/shops").param("limit", "2").param("offset", "3")).andExpect(jsonPath("$", hasSize(1)));
    }

    @Test
    void shopDetailListsItsProductsAndUnknownOrHiddenShopsAreNotFound() throws Exception {
        String id = db.queryForObject("select id::text from marketplace.flowers_shops where slug = 'flowers-demo-lavka'", String.class);
        http.perform(get("/api/v1/flowers/shops/" + id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.shop.name").value("Цветочная лавка (демо)"))
                .andExpect(jsonPath("$.products", hasSize(4)))
                .andExpect(jsonPath("$.products[*].categoryCode", hasItem("BOXED")));
        http.perform(get("/api/v1/flowers/shops/00000000-0000-0000-0000-000000000000"))
                .andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("FLOWERS_SHOP_NOT_FOUND"));
        db.update("insert into marketplace.flowers_shops (slug, name, is_synthetic) values ('hidden-real', 'Скрытый', false)");
        String hidden = db.queryForObject("select id::text from marketplace.flowers_shops where slug = 'hidden-real'", String.class);
        http.perform(get("/api/v1/flowers/shops/" + hidden)).andExpect(status().isNotFound());
    }

    @Test
    void popularShowsOnlyAvailableOnesFromOpenShops() throws Exception {
        http.perform(get("/api/v1/flowers/products/popular"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[*].popular", everyItem(is(true))))
                .andExpect(jsonPath("$[*].available", everyItem(is(true))));
        long popular = db.queryForObject("select count(*) from marketplace.flowers_products where popular", Long.class);
        http.perform(get("/api/v1/flowers/products/popular").param("limit", "100")).andExpect(status().isBadRequest());
        http.perform(get("/api/v1/flowers/products/popular").param("limit", "30")).andExpect(jsonPath("$", hasSize((int) popular)));
        db.update("update marketplace.flowers_shops set is_open = false");
        http.perform(get("/api/v1/flowers/products/popular")).andExpect(jsonPath("$", hasSize(0)));
    }

    @Test
    void seedingTwiceInsertsNothingNew() {
        org.assertj.core.api.Assertions.assertThat(new FlowersDemoSeeder(db).seed()).isZero();
    }
}
