/*
WHAT THE DATA CONTAINS
4 aircraft models, 8 aircraft, 8 airports, 12 flights over three days (2026-11-06 to 2026-11-08, times in UTC), 
12 crew members, 35 crew assignments, 17 passengers, 16 bookings, 25 itinerary legs, 
23 tickets, and one seat map per flight (generated).

NOTE: 
seats are 4 across (A to D). Rows 1-2 are First, rows 3-5 are Business, and the rest are Economy. 
Each flight gets as many seats as its aircraft model's capacity.
*/

USE airline_reservation;

-- 1. Aircraft Model (4)
INSERT INTO aircraft_model (model_id, model_name, capacity) VALUES
(1, 'Embraer ERJ-145',     48),
(2, 'Bombardier CRJ-700',  72),
(3, 'Embraer E175',        76),
(4, 'Embraer E190',       100);

-- 2. Aircraft
-- 2 aircrafts of each model; one in Maintenance, one Retired
INSERT INTO aircraft (aircraft_id, model_id, status) VALUES
(1, 1, 'Active'),
(2, 1, 'Active'),
(3, 2, 'Active'),
(4, 2, 'Maintenance'),
(5, 3, 'Active'),
(6, 3, 'Active'),
(7, 4, 'Active'),
(8, 4, 'Retired');

-- 3. Airport (8)
INSERT INTO airport (airport_id, code, city, country) VALUES
(1, 'ATL', 'Atlanta',     'United States'),
(2, 'BNA', 'Nashville',   'United States'),
(3, 'CLT', 'Charlotte',   'United States'),
(4, 'ORD', 'Chicago',     'United States'),
(5, 'DFW', 'Dallas',      'United States'),
(6, 'JFK', 'New York',    'United States'),
(7, 'MIA', 'Miami',       'United States'),
(8, 'YYZ', 'Toronto',     'Canada');

-- 4. Flight
-- 4 flights per day; day 1 is 2026-11-06, day 2 is 2026-11-07, day 3 is 2026-11-08
INSERT INTO flight (flight_id, flight_number, aircraft_id, origin_airport_id,
                    destination_airport_id, departure_time, arrival_time) VALUES
( 1, 'VA101', 1, 2, 1, '2026-11-06 12:00:00', '2026-11-06 13:05:00'),  -- BNA to ATL
( 2, 'VA201', 5, 1, 6, '2026-11-06 14:00:00', '2026-11-06 16:15:00'),  -- ATL to JFK
( 3, 'VA301', 3, 2, 4, '2026-11-06 14:00:00', '2026-11-06 15:20:00'),  -- BNA to ORD
( 4, 'VA401', 7, 1, 7, '2026-11-06 14:15:00', '2026-11-06 16:10:00'),  -- ATL to MIA
( 5, 'VA102', 1, 1, 2, '2026-11-07 12:00:00', '2026-11-07 13:05:00'),  -- ATL to BNA
( 6, 'VA202', 5, 6, 1, '2026-11-07 13:00:00', '2026-11-07 15:15:00'),  -- JFK to ATL
( 7, 'VA302', 3, 4, 2, '2026-11-07 13:00:00', '2026-11-07 14:20:00'),  -- ORD to BNA
( 8, 'VA402', 7, 7, 1, '2026-11-07 14:00:00', '2026-11-07 15:55:00'),  -- MIA to ATL
( 9, 'VA103', 2, 2, 3, '2026-11-08 12:00:00', '2026-11-08 13:20:00'),  -- BNA to CLT
(10, 'VA501', 6, 4, 5, '2026-11-08 13:00:00', '2026-11-08 15:20:00'),  -- ORD to DFW
(11, 'VA601', 3, 2, 8, '2026-11-08 14:00:00', '2026-11-08 15:50:00'),  -- BNA to YYZ
(12, 'VA602', 3, 8, 2, '2026-11-08 18:00:00', '2026-11-08 19:50:00');  -- YYZ to BNA

