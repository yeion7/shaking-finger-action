#!/bin/bash
set -e
set -o pipefail

if [[ -z "$GITHUB_TOKEN" ]]; then
	echo "Set the GITHUB_TOKEN env variable."
	exit 1
fi

if [[ -z "$GITHUB_REPOSITORY" ]]; then
	echo "Set the GITHUB_REPOSITORY env variable."
	exit 1
fi

URI=https://api.github.com
API_VERSION=v3
API_HEADER="Accept: application/vnd.github.${API_VERSION}+json; application/vnd.github.antiope-preview+json"
AUTH_HEADER="Authorization: token ${GITHUB_TOKEN}"

GIF_URL=https://github.com/jessfraz/shaking-finger-action/raw/master/finger.gif

delete_comment_if_exists() {
	# Get all the comments for the pull request.
	body=$(curl -sSL -H "${AUTH_HEADER}" -H "${API_HEADER}" "${URI}/repos/${GITHUB_REPOSITORY}/issues/${NUMBER}/comments")

	comments=$(echo "$body" | jq --raw-output '.[] | {id: .id, body: .body} | @base64')

	for c in $comments; do
		comment="$(echo "$c" | base64 --decode)"
		id=$(echo "$comment" | jq --raw-output '.id')
		b=$(echo "$comment" | jq --raw-output '.body')

		if [[ "$b" == *"Deployed:"* ]]; then
			# We have found our comment.
			# Delete it.

			echo "Deleting old comment ID: $id"
			curl -sSL -H "${AUTH_HEADER}" -H "${API_HEADER}" -X DELETE "${URI}/repos/${GITHUB_REPOSITORY}/issues/comments/${id}"
		fi
	done
}

post_gif() {
	MESSAGE=`cat $HOME/url.txt`
	curl -sSL -H "${AUTH_HEADER}" -H "${API_HEADER}" -d '{"body":"Deployed: [Abrir]('${MESSAGE}')"}' -H "Content-Type: application/json" -X POST "${URI}/repos/${GITHUB_REPOSITORY}/issues/${NUMBER}/comments"
}

get_checks() {
	# Get all the checks for the sha.
	body=$(curl -sSL -H "${AUTH_HEADER}" -H "${API_HEADER}" "${URI}/repos/${GITHUB_REPOSITORY}/commits/${GITHUB_SHA}/check-runs")

	checks=$(echo "$body" | jq --raw-output '.check_runs | .[] | {name: .name, status: .status, conclusion: .conclusion} | @base64')

	IN_PROGRESS=0
	for c in $checks; do
		check="$(echo "$c" | base64 --decode)"
		name=$(echo "$check" | jq --raw-output '.name')
		state=$(echo "$check" | jq --raw-output '.status')
		conclusion=$(echo "$check" | jq --raw-output '.conclusion')

		if [[ "$GITHUB_ACTION" == "$name" ]]; then
			# Continue if it's us.
			continue
		fi

		if [[ "$state" == "in_progress" ]]; then
			# Continue if it's in progress.
			IN_PROGRESS=1
			continue
		fi

		if [[ "$state" == "completed" ]] && [[ "$conclusion" == "failure" ]]; then
			echo "Check: $name failed. Posting gif..."

			delete_comment_if_exists;
			post_gif;

			exit 0
		fi
	done

	# If we got in progress checks then sleep and loop again.
	if [[ "$IN_PROGRESS" == "1" ]]; then
		echo "In progress loop. Sleeping..."
		sleep 2

		get_checks;
	fi

	# We made it to the end and nothing failed so let's delete the comment if it
	# exists.
	delete_comment_if_exists;
}

main() {
	# Validate the GitHub token.
	curl -o /dev/null -sSL -H "${AUTH_HEADER}" -H "${API_HEADER}" "${URI}/repos/${GITHUB_REPOSITORY}" || { echo "Error: Invalid repo, token or network issue!";  exit 1; }

	# Get the check run action.
	action=$(jq --raw-output .action "$GITHUB_EVENT_PATH")

	# If it's not synchronize or opened event return early.
	if [[ "$action" != "synchronize" ]] && [[ "$action" != "opened" ]]; then
		# Return early we only care about synchronize or opened.
		echo "Check run has action: $action"
		echo "Want: synchronize or opened"
		exit 0
	fi

	# Get the pull request number.
	NUMBER=$(jq --raw-output .number "$GITHUB_EVENT_PATH")

	echo "running $GITHUB_ACTION for PR #${NUMBER}"

	get_checks;
}

main
