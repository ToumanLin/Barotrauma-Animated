# Barotrauma-Animated
木卫二萌化计划

文件解释:
  [About](./About)文件夹中提供了 [修改日志](./About/changelog.txt), 和本Mod的 [item增加和覆盖列表](./About/itemlist.md)


  [Content](./Content)文件夹是mod内容


  [Repo](./Repo)文件夹是存放一些工具脚本


  -[自动生成物品列表](./Repo/item_list_generator.py)
   自动和原版游戏对比ID, 给出覆盖的物品表, 和新增的物品表
  
  -[自动发布更新](./Repo/release.py)
    自动删除dev内容, 推送到00_RELEASE文件夹
    
  -[生成潜在需要更进游戏更新的物品列表](./Repo/GameUpdateChecker.py)
      拉取游戏的上一次更新, 给出潜在需要更新的物品列表

  -[自动计算Origin](./Repo/自动计算新Origin.xlsx)
      输入旧坐标和新坐标, 自动计算新原点

Github link: [https://github.com/Raven-233486/Barotrauma-Animated](https://github.com/Raven-233486/Barotrauma-Animated)

All override & new items are listed in the Itemlist.txt

Classic Verison: %ModDir:2809175631%
Lite Version: %ModDir:2850994195%

label all vanilla uniforms as wf_withboots
  with boots 需要:
  1. subcategory="wf_withboots" identifier="h_[place holder]" description
  2. LeftFoot, RightFoot 增加 sound="footstep_metal_boots"
  with heels 需要:
  1. subcategory="wf_withheels"
  2. LeftFoot, RightFoot 增加 sound="footstep_metal_heels"
  3. LeftFoot, RightFoot 修改 
      <sprite name="[place holder] Left Shoe" texture="[place holder]_2.png" limb="LeftFoot" hidelimb="true" inherittexturescale="true" sourcerect="336,208,64,64" origin="0.48, 0.4125" sound="footstep_metal_heels" />
      <sprite name="[place holder] Right Shoe" texture="[place holder]_2.png" limb="RightFoot" hidelimb="true" inherittexturescale="true" sourcerect="272,208,64,64" origin="0.48, 0.4125" sound="footstep_metal_heels" />
  3. 增加heels animation
      <StatusEffect type="OnWearing" target="Character" setvalue="true" >
        <TriggerAnimation Type="Walk" path="%ModDir%/Content/Characters/Human/Animations/HumanWalkHeels.xml" priority="0" ExpectedSpecies="Human" />
        <TriggerAnimation Type="Run" path="%ModDir%/Content/Characters/Human/Animations/HumanRunHeels.xml" priority="0" ExpectedSpecies="Human" />
        <TriggerAnimation Type="Crouch" path="%ModDir%/Content/Characters/Human/Animations/HumanCrouchHeels.xml" priority="0" ExpectedSpecies="Human" />
      </StatusEffect>
  4. 别忘了本地化, description

更新流程:
 把00_RELEASE文件夹复制到LocalMods, 然后双击ZZ_release.bat 