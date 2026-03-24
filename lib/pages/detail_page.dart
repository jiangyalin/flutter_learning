import 'package:flutter/material.dart';

/// 详情页示例
/// 类比 Vue 的 views/DetailPage.vue
class DetailPage extends StatelessWidget {
  const DetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('详情页'),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.star, size: 64, color: Colors.amber),
            SizedBox(height: 16),
            Text(
              '这是详情页',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('从首页点击按钮跳转过来的', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

