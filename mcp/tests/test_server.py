from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


class ServerSmokeTests(unittest.IsolatedAsyncioTestCase):
    async def test_server_lists_read_only_tools(self) -> None:
        parameters = StdioServerParameters(
            command=sys.executable,
            args=["-m", "luciddisk_mcp.server"],
        )

        with tempfile.TemporaryDirectory() as directory:
            candidate = Path(directory) / "candidate.bin"
            candidate.write_bytes(b"unchanged")
            before = candidate.read_bytes()

            async with stdio_client(parameters) as (read_stream, write_stream):
                async with ClientSession(read_stream, write_stream) as session:
                    await session.initialize()
                    result = await session.list_tools()
                    assessment = await session.call_tool(
                        "assess_paths",
                        {"paths": [str(candidate)], "calculate_size": False},
                    )
                    inventory = await session.call_tool(
                        "inventory_directory",
                        {"path": directory, "limit": 10},
                    )
                    plan = await session.call_tool(
                        "create_cleanup_plan",
                        {"paths": [str(candidate)], "calculate_size": False},
                    )

            self.assertEqual(candidate.read_bytes(), before)
            self.assertEqual([path.name for path in Path(directory).iterdir()], ["candidate.bin"])

        tools = {tool.name: tool for tool in result.tools}
        self.assertEqual(
            set(tools),
            {"assess_paths", "inventory_directory", "create_cleanup_plan"},
        )
        for tool in tools.values():
            self.assertTrue(tool.annotations.readOnlyHint)
            self.assertFalse(tool.annotations.destructiveHint)
        self.assertFalse(assessment.isError)
        item = assessment.structuredContent["assessments"][0]
        self.assertIn("resolved_path", item)
        self.assertIn("effective_risk", item)
        self.assertIn("size_accuracy", item)
        self.assertIn("warnings", item)
        self.assertNotIn("changed_files", assessment.structuredContent)
        self.assertNotIn("changed_files", inventory.structuredContent)
        self.assertNotIn("changed_files", plan.structuredContent)


if __name__ == "__main__":
    unittest.main()
