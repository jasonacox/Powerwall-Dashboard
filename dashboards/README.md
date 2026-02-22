# Dashboards

This folder contains dashboard definition files for Powerwall-Dashboard. Use the [dashboard.json](dashboard.json) if you are just getting started.

## Default Dashboard

The default dashboard is [dashboard.json](dashboard.json) as shown in the main README setup instructions.

<img width="1343" alt="image" src="https://github.com/jasonacox/Powerwall-Dashboard/assets/836718/bfe04a05-58fd-4c70-b569-508b694d5497">

## HTTPS / Reverse Proxy (pypowerwall-server)

If you access Grafana over HTTPS (e.g., via nginx / NGINX Proxy Manager / Traefik), browsers will block loading the Power Flow animation and the pypowerwall-server console if they are fetched directly from `http://<host>:8675` (mixed content).

The dashboards that include the Power Flow panel now use this behavior:

- When Grafana is loaded over **HTTP**, the dashboard will continue using `http://<hostname>:8675`.
- When Grafana is loaded over **HTTPS**, the dashboard will instead use the same-origin path prefix: `/pypowerwall`.

To make HTTPS work, your reverse proxy must forward **`/pypowerwall/`** to the pypowerwall-server on port **8675** *on the same HTTPS host as Grafana*.

Example nginx config (adapt as needed):

```nginx
server {
    listen 443 ssl;
    server_name pypowerwall.domain.local;

    ssl_certificate     /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;

    # pypowerwall-server: animation page
    # Rewrite absolute paths so sub-resources stay under /pypowerwall/ prefix
    location /pypowerwall/ {
        proxy_pass http://127.0.0.1:8675/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        sub_filter_once off;
        sub_filter '"/static/powerflow/' '"/pypowerwall/static/powerflow/';
        sub_filter 'window.apiBaseUrl = "http://' 'window.apiBaseUrl = "/pypowerwall/api"; // http://';
    }

    # pypowerwall-server: static assets (under /pypowerwall/ prefix)
    location /pypowerwall/static/powerflow/ {
        proxy_pass http://127.0.0.1:8675/static/powerflow/;
        proxy_set_header Host $host;
    }

    # pypowerwall-server: API (under /pypowerwall/ prefix)
    location /pypowerwall/api/ {
        proxy_pass http://127.0.0.1:8675/api/;
        proxy_set_header Host $host;
    }

    # Grafana dashboard (port 9000) - catch-all, no conflicts
    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

Notes:

- If you don’t want to rewrite content, another option is to expose pypowerwall-server via HTTPS separately and load it from that HTTPS origin (but the dashboards’ HTTPS path mode expects `/pypowerwall` on the Grafana origin).
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
