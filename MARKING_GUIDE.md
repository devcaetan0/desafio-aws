# SC2026 GameDay - Professional Marking & Scoring Guide

## 📋 Overview

This guide explains how to use the professional marking schemes and automated scoring scripts for SC2026 GameDay challenges.

## 📊 Marking Scheme Files (XLSX)

### SC2026_Day1_Marking_Scheme.xlsx
**AWS Well-Architected Framework-based rubric for Day 1 (Complaint Processing Pipeline)**

- **Total Marks**: 100
- **Sections**: 5 AWS Pillars (20 marks each)
  1. **Operational Excellence** (20 marks): Infrastructure setup, logging, monitoring
  2. **Security** (20 marks): IAM roles, encryption, access control
  3. **Reliability** (20 marks): Fault tolerance, data durability
  4. **Performance Efficiency** (20 marks): Scalability, optimization
  5. **Cost Optimization** (20 marks): Resource efficiency, cost control

- **Structure**:
  - Header with competition info
  - Per-section criteria with individual marks
  - Automatic calculation of section totals
  - Professional color coding
  - Pass/Fail column for evaluator marks

### SC2026_Day2_Marking_Scheme.xlsx
**AWS Well-Architected Framework-based rubric for Day 2 (E-Commerce Platform)**

- **Total Marks**: 100
- **Sections**: 5 AWS Pillars (20 marks each)
  - Same structure as Day 1
  - Task-specific criteria for e-commerce platform

## 🤖 Automated Scoring Scripts (Bash)

### score_day1.sh
**Automated validator and scorer for Day 1 deployment**

```bash
./score_day1.sh
```

**Features:**
- ✅ Validates AWS resources (DynamoDB, Lambda, RDS, API Gateway)
- ✅ Checks security configurations (IAM roles, TLS, public access)
- ✅ Verifies performance metrics and cost optimization
- ✅ Calculates score out of 100
- ✅ Color-coded pass/fail output
- ✅ Exit code 0 if score ≥ 70, exit code 1 if < 70

**Environment Variables:**
```bash
export AWS_REGION=us-east-1      # Default: us-east-1
export AWS_PROFILE=default       # Default: default
export API_ENDPOINT=https://...  # API Gateway URL (prompted if not set)
```

**Usage Examples:**
```bash
# Basic usage
./score_day1.sh

# With specific AWS profile
AWS_PROFILE=learner-lab ./score_day1.sh

# With specific region and API endpoint
AWS_REGION=us-west-2 API_ENDPOINT=https://xxxxx.execute-api.us-west-2.amazonaws.com/prod ./score_day1.sh

# Check exit code
./score_day1.sh
if [ $? -eq 0 ]; then
    echo "Participant passed (≥70 marks)"
else
    echo "Participant failed (<70 marks)"
fi
```

### score_day2.sh
**Automated validator and scorer for Day 2 deployment**

```bash
./score_day2.sh
```

**Features:**
- ✅ Validates ECS cluster and task definitions
- ✅ Checks ALB configuration and health
- ✅ Verifies DynamoDB tables and data
- ✅ Tests API and Frontend endpoints
- ✅ Validates Docker images
- ✅ Checks CloudWatch monitoring
- ✅ Calculates score out of 100
- ✅ Color-coded pass/fail output

**Usage Examples:**
```bash
# Basic usage
./score_day2.sh

# With specific AWS profile
AWS_PROFILE=learner-lab ./score_day2.sh

# Check results
./score_day2.sh > score_day2_results.txt
cat score_day2_results.txt
```

---

## 🔧 Workflow: Evaluation & Scoring

### Step 1: Before Challenge Ends
```bash
# Ensure scripts are executable
chmod +x score_day*.sh

# Test environment (optional)
aws sts get-caller-identity
```

### Step 2: Validate Deployment
```bash
# Run automated validator
./score_day1.sh  # or ./score_day2.sh

# Review output for failures
# Output shows which criteria failed and why
```

### Step 3: Manual Review (Optional)
```bash
# Open XLSX marking scheme in Excel/Sheets
# Use validator output as reference
# Manually verify functionality items
# Mark each criterion
# System auto-calculates total
```

### Step 4: Record Score
```bash
# Script outputs final score
# Exit code indicates pass/fail:
#   0 = PASS (≥70 marks)
#   1 = FAIL (<70 marks)

./score_day1.sh
FINAL_SCORE=$?
```

---

## 📊 Marking Scheme Structure (Per Pillar)

### Example: Operational Excellence (Day 1)
| Criterion | Marks | Validator Check |
|-----------|-------|-----------------|
| DynamoDB table exists with correct schema | 5 | ✓ Automated |
| Lambda function deployed | 5 | ✓ Automated |
| API Gateway returns HTTP 200 | 5 | ✓ Automated |
| CloudWatch logs configured | 5 | ✓ Automated |
| **Section Total** | **20** | |

