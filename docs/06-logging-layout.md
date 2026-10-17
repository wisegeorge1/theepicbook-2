# Epicbook: Logging and Observability

**Written by:** George Adimowei Epebifie\
**Project:** Epicbook\
**Documentation Area:** Logging, Monitoring, and Operational Troubleshooting\
**Testing Date:** October 15, 2026

## 1\. Introduction

### 1.1 Purpose

This document describes the logging and observability implementation for Epicbook, including the reverse proxy, 
backend application, database logging, log formats, security requirements, and failure testing.

The purpose of the logging infrastructure is to provide visibility into HTTP requests, application behavior, and system errors.
It enables operators to investigate failed requests, identify infrastructure problems, inspect backend activity, 
:and verify that logs remain accessible after container restarts.

Epicbook uses Docker Compose to manage its application services, Nginx as its reverse proxy, Node.js and Express for the backend application, and MySQL as its database.

The logging architecture follows a service-specific approach:

- **Nginx reverse proxy:** Records incoming HTTP requests and proxy-level errors in host-accessible log files.
- **Node.js/Express backend:** Writes application logs to standard output and standard error, which Docker captures.
- **MySQL database:** Writes logs to standard output according to the configured MySQL logging behavior, making them accessible through Docker Compose.

This approach provides visibility into different layers of the application without requiring a separate logging service for the current deployment.

### 1.2 Objectives

The logging and observability implementation has the following objectives:

1. Record incoming HTTP requests and their response status codes.
2. Provide access to Nginx access and error logs directly from the VM host.
3. Allow operators to inspect backend application logs through Docker Compose.
4. Support troubleshooting of successful requests, API requests, static assets, and HTTP errors.
5. Verify that proxy logs remain accessible after a container restart.
6. Prevent sensitive credentials and confidential information from being exposed in logs.
7. Establish a foundation for future centralized logging and automated monitoring.

## 2\. Logging Architecture

Epicbook uses a container based logging architecture in which each service writes logs through an appropriate output mechanism.
The reverse proxy provides visibility into incoming traffic, while the backend logs provide information about application execution. 
Database logs offer additional diagnostic information when investigating database-related issues.

The logging destinations differ by service because Nginx requires host-accessible files for proxy diagnostics, whereas the backend and database use Docker's container logging mechanism.

### 2.2 Logging Components

| Component               | Logging destination                                     | Access method                           |
| ----------------------- |-------------------------------------------------------- | --------------------------------------- |
| Nginx reverse proxy     | Host-mounted access and error log files                 | `cat`, `tail`, and other host utilities |
| Node.js/Express backend | Standard output and standard error                      | `docker compose logs backend`           |
| MySQL database          | Standard output, according to its logging configuration | `docker compose logs database`          |

The implementation is designed for a single-VM deployment. A separate centralized logging platform is not currently required for the documented setup.

## 3\. Reverse Proxy: Nginx

### 3.1 Overview

Nginx serves as the public entry point for Epicbook. It receives incoming HTTP requests and forwards them to the appropriate application service 
or serves configured resources according to its routing rules.

Because Nginx is positioned at the entry point, its logs provide an important record of application traffic. 
They allow operators to determine whether requests reached the proxy, which paths were requested, and which HTTP response codes were returned.

Nginx maintains two primary log files:

- **Access log:** Records HTTP requests and response information.
- **Error log:** Records proxy-related errors and diagnostic messages.

The reverse proxy configuration is maintained in `proxy/nginx.conf`, which defines the logging configuration, including the `json_combined` access log format.

### 3.2 Log File Locations

The Nginx logs are bind-mounted from the host machine.

The documented host-side directory is:

```
./logs/nginx/
├── access.log
└── error.log
```

The corresponding container directory is:

```
/var/log/nginx/
├── access.log
└── error.log
```

The host directory is mounted into `/var/log/nginx` inside the reverse proxy container.

This arrangement allows operators to inspect log files directly from the VM without using `docker exec` to enter the container.

