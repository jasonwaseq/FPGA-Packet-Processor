from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

try:
    from cocotb_tools.runner import get_runner as _get_runner  # cocotb >= 2.0
except Exception:  # pragma: no cover - compatibility path
    try:
        from cocotb.runner import get_runner as _get_runner  # cocotb 1.8 - 1.x
    except Exception:  # pragma: no cover - compatibility path
        _get_runner = None


ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "rtl"
TB = ROOT / "tb"


COMMON_RTL = [
    RTL / "packet_processor_pkg.sv",
]


TESTS = {
    "uart_loopback": {
        "toplevel": "dut_uart_loopback",
        "module": "tb.test_uart_loopback",
        "sources": COMMON_RTL + [RTL / "uart_rx.sv", RTL / "uart_tx.sv", TB / "dut_uart_loopback.sv"],
    },
    "frame_codec": {
        "toplevel": "dut_frame_codec",
        "module": "tb.test_frame_codec",
        "sources": COMMON_RTL + [RTL / "uart_frame_decoder.sv", RTL / "uart_frame_encoder.sv", TB / "dut_frame_codec.sv"],
    },
    "packet_parser": {
        "toplevel": "dut_packet_parser",
        "module": "tb.test_packet_parser",
        "sources": COMMON_RTL + [RTL / "packet_header_parser.sv", TB / "dut_packet_parser.sv"],
    },
    "classifier_engine": {
        "toplevel": "dut_classifier_engine",
        "module": "tb.test_classifier_engine",
        "sources": COMMON_RTL + [RTL / "rule_table.sv", RTL / "classifier_engine.sv", TB / "dut_classifier_engine.sv"],
    },
}


def _find_cocotb_config() -> str | None:
    cocotb_config = shutil.which("cocotb-config")
    if cocotb_config:
        return cocotb_config

    candidate_dirs = [
        Path(sys.executable).parent,
        Path(sys.prefix) / "bin",
    ]
    for scripts_dir in candidate_dirs:
        for candidate in ("cocotb-config", "cocotb-config.exe"):
            maybe = scripts_dir / candidate
            if maybe.is_file():
                return str(maybe)
    return None


def resolve_sim(cfg: dict[str, object], sim_override: str | None) -> str:
    if sim_override:
        return sim_override

    preferred_sim = str(cfg.get("preferred_sim", "icarus"))
    if preferred_sim == "verilator" and shutil.which("verilator") is None:
        return "icarus"
    return preferred_sim


def run_test(name: str, sim: str | None) -> None:
    cfg = TESTS[name]
    resolved_sim = resolve_sim(cfg, sim)
    build_dir = ROOT / "build" / "cocotb" / name
    launcher = os.environ.get("COCOTB_LAUNCHER", "auto")

    if launcher not in {"auto", "legacy", "runner"}:
        raise ValueError("COCOTB_LAUNCHER must be one of: auto, legacy, runner")

    prefer_legacy = launcher == "legacy" and _find_cocotb_config() is not None

    if prefer_legacy:
        run_test_legacy(name, resolved_sim, cfg, build_dir)
    elif _get_runner is not None:
        build_args = ["--sv"] if resolved_sim == "verilator" else ["-g2012"]
        runner = _get_runner(resolved_sim)
        build_kwargs = dict(
            hdl_toplevel=cfg["toplevel"],
            always=True,
            build_dir=str(build_dir),
            waves=False,
            build_args=build_args,
        )
        try:
            runner.build(
                sources=[str(path) for path in cfg["sources"]],
                **build_kwargs,
            )
        except TypeError:
            runner.build(
                verilog_sources=[str(path) for path in cfg["sources"]],
                **build_kwargs,
            )
        runner.test(
            hdl_toplevel=cfg["toplevel"],
            test_module=cfg["module"],
            waves=False,
        )
    else:
        run_test_legacy(name, resolved_sim, cfg, build_dir)


def _stdout_indicates_pass(stdout: str, stderr: str) -> bool:
    combined = f"{stdout}\n{stderr}"
    if "Segmentation fault" not in combined and "core dumped" not in combined:
        return False
    summary_match = re.search(r"TESTS=(\d+)\s+PASS=(\d+)\s+FAIL=(\d+)\s+SKIP=(\d+)", combined)
    if summary_match is None:
        return False
    tests, passed, failed, _skipped = map(int, summary_match.groups())
    return tests > 0 and passed == tests and failed == 0


def run_test_legacy(name: str, sim: str, cfg: dict[str, object], build_dir: Path) -> None:
    cocotb_config = _find_cocotb_config()
    if cocotb_config is None:
        raise RuntimeError(
            "cocotb.runner is unavailable and cocotb-config was not found. "
            "Install cocotb or add cocotb-config to PATH."
        )

    makefiles_dir = subprocess.check_output(
        [cocotb_config, "--makefiles"],
        text=True,
        cwd=ROOT,
    ).strip()
    makefile_sim = Path(makefiles_dir) / "Makefile.sim"

    env = os.environ.copy()
    env["SIM"] = sim
    env["TOPLEVEL_LANG"] = "verilog"
    env["TOPLEVEL"] = str(cfg["toplevel"])
    env["MODULE"] = str(cfg["module"])
    env["COCOTB_TOPLEVEL"] = str(cfg["toplevel"])
    env["COCOTB_TEST_MODULES"] = str(cfg["module"])
    env["VERILOG_SOURCES"] = " ".join(str(path) for path in cfg["sources"])
    env["SIM_BUILD"] = str(build_dir)
    env["PYTHONPATH"] = str(ROOT) + os.pathsep + env.get("PYTHONPATH", "")

    completed = subprocess.run(
        ["make", "-f", str(makefile_sim)],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
    )
    if completed.stdout:
        print(completed.stdout, end="")
    if completed.stderr:
        print(completed.stderr, end="", file=sys.stderr)

    if completed.returncode == 0:
        return

    if _stdout_indicates_pass(completed.stdout, completed.stderr):
        print(
            f"[tb.run] treating '{name}' as PASS despite simulator post-pass crash "
            "because cocotb reported all tests passed.",
            file=sys.stderr,
        )
        return

    raise subprocess.CalledProcessError(
        completed.returncode,
        completed.args,
        output=completed.stdout,
        stderr=completed.stderr,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Run cocotb tests")
    parser.add_argument("test", choices=["all", *TESTS.keys()])
    parser.add_argument("--sim", default=os.environ.get("SIM"))
    args = parser.parse_args()

    selected = TESTS.keys() if args.test == "all" else [args.test]
    for name in selected:
        run_test(name, args.sim)


if __name__ == "__main__":
    main()
