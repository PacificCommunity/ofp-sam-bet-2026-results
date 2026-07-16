#!/usr/bin/env python3
"""Submit the 36-model BET LF sensitivity Results job to Kflow."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request


RESULTS_TASK = "ofp-sam-bet-2026-results"
HESSIAN_MERGE_TASK = (
    "ofp-sam-bet-2026-lf-conflict-sensitivities-standalone-"
    "check-hessian-merge"
)
FIT_TASK = "ofp-sam-bet-2026-lf-conflict-sensitivities-standalone"


def expected_scenarios() -> list[str]:
    scenarios: list[str] = []
    number = 1
    for divisor in (1, 10, 100):
        for cutoff in ("NOCUT", "CUT100", "CUT70"):
            for compression in (0, 1, 3, 5):
                scenarios.append(
                    f"S{number:03d}-TC{compression}-{cutoff}-DW{divisor}"
                )
                number += 1
    return scenarios


class KflowAPI:
    def __init__(self, base_url: str, token: str, github_token: str = "") -> None:
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.github_token = github_token.strip()

    def request(self, method: str, path: str, payload: dict | None = None) -> dict:
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json",
        }
        if self.github_token:
            headers["X-GitHub-Token"] = self.github_token
        request = urllib.request.Request(
            f"{self.base_url}{path}",
            data=body,
            method=method,
            headers=headers,
        )
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"Kflow API {error.code}: {detail}") from error

    def task_jobs(self, task: str) -> list[dict]:
        jobs: list[dict] = []
        page = 1
        while True:
            response = self.request("GET", f"/api/jobs/{task}?page={page}")
            batch = response.get("jobs", [])
            if not batch:
                break
            jobs.extend(batch)
            page += 1
        return jobs


def completed_hessian_merges(api: KflowAPI) -> tuple[list[int], dict[str, dict]]:
    expected = expected_scenarios()
    latest: dict[str, dict] = {}
    observed: dict[str, list[dict]] = {}
    for job in api.task_jobs(HESSIAN_MERGE_TASK):
        model = str((job.get("tags") or {}).get("model") or "").strip()
        if model not in expected:
            continue
        observed.setdefault(model, []).append(job)
        if job.get("status") != "completed":
            continue
        previous = latest.get(model)
        if previous is None or int(job["job_number"]) > int(previous["job_number"]):
            latest[model] = job

    missing = [model for model in expected if model not in latest]
    if missing:
        details = []
        for model in missing:
            statuses = sorted(
                {
                    f"#{job.get('job_number')}={job.get('status')}"
                    for job in observed.get(model, [])
                }
            )
            details.append(f"{model}: {', '.join(statuses) or 'not found'}")
        raise RuntimeError(
            "Results submission requires 36 completed Hessian merge jobs. "
            "Incomplete inputs: " + "; ".join(details)
        )

    job_numbers = [int(latest[model]["job_number"]) for model in expected]
    if len(job_numbers) != 36 or len(set(job_numbers)) != 36:
        raise RuntimeError("Expected 36 unique Hessian merge jobs.")
    return job_numbers, latest


def submission_payload(job_numbers: list[int], latest: dict[str, dict]) -> dict:
    flow_group = "bet-2026-lf-conflict-sensitivity-results"
    model_jobs = {
        model: int(latest[model]["job_number"]) for model in expected_scenarios()
    }
    return {
        "branch": "main",
        "remote_user": os.environ.get("KFLOW_REMOTE_USER", "kyuhank"),
        "remote_host": os.environ.get(
            "KFLOW_REMOTE_HOST", "suvofpsubmit.corp.spc.int"
        ),
        "remote_base_dir": os.environ.get(
            "KFLOW_REMOTE_BASE_DIR", "/home/kyuhank/KflowOutput"
        ),
        "disk": "60GB",
        "input_jobs": job_numbers,
        "output_patterns": ["outputs/**"],
        "env": {
            "FLOW_SPECIES": "BET",
            "FLOW_SPECIES_LABEL": "bigeye tuna",
            "FLOW_ASSESSMENT_YEAR": "2026",
            "FLOW_GROUP": flow_group,
            "PLOT_TITLE": "BET 2026 LF conflict sensitivity results",
            "MFCLSHINY_INTERACTIVE_VIEWER_TITLE": (
                "BET 2026 LF conflict sensitivity viewer"
            ),
            "MFCLSHINY_INTERACTIVE_FIT_MODEL_LIMIT": "4",
            "LF_SENSITIVITY_EXPECTED_MODELS": "36",
            "PLOT_RENDER_REVIEW_HTML": "false",
            "RESULTS_VIEWER_ONLY": "true",
            "KFLOW_JOB_TITLE": "BET 2026 LF conflict sensitivity results",
            "KFLOW_JOB_DESCRIPTION": (
                "Aggregate 36 completed LF sensitivity models with merged "
                "Hessian diagnostics and build the interactive Results viewer."
            ),
            "KFLOW_JOB_KEY": "lf-conflict-sensitivity-results",
            "KFLOW_FORWARD_GITHUB_TOKEN_TO_RUNTIME": "true",
            "KFLOW_RUNTIME_GITHUB_AUTH": "true",
            "TRIGGER_NEXT": "false",
        },
        "tags": {
            "flow": flow_group,
            "species": "BET",
            "stage": "results",
            "experiment": "lf-conflict-sensitivities",
            "model_count": "36",
        },
        "metadata": {
            "allow_failed_input_jobs": False,
            "input_jobs_override": True,
            "interactive_viewer": True,
            "hessian_summary": True,
            "model_count": 36,
            "source_fit_task": FIT_TASK,
            "source_hessian_merge_task": HESSIAN_MERGE_TASK,
            "hessian_merge_jobs": model_jobs,
            "job_title": "BET 2026 LF conflict sensitivity results",
            "job_description": (
                "One completed Hessian merge bundle per LF sensitivity model."
            ),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--api-url",
        default=os.environ.get("KFLOW_API_URL", "http://127.0.0.1:8089"),
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    token = os.environ.get("KFLOW_API_TOKEN", "").strip()
    if not token:
        raise RuntimeError("KFLOW_API_TOKEN is required.")

    api = KflowAPI(
        args.api_url,
        token,
        github_token=os.environ.get("KFLOW_GITHUB_TOKEN", ""),
    )
    job_numbers, latest = completed_hessian_merges(api)
    payload = submission_payload(job_numbers, latest)
    print(
        f"Validated {len(job_numbers)} completed Hessian merge inputs: "
        f"#{min(job_numbers)} to #{max(job_numbers)}"
    )
    if args.dry_run:
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0

    response = api.request("POST", f"/api/job/{RESULTS_TASK}", payload)
    job = response.get("job", response)
    print(
        "Submitted Results job "
        f"#{job.get('job_number')} ({job.get('status')}) to "
        f"{job.get('remote_host')}."
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, urllib.error.URLError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