The bind mount also separates log-file storage from the container's writable filesystem. Consequently, 
the log files can remain available across container restarts and rebuilds, provided that the host-side directory and files are retained and the mount configuration remains unchanged.

**Note:** The project overview initially identifies `logs/proxy/access.log` and `logs/proxy/error.log` as log locations. 
The implementation details and test record in this document identify `./logs/nginx/access.log` and `./logs/nginx/error.log`. 
The deployed Docker Compose configuration should be treated as the authoritative source for resolving this path discrepancy.

### 3.3 Access Log

The access log records HTTP requests processed by Nginx. Epicbook uses a JSON-formatted access log in which each request is represented by a separate JSON object on a single line.

Depending on the active configuration, each entry records fields such as:

- Request timestamp.
- Client IP address.
- HTTP request method, URI, and protocol.
- HTTP response status code.
- Response body size.
- Request processing time.
- HTTP referrer.
- User-Agent.

This information supports the investigation of request failures, response behavior, application traffic, and performance issues.

#### Viewing the access log

Run the following commands from the project directory on the VM host:

```
# Display the most recent 50 requests
tail -n 50 ./logs/nginx/access.log

# Follow incoming requests in real time
tail -f ./logs/nginx/access.log

# Display the entire access log
cat ./logs/nginx/access.log
```

Because the file is bind-mounted, these commands read the host-side file directly.

#### Identifying HTTP errors

The JSON access log can be searched for specific response codes. For example, the following command uses `jq` to identify requests that returned HTTP 404:

```
jq 'select(.status == 404)' ./logs/nginx/access.log
```

To identify server-side errors with status codes from 500 through 599:

```
jq 'select(.status >= 500 and .status < 600)' \
  ./logs/nginx/access.log
```

These examples assume that `jq` is installed on the host and that each access log line contains valid JSON with a numeric `status` field.

### 3.4 Error Log

The Nginx error log records diagnostic information generated by the reverse proxy.

It is useful when investigating:

- Upstream connection failures.
- Backend service unavailability.
- Request-processing errors.
- Connection timeouts.
- Invalid Nginx configuration.
- Permission problems.
- Other proxy-level operational failures.

To inspect recent errors:

```
tail -n 50 ./logs/nginx/error.log
```

To monitor new errors as they occur:

```
tail -f ./logs/nginx/error.log
```

Access and error logs should be examined together during troubleshooting. An access log entry shows the request and its response status, 
while the error log may explain why the request failed.

A 404 response does not necessarily indicate a proxy failure. If Nginx or the backend intentionally returns 404 for a nonexistent resource, 
the request may appear in the access log without producing an error log entry.

### 3.5 Bind-Mount Benefits

The use of host bind mounts provides several operational advantages.

**Direct host access:** Operators can inspect logs using standard Linux commands without entering the container.

**Persistence across container restarts:** Log files remain on the host when the reverse proxy container is restarted, assuming the host files are not deleted or replaced.

**Simplified troubleshooting:** Host-side inspection reduces the number of steps required to diagnose proxy behavior.

**Integration with host utilities:** Log files can be read by authorized monitoring agents, backup processes, and log-management tools.

However, bind mounts do not automatically provide log rotation, retention, backups, or protection against disk exhaustion. These controls must be managed separately.

### 3.6 Nginx Configuration

The logging configuration is defined in `proxy/nginx.conf`. The documented access log format is named `json_combined`.

The configuration ensures that the access log is written to the expected container path and that the error log is enabled at an appropriate diagnostic level.

The configuration behaviour is:

- Write access log entries to `/var/log/nginx/access.log`.
- Write proxy error messages to `/var/log/nginx/error.log`.
- Use the `json_combined` format for access entries.
- Ensure the container's log paths correspond to the host bind mounts.

The deployed configuration should be checked directly before making changes. In particular, the name `json_combined` is a custom format name and must have a corresponding `log_format`
definition in the Nginx configuration.

## 4\. Backend: Node.js and Express

### 4.1 Overview

The Epicbook backend is implemented using Node.js and Express.

Backend application logs are written to standard output (`stdout`) and standard error (`stderr`). Docker captures the container output through its logging driver, 
making application messages available through Docker Compose.

