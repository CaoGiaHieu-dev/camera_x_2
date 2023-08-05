import 'package:flutter/material.dart';
import 'package:mobile_scanner_example/barcode_scanner_returning_image.dart';

void main() => runApp(const MaterialApp(home: MyHome()));

class MyHome extends StatelessWidget {
  const MyHome({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter Demo Home Page')),
      body: SizedBox(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        child: Center(
          child: ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const BarcodeScannerReturningImage(),
                ),
              );
            },
            child: const Text('Start'),
          ),
        ),
      ),
    );
  }
}
