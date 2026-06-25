import psycopg2
import pandas as pd
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr
import bcrypt
import os
from datetime import datetime, timedelta, timezone
from typing import Optional, List
from jose import jwt
import traceback
import numpy as np

load_dotenv()

app = FastAPI(
    title="DBW Accident Data API",
    version="1.0.0"
)

# Fix for CORS errors when frontend connects
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],       
    allow_credentials=False,
    allow_methods=["*"],       
    allow_headers=["*"],       
)

SECRET_KEY = "super_secret_university_project_key"
ALGORITHM = "HS256"

# Hash passwords before saving
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

# Model for handling map search 
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

# ─── OPTIMIZED MEMORY LOADING FOR RENDER FREE TIER (LIMIT TO CHUNKS) ───
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(BASE_DIR, "accident_fallback_data")

try:
    # Using nrows=2000 tells pandas to only load the first 2000 rows
    # This gives us all unique Categories & Accident Types without consuming 512MB of RAM!
    df1 = pd.read_csv(os.path.join(DATA_DIR, "accident_per_location_2023.csv"), sep=";", nrows=2000)
    df2 = pd.read_csv(os.path.join(DATA_DIR, "accident_per_location_2021_in_Schleswig-Holstein.csv"), sep=";", nrows=2000)
    df3 = pd.read_csv(os.path.join(DATA_DIR, "accident_per_10000_per_city.csv"), sep=";", skiprows=2, nrows=2000)
    df4 = pd.read_csv(os.path.join(DATA_DIR, "accidents_with_persons_per_month.csv"), sep=";", skiprows=7, nrows=2000)
    
    df = pd.concat([df1, df2, df3, df4], ignore_index=True)
    print(f"✅ Clean Memory Init: Loaded {len(df)} rows for filter population.")
except Exception as e:
    print(f"⚠️ Warning: Local CSV fallback files couldn't load: {e}")
    df = pd.DataFrame()
    df3 = pd.DataFrame(columns=["schluessel", "regionaleinheit"])
# ───────────────────────────────────────────────────────────────────────BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(BASE_DIR, "accident_fallback_data")

try:
    df1 = pd.read_csv(os.path.join(DATA_DIR, "accident_per_location_2023.csv"), sep=";")
    df2 = pd.read_csv(os.path.join(DATA_DIR, "accident_per_location_2021_in_Schleswig-Holstein.csv"), sep=";")
    df3 = pd.read_csv(os.path.join(DATA_DIR, "accident_per_10000_per_city.csv"), sep=";", skiprows=2)
    df4 = pd.read_csv(os.path.join(DATA_DIR, "accidents_with_persons_per_month.csv"), sep=";", skiprows=7)
    
    df = pd.concat([df1, df2, df3, df4], ignore_index=True)
    print(f" Successfully imported {len(df)} rows from fallback CSV files.")
except Exception as e:
    print(f" Warning: Local CSV fallback files couldn't load: {e}")
    # Fallback initialization to prevent backend crashes if files are completely missing
    df = pd.DataFrame()
    df3 = pd.DataFrame(columns=["schluessel", "regionaleinheit"])
# ───────────────────────────────────────────────────────────────────────

