"""Airline Reservation & Scheduling System: web front end (Flask).

The app talks to the MySQL database only through the least-privilege login
'agent_user' (see sql/06_security.sql). It cannot insert, update, or delete
table rows directly: every change goes through a stored procedure, so the
triggers and business rules always run.
"""
import os

import mysql.connector
from mysql.connector import Error
from flask import Flask, render_template, request, redirect, url_for, flash, abort

from queries_data import QUERIES

app = Flask(__name__)
app.secret_key = os.environ.get("FLASK_SECRET_KEY", "dev-secret-key-for-flash-messages")

# ---------------------------------------------------------------------------
# Database settings (override with environment variables; see README)
# The default passwords are the placeholders in sql/06_security.sql.
# ---------------------------------------------------------------------------
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = int(os.environ.get("DB_PORT", "3306"))
DB_NAME = os.environ.get("DB_NAME", "airline_reservation")
APP_USER = os.environ.get("DB_USER", "agent_user")
APP_PASSWORD = os.environ.get("DB_PASSWORD", "Agent#2026pw")
READER_USER = os.environ.get("READER_USER", "reader_user")
READER_PASSWORD = os.environ.get("READER_PASSWORD", "Reader#2026pw")


def get_db_connection(user=None, password=None):
    return mysql.connector.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=user or APP_USER,
        password=APP_PASSWORD if password is None else password,
        database=DB_NAME,
    )


def fetch(cursor, sql, params=None):
    cursor.execute(sql, params or ())
    return cursor.fetchall()


def call_proc(cursor, name, args):
    """Call a stored procedure and return the rows of its result set (if any)."""
    cursor.callproc(name, args)
    rows = []
    for result in cursor.stored_results():
        cols = result.column_names
        for row in result.fetchall():
            # the connector returns dicts when the cursor is a dictionary cursor
            rows.append(row if isinstance(row, dict) else dict(zip(cols, row)))
    return rows


