import json
import os
import urllib.request
import urllib.error
from datetime import datetime, timezone

import boto3


secretsmanager = boto3.client("secretsmanager")

_SECRET_CACHE = None


def get_teams_webhook_url():
    global _SECRET_CACHE

    if _SECRET_CACHE:
        return _SECRET_CACHE["WEBHOOK_URL"]

    secret_name = os.environ["TEAMS_WEBHOOK_SECRET_NAME"]

    response = secretsmanager.get_secret_value(SecretId=secret_name)
    secret_string = response["SecretString"]

    _SECRET_CACHE = json.loads(secret_string)
    return _SECRET_CACHE["WEBHOOK_URL"]


def parse_sns_message(record):
    sns = record.get("Sns", {})
    message = sns.get("Message", "{}")

    try:
        parsed = json.loads(message)
        if isinstance(parsed, dict):
            return parsed
    except json.JSONDecodeError:
        pass

    return {
        "AlarmName": sns.get("Subject", "SNS Notification"),
        "NewStateValue": "UNKNOWN",
        "NewStateReason": message,
        "Region": os.environ.get("AWS_REGION", "unknown"),
    }


def build_teams_card(alarm):
    alarm_name = alarm.get("AlarmName", "Unknown Alarm")
    new_state = alarm.get("NewStateValue", "UNKNOWN")
    old_state = alarm.get("OldStateValue", "-")
    reason = alarm.get("NewStateReason", "-")
    region = alarm.get("Region", os.environ.get("AWS_REGION", "-"))
    account_id = alarm.get("AWSAccountId", "-")
    state_change_time = alarm.get("StateChangeTime", "-")

    severity = "attention" if new_state == "ALARM" else "good"

    title = f"🚨 CloudWatch Alarm: {alarm_name}" if new_state == "ALARM" else f"✅ CloudWatch Alarm: {alarm_name}"

    return {
        "type": "message",
        "attachments": [
            {
                "contentType": "application/vnd.microsoft.card.adaptive",
                "content": {
                    "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
                    "type": "AdaptiveCard",
                    "version": "1.4",
                    "body": [
                        {
                            "type": "TextBlock",
                            "text": title,
                            "weight": "Bolder",
                            "size": "Large",
                            "wrap": True,
                        },
                        {
                            "type": "FactSet",
                            "facts": [
                                {"title": "State", "value": new_state},
                                {"title": "Previous", "value": old_state},
                                {"title": "Region", "value": region},
                                {"title": "Account", "value": account_id},
                                {"title": "Changed At", "value": state_change_time},
                            ],
                        },
                        {
                            "type": "TextBlock",
                            "text": "Reason",
                            "weight": "Bolder",
                            "spacing": "Medium",
                        },
                        {
                            "type": "TextBlock",
                            "text": reason,
                            "wrap": True,
                            "color": severity,
                        },
                        {
                            "type": "TextBlock",
                            "text": f"Generated at {datetime.now(timezone.utc).isoformat()}",
                            "isSubtle": True,
                            "size": "Small",
                            "spacing": "Medium",
                        },
                    ],
                },
            }
        ],
    }


def post_to_teams(payload):
    webhook_url = get_teams_webhook_url()

    data = json.dumps(payload).encode("utf-8")

    request = urllib.request.Request(
        webhook_url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            body = response.read().decode("utf-8")
            return {
                "status_code": response.status,
                "body": body,
            }
    except urllib.error.HTTPError as exc:
        error_body = exc.read().decode("utf-8")
        raise RuntimeError(f"Teams webhook failed: status={exc.code}, body={error_body}") from exc


def lambda_handler(event, context):
    print(json.dumps({"event": event}, ensure_ascii=False))

    results = []

    for record in event.get("Records", []):
        alarm = parse_sns_message(record)
        teams_payload = build_teams_card(alarm)
        result = post_to_teams(teams_payload)

        results.append({
            "alarm_name": alarm.get("AlarmName"),
            "teams_response": result,
        })

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Teams notification sent",
            "results": results,
        }),
    }
