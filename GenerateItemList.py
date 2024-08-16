import os
import re

def find_xml_files(directory):
    xml_files = []
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.xml'):
                xml_files.append(os.path.join(root, file))
    return xml_files

def remove_unwanted_sections(xml_content):
    # 移除XML注释
    comment_pattern = re.compile(r'<!--.*?-->', re.DOTALL)
    xml_content = comment_pattern.sub('', xml_content)
    
    # 移除 <Fabricate> 标签及其内容
    fabricate_pattern1 = re.compile(r'<Fabricate[^>]*?/>', re.DOTALL)
    fabricate_pattern2 = re.compile(r'<Fabricate.*?</Fabricate>', re.DOTALL)
    xml_content = fabricate_pattern1.sub('', xml_content)
    xml_content = fabricate_pattern2.sub('', xml_content)
    
    # 移除 <Deconstruct> 标签及其内容
    deconstruct_pattern1 = re.compile(r'<Deconstruct[^>]*?/>', re.DOTALL)
    deconstruct_pattern2 = re.compile(r'<Deconstruct.*?</Deconstruct>', re.DOTALL)
    xml_content = deconstruct_pattern1.sub('', xml_content)
    xml_content = deconstruct_pattern2.sub('', xml_content)
    
    # 移除 <Inventory> 标签及其内容
    inventory_pattern1 = re.compile(r'<Inventory[^>]*?/>', re.DOTALL)
    inventory_pattern2 = re.compile(r'<Inventory.*?</Inventory>', re.DOTALL)
    xml_content = inventory_pattern1.sub('', xml_content)
    xml_content = inventory_pattern2.sub('', xml_content)

    # 移除 <ItemSet> 标签及其内容
    itemSet_pattern1 = re.compile(r'<ItemSet[^>]*?/>', re.DOTALL)
    itemSet_pattern2 = re.compile(r'<ItemSet.*?</ItemSet>', re.DOTALL)
    xml_content = itemSet_pattern1.sub('', xml_content)
    xml_content = itemSet_pattern2.sub('', xml_content)
    
    # 移除 <npcsets> 标签及其内容
    npcsets_pattern1 = re.compile(r'<npcsets[^>]*?/>', re.DOTALL)
    npcsets_pattern2 = re.compile(r'<npcsets.*?</npcsets>', re.DOTALL)
    xml_content = npcsets_pattern1.sub('', xml_content)
    xml_content = npcsets_pattern2.sub('', xml_content)
    
    # 移除 <Jobs> 标签及其内容
    jobs_pattern1 = re.compile(r'<Jobs[^>]*?/>', re.DOTALL)
    jobs_pattern2 = re.compile(r'<Jobs.*?</Jobs>', re.DOTALL)
    xml_content = jobs_pattern1.sub('', xml_content)
    xml_content = jobs_pattern2.sub('', xml_content)

    # 移除 <Missions> 标签及其内容
    missions_pattern1 = re.compile(r'<Missions[^>]*?/>', re.DOTALL)
    missions_pattern2 = re.compile(r'<Missions.*?</Missions>', re.DOTALL)
    xml_content = missions_pattern1.sub('', xml_content)
    xml_content = missions_pattern2.sub('', xml_content)

    return xml_content

def extract_identifiers_from_xml(xml_content):
    identifiers = re.findall(r'<Item[^>]*?identifier="([^"]+)', xml_content)
    return identifiers

def write_identifiers_to_file(identifiers, output_file):
    with open(output_file, 'w', encoding='utf-8') as file:
        file.write('The ID of all items that added or overrided by this Mod: \n\n')
        for identifier in identifiers:
            file.write(identifier + '\n')

def main():
    current_directory = os.path.dirname(os.path.abspath(__file__))
    xml_files = find_xml_files(current_directory)
    
    all_identifiers = []
    for xml_file in xml_files:
        with open(xml_file, 'r', encoding="utf-8") as file:
            content = file.read()
            cleaned_content = remove_unwanted_sections(content)
            identifiers = extract_identifiers_from_xml(cleaned_content)
            all_identifiers.extend(identifiers)
    
    output_file = os.path.join(current_directory, 'itemlist.txt')
    write_identifiers_to_file(all_identifiers, output_file)

if __name__ == "__main__":
    main()