-- 5. Seat 
INSERT INTO seat (flight_id, seat_number, seat_class)
WITH RECURSIVE seat_n (n) AS (
    SELECT 0
    UNION ALL
    SELECT n + 1 FROM seat_n WHERE n < 99
)
SELECT f.flight_id,
       CONCAT(sn.n DIV 4 + 1, CHAR(65 + MOD(sn.n, 4) USING utf8mb4)),
       CASE WHEN sn.n DIV 4 + 1 <= 2 THEN 'First'
            WHEN sn.n DIV 4 + 1 <= 5 THEN 'Business'
            ELSE 'Economy' END
FROM flight f
JOIN aircraft a       ON a.aircraft_id = f.aircraft_id
JOIN aircraft_model m ON m.model_id    = a.model_id
JOIN seat_n sn        ON sn.n < m.capacity
ORDER BY f.flight_id, sn.n;

-- 6. Crew Member
-- 8 pilots, 4 flight attendants
INSERT INTO crew_member (crew_id, first_name, last_name, role) VALUES
( 1, 'Marcus',  'Reed',      'Pilot'),
( 2, 'Elena',   'Vasquez',   'Pilot'),
( 3, 'Daniel',  'Okafor',    'Pilot'),
( 4, 'Priya',   'Nair',      'Pilot'),
( 5, 'Thomas',  'Whitfield', 'Pilot'),
( 6, 'Sofia',   'Marino',    'Pilot'),
( 7, 'Kevin',   'Brandt',    'Pilot'),
( 8, 'Aisha',   'Rahman',    'Pilot'),
( 9, 'Laura',   'Chen',      'Flight Attendant'),
(10, 'James',   'Whitaker',  'Flight Attendant'),
(11, 'Maria',   'Santos',    'Flight Attendant'),
(12, 'Derek',   'Holloway',  'Flight Attendant');

-- 7. Crew Certification
-- model 1 = ERJ-145, 2 = CRJ-700, 3 = E175, 4 = E190
INSERT INTO crew_certification (crew_id, model_id, issue_date, expiration_date) VALUES
( 1, 1, '2023-04-10', '2027-04-10'),
( 1, 3, '2025-01-15', '2028-01-15'),
( 2, 1, '2024-02-20', '2027-02-20'),
( 3, 3, '2023-09-05', '2027-09-05'),
( 4, 3, '2024-05-12', '2027-05-12'),
( 5, 2, '2024-03-18', '2027-03-18'),
( 6, 2, '2023-11-30', '2027-11-30'),
( 7, 4, '2024-08-01', '2027-08-01'),
( 7, 2, '2025-02-10', '2028-02-10'),
( 8, 4, '2023-10-22', '2027-10-22'),
( 8, 2, '2025-03-05', '2028-03-05'),
( 9, 2, '2024-01-09', '2027-01-09'),
( 9, 3, '2024-01-09', '2027-01-09'),
( 9, 4, '2024-01-09', '2027-01-09'),
(10, 2, '2024-06-14', '2027-06-14'),
(10, 3, '2024-06-14', '2027-06-14'),
(10, 4, '2024-06-14', '2027-06-14'),
(11, 3, '2025-04-02', '2028-04-02'),
(11, 4, '2025-04-02', '2028-04-02'),
(12, 4, '2025-07-21', '2028-07-21'),
(12, 2, '2021-07-01', '2026-06-30');   -- expired

-- 8. Crew Assignment
-- Pilots always fly in pairs, attendants on large aircrafts, person work at most one flight per day
INSERT INTO crew_assignment (crew_id, flight_id, role_on_flight) VALUES
-- Day 1
(1,  1, 'Captain'),  (2,  1, 'First Officer'),
(3,  2, 'Captain'),  (4,  2, 'First Officer'),  (9,  2, 'Lead Attendant'),
(5,  3, 'Captain'),  (6,  3, 'First Officer'),  (10, 3, 'Lead Attendant'),
(7,  4, 'Captain'),  (8,  4, 'First Officer'),  (11, 4, 'Lead Attendant'), (12, 4, 'Attendant'),

