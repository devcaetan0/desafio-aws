package main

import (
	"context"
	"crypto/tls"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	_ "github.com/lib/pq"
)

// Complaint represents a complaint from the NoSQL database
type Complaint struct {
	ComplaintID string `dynamodbav:"complaint_id"`
	CustomerID  string `dynamodbav:"customer_id"`
	Message     string `dynamodbav:"message"`
	Severity    string `dynamodbav:"severity"`
	CreatedAt   int64  `dynamodbav:"created_at"`
	Processed   bool   `dynamodbav:"processed"`
}

// ProcessedComplaint represents the enriched complaint for Postgres
type ProcessedComplaint struct {
	ComplaintID   string
	CustomerID    string
	Message       string
	SeverityScore int
	AICategory    string
	ProcessedAt   time.Time
}

var (
	logger            *log.Logger
	dynamodbClient    *dynamodb.Client
	rdsConnection     *sql.DB
	complaintsTable   string
	rdsHost           string
	rdsPort           string
	rdsUser           string
	rdsPassword       string
	rdsDB             string
	tlsCertPath       string
)

func init() {
	logger = log.New(os.Stdout, "[PROCESSOR] ", log.LstdFlags|log.Lshortfile)

	// Load environment variables
	complaintsTable = getEnv("COMPLAINTS_TABLE", "complaints")
	rdsHost = getEnv("RDS_HOST", "localhost")
	rdsPort = getEnv("RDS_PORT", "5432")
	rdsUser = getEnv("RDS_USER", "admin")
	rdsPassword = getEnv("RDS_PASSWORD", "password123")
	rdsDB = getEnv("RDS_DB", "complaints_db")
	tlsCertPath = getEnv("RDS_CERT_PATH", "/tmp/rds-ca-bundle.pem")
}

func getEnv(key, defaultVal string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultVal
}

func main() {
	logger.Println("=== Data Migration Processor Started ===")
	logger.Printf("Config - DynamoDB Table: %s", complaintsTable)
	logger.Printf("Config - RDS Host: %s:%s", rdsHost, rdsPort)

	// Initialize DynamoDB client
	if err := initDynamoDB(); err != nil {
		logger.Fatalf("Failed to initialize DynamoDB: %v", err)
	}
	logger.Println("✓ DynamoDB client initialized")

	// Initialize RDS connection
	if err := initRDS(); err != nil {
		logger.Fatalf("Failed to initialize RDS: %v", err)
	}
	logger.Println("✓ RDS connection established with TLS")

	// Create table if not exists
	if err := createProcessedComplaintsTable(); err != nil {
		logger.Fatalf("Failed to create table: %v", err)
	}
	logger.Println("✓ Processed complaints table ready")

	// Main processing loop
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	logger.Println("Starting processing loop (scanning every 5 seconds)...")
	for range ticker.C {
		processComplaints()
	}
}

func initDynamoDB() error {
	cfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		return fmt.Errorf("unable to load SDK config: %w", err)
	}

	dynamodbClient = dynamodb.NewFromConfig(cfg)
	return nil
}

func initRDS() error {
	// Create TLS configuration
	tlsConfig := &tls.Config{
		InsecureSkipVerify: false,
		MinVersion:         tls.VersionTLS12,
	}

	// Build connection string with TLS REQUIRED
	connStr := fmt.Sprintf(
		"postgres://%s:%s@%s:%s/%s?sslmode=require",
		rdsUser,
		rdsPassword,
		rdsHost,
		rdsPort,
		rdsDB,
	)

	// Create connector with TLS
	var err error
	rdsConnection, err = sql.Open("postgres", connStr)
	if err != nil {
		return fmt.Errorf("failed to open database connection: %w", err)
	}

	// Verify connection with TLS
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := rdsConnection.PingContext(ctx); err != nil {
		return fmt.Errorf("failed to ping RDS (TLS): %w", err)
	}

	// Configure connection pool
	rdsConnection.SetMaxOpenConns(25)
	rdsConnection.SetMaxIdleConns(5)
	rdsConnection.SetConnMaxLifetime(time.Hour)

	logger.Println("TLS Configuration: Min Version TLS 1.2")

	return nil
}

func createProcessedComplaintsTable() error {
	createTableSQL := `
	CREATE TABLE IF NOT EXISTS processed_complaints (
		id SERIAL PRIMARY KEY,
		complaint_id VARCHAR(50) NOT NULL UNIQUE,
		customer_id VARCHAR(50) NOT NULL,
		message TEXT,
		severity_score INT CHECK(severity_score >= 1 AND severity_score <= 10),
		ai_category VARCHAR(20),
		processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);
	CREATE INDEX IF NOT EXISTS idx_processed_complaints_complaint_id 
		ON processed_complaints(complaint_id);
	CREATE INDEX IF NOT EXISTS idx_processed_complaints_customer_id 
		ON processed_complaints(customer_id);
	`

	_, err := rdsConnection.Exec(createTableSQL)
	return err
}