---

## 🎯 Scoring Guide

### Final Score Calculation
- **90-100**: Excellent - All requirements met with optimizations
- **70-89**: Good - Core requirements met
- **50-69**: Fair - Most requirements met, some gaps
- **0-49**: Poor - Major gaps or non-functional deployment

### Pass/Fail Threshold
- **Pass**: ≥ 70 marks
- **Fail**: < 70 marks

---

## 📝 AWS Well-Architected Pillars

### 1. Operational Excellence (20 marks)
Focus: Operations, monitoring, logging, infrastructure-as-code
- Infrastructure properly configured
- Monitoring and logging enabled
- Health checks and diagnostics working

### 2. Security (20 marks)
Focus: Data protection, access control, compliance
- IAM roles and policies correct
- Encryption enabled (TLS, at-rest)
- Public access properly restricted

### 3. Reliability (20 marks)
Focus: Fault tolerance, data durability, disaster recovery
- Database replication/backup configured
- Error handling implemented
- Service health maintained

### 4. Performance Efficiency (20 marks)
Focus: Resource utilization, scalability, optimization
- Auto-scaling configured
- Resource sizes appropriate
- Caching strategies implemented

### 5. Cost Optimization (20 marks)
Focus: Resource efficiency, right-sizing, waste elimination
- On-demand vs reserved capacity decisions
- Unused resources cleaned up
- Cost monitoring enabled

---

## 💡 Scoring Tips

### For Evaluators
1. **Run automated script first** - Gets 70-80% of marks automatically
2. **Use XLSX for documentation** - Manual criteria go in spreadsheet
3. **Keep JSON output** - For audit trail and records
4. **Note deviations** - If implementation differs from checklist
5. **Test functionality** - Some criteria require manual testing

### Common Issues

**Script fails with "AWS CLI not found"**
- Install AWS CLI v2: https://aws.amazon.com/cli/
- Verify: `aws --version`

**"jq not found"**
- Install jq: `brew install jq` (macOS) or `apt-get install jq` (Linux)
- Verify: `jq --version`

**"AccessDenied" errors**
- Check AWS credentials: `aws sts get-caller-identity`
- Verify IAM permissions for LabRole
- Ensure AWS_PROFILE and AWS_REGION are set correctly

**API endpoint not responding**
- Ensure ALB/API Gateway is properly deployed
- Check security groups allow inbound traffic
- Verify health checks passing

---

## 📂 File Structure

```
/Users/thiagogeremias/Projetos/seletiva-sc-2026/
├── SC2026_Day1_Marking_Scheme.xlsx     # Day 1 scoring rubric (XLSX)
├── SC2026_Day2_Marking_Scheme.xlsx     # Day 2 scoring rubric (XLSX)
├── score_day1.sh                       # Day 1 automated scorer (bash)
├── score_day2.sh                       # Day 2 automated scorer (bash)
├── MARKING_GUIDE.md                    # This file
├── day1/README.md                      # Day 1 challenge description
├── day2/README.md                      # Day 2 challenge description
└── validate_day1.py, validate_day2.py # Alternative Python validators
```

---

## 🚀 Quick Start

### For a Single Participant
```bash
cd /Users/thiagogeremias/Projetos/seletiva-sc-2026

# Score Day 1
./score_day1.sh

# Score Day 2
./score_day2.sh
```

### For Multiple Participants
```bash
#!/bin/bash
PARTICIPANTS=("team1" "team2" "team3")

for participant in "${PARTICIPANTS[@]}"; do
    echo "Scoring $participant - Day 1"
    AWS_PROFILE=$participant ./score_day1.sh > results_${participant}_day1.txt
    
    echo "Scoring $participant - Day 2"
    AWS_PROFILE=$participant ./score_day2.sh > results_${participant}_day2.txt
done
```

---

## ✅ Verification Checklist

Before starting competition:
- [ ] Scripts are executable: `ls -l score_day*.sh`
- [ ] AWS CLI installed: `aws --version`
- [ ] jq installed: `jq --version`
- [ ] AWS credentials configured: `aws sts get-caller-identity`
- [ ] XLSX files open without errors
- [ ] Sample run works: `./score_day1.sh --help` or dry-run

---

## 📞 Support

**Script issues?**
- Check logs: `./score_day1.sh 2>&1 | tee debug.log`
- Set debug mode: `bash -x score_day1.sh`

**XLSX issues?**
- Try opening in Google Sheets
- Re-generate if corrupted

**AWS access issues?**
- Verify LabRole permissions
- Check region settings
- Confirm resource names match

---

**SC2026 GameDay Marking & Scoring System**  
*Professional evaluation based on AWS Well-Architected Framework*  
*Automated scoring with manual review capability*
