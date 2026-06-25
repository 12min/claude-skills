---
name: logcli-ingress
description: Search and analyze nginx/ingress logs from Loki in production or staging. Use for investigating 5xx/4xx errors, timeouts, endpoint filtering, real-time log tailing, or any nginx ingress log analysis.
---

# Logcli Ingress - Nginx/Ingress Log Search

Search and analyze nginx/ingress logs from Loki in production or staging environments.

## Usage

```
/logcli-ingress [environment]
```

**Parameters:**
- `environment` (optional): `production` or `staging` (default: `production`)

## Description

This skill provides an interactive menu to query nginx/ingress logs from Loki with common search patterns:

1. **All logs** - View all nginx/ingress logs from the last hour
2. **5xx errors** - Filter server errors (last 30 min)
3. **4xx errors** - Filter client errors (last 30 min)
4. **Timeouts** - Search for timeout errors
5. **Specific endpoint** - Search logs for a specific API endpoint
6. **Real-time tail** - Follow logs in real-time (Ctrl+C to stop)
7. **Specific domain** - Filter by domain (billing.12min.com or api.12min.com)
8. **Custom query** - Enter your own LogQL query
9. **Show labels** - Display available Loki labels and values

The skill automatically:
- Switches to the correct Kubernetes context
- Sets up port-forward to Loki if not already running
- Validates Loki connectivity before running queries

## Examples

**Search production logs:**
```
/logcli-ingress production
```

**Search staging logs:**
```
/logcli-ingress staging
```

## Script

