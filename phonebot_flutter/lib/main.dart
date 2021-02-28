import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';

void main() {
  runApp(PhonebotApp());
}

class PhonebotApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(primaryColor: Colors.blueGrey),
      home: FindDevicesScreen(),
    );
  }
}

class FindDevicesScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Find Devices'),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            FlutterBlue.instance.startScan(timeout: Duration(seconds: 4)),
        child: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              // List of connected devices
              StreamBuilder<List<BluetoothDevice>>(
                stream: Stream.periodic(Duration(seconds: 2))
                    .asyncMap((_) => FlutterBlue.instance.connectedDevices),
                initialData: [],
                builder: (c, snapshot) => Column(
                  children: snapshot.data
                      .map((d) => ListTile(title: Text(d.name)))
                      .toList(),
                ),
              ),
              // List of not yet connected devices. Only list devices
              // which have a non-empty name.
              StreamBuilder<List<ScanResult>>(
                stream: FlutterBlue.instance.scanResults,
                initialData: [],
                builder: (c, snapshot) {
                  final rowData = snapshot.data
                      .where((d) => d.device.name.length > 0)
                      .map((r) => DeviceRow(result: r))
                      .toList();
                  final rowList = ListView.separated(
                      scrollDirection: Axis.vertical,
                      shrinkWrap: true,
                      itemBuilder: (BuildContext context, int index) {
                        return Container(child: rowData[index]);
                      },
                      separatorBuilder: (BuildContext context, int index) =>
                          Divider(
                            height: 0,
                          ),
                      itemCount: rowData.length);

                  return rowList;
                  // return Column(children: rowData);
                },
              )
            ],
          ),
        ),
      ),
      floatingActionButton: StreamBuilder<bool>(
        stream: FlutterBlue.instance.isScanning,
        initialData: false,
        builder: (c, snapshot) {
          if (snapshot.data) {
            return FloatingActionButton(
              child: Icon(Icons.stop),
              onPressed: () => FlutterBlue.instance.stopScan(),
              backgroundColor: Colors.red,
            );
          } else {
            return FloatingActionButton(
                child: Icon(Icons.search),
                onPressed: () => FlutterBlue.instance
                    .startScan(timeout: Duration(seconds: 4)));
          }
        },
      ),
    );
  }
}

class DeviceRow extends StatelessWidget {
  const DeviceRow({Key key, this.result, this.fontSize = 24, this.padding = 8})
      : super(key: key);

  final double padding;
  final double fontSize;
  final ScanResult result;

  @override
  Widget build(BuildContext context) {
    return InkWell(
        onTap: () {
          final snackBar = SnackBar(content: Text("Connecting"));
          ScaffoldMessenger.of(context).showSnackBar(snackBar);
        },
        child: Column(
          children: <Widget>[
            Padding(
                padding: EdgeInsets.all(padding),
                child: Column(children: [
                  Row(children: <Widget>[
                    Text(result.device.name,
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: fontSize)),
                  ]),
                  Row(children: [Text(result.device.id.toString())]),
                ])),
          ],
        ));
  }
}
