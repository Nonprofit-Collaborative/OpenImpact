#!/usr/bin/env python3
"""generate-sample-data.py

Generates the C-10 sample data set: 200 realistic, diverse US households
(440 contacts), plus 25 organizations, and writes it as the JSON body of
the SampleData static resource consumed by SampleDataLoader (Apex).

Python 3 standard library only. Deterministic: a fixed random seed means the
output is byte-identical across runs and across machines, so the generated
static resource can be regenerated and diffed in code review.

Usage:
    python3 scripts/data/generate-sample-data.py

Writes:
    packages/core/main/default/staticresources/SampleData.json

See data/sample/README.md for the JSON structure and regeneration notes.
"""

import json
import random
from pathlib import Path

SEED = 20260907
RNG = random.Random(SEED)

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
OUTPUT_PATH = (
    REPO_ROOT
    / "packages"
    / "core"
    / "main"
    / "default"
    / "staticresources"
    / "SampleData.json"
)

# ---------------------------------------------------------------------------
# Name and address pools. Deliberately diverse: Hispanic, East Asian, South
# Asian, African-American, Middle Eastern, and Anglo-European names, so the
# sample set exercises naming rules (hyphenation, differing surnames, single
# words) the way a real donor list does.
# ---------------------------------------------------------------------------

MALE_FIRST_NAMES = [
    "James", "Robert", "John", "Michael", "David", "William", "Carlos",
    "Luis", "Miguel", "Jose", "Antonio", "Diego", "Wei", "Jun", "Hiroshi",
    "Kenji", "Raj", "Arjun", "Amir", "Omar", "Hassan", "Malik", "DeShawn",
    "Marcus", "Andre", "Terrence", "Kwame", "Liam", "Noah", "Ethan",
    "Mason", "Lucas", "Henry", "Samuel", "Benjamin", "Daniel", "Matthew",
    "Joseph", "Thomas", "Charles", "Gabriel", "Ricardo", "Fernando",
    "Alejandro", "Mateo", "Sung", "Minh", "Tuan", "Dmitri", "Pavel",
]

FEMALE_FIRST_NAMES = [
    "Mary", "Patricia", "Linda", "Barbara", "Elizabeth", "Jennifer",
    "Maria", "Sofia", "Isabella", "Camila", "Valentina", "Lucia", "Ana",
    "Mei", "Ling", "Yuki", "Priya", "Anika", "Fatima", "Layla", "Amara",
    "Keisha", "Aaliyah", "Jasmine", "Tanya", "Nia", "Olivia", "Emma",
    "Ava", "Sophia", "Charlotte", "Amelia", "Harper", "Evelyn", "Grace",
    "Chloe", "Victoria", "Rosa", "Carmen", "Elena", "Jun", "Hana",
    "Soo", "Anh", "Thu", "Katarina", "Ingrid", "Margaret", "Susan", "Jen",
]

SURNAMES = [
    "Garcia", "Martinez", "Rodriguez", "Hernandez", "Lopez", "Gonzalez",
    "Perez", "Sanchez", "Ramirez", "Torres", "Flores", "Alvarez", "Diaz",
    "Smith", "Johnson", "Williams", "Brown", "Jones", "Miller", "Davis",
    "Wilson", "Anderson", "Thomas", "Taylor", "Moore", "Jackson", "Martin",
    "Lee", "Walker", "Hall", "Allen", "Young", "King", "Wright", "Scott",
    "Chen", "Wang", "Zhang", "Liu", "Kim", "Park", "Nguyen", "Tran", "Pham",
    "Patel", "Shah", "Kumar", "Singh", "Khan", "Ahmed", "Hassan", "Ali",
    "Washington", "Jefferson", "Freeman", "Coleman", "Bell", "Foster",
    "Okafor", "Adeyemi", "Mensah", "Osei", "Silva", "Costa", "Rossi",
    "Novak", "Kowalski", "Petrov", "Ivanov", "Sullivan", "O'Brien",
    "O'Connor", "Murphy", "Reyes", "Morales", "Castillo", "Ortiz",
]

# Second halves for hyphenated surnames (a person's own surname combined
# with a partner's), kept separate so we can build realistic pairs.
HYPHEN_PARTNERS = [
    "Bennett", "Clarke", "Ferreira", "Nakamura", "Okonkwo", "Reyes",
    "Whitfield", "Ellison", "Duarte", "Sato",
]