DATA = {
    "states": [
        {"state": "Baden-Württemberg", "cities": ["Stuttgart", "Karlsruhe", "Mannheim", "Freiburg im Breisgau", "Heidelberg", "Heilbronn", "Pforzheim", "Ulm"]},
        {"state": "Bayern", "cities": ["München", "Nürnberg", "Augsburg", "Regensburg", "Ingolstadt", "Würzburg", "Fürth", "Erlangen", "Bamberg"]},
        {"state": "Berlin", "cities": ["Berlin"]},
        {"state": "Brandenburg", "cities": ["Potsdam", "Cottbus", "Brandenburg an der Havel", "Frankfurt (Oder)", "Oranienburg"]},
        {"state": "Bremen", "cities": ["Bremen", "Bremerhaven"]},
        {"state": "Hamburg", "cities": ["Hamburg"]},
        {"state": "Hessen", "cities": ["Wiesbaden", "Frankfurt am Main", "Kassel", "Darmstadt", "Offenbach am Main", "Hanau", "Gießen"]},
        {"state": "Mecklenburg-Vorpommern", "cities": ["Schwerin", "Rostock", "Stralsund", "Greifswald", "Neubrandenburg"]},
        {"state": "Niedersachsen", "cities": ["Hannover", "Braunschweig", "Oldenburg", "Osnabrück", "Wolfsburg", "Göttingen", "Salzgitter", "Hildesheim"]},
        {"state": "Nordrhein-Westfalen", "cities": ["Düsseldorf", "Köln", "Dortmund", "Essen", "Duisburg", "Bochum", "Wuppertal", "Bielefeld", "Bonn", "Münster", "Gelsenkirchen", "Aachen", "Mönchengladbach"]},
        {"state": "Rheinland-Pfalz", "cities": ["Mainz", "Ludwigshafen am Rhein", "Koblenz", "Trier", "Kaiserslautern", "Worms"]},
        {"state": "Saarland", "cities": ["Saarbrücken", "Homburg", "Neunkirchen", "Saarlouis"]},
        {"state": "Sachsen", "cities": ["Dresden", "Leipzig", "Chemnitz", "Zwickau", "Plauen", "Görlitz"]},
        {"state": "Sachsen-Anhalt", "cities": ["Magdeburg", "Halle (Saale)", "Dessau-Roßlau", "Lutherstadt Wittenberg", "Halberstadt"]},
        {"state": "Schleswig-Holstein", "cities": ["Kiel", "Lübeck", "Flensburg", "Neumünster", "Norderstedt"]},
        {"state": "Thüringen", "cities": ["Erfurt", "Jena", "Gera", "Weimar", "Gotha", "Eisenach"]}
    ]
}

CATEGORY_MAP = {
    1: "Fatal Accident",
    2: "Serious Injury Accident",
    3: "Minor Injury Accident"
}

ACCIDENT_TYPE_MAP = {
    1: "Collision with another vehicle turning",
    2: "Collision with another vehicle ahead",
    3: "Collision with another vehicle crossing",
    4: "Collision with oncoming traffic",
    5: "Collision with parked vehicle",
    6: "Collision between vehicle and pedestrian",
    7: "Collision with obstacle",
    8: "Road departure to the right",
    9: "Road departure to the left",
    0: "Other accident"
}

@app.get("/categories")
def get_categories():
    if df.empty: return []
    categories = sorted(df["UKATEGORIE"].dropna().unique())
    return [{"id": int(cat), "name": CATEGORY_MAP.get(int(cat), "Unknown")} for cat in categories]

@app.get("/accidentTypes")
def get_accident_types():
    if df.empty: return []
    types = sorted(df["UART"].dropna().unique())
    return [{"id": int(t), "name": ACCIDENT_TYPE_MAP.get(int(t), "Unknown")} for t in types]

@app.get("/states")
def get_states():
    return [{"id": i + 1, "name": state["state"]} for i, state in enumerate(DATA["states"])]

if not df.empty:
    df["AGS"] = (
        df["ULAND"].fillna(0).astype(int).astype(str).str.zfill(2)
        + df["UREGBEZ"].fillna(0).astype(int).astype(str).str.zfill(1)
        + df["UKREIS"].fillna(0).astype(int).astype(str).str.zfill(2)
        + df["UGEMEINDE"].fillna(0).astype(int).astype(str).str.zfill(3)
    )

if not df3.empty:
    df3["schluessel"] = df3["schluessel"].astype(str).str.zfill(8)

@app.get("/cities")
def get_cities(state: int):
    if state < 1 or state > len(DATA["states"]):
        raise HTTPException(status_code=404, detail="State not found")
    state_data = DATA["states"][state - 1]
    return [{"id": i + 1, "name": city} for i, city in enumerate(state_data["cities"])]

vehicle_types = [
    {"id": 1, "name": "Bicycle", "column": "IstRad"},
    {"id": 2, "name": "Passenger Car", "column": "IstPKW"},
    {"id": 3, "name": "Pedestrian", "column": "IstFuss"},
    {"id": 4, "name": "Motorcycle", "column": "IstKrad"},
    {"id": 5, "name": "Goods Vehicle", "column": "IstGkfz"},
    {"id": 6, "name": "Other Vehicle", "column": "IstSonstige"},
]

@app.get("/vehicleTypes")
def get_vehicle_types():
    return vehicle_types

