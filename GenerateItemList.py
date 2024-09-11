import os
import re

def find_xml_files(directory):
    xml_files = []
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.xml') and file != 'Reference.xml':
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

def process_directory(directory):
    xml_files = find_xml_files(directory)
    
    all_identifiers = set()
    for xml_file in xml_files:
        with open(xml_file, 'r', encoding="utf-8") as file:
            content = file.read()
            cleaned_content = remove_unwanted_sections(content)
            identifiers = extract_identifiers_from_xml(cleaned_content)
            all_identifiers.update(identifiers)
    
    return all_identifiers

def compare_itemlists(mod_identifiers, vanilla_identifiers):
    # 找出相同的项目，放入 override
    override = mod_identifiers.intersection(vanilla_identifiers)
    
    # 找出 mod 独有的项目，放入 addon
    addon = mod_identifiers.difference(vanilla_identifiers)
    
    return override, addon

def write_comparison_to_file(override, addon, output_file):
    """
    将 override 和 addon 项目写入输出文件。
    """
    with open(output_file, 'w', encoding='utf-8') as file:
        # 写入 Override Items
        file.write("Items Overrided by This mod:\n")
        for item in override:
            file.write(f"{item}\n")
        
        file.write("\n")  # 添加空行分隔
        
        # 写入 Addon Items
        file.write("Items Added by This mod:\n")
        for item in addon:
            file.write(f"{item}\n")

def main():
    # 获取当前目录下的 Mod itemlist
    current_directory = os.path.dirname(os.path.abspath(__file__))
    mod_identifiers = process_directory(current_directory)

    # 获取 Barotrauma Content 目录下的 Vanilla itemlist
    barotrauma_directory = r'C:\Program Files (x86)\Steam\steamapps\common\Barotrauma\Content'
    vanilla_identifiers = process_directory(barotrauma_directory)

    # 对比 Mod 和 Vanilla 的 itemlist，生成 override 和 addon 集合
    override, addon = compare_itemlists(mod_identifiers, vanilla_identifiers)

    # 输出结果到文件
    output_file = os.path.join(current_directory, 'itemlist.txt')
    write_comparison_to_file(override, addon, output_file)

if __name__ == "__main__":
    main()
