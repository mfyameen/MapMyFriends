#!/usr/bin/env python3
"""Generates a deterministic 1000-contact fixture spanning the US and the world."""

import json
import os
import random

random.seed(20260731)

# (city, admin_area, postal, country, lat, lng) — real coordinates, city centres.
US_CITIES = [
    ("Birmingham", "AL", "35203", 33.5186, -86.8104),
    ("Anchorage", "AK", "99501", 61.2181, -149.9003),
    ("Phoenix", "AZ", "85004", 33.4484, -112.0740),
    ("Little Rock", "AR", "72201", 34.7465, -92.2896),
    ("Los Angeles", "CA", "90012", 34.0522, -118.2437),
    ("San Francisco", "CA", "94102", 37.7749, -122.4194),
    ("San Diego", "CA", "92101", 32.7157, -117.1611),
    ("Denver", "CO", "80202", 39.7392, -104.9903),
    ("Hartford", "CT", "06103", 41.7658, -72.6734),
    ("Wilmington", "DE", "19801", 39.7391, -75.5398),
    ("Washington", "DC", "20001", 38.9072, -77.0369),
    ("Miami", "FL", "33130", 25.7617, -80.1918),
    ("Orlando", "FL", "32801", 28.5383, -81.3792),
    ("Atlanta", "GA", "30303", 33.7490, -84.3880),
    ("Honolulu", "HI", "96813", 21.3069, -157.8583),
    ("Boise", "ID", "83702", 43.6150, -116.2023),
    ("Chicago", "IL", "60601", 41.8781, -87.6298),
    ("Indianapolis", "IN", "46204", 39.7684, -86.1581),
    ("Des Moines", "IA", "50309", 41.5868, -93.6250),
    ("Wichita", "KS", "67202", 37.6872, -97.3301),
    ("Louisville", "KY", "40202", 38.2527, -85.7585),
    ("New Orleans", "LA", "70112", 29.9511, -90.0715),
    ("Portland", "ME", "04101", 43.6591, -70.2568),
    ("Baltimore", "MD", "21201", 39.2904, -76.6122),
    ("Boston", "MA", "02108", 42.3601, -71.0589),
    ("Detroit", "MI", "48226", 42.3314, -83.0458),
    ("Minneapolis", "MN", "55401", 44.9778, -93.2650),
    ("Jackson", "MS", "39201", 32.2988, -90.1848),
    ("Kansas City", "MO", "64106", 39.0997, -94.5786),
    ("St. Louis", "MO", "63101", 38.6270, -90.1994),
    ("Billings", "MT", "59101", 45.7833, -108.5007),
    ("Omaha", "NE", "68102", 41.2565, -95.9345),
    ("Las Vegas", "NV", "89101", 36.1699, -115.1398),
    ("Manchester", "NH", "03101", 42.9956, -71.4548),
    ("Newark", "NJ", "07102", 40.7357, -74.1724),
    ("Albuquerque", "NM", "87102", 35.0844, -106.6504),
    ("New York", "NY", "10001", 40.7128, -74.0060),
    ("Buffalo", "NY", "14202", 42.8864, -78.8784),
    ("Charlotte", "NC", "28202", 35.2271, -80.8431),
    ("Fargo", "ND", "58102", 46.8772, -96.7898),
    ("Columbus", "OH", "43215", 39.9612, -82.9988),
    ("Cleveland", "OH", "44113", 41.4993, -81.6944),
    ("Oklahoma City", "OK", "73102", 35.4676, -97.5164),
    ("Portland", "OR", "97204", 45.5152, -122.6784),
    ("Philadelphia", "PA", "19107", 39.9526, -75.1652),
    ("Pittsburgh", "PA", "15222", 40.4406, -79.9959),
    ("Providence", "RI", "02903", 41.8240, -71.4128),
    ("Charleston", "SC", "29401", 32.7765, -79.9311),
    ("Sioux Falls", "SD", "57104", 43.5460, -96.7313),
    ("Nashville", "TN", "37203", 36.1627, -86.7816),
    ("Memphis", "TN", "38103", 35.1495, -90.0490),
    ("Austin", "TX", "78701", 30.2672, -97.7431),
    ("Houston", "TX", "77002", 29.7604, -95.3698),
    ("Dallas", "TX", "75201", 32.7767, -96.7970),
    ("Salt Lake City", "UT", "84101", 40.7608, -111.8910),
    ("Burlington", "VT", "05401", 44.4759, -73.2121),
    ("Richmond", "VA", "23219", 37.5407, -77.4360),
    ("Seattle", "WA", "98101", 47.6062, -122.3321),
    ("Spokane", "WA", "99201", 47.6588, -117.4260),
    ("Charleston", "WV", "25301", 38.3498, -81.6326),
    ("Milwaukee", "WI", "53202", 43.0389, -87.9065),
    ("Cheyenne", "WY", "82001", 41.1400, -104.8202),
]

