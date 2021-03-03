此脚本为测试vps回程一键脚本（修改完善版）
---------------
**概述**

此脚本源自南琴浪大佬，大佬的脚本已经4年未做修改，近期（2021年3月15日），脚本核心besttrace即将过期，小弟不才，就此更新besttrace核心并且更新了部分失效的节点

**更新**

 - 升级besttrace核心版本，避免3月15日的失效提醒
 - 加入新的测试节点
 
 **一键脚本**
 
    #下载脚本
    wget -O jcnf.sh https://raw.githubusercontent.com/Netflixxp/jcnfbesttrace/main/jcnf.sh -O jcnf.sh
    

    #运行脚本（再次检查也仅需运行下面代码）
    bash jcnf.sh
    
**功能说明**

脚本的安装目录位于 /home/testrace
测试完成并退出脚本后，会生成测试的记录文件于 /home/testrace/testrace.log
运行脚本后将出现三个选项，分别为

- 1.选择一个节点进行测试
- 2.四网路由快速测试
- 3.手动输入ip进行测试

输入数字选择需要进行的测试。

其中手动输入的意思为指定IP测试，获取自己ip可前往https://www.ipip.net/


----------


脚本修改自 南琴浪 https://github.com/nanqinlang-script/testrace