SALUTATIONS_MALE = ["Mr."]
SALUTATIONS_FEMALE = ["Mrs.", "Ms."]
SALUTATION_NEUTRAL_TITLES = ["Dr."]

NICKNAMES = {
    "William": "Bill",
    "Robert": "Bob",
    "Richard": "Rick",
    "Elizabeth": "Liz",
    "Margaret": "Peggy",
    "Charles": "Chuck",
    "Katherine": "Kate",
    "Jennifer": "Jen",
    "Michael": "Mike",
    "Patricia": "Pat",
    "Anthony": "Tony",
    "Deborah": "Debbie",
    "James": "Jim",
    "Susan": "Sue",
    "Thomas": "Tom",
}

# A handful of states, each with a couple of cities and a zip prefix range,
# so mailing addresses are spread across several states rather than one.
STATE_CITIES = {
    "CA": [("San Diego", "921"), ("Fresno", "937"), ("Sacramento", "958")],
    "TX": [("Austin", "787"), ("El Paso", "799"), ("San Antonio", "782")],
    "NY": [("Rochester", "146"), ("Syracuse", "132"), ("Albany", "122")],
    "IL": [("Springfield", "627"), ("Peoria", "616"), ("Rockford", "611")],
    "OH": [("Columbus", "432"), ("Dayton", "454"), ("Toledo", "436")],
    "GA": [("Savannah", "314"), ("Macon", "312"), ("Athens", "306")],
    "WA": [("Spokane", "992"), ("Tacoma", "984"), ("Olympia", "985")],
    "CO": [("Boulder", "803"), ("Pueblo", "810"), ("Aurora", "800")],
    "FL": [("Tampa", "336"), ("Orlando", "328"), ("Tallahassee", "323")],
    "PA": [("Erie", "165"), ("Allentown", "181"), ("Scranton", "185")],
    "NC": [("Asheville", "288"), ("Durham", "277"), ("Wilmington", "284")],
    "MN": [("Duluth", "558"), ("Rochester", "559"), ("St. Cloud", "563")],
}
STATES = list(STATE_CITIES.keys())

STREET_NAMES = [
    "Maple", "Oak", "Cedar", "Elm", "Willow", "Birch", "Sunset", "Ridge",
    "Meadow", "River", "Lake", "Highland", "Prairie", "Orchard", "Chestnut",
    "Magnolia", "Aspen", "Juniper", "Harbor", "Foxglove", "Hillcrest",
    "Fairview", "Grand", "Pine", "Spruce",
]
STREET_SUFFIXES = ["St", "Ave", "Dr", "Ln", "Rd", "Ct", "Way", "Blvd"]

HOUSEHOLD_ROLES = ["Head", "Spouse or Partner", "Child", "Other"]

ADULT_MIN_AGE = 24
ADULT_MAX_AGE = 88
# Half the widest plausible gap between partners, so a couple is at most 24 years apart.
SPOUSE_AGE_SPREAD = 12

# "Garcia" is reserved for the single guaranteed household the admin guide's
# walkthrough looks for ("The Garcia Family"), so every other random draw
# uses this pool instead, keeping that name unique in the sample set.
SURNAME_POOL = [s for s in SURNAMES if s != "Garcia"]

ORG_NAME_TEMPLATES = [
    ("foundation", "{word} Family Foundation"),
    ("foundation", "The {word} Foundation"),
    ("foundation", "{word} Community Foundation"),
    ("business", "{word} & {word2} LLC"),
    ("business", "{word} Hardware"),
    ("business", "{word} Consulting Group"),
    ("business", "{word} Coffee Roasters"),
    ("church", "{word} Community Church"),
    ("church", "St. {word} Parish"),
    ("church", "{word} Congregation"),
    ("school", "{word} County School District"),
]
ORG_WORDS = [
    "Cedar Valley", "Riverside", "Hilltop", "Northgate", "Bright Horizons",
    "Willowbrook", "Union", "Heritage", "Lakeside", "Franklin", "Grace",
    "Trinity", "Mercy", "Unity", "Founders", "Evergreen", "Summit",
    "Meridian", "Cornerstone", "Fellowship", "Harborview", "Ashford",
]


