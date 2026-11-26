import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


pipeline, plan = sys.argv[1:]
cli = [sys.executable, pipeline]
control = Path(".runweld/workflow")
started = control / "started"
suite_starts = control / "suite-starts"
hold = control / "hold"
spawn_nested = control / "spawn-nested"
nested = control / "nested"
state_path = Path(plan).with_suffix(".json")
(control / "controlled-check.py").write_text('''
import os
from pathlib import Path
import subprocess
import sys
import time

control = Path(".runweld/workflow")
if len(sys.argv) > 1:
    (control / "nested").write_text(str(os.getpid()))
    while (control / "hold").exists():
        time.sleep(0.02)
    sys.exit()
with (control / "started").open("a") as log:
    log.write(f"{os.getpid()}\\n")
if (control / "spawn-nested").exists():
    subprocess.Popen([sys.executable, __file__, "nested"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).wait()
while (control / "hold").exists():
    time.sleep(0.02)
''')


def call(*args, code=0):
    result = subprocess.run([*cli, *args, plan], capture_output=True, text=True, timeout=20)
    assert result.returncode == code, (args, result.stdout, result.stderr)
    return result.stdout


def action():
    return json.loads(call("status", "--json"))["workflow"]["actions"][0]


def ready(command):
    retry = wait_for(lambda: step if (step := action())["kind"] == "run" else None)
    assert retry["argv"][2:4] == command.split(), retry
    assert retry["argv"][4] == plan, retry
    return retry["argv"]


def wait_for(predicate):
    end = time.monotonic() + 15
    while time.monotonic() < end:
        if (value := predicate()):
            return value
        time.sleep(0.03)
    raise AssertionError("the check did not reach the expected state")


def pids():
    return list(map(int, started.read_text().splitlines())) if started.exists() else []


def launch(args):
    process = subprocess.Popen(args, start_new_session=True, cwd="/", stdout=subprocess.DEVNULL)
    processes.append(process)
    return process


def complete(args, code=0):
    result = subprocess.run(args, cwd="/", start_new_session=True, capture_output=True, text=True, timeout=20)
    assert result.returncode == code, (args, result.stdout, result.stderr)
    return result.stdout


def state():
    return json.loads(state_path.read_text())


def commit(message):
    subprocess.run(["git", "commit", "-qm", message, "--allow-empty"], check=True)
    return subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()


def kill(process):
    process.kill()
    process.wait(timeout=5)


processes = []
try:
    # build#full-check-recovery: coordinator death does not imply the child stopped.
    hold.touch()
    gate = launch([*cli, "gate", "start", plan])
    child = wait_for(pids)[0]
    assert action()["kind"] == "wait", action()
    kill(gate)
    assert action()["kind"] == "wait", ("the old child is still running", action())
    assert "checks-running" in call("gate", "start", code=1)

    os.kill(child, signal.SIGTERM)
    retry = ready("gate start")
    inventory = subprocess.check_output([*cli, "status", "--json", "--current"], text=True)
    current = json.loads(inventory)[0]["workflow"]["actions"][0]
    assert current == action(), (current, action())
    original = state_path.read_text()
    foreign = state()
    foreign["check_transition"]["host"] = "unobservable process scope"
    state_path.write_text(json.dumps(foreign))
    assert action()["kind"] == "ask" and action()["input"] == "check-ownership", action()
    assert "unobservable process scope" in call("gate", "start", code=1)
    incomplete = state()
    del incomplete["check_transition"]
    incomplete["cycles"][0]["runs"][0]["pid"] = os.getpid()
    state_path.write_text(json.dumps(incomplete))
    assert action()["kind"] == "ask" and "lacks child ownership evidence" in action()["action"], action()
    assert "checks-owner-unknown" in call("gate", "start", code=1)
    state_path.write_text(original)

    first = launch(retry)
    wait_for(lambda: len(pids()) == 2)
    assert "checks-running" in complete(retry, code=1)
    assert len(pids()) == 2, pids()
    hold.unlink()
    assert first.wait(timeout=15) == 0
    assert len(state()["cycles"][0]["runs"]) == 1
    assert len(suite_starts.read_text().splitlines()) == 2
    assert "checks-recovery-stale" in complete(retry, code=1)

    # A descendant which closes inherited descriptors still belongs to the check's process group.
    call("note", "add", "--text", "round work", "--cause", "bug")
    complete([*cli, "note", "edit", plan, "1", "--source", "missed"])
    call("round", "start")
    call("round", "report", "--became", "round work", "--commit", commit("round"))
    hold.touch()
    spawn_nested.touch()
    round_process = launch([*cli, "round", "done", plan])
    worker = int(wait_for(lambda: nested.read_text() if nested.exists() else None))
    kill(round_process)
    os.kill(pids()[-1], signal.SIGTERM)
    descendant = wait_for(lambda: step if "process group" in (step := action())["action"] else None)
    assert descendant["kind"] == "wait", ("the descendant still owns the round check", descendant)
    assert "checks-running" in call("gate", "start", code=1)
    os.kill(worker, signal.SIGTERM)
    retry = ready("round done")
    assert "round done" in call("gate", "start", code=1)
    hold.unlink()
    spawn_nested.unlink()
    assert "round 1 done" in complete(retry)
    assert state()["rounds"][0]["done"]

    # A finished result can close its original fix in a round without another suite.
    call("finding", "--kind", "defect", "--where", "src/start:1", "--source", "plan", "--text", "fix in a round")
    call("fix", "start")
    call("fix", "report", "--became", "fix work", "--commit", commit("fix"))
    hold.touch()
    fix_process = launch([*cli, "fix", "done", plan])
    wait_for(lambda: len(pids()) == 5)
    kill(fix_process)
    assert action()["kind"] == "wait", action()
    os.kill(pids()[-1], signal.SIGTERM)
    retry = ready("fix done")
    assert action()["check"] == {"command": "fix done", "cycle": "round-1", "target": 1}
    assert "fix done" in call("round", "done", code=1)
    assert "fix done" in call("brief", "judge", code=1)
    hold.unlink()

    marker = control.resolve() / "checks-finished"
    pause_at_close = '''
import runpy, sys, time
from pathlib import Path

pipeline, marker = sys.argv[1:3]
sys.argv = [pipeline, *sys.argv[3:]]
# run_path on a source file omits the script directory that direct execution adds.
sys.path.insert(0, str(Path(pipeline).resolve().parent))
namespace = runpy.run_path(pipeline)["main"].__globals__
run_checks = namespace["run_checks"]
def paused(*args):
    result = run_checks(*args)
    Path(marker).touch()
    time.sleep(30)
    return result
namespace["run_checks"] = paused
sys.exit(namespace["main"]())
'''
    finishing = launch([sys.executable, "-c", pause_at_close, pipeline, str(marker), *retry[2:]])
    wait_for(marker.exists)
    assert state()["cycles"][-1]["runs"][-1]["done"]
    assert state()["cycles"][-1]["fixes"][0]["done"] is None
    kill(finishing)
    assert ready("fix done") == retry
    assert "reused" in complete(retry)
    assert len(pids()) == 6, pids()
    assert len(suite_starts.read_text().splitlines()) == 6
    assert state()["cycles"][-1]["fixes"][0]["done"]
    assert "checks-recovery-stale" in complete(retry, code=1)
finally:
    hold.unlink(missing_ok=True)
    for process in processes:
        if process.poll() is None:
            kill(process)
