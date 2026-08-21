#!/usr/bin/env python3
"""Small MCP client that demonstrates an agent-style Powerwall query workflow."""

import argparse
import json
import math
import sys
import urllib.error
import urllib.request


class MCPClient:
    def __init__(self, url, auth_token=None):
        self.url = url
        self.auth_token = auth_token
        self.session_id = None
        self.request_id = 0

    def _post(self, payload):
        headers = {
            "Accept": "application/json, text/event-stream",
            "Content-Type": "application/json",
        }
        if self.auth_token:
            headers["Authorization"] = f"Bearer {self.auth_token}"
        if self.session_id:
            headers["Mcp-Session-Id"] = self.session_id

        request = urllib.request.Request(
            self.url,
            data=json.dumps(payload).encode(),
            headers=headers,
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            if not self.session_id:
                self.session_id = response.headers.get("Mcp-Session-Id")
            body = response.read().decode()

        data_lines = [
            line.removeprefix("data:").strip()
            for line in body.splitlines()
            if line.startswith("data:")
        ]
        if not data_lines:
            return None
        message = json.loads("\n".join(data_lines))
        if "error" in message:
            error = message["error"]
            raise RuntimeError(f"MCP error {error.get('code')}: {error.get('message')}")
        return message.get("result")

    def request(self, method, params=None):
        self.request_id += 1
        return self._post(
            {
                "jsonrpc": "2.0",
                "id": self.request_id,
                "method": method,
                "params": params or {},
            }
        )

    def notify(self, method, params=None):
        self._post(
            {
                "jsonrpc": "2.0",
                "method": method,
                "params": params or {},
            }
        )

    def initialize(self):
        result = self.request(
            "initialize",
            {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {
                    "name": "powerwall-mcp-mock-agent",
                    "version": "1.0",
                },
            },
        )
        self.notify("notifications/initialized")
        return result

    def call_tool(self, name, arguments=None):
        result = self.request(
            "tools/call",
            {"name": name, "arguments": arguments or {}},
        )
        if result.get("isError"):
            raise RuntimeError(result["content"][0]["text"])
        value = result.get("structuredContent", {}).get("result")
        if value is None:
            value = result["content"][0]["text"]
        return json.loads(value)


def available_fields(overview, retention_policy, measurement):
    return overview.get(retention_policy, {}).get(measurement, {}).get("fields", [])


def query_latest(client, overview, retention_policy, measurement, desired_fields, where=""):
    fields = [
        field
        for field in desired_fields
        if field in available_fields(overview, retention_policy, measurement)
    ]
    if not fields:
        return None
    columns = ", ".join(f'"{field}"' for field in fields)
    query = f'SELECT {columns} FROM "{retention_policy}"."{measurement}"'
    if where:
        query += f" WHERE {where}"
    query += " ORDER BY time DESC LIMIT 1"
    rows = client.call_tool("query_powerwall", {"query": query})
    return rows[0] if rows else None


def number(value):
    return float(value) if isinstance(value, (int, float)) and math.isfinite(value) else 0.0


def power_direction(imported, exported, import_label, export_label):
    net = number(imported) - number(exported)
    if abs(net) < 1:
        return "idle"
    if net > 0:
        return f"{import_label} {net:,.0f} W"
    return f"{export_label} {-net:,.0f} W"


def print_report(current, pod, grid, yesterday):
    print("\nPowerwall summary")
    print("=================")

    if current:
        print(f"Latest sample:       {current.get('time', 'unknown')}")
        print(f"Solar production:    {number(current.get('solar')):,.0f} W")
        print(f"Home consumption:    {number(current.get('home')):,.0f} W")
        print(
            "Grid flow:          "
            + power_direction(
                current.get("from_grid"),
                current.get("to_grid"),
                "importing",
                "exporting",
            )
        )
        print(
            "Battery flow:       "
            + power_direction(
                current.get("from_pw"),
                current.get("to_pw"),
                "supplying",
                "charging",
            )
        )
        if "percentage" in current:
            print(f"Battery charge:      {number(current['percentage']):.1f}%")
    else:
        print("Current power data:  unavailable")

    if pod:
        remaining = number(pod.get("nominal_energy_remaining"))
        capacity = number(pod.get("nominal_full_pack_energy"))
        if remaining:
            print(f"Stored energy:       {remaining / 1000:,.1f} kWh")
        if capacity:
            print(f"Pack capacity:       {capacity / 1000:,.1f} kWh")
        if "backup_reserve_percent" in pod:
            print(f"Backup reserve:      {number(pod['backup_reserve_percent']):.1f}%")

    if grid and "grid_status" in grid:
        print(f"Grid status:         {grid['grid_status']}")

    if yesterday:
        solar = number(yesterday.get("solar"))
        home = number(yesterday.get("home"))
        exported = number(yesterday.get("to_grid"))
        imported = number(yesterday.get("from_grid"))
        self_consumed = max(solar - exported, 0)
        print("\nPrevious complete day")
        print("---------------------")
        print(f"Date bucket:         {yesterday.get('time', 'unknown')}")
        print(f"Solar generated:     {solar:,.1f} kWh")
        print(f"Home consumed:       {home:,.1f} kWh")
        print(f"Grid imported:       {imported:,.1f} kWh")
        print(f"Grid exported:       {exported:,.1f} kWh")
        print(f"Solar self-consumed: {self_consumed:,.1f} kWh")


def main():
    parser = argparse.ArgumentParser(
        description="Exercise Powerwall MCP tools like a simple AI agent."
    )
    parser.add_argument(
        "--url",
        default="http://127.0.0.1:8765/mcp",
        help="Streamable HTTP MCP endpoint",
    )
    parser.add_argument("--auth-token", help="Optional MCP bearer token")
    args = parser.parse_args()

    client = MCPClient(args.url, args.auth_token)
    initialized = client.initialize()
    server = initialized.get("serverInfo", {})
    print(f"Connected to {server.get('name', 'MCP server')} {server.get('version', '')}")

    tools = client.request("tools/list").get("tools", [])
    print("Discovered tools: " + ", ".join(tool["name"] for tool in tools))

    overview = client.call_tool("get_database_overview")
    populated = {
        policy: sorted(measurements)
        for policy, measurements in overview.items()
        if measurements
    }
    print(
        f"Discovered {len(populated)} populated retention policies: "
        + ", ".join(populated)
    )

    current = query_latest(
        client,
        overview,
        "autogen",
        "http",
        ["solar", "home", "from_grid", "to_grid", "from_pw", "to_pw", "percentage"],
    )
    pod = query_latest(
        client,
        overview,
        "pod",
        "http",
        [
            "nominal_energy_remaining",
            "nominal_full_pack_energy",
            "backup_reserve_percent",
        ],
    )
    grid = query_latest(client, overview, "grid", "http", ["grid_status"])
    yesterday = query_latest(
        client,
        overview,
        "daily",
        "http",
        ["solar", "home", "from_grid", "to_grid", "from_pw", "to_pw"],
        "time < now() - 1d",
    )
    print_report(current, pod, grid, yesterday)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(f"Error: {error}", file=sys.stderr)
        raise SystemExit(1)
