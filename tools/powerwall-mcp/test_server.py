import importlib.util
import json
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import Mock, patch


class FakeFastMCP:
    def __init__(self, *args, **kwargs):
        pass

    def tool(self):
        return lambda function: function


class FakeInfluxDBClient:
    def __init__(self, *args, **kwargs):
        self.init_kwargs = kwargs

    def query(self, query):
        raise AssertionError(f"Unexpected query: {query}")


def load_server():
    mcp_module = types.ModuleType("mcp")
    mcp_server_module = types.ModuleType("mcp.server")
    mcp_fastmcp_module = types.ModuleType("mcp.server.fastmcp")
    mcp_fastmcp_module.FastMCP = FakeFastMCP
    influxdb_module = types.ModuleType("influxdb")
    influxdb_module.InfluxDBClient = FakeInfluxDBClient

    modules = {
        "mcp": mcp_module,
        "mcp.server": mcp_server_module,
        "mcp.server.fastmcp": mcp_fastmcp_module,
        "influxdb": influxdb_module,
    }
    with patch.dict(sys.modules, modules):
        path = Path(__file__).with_name("server.py")
        spec = importlib.util.spec_from_file_location("powerwall_mcp_server", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module


server = load_server()


class QueryResult:
    def __init__(self, points):
        self.points = points

    def get_points(self):
        return iter(self.points)


class ServerTests(unittest.TestCase):
    def setUp(self):
        server._OVERVIEW_CACHE = None
        server._OVERVIEW_CACHE_TIME = 0.0

    def test_client_has_request_timeout(self):
        self.assertEqual(server.client.init_kwargs["timeout"], 30)

    def test_overview_uses_field_keys_instead_of_point_tags(self):
        client = Mock()

        def query(query_text):
            if query_text.startswith("SELECT"):
                return QueryResult(
                    [{"time": "2026-08-20T00:00:00Z", "solar": 5.0, "month": "08"}]
                )
            if query_text.startswith("SHOW FIELD KEYS"):
                return QueryResult(
                    [
                        {"fieldKey": "solar", "fieldType": "float"},
                        {"fieldKey": "home", "fieldType": "float"},
                    ]
                )
            raise AssertionError(f"Unexpected query: {query_text}")

        client.query.side_effect = query
        with (
            patch.object(server, "client", client),
            patch.object(server, "_measurement_pool", return_value=["http"]),
            patch.object(server, "_rps", return_value=["autogen"]),
        ):
            overview = server._build_overview()

        self.assertEqual(overview["autogen"]["http"]["fields"], ["home", "solar"])
        self.assertNotIn("month", overview["autogen"]["http"]["fields"])

    def test_overview_cache_expires_and_can_be_refreshed(self):
        build = Mock(side_effect=[{"version": 1}, {"version": 2}, {"version": 3}])
        with (
            patch.object(server, "_build_overview", build),
            patch.object(server, "OVERVIEW_CACHE_TTL", 300),
            patch.object(server.time, "monotonic", side_effect=[100, 200, 401, 402]),
        ):
            self.assertEqual(server._get_overview(), {"version": 1})
            self.assertEqual(server._get_overview(), {"version": 1})
            self.assertEqual(server._get_overview(), {"version": 2})
            self.assertEqual(server._get_overview(force=True), {"version": 3})

        self.assertEqual(build.call_count, 3)

    def test_query_requires_a_bounded_limit(self):
        self.assertIn(
            "must end with a LIMIT",
            server.query_powerwall('SELECT * FROM "autogen".http'),
        )
        self.assertIn(
            "LIMIT must be between",
            server.query_powerwall('SELECT * FROM "autogen".http LIMIT 1001'),
        )
        self.assertIn(
            "must end with a LIMIT",
            server.query_powerwall(
                'SELECT * FROM "autogen".http WHERE "status" = \'LIMIT 10\''
            ),
        )
        self.assertIn(
            "comments are not allowed",
            server.query_powerwall('SELECT * FROM "autogen".http -- LIMIT 10'),
        )

    def test_query_with_valid_limit_executes(self):
        client = Mock()
        client.query.return_value = QueryResult([{"solar": 5.0}])
        with patch.object(server, "client", client):
            response = server.query_powerwall(
                'SELECT "solar" FROM "autogen".http LIMIT 10'
            )

        self.assertEqual(json.loads(response), [{"solar": 5.0}])
        client.query.assert_called_once_with(
            'SELECT "solar" FROM "autogen".http LIMIT 10'
        )


if __name__ == "__main__":
    unittest.main()