This follows the standard container logging principle: applications write logs to their output streams, and the container platform manages log collection.

The backend already produces application messages, including startup information and Sequelize query output, through standard output. 
Therefore, a separate backend log-file volume is not required for the documented implementation.

### 4.2 Accessing Backend Logs

The primary command for inspecting backend logs is:

```
docker compose logs backend
```

Run this command from the directory containing the Docker Compose configuration.

The command displays the log output associated with the Compose service named `backend`.

Additional useful commands include:

```
# Show the most recent 100 lines
docker compose logs --tail=100 backend

# Follow backend output in real time
docker compose logs -f backend

# Include timestamps
docker compose logs -t backend

# Follow logs with timestamps
docker compose logs -f -t backend
```

These commands are useful when investigating startup failures, application exceptions, database connectivity issues, or unexpected request behavior.

### 4.3 Types of Backend Events

Backend logs may contain operational events such as:

- Application startup and initialization messages.
- Express application errors.
- Request-processing failures.
- Sequelize database operations and related errors.
- Dependency connection failures.
- Unexpected exceptions.
- Application shutdown or restart messages, when emitted by the application.

The availability of these messages depends on the application's logging statements and the active logging configuration.

### 4.4 Troubleshooting the Backend

When an HTTP request fails, backend logs should be checked alongside the Nginx access and error logs.

For example:

```
# Terminal 1: Observe incoming HTTP traffic
tail -f ./logs/nginx/access.log

# Terminal 2: Observe Nginx errors
tail -f ./logs/nginx/error.log

# Terminal 3: Observe backend application logs
docker compose logs -f -t backend
```

Correlating these outputs can help distinguish between a request rejected at the proxy layer, a request that reaches the backend and fails during processing, a
nd a failure caused by a downstream dependency.

### 4.5 Backend Log Persistence and Retention

Backend logs are accessed through Docker Compose rather than through a dedicated host-mounted application log file.

Their retention depends on the Docker logging driver, its configuration, and the container lifecycle.

The command `docker compose logs backend` retrieves available container logs; it does not by itself guarantee indefinite retention or persistence after container removal.

For production use, the Docker logging driver and its rotation settings should be reviewed to ensure that backend output remains available for an appropriate 
period without consuming excessive disk space.

## 5\. Database: MySQL

### 5.1 Overview

Epicbook uses MySQL as its database service. Database logging is included in this document to provide a complete overview of the application's logging architecture, 
although database logging is not a primary deliverable of this task.

The documented logging destination is standard output, using the configured MySQL container behaviour.

Database logs can be inspected with:

```
docker compose logs database
```

To follow database log output in real time:

```
docker compose logs -f -t database
```

The service name `database` must match the service name defined in the project's Docker Compose configuration.

### 5.2 Operational Use

Database logs can provide useful diagnostic information when investigating database startup issues, connectivity failures, configuration errors, and other database-related events.

The exact messages recorded depend on the MySQL image, startup options, server configuration, and enabled logging facilities.

MySQL query logging should not be assumed to be enabled merely because the container writes logs to standard output. 
Query logs and other database diagnostics should be enabled only when justified and configured with appropriate security safeguards.

### 5.3 Scope

Database logging is documented for completeness. The primary focus of the logging and observability implementation remains the Nginx reverse proxy and backend application.

## 6\. Log Format

### 6.1 JSON Access Logging

Epicbook's documented Nginx access log format is `json_combined`, defined in `proxy/nginx.conf`.

Unlike a traditional space delimited access log, JSON represents each request as a structured object containing named fields.

Each JSON object occupies one line. This is commonly called JSON Lines or newline delimited JSON and allows individual records to be 
inspected with command line tools or processed by compatible log collection systems.

Structured logging improves the ability to search and filter specific fields, such as status codes, timestamps, and request durations.

### 6.2 Nginx Access Log Entry

The following entry illustrates the documented format:

