# Dashboards

This folder contains dashboard definition files for Powerwall-Dashboard. Use the [dashboard.json](dashboard.json) if you are just getting started.

## Default Dashboard

The default dashboard is [dashboard.json](dashboard.json) as shown in the main README setup instructions.

<img width="1343" alt="image" src="https://github.com/jasonacox/Powerwall-Dashboard/assets/836718/bfe04a05-58fd-4c70-b569-508b694d5497">

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
