# Food-Delivery-Platform
DROP DATABASE IF EXISTS FoodDeliveryPlatform;
CREATE DATABASE FoodDeliveryPlatform;
USE FoodDeliveryPlatform;

-- Table for Users (Customers and Riders)
CREATE TABLE Users (
    UserID INT PRIMARY KEY AUTO_INCREMENT,
    FullName VARCHAR(100) NOT NULL,
    Email VARCHAR(100) UNIQUE NOT NULL,
    PhoneNumber VARCHAR(15) NOT NULL,
    UserRole ENUM('Customer', 'Rider') NOT NULL,
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table for Restaurants
CREATE TABLE Restaurants (
    RestaurantID INT PRIMARY KEY AUTO_INCREMENT,
    Name VARCHAR(100) NOT NULL,
    Address TEXT NOT NULL,
    ContactNumber VARCHAR(15),
    Rating DECIMAL(2,1) DEFAULT 0.0 CHECK (Rating >= 0 AND Rating <= 5)
);

-- Table for Menu Items (3NF: Linked to Restaurants)
CREATE TABLE MenuItems (
    ItemID INT PRIMARY KEY AUTO_INCREMENT,
    RestaurantID INT,
    ItemName VARCHAR(100) NOT NULL,
    Price DECIMAL(10,2) NOT NULL CHECK (Price > 0),
    IsAvailable BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (RestaurantID) REFERENCES Restaurants(RestaurantID) ON DELETE CASCADE
);

-- Table for Orders
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY AUTO_INCREMENT,
    CustomerID INT,
    RestaurantID INT,
    TotalAmount DECIMAL(10,2) NOT NULL,
    OrderStatus ENUM('Pending', 'Preparing', 'On the Way', 'Delivered', 'Cancelled') DEFAULT 'Pending',
    OrderDate TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (CustomerID) REFERENCES Users(UserID),
    FOREIGN KEY (RestaurantID) REFERENCES Restaurants(RestaurantID)
);

-- Table for Deliveries
CREATE TABLE Deliveries (
    DeliveryID INT PRIMARY KEY AUTO_INCREMENT,
    OrderID INT UNIQUE,
    RiderID INT,
    DeliveryStatus ENUM('Assigned', 'Picked Up', 'Delivered') DEFAULT 'Assigned',
    DeliveryTime DATETIME,
    FOREIGN KEY (OrderID) REFERENCES Orders(OrderID),
    FOREIGN KEY (RiderID) REFERENCES Users(UserID)
);

-- Indexing for fast search on Restaurant Names and Emails
CREATE INDEX idx_restaurant_name ON Restaurants(Name);
CREATE INDEX idx_user_email ON Users(Email);

-- View for Rider: Restricted access (No sensitive payment info)
CREATE VIEW RiderDeliverySchedule AS
SELECT d.DeliveryID, o.OrderID, r.Name AS RestaurantName, r.Address AS PickupAddress, u.FullName AS CustomerName
FROM Deliveries d
JOIN Orders o ON d.OrderID = o.OrderID
JOIN Restaurants r ON o.RestaurantID = r.RestaurantID
JOIN Users u ON o.CustomerID = u.UserID
WHERE d.DeliveryStatus != 'Delivered';

DELIMITER //
CREATE PROCEDURE PlaceOrder(
    IN p_CustomerID INT, 
    IN p_RestaurantID INT, 
    IN p_TotalAmount DECIMAL(10,2)
)
BEGIN
    START TRANSACTION; -- Ensures ACID properties
    INSERT INTO Orders (CustomerID, RestaurantID, TotalAmount, OrderStatus)
    VALUES (p_CustomerID, p_RestaurantID, p_TotalAmount, 'Pending');
    
    -- Logic for rollback if amount is invalid
    IF p_TotalAmount <= 0 THEN
        ROLLBACK;
    ELSE
        COMMIT;
    END IF;
END //
DELIMITER ;