```
{"time":"2026-09-25T12:40:00+00:00","remote_addr":"172.19.0.1","request":"GET / HTTP/1.1","status":200,"body_bytes_sent":24980,"request_time":0.045,"http_referer":"-",
"http_user_agent":"curl/8.5.0"}
```

This example is a representative log entry, not a claim that the exact record was generated during the failure tests.

### 6.3 Field Descriptions

| Field             | Description                                                            |
| ----------------- | ---------------------------------------------------------------------- |
| `time`            | Timestamp associated with the request, including its timezone offset.  |
| `remote_addr`     | Client address as observed by Nginx.                                   |
| `request`         | HTTP request line containing the method, request target, and protocol. |
| `status`          | HTTP response status code.                                             |
| `body_bytes_sent` | Number of response body bytes sent to the client.                      |
| `request_time`    | Total request processing time in seconds, as measured by Nginx.        |
| `http_referer`    | Referrer value supplied with the request, or `-` when unavailable.     |
| `http_user_agent` | User-Agent value supplied with the request.                            |

The fields shown are those present in the representative sample. Additional fields may be included if the actual `json_combined` definition is configured to record them.

### 6.4 Timestamp and Request Correlation

The `time` field supports chronological analysis of incoming requests.

During troubleshooting, timestamps can be compared with backend and database log messages to help determine when a failure occurred and which services were involved.

Operators should account for timezone differences between Nginx, the host, the backend application, and the database. The sample uses a UTC offset of `+00:00`.

Request correlation can be improved by introducing a request ID that is consistently generated or propagated by the reverse proxy and included in backend logs. 
Such an identifier should be treated as operational metadata and must not contain credentials or other sensitive information.

A correlation ID is a potential enhancement unless it has been explicitly implemented and verified.

### 6.5 Log Parsing and Analysis

Because access entries are JSON-formatted, tools such as `jq` can be used to extract fields and filter requests.

For example, to display the timestamp, request, and status code for each entry:

```
jq '{time, request, status}' ./logs/nginx/access.log
```

To count the number of logged requests with HTTP 404 responses:

```
jq -s '[.[] | select(.status == 404)] | length' \
  ./logs/nginx/access.log
```

These commands assume that all processed lines contain valid JSON. If a log file contains malformed entries or non-JSON messages, those entries should be investigated separately.

## 7\. Security and Sensitive Data Protection

### 7.1 Security Requirements

Logs are operational records and may contain information about users, requests, application behavior, and internal infrastructure. 
If logging is not configured carefully, these records can expose credentials or confidential information.

**Epicbook logs must never contain sensitive authentication material, secrets, or private cryptographic information.**

The following categories of information are prohibited:

- **Passwords:** Plain-text passwords and password-equivalent values.
- **Database connection strings:** Connection strings containing credentials, secrets, or other confidential connection information.
- **Authorization headers:** Complete `Authorization` header values, including Basic credentials and Bearer tokens.
- **API tokens:** API keys, access tokens, refresh tokens, and similar authentication secrets.
- **Session identifiers:** Session IDs, session cookies, and other values that could facilitate session impersonation.
- **Private keys:** Private cryptographic keys, signing keys, and confidential key material.

These restrictions apply to Nginx access logs, Nginx error logs, backend application output, database diagnostics, and any future centralized logging destination.

### 7.2 Preventing Sensitive Information in Nginx Logs

Nginx access logs can expose sensitive information if they include complete request targets, query strings, or other confidential request data.

For example, logging a full URI that contains a token as a query parameter may expose that token in the access log even if the `Authorization` header is excluded.

To reduce this risk:

1. Review the `json_combined` format definition in `proxy/nginx.conf`.
2. Avoid logging complete authorization header values.
3. Avoid recording cookies and session identifiers.
4. Ensure query strings do not expose credentials or tokens.
5. Prefer logging the request path without sensitive query parameters when required.
6. Avoid including request bodies in logs unless there is a justified need and sensitive fields are reliably excluded.

The request field in the sample log entry is `GET / HTTP/1.1`. That example does not establish whether sensitive query strings are excluded for all possible requests. 
The active configuration must be reviewed to verify the required behavior.

### 7.3 Protecting Backend Logs