INTL_CITIES = [
    ("Toronto", "ON", "M5H 2N2", "Canada", 43.6532, -79.3832),
    ("Vancouver", "BC", "V6B 1A1", "Canada", 49.2827, -123.1207),
    ("Montreal", "QC", "H2Y 1C6", "Canada", 45.5019, -73.5674),
    ("Mexico City", "CDMX", "06000", "Mexico", 19.4326, -99.1332),
    ("Guadalajara", "JAL", "44100", "Mexico", 20.6597, -103.3496),
    ("London", "", "EC1A 1BB", "United Kingdom", 51.5074, -0.1278),
    ("Manchester", "", "M1 1AE", "United Kingdom", 53.4808, -2.2426),
    ("Edinburgh", "", "EH1 1YZ", "United Kingdom", 55.9533, -3.1883),
    ("Dublin", "", "D02 X285", "Ireland", 53.3498, -6.2603),
    ("Paris", "", "75001", "France", 48.8566, 2.3522),
    ("Lyon", "", "69001", "France", 45.7640, 4.8357),
    ("Berlin", "", "10115", "Germany", 52.5200, 13.4050),
    ("Munich", "", "80331", "Germany", 48.1351, 11.5820),
    ("Amsterdam", "", "1012 JS", "Netherlands", 52.3676, 4.9041),
    ("Brussels", "", "1000", "Belgium", 50.8503, 4.3517),
    ("Zurich", "", "8001", "Switzerland", 47.3769, 8.5417),
    ("Vienna", "", "1010", "Austria", 48.2082, 16.3738),
    ("Prague", "", "110 00", "Czechia", 50.0755, 14.4378),
    ("Warsaw", "", "00-001", "Poland", 52.2297, 21.0122),
    ("Stockholm", "", "111 20", "Sweden", 59.3293, 18.0686),
    ("Oslo", "", "0150", "Norway", 59.9139, 10.7522),
    ("Copenhagen", "", "1050", "Denmark", 55.6761, 12.5683),
    ("Helsinki", "", "00100", "Finland", 60.1699, 24.9384),
    ("Madrid", "", "28013", "Spain", 40.4168, -3.7038),
    ("Barcelona", "", "08001", "Spain", 41.3874, 2.1686),
    ("Lisbon", "", "1100-148", "Portugal", 38.7223, -9.1393),
    ("Rome", "", "00184", "Italy", 41.9028, 12.4964),
    ("Milan", "", "20121", "Italy", 45.4642, 9.1900),
    ("Athens", "", "105 57", "Greece", 37.9838, 23.7275),
    ("Istanbul", "", "34110", "Turkey", 41.0082, 28.9784),
    ("Moscow", "", "101000", "Russia", 55.7558, 37.6173),
    ("Dubai", "", "00000", "United Arab Emirates", 25.2048, 55.2708),
    ("Doha", "", "00000", "Qatar", 25.2854, 51.5310),
    ("Tel Aviv", "", "6100000", "Israel", 32.0853, 34.7818),
    ("Cairo", "", "11511", "Egypt", 30.0444, 31.2357),
    ("Nairobi", "", "00100", "Kenya", -1.2921, 36.8219),
    ("Lagos", "", "100001", "Nigeria", 6.5244, 3.3792),
    ("Accra", "", "GA184", "Ghana", 5.6037, -0.1870),
    ("Johannesburg", "GP", "2001", "South Africa", -26.2041, 28.0473),
    ("Cape Town", "WC", "8001", "South Africa", -33.9249, 18.4241),
    ("Mumbai", "MH", "400001", "India", 19.0760, 72.8777),
    ("New Delhi", "DL", "110001", "India", 28.6139, 77.2090),
    ("Bengaluru", "KA", "560001", "India", 12.9716, 77.5946),
    ("Karachi", "", "74000", "Pakistan", 24.8607, 67.0011),
    ("Dhaka", "", "1000", "Bangladesh", 23.8103, 90.4125),
    ("Bangkok", "", "10200", "Thailand", 13.7563, 100.5018),
    ("Singapore", "", "179097", "Singapore", 1.3521, 103.8198),
    ("Kuala Lumpur", "", "50050", "Malaysia", 3.1390, 101.6869),
    ("Jakarta", "", "10110", "Indonesia", -6.2088, 106.8456),
    ("Manila", "", "1000", "Philippines", 14.5995, 120.9842),
    ("Hong Kong", "", "999077", "China", 22.3193, 114.1694),
    ("Shanghai", "", "200001", "China", 31.2304, 121.4737),
    ("Beijing", "", "100000", "China", 39.9042, 116.4074),
    ("Seoul", "", "04524", "South Korea", 37.5665, 126.9780),
    ("Tokyo", "", "100-0001", "Japan", 35.6762, 139.6503),
    ("Osaka", "", "530-0001", "Japan", 34.6937, 135.5023),
    ("Sydney", "NSW", "2000", "Australia", -33.8688, 151.2093),
    ("Melbourne", "VIC", "3000", "Australia", -37.8136, 144.9631),
    ("Auckland", "", "1010", "New Zealand", -36.8485, 174.7633),
    ("Sao Paulo", "SP", "01310-100", "Brazil", -23.5505, -46.6333),
    ("Rio de Janeiro", "RJ", "20040-020", "Brazil", -22.9068, -43.1729),
    ("Buenos Aires", "", "C1002", "Argentina", -34.6037, -58.3816),
    ("Santiago", "", "8320000", "Chile", -33.4489, -70.6693),
    ("Lima", "", "15001", "Peru", -12.0464, -77.0428),
    ("Bogota", "", "110111", "Colombia", 4.7110, -74.0721),
]

