import psycopg2
import pandas as pd
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr
import bcrypt
import os
from datetime import datetime, timedelta, timezone
from typing import Optional
from jose import jwt
import traceback

load_dotenv()

app = FastAPI(
    title="SafeRoute Intelligence API",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],       
    allow_credentials=False,
    allow_methods=["*"],       
    allow_headers=["*"],       
)

SECRET_KEY = "super_secret_university_project_key"
ALGORITHM = "HS256"

def hash_password(password: str) -> str:
    pwd_bytes = password.encode('utf-8')[:72]
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(pwd_bytes, salt)
    return hashed.decode('utf-8')

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))

class UserRegister(BaseModel):
    username: str
    email: EmailStr
    password: str

class UserLogin(BaseModel):
    username: str
    password: str

class MapFilterRequest(BaseModel):
    year: Optional[int] = None
    month: Optional[int] = None
    hour: Optional[int] = None
    day_of_week: Optional[int] = None
    city: Optional[str] = None
    state: Optional[str] = None
    car_involved: bool = False
    truck_involved: bool = False
    bike_involved: bool = False
    motorcycle_involved: bool = False
    pedestrian_involved: bool = False

def create_access_token(data: dict, expires_delta: timedelta = timedelta(hours=1)):
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + expires_delta
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def get_db_connection():
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        database=os.getenv("DB_NAME", "dbw_project"),
        user=os.getenv("DB_USER", "postgres"),
        password=os.getenv("DB_PASSWORD", "")
    )

@app.get("/", tags=["Health"])
def root():
    return {"status": "online", "application": "SafeRoute Intelligence"}

@app.get("/favicon.ico", include_in_schema=False)
def favicon():
    return {}

@app.post("/api/auth/register", tags=["Authentication"])
def register_user(user: UserRegister):
    conn = get_db_connection()
    cur = conn.cursor()
    
    cur.execute("SELECT id FROM users WHERE username = %s OR email = %s;", (user.username, user.email))
    if cur.fetchone():
        cur.close()
        conn.close()
        raise HTTPException(status_code=400, detail="Username or email already registered")
    
    hashed_pwd = hash_password(user.password)
    
    try:
        cur.execute(
            "INSERT INTO users (username, email, hashed_password) VALUES (%s, %s, %s);",
            (user.username, user.email, hashed_pwd)
        )
        conn.commit()
        return {"status": "success", "message": "User registered successfully"}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    finally:
        cur.close()
        conn.close()

@app.post("/api/auth/login", tags=["Authentication"])
def login_user(user: UserLogin):
    conn = get_db_connection()
    cur = conn.cursor()
    
    cur.execute("SELECT username, hashed_password FROM users WHERE username = %s;", (user.username,))
    db_user = cur.fetchone()
    
    cur.close()
    conn.close()
    
    if not db_user or not verify_password(user.password, db_user[1]):
        raise HTTPException(status_code=401, detail="Invalid username or password")
    
    access_token = create_access_token(data={"sub": db_user[0]})
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "username": db_user[0],
        "message": "Login successful!"
    }

@app.post("/api/accidents/map", tags=["Accident Data"])
def get_filtered_coordinates(filters: MapFilterRequest):
    from psycopg2.extras import RealDictCursor

    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)

    query = """
        SELECT a.lat, a.lon
        FROM accidents a
        LEFT JOIN city_statistics c ON a.ags = c.ags
        WHERE a.lat IS NOT NULL
          AND a.lon IS NOT NULL
    """
    params = []

    if filters.year is not None:
        query += " AND a.year = %s"
        params.append(filters.year)

    if filters.month is not None:
        query += " AND a.month = %s"
        params.append(filters.month)

    if filters.hour is not None:
        query += " AND a.hour = %s"
        params.append(filters.hour)

    if filters.day_of_week is not None:
        query += " AND a.weekday = %s"
        params.append(filters.day_of_week)

    if filters.city:
        query += " AND LOWER(c.city_name) = LOWER(%s)"
        params.append(filters.city)

    if filters.state:
        query += " AND LOWER(c.state_name) = LOWER(%s)"
        params.append(filters.state)

    if filters.pedestrian_involved:
        query += " AND a.is_pedestrian = TRUE"

    if filters.bike_involved:
        query += " AND a.is_bike = TRUE"

    if filters.car_involved:
        query += " AND a.is_car = TRUE"

    if filters.motorcycle_involved:
        query += " AND a.is_motorcycle = TRUE"

    query += " LIMIT 5000;"

    try:
        cur.execute(query, tuple(params))
        records = cur.fetchall()

        coordinates_list = [[float(row["lat"]), float(row["lon"])] for row in records]
        return {"coordinates": coordinates_list}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Query failed: {str(e)}")
    finally:
        cur.close()
        conn.close()

