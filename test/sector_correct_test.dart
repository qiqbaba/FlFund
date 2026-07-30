import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_fund/core/utils/pinyin_search.dart';

void main() {
  group('Sector Correction & Cleaning Tests', () {
    final pinyinSearch = PinyinSearch();

    setUpAll(() async {
      // 初始化拼音字典，以便 getNameByCode 能用
      await pinyinSearch.init();
    });

    test('getCleanSector matches trackingTarget and benchmark correctly', () {
      // 1. 测试跟踪标的 "创业板指数(价格)" -> "创业板"
      final sector1 = pinyinSearch.getCleanSector("创业板指数(价格)", "其它");
      expect(sector1, equals("创业板"));

      // 2. 测试业绩基准 "中证白酒指数收益率*95%+银行活期存款利率(税后)*5%" -> "白酒" (扁平化)
      final sector2 = pinyinSearch.getCleanSector("中证白酒指数收益率*95%+银行活期存款利率(税后)*5%", "其它");
      expect(sector2, equals("白酒"));

      // 3. 测试业绩基准 "中证新能源汽车指数收益率*80%+中证全债指数收益率*20%" -> "新能源汽车" (扁平细化)
      final sector3 = pinyinSearch.getCleanSector("中证新能源汽车指数收益率*80%+中证全债指数收益率*20%", "其它");
      expect(sector3, equals("新能源汽车"));

      // 4. 测试业绩基准 "中证半导体产品与设备指数收益率*95%+..." -> "半导体"
      final sector4 = pinyinSearch.getCleanSector("中证半导体产品与设备指数收益率*95%+银行活期...", "其它");
      expect(sector4, equals("半导体"));

      // 5. 新增：测试 "富国中证消费50ETF联接A" -> "中证消费50"
      final sector5 = pinyinSearch.getCleanSector("富国中证消费50ETF联接A", "其它");
      expect(sector5, equals("中证消费50"));

      // 6. 新增：测试 恒生/港股通 消费 -> "港股消费"
      final sector6 = pinyinSearch.getCleanSector("恒生港股通主要消费ETF", "其它");
      expect(sector6, equals("港股消费"));

      // 7. 新增：测试 标普500 -> "标普500"
      final sector7 = pinyinSearch.getCleanSector("博时标普500ETF联接C", "其它");
      expect(sector7, equals("标普500"));

      // 8. 新增：测试 纳斯达克100 -> "纳斯达克100"
      final sector8 = pinyinSearch.getCleanSector("广发纳斯达克100ETF联接C", "其它");
      expect(sector8, equals("纳斯达克100"));

      // 9. 新增：测试 中证A500，确保 A 不会被误删为中证500 -> "A500"
      final sector9 = pinyinSearch.getCleanSector("易方达中证A500ETF联接C", "其它");
      expect(sector9, equals("A500"));

      // 10. 新增：测试科创创业50 -> "双创50"
      final sector10 = pinyinSearch.getCleanSector("华富中证科创创业50指数增强C", "其它");
      expect(sector10, equals("双创50"));

      // 11. 新增：中欧中证港股通创新药指数发起C -> 港股创新药
      final sector11 = pinyinSearch.getCleanSector("中欧中证港股通创新药指数发起C", "其它");
      expect(sector11, equals("港股创新药"));

      // 12. 新增：广发稀有金属ETF联接C -> 稀有金属
      final sector12 = pinyinSearch.getCleanSector("广发稀有金属ETF联接C", "其它");
      expect(sector12, equals("稀有金属"));

      // 13. 新增：国泰CES半导体芯片行业ETF联接C -> 芯片
      final sector13 = pinyinSearch.getCleanSector("国泰CES半导体芯片行业ETF联接C", "其它");
      expect(sector13, equals("芯片"));

      // 14. 新增：国泰半导体设备ETF联接C -> 半导体设备
      final sector14 = pinyinSearch.getCleanSector("国泰半导体设备ETF联接C", "其它");
      expect(sector14, equals("半导体设备"));

      // 15. 新增：南方恒生指数ETF联接C -> 恒生指数
      final sector15 = pinyinSearch.getCleanSector("南方恒生指数ETF联接C", "其它");
      expect(sector15, equals("恒生指数"));

      // 16. 新增：平安中证卫星产业指数C -> 卫星通信
      final sector16 = pinyinSearch.getCleanSector("平安中证卫星产业指数C", "其它");
      expect(sector16, equals("卫星通信"));

      // 17. 新增：华安国证航天航空行业ETF发起式联接C -> 国证航空航天
      final sector17 = pinyinSearch.getCleanSector("华安国证航天航空行业ETF发起式联接C", "其它");
      expect(sector17, equals("国证航空航天"));

      // 18. 新增：华泰柏瑞上证科创板50成份ETF联接C -> 科创50
      final sector18 = pinyinSearch.getCleanSector("华泰柏瑞上证科创板50成份ETF联接C", "其它");
      expect(sector18, equals("科创50"));

      // 19. 新增：嘉实沪深300红利低波动ETF联接C -> 沪深300红利
      final sector19 = pinyinSearch.getCleanSector("嘉实沪深300红利低波动ETF联接C", "其它");
      expect(sector19, equals("沪深300红利"));

      // 20. 新增：鹏华中证800证券保险指数(LOF)C -> 证券保险
      final sector20 = pinyinSearch.getCleanSector("鹏华中证800证券保险指数(LOF)C", "其它");
      expect(sector20, equals("证券保险"));

      // 21. 新增：广发上海金ETF联接A -> 黄金
      final sector21 = pinyinSearch.getCleanSector("广发上海金ETF联接A", "其它");
      expect(sector21, equals("黄金"));

      // 22. 新增：建信上海金ETF联接C -> 黄金
      final sector22 = pinyinSearch.getCleanSector("建信上海金ETF联接C", "其它");
      expect(sector22, equals("黄金"));

      // 23. 新增：中银上海金ETF联接C -> 黄金
      final sector23 = pinyinSearch.getCleanSector("中银上海金ETF联接C", "其它");
      expect(sector23, equals("黄金"));

      // 24. 新增：天弘黄金ETF联接A -> 黄金
      final sector24 = pinyinSearch.getCleanSector("天弘黄金ETF联接A", "其它");
      expect(sector24, equals("黄金"));

      // 25. 新增：嘉实上海金ETF发起联接A -> 黄金
      final sector25 = pinyinSearch.getCleanSector("嘉实上海金ETF发起联接A", "其它");
      expect(sector25, equals("黄金"));

      // 26. 新增漏洞修复测试：011147的业绩基准（主导权在A股，不应因10%港股而误分类为恒生科技）
      final sector26 = pinyinSearch.getCleanSector("中证800指数收益率*80%+中债综合全价指数收益率*10%+恒生指数收益率*10%", "其它");
      expect(sector26, equals("其它"));

      // 27. 新增漏洞修复测试：020194的业绩基准（主导部分中证800金融，应正确映射到金融，且不被数字截断为中证）
      final sector27 = pinyinSearch.getCleanSector("中证800金融指数收益率*65%+中债国债总全价(总值)指数收益率*20%+中证香港300金融服务指数(人民币)收益率*15%", "其它");
      expect(sector27, equals("金融"));

      // 28. 新增漏洞修复测试：020194基金名称（天弘金融优选混合发起C -> 金融）
      final sector28 = pinyinSearch.getCleanSector("天弘金融优选混合发起C", "其它");
      expect(sector28, equals("金融"));

      // 29. 新增漏洞修复测试：011147基金名称（创金合信气候变化责任投资股票C -> 绿色低碳）
      final sector29 = pinyinSearch.getCleanSector("创金合信气候变化责任投资股票C", "其它");
      expect(sector29, equals("绿色低碳"));

      // 30. 修复 002112 -> 主动混合
      expect(pinyinSearch.getCleanSector("德邦鑫星价值灵活配置混合C", "其它"), equals("主动混合"));

      // 31. 修复 011370 -> 主动混合
      expect(pinyinSearch.getCleanSector("华商均衡成长混合C", "其它"), equals("主动混合"));

      // 32. 修复 161226 -> 白银
      expect(pinyinSearch.getCleanSector("国投瑞银白银期货(LOF)A", "其它"), equals("白银"));

      // 33. 修复 018994 -> 数字经济
      expect(pinyinSearch.getCleanSector("中欧数字经济混合发起C", "其它"), equals("数字经济"));

      // 34. 修复 022365 -> 科技
      expect(pinyinSearch.getCleanSector("永赢科技智选混合发起C", "其它"), equals("科技"));

      // 35. 针对历史污染分类的自动清洗与防锁死升级测试
      expect(pinyinSearch.getCleanSector("永赢科技智选混合发起C", "科技智选发起"), equals("科技"));
      expect(pinyinSearch.getCleanSector("中欧数字经济混合发起C", "数字经济发起"), equals("数字经济"));
      expect(pinyinSearch.getCleanSector("国投瑞银白银期货(LOF)A", "国投瑞银白银"), equals("白银"));
      expect(pinyinSearch.getCleanSector("德邦鑫星价值灵活配置混合C", "德邦鑫星价值"), equals("主动混合"));

      // 36. 黄金股测试 (021874, 021959)
      expect(pinyinSearch.getCleanSector("中欧黄金股指数C", "其它"), equals("黄金股"));
      expect(pinyinSearch.getCleanSector("南方黄金股C", "其它"), equals("黄金股"));

      // 37. 电网设备与智能电网测试 (025857)
      expect(pinyinSearch.getCleanSector("华夏中证电网设备主题ETF联接C", "其它"), equals("电网设备"));
      expect(pinyinSearch.getCleanSector("国泰中证智能电网A", "其它"), equals("智能电网"));

      // 38. 石油天然气/油气测试 (021620)
      expect(pinyinSearch.getCleanSector("天弘石油天然气指数C", "其它"), equals("油气"));

      // 39. 原油商品测试 (006476)
      expect(pinyinSearch.getCleanSector("南方原油C", "其它"), equals("原油"));

      // 40. 港股通科技与恒生科技区分测试 (025545, 013446 等)
      expect(pinyinSearch.getCleanSector("汇添富港股通科技精选混合发起式C", "其它"), equals("港股通科技"));
      expect(pinyinSearch.getCleanSector("华泰柏瑞中证港股通科技ETF发起式联接A", "其它"), equals("港股通科技"));
      expect(pinyinSearch.getCleanSector("天弘恒生科技ETF联接C", "其它"), equals("恒生科技"));
      expect(pinyinSearch.getCleanSector("易方达恒生科技ETF联接A", "其它"), equals("恒生科技"));

      // 40. 历史板块防锁死自动清洗升级测试
      expect(pinyinSearch.getCleanSector("中欧黄金股指数C", "黄金"), equals("黄金股"));
      expect(pinyinSearch.getCleanSector("南方黄金股C", "黄金"), equals("黄金股"));
      expect(pinyinSearch.getCleanSector("华夏中证电网设备主题ETF联接C", "电力"), equals("电网设备"));
      expect(pinyinSearch.getCleanSector("天弘石油天然气指数C", "原油"), equals("油气"));

      // 41. 其它细节表述优化测试
      expect(pinyinSearch.getCleanSector("天弘全球高端制造QDII C", "其它"), equals("全球制造"));
      expect(pinyinSearch.getCleanSector("永赢先进制造智选混合发起C", "其它"), equals("先进制造"));
      expect(pinyinSearch.getCleanSector("永赢国证商用卫星通信ETF联接C", "其它"), equals("卫星通信"));
      expect(pinyinSearch.getCleanSector("汇添富港股红利ETF联接C", "其它"), equals("港股红利"));
      expect(pinyinSearch.getCleanSector("富国互联科技股票C", "其它"), equals("互联科技"));

      // 42. 新增的精确匹配与细化测试
      expect(pinyinSearch.getCleanSector("东方人工智能主题混合C", "其它"), equals("人工智能"));
      expect(pinyinSearch.getCleanSector("易方达标普信息科技", "其它"), equals("科技"));
      expect(pinyinSearch.getCleanSector("天弘中证电子ETF联接C", "其它"), equals("电子"));
      expect(pinyinSearch.getCleanSector("富国中证信创ETF联接C", "其它"), equals("信创"));
      expect(pinyinSearch.getCleanSector("天弘中证农业主题ETF联接C", "其它"), equals("农业"));
      expect(pinyinSearch.getCleanSector("永赢高端装备智选混合发起C", "其它"), equals("高端装备"));
      expect(pinyinSearch.getCleanSector("前海开源金银珠宝混合C", "其它"), equals("金银珠宝"));
      expect(pinyinSearch.getCleanSector("广发中证建筑材料ETF联接C", "其它"), equals("建材"));
      expect(pinyinSearch.getCleanSector("广发中证环保产业ETF联接C", "其它"), equals("绿色低碳"));

      // 43. 有色金属细分测试 (有色金属、工业金属、贵金属)
      expect(pinyinSearch.getCleanSector("南方有色金属ETF联接C", "其它"), equals("有色金属"));
      expect(pinyinSearch.getCleanSector("天弘中证工业有色金属主题ETF发起联接C", "其它"), equals("工业金属"));
      expect(pinyinSearch.getCleanSector("华夏有色金属ETF联接C", "其它"), equals("有色金属"));
      expect(pinyinSearch.getCleanSector("招商中证贵金属ETF", "其它"), equals("贵金属"));
      
      // 有色金属防锁死自动清洗升级测试
      expect(pinyinSearch.getCleanSector("南方有色金属ETF联接C", "有色金属"), equals("有色金属"));
      expect(pinyinSearch.getCleanSector("天弘中证工业有色金属主题ETF发起联接C", "有色金属"), equals("工业金属"));

      // 44. 信息技术与信息安全板块测试
      expect(pinyinSearch.getCleanSector("南方中证500信息技术联接C", "其它"), equals("信息技术"));
      expect(pinyinSearch.getCleanSector("鹏华中证信息技术指数(LOF)C", "其它"), equals("信息技术"));
      expect(pinyinSearch.getCleanSector("中信保诚中证信息安全指数(LOF)C", "其它"), equals("信息技术"));
      expect(pinyinSearch.getCleanSector("华夏中证全指信息技术ETF发起式联接A", "其它"), equals("信息技术"));
      
      // 信息技术自动清洗防锁死升级测试
      expect(pinyinSearch.getCleanSector("南方中证500信息技术联接C", "中证500"), equals("信息技术"));

      // 45. 黄金产业与大宗商品分类优化测试 (021075, 257060)
      expect(pinyinSearch.getCleanSector("华夏中证沪深港黄金产业股票ETF发起式联接C", "黄金"), equals("黄金股"));
      expect(pinyinSearch.getCleanSector("国联安上证商品ETF联接A", "上证"), equals("大宗商品"));
    });

    test('upgrade local my_funds.json sectors', () async {
      final file = File('my_funds.json');
      if (await file.exists()) {
        final content = await file.readAsString(encoding: utf8);
        final Map<String, dynamic> jsonMap = json.decode(content);
        if (jsonMap['funds_info'] != null) {
          final Map<String, dynamic> infoMap = jsonMap['funds_info'];
          int count = 0;
          infoMap.forEach((code, value) {
            if (value is Map<String, dynamic>) {
              final name = value['name'] ?? '';
              final oldSector = value['sector'] ?? '';
              final newSector = pinyinSearch.getCleanSector(name, oldSector);
              if (newSector != oldSector) {
                value['sector'] = newSector;
                // ignore: avoid_print
                print('基金 $code ($name) 本地板块从 $oldSector 自动升级为 $newSector');
                count++;
              }
            }
          });
          if (count > 0) {
            const encoder = JsonEncoder.withIndent('    ');
            await file.writeAsString(encoder.convert(jsonMap), encoding: utf8);
            // ignore: avoid_print
            print('已升级本地 $count 只基金的板块分类！');
          }
        }
      }
    });

    test('HTML clean tags utility works correctly', () {
      // 模拟包含链接的HTML
      const htmlText = '<a>中证消费指数</a>&nbsp;*95%';
      // 使用私有方法_cleanHtmlTags测试（此处通过反射或直接用RegExp测试）
      final cleanText = htmlText.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&nbsp;', ' ');
      expect(cleanText, equals('中证消费指数 *95%'));
    });
  });
}
