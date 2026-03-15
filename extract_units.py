#!/usr/bin/env python3
import xml.etree.ElementTree as ET

NS = {'bs': 'http://www.battlescribe.net/schema/catalogueSchema'}

def parse_file(path):
    tree = ET.parse(path)
    return tree.getroot()

def find_all_entries(root, tag='selectionEntry'):
    """Recursively find all selectionEntry or selectionEntryGroup elements."""
    results = []
    # Search broadly with namespace
    for elem in root.iter('{http://www.battlescribe.net/schema/catalogueSchema}' + tag):
        results.append(elem)
    return results

def get_profiles(entry):
    profiles = []
    for profile in entry.findall('.//{http://www.battlescribe.net/schema/catalogueSchema}profile'):
        p_info = {
            'name': profile.get('name', ''),
            'typeName': profile.get('typeName', ''),
            'characteristics': {}
        }
        for char in profile.findall('.//{http://www.battlescribe.net/schema/catalogueSchema}characteristic'):
            p_info['characteristics'][char.get('name', '')] = char.text or ''
        profiles.append(p_info)
    return profiles

def get_rules(entry):
    rules = []
    for rule in entry.findall('.//{http://www.battlescribe.net/schema/catalogueSchema}rule'):
        desc_elem = rule.find('{http://www.battlescribe.net/schema/catalogueSchema}description')
        desc = desc_elem.text if desc_elem is not None else ''
        rules.append({
            'name': rule.get('name', ''),
            'description': (desc or '')[:120]
        })
    return rules

def get_infolinks(entry):
    links = []
    for link in entry.findall('.//{http://www.battlescribe.net/schema/catalogueSchema}infoLink'):
        links.append({
            'name': link.get('name', ''),
            'type': link.get('type', '')
        })
    return links

def get_categorylinks(entry):
    cats = []
    for cat in entry.findall('.//{http://www.battlescribe.net/schema/catalogueSchema}categoryLink'):
        cats.append(cat.get('name', ''))
    return cats

def get_costs(entry):
    costs = []
    for cost in entry.findall('.//{http://www.battlescribe.net/schema/catalogueSchema}cost'):
        costs.append({
            'name': cost.get('name', ''),
            'value': cost.get('value', '')
        })
    return costs

def print_entry(entry, indent=0):
    pad = ' ' * indent
    name = entry.get('name', 'UNKNOWN')
    etype = entry.get('type', '')
    eid = entry.get('id', '')
    print(f"{pad}=== ENTRY: {name} (type={etype}, id={eid}) ===")

    # Only get DIRECT profiles (not nested in child selectionEntries)
    # We need to be careful here - get profiles only at the direct level
    direct_profiles = get_direct_profiles(entry)
    if direct_profiles:
        print(f"{pad}  PROFILES:")
        for p in direct_profiles:
            print(f"{pad}    [{p['typeName']}] {p['name']}")
            for k, v in p['characteristics'].items():
                print(f"{pad}      {k}: {v}")

    direct_rules = get_direct_rules(entry)
    if direct_rules:
        print(f"{pad}  INLINE RULES:")
        for r in direct_rules:
            print(f"{pad}    {r['name']}: {r['description']}")

    infolinks = get_direct_infolinks(entry)
    if infolinks:
        print(f"{pad}  INFO LINKS:")
        for l in infolinks:
            print(f"{pad}    {l['name']} ({l['type']})")

    catlinks = get_direct_categorylinks(entry)
    if catlinks:
        print(f"{pad}  CATEGORY LINKS:")
        for c in catlinks:
            print(f"{pad}    {c}")

    costs = get_direct_costs(entry)
    if costs:
        print(f"{pad}  COSTS:")
        for c in costs:
            print(f"{pad}    {c['name']}: {c['value']}")

    print()

