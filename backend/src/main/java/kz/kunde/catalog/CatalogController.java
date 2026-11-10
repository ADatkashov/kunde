package kz.kunde.catalog;

import java.util.List;
import jakarta.validation.constraints.Size;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.validation.annotation.Validated;

@RestController
@Validated
@RequestMapping("/api/v1")
public class CatalogController {

    @GetMapping("/categories")
    public List<Category> categories() { return List.of(); }

    @GetMapping("/search")
    public List<Category> search(@RequestParam(defaultValue = "") @Size(max = 200) String q) {
        return List.of();
    }
}
