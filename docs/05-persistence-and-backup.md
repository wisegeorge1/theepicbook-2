# Epicbook :  Persistence, Backup and Restore
** Written by : George Adimowei Epebifie **

## 1. Overview

EpicBook uses Docker Compose to run its application services, including the frontend, backend API, Nginx reverse proxy, and MySQL database. 
Database persistence, regular backups, and a tested restoration procedure are essential to protect application data against container failures, accidental deletion, 
database corruption, and infrastructure outages.

The database uses a named Docker volume, `epicbook_db_data`, to retain its data independently of the lifecycle of the MySQL container. 
Database backups are stored separately on the Azure VM host under `./backups/`, allowing recovery from failures that affect the running database container.

The backup strategy combines persistent storage, compressed logical database backups, scheduled retention, and external backup storage for stronger disaster recovery.

## 2. Persistent Volume

### Volume configuration

- Volume name: `epicbook_db_data`
- Container mount path: `/var/lib/mysql`
- Database engine: MySQL
- Storage mechanism: Named Docker volume

The MySQL container writes its database files to `/var/lib/mysql`. Docker mounts the named volume at this location so that the database files remain available 
when the container is stopped, restarted, or recreated.

Example Docker Compose configuration:

yaml
```
services:
  database:
    image: mysql:8.0
    volumes:
      - epicbook_db_data:/var/lib/mysql

volumes:
  epicbook_db_data:
```

This is an illustrative configuration; the MySQL image version and service configuration should match the actual deployment.

### Why persistent storage is important

Containers are replaceable execution environments. If the MySQL container is removed and recreated, data stored only in the container's writable layer may be lost. 
A named volume separates the database's persistent files from the container itself.

The volume supports:

- Database continuity after routine container restarts.
- Container recreation without intentionally deleting database files.
- Separation of database storage from application image updates.
- Recovery after certain container-level failures.

However, a named volume alone is not a complete backup strategy. Disk failure, accidental volume deletion, filesystem corruption, or loss of the VM can still result in data loss. 
Independent backups are therefore necessary.

### Verify the volume

Run the following commands from the project directory:

```
docker volume inspect epicbook_db_data

docker compose ps

docker compose exec database \
  mysqladmin ping -u root -p
```

The last command prompts for the MySQL root password. Enter it securely when prompted.

Confirm that the volume is mounted at `/var/lib/mysql` and that the database responds successfully.

## 3. Backup Location

### Host backup directory

Backups are stored on the Azure VM host in:

```
/home/azureuser/theepicbook-2/backups/
```

This is the absolute path corresponding to `./backups/` when the commands are run from the project directory.

The backup directory is separate from the MySQL container's filesystem. This separation means that removing or recreating the database container does not automatically 
remove the backup files.

Create the directory and restrict access:

bash
```
cd /home/azureuser/theepicbook-2

mkdir -p backups
chmod 700 backups
```

Confirm that the directory exists:

```
ls -ld backups
```

Important: Host-based backups protect against some database and container failures, but not against every VM-level disaster. If the Azure VM or its disk is lost, backups stored only on that VM may also be lost. Copy backups to external durable storage, such as a private Azure Storage account, for stronger disaster recovery.

## 4. Backup Method

### Logical database backup with `mysqldump`

EpicBook uses MySQL logical backups created with `mysqldump`. The utility exports database objects and data into an SQL file that can be restored into a compatible MySQL database.

The backup uses these options:

- `--single-transaction` — creates a consistent snapshot for transactional tables such as InnoDB, without locking those tables for the entire dump.
- `--routines` — includes stored procedures and functions.
- `--triggers` — includes database triggers.
- `gzip` — compresses the SQL output to reduce storage requirements.

`--single-transaction` does not guarantee a consistent backup of nontransactional tables such as MyISAM. Schema-changing operations should also be avoided while the dump is running.

### Manual backup procedure

Run the following from the EpicBook project directory on the VM:

```
cd /home/azureuser/theepicbook-2

mkdir -p backups
chmod 700 backups

read -rp "MySQL database name: " DB_NAME
read -rp "MySQL username: " DB_USER
read -rsp "MySQL password: " DB_PASSWORD
echo

BACKUP_FILE="backups/${DB_NAME}_$(date +%F_%H%M%S).sql.gz"
TEMP_FILE="${BACKUP_FILE}.tmp"

if docker compose exec -T \
    -e MYSQL_PWD="$DB_PASSWORD" \
    database \
    mysqldump \
      -u "$DB_USER" \
      --single-transaction \
      --routines \
      --triggers \
      --no-tablespaces \
      "$DB_NAME" |
    gzip -c > "$TEMP_FILE"; then

    if gzip -t "$TEMP_FILE"; then
        mv "$TEMP_FILE" "$BACKUP_FILE"
        chmod 600 "$BACKUP_FILE"
        echo "Backup created: $BACKUP_FILE"
    else
        echo "ERROR: Backup archive validation failed."
        rm -f "$TEMP_FILE"
        unset DB_PASSWORD
        exit 1
    fi
else
    echo "ERROR: Database backup failed."
    rm -f "$TEMP_FILE"
    unset DB_PASSWORD
    exit 1
fi

unset DB_PASSWORD
```

