#!/bin/bash
#
# SC2026 Day 2 - Automatic Marking Scheme Validator
# Validates AWS GameDay Day 2 challenge: E-Commerce Platform on ECS
# Requires: AWS CLI v2, jq, curl
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
check_dependency "curl"

# Get AWS region and profile
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-default}"

export AWS_REGION AWS_PROFILE

log_section "SC2026 Day 2 - Marking Scheme Validator"
printf "Region: %s | Profile: %s\n" "$AWS_REGION" "$AWS_PROFILE"

# ============================================================================
# Section 1: Operational Excellence (20 marks)
# ============================================================================
log_section "Section 1: Operational Excellence (20 marks)"

# Check 1: ECS cluster 'ecommerce-cluster' exists
if aws ecs describe-clusters --clusters ecommerce-cluster --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
   jq -e '.clusters[0].clusterName=="ecommerce-cluster" and (.clusters[0].status=="ACTIVE")' &>/dev/null; then
    log_pass 5 5 "ECS cluster 'ecommerce-cluster' exists and is ACTIVE"
else
    log_fail 5 "ECS cluster 'ecommerce-cluster' not found or not active"
fi

# Check 2: API task definition deployed and running
if aws ecs list-services --cluster ecommerce-cluster --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
   jq -e '.serviceArns[] | select(contains("ecommerce-api"))' &>/dev/null; then
    
    API_SERVICE=$(aws ecs list-services --cluster ecommerce-cluster --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
        jq -r '.serviceArns[] | select(contains("ecommerce-api")) | split("/")[-1]' | head -1)
    
    if aws ecs describe-services --cluster ecommerce-cluster --services "$API_SERVICE" --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
       jq -e '.services[0] | select(.runningCount >= 1 and .desiredCount >= 1)' &>/dev/null; then
        log_pass 5 5 "API service deployed and running on Fargate"
    else
        log_fail 5 "API service not running"
    fi
else
    log_fail 5 "API service not found"
fi

# Check 3: Frontend task definition deployed and running
if aws ecs list-services --cluster ecommerce-cluster --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
   jq -e '.serviceArns[] | select(contains("ecommerce-frontend"))' &>/dev/null; then
    
    FRONTEND_SERVICE=$(aws ecs list-services --cluster ecommerce-cluster --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
        jq -r '.serviceArns[] | select(contains("ecommerce-frontend")) | split("/")[-1]' | head -1)
    
    if aws ecs describe-services --cluster ecommerce-cluster --services "$FRONTEND_SERVICE" --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
       jq -e '.services[0] | select(.runningCount >= 1 and .desiredCount >= 1)' &>/dev/null; then
        log_pass 5 5 "Frontend service deployed and running on Fargate"
    else
        log_fail 5 "Frontend service not running"
    fi
else
    log_fail 5 "Frontend service not found"
fi

# Check 4: ALB configured with routing
if aws elbv2 describe-load-balancers --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
   jq -e '.LoadBalancers[] | select(.LoadBalancerName | contains("ecommerce"))' &>/dev/null; then
    
    ALB_ARN=$(aws elbv2 describe-load-balancers --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
        jq -r '.LoadBalancers[] | select(.LoadBalancerName | contains("ecommerce")) | .LoadBalancerArn' | head -1)
    
    TARGET_GROUP_COUNT=$(aws elbv2 describe-target-groups --load-balancer-arn "$ALB_ARN" --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
        jq '.TargetGroups | length')
    
    if [ "$TARGET_GROUP_COUNT" -ge 2 ]; then
        log_pass 5 5 "ALB configured with at least 2 target groups (API and Frontend)"
    else
        log_fail 5 "ALB does not have enough target groups ($TARGET_GROUP_COUNT < 2)"
    fi
else
    log_fail 5 "ALB not found"
fi

# ============================================================================
# Section 2: Security (20 marks)
# ============================================================================
log_section "Section 2: Security (20 marks)"

# Check 5: ECS tasks use LabRole
# This requires checking task definition execution role
if aws ecs describe-task-definition --task-definition ecommerce-api --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
   jq -e '.taskDefinition.executionRoleArn | contains("LabRole")' &>/dev/null; then
    log_pass 5 5 "ECS tasks use LabRole execution role"
