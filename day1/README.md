# 🎮 The Great Data Migration Quest - Day 1 Challenge

## 📖 Mission Briefing

Your company's complaint system is drowning! You need to build a **serverless data pipeline** on AWS that:

1. **Accepts complaints** via HTTP API
2. **Stores them temporarily** in NoSQL (DynamoDB)
3. **Processes & enriches** with a pre-compiled Golang app
4. **Archives them** in SQL (PostgreSQL) **with TLS encryption**

**⏱️ Time:** 45 minutes | **🔐 Critical:** TLS is mandatory for database connection!  
**🏫 Platform:** AWS Academy Learner Lab | **👤 IAM Role:** LabRole (pre-configured)

---

## 🏗️ Architecture Diagram

```mermaid
graph LR
    A["👤 Customer"] -->|POST /complaints| B["API Gateway"]
    B -->|invoke| C["Lambda Function"]
    C -->|PutItem| D["DynamoDB<br/>Table: complaints"]
    
    E["Golang Processor<br/>(pre-compiled binary)"] -->|Scan| D
    E -->|enrich data| E
    E -->|INSERT<br/>TLS required| F["RDS PostgreSQL<br/>Table: processed_complaints"]
    E -->|UpdateItem| D
    
    D -.poll every 5s.-> E
    
    style B fill:#FF9900
    style C fill:#FF9900
    style D fill:#527FFF
    style F fill:#527FFF
    style E fill:#37475A
    style A fill:#146EB4
```

### Services Used

| Service | Purpose | Notes |
|---------|---------|-------|
| **API Gateway** | REST endpoint for complaint submission | `POST /complaints` |
| **Lambda** | Validate & store complaints | Triggered by API Gateway |
| **DynamoDB** | Temporary complaint storage | On-demand billing (perfect for Learner Lab) |
| **RDS PostgreSQL** | Persistent processed complaint storage | **TLS encryption MANDATORY** |
| **EC2 or Lambda** | Run Golang processor binary | Pre-compiled, just execute |
| **CloudWatch** | Logs & monitoring | All operations logged |

### IAM Permissions

Your **LabRole** includes all required permissions:
- ✅ API Gateway management
- ✅ Lambda invocation
- ✅ DynamoDB scan/write
- ✅ RDS management
- ✅ EC2 launch
- ✅ CloudWatch Logs

**No additional IAM configuration needed!**

---

## 📋 The 3 Phases

### Phase 1: Deploy API Endpoint (15 min)

**Goal:** Create HTTP API that receives and stores complaints

1. **Create DynamoDB Table**
   ```bash
   aws dynamodb create-table \
     --table-name complaints \
     --attribute-definitions \
       AttributeName=complaint_id,AttributeType=S \
       AttributeName=customer_id,AttributeType=S \
     --key-schema \
       AttributeName=complaint_id,KeyType=HASH \
       AttributeName=customer_id,KeyType=RANGE \
     --billing-mode PAY_PER_REQUEST \
     --region us-east-1
   ```

2. **Create Lambda Function** (receives complaints)
   - **Runtime:** Python 3.11
   - **Handler:** `index.lambda_handler`
   - **Trigger:** API Gateway POST `/complaints`
   - **Logic:**
     - Validate JSON: `{customer_id, message, severity}`
     - Generate: `complaint_id = "comp_" + UUID`
     - Store in DynamoDB with `processed = false`
     - Return: `{complaint_id, status: "received", timestamp}`

3. **Create API Gateway**
   - REST API
   - Method: `POST`
   - Resource: `/complaints`
   - Integration: Lambda function
   - CORS: Enabled

**Expected DynamoDB Entry:**
```json
{
  "complaint_id": "comp_abc123xyz",
  "customer_id": "cust_001",
  "message": "Your app crashed!",
  "severity": "high",
  "created_at": 1699951200,
  "processed": false
}
```

### Phase 2: Deploy Processor & Database (20 min)

**Goal:** Process complaints asynchronously with TLS encryption

1. **Create RDS PostgreSQL Instance**
   ```bash
   aws rds create-db-instance \
     --db-instance-identifier complaint-db \
     --db-instance-class db.t3.micro \
     --engine postgres \
     --master-username admin \
     --master-user-password MySecurePassword123! \
     --allocated-storage 20 \
     --storage-encrypted \
     --db-name complaints_db \
     --publicly-accessible true \
     --region us-east-1
   ```
   
   ⚠️ **Save the RDS Endpoint** (e.g., `complaint-db.xxxxx.us-east-1.rds.amazonaws.com`)

2. **Create PostgreSQL Table**
   ```sql
   CREATE TABLE processed_complaints (
       id SERIAL PRIMARY KEY,
       complaint_id VARCHAR(50) UNIQUE NOT NULL,
       customer_id VARCHAR(50) NOT NULL,
       message TEXT,
       severity_score INT CHECK(severity_score >= 1 AND severity_score <= 10),
       ai_category VARCHAR(20),
       processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
   );
   
   CREATE INDEX idx_complaint_id ON processed_complaints(complaint_id);
   CREATE INDEX idx_customer_id ON processed_complaints(customer_id);
   ```

