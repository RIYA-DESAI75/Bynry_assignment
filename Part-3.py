from flask import Flask, jsonify
from flask_sqlalchemy import SQLAlchemy
from datetime import datetime, timedelta
from sqlalchemy import func

# -----------------------------------
# App & Database setup
# -----------------------------------
app = Flask(__name__)

# Using SQLite for simplicity (assumption for take-home task)
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///stockflow.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)

# -----------------------------------
# Database Models
# -----------------------------------
# NOTE:
# These are simplified models just to support
# the low-stock alert use case.

class Company(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100))


class Warehouse(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100))
    company_id = db.Column(db.Integer)


class Product(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100))
    sku = db.Column(db.String(50))
    product_type = db.Column(db.String(50))  # e.g. simple / bundle


class Inventory(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(db.Integer)
    warehouse_id = db.Column(db.Integer)
    quantity = db.Column(db.Integer)


class Supplier(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100))
    contact_email = db.Column(db.String(100))


class ProductSupplier(db.Model):
    product_id = db.Column(db.Integer, primary_key=True)
    supplier_id = db.Column(db.Integer, primary_key=True)


class InventoryMovement(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(db.Integer)
    warehouse_id = db.Column(db.Integer)
    quantity_change = db.Column(db.Integer)
    reason = db.Column(db.String(50))  # sale / restock
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

# -----------------------------------
# Create tables
# -----------------------------------
# Ensures tables exist before API usage
with app.app_context():
    db.create_all()

# -----------------------------------
# Low Stock Alerts API
# -----------------------------------
@app.route('/api/companies/<int:company_id>/alerts/low-stock', methods=['GET'])
def low_stock_alerts(company_id):
    """
    APPROACH:
    1. Fetch inventory records for all warehouses of a company
    2. Apply product-type based low stock thresholds
    3. Consider only products with recent sales activity
    4. Calculate days until stockout using average daily sales
    5. Include supplier details for reordering
    """

    alerts = []

    # Business rule:
    # Low stock threshold varies by product type
    THRESHOLDS = {
        "simple": 20,
        "bundle": 10
    }

    # Assumption:
    # "Recent sales activity" = last 30 days
    thirty_days_ago = datetime.utcnow() - timedelta(days=30)

    # Fetch inventory along with product, warehouse, and supplier
    # EDGE CASE HANDLED:
    # - Multiple warehouses per company
    # - Each warehouse evaluated independently
    results = db.session.query(
        Inventory, Product, Warehouse, Supplier
    ).join(Product, Inventory.product_id == Product.id)\
     .join(Warehouse, Inventory.warehouse_id == Warehouse.id)\
     .join(ProductSupplier, Product.id == ProductSupplier.product_id)\
     .join(Supplier, Supplier.id == ProductSupplier.supplier_id)\
     .filter(Warehouse.company_id == company_id)\
     .all()

    for inventory, product, warehouse, supplier in results:

        # Get threshold based on product type
        # EDGE CASE:
        # If product_type is missing or unknown, use default threshold
        threshold = THRESHOLDS.get(product.product_type, 20)

        # Calculate total sales quantity in last 30 days
        # Sales are stored as negative quantity changes
        sales = db.session.query(
            func.abs(func.sum(InventoryMovement.quantity_change))
        ).filter(
            InventoryMovement.product_id == product.id,
            InventoryMovement.warehouse_id == warehouse.id,
            InventoryMovement.reason == 'sale',
            InventoryMovement.created_at >= thirty_days_ago
        ).scalar()

        # EDGE CASE:
        # If there are no recent sales, skip alert
        # Prevents false alerts for inactive products
        if not sales or sales == 0:
            continue

        # Calculate average daily sales
        # EDGE CASE:
        # Division by zero avoided because we skip zero sales above
        avg_daily_sales = sales / 30

        # Check if stock is below threshold
        if inventory.quantity <= threshold:

            # Calculate estimated days until stock runs out
            # EDGE CASE:
            # If stock is already zero, days_until_stockout becomes 0
            days_until_stockout = int(inventory.quantity / avg_daily_sales)

            alerts.append({
                "product_id": product.id,
                "product_name": product.name,
                "sku": product.sku,
                "warehouse_id": warehouse.id,
                "warehouse_name": warehouse.name,
                "current_stock": inventory.quantity,
                "threshold": threshold,
                "days_until_stockout": days_until_stockout,
                "supplier": {
                    "id": supplier.id,
                    "name": supplier.name,
                    "contact_email": supplier.contact_email
                }
            })

    # Final response includes total alerts for summary
    return jsonify({
        "alerts": alerts,
        "total_alerts": len(alerts)
    })

# -----------------------------------
# Run app
# -----------------------------------
if __name__ == "__main__":
    app.run(debug=True)
