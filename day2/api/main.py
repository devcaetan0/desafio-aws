"""
E-Commerce API - FastAPI Backend
Handles products, orders, and shopping cart
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime
import boto3
import uuid
import os

# Initialize FastAPI app
app = FastAPI(title="E-Commerce API", version="1.0.0")

# Enable CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# DynamoDB client
dynamodb = boto3.resource("dynamodb", region_name=os.getenv("AWS_REGION", "us-east-1"))

# Table references
products_table = dynamodb.Table(os.getenv("PRODUCTS_TABLE", "products"))
orders_table = dynamodb.Table(os.getenv("ORDERS_TABLE", "orders"))
cart_table = dynamodb.Table(os.getenv("CART_TABLE", "cart"))


# Request/Response models
class CartItem(BaseModel):
    product_id: str
    quantity: int


class OrderItem(BaseModel):
    product_id: str
    quantity: int


class OrderRequest(BaseModel):
    customer_id: str
    items: list[OrderItem]


# Health check endpoint (REQUIRED)
@app.get("/health")
async def health_check():
    """Health check endpoint for ECS"""
    return {
        "status": "healthy",
        "service": "ecommerce-api",
        "timestamp": datetime.now().isoformat(),
    }


# Product endpoints
@app.get("/products")
async def list_products():
    """List all products"""
    try:
        response = products_table.scan()
        items = response.get("Items", [])
        return {"products": items, "count": len(items)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/products/{product_id}")
async def get_product(product_id: str):
    """Get specific product details"""
    try:
        response = products_table.get_item(Key={"product_id": product_id})
        if "Item" not in response:
            raise HTTPException(status_code=404, detail="Product not found")
        return response["Item"]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# Order endpoints
@app.post("/orders")
async def create_order(order_request: OrderRequest):
    """Create a new order"""
    try:
        order_id = f"ord_{uuid.uuid4().hex[:8]}"
        total_price = 0

        # Fetch products and calculate total
        items_with_prices = []
        for item in order_request.items:
            product = products_table.get_item(Key={"product_id": item.product_id})
            if "Item" not in product:
                raise HTTPException(status_code=404, detail=f"Product {item.product_id} not found")

            prod = product["Item"]
            item_total = prod["price"] * item.quantity
            total_price += item_total
            items_with_prices.append({
                "product_id": item.product_id,
                "name": prod.get("name"),
                "quantity": item.quantity,
                "price": prod["price"],
                "subtotal": item_total,
            })

        # Store order in DynamoDB
        orders_table.put_item(
            Item={
                "order_id": order_id,
                "customer_id": order_request.customer_id,
                "items": items_with_prices,
                "total_price": total_price,
                "status": "pending",
                "created_at": int(datetime.now().timestamp()),
            }
        )

        return {
            "order_id": order_id,
            "customer_id": order_request.customer_id,
            "status": "pending",
            "total": total_price,
            "timestamp": datetime.now().isoformat(),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/orders/{order_id}")
async def get_order(order_id: str):
    """Get order details"""
    try:
        # Note: order_id is PK, so need to scan with filter
        response = orders_table.scan(FilterExpression="order_id = :oid", ExpressionAttributeValues={":oid": order_id})
        items = response.get("Items", [])
        if not items:
            raise HTTPException(status_code=404, detail="Order not found")
        return items[0]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# Cart endpoints
@app.get("/cart/{cart_id}")
async def get_cart(cart_id: str):
    """Get shopping cart items"""
    try:
        response = cart_table.query(KeyConditionExpression="cart_id = :cid", ExpressionAttributeValues={":cid": cart_id})
        items = response.get("Items", [])
        return {"cart_id": cart_id, "items": items, "count": len(items)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/cart/{cart_id}")
async def add_to_cart(cart_id: str, item: CartItem):
    """Add item to cart"""
    try:
        # Get product to verify it exists
        product = products_table.get_item(Key={"product_id": item.product_id})
        if "Item" not in product:
            raise HTTPException(status_code=404, detail="Product not found")

        # Add to cart
        prod = product["Item"]
        cart_table.put_item(
            Item={
                "cart_id": cart_id,
                "product_id": item.product_id,
                "quantity": item.quantity,
                "price_at_time": prod["price"],
                "product_name": prod.get("name"),
            }
        )

        return {"status": "added", "product_id": item.product_id, "quantity": item.quantity}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/cart/{cart_id}/{product_id}")
async def remove_from_cart(cart_id: str, product_id: str):
    """Remove item from cart"""
    try:
        cart_table.delete_item(Key={"cart_id": cart_id, "product_id": product_id})
        return {"status": "removed", "product_id": product_id}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
