/*
RUN ORDER: create_tables, sample_data, then this file
DBMS: MySQL 8.0.16 or later.

WHAT THIS FILE CREATES
   3 views       v_flight_load, v_available_seats, v_booking_itinerary
   1 function    fn_load_factor
   3 procedures  sp_book_ticket, sp_cancel_booking, sp_flight_manifest
   7 triggers    on flight, crew_assignment, ticket, itinerary_flight
   4 helper procedures (sp_chk_...) that hold the rule logic the triggers call. Do not call these directly.

BUSINESS RULES ENFORCED BY THE TRIGGERS (from the requirements)
   * an aircraft cannot be on two overlapping flights
   * only an 'Active' aircraft can be scheduled (small extra rule)
   * a crew member cannot work two overlapping flights
   * a crew member needs at least 10 hours of rest between flights
   * a crew member must hold a valid (not expired) certification for the aircraft model of the flight
   * a ticket's seat must be on a flight in the ticket's booking
   * the legs of a booking must connect in order
   * cancelling a booking deletes its tickets (procedure)

*/

USE airline_reservation;


-- PART 1: VIEWS -----------------------------------------------------

-- Seats, tickets sold, and load factor for every flight.
CREATE OR REPLACE VIEW v_flight_load AS
SELECT f.flight_id,
       f.flight_number,
       o.code                                              AS origin,
       d.code                                              AS destination,
       f.departure_time,
       m.model_name                                        AS aircraft_model,
       COUNT(s.seat_id)                                    AS seats,
       COUNT(t.ticket_id)                                  AS tickets_sold,
       ROUND(100 * COUNT(t.ticket_id) / COUNT(s.seat_id), 1) AS load_factor_pct
FROM flight f
JOIN airport o        ON o.airport_id  = f.origin_airport_id
JOIN airport d        ON d.airport_id  = f.destination_airport_id
JOIN aircraft a       ON a.aircraft_id = f.aircraft_id
JOIN aircraft_model m ON m.model_id    = a.model_id
LEFT JOIN seat s      ON s.flight_id   = f.flight_id
LEFT JOIN ticket t    ON t.seat_id     = s.seat_id
GROUP BY f.flight_id, f.flight_number, o.code, d.code,
         f.departure_time, m.model_name;

-- Every seat that has not been sold. A seat is available when no ticket points to it (availability is derived, never stored).
CREATE OR REPLACE VIEW v_available_seats AS
SELECT s.seat_id,
       f.flight_id,
       f.flight_number,
       f.departure_time,
       s.seat_number,
       s.seat_class
FROM seat s
JOIN flight f      ON f.flight_id = s.flight_id
LEFT JOIN ticket t ON t.seat_id   = s.seat_id
WHERE t.ticket_id IS NULL;

-- One readable row per booking leg: passenger, flight, and airports.
CREATE OR REPLACE VIEW v_booking_itinerary AS
SELECT b.booking_id,
       CONCAT(p.first_name, ' ', p.last_name) AS passenger,
       b.status                               AS booking_status,
       i.sequence_number                      AS leg,
       f.flight_number,
       o.code                                 AS origin,
       d.code                                 AS destination,
       f.departure_time,
       f.arrival_time
FROM booking b
JOIN passenger p        ON p.passenger_id = b.passenger_id
JOIN itinerary_flight i ON i.booking_id   = b.booking_id
JOIN flight f           ON f.flight_id    = i.flight_id
JOIN airport o          ON o.airport_id   = f.origin_airport_id
JOIN airport d          ON d.airport_id   = f.destination_airport_id;




-- PART 2: ROUTINES AND TRIGGERS -----------------------------------------------------------------
-- DELIMITER $$ lets a routine body contain ; characters

DELIMITER $$

/*
FUNCTION fn_load_factor(flight_id)
Returns tickets sold as a percentage of seats on the flight.
*/
DROP FUNCTION IF EXISTS fn_load_factor$$
CREATE FUNCTION fn_load_factor(p_flight_id INT)
RETURNS DECIMAL(5,1)
READS SQL DATA
BEGIN
    DECLARE v_seats INT;
    DECLARE v_sold  INT;

    SELECT COUNT(*) INTO v_seats FROM seat WHERE flight_id = p_flight_id;
    SELECT COUNT(*) INTO v_sold
    FROM ticket t JOIN seat s ON s.seat_id = t.seat_id
    WHERE s.flight_id = p_flight_id;

    IF v_seats = 0 THEN
        RETURN NULL;
    END IF;
    RETURN ROUND(100 * v_sold / v_seats, 1);