vehicle_map = {item["id"]: item["column"] for item in vehicle_types}

@app.get("/accidents/filter")
def get_accidents(
    state: int | None = None,
    city: int | None = None,
    year: int | None = None,
    month: int | None = None,
    day: int | None = None,
    hour: int | None = None,
    accident_type: int | None = None,
    category: int | None = None,
    vehicle_type: List[str] = Query(None)
):
    if df.empty:
        return []
        
    filtered = df.copy()

    if state is not None: filtered = filtered[filtered["ULAND"] == state]
    if city is not None: filtered = filtered[filtered["UGEMEINDE"] == city]
    if year is not None: filtered = filtered[filtered["UJAHR"] == year]
    if month is not None: filtered = filtered[filtered["UMONAT"] == month]
    if day is not None: filtered = filtered[filtered["UWOCHENTAG"] == day]
    if hour is not None: filtered = filtered[filtered["USTUNDE"] == hour]
    if accident_type is not None: filtered = filtered[filtered["UART"] == accident_type]
    if category is not None: filtered = filtered[filtered["UKATEGORIE"] == category]

    columns = [vehicle_map[v] for v in (vehicle_type or []) if v in vehicle_map]
    if columns:
        mask = filtered[columns].eq(1).any(axis=1)
        filtered = filtered[mask]

    filtered = filtered.dropna(subset=["YGCSWGS84", "XGCSWGS84", "UKATEGORIE"])

    return [
        {
            "lat": float(str(row["YGCSWGS84"]).replace(",", ".")),
            "lon": float(str(row["XGCSWGS84"]).replace(",", ".")),
            "severity": int(row["UKATEGORIE"]),
            "vehicleType": vehicle_type
        }
        for _, row in filtered.iterrows()
    ]

@app.get("/", tags=["Health"])
def root():
    return {"status": "online"}

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
            "INSERT INTO users (username, email, password_hash) VALUES (%s, %s, %s);",
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
    
    cur.execute("SELECT username, password_hash FROM users WHERE username = %s;", (user.username,))
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
    conn = get_db_connection()
    from psycopg2.extras import RealDictCursor
    cur = conn.cursor(cursor_factory=RealDictCursor)
    
    query = """
        SELECT a.lat, a.lon, a.category, a.year, a.month, a.hour
        FROM accidents a
        JOIN city_statistics c ON a.ags = c.ags
        WHERE 1=1
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
    if filters.city is not None:
        query += " AND c.city_name = %s"
        params.append(filters.city)
    if filters.state is not None:
        query += " AND c.state_name = %s"
        params.append(filters.state)
    if filters.car_involved:
        query += " AND a.is_car = 1"
    if filters.truck_involved:
        query += " AND a.is_truck = 1"
    if filters.bike_involved:
        query += " AND a.is_bike = 1"
    if filters.motorcycle_involved:
        query += " AND a.is_motorcycle = 1"
    if filters.pedestrian_involved:
        query += " AND a.is_pedestrian = 1"
        
    query += " LIMIT 2000;" 
        
    try:
        cur.execute(query, tuple(params))
        records = cur.fetchall()
        
        coordinates_list = [
            {
                "lat": row["lat"],
                "lng": row["lon"],
                "category": row["category"],
                "year": row["year"],
                "month": row["month"],
                "hour": row["hour"]
            }
            for row in records
        ]
        return {"status": "success", "count": len(coordinates_list), "data": coordinates_list}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Query failed: {str(e)}")
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
            SELECT year, month, hour, lat, lon, is_bike, is_car, is_pedestrian, is_motorcycle
            FROM accidents LIMIT 500;
        """)
        vehicle_data = [
            {
                "year": r[0], "month": r[1], "hour": r[2], "lat": r[3], "lon": r[4],
                "is_bike": r[5], "is_car": r[6], "is_pedestrian": r[7], "is_motorcycle": r[8]
            }
            for r in cur.fetchall()
        ]
        
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
        
        cur.execute(
            "SELECT COUNT(*) as total_incidents FROM accidents WHERE "
            "LEFT(CAST(ags AS TEXT), 8) = %s;", (ags,)
        )
        incident_count = cur.fetchone()
        
        cur.execute(
            'SELECT * FROM city_statistics WHERE ags = %s LIMIT 1;', (ags,)
        )
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