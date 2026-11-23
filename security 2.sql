-- 06_security.sql  --  Access control for airline_reservation
-- Run AFTER tables, data, views/procedures/triggers
-- Run as an admin account (e.g. root). Needs MySQL 8.0+.

-- Three roles, least privilege:
--   airline_reader : read-only, reports and views only
--   airline_agent  : read + book/cancel ONLY through procedures
--   airline_admin  : full control of this database only

USE airline_reservation;

-- 1. Roles 
DROP ROLE IF EXISTS 'airline_reader', 'airline_agent', 'airline_admin';
CREATE ROLE 'airline_reader', 'airline_agent', 'airline_admin';

-- 2. Reader: SELECT on views and non-sensitive tables
GRANT SELECT ON airline_reservation.v_flight_load        TO 'airline_reader';
GRANT SELECT ON airline_reservation.v_available_seats    TO 'airline_reader';
GRANT SELECT ON airline_reservation.v_booking_itinerary  TO 'airline_reader';
GRANT SELECT ON airline_reservation.flight               TO 'airline_reader';
GRANT SELECT ON airline_reservation.airport              TO 'airline_reader';
GRANT SELECT ON airline_reservation.aircraft_model       TO 'airline_reader';
GRANT SELECT ON airline_reservation.aircraft             TO 'airline_reader';
GRANT EXECUTE ON FUNCTION airline_reservation.fn_load_factor TO 'airline_reader';
-- No access to passenger, ticket, booking, or crew tables.

-- 3. Agent: reader + read bookings/passengers + book/cancel by procedure 
GRANT 'airline_reader' TO 'airline_agent';
GRANT SELECT ON airline_reservation.seat       TO 'airline_agent';
GRANT SELECT ON airline_reservation.booking    TO 'airline_agent';
GRANT SELECT ON airline_reservation.ticket     TO 'airline_agent';
GRANT SELECT ON airline_reservation.passenger  TO 'airline_agent';
GRANT EXECUTE ON PROCEDURE airline_reservation.sp_book_ticket     TO 'airline_agent';
GRANT EXECUTE ON PROCEDURE airline_reservation.sp_cancel_booking  TO 'airline_agent';
GRANT EXECUTE ON PROCEDURE airline_reservation.sp_flight_manifest TO 'airline_agent';
-- No INSERT / UPDATE / DELETE on any table: every change goes through
-- the procedures, which run the triggers and business-rule checks.

-- 4. Admin: everything, but only in this database 
GRANT ALL PRIVILEGES ON airline_reservation.* TO 'airline_admin';

-- 5. Users (dont use these passwords anywhere real) 
DROP USER IF EXISTS 'reader_user'@'localhost', 'agent_user'@'localhost', 'admin_user'@'localhost';
CREATE USER 'reader_user'@'localhost' IDENTIFIED BY 'Reader#2026pw';
CREATE USER 'agent_user'@'localhost'  IDENTIFIED BY 'Agent#2026pw';
CREATE USER 'admin_user'@'localhost'  IDENTIFIED BY 'Admin#2026pw';

GRANT 'airline_reader' TO 'reader_user'@'localhost';
GRANT 'airline_agent'  TO 'agent_user'@'localhost';
GRANT 'airline_admin'  TO 'admin_user'@'localhost';

-- roles must be switched on at login for the users to use them.
SET DEFAULT ROLE 'airline_reader' TO 'reader_user'@'localhost';
SET DEFAULT ROLE 'airline_agent'  TO 'agent_user'@'localhost';
SET DEFAULT ROLE 'airline_admin'  TO 'admin_user'@'localhost';

FLUSH PRIVILEGES;

-- 6. Check what each user can do 
-- SHOW GRANTS FOR 'reader_user'@'localhost' USING 'airline_reader';
-- SHOW GRANTS FOR 'agent_user'@'localhost'  USING 'airline_reader', 'airline_agent';