-- Day 2
(2,  5, 'Captain'),  (1,  5, 'First Officer'),
(4,  6, 'Captain'),  (3,  6, 'First Officer'),  (10, 6, 'Lead Attendant'),
(6,  7, 'Captain'),  (5,  7, 'First Officer'),  (9,  7, 'Lead Attendant'),
(8,  8, 'Captain'),  (7,  8, 'First Officer'),  (12, 8, 'Lead Attendant'), (11, 8, 'Attendant'),

-- Day 3
(1,  9, 'Captain'),  (2,  9, 'First Officer'),
(3, 10, 'Captain'),  (4, 10, 'First Officer'),  (11, 10, 'Lead Attendant'),
(5, 11, 'Captain'),  (6, 11, 'First Officer'),  (9,  11, 'Lead Attendant'),
(7, 12, 'Captain'),  (8, 12, 'First Officer'),  (10, 12, 'Lead Attendant');

-- 9. Passenger
-- passport numbers only where travel is international; phone may be null
INSERT INTO passenger (passenger_id, first_name, last_name, email, phone, passport_number) VALUES
( 1, 'Emily',     'Carter',   'emily.carter@example.com',     '615-555-0101', NULL),
( 2, 'Jonathan',  'Brooks',   'j.brooks@example.com',         '615-555-0102', NULL),
( 3, 'Sophia',    'Nguyen',   'sophia.nguyen@example.com',    '931-555-0103', 'P12345678'),
( 4, 'Michael',   'Thompson', 'm.thompson@example.com',       '615-555-0104', NULL),
( 5, 'Ava',       'Patel',    'ava.patel@example.com',        '423-555-0105', 'P23456789'),
( 6, 'Ethan',     'Walker',   'ethan.walker@example.com',     NULL,           NULL),
( 7, 'Isabella',  'Garcia',   'isabella.garcia@example.com',  '404-555-0107', 'P34567890'),
( 8, 'Noah',      'Johnson',  'noah.johnson@example.com',     '931-555-0108', NULL),
( 9, 'Mia',       'Robinson', 'mia.robinson@example.com',     '615-555-0109', NULL),
(10, 'Lucas',     'Martin',   'lucas.martin@example.com',     '865-555-0110', NULL),
(11, 'Charlotte', 'Davis',    'charlotte.davis@example.com',  NULL,           NULL),
(12, 'Benjamin',  'Lee',      'ben.lee@example.com',          '931-555-0112', 'P45678901'),
(13, 'Amelia',    'Scott',    'amelia.scott@example.com',     '615-555-0113', NULL),
(14, 'Henry',     'Turner',   'henry.turner@example.com',     '931-555-0114', NULL),
(15, 'Harper',    'Wilson',   'harper.wilson@example.com',    '423-555-0115', NULL),
(16, 'Daniel',    'Kim',      'daniel.kim@example.com',       '615-555-0116', 'P56789012'),
(17, 'Grace',     'Hall',     'grace.hall@example.com',       NULL,           NULL);

