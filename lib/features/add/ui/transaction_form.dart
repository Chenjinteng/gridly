// lib/features/add/ui/transaction_form.dart
// 流水编辑 / 新增表单(纯 body,无 Scaffold/AppBar)——
//   - AddTransactionPage:包成 Scaffold 做"全屏记一笔"页面
//   - EditTransactionPage:包成 Scaffold 做"全屏编辑"页面(/edit/:id 路由)
//
// 两处共用同一份表单逻辑(type toggle / 表达式计算器 / 分类 / 日期 / 备注 / 保存),
// 调用方通过 onSaved 回调决定保存后行为(都 context.pop(),返回路由栈上一级)。
//
// ⚠️ 2026-10-11 改:之前流水编辑用 showEditTransactionSheet(modal sheet),sheet 内
// AnimatedPadding 会按 viewInsets 推 Numpad 上移,跟全屏不一致。改成全屏路由后,
// 两处都用 Scaffold(resizeToAvoidBottomInset:false)+ SafeArea(bottom:false) 的
// 同一套物理布局:键盘弹起时 Numpad 真正被键盘盖住。
//
// ⚠️ 字符串插值陷阱(沿用历史踩坑注释):
// Dart 里 `'$_calc.display'` 不会取 _calc.display 的值,而是把 $_calc
// 当插值(_calc.toString() = "Instance of '_CalcState'"),再把 .display 当字面量
// 拼在后面,最终 _calc.display 被赋值成 "Instance of '_CalcState'.display"。
// 正确写法是 '${_calc.display}'(加花括号)。
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;

import '../../../core/database/app_database.dart';
import '../../../core/database/providers.dart';
import '../../../core/settings/amount_visibility_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/card_shadows.dart';
import '../../../core/utils/asset_balance_provider.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/gridly_banner.dart';
import '../../../core/utils/refresh_providers.dart';
import '../../../shared/constants/default_categories.dart';
import '../../ledger/application/transactions_providers.dart';
import '../../settings/ui/widgets/asset_tile.dart';
import 'widgets/amount_display.dart';
import 'widgets/custom_date_picker.dart';
import 'widgets/numpad.dart';
import 'widgets/type_toggle.dart';

class TransactionForm extends ConsumerStatefulWidget {
  const TransactionForm({
    super.key,
    this.editTransaction,
    this.onSaved,
    this.preselectedAssetType,
    this.allowBalance = true,
    this.accountTypeFilter,
  });

  /// 非空 → 编辑模式(预填 + 保存 update)
  /// 为空 → 新增模式(保存 insert)
  final Transaction? editTransaction;

  /// 保存成功后回调(由调用方决定:AddTransactionPage 跳 /home,edit sheet 仅 dismiss)
  final VoidCallback? onSaved;

  /// 2026-10-13 P6 commit:预选资产类型(短按 + 默认 'cash_flow',长按 + 5 小圆选)
  /// - null 或 'cash_flow' → 取 cash_flow 段第 1 个账户作 accountId
  /// - 其他 → 取对应 type 段第 1 个账户作 accountId
  final String? preselectedAssetType;

  /// 2026-10-13 P6 UAT 改:是否显示"调拨"段
  ///   - 短按路径(老版):false,只显示 支出/收入
  ///   - 长按路径(目前):true,保留 3 段
  final bool allowBalance;

  /// 2026-10-13 P6 UAT 改:账户选择 sheet 按该 type 过滤(allAssets)
  ///   - 短按 'cash_flow' → 只显示 cash_flow 账户
  ///   - 长按 'investment' → 只显示 investment 账户
  ///   - null → 不过滤(显示所有)
  final String? accountTypeFilter;

  @override
  ConsumerState<TransactionForm> createState() => _TransactionFormState();
}

class _CalcState {
  String display = '0'; // 当前显示字符串
  String expression = ''; // 表达式(已计算的部分)
  double? previousValue; // 上一个数
  String? pendingOp; // 等待中的运算符
  bool justEvaluated = false; // 上一次按键是 =
}

class _TransactionFormState extends ConsumerState<TransactionForm> {
  // 2026-10-13 P8 重构:用 _intent 表达 toggle UI 语义,用 _type 表达 DB 存储
  // - cash_flow:_intent = _type = 'expense' / 'income' / 'balance'(1:1 对应 DB)
  // - investment:_intent = 'input' / 'output' / 'transfer',DB _type 始终 'balance',
  //   通过 destinationAccountId 表达 source→dest 流向
  //
  // 2026-10-13 P9 UAT 改:_intent 默认按上下文(cash_flow='expense', investment='input')
  //   user:"默认还是选择投入,不然用户不知道这个是可以选择的"
  //   - investment _intent='expense' 不在 investmentSegments 里,显示无选中态
  //   - 改成 'input' 后,投入段自动可见选中,user 一眼知道 toggle 可点
  String _intent = 'expense';

  /// DB 存储的实际 type:
  /// - cash_flow → 直接用 _intent(expense / income / balance)
  /// - investment → 投入/调拨存 'balance'(双账户,source→dest),收益存 'income'(单账户)
  ///   2026-10-14 P18 大改:
  ///   - 投入(_intent='input'):type='balance',双账户(source=cash → dest=investment)
  ///   - 收益(_intent='output'):type='income',单账户(只有 accountId,无 destination)
  ///     收益是账户自身的增长,没有"从哪到哪"的流向,跟转入转出语义无关
  ///   - 调拨(_intent='transfer'):type='balance',双账户(任意 ↔ 任意)
  ///   - 之前 P8→P17 一律存 'balance',收益也要 destinationAccountId(语义错)
  /// - 2026-10-14 D51:receivable → 直接用 _intent('lend_out' / 'borrow_in' / 'transfer'),大部分 1:1
  ///   - 借出 = 'lend_out',accountId=负债账户,balance += amount
  ///   - 借入 = 'borrow_in',accountId=负债账户,balance -= amount
  ///   - 调拨 = 'balance',双账户(负债 source → 现金 dest,或反之),有 destinationAccountId
  ///   - 借出/借入 单账户操作,无 destinationAccountId;调拨 跟 cash_flow 调拨同 schema
  String get _type {
    if (_isInvestmentContext) {
      if (_intent == 'output') return 'income'; // 收益:单账户增加
      return 'balance'; // 投入/调拨:source → dest
    }
    if (_isReceivableContext) {
      // D51 v2:调拨段走 'balance' 跟 cash_flow / investment 一致
      if (_intent == 'transfer') return 'balance';
      return _intent; // 'lend_out' / 'borrow_in' 1:1 对应 DB
    }
    return _intent;
  }

  int? _categoryId; // cash_flow 才有;investment 不需要
  DateTime _occurredAt = DateTime.now();
  // 2026-10-12 P3 commit 加:账户选择(state)
  //   - 新增模式:initState 时取第一个 cash_flow 账户(displayOrder 升序 = "现金")
  //   - 编辑模式:用 editTransaction.accountId(已有流水自带)
  //   - 改 _intent 时**保留账户**(切换支出/收入/调拨不重置账户,跟用户"调拨对应账户"的预期一致)
  // 2026-10-13 P8:investment 场景下 _accountId 是"转出",_destinationAccountId 是"转入"
  int? _accountId;
  int? _destinationAccountId;
  final _noteController = TextEditingController();
  final _calc = _CalcState();

  /// 2026-10-13 P8:投资场景标识
  bool get _isInvestmentContext => widget.preselectedAssetType == 'investment';

  /// 2026-10-14 加:福利场景标识(preselectedAssetType='benefit')
  ///   - 福利 = 公司社保/医保/餐补等日常福利账户,逻辑跟 cash_flow 短按 + 同:
  ///     只收入支出 / 隐藏分类选择器(默认 fallback 到 cat.type='benefit' 的 cat)/ 单账户
  ///   - 跟 investment 区别:investment 三段(投入/收益/调拨),福利就 2 段(支出/收入)
  bool get _isBenefitContext => widget.preselectedAssetType == 'benefit';

  /// 2026-10-14 加:债权场景标识(preselectedAssetType='receivable')
  ///   - 2026-10-14 简化:user 反馈"期权直接去掉,放到投资中",
  ///     receivable 段下只剩 1 cat"负债"(cat.type='liability')
  ///   - 跟福利/投资同 pattern:UI 隐藏 cat 选择,自动 fallback
  ///     (不跟之前"保留选分类,2 cat 选"逻辑,简化设计)
  ///   - 2 段 toggle(支出/收入),无调拨(同 cashFlow 短按 +)
  ///   - 跟福利/投资行为对齐:_needsCategory=false,_firstCategoryId 走 fallback
  bool get _isReceivableContext => widget.preselectedAssetType == 'receivable';

  /// 2026-10-14 D55 加:其它场景标识(preselectedAssetType='other')
  /// 2026-10-14 D57 改:"其它" 段参考福利 pattern,跟其它 5 大类资产场景脱钩
  ///   - 之前 D55 想"6 大类账户都能选",user 反馈太复杂,改成跟福利同样的简化结构:
  ///   - 2 段 toggle(支出/收入,无调拨;同 cash_flow 短按 +)
  ///   - 账户 picker 只显示 'other' 类型账户(_accountTypeFilter='other')
  ///   - UI 隐藏 cat 选择器(_needsCategory=false),自动 fallback 到 cat.type='other' 的 cat
  ///   - 跟 cash_flow 区别:asset.type='other',cat.type='other';都跟"其它"对应
  ///   - user:"如果要在其它这里考虑其它5个资产场景的话太复杂了,这里的其它就直接是其它的类型,
  ///         只有支出收入,然后帐户能选择的是其它,然后分类类型默认是其它"
  bool get _isOtherContext => widget.preselectedAssetType == 'other';

