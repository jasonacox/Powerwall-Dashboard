INSERT INTO pw_grid_1m (time, grid_status)
SELECT
  time_bucket('1 minute', time) AT TIME ZONE 'UTC' AS bucket,
  min(grid_status) AS grid_status
FROM http
WHERE time >= date_trunc('minute', (now() - interval '15 minutes') AT TIME ZONE 'UTC')
GROUP BY 1
ON CONFLICT (time) DO UPDATE SET grid_status = EXCLUDED.grid_status;
