"""The 12 project queries (same SQL as queries.sql), so the web app can run them.

Each entry: n, title, question, tags, sql, and optionally one parameter.
A parameter is filled in with %s placeholders (never pasted into the SQL text).
"""

QUERIES = [
    {
        "n": 1,
        "title": "Flight schedule",
        "question": "Full flight schedule with route, aircraft model, and aircraft status.",
        "tags": ["JOIN"],
        "sql": """SELECT f.flight_number,
       o.code AS origin,
       d.code AS destination,
       f.departure_time,
       f.arrival_time,
       m.model_name AS aircraft_model,
       a.status     AS aircraft_status
FROM flight f
JOIN airport o        ON o.airport_id  = f.origin_airport_id
JOIN airport d        ON d.airport_id  = f.destination_airport_id
JOIN aircraft a       ON a.aircraft_id = f.aircraft_id
JOIN aircraft_model m ON m.model_id    = a.model_id
ORDER BY f.departure_time;""",
    },
    {
        "n": 2,
        "title": "Revenue by route",
        "question": "Tickets sold, total revenue, and average fare for each origin-destination pair, best route first.",
        "tags": ["JOIN", "AGGREGATE"],
        "sql": """SELECT o.code AS origin,
       d.code AS destination,
       COUNT(t.ticket_id)        AS tickets_sold,
       SUM(t.fare_paid)          AS revenue,
       ROUND(AVG(t.fare_paid), 2) AS average_fare
FROM ticket t
JOIN seat s    ON s.seat_id    = t.seat_id
JOIN flight f  ON f.flight_id  = s.flight_id
JOIN airport o ON o.airport_id = f.origin_airport_id
JOIN airport d ON d.airport_id = f.destination_airport_id
GROUP BY o.code, d.code
ORDER BY revenue DESC;""",
    },
    {
        "n": 3,
        "title": "Load factor per flight",
        "question": "Load factor of every flight (% of seats sold), using the fn_load_factor function.",
        "tags": ["JOIN", "FUNCTION"],
        "sql": """SELECT f.flight_number,
       o.code AS origin,
       d.code AS destination,
       f.departure_time,
       fn_load_factor(f.flight_id) AS load_factor_pct
FROM flight f
JOIN airport o ON o.airport_id = f.origin_airport_id
JOIN airport d ON d.airport_id = f.destination_airport_id
ORDER BY load_factor_pct DESC, f.flight_number;""",
    },
    {
        "n": 4,
        "title": "Crew utilization",
        "question": "Flights worked and total flight hours for every crew member.",
        "tags": ["JOIN", "AGGREGATE"],
        "sql": """SELECT c.crew_id,
       CONCAT(c.first_name, ' ', c.last_name) AS crew_member,
       c.role,
       COUNT(ca.flight_id) AS flights_worked,
       ROUND(COALESCE(SUM(TIMESTAMPDIFF(MINUTE, f.departure_time, f.arrival_time)), 0) / 60, 2)
           AS flight_hours
FROM crew_member c
LEFT JOIN crew_assignment ca ON ca.crew_id   = c.crew_id
LEFT JOIN flight f           ON f.flight_id  = ca.flight_id
GROUP BY c.crew_id, c.first_name, c.last_name, c.role
ORDER BY flight_hours DESC, c.crew_id;""",
    },
    {
        "n": 5,
        "title": "Passenger spending",
        "question": "Bookings, tickets, and total fares for every passenger, including passengers who never booked.",
        "tags": ["JOIN", "AGGREGATE"],
        "sql": """SELECT p.passenger_id,
       CONCAT(p.first_name, ' ', p.last_name) AS passenger,
       COUNT(DISTINCT b.booking_id)            AS bookings,
       COUNT(t.ticket_id)                      AS tickets,
       COALESCE(SUM(t.fare_paid), 0)           AS total_spent
FROM passenger p
LEFT JOIN booking b ON b.passenger_id = p.passenger_id
LEFT JOIN ticket t  ON t.booking_id   = b.booking_id
GROUP BY p.passenger_id, p.first_name, p.last_name
ORDER BY total_spent DESC, p.passenger_id;""",
    },
    {
        "n": 6,
        "title": "Passengers who never booked",
        "question": "Passengers who have never made a booking.",
        "tags": ["SUBQUERY"],
        "sql": """SELECT p.passenger_id,
       CONCAT(p.first_name, ' ', p.last_name) AS passenger,
       p.email
FROM passenger p
WHERE NOT EXISTS (SELECT 1
                  FROM booking b
                  WHERE b.passenger_id = p.passenger_id);""",
    },
    {
        "n": 7,
        "title": "Above-average load factor",
        "question": "Flights with a load factor above the average of all flights.",
        "tags": ["VIEW", "SUBQUERY"],
        "sql": """SELECT flight_number, origin, destination, aircraft_model,
       seats, tickets_sold, load_factor_pct
FROM v_flight_load
WHERE load_factor_pct > (SELECT AVG(load_factor_pct) FROM v_flight_load)
ORDER BY load_factor_pct DESC;""",
    },
    {
        "n": 8,
        "title": "Available seats on a flight",
        "question": "Seats still available on a flight, by class.",
        "tags": ["VIEW", "AGGREGATE"],
        "param": {"name": "flight_number", "label": "Flight number", "default": "VA201", "type": "text"},
        "sql": """SELECT seat_class,
       COUNT(*) AS seats_available
FROM v_available_seats
WHERE flight_number = %s
GROUP BY seat_class
ORDER BY FIELD(seat_class, 'First', 'Business', 'Economy');""",
    },
    {
        "n": 9,
        "title": "Multi-leg itineraries",
        "question": "Bookings with more than one leg and the full route.",
        "tags": ["VIEW", "AGGREGATE"],
        "sql": """SELECT booking_id,
       passenger,
       COUNT(*) AS legs,
       GROUP_CONCAT(CONCAT(origin, '-', destination)
                    ORDER BY leg SEPARATOR ', ') AS route
FROM v_booking_itinerary
GROUP BY booking_id, passenger
HAVING COUNT(*) > 1
ORDER BY legs DESC, booking_id;""",
    },
    {
        "n": 10,
        "title": "Certifications expired or expiring",
        "question": "Crew certifications that are expired or expire within 180 days of the chosen date.",
        "tags": ["JOIN"],
        "param": {"name": "as_of", "label": "As-of date", "default": "2026-11-06", "type": "date", "repeat": 3},
        "sql": """SELECT CONCAT(c.first_name, ' ', c.last_name) AS crew_member,
       m.model_name,
       cc.expiration_date,
       DATEDIFF(cc.expiration_date, %s) AS days_left,
       CASE WHEN cc.expiration_date < %s
            THEN 'EXPIRED' ELSE 'Expiring soon' END AS status
FROM crew_certification cc
JOIN crew_member c    ON c.crew_id  = cc.crew_id
JOIN aircraft_model m ON m.model_id = cc.model_id
WHERE cc.expiration_date <= DATE_ADD(%s, INTERVAL 180 DAY)
ORDER BY cc.expiration_date;""",
    },
    {
        "n": 11,
        "title": "Never-scheduled aircraft",
        "question": "Aircraft that have never been scheduled on a flight.",
        "tags": ["JOIN", "SUBQUERY"],
        "sql": """SELECT a.aircraft_id,
       m.model_name,
       a.status
FROM aircraft a
JOIN aircraft_model m ON m.model_id = a.model_id
WHERE a.aircraft_id NOT IN (SELECT aircraft_id FROM flight)
ORDER BY a.aircraft_id;""",
    },
    {
        "n": 12,
        "title": "Airport traffic",
        "question": "Departures, arrivals, and total flights per airport (a subquery combines both directions).",
        "tags": ["JOIN", "AGGREGATE", "SUBQUERY"],
        "sql": """SELECT ap.code,
       ap.city,
       SUM(tr.departures)                 AS departures,
       SUM(tr.arrivals)                   AS arrivals,
       SUM(tr.departures + tr.arrivals)   AS total_flights
FROM airport ap
JOIN (SELECT origin_airport_id      AS airport_id, 1 AS departures, 0 AS arrivals FROM flight
      UNION ALL
      SELECT destination_airport_id AS airport_id, 0 AS departures, 1 AS arrivals FROM flight) tr
     ON tr.airport_id = ap.airport_id
GROUP BY ap.airport_id, ap.code, ap.city
ORDER BY total_flights DESC, ap.code;""",
    },
]
