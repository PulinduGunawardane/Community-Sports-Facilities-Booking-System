/* ============================================================================
   COMMUNITY SPORTS FACILITIES BOOKING SYSTEM
   SQL Server (T-SQL) Database Script
   ----------------------------------------------------------------------------
   Sections:
     1. Database creation
     2. Table definitions (with constraints)
     3. Indexes
     4. Sample data (INSERT statements)
     5. Views
     6. Scalar / table-valued functions
     7. Stored procedures (transaction-safe booking + payment workflow)
     8. Triggers (defence-in-depth against double-booking)
     9. Example SELECT queries (for documentation / testing)
   ============================================================================ */

-- ============================================================================
-- 1. DATABASE CREATION
-- ============================================================================
IF DB_ID('SportsBookingDB') IS NULL
BEGIN
    CREATE DATABASE SportsBookingDB;
END
GO

USE SportsBookingDB;
GO

-- ============================================================================
-- 2. TABLE DEFINITIONS
-- ============================================================================

-- Drop in dependency order if re-running the script during development
IF OBJECT_ID('dbo.Inquiry', 'U') IS NOT NULL DROP TABLE dbo.Inquiry;
IF OBJECT_ID('dbo.Review', 'U') IS NOT NULL DROP TABLE dbo.Review;
IF OBJECT_ID('dbo.Payment', 'U') IS NOT NULL DROP TABLE dbo.Payment;
IF OBJECT_ID('dbo.Booking', 'U') IS NOT NULL DROP TABLE dbo.Booking;
IF OBJECT_ID('dbo.Facility', 'U') IS NOT NULL DROP TABLE dbo.Facility;
IF OBJECT_ID('dbo.MemberSportPreference', 'U') IS NOT NULL DROP TABLE dbo.MemberSportPreference;
IF OBJECT_ID('dbo.SportType', 'U') IS NOT NULL DROP TABLE dbo.SportType;
IF OBJECT_ID('dbo.Member', 'U') IS NOT NULL DROP TABLE dbo.Member;
GO

CREATE TABLE dbo.Member (
    MemberID        INT IDENTITY(1,1) PRIMARY KEY,
    FirstName       VARCHAR(50)     NOT NULL,
    LastName        VARCHAR(50)     NOT NULL,
    Email           VARCHAR(100)    NOT NULL UNIQUE,
    Phone           VARCHAR(20)     NULL,
    Address         VARCHAR(200)    NULL,
    PasswordHash    VARBINARY(256)  NOT NULL,   -- HASHBYTES('SHA2_256', password + salt)
    PasswordSalt    VARBINARY(128)  NOT NULL,
    RegisteredDate  DATETIME        NOT NULL DEFAULT GETDATE(),
    IsActive        BIT             NOT NULL DEFAULT 1
);

CREATE TABLE dbo.SportType (
    SportTypeID     INT IDENTITY(1,1) PRIMARY KEY,
    SportName       VARCHAR(50)     NOT NULL UNIQUE
);

CREATE TABLE dbo.MemberSportPreference (
    MemberID        INT NOT NULL,
    SportTypeID     INT NOT NULL,
    CONSTRAINT PK_MemberSportPreference PRIMARY KEY (MemberID, SportTypeID),
    CONSTRAINT FK_MSP_Member FOREIGN KEY (MemberID) REFERENCES dbo.Member(MemberID) ON DELETE CASCADE,
    CONSTRAINT FK_MSP_SportType FOREIGN KEY (SportTypeID) REFERENCES dbo.SportType(SportTypeID) ON DELETE CASCADE
);

CREATE TABLE dbo.Facility (
    FacilityID      INT IDENTITY(1,1) PRIMARY KEY,
    FacilityName    VARCHAR(100)    NOT NULL,
    FacilityType    VARCHAR(50)     NOT NULL,   -- e.g. Tennis Court, Soccer Field, Basketball Court
    Location        VARCHAR(150)    NOT NULL,
    Capacity        INT             NOT NULL CHECK (Capacity > 0),
    HourlyRate      DECIMAL(8,2)    NOT NULL CHECK (HourlyRate > 0),
    Status          VARCHAR(20)     NOT NULL DEFAULT 'Available'
                        CHECK (Status IN ('Available','Maintenance','Closed'))
);

