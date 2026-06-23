import os
import psycopg2
from dotenv import load_dotenv

load_dotenv()

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "dbw_project")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "") 

def setup_database():
    print("🔌 Connecting to master PostgreSQL engine...")
    try:
        conn = psycopg2.connect(
            dbname="postgres",
            user=DB_USER,
            password=DB_PASSWORD,
            host=DB_HOST,
            port=DB_PORT
        )
        conn.autocommit = True
        cur = conn.cursor()
        
        cur.execute(f"CREATE DATABASE {DB_NAME};")
        print(f"✨ Database '{DB_NAME}' successfully created!")
    except psycopg2.errors.DuplicateDatabase:
        print(f"📦 Database '{DB_NAME}' already exists. Moving to table schema generation...")
    except Exception as e:
        print(f"❌ Master engine connection failure: {e}")
        return
    finally:
        if 'cur' in locals(): cur.close()
        if 'conn' in locals(): conn.close()

    print(f"🗄️ Connecting directly to '{DB_NAME}' to configure structural constraints...")
    try:
        conn = psycopg2.connect(
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            host=DB_HOST,
            port=DB_PORT
        )
        cur = conn.cursor()
    except Exception as e:
        print(f"❌ Failed to log into database '{DB_NAME}': {e}")
        return
    
    create_tables_query = """
    CREATE TABLE IF NOT EXISTS accidents (
        accident_id VARCHAR(100) PRIMARY KEY,
        year INT NOT NULL,
        month INT NOT NULL,
        hour INT NOT NULL,
        weekday INT NOT NULL,
        category INT NOT NULL,
        is_bike BOOLEAN DEFAULT FALSE,
        is_pedestrian BOOLEAN DEFAULT FALSE,
        is_motorcycle BOOLEAN DEFAULT FALSE,
        is_car BOOLEAN DEFAULT FALSE,
        lon DECIMAL(9,6) NOT NULL,
        lat DECIMAL(9,6) NOT NULL,
        ags VARCHAR(8)
    );

    CREATE TABLE IF NOT EXISTS accidents_2021 (
        accident_id VARCHAR(100) PRIMARY KEY,
        year INT NOT NULL,
        month INT NOT NULL,
        hour INT NOT NULL,
        weekday INT NOT NULL,
        category INT NOT NULL,
        is_bike BOOLEAN DEFAULT FALSE,
        is_pedestrian BOOLEAN DEFAULT FALSE,
        is_motorcycle BOOLEAN DEFAULT FALSE,
        is_car BOOLEAN DEFAULT FALSE,
        lon DECIMAL(9,6) NOT NULL,
        lat DECIMAL(9,6) NOT NULL,
        ags VARCHAR(8)
    );

    CREATE TABLE IF NOT EXISTS city_statistics (
        ags VARCHAR(8) PRIMARY KEY,
        city_name VARCHAR(255) NOT NULL,
        state_name VARCHAR(100),
        accidents_per_10000 DECIMAL(10,2)
    );

    CREATE TABLE IF NOT EXISTS monthly_stats (
        id SERIAL PRIMARY KEY,
        year INT NOT NULL,
        month INT NOT NULL,
        total_injured INT DEFAULT 0,
        total_fatalities INT DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        email VARCHAR(100) UNIQUE NOT NULL,
        hashed_password VARCHAR(255) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    """
    
    try:
        cur.execute(create_tables_query)
        conn.commit()
        print("🚀 Success! All table targets are safely constructed and typed inside your relational schema.")
    except Exception as e:
        print(f"❌ Database blueprint failure: {e}")
    finally:
        cur.close()
        conn.close()

if __name__ == "__main__":
    setup_database()