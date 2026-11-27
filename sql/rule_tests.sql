/*
WHAT THIS FILE DOES
   Creates one procedure, sp_run_rule_tests(). It tries to break each business rule, checks that 
   the database refuses with the expected message, and also checks that the stored procedures work. 
   It returns a report with one row per test (PASS or FAIL) and a summary.

HOW TO USE: run files all 4 other files first, then this file, then run:
       CALL sp_run_rule_tests();
   The call can be repeated at any time.


NOTE: the tests use the ids from airline_sample_data.sql. If you change the sample data, some tests may need new ids.
*/

USE airline_reservation;

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_run_rule_tests$$
CREATE PROCEDURE sp_run_rule_tests()
BEGIN
    DECLARE v_msg VARCHAR(255);

    SET @sp_quiet = 1;   -- hide the result sets of sp_book_ticket / sp_cancel_booking
    DROP TEMPORARY TABLE IF EXISTS rule_test_results;
    CREATE TEMPORARY TABLE rule_test_results (
        test_no        INT,
        rule_tested    VARCHAR(80),
        expected       VARCHAR(60),
        actual_message VARCHAR(255),
        result         VARCHAR(4)
    );

    -- 1. Aircraft cannot be on two overlapping flights
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO rule_test_results VALUES (1, 'Aircraft cannot overlap another flight', 'Rejected', v_msg,
                IF(v_msg LIKE 'Aircraft%overlapping flight%', 'PASS', 'FAIL'));
        END;
        INSERT INTO flight (flight_number, aircraft_id, origin_airport_id, destination_airport_id, departure_time, arrival_time)
        VALUES ('TEST01', 1, 2, 3, '2026-11-06 12:30:00', '2026-11-06 13:30:00');
        INSERT INTO rule_test_results VALUES (1, 'Aircraft cannot overlap another flight', 'Rejected', 'NOT REJECTED', 'FAIL');
    END;

    -- 2. Only an Active aircraft can be scheduled
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO rule_test_results VALUES (2, 'Only an Active aircraft can be scheduled', 'Rejected', v_msg,
                IF(v_msg LIKE '%not Active%', 'PASS', 'FAIL'));
        END;
        INSERT INTO flight (flight_number, aircraft_id, origin_airport_id, destination_airport_id, departure_time, arrival_time)
        VALUES ('TEST02', 4, 2, 3, '2026-11-20 12:00:00', '2026-11-20 13:00:00');
        INSERT INTO rule_test_results VALUES (2, 'Only an Active aircraft can be scheduled', 'Rejected', 'NOT REJECTED', 'FAIL');
    END;

    -- 3. A valid new flight is accepted (then removed)
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO rule_test_results VALUES (3, 'A valid new flight is accepted', 'Accepted', v_msg, 'FAIL');
        END;
        INSERT INTO flight (flight_number, aircraft_id, origin_airport_id, destination_airport_id, departure_time, arrival_time)
        VALUES ('TEST03', 2, 2, 1, '2026-11-12 12:00:00', '2026-11-12 13:05:00');
        DELETE FROM flight WHERE flight_number = 'TEST03';
        INSERT INTO rule_test_results VALUES (3, 'A valid new flight is accepted', 'Accepted', 'Accepted', 'PASS');
    END;

    -- 4. Crew member cannot work two overlapping flights
    --    (pilot 7 flies VA401 at 14:15; VA301 departs 14:00 and 7 is certified on it)
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO rule_test_results VALUES (4, 'Crew cannot work overlapping flights', 'Rejected', v_msg,
                IF(v_msg LIKE 'Crew member%overlapping flight%', 'PASS', 'FAIL'));
        END;
        INSERT INTO crew_assignment (crew_id, flight_id, role_on_flight) VALUES (7, 3, 'Captain');
        INSERT INTO rule_test_results VALUES (4, 'Crew cannot work overlapping flights', 'Rejected', 'NOT REJECTED', 'FAIL');
    END;

    -- 5. Crew need at least 10 hours of rest between flights
    --    (pilot 1 lands 13:05 on VA101; VA201 departs 14:00 and 1 is certified on it)
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO rule_test_results VALUES (5, 'Crew need 10 hours of rest between flights', 'Rejected', v_msg,
                IF(v_msg LIKE '%hours of rest%', 'PASS', 'FAIL'));
        END;
        INSERT INTO crew_assignment (crew_id, flight_id, role_on_flight) VALUES (1, 2, 'Captain');
        INSERT INTO rule_test_results VALUES (5, 'Crew need 10 hours of rest between flights', 'Rejected', 'NOT REJECTED', 'FAIL');
    END;

    -- 6. Crew must be certified on the aircraft model
    --    (pilot 1 holds no CRJ-700 certification; VA301 is a CRJ-700)
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO rule_test_results VALUES (6, 'Crew must be certified on the aircraft model', 'Rejected', v_msg,
                IF(v_msg LIKE '%not certified%', 'PASS', 'FAIL'));
        END;
        INSERT INTO crew_assignment (crew_id, flight_id, role_on_flight) VALUES (1, 3, 'Captain');
        INSERT INTO rule_test_results VALUES (6, 'Crew must be certified on the aircraft model', 'Rejected', 'NOT REJECTED', 'FAIL');
    END;

    -- 7. An expired certification does not count
    --    (attendant 12's CRJ-700 certification expired 2026-06-30)
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO rule_test_results VALUES (7, 'An expired certification does not count', 'Rejected', v_msg,
                IF(v_msg LIKE '%not certified%', 'PASS', 'FAIL'));
        END;
        INSERT INTO crew_assignment (crew_id, flight_id, role_on_flight) VALUES (12, 7, 'Attendant');
        INSERT INTO rule_test_results VALUES (7, 'An expired certification does not count', 'Rejected', 'NOT REJECTED', 'FAIL');
    END;

    -- 8. Ticket seat must be on a flight in the booking
    --    (booking 8 is only flight VA103; the seat is on VA101)
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO rule_test_results VALUES (8, 'Ticket seat must be on a flight in the booking', 'Rejected', v_msg,
                IF(v_msg LIKE '%not part of this booking%', 'PASS', 'FAIL'));
        END;
        INSERT INTO ticket (booking_id, seat_id, fare_paid)
        SELECT 8, seat_id, 100.00 FROM seat WHERE flight_id = 1 AND seat_number = '2A';
        INSERT INTO rule_test_results VALUES (8, 'Ticket seat must be on a flight in the booking', 'Rejected', 'NOT REJECTED', 'FAIL');
    END;

    -- 9. A seat can be sold only once
    --    (seat 9C on VA301 is already sold to booking 4; booking 11 is for VA301)
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO rule_test_results VALUES (9, 'A seat can be sold only once', 'Rejected', v_msg,
                IF(v_msg LIKE 'Duplicate entry%', 'PASS', 'FAIL'));
        END;
        INSERT INTO ticket (booking_id, seat_id, fare_paid)
        SELECT 11, seat_id, 100.00 FROM seat WHERE flight_id = 3 AND seat_number = '9C';
        INSERT INTO rule_test_results VALUES (9, 'A seat can be sold only once', 'Rejected', 'NOT REJECTED', 'FAIL');
    END;

    -- 10. No ticket on a cancelled booking (booking 13 is cancelled)
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO rule_test_results VALUES (10, 'No ticket on a cancelled booking', 'Rejected', v_msg,
                IF(v_msg LIKE '%cancelled booking%', 'PASS', 'FAIL'));
        END;
        INSERT INTO ticket (booking_id, seat_id, fare_paid)
        SELECT 13, seat_id, 100.00 FROM seat WHERE flight_id = 2 AND seat_number = '2A';
        INSERT INTO rule_test_results VALUES (10, 'No ticket on a cancelled booking', 'Rejected', 'NOT REJECTED', 'FAIL');
    END;

    -- 11. Legs must connect (booking 8 ends in CLT; VA401 leaves ATL)
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO rule_test_results VALUES (11, 'Legs must connect airport to airport', 'Rejected', v_msg,
                IF(v_msg LIKE '%does not start%', 'PASS', 'FAIL'));
        END;
        INSERT INTO itinerary_flight (booking_id, flight_id, sequence_number) VALUES (8, 4, 2);
        INSERT INTO rule_test_results VALUES (11, 'Legs must connect airport to airport', 'Rejected', 'NOT REJECTED', 'FAIL');
    END;

    -- 12. Legs must be added in order (booking 15 has only leg 1)
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO rule_test_results VALUES (12, 'Legs must be added in order', 'Rejected', v_msg,
                IF(v_msg LIKE '%previous leg is missing%', 'PASS', 'FAIL'));
        END;
        INSERT INTO itinerary_flight (booking_id, flight_id, sequence_number) VALUES (15, 5, 3);
        INSERT INTO rule_test_results VALUES (12, 'Legs must be added in order', 'Rejected', 'NOT REJECTED', 'FAIL');
    END;

    -- 13. A flight must arrive after it departs (check constraint)
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO rule_test_results VALUES (13, 'Flight must arrive after it departs', 'Rejected', v_msg,
                IF(v_msg LIKE '%chk_flight_times%', 'PASS', 'FAIL'));
        END;
        INSERT INTO flight (flight_number, aircraft_id, origin_airport_id, destination_airport_id, departure_time, arrival_time)
        VALUES ('TEST13', 2, 2, 1, '2026-11-13 14:00:00', '2026-11-13 13:00:00');
        INSERT INTO rule_test_results VALUES (13, 'Flight must arrive after it departs', 'Rejected', 'NOT REJECTED', 'FAIL');
    END;

    -- 14. sp_book_ticket refuses a seat that is already sold
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO rule_test_results VALUES (14, 'sp_book_ticket refuses a sold seat', 'Rejected', v_msg,
                IF(v_msg LIKE '%already sold%', 'PASS', 'FAIL'));
        END;
        CALL sp_book_ticket(11, 3, '9C', 100.00);
        INSERT INTO rule_test_results VALUES (14, 'sp_book_ticket refuses a sold seat', 'Rejected', 'NOT REJECTED', 'FAIL');
    END;

    -- 15. sp_book_ticket issues a ticket and confirms the Pending booking 11
    BEGIN
        DECLARE v_status VARCHAR(20);
        DECLARE v_count  INT;
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO rule_test_results VALUES (15, 'sp_book_ticket issues a ticket', 'Accepted', v_msg, 'FAIL');
        END;
        CALL sp_book_ticket(11, 3, '12A', 149.00);
        SELECT status INTO v_status FROM booking WHERE booking_id = 11;
        SELECT COUNT(*) INTO v_count FROM ticket WHERE booking_id = 11;
        INSERT INTO rule_test_results VALUES (15, 'sp_book_ticket issues a ticket', 'Accepted',
            CONCAT('Booking 11 is ', v_status, ' with ', v_count, ' ticket'),
            IF(v_status = 'Confirmed' AND v_count = 1, 'PASS', 'FAIL'));
    END;

    -- 16. sp_cancel_booking deletes the tickets and cancels the booking
    BEGIN
        DECLARE v_status VARCHAR(20);
        DECLARE v_count  INT;
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            INSERT INTO rule_test_results VALUES (16, 'sp_cancel_booking releases the seats', 'Accepted', v_msg, 'FAIL');
        END;
        CALL sp_cancel_booking(11);
        SELECT status INTO v_status FROM booking WHERE booking_id = 11;
        SELECT COUNT(*) INTO v_count FROM ticket WHERE booking_id = 11;
        INSERT INTO rule_test_results VALUES (16, 'sp_cancel_booking releases the seats', 'Accepted',
            CONCAT('Booking 11 is ', v_status, ' with ', v_count, ' tickets'),
            IF(v_status = 'Cancelled' AND v_count = 0, 'PASS', 'FAIL'));
    END;

    -- Restore the sample data. These deletes remove only rows the tests
    -- could have created, even if a rule failed to reject one of them.
    DELETE FROM crew_assignment
    WHERE (crew_id, flight_id) IN ((7, 3), (1, 2), (1, 3), (12, 7));
    DELETE FROM itinerary_flight WHERE (booking_id, flight_id) IN ((8, 4), (15, 5));
    DELETE FROM ticket WHERE booking_id IN (11, 13)
       OR (booking_id = 8 AND seat_id IN (SELECT seat_id FROM seat WHERE flight_id = 1));
    DELETE FROM flight WHERE flight_number LIKE 'TEST%';
    UPDATE booking SET status = 'Pending' WHERE booking_id = 11;
    SET @sp_quiet = NULL;

    SELECT test_no, rule_tested, expected, actual_message, result
    FROM rule_test_results
    ORDER BY test_no;

    SELECT SUM(result = 'PASS') AS passed,
           COUNT(*)             AS total_tests
    FROM rule_test_results;

    DROP TEMPORARY TABLE rule_test_results;
END$$

DELIMITER ;

-- uncomment below line to run tests
-- CALL sp_run_rule_tests();