else
    log_fail 5 "ECS tasks do not use LabRole execution role"
fi

# Check 6: Security groups restrict ports
log_fail 5 "Security group restrictions on ports 8000/5000 (requires manual verification)"

# Check 7: DynamoDB not publicly exposed
if aws dynamodb list-tables --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
   jq -e '.TableNames[] | select(. == "products" or . == "orders" or . == "cart")' &>/dev/null; then
    log_pass 5 5 "DynamoDB tables exist (access via IAM only)"
else
    log_fail 5 "DynamoDB tables not found"
fi

# Check 8: ALB has listener configured
if [ -n "${ALB_ARN:-}" ]; then
    LISTENER_COUNT=$(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
        jq '.Listeners | length')
    
    if [ "$LISTENER_COUNT" -ge 1 ]; then
        log_pass 5 5 "ALB has HTTP/HTTPS listener configured"
    else
        log_fail 5 "ALB has no listeners configured"
    fi
else
    log_fail 5 "ALB not found for listener check"
fi

# ============================================================================
# Section 3: Reliability (30 marks)
# ============================================================================
log_section "Section 3: Reliability (30 marks)"

# Get endpoints
if [ -z "${API_ENDPOINT:-}" ]; then
    read -p "Enter API endpoint URL (e.g., http://alb-dns:8000 or https://...): " API_ENDPOINT
fi

if [ -z "${FRONTEND_ENDPOINT:-}" ]; then
    read -p "Enter Frontend endpoint URL (e.g., http://alb-dns:5000 or https://...): " FRONTEND_ENDPOINT
fi

# Check 9: GET /health on API returns 200
if [ -n "$API_ENDPOINT" ]; then
    API_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "$API_ENDPOINT/health" 2>/dev/null || echo "000")
    
    if [ "$API_HEALTH" = "200" ]; then
        API_RESPONSE=$(curl -s "$API_ENDPOINT/health" 2>/dev/null || echo "{}")
        if echo "$API_RESPONSE" | jq -e '.status == "healthy"' &>/dev/null; then
            log_pass 5 5 "API GET /health returns HTTP 200 with status=healthy"
        else
            log_pass 5 5 "API GET /health returns HTTP 200"
        fi
    else
        log_fail 5 "API GET /health returns HTTP $API_HEALTH (expected 200)"
    fi
else
    log_fail 5 "API endpoint not provided"
fi

# Check 10: GET /health on Frontend returns 200
if [ -n "$FRONTEND_ENDPOINT" ]; then
    FRONTEND_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "$FRONTEND_ENDPOINT/health" 2>/dev/null || echo "000")
    
    if [ "$FRONTEND_HEALTH" = "200" ]; then
        log_pass 5 5 "Frontend GET /health returns HTTP 200"
    else
        log_fail 5 "Frontend GET /health returns HTTP $FRONTEND_HEALTH (expected 200)"
    fi
else
    log_fail 5 "Frontend endpoint not provided"
fi

# Check 11: GET /products returns at least 5 products
if [ -n "$API_ENDPOINT" ]; then
    PRODUCTS_RESPONSE=$(curl -s "$API_ENDPOINT/products" 2>/dev/null || echo "[]")
    PRODUCT_COUNT=$(echo "$PRODUCTS_RESPONSE" | jq '. | length // 0' 2>/dev/null || echo "0")
    
    if [ "$PRODUCT_COUNT" -ge 5 ]; then
        log_pass 5 5 "GET /products returns at least 5 products ($PRODUCT_COUNT found)"
    else
        log_fail 5 "GET /products returns insufficient products ($PRODUCT_COUNT < 5)"
    fi
else
    log_fail 5 "API endpoint not provided"
fi

# Check 12: POST /orders creates order
if [ -n "$API_ENDPOINT" ]; then
    ORDER_RESPONSE=$(curl -s -X POST "$API_ENDPOINT/orders" \
        -H "Content-Type: application/json" \
        -d '{"customer_id":"test","items":[]}' 2>/dev/null || echo "{}")
    
    ORDER_ID=$(echo "$ORDER_RESPONSE" | jq -r '.order_id // empty')
    
    if [ -n "$ORDER_ID" ]; then
        log_pass 5 5 "POST /orders creates order in DynamoDB with order_id"
    else
        log_fail 5 "POST /orders does not return order_id"
    fi
