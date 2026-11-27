DROP DATABASE IF EXISTS airline_reservation;

CREATE DATABASE airline_reservation CHARACTER SET utf8mb4;
USE airline_reservation;

-- 1. AIRCRAFT_MODEL: kind of aircraft and its seating capacity
CREATE TABLE aircraft_model(
    model_id INT NOT NULL AUTO_INCREMENT,
    model_name VARCHAR(50) NOT NULL,
    capacity INT NOT NULL,
    CONSTRAINT pk_aircraft_model PRIMARY KEY (model_id),
    CONSTRAINT uq_aircraft_model_name UNIQUE (model_name),
    CONSTRAINT chk_aircraft_model_capacity CHECK (capacity > 0)
);

-- 2. AIRCRAFT: one physical plane in the fleet
CREATE TABLE aircraft(
    aircraft_id INT NOT NULL AUTO_INCREMENT,
    model_id INT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'Active',
    CONSTRAINT pk_aircraft PRIMARY KEY (aircraft_id),
    CONSTRAINT fk_aircraft_model FOREIGN KEY (model_id)
        REFERENCES aircraft_model (model_id) ON DELETE RESTRICT,
    CONSTRAINT chk_aircraft_status
        CHECK(status IN('Active', 'Maintenance', 'Retired'))
);

-- 3. AIRPORT: departure and arrival points
CREATE TABLE airport(
    airport_id INT NOT NULL AUTO_INCREMENT,
    code CHAR(3) NOT NULL,
    city VARCHAR(60) NOT NULL,
    country VARCHAR(60) NOT NULL,
    CONSTRAINT pk_airport PRIMARY KEY (airport_id),
    CONSTRAINT uq_airport_code UNIQUE (code)
);

-- 4. FLIGHT: one scheduled deperture of a flight number (date-times in UTC)
CREATE TABLE flight(
    flight_id INT NOT NULL AUTO_INCREMENT,
    flight_number VARCHAR(10) NOT NULL,
    aircraft_id INT NOT NULL,
    origin_airport_id INT NOT NULL,
    destination_airport_id INT NOT NULL,
    departure_time DATETIME NOT NULL,
    arrival_time DATETIME NOT NULL,
    CONSTRAINT pk_flight PRIMARY KEY (flight_id),
    CONSTRAINT uq_flight_number_departure UNIQUE (flight_number, departure_time),
    CONSTRAINT fk_flight_aircraft FOREIGN KEY (aircraft_id)
        REFERENCES aircraft (aircraft_id) ON DELETE RESTRICT,
    CONSTRAINT fk_flight_origin FOREIGN KEY (origin_airport_id)
        REFERENCES airport (airport_id) ON DELETE RESTRICT,
    CONSTRAINT fk_flight_destination FOREIGN KEY (destination_airport_id)
        REFERENCES airport (airport_id) ON DELETE RESTRICT,
    CONSTRAINT chk_flight_times CHECK (arrival_time > departure_time),
    CONSTRAINT chk_flight_airports CHECK (origin_airport_id <> destination_airport_id)
);

-- 5. SEAT: one seat on one specific flight
CREATE TABLE seat(
    seat_id INT NOT NULL AUTO_INCREMENT,
    flight_id INT NOT NULL,
    seat_number VARCHAR(4) NOT NULL,
    seat_class VARCHAR(20) NOT NULL,
    CONSTRAINT pk_seat PRIMARY KEY (seat_id),
    CONSTRAINT uq_seat_flight_number UNIQUE (flight_id, seat_number),
    CONSTRAINT fk_seat_flight FOREIGN KEY (flight_id)
        REFERENCES flight (flight_id) ON DELETE RESTRICT,
    CONSTRAINT chk_seat_class
        CHECK (seat_class IN ('Economy', 'Business', 'First'))
);

-- 6. CREW_MEMBER: a pilot or flight attendant
CREATE TABLE crew_member(
    crew_id INT NOT NULL AUTO_INCREMENT,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    role VARCHAR(30) NOT NULL,
    CONSTRAINT pk_crew_member PRIMARY KEY (crew_id),
    CONSTRAINT chk_crew_member_role
        CHECK (role IN ('Pilot', 'Flight Attendant'))
);

