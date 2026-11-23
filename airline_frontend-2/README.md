# Airline Reservation & Scheduling System: Web App

A Flask web app on top of the `airline_reservation` MySQL database. CSC 3300-002: Jerry Chandler, Teagan Tobias, Logan Wolford.

The app logs in as the restricted `agent_user` (not root). It cannot insert, update, or delete table rows directly: every change goes through a stored procedure, so the triggers and business rules always run.

## Pages

| Page | What it does |
|---|---|
| **Flights** | Schedule, aircraft, load factor; search by airport or date; click a flight for its passenger manifest (`sp_flight_manifest`) |
| **Book** | New booking (`sp_new_booking`), ticket an existing booking (`sp_book_ticket`), add a connecting flight (`sp_add_leg`) |
| **Bookings** | All bookings, itinerary with seats and fares, cancel a booking (`sp_cancel_booking`) |
| **Crew** | Assign or remove crew (`sp_assign_crew`, `sp_unassign_crew`); triggers enforce certification, overlap, and rest; certification list |
| **Queries** | Runs all 12 project queries (Q1 to Q12) and shows the SQL and results; Q8 and Q10 take an input |
| **Security** | Explains the three roles and lets you run allowed and denied statements live as `reader_user` and `agent_user` |

## Setup

1. **Run the SQL files in this order** (MySQL 8.0.16 or later, as an admin such as root):
   1. `airline_res_create_tables.sql`
   2. `airline_sample_data.sql`
   3. `views_procedures_triggers.sql`
   4. `security.sql` (the `06_security.sql` file)
   5. `sql/07_frontend_support.sql` (this folder: 4 extra procedures and grants for the app)

   `queries.sql` and `rule_tests.sql` are not needed by the app.
2. **Install Python 3.9 or later**, then in this folder:
   ```
   pip install -r requirements.txt
   ```
3. **Start the app:**
   ```
   python app.py
   ```
4. Open **http://127.0.0.1:5000** in a browser.

Bootstrap is included in `static/vendor`, so the app works without internet.

## Settings (optional)

The defaults match the placeholder passwords in `security.sql`, so nothing needs to be set. To change anything, set environment variables before `python app.py`:

| Variable | Default |
|---|---|
| `DB_HOST` | `localhost` (try `127.0.0.1` if you get a host error) |
| `DB_PORT` | `3306` |
| `DB_NAME` | `airline_reservation` |
| `DB_USER` / `DB_PASSWORD` | `agent_user` / `Agent#2026pw` |
| `READER_USER` / `READER_PASSWORD` | `reader_user` / `Reader#2026pw` (Security page only) |

Windows (Command Prompt): `set DB_PASSWORD=NewPassword` then `python app.py`.
Mac/Linux: `DB_PASSWORD=NewPassword python app.py`.

If you change a password in `security.sql`, change it here too. Never commit real passwords.

## Demo ideas (about 8 minutes)

1. **Flights**: search `BNA`, open a manifest.
2. **Book**: new booking for a passenger on VA301 (seat dropdown shows only open seats).
3. **Book, "Ticket an existing booking"**: booking #11 (Pending), flight VA301, seat `9C`. The database refuses it ("Seat is already sold"). Try seat `12A` to succeed.
4. **Book, "Add a connecting flight"**: booking #12 plus VA201 works; booking #12 plus VA301 is refused by the trigger.
5. **Bookings**: view an itinerary, cancel a booking.
6. **Crew**: assign crew member 1 to VA201 (refused: 10-hour rest). Remove someone, then assign them again to show a valid assignment.
7. **Queries**: run Q2, Q7, Q9; change the date on Q10.
8. **Security**: run the denied statements and show the MySQL error.

## Reset the demo data

Re-run files 1 to 5 above (file 1 drops and recreates the database).

## Files

```
app.py              routes and database calls
queries_data.py     the 12 queries (same SQL as queries.sql)
templates/          HTML pages
static/             CSS and bundled Bootstrap
sql/07_frontend_support.sql
requirements.txt
```