CREATE TABLE dbo.Booking (
    BookingID       INT IDENTITY(1,1) PRIMARY KEY,
    MemberID        INT             NOT NULL,
    FacilityID      INT             NOT NULL,
    BookingDate     DATE            NOT NULL,
    StartTime       TIME(0)         NOT NULL,
    EndTime         TIME(0)         NOT NULL,
    Status          VARCHAR(20)     NOT NULL DEFAULT 'Pending'
                        CHECK (Status IN ('Pending','Confirmed','Cancelled','Completed')),
    CreatedAt       DATETIME        NOT NULL DEFAULT GETDATE(),
    CONSTRAINT FK_Booking_Member FOREIGN KEY (MemberID) REFERENCES dbo.Member(MemberID),
    CONSTRAINT FK_Booking_Facility FOREIGN KEY (FacilityID) REFERENCES dbo.Facility(FacilityID),
    CONSTRAINT CK_Booking_TimeOrder CHECK (EndTime > StartTime)
);

CREATE TABLE dbo.Payment (
    PaymentID       INT IDENTITY(1,1) PRIMARY KEY,
    BookingID       INT             NOT NULL UNIQUE,     -- 1:1 with Booking
    Amount          DECIMAL(8,2)    NOT NULL CHECK (Amount >= 0),
    PaymentMethod   VARCHAR(30)     NOT NULL
                        CHECK (PaymentMethod IN ('Card','PayPal','Cash')),
    PaymentStatus   VARCHAR(20)     NOT NULL DEFAULT 'Pending'
                        CHECK (PaymentStatus IN ('Pending','Paid','Failed','Refunded')),
    PaymentDate     DATETIME        NULL,
    TransactionRef  VARCHAR(50)     NULL,
    CONSTRAINT FK_Payment_Booking FOREIGN KEY (BookingID) REFERENCES dbo.Booking(BookingID)
);

CREATE TABLE dbo.Review (
    ReviewID        INT IDENTITY(1,1) PRIMARY KEY,
    MemberID        INT             NOT NULL,
    FacilityID      INT             NOT NULL,
    BookingID       INT             NULL,        -- links review to the booking it followed
    Rating          TINYINT         NOT NULL CHECK (Rating BETWEEN 1 AND 5),
    Comment         VARCHAR(500)    NULL,
    ReviewDate      DATETIME        NOT NULL DEFAULT GETDATE(),
    CONSTRAINT FK_Review_Member FOREIGN KEY (MemberID) REFERENCES dbo.Member(MemberID),
    CONSTRAINT FK_Review_Facility FOREIGN KEY (FacilityID) REFERENCES dbo.Facility(FacilityID),
    CONSTRAINT FK_Review_Booking FOREIGN KEY (BookingID) REFERENCES dbo.Booking(BookingID)
);

CREATE TABLE dbo.Inquiry (
    InquiryID       INT IDENTITY(1,1) PRIMARY KEY,
    GuestName       VARCHAR(100)    NOT NULL,
    GuestEmail      VARCHAR(100)    NOT NULL,
    FacilityID      INT             NULL,        -- optional: inquiry about a specific facility
    Message         VARCHAR(500)    NOT NULL,
    SubmittedDate   DATETIME        NOT NULL DEFAULT GETDATE(),
    Status          VARCHAR(20)     NOT NULL DEFAULT 'New'
                        CHECK (Status IN ('New','Responded','Closed')),
    CONSTRAINT FK_Inquiry_Facility FOREIGN KEY (FacilityID) REFERENCES dbo.Facility(FacilityID)
);
GO

-- ============================================================================
-- 3. INDEXES  (search + conflict-check performance)
-- ============================================================================
CREATE INDEX IX_Booking_Facility_Date ON dbo.Booking (FacilityID, BookingDate, Status);
CREATE INDEX IX_Member_Email ON dbo.Member (Email);
CREATE INDEX IX_Facility_Type_Location ON dbo.Facility (FacilityType, Location);
GO

-- ============================================================================
-- 4. SAMPLE DATA
-- ============================================================================

INSERT INTO dbo.SportType (SportName) VALUES
('Tennis'), ('Soccer'), ('Basketball'), ('Badminton'), ('Swimming');

INSERT INTO dbo.Facility (FacilityName, FacilityType, Location, Capacity, HourlyRate, Status) VALUES
('Central Tennis Court 1', 'Tennis Court', 'Riverside Sports Complex', 4, 15.00, 'Available'),
('Central Tennis Court 2', 'Tennis Court', 'Riverside Sports Complex', 4, 15.00, 'Available'),
('Greenfield Soccer Pitch', 'Soccer Field', 'Greenfield Park', 22, 40.00, 'Available'),
('Downtown Basketball Court', 'Basketball Court', 'Downtown Recreation Centre', 10, 20.00, 'Available'),
('Lakeside Badminton Hall', 'Badminton Court', 'Lakeside Community Hall', 4, 12.00, 'Maintenance');

