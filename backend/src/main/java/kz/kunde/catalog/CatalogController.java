package kz.kunde.catalog;

import java.util.List;
import jakarta.validation.constraints.Size;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.validation.annotation.Validated;

@RestController
@Validated
@RequestMapping("/api/v1")
public class CatalogController {
    private final JdbcTemplate jdbc;

    public CatalogController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    /** Only explicitly published categories are visible; DRAFT and RETIRED rows are never returned. */
    @GetMapping("/categories")
    public List<Category> categories() {
        return jdbc.query("""
                select id, name_ru, name_kk from marketplace.categories
                where status = 'PUBLISHED' order by sort_order, code
                """, (rs, row) -> new Category(rs.getString("id"), rs.getString("name_ru"),
                rs.getString("name_kk"), null, null));
    }

    @GetMapping("/search")
    public List<Category> search(@RequestParam(defaultValue = "") @Size(max = 200) String q) {
        return List.of();
    }
}
