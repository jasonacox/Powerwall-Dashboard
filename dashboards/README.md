# Dashboards

This folder contains dashboard definition files for Powerwall-Dashboard. Use the [dashboard.json](dashboard.json) if you are just getting started.

## Default Dashboard

The default dashboard is [dashboard.json](dashboard.json) as shown in the main README setup instructions.

<img width="1343" alt="image" src="https://github.com/jasonacox/Powerwall-Dashboard/assets/836718/bfe04a05-58fd-4c70-b569-508b694d5497">

## HTTPS / Reverse Proxy (pypowerwall-server)

If you access Grafana over HTTPS (e.g., via nginx / NGINX Proxy Manager / Traefik), browsers will block loading the Power Flow animation if it is fetched directly from `http://<host>:8675` (mixed content).

The included nginx configuration (`nginx/conf.d/default.conf`) puts **both Grafana and pypowerwall behind a single HTTPS port (443)**. pypowerwall is mounted under the `/pypowerwall/` sub-path by setting `PROXY_BASE_URL=/pypowerwall` in the pypowerwall service (injected via `powerwall-nginx.yml`). This tells the server to prefix all its API and asset paths with `/pypowerwall/`, so the compiled animation JS calls `/pypowerwall/api/system_status/soe` instead of bare `/api/...`, which nginx can unambiguously route to pypowerwall rather than Grafana.

The dashboards automatically detect the protocol:

- **HTTP** (direct Grafana access) → animation iframe uses `http://<hostname>:8675` directly
- **HTTPS** (via nginx) → animation iframe uses `/pypowerwall` (same-origin path on port 443)

### Enabling nginx HTTPS

The easiest way is to run `setup.sh` and choose option **2 – HTTPS via nginx** when prompted for installation type. This will:

1. Set `NGINX_ENABLED=true` in `compose.env`
2. Automatically generate a self-signed SSL certificate in `nginx/ssl/`
3. Include `powerwall-nginx.yml` when starting containers

To enable manually, add `NGINX_ENABLED=true` to `compose.env` and generate a certificate:

```sh
# Optionally pass your hostname/domain as an argument (default: localhost)
./nginx/generate-self-signed.sh your.domain.local
```

Then restart with:

```sh
./compose-dash.sh up -d
```

### nginx config (`nginx/conf.d/default.conf`)

```nginx
# Grafana and pypowerwall-server on a single port 443.
# pypowerwall is mounted under /pypowerwall/ (PROXY_BASE_URL=/pypowerwall in powerwall-nginx.yml).
server {
    listen 443 ssl;
    server_name _;

    ssl_certificate     /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;

    # Tesla's animation JS calls /pypowerwall/api/networks expecting an array.
    # pypowerwall returns an object {}; return [] directly to avoid a JS TypeError.
    location ~ ^/pypowerwall/api/(networks|system/networks)$ {
        default_type application/json;
        return 200 '[]';
    }

    # pypowerwall-server — trailing slash strips /pypowerwall/ prefix before forwarding
    location /pypowerwall/ {
        proxy_pass http://pypowerwall:8675/;
        proxy_set_header Host              $http_host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host  $http_host;
        proxy_set_header X-Forwarded-Port  $server_port;

        # WebSocket support (required for /ws/* real-time endpoints)
        proxy_http_version 1.1;
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;

        # allow embedding in Grafana iframe
        proxy_hide_header X-Frame-Options;

        # Strip upstream CORS headers to prevent duplicates
        proxy_hide_header Access-Control-Allow-Origin;
        proxy_hide_header Access-Control-Allow-Credentials;
        proxy_hide_header Access-Control-Allow-Methods;
        proxy_hide_header Access-Control-Allow-Headers;

        add_header 'Access-Control-Allow-Origin'      $http_origin always;
        add_header 'Access-Control-Allow-Credentials' 'true'       always;
        add_header 'Access-Control-Allow-Methods'     '*'          always;
        add_header 'Access-Control-Allow-Headers'     '*'          always;
    }

    # Favicon: try pypowerwall first, fall back to Grafana icon on non-200
    location = /favicon.ico {
        proxy_pass http://pypowerwall:8675;
        proxy_intercept_errors on;
        error_page 301 302 303 304 400 401 403 404 500 502 503 504 = @grafana_favicon;
    }
    location @grafana_favicon {
        rewrite ^ /public/img/grafana_icon.svg break;
        proxy_pass http://grafana:9000;
    }

    # Grafana — catch-all
    location / {
        proxy_pass http://grafana:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

Notes:

- Only port **443** needs to be open — no extra firewall rules required.
- Your browser will show a security warning for the self-signed certificate; click **Advanced → Proceed** to continue.
- See https://github.com/jasonacox/Powerwall-Dashboard/issues/748 for background and troubleshooting.
## Alternative Dashboards

### Min-Mean-Max

This dashboard graphs min(), mean() and max() values for the Solar, Home, Grid and Powerwall series.  The Bright line is mean with spikes showing up as a translucent shade of the primary color.

[dashboard-min-mean-max.json](dashboard-min-mean-max.json)

<img width="863" alt="image" src="https://user-images.githubusercontent.com/836718/224519614-76dcab24-deb3-42fe-a0ba-9f4837af7ee8.png">

### No Animation

This dashboard provides the original time series "Live Monitoring" graph but removes the Powerwall flow animation panel.

[dashboard-no-animation.json](dashboard-no-animation.json)

<img width="864" alt="image" src="https://user-images.githubusercontent.com/836718/224519662-f29a044a-34d8-4d1f-9220-bebfe7172cd3.png">

### Simple

Similar to the above, this dashboard provides a basic time series graph and meter data but without any of the Powerwall+ or extended data.

[dashboard-simple.json](dashboard-simple.json)

## Solar Only Dashboard

This dashboard is for [Solar Only](../tools/solar-only/) users and is similar to the default dashboard, but removes the Powerwall flow animation panel and other Powerwall+ or extended data panels.

[dashboard-solar-only.json](dashboard-solar-only.json)

![Screenshot (2)](https://github.com/jasonacox/Powerwall-Dashboard/assets/20891340/3f954359-e851-462e-ba20-e1ad90db5bd7)

Thanks to [@Jot18](https://github.com/Jot18) for the example dashboard screenshot.

## Submit Your Dashboard

Do you have a great dashboard?  Do you think others might be able to use it?  If so, submit a PR so we can get it added.

## Color Scheme

In general, the Dashboard uses this color scheme to help identify the metrics:

| Swatch | Hex | RGB | Use Case |
|------|------|------|---------|
| <img width="50" height="50" alt="image" src="https://github.com/user-attachments/assets/194e3871-151a-4e28-afec-3fe907e3c646" /> | `#FADE2A` | `rgb(250, 222, 42)` | Solar |
| <img width="50" height="50" alt="image" src="https://github.com/user-attachments/assets/b8175f7d-ca73-493e-81a8-5a005c9bd621" /> | `#73BF69` | `rgb(115, 191, 105)` | Powerwall |
| <img width="50" height="50" alt="image" src="https://github.com/user-attachments/assets/32815264-0170-48d6-9189-f6395ff4a4c2" /> | `#5794F2` | `rgb(87, 148, 242)` | Home |
| <img width="50" height="50" alt="image" src="https://github.com/user-attachments/assets/b1cf5a13-68e5-4437-b5a2-66b46c42542a" /> | `#B877D9` | `rgb(184, 119, 217)` | Grid |
