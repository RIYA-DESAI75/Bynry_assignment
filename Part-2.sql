/* =========================================================
   COMPANIES
   ---------------------------------------------------------
   Stores tenant companies using the StockFlow platform.
   Each company can own multiple warehouses and products.
   ========================================================= */
CREATE TABLE companies (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,   /* Surrogate primary key */
    name VARCHAR(255) NOT NULL,                            /* Company display name */
    code VARCHAR(50) NOT NULL UNIQUE,                      /* Unique company identifier/code */
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL, /* Record creation time (UTC) */
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL, /* Last update timestamp */
    is_active SMALLINT DEFAULT 1 NOT NULL                  /* Soft delete / active flag */
);


/* =========================================================
   WAREHOUSES
   ---------------------------------------------------------
   Physical or logical storage locations owned by a company.
   A company can have multiple warehouses.
   ========================================================= */
CREATE TABLE warehouses (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,   /* Warehouse primary key */
    company_id BIGINT NOT NULL,                           /* Owning company */
    name VARCHAR(255) NOT NULL,                           /* Warehouse name */
    code VARCHAR(50) NOT NULL,                            /* Short warehouse code */
    address VARCHAR(1000),                                /* Optional address */
    is_active SMALLINT DEFAULT 1 NOT NULL,                /* Warehouse operational status */
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,

    /* Relationship: warehouse belongs to a company */
    CONSTRAINT fk_wh_company FOREIGN KEY (company_id) REFERENCES companies(id),

    /* Ensures warehouse codes are unique per company */
    CONSTRAINT uq_wh_company_code UNIQUE (company_id, code)
);


/* =========================================================
   SUPPLIERS
   ---------------------------------------------------------
   External vendors who supply products.
   Suppliers may supply multiple products.
   ========================================================= */
CREATE TABLE suppliers (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,   /* Supplier primary key */
    name VARCHAR(255) NOT NULL,                           /* Supplier name */
    code VARCHAR(50) NOT NULL UNIQUE,                     /* Supplier unique code */
    contact_email VARCHAR(255),                           /* Ordering contact email */
    contact_phone VARCHAR(50),                            /* Contact phone number */
    is_active SMALLINT DEFAULT 1 NOT NULL,                /* Supplier availability flag */
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
);


/* =========================================================
   PRODUCTS
   ---------------------------------------------------------
   Master product catalog per company.
   Products may be simple items or bundles.
   ========================================================= */
CREATE TABLE products (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,   /* Product primary key */
    company_id BIGINT NOT NULL,                           /* Owning company */
    sku VARCHAR(100) NOT NULL,                            /* Stock Keeping Unit */
    name VARCHAR(255) NOT NULL,                           /* Product name */
    description VARCHAR(2000),                            /* Optional description */
    is_bundle SMALLINT DEFAULT 0 NOT NULL,                /* 0 = simple, 1 = bundle */
    unit_of_measure VARCHAR(50),                          /* pcs, kg, liters, etc. */
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    is_active SMALLINT DEFAULT 1 NOT NULL,                /* Soft delete flag */

    /* Relationship: product belongs to a company */
    CONSTRAINT fk_product_company FOREIGN KEY (company_id) REFERENCES companies(id),

    /* SKU must be unique within a company */
    CONSTRAINT uq_product_company_sku UNIQUE (company_id, sku)
);


/* =========================================================
   PRODUCT_BUNDLES
   ---------------------------------------------------------
   Defines which products make up a bundle and in what
   quantity. Supports multi-component bundles.
   ========================================================= */
