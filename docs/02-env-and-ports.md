# Epicbook : Environment Variables, Ports, Persistence and Health Checks
**Prepared by : George Adimowei Epebifie**


## 1. Environment Variables
The application uses environment variables to configure the backend and database. Sensitive values must be supplied through a local .env file or another secure environment-variable management mechanism.

**Required variables**


| **Variable**	       |    **Used by**	         |    **Purpose**                                                                             |
|--------------------- | ------------------------|--------------------------------------------------------------------------------------------|
| DB_ROOT_PASSWORD	   |    Database	           |   Sets the MySQL root password.                                                            |
| DB_NAME	             |    Backend, Database	   |   Specifies the application database name.                                                 |
| DB_USER	             |    Backend, Database	   |   Specifies the application database username.                                             |
| DB_PASSWORD	         |    Backend, Database	   |   Sets the application database user's password.                                           |
| NODE_ENV	           |    Backend	             |   Sets the Node.js environment to production.                                              |
| PORT	               |    Backend	             |   Configures the backend application to listen on port 8080.                               |
| JAWSDB_URL	         |    Backend	             |   Provides the MySQL connection URL, constructed from the database environment variables.  | 
|                      |                         |                                                                                            |


**Security Requirements**
 - Never commit real credentials, passwords, or populated .env files to version control.
 - Provide a .env.example containing variable names and clearly marked placeholder values only.
 - Add .env to .gitignore.
 - Do not include secrets in documentation, screenshots, logs, or deployment examples.
 - Use a secrets manager or platform-managed secrets for production deployments where appropriate.

## 2. Network Ports
The application uses separate Docker networks to control communication between services.

| **Service**	            | **Internal Port**  |  **Host Port**     | **Purpose**                                                                        |
| ----------------------- | ------------------ | ------------------ | ---------------------------------------------------------------------------------- |
| Reverse proxy (Nginx)	  |   80	             |   80       	      | Receives external HTTP traffic and forwards requests to the application services.  |
| Frontend	              |   80	             |   Not published	  | Serves the frontend application to the reverse proxy.                              |
| Backend	                |   8080     	       |   Not published	  | Handles application logic and API requests.                                        |
| Database (MySQL)	      |   3306	           |   Not published	  | Provides database access to the backend.                                           |
| MySQL X Protocol	      |   33060	           |   Not published	  | MySQL X Protocol listener; not required for the standard application connection.   |
|                         |                                         |                                                                                    |

Only port 80 is published to the host in the current Compose configuration. The frontend, backend, and database communicate over their assigned Docker networks using service names.

**Docker Networks**\
 -*front-tier:* Connects the reverse proxy, frontend, and backend.\
 -*back-tier:* Connects the backend and database. This network is marked internal: true to restrict external connectivity through that network.

The backend connects to MySQL using the hostname database and internal port 3306. The database port does not need to be published to the host.

## 3. Persistent Data

**Database Storage**
The MySQL service uses a named Docker volume:

| **Volume or Mount**	                        |   **Purpose**
| ------------------------------------------- | --------------------------------------------------------------------------------------- |
| db_data:/var/lib/mysql	                    |   Stores MySQL database files persistently across container recreation.                 |
| ./db/BuyTheBook_Schema.sql	                |   Initializes the database schema on first-time database initialization.                |
| ./db/author_seed.sql	                      |   Supplies initial author records.                                                      |
| ./db/books_seed.sql	                        |   Supplies initial book records.                                                        |
|                                             |                                                                                         |

The SQL files are mounted read-only into /docker-entrypoint-initdb.d/ in the database container.

MySQL initialization scripts are normally executed when the data directory is first initialized. Changing these scripts does not automatically reapply them to an existing database volume.

**Data Retention and Backup**
 - Recreating containers does not normally remove data stored in db_data.
 - Removing containers is different from removing their named volumes.
 - Avoid docker compose down -v unless intentionally deleting persistent database data.
 - Back up the database regularly using an appropriate MySQL dump or backup procedure.
 - Store backups securely and periodically test restoration.

## 4. Health Checks
Docker Compose uses health checks to determine whether services are ready to accept requests.

**Database Health Check**

**Method:** mysqladmin ping

 - Connects to the local MySQL server using 127.0.0.1.
 - Uses the configured root password without embedding the actual password in the Compose file.
 - Checks every 10 seconds.
 - Uses a 5-second timeout.
 - Allows 10 retries.
 - Uses a 30-second startup grace period.

The database is considered healthy when the health-check command succeeds.

**Backend Health Check**
**Method:** Node.js built-in fetch()

The health check sends an HTTP request to:

http://127.0.0.1:8080/health

It exits successfully when the endpoint returns an HTTP success status. Connection failures and unsuccessful HTTP responses cause the check to fail.

 - Interval: 10 seconds.
 - Timeout: 5 seconds.
 - Retries: 5.
 - Startup grace period: 10 seconds.

**Requirement:** The backend application must implement a /health endpoint that returns a successful status when the application is ready. If the endpoint does not exist, the container can be marked unhealthy even when the server is running.

**Frontend Health Check**
**Method:** wget

The health check requests:

http://localhost:80

using wget -q --spider.

 - Interval: 10 seconds.
 - Timeout: 5 seconds.
 - Retries: 5.
 - Startup grace period: 5 seconds.

The check succeeds when the frontend responds successfully to the HTTP request.

**Service Dependencies**
The Compose configuration uses depends_on with condition: service_healthy to establish startup dependencies:

 1. The database must become healthy before the backend starts.
 2. The backend and frontend must become healthy before the reverse proxy starts.

Health checks report service status; they do not automatically guarantee that every application feature or database query is working correctly.

## 5. Operational Verification
Use the following commands to validate the configuration and monitor the application.

Validate the Compose configuration:

docker compose config --quiet
List services and health status:

docker compose ps
Inspect backend health-check results:

docker inspect theepicbook-2-backend-1 \
  --format '{{json .State.Health}}'
View service logs:

docker compose logs --tail=100 backend database frontend reverse-proxy
Check persistent volumes:

docker volume ls

## 6. Configuration Summary
 - External entry point: HTTP port 80.
 - Frontend internal port: 80.
 - Backend internal port: 8080.
 - Database internal port: 3306.
 - Persistent database storage: named volume db_data.
 - Database initialization: SQL scripts mounted read-only.
 - Health checks: mysqladmin ping, Node.js fetch(), and wget.
 - Secrets: supplied externally; real credentials are excluded from this document.
