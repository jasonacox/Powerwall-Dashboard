-- weather411 -> pw_weather_log. telegraf-timescale.conf polls weather411's
-- /all JSON endpoint into the raw "weather" table (one wide row per poll,
-- timestamped with OpenWeatherMap's own observation time "dt"). This unpivots
-- each row into pw_weather_log's narrow (time, metric_name, value, text_value)
-- shape: numbers go to value, strings (name, country, weather_*) to text_value.
--
-- Telegraf polls more often than OpenWeatherMap updates, so the raw table
-- holds repeated identical rows per "dt" -- GROUP BY collapses them, and
-- ON CONFLICT makes re-runs harmless. The 2-hour window is wider than the
-- other aggregates' 15 minutes because "dt" can lag well behind now().
--
-- Raw "time" is timestamp WITHOUT time zone holding UTC (Telegraf's
-- default), hence the explicit AT TIME ZONE 'UTC' conversions.
--
-- No-op until the "weather" table exists (Telegraf creates it on its first
-- successful poll; it never will if weather411 has no OpenWeatherMap key).
DO $$
BEGIN
  IF to_regclass('public.weather') IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO pw_weather_log (time, metric_name, value, text_value)
  SELECT w.time AT TIME ZONE 'UTC',
         kv.key,
         max(CASE WHEN jsonb_typeof(kv.value) = 'number'
                  THEN (kv.value)::text::double precision END),
         max(CASE WHEN jsonb_typeof(kv.value) = 'string'
                  THEN kv.value #>> '{}' END)
  FROM weather w
  CROSS JOIN LATERAL jsonb_each(
    to_jsonb(w) - 'time' - 'host' - 'url' - 'month' - 'year'
  ) AS kv(key, value)
  WHERE w.time >= (now() - interval '2 hours') AT TIME ZONE 'UTC'
    AND jsonb_typeof(kv.value) <> 'null'
  GROUP BY w.time, kv.key
  UNION ALL
  -- Telegraf consumes "dt" as the timestamp, so it isn't a column; store it
  -- as a metric too, matching weather411's own InfluxDB fields.
  SELECT DISTINCT w.time AT TIME ZONE 'UTC', 'dt',
         extract(epoch FROM w.time AT TIME ZONE 'UTC'), NULL
  FROM weather w
  WHERE w.time >= (now() - interval '2 hours') AT TIME ZONE 'UTC'
  ON CONFLICT (time, metric_name) DO UPDATE
    SET value = EXCLUDED.value, text_value = EXCLUDED.text_value;
END $$;
