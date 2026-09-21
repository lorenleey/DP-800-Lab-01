/* ============================================================
   DP-800 - Lab 01
   Design and implement database objects with SQL
   Database: EcommerceDB
   ============================================================ */

-- 1. CREACIÓN DE LA BASE DE DATOS

 USE EcommerceDB;
 GO

 
/* ============================================================
   2. TABLAS PRINCIPALES
   ============================================================ */



 -- Crear tabla Supplier
 CREATE TABLE Supplier (
     SupplierID INT PRIMARY KEY IDENTITY(1,1),
     SupplierName NVARCHAR(100) NOT NULL UNIQUE,
     Country NVARCHAR(50) NOT NULL,
     Email NVARCHAR(100),
     Phone NVARCHAR(20),
     CreatedDate DATETIME2 DEFAULT GETUTCDATE()
 );

 -- Create tabla Category
 CREATE TABLE Category (
     CategoryID INT PRIMARY KEY IDENTITY(1,1),
     CategoryName NVARCHAR(100) NOT NULL UNIQUE,
     Description NVARCHAR(500)
 );

 -- Create tabla Product con constraints
 CREATE TABLE Product (
     ProductID INT PRIMARY KEY IDENTITY(1,1),
     ProductName NVARCHAR(100) NOT NULL,
     CategoryID INT NOT NULL,
     SupplierID INT NOT NULL,
     BasePrice DECIMAL(10,2) NOT NULL,
     StockQuantity INT NOT NULL DEFAULT 0,
     CreatedDate DATETIME2 DEFAULT GETUTCDATE(),
     CHECK (BasePrice > 0),
     CHECK (StockQuantity >= 0),
     FOREIGN KEY (CategoryID) REFERENCES Category(CategoryID),
     FOREIGN KEY (SupplierID) REFERENCES Supplier(SupplierID),
 );

 /* ============================================================
   3. ÍNDICES 
   ============================================================ */


 -- Crear índices
 CREATE INDEX IX_Category ON Product(CategoryID);
 CREATE INDEX IX_Supplier ON Product(SupplierID);

 GO

  
/* ============================================================
   4. DATOS DE EJEMPLO
   ============================================================ */

    USE EcommerceDB;
 GO

 -- Insertar datos en Supplier
 INSERT INTO Supplier (SupplierName, Country, Email, Phone)
 VALUES 
     ('Contoso Supplies', 'USA', 'contact@contoso.com', '555-0100'),
     ('Fabrikam Inc', 'Canada', 'sales@fabrikam.com', '555-0200');

 -- Insertar datos en Category
 INSERT INTO Category (CategoryName, Description)
 VALUES 
     ('Electronics', 'Electronic devices and accessories'),
     ('Clothing', 'Apparel and fashion items');

 -- Insertar datos en Product
 INSERT INTO Product (ProductName, CategoryID, SupplierID, BasePrice, StockQuantity)
 VALUES 
     ('Wireless Mouse', 1, 1, 29.99, 100),
     ('Cotton T-Shirt', 2, 2, 19.99, 250);
 GO

 /* ============================================================
   5. TABLAS TEMPORALES
   ============================================================ */

 -- Crear tabla temporal con los precios de los productos
 CREATE TABLE ProductPrice (
     PriceID INT PRIMARY KEY IDENTITY(1,1),
     ProductID INT NOT NULL,
     CurrentPrice DECIMAL(10,2) NOT NULL,
     EffectiveDate DATE,
     SysStartTime DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN,
     SysEndTime DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN,
     PERIOD FOR SYSTEM_TIME (SysStartTime, SysEndTime),
     FOREIGN KEY (ProductID) REFERENCES Product(ProductID)
 ) WITH (SYSTEM_VERSIONING = ON);
 GO

 -- Insertar datos iniciales en ProductPrice
 INSERT INTO ProductPrice (ProductID, CurrentPrice, EffectiveDate)
 VALUES (1, 99.99, '2025-01-01'), (2, 149.99, '2025-01-01');

 -- Actualizar precios y crear entradas para el historial
 UPDATE ProductPrice SET CurrentPrice = 109.99 WHERE ProductID = 1;
 GO


 -- Consulta de la tabla ProductPrice
 SELECT ProductID, CurrentPrice, SysStartTime, SysEndTime
 FROM ProductPrice
 FOR SYSTEM_TIME ALL
 WHERE ProductID = 1;



 /* ============================================================
   6. JSON
   ============================================================ */

 -- Agregar columna de metadata a Product (JSON requiere SQL Server 2025)
 ALTER TABLE Product ADD Metadata JSON;
 GO

 -- Agregar columna calculada indexada
 ALTER TABLE Product ADD MetadataColor AS JSON_VALUE(Metadata, '$.color');
 GO

 -- Crear índice en la columna calculada
 CREATE NONCLUSTERED INDEX IX_Product_Metadata_Color
     ON Product (MetadataColor);
 GO

 -- Actualizar los productos con metadata
 UPDATE Product SET Metadata = N'{"color":"blue","size":"large","material":"cotton"}'
 WHERE ProductID = 1;

 UPDATE Product SET Metadata = N'{"color":"red","size":"small","material":"silk"}'
 WHERE ProductID = 2;
 GO

 -- Consulta sobre la metadata sobre productos de color azul
 SELECT 
     ProductID,
     ProductName,
     JSON_VALUE(Metadata, '$.color') AS Color,
     JSON_VALUE(Metadata, '$.size') AS Size,
     JSON_VALUE(Metadata, '$.material') AS Material
 FROM Product
 WHERE JSON_VALUE(Metadata, '$.color') = 'blue';
 
