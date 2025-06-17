import os
import re
import xml.etree.ElementTree as ET
from typing import Set, Dict, Tuple

# --- Configuration Constants ---
# Default path for Barotrauma's vanilla content.
BAROTRAUMA_CONTENT_PATH = r'C:\Program Files (x86)\Steam\steamapps\common\Barotrauma\Content'
OUTPUT_FILENAME = 'itemlist.md' # Changed to .md for Markdown
CHINESE_LANG_CODE = "Simplified Chinese" # From infotexts language attribute
ENGLISH_LANG_CODE = "English" # From infotexts language attribute

# Regex for extracting entity names (identifiers) from localization files
ENTITY_NAME_PATTERN = re.compile(r'<entityname\.([^>]+)>')

# --- Helper Functions for XML Processing (unchanged mostly) ---

def find_xml_files(directory: str) -> list[str]:
    """
    Finds all .xml files in the given directory and its subdirectories,
    excluding 'Reference.xml'.
    """
    xml_files = []
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.xml') and file != 'Reference.xml':
                xml_files.append(os.path.join(root, file))
    return xml_files

def _get_removal_patterns():
    """Defines and compiles regex patterns for unwanted XML sections."""
    patterns = [
        r'',  # XML comments
        r'<Fabricate[^>]*?/>', r'<Fabricate.*?</Fabricate>',
        r'<Deconstruct[^>]*?/>', r'<Deconstruct.*?</Deconstruct>',
        r'<Inventory[^>]*?/>', r'<Inventory.*?</Inventory>',
        r'<ItemSet[^>]*?/>', r'<ItemSet.*?</ItemSet>',
        r'<npcsets[^>]*?/>', r'<npcsets.*?</npcsets>',
        r'<Jobs[^>]*?/>', r'<Jobs.*?</Jobs>',
        r'<Missions[^>]*?/>', r'<Missions.*?</Missions>',
    ]
    return [(re.compile(p, re.DOTALL)) for p in patterns]

def remove_unwanted_sections(xml_content: str) -> str:
    """
    Removes specified XML comments and tags (Fabricate, Deconstruct, etc.)
    from the given XML content using pre-compiled regex patterns.
    """
    patterns = _get_removal_patterns()
    for pattern in patterns:
        xml_content = pattern.sub('', xml_content)
    return xml_content

def extract_identifiers_from_xml(xml_content: str) -> Set[str]:
    """
    Extracts 'identifier' attributes from <Item> tags within the XML content.
    """
    identifiers = re.findall(r'<Item[^>]*?identifier="([^"]+)', xml_content)
    return set(identifiers)

def _get_xml_files_from_filelist(mod_filelist_path: str, mod_root_dir: str) -> list[str]:
    """
    Parses filelist.xml to get paths of relevant XML files,
    replacing %ModDir% with the actual mod root directory.
    Only includes file paths that are likely to contain item definitions.
    """
    xml_paths = []
    try:
        tree = ET.parse(mod_filelist_path)
        root = tree.getroot()

        # Define tags whose 'file' attributes we are interested in for item processing.
        relevant_tags = {"Item", "Jobs", "NPCSets", "Character", "Afflictions", "Sounds", "Text", "Particles", "UIStyle", "RandomEvents", "Missions", "Factions", "Corpses", "EnemySubmarine"}

        for element in root:
            if element.tag in relevant_tags:
                file_path_raw = element.get('file')
                if file_path_raw:
                    # Replace %ModDir% with the actual mod root directory
                    absolute_path = file_path_raw.replace("%ModDir%", mod_root_dir)
                    xml_paths.append(absolute_path)
    except FileNotFoundError:
        print(f"Warning: filelist.xml not found at {mod_filelist_path}. This will prevent reading mod content via filelist.")
    except ET.ParseError as e:
        print(f"Warning: Error parsing filelist.xml at {mod_filelist_path}: {e}. This will prevent reading mod content via filelist.")
    return xml_paths

def process_mod_directory(mod_root_dir: str) -> Set[str]:
    """
    Processes item-related XML files for a mod.
    Attempts to use filelist.xml for efficiency; falls back to directory scan if filelist.xml is not found or malformed.
    """
    mod_filelist_path = os.path.join(mod_root_dir, 'filelist.xml')
    xml_files_to_process = []

    # Try to get files from filelist.xml first
    filelist_paths = _get_xml_files_from_filelist(mod_filelist_path, mod_root_dir)
    if filelist_paths:
        xml_files_to_process = filelist_paths
        print(f"Identified {len(xml_files_to_process)} XML files from filelist.xml for mod: {mod_root_dir}")
    else:
        # Fallback to general directory scan if filelist.xml is missing or invalid
        print(f"Could not use filelist.xml at {mod_filelist_path}. Scanning directory for mod content...")
        xml_files_to_process = find_xml_files(mod_root_dir)
        print(f"Identified {len(xml_files_to_process)} XML files by scanning directory for mod: {mod_root_dir}")

    all_identifiers = set()
    for xml_file in xml_files_to_process:
        if not os.path.exists(xml_file):
            print(f"Warning: Referenced file not found (might be deleted or incorrect path): {xml_file}")
            continue
        try:
            with open(xml_file, 'r', encoding="utf-8") as file:
                content = file.read()
                cleaned_content = remove_unwanted_sections(content)
                identifiers = extract_identifiers_from_xml(cleaned_content)
                all_identifiers.update(identifiers)
        except Exception as e:
            print(f"Error processing {xml_file}: {e}")
    
    return all_identifiers

