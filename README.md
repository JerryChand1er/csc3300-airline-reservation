# Airline Reservation & Flight Scheduling System

CSC 3300-002, Database Management Systems

**Team:** Jerry Chandler, Teagan Tobias, Logan Wolford

A MySQL database for an airline with a Flask web app on top. Triggers and stored procedures inside the database stop double-booked seats, invalid connecting flights and crew rest violations.

## What's included

- **12 tables in 3NF:** aircraft, airports, flights, seats, crew, passengers, bookings, tickets and more.
- **Views, a function, stored procedures and 7 triggers** that enforce the business rules.
- **12 queries:** joins, aggregates, subqueries and a recursive CTE.
- **Role-based security:** reader, agent and admin roles with least-privilege logins.
- **16 rule tests** (`sp_run_rule_tests`) that prove the rules work.
- **Flask web app:** search flights, book passengers, manage crew, run the 12 queries and demo security.

**Requires:** MySQL 8.0.16+ and Python 3.9+

## Repository layout

```
sql/                  database scripts and queries
airline_frontend-2/   Flask web app (see its README for details)
docs/                 final report, appendix and presentation
```

## Setup

**1. Build the database.** Run these files in order as `root` (or another admin account), in MySQL Workbench or with `mysql -u root -p < file.sql`:

```
sql/airline_res_create_tables.sql
sql/airline_sample_data.sql
sql/views_procedures_triggers.sql
sql/security.sql
airline_frontend-2/sql/07_frontend_support.sql
```

**2. Start the web app.**

```
cd airline_frontend-2
pip install -r requirements.txt
python app.py
```

**3. Open** http://127.0.0.1:5000 in your browser.

The app connects as `agent_user` (password `Agent#2026pw`, created by `security.sql`). To use a different login, set the `DB_USER` and `DB_PASSWORD` environment variables before running `python app.py`. Other settings: `DB_HOST`, `DB_PORT`, `DB_NAME`. See `airline_frontend-2/README.md` for more.

## Using the app

- **Flights:** search by airport and open a flight's passenger manifest.
- **Book / Bookings:** create bookings, ticket seats, add connecting flights, cancel.
- **Crew:** assign or remove crew on a flight.
- **Queries:** run each of the 12 queries.
- **Security:** run fixed tests as the reader and agent logins and see what MySQL allows or denies.

## Other notes

- `sql/queries.sql` and `sql/rule_tests.sql` can also be run on their own in Workbench.
- The app changes the real database. To reset the data, re-run the five SQL files above.
- Demo logins (`reader_user`, `agent_user`, `admin_user`) are for class use only. Security is at the database level; the website has no end-user login.