This example assumes the Compose service is named `database`, and that `mysqldump` is installed in its container. 
The account must have sufficient privileges to dump the required database objects. 
If the database name or account differs from the deployment configuration, enter the correct values when prompted.

The password is requested interactively rather than written into the script or placed in the backup filename. 
`MYSQL_PWD` is used to pass the password to the container process; it is preferable to hardcoding the password,
 but environment-based credentials can still be exposed to sufficiently privileged processes. 
For higher-security deployments, use an appropriately protected MySQL client option file or another supported secret mechanism.

### Verify the backup

List the available archives:

bash
```
ls -lh backups/
```

Validate the gzip archive:

```
gzip -t backups/epicbook_database_YYYY-MM-DD_HHMMSS.sql.gz
```

Replace the example filename with the actual backup filename. A successful `gzip -t` verifies the compressed archive's integrity,
but does not prove that the SQL can be fully restored. Periodic restoration tests are required.

## 5. Backup Plan and Schedule

Daily backups are recommended to reduce potential data loss following a database failure or accidental data modification.

| Backup type | Recommended frequency | Retention         |
| ----------- | --------------------- | ----------------- |
| Daily       | Every day             | 7 daily backups   |
| Weekly      | Once per week         | 4 weekly backups  |
| Monthly     | Once per month        | 3 monthly backups |

### Scheduling

The backup script should run automatically through a scheduled task, such as `cron` on the Azure VM. A production implementation should:

1. Run the backup during a period of relatively low database activity.
2. Check that `mysqldump` completed successfully.
3. Validate the gzip archive.
4. Record the backup date, filename, and result in an operations log.
5. Alert an administrator if a backup fails.
6. Copy verified backups to external storage.
7. Apply the retention policy without deleting the only known-good recovery copy.

A daily backup at 02:00 can be configured with a cron entry, provided the server's local timezone and the execution environment are confirmed.

Example:
cron
```
0 2 * * * /home/azureuser/theepicbook-2/scripts/backup-mysql.sh >> /home/azureuser/theepicbook-2/backups/backup.log 2>&1
```

This entry assumes the backup script has been saved at that location, made executable, and tested. Ensure its credentials are obtained securely when running unattended; a script that prompts for a password will not work unattended without an appropriate noninteractive credential mechanism.

### Retention policy

The retention process should preserve:

- The most recent seven daily backups.
- Four weekly recovery points.
- Three monthly recovery points.

Weekly and monthly backups should be retained independently of the daily rotation. Otherwise, a simple seven-file cleanup could accidentally delete the longer-term recovery points.

Backups should be periodically checked for integrity, copied to a separate storage location, and protected with appropriate access controls and encryption.

## 6. Restore Procedure

Restoration should be controlled and verified. A backup is useful only if it can be restored successfully and the resulting data is correct.

### Step 1: Identify the backup

List the backup files:

```
cd /home/azureuser/theepicbook-2

ls -lht backups/*.sql.gz
```

Select a backup from the required recovery date. Prefer a recent verified backup that predates the incident.
Before restoring, determine whether the operation should recover a separate test database or replace the production database.

### Step 2: Validate the gzip archive

Run:

```
gzip -t backups/epicbook_database_YYYY-MM-DD_HHMMSS.sql.gz
```

If validation fails, do not use that archive for recovery. Locate another verified backup.
For additional inspection, display the first few lines of the decompressed SQL without extracting the entire file:
```
gzip -dc backups/epicbook_database_YYYY-MM-DD_HHMMSS.sql.gz \
  | head -n 20
```

The archive should contain the expected SQL dump. Note that inspecting the beginning of a file does not establish that the complete dump is valid.

### Step 3: Restore into a temporary database where possible

Restoring into a separate test database helps verify the backup without immediately overwriting production data.
For example, create a temporary database using an appropriately privileged MySQL account:

```
docker compose exec database mysql -u root -p
```

At the MySQL prompt:

sql
```
CREATE DATABASE epicbook_restore_test;
EXIT;
```

Then restore the SQL archive:

```
gzip -dc backups/epicbook_database_YYYY-MM-DD_HHMMSS.sql.gz |
  docker compose exec -T database mysql -u root -p epicbook_restore_test
```

The interactive `-p` option is unsuitable for some noninteractive pipeline contexts. 
For unattended restoration, use a secure supported credential mechanism rather than embedding the password in the command.

Important: The example backup command dumps a specific database without explicitly creating that database in the dump. 
The temporary database must therefore be created before restoring. 
Database level routines and triggers should also be reviewed during validation.

