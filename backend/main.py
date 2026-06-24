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

# fix for cors errors when frontend connects
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],       
    allow_credentials=False,
    allow_methods=["*"],       
    allow_headers=["*"],       
)

SECRET_KEY = "super_secret_university_project_key"
ALGORITHM = "HS256"

# hash passwords before saving
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

# model for handling map search 
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

def create_access_token(data: dict, expires_delta: timedelta = timedelta(hours=12)):
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + expires_delta
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)



def get_db_connection():
    return psycopg2.connect(
        host=os.getenv("DB_HOST"),
        database=os.getenv("DB_NAME"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD")

        )

df1 = pd.read_csv(
            r"https://github.com/ViratMaan/saferoute-backend/blob/main/accident_per_location_2023.csv",
    sep=";"
        )

df2 = pd.read_csv(
            r"https://github.com/ViratMaan/saferoute-backend/blob/main/accident_per_location_2021_in_Schleswig-Holstein.csv",
    sep=";"
        )



df3 = pd.read_csv(
    r"https://github.com/ViratMaan/saferoute-backend/blob/main/accident_per_10000_per_city.csv",
    sep=";",
    skiprows=2
)

df4 = pd.read_csv(
    r"https://github.com/ViratMaan/saferoute-backend/blob/main/accidents_with_persons_per_month.csv",
    sep=";",
    skiprows=7
)

df = pd.concat([df1, df2, df3, df4], ignore_index=True)

# print(f"✅ Successfully imported {len(df)} rows from CSV into the database.")
# print(df.columns.tolist())

# print(df["UGEMEINDE"].head(10))
# print(df3["schluessel"].head(10))
# print(df3["regionaleinheit"].head(10))
# print(df["UGEMEINDE"].dtype)
# print(df3["schluessel"].dtype)

DATA = {
    "states": [
        {
            "state": "Baden-Württemberg",
            "cities": [
                "Stuttgart", "Karlsruhe", "Mannheim",
                "Freiburg im Breisgau", "Heidelberg",
                "Heilbronn", "Pforzheim", "Ulm"
            ]
        },
        {
            "state": "Bayern",
            "cities": [
                "München", "Nürnberg", "Augsburg",
                "Regensburg", "Ingolstadt",
                "Würzburg", "Fürth", "Erlangen", "Bamberg"
            ]
        },
        {
            "state": "Berlin",
            "cities": ["Berlin"]
        },
        {
            "state": "Brandenburg",
            "cities": [
                "Potsdam", "Cottbus",
                "Brandenburg an der Havel",
                "Frankfurt (Oder)", "Oranienburg"
            ]
        },
        {
            "state": "Bremen",
            "cities": ["Bremen", "Bremerhaven"]
        },
        {
            "state": "Hamburg",
            "cities": ["Hamburg"]
        },
        {
            "state": "Hessen",
            "cities": [
                "Wiesbaden", "Frankfurt am Main",
                "Kassel", "Darmstadt",
                "Offenbach am Main", "Hanau", "Gießen"
            ]
        },
        {
            "state": "Mecklenburg-Vorpommern",
            "cities": [
                "Schwerin", "Rostock",
                "Stralsund", "Greifswald",
                "Neubrandenburg"
            ]
        },
        {
            "state": "Niedersachsen",
            "cities": [
                "Hannover", "Braunschweig",
                "Oldenburg", "Osnabrück",
                "Wolfsburg", "Göttingen",
                "Salzgitter", "Hildesheim"
            ]
        },
        {
            "state": "Nordrhein-Westfalen",
            "cities": [
                "Düsseldorf", "Köln", "Dortmund",
                "Essen", "Duisburg", "Bochum",
                "Wuppertal", "Bielefeld", "Bonn",
                "Münster", "Gelsenkirchen",
                "Aachen", "Mönchengladbach"
            ]
        },
        {
            "state": "Rheinland-Pfalz",
            "cities": [
                "Mainz", "Ludwigshafen am Rhein",
                "Koblenz", "Trier",
                "Kaiserslautern", "Worms"
            ]
        },
        {
            "state": "Saarland",
            "cities": [
                "Saarbrücken", "Homburg",
                "Neunkirchen", "Saarlouis"
            ]
        },
        {
            "state": "Sachsen",
            "cities": [
                "Dresden", "Leipzig",
                "Chemnitz", "Zwickau",
                "Plauen", "Görlitz"
            ]
        },
        {
            "state": "Sachsen-Anhalt",
            "cities": [
                "Magdeburg", "Halle (Saale)",
                "Dessau-Roßlau",
                "Lutherstadt Wittenberg",
                "Halberstadt"
            ]
        },
        {
            "state": "Schleswig-Holstein",
            "cities": [
                "Kiel", "Lübeck",
                "Flensburg", "Neumünster",
                "Norderstedt"
            ]
        },
        {
            "state": "Thüringen",
            "cities": [
                "Erfurt", "Jena",
                "Gera", "Weimar",
                "Gotha", "Eisenach"
            ]
        }
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
    categories = sorted(
        df["UKATEGORIE"]
        .dropna()
        .unique()
    )

    return [
        {
            "id": int(cat),
            "name": CATEGORY_MAP.get(
                int(cat),
                "Unknown"
            )
        }
        for cat in categories
    ]

@app.get("/accidentTypes")
def get_accident_types():
    types = sorted(
        df["UART"]
        .dropna()
        .unique()
    )

    return [
        {
            "id": int(t),
            "name": ACCIDENT_TYPE_MAP.get(
                int(t),
                "Unknown"
            )
        }
        for t in types
    ]
@app.get("/states")
def get_states():
    return [
        {
            "id": i + 1,
            "name": state["state"]
        }
        for i, state in enumerate(DATA["states"])
    ]
df["AGS"] = (
    df["ULAND"].fillna(0).astype(int).astype(str).str.zfill(2)
    + df["UREGBEZ"].fillna(0).astype(int).astype(str).str.zfill(1)
    + df["UKREIS"].fillna(0).astype(int).astype(str).str.zfill(2)
    + df["UGEMEINDE"].fillna(0).astype(int).astype(str).str.zfill(3)
)
df3["schluessel"] = (
    df3["schluessel"]
    .astype(str)
    .str.zfill(8)
)

print('KHUSHI')
print(df["AGS"].str.len().value_counts())
print(df3["schluessel"].astype(str).str.len().value_counts())
print(df[["ULAND","UREGBEZ","UKREIS","UGEMEINDE"]].head(20))
print(df["AGS"].head(20))
# print(df.columns)
# print(df3.columns)
# print(df3.head(20))
# print(df3[["schluessel", "regionaleinheit"]].head(20))

@app.get("/cities")
def get_cities(state: int):
    state_data = DATA["states"][state - 1]

    return [
                {
                    "id": i + 1,
                    "name": city
                }
                for i, city in enumerate(state_data ["cities"])
            ]

    raise HTTPException(
        status_code=404,
        detail="State not found"
    )

# @app.get("/cities")
# def get_cities(state: int):
#     cities = (
#         df[df["ULAND"] == state]
#         ["UGEMEINDE"]
#         .dropna()
#         .unique()
#     )

#     return [
#         {
#             "id": int(city),
#             "name": CITY_MAP.get(
#                 int(city),
#                 f"City {city}"
#             )
#         }
#         for city in cities
#     ]

print(f"✅ Successfully imported states for dropdown filter {(get_states())} endpoint.")
print(f"✅ Successfully imported cities for dropdown filter {(get_cities(2))} endpoint.")
print(f"✅ Successfully imported categories for dropdown filter {(get_categories())} endpoint.")
print(f"✅ Successfully imported accident types for dropdown filter {(get_accident_types())} endpoint.")

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

vehicle_map = {
    item["id"]: item["column"]
    for item in vehicle_types
}

# print(df["ULAND"].unique())
# print(df["UGEMEINDE"].unique())
# print(df["UJAHR"].unique())
# print(df["UMONAT"].unique())
# print(df["UWOCHENTAG"].unique())
# print(df["USTUNDE"].unique())
# print(df["UART"].unique())
# print(df["UKATEGORIE"].unique())
# print(df.columns.tolist())


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
    filtered = df.copy()

    if state is not None:
        filtered = filtered[filtered["ULAND"] == state]

    if city is not None:
        filtered = filtered[filtered["UGEMEINDE"] == city]

    if year is not None:
        filtered = filtered[filtered["UJAHR"] == year]

    if month is not None:
        filtered = filtered[filtered["UMONAT"] == month]

    if day is not None:
        filtered = filtered[filtered["UWOCHENTAG"] == day]

    if hour is not None:
        filtered = filtered[filtered["USTUNDE"] == hour]

    if accident_type is not None:
        filtered = filtered[filtered["UART"] == accident_type]

    if category is not None:
        filtered = filtered[filtered["UKATEGORIE"] == category]

    columns = [
        vehicle_map[v]
        for v in (vehicle_type or [])
        if v in vehicle_map
    ]

    if columns:
        mask = filtered[columns].eq(1).any(axis=1)
        filtered = filtered[mask]

    filtered = filtered.dropna(
        subset=["YGCSWGS84", "XGCSWGS84", "UKATEGORIE"]
    )

    return [
    {
        "lat": float(str(row["YGCSWGS84"]).replace(",", ".")),
        "lon": float(str(row["XGCSWGS84"]).replace(",", ".")),
        "severity": int(row["UKATEGORIE"]),
        "vehicleType": vehicle_type
    }
    for _, row in filtered.iterrows()
]

combo = (
    df[
        [
            "ULAND",
            "UGEMEINDE",
            "UJAHR",
            "UMONAT",
            "UWOCHENTAG",
            "USTUNDE",
            "UART",
            "UKATEGORIE"
        ]
    ]
    .dropna()
    .drop_duplicates()
    .iloc[0]
)

print(combo)

print(f"✅ Successfully imported vehicle {(get_vehicle_types())} endpoint.")
print(f"✅ Successfully imported accidents {(get_accidents(1,0,2023,5,6,22,5,3,[1,2]))} endpoint.")

# print(f"✅ Successfully imported accidents {(get_accidents(1, 0, 2023, None, 6, None, 5, None, [1]))} endpoint.")

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

    print("Username:", user.username)
    
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
    print("DB result:", db_user)
    
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

# converted to post
@app.post("/api/accidents/map", tags=["Accident Data"])
def get_filtered_coordinates(filters: MapFilterRequest):
    conn = get_db_connection()
    
    # 🌟 CHANGE THIS LINE: Add cursor_factory
    from psycopg2.extras import RealDictCursor
    cur = conn.cursor(cursor_factory=RealDictCursor)
    
    query = """
        SELECT a.lat, a.lon, a.category, a.year, a.month, a.hour
        FROM accidents a
        JOIN city_statistics c ON a.ags = c.ags
        WHERE 1=1
    """
    params = []
    
    # ... (keep all your IF statements for filters exactly the same) ...
    
    if filters.pedestrian_involved:
        query += " AND a.is_pedestrian = 1"
        
    query += " LIMIT 2000;" 
        
    try:
        cur.execute(query, tuple(params))
        records = cur.fetchall()  # 🌟 This is now a list of dictionaries!
        
        # 🌟 UPDATE THIS BLOCK: Read by column name strings instead of numbers
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

        cur.execute("SELECT current_database();")
        print("Database:", cur.fetchone())

        cur.execute("SELECT current_schema();")
        print("Schema:", cur.fetchone())
        
        cur.execute("SELECT month, COUNT(*) as count FROM accidents WHERE month IS NOT NULL GROUP BY month ORDER BY month;")
        monthly_data = cur.fetchall()
        
        cur.execute("SELECT hour, COUNT(*) as count FROM accidents WHERE hour IS NOT NULL GROUP BY hour ORDER BY hour;")
        hourly_data = cur.fetchall()
        
        cur.execute("""
            SELECT
                year,
            month,
            hour,
            lat,
            lon,
            is_bike,
            is_car,
            is_pedestrian,
            is_motorcycle
            FROM accidents;
        """)
        vehicle_data = cur.fetchone()
        vehicle_data = [
             {
            "year": r[0],
            "month": r[1],
            "hour": r[2],
            "lat": r[3],
            "lon": r[4],
            "is_bike": r[5],
            "is_car": r[6],
            "is_pedestrian": r[7],
            "is_motorcycle": r[8]
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
        
        # checks string length matching
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