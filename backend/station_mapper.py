import math
from typing import Tuple, Dict

STATION_COORDINATES: Dict[str, dict] = {
    "SHA": {"name": "Shasta Lake",              "lat": 40.75417, "lon": -122.35361},
    "ORO": {"name": "Lake Oroville",            "lat": 39.53722, "lon": -121.48333},
    "TRM": {"name": "Trinity Lake",             "lat": 40.86000, "lon": -122.72333},
    "NML": {"name": "New Melones Lake",         "lat": 38.00056, "lon": -120.52000},
    "SNL": {"name": "San Luis Reservoir",       "lat": 37.06778, "lon": -121.13111},
    "DNP": {"name": "Don Pedro Reservoir",      "lat": 37.74167, "lon": -120.37361},
    "BER": {"name": "Lake Berryessa",           "lat": 38.53139, "lon": -122.16361},
    "FOL": {"name": "Folsom Lake",              "lat": 38.72389, "lon": -121.11750},
    "EXC": {"name": "Lake McClure (Exchequer)", "lat": 37.63639, "lon": -120.28028},
    "PNF": {"name": "Pine Flat Lake",           "lat": 36.83250, "lon": -119.32583},
    "BUL": {"name": "New Bullards Bar",         "lat": 39.39222, "lon": -121.14167},
    "MIL": {"name": "Millerton Lake",           "lat": 36.99750, "lon": -119.69333},
    "CMN": {"name": "Camanche Reservoir",       "lat": 38.22389, "lon": -120.96778},
    "SNN": {"name": "Lake Sonoma",              "lat": 38.71806, "lon": -123.00944},
    "CLE": {"name": "Whiskeytown Lake",         "lat": 40.62806, "lon": -122.56417},
    "CAS": {"name": "Castaic Lake",             "lat": 34.52000, "lon": -118.60639},
    "CCH": {"name": "Lake Cachuma",             "lat": 34.58667, "lon": -119.98111},
    "PAR": {"name": "Pardee Reservoir",         "lat": 38.25750, "lon": -120.85028},
}


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Calculate distance in miles between two lat/lon points using the Haversine formula.
    """
    R = 3958.8  # Earth's radius in miles

    lat1_r, lat2_r = math.radians(lat1), math.radians(lat2)
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)

    a = (math.sin(dlat / 2) ** 2 +
         math.cos(lat1_r) * math.cos(lat2_r) * math.sin(dlon / 2) ** 2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    return R * c


def get_nearest_station(lat: float, lon: float) -> dict:
    """
    Given a lat/lon from the frontend, find the closest CDEC reservoir station.

    Input:
        lat: float — latitude from the frontend
        lon: float — longitude from the frontend

    Returns:
        dict with:
            - station_id: str (e.g. "SHA")
            - station_name: str (e.g. "Shasta Lake")
            - station_lat: float
            - station_lon: float
            - distance_miles: float (how far the user's location is from the station)
    """
    closest = None
    min_dist = float("inf")

    for station_id, info in STATION_COORDINATES.items():
        dist = haversine_distance(lat, lon, info["lat"], info["lon"])
        if dist < min_dist:
            min_dist = dist
            closest = {
                "station_id": station_id,
                "station_name": info["name"],
                "station_lat": info["lat"],
                "station_lon": info["lon"],
                "distance_miles": round(dist, 1),
            }

    return closest


# ─────────────────────────────────────────────
# DEMO / TEST
# ─────────────────────────────────────────────
if __name__ == "__main__":
    test_locations = [
        (34.0522, -118.2437, "Los Angeles"),
        (38.5816, -121.4944, "Sacramento"),
        (37.7749, -122.4194, "San Francisco"),
        (36.7378, -119.7871, "Fresno"),
        (40.5865, -122.3917, "Redding"),
        (34.4208, -119.6982, "Santa Barbara"),
        (37.3382, -121.8863, "San Jose"),
        (39.5296, -121.5547, "Oroville (city)"),
        (38.6780, -121.1761, "Folsom (city)"),
        (33.9425, -117.2297, "Riverside"),
    ]

    print("Station Mapping Results:")
    print("=" * 80)
    for lat, lon, city in test_locations:
        result = get_nearest_station(lat, lon)
        print(
            f"  {city:<22} -> {result['station_id']} ({result['station_name']}) "
            f"— {result['distance_miles']} miles away"
        )