Backend logs may contain application errors, Sequelize diagnostics, and startup information.

Although these messages are useful for troubleshooting, application logging must avoid exposing secrets or confidential request data.

The backend should not write the following to standard output or standard error:

- Passwords or authentication credentials.
- Complete database connection strings containing secrets.
- Authorization header values.
- API keys and access tokens.
- Session identifiers or cookie values.
- Private keys or secret configuration values.

Database errors should be logged in a way that preserves useful diagnostic information without printing credential-bearing connection details.

Where exceptions contain request payloads or confidential configuration, sensitive fields should be removed before the error is logged.

### 7.4 Database Log Security

Database diagnostics must also comply with the same restrictions.

If additional MySQL logging is enabled in the future, the configuration should be reviewed to determine whether query text, connection metadata,
or diagnostic messages could expose credentials or confidential application data.

Sensitive information must not be added to logs merely to make troubleshooting easier.

### 7.5 File Permissions and Access Control

Because the Nginx logs are stored on the VM host, access to the host-side log directory must be restricted.

Recommended controls include:

- Restrict read access to authorized operators and monitoring services.
- Apply appropriate ownership and permissions to the log directory and files.
- Prevent unauthorized modification or deletion of log records.
- Include log storage in relevant host security and disk monitoring.
- Ensure backups and future log forwarding use appropriate access controls.
- Sanitize log excerpts before sharing them in tickets, reports, or external systems.

Bind mounts make logs easier to access, but they do not automatically make them secure.

### 7.6 Retention and Rotation

Log retention should balance operational troubleshooting needs with security and storage requirements.

Unbounded log growth can consume disk space and affect application availability. Retention policies should therefore be established 
for both host-mounted Nginx logs and Docker managed backend logs.

For Nginx, rotation should be configured so that active logging continues correctly after log files are rotated. The procedure should account for how Nginx opens and reopens log files.

For Docker managed services, the selected logging driver and its rotation settings should be reviewed.

Log rotation and retention are operational recommendations; they should not be considered implemented until the relevant configuration has been verified.

## 8\. Failure Testing and Verification

### 8.1 Test Objective

The purpose of failure testing was to verify that Epicbook's reverse proxy recorded representative request types and that the resulting logs could be inspected from the VM host.

The tests covered four scenarios:

1. Successful application request.
2. API request.
3. Static asset request.
4. HTTP 404 request.

The documented test date was **October 15, 2026**.

### 8.2 Test Environment

The verification focused on the Nginx reverse proxy and its host-mounted access log.

The relevant host side file was:

```
./logs/nginx/access.log
```

The test procedure involved generating the four requests and inspecting the resulting access log entries directly from the VM host.

The error log remained available for investigating any Nginx-level failures associated with the requests.

### 8.3 Test Cases and Expected Results

| Test                           | Action                               | Expected log evidence                                                                                          |
| ------------------------------ | ------------------------------------ | -------------------------------------------------------------------------------------------------------------- |
| Successful application request | Request the application's main page. | A JSON access log entry with the requested path and successful response status, such as `200` when applicable. |
| API request                    | Request an application API endpoint. | A JSON access log entry showing the API request and its response status.                                       |
| Static asset request           | Request an available static file.    | A JSON access log entry showing the asset request and its response status,
                                                                          commonly `200` or `304` depending on caching. |
| 404 request                    | Request a nonexistent resource.      | A JSON access log entry with status `404` when the request returns that status.                                |

The expected status codes are illustrative. The exact response depends on the application's routing configuration and the requested resource.

### 8.4 Test Execution

The following commands provide an example of how the tests can be repeated.

Replace the example API and static asset paths with valid paths from the Epicbook deployment.

```
# Set the base URL for the deployed application
BASE_URL="http://localhost"

# Test 1: Main application page
curl -sS -o /dev/null \
  -w 'Application request: %{http_code}\n' \
  "$BASE_URL/"

# Test 2: API endpoint
curl -sS -o /dev/null \
  -w 'API request: %{http_code}\n' \
  "$BASE_URL/api/"

# Test 3: Static asset
curl -sS -o /dev/null \
  -w 'Static asset request: %{http_code}\n' \
  "$BASE_URL/static/example.css"

# Test 4: Nonexistent resource
curl -sS -o /dev/null \
  -w '404 request: %{http_code}\n' \
  "$BASE_URL/does-not-exist"
```