-- Sample members (password/salt values are placeholders — the application
-- layer generates a real random salt and SHA2_256 hash at registration time)
INSERT INTO dbo.Member (FirstName, LastName, Email, Phone, Address, PasswordHash, PasswordSalt) VALUES
('Nadia', 'Perera', 'nadia.perera@example.com', '0771234567', '12 Lake Road, Colombo',
    HASHBYTES('SHA2_256', 'Passw0rd!' + '2f1a9c'), CAST('2f1a9c' AS VARBINARY(128))),
('Kasun', 'Silva', 'kasun.silva@example.com', '0779876543', '45 Hill Street, Kandy',
    HASHBYTES('SHA2_256', 'Passw0rd!' + '7b3e21'), CAST('7b3e21' AS VARBINARY(128)));

INSERT INTO dbo.MemberSportPreference (MemberID, SportTypeID) VALUES
(1, 1), (1, 3), (2, 2), (2, 4);

INSERT INTO dbo.Booking (MemberID, FacilityID, BookingDate, StartTime, EndTime, Status) VALUES
(1, 1, '2026-09-10', '10:00', '11:00', 'Confirmed'),
(2, 3, '2026-09-12', '16:00', '18:00', 'Confirmed');

INSERT INTO dbo.Payment (BookingID, Amount, PaymentMethod, PaymentStatus, PaymentDate, TransactionRef) VALUES
(1, 15.00, 'Card', 'Paid', GETDATE(), 'TXN-0001'),
(2, 80.00, 'Card', 'Paid', GETDATE(), 'TXN-0002');

INSERT INTO dbo.Review (MemberID, FacilityID, BookingID, Rating, Comment) VALUES
(1, 1, 1, 5, 'Court surface was excellent, well maintained.'),
(2, 3, 2, 4, 'Good pitch, lighting could be better in the evening.');

INSERT INTO dbo.Inquiry (GuestName, GuestEmail, FacilityID, Message) VALUES
('Ravi Fernando', 'ravi.f@example.com', 4, 'Do you offer group rates for basketball court bookings?');
GO

-- ============================================================================
-- 5. VIEWS
-- ============================================================================

-- Facility average rating + review count (used on facility search / detail pages)
CREATE OR ALTER VIEW dbo.vw_FacilityRatingSummary AS
SELECT
    f.FacilityID,
    f.FacilityName,
    f.FacilityType,
    f.Location,
    f.HourlyRate,
    f.Status,
    ISNULL(AVG(CAST(r.Rating AS DECIMAL(3,2))), 0) AS AverageRating,
    COUNT(r.ReviewID) AS ReviewCount
FROM dbo.Facility f
LEFT JOIN dbo.Review r ON r.FacilityID = f.FacilityID
GROUP BY f.FacilityID, f.FacilityName, f.FacilityType, f.Location, f.HourlyRate, f.Status;
GO

-- Upcoming (future, non-cancelled) bookings per facility — powers the search/availability screen
CREATE OR ALTER VIEW dbo.vw_UpcomingBookings AS
SELECT
    b.BookingID,
    f.FacilityID,
    f.FacilityName,
    b.BookingDate,
    b.StartTime,
    b.EndTime,
    b.Status,
    m.MemberID,
    m.FirstName + ' ' + m.LastName AS MemberName
FROM dbo.Booking b
JOIN dbo.Facility f ON f.FacilityID = b.FacilityID
JOIN dbo.Member m   ON m.MemberID = b.MemberID
WHERE b.BookingDate >= CAST(GETDATE() AS DATE)
  AND b.Status IN ('Pending','Confirmed');
GO

-- ============================================================================
-- 6. FUNCTIONS
-- ============================================================================

-- Scalar function: average rating for a single facility (used in Razor views / controllers)
CREATE OR ALTER FUNCTION dbo.fn_GetAverageRating (@FacilityID INT)
RETURNS DECIMAL(3,2)
AS
BEGIN
    DECLARE @AvgRating DECIMAL(3,2);
    SELECT @AvgRating = ISNULL(AVG(CAST(Rating AS DECIMAL(3,2))), 0)
    FROM dbo.Review
    WHERE FacilityID = @FacilityID;
    RETURN @AvgRating;
