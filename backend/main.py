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
    vehicle_type: List[str] = Query(None),
    limit: int = Query(1000, ge=1, le=2000) # Reduced baseline chunk footprint
):
    if df.empty: 
        return []
        
    try:
        # Avoid full df.copy() memory spikes by slicing columns early
        columns_needed = ["YGCSWGS84", "XGCSWGS84", "UKATEGORIE", "ULAND", "UGEMEINDE", "UART"]
        for v in (vehicle_type or []):
            if int(v) in vehicle_map and vehicle_map[int(v)] in df.columns:
                columns_needed.append(vehicle_map[int(v)])
                
        # Filter available columns dynamically to save RAM space
        available_cols = [c for c in columns_needed if c in df.columns]
        filtered = df[available_cols].copy()
        
        # Apply standard structural filters
        if state is not None and state != 0: 
            filtered = filtered[filtered["ULAND"] == state]
        if city is not None and city != 1000000: 
            filtered = filtered[filtered["UGEMEINDE"] == city]
        if accident_type is not None and accident_type != -1: 
            filtered = filtered[filtered["UART"] == accident_type]
            
        # ─── CORE FIX: MAP CATEGORIES SAFELY ───
        if category is not None and category != 0: 
            filtered = filtered[filtered["UKATEGORIE"] == category]

        # ─── CORE FIX: MAP VEHICLE TYPES SAFELY ───
        if vehicle_type:
            active_cols = [vehicle_map[int(v)] for v in vehicle_type if int(v) in vehicle_map]
            if active_cols:
                mask = filtered[active_cols].eq(1).any(axis=1)
                filtered = filtered[mask]

        # Clean rows efficiently
        filtered = filtered.dropna(subset=["YGCSWGS84", "XGCSWGS84", "UKATEGORIE"])
        filtered = filtered.head(limit)
        
        return [
            {
                "lat": float(str(row["YGCSWGS84"]).replace(",", ".")),
                "lon": float(str(row["XGCSWGS84"]).replace(",", ".")),
                "severity": int(row["UKATEGORIE"]),
                "vehicleType": vehicle_type or []
            }
            for _, row in filtered.iterrows()
        ]
    except Exception as e:
        print(f"Filter processing anomaly intercepted: {e}")
        return [] 