END$$

/*
-- HELPER sp_chk_aircraft: rules for scheduling an aircraft.
p_check_status = 1 also requires the aircraft to be Active.
*/
DROP PROCEDURE IF EXISTS sp_chk_aircraft$$
CREATE PROCEDURE sp_chk_aircraft(
    IN p_flight_id    INT,
    IN p_aircraft_id  INT,
    IN p_dep          DATETIME,
    IN p_arr          DATETIME,
    IN p_check_status TINYINT)
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_msg    VARCHAR(128);

    IF p_check_status = 1 THEN
        SELECT status INTO v_status FROM aircraft WHERE aircraft_id = p_aircraft_id;
        IF v_status IS NOT NULL AND v_status <> 'Active' THEN
            SET v_msg = CONCAT('Aircraft ', p_aircraft_id, ' is not Active (', v_status, ') and cannot be scheduled');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
        END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM flight f
               WHERE f.aircraft_id    = p_aircraft_id
                 AND f.flight_id     <> COALESCE(p_flight_id, 0)
                 AND f.departure_time < p_arr
                 AND f.arrival_time   > p_dep) THEN
        SET v_msg = CONCAT('Aircraft ', p_aircraft_id, ' is already assigned to an overlapping flight');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;
END$$

/*
HELPER sp_chk_crew_assignment: certification, overlap, and rest.
p_old_crew / p_old_flight identify the row being updated (so it is not compared with itself); pass NULL for an insert.
*/
DROP PROCEDURE IF EXISTS sp_chk_crew_assignment$$
CREATE PROCEDURE sp_chk_crew_assignment(
    IN p_crew_id    INT,
    IN p_flight_id  INT,
    IN p_old_crew   INT,
    IN p_old_flight INT)
BEGIN
    DECLARE c_min_rest_hours INT DEFAULT 10;  
    DECLARE v_dep   DATETIME;
    DECLARE v_arr   DATETIME;
    DECLARE v_model INT;
    DECLARE v_msg   VARCHAR(128);

    SELECT f.departure_time, f.arrival_time, a.model_id
      INTO v_dep, v_arr, v_model
    FROM flight f
    JOIN aircraft a ON a.aircraft_id = f.aircraft_id
    WHERE f.flight_id = p_flight_id;

    IF v_dep IS NOT NULL THEN
        -- 1. Valid certification for this aircraft model on the flight date
        IF NOT EXISTS (SELECT 1 FROM crew_certification cc
                       WHERE cc.crew_id  = p_crew_id
                         AND cc.model_id = v_model
                         AND DATE(v_dep) BETWEEN cc.issue_date AND cc.expiration_date) THEN
            SET v_msg = CONCAT('Crew member ', p_crew_id, ' is not certified (or certification expired) for this aircraft model');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
        END IF;

        -- 2. No overlap with another flight of the same crew member
        IF EXISTS (SELECT 1 FROM crew_assignment ca
                   JOIN flight f2 ON f2.flight_id = ca.flight_id
                   WHERE ca.crew_id = p_crew_id
                     AND NOT (ca.crew_id <=> p_old_crew AND ca.flight_id <=> p_old_flight)
                     AND f2.flight_id <> p_flight_id
                     AND f2.departure_time < v_arr
                     AND f2.arrival_time   > v_dep) THEN
            SET v_msg = CONCAT('Crew member ', p_crew_id, ' is already assigned to an overlapping flight');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
        END IF;

        -- 3. Minimum rest between this flight and every other flight
        IF EXISTS (SELECT 1 FROM crew_assignment ca
                   JOIN flight f2 ON f2.flight_id = ca.flight_id
                   WHERE ca.crew_id = p_crew_id
                     AND NOT (ca.crew_id <=> p_old_crew AND ca.flight_id <=> p_old_flight)
                     AND f2.flight_id <> p_flight_id
                     AND f2.departure_time < v_arr + INTERVAL c_min_rest_hours HOUR
                     AND f2.arrival_time + INTERVAL c_min_rest_hours HOUR > v_dep) THEN
            SET v_msg = CONCAT('Crew member ', p_crew_id, ' needs at least ', c_min_rest_hours, ' hours of rest between flights');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
        END IF;
    END IF;
END$$

