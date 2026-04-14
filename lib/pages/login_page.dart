import 'package:flutter/material.dart';
import 'dart:math';
import 'package:tdesign_flutter/tdesign_flutter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _rememberPassword = true;
  bool _showPassword = false;

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Widget _buildWave({
    required String asset,
    required double opacity,
    double? bottom,
    required double width,
    double? top,
  }) {
    assert(top != null || bottom != null, 'top 和 bottom 不能同时为空');
    return Positioned(
      top: bottom != null ? null : top,
      bottom: top != null ? null : bottom,
      left: 0,
      right: 0,
      child: Opacity(
        opacity: opacity,
        child: Image.asset(asset, width: width, fit: BoxFit.fitWidth),
      ),
    );
  }

  /// 带下边框的输入行
  Widget _buildUnderlineField({
    required IconData icon,
    required Widget field,
  }) {
    return Container(
      height: 54,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFFBBBBBB)),
          const SizedBox(width: 12),
          Expanded(child: field),
        ],
      ),
    );
  }

  /// 账号输入框
  Widget _buildAccountField() {
    return _buildUnderlineField(
      icon: TDIcons.user,
      field: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _accountController,
              decoration: const InputDecoration(
                hintText: '请输入账号',
                hintStyle: TextStyle(color: Color(0xFFCCCCCC), fontSize: 15),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
            ),
          ),
          GestureDetector(
            onTap: () => _accountController.clear(),
            child: const Icon(TDIcons.close_circle_filled, size: 18, color: Color(0xFFCCCCCC)),
          ),
        ],
      ),
    );
  }

  /// 密码输入框
  Widget _buildPasswordField() {
    return _buildUnderlineField(
      icon: TDIcons.lock_on,
      field: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _passwordController,
              obscureText: !_showPassword,
              decoration: const InputDecoration(
                hintText: '请输入密码',
                hintStyle: TextStyle(color: Color(0xFFCCCCCC), fontSize: 15),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
            ),
          ),
          GestureDetector(
            onTap: () => _passwordController.clear(),
            child: const Icon(TDIcons.close_circle_filled, size: 18, color: Color(0xFFCCCCCC)),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _showPassword = !_showPassword),
            child: Icon(
              _showPassword ? TDIcons.browse : TDIcons.browse_off,
              size: 18,
              color: const Color(0xFFCCCCCC),
            ),
          ),
        ],
      ),
    );
  }

  /// 可点击选择行（环境 / 公司）
  Widget _buildSelectField({required IconData icon, required String value}) {
    return _buildUnderlineField(
      icon: icon,
      field: GestureDetector(
        onTap: () {},
        child: SizedBox(
          height: 54,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 15, color: Color(0xFF333333))),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final headerHeight = constraints.maxHeight * 0.4;
          final tailHeight = constraints.maxHeight * 0.12;
          final tailTop = constraints.maxHeight - tailHeight - 1;
          final waveBottom = constraints.maxHeight - headerHeight - 1;

          return Stack(
            children: [
              // ── 顶部渐变 ──
              Positioned(
                top: 0, left: 0, right: 0,
                height: headerHeight,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [Color(0xFF20D3CD), Color(0xFF646CFF)],
                      stops: [0.0, 0.8],
                    ),
                  ),
                ),
              ),
              // ── 底部渐变 ──
              Positioned(
                left: 0, right: 0, bottom: 0,
                height: tailHeight,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [Color(0xFF20D3CD), Color(0xFF646CFF)],
                      stops: [0.0, 0.8],
                    ),
                  ),
                ),
              ),
              // ── 顶部波浪 ──
              _buildWave(asset: 'assets/images/wave-03.png', opacity: 0.15, bottom: waveBottom, width: constraints.maxWidth),
              _buildWave(asset: 'assets/images/wave-02.png', opacity: 0.2,  bottom: waveBottom, width: constraints.maxWidth),
              _buildWave(asset: 'assets/images/wave-01.png', opacity: 1,    bottom: waveBottom, width: constraints.maxWidth),
              // ── 底部波浪（翻转） ──
              Transform.rotate(
                angle: pi,
                child: Stack(children: [
                  _buildWave(asset: 'assets/images/wave-03.png', opacity: 0.15, bottom: tailTop, width: constraints.maxWidth),
                  _buildWave(asset: 'assets/images/wave-02.png', opacity: 0.15, bottom: tailTop, width: constraints.maxWidth),
                  _buildWave(asset: 'assets/images/wave-01.png', opacity: 1,    bottom: tailTop, width: constraints.maxWidth),
                ]),
              ),
              // ── Logo 居中于顶部渐变区 ──
              Positioned(
                top: 0, left: 0, right: 0,
                height: headerHeight - 20,
                child: Center(
                  child: Container(
                    width: 150,
                    height: 64,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/logo-icon.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              // ── 表单内容 ──
              Positioned(
                top: headerHeight + 8,
                left: 0, right: 0,
                bottom: tailHeight + 8,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildAccountField(),
                      _buildPasswordField(),
                      _buildSelectField(icon: TDIcons.view_list, value: '内部'),
                      _buildSelectField(icon: TDIcons.shop, value: '[008]纪州喷码技术（上海）有限公司'),
                      const SizedBox(height: 18),
                      // 记住密码 + 配置服务
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => setState(() => _rememberPassword = !_rememberPassword),
                            child: Row(
                              children: [
                                Container(
                                  width: 20, height: 20,
                                  decoration: BoxDecoration(
                                    color: _rememberPassword ? const Color(0xFF646CFF) : Colors.white,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: _rememberPassword ? const Color(0xFF646CFF) : const Color(0xFFCCCCCC),
                                    ),
                                  ),
                                  child: _rememberPassword
                                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                                      : null,
                                ),
                                const SizedBox(width: 6),
                                const Text('记住密码', style: TextStyle(fontSize: 13, color: Color(0xFF646CFF))),
                              ],
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {},
                            child: const Text('配置服务', style: TextStyle(fontSize: 13, color: Color(0xFF646CFF))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      // 渐变登录按钮
                      GestureDetector(
                        onTap: () {},
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(25),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF646CFF), Color(0xFF20D3CD)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                          ),
                          child: const Center(
                            child: Text(
                              '登录',
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