def current_login():
    """Who is the app logged in to MySQL as? (shown in the navigation bar)"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT CURRENT_USER()")
        who = cur.fetchone()[0]
        cur.close()
        conn.close()
        return who
    except Error:
        return None


@app.context_processor
def inject_globals():
    return {"login_name": current_login(), "nav_queries": QUERIES}


@app.errorhandler(Error)
def database_error(e):
    """Connection problems (wrong password, server off, database missing)."""
    return render_template("error.html", message=getattr(e, "msg", str(e)),
                           host=DB_HOST, port=DB_PORT, user=APP_USER, db=DB_NAME), 500


@app.route("/")
def index():
    return redirect(url_for("flights"))


# ---------------------------------------------------------------------------
# 1. FLIGHTS: schedule, aircraft, load factor (+ link to each flight's manifest)
# ---------------------------------------------------------------------------
@app.route("/flights")
def flights():
    airport_filter = request.args.get("airport", "").strip()
    date_filter = request.args.get("date", "").strip()

    sql = """
        SELECT f.flight_id, f.flight_number,
               o.code AS origin, d.code AS destination,
               f.departure_time, f.arrival_time,
               m.model_name AS aircraft_model,
               a.status AS aircraft_status,
               vl.seats, vl.tickets_sold,
               fn_load_factor(f.flight_id) AS load_factor_pct
        FROM flight f
        JOIN airport o ON o.airport_id = f.origin_airport_id
        JOIN airport d ON d.airport_id = f.destination_airport_id
        JOIN aircraft a ON a.aircraft_id = f.aircraft_id
        JOIN aircraft_model m ON m.model_id = a.model_id
        JOIN v_flight_load vl ON vl.flight_id = f.flight_id
        WHERE 1=1
    """
    params = []
    if airport_filter:
        sql += " AND (o.code LIKE %s OR d.code LIKE %s)"
        like_val = f"%{airport_filter}%"
        params.extend([like_val, like_val])
    if date_filter:
        sql += " AND DATE(f.departure_time) = %s"
        params.append(date_filter)
    sql += " ORDER BY f.departure_time ASC"

    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    flight_list = fetch(cursor, sql, params)
    cursor.close()
    conn.close()
    return render_template("flights.html", flights=flight_list,
                           airport=airport_filter, date=date_filter)


@app.route("/flights/<int:flight_id>/manifest")
def manifest(flight_id):
    """Passenger list for one flight (calls sp_flight_manifest)."""
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    info = fetch(cursor, """
        SELECT f.flight_id, f.flight_number, o.code AS origin, d.code AS destination,
               f.departure_time, f.arrival_time
        FROM flight f
        JOIN airport o ON o.airport_id = f.origin_airport_id
        JOIN airport d ON d.airport_id = f.destination_airport_id
        WHERE f.flight_id = %s""", (flight_id,))
    if not info:
        cursor.close()
        conn.close()
        abort(404)
    rows = call_proc(cursor, "sp_flight_manifest", [flight_id])
    cursor.close()
    conn.close()
    return render_template("manifest.html", flight=info[0], rows=rows)


# ---------------------------------------------------------------------------
# 2. BOOK: new booking, ticket an existing booking, add a connecting leg
# ---------------------------------------------------------------------------
def book_form_data(cursor):
    data = {}
    data["passengers"] = fetch(cursor, """
        SELECT passenger_id, CONCAT(first_name, ' ', last_name) AS passenger_name
        FROM passenger ORDER BY last_name, first_name""")
    data["flights"] = fetch(cursor, """
        SELECT f.flight_id, f.flight_number, o.code AS origin, d.code AS destination,
               f.departure_time
        FROM flight f
        JOIN airport o ON o.airport_id = f.origin_airport_id
        JOIN airport d ON d.airport_id = f.destination_airport_id
        ORDER BY f.departure_time""")
    data["seats"] = fetch(cursor, """
        SELECT flight_id, seat_number, seat_class
        FROM v_available_seats
        ORDER BY flight_id, CAST(seat_number AS UNSIGNED), seat_number""")
    data["bookings"] = fetch(cursor, """
        SELECT b.booking_id, CONCAT(p.first_name, ' ', p.last_name) AS passenger_name, b.status
        FROM booking b
        JOIN passenger p ON p.passenger_id = b.passenger_id
        WHERE b.status <> 'Cancelled'
        ORDER BY b.booking_id DESC""")
    # which flights each booking already contains (so the ticket form can offer only those)
    legs = fetch(cursor, """
        SELECT v.booking_id, f.flight_id
        FROM v_booking_itinerary v
        JOIN flight f ON f.flight_number = v.flight_number
                     AND f.departure_time = v.departure_time""")
    booking_flights = {}
    for row in legs:
        booking_flights.setdefault(row["booking_id"], []).append(row["flight_id"])
    data["booking_flights"] = booking_flights
    seat_map = {}
    for s in data["seats"]:
        seat_map.setdefault(s["flight_id"], []).append(
            {"seat": s["seat_number"], "cls": s["seat_class"]})
    data["seat_map"] = seat_map
    return data


@app.route("/book", methods=["GET", "POST"])
def book():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    if request.method == "POST":
        action = request.form.get("action")
        try:
            if action == "new":
                rows = call_proc(cursor, "sp_new_booking", [
                    int(request.form["passenger_id"]),
                    int(request.form["flight_id"]),
                    request.form["seat_number"],
                    float(request.form["fare_paid"]),
                ])
                conn.commit()
                booking_id = rows[0]["booking_id"]
                flash(f"Booking #{booking_id} created and confirmed.", "success")
                cursor.close()
                conn.close()
                return redirect(url_for("bookings", booking_id=booking_id))

            elif action == "ticket":
                booking_id = int(request.form["booking_id"])
                call_proc(cursor, "sp_book_ticket", [
                    booking_id,
                    int(request.form["flight_id"]),
                    request.form["seat_number"],
                    float(request.form["fare_paid"]),
                ])
                conn.commit()
                flash(f"Ticket issued on booking #{booking_id}.", "success")
                cursor.close()
                conn.close()
                return redirect(url_for("bookings", booking_id=booking_id))

            elif action == "leg":
                booking_id = int(request.form["booking_id"])
                rows = call_proc(cursor, "sp_add_leg", [
                    booking_id, int(request.form["flight_id"])])
                conn.commit()
                flash(f"Flight added to booking #{booking_id} as leg {rows[0]['leg']}. "
                      f"Now issue a ticket for it.", "success")
                cursor.close()
                conn.close()
                return redirect(url_for("book", tab="ticket"))
            else:
                flash("Unknown action.", "error")
        except (Error, KeyError, ValueError) as e:
            try:
                conn.rollback()
            except Error:
                pass
            msg = e.msg if isinstance(e, Error) else "Please fill in every field with valid values."
            flash(f"Database rejected the request: {msg}", "error")

    data = book_form_data(cursor)
    cursor.close()
    conn.close()
    return render_template("book.html", tab=request.args.get("tab") or request.form.get("action") or "new",
                           **data)


# ---------------------------------------------------------------------------
# 3. BOOKINGS: list, itinerary with tickets, cancel
# ---------------------------------------------------------------------------
@app.route("/bookings", methods=["GET", "POST"])
def bookings():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    if request.method == "POST":
        cancel_id = request.form.get("cancel_booking_id", "")
        try:
            call_proc(cursor, "sp_cancel_booking", [int(cancel_id)])
            conn.commit()
            flash(f"Booking #{cancel_id} cancelled and its seats released.", "success")
        except (Error, ValueError) as e:
            try:
                conn.rollback()
            except Error:
                pass
            msg = e.msg if isinstance(e, Error) else "Invalid booking number."
            flash(f"Cancellation rejected: {msg}", "error")

    selected = request.args.get("booking_id") or request.form.get("cancel_booking_id") or ""

    all_bookings = fetch(cursor, """
        SELECT b.booking_id,
               CONCAT(p.first_name, ' ', p.last_name) AS passenger_name,
               b.booking_date, b.status,
               (SELECT COUNT(*) FROM v_booking_itinerary v
                 WHERE v.booking_id = b.booking_id)                AS legs,
               (SELECT COUNT(*) FROM ticket t
                 WHERE t.booking_id = b.booking_id)                AS tickets,
               (SELECT COALESCE(SUM(t.fare_paid), 0) FROM ticket t
                 WHERE t.booking_id = b.booking_id)                AS total_fare
        FROM booking b
        JOIN passenger p ON p.passenger_id = b.passenger_id
        ORDER BY b.booking_id DESC""")

    itinerary = []
    if selected.isdigit():
        itinerary = fetch(cursor, """
            SELECT v.leg, v.flight_number, v.origin, v.destination,
                   v.departure_time, v.arrival_time, v.passenger, v.booking_status,
                   (SELECT s.seat_number FROM ticket t
                      JOIN seat s ON s.seat_id = t.seat_id
                     WHERE t.booking_id = v.booking_id AND s.flight_id = f.flight_id) AS seat_number,
                   (SELECT t.fare_paid FROM ticket t
                      JOIN seat s ON s.seat_id = t.seat_id
                     WHERE t.booking_id = v.booking_id AND s.flight_id = f.flight_id) AS fare_paid
            FROM v_booking_itinerary v
            JOIN flight f ON f.flight_number = v.flight_number
                         AND f.departure_time = v.departure_time
            WHERE v.booking_id = %s
            ORDER BY v.leg""", (int(selected),))

    cursor.close()
    conn.close()
    return render_template("bookings.html", all_bookings=all_bookings,
                           selected_booking_id=selected, itinerary=itinerary)


# ---------------------------------------------------------------------------
# 4. CREW: assign crew to flights (triggers enforce the rules) + certifications
# ---------------------------------------------------------------------------
@app.route("/crew", methods=["GET", "POST"])
def crew():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    if request.method == "POST":
        try:
            if request.form.get("action") == "unassign":
                call_proc(cursor, "sp_unassign_crew", [
                    int(request.form["crew_id"]), int(request.form["flight_id"])])
                conn.commit()
                flash("Crew member removed from the flight.", "success")
            else:
                call_proc(cursor, "sp_assign_crew", [
                    int(request.form["crew_id"]),
                    int(request.form["flight_id"]),
                    request.form["role_on_flight"],
                ])
                conn.commit()
                flash("Crew member assigned to the flight.", "success")
        except (Error, KeyError, ValueError) as e:
            try:
                conn.rollback()
            except Error:
                pass
            msg = e.msg if isinstance(e, Error) else "Please fill in every field."
            flash(f"Rule violation: {msg}", "error")

    crew_members = fetch(cursor, """
        SELECT crew_id, CONCAT(first_name, ' ', last_name) AS name, role
        FROM crew_member ORDER BY last_name, first_name""")
    all_flights = fetch(cursor, """
        SELECT f.flight_id, f.flight_number, m.model_name AS aircraft_model,
               o.code AS origin, d.code AS destination, f.departure_time
        FROM flight f
        JOIN aircraft a ON a.aircraft_id = f.aircraft_id
        JOIN aircraft_model m ON m.model_id = a.model_id
        JOIN airport o ON o.airport_id = f.origin_airport_id
        JOIN airport d ON d.airport_id = f.destination_airport_id
        ORDER BY f.departure_time""")
    assignments = fetch(cursor, """
        SELECT ca.crew_id, ca.flight_id, f.flight_number, f.departure_time, f.arrival_time,
               CONCAT(cm.first_name, ' ', cm.last_name) AS crew_name,
               cm.role, ca.role_on_flight
        FROM crew_assignment ca
        JOIN flight f ON f.flight_id = ca.flight_id
        JOIN crew_member cm ON cm.crew_id = ca.crew_id
        ORDER BY f.departure_time DESC, f.flight_number, ca.role_on_flight""")
    certs = fetch(cursor, """
        SELECT CONCAT(c.first_name, ' ', c.last_name) AS crew_name, m.model_name,
               cc.issue_date, cc.expiration_date,
               CASE WHEN cc.expiration_date < CURDATE() THEN 'Expired' ELSE 'Valid' END AS cert_status
        FROM crew_certification cc
        JOIN crew_member c ON c.crew_id = cc.crew_id
        JOIN aircraft_model m ON m.model_id = cc.model_id
        ORDER BY c.last_name, m.model_name""")

    cursor.close()
    conn.close()
    return render_template("crew.html", crew_members=crew_members, flights=all_flights,
                           assignments=assignments, certs=certs)


# ---------------------------------------------------------------------------
# 5. QUERIES: run any of the 12 project queries
# ---------------------------------------------------------------------------
@app.route("/queries")
def queries_index():
    return redirect(url_for("run_query", n=1))


@app.route("/queries/<int:n>")
def run_query(n):
    q = next((x for x in QUERIES if x["n"] == n), None)
    if q is None:
        abort(404)

    param = q.get("param")
    value = None
    params = ()
    shown_sql = q["sql"]
    if param:
        value = request.args.get(param["name"], "").strip() or param["default"]
        params = (value,) * param.get("repeat", 1)
        shown_sql = q["sql"].replace("%s", f"'{value}'")

    conn = get_db_connection()
    cursor = conn.cursor()
    error = None
    columns, rows = [], []
    try:
        cursor.execute(q["sql"], params)
        columns = list(cursor.column_names)
        rows = cursor.fetchall()
    except Error as e:
        error = e.msg
    cursor.close()
    conn.close()
    return render_template("queries.html", q=q, value=value, shown_sql=shown_sql,
                           columns=columns, rows=rows, error=error)


# ---------------------------------------------------------------------------
# 6. SECURITY: show the access rules, and prove them with live attempts
# ---------------------------------------------------------------------------
# A fixed list (nothing typed by the user is ever run). Every statement is harmless:
# the writes target a row that does not exist and are rolled back either way.
SECURITY_TESTS = [
    {"id": 1, "who": "reader", "sql": "SELECT flight_number, load_factor_pct FROM v_flight_load LIMIT 3",
     "why": "The reader may read the reporting views."},
    {"id": 2, "who": "reader", "sql": "SELECT * FROM passenger LIMIT 1",
     "why": "The reader may not see passenger personal data."},
    {"id": 3, "who": "reader", "sql": "DELETE FROM flight WHERE flight_id = -1",
     "why": "The reader may not change any data."},
    {"id": 4, "who": "agent", "sql": "SELECT COUNT(*) AS bookings FROM booking",
     "why": "The agent (this app's login) may read bookings."},
    {"id": 5, "who": "agent",
     "sql": "INSERT INTO passenger (first_name, last_name, email) VALUES ('Test', 'User', 'test@example.com')",
     "why": "The agent may not write to tables directly."},
    {"id": 6, "who": "agent", "sql": "DELETE FROM ticket WHERE ticket_id = -1",
     "why": "The agent may not delete tickets directly."},
    {"id": 7, "who": "agent", "sql": "CALL sp_flight_manifest(1)", "proc": ("sp_flight_manifest", [1]),
     "why": "The agent may use the stored procedures (all changes go through them)."},
]


@app.route("/security", methods=["GET", "POST"])
def security():
    result = None
    if request.method == "POST":
        test = next((t for t in SECURITY_TESTS
                     if str(t["id"]) == request.form.get("test_id")), None)
        if test is None:
            abort(400)
        if test["who"] == "reader":
            user, password = READER_USER, READER_PASSWORD
        else:
            user, password = APP_USER, APP_PASSWORD
        result = {"test": test, "user": user}
        try:
            conn = get_db_connection(user, password)
            cursor = conn.cursor()
            if "proc" in test:
                name, args = test["proc"]
                cursor.callproc(name, args)
                for res in cursor.stored_results():
                    result["columns"] = list(res.column_names)
                    result["rows"] = res.fetchall()
            else:
                cursor.execute(test["sql"])
                if cursor.with_rows:
                    result["rows"] = cursor.fetchall()
                    result["columns"] = list(cursor.column_names)
            conn.rollback()
            cursor.close()
            conn.close()
            result["allowed"] = True
        except Error as e:
            result["allowed"] = False
            result["error"] = f"ERROR {e.errno}: {e.msg}"
    return render_template("security.html", tests=SECURITY_TESTS, result=result,
                           reader_user=READER_USER, agent_user=APP_USER)


if __name__ == "__main__":
    app.run(debug=True)
