#!/usr/bin/env python3

"""Measure the installed app's onscreen replay; save timing/resource data, never pixels."""
import argparse
import json
import math
import os
import plistlib
import statistics
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def percentile(values, fraction):
    values = sorted(values)
    return values[max(0, math.ceil(len(values) * fraction) - 1)] if values else None


def distribution(values):
    if not values:
        return "unavailable"
    return "/".join(f"{percentile(values, q):.2f}" for q in (0.5, 0.95, 0.99)) + f" (max {max(values):.2f})"


def cpu_seconds(value):
    days, _, clock = value.rpartition("-")
    parts = list(map(float, clock.split(":")))
    return (float(days) * 86400 if days else 0) + sum(n * 60 ** i for i, n in enumerate(reversed(parts)))


def sample(pids):
    result = {"time": time.monotonic(), "processes": {}}
    ps = subprocess.run(["ps", "-p", ",".join(map(str, pids)), "-o", "pid=,time=,rss="], capture_output=True, text=True)
    for row in ps.stdout.splitlines():
        pid, cpu, rss = row.split()
        result["processes"][pid] = {"cpu_seconds": cpu_seconds(cpu), "rss_mb": int(rss) / 1024}
    raw = subprocess.check_output(["ioreg", "-a", "-r", "-c", "AppleSmartBattery"])
    batteries = plistlib.loads(raw)
    if batteries:
        battery = batteries[0]
        amps = battery.get("InstantAmperage", battery.get("Amperage", 0))
        if amps >= 2 ** 63:
            amps -= 2 ** 64
        on_battery = not battery.get("ExternalConnected", True)
        result["battery"] = {
            "on_battery": on_battery,
            "percent": battery.get("CurrentCapacity"),
            "discharge_watts": -amps * battery.get("Voltage", 0) / 1_000_000 if on_battery and amps < 0 else None,
        }
    return result


