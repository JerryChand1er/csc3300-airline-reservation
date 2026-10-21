# Airline Reservation & Flight Scheduling System

CSC 3300-002 database project: Jerry Chandler, Teagan Tobias, Logan Wolford

## About

A MySQL database for an airline. It stores the fleet, flight schedule, crew, seats, passengers, bookings, and tickets. Scheduling and booking rules are enforced inside the database, so errors such as a double-booked aircraft or a seat sold twice cannot be saved.

**Requires:** MySQL 8.0.16 or later.

## What's included

- **Database design:** 12 tables in 3NF covering aircraft, airports, flights, seats, crew, passengers, bookings, and tickets.
- **Sample data:** 12 flights over three days, with crew, passengers, bookings, and tickets.
- **Views, a function, procedures, and triggers** that enforce the business rules and support common tasks such as booking and cancelling.
- **12 example queries** for reports like flight schedules, revenue by route, load factor, and crew utilization.
- **Rule tests (optional):** a test report that tries to break each rule.

## How to run

Run the files in this order:

1. `airline_res_create_tables.sql` (creates the database and tables; resets everything)
2. `airline_sample_data.sql`
3. `views_procedures_triggers.sql`
4. `queries.sql` (run one query at a time)
5. `rule_tests.sql` (optional; all 16 tests should say PASS)

Run steps 1 to 3 first and in order, since the queries and tests depend on them.
