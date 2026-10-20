#!/usr/bin/env python3
"""Opens and closes the AppFinder panel over the test fixture many times and checks the input
source every round (see CLAUDE.md, "Input source check").

Usage: scripts/check-input-source.py [--rounds N] [--source ID] [--focus-lost]

Needs the Debug AppFinder running (scripts/build.sh debug, then open build/AppFinder.app) and
builds/launches build/AppFinderFixture.app itself. Every round:

  1. the fixture is frontmost with its text view focused and the source under test selected;
  2. panel.show (the hotkey's code path), then the panel must be key, the selected source ABC,
     and a probe typed into the search field must not be composed by an input method;
  3. panel.hide (Esc's code path), or with --focus-lost the fixture is activated while the panel
     is open, as a click elsewhere would;
  4. a probe typed into the fixture right away must be composed by the source under test, and
     the fixture's own input context and TIS must report it.

Prints one line per failed round and a summary; exit code 0 only when every round passed.
"""

import argparse
import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CTL = os.path.join(ROOT, ".build", "debug", "appfinderctl")
FIXTURE = os.path.join(ROOT, "build", "AppFinderFixture.app")
ABC = "com.apple.keylayout.ABC"
INKFLOW = "io.damao.inputmethod.inkflow.Hans"


def call(target, command, params=None):
    args = [CTL, target, command]
    if params is not None:
        args.append(json.dumps(params))
    out = subprocess.run(args, capture_output=True, text=True, timeout=20)
    if out.returncode != 0:
        raise RuntimeError(f"{target} {command}: {out.stdout.strip() or out.stderr.strip()}")
    return json.loads(out.stdout)["result"]


def frontmost_is_fixture():
    out = subprocess.run(["lsappinfo", "info", "-only", "bundleid", subprocess.run(
        ["lsappinfo", "front"], capture_output=True, text=True).stdout.strip()], capture_output=True, text=True)
    return "io.damao.appfinder.fixture" in out.stdout


def focus_fixture(source):
    for _ in range(20):
        subprocess.run(["open", FIXTURE])
        state = call("fixture", "focus")
        if state["active"] and state["key"] and state["textFocused"] and frontmost_is_fixture():
            if state["contextSource"] != source:
                call("fixture", "select", {"id": source})
                time.sleep(0.2)
            return True
        time.sleep(0.25)
    return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rounds", type=int, default=50)
    parser.add_argument("--source", default=INKFLOW)
    parser.add_argument("--focus-lost", action="store_true")
    args = parser.parse_args()

    if not os.path.exists(CTL):
        subprocess.run(["swift", "build", "--product", "appfinderctl"], cwd=ROOT, check=True)
    call("app", "status")
    subprocess.run(["open", FIXTURE])
    for _ in range(50):
        try:
            call("fixture", "state")
            break
        except RuntimeError:
            time.sleep(0.1)

    if not focus_fixture(args.source):
        sys.exit("cannot bring the fixture to the front")
    baseline = call("fixture", "probe")
    expect_composed = args.source != ABC
    if baseline["composed"] != expect_composed:
        sys.exit(f"baseline probe in the fixture: composed={baseline['composed']}, expected {expect_composed}")

    failures = []
    refocused = 0
    open_ms = []
    close_ms = []
    not_lost = 0
    for round_number in range(1, args.rounds + 1):
        if call("app", "panel.state")["open"]:
            call("app", "panel.hide")
        state = call("fixture", "state")
        if not (state["active"] and state["key"] and frontmost_is_fixture()) or state["contextSource"] != args.source:
            refocused += 1
            if not focus_fixture(args.source):
                failures.append((round_number, "cannot bring the fixture to the front"))
                continue

        shown = call("app", "panel.show")
        open_ms.append(shown["lastOpen"]["visibleMs"])
        problems = []
        if not shown["key"]:
            problems.append("panel not key")
        if shown["inputSource"] != ABC:
            problems.append(f"open: source {shown['inputSource']}")
        probe = call("app", "panel.probe")
        if probe.get("composed") is not False:
            problems.append(f"open: field probe {probe}")

        if args.focus_lost:
            subprocess.run(["open", FIXTURE])
            call("fixture", "focus")
            for _ in range(200):
                if not call("app", "panel.state")["open"] and call("fixture", "state")["key"]:
                    break
                time.sleep(0.01)
            closed = call("app", "panel.state")
            if closed["open"]:
                # The fixture did not take the focus from the panel: a setup problem, not a result.
                not_lost += 1
                call("app", "panel.hide")
                continue
        else:
            closed = call("app", "panel.hide")
        close_ms.append(closed["lastClose"].get("ms", 0))

        after = call("fixture", "probe")
        if after["composed"] != expect_composed:
            problems.append(f"close: fixture probe composed={after['composed']}")
        if after["contextSource"] != args.source:
            problems.append(f"close: fixture context {after['contextSource']}")
        if after["tis"] != args.source:
            problems.append(f"close: TIS {after['tis']}")
        if not after["key"]:
            problems.append("close: fixture not key")
        if problems:
            failures.append((round_number, "; ".join(problems) + f" (lastClose {closed['lastClose']})"))
            print(f"round {round_number}: " + failures[-1][1], flush=True)

    def stats(values):
        values = sorted(values)
        if not values:
            return "-"
        return f"median {values[len(values) // 2]:.1f} ms, max {values[-1]:.1f} ms"

    mode = "focus lost" if args.focus_lost else "Esc"
    print(f"{args.rounds} rounds ({mode}, source {args.source}): {len(failures)} failed, "
          f"fixture refocused {refocused} times, focus not taken {not_lost} times; panel visible after {stats(open_ms)}; close took {stats(close_ms)}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