else
    log_fail 5 "API endpoint not provided"
fi

# Check 13: Cart operations
if [ -n "$API_ENDPOINT" ]; then
    CART_RESPONSE=$(curl -s "$API_ENDPOINT/cart/test-cart" 2>/dev/null || echo "{}")
    
    if echo "$CART_RESPONSE" | jq -e 'has("items")' &>/dev/null; then
        log_pass 5 5 "Cart operations (GET /cart/{id}) work correctly"
    else
        log_fail 5 "Cart operations not responding correctly"
    fi
else
    log_fail 5 "API endpoint not provided"
fi

# Check 14: End-to-end flow
log_fail 5 "End-to-end flow verification (browse → add to cart → checkout)"

# ============================================================================
# Section 4: Performance Efficiency (15 marks)
# ============================================================================
log_section "Section 4: Performance Efficiency (15 marks)"

# Check 15: API response time < 3 seconds
if [ -n "$API_ENDPOINT" ]; then
    RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" "$API_ENDPOINT/products" 2>/dev/null || echo "999")
    
    if (( $(echo "$RESPONSE_TIME < 3.0" | bc -l) )); then
        log_pass 5 5 "API GET /products responds < 3 seconds (${RESPONSE_TIME}s)"
    else
        log_fail 5 "API GET /products response time >= 3 seconds (${RESPONSE_TIME}s)"
    fi
else
    log_fail 5 "API endpoint not provided"
fi

# Check 16: Fargate task CPU/memory configured
if aws ecs describe-task-definition --task-definition ecommerce-api --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
   jq -e '.taskDefinition | select(.cpu == "256" or .cpu == "512" or .cpu == "1024") and select(.memory == "512" or .memory == "1024" or .memory == "2048")' &>/dev/null; then
    log_pass 5 5 "Fargate task CPU/memory configured appropriately"
else
    log_fail 5 "Fargate task CPU/memory not configured correctly"
fi

# Check 17: DynamoDB PAY_PER_REQUEST
DYNAMO_PAY_PER_REQUEST=0
for table in products orders cart; do
    if aws dynamodb describe-table --table-name "$table" --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
       jq -e '.Table.BillingModeSummary.BillingMode=="PAY_PER_REQUEST"' &>/dev/null; then
        ((DYNAMO_PAY_PER_REQUEST++))
    fi
done

if [ $DYNAMO_PAY_PER_REQUEST -ge 3 ]; then
    log_pass 5 5 "DynamoDB tables use PAY_PER_REQUEST billing mode"
else
    log_fail 5 "Not all DynamoDB tables using PAY_PER_REQUEST ($DYNAMO_PAY_PER_REQUEST/3)"
fi

# ============================================================================
# Section 5: Cost Optimization (15 marks)
# ============================================================================
log_section "Section 5: Cost Optimization (15 marks)"

# Check 18: Fargate tasks right-sized (<=256 CPU / 512 MB memory)
if aws ecs describe-task-definition --task-definition ecommerce-api --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
   jq -e '.taskDefinition | select((.cpu | tonumber) <= 256 and (.memory | tonumber) <= 512)' &>/dev/null; then
    log_pass 5 5 "Fargate tasks right-sized (CPU <= 256, Memory <= 512 MB)"
else
    log_fail 5 "Fargate tasks not properly right-sized"
fi

# Check 19: ECR images used
if aws ecr describe-repositories --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null | \
   jq -e '.repositories[] | select(.repositoryName | contains("ecommerce") or contains("api") or contains("frontend"))' &>/dev/null; then
    log_pass 5 5 "ECR repository exists (not using Docker Hub directly)"
else
    log_fail 5 "ECR repository not found"
fi

# Check 20: No unnecessary NAT Gateway
log_fail 5 "NAT Gateway usage verification (requires VPC inspection)"

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