/* ============================================================
   7. PARTICIONADO
   ============================================================ */
-- Crear una función de partición basada en las fechas de los pedidos
-- Usar RANGE RIGHT para mantener juntos los valores correspondientes al mismo día
 CREATE PARTITION FUNCTION PF_OrderDate (DATE)
     AS RANGE RIGHT FOR VALUES 
     ('2025-01-01', '2025-04-01', '2025-07-01', '2025-10-01');

-- Crear el esquema de partición utilizando el grupo de archivos PRIMARY
 CREATE PARTITION SCHEME PS_OrderDate
     AS PARTITION PF_OrderDate ALL TO ([PRIMARY]);

-- Crear la tabla Order particionada
-- Incluir OrderDate en la clave primaria para alinear el índice con el particionado
 CREATE TABLE [Order] (
     OrderID BIGINT IDENTITY(1,1),
     OrderDate DATE NOT NULL,
     CustomerName NVARCHAR(100) NOT NULL,
     TotalAmount DECIMAL(12,2) NOT NULL,
     OrderStatus NVARCHAR(20) DEFAULT 'Pending',
     CONSTRAINT PK_Order PRIMARY KEY (OrderID, OrderDate),
     CHECK (TotalAmount > 0),
     CHECK (OrderStatus IN ('Pending', 'Processing', 'Shipped', 'Delivered', 'Cancelled'))
 ) ON PS_OrderDate(OrderDate);

-- Crear un índice particionado
 CREATE NONCLUSTERED INDEX IX_Order_Customer
     ON [Order](CustomerName)
     ON PS_OrderDate(OrderDate);
 GO

-- Insertar pedidos de ejemplo
 INSERT INTO [Order] (OrderDate, CustomerName, TotalAmount, OrderStatus) VALUES
     ('2025-01-15', 'John Smith', 299.97, 'Delivered'),
     ('2025-02-20', 'Jane Doe', 149.99, 'Shipped'),
     ('2025-06-10', 'Bob Johnson', 449.95, 'Processing');
 GO

/* ============================================================
   8. SECUENCIA Y DETALLE DE PEDIDOS
   ============================================================ */
-- Crear una SEQUENCE para generar los identificadores de las líneas de pedido
 CREATE SEQUENCE OrderLineSequence
     START WITH 1
     INCREMENT BY 1;

-- Crear la tabla OrderDetail
 CREATE TABLE OrderDetail (
     OrderLineID INT PRIMARY KEY,
     OrderID BIGINT NOT NULL,
     OrderDate DATE NOT NULL,
     ProductID INT NOT NULL,
     Quantity INT NOT NULL,
     UnitPrice DECIMAL(10,2) NOT NULL,
     LineTotal AS (Quantity * UnitPrice),
     CHECK (Quantity > 0),
     CHECK (UnitPrice > 0),
     FOREIGN KEY (OrderID, OrderDate) REFERENCES [Order](OrderID, OrderDate),
     FOREIGN KEY (ProductID) REFERENCES Product(ProductID)
 );
 GO

-- Insertar detalles de pedidos utilizando la SEQUENCE
 INSERT INTO OrderDetail (OrderLineID, OrderID, OrderDate, ProductID, Quantity, UnitPrice)
 VALUES 
     (NEXT VALUE FOR OrderLineSequence, 1, '2025-01-15', 1, 2, 99.99),
     (NEXT VALUE FOR OrderLineSequence, 1, '2025-01-15', 2, 1, 149.99),
     (NEXT VALUE FOR OrderLineSequence, 2, '2025-02-20', 1, 3, 99.99);
 GO

 SELECT * FROM OrderDetail;
 /* ============================================================
   9. COMPROBACIONES
   ============================================================ */

-- Comprobar que las restricciones funcionan correctamente
-- Esta inserción debe fallar porque el precio es negativo
 INSERT INTO Product (ProductName, CategoryID, SupplierID, BasePrice, StockQuantity)
 VALUES ('Invalid', 1, 1, -50, 10);

-- Comprobar que las consultas sobre datos JSON funcionan correctamente
 SELECT ProductName, JSON_VALUE(Metadata, '$.color') AS Color
 FROM Product
 WHERE Metadata IS NOT NULL;

-- Comprobar la distribución de los registros entre las particiones
 SELECT $PARTITION.PF_OrderDate(OrderDate) AS Partition, COUNT(*) AS RecordCount
 FROM [Order]
 GROUP BY $PARTITION.PF_OrderDate(OrderDate);

-- Comprobar el historial de la tabla temporal SELECT ProductID, CurrentPrice, SysStartTime, SysEndTime
  SELECT ProductID, CurrentPrice, SysStartTime, SysEndTime
 FROM ProductPrice FOR SYSTEM_TIME ALL
 ORDER BY ProductID, SysStartTime;
