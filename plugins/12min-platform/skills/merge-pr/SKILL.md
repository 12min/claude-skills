---
name: merge-pr
description: Smart PR merge for 12min repos — squash merge, auto-cleanup branch, sync development, monitor CI/CD deploy. Use when the user asks to merge a PR, ship a PR, or close out a feature branch.
---

# Merge PR Command

Smartly merge PRs with automatic branch cleanup, development synchronization, and CI/CD monitoring.

```bash
#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Helper functions
print_header() {
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_status() {
  local status=$1
  local conclusion=$2

  case "$status" in
    "completed")
      case "$conclusion" in
        "success") echo -e "${GREEN}✓ PASSED${NC}" ;;
        "failure") echo -e "${RED}✗ FAILED${NC}" ;;
        "neutral") echo -e "${GRAY}⊘ NEUTRAL${NC}" ;;
        *) echo -e "${YELLOW}? UNKNOWN${NC}" ;;
      esac
      ;;
    "queued")
      echo -e "${YELLOW}⏳ QUEUED${NC}"
      ;;
    "in_progress")
      echo -e "${YELLOW}⟳ IN PROGRESS${NC}"
      ;;
    *)
      echo -e "${GRAY}? UNKNOWN${NC}"
      ;;
  esac
}

monitor_travis_ci() {
  local repo="12min/web"
  local latest_commit=$(git log -1 --pretty=format:"%H")
  local check_interval=15
  local max_wait=3600
  local start_time=$(date +%s)
  local last_status=""

  print_header "Monitoring Travis CI Build"
  echo -e "${GRAY}Commit:${NC} ${latest_commit:0:7}"
  echo -e "${GRAY}Checking every ${check_interval}s (timeout: ${max_wait}s)${NC}"
  echo ""

  while true; do
    local elapsed=$(($(date +%s) - start_time))

    if [ $elapsed -gt $max_wait ]; then
      echo -e "${YELLOW}⚠ Timeout: Build is taking too long (${elapsed}s)${NC}"
      return 1
    fi

    local checks=$(gh api repos/$repo/commits/$latest_commit/check-runs \
      -q ".check_runs[] | {name: .name, status: .status, conclusion: .conclusion, details_url: .details_url}" 2>/dev/null)

    if [ -z "$checks" ]; then
      echo -e "[$(date +%H:%M:%S)] Waiting for checks to start..."
      sleep $check_interval
      continue
    fi

    local build_status=$(echo "$checks" | jq -r ".status" | head -1)
    local build_conclusion=$(echo "$checks" | jq -r ".conclusion" | head -1)

    if [ "$build_status" != "$last_status" ]; then
      echo -e "[$(date +%H:%M:%S)] Status: $(print_status "$build_status" "$build_conclusion") (${elapsed}s)"
      last_status="$build_status"
    fi

    if [ "$build_status" = "completed" ]; then
      echo ""
      echo "$checks" | jq -r "@json" | while read line; do
        local check=$(echo "$line" | jq -r ".")
        local name=$(echo "$check" | jq -r ".name")
        local status=$(echo "$check" | jq -r ".status")
        local conclusion=$(echo "$check" | jq -r ".conclusion")

        echo -e "${BLUE}→${NC} $name"
        echo -e "  Status: $(print_status "$status" "$conclusion")"
      done

      echo ""
      if [ "$build_conclusion" = "success" ]; then
        echo -e "${GREEN}✓ Build successful! (${elapsed}s)${NC}"
        return 0
      else
        echo -e "${RED}✗ Build failed! Check the logs for details.${NC}"
        return 1
      fi
    fi

    sleep $check_interval
  done
}

monitor_rollout() {
  local environment=$1
  local cluster
  local deployment
  local pod_label

  if [ "$environment" = "staging" ]; then
    cluster="gke_min-b302a_us-central1-c_api-staging-0"
    deployment="api-staging"
    pod_label="app=api-staging"
  else
    cluster="gke_min-b302a_southamerica-east1-a_api-production"
    deployment="api"
    pod_label="app=api"
  fi

  local namespace="default"
  local timeout="10m"

  print_header "Monitoring Kubernetes Rollout ($environment)"
  echo -e "${GRAY}Cluster:${NC} $cluster"
  echo -e "${GRAY}Deployment:${NC} $deployment"
  echo -e "${GRAY}Timeout:${NC} $timeout${NC}"
  echo ""

  # Check if cluster context exists
  if ! kubectl config get-contexts | grep -q "$cluster"; then
    echo -e "${RED}✗ Cluster context not found: $cluster${NC}"
    return 1
  fi

  # Switch to correct cluster
  echo -e "${GRAY}Switching to cluster context...${NC}"
  kubectl config use-context "$cluster" > /dev/null 2>&1

  if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Failed to switch to cluster context${NC}"
    return 1
  fi

  echo -e "${GREEN}✓ Switched to $environment cluster${NC}"
  echo ""

  # Check if deployment exists
  if ! kubectl get deployment "$deployment" -n "$namespace" > /dev/null 2>&1; then
    echo -e "${RED}✗ Deployment not found: $deployment${NC}"
    return 1
  fi

  echo -e "${GREEN}✓ Deployment found${NC}"
  echo ""

  # Get current pod status
  print_header "Current Pod Status"
  kubectl get pods -n "$namespace" -l "$pod_label" -o wide 2>/dev/null || {
    echo -e "${GRAY}No pods found with label $pod_label${NC}"
  }
  echo ""

  # Watch rollout status
  local start_time=$(date +%s)

  if kubectl rollout status deployment/"$deployment" -n "$namespace" --timeout="$timeout"; then
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo ""
    print_header "Rollout Completed Successfully"
    echo -e "${GREEN}✓ Deployment rolled out in ${duration}s${NC}"

    echo ""
    print_header "Final Pod Status"
    kubectl get pods -n "$namespace" -l "$pod_label" -o wide

    echo ""
    return 0
  else
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo ""
    print_header "Rollout Failed or Timeout"
    echo -e "${RED}✗ Rollout did not complete within $timeout (${duration}s)${NC}"

    echo ""
    echo -e "${YELLOW}⚠ Current pod status:${NC}"
    kubectl get pods -n "$namespace" -l "$pod_label" -o wide

    return 1
  fi
}

# Get PR number from argument or detect from current branch
PR_NUMBER="${1}"

if [ -z "$PR_NUMBER" ]; then
  # Try to detect PR from current branch
  CURRENT_BRANCH=$(git branch --show-current)
  PR_INFO=$(gh pr view --json number --jq '.number' 2>/dev/null || echo "")

  if [ -z "$PR_INFO" ]; then
    echo -e "${RED}Error: Could not detect PR number.${NC}"
    echo "Usage: merge-pr [PR_NUMBER] [--monitor]"
    exit 1
  fi
  PR_NUMBER=$PR_INFO
fi

# Check for --monitor flag
MONITOR_DEPLOY=0
if [ "$2" = "--monitor" ]; then
  MONITOR_DEPLOY=1
fi

# Get PR details
echo -e "${BLUE}Fetching PR #${PR_NUMBER} details...${NC}"
PR_DATA=$(gh pr view "$PR_NUMBER" --json number,title,headRefName,baseRefName,state)

PR_TITLE=$(echo "$PR_DATA" | jq -r '.title')
HEAD_BRANCH=$(echo "$PR_DATA" | jq -r '.headRefName')
BASE_BRANCH=$(echo "$PR_DATA" | jq -r '.baseRefName')
PR_STATE=$(echo "$PR_DATA" | jq -r '.state')

# Validate PR state
if [ "$PR_STATE" != "OPEN" ]; then
  echo -e "${RED}Error: PR #${PR_NUMBER} is not OPEN (state: $PR_STATE)${NC}"
  exit 1
fi

# Check git status
if ! git diff-index --quiet HEAD --; then
  echo -e "${RED}Error: Working directory has uncommitted changes.${NC}"
  echo "Please commit or stash your changes first."
  exit 1
fi

# Show confirmation
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}PR #${PR_NUMBER}${NC}: $PR_TITLE"
echo -e "Branch: ${BLUE}${HEAD_BRANCH}${NC} → ${BLUE}${BASE_BRANCH}${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Prompt for confirmation
read -p "Confirm squash merge? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}Merge cancelled.${NC}"
  exit 0
fi

# Ask about monitoring if not provided
if [ $MONITOR_DEPLOY -eq 0 ]; then
  read -p "Monitor CI/CD deployment? (y/N) " -n 1 -r
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    MONITOR_DEPLOY=1
  fi
fi

# Validate merge direction
if [ "$BASE_BRANCH" = "master" ] && [ "$HEAD_BRANCH" != "development" ]; then
  echo -e "${RED}Error: Cannot merge feature branch directly to master.${NC}"
  echo "Feature branches must be merged to 'development' first."
  exit 1
fi

echo ""
echo -e "${BLUE}Starting merge process...${NC}"
echo ""

# Perform squash merge
echo -e "${YELLOW}Step 1/4: Squash merging PR #${PR_NUMBER}...${NC}"
gh pr merge "$PR_NUMBER" --squash --delete-branch

# Determine environment and next steps based on base branch
DEPLOY_ENVIRONMENT=""

if [ "$BASE_BRANCH" = "development" ]; then
  # FLUXO A: Feature → Development
  echo -e "${YELLOW}Step 2/4: Checking out development...${NC}"
  git checkout development
  git pull origin development

  echo -e "${GREEN}✓ Feature branch ${HEAD_BRANCH} merged to development${NC}"
  echo -e "${GREEN}✓ Remote branch deleted by GitHub${NC}"
  DEPLOY_ENVIRONMENT="staging"

else
  # FLUXO B: Development → Master
  echo -e "${YELLOW}Step 2/4: Checking out master...${NC}"
  git checkout master
  git pull origin master

  echo -e "${YELLOW}Step 3/4: Deleting development branch...${NC}"
  git push origin --delete development 2>/dev/null || true
  git branch -D development 2>/dev/null || true

  echo -e "${YELLOW}Step 4/4: Recreating development from master...${NC}"
  git checkout -b development
  git push -u origin development

  echo -e "${GREEN}✓ Development merged to master${NC}"
  echo -e "${GREEN}✓ Development branch recreated and synced with master${NC}"
  DEPLOY_ENVIRONMENT="production"
fi

echo ""
echo -e "${GREEN}✓ Merge completed successfully!${NC}"
echo ""

# Monitor deployment if requested
if [ $MONITOR_DEPLOY -eq 1 ]; then
  echo ""
  echo -e "${GRAY}Waiting 20 seconds for CI/CD pipeline to initialize...${NC}"
  sleep 20

  echo ""
  if monitor_travis_ci; then
    echo ""
    echo -e "${GRAY}Waiting 30 seconds before monitoring rollout...${NC}"
    sleep 30

    echo ""
    if monitor_rollout "$DEPLOY_ENVIRONMENT"; then
      echo ""
      print_header "✓ Deployment Complete!"
      echo -e "${GREEN}Your changes have been successfully deployed to $DEPLOY_ENVIRONMENT!${NC}"
      echo ""
    else
      echo ""
      echo -e "${RED}✗ Rollout monitoring failed. Check the deployment manually.${NC}"
      exit 1
    fi
  else
    echo ""
    echo -e "${RED}✗ CI/CD build failed. Deployment cancelled.${NC}"
    exit 1
  fi
else
  echo -e "${GRAY}Tip: Use 'merge-pr $PR_NUMBER --monitor' to watch the deployment${NC}"
fi

echo ""
```
