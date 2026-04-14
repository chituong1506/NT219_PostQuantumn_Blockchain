FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app

# Copy pom.xml and download dependencies
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy source code and build
COPY src ./src
RUN mvn clean package -DskipTests

# Runtime stage
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

# Create user for security
RUN addgroup -S ksm && adduser -S ksm -G ksm

# Copy jar from build stage
COPY --from=build /app/target/ksm-*.jar app.jar

# Change ownership
RUN chown -R ksm:ksm /app

# Switch to non-root user
USER ksm

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s \  
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/ksm/health || exit 1

# Run application
ENTRYPOINT ["java", "-jar", "app.jar"]

