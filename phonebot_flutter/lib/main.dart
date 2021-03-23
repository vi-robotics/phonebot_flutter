import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

// class DummyScreen extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     FlutterBlue flutterBlue = FlutterBlue.instance;
//     flutterBlue.startScan(timeout: Duration(seconds: 4));

//     // Listen to scan results
//     var subscription = flutterBlue.scanResults.listen((results) async {
//       // do something with scan results
//       for (ScanResult r in results) {
//         if (r.device.name.contains("PhoneBot")) {
//           print('${r.device.name} found! rssi: ${r.rssi}');
//           // Connect to device, send some info, and disconnect
//           PhoneBotController pc = PhoneBotController(device: r.device);
//           flutterBlue.stopScan();

//         }
//       }
//     }).onDone(() { });

//     subscription.cancel();

//     await pc.connect();
//     print("Connected");
//     await pc.openStream();
//     print("Stream Open");
//     await pc.setLegs();
//     print("Legs set I guess?");
//     await pc.disconnect();
//     return;
//     // final btmang = PhoneBotController();
//     return Container();
//   }
// }

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
                  children: snapshot.data.map((d) => Text(d.name)).toList(),
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

class PhoneBotScreen extends StatelessWidget {
  const PhoneBotScreen({Key key, this.device}) : super(key: key);

  final BluetoothDevice device;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(device.name)),
      body: Column(
        children: [
          Row(
            children: [Text("Signal Strength: ")],
          )
        ],
      ),
    );
  }
}

class DeviceRow extends StatelessWidget {
  const DeviceRow({Key key, this.result, this.fontSize = 24, this.padding = 8})
      : super(key: key);

  // final VoidCallback onTap;
  final double padding;
  final double fontSize;
  final ScanResult result;

  @override
  Widget build(BuildContext context) {
    return InkWell(
        onTap: () async {
          if (result.advertisementData.connectable) {
            await result.device.connect();
            print("Connected...");
            await result.device.discoverServices();

            PhoneBotController pc = PhoneBotController(device: result.device);

            await pc.connect();
            print("Connected");
            await pc.openStream();
            print("Stream Open");
            await pc.setLegs();
            await pc.setLegs(frontLeftA: 60);
            await pc.setLegs(frontLeftA: 120);
            print("Legs set I guess?");
            await pc.disconnect();

            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => PhoneBotScreen(device: result.device)));
          } else {
            final snackBar =
                SnackBar(content: Text("Device isn't connectable."));
            ScaffoldMessenger.of(context).showSnackBar(snackBar);
          }
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
                  Row(children: [
                    Text(result.device.id.toString()),
                    Spacer(),
                    Text('${result.advertisementData.txPowerLevel ?? 'N/A'}')
                  ]),
                ])),
          ],
        ));
  }
}

class PhoneBotCommand {
  static const int SET_LEG_POSITIONS = 0;
  static const int REQUEST_BATTERY_VOLTAGE = 1;
  static const int SET_DEVICE_NAME = 2;
}

class PhoneBotController {
  PhoneBotController({Key key, this.device});

  final BluetoothDevice device;
  BluetoothCharacteristic rxChar;

  static Guid transparentUartServiceUuid =
      Guid("49535343-fe7d-4ae5-8fa9-9fafd205e455");
  static Guid transparentUartTxCharUuid =
      Guid("49535343-1e4d-4bd9-ba61-23c647249616");
  static Guid transparentUartRxCharUuid =
      Guid("49535343-8841-43f4-a8d4-ecbe34729bb3");
  static Guid txCharacteristicConfiguration =
      Guid("00002902-0000-1000-8000-00805f9b34fb");

  List<BluetoothService> services;
  BluetoothService transparentUartService;

  List<int> legState = List<int>.filled(8, 90,
      growable: false); // The angles of the legs in degrees

  BluetoothService getService(
      Guid serviceUUID, List<BluetoothService> services) {
    for (BluetoothService service in services) {
      if (service.uuid == serviceUUID) {
        return service;
      }
    }
    return null;
  }

  BluetoothCharacteristic getCharacteristic(
      BluetoothService service, Guid characteristicUUID) {
    for (BluetoothCharacteristic char in service.characteristics) {
      if (char.uuid == characteristicUUID) {
        return char;
      }
    }
    return null;
  }

  BluetoothDescriptor getDescriptor(
      BluetoothCharacteristic characteristic, Guid descriptorUUID) {
    for (BluetoothDescriptor des in characteristic.descriptors) {
      if (des.uuid == descriptorUUID) {
        return des;
      }
    }
    return null;
  }

  Future<void> openStream() async {
    BluetoothService uartService =
        getService(transparentUartServiceUuid, services);

    if (uartService == null) {
      // Do something?
      return;
    }

    // Assign the class RX characteristic
    rxChar = getCharacteristic(uartService, transparentUartRxCharUuid);
    BluetoothCharacteristic txChar =
        getCharacteristic(uartService, transparentUartTxCharUuid);
    if (await isConnected()) {
      await txChar.setNotifyValue(true);
      print("Notify set!!!");
    } else {
      print("Awww disconnected???");
    }
  }

  Future<void> connect() async {
    if (!(await isConnected())) {
      await device.connect();
    }

    services = await device.discoverServices();

    if (await isConnected()) {
      print("Actually connected!!!");
    }
  }

  Future<void> disconnect() async {
    await device.disconnect();
  }

  Future<bool> isConnected() async {
    if ((await FlutterBlue.instance.connectedDevices).contains(device)) {
      return true;
    }
    return false;
  }

  List<int> encodeCommand(int command, List<int> values) {
    List<int> commandPreamble = [255, 255];
    List<int> commandHeader = [command];
    List<int> commandByteLength = [values.length];
    List<int> commandFooter = [values.length];

    if (command == PhoneBotCommand.SET_LEG_POSITIONS) {
      if (values.length != 8) {
        throw new Exception(
            "Length of values needs to be 8. Length is: ${values.length}");
      }

      for (int i = 0; i < values.length; i++) {
        int checkVal = values[i] & 0xFF;
        if ((checkVal > 180) | (checkVal < 0)) {
          throw new Exception(
              "Payload value is invalid. Value = $checkVal, Index = $i");
        }
      }
    }

    List<List<int>> resConstruct = [
      commandPreamble,
      commandHeader,
      commandByteLength,
      values,
      commandFooter
    ];

    List<int> res = resConstruct.expand((x) => x).toList();
    return res;
  }

  Future<void> setLegs(
      {int frontLeftA,
      int frontLeftB,
      int backLeftA,
      int backLeftB,
      int frontRightA,
      int frontRightB,
      int backRightA,
      int backRightB}) async {
    List<int> newLegState = [
      frontLeftA,
      frontLeftB,
      backLeftA,
      backLeftB,
      frontRightA,
      frontRightB,
      backRightA,
      backRightB
    ];

    // Assign null values to old state values
    for (int i = 0; i < newLegState.length; i++) {
      if (newLegState[i] == null) {
        newLegState[i] = legState[i];
      }
    }

    List<int> command =
        encodeCommand(PhoneBotCommand.SET_LEG_POSITIONS, newLegState);
    await rxChar.write(command, withoutResponse: true);
  }
}
