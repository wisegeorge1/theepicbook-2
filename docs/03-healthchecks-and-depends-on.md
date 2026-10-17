# Epicbook : Health Checks and Startup Order
**Prepared by George Adimowei Epebifie**



# 1. Health Checks
Docker Compose uses health checks to determine whether a service is ready to operate, rather than simply checking whether its container is running.

**Database Service**\
**Health-check method:** Uses mysqladmin ping to check whether the MySQL server is responding.

healthcheck:\
  test:\
    - CMD-SHELL\
    - 'mysqladmin ping -h 127.0.0.1 -uroot -p"$$MYSQL_ROOT_PASSWORD" --silent'\
  interval: 10s\
  timeout: 5s\
  retries: 10\
  start_period: 30s
  
  - Interval: Every 10 seconds.
  - Timeout: 5 seconds.
  - Retries: 10 consecutive failures before being marked unhealthy.
  - Start period: 30 seconds to allow MySQL to initialize.
  - Purpose: Confirms that the database server is responding to health checks.

**Backend Service**\
**Health-check method:** Uses Node.js's built-in fetch() to send an HTTP request to the backend's health endpoint.

healthcheck:\
  test:\
    - CMD\
    - node\
    - -e \
    - "fetch('http://127.0.0.1:8080/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"\
  interval: 10s\
  timeout: 5s\
  retries: 5\
  start_period: 10s

  - Interval: Every 10 seconds.
  - Timeout: 5 seconds.
  - Retries: 5 consecutive failures before being marked unhealthy.
  - Start period: 10 seconds.
  - Purpose: Checks whether the backend responds successfully to an HTTP request on port 8080. A successful HTTP status produces exit code 0; a failed response or 
    connection error produces exit code 1.

**Important:** The backend application must implement the /health endpoint and return a successful HTTP status, such as 200 OK, for this check to pass.

**Frontend Service**\
**Health-check method:** Uses wget to check whether the frontend responds over HTTP on port 80.

healthcheck:\
  test: ["CMD", "wget", "-q", "--spider", "http://localhost:80"]\
  interval: 10s\
  timeout: 5s\
  retries: 5\
  start_period: 5s

  - Interval: Every 10 seconds.
  - Timeout: 5 seconds.
  - Retries: 5 consecutive failures before being marked unhealthy.
  - Start period: 5 seconds.
  - Purpose: Verifies that the frontend web server responds to an HTTP request. The check requires wget to be installed in the frontend image.

**Reverse Proxy Service**\
The reverse proxy does not have an explicit health check in the current Compose configuration.

Its startup depends on the frontend and backend health states. However, without its own health check, Docker Compose does not independently verify that Nginx is serving requests successfully.

# 2. Startup Dependencies (depends_on)

The depends_on configuration controls service startup order and, when using condition: service_healthy, waits for dependencies to become healthy before starting dependent services.

**Reverse Proxy**
\
depends_on: \
  frontend: \
    condition: service_healthy \
  backend: \
    condition: service_healthy \
The reverse proxy waits for both the frontend and backend health checks to pass before starting.

**Backend** \
depends_on: \
  database: \
      condition: service_healthy

The backend waits until the database is reported healthy before starting. This helps prevent database connection attempts before MySQL is ready.

**Frontend**\
The frontend has no depends_on entry and can start independently of the other services.

**Database**\
The database has no startup dependencies and can start first.


# 3. Startup Dependency Order
The expected startup sequence is:

   1. Database: Starts first and initializes MySQL.
   2. Backend: Starts after the database becomes healthy.
   3. Frontend: Starts independently; it may start before or after the backend.
   4. Reverse proxy: Starts only after both the frontend and backend are healthy.

The frontend and backend can start in parallel, subject to their individual dependencies. The reverse proxy waits for both health checks to succeed.

# 4. Important Notes
 - depends_on with condition: service_healthy waits for a dependency to become healthy during startup; it does not automatically restart dependent services whenever a 
   dependency later becomes unhealthy.
 - Health checks report service health but do not guarantee that every application feature is functioning correctly.
 - The MySQL health check confirms that MySQL is responding; it does not verify that all schema and seed-data operations completed successfully.
 - The backend health check assumes Node.js supports the built-in fetch() API and that the /health endpoint exists.
 - The frontend health check assumes wget is available in the frontend container.
 - Health checks and dependency conditions improve startup reliability, but applications should still handle temporary database or network failures gracefully.

# 5. Summary
The Compose configuration uses health checks to verify database availability, backend HTTP responsiveness, and frontend web-server responsiveness. Startup dependencies ensure that the backend waits for a healthy database and that the reverse proxy waits for both the frontend and backend to become healthy. These checks improve startup reliability and help prevent services from being exposed before their dependencies are ready.