def get_direct_profiles(entry):
    """Get profiles directly in this entry (not in nested selectionEntries)."""
    profiles = []
    # Look in profiles container at this level
    SE_TAG = '{http://www.battlescribe.net/schema/catalogueSchema}selectionEntry'
    SEG_TAG = '{http://www.battlescribe.net/schema/catalogueSchema}selectionEntryGroup'
    PROFILES_TAG = '{http://www.battlescribe.net/schema/catalogueSchema}profiles'
    PROFILE_TAG = '{http://www.battlescribe.net/schema/catalogueSchema}profile'

    def search_profiles(elem, depth=0):
        if depth > 0 and elem.tag in (SE_TAG, SEG_TAG):
            return  # Don't recurse into child selection entries
        if elem.tag == PROFILE_TAG:
            p_info = {
                'name': elem.get('name', ''),
                'typeName': elem.get('typeName', ''),
                'characteristics': {}
            }
            for char in elem.findall('.//{http://www.battlescribe.net/schema/catalogueSchema}characteristic'):
                p_info['characteristics'][char.get('name', '')] = char.text or ''
            profiles.append(p_info)
        for child in elem:
            search_profiles(child, depth + (1 if elem.tag in (SE_TAG, SEG_TAG) else 0))

    search_profiles(entry)
    return profiles

def get_direct_rules(entry):
    rules = []
    SE_TAG = '{http://www.battlescribe.net/schema/catalogueSchema}selectionEntry'
    SEG_TAG = '{http://www.battlescribe.net/schema/catalogueSchema}selectionEntryGroup'
    RULE_TAG = '{http://www.battlescribe.net/schema/catalogueSchema}rule'

    def search_rules(elem, depth=0):
        if depth > 0 and elem.tag in (SE_TAG, SEG_TAG):
            return
        if elem.tag == RULE_TAG:
            desc_elem = elem.find('{http://www.battlescribe.net/schema/catalogueSchema}description')
            desc = desc_elem.text if desc_elem is not None else ''
            rules.append({
                'name': elem.get('name', ''),
                'description': (desc or '')[:120]
            })
        for child in elem:
            search_rules(child, depth + (1 if elem.tag in (SE_TAG, SEG_TAG) else 0))

    search_rules(entry)
    return rules

def get_direct_infolinks(entry):
    links = []
    SE_TAG = '{http://www.battlescribe.net/schema/catalogueSchema}selectionEntry'
    SEG_TAG = '{http://www.battlescribe.net/schema/catalogueSchema}selectionEntryGroup'
    LINK_TAG = '{http://www.battlescribe.net/schema/catalogueSchema}infoLink'

    def search(elem, depth=0):
        if depth > 0 and elem.tag in (SE_TAG, SEG_TAG):
            return
        if elem.tag == LINK_TAG:
            links.append({
                'name': elem.get('name', ''),
                'type': elem.get('type', '')
            })
        for child in elem:
            search(child, depth + (1 if elem.tag in (SE_TAG, SEG_TAG) else 0))

    search(entry)
    return links

def get_direct_categorylinks(entry):
    cats = []
    SE_TAG = '{http://www.battlescribe.net/schema/catalogueSchema}selectionEntry'
    SEG_TAG = '{http://www.battlescribe.net/schema/catalogueSchema}selectionEntryGroup'
    CAT_TAG = '{http://www.battlescribe.net/schema/catalogueSchema}categoryLink'

    def search(elem, depth=0):
        if depth > 0 and elem.tag in (SE_TAG, SEG_TAG):
            return
        if elem.tag == CAT_TAG:
            cats.append(elem.get('name', ''))
        for child in elem:
            search(child, depth + (1 if elem.tag in (SE_TAG, SEG_TAG) else 0))

    search(entry)
    return cats

def get_direct_costs(entry):
    costs = []
    SE_TAG = '{http://www.battlescribe.net/schema/catalogueSchema}selectionEntry'
    COST_TAG = '{http://www.battlescribe.net/schema/catalogueSchema}cost'

    def search(elem, depth=0):
        if depth > 0 and elem.tag == SE_TAG:
            return
        if elem.tag == COST_TAG:
            costs.append({
                'name': elem.get('name', ''),
                'value': elem.get('value', '')
            })
        for child in elem:
            search(child, depth + (1 if elem.tag == SE_TAG else 0))

    search(entry)
    return costs

def find_entry_by_name(root, name, entry_type=None):
    SE_TAG = '{http://www.battlescribe.net/schema/catalogueSchema}selectionEntry'
    SEG_TAG = '{http://www.battlescribe.net/schema/catalogueSchema}selectionEntryGroup'

    for tag in [SE_TAG, SEG_TAG]:
        for elem in root.iter(tag):
            ename = elem.get('name', '')
            etype = elem.get('type', '')
            if ename == name:
                if entry_type is None or etype == entry_type:
                    return elem
    return None

