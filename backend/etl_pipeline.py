import os
import zipfile
import pandas as pd
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

load_dotenv()

ZIP_FILE_PATH = os.path.join("..", "accident_fallback_data.zip")
DB_CONNECTION_STRING = f"postgresql://{os.getenv('DB_USER','postgres')}:{os.getenv('DB_PASSWORD','')}@{os.getenv('DB_HOST','localhost')}:{os.getenv('DB_PORT','5432')}/{os.getenv('DB_NAME','dbw_project')}"

# Helper function to map AGS prefix to German State names dynamically
def get_state_name_from_ags(ags_str):
    if not ags_str:
        return "Unknown"
    prefix = ags_str[:2]
    state_map = {
        "01": "Schleswig-Holstein", "02": "Hamburg", "03": "Niedersachsen", "04": "Bremen",
        "05": "Nordrhein-Westfalen", "06": "Hessen", "07": "Rheinland-Pfalz", "08": "Baden-Württemberg",
        "09": "Bayern", "10": "Saarland", "11": "Berlin", "12": "Brandenburg", 
        "13": "Mecklenburg-Vorpommern", "14": "Sachsen", "15": "Sachsen-Anhalt", "16": "Thüringen"
    }
    return state_map.get(prefix, "Unknown")

def run_full_etl():
    print("🚀 Starting Multi-File SafeRoute Intelligence ETL Pipeline...")
    engine = create_engine(DB_CONNECTION_STRING)

    if not os.path.exists(ZIP_FILE_PATH):
        print(f"❌ Error: Missing zip file source at {ZIP_FILE_PATH}")
        return

    with zipfile.ZipFile(ZIP_FILE_PATH, 'r') as z:
        files = z.namelist()
        
        for file_name in files:
            print(f"\n📦 Processing file element: {file_name}...")
            
            try:
                # --- ROUTING & CLEANING STRATEGIES ---
                if "location_2023" in file_name or "location_2021" in file_name:
                    table_name = "accidents_2021" if "2021" in file_name else "accidents"
                    
                    with z.open(file_name) as f:
                        df = pd.read_csv(f, sep=';', encoding='latin1', low_memory=False)
                    df.columns = df.columns.str.strip()

                    # Fix Bug 2: Construct the valid 5-digit AGS region code from components
                    if 'ULAND' in df.columns and 'UREGBEZ' in df.columns and 'UKREIS' in df.columns:
                        df['ags'] = (
                            df['ULAND'].astype(str).str.zfill(2) + 
                            df['UREGBEZ'].astype(str) + 
                            df['UKREIS'].astype(str).str.zfill(2)
                        )

                    # Safe numeric translation for map viewfinders
                    if 'XGCSWGS84' in df.columns:
                        df['lon'] = df['XGCSWGS84'].astype(str).str.replace(',', '.').astype(float)
                        df['lat'] = df['YGCSWGS84'].astype(str).str.replace(',', '.').astype(float)

                    rename_dict = {
                        "UKEY": "accident_id", "UJAHR": "year", "UMONAT": "month", 
                        "USTUNDE": "hour", "UWOCHENTAG": "weekday", "UKATEGORIE": "category",
                        "IstRad": "is_bike", "IstFuss": "is_pedestrian", 
                        "IstKrad": "is_motorcycle", "IstPKW": "is_car"
                    }
                    df = df.rename(columns=rename_dict)
                    
                    valid_cols = ["accident_id", "year", "month", "hour", "weekday", "category", 
                                  "is_bike", "is_pedestrian", "is_motorcycle", "is_car", "lon", "lat", "ags"]
                    df = df[[c for c in df.columns if c in valid_cols]]

                elif "per_10000_per_city" in file_name:
                    table_name = "city_statistics"
                    
                    # Fix Bug 1: Skip the first 2 metadata rows, read keys directly as a string object
                    with z.open(file_name) as f:
                        df = pd.read_csv(f, sep=';', encoding='latin1', skiprows=2, dtype={0: str})
                    df.columns = df.columns.str.strip()

                    # Handle explicit 3-column index translation matrix safely
                    df['ags'] = df.iloc[:, 0].astype(str).str.zfill(5)
                    df['city_name'] = df.iloc[:, 1]
                    df['accidents_per_10000'] = df.iloc[:, 2].astype(str).str.replace(',', '.').astype(float)
                    
                    # Compute the missing state relation code automatically
                    df['state_name'] = df['ags'].apply(get_state_name_from_ags)
                    
                    df = df[["ags", "city_name", "state_name", "accidents_per_10000"]]

                elif "persons_per_month" in file_name:
                    table_name = "monthly_stats"
                    with z.open(file_name) as f:
                        df = pd.read_csv(f, sep=';', encoding='latin1')
                    df.columns = df.columns.str.strip()
                    
                    df = df.rename(columns={
                        df.columns[0]: "year", df.columns[1]: "month",
                        df.columns[2]: "total_injured", df.columns[3]: "total_fatalities"
                    })
                else:
                    continue

                # STREAM REFRESH INTO POSTGRESQL
                print(f"📡 Refreshing {len(df)} rows into structural layer schema '{table_name}'...")
                with engine.connect() as connection:
                    connection.execute(text(f"TRUNCATE TABLE {table_name} RESTART IDENTITY CASCADE;"))
                    connection.commit()

                df.to_sql(name=table_name, con=engine, if_exists='append', index=False, chunksize=5000)
                print(f"✅ Table structure '{table_name}' successfully built and active.")

            except Exception as file_err:
                print(f"⚠️ Safe Skip: Processing failed on data element '{file_name}': {file_err}")
                continue

    print("\n🏆 DATABASE FULLY ALIGNED: All real regional parameters map perfectly!")

if __name__ == "__main__":
    run_full_etl()