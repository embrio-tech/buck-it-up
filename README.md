# Buck It Up – Simple Docker Volume Backups to Object Storage

[![Publish Docker image](https://github.com/embrio-tech/buck-it-up/actions/workflows/docker-image.yml/badge.svg)](https://github.com/embrio-tech/buck-it-up/actions/workflows/docker-image.yml)
[![embrio.tech](https://img.shields.io/static/v1?label=by&message=EMBRIO.tech&color=24ae5f)](https://embrio.tech)

> Inspired by https://github.com/jareware/docker-volume-backup

Docker image for performing simple backups of Docker volumes to cloud object storage. Main features:

- Basic backup and restore controlled through labels (integrated with docker compose projects)
- Use `cron` expressions for backup scheduling
- Back-up to a Google Cloud Storage bucket
- Manual backups
- Stop containers while backing-up
- Execution of custom pre/post-backup commands
- Restore of single, multiple or ALL `docker compose` projects
- Custom restore commands per service
- Monitoring of backups with [healthchecks.io](https://healthchecks.io)

## Recommended compose project/folder structure
To achieve the best user experience with buck-it-up, we recommend to split your docker services related to a given project in different folders. An hypotetical example with 3 services is given below. There the `back-it-up` service is added in a dedicated project named `backup` to provide backup and restore services to all other workloads on the host.

```bash
.
├── backup
│   └── docker-compose.yml
├── invoiceninja
│   └── docker-compose.yml
├── gitlab 
│   └── docker-compose.yml
└── bitwarden
    └── docker-compose.yml
```

## Backing up to GCS

Set up the backup project with docker compose:
```yml
version: "3"

volumes:
  volumes:

services:
  backup:
    image: embriotech/buck-it-up
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - volumes:/backup/volumes

    environment:
      CRON_SCHEDULE: "18 4 * * *"
      BACKUP_LABEL: "buck.it.up"
      GS_BUCKET_NAME: "eio-services-csb-dockerhost-backup"
      #HEALTHCHECK_UUID: "healthchecks.io UUID"
      #GS_SA_KEY: "Base64 encoded credentials.json" unnecessary if a workload identity is available
```

Now you can perform backups of your `docker compose` projects on the same host by adding special labels to your services. In this example we demonstrate how to set-up backup for an invoiceninja installation:

```yml
version: "3"
services:
  webserver:
    image: nginx
    labels:
      - "buck.it.up.volumes=invoiceninjaNginx"
    env_file: .env
    volumes:
      - invoiceninjaNginx:/etc/nginx/conf.d
      - invoiceninjaPublic:/var/www/app/public:ro
      - invoiceninjaStorage:/var/www/app/storage:ro
    depends_on:
      - app

  app:
    image: invoiceninja/invoiceninja:latest
    labels:
      - "buck.it.up.volumes=invoiceninjaPublic invoiceninjaStorage"
    volumes:
      - invoiceninjaPublic:/var/www/app/public:rw,delegated
      - invoiceninjaStorage:/var/www/app/storage:rw,delegated

  db:
    image: mysql:5
    labels:
      - buck.it.up.volumes=invoiceninjaSqlBackup
      - buck.it.up.pre=bash -c 'mysqldump --no-tablespaces -u $$MYSQL_USER -p$$MYSQL_PASSWORD $$MYSQL_DATABASE | gzip > /backup/latest.sql.gz'
      - buck.it.up.restore=bash -c 'gunzip < /backup/latest.sql.gz | mysql -u $$MYSQL_USER -p$$MYSQL_PASSWORD $$MYSQL_DATABASE'
    env_file: .env
    volumes:
      - invoiceninjaSqldata:/var/lib/mysql:rw,delegated
      - invoiceninjaSqlBackup:/backup

volumes:
  invoiceninjaPublic:
  invoiceninjaStorage:
  invoiceninjaSqldata:
  invoiceninjaSqlBackup:
  invoiceninjaNginx:
```

This will back up the invoiceninja data volumes defined in the label `buck.it.up.volumes` for each service, once per day at 04:18AM, and upload backups to google cloud. For the db service, a pre command is used to save a db dump to a dedicated volume. The dump can be used with restore commands, to automatically re-seed the database.

The following special labels can be used on individual containers (compose services) such as:

`buck.it.up.stop`
: Stop container before performing the backup

`buck.it.up.pre`
: Run a custom command in the container prior to backup

`buck.it.up.post`
: Run a custom command in the container after the backup

`buck.it.up.restore`
: Run a custom command in the container after restoring its volumes from object storage

## Configuring buckets

GCP Buckets have Versioning and Object Lifecycle Management features that can be useful for backups.

This allows you to retain previous versions of the backup file, but the _most recent_ version is always available with the same filename.

To make sure your bucket doesn't continue to grow indefinitely, you can enable some lifecycle rules

These rules will:

- Move non-latest backups to a cheaper, long-term storage class
- Permanently remove backups after a year
- Still always keep the latest backup available (even after a year has passed)

## Manual Backups

To perform a manual backup, `cd` in the directory where the backup compose project is defined and execute:

```bash
docker compose exec backup backup.sh
```

## Restoring

To restore a workload (such as invoiceninja above), `cd` in the directory where the backup compose project is defined and execute:

```bash
docker compose exec backup restore.sh invoiceninja
```

to restore multiple projects execute:

```bash
docker compose exec backup restore.sh invoiceninja project2 project3
```

to restore ALL defined projects on the host execute:

```bash
docker compose exec backup restore.sh ALL
```

## :speech_balloon: Contact

[EMBRIO.tech](https://embrio.tech)  
[hello@embrio.tech](mailto:hello@embrio.tech)  
+41 44 552 00 75
