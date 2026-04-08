from __future__ import annotations

import argparse
import json

from .client import PacketProcessorClient
from .protocol import Action, Mode
from .rules import Rule


def main() -> None:
    parser = argparse.ArgumentParser(description="Packet processor control CLI")
    parser.add_argument("--port", required=True)
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("ping")
    sub.add_parser("info")
    sub.add_parser("counters")
    sub.add_parser("last-result")

    mode_p = sub.add_parser("set-mode")
    mode_p.add_argument("mode", choices=["inspect", "inline", "benchmark"])

    verbose_p = sub.add_parser("set-verbose")
    verbose_p.add_argument("enabled", choices=["0", "1"])

    clear_rule_p = sub.add_parser("clear-rule")
    clear_rule_p.add_argument("index", type=int)
    sub.add_parser("clear-all-rules")

    write_rule_p = sub.add_parser("write-rule")
    write_rule_p.add_argument("index", type=int)
    write_rule_p.add_argument("json_rule", help="JSON object matching host.rules.Rule fields")

    args = parser.parse_args()
    client = PacketProcessorClient(args.port)
    try:
        if args.cmd == "ping":
            print(client.ping())
        elif args.cmd == "info":
            print(client.get_info())
        elif args.cmd == "counters":
            print(json.dumps(client.read_counters(), indent=2))
        elif args.cmd == "last-result":
            print(client.read_last_result())
        elif args.cmd == "set-mode":
            mode_map = {
                "inspect": int(Mode.INSPECT),
                "inline": int(Mode.INLINE),
                "benchmark": int(Mode.BENCHMARK),
            }
            client.set_mode(mode_map[args.mode])
        elif args.cmd == "set-verbose":
            client.set_verbose(args.enabled == "1")
        elif args.cmd == "clear-rule":
            client.clear_rule(args.index)
        elif args.cmd == "clear-all-rules":
            client.clear_all_rules()
        elif args.cmd == "write-rule":
            client.write_rule(args.index, Rule(**json.loads(args.json_rule)))
    finally:
        client.close()


if __name__ == "__main__":
    main()

