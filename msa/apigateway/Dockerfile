# The uploaded base omitted gradle-wrapper.jar; official Gradle builder fixes clean builds.
FROM gradle:8.12.1-jdk17 AS build
WORKDIR /home/gradle/project
COPY --chown=gradle:gradle build.gradle settings.gradle ./
COPY --chown=gradle:gradle src ./src
RUN gradle --no-daemon bootJar -x test
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
RUN addgroup -S app && adduser -S app -G app
COPY --from=build /home/gradle/project/build/libs/*.jar /app/app.jar
USER app
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
