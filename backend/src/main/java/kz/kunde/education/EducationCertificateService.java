package kz.kunde.education;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.UUID;
import kz.kunde.platform.authz.AdminGrants;
import kz.kunde.platform.ApiException;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDPageContentStream;
import org.apache.pdfbox.pdmodel.common.PDRectangle;
import org.apache.pdfbox.pdmodel.font.PDType0Font;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class EducationCertificateService {
    private final JdbcClient db;
    private final AdminGrants grants;

    public EducationCertificateService(JdbcClient db, AdminGrants grants) {
        this.db = db;
        this.grants = grants;
    }

    public Verification verify(UUID code) {
        return db.sql("""
                select course_title as title, organization_name as organization, completed_at,
                       case when revoked_at is null then 'VALID' else 'REVOKED' end as status
                from transactions.education_certificates where code=:code
                """).param("code", code).query(Verification.class).optional()
                .orElseThrow(EducationCertificateService::notFound);
    }

    @Transactional
    public Verification revoke(UUID admin, UUID code, String reason) {
        grants.require(admin, AdminGrants.Permission.EDUCATION_OPERATIONS);
        var certificate = verify(code);
        if ("REVOKED".equals(certificate.status())) return certificate;
        db.sql("""
                update transactions.education_certificates set revoked_at=now(),revoked_by=:admin,revocation_reason=:reason
                where code=:code and revoked_at is null
                """).param("admin", admin).param("code", code).param("reason", reason).update();
        return verify(code);
    }

    public byte[] pdf(UUID user, UUID enrollment) throws IOException {
        var record = db.sql("""
                select c.code,c.course_title,c.organization_name,c.learner_name,c.completed_at,c.revoked_at
                from transactions.education_certificates c
                join transactions.education_enrollments e on e.id=c.enrollment_id
                where c.enrollment_id=:id and e.user_id=:user
                """).param("id", enrollment).param("user", user).query(Printable.class).optional()
                .orElseThrow(EducationCertificateService::notFound);
        if (record.revokedAt() != null) {
            throw new ApiException(HttpStatus.GONE, "CERTIFICATE_REVOKED", "This certificate was revoked");
        }
        return render(record);
    }

    private static byte[] render(Printable record) throws IOException {
        try (var document = new PDDocument(); var bytes = new ByteArrayOutputStream();
                var fontFile = new ClassPathResource("education/fonts/NotoSans-Regular.ttf").getInputStream()) {
            var page = new PDPage(new PDRectangle(842, 595));
            document.addPage(page);
            var font = PDType0Font.load(document, fontFile);
            try (var canvas = new PDPageContentStream(document, page)) {
                canvas.setNonStrokingColor(0.16f, 0.07f, 0.32f);
                canvas.addRect(0, 475, 842, 120);
                canvas.fill();
                canvas.setNonStrokingColor(1f, 1f, 1f);
                text(canvas, font, 28, 55, 533, "KUNDE Education");
                text(canvas, font, 13, 55, 502, "Подтверждение завершения курса");
                canvas.setNonStrokingColor(0.13f, 0.08f, 0.23f);
                float y = 423;
                if (record.learnerName() != null && !record.learnerName().isBlank()) {
                    y = lines(canvas, font, 24, y, record.learnerName(), 2) - 17;
                }
                y = lines(canvas, font, 20, y, record.courseTitle(), 4) - 10;
                y = lines(canvas, font, 14, y, record.organizationName(), 3) - 8;
                text(canvas, font, 13, 55, y, "Дата завершения  " +
                        record.completedAt().atZoneSameInstant(ZoneId.of("Asia/Almaty")).toLocalDate());
                canvas.setNonStrokingColor(0.35f, 0.16f, 0.64f);
                text(canvas, font, 13, 55, 104, "Код проверки  " + record.code());
                text(canvas, font, 11, 55, 80, "/api/v1/education/certificates/" + record.code());
                text(canvas, font, 11, 55, 55, "Синтетический сертификат для DEV/TEST. Не является государственным документом.");
            }
            document.save(bytes);
            return bytes.toByteArray();
        }
    }

    private static float lines(PDPageContentStream canvas, PDType0Font font, int preferredSize, float y,
            String value, int maxLines) throws IOException {
        var glyphs = new ArrayList<Glyph>();
        float totalUnits = 0;
        for (int point : value.codePoints().toArray()) {
            String glyph = Character.isISOControl(point) ? " " : Character.toString(point);
            float units;
            try {
                units = font.getStringWidth(glyph);
            } catch (IllegalArgumentException unsupportedGlyph) {
                glyph = "?";
                units = font.getStringWidth(glyph);
            }
            glyphs.add(new Glyph(glyph, units));
            totalUnits += units;
        }
        // Leave room for glyph boundaries between lines and for the verification footer.
        int size = Math.min(preferredSize, (int) (maxLines * 650_000 / Math.max(totalUnits, 1)));
        var current = new StringBuilder();
        float used = 0;
        for (var glyph : glyphs) {
            float width = glyph.units() * size / 1000;
            if (used + width > 730) {
                text(canvas, font, size, 55, y, current.toString());
                y -= size + 6;
                current.setLength(0);
                used = 0;
            }
            current.append(glyph.text());
            used += width;
        }
        text(canvas, font, size, 55, y, current.toString());
        return y - size - 6;
    }

    private record Glyph(String text, float units) {}

    private static void text(PDPageContentStream canvas, PDType0Font font, int size, float x, float y, String value) throws IOException {
        canvas.beginText();
        canvas.setFont(font, size);
        canvas.newLineAtOffset(x, y);
        canvas.showText(value);
        canvas.endText();
    }

    private static ApiException notFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "CERTIFICATE_NOT_FOUND", "Certificate not found");
    }

    public record Verification(String title, String organization, OffsetDateTime completedAt, String status) {}
    private record Printable(UUID code, String courseTitle, String organizationName, String learnerName,
            OffsetDateTime completedAt, OffsetDateTime revokedAt) {}
}