def pick_first_name(rng, gender):
    return rng.choice(MALE_FIRST_NAMES if gender == "M" else FEMALE_FIRST_NAMES)


# Children below this age get no salutation and no email address of their own:
# a nonprofit does not address a nine year old as "Mr." or mail them directly.
MINOR_COURTESY_AGE = 13

REFERENCE_YEAR = 2026


def salutation_for(rng, gender, formal_title=None):
    if formal_title:
        return formal_title
    if gender == "M":
        return "Mr."
    return random_choice_weighted(rng, [("Mrs.", 0.6), ("Ms.", 0.4)])


def random_choice_weighted(rng, options):
    total = sum(weight for _, weight in options)
    threshold = rng.uniform(0, total)
    running = 0.0
    for value, weight in options:
        running += weight
        if threshold <= running:
            return value
    return options[-1][0]


def make_phone(rng):
    return "({:03d}) {:03d}-{:04d}".format(
        rng.choice([202, 312, 404, 415, 512, 617, 702, 720, 803, 919]),
        rng.randint(200, 999),
        rng.randint(0, 9999),
    )


def make_email(first, last, index):
    slug = "{0}.{1}{2}".format(first.lower(), last.lower().replace("'", "").replace(" ", ""), index)
    return "{0}@example.org".format(slug)


def make_address(rng):
    state = rng.choice(STATES)
    city, zip_prefix = rng.choice(STATE_CITIES[state])
    street_number = rng.randint(100, 9999)
    street = "{0} {1} {2}".format(
        street_number, rng.choice(STREET_NAMES), rng.choice(STREET_SUFFIXES)
    )
    postal_code = "{0}{1:02d}".format(zip_prefix, rng.randint(0, 99))
    return {
        "street": street,
        "city": city,
        "state": state,
        "postalCode": postal_code,
    }


def make_birthdate(rng, min_age, max_age, reference_year=REFERENCE_YEAR):
    age = rng.randint(min_age, max_age)
    year = reference_year - age
    month = rng.randint(1, 12)
    day = rng.randint(1, 28)
    return "{0:04d}-{1:02d}-{2:02d}".format(year, month, day)


def maybe_preferred_name(rng, first_name):
    nickname = NICKNAMES.get(first_name)
    if nickname and rng.random() < 0.5:
        return nickname
    return None


def make_member(
    rng,
    first_name,
    last_name,
    gender,
    role,
    address,
    index,
    is_child=False,
    formal_title=None,
    deceased=False,
    min_age=None,
    max_age=None,
):
    if is_child:
        birthdate = make_birthdate(rng, 2, 17)
    else:
        birthdate = make_birthdate(
            rng,
            ADULT_MIN_AGE if min_age is None else min_age,
            ADULT_MAX_AGE if max_age is None else max_age,
        )
    age = age_from_birthdate(birthdate)

    member = {
        "firstName": first_name,
        "lastName": last_name,
    }
    if age >= MINOR_COURTESY_AGE:
        member["salutation"] = salutation_for(rng, gender, formal_title)
    member["householdRole"] = role
    if age >= MINOR_COURTESY_AGE:
        member["email"] = make_email(first_name, last_name, index)
    member["phone"] = make_phone(rng)
    member["mailingStreet"] = address["street"]
    member["mailingCity"] = address["city"]
    member["mailingState"] = address["state"]
    member["mailingPostalCode"] = address["postalCode"]
    member["birthdate"] = birthdate

    preferred = maybe_preferred_name(rng, first_name)
    if preferred:
        member["preferredName"] = preferred
    if deceased:
        member["deceased"] = True
    return member


def age_from_birthdate(birthdate):
    return REFERENCE_YEAR - int(birthdate[:4])


def spouse_age_range(head_member):
    """Keep partners within a plausible span: at most 24 years apart."""
    head_age = age_from_birthdate(head_member["birthdate"])
    return (
        max(ADULT_MIN_AGE, head_age - SPOUSE_AGE_SPREAD),
        min(ADULT_MAX_AGE, head_age + SPOUSE_AGE_SPREAD),
    )


