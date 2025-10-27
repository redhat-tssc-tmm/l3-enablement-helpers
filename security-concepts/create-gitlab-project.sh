#!/bin/bash

set -e

echo "Creating GitLab Group 'l3-students' and Project 'signing-and-verification'"
echo "=========================================================================="
echo ""

# Get GitLab route URL
echo "Retrieving GitLab route URL..."
GITLAB_HOST=$(oc get route gitlab -n gitlab -o jsonpath='{.spec.host}')
if [ -z "$GITLAB_HOST" ]; then
    echo "Error: Could not extract GitLab route URL"
    exit 1
fi
echo "GitLab Host: $GITLAB_HOST"
GITLAB_URL="https://$GITLAB_HOST"
echo "GitLab URL: $GITLAB_URL"

# Extract GitLab root token from secret
echo "Retrieving GitLab root personal access token from secret..."
GITLAB_TOKEN=$(oc get secret root-user-personal-token -n gitlab -o jsonpath='{.data.token}' | base64 -d)
if [ -z "$GITLAB_TOKEN" ]; then
    echo "Error: Could not extract token from secret"
    exit 1
fi
echo "GitLab Token: [REDACTED]"
echo ""

# Create group 'l3-students'
echo "Creating group 'l3-students'..."
GROUP_RESPONSE=$(curl -k -X POST \
    -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"name": "l3-students", "path": "l3-students", "visibility": "public"}' \
    "$GITLAB_URL/api/v4/groups" \
    -w "\n%{http_code}" \
    -s)

GROUP_HTTP_CODE=$(echo "$GROUP_RESPONSE" | tail -n1)
GROUP_RESPONSE_BODY=$(echo "$GROUP_RESPONSE" | sed '$d')

if [ "$GROUP_HTTP_CODE" -eq 201 ]; then
    echo "Group 'l3-students' created successfully"
    GROUP_ID=$(echo "$GROUP_RESPONSE_BODY" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
    echo "Group ID: $GROUP_ID"
elif [ "$GROUP_HTTP_CODE" -eq 400 ] && echo "$GROUP_RESPONSE_BODY" | grep -q "has already been taken"; then
    echo "Group 'l3-students' already exists, retrieving group ID..."
    # Get existing group ID
    GROUP_INFO=$(curl -k -X GET \
        -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "$GITLAB_URL/api/v4/groups/l3-students" \
        -s)
    GROUP_ID=$(echo "$GROUP_INFO" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
    echo "Group ID: $GROUP_ID"
else
    echo "Error: Failed to create group (HTTP $GROUP_HTTP_CODE)"
    echo "Response: $GROUP_RESPONSE_BODY"
    exit 1
fi

if [ -z "$GROUP_ID" ]; then
    echo "Error: Could not determine group ID"
    exit 1
fi

echo ""

# Get user IDs for user1 and root
echo "Retrieving user IDs..."

# Get user1 ID
USER1_INFO=$(curl -k -X GET \
    -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "$GITLAB_URL/api/v4/users?username=user1" \
    -s)
USER1_ID=$(echo "$USER1_INFO" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)

if [ -z "$USER1_ID" ]; then
    echo "Warning: Could not find user 'user1', skipping..."
else
    echo "User 'user1' ID: $USER1_ID"
fi

# Get root ID
ROOT_INFO=$(curl -k -X GET \
    -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "$GITLAB_URL/api/v4/users?username=root" \
    -s)
ROOT_ID=$(echo "$ROOT_INFO" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)

if [ -z "$ROOT_ID" ]; then
    echo "Warning: Could not find user 'root', skipping..."
else
    echo "User 'root' ID: $ROOT_ID"
fi

echo ""

# Add user1 to group as Developer (access_level: 30)
if [ -n "$USER1_ID" ]; then
    echo "Adding user1 to group 'l3-students'..."
    USER1_MEMBER_RESPONSE=$(curl -k -X POST \
        -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"user_id\": $USER1_ID, \"access_level\": 30}" \
        "$GITLAB_URL/api/v4/groups/$GROUP_ID/members" \
        -w "\n%{http_code}" \
        -s)

    USER1_HTTP_CODE=$(echo "$USER1_MEMBER_RESPONSE" | tail -n1)

    if [ "$USER1_HTTP_CODE" -eq 201 ]; then
        echo "User 'user1' added to group successfully"
    elif [ "$USER1_HTTP_CODE" -eq 409 ]; then
        echo "User 'user1' is already a member of the group"
    else
        echo "Warning: Failed to add user1 to group (HTTP $USER1_HTTP_CODE)"
    fi
fi

# Add root to group as Owner (access_level: 50)
if [ -n "$ROOT_ID" ]; then
    echo "Adding root to group 'l3-students'..."
    ROOT_MEMBER_RESPONSE=$(curl -k -X POST \
        -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"user_id\": $ROOT_ID, \"access_level\": 50}" \
        "$GITLAB_URL/api/v4/groups/$GROUP_ID/members" \
        -w "\n%{http_code}" \
        -s)

    ROOT_HTTP_CODE=$(echo "$ROOT_MEMBER_RESPONSE" | tail -n1)

    if [ "$ROOT_HTTP_CODE" -eq 201 ]; then
        echo "User 'root' added to group successfully"
    elif [ "$ROOT_HTTP_CODE" -eq 409 ]; then
        echo "User 'root' is already a member of the group"
    else
        echo "Warning: Failed to add root to group (HTTP $ROOT_HTTP_CODE)"
    fi
fi

echo ""

# Create project 'signing-and-verification' in the group
echo "Creating project 'signing-and-verification' in group 'l3-students'..."
PROJECT_RESPONSE=$(curl -k -X POST \
    -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"signing-and-verification\", \"namespace_id\": $GROUP_ID, \"visibility\": \"public\"}" \
    "$GITLAB_URL/api/v4/projects" \
    -w "\n%{http_code}" \
    -s)

PROJECT_HTTP_CODE=$(echo "$PROJECT_RESPONSE" | tail -n1)
PROJECT_RESPONSE_BODY=$(echo "$PROJECT_RESPONSE" | sed '$d')

if [ "$PROJECT_HTTP_CODE" -eq 201 ]; then
    echo "Project 'signing-and-verification' created successfully"
elif [ "$PROJECT_HTTP_CODE" -eq 400 ] && echo "$PROJECT_RESPONSE_BODY" | grep -q "has already been taken"; then
    echo "Project 'signing-and-verification' already exists in group"
else
    echo "Error: Failed to create project (HTTP $PROJECT_HTTP_CODE)"
    echo "Response: $PROJECT_RESPONSE_BODY"
    exit 1
fi

echo ""
echo "================================"
echo "Success!"
echo "================================"
echo "Group 'l3-students' configured"
echo "Project 'signing-and-verification' created"
echo "Project URL: $GITLAB_URL/l3-students/signing-and-verification"
echo "================================"
