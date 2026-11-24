package kz.kunde.platform.support;

import java.util.UUID;
import kz.kunde.platform.support.SupportCaseDirectory.Subject;

/**
 * Implemented by the product that owns a kind of support-case subject (a ride, a delivery). Support asks it whether a
 * consumer may attach a case to a subject, instead of calling the product's services. A subject that is missing or
 * belongs to someone else must look the same to the caller: the implementation throws the product's own "not found"
 * error, exactly as its own consumer endpoints do. A remote adapter can replace the in-process one on extraction.
 */
public interface CaseSubjectOwnership {
    Subject subject();

    /** @throws kz.kunde.platform.ApiException 404 when {@code subjectId} does not exist for {@code owner} */
    void requireOwnedBy(UUID owner, UUID subjectId);
}
