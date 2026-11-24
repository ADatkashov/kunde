# Supported Java 21 / RHEL UBI 10; immutable Linux/amd64 manifests.
FROM eclipse-temurin:21-jdk-ubi10-minimal@sha256:d349d0bbdc1483f90977f5e6298bab46964bf1e37e3c03439d58cdb5356d40b4 AS build
# Gradle is fetched by the pinned wrapper (distributionSha256Sum in gradle/wrapper/gradle-wrapper.properties); the wrapper
# jar is started directly because the minimal UBI image has no xargs for the gradlew shell script.
WORKDIR /workspace
COPY settings.gradle.kts build.gradle.kts ./
COPY gradle ./gradle
COPY platform ./platform
COPY services ./services
COPY app ./app
RUN java -cp gradle/wrapper/gradle-wrapper.jar org.gradle.wrapper.GradleWrapperMain --no-daemon -q bootJar

FROM eclipse-temurin:21-jre-ubi10-minimal@sha256:b031b9d49d16229b6d49a354fee4d6ab936d973ee2a0ce13d00167f11bce4ccc
WORKDIR /app
COPY --from=build /workspace/build/libs/kunde-api-*.jar /app/app.jar
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "/app/app.jar"]
