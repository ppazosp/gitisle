"""Run one development check with a log, result artifact, and stale-output watchdog."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument("name")
parser.add_argument("command", nargs=argparse.REMAINDER)
arguments = parser.parse_args()
directory = Path(".artifacts")
directory.mkdir(exist_ok=True)
log_path = directory / (arguments.name + ".log")
result_path = directory / (arguments.name + ".json")
started = time.monotonic()
reason = None
with log_path.open("w") as log:
    log.write("Command: " + " ".join(arguments.command) + "\n")
    log.flush()
    process = subprocess.Popen(arguments.command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    print(json.dumps({"pid": process.pid, "log": str(log_path), "result": str(result_path)}), flush=True)
    while process.poll() is None:
        if time.monotonic() - started > 1200:
            reason = "duration_limit"
        elif time.time() - log_path.stat().st_mtime > 300:
            reason = "stale_output"
        if reason:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
            break
        time.sleep(1)
    code = process.wait()
result = {"exit_code": code, "watchdog": reason, "elapsed_seconds": round(time.monotonic() - started, 1), "command": arguments.command}
result_path.write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result), flush=True)
raise SystemExit(code if code >= 0 else 1)