def summarize(directory):
    report = json.loads((directory / "frames.json").read_text())
    resources = json.loads((directory / "resources.json").read_text())
    events = report["events"]
    hz = next((int(e["value"]) for e in events if e["name"] == "requested-hz"), min(max(report["refreshHz"], 60), 120))
    budget = 1000 / hz
    lines = ["# DuoFX onscreen performance measurement", "",
             f"{resources['chip']} · {report['os']} · {report['width']}×{report['height']} pixels · requested {hz} Hz ({budget:.2f} ms/frame).", "",
             "Installed Release app, Settings closed, live desktop capture, manual angle replay, Perspective, sound off. Six closing/opening cycles, then a held half-close. No captured frames were saved.", "",
             f"Measured configuration: `{json.dumps(report['configuration'], sort_keys=True)}`", ""]
    if report.get("error"):
        lines += [f"**Run error:** {report['error']}", ""]
    lines += ["Intervals below use Metal drawable presentedTime, not draw callbacks or GPU completion. Gaps above 1.5× the requested frame budget are counted as long intervals; adaptive refresh and other apps can also cause these gaps.", "",
              "| Session | Target → first presentation ms | First second p50/p95/p99 ms (max) | Steady p50/p95/p99 ms (max) | Long intervals / all |",
              "|---|---:|---|---|---:|"]
    all_intervals = []
    for session in sorted({e["session"] for e in events if e["name"] == "target"}):
        group = [e for e in events if e["session"] == session]
        times = sorted(e["value"] for e in group if e["name"] == "presented" and e["value"] > 0)
        target = next(e["time"] for e in group if e["name"] == "target")
        pairs = [(b, (b - a) * 1000) for a, b in zip(times, times[1:]) if b > a]
        intervals = [v for _, v in pairs]
        all_intervals.extend(intervals)
        early = [v for t, v in pairs if t - times[0] <= 1] if times else []
        steady = [v for t, v in pairs if t - times[0] > 1] if times else []
        latency = f"{(times[0] - target) * 1000:.1f}" if times else "unavailable"
        lines.append(f"| {session} | {latency} | {distribution(early)} | {distribution(steady)} | {sum(v > budget * 1.5 for v in intervals)} / {len(intervals)} |")
    lines += ["", f"All presented intervals p50/p95/p99 ms: {distribution(all_intervals)}.",
              f"GPU duration p50/p95/p99 ms: {distribution([e['value'] for e in events if e['name'] == 'gpu-ms'])}.",
              f"Draw callback through encoding p50/p95/p99 ms: {distribution([e['value'] for e in events if e['name'] == 'encode-ms'])}.",
              f"Skipped draws: {sum(e['name'] == 'inflight-skip' for e in events)} in-flight limit; {sum(e['name'] == 'drawable-skip' for e in events)} missing drawable. Presentation callbacks reporting zero: {sum(e['name'] == 'presented' and e['value'] == 0 for e in events)}.", "",
              "## Resources and battery", "",
              "CPU is measured from deltas of cumulative process CPU time (100% = one core). RSS is resident memory. Phase summaries exclude the first two seconds. WindowServer includes all apps; battery watts are whole-machine discharge, not isolated DuoFX power.", "",
              "| Phase | DuoFX CPU mean % | WindowServer CPU mean % | DuoFX RSS max MB | Battery discharge median W |",
              "|---|---:|---:|---:|---:|"]
    samples = resources["samples"]
    phases = [e for e in events if e["name"].startswith("phase:")]
    for i, phase in enumerate(phases):
        end = phases[i + 1]["time"] if i + 1 < len(phases) else float("inf")
        selected = [s for s in samples if phase["time"] + 2 <= s["time"] < end]
        cpus = []
        for pid in (resources["pid"], resources["windowserver_pid"]):
            values = []
            for a, b in zip(selected, selected[1:]):
                pa, pb = a["processes"].get(str(pid)), b["processes"].get(str(pid))
                if pa and pb:
                    values.append(100 * (pb["cpu_seconds"] - pa["cpu_seconds"]) / (b["time"] - a["time"]))
            cpus.append(f"{statistics.mean(values):.2f}" if values else "unavailable")
        rss = [s["processes"][str(resources["pid"])]["rss_mb"] for s in selected if str(resources["pid"]) in s["processes"]]
        watts = [s["battery"]["discharge_watts"] for s in selected if s.get("battery", {}).get("discharge_watts") is not None]
        power = f"{statistics.median(watts):.2f} (n={len(watts)})" if len(watts) >= 10 else "unmeasured"
        memory = f"{max(rss):.1f}" if rss else "unavailable"
        lines.append(f"| {phase['name'][6:]} | {cpus[0]} | {cpus[1]} | {memory} | {power} |")
    lines += ["", "Limitations: replay measures capture/startup/render/presentation, not physical HID sensor latency or camera-observed panel latency. Static desktop content may yield fewer capture frames. Short battery samples are noisy and do not establish battery runtime. If plugged in, battery impact is unmeasured. No privileged power counters are collected. Sampling and telemetry add some overhead.", ""]
    (directory / "REPORT.md").write_text("\n".join(lines))
    print("\n".join(lines))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=Path("/Applications/DuoFX.app"))
    parser.add_argument("--output", type=Path, default=ROOT / "build" / f"performance-{time.strftime('%Y%m%d-%H%M%S')}")
    parser.add_argument("--summarize", type=Path, help="Regenerate a report from an existing result directory")
    args = parser.parse_args()
    if args.summarize:
        summarize(args.summarize.resolve())
        return
    app = args.app.resolve()
    executable = app / "Contents/MacOS/DuoFX"
    if not executable.is_file():
        parser.error("Install a Release build with scripts/build-and-install.sh first")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    subprocess.run(["xcrun", "swift", str(ROOT / "scripts/quit-running-app.swift")], check=True)
    env = dict(os.environ, DUOFX_PERFORMANCE_REPORT=str(output / "frames.json"))
    windowserver = subprocess.run(["pgrep", "-x", "WindowServer"], capture_output=True, text=True)
    windowserver_pid = int(windowserver.stdout.splitlines()[0]) if windowserver.stdout.strip() else 0
    samples = []
    print(f"Running 150-second onscreen replay. Pause from DuoFX's menu to end active effects. Output: {output}", flush=True)
    with (output / "app.log").open("w") as log:
        process = subprocess.Popen([str(executable)], env=env, stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 180
            while process.poll() is None and time.monotonic() < deadline:
                samples.append(sample([process.pid] + ([windowserver_pid] if windowserver_pid else [])))
                time.sleep(1)
        finally:
            chip = subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip()
            (output / "resources.json").write_text(json.dumps({"pid": process.pid, "windowserver_pid": windowserver_pid, "chip": chip, "samples": samples}))
            if process.poll() is None:
                subprocess.run(["xcrun", "swift", str(ROOT / "scripts/quit-running-app.swift")], check=True)
            subprocess.run(["open", str(app)], check=True)
    if not (output / "frames.json").exists():
        raise SystemExit(f"No frame report produced. Check {output / 'app.log'} and rebuild the app with performance instrumentation.")
    summarize(output)


if __name__ == "__main__":
    main()