3. **Deploy Golang Processor**
   
   You receive a pre-compiled binary `processor`. Deploy it on EC2 or run as Lambda function:
   
   **Option A: EC2**
   ```bash
   # On EC2 instance
   wget https://your-bucket/processor  # Download binary
   chmod +x processor
   
   # Set environment variables
   export AWS_REGION=us-east-1
   export COMPLAINTS_TABLE=complaints
   export RDS_HOST=complaint-db.xxxxx.us-east-1.rds.amazonaws.com
   export RDS_USER=admin
   export RDS_PASSWORD=MySecurePassword123!
   export RDS_DB=complaints_db
   
   # Download RDS certificate
   wget https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem \
     -O /tmp/rds-ca-bundle.pem
   
   # Run processor
   ./processor
   ```
   
   **Option B: Lambda (Scheduled)**
   - Upload binary as Lambda function layer
   - Trigger via EventBridge every minute

**Processor Behavior:**
- Scans DynamoDB every 5 seconds for `processed = false`
- **Enriches data:**
  - `severity_score` (1-10): Base score from severity + keyword bonuses
  - `ai_category`: Keyword matching
    - "billing" ← payment, refund, invoice, cost
    - "technical" ← bug, crash, error, broken
    - "shipping" ← shipping, delivery, package
    - "service" ← support, help, staff, rude
    - "other" ← default
- **Connects to RDS with TLS** (`sslmode=require`)
- **Inserts processed complaint** into PostgreSQL
- **Updates DynamoDB:** Sets `processed = true`
- **Logs to CloudWatch** all operations

**⚠️ CRITICAL: TLS Configuration**

Connection string MUST be:
```
postgres://admin:password@complaint-db.xxxxx.us-east-1.rds.amazonaws.com:5432/complaints_db?sslmode=require
```

❌ WRONG: No `sslmode=require`  
✅ RIGHT: With `sslmode=require`

### Phase 3: Testing & Validation (10 min)

**Goal:** Verify end-to-end data flow

1. **Send Test Complaint**
   ```bash
   curl -X POST https://YOUR_API_ENDPOINT/complaints \
     -H "Content-Type: application/json" \
     -d '{
       "customer_id": "cust_001",
       "message": "Your app crashed with a billing error!",
       "severity": "high"
     }'
   ```

2. **Check DynamoDB** (should have complaint with `processed=false`)
   ```bash
   aws dynamodb scan \
     --table-name complaints \
     --filter-expression "processed = :false" \
     --expression-attribute-values '{":false":{"BOOL":false}}'
   ```

3. **Wait 15 Seconds** (processor scans every 5 seconds)

4. **Verify PostgreSQL** (complaint should be processed)
   ```bash
   psql -h complaint-db.xxxxx.us-east-1.rds.amazonaws.com \
     -U admin -d complaints_db -c \
     "SELECT complaint_id, severity_score, ai_category FROM processed_complaints;"
   ```

5. **Check CloudWatch Logs**
   ```bash
   aws logs tail /aws/lambda/complaint-receiver --follow
   
   # If running on EC2, SSH and check processor output
   ```

6. **Expected PostgreSQL Entry**
   ```
   complaint_id    | comp_abc123xyz
   customer_id     | cust_001
   message         | Your app crashed with a billing error!
   severity_score  | 9
   ai_category     | technical
   processed_at    | 2024-11-14 10:30:00
   ```

---

## ✅ Success Checklist

- [ ] API Gateway endpoint created and accessible
- [ ] Lambda function deployed and receiving requests
- [ ] Complaint stored in DynamoDB with `processed=false`
- [ ] RDS PostgreSQL instance created and accessible
- [ ] Golang processor running (binary executing)
- [ ] RDS certificate downloaded and configured
- [ ] **TLS connection verified** (look for "TLS" in logs, not plain TCP)
- [ ] Complaint appears in PostgreSQL within 15 seconds
- [ ] Severity score calculated (1-10)
- [ ] AI category assigned correctly
- [ ] All operations logged in CloudWatch
- [ ] Multiple complaints processed without errors
- [ ] Zero unprocessed complaints after 2 minutes

---

## 🎯 Critical Points

⚠️ **TLS is MANDATORY**
- Database connection MUST use `sslmode=require`
- Download RDS CA certificate
- Verify in logs: check for TLS handshake messages

⚠️ **Environment Variables**
- RDS credentials in env vars, NOT hardcoded
- Processor needs: `RDS_HOST`, `RDS_USER`, `RDS_PASSWORD`, `RDS_DB`
- AWS credentials come from LabRole (no manual config needed)