-- 10. Booking
-- booking 11 and 13 are pending/cancelled, neither have tickets
INSERT INTO booking (booking_id, passenger_id, booking_date, status) VALUES
( 1,  1, '2026-10-02', 'Confirmed'),   -- 3 legs: BNA-ATL-JFK-ATL
( 2,  2, '2026-10-05', 'Confirmed'),   -- BNA-ATL-MIA
( 3,  3, '2026-09-28', 'Confirmed'),   -- BNA-YYZ-BNA (international)
( 4,  4, '2026-10-08', 'Confirmed'),   -- BNA-ORD-BNA
( 5,  5, '2026-10-10', 'Confirmed'),   -- BNA-YYZ-BNA (international)
( 6,  6, '2026-10-11', 'Confirmed'),   -- ATL-JFK-ATL
( 7,  7, '2026-10-12', 'Confirmed'),   -- ATL-MIA-ATL
( 8,  8, '2026-10-12', 'Confirmed'),   -- BNA-CLT
( 9,  9, '2026-10-13', 'Confirmed'),   -- ORD-DFW
(10, 10, '2026-10-13', 'Confirmed'),   -- ATL-BNA
(11, 11, '2026-10-14', 'Pending'),     -- BNA-ORD, not yet ticketed
(12, 12, '2026-10-14', 'Confirmed'),   -- BNA-ATL
(13, 13, '2026-10-15', 'Cancelled'),   -- ATL-JFK, cancelled
(14, 14, '2026-10-15', 'Confirmed'),   -- ORD-BNA
(15, 15, '2026-10-16', 'Confirmed'),   -- MIA-ATL
(16, 16, '2026-10-16', 'Confirmed');   -- BNA-YYZ-BNA (international)

-- 11. Itinerary Flight
-- legs in travel order, each leg is connecting to next (arrival = next departure)
INSERT INTO itinerary_flight (booking_id, flight_id, sequence_number) VALUES
( 1,  1, 1), ( 1,  2, 2), ( 1,  6, 3),
( 2,  1, 1), ( 2,  4, 2),
( 3, 11, 1), ( 3, 12, 2),
( 4,  3, 1), ( 4,  7, 2),
( 5, 11, 1), ( 5, 12, 2),
( 6,  2, 1), ( 6,  6, 2),
( 7,  4, 1), ( 7,  8, 2),
( 8,  9, 1),
( 9, 10, 1),
(10,  5, 1),
(11,  3, 1),
(12,  1, 1),
(13,  2, 1),
(14,  7, 1),
(15,  8, 1),
(16, 11, 1), (16, 12, 2);

-- 12. Ticket
-- 1 ticket per leg, except pending and cancelled bookings stated above. seat is looked up by flight and seat number
INSERT INTO ticket (booking_id, seat_id, fare_paid)
SELECT t.booking_id, s.seat_id, t.fare_paid
FROM (
    SELECT  1 AS booking_id,  1 AS flight_id, '1A'  AS seat_number, 329.00 AS fare_paid UNION ALL
    SELECT  1,  2, '1B',  489.00 UNION ALL
    SELECT  1,  6, '3A',  389.00 UNION ALL
    SELECT  2,  1, '8C',  129.00 UNION ALL
    SELECT  2,  4, '14D', 169.00 UNION ALL
    SELECT  3, 11, '6A',  219.00 UNION ALL
    SELECT  3, 12, '6B',  219.00 UNION ALL
    SELECT  4,  3, '9C',  149.00 UNION ALL
    SELECT  4,  7, '9D',  149.00 UNION ALL
    SELECT  5, 11, '4A',  329.00 UNION ALL
    SELECT  5, 12, '4B',  329.00 UNION ALL
    SELECT  6,  2, '12C', 189.00 UNION ALL
    SELECT  6,  6, '12D', 189.00 UNION ALL
    SELECT  7,  4, '3C',  299.00 UNION ALL
    SELECT  7,  8, '3D',  299.00 UNION ALL
    SELECT  8,  9, '7A',   99.00 UNION ALL
    SELECT  9, 10, '10A', 179.00 UNION ALL
    SELECT 10,  5, '6C',  129.00 UNION ALL
    SELECT 12,  1, '10B', 129.00 UNION ALL
    SELECT 14,  7, '11A', 119.00 UNION ALL
    SELECT 15,  8, '15B', 149.00 UNION ALL
    SELECT 16, 11, '7C',  219.00 UNION ALL
    SELECT 16, 12, '7D',  219.00
) AS t
JOIN seat s ON s.flight_id = t.flight_id AND s.seat_number = t.seat_number
ORDER BY t.booking_id, t.flight_id;