def process_vanilla_directory(vanilla_content_dir: str) -> Set[str]:
    """
    Processes vanilla Barotrauma XML files to extract item identifiers.
    Vanilla content often doesn't have a single filelist, so a directory scan is typical.
    """
    print(f"Scanning directory for vanilla content: {vanilla_content_dir}")
    xml_files = find_xml_files(vanilla_content_dir)
    all_identifiers = set()
    for xml_file in xml_files:
        try:
            with open(xml_file, 'r', encoding="utf-8") as file:
                content = file.read()
                cleaned_content = remove_unwanted_sections(content)
                identifiers = extract_identifiers_from_xml(cleaned_content)
                all_identifiers.update(identifiers)
        except Exception as e:
            print(f"Error processing vanilla file {xml_file}: {e}")
    print(f"Vanilla unique item identifiers found: {len(all_identifiers)}.")
    return all_identifiers

def compare_itemlists(mod_identifiers: Set[str], vanilla_identifiers: Set[str]) -> Tuple[Set[str], Set[str]]:
    """
    Compares two sets of item identifiers to find overrides and additions.
    Returns (override_items, addon_items).
    """
    override = mod_identifiers.intersection(vanilla_identifiers)
    addon = mod_identifiers.difference(vanilla_identifiers)
    return override, addon

# --- New Functions for Translation Extraction ---

def extract_translations_from_xml(xml_file_path: str, language_filter: str = None) -> Dict[str, str]:
    """
    Extracts entityname translations from an XML localization file.
    Optionally filters by the 'language' attribute of the root element.
    """
    translations = {}
    if not os.path.exists(xml_file_path):
        # print(f"Translation file not found: {xml_file_path}")
        return translations

    try:
        tree = ET.parse(xml_file_path)
        root = tree.getroot()

        if language_filter and root.get('language') != language_filter:
            # print(f"Skipping {xml_file_path}: Language mismatch (expected '{language_filter}', got '{root.get('language')}')")
            return translations

        # Find all <entityname.*> tags
        # Using iter() to find all descendants, not just direct children
        for elem in root.iter():
            if elem.tag.startswith('entityname.'):
                identifier_raw = elem.tag
                # Remove 'entityname.' prefix to get the actual identifier
                identifier = identifier_raw.replace('entityname.', '')
                translations[identifier] = elem.text.strip() if elem.text else ''
            # Also consider displayname. for items that might only have a displayname
            elif elem.tag.startswith('displayname.'):
                # We need to extract the base identifier from patterns like "displayname.ChangeMode"
                # which usually have the format "displayname.itemidentifier.suffix"
                # For this specific file, it's "displayname.ChangeMode" or "displayname.lowefficiency"
                # which are not item identifiers themselves, but patterns.
                # We'll stick to 'entityname.' for direct item identifiers for now,
                # as that's what 'extract_identifiers_from_xml' provides.
                pass # You can extend this if needed
    except ET.ParseError as e:
        print(f"Error parsing translation file {xml_file_path}: {e}")
    except Exception as e:
        print(f"An unexpected error occurred while processing {xml_file_path}: {e}")
    return translations

def get_all_translations(mod_root_dir: str, vanilla_content_dir: str) -> Tuple[Dict[str, str], Dict[str, str]]:
    """
    Collects all Simplified Chinese and English entityname translations
    from both mod and vanilla text files.
    Returns (chinese_translations, english_translations).
    """
    chinese_translations = {}
    english_translations = {}

    print("Collecting mod translations...")
    # Mod translations
    mod_text_dir = os.path.join(mod_root_dir, 'Content', 'Texts')
    mod_cn_path = os.path.join(mod_text_dir, 'SimplifiedChinese.xml')
    mod_en_path = os.path.join(mod_text_dir, 'English.xml')
    
    chinese_translations.update(extract_translations_from_xml(mod_cn_path, CHINESE_LANG_CODE))
    english_translations.update(extract_translations_from_xml(mod_en_path, ENGLISH_LANG_CODE))
    print(f"Mod CN translations found: {len(chinese_translations)}, EN translations found: {len(english_translations)}")

    print("Collecting vanilla translations...")
    # Vanilla translations (multiple possible locations)
    vanilla_text_dir = os.path.join(vanilla_content_dir, 'Texts')

    # Standard vanilla paths
    vanilla_cn_path_1 = os.path.join(vanilla_text_dir, 'SimplifiedChinese.xml')
    vanilla_en_path_1 = os.path.join(vanilla_text_dir, 'English.xml')
    
    # Specific vanilla sub-directories often used
    vanilla_cn_sub_dir = os.path.join(vanilla_text_dir, 'SimplifiedChinese')
    vanilla_en_sub_dir = os.path.join(vanilla_text_dir, 'English')

    vanilla_cn_path_2 = os.path.join(vanilla_cn_sub_dir, 'SimplifiedChineseVanilla.xml')
    vanilla_cn_path_3 = os.path.join(vanilla_cn_sub_dir, 'SimplifiedChineseVanillaFactions.xml')
    
    vanilla_en_path_2 = os.path.join(vanilla_en_sub_dir, 'EnglishVanilla.xml')
    vanilla_en_path_3 = os.path.join(vanilla_en_sub_dir, 'EnglishVanillaFactions.xml')


    # Process vanilla paths, updating the dictionaries
    chinese_translations.update(extract_translations_from_xml(vanilla_cn_path_1, CHINESE_LANG_CODE))
    chinese_translations.update(extract_translations_from_xml(vanilla_cn_path_2, CHINESE_LANG_CODE))
    chinese_translations.update(extract_translations_from_xml(vanilla_cn_path_3, CHINESE_LANG_CODE))
    
    english_translations.update(extract_translations_from_xml(vanilla_en_path_1, ENGLISH_LANG_CODE))
    english_translations.update(extract_translations_from_xml(vanilla_en_path_2, ENGLISH_LANG_CODE))
    english_translations.update(extract_translations_from_xml(vanilla_en_path_3, ENGLISH_LANG_CODE))

    print(f"Total CN translations found: {len(chinese_translations)}, Total EN translations found: {len(english_translations)}")
    
    return chinese_translations, english_translations