END
GO

-- Table-valued function: parameterised facility search (drives both the
-- member "Search Facilities" and guest "Restricted Search" features —
-- the MVC controller passes NULL for any filter the user leaves blank)
CREATE OR ALTER FUNCTION dbo.fn_SearchFacilities
(
    @FacilityType VARCHAR(50) = NULL,
    @Location     VARCHAR(150) = NULL,
    @BookingDate  DATE = NULL
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        f.FacilityID,
        f.FacilityName,
        f.FacilityType,
        f.Location,
        f.Capacity,
        f.HourlyRate,
        f.Status,
        CASE WHEN EXISTS (
            SELECT 1 FROM dbo.Booking b
            WHERE b.FacilityID = f.FacilityID
              AND b.BookingDate = @BookingDate
              AND b.Status IN ('Pending','Confirmed')
        ) THEN 'Partially Booked' ELSE 'Fully Open' END AS DayAvailability
    FROM dbo.Facility f
    WHERE f.Status = 'Available'
      AND (@FacilityType IS NULL OR f.FacilityType = @FacilityType)
      AND (@Location IS NULL OR f.Location LIKE '%' + @Location + '%')
);
GO

-- ============================================================================
-- 7. STORED PROCEDURES
-- ============================================================================

-- sp_CreateBooking
-- Advanced logic: wraps the availability check + insert in a single
-- transaction with SERIALIZABLE isolation on the check, so two members
-- booking the same slot at the same instant cannot both succeed
-- (classic double-booking race condition).
CREATE OR ALTER PROCEDURE dbo.sp_CreateBooking
    @MemberID     INT,
    @FacilityID   INT,
    @BookingDate  DATE,
    @StartTime    TIME(0),
    @EndTime      TIME(0),
    @NewBookingID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @EndTime <= @StartTime
    BEGIN
        RAISERROR('End time must be after start time.', 16, 1);
        RETURN;
    END

    BEGIN TRANSACTION;

    -- SERIALIZABLE + HOLDLOCK prevents phantom reads: no other transaction
    -- can insert a conflicting booking between this check and our insert.
    IF EXISTS (
        SELECT 1
        FROM dbo.Booking WITH (HOLDLOCK, ROWLOCK, SERIALIZABLE)
        WHERE FacilityID = @FacilityID
          AND BookingDate = @BookingDate
          AND Status IN ('Pending','Confirmed')
          AND @StartTime < EndTime
          AND @EndTime   > StartTime      -- standard interval-overlap test
    )
    BEGIN
        ROLLBACK TRANSACTION;
        RAISERROR('This facility is already booked for the selected time slot.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.Booking (MemberID, FacilityID, BookingDate, StartTime, EndTime, Status)
    VALUES (@MemberID, @FacilityID, @BookingDate, @StartTime, @EndTime, 'Pending');

    SET @NewBookingID = SCOPE_IDENTITY();

    -- Create the matching (unpaid) payment record so the checkout page has
    -- something to update once the simulated payment is submitted.
    INSERT INTO dbo.Payment (BookingID, Amount, PaymentMethod, PaymentStatus)
    SELECT @NewBookingID,
           f.HourlyRate * DATEDIFF(MINUTE, @StartTime, @EndTime) / 60.0,
           'Card',
           'Pending'
    FROM dbo.Facility f
    WHERE f.FacilityID = @FacilityID;

    COMMIT TRANSACTION;
END
GO

-- sp_ProcessPayment
-- Simulated payment confirmation: marks the payment Paid and the booking
-- Confirmed atomically. TransactionRef is generated server-side so the
-- front end never fabricates its own "proof of payment".
CREATE OR ALTER PROCEDURE dbo.sp_ProcessPayment
    @BookingID      INT,
    @PaymentMethod  VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM dbo.Payment WHERE BookingID = @BookingID AND PaymentStatus = 'Pending')
    BEGIN
        ROLLBACK TRANSACTION;
        RAISERROR('No pending payment found for this booking.', 16, 1);
        RETURN;
    END

    UPDATE dbo.Payment
    SET PaymentStatus  = 'Paid',
        PaymentMethod  = @PaymentMethod,
        PaymentDate    = GETDATE(),
        TransactionRef = CONCAT('TXN-', CONVERT(VARCHAR(36), NEWID()))
    WHERE BookingID = @BookingID;

    UPDATE dbo.Booking
    SET Status = 'Confirmed'
    WHERE BookingID = @BookingID;

    COMMIT TRANSACTION;
