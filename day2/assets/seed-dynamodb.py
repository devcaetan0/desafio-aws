#!/usr/bin/env python3
"""
Seed DynamoDB with sample products for the e-commerce store
Run this after creating the DynamoDB tables
"""

import boto3
import os

# Initialize DynamoDB
dynamodb = boto3.resource("dynamodb", region_name=os.getenv("AWS_REGION", "us-east-1"))

# Reference tables
products_table = dynamodb.Table(os.getenv("PRODUCTS_TABLE", "products"))

# Sample products
SAMPLE_PRODUCTS = [
    {
        "product_id": "prod_001",
        "name": "Wireless Headphones",
        "price": 79.99,
        "description": "High-quality wireless headphones with noise cancellation",
        "category": "electronics",
        "stock": 50,
    },
    {
        "product_id": "prod_002",
        "name": "USB-C Cable",
        "price": 12.99,
        "description": "Fast charging USB-C cable, 2 meters",
        "category": "electronics",
        "stock": 200,
    },
    {
        "product_id": "prod_003",
        "name": "Phone Case",
        "price": 19.99,
        "description": "Protective phone case for major devices",
        "category": "accessories",
        "stock": 100,
    },
    {
        "product_id": "prod_004",
        "name": "Screen Protector",
        "price": 9.99,
        "description": "Tempered glass screen protector pack of 3",
        "category": "accessories",
        "stock": 150,
    },
    {
        "product_id": "prod_005",
        "name": "Portable Charger",
        "price": 39.99,
        "description": "20000mAh portable power bank with fast charging",
        "category": "electronics",
        "stock": 75,
    },
    {
        "product_id": "prod_006",
        "name": "Desk Lamp",
        "price": 34.99,
        "description": "LED desk lamp with adjustable brightness",
        "category": "office",
        "stock": 40,
    },
    {
        "product_id": "prod_007",
        "name": "Wireless Mouse",
        "price": 24.99,
        "description": "Ergonomic wireless mouse with precision tracking",
        "category": "electronics",
        "stock": 60,
    },
    {
        "product_id": "prod_008",
        "name": "USB Hub",
        "price": 29.99,
        "description": "7-port USB hub with power supply",
        "category": "electronics",
        "stock": 45,
    },
    {
        "product_id": "prod_009",
        "name": "HDMI Cable",
        "price": 14.99,
        "description": "High-speed HDMI 2.1 cable, 2 meters",
        "category": "electronics",
        "stock": 120,
    },
    {
        "product_id": "prod_010",
        "name": "Laptop Stand",
        "price": 49.99,
        "description": "Adjustable aluminum laptop stand",
        "category": "office",
        "stock": 35,
    },
    {
        "product_id": "prod_011",
        "name": "Keyboard",
        "price": 79.99,
        "description": "Mechanical keyboard with RGB lighting",
        "category": "electronics",
        "stock": 50,
    },
    {
        "product_id": "prod_012",
        "name": "Webcam",
        "price": 59.99,
        "description": "1080p HD webcam with built-in microphone",
        "category": "electronics",
        "stock": 30,
    },
    {
        "product_id": "prod_013",
        "name": "Monitor Arm",
        "price": 44.99,
        "description": "Adjustable monitor arm for single display",
        "category": "office",
        "stock": 25,
    },
    {
        "product_id": "prod_014",
        "name": "Cable Organizer",
        "price": 9.99,
        "description": "Set of 5 cable management organizers",
        "category": "accessories",
        "stock": 200,
    },
    {
        "product_id": "prod_015",
        "name": "Phone Stand",
        "price": 14.99,
        "description": "Adjustable phone stand for desk",
        "category": "accessories",
        "stock": 90,
    },
    {
        "product_id": "prod_016",
        "name": "External SSD",
        "price": 129.99,
        "description": "1TB portable SSD with USB-C, 1050MB/s",
        "category": "electronics",
        "stock": 20,
    },
    {
        "product_id": "prod_017",
        "name": "SD Card",
        "price": 24.99,
        "description": "128GB Class 10 SD card for cameras",
        "category": "electronics",
        "stock": 80,
    },
    {
        "product_id": "prod_018",
        "name": "Tripod",
        "price": 34.99,
        "description": "Portable camera tripod with phone holder",
        "category": "accessories",
        "stock": 40,
    },
    {
        "product_id": "prod_019",
        "name": "Ring Light",
        "price": 39.99,
        "description": "LED ring light with stand for streaming",
        "category": "electronics",
        "stock": 35,
    },
    {
        "product_id": "prod_020",
        "name": "Microphone",
        "price": 89.99,
        "description": "USB condenser microphone for streaming/podcasting",
        "category": "electronics",
        "stock": 25,
    },
]


def seed_products():
    """Insert sample products into DynamoDB"""
    print(f"Seeding {len(SAMPLE_PRODUCTS)} products into DynamoDB...")

    with products_table.batch_writer(batch_size=25) as batch:
        for product in SAMPLE_PRODUCTS:
            batch.put_item(Item=product)
            print(f"✓ Added: {product['name']}")

    print(f"\n✅ Successfully seeded {len(SAMPLE_PRODUCTS)} products!")


if __name__ == "__main__":
    try:
        seed_products()
    except Exception as e:
        print(f"❌ Error seeding products: {e}")
        exit(1)