def write_comparison_to_file_markdown(
    override: Set[str],
    addon: Set[str],
    chinese_translations: Dict[str, str],
    english_translations: Dict[str, str],
    output_file_path: str
):
    """
    Writes the override and addon item lists to the specified output file
    in Markdown table format, including Chinese and English names.
    """
    print(f"Writing comparison results to: {output_file_path}")

    with open(output_file_path, 'w', encoding='utf-8') as file:
        file.write("## Items Overridden by This Mod 以下物品被本模组覆盖\n\n")
        file.write("| ID | English | Chinese |\n")
        file.write("|:---|:---|:---|\n")
        def highlight_ukn(val):
            return '<span style="color:red">UKN</span>' if val == "UKN" else val

        if override:
            for item_id in sorted(list(override)):
                en_name = highlight_ukn(english_translations.get(item_id, "UKN"))
                cn_name = highlight_ukn(chinese_translations.get(item_id, "UKN"))
                file.write(f"| {item_id} | {en_name} | {cn_name} |\n")
        else:
            file.write("| (No items overridden) | | |\n")
        
        file.write("\n## Items Added by This Mod 以下物品被本模组添加\n\n")
        file.write("| ID | English | Chinese |\n")
        file.write("|:---|:---|:---|\n")
        if addon:
            for item_id in sorted(list(addon)):
                en_name = highlight_ukn(english_translations.get(item_id, "UKN"))
                cn_name = highlight_ukn(chinese_translations.get(item_id, "UKN"))
                file.write(f"| {item_id} | {en_name} | {cn_name} |\n")
        else:
            file.write("| (No new items added) | | |\n")
    print("Comparison results written successfully in Markdown format.")

if __name__ == "__main__":
    """
    Main function to run the item list generation process.
    It determines mod and vanilla paths and calls the core logic.
    """
    print("Starting item list generation process...")

    # Determine mod directory: This script expects to be in a 'Repo' folder
    # which is one level down from the actual mod root directory.
    current_script_dir = os.path.dirname(os.path.abspath(__file__))
    # Assuming 'Repo' is directly under the mod's root
    mod_root_directory = os.path.abspath(os.path.join(current_script_dir, '..')) 
    print(f"Determined mod root directory: {mod_root_directory}")

    # Process mod's item list
    print("Processing mod items...")
    mod_identifiers = process_mod_directory(mod_root_directory)
    print(f"Mod unique item identifiers found: {len(mod_identifiers)}")

    # Process vanilla item list
    print(f"Processing vanilla items from: {BAROTRAUMA_CONTENT_PATH}")
    vanilla_identifiers = process_vanilla_directory(BAROTRAUMA_CONTENT_PATH)
    print(f"Vanilla unique item identifiers found: {len(vanilla_identifiers)}")

    # Collect translations
    print("Collecting all relevant translations...")
    chinese_translations, english_translations = get_all_translations(mod_root_directory, BAROTRAUMA_CONTENT_PATH)
    print(f"Collected {len(chinese_translations)} Chinese and {len(english_translations)} English translations.")

    # Compare and generate output
    print("Comparing mod and vanilla item lists...")
    override_items, addon_items = compare_itemlists(mod_identifiers, vanilla_identifiers)

    # Output file will be placed in the mod's 'About' directory
    output_about_directory = os.path.join(mod_root_directory, 'About')
    os.makedirs(output_about_directory, exist_ok=True) # Ensure the 'About' directory exists
    output_file_path = os.path.join(output_about_directory, OUTPUT_FILENAME)
    
    write_comparison_to_file_markdown(
        override_items,
        addon_items,
        chinese_translations,
        english_translations,
        output_file_path
    )
    print("\nItem list generation complete.")