US_STREETS = [
    "Maple Street", "Oak Avenue", "Cedar Lane", "Pine Street", "Elm Street",
    "Washington Avenue", "Lincoln Boulevard", "Jefferson Drive", "Market Street",
    "Main Street", "Sunset Boulevard", "Lakeview Drive", "Hillcrest Road",
    "Riverside Drive", "Bridge Street", "Chestnut Street", "Walnut Street",
    "Birch Court", "Willow Way", "Juniper Terrace", "Madison Avenue",
    "Franklin Street", "Highland Avenue", "Park Place", "Church Street",
]

INTL_STREETS = [
    "High Street", "Station Road", "Rue de la Paix", "Kaiserstrasse", "Via Roma",
    "Calle Mayor", "Nieuwe Gracht", "Kungsgatan", "Nyhavn", "Bahnhofstrasse",
    "Queen Street", "King Street", "Marine Drive", "Orchard Road", "Ginza Avenue",
    "Nanjing Road", "Gangnam Boulevard", "Marina Way", "Harbour Road",
    "Independence Avenue", "Liberty Street", "Garden Road", "Victoria Street",
]

FIRST_NAMES = [
    "Ava", "Liam", "Noah", "Emma", "Olivia", "Mateo", "Sofia", "Aiden", "Isla",
    "Yuki", "Hiroshi", "Priya", "Arjun", "Wei", "Mei", "Fatima", "Omar", "Elena",
    "Nikolai", "Ingrid", "Lars", "Kwame", "Amara", "Thabo", "Lucia", "Diego",
    "Camila", "Rafael", "Zara", "Hassan", "Leila", "Jonas", "Marta", "Pierre",
    "Chloe", "Sean", "Fiona", "Aditi", "Rohan", "Anika", "Tomas", "Klara",
    "Sanjay", "Nadia", "Malik", "Grace", "Henry", "Isabel", "Jack", "Maya",
]