# 🚀 Path Fix: Removed "/api" to match Flutter's HTTP address call sequence directly
@app.get("/states", tags=["Metadata"])
def get_states():
    from psycopg2.extras import RealDictCursor

    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute(
            "SELECT DISTINCT state_name FROM city_statistics WHERE state_name IS NOT NULL AND state_name != 'Unknown' ORDER BY state_name;"
        )
        rows = cur.fetchall()
        states = [
            {"id": idx + 1, "name": row["state_name"]}
            for idx, row in enumerate(rows)
        ]
        return states
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Could not load states: {e}")
    finally:
        cur.close()
        conn.close()

# 🚀 Logic Fix: Changes state input to an integer to resolve the dropdown key mismatch
@app.get("/cities", tags=["Metadata"])
def get_cities(state: int):
    from psycopg2.extras import RealDictCursor

    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        # First, generate the exact same indexed list of states to decode the dropdown ID
        cur.execute(
            "SELECT DISTINCT state_name FROM city_statistics WHERE state_name IS NOT NULL AND state_name != 'Unknown' ORDER BY state_name;"
        )
        state_list = [row["state_name"] for row in cur.fetchall()]
        
        # Verify if the index number falls within bounds safely
        if state <= 0 or state > len(state_list):
            return []
            
        target_state_name = state_list[state - 1]

        # Fetch distinct cities belonging exclusively to that specific state string profile
        cur.execute(
            "SELECT DISTINCT city_name FROM city_statistics WHERE state_name = %s AND city_name IS NOT NULL ORDER BY city_name;",
            (target_state_name,)
        )
        rows = cur.fetchall()
        cities = [
            {"id": idx + 1, "name": row["city_name"]}
            for idx, row in enumerate(rows)
        ]
        return cities
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Could not load cities: {e}")
    finally:
        cur.close()
        conn.close()

@app.get("/api/accidents/analytics", tags=["Analytics"])
def get_chart_analytics():
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        cur.execute("SELECT month, COUNT(*) as count FROM accidents WHERE month IS NOT NULL GROUP BY month ORDER BY month;")
        monthly_data = cur.fetchall()
        
        cur.execute("SELECT hour, COUNT(*) as count FROM accidents WHERE hour IS NOT NULL GROUP BY hour ORDER BY hour;")
        hourly_data = cur.fetchall()
        
        cur.execute("""
            SELECT
                COUNT(*) FILTER (WHERE is_bike) AS total_bikes,
                COUNT(*) FILTER (WHERE is_car) AS total_cars,
                COUNT(*) FILTER (WHERE is_pedestrian) AS total_pedestrians,
                COUNT(*) FILTER (WHERE is_motorcycle) AS total_motorcycles
            FROM accidents;
        """)
        vehicle_data = cur.fetchone()
        vehicle_data = {
            "total_bikes": vehicle_data[0],
            "total_cars": vehicle_data[1],
            "total_pedestrians": vehicle_data[2],
            "total_motorcycles": vehicle_data[3]
        }
        
        cur.close()
        conn.close()
        
        return {
            "monthly_trends": monthly_data,
            "hourly_density": hourly_data,
            "vehicle_breakdown": vehicle_data
        }
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Analytics backend break: {e}")
    
@app.get("/api/accidents/region/{ags}", tags=["Regional Data"])
def get_regional_statistics(ags: str):
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        cur.execute("SELECT COUNT(*) as total_incidents FROM accidents WHERE LEFT(CAST(ags AS TEXT), 8) = %s;", (ags,))
        incident_count = cur.fetchone()
        
        cur.execute('SELECT * FROM city_statistics WHERE ags = %s LIMIT 1;', (ags,))
        city_stats = cur.fetchone()
        
        cur.close()
        conn.close()
        
        if not city_stats and incident_count == 0:
            raise HTTPException(status_code=404, detail=f"No matching AGS key found: {ags}")
            
        return {
            "ags_key": ags,
            "city_profile": city_stats,
            "live_total_count": incident_count[0] if incident_count else 0
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Regional endpoint break: {e}")