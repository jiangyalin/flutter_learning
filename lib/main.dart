import 'package:flutter/material.dart';
import 'pages/detail_page.dart';
import 'pages/login_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // 使用本地系统字体，避免 Web 端请求 Google Fonts（fonts.gstatic.com）。
        fontFamily: 'Arial',
        fontFamilyFallback: const <String>[
          'PingFang SC',
          'Hiragino Sans GB',
          'Microsoft YaHei',
          'sans-serif',
        ],
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // 跳转到详情页按钮，类比 Vue 的 this.$router.push('/detail')
          FloatingActionButton.extended(
            heroTag: 'nav',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DetailPage()),
              );
            },
            label: const Text('去详情页'),
            icon: const Icon(Icons.arrow_forward),
          ),
          // 登录
          FloatingActionButton.extended(
            heroTag: 'nav',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LoginPage()),
              );
            },
            label: const Text('去登录页'),
            icon: const Icon(Icons.arrow_forward),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'counter',
            onPressed: _incrementCounter,
            tooltip: 'Increment',
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
