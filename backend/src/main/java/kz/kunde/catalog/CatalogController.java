package kz.kunde.catalog;

import java.util.List;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Size;
import kz.kunde.platform.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
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
     * Name search over PUBLISHED offerings in PUBLISHED categories (SEARCH-001 baseline), same ranking
     * as category search: exact, prefix, substring. Separate path so the /search contract is unchanged.
     * Only the approved partner's id and name are exposed; no price, stock or availability; unpublished rows are never disclosed.
     */
    @GetMapping("/search/offerings")
    public List<Offering> searchOfferings(@RequestParam(defaultValue = "") @Size(max = 200) String q,
            @RequestParam(defaultValue = "50") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(100000) int offset) {
        String term = q.strip();
        if (term.isEmpty()) { return List.of(); }
        String escaped = term.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_");
        String contains = "%" + escaped + "%";
        String prefix = escaped + "%";
        return jdbc.query(OFFERING_SELECT + """
                where o.status = 'PUBLISHED' and c.status = 'PUBLISHED'
                  and (o.name_ru ilike ? or o.name_kk ilike ? or coalesce(o.name_en, '') ilike ?)
                order by case
                           when lower(?) in (lower(o.name_ru), lower(o.name_kk), lower(coalesce(o.name_en, ''))) then 0
                           when o.name_ru ilike ? or o.name_kk ilike ? or coalesce(o.name_en, '') ilike ? then 1
                           else 2 end,
                         o.published_at, o.id
                limit ? offset ?
                """, OFFERING_MAPPER, contains, contains, contains, term, prefix, prefix, prefix, limit, offset);
    }

    /**
     * Published offerings of a published category only. Offerings of partners that are not APPROVED are hidden; no price, stock or availability is
     * exposed or implied: those need approved contracts (TASK-014/015). Unknown, DRAFT or RETIRED
     * categories yield an empty list so existence of unpublished catalog data is not disclosed.
     */
    @GetMapping("/categories/{categoryId}/offerings")
    public List<Offering> offerings(@PathVariable UUID categoryId,
            @RequestParam(defaultValue = "50") @Min(1) @Max(100) int limit,
            @RequestParam(defaultValue = "0") @Min(0) @Max(100000) int offset) {
        return jdbc.query(OFFERING_SELECT + """
                where o.category_id = ? and o.status = 'PUBLISHED' and c.status = 'PUBLISHED'
                order by o.published_at, o.id
                limit ? offset ?
                """, OFFERING_MAPPER, categoryId, limit, offset);
    }

    /** Detail of one PUBLISHED offering in a PUBLISHED category; anything else is indistinguishable 404. */
    @GetMapping("/offerings/{offeringId}")
    public Offering offering(@PathVariable UUID offeringId) {
        return jdbc.query(OFFERING_SELECT + """
                where o.id = ? and o.status = 'PUBLISHED' and c.status = 'PUBLISHED'
                """, OFFERING_MAPPER, offeringId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "OFFERING_NOT_FOUND",
                        "Offering is not available"));
    }

    /** Public view of an APPROVED partner only; unknown and non-approved partners are indistinguishable 404. */
    @GetMapping("/partners/{partnerId}")
    public PartnerSummary partner(@PathVariable UUID partnerId) {
        return jdbc.query("""
                select id, display_name from marketplace.partners
                where id = ? and verification_status = 'APPROVED'
                """, (rs, row) -> new PartnerSummary(rs.getString("id"), rs.getString("display_name")),
                partnerId).stream().findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "PARTNER_NOT_FOUND",
                        "Partner is not available"));
    }

    private static final String OFFERING_SELECT = """
            select o.id, o.category_id, o.kind, o.name_ru, o.name_kk, o.name_en,
                   o.partner_id, p.display_name as partner_name
            from marketplace.offerings o
            join marketplace.categories c on c.id = o.category_id
            join marketplace.partners p on p.id = o.partner_id and p.verification_status = 'APPROVED'
            """;
    private static final RowMapper<Offering> OFFERING_MAPPER = (rs, row) -> new Offering(
            rs.getString("id"), rs.getString("category_id"), rs.getString("kind"),
            rs.getString("name_ru"), rs.getString("name_kk"), rs.getString("name_en"),
            rs.getString("partner_id"), rs.getString("partner_name"));
}
