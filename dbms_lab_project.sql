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
CREATE ROLE 'Admin', 'RestaurantManager', 'DeliveryRider';

-- Granting Privileges
GRANT ALL PRIVILEGES ON FoodDeliveryPlatform.* TO 'Admin';
GRANT SELECT, UPDATE ON FoodDeliveryPlatform.MenuItems TO 'RestaurantManager';
GRANT SELECT ON FoodDeliveryPlatform.RiderDeliverySchedule TO 'DeliveryRider';