CREATE TABLE product_bundles (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,   /* Bundle mapping ID */
    bundle_product_id BIGINT NOT NULL,                    /* Parent bundle product */
    component_product_id BIGINT NOT NULL,                 /* Component product */
    quantity DECIMAL(10,2) NOT NULL,                      /* Quantity of component */
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,

    /* Relationships to product table */
    CONSTRAINT fk_bundle_parent FOREIGN KEY (bundle_product_id) REFERENCES products(id),
    CONSTRAINT fk_bundle_child FOREIGN KEY (component_product_id) REFERENCES products(id),

    /* Prevent duplicate bundle definitions */
    CONSTRAINT uq_bundle UNIQUE (bundle_product_id, component_product_id),

    /* Prevent a product from bundling itself */
    CONSTRAINT chk_no_self CHECK (bundle_product_id <> component_product_id)
);


/* =========================================================
   SUPPLIER_PRODUCTS
   ---------------------------------------------------------
   Many-to-many mapping between suppliers and products.
   Stores supplier-specific attributes.
   ========================================================= */
CREATE TABLE supplier_products (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,   /* Mapping primary key */
    supplier_id BIGINT NOT NULL,                          /* Supplier reference */
    product_id BIGINT NOT NULL,                           /* Product reference */
    supplier_sku VARCHAR(100),                            /* Supplier's SKU */
    lead_time_days INT,                                   /* Reorder lead time */
    is_preferred SMALLINT DEFAULT 0 NOT NULL,             /* Preferred supplier flag */
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,

    /* Relationships */
    CONSTRAINT fk_sp_supplier FOREIGN KEY (supplier_id) REFERENCES suppliers(id),
    CONSTRAINT fk_sp_product FOREIGN KEY (product_id) REFERENCES products(id),

    /* One row per supplier-product combination */
    CONSTRAINT uq_supplier_product UNIQUE (supplier_id, product_id)
);


/* =========================================================
   WAREHOUSE_INVENTORY
   ---------------------------------------------------------
   Current stock snapshot per product per warehouse.
   Supports reserved stock for pending orders.
   ========================================================= */
CREATE TABLE warehouse_inventory (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,   /* Inventory row ID */
    warehouse_id BIGINT NOT NULL,                         /* Warehouse reference */
    product_id BIGINT NOT NULL,                           /* Product reference */
    quantity DECIMAL(10,2) DEFAULT 0 NOT NULL,            /* Available stock */
    reserved_quantity DECIMAL(10,2) DEFAULT 0 NOT NULL,   /* Reserved stock */
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,

    /* Relationships */
    CONSTRAINT fk_inv_wh FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
    CONSTRAINT fk_inv_prod FOREIGN KEY (product_id) REFERENCES products(id),

    /* One inventory record per warehouse-product */
    CONSTRAINT uq_wh_product UNIQUE (warehouse_id, product_id),

    /* Data integrity rules */
    CONSTRAINT chk_qty CHECK (quantity >= 0),
    CONSTRAINT chk_reserved CHECK (reserved_quantity >= 0),
    CONSTRAINT chk_reserved_limit CHECK (reserved_quantity <= quantity)
);


/* =========================================================
   INVENTORY_TRANSACTIONS
   ---------------------------------------------------------
   Immutable audit log of all inventory movements.
   Used for tracking, reporting, and debugging.
   ========================================================= */
CREATE TABLE inventory_transactions (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,   /* Transaction ID */
    warehouse_id BIGINT NOT NULL,                         /* Warehouse reference */
    product_id BIGINT NOT NULL,                           /* Product reference */
    transaction_type VARCHAR(50) NOT NULL,                /* sale, restock, adjustment */
    quantity_change DECIMAL(10,2) NOT NULL,               /* +ve or -ve change */
    quantity_before DECIMAL(10,2) NOT NULL,               /* Stock before change */
    quantity_after DECIMAL(10,2) NOT NULL,                /* Stock after change */
    reference_id VARCHAR(100),                            /* Order ID / PO ID */
    notes VARCHAR(2000),                                  /* Additional notes */
    created_by VARCHAR(100),                              /* User/system identifier */
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    metadata VARCHAR(2000),                               /* Extensible metadata */

    /* Relationships */
    CONSTRAINT fk_tx_wh FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
    CONSTRAINT fk_tx_prod FOREIGN KEY (product_id) REFERENCES products(id)
);