### Step 4: Verify the restored data

Check that the restored database contains the expected tables:
```
docker compose exec database \
  mysql -u root -p epicbook_restore_test \
  -e "SHOW TABLES;"
```

Verify important record counts and application-specific data, for example, the expected number of users, books, and orders. The actual table names must match the EpicBook schema.

Check for missing tables, failed imports, unexpected empty datasets, and errors in the restore output. 
A successful command exit alone is not sufficient to prove that the restored application data is correct.

### Step 5: Perform a controlled production restoration if required

Production restoration should be performed only after confirming the target database, obtaining appropriate authorization, and assessing the risk of overwriting newer data.

A controlled procedure should include:

1. Notify affected users or place the application into maintenance mode.
2. Stop or restrict application writes to prevent changes during restoration.
3. Take a fresh backup of the current database, if it remains accessible.
4. Confirm the selected recovery archive and target database.
5. Restore the verified backup.
6. Apply any required schema migrations or supported point-in-time recovery steps.
7. Re-enable application writes after validation.

Do not drop the production database or delete its Docker volume as a routine restore step.

### Step 6: Verify application health

After restoration:
```
docker compose ps

docker compose logs --tail=100 backend

curl -i http://localhost/health
```

Also verify application operations that depend on the database, such as retrieving records, authenticating a test user, or loading a representative page.

Confirm that the restored data is correct, database connectivity works, and the reverse proxy can route requests to the backend. Record the restoration time, 
backup filename, validation results, and any data loss identified.

## 7. Persistence Test

The persistence test verifies that database data remains intact when the Compose stack is stopped and subsequently started again.

The stack was stopped using:
```
docker compose down
```

It was not stopped using:
```
docker compose down -v
```

The distinction is important:

- `docker compose down` removes the containers and Compose-managed networks but normally preserves named volumes.
- `docker compose down -v` also removes the named volumes declared in the Compose configuration and attached anonymous volumes, subject to Docker Compose's volume-removal rules.

The named database volume, `epicbook_db_data`, should remain intact after a normal `docker compose down`, assuming it is correctly declared and no separate cleanup operation removes it.

### Persistence verification

Before stopping the stack, record representative database records or counts. Then execute:

```
docker compose down
docker volume inspect epicbook_db_data
docker compose up -d
docker compose ps
```

After the database has initialized, query the same records or counts and compare them with the baseline.

Expected result: The database container starts successfully, the named volume remains available, and the previously stored records are still present.

The volume's existence alone is not proof of data integrity. Successful database startup and record-level verification are necessary to demonstrate persistence.

## 8. Security

Database backups can contain sensitive application data and must be protected accordingly.

The following practices apply:

- Database passwords must not appear in backup filenames, screenshots, Git repositories, or documentation.
- Backup files and directories must have restricted filesystem permissions.
- Database credentials should be supplied through a secure credential mechanism.
- Backups transferred off the VM should use encrypted transport and encrypted storage.
- Access to backup files and restoration privileges should be restricted to authorized administrators.
- Backup logs should record success or failure without recording passwords or tokens.
- External backup storage should use appropriate access controls, retention protection, and encryption.
- Restore procedures should be tested periodically without unnecessarily disrupting production.

If credentials are exposed, rotate them and review access logs as appropriate.

## 9. Recovery Objectives and Testing

The backup policy should define two operational targets:
- Recovery Point Objective (RPO): The maximum acceptable amount of data loss, measured in time. With daily backups alone, the potential data loss can approach 24 hours,
  or more if backups fail.
- Recovery Time Objective (RTO): The target time to restore database service and application functionality after an incident. This must be established through actual recovery tests.

Recommended operational checks include:

| Test                                         | Expected result                                                         |
| -------------------------------------------- | ----------------------------------------------------------------------- |
| Container restart                            | Database starts and retains data                                        |
| `docker compose down` and `up -d`            | Named volume persists and records remain                                |
| Backup creation                              | SQL dump completes and gzip validation succeeds                         |
| Restore to temporary database                | Tables and expected records are recovered                               |
| Backend database connectivity                | Backend can query the restored database                                 |
| Public health check                          | Application health endpoint returns the expected response               |
| External backup recovery                     | Backup can be retrieved and restored without relying on the original VM |

Test outcomes should be documented with timestamps, command outputs, and PASS/FAIL results. Do not mark a recovery test successful until its expected conditions 
have actually been verified.

## 10. Summary

EpicBook's persistence and backup strategy separates live MySQL storage from compressed logical backups. The named volume `epicbook_db_data` preserves database files through 
ordinary container lifecycle operations, while daily `mysqldump` archives provide an independent recovery mechanism.

A reliable operational plan requires more than creating backup files: it also requires retention management, external storage, secret protection, tested restoration, 
and application level verification. Regular recovery exercises help ensure that the database and application can be returned to service within the organization's recovery objectives.