def make_anniversary(rng, members):
    """A date after every adult in the household turned twenty, never before one was born."""
    adult_years = [
        int(member["birthdate"][:4])
        for member in members
        if member["householdRole"] != "Child"
    ]
    if not adult_years:
        return None
    earliest_year = max(adult_years) + 20
    if earliest_year > REFERENCE_YEAR:
        return None
    year = rng.randint(earliest_year, REFERENCE_YEAR)
    return "{0:04d}-{1:02d}-{2:02d}".format(year, rng.randint(1, 12), rng.randint(1, 28))


def build_family(
    rng, key, surname, address, member_index, deceased=False, extra_child=False, child_count=None
):
    """Head + Spouse or Partner + zero or more Children, shared surname."""
    head_gender = rng.choice(["M", "F"])
    spouse_gender = "F" if head_gender == "M" else "M"
    head_first = pick_first_name(rng, head_gender)
    spouse_first = pick_first_name(rng, spouse_gender)

    members = []
    head = make_member(rng, head_first, surname, head_gender, "Head", address, member_index[0])
    members.append(head)
    member_index[0] += 1
    spouse_min, spouse_max = spouse_age_range(head)
    members.append(
        make_member(
            rng,
            spouse_first,
            surname,
            spouse_gender,
            "Spouse or Partner",
            address,
            member_index[0],
            deceased=deceased,
            min_age=spouse_min,
            max_age=spouse_max,
        )
    )
    member_index[0] += 1

    if child_count is None:
        child_count = 2 if extra_child else rng.randint(1, 2)
    for _ in range(child_count):
        child_gender = rng.choice(["M", "F"])
        child_first = pick_first_name(rng, child_gender)
        members.append(
            make_member(
                rng, child_first, surname, child_gender, "Child", address, member_index[0], is_child=True
            )
        )
        member_index[0] += 1

    anniversary = make_anniversary(rng, members) if rng.random() < 0.7 else None
    return {
        "key": key,
        "name": None,
        "customName": False,
        "anniversary": anniversary,
        "address": address,
        "members": members,
    }


def build_single(rng, key, surname, address, member_index):
    gender = rng.choice(["M", "F"])
    first = pick_first_name(rng, gender)
    members = [make_member(rng, first, surname, gender, "Head", address, member_index[0])]
    member_index[0] += 1
    return {
        "key": key,
        "name": None,
        "customName": False,
        "anniversary": None,
        "address": address,
        "members": members,
    }


def build_differing_surnames(rng, key, address, member_index):
    """A household where the two adults kept different surnames."""
    surname_a = rng.choice(SURNAME_POOL)
    surname_b = rng.choice([s for s in SURNAME_POOL if s != surname_a])
    gender_a = rng.choice(["M", "F"])
    gender_b = "F" if gender_a == "M" else "M"
    first_a = pick_first_name(rng, gender_a)
    first_b = pick_first_name(rng, gender_b)
    head = make_member(rng, first_a, surname_a, gender_a, "Head", address, member_index[0])
    members = [head]
    member_index[0] += 1
    spouse_min, spouse_max = spouse_age_range(head)
    members.append(
        make_member(
            rng,
            first_b,
            surname_b,
            gender_b,
            "Spouse or Partner",
            address,
            member_index[0],
            min_age=spouse_min,
            max_age=spouse_max,
        )
    )
    member_index[0] += 1
    if rng.random() < 0.5:
        child_gender = rng.choice(["M", "F"])
        child_first = pick_first_name(rng, child_gender)
        child_surname = rng.choice([surname_a, surname_b])
        members.append(
            make_member(
                rng,
                child_first,
                child_surname,
                child_gender,
                "Child",
                address,
                member_index[0],
                is_child=True,
            )
        )
        member_index[0] += 1
    return {
        "key": key,
        "name": None,
        "customName": False,
        "anniversary": make_anniversary(rng, members) if rng.random() < 0.5 else None,
        "address": address,
        "members": members,
    }


