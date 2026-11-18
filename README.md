# SafeRoute Intelligence

A full-stack platform that integrates official German road-accident open data into a PostgreSQL database and exposes it through a documented REST API and an interactive Flutter map client.

Built as the final project for *Datenbanken und Web-Techniken* (Databases and Web Technologies) at TU Chemnitz, summer semester 2026.

**Live demo**
- Web app: https://viratmaan.github.io/saferoute-backend/
- API docs (Swagger UI): https://saferoute-intelligence-api.onrender.com/docs

> The API runs on a free Render instance, so the first request after a period of inactivity can take about a minute while it wakes up.

---

## What it does

- Ingests accident point data (Unfallatlas) and regional statistics, and harmonises them on the official municipality key (AGS).
- Serves filtered accident locations by state, city, year, month, weekday, hour, accident category, accident type and participant type (bicycle, car, pedestrian, motorcycle, goods vehicle).
- Shows results on an interactive map with marker clustering, plus a filter drawer.
- Provides user registration and login (bcrypt-hashed passwords).
- Ships an OpenAPI 3.0 specification (`openapi.json`).

## Architecture

```
Flutter app (GitHub Pages)
        |  HTTPS / REST
        v
FastAPI backend (Render)  <---- .env configuration
        |
        +-- PostgreSQL  (accidents, city_statistics, monthly_stats, users)
        +-- CSV fallback layer (chunk-loaded to stay inside memory limits)
```

| Table | Content | Source |
|---|---|---|
| `accidents` | Accident points, 2023 (nationwide) | Unfallatlas, OpenGeoData NRW |
| `accidents_2021` | Accident points, 2021 (Schleswig-Holstein) | Unfallatlas, OpenGeoData NRW |
| `city_statistics` | Accidents per 10,000 inhabitants by region | Regionalstatistik |
| `monthly_stats` | Injured / fatalities per month | Destatis GENESIS |
| `users` | Accounts | n/a |

**Join key.** The AGS (Amtlicher Gemeindeschlüssel) is not a single column in the Unfallatlas CSV. It is assembled from `ULAND` + `UREGBEZ` + `UKREIS` and matched to the keys in the regional statistics.

## Tech stack

Python, FastAPI, PostgreSQL, pandas, SQLAlchemy, psycopg2, bcrypt, Flutter (Dart), flutter_map with OpenStreetMap tiles, Render, GitHub Pages.

## Repository layout

```
.github/workflows/deploy.yml   builds the Flutter web app and publishes it to GitHub Pages
backend/
  main.py                      FastAPI application and endpoints
  init_db.py                   creates the database and tables
  etl_pipeline.py              extract, parse, map, load into PostgreSQL
  openapi.json                 OpenAPI 3.0 specification
  Requirements.txt             Python dependencies
  accident_fallback_data/      source CSVs (Unfallatlas, Regionalstatistik, GENESIS)
frontend/myapp/
  lib/                         Flutter source (login, dashboard, map)
  pubspec.yaml
```

## Run it locally

**Prerequisites:** Python 3.11+, PostgreSQL 15+, Flutter 3.x.

```bash
# 1. Backend configuration: create backend/.env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=dbw_project
DB_USER=postgres
DB_PASSWORD=<your password>

# 2. Install and create the schema
cd backend
pip install -r Requirements.txt
python init_db.py

# 3. Load data (see "Data" below), then start the API
python etl_pipeline.py
uvicorn main:app --reload --port 8000
# Swagger UI: http://localhost:8000/docs

# 4. Frontend
cd ../frontend/myapp
flutter pub get
flutter run
```

Point `_baseUrl` in `login.dart` and `dashboard.dart` at `http://localhost:8000` for local development.

## Data

The source CSVs are included in `backend/accident_fallback_data/` because the deployed API reads them at runtime. They are redistributed under the licence below. The ETL script expects them zipped as `accident_fallback_data.zip` one directory above `backend/`.

- Unfallatlas: https://www.opengeodata.nrw.de/produkte/transport_verkehr/unfallatlas/
- Regionalstatistik: https://www.regionalstatistik.de/

**Licence of the source data:** Datenlizenz Deutschland, Namensnennung 2.0 (dl-de/by-2-0). Attribution: Statistische Ämter des Bundes und der Länder, Unfallatlas / OpenGeoData NRW.

## API overview

| Method | Endpoint | Description |
|---|---|---|
| GET | `/states`, `/cities?state=` | Region metadata |
| GET | `/categories`, `/accidentTypes`, `/vehicleTypes` | Code tables |
| GET | `/accidents/filter` | Filtered accident coordinates (`limit` up to 5000) |
| POST | `/api/accidents/map` | Database query joined with `city_statistics` |
| POST | `/api/auth/register`, `/api/auth/login` | Accounts |

Full documentation is available in Swagger UI (`/docs`) and `openapi.json`.

## Known limitations

This was a time-boxed university project, and these are the open items:

- **Partial year coverage.** Unfallatlas publishes 2016 to 2024. This deployment holds 2023 (nationwide) and 2021 (Schleswig-Holstein only). The free Render tier (512 MB RAM) ran out of memory with the full data loaded in memory.
- **No aggregate endpoint.** Accident endpoints return coordinates and severity, not totals. A `GET /accidents/count` endpoint is the next step.
- **Row cap.** Responses are limited to a maximum of 5000 records per request.
- **Login token.** The login endpoint returns a placeholder token rather than a signed JWT. Real token issuing and verification are not implemented yet.
- **Map UX.** The camera zooms to the filtered region, but zooming back out is not smooth.

## Author

Virat Maan