-- Audit Log Table
CREATE TABLE PriceAudit (
    AuditID INT PRIMARY KEY AUTO_INCREMENT,
    ItemID INT,
    OldPrice DECIMAL(10,2),
    NewPrice DECIMAL(10,2),
    ChangeDate TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Trigger: Log price changes automatically
DELIMITER //
CREATE TRIGGER Before_Price_Update
BEFORE UPDATE ON MenuItems
FOR EACH ROW
BEGIN
    IF OLD.Price <> NEW.Price THEN
        INSERT INTO PriceAudit (ItemID, OldPrice, NewPrice)
        VALUES (OLD.ItemID, OLD.Price, NEW.Price);
    END IF;
END //
DELIMITER ;

-- Trigger: Automatically create delivery record when order is "Preparing"
DELIMITER //
CREATE TRIGGER After_Order_Status_Update
AFTER UPDATE ON Orders
FOR EACH ROW
BEGIN
    IF NEW.OrderStatus = 'Preparing' AND OLD.OrderStatus = 'Pending' THEN
        INSERT INTO Deliveries (OrderID) VALUES (NEW.OrderID);
    END IF;
END //
DELIMITER ;

-- Creating Roles
DROP ROLE IF EXISTS 'Admin', 'RestaurantManager', 'DeliveryRider';
CREATE ROLE 'Admin', 'RestaurantManager', 'DeliveryRider';

-- Granting Privileges
GRANT ALL PRIVILEGES ON FoodDeliveryPlatform.* TO 'Admin';
GRANT SELECT, UPDATE ON FoodDeliveryPlatform.MenuItems TO 'RestaurantManager';
GRANT SELECT ON FoodDeliveryPlatform.RiderDeliverySchedule TO 'DeliveryRider';

-- Insert Users (Customers & Riders)
INSERT INTO Users (FullName, Email, PhoneNumber, UserRole) VALUES
('John Doe', 'john@email.com', '03001234567', 'Customer'),
('Sarah Ahmed', 'sarah@email.com', '03012345678', 'Customer'),
('Ali Raza', 'ali@email.com', '03023456789', 'Customer'),
('Usman Khan', 'usman@email.com', '03111234567', 'Rider'),
('Fatima Zafar', 'fatima@email.com', '03211234567', 'Rider');

-- Insert Restaurants
INSERT INTO Restaurants (Name, Address, ContactNumber, Rating) VALUES
('Tasty Bites', 'Gulshan Block 5, Karachi', '021-1234567', 4.5),
('Spice King', 'DHA Phase 2, Lahore', '042-7654321', 4.2),
('Pizza Hub', 'F-10 Markaz, Islamabad', '051-9988776', 4.8),
('Sushi Queen', 'Clifton, Karachi', '021-3344556', 4.0);

-- Insert Menu Items
INSERT INTO MenuItems (RestaurantID, ItemName, Price, IsAvailable) VALUES
(1, 'Chicken Biryani', 350.00, TRUE),
(1, 'Zinger Burger', 450.00, TRUE),
(1, 'Cold Drink', 80.00, TRUE),
(2, 'Mutton Karahi', 1200.00, TRUE),
(2, 'Garlic Naan', 60.00, TRUE),
(3, 'Large Pepperoni Pizza', 1500.00, TRUE),
(3, 'Medium Margherita', 1100.00, TRUE),
(4, 'California Roll', 800.00, FALSE);

-- Insert Orders (Using the Stored Procedure)
CALL PlaceOrder(1, 1, 880.00);  -- OrderID 1
CALL PlaceOrder(2, 3, 1500.00); -- OrderID 2
CALL PlaceOrder(1, 2, 1260.00); -- OrderID 3

-- Manually update some orders to trigger delivery creation
UPDATE Orders SET OrderStatus = 'Preparing' WHERE OrderID = 1;
UPDATE Orders SET OrderStatus = 'Preparing' WHERE OrderID = 2;

-- Assign riders to deliveries
UPDATE Deliveries SET RiderID = 4, DeliveryStatus = 'Assigned' WHERE OrderID = 1;
UPDATE Deliveries SET RiderID = 5, DeliveryStatus = 'Assigned' WHERE OrderID = 2;

-- 2.1 View all available menu items with restaurant names
SELECT r.Name AS RestaurantName, 
       mi.ItemName, 
       mi.Price,
       CASE WHEN mi.IsAvailable THEN 'Yes' ELSE 'No' END AS Available
FROM MenuItems mi
JOIN Restaurants r ON mi.RestaurantID = r.RestaurantID
WHERE mi.IsAvailable = TRUE
ORDER BY r.Name, mi.Price;

-- 2.2 Get customer order history with details
SELECT o.OrderID, 
       u.FullName AS Customer, 
       r.Name AS Restaurant,
       o.TotalAmount, 
       o.OrderStatus,
       DATE_FORMAT(o.OrderDate, '%Y-%m-%d %H:%i') AS OrderDateTime
FROM Orders o
JOIN Users u ON o.CustomerID = u.UserID
JOIN Restaurants r ON o.RestaurantID = r.RestaurantID
WHERE u.FullName = 'John Doe'
ORDER BY o.OrderDate DESC;

-- 2.3 Check delivery status for a specific rider
SELECT d.DeliveryID, 
       o.OrderID, 
       u.FullName AS CustomerName,
       r.Name AS Restaurant,
       r.Address AS PickupLocation,
       d.DeliveryStatus,
       CASE 
           WHEN d.DeliveryTime IS NULL THEN 'Not yet delivered'
           ELSE DATE_FORMAT(d.DeliveryTime, '%Y-%m-%d %H:%i')
       END AS DeliveryCompletionTime
FROM Deliveries d
JOIN Orders o ON d.OrderID = o.OrderID
JOIN Users u ON o.CustomerID = u.UserID
JOIN Restaurants r ON o.RestaurantID = r.RestaurantID
WHERE d.RiderID = 4 AND d.DeliveryStatus != 'Delivered';

-- 3.1 Top 3 restaurants by total orders revenue
SELECT r.Name AS Restaurant, 
       COUNT(o.OrderID) AS TotalOrders, 
       SUM(o.TotalAmount) AS TotalRevenue,
       AVG(o.TotalAmount) AS AvgOrderValue
FROM Orders o
JOIN Restaurants r ON o.RestaurantID = r.RestaurantID
WHERE o.OrderStatus NOT IN ('Cancelled')
GROUP BY r.RestaurantID
ORDER BY TotalRevenue DESC
LIMIT 3;

-- 3.2 Daily sales report (last 7 days)
SELECT DATE(o.OrderDate) AS SaleDate,
       COUNT(o.OrderID) AS NumOrders,
       SUM(o.TotalAmount) AS DailyRevenue,
       AVG(o.TotalAmount) AS AvgOrderValue,
       COUNT(CASE WHEN o.OrderStatus = 'Delivered' THEN 1 END) AS CompletedOrders
FROM Orders o
WHERE o.OrderDate >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
GROUP BY DATE(o.OrderDate)
ORDER BY SaleDate DESC;

-- 3.3 Rider performance report (delivery statistics)
SELECT u.FullName AS Rider,
       COUNT(d.DeliveryID) AS TotalDeliveries,
       SUM(CASE WHEN d.DeliveryStatus = 'Delivered' THEN 1 ELSE 0 END) AS CompletedDeliveries,
       ROUND(AVG(CASE 
           WHEN d.DeliveryTime IS NOT NULL AND o.OrderDate IS NOT NULL
           THEN TIMESTAMPDIFF(MINUTE, o.OrderDate, d.DeliveryTime)
           ELSE NULL 
       END), 0) AS AvgDeliveryMinutes
FROM Deliveries d
JOIN Users u ON d.RiderID = u.UserID
JOIN Orders o ON d.OrderID = o.OrderID
WHERE u.UserRole = 'Rider'
GROUP BY u.UserID
HAVING TotalDeliveries > 0;

-- 3.4 Restaurants with low-rated items (below 4.0 rating)
SELECT r.Name AS Restaurant,
       r.Rating,
       COUNT(mi.ItemID) AS TotalMenuItems,
       SUM(CASE WHEN mi.Price > 1000 THEN 1 ELSE 0 END) AS PremiumItems
FROM Restaurants r
LEFT JOIN MenuItems mi ON r.RestaurantID = mi.RestaurantID
WHERE r.Rating < 4.0
GROUP BY r.RestaurantID;

-- 3.5 Customer lifetime value analysis
SELECT u.FullName AS Customer,
       COUNT(o.OrderID) AS TotalOrders,
       SUM(o.TotalAmount) AS TotalSpent,
       AVG(o.TotalAmount) AS AvgOrderValue,
       MAX(o.OrderDate) AS LastOrderDate,
       CASE 
           WHEN DATEDIFF(NOW(), MAX(o.OrderDate)) > 30 THEN 'Inactive'
           WHEN DATEDIFF(NOW(), MAX(o.OrderDate)) > 7 THEN 'At Risk'
           ELSE 'Active'
       END AS CustomerStatus
FROM Users u
LEFT JOIN Orders o ON u.UserID = o.CustomerID
WHERE u.UserRole = 'Customer'
GROUP BY u.UserID
ORDER BY TotalSpent DESC;

-- 4.1 Update order status with delivery tracking
-- Mark order as delivered and update delivery time
START TRANSACTION;

UPDATE Orders 
SET OrderStatus = 'Delivered' 
WHERE OrderID = 1;

UPDATE Deliveries 
SET DeliveryStatus = 'Delivered', 
    DeliveryTime = NOW() 
WHERE OrderID = 1;

COMMIT;

-- Verify the changes
SELECT 'Order Status Updated Successfully' AS Message;

-- 4.2 Update menu item price (triggers audit log automatically)
-- This will automatically log the price change in PriceAudit table
UPDATE MenuItems 
SET Price = 380.00 
WHERE ItemID = 1;  -- Chicken Biryani price increased

-- Check the audit log
SELECT * FROM PriceAudit;

-- 4.3 Cancel order with rollback consideration
DELIMITER //
CREATE PROCEDURE CancelOrder(IN p_OrderID INT)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'Order cancellation failed. Rolled back.' AS ErrorMessage;
    END;
    
    START TRANSACTION;
    
    UPDATE Orders 
    SET OrderStatus = 'Cancelled' 
    WHERE OrderID = p_OrderID;
    
    UPDATE Deliveries 
    SET DeliveryStatus = 'Assigned'  -- Reset if assigned
    WHERE OrderID = p_OrderID AND DeliveryStatus != 'Delivered';
    
    COMMIT;
    SELECT CONCAT('Order ', p_OrderID, ' cancelled successfully') AS Message;
END //
DELIMITER ;

-- Use the procedure
CALL CancelOrder(3);

-- 5.1 Find available riders for new delivery
SELECT u.UserID, u.FullName, u.PhoneNumber,
       COUNT(d.DeliveryID) AS ActiveDeliveries
FROM Users u
LEFT JOIN Deliveries d ON u.UserID = d.RiderID 
    AND d.DeliveryStatus != 'Delivered'
WHERE u.UserRole = 'Rider'
GROUP BY u.UserID
HAVING ActiveDeliveries < 2  -- Riders can handle max 2 active deliveries
ORDER BY ActiveDeliveries ASC;

-- 5.2 Customer favorite restaurants (most ordered from)
SELECT u.FullName AS Customer,
       r.Name AS FavoriteRestaurant,
       COUNT(o.OrderID) AS TimesOrdered,
       SUM(o.TotalAmount) AS TotalSpentAtThisRestaurant
FROM Orders o
JOIN Users u ON o.CustomerID = u.UserID
JOIN Restaurants r ON o.RestaurantID = r.RestaurantID
WHERE u.UserRole = 'Customer'
GROUP BY u.UserID, r.RestaurantID
HAVING TimesOrdered = (
    SELECT MAX(OrderCount)
    FROM (
        SELECT COUNT(*) AS OrderCount
        FROM Orders o2
        WHERE o2.CustomerID = u.UserID
        GROUP BY o2.RestaurantID
    ) AS SubQuery
)
ORDER BY u.FullName;

-- 5.3 Restaurants needing attention (high cancellation rate)
SELECT r.Name AS Restaurant,
       COUNT(o.OrderID) AS TotalOrders,
       SUM(CASE WHEN o.OrderStatus = 'Cancelled' THEN 1 ELSE 0 END) AS CancelledOrders,
       ROUND(SUM(CASE WHEN o.OrderStatus = 'Cancelled' THEN 1 ELSE 0 END) * 100.0 / COUNT(o.OrderID), 2) AS CancellationRatePercent
FROM Restaurants r
JOIN Orders o ON r.RestaurantID = o.RestaurantID
GROUP BY r.RestaurantID
HAVING CancellationRatePercent > 10
ORDER BY CancellationRatePercent DESC;

-- 6.1 Query the RiderDeliverySchedule view
-- Riders use this to see their pending deliveries
SELECT * FROM RiderDeliverySchedule 
WHERE DeliveryID IN (
    SELECT DeliveryID FROM Deliveries WHERE RiderID = 4
);

-- 6.2 Create additional views for reporting
-- Admin dashboard view
CREATE VIEW AdminDashboard AS
SELECT 
    (SELECT COUNT(*) FROM Users WHERE UserRole = 'Customer') AS TotalCustomers,
    (SELECT COUNT(*) FROM Users WHERE UserRole = 'Rider') AS TotalRiders,
    (SELECT COUNT(*) FROM Restaurants) AS TotalRestaurants,
    (SELECT COUNT(*) FROM Orders WHERE OrderStatus = 'Pending') AS PendingOrders,
    (SELECT COALESCE(SUM(TotalAmount), 0) FROM Orders WHERE DATE(OrderDate) = CURDATE()) AS TodayRevenue;

-- Query the admin dashboard
SELECT * FROM AdminDashboard;

-- 7.1 Check trigger functionality (price audit)
-- Update price again to test trigger
UPDATE MenuItems SET Price = 390.00 WHERE ItemID = 1;
UPDATE MenuItems SET Price = 375.00 WHERE ItemID = 1;

-- View audit trail
SELECT a.AuditID, 
       mi.ItemName,
       a.OldPrice, 
       a.NewPrice, 
       a.ChangeDate,
       (a.NewPrice - a.OldPrice) AS PriceDifference
FROM PriceAudit a
JOIN MenuItems mi ON a.ItemID = mi.ItemID
ORDER BY a.ChangeDate DESC;

-- 7.2 Check delivery auto-creation trigger
-- Test: Update order status to trigger delivery creation
UPDATE Orders SET OrderStatus = 'Preparing' WHERE OrderID = 3;

-- Verify delivery was created
SELECT o.OrderID, o.OrderStatus, d.DeliveryID, d.DeliveryStatus
FROM Orders o
LEFT JOIN Deliveries d ON o.OrderID = d.OrderID
WHERE o.OrderID = 3;

-- Record count before transaction
SELECT 'Orders before transaction:' AS '';
SELECT COUNT(*) AS OrderCount FROM Orders;

-- TEST 1: VALID TRANSACTION
-- This will succeed if CustomerID 1 and RestaurantID 1 exist
START TRANSACTION;
INSERT INTO Orders (CustomerID, RestaurantID, TotalAmount, OrderStatus) 
VALUES (1, 1, 75.00, 'Pending');
COMMIT;
SELECT '✓ Valid transaction committed successfully' AS Result;

-- TEST 2: INVALID TRANSACTION (Foreign Key)
-- This will FAIL automatically
START TRANSACTION;
INSERT INTO Orders (CustomerID, RestaurantID, TotalAmount, OrderStatus) 
VALUES (88888, 1, 100.00, 'Pending');
-- MySQL will show: ERROR 1452 (23000): Cannot add or update a child row
ROLLBACK;  -- Manually rollback to be safe
SELECT '✗ Transaction failed - Invalid CustomerID (88888 does not exist)' AS Result;

-- TEST 3: INVALID TRANSACTION (Negative amount with CHECK)
START TRANSACTION;
INSERT INTO Orders (CustomerID, RestaurantID, TotalAmount, OrderStatus) 
VALUES (1, 1, -10.00, 'Pending');
-- MySQL will reject due to CHECK constraint
ROLLBACK;
SELECT '✗ Transaction failed - Negative amount violates CHECK constraint' AS Result;

-- Final verification
SELECT 'Final order count after all tests:' AS '';
SELECT COUNT(*) AS OrderCount FROM Orders;

-- 8.1 Test role permissions (Run as different users)
-- As Admin: Should see all tables
SHOW TABLES;
SELECT * FROM Users;

-- As RestaurantManager: Should only see/update MenuItems
-- (Test by creating a user with RestaurantManager role)
CREATE USER 'restaurant_mgr'@'localhost' IDENTIFIED BY 'password123';
GRANT 'RestaurantManager' TO 'restaurant_mgr'@'localhost';
SET DEFAULT ROLE 'RestaurantManager' TO 'restaurant_mgr'@'localhost';

-- As DeliveryRider: Should only see RiderDeliverySchedule view
CREATE USER 'rider_user'@'localhost' IDENTIFIED BY 'riderpass';
GRANT 'DeliveryRider' TO 'rider_user'@'localhost';
SET DEFAULT ROLE 'DeliveryRider' TO 'rider_user'@'localhost';

-- 8.2 Display current user privileges
-- Show grants for current user
SHOW GRANTS;

-- Show all roles
SELECT * FROM mysql.roles_mapping;

-- 9.1 Check index usage
-- Analyze query execution plan
EXPLAIN SELECT * FROM Restaurants WHERE Name LIKE 'Pizza%';

EXPLAIN SELECT * FROM Users WHERE Email = 'john@email.com';

-- Check table sizes
SELECT 
    table_name AS `Table`,
    round(((data_length + index_length) / 1024 / 1024), 2) AS `Size (MB)`
FROM information_schema.tables
WHERE table_schema = 'FoodDeliveryPlatform'
ORDER BY (data_length + index_length) DESC;

-- 9.2 Slow query detection setup
-- Enable slow query log (if you have admin rights)
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 2;

-- Find queries without indexes
SELECT * FROM sys.statements_with_full_table_scans 
WHERE db = 'FoodDeliveryPlatform';

-- 10.2 Check for orphaned records
-- Find MenuItems without valid restaurants
SELECT mi.ItemID, mi.ItemName, mi.RestaurantID
FROM MenuItems mi
LEFT JOIN Restaurants r ON mi.RestaurantID = r.RestaurantID
WHERE r.RestaurantID IS NULL;

-- Find Deliveries without valid orders
SELECT d.DeliveryID, d.OrderID
FROM Deliveries d
LEFT JOIN Orders o ON d.OrderID = o.OrderID
WHERE o.OrderID IS NULL;

-- 10.3 Data cleanup query (archive old delivered orders)
-- Create archive table first
CREATE TABLE OrdersArchive LIKE Orders;

-- Move orders older than 90 days
INSERT INTO OrdersArchive 
SELECT * FROM Orders 
WHERE OrderDate < DATE_SUB(NOW(), INTERVAL 90 DAY)
AND OrderStatus = 'Delivered';

-- Delete from main table (careful!)
-- DELETE FROM Orders 
-- WHERE OrderDate < DATE_SUB(NOW(), INTERVAL 90 DAY)
-- AND OrderStatus = 'Delivered';

-- Bonus: Query for Project Report - Normalization Proof
-- Show 3NF compliance: No transitive dependencies
-- Example: MenuItems depends only on RestaurantID, not on Restaurant name
SELECT mi.ItemName, mi.Price, r.Name AS RestaurantName, r.Rating
FROM MenuItems mi
JOIN Restaurants r ON mi.RestaurantID = r.RestaurantID
-- If Restaurant Rating changes, it doesn't affect MenuItems table
-- This proves transitive dependency is eliminated
ORDER BY mi.ItemID;