def build_hyphenated(rng, key, address, member_index):
    base = rng.choice(SURNAME_POOL)
    partner = rng.choice(HYPHEN_PARTNERS)
    hyphenated = "{0}-{1}".format(base, partner)
    head_gender = rng.choice(["M", "F"])
    spouse_gender = "F" if head_gender == "M" else "M"
    head_first = pick_first_name(rng, head_gender)
    spouse_first = pick_first_name(rng, spouse_gender)
    head = make_member(rng, head_first, hyphenated, head_gender, "Head", address, member_index[0])
    members = [head]
    member_index[0] += 1
    spouse_min, spouse_max = spouse_age_range(head)
    members.append(
        make_member(
            rng,
            spouse_first,
            hyphenated,
            spouse_gender,
            "Spouse or Partner",
            address,
            member_index[0],
            min_age=spouse_min,
            max_age=spouse_max,
        )
    )
    member_index[0] += 1
    if rng.random() < 0.6:
        child_gender = rng.choice(["M", "F"])
        child_first = pick_first_name(rng, child_gender)
        members.append(
            make_member(
                rng,
                child_first,
                hyphenated,
                child_gender,
                "Child",
                address,
                member_index[0],
                is_child=True,
            )
        )
        member_index[0] += 1
    return {
        "key": key,
        "name": None,
        "customName": False,
        "anniversary": make_anniversary(rng, members) if rng.random() < 0.7 else None,
        "address": address,
        "members": members,
    }


def build_three_generation(rng, key, surname, address, member_index):
    """Grandparent(s), a parent couple, and children, all sharing a surname."""
    members = []

    grandparent_gender = rng.choice(["M", "F"])
    grandparent_first = pick_first_name(rng, grandparent_gender)
    members.append(
        make_member(
            rng, grandparent_first, surname, grandparent_gender, "Other", address, member_index[0]
        )
    )
    member_index[0] += 1
    if rng.random() < 0.6:
        other_gp_gender = "F" if grandparent_gender == "M" else "M"
        other_gp_first = pick_first_name(rng, other_gp_gender)
        members.append(
            make_member(
                rng, other_gp_first, surname, other_gp_gender, "Other", address, member_index[0]
            )
        )
        member_index[0] += 1

    parent_gender = rng.choice(["M", "F"])
    spouse_gender = "F" if parent_gender == "M" else "M"
    parent_first = pick_first_name(rng, parent_gender)
    spouse_first = pick_first_name(rng, spouse_gender)
    head = make_member(rng, parent_first, surname, parent_gender, "Head", address, member_index[0])
    members.append(head)
    member_index[0] += 1
    spouse_min, spouse_max = spouse_age_range(head)
    members.append(
        make_member(
            rng,
            spouse_first,
            surname,
            spouse_gender,
            "Spouse or Partner",
            address,
            member_index[0],
            min_age=spouse_min,
            max_age=spouse_max,
        )
    )
    member_index[0] += 1

    for _ in range(rng.randint(1, 2)):
        child_gender = rng.choice(["M", "F"])
        child_first = pick_first_name(rng, child_gender)
        members.append(
            make_member(
                rng, child_first, surname, child_gender, "Child", address, member_index[0], is_child=True
            )
        )
        member_index[0] += 1

    return {
        "key": key,
        "name": None,
        "customName": False,
        "anniversary": make_anniversary(rng, members) if rng.random() < 0.6 else None,
        "address": address,
        "members": members,
    }


def build_custom_name_household(rng, key, custom_name, surname, address, member_index, formal_title):
    head_gender = rng.choice(["M", "F"])
    spouse_gender = "F" if head_gender == "M" else "M"
    head_first = pick_first_name(rng, head_gender)
    spouse_first = pick_first_name(rng, spouse_gender)
    head = make_member(
        rng,
        head_first,
        surname,
        head_gender,
        "Head",
        address,
        member_index[0],
        formal_title=formal_title,
    )
    members = [head]
    member_index[0] += 1
    spouse_min, spouse_max = spouse_age_range(head)
    members.append(
        make_member(
            rng,
            spouse_first,
            surname,
            spouse_gender,
            "Spouse or Partner",
            address,
            member_index[0],
            min_age=spouse_min,
            max_age=spouse_max,
        )
    )
    member_index[0] += 1
    return {
        "key": key,
        "name": custom_name,
        "customName": True,
        "anniversary": make_anniversary(rng, members),
        "address": address,
        "members": members,
    }


def build_staff_household(rng, key, address, member_index):
    staff = [
        ("Maria", "F", "Head"),
        ("David", "M", "Other"),
        ("Priya", "F", "Other"),
        ("Tom", "M", "Other"),
        ("Jen", "F", "Other"),
        ("Sam", "M", "Other"),
    ]
    surname = "Whitfield"
    members = []
    for first_name, gender, role in staff:
        members.append(
            make_member(rng, first_name, surname, gender, role, address, member_index[0])
        )
        member_index[0] += 1
    return {
        "key": key,
        "name": "Staff Household",
        "customName": True,
        "anniversary": None,
        "address": address,
        "members": members,
    }