  /// toggle segments 配置(2026-10-13 P8:caller 完全控制)
  /// 2026-10-13 P11 UAT 修:之前承诺 allowBalance=false 时过滤掉"调拨",
  ///   但实现漏了 → 短按+ 仍出 3 段含"调拨",user:"日常现金流水只关注支出收入"
  ///   - 短按 cash_flow(allowBalance=false)→ 2 段(支出/收入),无"调拨"
  ///   - 长按 investment(_isInvestmentContext)→ investmentSegments 3 段
  ///   - 长按 非投资(allowBalance=true)→ 3 段(支出/收入/调拨)
  /// 2026-10-14 加:_isBenefitContext 走 2 段(同 cash_flow 短按 +),无调拨
  ///   - user 截图:"调拨:动资产,不算月度收支" tip 在福利页 toggle 上也有
  ///   - 福利是"日常福利",不涉及账户间调拨,跟 cash_flow 短按 + 同样逻辑
  /// 2026-10-14 D51 改:_isReceivableContext 走 receivableSegments 2 段(借出/借入)
  ///   - 之前 v1 用 cashFlowSegments 过滤 balance 段(走支出/收入),user 反馈
  ///     语义错:"借出"是债权人(正数),"借入"是负债方(负数),跟支出/收入对不上
  ///   - 改成借出/借入 2 段,DB 存 'lend_out' / 'borrow_in' 直接对应
  List<ToggleSegment> get _toggleSegments {
    if (_isInvestmentContext) return TypeToggle.investmentSegments;
    if (_isReceivableContext) {
      // 2026-10-14 D51:负债段走独立 receivableSegments(借出 / 借入)
      //   不复用 cashFlowSegments 过滤,因为语义完全不同
      return TypeToggle.receivableSegments;
    }
    if (_isBenefitContext) {
      // 福利 2 段:filter 掉 balance(同 cashFlow 短按 + path)
      return TypeToggle.cashFlowSegments
          .where((s) => s.key != 'balance')
          .toList();
    }
    if (_isOtherContext) {
      // 2026-10-14 D57:其它 2 段:filter 掉 balance(同福利 pattern)
      //   其它 = 兜底简化,无调拨,跟福利同结构
      return TypeToggle.cashFlowSegments
          .where((s) => s.key != 'balance')
          .toList();
    }
    if (widget.allowBalance) return TypeToggle.cashFlowSegments;
    // cash_flow + 不允许 balance → 过滤掉"调拨"
    return TypeToggle.cashFlowSegments
        .where((s) => s.key != 'balance')
        .toList();
  }

  /// 2026-10-13 P8:是否需要分类(只有 cash_flow 需要;投资场景分类去掉)
  /// 2026-10-14 加:福利场景也去掉分类选择器,默认 fallback cat.type='benefit' 的 cat
  ///   - 跟 investment 同 pattern:UI 隐藏 + DB NOT NULL 通过 fallback 填
  /// 2026-10-14 加:债权场景也去掉分类选择器(跟福利/投资同 pattern)
  ///   - 简化前:债权段有 2 cat(股份期权 / 负债借贷),user 主动选
  ///   - 简化后:user 反馈"期权直接去掉,放到投资中",只剩 1 cat"负债"
  ///   - 1 cat 跟投资/福利同样处理:UI 隐藏,自动 fallback 到 cat.type='liability' 的 cat
  /// 2026-10-14 D57 加:其它场景也去掉分类选择器(跟福利/投资/债务同 pattern)
  ///   - 自动 fallback 到 cat.type='other' 的 cat(1 个内置)
  bool get _needsCategory {
    if (_isInvestmentContext) return false;
    if (_isBenefitContext) return false;
    if (_isReceivableContext) return false;
    if (_isOtherContext) return false; // D57:其它段 UI 隐藏 cat
    return true;
  }

  /// 2026-10-14 P18 大改:investment 三段拆分
  ///   - 投入 / 调拨 → 双账户(转出 + 转入)
  ///   - 收益 → 单账户(只有 accountId)
  /// 收益是账户自身的增长,没有"从哪到哪"的流向,UI 上不显示转入转出 pill,
  ///   save() 时 destinationAccountId 传 null
  /// 2026-10-14 D51:receivable 借出/借入 → 单账户;调拨 → 双账户
  ///   - 借出/借入:无 destinationAccountId(单账户记录,只动负债账户)
  ///   - 调拨:有 destinationAccountId(负债 ↔ 现金 流转)
  bool get _needsDualAccount {
    if (_isInvestmentContext) {
      return _intent != 'output'; // 投入/调拨:双;收益:单
    }
    if (_isReceivableContext) {
      return _intent == 'transfer'; // D51 v2:调拨是双账户,借出/借入都是单
    }
    return false; // cash_flow 暂用单 accountId
  }

  /// 2026-10-14 D56 废:其它段选分类按账户 type 过滤 —— 2026-10-14 D57 撤销
  ///   - D56 假设"其它"段可选 6 大类账户,picker 跟随账户 type 显示内置 cat
  ///   - D57 改:"其它"段跟福利同 pattern(只显示 other 账户 + cat UI 隐藏),不再需要这个逻辑
  ///   - 代码已移除,留此注释记录设计变迁

  bool get _isEdit => widget.editTransaction != null;

