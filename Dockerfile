FROM gcr.io/google.com/cloudsdktool/google-cloud-cli:alpine
RUN apk --update --no-cache add jq tar bash tzdata
RUN gcloud components install gsutil
COPY --chown=root:root ./docker-entrypoint.sh /
COPY --chown=root:root ./log.sh /
WORKDIR /backup
COPY --chown=root:root ./environment.sh .
COPY --chown=root:root ./backup.sh .
COPY --chown=root:root ./restore.sh .
ENTRYPOINT [ "/docker-entrypoint.sh" ]