END
GO

-- sp_SubmitReview: a member may only review a facility they have an actual
-- (completed/confirmed) booking for — enforced in the procedure, not just the UI.
CREATE OR ALTER PROCEDURE dbo.sp_SubmitReview
    @MemberID   INT,
    @BookingID  INT,
    @Rating     TINYINT,
    @Comment    VARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FacilityID INT;

    SELECT @FacilityID = FacilityID
    FROM dbo.Booking
    WHERE BookingID = @BookingID
      AND MemberID = @MemberID
      AND Status IN ('Confirmed','Completed');

    IF @FacilityID IS NULL
    BEGIN
        RAISERROR('You can only review facilities from your own confirmed bookings.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.Review (MemberID, FacilityID, BookingID, Rating, Comment)
    VALUES (@MemberID, @FacilityID, @BookingID, @Rating, @Comment);
END
GO

-- ============================================================================
-- 8. TRIGGER (defence-in-depth against double-booking)
-- ============================================================================
-- Even though sp_CreateBooking already guards against overlaps, a trigger
-- catches any insert/update that bypasses the procedure (e.g. an ad-hoc
-- admin UPDATE), keeping the data consistent regardless of entry point.
CREATE OR ALTER TRIGGER dbo.trg_Booking_PreventOverlap
ON dbo.Booking
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.Booking b
          ON b.FacilityID = i.FacilityID
         AND b.BookingDate = i.BookingDate
         AND b.BookingID <> i.BookingID
         AND b.Status IN ('Pending','Confirmed')
         AND i.Status IN ('Pending','Confirmed')
         AND i.StartTime < b.EndTime
         AND i.EndTime   > b.StartTime
    )
    BEGIN
        RAISERROR('Trigger check failed: overlapping booking detected for this facility.', 16, 1);
        ROLLBACK TRANSACTION;
    END
END
GO

-- ============================================================================
-- 9. EXAMPLE SELECT QUERIES  (for the "Display Data" documentation section)
-- ============================================================================

-- 9a. All bookings with member and facility names
SELECT b.BookingID, m.FirstName + ' ' + m.LastName AS Member, f.FacilityName,
       b.BookingDate, b.StartTime, b.EndTime, b.Status
FROM dbo.Booking b
JOIN dbo.Member m ON m.MemberID = b.MemberID
JOIN dbo.Facility f ON f.FacilityID = b.FacilityID
ORDER BY b.BookingDate, b.StartTime;
GO

-- 9b. Facility availability search (drives the guest/member "Search Facilities" page)
SELECT * FROM dbo.fn_SearchFacilities('Tennis Court', 'Riverside', '2026-09-10');
GO

-- 9c. Facility ratings, best-rated first (drives the reviews page)
SELECT * FROM dbo.vw_FacilityRatingSummary ORDER BY AverageRating DESC;
GO

-- 9d. Booking + payment detail joined together (what a member sees in "My Bookings")
SELECT b.BookingID, f.FacilityName, b.BookingDate, b.StartTime, b.EndTime,
       b.Status AS BookingStatus, p.Amount, p.PaymentMethod, p.PaymentStatus, p.TransactionRef
FROM dbo.Booking b
JOIN dbo.Facility f ON f.FacilityID = b.FacilityID
LEFT JOIN dbo.Payment p ON p.BookingID = b.BookingID
ORDER BY b.BookingDate;
GO

-- 9e. Open (unresolved) guest inquiries, most recent first
SELECT InquiryID, GuestName, GuestEmail, Message, SubmittedDate, Status
FROM dbo.Inquiry
WHERE Status = 'New'
ORDER BY SubmittedDate DESC;
GO

-- 9f. Worked example: booking a facility through the stored procedure, then
--     confirming payment through the second procedure, end to end.
DECLARE @NewID INT;
EXEC dbo.sp_CreateBooking
     @MemberID = 1, @FacilityID = 2,
     @BookingDate = '2026-09-15', @StartTime = '09:00', @EndTime = '10:00',
     @NewBookingID = @NewID OUTPUT;

EXEC dbo.sp_ProcessPayment @BookingID = @NewID, @PaymentMethod = 'Card';

SELECT b.BookingID, b.Status AS BookingStatus, p.PaymentStatus, p.Amount, p.TransactionRef
FROM dbo.Booking b
JOIN dbo.Payment p ON p.BookingID = b.BookingID
WHERE b.BookingID = @NewID;
GO