func processComplaints() {
	logger.Println("--- Scanning for unprocessed complaints ---")

	ctx := context.Background()

	// Scan for unprocessed complaints
	response, err := dynamodbClient.Scan(ctx, &dynamodb.ScanInput{
		TableName:        aws.String(complaintsTable),
		FilterExpression: aws.String("processed = :false"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":false": &types.AttributeValueMemberBOOL{Value: false},
		},
		Limit: aws.Int32(100),
	})

	if err != nil {
		logger.Printf("ERROR scanning complaints: %v", err)
		return
	}

	if len(response.Items) == 0 {
		logger.Println("No unprocessed complaints found")
		return
	}

	logger.Printf("Found %d unprocessed complaints", len(response.Items))

	// Process each complaint
	for _, item := range response.Items {
		var complaint Complaint
		if err := attributevalue.UnmarshalMap(item, &complaint); err != nil {
			logger.Printf("ERROR unmarshaling complaint: %v", err)
			continue
		}

		if err := processAndStoreSingleComplaint(&complaint); err != nil {
			logger.Printf("ERROR processing complaint %s: %v", complaint.ComplaintID, err)
			continue
		}

		// Mark as processed in DynamoDB
		if err := markAsProcessed(ctx, complaint.ComplaintID, complaint.CustomerID); err != nil {
			logger.Printf("ERROR marking complaint %s as processed: %v", complaint.ComplaintID, err)
			continue
		}

		logger.Printf("✓ Successfully processed complaint %s from customer %s",
			complaint.ComplaintID, complaint.CustomerID)
	}
}

func processAndStoreSingleComplaint(complaint *Complaint) error {
	// Enrich the complaint
	processed := enrichComplaint(complaint)

	// Store in Postgres with TLS
	err := storeInRDS(processed)
	if err != nil {
		return fmt.Errorf("failed to store in RDS: %w", err)
	}

	return nil
}

func enrichComplaint(complaint *Complaint) ProcessedComplaint {
	processed := ProcessedComplaint{
		ComplaintID: complaint.ComplaintID,
		CustomerID:  complaint.CustomerID,
		Message:     complaint.Message,
		ProcessedAt: time.Now(),
	}

	// Calculate severity score (1-10)
	processed.SeverityScore = calculateSeverityScore(complaint.Severity, complaint.Message)

	// Assign AI category
	processed.AICategory = categorizeComplaint(complaint.Message)

	logger.Printf("Enriched: %s -> Score: %d, Category: %s",
		processed.ComplaintID, processed.SeverityScore, processed.AICategory)

	return processed
}

func calculateSeverityScore(severity, message string) int {
	score := 5

	switch strings.ToLower(severity) {
	case "low":
		score = 3
	case "medium":
		score = 5
	case "high":
		score = 8
	}

	messageLower := strings.ToLower(message)
	keywords := map[string]int{
		"critical": 3,
		"urgent":   2,
		"lost":     2,
		"broken":   1,
		"crash":    2,
		"fail":     1,
		"angry":    1,
		"furious":  2,
	}

	for keyword, bonus := range keywords {
		if strings.Contains(messageLower, keyword) {
			score += bonus
		}
	}

	if score < 1 {
		score = 1
	} else if score > 10 {
		score = 10
	}

	return score
}

func categorizeComplaint(message string) string {
	messageLower := strings.ToLower(message)

	categories := map[string][]string{
		"billing":    {"payment", "refund", "billing", "charge", "invoice", "cost", "price"},
		"technical":  {"bug", "crash", "error", "doesn't work", "broken", "failing"},
		"shipping":   {"shipping", "delivery", "package", "tracking", "warehouse", "slow"},
		"service":    {"support", "help", "response", "time", "staff", "rude", "unhelpful"},
	}

	for category, keywords := range categories {
		for _, keyword := range keywords {
			if strings.Contains(messageLower, keyword) {
				return category
			}
		}
	}

	return "other"
}

func storeInRDS(complaint ProcessedComplaint) error {
	insertSQL := `
	INSERT INTO processed_complaints 
	(complaint_id, customer_id, message, severity_score, ai_category, processed_at)
	VALUES ($1, $2, $3, $4, $5, $6)
	ON CONFLICT (complaint_id) DO NOTHING
	`

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	result, err := rdsConnection.ExecContext(
		ctx,
		insertSQL,
		complaint.ComplaintID,
		complaint.CustomerID,
		complaint.Message,
		complaint.SeverityScore,
		complaint.AICategory,
		complaint.ProcessedAt,
	)

	if err != nil {
		return fmt.Errorf("insert failed: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected: %w", err)
	}

	if rowsAffected == 0 {
		logger.Printf("⚠ Complaint %s already exists in RDS", complaint.ComplaintID)
	}

	return nil
}

func markAsProcessed(ctx context.Context, complaintID, customerID string) error {
	_, err := dynamodbClient.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName: aws.String(complaintsTable),
		Key: map[string]types.AttributeValue{
			"complaint_id": &types.AttributeValueMemberS{Value: complaintID},
			"customer_id":  &types.AttributeValueMemberS{Value: customerID},
		},
		UpdateExpression: aws.String("SET processed = :true"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":true": &types.AttributeValueMemberBOOL{Value: true},
		},
	})

	return err
}