⚠️ **Data Flow Timing**
- API response: < 200ms (P99)
- DynamoDB write: ~100ms
- Processor scan cycle: every 5 seconds
- RDS insert: ~500ms-1s
- **Total E2E: 5-10 seconds typical**

⚠️ **AWS Academy Learner Lab Notes**
- Lab session is **4 hours** (resets after)
- Use on-demand billing for DynamoDB/Lambda
- EC2 `t2.micro` instances are free tier
- Save RDS endpoint details before cleanup
- Export/document results before lab ends

---

## 📊 Data Schema Summary

### DynamoDB: complaints
```
PK: complaint_id (String)
SK: customer_id (String)
Attributes:
  - message (String)
  - severity (String: low/medium/high)
  - created_at (Number: Unix timestamp)
  - processed (Boolean)
```

### PostgreSQL: processed_complaints
```
id (Serial PK)
complaint_id (VARCHAR 50, UNIQUE)
customer_id (VARCHAR 50)
message (TEXT)
severity_score (INT 1-10)
ai_category (VARCHAR 20)
processed_at (TIMESTAMP)
```

---

## 🔧 AWS CLI Cheat Sheet

### DynamoDB
```bash
# Create table
aws dynamodb create-table --table-name complaints \
  --attribute-definitions AttributeName=complaint_id,AttributeType=S AttributeName=customer_id,AttributeType=S \
  --key-schema AttributeName=complaint_id,KeyType=HASH AttributeName=customer_id,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST

# Scan for unprocessed
aws dynamodb scan --table-name complaints \
  --filter-expression "processed = :false" \
  --expression-attribute-values '{":false":{"BOOL":false}}'

# Describe table
aws dynamodb describe-table --table-name complaints
```

### RDS
```bash
# Create instance
aws rds create-db-instance --db-instance-identifier complaint-db \
  --db-instance-class db.t3.micro --engine postgres \
  --master-username admin --master-user-password MyPassword123! \
  --allocated-storage 20 --storage-encrypted --db-name complaints_db \
  --publicly-accessible true

# Get endpoint
aws rds describe-db-instances --db-instance-identifier complaint-db \
  --query 'DBInstances[0].Endpoint.Address'

# Delete instance (cleanup)
aws rds delete-db-instance --db-instance-identifier complaint-db --skip-final-snapshot
```

### Lambda
```bash
# View logs
aws logs tail /aws/lambda/complaint-receiver --follow

# Create function
aws lambda create-function --function-name complaint-receiver \
  --runtime python3.11 --role arn:aws:iam::ACCOUNT_ID:role/LabRole \
  --handler index.lambda_handler --zip-file fileb://function.zip
```

---

## 📞 Troubleshooting

### API not responding
- Verify API Gateway is deployed
- Check Lambda function is receiving events
- View Lambda logs: `aws logs tail /aws/lambda/complaint-receiver --follow`

### Processor not processing
- Verify RDS instance is in "available" state
- Check processor is running: `ps aux | grep processor`
- Verify environment variables are set correctly
- Check DynamoDB has unprocessed items: `aws dynamodb scan --table-name complaints`

### TLS Connection Failed
- Download fresh certificate: `wget https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem`
- Verify `sslmode=require` in connection string
- Check RDS security group allows inbound on port 5432
- Verify RDS instance is publicly accessible

### DynamoDB Scan Returns Empty
- Send complaints via API first
- Check table name is exactly `complaints`
- Verify Lambda is writing to correct table

### PostgreSQL Query Fails
- Verify RDS endpoint is correct
- Check password is correct
- Verify database name is `complaints_db`
- Ensure RDS is publicly accessible

---

## 🏆 Scoring

| Score | Criteria |
|-------|----------|
| **100** | All phases complete, TLS verified, zero errors |
| **80** | All phases complete, minor issues |
| **60** | Phases 1-2 complete, processor not running |
| **40** | API & DynamoDB working, RDS issues |
| **0** | No TLS encryption or major components missing |

---

## � Tips for Success

1. **Phase 1 first** - Get API working before processor
2. **Test DynamoDB** - Use AWS console or CLI to verify writes
3. **TLS early** - Configure encryption before processor deployment
4. **Verify connectivity** - Test RDS connection manually with psql
5. **Check logs frequently** - CloudWatch is your debugging friend
6. **Document endpoints** - Save API Gateway URL, RDS endpoint, etc.
7. **Time management** - You have 45 minutes! Plan accordingly

---

## 🎓 What You'll Learn

- ✅ Serverless architecture (API Gateway + Lambda)
- ✅ NoSQL vs SQL databases
- ✅ Asynchronous processing patterns
- ✅ TLS/SSL encryption in production
- ✅ AWS IAM & managed roles
- ✅ CloudWatch monitoring & logs
- ✅ Database connections with Golang
- ✅ AWS CLI automation

---

**Good luck, cloud warrior! May your TLS handshakes succeed and your data flow smoothly!** 🚀

⏰ **45 minutes on the clock. Go build!** 🎮
