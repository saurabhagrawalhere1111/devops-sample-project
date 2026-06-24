"""
NotesOps AI incident-triage agent.

Receives Alertmanager webhooks, asks Claude (on Amazon Bedrock) for a
root-cause hypothesis + suggested remediation, and posts the summary to Slack.

Auth to Bedrock is via IRSA (the 'ai-agent' ServiceAccount in the 'aiops'
namespace, see infra/terraform/irsa.tf) — no static AWS keys.
"""
import json
import logging
import os
import urllib.request

import boto3
from fastapi import FastAPI, Request

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("ai-agent")

# Bedrock uses provider-prefixed model IDs. The "us." inference-profile prefix
# is required for cross-region on-demand throughput in most accounts; drop it to
# "anthropic.claude-opus-4-8" if you've enabled the bare model in your region.
MODEL_ID = os.getenv("BEDROCK_MODEL_ID", "us.anthropic.claude-opus-4-8")
REGION = os.getenv("AWS_REGION", "us-east-1")
SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL", "")

app = FastAPI(title="notesops-ai-agent")
bedrock = boto3.client("bedrock-runtime", region_name=REGION)

SYSTEM_PROMPT = (
    "You are an SRE incident-triage assistant for a Kubernetes platform "
    "(NotesOps: a Django + React app on Amazon EKS, observed with Prometheus, "
    "Loki, and Tempo). Given a Prometheus/Alertmanager alert, produce a concise "
    "triage note: (1) one-line summary, (2) most likely root cause, (3) the "
    "single highest-value next diagnostic step (a kubectl/PromQL/LogQL command), "
    "and (4) a safe, reversible remediation suggestion. Be specific and brief. "
    "If you are uncertain, say so rather than guessing."
)


def ask_claude(alert_text: str) -> str:
    body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 1024,
        "system": SYSTEM_PROMPT,
        "messages": [{"role": "user", "content": alert_text}],
    }
    resp = bedrock.invoke_model(modelId=MODEL_ID, body=json.dumps(body))
    payload = json.loads(resp["body"].read())
    # Messages API response: content is a list of blocks; take the text blocks.
    return "".join(b.get("text", "") for b in payload.get("content", []) if b.get("type") == "text")


def post_to_slack(text: str) -> None:
    if not SLACK_WEBHOOK_URL:
        log.warning("SLACK_WEBHOOK_URL not set; printing instead:\n%s", text)
        return
    req = urllib.request.Request(
        SLACK_WEBHOOK_URL,
        data=json.dumps({"text": text}).encode(),
        headers={"Content-Type": "application/json"},
    )
    urllib.request.urlopen(req, timeout=10)  # noqa: S310 - trusted Slack URL


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.post("/alert")
async def alert(request: Request):
    """Alertmanager webhook receiver."""
    data = await request.json()
    for a in data.get("alerts", []):
        if a.get("status") == "resolved":
            continue
        labels = a.get("labels", {})
        annotations = a.get("annotations", {})
        alert_text = (
            f"Alert: {labels.get('alertname')}\n"
            f"Severity: {labels.get('severity')}\n"
            f"Namespace: {labels.get('namespace')}\n"
            f"Pod: {labels.get('pod')}\n"
            f"Description: {annotations.get('description')}\n"
        )
        try:
            triage = ask_claude(alert_text)
            post_to_slack(f":robot_face: *AI triage — {labels.get('alertname')}*\n{triage}")
        except Exception:  # noqa: BLE001 - never let triage crash the webhook
            log.exception("triage failed for alert %s", labels.get("alertname"))
    return {"received": len(data.get("alerts", []))}
