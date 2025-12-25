#!/bin/bash

REPORT_FILE="github_repos.txt"
GITHUB_USER="deepikasri674"
GITHUB_TOKEN=${GITHUB_TOKEN}
#GITHUB_TOKEN="$TOKEN_GITHUB"

echo "================ GITHUB REPOSITORIES =================" > "$REPORT_FILE"

# Use token if available (private + public repos)
if [ -n "$GITHUB_TOKEN" ]; then
    GITHUB_API="https://api.github.com/user/repos?per_page=100&sort=updated&affiliation=owner"
    REPOS_JSON=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$GITHUB_API")
else
    GITHUB_API="https://api.github.com/users/${GITHUB_USER}/repos?per_page=100&sort=updated"
    REPOS_JSON=$(curl -s "$GITHUB_API")
fi

if [ $? -eq 0 ] && [ -n "$REPOS_JSON" ]; then

    TOTAL_REPOS=$(echo "$REPOS_JSON" | jq '. | length' 2>/dev/null)

    if [ -n "$TOTAL_REPOS" ] && [ "$TOTAL_REPOS" -gt 0 ]; then

        echo "GitHub User : ${GITHUB_USER}" >> "$REPORT_FILE"
        echo "Total Repos : ${TOTAL_REPOS}" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"

        printf "%-35s %-20s %-15s\n" \
        "Repository Name" "Last Updated" "Visibility" >> "$REPORT_FILE"

        echo "------------------------------------------------------------------------" >> "$REPORT_FILE"

        echo "$REPOS_JSON" | jq -r '.[] | "\(.name)|\(.updated_at)|\(.private)"' |
        while IFS='|' read -r name updated private; do

            UPDATED_DATE=$(date -d "$updated" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$updated")

            if [ "$private" = "true" ]; then
                VISIBILITY="Private 🔒"
            else
                VISIBILITY="Public ✅"
            fi

            printf "%-35s %-20s %-15s\n" \
            "$name" "$UPDATED_DATE" "$VISIBILITY" >> "$REPORT_FILE"
        done
    else
        echo "No repositories found ⚠️" >> "$REPORT_FILE"
    fi
else
    echo "Failed to fetch GitHub repos ⚠️" >> "$REPORT_FILE"
fi

echo "" >> "$REPORT_FILE"

