import 'package:flutter/material.dart';
import '../../widgets/main_scaffold.dart';
import '../tqr/tqr_connect_page.dart'; // import

class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MainScaffold(
      selectedIndex: 1,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(0),
            // child: Text(
            //   'Welcome to TqrConnect!',
            //   style: Theme.of(context).textTheme.headlineSmall,
            // ),
          ),
          Expanded(child: TqrConnectPage()), // 👈 embed the page
        ],
      ),
    );
  }
}
