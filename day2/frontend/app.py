"""
E-Commerce Frontend - Flask Web Application
Customer-facing storefront
"""

from flask import Flask, render_template, request, jsonify, session
import requests
import os
import uuid
from datetime import datetime

app = Flask(__name__)
app.secret_key = os.getenv("SECRET_KEY", "your-secret-key-change-in-production")

# API endpoint
API_URL = os.getenv("API_URL", "http://localhost:8000")


# Health check endpoint (REQUIRED for ECS)
@app.route("/health", methods=["GET"])
def health_check():
    """Health check endpoint for ECS"""
    return jsonify({
        "status": "healthy",
        "service": "ecommerce-frontend",
        "timestamp": datetime.now().isoformat(),
    }), 200


# Homepage - List all products
@app.route("/", methods=["GET"])
def index():
    """Display all products"""
    try:
        # Get products from API
        response = requests.get(f"{API_URL}/products", timeout=5)
        products = response.json().get("products", [])

        # Get or create cart session
        if "cart_id" not in session:
            session["cart_id"] = f"cart_{uuid.uuid4().hex[:8]}"

        # Get cart items
        cart_response = requests.get(
            f"{API_URL}/cart/{session['cart_id']}", timeout=5
        )
        cart_items = cart_response.json().get("items", [])
        cart_count = len(cart_items)

        return render_template(
            "index.html",
            products=products,
            cart_count=cart_count,
            cart_id=session["cart_id"],
        )
    except Exception as e:
        return f"Error loading products: {str(e)}", 500


# Product detail page
@app.route("/product/<product_id>", methods=["GET"])
def product_detail(product_id):
    """Show product details"""
    try:
        response = requests.get(f"{API_URL}/products/{product_id}", timeout=5)
        product = response.json()

        if "cart_id" not in session:
            session["cart_id"] = f"cart_{uuid.uuid4().hex[:8]}"

        return render_template(
            "product.html", product=product, cart_id=session["cart_id"]
        )
    except Exception as e:
        return f"Error loading product: {str(e)}", 500


# Shopping cart page
@app.route("/cart", methods=["GET"])
def view_cart():
    """Display shopping cart"""
    try:
        if "cart_id" not in session:
            session["cart_id"] = f"cart_{uuid.uuid4().hex[:8]}"

        # Get cart items
        response = requests.get(
            f"{API_URL}/cart/{session['cart_id']}", timeout=5
        )
        cart_data = response.json()
        items = cart_data.get("items", [])

        # Calculate total
        total = sum(item["price_at_time"] * item["quantity"] for item in items)

        return render_template(
            "cart.html", items=items, total=total, cart_id=session["cart_id"]
        )
    except Exception as e:
        return f"Error loading cart: {str(e)}", 500


# Add to cart API endpoint
@app.route("/api/cart/add", methods=["POST"])
def add_to_cart():
    """Add item to cart (API call)"""
    try:
        if "cart_id" not in session:
            session["cart_id"] = f"cart_{uuid.uuid4().hex[:8]}"

        data = request.json
        response = requests.post(
            f"{API_URL}/cart/{session['cart_id']}",
            json={
                "product_id": data["product_id"],
                "quantity": data.get("quantity", 1),
            },
            timeout=5,
        )

        return jsonify(response.json()), response.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# Remove from cart API endpoint
@app.route("/api/cart/remove/<product_id>", methods=["DELETE"])
def remove_from_cart(product_id):
    """Remove item from cart (API call)"""
    try:
        if "cart_id" not in session:
            return jsonify({"error": "No cart session"}), 400

        response = requests.delete(
            f"{API_URL}/cart/{session['cart_id']}/{product_id}",
            timeout=5,
        )

        return jsonify(response.json()), response.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# Checkout page
@app.route("/checkout", methods=["GET", "POST"])
def checkout():
    """Checkout page"""
    try:
        if "cart_id" not in session:
            return "No cart found", 400

        if request.method == "GET":
            # Display checkout form
            response = requests.get(
                f"{API_URL}/cart/{session['cart_id']}", timeout=5
            )
            cart_data = response.json()
            items = cart_data.get("items", [])
            total = sum(item["price_at_time"] * item["quantity"] for item in items)

            return render_template(
                "checkout.html", items=items, total=total, cart_id=session["cart_id"]
            )

        elif request.method == "POST":
            # Process order
            data = request.json

            # Get cart items
            cart_response = requests.get(
                f"{API_URL}/cart/{session['cart_id']}", timeout=5
            )
            cart_items = cart_response.json().get("items", [])

            if not cart_items:
                return jsonify({"error": "Cart is empty"}), 400

            # Create order
            order_items = [
                {"product_id": item["product_id"], "quantity": item["quantity"]}
                for item in cart_items
            ]

            order_response = requests.post(
                f"{API_URL}/orders",
                json={
                    "customer_id": data.get("customer_id", "guest"),
                    "items": order_items,
                },
                timeout=5,
            )

            order = order_response.json()

            # Clear cart from session (you could also clear from DynamoDB)
            session.pop("cart_id", None)

            return render_template("confirmation.html", order=order)

    except Exception as e:
        return f"Error during checkout: {str(e)}", 500


# Order confirmation page
@app.route("/order/<order_id>", methods=["GET"])
def order_confirmation(order_id):
    """Display order confirmation"""
    try:
        response = requests.get(f"{API_URL}/orders/{order_id}", timeout=5)
        order = response.json()
        return render_template("confirmation.html", order=order)
    except Exception as e:
        return f"Error loading order: {str(e)}", 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
