import 'package:flutter/material.dart';
import 'dart:math';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

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
        child: Image.asset(
          asset,
          width: width,
          fit: BoxFit.fitWidth,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final headerHeight = constraints.maxHeight * 0.4;
          final tailHeight = constraints.maxHeight * 0.12;
          final tailTop = constraints.maxHeight - tailHeight - 1;
          final waveBottom = constraints.maxHeight - headerHeight - 1;
          final pageWidthText =
              '这是登录页3 ${constraints.maxWidth.toStringAsFixed(0)}';

          return Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: headerHeight,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [
                        Color(0xFF20D3CD),
                        Color(0xFF646CFF),
                      ],
                      stops: [0.0, 0.8],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: tailHeight,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [
                        Color(0xFF20D3CD),
                        Color(0xFF646CFF),
                      ],
                      stops: [0.0, 0.8],
                    ),
                  ),
                ),
              ),
              _buildWave(
                asset: 'assets/images/wave-03.png',
                opacity: 0.15,
                bottom: waveBottom,
                width: constraints.maxWidth,
              ),
              _buildWave(
                asset: 'assets/images/wave-02.png',
                opacity: 0.2,
                bottom: waveBottom,
                width: constraints.maxWidth,
              ),
              _buildWave(
                asset: 'assets/images/wave-01.png',
                opacity: 1,
                bottom: waveBottom,
                width: constraints.maxWidth,
              ),
              Transform.rotate(
                angle: pi,
                child: Stack(
                  children: [
                    _buildWave(
                      asset: 'assets/images/wave-03.png',
                      opacity: 0.15,
                      bottom: tailTop,
                      width: constraints.maxWidth,
                    ),
                    _buildWave(
                      asset: 'assets/images/wave-02.png',
                      opacity: 0.15,
                      bottom: tailTop,
                      width: constraints.maxWidth,
                    ),
                    _buildWave(
                      asset: 'assets/images/wave-01.png',
                      opacity: 1,
                      bottom: tailTop,
                      width: constraints.maxWidth,
                    ),
                  ]
                )
              ),
              Center(
                child: Text(
                  pageWidthText,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue,
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