/*
HELPER sp_chk_ticket: a ticket needs an open booking, a seat on one of the booking's flights, and at most one ticket per flight.
p_exclude_ticket_id is the ticket being updated (0 for an insert).
*/
DROP PROCEDURE IF EXISTS sp_chk_ticket$$
CREATE PROCEDURE sp_chk_ticket(
    IN p_booking_id        INT,
    IN p_seat_id           INT,
    IN p_exclude_ticket_id INT)
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_flight INT;

    SELECT status    INTO v_status FROM booking WHERE booking_id = p_booking_id;
    SELECT flight_id INTO v_flight FROM seat    WHERE seat_id    = p_seat_id;

    IF v_status = 'Cancelled' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot issue a ticket on a cancelled booking';
    END IF;

    IF v_flight IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM itinerary_flight i
                       WHERE i.booking_id = p_booking_id AND i.flight_id = v_flight) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'That seat is on a flight that is not part of this booking';
        END IF;

        IF EXISTS (SELECT 1 FROM ticket t
                   JOIN seat s ON s.seat_id = t.seat_id
                   WHERE t.booking_id = p_booking_id
                     AND s.flight_id  = v_flight
                     AND t.ticket_id <> COALESCE(p_exclude_ticket_id, 0)) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This booking already has a ticket for that flight';
        END IF;
    END IF;
END$$

/*
HELPER sp_chk_leg: a leg must follow the previous leg (leg n-1): it must exist, end where this leg starts, and arrive before this leg departs.
*/
DROP PROCEDURE IF EXISTS sp_chk_leg$$
CREATE PROCEDURE sp_chk_leg(
    IN p_booking_id INT,
    IN p_flight_id  INT,
    IN p_seq        INT)
BEGIN
    DECLARE v_origin    INT;
    DECLARE v_dep       DATETIME;
    DECLARE v_prev_dest INT;
    DECLARE v_prev_arr  DATETIME;

    SELECT origin_airport_id, departure_time
      INTO v_origin, v_dep
    FROM flight WHERE flight_id = p_flight_id;

    IF p_seq > 1 AND v_origin IS NOT NULL THEN
        SELECT f.destination_airport_id, f.arrival_time
          INTO v_prev_dest, v_prev_arr
        FROM itinerary_flight i
        JOIN flight f ON f.flight_id = i.flight_id
        WHERE i.booking_id = p_booking_id AND i.sequence_number = p_seq - 1;

        IF v_prev_dest IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'The previous leg is missing: add legs in order';
        END IF;
        IF v_prev_dest <> v_origin THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This leg does not start at the airport where the previous leg ended';
        END IF;
        IF v_prev_arr >= v_dep THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This leg departs before the previous leg arrives';
        END IF;
    END IF;
END$$


-- TRIGGERS: each one calls a helper procedure above
DROP TRIGGER IF EXISTS trg_flight_bi$$
CREATE TRIGGER trg_flight_bi BEFORE INSERT ON flight
FOR EACH ROW
BEGIN
    CALL sp_chk_aircraft(NEW.flight_id, NEW.aircraft_id,
                         NEW.departure_time, NEW.arrival_time, 1);
END$$

DROP TRIGGER IF EXISTS trg_flight_bu$$
CREATE TRIGGER trg_flight_bu BEFORE UPDATE ON flight
FOR EACH ROW
BEGIN
    IF NEW.aircraft_id    <> OLD.aircraft_id
       OR NEW.departure_time <> OLD.departure_time
       OR NEW.arrival_time   <> OLD.arrival_time THEN
        CALL sp_chk_aircraft(OLD.flight_id, NEW.aircraft_id,
                             NEW.departure_time, NEW.arrival_time,
                             IF(NEW.aircraft_id <> OLD.aircraft_id, 1, 0));
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_crew_assignment_bi$$
CREATE TRIGGER trg_crew_assignment_bi BEFORE INSERT ON crew_assignment
FOR EACH ROW
BEGIN
    CALL sp_chk_crew_assignment(NEW.crew_id, NEW.flight_id, NULL, NULL);
END$$

DROP TRIGGER IF EXISTS trg_crew_assignment_bu$$
CREATE TRIGGER trg_crew_assignment_bu BEFORE UPDATE ON crew_assignment
FOR EACH ROW
BEGIN
    IF NEW.crew_id <> OLD.crew_id OR NEW.flight_id <> OLD.flight_id THEN
        CALL sp_chk_crew_assignment(NEW.crew_id, NEW.flight_id,
                                    OLD.crew_id, OLD.flight_id);
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_ticket_bi$$
CREATE TRIGGER trg_ticket_bi BEFORE INSERT ON ticket
FOR EACH ROW
BEGIN
    CALL sp_chk_ticket(NEW.booking_id, NEW.seat_id, 0);
END$$