The commands use `curl` to issue requests and print their HTTP status codes without displaying response bodies.

The API path `/api/` and static asset path `/static/example.css` are placeholders. They should be replaced with the actual Epicbook routes.

If Nginx is not exposed on the VM's loopback interface, the base URL should use the correct host address and port.

### 8.5 Verifying Host-Side Logs

After generating the requests, inspect the access log:

```
tail -n 100 ./logs/nginx/access.log
```

To validate the JSON structure of the entries:

```
jq . ./logs/nginx/access.log
```

To inspect the four relevant response categories:

```
# Successful responses
jq 'select(.status >= 200 and .status < 300)' \
  ./logs/nginx/access.log

# API requests: adjust the path to match the application
jq 'select(.request | contains("/api/"))' \
  ./logs/nginx/access.log

# Static asset requests: adjust the path as necessary
jq 'select(.request | contains("/static/"))' \
  ./logs/nginx/access.log

# 404 responses
jq 'select(.status == 404)' \
  ./logs/nginx/access.log
```

These commands assume that the relevant request fields are present in the JSON access log. They should be adapted if the deployed configuration uses a 
different field name or request representation.

For a reliable verification, inspect entries generated during the test window and confirm that the paths and status codes correspond to the requests issued.

### 8.6 Test Results

The documented test record states that, on October 15, 2026:

- Four requests were generated: an application page request, an API request, a static asset request, and a 404 request.
- All four requests were confirmed in `logs/nginx/access.log` on the VM host.
- The requests appeared as JSON log lines.
- The log file persisted after running `docker compose restart reverse-proxy`.

These results provide evidence that the reverse proxy access log captured the four tested request types and that the host-side log file remained available after a reverse proxy restart.

The restart test is particularly relevant because it verifies that the log file is not dependent solely on the lifetime of the reverse proxy container's writable filesystem.

The test record does not independently establish that all security exclusions, retention policies, alerting mechanisms, or database logging behavior have been tested. 
Those items require separate verification.

### 8.7 Verifying Persistence After Restart

The persistence test can be repeated using the following procedure:

```
# Confirm that the access log exists
ls -l ./logs/nginx/access.log

# Record the current file size and modification time
stat ./logs/nginx/access.log

# Restart the reverse proxy service
docker compose restart reverse-proxy

# Confirm that the host-side log file remains available
ls -l ./logs/nginx/access.log

# Inspect recent entries
tail -n 20 ./logs/nginx/access.log
```

The service name `reverse-proxy` must match the name used in the Compose configuration.

To confirm that logging continues after the restart, generate a new HTTP request and inspect the access log again. The expected result is a new JSON access entry for the request.

The existing file should remain available because the log directory is bind-mounted from the host, provided the mount remains correctly configured.

### 8.8 Failure Investigation Procedure

If an expected request does not appear in the access log, use the following procedure:

1. Confirm that the request reached the correct VM address and port.
2. Verify that the reverse proxy container is running.
3. Check that Nginx writes to `/var/log/nginx/access.log`.
4. Confirm that the host bind mount maps the expected directory.
5. Check file permissions and ownership.
6. Confirm that access logging is enabled for the relevant Nginx location.
7. Check whether log rotation has moved recent entries to another file.

If the request appears but returns an unexpected status:

1. Inspect the logged request and status code.
2. Review `./logs/nginx/error.log` for proxy-level failures.
3. Inspect backend output using `docker compose logs -t backend`.
4. If relevant, inspect database output using `docker compose logs -t database`.
5. Compare timestamps to determine where the failure occurred.
6. Document the findings and corrective action.

## 9\. Optional Log Forwarding and Centralized Observability

### 9.1 Overview

The current Epicbook deployment uses local host-mounted files for Nginx logs and Docker-managed logging for the backend and database.

