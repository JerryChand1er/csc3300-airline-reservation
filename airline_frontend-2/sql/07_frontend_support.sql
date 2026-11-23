/*
07_frontend_support.sql -- extra procedures and grants for the web app

RUN ORDER: create_tables, sample_data, views_procedures_triggers, security, then this file.
Run as an admin account (e.g. root). Needs MySQL 8.0.16 or later.

WHAT THIS FILE ADDS
   4 procedures  sp_new_booking, sp_add_leg, sp_assign_crew, sp_unassign_crew
   grants        the airline_agent role (the web app's login) may run them, and may
                 read the crew tables so the Crew page and crew reports work

The existing files are not changed. Like the other procedures, these run with their
creator's rights, so the agent login still has no INSERT/UPDATE/DELETE on any table:
every change goes through a procedure, and the triggers still check every rule.
*/

USE airline_reservation;

DELIMITER $$

/*
PROCEDURE sp_new_booking(passenger, flight, seat number, fare)
Creates a booking with one flight leg and one ticket, all or nothing: if any rule
rejects it (seat sold, bad seat, bad passenger), nothing is saved. The booking is
Confirmed because it is ticketed. Returns the new booking_id.
*/
DROP PROCEDURE IF EXISTS sp_new_booking$$
CREATE PROCEDURE sp_new_booking(
    IN p_passenger_id INT,
    IN p_flight_id    INT,
    IN p_seat_number  VARCHAR(4),
    IN p_fare         DECIMAL(10,2))
BEGIN
    DECLARE v_seat_id    INT;
    DECLARE v_booking_id INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM passenger WHERE passenger_id = p_passenger_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Passenger not found';
    END IF;

    SELECT seat_id INTO v_seat_id FROM seat
    WHERE flight_id = p_flight_id AND seat_number = p_seat_number FOR UPDATE;
    IF v_seat_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Seat does not exist on that flight';
    END IF;
    IF EXISTS (SELECT 1 FROM ticket WHERE seat_id = v_seat_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Seat is already sold';
    END IF;

    INSERT INTO booking (passenger_id, status) VALUES (p_passenger_id, 'Pending');
    SET v_booking_id = LAST_INSERT_ID();

    INSERT INTO itinerary_flight (booking_id, flight_id, sequence_number)
    VALUES (v_booking_id, p_flight_id, 1);

    INSERT INTO ticket (booking_id, seat_id, fare_paid)
    VALUES (v_booking_id, v_seat_id, p_fare);

    UPDATE booking SET status = 'Confirmed' WHERE booking_id = v_booking_id;

    COMMIT;

    SELECT v_booking_id AS booking_id;
END$$

/*
PROCEDURE sp_add_leg(booking, flight)
Adds the flight as the next leg of an open booking (a connecting flight). The
itinerary trigger checks that it starts where the previous leg ended and leaves
after it lands. Returns the new leg number.
*/
DROP PROCEDURE IF EXISTS sp_add_leg$$
CREATE PROCEDURE sp_add_leg(
    IN p_booking_id INT,
    IN p_flight_id  INT)
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_next   INT;

    SELECT status INTO v_status FROM booking WHERE booking_id = p_booking_id;
    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Booking not found';
    END IF;
    IF v_status = 'Cancelled' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot add a leg to a cancelled booking';
    END IF;

    SELECT COALESCE(MAX(sequence_number), 0) + 1 INTO v_next
    FROM itinerary_flight WHERE booking_id = p_booking_id;

    INSERT INTO itinerary_flight (booking_id, flight_id, sequence_number)
    VALUES (p_booking_id, p_flight_id, v_next);

    SELECT v_next AS leg;
END$$

/*
PROCEDURE sp_assign_crew(crew member, flight, role on flight)
Assigns a crew member to a flight. The crew_assignment triggers enforce the
certification, overlap, and 10-hour rest rules.
*/
DROP PROCEDURE IF EXISTS sp_assign_crew$$
CREATE PROCEDURE sp_assign_crew(
    IN p_crew_id        INT,
    IN p_flight_id      INT,
    IN p_role_on_flight VARCHAR(30))
BEGIN
    INSERT INTO crew_assignment (crew_id, flight_id, role_on_flight)
    VALUES (p_crew_id, p_flight_id, p_role_on_flight);

    SELECT p_crew_id AS crew_id, p_flight_id AS flight_id, p_role_on_flight AS role_on_flight;
END$$

/*
PROCEDURE sp_unassign_crew(crew member, flight)
Removes a crew member from a flight (so a schedule can be corrected and the
member assigned elsewhere). Returns the number of assignments removed.
*/
DROP PROCEDURE IF EXISTS sp_unassign_crew$$
CREATE PROCEDURE sp_unassign_crew(
    IN p_crew_id   INT,
    IN p_flight_id INT)
BEGIN
    DELETE FROM crew_assignment WHERE crew_id = p_crew_id AND flight_id = p_flight_id;
    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'That crew member is not assigned to that flight';
    END IF;
    SELECT 1 AS removed;
END$$

DELIMITER ;

-- GRANTS: still no INSERT / UPDATE / DELETE on any table for the app login.
GRANT EXECUTE ON PROCEDURE airline_reservation.sp_new_booking TO 'airline_agent';
GRANT EXECUTE ON PROCEDURE airline_reservation.sp_add_leg     TO 'airline_agent';
GRANT EXECUTE ON PROCEDURE airline_reservation.sp_assign_crew TO 'airline_agent';
GRANT EXECUTE ON PROCEDURE airline_reservation.sp_unassign_crew TO 'airline_agent';
GRANT SELECT ON airline_reservation.crew_member        TO 'airline_agent';
GRANT SELECT ON airline_reservation.crew_assignment    TO 'airline_agent';
GRANT SELECT ON airline_reservation.crew_certification TO 'airline_agent';
