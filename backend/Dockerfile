# Supported Java 21 / RHEL UBI 10; immutable Linux/amd64 manifests.
FROM eclipse-temurin:21-jdk-ubi10-minimal@sha256:d349d0bbdc1483f90977f5e6298bab46964bf1e37e3c03439d58cdb5356d40b4 AS build
# Official Apache distribution; SHA512 independently verified in hosted probe 43068283648.
ADD --checksum=sha256:1f6d9909266510f039f59aa0e13dcd2c66da85f043e56276e41f2918f8bddaff https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.10.0/apache-maven-3.10.0-bin.zip /opt/maven.zip
WORKDIR /opt
RUN jar -xf maven.zip && rm maven.zip && chmod 755 /opt/apache-maven-3.10.0/bin/mvn
ENV MAVEN_HOME=/opt/apache-maven-3.10.0
ENV PATH="/opt/apache-maven-3.10.0/bin:${PATH}"
WORKDIR /workspace
COPY pom.xml .
COPY src ./src
RUN mvn -B -ntp -DskipTests package

FROM eclipse-temurin:21-jre-ubi10-minimal@sha256:b031b9d49d16229b6d49a354fee4d6ab936d973ee2a0ce13d00167f11bce4ccc
WORKDIR /app
COPY --from=build /workspace/target/kunde-api-*.jar /app/app.jar
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "/app/app.jar"]