def build_organization(rng, index):
    kind, template = rng.choice(ORG_NAME_TEMPLATES)
    word = rng.choice(ORG_WORDS)
    word2 = rng.choice([w for w in ORG_WORDS if w != word])
    name = template.format(word=word, word2=word2)
    domain_slug = "".join(ch.lower() for ch in name if ch.isalnum())[:20] or "org{0}".format(index)
    return {
        "key": "O{0:03d}".format(index),
        "name": name,
        "type": kind,
        "website": "https://www.{0}.example.org".format(domain_slug),
        "phone": make_phone(rng),
    }


def build_households(rng):
    households = []
    member_index = [1]
    household_number = 1

    def next_key():
        nonlocal household_number
        key = "H{0:03d}".format(household_number)
        household_number += 1
        return key

    # Guarantee "The Garcia Family" exists and computes naturally (not a
    # custom name), for the admin guide's five minute walkthrough.
    address = make_address(rng)
    households.append(build_family(rng, next_key(), "Garcia", address, member_index))

    # Staff household, so the walkthrough always finds Maria, David, Priya,
    # Tom, Jen, and Sam.
    address = make_address(rng)
    households.append(build_staff_household(rng, next_key(), address, member_index))

    # Three custom-name households (Custom_Name__c = true).
    custom_specs = [
        ("The Reverend and Mrs. Alvarez", "Alvarez", "Rev."),
        ("The Doctors Nguyen", "Nguyen", "Dr."),
        ("The Wilson Family Trust Household", "Wilson", None),
    ]
    for custom_name, surname, title in custom_specs:
        address = make_address(rng)
        households.append(
            build_custom_name_household(
                rng, next_key(), custom_name, surname, address, member_index, title
            )
        )

    # Five households with a deceased member.
    for _ in range(5):
        surname = rng.choice(SURNAME_POOL)
        address = make_address(rng)
        households.append(
            build_family(rng, next_key(), surname, address, member_index, deceased=True)
        )

    # Ten three-generation households.
    for _ in range(10):
        surname = rng.choice(SURNAME_POOL)
        address = make_address(rng)
        households.append(build_three_generation(rng, next_key(), surname, address, member_index))

    # Eight hyphenated-surname households.
    for _ in range(8):
        address = make_address(rng)
        households.append(build_hyphenated(rng, next_key(), address, member_index))

    # Twenty households with differing surnames.
    for _ in range(20):
        address = make_address(rng)
        households.append(build_differing_surnames(rng, next_key(), address, member_index))

    # Forty single-person households.
    for _ in range(40):
        surname = rng.choice(SURNAME_POOL)
        address = make_address(rng)
        households.append(build_single(rng, next_key(), surname, address, member_index))

    # Fill the remainder with ordinary same-surname couples, mostly childless
    # (couples who give as a household but have grown children or none),
    # some with one child, a few with two, until we reach 200 households.
    while len(households) < 200:
        surname = rng.choice(SURNAME_POOL)
        address = make_address(rng)
        child_count = random_choice_weighted(
            rng, [(0, 0.82), (1, 0.13), (2, 0.05)]
        )
        households.append(
            build_family(rng, next_key(), surname, address, member_index, child_count=child_count)
        )

    return households


def build_organizations(rng):
    return [build_organization(rng, i) for i in range(1, 26)]


def main():
    households = build_households(RNG)
    organizations = build_organizations(RNG)

    total_members = sum(len(h["members"]) for h in households)

    data = {"households": households, "organizations": organizations}

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_PATH.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=None, separators=(",", ":"), sort_keys=False)
        handle.write("\n")

    size_bytes = OUTPUT_PATH.stat().st_size
    print("Wrote {0}".format(OUTPUT_PATH))
    print("Households: {0}".format(len(households)))
    print("Contacts: {0}".format(total_members))
    print("Organizations: {0}".format(len(organizations)))
    print("File size: {0} bytes ({1:.1f} KB)".format(size_bytes, size_bytes / 1024.0))


if __name__ == "__main__":
    main()