DROP TRIGGER IF EXISTS trg_ticket_bu$$
CREATE TRIGGER trg_ticket_bu BEFORE UPDATE ON ticket
FOR EACH ROW
BEGIN
    IF NEW.booking_id <> OLD.booking_id OR NEW.seat_id <> OLD.seat_id THEN
        CALL sp_chk_ticket(NEW.booking_id, NEW.seat_id, OLD.ticket_id);
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_itinerary_flight_bi$$
CREATE TRIGGER trg_itinerary_flight_bi BEFORE INSERT ON itinerary_flight
FOR EACH ROW
BEGIN
    CALL sp_chk_leg(NEW.booking_id, NEW.flight_id, NEW.sequence_number);
END$$

/*
PROCEDURE sp_book_ticket(booking, flight, seat number, fare)
Issues a ticket for a seat on one flight of a booking. Checks that the booking is open and the seat 
exists and is unsold, then inserts the ticket (the ticket trigger confirms the flight belongs to the
booking). Ticketing a Pending booking sets it to Confirmed.
*/
DROP PROCEDURE IF EXISTS sp_book_ticket$$
CREATE PROCEDURE sp_book_ticket(
    IN p_booking_id  INT,
    IN p_flight_id   INT,
    IN p_seat_number VARCHAR(4),
    IN p_fare        DECIMAL(10,2))
BEGIN
    DECLARE v_status  VARCHAR(20);
    DECLARE v_seat_id INT;
    DECLARE v_ticket  INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT status INTO v_status FROM booking
    WHERE booking_id = p_booking_id FOR UPDATE;
    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Booking not found';
    END IF;
    IF v_status = 'Cancelled' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot issue a ticket on a cancelled booking';
    END IF;

    SELECT seat_id INTO v_seat_id FROM seat
    WHERE flight_id = p_flight_id AND seat_number = p_seat_number FOR UPDATE;
    IF v_seat_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Seat does not exist on that flight';
    END IF;
    IF EXISTS (SELECT 1 FROM ticket WHERE seat_id = v_seat_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Seat is already sold';
    END IF;

    INSERT INTO ticket (booking_id, seat_id, fare_paid)
    VALUES (p_booking_id, v_seat_id, p_fare);
    SET v_ticket = LAST_INSERT_ID();

    UPDATE booking SET status = 'Confirmed'
    WHERE booking_id = p_booking_id AND status = 'Pending';

    COMMIT;

    IF COALESCE(@sp_quiet, 0) = 0 THEN
        SELECT v_ticket AS ticket_id, p_booking_id AS booking_id,
               f.flight_number, p_seat_number AS seat_number, p_fare AS fare_paid
        FROM flight f WHERE f.flight_id = p_flight_id;
    END IF;
END$$

/*
PROCEDURE sp_cancel_booking(booking)
Deletes the booking's tickets (releasing the seats) and sets its status to Cancelled. The booking and its legs are kept as history.
*/
DROP PROCEDURE IF EXISTS sp_cancel_booking$$
CREATE PROCEDURE sp_cancel_booking(IN p_booking_id INT)
BEGIN
    DECLARE v_status   VARCHAR(20);
    DECLARE v_released INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT status INTO v_status FROM booking
    WHERE booking_id = p_booking_id FOR UPDATE;
    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Booking not found';
    END IF;
    IF v_status = 'Cancelled' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Booking is already cancelled';
    END IF;

    DELETE FROM ticket WHERE booking_id = p_booking_id;
    SET v_released = ROW_COUNT();
    UPDATE booking SET status = 'Cancelled' WHERE booking_id = p_booking_id;

    COMMIT;

    IF COALESCE(@sp_quiet, 0) = 0 THEN
        SELECT p_booking_id AS booking_id, 'Cancelled' AS status,
               v_released AS tickets_deleted;
    END IF;
END$$

/*
PROCEDURE sp_flight_manifest(flight)
Lists every sold seat on a flight with the passenger and fare.
*/
DROP PROCEDURE IF EXISTS sp_flight_manifest$$
CREATE PROCEDURE sp_flight_manifest(IN p_flight_id INT)
BEGIN
    SELECT s.seat_number,
           s.seat_class,
           CONCAT(p.first_name, ' ', p.last_name) AS passenger,
           b.booking_id,
           t.fare_paid
    FROM ticket t
    JOIN seat s      ON s.seat_id      = t.seat_id
    JOIN booking b   ON b.booking_id   = t.booking_id
    JOIN passenger p ON p.passenger_id = b.passenger_id
    WHERE s.flight_id = p_flight_id
    ORDER BY CAST(s.seat_number AS UNSIGNED), s.seat_number;
END$$

DELIMITER ;