  @override
  void initState() {
    super.initState();
    // 2026-10-13 P9 UAT 加:investment context 默认 _intent='input'(投入)
    // user:"默认还是选择投入,不然用户不知道这个是可以选择的"
    // cash_flow 默认仍是 'expense'(短按+ 默认日常支出)
    // 2026-10-14 D51:receivable context 默认 _intent='lend_out'(借出)
    //   - 借出 是 2 段里的"正向"动作(我是债权人,balance +)
    //   - 跟 investment 选 'input'(投入) 同样的设计哲学:默认展示最常用 / 最明确的语义
    if (_isReceivableContext) {
      _intent = 'lend_out';
    } else if (!_isInvestmentContext) {
      // _intent 已是 'expense',无需覆盖
    } else {
      _intent = 'input';
    }
    final t = widget.editTransaction;
    if (t != null) {
      // 编辑模式:预填已有数据
      // 2026-10-14 D51:receivable 编辑时_type = 'lend_out' / 'borrow_in' 1:1
      // 2026-10-16 D64.84 改:investment 编辑也支持
      //   - 之前 _intent = t.type 直接赋值,但 investment DB type 是 'income' /
      //     'balance',不在 TypeToggle.investmentSegments = ['input','output',
      //     'transfer'] 里 → toggle 永远无选中 + 保存撞 "选个转入账户" banner
      //   - 修:investment 用 _firstCategoryId 查 cat.type,再按 (cat.type, t.type,
      //     dest) 映射回 _intent(input/output/transfer)
      //   - cash_flow / receivable 仍 1:1 不变
      //   - 同步 investment pre-fill asset 跟 _intent 匹配(之前只 new mode 走)
      // 2026-10-16 D64.85 改:异步查 source asset 类型决定 _intent(input vs transfer)
      //   - 投入 vs 调拨 DB 都是 'balance' + dest!=null,只看 DB type 区分不开
      //   - 看 source account type:source=cash_flow 视为 'input' (投入),
      //     其它视为 'transfer' (调拨),符合 user 实际大多数场景
      if (_isInvestmentContext) {
        // investment 段:按 cat.type 判定,然后再按 source 决定 input vs transfer
        //   - DB type='income' → 投资收益 → _intent='output'
        //   - DB type='balance' + dest=null → 理论上不存在(投资只能单/双账户)
        //   - DB type='balance' + dest!=null → 投资投入/调拨,需看 source
        if (t.type == 'income') {
          _intent = 'output';
        } else {
          // 临时先按 'transfer',source asset 加载后修正
          _intent = 'transfer';
        }
      } else {
        _intent = t.type; // cash_flow / receivable 直接 1:1
      }
      _categoryId = _needsCategory ? t.categoryId : null;
      _accountId = t.accountId;
      _destinationAccountId = t.destinationAccountId;
      _occurredAt = t.occurredAt;
      _noteController.text = t.note ?? '';
      // 金额显示:整数显示整数,小数保留原值
      if (t.amount == t.amount.truncateToDouble() && t.amount.abs() < 1e15) {
        _calc.display = t.amount.toInt().toString();
      } else {
        _calc.display = t.amount.toString();
      }
      // 2026-10-16 D64.85:异步加载 source asset,investment 双账户区分 input/transfer
      //   - postFrameCallback 第一次 build 时 ref 还没 ready,直接 read 会触发
      //     "ref used outside build" 警告
      if (_isInvestmentContext &&
          t.type == 'balance' &&
          t.destinationAccountId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          final sourceAsset =
              await ref.read(assetRepositoryProvider).byId(t.accountId);
          if (!mounted) return;
          // source=cash_flow 视为投入(input),其它视为调拨(transfer)
          if (sourceAsset?.type == 'cash_flow') {
            setState(() => _intent = 'input');
          }
        });
      }
    } else {
      // 新增模式:默认账户取 preselectedAssetType 段优先的
      //   (2026-10-13 P6:从硬编码 'cash_flow' 改成参数化,支持中央 + 长按选 type)
      //   短按 + → 'cash_flow'(默认);长按 + → 5 小圆选(investment/benefit/...)
      //   改用 addPostFrameCallback:第一次 build 时 ref 还没 ready,
      //   直接 read 会触发 "ref used outside build" 警告
      //
      // 2026-10-13 P7:优先选 isDefault=true 账户(user 在 form 里"设为默认"开关)
      //   - 没有 isDefault 的(cash_flow 段默认账户未设置)→ fallback 到 typeAssets.first
      //   - 仅在 _accountId 仍为 null 时赋值(避免覆盖用户已选的账户)
      //
      // 2026-10-14 P18 大改:investment 三段各自合理 pre-fill
      //   - 投入 (_intent='input'):source=cash_flow(从现金)+ dest=investment(到投资账户)
      //     投入本质是 cash → investment 的流向,引导 user 一眼看到默认配对
      //   - 收益 (_intent='output'):_accountId=investment 第 1 个(只有投资账户能涨)
      //     _destinationAccountId=null(单账户)
      //   - 调拨 (_intent='transfer'):不预填(_accountId/_destinationAccountId 都 null)
      //     user 反馈"只清理就好",转出/转入互不预设
      //   - cash_flow:原行为,取第一个 cash_flow(isDefault 优先)
      final preselectedType = widget.preselectedAssetType ?? 'cash_flow';
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final repo = ref.read(assetRepositoryProvider);
        final assets = await repo.all();
        if (!mounted) return;

        // 通用 helper:从指定 type 段挑第一个(isDefault 优先)
        Asset? pickFirst(String type) {
          final list = assets.where((a) => a.type == type).toList();
          for (final a in list) {
            if (a.isDefault) return a;
          }
          return list.isEmpty ? null : list.first;
        }

        int? pickedAccountId;
        int? pickedDestId;
        if (_isInvestmentContext) {
          switch (_intent) {
            case 'input':
              // 投入:cash_flow(转出)+ investment(转入)
              pickedAccountId = pickFirst('cash_flow')?.id;
              pickedDestId = pickFirst('investment')?.id;
            case 'output':
              // 收益:investment(单账户)
              pickedAccountId = pickFirst('investment')?.id;
              pickedDestId = null;
            case 'transfer':
              // 调拨:不预填
              pickedAccountId = null;
              pickedDestId = null;
          }
        } else {
          // cash_flow:原行为,取 preselectedType 段第 1 个(isDefault 优先)
          pickedAccountId = pickFirst(preselectedType)?.id;
          pickedDestId = null;
        }

        setState(() {
          _accountId ??= pickedAccountId;
          _destinationAccountId ??= pickedDestId;
        });
      });
    }
  }

  /// 2026-10-14 P18 大改:investment 三段按 intent 各自合理 filter
  ///   - 投入 (_intent='input'):source='cash_flow'(从现金投入)/ dest='investment'(到投资账户)
  ///     投入本质是 cash → investment 的流向,filter 引导 user 选对账户
  ///   - 调拨 (_intent='transfer'):不 filter(任意 ↔ 任意,user 自由选)
  ///   - 收益 (_intent='output'):source='investment'(只有投资账户才能产生收益)
  ///     / dest=null(单账户,没有 destination)
  ///   - cash_flow:source 用 widget.accountTypeFilter(caller 决定);dest=null
  ///
  /// 2026-10-13 P17 UAT 中途方案:investment 全部不 filter(投入也要 source=cash 限制的 user
  ///   反馈反复改,P18 三段分开后恢复 P8 的合理限制
  ///
  /// 2026-10-14 D51 v3:债务段调拨段不 filter(转出/转入都能选 现金 + 债务)
  ///   借出/借入段仍走 caller 默认(preselectedAssetType='receivable',只显示 债务账户)
  /// 2026-10-14 D57 改:"其它" 段只显示 other 类型账户
  ///   - 之前 D55 想"6 大类账户都能选",user 反馈太复杂,改成跟福利同样的简化结构
  ///   - 其它 = 兜底简化,只显示 asset.type='other' 的账户(_accountTypeFilter='other')
  /// 2026-10-14 D58 改:类型 `String?` → `List<String>?`,支持多类型白名单
  ///   - 之前 D51 v3 债务调拨不限类型 → D58 user 推翻,改限定 cash_flow ↔ receivable,
  ///     picker 要能传"白名单多 type"(同 D50 互斥仍适用)
  ///   - 各 path 返单元素 list 而不是裸 string,统一 list 协议
  /// 2026-10-14 D59 加:cash_flow 支出段允许 source 选 receivable 账户(信用卡/花呗场景)
  ///   - user:"在记一笔现金流中可以选择的支出账号增加债务的资产"
  ///   - 信用卡/花呗 是超前消费,本质是"支出但付款来源是负债账户"
  ///   - balance -= amount(扣到更负 = 欠款增加,D49 校验例外已覆盖)
  ///   - 走 cash_flow 支出段,cat 正常选真实分类(餐饮/购物等),报表分类统计准
  ///   - 收入段保持 cash_flow 不变(信用卡收款语义错位,不允许)
  ///   - 调拨段已被 D58 限定 cash_flow ↔ receivable(跟支出独立,无影响)
  List<String>? get _accountTypeFilter {
    if (_isInvestmentContext) {
      switch (_intent) {
        case 'input':
          return ['cash_flow']; // 投入:转出限现金账户
        case 'output':
          return ['investment']; // 收益:单账户限投资账户
        case 'transfer':
          return null; // 调拨:不限制
      }
    }
    if (_isReceivableContext && _intent == 'transfer') {
      // D58:user 推翻 D51 v3 改限定 cash_flow ↔ receivable,转出/转入都按此
      //   之前的 v3 不限太松(能选投资/福利/不动产/其它,语义错位)
      return ['cash_flow', 'receivable'];
    }
    if (widget.preselectedAssetType == 'cash_flow' && _intent == 'expense') {
      // D59:cash_flow 支出段允许 source 选 receivable(信用卡/花呗)
      //   - 之前:['_accountTypeFilter'] = ['cash_flow'] → 只显示现金账户
      //   - 现在:['_cash_flow', 'receivable'] → 现金账户 + 信用卡/花呗
      //   - D49 余额校验例外已覆盖(receivable 跳过),balance 扣到更负 = 负债增加
      //   - 跟 D51 lend/borrow 语义不冲突 —— receivable 段保留给"我借出去/借入现金"用,
      //     信用卡消费走 cash_flow 支出段,语义更自然("花出去"对应"支出")
      return ['cash_flow', 'receivable'];
    }
    if (widget.accountTypeFilter != null) {
      return [
        widget.accountTypeFilter!,
      ]; // cash_flow / benefit / receivable / other:caller 决定
    }
    return null;
  }

  List<String>? get _destinationTypeFilter {
    if (_isInvestmentContext) {
      switch (_intent) {
        case 'input':
          return ['investment']; // 投入:转入限投资账户
        case 'output':
          return null; // 收益:无 destination
        case 'transfer':
          return null; // 调拨:不限制
      }
    }
    if (_isReceivableContext && _intent == 'transfer') {
      // D58:跟 _accountTypeFilter 同步,转入也限定 cash_flow ↔ receivable
      return ['cash_flow', 'receivable'];
    }
    return null; // cash_flow:无 destination
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _onKey(String key) {
    // 个人记账上限:9,999,999.99(≈ 10 百万)
    // 上限由"语义"决定(7 位整数 + 小数点 + 2 位小数),而不是字符数:
    //   - 长度限制会被"9999999999"(10 位整数=99 亿)等绕开,远超业务上限
    //   - 真正的上限是数学意义上的绝对值,所以按整/小数位分别判断
    // 负号由 ± 单独处理,不影响整/小数位判断
    setState(() {
      if (key == 'C') {
        _calc.display = '0';
        _calc.expression = '';
        _calc.previousValue = null;
        _calc.pendingOp = null;
        _calc.justEvaluated = false;
        return;
      }
      if (key == '⌫') {
        if (_calc.justEvaluated) {
          _calc.display = '0';
          _calc.justEvaluated = false;
          return;
        }
        if (_calc.display.length > 1) {
          _calc.display = _calc.display.substring(0, _calc.display.length - 1);
          if (_calc.display == '-') _calc.display = '0';
        } else {
          _calc.display = '0';
        }
        return;
      }
      if (key == '%') {
        final v = double.tryParse(_calc.display) ?? 0;
        _calc.display = _formatNumber(v / 100);
        _calc.justEvaluated = true;
        return;
      }
      if (key == '±') {
        if (_calc.display.startsWith('-')) {
          _calc.display = _calc.display.substring(1);
        } else if (_calc.display != '0') {
          _calc.display = '-${_calc.display}';
        }
        return;
      }
      if ('+-×÷'.contains(key)) {
        if (_calc.pendingOp != null && !_calc.justEvaluated) {
          _evaluate();
        }
        _calc.previousValue = double.tryParse(_calc.display);
        _calc.pendingOp = key;
        _calc.justEvaluated = false;
        _calc.expression = '${_formatNumber(_calc.previousValue ?? 0)} $key';
        _calc.display = '0';
        return;
      }
      if (key == '=') {
        _evaluate();
        return;
      }
      // 数字 / 小数点
      if (_calc.justEvaluated) {
        _calc.display = '0';
        _calc.justEvaluated = false;
      }
      if (key == '.' && _calc.display.contains('.')) return;
      // 语义上限:7 位整数 + 2 位小数 = 9999999.99
      // 负号前缀不影响位数(由 ± 单独维护),只剥离后判断数字部分
      const maxIntegerDigits = 7;
      const maxFractionDigits = 2;
      // 数字键按当前是否已含小数点判断是限制整数位还是小数位
      if (RegExp(r'^[0-9]$').hasMatch(key)) {
        final s = _calc.display.startsWith('-')
            ? _calc.display.substring(1)
            : _calc.display;
        final dotIdx = s.indexOf('.');
        if (dotIdx == -1) {
          if (s.length >= maxIntegerDigits) return; // 整数位已满
        } else {
          final fracLen = s.length - dotIdx - 1;
          if (fracLen >= maxFractionDigits) return; // 小数位已满
        }
      }
      if (_calc.display == '0' && key != '.') {
        _calc.display = key;
      } else {
        // 必须用花括号:'$_calc.display' 会被 linter 当作 _calc.toString() + ".display",
        // 触发文件头的"字符串插值陷阱"。_calc.display 是 String 拼接,加花括号强制语义。
        // ignore: unnecessary_brace_in_string_interps
        _calc.display = '${_calc.display}${key}';
      }
    });
  }

  void _evaluate() {
    if (_curr.previousValue == null || _curr.pendingOp == null) return;
    final cur = double.tryParse(_curr.display) ?? 0;
    double result;
    switch (_curr.pendingOp) {
      case '+':
        result = _curr.previousValue! + cur;
        break;
      case '-':
        result = _curr.previousValue! - cur;
        break;
      case '×':
        result = _curr.previousValue! * cur;
        break;
      case '÷':
        if (cur == 0) {
          _toast('除数不能为 0');
          return;
        }
        result = _curr.previousValue! / cur;
        break;
      default:
        return;
    }
    // 计算结果超出 9999999.99 → 显示"超出范围"
    if (result.abs() > 9999999.99 || result.isNaN || result.isInfinite) {
      _curr.expression = '';
      _curr.display = '超出范围';
      _curr.previousValue = null;
      _curr.pendingOp = null;
      _curr.justEvaluated = true;
      return;
    }
    _curr.expression =
        '${_formatNumber(_curr.previousValue!)} ${_curr.pendingOp} ${_formatNumber(cur)} =';
    _curr.display = _formatNumber(result);
    _curr.previousValue = null;
    _curr.pendingOp = null;
    _curr.justEvaluated = true;
  }

  // 简化 alias,防止多次 _curr 前缀写错
  _CalcState get _curr => _calc;

  String _formatNumber(double v) {
    if (v == v.truncateToDouble() && v.abs() < 1e15) {
      return v.toInt().toString();
    }
    var s = v.toStringAsFixed(6);
    // 去掉尾随 0 和无意义的小数点
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  Future<void> _save() async {
    final value = double.tryParse(_calc.display);
    if (value == null || value <= 0) {
      _toast('金额要大于 0');
      return;
    }
    // 2026-10-13 P8:分类只在 cash_flow 必需;investment 不需要分类
    if (_needsCategory && _categoryId == null) {
      _toast('选个分类');
      return;
    }
    if (_accountId == null) {
      // 2026-10-16 D64.72 修:删"P2 阶段兜底 _firstCashAssetId"旧注释
      //   - 该方法在当前代码不存在,留着 grep 误导
      //   - 实际行为就是 _toast 提示 user,assets 空时 repo.add 会抛 StateError
      _toast('先在"我的"里建账户');
      return;
    }
    // 2026-10-13 P8:investment 场景必须同时填转入账户,否则 banner 提示
    if (_needsDualAccount && _destinationAccountId == null) {
      _toast('选个转入账户');
      return;
    }
    // 2026-10-14 P18 D49:余额校验 —— 转出类流水 source 账户余额不足时阻断
    //   - 转出类:_type ∈ {'expense', 'balance'}(现金支出 / 调拨 / 投资投入 / 投资调拨)
    //   - 所有非 负债 类型账户(source)必校验:日常现金流出不能超过实际余额
    //     之前只校验 cash_flow,user 反馈投资调拨时 source 投资账户可以扣成负数
    //     (P18 D34 当时考虑"投资市值波动 user 自负责",但 user UAT 明确不接受 ——
    //      任何"扣款"动作都不允许出负数,跟"市值波动"是另一个维度)
    //   - 负债 (receivable) 不校验:负债账户语义是"我欠的",余额正常为负,
    //     调拨 / 支出时继续扣到更负代表"我多欠了",逻辑正确
    //   - type='income'(现金收入 / 投资收益)不校验:账户增加,无上限
    //   - 编辑模式:只有金额变化时校验,其它情况跳过(因为余额已变化过)
    final isTransferOut = _type == 'expense' || _type == 'balance';
    if (isTransferOut) {
      final repo = ref.read(assetRepositoryProvider);
      final sourceAsset = await repo.byId(_accountId!);
      if (sourceAsset != null && sourceAsset.type != 'receivable') {
        final balances = await ref.read(assetBalancesProvider.future);
        final sourceBalance =
            balances[_accountId!] ?? sourceAsset.initialBalance;
        if (sourceBalance < value) {
          _toast(
            '${sourceAsset.name} 余额 ¥${sourceBalance.toStringAsFixed(2)} 不足',
          );
          return;
        }
      }
    }
    // 2026-10-13 P8:investment 场景下 DB transactions.categoryId NOT NULL 字段
    //   需要非空值,虽然 investment 不用分类。fallback 用任意一个有效 category id
    //   (DB schema 限制,语义上忽略)。后续如要彻底不要分类,需把 schema 改 nullable。
    final categoryForSave = _needsCategory
        ? _categoryId!
        : ((await _firstCategoryId()) ?? 0);
    final note = _noteController.text.isEmpty ? null : _noteController.text;
    // 2026-10-14 P18:投资收益单账户 → destinationAccountId 强制 null
    //   - _needsDualAccount=false(收益)→ destForSave=null,DB 只存 accountId
    //   - _needsDualAccount=true(投入/调拨)→ destForSave=_destinationAccountId,存 source→dest
    //   - cash_flow:始终 _needsDualAccount=false → 传 null(原本行为)
    final destForSave = _needsDualAccount ? _destinationAccountId : null;
    final repo = ref.read(transactionRepositoryProvider);
    try {
      if (_isEdit) {
        // 编辑:用原 id replace(Drift 的 replace 按主键 update)
        await repo.update(
          widget.editTransaction!.copyWith(
            amount: value,
            type: _type,
            categoryId: categoryForSave,
            accountId: _accountId!,
            // 2026-10-14 P18:按 _needsDualAccount 决定存不存 destinationAccountId
            destinationAccountId: Value(destForSave),
            occurredAt: _occurredAt,
            note: Value(note),
          ),
        );
        if (!mounted) return;
        _toast('已更新');
      } else {
        await repo.add(
          amount: value,
          type: _type,
          categoryId: categoryForSave,
          accountId: _accountId!,
          // 2026-10-14 P18:投资收益不传 destination(单账户);投入/调拨传
          destinationAccountId: destForSave,
          occurredAt: _occurredAt,
          note: note,
        );
      }
    } catch (e, st) {
      // 2026-10-12 bug:user 反馈"无法点击保存"
      //   - 现象:点击保存按钮后,UI 无任何反馈(banner 不显示,流水没保存),
      //     只有 logcat 一片 E/flutter 栈
      //   - 根因:drift InsertStatement.insert 抛 SqliteException(FOREIGN KEY /
      //     NOT NULL / UNIQUE 等约束失败),异常一路冒到 FilledButton 的
      //     onPressed closure,被 Flutter 框架捕获后打到 logcat,UI 层
      //     不知道发生了什么,banner 也不显示
      //   - 修法:包 try-catch
      //     1) developer.log 写完整 error + stackTrace 到 logcat
      //        (比 E/flutter 默认 stack 信息更全,方便后续定位)
      //     2) banner 显示 '保存失败:<exception 消息>'
      //        让 user 立即看到原因(FOREIGN KEY constraint failed / NOT NULL
      //        constraint failed / UNIQUE constraint failed ...)
      developer.log('保存失败', name: 'gridly.save', error: e, stackTrace: st);
      if (!mounted) return;
      _toast('保存失败:$e');
      return;
    }
    // 广谱刷新 —— 流水 / 首页 / 报表 / 分类页都同步更新
    refreshAllData(ref);
    if (!mounted) return;
    widget.onSaved?.call();
  }

  void _toast(String msg) {
    showGridlyBanner(context, msg, kind: GridlyBannerKind.warning);
  }

  Future<void> _pickDate() async {
    // 2026-10-11 UAT:系统 showDatePicker 满屏英文("Sun, Oct 11" / "Cancel")
    // + 卡片样式跟 gridly 不搭。换成自定义 CustomDatePickerSheet:
    //   - 全中文:年月日 / 快捷按钮 / 取消确定 / 周日一二三四五六
    //   - 卡片样式对齐 gridly(AppRadius.brXl + brand teal)
    //   - 顶部"今天/昨天/前天"快捷(覆盖记账 80% 场景)
    // 2026-10-15 D64.17:不传 lastDate,默认今天(记账场景不能选未来日期)
    final picked = await showCustomDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2020),
    );
    if (picked != null) {
      setState(() {
        _occurredAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _occurredAt.hour,
          _occurredAt.minute,
        );
      });
    }
  }

  void _openCategoryPicker() {
    // 2026-10-11 UAT 反馈:分类管理页加了新分类后,在记一笔的分类选择
    // 器里看不到。原因:之前这里 ref.read(provider) 拿到 picker 打开
    // 那一瞬间的快照(Snapshot),即使父级 _saveBar watch 的 invalidate
    // 已经触发,read 不会重新计算、也不会随新数据重建。
    // 修复:把 _CategoryPickerSheet 改成 ConsumerWidget,内部 watch 这个
    // provider。打开后 invalidate 完成的最新分类会自动出现在 grid 里。
    // 调用方只负责传 type + selected + onSelect,不再读 categories。
    //
    // 2026-10-14 简化:之前 receivable context 透传 forcedCategories(2 cat 选),
    //   现已跟福利/投资同 pattern(UI 隐藏 + 自动 fallback),不再需要选分类
    //   —— 这里不再处理 forcedCategories,picker 走默认 type filter
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      // 2026-10-13 P15 UAT 改:加 shape 圆角,跟 _openAccountPicker 一致
      //   之前漏了 → sheet 顶部直边跟其他 popup 视觉割裂
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _CategoryPickerSheet(
        type: _type,
        selected: _categoryId,
        onSelect: (id) {
          setState(() => _categoryId = id);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  // ============================================================
  // 2026-10-11 UAT 第三次重构 —— 单行操作栏:
  //   顶部:type toggle(支出/收入,很少切换,放最上面)
  //   中部:金额(大字,主视觉)
  //   操作行:[今天][分类][备注][保存] —— 一行内放完,贴近 Numpad,
  //         单手握机时拇指自然覆盖整个 row,不用抬手
  //   底部:Numpad(键盘区域固定)
  //   旧 _metaRow / _datePill / _categoryChip / _saveButton 全部弃用,
  //   单一 _actionRow 替代
  //
  // 2026-10-13 P7 UAT 改:操作行拆 2 行(4 items 一行挤爆 → 3+2 拆分)
  //   user 反馈:截图中 [今天][招...][选...][保存] 4 items 一行,
  //   pill 文字被 flex 吃掉变 "招..." / "选...",账户名根本显示不全。
  //   拆 2 行:
  //     第 1 行:[日期 pill][账户 pill][分类 pill]  —— 3 个等宽 Expanded
  //     第 2 行:[备注 TextField 弹性占满] [保存按钮固定宽度]
  //   - 长账户名(如"招商银行")在第 1 行通过 ellipsis 自然截断,不再被 flex 压扁
  //   - 备注独立在第 2 行,跟保存按钮并排,有充足输入空间
  // ============================================================

  /// ③两行操作栏(贴近 Numpad,单手拇指可达):
  ///   第 1 行:[日期 pill][账户 pill][分类 pill]  —— 3 个等宽 Expanded
  ///   第 2 行:[备注输入框(弹性占满)] [保存按钮(固定宽度 80)]
  Widget _actionRow(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // 2026-10-14 D45 改:cat chip 显示从 allCategoriesProvider 找,不依赖 _intent type filter
    //   - 之前用 categoriesByTypeProvider(_intent) 拿 cat,思路是 cash_flow 默认行为
    //     (cat.type='expense'/'income' 跟 _intent 1:1)
    //   - bug:multi-context 下 cat.type 不跟 _intent 对齐——
    //     receivable 的 cat.type='stock_option' / 'liability_loan',
    //     categoriesByTypeProvider('expense') / ('income') 都返回空 list,
    //     sel=null,chip 一直显示"选分类"(看上去像"选了 cat 没生效")
    //   - 实际 picker onSelect 真设了 _categoryId,DB 写入对的 cat_id
    //     —— 但因为 _actionRow 找不到 cat 显示,所以 user 看到"选了不显示"
    //   - 修:用 allCategoriesProvider 全表找,跟 _intent 维度脱钩
    //     picker 那边自己的 type filter 留给 categoriesByTypeProvider 用
    final allCats = ref.watch(allCategoriesProvider).valueOrNull ?? const [];
    Category? sel;
    for (final c in allCats) {
      if (c.id == _categoryId) {
        sel = c;
        break;
      }
    }
    final hasCat = sel != null;
    // 2026-10-12 P3 commit 加:账户 chip —— 监听 allAssetsProvider 取已选账户对象
    final assetsAsync = ref.watch(allAssetsProvider);
    Asset? selAccount;
    Asset? selDestAccount;
    assetsAsync.whenData((assets) {
      for (final a in assets) {
        if (a.id == _accountId) selAccount = a;
        if (a.id == _destinationAccountId) selDestAccount = a;
      }
    });
    final hasAccount = selAccount != null;
    final hasDestAccount = selDestAccount != null;
    final isToday =
        _occurredAt.year == DateTime.now().year &&
        _occurredAt.month == DateTime.now().month &&
        _occurredAt.day == DateTime.now().day;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s3,
        AppSpacing.s2,
        AppSpacing.s3,
        AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 2026-10-13 P7 UAT:第 1 行 —— 3 个等宽 pill
          // 2026-10-13 P8 UAT 改:按场景切 layout
          //  - cash_flow 非 balance:[日期][账户][分类]
          //  - cash_flow balance + investment 任意:[日期][转出][转入]
          if (_needsDualAccount)
            Row(
              children: [
                Expanded(
                  child: _ActionPill(
                    icon: Icons.calendar_today_rounded,
                    label: isToday
                        ? '今天'
                        : '${_occurredAt.month}月${_occurredAt.day}日',
                    highlighted: isToday,
                    highlightColor: AppBrand.teal,
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: _ActionPill(
                    icon: _assetIconFor(selAccount),
                    label: hasAccount ? selAccount!.name : '转出',
                    highlighted: hasAccount,
                    highlightColor: hasAccount
                        ? Color(selAccount!.color)
                        : null,
                    iconColorOverride: hasAccount
                        ? Color(selAccount!.color)
                        : null,
                    onTap: _openAccountPicker,
                  ),
                ),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: _ActionPill(
                    icon: _assetIconFor(selDestAccount),
                    label: hasDestAccount ? selDestAccount!.name : '转入',
                    highlighted: hasDestAccount,
                    highlightColor: hasDestAccount
                        ? Color(selDestAccount!.color)
                        : null,
                    iconColorOverride: hasDestAccount
                        ? Color(selDestAccount!.color)
                        : null,
                    onTap: _openDestinationAccountPicker,
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                // 1) 日期 pill
                Expanded(
                  child: _ActionPill(
                    icon: Icons.calendar_today_rounded,
                    label: isToday
                        ? '今天'
                        : '${_occurredAt.month}月${_occurredAt.day}日',
                    highlighted: isToday,
                    highlightColor: AppBrand.teal,
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: AppSpacing.s2),
                // 2) 账户 chip(P3 加)
                Expanded(
                  child: _ActionPill(
                    icon: _assetIconFor(selAccount),
                    label: hasAccount ? selAccount!.name : '选账户',
                    highlighted: hasAccount,
                    highlightColor: hasAccount
                        ? Color(selAccount!.color)
                        : null,
                    iconColorOverride: hasAccount
                        ? Color(selAccount!.color)
                        : null,
                    onTap: _openAccountPicker,
                  ),
                ),
                const SizedBox(width: AppSpacing.s2),
                // 3) 分类 chip(只在 _needsCategory 时显示)
                if (_needsCategory)
                  Expanded(
                    child: _ActionPill(
                      icon: hasCat
                          ? (CategoryIcons.map[sel.icon] ??
                                Icons.category_rounded)
                          : Icons.category_outlined,
                      label: hasCat ? sel.name : '选分类',
                      highlighted: hasCat,
                      highlightColor: hasCat ? Color(sel.color) : null,
                      iconColorOverride: hasCat ? Color(sel.color) : null,
                      onTap: _openCategoryPicker,
                    ),
                  ),
              ],
            ),
          const SizedBox(height: AppSpacing.s2),
          // 2026-10-13 P7 UAT:第 2 行 —— 备注输入框(弹性占满)+ 保存按钮(固定宽度)
          // 备注独立成 pill 容宽容器,跟上面 3 个 pill 风格统一(surfaceContainerLow + outlineVariant)
          // 内部 TextField 去掉自身 border,内容填满容器
          // 2026-10-13 P7 UAT 加:pill 投影,跟 TypeToggle + 上面 3 个 pill + 保存按钮立体感一致
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: AppRadius.brPill,
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                      width: 1,
                    ),
                    boxShadow: CardShadows.pill(context),
                  ),
                  child: TextField(
                    controller: _noteController,
                    maxLength: 30,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      hintText: '备注',
                      hintStyle: TextStyle(color: AppGray.g400, fontSize: 13),
                      prefixIcon: Icon(
                        Icons.edit_note_rounded,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s1,
                        vertical: AppSpacing.s2,
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s2),
              // 保存按钮(2026-10-13 P7:宽度从 64 提到 80,跟"短按"行展开视觉平衡)
              // 2026-10-13 P7 UAT 加:pill 投影,外层 Container 包 FilledButton 提供阴影
              // (FilledButton 自身 Material 3 默认 elevation=0,要立体感得手动加)
              Container(
                width: 80,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: AppRadius.brPill,
                  boxShadow: CardShadows.pill(context),
                ),
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(80, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.brPill,
                    ),
                  ),
                  child: const Text(
                    '保存',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
          // 2026-10-14 改(D42):仅 _intent='transfer' 才显示这条 tip
          //   - 2026-10-12 P3 commit 原条件是 _type == 'balance',P18 大改前
          //     只有 cash_flow 调拨 type='balance',没问题;P18 后投资"投入"
          //     _intent='input' / _intent='transfer' 都变成 type='balance',
          //     投入段也被误显"调拨:动资产,不算月度收支"误导成调拨
          //   - 修法:从 _type 改 _intent,只有 toggle 切到调拨段才提示
          //     - cash_flow 调拨 = _type='balance' + _intent='balance' = 文案准
          //     - 投资调拨 = _type='balance' + _intent='transfer' = 文案准
          //     - 投资投入 (_intent='input') / 投资收益 (_intent='output') = 不显示
          //   - 文案"调拨:动资产,不算月度收支"对真正调拨段都仍然准确
          //   - 用 onSurfaceVariant 中性色(提示性,非强调)
          if (_intent == 'transfer')
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s2),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '调拨:动资产,不算月度收支',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 2026-10-12 P3 commit 加:Asset icon 名 → IconData 转换
  /// 2026-10-16 D64.73 改:不再 inline 7 case switch,直接走 AssetTile.icons 集中表
  ///   - 之前是新加 icon key 时 3 处各改(asset_form_page / transaction_form /
  ///     transaction_tile);改成走集中表后只改 AssetTile.icons 一处
  ///   - 跟 ledger chip / 资产 form picker 视觉一致
  IconData _assetIconFor(Asset? a) {
    if (a == null) return Icons.account_balance_wallet_outlined;
    return AssetTile.icons[a.icon] ?? Icons.account_balance_wallet_rounded;
  }

  /// 2026-10-14 P18 重构:按 _intent 取对应 categoryId
  ///   - cash_flow → 用 _categoryId!(user 在 UI 必填)
  ///   - investment 投入/调拨(_intent='input'/'transfer')→ '投资投入' 分类
  ///   - investment 收益(_intent='output')→ '投资收益' 分类
  ///   - UI 隐藏:investment context 不显示分类选择器,user 看不到也选不到
  ///   - 之前 P8 一律 fallback 到 cash_flow 第一个分类(餐桌),导致投资 record 挂"餐饮"
  ///     显示在 cash_flow 流水里,语义错位
  ///   - DB schema NOT NULL 字段必须填,所以 fallback 是必要的,只是要选对分类
  /// 2026-10-14 加:福利场景 fallback 取 cat.type='benefit' 的第一个分类
  ///   - 跟 investment 同结构:UI 隐藏 + DB NOT NULL 字段必填,福利 1 个 cat 通用(支出/收入都 fallback 到它)
  /// 2026-10-14 D57 加:其它场景 fallback 取 cat.type='other' 的第一个分类
  ///   - 跟福利/债权同 pattern:UI 隐藏 cat,DB NOT NULL 通过 1 个内置 cat 兜底
  ///   - D56 旧版按账户 type 映射(6 类 cat 都考虑),D57 改成单一其它 cat
  Future<int?> _firstCategoryId() async {
    final repo = ref.read(categoryRepositoryProvider);
    final cats = await repo.all();
    if (cats.isEmpty) return null;
    if (_isInvestmentContext) {
      // 2026-10-14 P18:按 _intent 选投资分类,名字固定 seed 出来
      const investmentInName = '投资投入';
      const investmentOutName = '投资收益';
      final target = _intent == 'output' ? investmentOutName : investmentInName;
      for (final c in cats) {
        if (c.name == target) return c.id;
      }
      // seed 失败兜底(理论上 App 启动已 seed,不会走到这)
      return cats.first.id;
    }
    if (_isBenefitContext) {
      // 福利:取 cat.type='benefit' 的第一个分类(福利),seed 出来
      for (final c in cats) {
        if (c.type == 'benefit') return c.id;
      }
      // seed 失败兜底(同 investment)
      return cats.first.id;
    }
    if (_isReceivableContext) {
      // 债权:取 cat.type='liability' 的第一个分类(负债),seed 出来
      for (final c in cats) {
        if (c.type == 'liability') return c.id;
      }
      // seed 失败兜底(同 investment / benefit)
      return cats.first.id;
    }
    if (_isOtherContext) {
      // 2026-10-14 D57:其它:取 cat.type='other' 的第一个分类(其它),seed 出来
      for (final c in cats) {
        if (c.type == 'other') return c.id;
      }
      // seed 失败兜底(同 investment / benefit / receivable)
      return cats.first.id;
    }
    return cats.first.id;
  }

  /// 2026-10-12 P3 commit 加:账户选择 bottom sheet
  ///   - 类似 _openCategoryPicker,弹 modal sheet 显示所有账户列表
  ///   - 选完 → setState(_accountId) + pop
  /// 2026-10-13 P6 UAT 改:传 accountTypeFilter 给 sheet
  ///   - 短按 'cash_flow' → 只显示 cash_flow 账户
  ///   - 长按 'investment' → 只显示 investment 账户
  ///   - null → 不过滤,显示所有账户
  /// 2026-10-13 P8 UAT 改:investment 场景 _accountTypeFilter 优先(转出按 _intent 限定),
  ///   cash_flow 用 widget.accountTypeFilter(原有逻辑)
  void _openAccountPicker() {
    // 2026-10-14 D51 v4 修:source picker 过滤逻辑
    //   之前 `?? widget.accountTypeFilter` 会 fallback 到 caller 设的 'receivable',
    //   即便我在 _accountTypeFilter 返 null(债务调拨不过滤)也被覆盖
    //   改:用 _accountTypeFilter 优先;只在 _accountTypeFilter 返 null 时,
    //       fallback 到 widget.accountTypeFilter(包成单元素 list)
    //   实际效果:
    //   - 借出/借入段:_accountTypeFilter 返 ['receivable'] → 只看 债务账户(单账户操作)
    //   - 债务调拨段(D58):_accountTypeFilter 返 ['cash_flow', 'receivable'] → 限定这 2 类
    //   - 现金短按+:_accountTypeFilter 返 null → fallback 到 caller 'cash_flow'
    //   - 投资段:_accountTypeFilter 走投资 intent 限定(input=['cash_flow'], transfer=null)
    //   - 其它段:caller 默认 'other' → _accountTypeFilter 返 ['other'],显示 other 账户
    // 2026-10-14 D57 废:_isOtherContext 短路 —— D55 假设"6 大类可选",
    //   D57 改"只 other 账户",跟 caller 默认一致,不需要短路
    // 2026-10-14 D58 废:D51 v4 receivable transfer 短路 —— 现在 _accountTypeFilter
    //   本身返 List(['cash_flow', 'receivable']),不需要在 caller 端再覆盖
    final List<String>? filter =
        _accountTypeFilter ??
        (widget.accountTypeFilter == null ? null : [widget.accountTypeFilter!]);
    // 2026-10-15 D61:只有 cash_flow 段 + 支出 intent 走"充当现金流"过滤
    //   - 区分可消费债务(花呗/白条/信用卡,actAsCashFlow=true)和
    //     不可消费债务(车贷/房贷,actAsCashFlow=false)
    //   - 不可消费债务不应在 cash_flow 支出 picker 里出现(不可用 debt 付日常账)
    //   - receivable 段(借出/借入/调拨)picker 不传,显示所有 debt 账户(不影响)
    //   - 其它段(investment/benefit/other)picker 也不传
    final actAsCashFlowOnly =
        widget.preselectedAssetType == 'cash_flow' && _intent == 'expense';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      // 2026-10-14 D50:source picker 排除已选 dest
      //   调拨时 source = dest 是不合法(同一账户自转没意义,且会引发 balanceDelta 双重扣款)
      builder: (_) => _AccountPickerSheet(
        selected: _accountId,
        accountTypeFilter: filter,
        excludeId: _destinationAccountId,
        actAsCashFlowOnly: actAsCashFlowOnly,
        onSelect: (id) {
          setState(() => _accountId = id);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  /// 2026-10-13 P8 加:转入账户 picker(只 investment 场景使用)
  ///   - 按 _destinationTypeFilter 限定可选项
  ///   - null → 不过滤
  /// 2026-10-14 D50:dest picker 排除已选 source,user 反馈"如果原 A 选了,转入不能再出现 A"
  void _openDestinationAccountPicker() {
    final filter = _destinationTypeFilter;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _AccountPickerSheet(
        selected: _destinationAccountId,
        accountTypeFilter: filter,
        excludeId: _accountId,
        onSelect: (id) {
          setState(() => _destinationAccountId = id);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  /// ③ 金额块 —— 表达式(若有)+ 大金额(默认右对齐,跟数字键盘 Numpad 方向一致)
  Widget _amountBlock(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_calc.expression.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _calc.expression,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        AmountDisplay(amount: _calc.display, type: _type),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Numpad 始终固定在底部 —— 键盘弹起时被系统键盘覆盖(由 AddTransactionPage
    // 的 Scaffold.resizeToAvoidBottomInset=false 实现),不需要任何运行时检测。
    // 2026-10-11 UAT 最终方案:前 5 次尝试(保留 Numpad 高度 / MediaQuery 隐藏 /
    // FocusNode 隐藏 / Scaffold popUntil)都被推翻 —— 路线太复杂,改回最简单的:
    //   记金额 → Numpad 在,键盘不用
    //   写备注 → 键盘在,Numpad 被盖住(无所谓,写备注时用不到计算器)
    //   收键盘 → Numpad 回来
    // SafeArea(bottom: false) —— 关掉底部的 viewInsets/padding padding。
    // 原因:Scaffold.resizeToAvoidBottomInset=false 只挡 Scaffold 重排,
    // 但 SafeArea 默认会按 viewInsets.bottom 加底部 padding,
    // 结果键盘弹起时 Numpad 被顶起来(SafeArea 推上去),不被键盘覆盖。
    // 改 bottom: false 后 SafeArea 只挡 home indicator(由 padding.bottom 给),
    // 不挡键盘(由 viewInsets.bottom 给,但我们不要这个 padding)
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // 2026-10-11 UAT 三改:操作行单行化。
          // 上半区(type toggle + 金额)可滚动;
          // 下半区(_actionRow)是固定操作行,贴近 Numpad,
          // 拇指自然覆盖。
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ① type toggle(支出/收入,顶部居中)
                  //   2026-10-13 P6:allowBalance=false 时隐藏"调拨"段
                  //   - 短按路径(老版,默认 cash_flow):allowBalance=false → 2 段
                  //   - 长按路径(目前保留):allowBalance=true → 3 段
                  // 2026-10-13 P8:segments 由 caller 决定;cash_flow 用支出/收入/调拨,
                  //   investment 用投入/收益/调拨
                  // 2026-10-13 P8 UAT 改:切 toggle 时清掉 account / destAccount
                  //   user:"原有的已选的配置没有清空",换 toggle 后转出/转入
                  //   属于别的类,结果反了 → 切 toggle 时必须重置
                  // 2026-10-13 P16 UAT 改:cash_flow(支出↔收入)不清 _accountId
                  //   user:"切换支出收入的话,这个选账户还是会清空"
                  //   - cash_flow 是同 context 切 intent,账户类型不变,清掉反而要重选
                  //   - investment(input/output/transfer 跨段)仍清,避免残留的 source/dest 错位
                  // 2026-10-14 D44 改:切 toggle 时只清 cash_flow 的 _categoryId,其它 context 保留
                  //   - P16 UAT 原逻辑无条件清 _categoryId,理由:cash_flow 支出/收入的分类表
                  //     不同("餐饮"只在支出,"工资"只在收入),保留 cat 在另一边非法
                  //   - bug:receivable context 只有 2 个 cat(股份期权 / 负债借贷),2 cat 都支持
                  //     支出/收入方向。user 在 receivable context 切支出 → 收入时仍被清,
                  //     cat 视觉 chip 先显示 → toggle 一动就消失,user 看成"选了没生效"
                  //   - 修:receivable 不强制清,让 user 在支出/收入切换时保留 cat 选择
                  //   - cash_flow / 走原 P16 逻辑(强制清)
                  //   - investment 清 account / destAccount(原 P16 不变)
                  Align(
                    alignment: Alignment.center,
                    child: TypeToggle(
                      value: _intent,
                      segments: _toggleSegments,
                      onChanged: (v) => setState(() {
                        _intent = v;
                        // cash_flow 切支出 ↔ 收入,分类表不同,无效选择要清
                        // receivable 不清(2 cat 通用)
                        if (!_isReceivableContext) {
                          _categoryId = null;
                        }
                        // 2026-10-16 D64.79 改:切 toggle 统一按 _needsDualAccount 清双账户
                        //   - 之前仅 _isInvestmentContext 清 _accountId / _destinationAccountId,
                        //     receivable 调拨段(_isReceivableContext && _intent=='transfer')是
                        //     双账户但没清 → 残留 dest 跟 source/dest 互斥(D50)错配
                        //   - 改成统一条件:任何双账户 intent 切换都清 source + dest
                        if (_needsDualAccount) {
                          _accountId = null;
                          _destinationAccountId = null;
                        }
                        // cash_flow 短按+(_needsDualAccount=false):保留 _accountId(同 context 切 intent)
                      }),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  // ② 金额(主视觉,大)
                  _amountBlock(context),
                ],
              ),
            ),
          ),
          // ③ 单行操作栏:[今天] [分类] [备注] [保存]
          // 4 个 item 在一行内,贴近 Numpad,单手握机时拇指覆盖区
          _actionRow(context, ref),
          // 始终显示 —— 键盘弹起时由外层 Scaffold(resizeToAvoidBottomInset=false)
          // 让键盘自然覆盖此处。
          // 2026-10-11 UAT:外层 SafeArea(bottom:false) 把底部 padding 关了,
          // 键盘弹起时不会被顶上去,但代价是 Numpad 贴到屏幕底边、跟 iOS
          // 小白条(home indicator)叠在一起,最后一行数字(0 / . / 00 / =)
          // 几乎点不到。这里手动加 MediaQuery.padding.bottom,留出小白条
          // 高度的留白 —— 不影响键盘覆盖(键盘是 viewInsets.bottom,跟
          // padding.bottom 是两个独立维度,这里只读 padding 不读 viewInsets)。
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.s1,
              AppSpacing.s1,
              AppSpacing.s1,
              AppSpacing.s1 + MediaQuery.of(context).padding.bottom,
            ),
            child: Numpad(onKey: _onKey),
          ),
        ],
      ),
    );
  }
}

/// _actionRow 用的紧凑 pill 按钮 —— icon + label 单行展示
/// 配合不同 highlighted 状态(highlight color: teal/gold/分类色)区分语义
///
/// 2026-10-12 修:Hero flight 不再承接 chip(2026-10-12 UAT 反馈)。
/// 之前 chip 内 icon 包 Hero tag='tx-cat-${id}',但 tile 端 36x36 块飞到这里
/// 14px icon 形态不一致,落点视觉"挤"且 chip icon 跟飞行末态方块感觉重合。
/// 改成 tile → AppBar 右侧 36x36 块的承接点(同形态),chip 内 icon 不参与 Hero。
class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
    this.highlightColor,
    this.iconColorOverride,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;
  final Color? highlightColor;
  final Color? iconColorOverride;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = highlightColor ?? theme.colorScheme.onSurfaceVariant;
    final bg = highlighted
        ? accent.withValues(alpha: 0.10)
        : theme.colorScheme.surfaceContainerLow;
    final fg = highlighted ? accent : theme.colorScheme.onSurface;
    final iconColor =
        iconColorOverride ?? (highlighted ? accent : AppGray.g600);
    return InkWell(
      borderRadius: AppRadius.brPill,
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadius.brPill,
          border: Border.all(
            color: highlighted
                ? accent.withValues(alpha: 0.4)
                : theme.colorScheme.outlineVariant,
            width: 1,
          ),
          // 2026-10-13 P7 UAT 加:极轻 pill 投影,跟 TypeToggle + 保存按钮立体感统一
          // user:"想给切换以及所有按钮增加一点点投影"
          boxShadow: CardShadows.pill(context),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 4),
            // 2026-10-11 UAT 撤回居中:长分类名(如"吃吃喝喝必选")被
            // 居中后溢出 + ellipsis 切位,看起来"文字没居中"。改回左对齐,
            // icon + 文字紧贴左边,文字过长时自然尾部省略。
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分类选择底部 sheet —— 在 TransactionForm SaveBar 左侧点击时弹出。
///
/// 2026-10-11 UAT:从 StatelessWidget + 静态分类列表改成
/// ConsumerWidget + ref.watch(categoriesByTypeProvider(type))。原因:
/// 调用方 (TransactionForm._openCategoryPicker) 用 ref.read 拿一次性快照,
/// 即使父级 _saveBar watch 触发了 invalidate,read 不会重新计算 —— picker
/// 仍显示旧列表,在分类管理加新分类后这里看不到。改成 watch 后 invalidate
/// 完成时 picker 自动 rebuild 拿到最新分类。
class _CategoryPickerSheet extends ConsumerWidget {
  const _CategoryPickerSheet({
    required this.type,
    required this.selected,
    required this.onSelect,
  });
  final String type;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // 2026-10-14 简化:删除 forcedCategories 参数,reivable 段不再需要
    //   picker 强制传 2 cat(原 receiv 2 cat 设计) — 现在 receivable 跟福利/投资
    //   同样 UI 隐藏,1 个内置 cat 走自动 fallback,不再调 picker
    final catsAsync = ref.watch(categoriesByTypeProvider(type));
    // 2026-10-13 P14 UAT 改:DraggableScrollableSheet(0.6/0.3/0.9)→ 极值配置
    //   user:"不要做什么还能往上滑动的操作了"
    //   - max = 0.6 = initial → 上滑无效
    //   - min = 0.0 + snapSizes [0.0, 0.6] → 下拉能缩到 0 dismiss
    //   - GridView 4×3 = 12 项,初始 0.6 屏高刚好放下,scrollController 让超长 list 可滑
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.0,
      maxChildSize: 0.6,
      snap: true,
      snapSizes: const [0.0, 0.6],
      expand: false,
      builder: (context, scrollController) {
        // 2026-10-13 P15 UAT 改:不再套 Container(color: surface)
        //   showModalBottomSheet 已经设了 backgroundColor: surface,加 Container
        //   反而把外面 shape 的圆角盖住(方形铺满 sheet)
        //   去掉后 Column 透出 sheet 自身的 surface 背景 + 圆角 shape
        return catsAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.s4),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(AppSpacing.s4),
            child: Center(child: Text('加载失败:$e')),
          ),
          data: (cats) => LayoutBuilder(
            builder: (lctx, constraints) {
              final sheetHeight = constraints.maxHeight;
              const headerBlockHeight = 71.0;
              final showHeader = sheetHeight > headerBlockHeight;
              return Column(
                children: [
                  if (showHeader) ...[
                    // 把手
                    Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(top: 8, bottom: 12),
                      decoration: BoxDecoration(
                        color: AppGray.g400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // 标题 + 计数
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.s4,
                        0,
                        AppSpacing.s4,
                        AppSpacing.s2,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '选分类',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${cats.length} 个',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Expanded(
                    child: GridView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(AppSpacing.s4),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: AppSpacing.s2,
                            crossAxisSpacing: AppSpacing.s2,
                            childAspectRatio: 0.85,
                          ),
                      itemCount: cats.length,
                      itemBuilder: (context, i) {
                        final c = cats[i];
                        final isSelected = c.id == selected;
                        return InkWell(
                          borderRadius: AppRadius.brLg,
                          onTap: () => onSelect(c.id),
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.s2),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Color(c.color).withValues(alpha: 0.12)
                                  : theme.colorScheme.surfaceContainerLow,
                              borderRadius: AppRadius.brLg,
                              border: Border.all(
                                color: isSelected
                                    ? Color(c.color)
                                    : theme.colorScheme.outlineVariant,
                                width: isSelected ? 1.5 : 0.5,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  CategoryIcons.map[c.icon] ??
                                      Icons.category_rounded,
                                  color: Color(c.color),
                                  size: 26,
                                ),
                                const SizedBox(height: AppSpacing.s1),
                                Text(
                                  c.name,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// 2026-10-12 P3 commit 加:账户选择底部 sheet(列表模式,不像分类用 grid)
///   - 顶部把手 + 标题"选账户" + 计数
///   - 每行:icon + name + type chip + currentBalance(右对齐)
///   - 选中态:左侧 / 整行高亮 + check icon
///   - 空态:引导用户去"我的"建账户
///
/// 2026-10-13 P8 UAT 改:maxHeight 限 + 滑动
///   - user:"调拨 = 所有 ↔ 所有,这个 popup 太高了",全选 10+ 帐户
///     原 Column 自适应内容高度,isScrollControlled=true 不限高 → sheet
///     站屏幕 87%
///   - ConstrainedBox(maxHeight: 0.65 * screenHeight) 限 sheet 高
///     超出内容 ListView 内部滑动
///
/// 2026-10-13 P10 UAT 改:ConstrainedBox → DraggableScrollableSheet(跟 ledger
///   MultiSelectCategorySheet / MultiSelectAssetSheet 同款,初值 0.7 / min 0.5
///   / max 0.9)。user 可拖 sheet 调大小 + ListView 内部滑动,行为更接近
///   ColorOS Aquamorphic(那边 modal sheet 都支持拖拽调整高度)
///   - 调拨无"全部"概念 → 底部不加"显示全部"按钮(只有多选 + 有
///     AllPicked 选项的 sheet 才需要)
///
/// 2026-10-13 P14 UAT 改:DraggableScrollableSheet(0.7/0.5/0.9)→ 极值配置
///   同 P12-3 类型/月份/分类 picker
///   - max = 0.7 = initial → 上滑无效
///   - min = 0.0 + snapSizes [0.0, 0.7] → 下拉缩到 0 dismiss
///   - ListView scrollController 协调手势:list top 拖下 bubble 到 sheet 关
class _AccountPickerSheet extends ConsumerWidget {
  const _AccountPickerSheet({
    required this.selected,
    required this.onSelect,
    this.accountTypeFilter,
    this.excludeId,
    this.actAsCashFlowOnly = false,
  });
  final int? selected;
  final ValueChanged<int> onSelect;

  /// 2026-10-13 P6 UAT 改:按 type 过滤账户
  ///   - 单值:['cash_flow'] → 只显示 cash_flow 账户
  ///   - 多值:['cash_flow', 'receivable'] → 显示这 2 类账户(D58 债务调拨用)
  ///   - null → 不过滤,显示所有账户
  /// 2026-10-14 D58 改:从 `String?` → `List<String>?`,支持多类型过滤
  ///   - 之前 D51 v3 债务调拨不限类型 → D58 改限定 cash_flow ↔ receivable,
  ///     picker 需要支持"白名单多个 type"
  final List<String>? accountTypeFilter;

  /// 2026-10-14 D50:排除指定账户(给调拨 source / dest 互斥用)
  ///   - source picker 传 _destinationAccountId(已选 dest 不能作 source)
  ///   - dest picker 传 _accountId(已选 source 不能作 dest)
  ///   - 同一账户自转没意义 + 会引发 balanceDelta 双重扣款 bug
  final int? excludeId;

  /// 2026-10-15 D61:receivable 段"充当现金流"过滤
  ///   - true:receivable 段账户需 actAsCashFlow=true 才显示(花呗/白条/信用卡等)
  ///   - false:receivable 段账户正常显示(包括不可消费债务)
  ///   - 只对 cash_flow 段 picker 有意义(_openAccountPicker 在该处传 true)
  ///   - receivable 段(借出/借入/调拨)picker 不传,走默认 false
  final bool actAsCashFlowOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final assetsAsync = ref.watch(allAssetsProvider);
    // 2026-10-15 D60.2:账户 sheet 里的余额数字也接 amountVisibilityProvider
    //   user UAT 反馈:"上锁之后,通过记一笔时选择账户时还能看到金额,这里也要隐藏"
    //   - 关闭"显示金额"时,这里 balance 走 •••••• 占位,跟 ledger / stats 一致
    final hidden = !ref.watch(amountVisibilityProvider);
    return SafeArea(
      child: assetsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.s4),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: Center(child: Text('加载失败:$e')),
        ),
        data: (assets) {
          // 2026-10-13 P6 UAT 改:按 accountTypeFilter 过滤
          // 2026-10-14 D50:再按 excludeId 排除(调拨 source / dest 互斥)
          // 2026-10-14 D58 改:accountTypeFilter 类型 String? → List<String>?,支持多类型
          //   白名单(membership check);null 不过滤,list 含 account.type 才显示
          // 2026-10-15 D61:actAsCashFlowOnly 过滤 receivable 段的"非可消费"账户
          //   - 区分花呗/白条(actAsCashFlow=true)vs 车贷/房贷(actAsCashFlow=false)
          //   - 只在 cash_flow 段 picker 启用(_openAccountPicker 传 true),
          //     receivable 段 picker 仍显示所有 debt 账户(不影响调拨/借出/借入)
          final filtered = assets.where((a) {
            if (accountTypeFilter != null &&
                !accountTypeFilter!.contains(a.type)) {
              return false;
            }
            if (actAsCashFlowOnly &&
                a.type == 'receivable' &&
                !a.actAsCashFlow) {
              return false;
            }
            if (excludeId != null && a.id == excludeId) {
              return false;
            }
            return true;
          }).toList();
          // 2026-10-13 P10 UAT 改:DraggableScrollableSheet(0.7/0.5/0.9)
          //   user 可拖 sheet 调大小 + ListView 内部滑动;同款 ledger
          //   MultiSelectCategorySheet / MultiSelectAssetSheet 结构
          //   调拨无"全部"概念 → 底部无 FilledButton
          // 2026-10-13 P14 UAT 改:极值配置,user:"不要做什么还能往上滑动的操作了"
          //   - max = 0.7 = initial → 上滑无效
          //   - min = 0.0 + snapSizes [0.0, 0.7] → 下拉缩到 0 dismiss
          //   - ListView scrollController 协调手势:list top 拖下 bubble 到 sheet 关
          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.0,
            maxChildSize: 0.7,
            snap: true,
            snapSizes: const [0.0, 0.7],
            expand: false,
            builder: (ctx, scrollController) {
              // 2026-10-14 D52:修 RenderFlex overflow
              //   user 反馈:"popup 往下滑到底的时候,出现 overflow"
              //   根因:DraggableScrollableSheet snap 到 0.0 时,可用高度 ~0,
              //     Column 非 Expanded 子项(handle 24 + header 38 + divider 1 = 63)总高 > 可用
              //     → RenderFlex 报 OVERFLOWING(yellow black stripe)
              //   修:用 LayoutBuilder 拿可用高度,够装下 header 才显示
              //     不够时全隐藏,让 ListView(Expanded)接管,自然 dismiss 路径
              return LayoutBuilder(
                builder: (lctx, constraints) {
                  final sheetHeight = constraints.maxHeight;
                  // 阈值 = handle(24) + header(38) + divider(1) + buffer(8)
                  const headerBlockHeight = 71.0;
                  final showHeader = sheetHeight > headerBlockHeight;
                  return Column(
                    children: [
                      if (showHeader) ...[
                        Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(top: 8, bottom: 12),
                          decoration: BoxDecoration(
                            color: AppGray.g400,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.s4,
                            0,
                            AppSpacing.s4,
                            AppSpacing.s2,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '选账户',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${filtered.length} 个',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                      Expanded(
                        child: filtered.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.s4,
                                  AppSpacing.s4,
                                  AppSpacing.s4,
                                  AppSpacing.s5,
                                ),
                                child: Text(
                                  '还没有账户,请先到"我的 > 资产"新建',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final a = filtered[i];
                                  final isSelected = a.id == selected;
                                  final color = Color(a.color);
                                  final balanceAsync = ref.watch(
                                    assetBalanceProvider(a.id),
                                  );
                                  final balance =
                                      balanceAsync.valueOrNull ?? 0.0;
                                  return InkWell(
                                    onTap: () => onSelect(a.id),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.s4,
                                        vertical: AppSpacing.s3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? color.withValues(alpha: 0.10)
                                            : Colors.transparent,
                                        border: Border(
                                          bottom: BorderSide(
                                            color: theme
                                                .colorScheme
                                                .outlineVariant,
                                            width: 0.5,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: color.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius: AppRadius.brXs,
                                              border: Border.all(
                                                color: color.withValues(
                                                  alpha: 0.3,
                                                ),
                                                width: 0.5,
                                              ),
                                            ),
                                            child: Icon(
                                              _iconForAsset(a.icon),
                                              color: color,
                                              size: 18,
                                            ),
                                          ),
                                          const SizedBox(width: AppSpacing.s3),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  a.name,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                const SizedBox(height: AppSpacing.s05),
                                                Text(
                                                  AppSegment.labelFor(a.type),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            // 2026-10-15 D60.2:hidden 时用 •••••• 占位
                                            hidden
                                                ? '••••••'
                                                : '¥${Formatters.amount(balance)}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: hidden
                                                  ? theme
                                                        .colorScheme
                                                        .onSurfaceVariant
                                                  : AppSemantic.balanceFor(
                                                      balance,
                                                    ),
                                            ),
                                          ),
                                          if (isSelected) ...[
                                            const SizedBox(width: 8),
                                            Icon(
                                              Icons.check_circle_rounded,
                                              size: 18,
                                              color: color,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  IconData _iconForAsset(String iconKey) {
    switch (iconKey) {
      case 'credit_card':
        return Icons.credit_card_rounded;
      case 'savings':
        return Icons.savings_rounded;
      case 'payments':
        return Icons.payments_rounded;
      case 'account_balance':
        return Icons.account_balance_rounded;
      case 'home':
        return Icons.home_rounded;
      case 'directions_car':
        return Icons.directions_car_rounded;
      case 'swap_horiz':
        return Icons.swap_horiz_rounded;
      default:
        return Icons.account_balance_wallet_rounded;
    }
  }

  /// 2026-10-14 P18:Bug2 _typeLabel 补全 6 段翻译
  ///   之前只识别 cash_flow / fixed_asset / liability,其它 3 段(investment / benefit /
  ///   receivable / other)全 fallback 到'其他',导致选账户 picker 显示账户 type 标签错
  ///   (基金/黄金/保险都标'其他',实际是 investment 类型)
  ///
  /// 2026-10-16 D64.40:删除此重复 switch,改走 AppSegment.labelFor 统一数据源
  ///   - 之前 P18 因 AppSegment.labelFor 还没扩到 6 段,所以这里自己 switch
  ///   - 现在 AppSegment.labelFor 已扩到 6 段 + 'other' 兜底 + 'cash_flow'='流动资金' D64.40,
  ///     不需要本文件 hardcode 重复 switch
  ///   - 调用方 line 1845 已替换为 AppSegment.labelFor(a.type)
}
