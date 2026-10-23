#!/usr/bin/env bash
# Move this issue's card on the project board. Usage: board-status.sh working|review|human|done
# Reads the board from factory/config.json in the current directory.
# Needs ISSUE and FACTORY_BOARD_TOKEN in the environment. Never fails the job.
set -u
KEY="$1"
CFG=factory/config.json
OWNER=$(jq -r .board.owner "$CFG"); NUM=$(jq -r .board.number "$CFG"); REPO=$(jq -r .board.repo "$CFG")
STATUS=$(jq -r ".board.statuses.$KEY" "$CFG")
export GH_TOKEN="$FACTORY_BOARD_TOKEN"
PID=$(gh project view "$NUM" --owner "$OWNER" --format json --jq .id) || exit 0
FIELD=$(gh project field-list "$NUM" --owner "$OWNER" --format json --jq '.fields[]|select(.name=="Status")') || exit 0
FID=$(echo "$FIELD" | jq -r .id)
OPT=$(echo "$FIELD" | jq -r --arg s "$STATUS" '.options[]|select(.name==$s)|.id')
ITEM=$(gh project item-list "$NUM" --owner "$OWNER" --limit 200 --format json --jq ".items[]|select(.content.number==$ISSUE and .content.repository==\"$REPO\")|.id")
if [ -z "$ITEM" ] && [ "$KEY" != done ]; then
  ITEM=$(gh project item-add "$NUM" --owner "$OWNER" --url "https://github.com/$REPO/issues/$ISSUE" --format json --jq .id) || exit 0
fi
[ -z "$ITEM" ] && exit 0
gh project item-edit --id "$ITEM" --project-id "$PID" --field-id "$FID" --single-select-option-id "$OPT" >/dev/null \
  && echo "Board: #$ISSUE -> $STATUS" || echo "Board update failed (ignored)"
exit 0
