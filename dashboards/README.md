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
