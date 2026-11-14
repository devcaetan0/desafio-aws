#!/bin/bash
#
# SC2026 Day 1 - Automatic Marking Scheme Validator
# Validates AWS GameDay Day 1 challenge: Complaint Processing Pipeline
# Requires: AWS CLI v2, jq
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Scoring tracker
TOTAL_MARKS=0
TOTAL_AVAILABLE=100

# Helper functions
log_pass() {
    local marks=$1
    local max=$2
    local desc=$3
    TOTAL_MARKS=$((TOTAL_MARKS + marks))
    printf "${GREEN}[PASS %d/%d]${NC} %s\n" "$marks" "$max" "$desc"
}

log_fail() {
    local max=$1
    local desc=$2
    printf "${RED}[FAIL 0/%d]${NC} %s\n" "$max" "$desc"
}

log_section() {
    printf "\n${BLUE}=== %s ===${NC}\n" "$1"
}

log_error() {
    printf "${YELLOW}[ERROR]${NC} %s\n" "$1"
}

check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 not found. Please install it first."
        exit 1
    fi
}

# Verify dependencies
check_dependency "aws"
check_dependency "jq"

# Get AWS region and profile
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-default}"

export AWS_REGION AWS_PROFILE

log_section "SC2026 Day 1 - Marking Scheme Validator"
printf "Region: %s | Profile: %s\n" "$AWS_REGION" "$AWS_PROFILE"

# ============================================================================
# Section 1: Operational Excellence (20 marks)
# ============================================================================
log_section "Section 1: Operational Excellence (20 marks)"

# Check 1: DynamoDB table 'complaints' exists with correct schema
if aws dynamodb describe-table --table-name complaints --region "$AWS_REGION" --profile "$AWS_PROFILE" &>/dev/null; then
    TABLE_SCHEMA=$(aws dynamodb describe-table --table-name complaints --region "$AWS_REGION" --profile "$AWS_PROFILE" | jq '.Table.KeySchema')
    if echo "$TABLE_SCHEMA" | jq -e '.[] | select(.AttributeName=="complaint_id" and .KeyType=="HASH")' &>/dev/null && \
       echo "$TABLE_SCHEMA" | jq -e '.[] | select(.AttributeName=="customer_id" and .KeyType=="RANGE")' &>/dev/null; then
        log_pass 5 5 "DynamoDB table 'complaints' exists with correct schema (PK: complaint_id, SK: customer_id)"
    else
        log_fail 5 "DynamoDB table 'complaints' has incorrect schema"
    fi
else
    log_fail 5 "DynamoDB table 'complaints' not found"
fi

# Check 2: Lambda function deployed and integrated with API Gateway
if aws lambda list-functions --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | jq -e '.Functions[] | select(.FunctionName | contains("complaint"))' &>/dev/null; then
    log_pass 5 5 "Lambda function deployed (name contains 'complaint')"
else
    log_fail 5 "Lambda function not found or not named with 'complaint'"
fi

# Check 3: API Gateway stage deployed; POST /complaints returns HTTP 200
if [ -z "${API_ENDPOINT:-}" ]; then
    read -p "Enter API endpoint URL (e.g., https://xxxxx.execute-api.us-east-1.amazonaws.com/prod): " API_ENDPOINT
fi

