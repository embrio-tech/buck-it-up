# Buck It Up – Simple Docker Volume Backups to Object Storage

> Inspired from https://github.com/jareware/docker-volume-backup

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
      BACKUP_LABEL: "tech.embrio.backup"
      GS_BUCKET_NAME: "eio-services-csb-dockerhost-backup"
      #HEALTHCHECK_UUID: "healthchecks.io UUID"
      #GS_SA_KEY: "Base64 encoded credentials.json" unnecessary if a workload identity is available
```

After that you can perform backup of your `docker compose` by adding special labels. In this example we perform a backup of an invoiceninja instance:

```yml
version: "3"

services:
  webserver:
    image: nginx
    restart: always
    labels:
      - "tech.embrio.backup.volumes=invoiceninjaNginx"
      - "traefik.enable=true"
      - "traefik.http.routers.invoiceninja.rule=Host(`invoiceninja.magneto.embrio.tech`)"
      - "traefik.http.routers.invoiceninja.entrypoints=websecure"
      - "traefik.http.routers.invoiceninja.tls.certresolver=myresolver"
      - "traefik.http.services.invoiceninja.loadbalancer.server.port=80"
      - "traefik.docker.network=web"
    env_file: .env
    volumes:
      - invoiceninjaNginx:/etc/nginx/conf.d
      - invoiceninjaPublic:/var/www/app/public:ro
      - invoiceninjaStorage:/var/www/app/storage:ro
    depends_on:
      - app
    expose:
      - 80
    networks:
      - web
      - default

  app:
    image: invoiceninja/invoiceninja:latest
    env_file: .env
    restart: always
    labels:
      - "tech.embrio.backup.volumes=invoiceninjaPublic invoiceninjaStorage"
    volumes:
      - invoiceninjaPublic:/var/www/app/public:rw,delegated
      - invoiceninjaStorage:/var/www/app/storage:rw,delegated
    depends_on:
      - db
    networks:
      - default

  db:
    image: mysql:5
    restart: always
    labels:
      - tech.embrio.backup.volumes=invoiceninjaSqlBackup
      - tech.embrio.backup.pre=bash -c 'mysqldump --no-tablespaces -u $$MYSQL_USER -p$$MYSQL_PASSWORD $$MYSQL_DATABASE | gzip > /backup/latest.sql.gz'
      - tech.embrio.backup.restore=bash -c 'gunzip < /backup/latest.sql.gz | mysql -u $$MYSQL_USER -p$$MYSQL_PASSWORD $$MYSQL_DATABASE'
    env_file: .env
    volumes:
      - invoiceninjaSqldata:/var/lib/mysql:rw,delegated
      - invoiceninjaSqlBackup:/backup
    networks:
      - default

networks:
  default:
  web:
    external: true
    name: web

volumes:
  invoiceninjaPublic:
  invoiceninjaStorage:
  invoiceninjaSqldata:
  invoiceninjaSqlBackup:
  invoiceninjaNginx:
```

This will back up the Grafana data volume, once per day, and write it to `./backups` with a filename like `backup-2018-11-27T16-51-56.tar.gz`.

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
