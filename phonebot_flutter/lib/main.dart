import 'dart:math';
import 'dart:async';

import 'package:flutter/services.dart' show rootBundle;

import 'package:flutter/material.dart';
import 'package:control_pad/control_pad.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';

void main() {
  runApp(PhonebotApp());
}

class PhonebotApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(primaryColor: Colors.blueGrey),
      home: HomeScreen(),
      builder: EasyLoading.init(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('PhoneBot'),
      ),
      body: Column(
        children: [
          ElevatedButton(
              onPressed: () => {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => FindDevicesScreen()))
                  },
              child: Text('Connect to PhoneBot')),
          ElevatedButton(
            onPressed: () async {
              if (await PhoneBotController().isConnected()) {
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (context) {
                  PhoneBotRemoteController().start();
                  return RemoteControlScreen();
                }));
              }
            },
            child: Text('Remote Control PhoneBot'),
          ),
          ElevatedButton(
              onPressed: () {
                PhoneBotController().disconnect();
                final snackBar = SnackBar(content: Text('Disconnected'));
                ScaffoldMessenger.of(context).showSnackBar(snackBar);
              },
              child: Text('Disconnect from PhoneBot'))
        ],
      ),
    );
  }
}

class RemoteControlScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Remote Control'),
      ),
      body: Container(
        child: JoystickView(
          onDirectionChanged: (degrees, distance) =>
              PhoneBotRemoteController().changeDirection(degrees, distance),
        ),
      ),
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
          // List of not yet connected devices. Only list devices
          // which have a non-empty name.
          child: StreamBuilder<List<ScanResult>>(
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
            EasyLoading.show(status: 'Connecting...');

            // Get an instance of the singleton
            PhoneBotController pc = PhoneBotController();

            await pc.connect(result.device);
            await pc.openStream();
            await pc.setLegs();

            EasyLoading.showSuccess('Connected!');
            EasyLoading.dismiss();

            // Go back to the home screen
            Navigator.of(context).pop();
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

class PhoneBotRemoteController {
  // Make PhoneBotController a Singleton
  static final PhoneBotRemoteController _phoneBotRemoteController =
      PhoneBotRemoteController._internal();

  factory PhoneBotRemoteController() {
    return _phoneBotRemoteController;
  }

  PhoneBotRemoteController._internal();

  Timer timer;
  double lastUpdate = (new DateTime.now()).millisecondsSinceEpoch / 1000;
  double xAmount = 0;
  double yAmount = 0;
  double yPathTime = 0;
  dynamic rotCsvRaw;
  List<String> csvLines;
  List<List<double>> turnLegData;
  List<double> legTimes;

  Future<String> loadAsset(String path) async {
    return await rootBundle.loadString(path);
  }

  void start() {
    if (timer != null) {
      timer.cancel();
    }
    loadAsset('lib/assets/rotating_trajectory.csv').then((dynamic output) {
      rotCsvRaw = output;

      csvLines = rotCsvRaw.toString().split(RegExp(r"([\r\n\$])+"));

      int numCols = csvLines[0].split(',').length;
      turnLegData =
          List.generate(csvLines.length, (_) => List.filled(numCols, 0));
      legTimes = List.filled(csvLines.length, 0);
      // turnLegData = List.filled(csvLines.length, List.filled(numCols, 0));
      for (int i = 0; i < csvLines.length; i++) {
        List<String> row = csvLines[i].split(',');
        legTimes[i] = double.parse(row[0]);
        for (int j = 0; j < numCols; j++) {
          try {
            turnLegData[i][j] = double.parse(row[j + 1]);
          } catch (e) {
            if (e == FormatException) {
              print("Poorly formated CSV row: ${row[j]}");
            }
            if (e == RangeError) {
              print("Row not long enough: ${row[j]}");
            }
          }
        }
      }
      // print(turnLegData[turnLegData.length - 1]);
    });

    timer = Timer.periodic(
        Duration(milliseconds: 50), (Timer t) async => await update(t));
  }

  void update(Timer t) async {
    try {
      List<int> newLegData = List.filled(8, 90);

      // Find the time delta since last update
      double timeSinceLastUpdate =
          (new DateTime.now()).millisecondsSinceEpoch / 1000 - lastUpdate;
      // Add the time delta times the current speed (a float between 0 and 1)
      yPathTime += timeSinceLastUpdate *
          yAmount; // Simulated seconds/second is scaled by yAmount
      // print(turnLegData[turnLegData.length - 2][0]);
      // Make sure we don't go beyond the edges of the array
      if (yPathTime > legTimes[turnLegData.length - 1]) {
        yPathTime = 0;
      }
      if (yPathTime < 0) {
        yPathTime = legTimes[turnLegData.length - 1];
      }
      lastUpdate = (new DateTime.now()).millisecondsSinceEpoch / 1000;
      int idx = 0;
      // Do this more efficiently than looping through the whole CSV every
      // update event
      for (int i = 0; i < turnLegData.length; i++) {
        if (legTimes[i] > yPathTime) {
          idx = i;
          break;
        }
      }

      for (int i = 0; i < turnLegData[0].length - 1; i++) {
        newLegData[i] = (turnLegData[idx][i + 1] * 180 / pi + 90).toInt();
      }

      await PhoneBotController().setLegsFromValues(newLegData);
    } catch (e) {
      // Do nothing?
      print("error...");
    }
  }

  void changeDirection(double degrees, double distance) {
    xAmount = distance * sin(degrees / 180 * pi);
    yAmount = distance * cos(degrees / 180 * pi);
  }
}

class PhoneBotCommand {
  static const int SET_LEG_POSITIONS = 0;
  static const int REQUEST_BATTERY_VOLTAGE = 1;
  static const int SET_DEVICE_NAME = 2;
}

class PhoneBotController {
  // Make PhoneBotController a Singleton
  static final PhoneBotController _phoneBotController =
      PhoneBotController._internal();

  factory PhoneBotController() {
    return _phoneBotController;
  }

  PhoneBotController._internal();

  // Internal variables
  BluetoothDevice device;
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

  // Methods
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
    } else {
      // Do something?
    }
  }

  Future<void> connect(BluetoothDevice bluetoothDevice) async {
    device = bluetoothDevice;
    if (!(await isConnected())) {
      await device.connect();
    }
    services = await device.discoverServices();
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

  Future<void> setLegsFromValues(List<int> legValues) async {
    await setLegs(
        frontLeftA: legValues[0],
        frontLeftB: legValues[1],
        backLeftA: legValues[2],
        backLeftB: legValues[3],
        frontRightA: legValues[4],
        frontRightB: legValues[5],
        backRightA: legValues[6],
        backRightB: legValues[7]);
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

      if (i % 2 == 1) {
        newLegState[i] = 180 - newLegState[i];
      }
    }

    List<int> command =
        encodeCommand(PhoneBotCommand.SET_LEG_POSITIONS, newLegState);
    await rxChar.write(command, withoutResponse: true);
  }
}
