## Epicbook : Proxy Routing and CORS
**Written by : George Adimowei Epebifie**

# 1. Reverse Proxy
Nginx acts as the single public entry point for the EpicBook application, routing incoming HTTP requests to the appropriate Docker Compose service.

**Public access:** TCP port 80 (HTTP)

**Internal Docker network:**
Frontend: frontend:80
Backend API: backend:8080
Database: database:3306
These service names and ports represent the intended configuration and should match the actual Docker Compose and Nginx configuration.

**Proxy Routing**
Nginx routes requests according to the configured URL paths:

/assets/*
    -> frontend:80

/health
    -> backend:8080/health

/*
    -> backend:8080
/assets/* — Routes static asset requests to the frontend service.
/health — Forwards health-check requests to the backend health endpoint, allowing the application's availability to be monitored.
/* — Routes other requests to the backend application, including application pages and API endpoints, according to the backend's routing configuration.
The actual routing behaviour depends on the location directives and proxy settings in proxy/nginx.conf.

**Same-Origin Design**
Users access EpicBook through a single public origin:
http://PUBLIC_IP
The browser sends requests to this same origin, and Nginx forwards them internally to the frontend or backend services. Because the browser communicates with one origin, 
frontend requests routed through Nginx to the backend do not require cross-origin access.

# 2. Was CORS Required?
No, CORS configuration was not required for this same origin deployment, provided that the frontend makes its requests through the public Nginx origin rather than directly 
to the backend using a different hostname, IP address, or port.
CORS is a browser security mechanism that controls requests between different origins. Since the browser accesses the application and its API through the same scheme, 
host, and port, the requests are same origin. Therefore, the application does not need a wildcard CORS header such as:

Access-Control-Allow-Origin: *
Avoiding unnecessary CORS permissions reduces the risk of allowing unintended cross-origin access. If the frontend is later hosted on a different origin, an explicit CORS policy 
may be required.

# 3. Security
Nginx is the only publicly exposed application entry point on TCP port 80.
Backend and database ports should remain unpublished to the host and accessible only through the internal Docker network.
The database should not be directly accessible from the public internet.
Docker Compose service-to-service communication should use internal service names, such as backend:8080 and database:3306.
Production deployments should use HTTPS to protect credentials, session data, and application traffic in transit.


## Conclusion
The Nginx reverse proxy centralizes public access, routes requests to the appropriate internal services, and supports a same origin application design. 
Consequently, CORS is unnecessary for the described deployment as long as all browser facing requests use the same public origin.