def find_all_entries_by_name(root, name):
    SE_TAG = '{http://www.battlescribe.net/schema/catalogueSchema}selectionEntry'
    SEG_TAG = '{http://www.battlescribe.net/schema/catalogueSchema}selectionEntryGroup'

    results = []
    for tag in [SE_TAG, SEG_TAG]:
        for elem in root.iter(tag):
            ename = elem.get('name', '')
            if ename == name:
                results.append(elem)
    return results

# Load catalogs
tyranids_cat = parse_file('/home/user/combat-goblin_prime/test/Xenos - Tyranids.cat')
library_cat = parse_file('/home/user/combat-goblin_prime/test/Library - Tyranids.cat')
sm_cat = parse_file('/home/user/combat-goblin_prime/test/Imperium - Space Marines.cat')

print("=" * 80)
print("TYRANIDS DATA EXTRACTION")
print("=" * 80)

# 1. Genestealers (unit entry)
print("\n### 1. GENESTEALERS (unit entry) - searching Xenos - Tyranids.cat ###\n")
results = find_all_entries_by_name(tyranids_cat, 'Genestealers')
for r in results:
    print_entry(r)

results_lib = find_all_entries_by_name(library_cat, 'Genestealers')
for r in results_lib:
    print(f"  [Also found in Library - Tyranids.cat]")
    print_entry(r)

# 1b. Genestealer (model entry)
print("\n### 1b. GENESTEALER (model entry) ###\n")
results = find_all_entries_by_name(tyranids_cat, 'Genestealer')
for r in results:
    print_entry(r)
results_lib = find_all_entries_by_name(library_cat, 'Genestealer')
for r in results_lib:
    print(f"  [Also found in Library - Tyranids.cat]")
    print_entry(r)

# 2. Neurothrope (model entry)
print("\n### 2. NEUROTHROPE (model entry) ###\n")
results = find_all_entries_by_name(tyranids_cat, 'Neurothrope')
for r in results:
    print_entry(r)
results_lib = find_all_entries_by_name(library_cat, 'Neurothrope')
for r in results_lib:
    print(f"  [Also found in Library - Tyranids.cat]")
    print_entry(r)

# 3. Carnifex (model entry)
print("\n### 3. CARNIFEX (model entry) ###\n")
results = find_all_entries_by_name(tyranids_cat, 'Carnifex')
for r in results:
    print_entry(r)
results_lib = find_all_entries_by_name(library_cat, 'Carnifex')
for r in results_lib:
    print(f"  [Also found in Library - Tyranids.cat]")
    print_entry(r)

print("=" * 80)
print("SPACE MARINES DATA EXTRACTION")
print("=" * 80)

# 4. Captain (model entry)
print("\n### 4. CAPTAIN (model entry) ###\n")
results = find_all_entries_by_name(sm_cat, 'Captain')
for r in results:
    print_entry(r)

# 5. Eradicator (model entry)
print("\n### 5. ERADICATOR (model entry) ###\n")
results = find_all_entries_by_name(sm_cat, 'Eradicator')
for r in results:
    print_entry(r)

# 5b. Eradicator Squad
print("\n### 5b. ERADICATOR SQUAD (unit entry) ###\n")
results = find_all_entries_by_name(sm_cat, 'Eradicator Squad')
for r in results:
    print_entry(r)

# 6. Bladeguard Veterans (model entry)
print("\n### 6. BLADEGUARD VETERANS (model entry) ###\n")
results = find_all_entries_by_name(sm_cat, 'Bladeguard Veterans')
for r in results:
    print_entry(r)

# 6b. Bladeguard Veteran Squad
print("\n### 6b. BLADEGUARD VETERAN SQUAD (unit entry) ###\n")
results = find_all_entries_by_name(sm_cat, 'Bladeguard Veteran Squad')
for r in results:
    print_entry(r)

# Also check for just "Bladeguard Veteran" model
print("\n### 6c. BLADEGUARD VETERAN (model entry) ###\n")
results = find_all_entries_by_name(sm_cat, 'Bladeguard Veteran')
for r in results:
    print_entry(r)
