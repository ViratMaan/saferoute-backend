import psycopg2

try:
    print("🔌 Connecting to database...")
    conn = psycopg2.connect(dbname="postgres", user="postgres", host="localhost", port="5432")
    conn.autocommit = True
    cur = conn.cursor()
    
    # Executing the query with explicit single quotes around the password string
    cur.execute("ALTER USER postgres WITH PASSWORD 'admin1';")
    
    print("🔒 Password successfully updated to admin1!")
    cur.close()
    conn.close()
except Exception as e:
    print(f"❌ Error resetting password: {e}")