```bash
#!/bin/bash

# logcli-ingress - Search nginx/ingress logs in Loki (production or staging)
# Usage: /logcli-ingress [environment] [query_type] [options]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="${1:-production}"
LOKI_URL="http://localhost:3100"

echo -e "${BLUE}🔍 Logcli Ingress - Nginx/Ingress Log Search${NC}\n"

# Determine Loki service and context based on environment
if [[ "$ENVIRONMENT" == "production" ]]; then
    LOKI_SERVICE="loki-12"
    K8S_CONTEXT="gke_min-b302a_southamerica-east1-a_api-production"
    echo -e "${GREEN}Environment: Production${NC}"
elif [[ "$ENVIRONMENT" == "staging" ]]; then
    LOKI_SERVICE="loki-staging"
    K8S_CONTEXT="gke_min-b302a_us-central1-c_api-staging-0"
    echo -e "${YELLOW}Environment: Staging${NC}"
else
    echo -e "${RED}Error: Invalid environment. Use 'production' or 'staging'${NC}"
    exit 1
fi

# Check if port-forward is already running
if ! curl -s "$LOKI_URL/ready" > /dev/null 2>&1; then
    echo -e "${YELLOW}Port-forward not detected. Setting up...${NC}"

    # Switch context
    echo "Switching to $K8S_CONTEXT..."
    kubectl config use-context "$K8S_CONTEXT" > /dev/null 2>&1

    # Start port-forward in background
    echo "Starting port-forward for $LOKI_SERVICE..."
    kubectl port-forward "service/$LOKI_SERVICE" 3100:3100 > /dev/null 2>&1 &
    PORT_FORWARD_PID=$!

    # Wait for port-forward to be ready
    echo "Waiting for Loki to be ready..."
    for i in {1..10}; do
        if curl -s "$LOKI_URL/ready" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Loki is ready${NC}\n"
            break
        fi
        sleep 1
    done
else
    echo -e "${GREEN}✓ Loki already accessible${NC}\n"
fi

# Query type (second argument or interactive)
QUERY_TYPE="${2:-menu}"

if [[ "$QUERY_TYPE" == "menu" ]]; then
    echo -e "${BLUE}Select query type:${NC}"
    echo "1) All logs (last 1 hour)"
    echo "2) Errors 5xx (last 30 min)"
    echo "3) Errors 4xx (last 30 min)"
    echo "4) Timeouts"
    echo "5) Specific endpoint"
    echo "6) Real-time tail"
    echo "7) Specific domain (billing/api)"
    echo "8) Custom query"
    echo "9) Show available labels"
    echo ""
    read -p "Choose option (1-9): " OPTION
else
    OPTION="$QUERY_TYPE"
fi

# Build query based on selection
case "$OPTION" in
    1)
        echo -e "\n${GREEN}Running: All nginx/ingress logs (last 1 hour)${NC}\n"
        logcli query '{namespace="ingress-nginx"}' --since=1h --addr="$LOKI_URL"
        ;;
    2)
        echo -e "\n${GREEN}Running: 5xx errors (last 30 min)${NC}\n"
        logcli query '{namespace="ingress-nginx"} |~ " 5[0-9]{2} "' --since=30m --addr="$LOKI_URL"
        ;;
    3)
        echo -e "\n${GREEN}Running: 4xx errors (last 30 min)${NC}\n"
        logcli query '{namespace="ingress-nginx"} |~ " 4[0-9]{2} "' --since=30m --addr="$LOKI_URL"
        ;;
    4)
        echo -e "\n${GREEN}Running: Timeout errors (last 1 hour)${NC}\n"
        logcli query '{namespace="ingress-nginx"} |= "timeout"' --since=1h --addr="$LOKI_URL"
        ;;
    5)
        read -p "Enter endpoint path (e.g., /api/v2/users): " ENDPOINT
        echo -e "\n${GREEN}Running: Logs for endpoint $ENDPOINT (last 1 hour)${NC}\n"
        logcli query "{namespace=\"ingress-nginx\"} |= \"$ENDPOINT\"" --since=1h --addr="$LOKI_URL"
        ;;
    6)
        echo -e "\n${GREEN}Running: Real-time tail (all logs)${NC}\n"
        echo -e "${YELLOW}Press Ctrl+C to stop${NC}\n"
        logcli query '{namespace="ingress-nginx"}' --since=1m --tail --addr="$LOKI_URL"
        ;;
    7)
        echo "Select domain:"
        echo "1) billing.12min.com"
        echo "2) api.12min.com"
        read -p "Choose (1-2): " DOMAIN_OPTION
        case "$DOMAIN_OPTION" in
            1) DOMAIN="billing.12min.com" ;;
            2) DOMAIN="api.12min.com" ;;
            *) echo "Invalid option"; exit 1 ;;
        esac
        echo -e "\n${GREEN}Running: Logs for $DOMAIN (last 1 hour)${NC}\n"
        logcli query "{namespace=\"ingress-nginx\"} |= \"$DOMAIN\"" --since=1h --addr="$LOKI_URL"
        ;;
    8)
        read -p "Enter custom LogQL query: " CUSTOM_QUERY
        read -p "Time range (e.g., 1h, 30m, 2h): " TIME_RANGE
        echo -e "\n${GREEN}Running: Custom query${NC}\n"
        logcli query "$CUSTOM_QUERY" --since="$TIME_RANGE" --addr="$LOKI_URL"
        ;;
    9)
        echo -e "\n${GREEN}Available labels:${NC}\n"
        logcli labels --addr="$LOKI_URL"
        echo -e "\n${GREEN}Label values for 'namespace':${NC}\n"
        logcli labels namespace --addr="$LOKI_URL"
        echo -e "\n${GREEN}Label values for 'pod':${NC}\n"
        logcli labels pod --addr="$LOKI_URL" | grep -i nginx || echo "No nginx pods found"
        ;;
    *)
        echo -e "${RED}Invalid option${NC}"
        exit 1
        ;;
esac

echo -e "\n${BLUE}Done!${NC}"

# Clean up port-forward if we started it
if [[ -n "$PORT_FORWARD_PID" ]]; then
    echo -e "${YELLOW}Tip: Port-forward is running in background (PID: $PORT_FORWARD_PID)${NC}"
    echo -e "${YELLOW}To stop it: kill $PORT_FORWARD_PID${NC}"
fi
```

## Requirements

- `kubectl` configured with access to production/staging clusters
- `logcli` installed and in PATH
- Network access to Kubernetes clusters
- Port 3100 available locally for Loki port-forward

## Troubleshooting

**"Port-forward failed":**
- Check if you're authenticated to the cluster: `kubectl get pods`
- Verify cluster context is correct: `kubectl config current-context`

**"No results found":**
- Run option 9 to see available labels
- Adjust namespace in the script if different from `ingress-nginx`

**"Connection refused":**
- Port 3100 may be in use: `lsof -i :3100`
- Kill existing port-forward and try again