-- 7. CREW_CERTIFICATION: one crew member certified on one aircraft model
CREATE TABLE crew_certification(
    crew_id INT NOT NULL,
    model_id INT NOT NULL,
    issue_date DATE NOT NULL,
    expiration_date DATE NOT NULL,
    CONSTRAINT pk_crew_certification PRIMARY KEY (crew_id, model_id),
    CONSTRAINT fk_crew_cert_crew FOREIGN KEY (crew_id)
        REFERENCES crew_member (crew_id) ON DELETE RESTRICT,
    CONSTRAINT fk_crew_cert_model FOREIGN KEY (model_id)
        REFERENCES aircraft_model (model_id) ON DELETE RESTRICT,
    CONSTRAINT chk_crew_cert_dates CHECK (expiration_date > issue_date)
);

-- 8. CREW_ASSIGNMENT: one crew member working one flight
CREATE TABLE crew_assignment(
    crew_id  INT NOT NULL,
    flight_id INT NOT NULL,
    role_on_flight VARCHAR(30) NOT NULL,
    CONSTRAINT pk_crew_assignment PRIMARY KEY (crew_id, flight_id),
    CONSTRAINT fk_crew_assign_crew FOREIGN KEY (crew_id)
        REFERENCES crew_member (crew_id) ON DELETE RESTRICT,
    CONSTRAINT fk_crew_assign_flight FOREIGN KEY (flight_id)
        REFERENCES flight (flight_id) ON DELETE RESTRICT,
    CONSTRAINT chk_crew_assign_role
        CHECK (role_on_flight IN ('Captain', 'First Officer',
                                  'Lead Attendant', 'Attendant'))
);

-- 9. PASSENGER: a traveler
CREATE TABLE passenger(
    passenger_id INT NOT NULL AUTO_INCREMENT,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL,
    phone VARCHAR(20) NULL,
    passport_number VARCHAR(20) NULL,
    CONSTRAINT pk_passenger PRIMARY KEY (passenger_id),
    CONSTRAINT uq_passenger_email UNIQUE (email),
    CONSTRAINT uq_passenger_passport UNIQUE (passport_number)
);

-- 10. BOOKING: one passenger's reservation (may cover multi-leg trip)
CREATE TABLE booking(
    booking_id INT NOT NULL AUTO_INCREMENT,
    passenger_id INT NOT NULL,
    booking_date DATE NOT NULL DEFAULT (CURRENT_DATE),
    status VARCHAR(20) NOT NULL DEFAULT 'Pending',
    CONSTRAINT pk_booking PRIMARY KEY (booking_id),
    CONSTRAINT fk_booking_passenger FOREIGN KEY (passenger_id)
        REFERENCES passenger (passenger_id) ON DELETE RESTRICT,
    CONSTRAINT chk_booking_status
        CHECK (status IN ('Pending', 'Confirmed', 'Cancelled'))
);

-- 11. ITINERARY_FLIGHT: one flight leg within one booking
CREATE TABLE itinerary_flight(
    booking_id INT NOT NULL,
    flight_id INT NOT NULL,
    sequence_number INT NOT NULL,
    CONSTRAINT pk_itinerary_flight PRIMARY KEY (booking_id, flight_id),
    CONSTRAINT uq_itinerary_sequence UNIQUE (booking_id, sequence_number),
    CONSTRAINT fk_itinerary_booking FOREIGN KEY (booking_id)
        REFERENCES booking (booking_id) ON DELETE RESTRICT,
    CONSTRAINT fk_itinerary_flight FOREIGN KEY (flight_id)
        REFERENCES flight (flight_id) ON DELETE RESTRICT,
    CONSTRAINT chk_itinerary_sequence CHECK (sequence_number >= 1)
);

-- 12. TICKET: the ticket for one seat, issued under one booking
CREATE TABLE ticket(
    ticket_id INT NOT NULL AUTO_INCREMENT,
    booking_id INT NOT NULL,
    seat_id INT NOT NULL,
    fare_paid DECIMAL(10,2) NOT NULL,
    CONSTRAINT pk_ticket PRIMARY KEY (ticket_id),
    CONSTRAINT uq_ticket_seat UNIQUE (seat_id),
    CONSTRAINT fk_ticket_booking FOREIGN KEY (booking_id)
        REFERENCES booking (booking_id) ON DELETE RESTRICT,
    CONSTRAINT fk_ticket_seat FOREIGN KEY (seat_id)
        REFERENCES seat (seat_id) ON DELETE RESTRICT,
    CONSTRAINT chk_ticket_fare CHECK (fare_paid >= 0)
);