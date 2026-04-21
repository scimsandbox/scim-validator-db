FROM dhi.io/flyway:12-jre23

COPY sql/ /flyway/sql/

ENTRYPOINT ["/bin/sh", "-c", "exec flyway migrate -url=\"$FLYWAY_URL\" -user=\"$FLYWAY_USER\" -password=\"$FLYWAY_PASSWORD\" -locations=filesystem:/flyway/sql -connectRetries=5"]
