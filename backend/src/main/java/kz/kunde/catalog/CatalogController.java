package kz.kunde.catalog;

import java.util.List;
import jakarta.validation.constraints.Size;
import org.springframework.jdbc.core.JdbcTemplate;
import java.util.UUID;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
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

    /**
     * Baseline relevance over published categories only: case-insensitive match on RU/KK/EN names,
     * ranked exact, then prefix, then substring, then catalog order. LIKE wildcards in input are literal.
     */
    @GetMapping("/search")
    public List<Category> search(@RequestParam(defaultValue = "") @Size(max = 200) String q) {
        String term = q.strip();
        if (term.isEmpty()) { return List.of(); }
        String escaped = term.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_");
        String contains = "%" + escaped + "%";
        String prefix = escaped + "%";
        return jdbc.query("""
                select id, name_ru, name_kk from marketplace.categories
                where status = 'PUBLISHED'
                  and (name_ru ilike ? or name_kk ilike ? or coalesce(name_en, '') ilike ?)
                order by case
                           when lower(?) in (lower(name_ru), lower(name_kk), lower(coalesce(name_en, ''))) then 0
                           when name_ru ilike ? or name_kk ilike ? or coalesce(name_en, '') ilike ? then 1
                           else 2 end,
                         sort_order, code
                """, (rs, row) -> new Category(rs.getString("id"), rs.getString("name_ru"),
                        rs.getString("name_kk"), null, null),
                contains, contains, contains, term, prefix, prefix, prefix);
    }

    /**
     * Published offerings of a published category only. No price, stock, partner or availability is
     * exposed or implied: those need approved contracts (TASK-014/015). Unknown, DRAFT or RETIRED
     * categories yield an empty list so existence of unpublished catalog data is not disclosed.
     */
    @GetMapping("/categories/{categoryId}/offerings")
    public List<Offering> offerings(@PathVariable UUID categoryId) {
        return jdbc.query("""
                select o.id, o.category_id, o.kind, o.name_ru, o.name_kk, o.name_en
                from marketplace.offerings o
                join marketplace.categories c on c.id = o.category_id
                where o.category_id = ? and o.status = 'PUBLISHED' and c.status = 'PUBLISHED'
                order by o.published_at, o.id
                """, (rs, row) -> new Offering(rs.getString("id"), rs.getString("category_id"),
                        rs.getString("kind"), rs.getString("name_ru"), rs.getString("name_kk"),
                        rs.getString("name_en")), categoryId);
    }
}