LAST_NAMES = [
    "Nguyen", "Patel", "Smith", "Johnson", "Garcia", "Rodriguez", "Chen", "Wang",
    "Kim", "Sato", "Tanaka", "Muller", "Schmidt", "Rossi", "Ferrari", "Dubois",
    "Martin", "Silva", "Santos", "Okafor", "Mensah", "Mokoena", "Ivanov",
    "Petrov", "Andersson", "Nilsson", "Hansen", "Virtanen", "Kowalski", "Novak",
    "Horvath", "Papadopoulos", "Yilmaz", "Kaya", "Al-Sayed", "Haddad", "Khan",
    "Ahmed", "Rahman", "Sharma", "Iyer", "Lim", "Tan", "Wong", "Murphy",
    "O'Brien", "Byrne", "Larsen", "Berg", "Fischer",
]

LABELS = ["Home", "Work", "Other"]


def us_entry(index):
    city, state, postal, lat, lng = US_CITIES[index % len(US_CITIES)]
    street = US_STREETS[(index * 7) % len(US_STREETS)]
    number = 100 + (index * 37) % 9800
    address = f"{number} {street}\n{city} {state} {postal}\nUnited States"
    return address, lat, lng, "United States", state or city


def intl_entry(index):
    city, admin, postal, country, lat, lng = INTL_CITIES[index % len(INTL_CITIES)]
    street = INTL_STREETS[(index * 5) % len(INTL_STREETS)]
    number = 1 + (index * 23) % 480
    locality = f"{postal} {city}" if postal else city
    if admin:
        locality = f"{postal} {city} {admin}"
    address = f"{number} {street}\n{locality}\n{country}"
    return address, lat, lng, country, admin or city


def main():
    total = 1000
    us_count = 600  # US-heavy, matching a typical US address book
    contacts = []
    seen = set()

    for i in range(total):
        if i < us_count:
            address, lat, lng, country, region = us_entry(i)
        else:
            address, lat, lng, country, region = intl_entry(i - us_count)

        # Guarantee uniqueness without disturbing the deterministic layout.
        suffix = 0
        base = address
        while address in seen:
            suffix += 1
            head, rest = base.split("\n", 1)
            address = f"{head} Unit {suffix}\n{rest}"
        seen.add(address)

        # Deterministic jitter so no two contacts share a coordinate.
        jitter_lat = round(lat + random.uniform(-0.045, 0.045), 6)
        jitter_lng = round(lng + random.uniform(-0.045, 0.045), 6)

        first = FIRST_NAMES[(i * 13) % len(FIRST_NAMES)]
        last = LAST_NAMES[(i * 29) % len(LAST_NAMES)]

        contacts.append({
            "contactID": f"fixture-{i + 1:04d}",
            "fullName": f"{first} {last}",
            "addressLabel": LABELS[i % len(LABELS)],
            "addressString": address,
            "latitude": jitter_lat,
            "longitude": jitter_lng,
            "phoneNumber": f"+1 555 {(1000 + i) % 10000:04d}" if country == "United States" else None,
            "country": country,
            "region": region,
        })

    payload = {
        "schemaVersion": 1,
        "description": (
            "Deterministic fixture of 1000 contact addresses spanning all 50 US states, "
            "Washington DC, and 65 cities across 6 continents. Coordinates are real city "
            "centres with a small deterministic offset so every entry is unique. "
            "Used to exercise the contact -> geocode -> plot pipeline at realistic scale."
        ),
        "count": len(contacts),
        "contacts": contacts,
    }

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "contacts-1000.json")
    with open(out, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, ensure_ascii=False)
        handle.write("\n")

    countries = {c["country"] for c in contacts}
    states = {c["region"] for c in contacts if c["country"] == "United States"}
    coords = {(c["latitude"], c["longitude"]) for c in contacts}
    print(f"contacts={len(contacts)} unique_addresses={len(seen)} unique_coords={len(coords)}")
    print(f"countries={len(countries)} us_regions={len(states)}")


if __name__ == "__main__":
    main()