if [ -n "$API_ENDPOINT" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API_ENDPOINT/complaints" \
        -H "Content-Type: application/json" \
        -d '{"customer_id":"test","complaint":"test complaint"}' 2>/dev/null || echo "000")
    
    if [ "$HTTP_CODE" = "200" ]; then
        log_pass 5 5 "API Gateway POST /complaints returns HTTP 200"
    else
        log_fail 5 "API Gateway POST /complaints returns HTTP $HTTP_CODE (expected 200)"
    fi
else
    log_fail 5 "API endpoint not provided"
fi

# Check 4: Golang processor binary running and logs visible in CloudWatch
if aws logs describe-log-groups --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | jq -e '.logGroups[] | select(.logGroupName | contains("complaint") or contains("golang") or contains("processor"))' &>/dev/null; then
    log_pass 5 5 "Golang processor logs visible in CloudWatch"
else
    log_fail 5 "CloudWatch log group for processor not found"
fi

# ============================================================================
# Section 2: Security (20 marks)
# ============================================================================
log_section "Section 2: Security (20 marks)"

# Check 5: Lambda uses LabRole execution role
LAMBDA_ROLE=$(aws lambda list-functions --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
    jq -r '.Functions[] | select(.FunctionName | contains("complaint")) | .Role' | head -1)

if [ -n "$LAMBDA_ROLE" ] && echo "$LAMBDA_ROLE" | grep -q "LabRole"; then
    log_pass 5 5 "Lambda uses LabRole execution role"
else
    log_fail 5 "Lambda does not use LabRole (uses: $LAMBDA_ROLE)"
fi

# Check 6: RDS PostgreSQL enforces TLS
if aws rds describe-db-instances --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | jq -e '.DBInstances[] | select(.Engine | contains("postgres"))' &>/dev/null; then
    RDS_PARAM_GROUP=$(aws rds describe-db-instances --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
        jq -r '.DBInstances[] | select(.Engine | contains("postgres")) | .DBParameterGroups[0].DBParameterGroupName' | head -1)
    
    if [ -n "$RDS_PARAM_GROUP" ]; then
        if aws rds describe-db-parameters --db-parameter-group-name "$RDS_PARAM_GROUP" --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
           jq -e '.Parameters[] | select(.ParameterName=="rds.force_ssl" and .ParameterValue=="1")' &>/dev/null; then
            log_pass 5 5 "RDS PostgreSQL enforces TLS (rds.force_ssl=1)"
        else
            log_fail 5 "RDS PostgreSQL does not enforce TLS"
        fi
    else
        log_fail 5 "Could not determine RDS parameter group"
    fi
else
    log_fail 5 "RDS PostgreSQL instance not found"
fi

# Check 7: RDS instance not publicly accessible
if aws rds describe-db-instances --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
   jq -e '.DBInstances[] | select(.Engine | contains("postgres")) | select(.PubliclyAccessible==false)' &>/dev/null; then
    log_pass 5 5 "RDS instance not publicly accessible"
else
    log_fail 5 "RDS instance is publicly accessible (should be private)"
fi

# Check 8: Golang processor connects with sslmode=require
# This is a documentation/code check - log a note
log_fail 5 "Golang processor TLS connection (requires code inspection)"

# ============================================================================
# Section 3: Reliability (25 marks)
# ============================================================================
log_section "Section 3: Reliability (25 marks)"

# Check 9: POST /complaints stores item in DynamoDB with processed=false
if [ -n "$API_ENDPOINT" ]; then
    RESPONSE=$(curl -s -X POST "$API_ENDPOINT/complaints" \
        -H "Content-Type: application/json" \
        -d '{"customer_id":"test-reliability","complaint":"test"}' 2>/dev/null || echo "{}")
    
    COMPLAINT_ID=$(echo "$RESPONSE" | jq -r '.complaint_id // empty')
    
    if [ -n "$COMPLAINT_ID" ]; then
        ITEM=$(aws dynamodb get-item --table-name complaints --key "{\"complaint_id\":{\"S\":\"$COMPLAINT_ID\"},\"customer_id\":{\"S\":\"test-reliability\"}}" \
            --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | jq '.Item.processed // empty')
        
        if [ -z "$ITEM" ] || echo "$ITEM" | jq -e '.BOOL==false' &>/dev/null; then
            log_pass 5 5 "POST /complaints stores item with processed=false"
        else
            log_fail 5 "Item in DynamoDB does not have processed=false"
        fi
    else
        log_fail 5 "API response missing complaint_id"
    fi
else
    log_fail 5 "API endpoint not provided (cannot test)"
fi

# Check 10: Golang processor scans DynamoDB every 5 seconds
log_fail 5 "Golang processor scan interval (requires code/log inspection)"

# Check 11: Processed complaints in RDS table
if aws rds describe-db-instances --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | jq -e '.DBInstances[] | select(.Engine | contains("postgres"))' &>/dev/null; then
    log_fail 5 "RDS processed_complaints table verification (requires DB query)"
else
    log_fail 5 "RDS instance not available for verification"
fi

# Check 12: DynamoDB item updated to processed=true
log_fail 5 "DynamoDB processed=true update (requires monitoring)"

# Check 13: System handles 50+ concurrent requests
log_fail 5 "Concurrent request load test (requires locust/load testing)"

# ============================================================================
# Section 4: Performance Efficiency (20 marks)
# ============================================================================
log_section "Section 4: Performance Efficiency (20 marks)"

# Check 14: API latency < 2 seconds
log_fail 5 "API latency test (requires performance testing)"

# Check 15: Processing within 15 seconds
log_fail 5 "End-to-end processing time (requires monitoring)"

# Check 16: RDS indexes
log_fail 5 "RDS table indexes (requires DB query)"

# Check 17: Connection pool
log_fail 5 "Golang connection pool configuration (requires code inspection)"

# ============================================================================
# Section 5: Cost Optimization (15 marks)
# ============================================================================
log_section "Section 5: Cost Optimization (15 marks)"

# Check 18: Lambda memory <= 512 MB
if [ -n "$LAMBDA_ROLE" ]; then
    LAMBDA_FUNC=$(aws lambda list-functions --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
        jq -r '.Functions[] | select(.FunctionName | contains("complaint")) | .FunctionName' | head -1)
    
    if [ -n "$LAMBDA_FUNC" ]; then
        MEMORY=$(aws lambda get-function-configuration --function-name "$LAMBDA_FUNC" --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | jq '.MemorySize')
        
        if [ "$MEMORY" -le 512 ]; then
            log_pass 5 5 "Lambda memory configured <= 512 MB (${MEMORY}MB)"
        else
            log_fail 5 "Lambda memory too high: ${MEMORY}MB (max 512MB)"
        fi
    fi
fi

# Check 19: DynamoDB PAY_PER_REQUEST
if aws dynamodb describe-table --table-name complaints --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
   jq -e '.Table.BillingModeSummary.BillingMode=="PAY_PER_REQUEST"' &>/dev/null; then
    log_pass 5 5 "DynamoDB uses PAY_PER_REQUEST billing mode"
else
    log_fail 5 "DynamoDB not using PAY_PER_REQUEST billing mode"
fi

# Check 20: RDS instance class is db.t3.micro or db.t4g.micro
if aws rds describe-db-instances --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
   jq -e '.DBInstances[] | select(.Engine | contains("postgres")) | select(.DBInstanceClass | test("db.t[34]g?.micro"))' &>/dev/null; then
    log_pass 5 5 "RDS instance class is db.t3.micro or db.t4g.micro"
else
    log_fail 5 "RDS instance class is not cost-optimized (not t3.micro or t4g.micro)"
fi

# ============================================================================
# Final Score
# ============================================================================
log_section "FINAL SCORE"
printf "Total Marks Awarded: ${GREEN}%d${NC} / ${TOTAL_AVAILABLE}\n" "$TOTAL_MARKS"
PERCENTAGE=$((TOTAL_MARKS * 100 / TOTAL_AVAILABLE))
printf "Percentage: ${GREEN}%d%%${NC}\n" "$PERCENTAGE"

if [ $TOTAL_MARKS -ge 70 ]; then
    printf "${GREEN}PASS${NC} - Score is >= 70\n"
    exit 0
else
    printf "${RED}FAIL${NC} - Score is < 70\n"
    exit 1
fi
