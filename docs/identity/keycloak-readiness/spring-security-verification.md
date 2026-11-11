# Spring Security verification and Windows build

The live drill starts the executable JAR with the existing `identity-poc` profile, exact synthetic Keycloak issuer, API audience and a loopback listener. The normal production JWT configuration and the prior ZITADEL path remain available through their existing contracts.

## Build investigation

- The existing JAR admitted an exclusive read/write open at inspection. An active Java Maven parent and a KUNDE application process were present. No observed command line launched the old file as a JAR.
- Initial offline `mvn clean verify` lacked `maven-clean-plugin:3.4.1`. The standard [Maven TLS bootstrap](../poc/maven-tls.md) validated the Windows certificate chain and used the trusted AVG inspection root for Maven Central. Certificate and hostname verification stayed enabled.
- The repository-path retry reached Maven Clean and failed deleting `backend/target/classes/application-identity-poc.yml`. Windows reported the file as `ReadOnly, Archive`, and exclusive read/write returned `0x80070005` (access denied). An existing Maven `spring-boot:run` used the shared backend. The separate source copy avoided the shared target without changing its attributes, the POM or the running service.
- AVG TLS interception was observed. That observation does not identify the process that held any build file or establish that antivirus caused the earlier Spring Boot rename failure.

## Verified artifact

Maven 3.9.9 with Java 21.0.9 ran `mvn clean verify` on the isolated copy of the current backend. **24 passed, 0 failures, 0 errors, 0 skipped.** Boot repackage renamed the original archive and added dependencies under `BOOT-INF/`. Archive inspection found both the Boot launcher and KUNDE application class. The executable artifact is `kunde-api-0.1.0-SNAPSHOT.jar`, 33,396,461 bytes, SHA-256 `917ab39ad9df8a6c2de4088383de42bc8a6597dfa86dac7899b27a767dd41a2c`.

Keep build output separate from a running development service. For a later in-place build, stop only the process using that workspace and check generated file attributes before cleaning.

The exact verified JAR was launched with `java -jar` on `127.0.0.1:18086`. The live probe observed healthy startup and authenticated HTTP 200 from the packaged application.