For a larger deployment, a log forwarder such as Fluent Bit could collect these sources and send them to a centralized log store, such as Amazon CloudWatch Logs.

This enhancement is described as a future option. It is **not implemented as part of the current logging setup**.

### 9.2 Proposed Architecture

A future centralized logging pipeline could work as follows:

1. Fluent Bit monitors the host-side Nginx access and error logs.
2. Backend logs are collected from the Docker logging system using an appropriate collection method.
3. The forwarder processes and, where necessary, redacts or transforms records.
4. Logs are transmitted securely to a centralized log destination.
5. Operators search and analyze logs from a single interface.

A centralized store can improve visibility when the application grows beyond a single VM or when multiple instances need to be monitored.

### 9.3 Potential Benefits

Centralized logging could provide:

- Cross-service log searches.
- Longer-term log retention.
- Unified investigation across multiple application instances.
- Automated alerts for repeated errors.
- Dashboards for request volume and response status codes.
- Improved incident investigation and operational reporting.

### 9.4 Security and Implementation Considerations

Before introducing a log forwarder, the implementation should account for:

- Authentication and authorization for the destination.
- Encryption in transit.
- Redaction of sensitive fields.
- Appropriate retention and deletion policies.
- Collection permissions and host security.
- Forwarder resource consumption.
- Network availability and retry behavior.

The forwarder should not transmit passwords, database connection strings, authorization headers, API tokens, session identifiers, or private keys.

Given the documented deployment scale of one VM and one application, the existing local logging arrangement is sufficient for the current requirements. 
Centralized logging can be introduced when operational needs justify the additional complexity.

## 10\. Operational Recommendations

The following practices are recommended to maintain the reliability and security of the Epicbook logging infrastructure.

### 10.1 Routine Log Inspection

Operators should periodically:

- Review Nginx access logs for unexpected response patterns.
- Inspect Nginx error logs for upstream failures and configuration issues.
- Review backend logs for application exceptions and startup failures.
- Inspect database logs when investigating database-related problems.
- Correlate timestamps across services when diagnosing incidents.

### 10.2 Storage Management

Host-mounted logs can grow over time. The VM should be monitored for available disk space, and appropriate rotation and retention policies should be established.

Docker managed backend logs should also have an appropriate retention policy.

### 10.3 Security Review

Logging configuration should be reviewed whenever request routing, authentication, session handling, database connectivity, or application diagnostics change.

The review should verify that sensitive values are excluded and that access to log storage remains restricted.

### 10.4 Future Monitoring

As Epicbook grows, useful enhancements may include:

- Automated alerts for recurring HTTP 5xx responses.
- Request duration analysis.
- Backend error-rate monitoring.
- Host disk usage alerts.
- Centralized log aggregation.
- Consistent request IDs across the proxy and backend.
- Automated tests for JSON validity and sensitive-data redaction.

These enhancements are recommendations rather than claims about existing deployed capabilities.

## 11\. Conclusion

Epicbook uses Nginx, Node.js/Express, Docker Compose, and MySQL to provide a practical logging foundation for application troubleshooting and operational visibility.

The reverse proxy writes JSON-formatted access logs and error logs to host-mounted files, allowing direct inspection from the VM. 
The backend writes application messages to standard output and standard error, which can be inspected using `docker compose logs backend`. 
Database logs are available through `docker compose logs database`, subject to the configured MySQL logging behavior.

Failure testing was documented on October 15, 2026. Four request types—application page, API, static asset, and 404—were generated and 
verified as JSON access log entries on the VM host. The access log also remained available after restarting the reverse proxy container.

The logging architecture supports the current single-VM deployment without requiring a separate centralized logging service. 
Future enhancements, including Fluent Bit forwarding and centralized log storage, remain optional.

The key operational requirement is to preserve useful diagnostic information while ensuring that logs never expose passwords,
credential bearing database connection strings, authorization headers, API tokens, session identifiers, or private keys.
Appropriate access controls, retention policies, log rotation, and configuration reviews are essential to maintaining a reliable and secure observability system.
